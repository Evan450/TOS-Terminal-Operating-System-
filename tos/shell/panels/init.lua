-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Menu + Browser TUI                      ║
-- ║  Single-panel file browser, menu bar, context menus  ║
-- ║  Tab-based multitasking with enhanced editor/viewer  ║
-- ╚══════════════════════════════════════════════════════╝
-- Layout — ONE surface, two views. Home is a single tab; F2 (the `view`
-- action in shell/keys.lua) flips which middle it draws. The bottom four
-- rows are identical either way, which is the point: the prompt is never
-- somewhere else, and a command's output lands where the last one did.
--
--   Row 1:      Menus + tab chips + free memory
--   Row 2:      files: ─┤ path ├ Name ─┤ F2 ▸ tiles ├─ Size  Type ─
--               tiles: ─┤ ⌂ user@host ├ cwd ─────────────── clock ─
--   Row 3:      files: first file row
--               tiles: ─┤ ‹ page 1/2 › ├ N tiles · N shown ────────
--   Rows 4..H-4: the file list, or the tile grid
--   Row H-3:    Summary rail  (N items / N tiles, free space)
--   Row H-2:    Output message, or the F-key / tile legend
--   Row H-1:    Command prompt          ← resident in BOTH views
--   Row H:      Customizable status bar (carries the View: widget)
--
-- Boot Settings → Interface = "split" restores the pre-merge shape: a
-- Shell tab and a separate Desktop tab, with F2 cycling between them.
--
-- Submodules (extracted from this file):
--   state.lua      - shared state table
--   helpers.lua    - path, file, text, permission helpers
--   tabs.lua       - tab create/close/cycle/find
--   widgets.lua    - syntax highlighting, status bar widgets
--   dialogs.lua    - inline input prompts
--   draw.lua       - all TUI rendering
--   filebrowser.lua - file browser operations
--   editor.lua     - view/edit tab opening
--   context.lua    - context menu
--   commands.lua   - command table (~50 commands)
--   executor.lua   - command executor + pipe handler
--   menus.lua      - menu bar action handler
--   events.lua     - main event loop
--   keymap.lua     - OC scancode table
--   home.lua       - the merged surface: view state + the tiles view

local computer  = require("computer")
local component = require("component")

local M = {}

function M.run(ctx)
  -- ── Build shared state ──
  local stateMod  = require("shell.panels.state")
  local S = stateMod.new(ctx)

  -- ── Load submodules ──
  local helpers    = require("shell.panels.helpers")
  local widgetsMod = require("shell.panels.widgets")
  local dialogsMod = require("shell.panels.dialogs")
  local drawMod    = require("shell.panels.draw")
  local editorMod  = require("shell.panels.editor")
  local executorMod= require("shell.panels.executor")
  local commandsMod= require("shell.panels.commands")
  local eventsMod  = require("shell.panels.events")

  -- ── Sandbox / program environment ──
  -- kernel.sandbox builds capability-checked environments for user
  -- programs. No ambient _G access, no raw kernel require.
  -- Lives in shell/progenv.lua since the CLI needs the identical builder
  -- and a second sandbox-env builder is the last thing this codebase
  -- should have — see that file's header.
  local makeProgramEnv = require("shell.progenv").builder(S)

  -- ── Menu definitions (per-session: built-ins + ~/.menu.cfg) ──
  S.menuDefs = drawMod.buildMenuDefs(S)

  -- ── Landing view ──
  -- The per-user profile's `landing` field used to pick a SURFACE — the
  -- Desktop tab or the Shell tab. There is one surface now, so it picks
  -- a VIEW of it instead: tiles or files. The stored values are
  -- unchanged (desktop == tiles, shell == files), so nobody's saved
  -- profile needs migrating and the split-mode meaning still reads
  -- correctly. No preference saved: root keeps the files-first muscle
  -- memory, everyone else lands on tiles.
  --
  -- Failure-tolerant throughout: anything wrong here leaves the session
  -- on the file list, which is a working shell.
  pcall(function()
    local landing = nil
    local okP, profileMod = pcall(require, "kernel.profile")
    if okP and profileMod and profileMod.load then
      local sess = (S.U and S.st and S.U.getSession and S.U.getSession(S.st)) or nil
      local okL, p = pcall(profileMod.load, sess)
      if okL and type(p) == "table" then landing = p.landing end
    end
    -- (Keep in sync with settingsapp.defaultLanding — duplicated here so
    -- the settings app stays lazy-loaded at shell start.)
    if not landing then
      landing = (S.who == "root") and "shell" or "desktop"
    end
    local wantsTiles = (landing == "desktop" or landing == "tiles")

    if not S.uiSplit then
      -- Merged: the tile grid is a view of the tab we already have. The
      -- RAM gate still applies to PARSING desktop.lua+ui.lua at shell
      -- start (the v1.4.0 emulator round OOM'd a ~230KB-free box doing
      -- exactly that), so on a tight box we simply land on files — F2
      -- loads the tiles on demand, which is the whole reason home.lua
      -- requires desktop.lua lazily.
      if wantsTiles and computer.freeMemory() >= 300 * 1024 then
        local homeMod = require("shell.panels.home")
        homeMod.setView(S, "tiles")
      end
      return
    end

    -- Split (the escape hatch): two tabs, exactly as before the merge.
    if not wantsTiles and computer.freeMemory() < 300 * 1024 then
      return
    end
    local desktopMod = require("shell.panels.desktop")
    desktopMod.open(S, { background = not wantsTiles })
  end)

  -- ── Status bar widgets ──
  local widgetDefs = widgetsMod.makeWidgetDefs(S)
  pcall(widgetsMod.loadCustomWidgets, S, widgetDefs)

  -- ── Auto-mount helper ──
  -- Labels are attacker-controllable (any player with a filesystem can
  -- set one to "../etc") so strip traversal bytes before the /mnt/ join.
  -- On collision, suffix with an address stub so two disks can't silently
  -- overwrite the same mount point.
  local function sanitizeMountLabel(raw, addr)
    local fallback = "disk_" .. addr:sub(1, 4)
    if type(raw) ~= "string" then return fallback end
    local cleaned = raw:gsub("[^%w_%- ]", "_")
    cleaned = cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" or cleaned == "." or cleaned == ".." then return fallback end
    if #cleaned > 32 then cleaned = cleaned:sub(1, 32) end
    return cleaned
  end
  local function autoMount(addr)
    local ok, px = pcall(component.proxy, addr)
    if not ok or not px then return nil, nil end
    -- #SEC H26 — refuse to auto-mount the BOOT filesystem under /mnt.
    -- Without this gate, a freshly-attached disk OR an undefined bootAddr
    -- (early hot-plug, or shell loading before the kernel finished
    -- setting _TOS.bootAddr) could shadow the boot FS at /mnt/<label>
    -- and bypass securefs's protected paths. Fail closed when the boot
    -- address is unknown.
    local bootAddr = _G._TOS and _G._TOS.bootAddr
    if not bootAddr then
      -- We can't tell which disk is the boot disk — refuse to mount
      -- anything from auto-mount until init has set bootAddr. The
      -- operator can still mount explicitly via `mount` command which
      -- is admin-gated.
      return nil, nil
    end
    if addr == bootAddr then
      return nil, nil  -- never mount the boot drive under /mnt
    end
    local lbl     = (px.getLabel and px.getLabel()) or nil
    local mntName = sanitizeMountLabel(lbl, addr)
    local mntPath = "/mnt/" .. mntName
    if S.F.exists(mntPath) then
      mntPath = mntPath .. "_" .. addr:sub(1, 4)
      -- If even the address-stubbed path collides (rare: same label AND
      -- same 4-char prefix), walk an integer suffix until we land on a
      -- free slot instead of mounting atop an existing entry.
      local n = 2
      local candidate = mntPath
      while S.F.exists(candidate) and n < 100 do
        candidate = mntPath .. "_" .. n
        n = n + 1
      end
      mntPath = candidate
    end
    if not S.F.exists("/mnt") then pcall(S.F.makeDirectory, "/mnt") end
    if not S.F.exists(mntPath) then pcall(S.F.makeDirectory, mntPath) end
    S.F.mount(mntPath, px)
    return mntPath, lbl or mntName
  end

  -- ── Build command table ──
  local C = commandsMod.build(S, {
    rp             = function(p) return helpers.resolvePath(S, p) end,
    openViewTab    = function(buf, label) return editorMod.openViewTab(S, buf, label) end,
    openLiveTab    = function(label, fn, interval) return editorMod.openLiveTab(S, label, fn, interval) end,
    openEditTab    = function(path) return editorMod.openEditTab(S, path) end,
    refreshBrowser = function() return helpers.refreshBrowser(S) end,
    canRead        = function(path, o) return helpers.canRead(S, path, o) end,
    canWrite       = function(path, o) return helpers.canWrite(S, path, o) end,
    canAccess      = function(path, mode, o) return helpers.canAccess(S, path, mode, o) end,
    rootOnly       = function(o) return helpers.rootOnly(S, o) end,
    adminOnly      = function(o) return helpers.adminOnly(S, o) end,
    makeProgramEnv = makeProgramEnv,
    promptInput    = function(msg, maxLen, isPw) return dialogsMod.promptInput(S, msg, maxLen, isPw) end,
    -- Dialog boxes (the titled, framed, blocking kind). They auto-repaint
    -- the screen under the box via drawAll once dismissed, so a command can
    -- raise one mid-output without leaving a hole behind. `dialog` is the
    -- general primitive (any title/buttons/style); alert/confirm are the
    -- common one-button / yes-no shortcuts.
    dialog         = function(opts)
      opts = opts or {}; opts.redraw = opts.redraw or function() drawMod.all(S, widgetDefs) end
      return dialogsMod.dialog(S, opts)
    end,
    alert          = function(msg, opts)
      opts = opts or {}; opts.redraw = opts.redraw or function() drawMod.all(S, widgetDefs) end
      return dialogsMod.alert(S, msg, opts)
    end,
    confirm        = function(msg, opts)
      opts = opts or {}
      --! `redraw = false` means "another box follows" -- do NOT replace
      --! it with the default repaint, or a run of questions flickers the
      --! whole shell between every one. `or` would have done exactly
      --! that, since false is falsey.
      if opts.redraw == nil then
        opts.redraw = function() drawMod.all(S, widgetDefs) end
      end
      return dialogsMod.confirm(S, msg, opts)
    end,
    -- Same box, but yes requires typing `word`. For operations whose
    -- failure mode is a machine that no longer boots.
    confirmTyped   = function(msg, word, opts)
      opts = opts or {}; opts.redraw = opts.redraw or function() drawMod.all(S, widgetDefs) end
      return dialogsMod.confirmTyped(S, msg, word, opts)
    end,
    drawAll        = function() return drawMod.all(S, widgetDefs) end,
    drawOutRow     = function(text, color) return drawMod.outRow(S, text, color) end,
    loadFiles      = function(b) return helpers.loadFiles(S, b) end,
    createTab      = function(tt, label, data) return require("shell.panels.tabs").create(S, tt, label, data) end,
    tabs           = S.tabs,
    pullSignal     = function()
      if coroutine.isyieldable and coroutine.isyieldable() then return coroutine.yield() end
      return computer.pullSignal(0.05)
    end,
  })

  -- ── Build command executor ──
  local exec = executorMod.build(S, {
    rp             = function(p) return helpers.resolvePath(S, p) end,
    makeProgramEnv = makeProgramEnv,
    C              = C,
  })

  -- ── Register as the seat's Monitor host ──
  -- Ctrl+T then focuses this shell and opens the Monitor as a full-screen
  -- TAB instead of spawning the cramped modal switcher. Kernel-verified
  -- (only the seat's own shell process may register), and unregistered on
  -- the way out so a panels→CLI handoff gets the modal fallback back.
  local TOSk = _G._TOS and _G._TOS.kernel
  if TOSk and TOSk.setMonitorHost then pcall(TOSk.setMonitorHost, true) end

  -- ── Run event loop ──
  local result = eventsMod.run(S, {
    C              = C,
    exec           = exec,
    autoMount      = autoMount,
    makeProgramEnv = makeProgramEnv,
    widgetDefs     = widgetDefs,
  })
  -- #SEC (round 4) — drop any active `sudo -s` elevation on EVERY exit
  -- from the panels loop. The "cli" handoff runs the CLI shell in this
  -- same process: without this, the swapped process principal (which
  -- securefs + users.currentSession read) stayed ELEVATED in the CLI.
  -- Also cleans the registered elevated session on menu/tile logouts,
  -- which push tos_logout without going through C.logout's own drop.
  if S.sudoDrop then pcall(S.sudoDrop) end
  --! #SEC — wipe the seat's TEXT clipboard on the way out. A seat is a
  --! physical screen the next person walks up to, and "whatever the last
  --! operator copied" is sometimes a password on its way to a prompt. The
  --! panels->CLI handoff is NOT an exit (it sets S._exitTo and returns
  --! "cli"), so this does not fire between the two shells of one session,
  --! which is the case where keeping the clipboard is the correct answer.
  if result ~= "cli" then
    local okCB, clip = pcall(require, "kernel.clipboard")
    if okCB and clip and clip.clear then pcall(clip.clear, S.displayIdx) end
  end
  if TOSk and TOSk.setMonitorHost then pcall(TOSk.setMonitorHost, false) end
  return result
end

return M
