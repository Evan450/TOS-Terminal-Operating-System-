local M = {}

local registry = {}

function M.register(spec)
  assert(type(spec) == "table" and type(spec.type) == "string",
    "app spec needs a string `type`")
  registry[spec.type] = spec
  return spec
end

function M.get(t) return registry[t] end
function M.has(t) return registry[t] ~= nil end

function M.types()
  local out = {}
  for t in pairs(registry) do out[#out + 1] = t end
  table.sort(out)
  return out
end

local BUILTINS = {
  desktop  = "shell.panels.desktop",
  settings = "shell.panels.settingsapp",
  monitor  = "shell.panels.monitorapp",
  chat     = "shell.panels.chatapp",
  mail     = "mailapp",
  intercom = "intercomapp",
}

local PROGRAM_APP

local ensured = false
function M.ensureBuiltins()
  if ensured then return end
  ensured = true

  if PROGRAM_APP and not registry[PROGRAM_APP.type] then M.register(PROGRAM_APP) end
  for typ, modname in pairs(BUILTINS) do
    if not registry[typ] then
      local ok, mod = pcall(require, modname)
      if ok and mod and mod.draw then

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

          tick = mod.tick,

          onClose = mod.onClose,
          _module = mod,
        })
      end
    end
  end
end

local function procOf(tab)
  if not tab or not tab.pid then return nil, nil end
  local ok, proc = pcall(require, "kernel.process")
  if not ok or type(proc) ~= "table" or not proc.get then return nil, nil end
  local p = proc.get(tab.pid)
  if not p or (proc.STATE and p.state == proc.STATE.DEAD) then return proc, nil end
  return proc, p
end

local function alive(S, tab)
  local proc, p = procOf(tab)
  if p then return proc, p end

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

  draw = function(S, tab)
    local proc, p = alive(S, tab)
    if not p then return end
    local seat = tab.seat or S.displayIdx
    if not seat then return end

    S.suspendIdleDraw = true
    if S.D and S.D.invalidate then pcall(S.D.invalidate) end
    proc.setForeground(tab.pid, seat, { kernel = true })
    ;(proc.signalKernel or proc.signal)(tab.pid, "tos_focus")
  end,

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

function M.refreshTabs(S)
  if not S or type(S.tabs) ~= "table" then return end

  local snapshot = {}
  for i, t in ipairs(S.tabs) do snapshot[i] = t end
  for _, tab in ipairs(snapshot) do
    local app = registry[tab.type]
    if app and app.refresh then pcall(app.refresh, S, tab) end
  end
end

function M._reset() registry = {}; ensured = false end

return M
