-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels App Registry                          ║
-- ║                                                            ║
-- ║  Tabs used to be a hardcoded `type` chain duplicated in    ║
-- ║  draw.lua (render) and events.lua (input). Adding an       ║
-- ║  interactive tab meant editing both. This registry lets an ║
-- ║  app register under a tab `type` and implement a small     ║
-- ║  lifecycle contract; the shell dispatches render + input   ║
-- ║  to the active tab's app.                                  ║
-- ║                                                            ║
-- ║  HYBRID app model (operator's call): an app is either      ║
-- ║  in-shell (a module the shell draws inside its own loop —  ║
-- ║  cheap, for glanceable/utility tabs like Desktop/Settings/ ║
-- ║  Monitor) or process-backed (a real scheduled process that ║
-- ║  keeps running when you switch away — for Chat and other   ║
-- ║  live things). `model` names which; Stage 1 wires in-shell ║
-- ║  render, later stages add process binding + input.         ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- App spec (all fields optional except `type`):
--   type    string    the tab.type this app owns
--   title   string|fn(tab)->string   tab label (defaults to type)
--   model   "inshell"|"process"      how it runs (default "inshell")
--   draw    fn(S, tab)               render the content area (below top bar)
--   onKey   fn(S, tab, ev)->redraw   ev = { ch=, co= }; return a redraw hint
--                                     (1/2/3) or true if handled, false/nil if not
--   onMouse fn(S, tab, ev)->redraw   ev = { kind=, x=, y=, button= }
--   onClose fn(S, tab)               cleanup when the tab closes
--   tick    fn(S, tab)               optional periodic (live/refreshing apps)

local M = {}

local registry = {}

--- Register (or replace) an app spec. `spec.type` is required.
function M.register(spec)
  assert(type(spec) == "table" and type(spec.type) == "string",
    "app spec needs a string `type`")
  registry[spec.type] = spec
  return spec
end

function M.get(t) return registry[t] end
function M.has(t) return registry[t] ~= nil end

--- All registered types (for tests / introspection).
function M.types()
  local out = {}
  for t in pairs(registry) do out[#out + 1] = t end
  table.sort(out)
  return out
end

-- Built-in apps that already exist as their own modules. Registered lazily
-- (and pcall-guarded) so off-box unit tests that load draw.lua without every
-- app module still work — exactly the posture draw.lua used before.
-- `mail` resolves to /usr/lib/mailapp.lua, shipped by the mail ADD-ON
-- (stage 5) rather than the base image; the pcall below simply skips it
-- when the package isn't installed, so an add-on can register a tab app
-- exactly like a built-in one.
local BUILTINS = {
  desktop  = "shell.panels.desktop",
  settings = "shell.panels.settingsapp",
  monitor  = "shell.panels.monitorapp",
  chat     = "shell.panels.chatapp",
  mail     = "mailapp",
  intercom = "intercomapp",
}

-- Forward declaration: the process-backed program app is defined near
-- the bottom of this file, but ensureBuiltins (above it) has to be able
-- to re-register it after M._reset(). Without this it would resolve as
-- a nil GLOBAL there and the re-registration would silently no-op.
local PROGRAM_APP

local ensured = false
function M.ensureBuiltins()
  if ensured then return end
  ensured = true
  -- The process-backed program app is defined in this file rather than
  -- loaded from a module, but it still has to survive M._reset().
  if PROGRAM_APP and not registry[PROGRAM_APP.type] then M.register(PROGRAM_APP) end
  for typ, modname in pairs(BUILTINS) do
    if not registry[typ] then
      local ok, mod = pcall(require, modname)
      if ok and mod and mod.draw then
        -- Adapt the existing module interface (draw/handleKey/handleClick/
        -- handleScroll → (draw, result)) to the app contract, so events.lua
        -- and mouse.lua dispatch input through the registry instead of a
        -- hardcoded per-type chain.
        M.register({
          type = typ, model = "inshell", draw = mod.draw,
          onKey = mod.handleKey and function(S, tab, ev)
            return mod.handleKey(S, tab, ev.ch, ev.co, { exec = ev.exec })
          end or nil,
          onMouse = mod.handleClick and function(S, tab, ev, deps)
            return mod.handleClick(S, tab, ev, deps)
          end or nil,
          onScroll = mod.handleScroll and function(S, tab, ev)
            return mod.handleScroll(S, tab, ev)
          end or nil,
          -- Periodic callback (live apps like the Monitor); the event
          -- loop drives it only while the tab is front and the shell
          -- owns the screen.
          tick = mod.tick,
          -- Lifecycle: tabs.close fires this so an app can release
          -- listeners/processes (Chat's NM.on registration).
          onClose = mod.onClose,
          _module = mod,
        })
      end
    end
  end
end

-- ============================================================
-- The PROCESS-backed app: a running full-screen program
-- ============================================================
-- `model = "process"` has been in the spec since stage 1 and only
-- "inshell" was ever built. This is that missing half, and it is the
-- one app whose "draw" is not a draw at all: a program owns the real
-- screen, so making its tab active means HANDING THE SEAT OVER —
-- foreground its process, tell it to repaint, and stop drawing.
--
-- Lifecycle:
--   executor.handOff  creates the tab when a program is launched
--   activate (draw)   gives it the seat (F2 / clicking the chip)
--   Ctrl+B            kernel hands the seat back; events.lua moves the
--                     active tab off this one so we don't immediately
--                     hand it straight back again
--   refresh           keeps the chip honest: bracketed while the
--                     program is still running in the background,
--                     plain once the scheduler has frozen it
--   onClose           ^W / F4 kills the process
--
-- The tab carries { pid, seat, prog }. A tab whose process is gone is
-- closed on sight rather than left as a chip that does nothing.
local function procOf(tab)
  if not tab or not tab.pid then return nil, nil end
  local ok, proc = pcall(require, "kernel.process")
  if not ok or type(proc) ~= "table" or not proc.get then return nil, nil end
  local p = proc.get(tab.pid)
  if not p or (proc.STATE and p.state == proc.STATE.DEAD) then return proc, nil end
  return proc, p
end

--- Is this program still alive? Closes its tab if not.
local function alive(S, tab)
  local proc, p = procOf(tab)
  if p then return proc, p end
  -- Gone: drop the chip. Guarded require so a headless test that never
  -- loaded tabs.lua doesn't explode here.
  local okT, tabsMod = pcall(require, "shell.panels.tabs")
  if okT and tabsMod and S and S.tabs then
    for i, t in ipairs(S.tabs) do
      if t == tab then tabsMod.close(S, i); break end
    end
  end
  return nil, nil
end

PROGRAM_APP = {
  type  = "program",
  model = "process",
  title = function(tab) return tab.prog or tab.label or "program" end,

  -- Activating the tab hands the program the seat.
  draw = function(S, tab)
    local proc, p = alive(S, tab)
    if not p then return end
    local seat = tab.seat or S.displayIdx
    if not seat then return end
    -- Stop painting BEFORE handing over, or this shell's own tick could
    -- land a status bar on top of the program's first frame.
    S.suspendIdleDraw = true
    if S.D and S.D.invalidate then pcall(S.D.invalidate) end
    proc.setForeground(tab.pid, seat, { kernel = true })
    ;(proc.signalKernel or proc.signal)(tab.pid, "tos_focus")
  end,

  -- Chip state (visual grammar rule 5): a backgrounded program that is
  -- still being scheduled is BUSY; once frozen it is idle. Nothing here
  -- draws — refreshTabs calls it just before the top bar is built.
  refresh = function(S, tab)
    local proc, p = alive(S, tab)
    if not p then return end
    if proc.bgState then
      local ok, state = pcall(proc.bgState, tab.pid)
      tab.live = ok and state == "drowsy" or false
    end
  end,

  onClose = function(S, tab)
    local proc, p = procOf(tab)
    if proc and p then pcall(proc.kill, tab.pid, { kernel = true }) end
  end,
}
M.register(PROGRAM_APP)

--- Give every tab whose app wants it a chance to update its chip state
--- before the top bar is drawn. Cheap: only apps that define `refresh`
--- do anything, and today that is only the program app.
function M.refreshTabs(S)
  if not S or type(S.tabs) ~= "table" then return end
  -- Iterate a snapshot: refresh may CLOSE a tab (dead process), and
  -- mutating S.tabs under ipairs would skip the next one.
  local snapshot = {}
  for i, t in ipairs(S.tabs) do snapshot[i] = t end
  for _, tab in ipairs(snapshot) do
    local app = registry[tab.type]
    if app and app.refresh then pcall(app.refresh, S, tab) end
  end
end

--- Test hook: forget all registrations (so a test starts clean).
function M._reset() registry = {}; ensured = false end

return M
