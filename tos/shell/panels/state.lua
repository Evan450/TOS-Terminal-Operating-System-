-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Shared State                     ║
-- ║  Central state table passed to all panel submodules  ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local KEYS = require("shell.panels.keymap")

local M = {}

--- (Re)compute the screen size and all layout constants from the current
--- display size. Called at startup and again after a live screen resize
--- (the `screen res` command) so the panels re-fit the new resolution.
function M.recomputeLayout(S)
  -- Prefer the live GPU resolution so a resize is picked up even if a display
  -- cache lagged; fall back to the display's reported size.
  local dw, dh
  local gpu = S.D.getGpu and S.D.getGpu()
  if gpu then
    local ok, w, h = pcall(gpu.getResolution)
    if ok and w and h then dw, dh = w, h end
  end
  if not dw then dw, dh = S.D.getSize() end
  if dw and dh and dw > 0 and dh > 0 then S.W, S.H = dw, dh end
  S.padW = string.rep(" ", S.W)
  -- Visual-grammar layout (v1.4.0): the old 4 chrome rows (tab bar,
  -- menu bar, path bar, column header) merge into 2 — row 1 carries
  -- menus + tab chips, row 2 is the path/columns RAIL — and a summary
  -- rail sits above the output row. Net: one more file row than the
  -- old layout, and the stacked-bars busyness gone.
  S.MENU_ROW = 1              -- merged menus+tabs bar (dropdowns open at 2)
  S.RAIL_ROW = 2              -- ─┤ path ├─ Name ─── Size ─ rail
  S.LIST_TOP = 3
  S.SUM_ROW  = S.H - 3        -- ─┤ N items · free ├─ summary rail
  S.OUT_ROW  = S.H - 2
  S.CMD_ROW  = S.H - 1
  S.STAT_ROW = S.H
  S.LIST_H   = S.SUM_ROW - S.LIST_TOP
  -- Home's TILES view (v1.4 merge). The bottom four rows — summary rail,
  -- output, prompt, status — are the SAME rows in both views by design:
  -- the point of merging the Desktop into the Shell is that the prompt is
  -- never somewhere else, so only the middle of the screen changes. Tiles
  -- therefore get one row less than the file list, spent on the band rail
  -- that carries the page counter.
  S.BAND_ROW = S.RAIL_ROW + 1 -- ─┤ ‹ page 1/2 › ├ N tiles ├─
  S.TILE_TOP = S.BAND_ROW + 1
  S.TILE_H   = S.SUM_ROW - S.TILE_TOP
end

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
  -- Seat index. Fall back to asking the kernel handle: a ctx that forgets
  -- to thread it (the old `tui` command did) must not leave this nil —
  -- a nil seat on tos_logout used to read as GLOBAL logout -> power-off,
  -- and it also widens monitor/process views past this seat.
  S.displayIdx = ctx.displayIdx
    or (ctx.K and ctx.K.getDisplayIdx and ctx.K.getDisplayIdx())
    or nil
  S.W  = ctx.W
  S.H  = ctx.H
  S.T  = S.D.getTheme()
  S.tier = S.D.getGpuTier()

  -- Pre-allocated blank row used by drawing code in place of per-frame
  -- string.rep(" ", W). Substrings of this string are cheap; a fresh
  -- rep on every redraw produces noticeable GC churn at low RAM.
  -- Size + layout constants (also re-runnable after a live screen resize).
  M.recomputeLayout(S)

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
  S.cmdCursor  = 1            -- 1-based insertion point (1 .. #cmdline+1)
  S.cmdSel     = nil          -- selection anchor, same space as cmdCursor
  S.cmdHistory = {}
  S.cmdHistIdx = 0
  S.lastOut    = nil

  -- Live modifier state. Shift+Left and Left are indistinguishable in a
  -- key_down signal — same scancode, no character — so selection needs
  -- the key_up/key_down bookkeeping shell.keys does. See its header for
  -- why the state also expires.
  local okK, keysMod = pcall(require, "shell.keys")
  S.mods = (okK and keysMod and keysMod.newMods) and keysMod.newMods()
    or { shift = false, ctrl = false, alt = false, at = 0 }

  -- The FILE clipboard: a path marked with F5, pasted as a file copy.
  -- Text lives on kernel.clipboard instead — one clipboard shared by the
  -- prompt, the editor and view buffers, and per-seat. These are two
  -- different verbs; see that module's header.
  S.clipboard     = nil

  -- File browser
  S.browser = { path = S.cwd, sel = 1, scroll = 0, files = {} }

  -- Interface shape (Boot Settings → Interface). "home" is the merged
  -- surface: one tab, two views, the prompt resident in both. "split" is
  -- the pre-merge behaviour — a Shell tab and a separate Desktop tab —
  -- kept as an operator escape hatch rather than deleted, because a
  -- rearrangement of surfaces this large should not be a one-way door.
  S.uiSplit = ctx.uiSplit or false

  -- Tab state. In home mode tab 1 IS Home; `view` says which half of it
  -- is drawn and is the only thing F2 changes.
  S.tabs = { { type = "shell",
               label = S.uiSplit and "Shell" or "Home",
               view  = S.uiSplit and "files" or (ctx.homeView or "files") } }
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
