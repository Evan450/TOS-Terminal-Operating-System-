local computer = require("computer")
local KEYS = require("shell.panels.keymap")

local M = {}

function M.recomputeLayout(S)

  local dw, dh
  local gpu = S.D.getGpu and S.D.getGpu()
  if gpu then
    local ok, w, h = pcall(gpu.getResolution)
    if ok and w and h then dw, dh = w, h end
  end
  if not dw then dw, dh = S.D.getSize() end
  if dw and dh and dw > 0 and dh > 0 then S.W, S.H = dw, dh end
  S.padW = string.rep(" ", S.W)

  S.MENU_ROW = 1
  S.RAIL_ROW = 2
  S.LIST_TOP = 3
  S.SUM_ROW  = S.H - 3
  S.OUT_ROW  = S.H - 2
  S.CMD_ROW  = S.H - 1
  S.STAT_ROW = S.H
  S.LIST_H   = S.SUM_ROW - S.LIST_TOP

  S.BAND_ROW = S.RAIL_ROW + 1
  S.TILE_TOP = S.BAND_ROW + 1
  S.TILE_H   = S.SUM_ROW - S.TILE_TOP
end

function M.new(ctx)
  local S = {}

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
    or (ctx.K and ctx.K.getDisplayIdx and ctx.K.getDisplayIdx())
    or nil
  S.W  = ctx.W
  S.H  = ctx.H
  S.T  = S.D.getTheme()
  S.tier = S.D.getGpuTier()

  M.recomputeLayout(S)

  S.cwd      = ctx.cwd or "/"
  S.who      = ctx.who or "root"
  S.userTier = 3
  if S.U and S.st then
    local sess = S.U.getSession(S.st)
    if sess then S.userTier = sess.tier or 3 end
  end

  S.cmdline    = ""
  S.cmdCursor  = 1
  S.cmdSel     = nil
  S.cmdHistory = {}
  S.cmdHistIdx = 0
  S.lastOut    = nil

  local okK, keysMod = pcall(require, "shell.keys")
  S.mods = (okK and keysMod and keysMod.newMods) and keysMod.newMods()
    or { shift = false, ctrl = false, alt = false, at = 0 }

  S.clipboard     = nil

  S.browser = { path = S.cwd, sel = 1, scroll = 0, files = {} }

  S.uiSplit = ctx.uiSplit or false

  S.tabs = { { type = "shell",
               label = S.uiSplit and "Shell" or "Home",
               view  = S.uiSplit and "files" or (ctx.homeView or "files") } }
  S.activeTab = 1

  S.menuFocused = false
  S.menuIdx     = 1
  S.menuOpen    = nil
  S.menuSel     = 1

  S.ctxOpen  = false
  S.ctxItems = {}
  S.ctxSel   = 1
  S.ctxPath  = nil
  S.ctxFile  = nil
  S.ctxX     = 1
  S.ctxY     = 1

  S.KEYS = KEYS

  S.sandboxMod = nil

  return S
end

return M
