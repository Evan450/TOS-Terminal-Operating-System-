-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Menu + Browser TUI                      ║
-- ║  Single-panel file browser, menu bar, context menus  ║
-- ║  Tab-based multitasking with enhanced editor/viewer  ║
-- ╚══════════════════════════════════════════════════════╝
-- Layout:
--   Row 1:      Tab bar (with memory info)
--   Row 2:      Menu bar (File | Tools | System | Settings)
--   Row 3:      Path breadcrumb
--   Row 4:      Column header (T2/T3 only)
--   Rows 5-H-3: Full-width file list
--   Row H-2:    Output message
--   Row H-1:    Command prompt
--   Row H:      Customizable status bar
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
  local sandboxMod = nil
  local function getSandbox()
    if sandboxMod == nil then
      local ok, mod = pcall(require, "kernel.sandbox")
      sandboxMod = ok and mod or false
    end
    return sandboxMod or nil
  end

  local function makeProgramEnv(opts)
    opts = opts or {}
    local sb = getSandbox()
    if not sb then
      local env = {
        assert = assert, error = error, pcall = pcall, xpcall = xpcall,
        type = type, tostring = tostring, tonumber = tonumber,
        pairs = pairs, ipairs = ipairs, next = next, select = select,
        setmetatable = setmetatable, getmetatable = getmetatable,
        math = math, string = string, table = table,
        print = opts.stdout or print,
      }
      env._G = env
      return env
    end
    local caps = {
      ["fs.read"]   = true,
      ["fs.write"]  = true,
      ["compat.io"] = true,
    }
    if opts.caps then
      for k, v in pairs(opts.caps) do caps[k] = v end
    end
    return sb.build{
      name    = opts.name or "panels:program",
      cwd     = S.cwd,
      session = (S.U and S.U.currentSession and S.U.currentSession()) or nil,
      caps    = caps,
      stdout  = opts.stdout,
    }
  end

  -- ── Status bar widgets ──
  local widgetDefs = widgetsMod.makeWidgetDefs(S)
  pcall(widgetsMod.loadCustomWidgets, S, widgetDefs)

  -- ── Auto-mount helper ──
  local function autoMount(addr)
    local ok, px = pcall(component.proxy, addr)
    if not ok or not px then return nil, nil end
    local lbl     = (px.getLabel and px.getLabel()) or nil
    local mntName = lbl and lbl:gsub("[^%w_%-]", "_"):sub(1, 12) or addr:sub(1, 6)
    local mntPath = "/mnt/" .. mntName
    if not S.F.exists("/mnt") then pcall(S.F.makeDirectory, "/mnt") end
    if not S.F.exists(mntPath) then pcall(S.F.makeDirectory, mntPath) end
    S.F.mount(mntPath, px)
    return mntPath, lbl or mntName
  end

  -- ── Build command table ──
  local C = commandsMod.build(S, {
    rp             = function(p) return helpers.resolvePath(S, p) end,
    openViewTab    = function(buf, label) return editorMod.openViewTab(S, buf, label) end,
    openEditTab    = function(path) return editorMod.openEditTab(S, path) end,
    refreshBrowser = function() return helpers.refreshBrowser(S) end,
    canRead        = function(path, o) return helpers.canRead(S, path, o) end,
    canWrite       = function(path, o) return helpers.canWrite(S, path, o) end,
    canAccess      = function(path, mode, o) return helpers.canAccess(S, path, mode, o) end,
    rootOnly       = function(o) return helpers.rootOnly(S, o) end,
    adminOnly      = function(o) return helpers.adminOnly(S, o) end,
    makeProgramEnv = makeProgramEnv,
    promptInput    = function(msg, maxLen, isPw) return dialogsMod.promptInput(S, msg, maxLen, isPw) end,
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

  -- ── Run event loop ──
  return eventsMod.run(S, {
    C              = C,
    exec           = exec,
    autoMount      = autoMount,
    makeProgramEnv = makeProgramEnv,
    widgetDefs     = widgetDefs,
  })
end

return M
