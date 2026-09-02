local computer  = require("computer")
local component = require("component")

local M = {}

function M.run(ctx)

  local stateMod  = require("shell.panels.state")
  local S = stateMod.new(ctx)

  local helpers    = require("shell.panels.helpers")
  local widgetsMod = require("shell.panels.widgets")
  local dialogsMod = require("shell.panels.dialogs")
  local drawMod    = require("shell.panels.draw")
  local editorMod  = require("shell.panels.editor")
  local executorMod= require("shell.panels.executor")
  local commandsMod= require("shell.panels.commands")
  local eventsMod  = require("shell.panels.events")

  local makeProgramEnv = require("shell.progenv").builder(S)

  S.menuDefs = drawMod.buildMenuDefs(S)

  pcall(function()
    local landing = nil
    local okP, profileMod = pcall(require, "kernel.profile")
    if okP and profileMod and profileMod.load then
      local sess = (S.U and S.st and S.U.getSession and S.U.getSession(S.st)) or nil
      local okL, p = pcall(profileMod.load, sess)
      if okL and type(p) == "table" then landing = p.landing end
    end

    if not landing then
      landing = (S.who == "root") and "shell" or "desktop"
    end
    local wantsTiles = (landing == "desktop" or landing == "tiles")

    if not S.uiSplit then

      if wantsTiles and computer.freeMemory() >= 300 * 1024 then
        local homeMod = require("shell.panels.home")
        homeMod.setView(S, "tiles")
      end
      return
    end

    if not wantsTiles and computer.freeMemory() < 300 * 1024 then
      return
    end
    local desktopMod = require("shell.panels.desktop")
    desktopMod.open(S, { background = not wantsTiles })
  end)

  local widgetDefs = widgetsMod.makeWidgetDefs(S)
  pcall(widgetsMod.loadCustomWidgets, S, widgetDefs)

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

    local bootAddr = _G._TOS and _G._TOS.bootAddr
    if not bootAddr then

      return nil, nil
    end
    if addr == bootAddr then
      return nil, nil
    end
    local lbl     = (px.getLabel and px.getLabel()) or nil
    local mntName = sanitizeMountLabel(lbl, addr)
    local mntPath = "/mnt/" .. mntName
    if S.F.exists(mntPath) then
      mntPath = mntPath .. "_" .. addr:sub(1, 4)

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

    dialog         = function(opts)
      opts = opts or {}; opts.redraw = opts.redraw or function() drawMod.all(S, widgetDefs) end
      return dialogsMod.dialog(S, opts)
    end,
    alert          = function(msg, opts)
      opts = opts or {}; opts.redraw = opts.redraw or function() drawMod.all(S, widgetDefs) end
      return dialogsMod.alert(S, msg, opts)
    end,
    confirm        = function(msg, opts)
      opts = opts or {}; opts.redraw = opts.redraw or function() drawMod.all(S, widgetDefs) end
      return dialogsMod.confirm(S, msg, opts)
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

  local exec = executorMod.build(S, {
    rp             = function(p) return helpers.resolvePath(S, p) end,
    makeProgramEnv = makeProgramEnv,
    C              = C,
  })

  local TOSk = _G._TOS and _G._TOS.kernel
  if TOSk and TOSk.setMonitorHost then pcall(TOSk.setMonitorHost, true) end

  local result = eventsMod.run(S, {
    C              = C,
    exec           = exec,
    autoMount      = autoMount,
    makeProgramEnv = makeProgramEnv,
    widgetDefs     = widgetDefs,
  })

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
