-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Shared State                    ║
-- ║  Central state table passed to all panel submodules ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local KEYS = require("shell.panels.keymap")

local M = {}

function M.new(ctx)
  local S = {}

  -- Module references from ctx
  S.K  = ctx.K
  S.E  = ctx.E
  S.P  = ctx.P
  S.F  = ctx.F
  S.D  = ctx.D
  S.U  = ctx.U
  S.SC = ctx.SC
  S.NM = ctx.NM
  S.st = ctx.st
  S.displayIdx = ctx.displayIdx
  S.W  = ctx.W
  S.H  = ctx.H
  S.T  = S.D.getTheme()
  S.tier = S.D.getGpuTier()

  -- Layout constants
  S.MENU_ROW = 2
  S.PATH_ROW = 3
  S.HDR_ROW  = S.tier >= 2 and 4 or nil
  S.LIST_TOP = S.HDR_ROW and 5 or 4
  S.OUT_ROW  = S.H - 2
  S.CMD_ROW  = S.H - 1
  S.STAT_ROW = S.H
  S.LIST_H   = S.OUT_ROW - S.LIST_TOP

  -- User state
  S.cwd      = ctx.cwd or "/"
  S.who      = ctx.who or "root"
  S.userTier = 3  -- default ROOT; updated from session
  if S.U and S.st then
    local sess = S.U.getSession(S.st)
    if sess then S.userTier = sess.tier or 3 end
  end

  -- Command line
  S.cmdline    = ""
  S.cmdHistory = {}
  S.cmdHistIdx = 0
  S.lastOut    = nil

  -- Clipboards
  S.clipboard     = nil
  S.editClipboard = nil  -- Cross-tab editor clipboard (array of lines)

  -- File browser
  S.browser = { path = S.cwd, sel = 1, scroll = 0, files = {} }

  -- Tab state
  S.tabs = { { type = "shell", label = "Shell" } }
  S.activeTab = 1

  -- Menu state
  S.menuFocused = false
  S.menuIdx     = 1
  S.menuOpen    = nil
  S.menuSel     = 1

  -- Context menu state
  S.ctxOpen  = false
  S.ctxItems = {}
  S.ctxSel   = 1
  S.ctxPath  = nil
  S.ctxFile  = nil
  S.ctxX     = 1
  S.ctxY     = 1

  -- Scancodes
  S.KEYS = KEYS

  -- Sandbox module (lazy-loaded)
  S.sandboxMod = nil

  return S
end

return M
