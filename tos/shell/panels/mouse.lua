-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Mouse Input                      ║
-- ║  Click/scroll handling via the optional mouse driver ║
-- ╚══════════════════════════════════════════════════════╝
-- TOS has no baked-in mouse support (like MS-DOS): this module only
-- comes alive when the Optional Utilities "mouse" package has installed
-- its userspace driver, require("mouse") (/usr/lib/mouse.lua). The
-- driver normalizes raw OC touch/drag/drop/scroll signals; this module
-- maps the resulting events onto the panels UI:
--
--   tab bar      click switches tab; right-click closes a closable tab
--   menu bar     click toggles a menu open/closed
--   dropdowns    click runs the item; clicking elsewhere closes
--   file list    left-click selects; left-click the selection again does
--                the quick action (enter a dir / view a file); right-click
--                opens the context menu (the detailed options); scroll
--                moves the selection
--   view tab     scroll wheel scrolls the content; drag selects lines
--   editor       click places the cursor; scroll moves it by rows;
--                drag selects a range of text
--   prompt       click places the cursor; drag selects
--
-- Without the driver installed every mouse signal is ignored, exactly
-- as before — keyboard behaviour is unchanged either way.
--
-- All collaborators arrive via the `deps` table (built in events.lua),
-- so this module has no kernel requires and unit-tests off-box.

local M = {}

local function uptime()
  local ok, c = pcall(require, "computer")
  if ok and c and c.uptime then return c.uptime() end
  return os and os.clock and os.clock() or 0
end

-- ── Driver probe ─────────────────────────────────────────────
-- S._mouseLib caches the loaded driver (table) or false (probed,
-- missing). A missing driver is re-probed at most every 10s so
-- installing the mouse package mid-session starts working without a
-- re-login, while an uninstalled driver costs one fs.exists per probe
-- window instead of one failed require per touch.
local REPROBE_SECS = 10

function M.available(S)
  if type(S._mouseLib) == "table" then return S._mouseLib end
  if S._mouseLib == false
     and uptime() < (S._mouseProbeAt or 0) + REPROBE_SECS then
    return nil
  end
  S._mouseProbeAt = uptime()
  S._mouseLib = false
  -- Cheap existence check first — require() raises on missing modules.
  local F = S.F
  if F and F.exists and not F.exists("/usr/lib/mouse.lua") then return nil end
  -- Honor the package manager's enabled bit when the driver came in as
  -- the "mouse" package (a hand-copied lib has no pkg record and runs).
  local okP, pkgMod = pcall(require, "kernel.pkg")
  if okP and pkgMod and pkgMod.info and pkgMod.info("mouse")
     and pkgMod.isEnabled and not pkgMod.isEnabled("mouse") then
    return nil
  end
  local ok, lib = pcall(require, "mouse")
  if ok and type(lib) == "table" and lib.parse then
    S._mouseLib = lib
    return lib
  end
  return nil
end

-- ── Geometry ─────────────────────────────────────────────────
-- Row 1 (the merged menus+tabs bar) is hit-tested against the SPANS
-- draw.topBar stored on S at draw time (S._menuSpans / S._tabSpans) —
-- the same table that placed the pixels, so clicks can never drift
-- from the rendering. The menu fallback below reproduces topBar's
-- span math only for the pre-first-draw edge case.

local function spanAt(spans, px)
  for _, sp in ipairs(spans or {}) do
    if px >= sp.s and px <= sp.e then return sp end
  end
  return nil
end

-- Which menu label the click landed on. Prefers stored spans; falls
-- back to the historical math (first label at x=2, " label " cells,
-- one gap — keep in sync with ui.menuSpans).
local function menuAt(S, menuDefs, px)
  local sp = spanAt(S._menuSpans, px)
  if sp then return sp.idx end
  if S._menuSpans then return nil end
  local x = 2
  for i, item in ipairs(menuDefs) do
    local label = " " .. (item.label or "") .. " "
    if px >= x and px < x + #label then return i end
    x = x + #label + 1
  end
  return nil
end

-- Which tab CHIP the click landed on (stored spans only — chips are
-- right-aligned against live values, so there is no static fallback).
-- Returns (idx) for a real tab, or (nil, true) for the «N overflow chip.
local function tabAt(S, px)
  local sp = spanAt(S._tabSpans, px)
  if not sp then return nil end
  if sp.state == "more" then return nil, true end
  return sp.idx
end

-- The «N overflow chip is a PREVIOUS-TAB button (wrapping): the active
-- tab is always rendered, so repeated clicks walk the entire tab list
-- even when more tabs exist than the row can ever show. (An earlier
-- "activate the nearest hidden" rule stalled once tab 1 was active,
-- because the dropped chips are then MIDDLE tabs.)
local function activateHidden(S)
  local n = #S.tabs
  if n < 2 then return end
  S.activeTab = (S.activeTab > 1) and (S.activeTab - 1) or n
end

-- Dropdown box geometry (mirror of display.dropdown's sizing+clamping).
local function dropdownGeom(S, x, y, items)
  local maxLabelW, maxKeyW = 0, 0
  for _, item in ipairs(items) do
    if not item.sep then
      maxLabelW = math.max(maxLabelW, #(item.label or ""))
      maxKeyW   = math.max(maxKeyW, #(item.key or ""))
    end
  end
  local gap = maxKeyW > 0 and 2 or 0
  local dw = maxLabelW + gap + maxKeyW + 4  -- 2 border + 2 margin
  local dh = #items + 2                     -- 2 border
  if x + dw > S.W then x = S.W - dw end
  if x < 1 then x = 1 end
  if y + dh > S.H then y = S.H - dh end
  if y < 1 then y = 1 end
  return x, y, dw, dh
end

local function insideBox(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end

-- ── Click handling ───────────────────────────────────────────
-- Returns (drawLevel, result) where result propagates menu actions
-- like "exit"/"cli" back to the event loop.
local function handleClick(S, deps, ev)
  local px, py = ev.x, ev.y
  local tab = S.tabs[S.activeTab]
  local tabType = tab and tab.type or "shell"

  -- #REV — read the LIVE per-session menus (S.menuDefs), not the snapshot
  -- captured when the mouse deps table was built: the `menu` command
  -- rebuilds S.menuDefs at runtime, and a stale deps.menuDefs would make
  -- clicks target the old menu layout while the keyboard used the new one.
  local menuDefs = S.menuDefs or deps.menuDefs
  -- Open dropdown menu has first claim on clicks (keyboard parity).
  if S.menuOpen then
    local def = menuDefs[S.menuOpen]
    local dx, dy, dw, dh = dropdownGeom(S, def._x or 2, S.MENU_ROW + 1, def.items)
    if insideBox(px, py, dx, dy, dw, dh) then
      local idx = py - dy  -- items start one row below the border
      local item = def.items[idx]
      if item and not item.sep then
        S.menuSel = idx
        return 3, deps.menuExecute(item)
      end
      return 3  -- border or separator: stay open
    end
    if py ~= S.MENU_ROW then
      S.menuOpen = nil; S.menuFocused = false
      return 3
    end
    -- A click on the menu bar row falls through to the toggle below.
  end

  -- Open context menu.
  if S.ctxOpen then
    local dx, dy, dw, dh = dropdownGeom(S, S.ctxX, S.ctxY, S.ctxItems)
    if insideBox(px, py, dx, dy, dw, dh) then
      local idx = py - dy
      local item = S.ctxItems[idx]
      if item and not item.sep then
        S.ctxSel = idx
        deps.ctxExecute(item.action)
      end
      return 3
    end
    S.ctxOpen = false
    return 3
  end

  -- Row 1 — the merged bar: menus on the left, tab chips on the right.
  -- Menus: click toggles (from a non-shell tab, jump to the shell tab
  -- first, mirroring the F9 keyboard behaviour). Chips: left-click
  -- switches, right-click closes (when closable).
  if py == (S.MENU_ROW or 1) then
    local mIdx = menuAt(S, menuDefs, px)
    if mIdx then
      if tabType ~= "shell" then
        for i, t2 in ipairs(S.tabs) do
          if t2.type == "shell" then S.activeTab = i; break end
        end
      end
      if S.menuOpen == mIdx then
        S.menuOpen = nil; S.menuFocused = false
      else
        S.menuOpen = mIdx; S.menuSel = 1
        S.menuFocused = true; S.menuIdx = mIdx
      end
      return 3
    end
    local idx, isMore = tabAt(S, px)
    if isMore then
      activateHidden(S)
      return 3
    end
    if not idx then
      if S.menuOpen then S.menuOpen = nil; S.menuFocused = false; return 3 end
      return 0
    end
    if ev.button == 1 then
      local t2 = S.tabs[idx]
      if t2 and t2.type ~= "shell" then
        if t2.type == "edit" and t2.modified then
          -- Don't silently drop unsaved work; surface the tab instead.
          S.activeTab = idx
          S.lastOut = { "Unsaved changes — close with F4", (S.T or {}).warning }
        else
          deps.closeTab(idx)
        end
      end
    else
      S.activeTab = idx
    end
    return 3
  end

  if tabType == "shell" then
    -- The command prompt: click to place the cursor, drag to select.
    -- Same row in both Home views, which is the whole point of the
    -- merge, so this needs no view test.
    if py == S.CMD_ROW then
      local col = deps.cmdColAt and deps.cmdColAt(px)
      if col then
        S.cmdCursor = col
        S.cmdSel = nil
        S._drag = { kind = "cmd" }
        return 1
      end
      return 0
    end

    -- Home carries its own click targets on rows the file view doesn't
    -- use: the tile field, the band rail's ‹ › page markers, and the F2
    -- legend itself. A surface that tells you which key flips it should
    -- also let you click the words — that costs nothing and is the first
    -- thing someone tries.
    local okH, home = pcall(require, "shell.panels.home")
    if okH and home and home.enabled(S) then
      if ev.button ~= 1 and home.hitToggle(S, px, py) then
        home.toggle(S, tab)
        return 3
      end
      if home.isTiles(S, tab) then
        return home.handleClick(S, tab, ev, deps)
      end
    end

    -- File list — left and right click do DIFFERENT things (a mouse has
    -- both; the keyboard reaches options via Enter instead):
    --   RIGHT-click            → context menu (the detailed options)
    --   LEFT-click (unselected) → just select
    --   LEFT-click (selected)   → the quick action: open a dir / view a file
    if py >= S.LIST_TOP and py < S.LIST_TOP + S.LIST_H then
      local fi = S.browser.scroll + (py - S.LIST_TOP) + 1
      local f = S.browser.files[fi]
      if not f then return 0 end
      local prevSel = S.browser.sel
      S.browser.sel = fi
      if ev.button == 1 then
        deps.openContextMenu()         -- right-click: options, on any file
        return 3
      end
      if prevSel == fi then            -- left-click the selection: quick action
        if f.name == ".." then deps.navigateUp()
        elseif f.dir then deps.navigateInto(f.name)
        elseif deps.viewFile then deps.viewFile()   -- open/view the file
        else deps.openContextMenu() end             -- fallback if no viewer wired
        return 3
      end
      -- Selection moved within the visible window: repaint just the two
      -- affected rows (same fast path as arrow-key navigation).
      if deps.drawFileListRow then
        deps.drawFileListRow(prevSel)
        deps.drawFileListRow(fi)
        return 0
      end
      return 2
    end
    return 0
  end

  -- Registered app tabs (Desktop/Settings/…) own their whole surface below
  -- the tab bar. Dispatch the click to the app's onMouse via the registry
  -- instead of a hardcoded per-type chain. get() returns nil for the core
  -- types (shell/view/edit) so they fall through to their handling below.
  if tab then
    local ok, appsMod = pcall(require, "shell.panels.apps")
    if ok and appsMod then
      appsMod.ensureBuiltins()
      local app = appsMod.get(tabType)
      if app and app.onMouse then return app.onMouse(S, tab, ev, deps) or 0 end
    end
  end

  -- Editor: click places the cursor (gutter-aware) and arms a drag.
  if tabType == "edit" and tab then
    local edH = S.H - 2
    if py >= 2 and py < 2 + edH then
      local lines = tab.lines or { "" }
      local gutterW = S.tier >= 2 and (math.max(#tostring(#lines), 2) + 1) or 0
      tab.curRow = math.max(1, math.min(#lines, (tab.viewTop or 1) + (py - 2)))
      tab.curCol = math.max(1, math.min(#(lines[tab.curRow] or "") + 1, px - gutterW))
      -- A click CLEARS the selection and remembers where it started;
      -- dragging from here is what turns it into one.
      tab.selAnchor = nil
      S._drag = { kind = "edit", row = tab.curRow, col = tab.curCol }
      return 1
    end
    return 0
  end

  -- View buffer: click marks a line, dragging extends the run.
  if (tabType == "view" or tabType == "output") and tab then
    local viewH = S.H - 2
    if py >= 2 and py < 2 + viewH then
      local li = (tab.offset or 0) + (py - 1)
      local content = tab.content or {}
      if li >= 1 and li <= #content then
        tab.selAnchor, tab.selCur = li, li
        S._drag = { kind = "view" }
        return 1
      end
    end
    return 0
  end

  return 0
end

-- ── Drag handling ────────────────────────────────────────────
-- A drag is only ever a SELECTION here. TOS has no drag-and-drop and is
-- not getting one: moving a file by dragging it needs a drop target, a
-- hover state and an undo story, none of which exist. Selecting text is
-- the gesture people actually reach for on a terminal.
local function handleDrag(S, deps, ev)
  local d = S._drag
  if not d then return 0 end
  local tab = S.tabs[S.activeTab]
  local px, py = ev.x, ev.y

  if d.kind == "cmd" then
    local col = deps.cmdColAt and deps.cmdColAt(px)
    if not col then return 0 end
    if col == S.cmdCursor then return 0 end
    if not S.cmdSel then S.cmdSel = S.cmdCursor end
    S.cmdCursor = col
    if S.cmdSel == S.cmdCursor then S.cmdSel = nil end
    return 1

  elseif d.kind == "edit" and tab and tab.type == "edit" then
    local lines = tab.lines or { "" }
    local edH = S.H - 2
    local gutterW = S.tier >= 2 and (math.max(#tostring(#lines), 2) + 1) or 0
    local row = math.max(1, math.min(#lines, (tab.viewTop or 1) + (py - 2)))
    local col = math.max(1, math.min(#(lines[row] or "") + 1, px - gutterW))
    if py < 2 or py >= 2 + edH then return 0 end
    if not tab.selAnchor then
      tab.selAnchor = { row = d.row or tab.curRow, col = d.col or tab.curCol }
    end
    tab.curRow, tab.curCol = row, col
    return 1

  elseif d.kind == "view" and tab and (tab.type == "view" or tab.type == "output") then
    local content = tab.content or {}
    local viewH = S.H - 2
    local li = (tab.offset or 0) + (py - 1)
    -- Dragging past the top or bottom edge scrolls, so a selection can
    -- run longer than the window.
    if py < 2 then
      tab.offset = math.max(0, (tab.offset or 0) - 1); li = (tab.offset or 0) + 1
    elseif py >= 2 + viewH then
      tab.offset = math.min(math.max(0, #content - viewH), (tab.offset or 0) + 1)
      li = (tab.offset or 0) + viewH
    end
    li = math.max(1, math.min(#content, li))
    tab.selCur = li
    return 1
  end
  return 0
end

-- ── Scroll handling ──────────────────────────────────────────
local function handleScroll(S, deps, ev)
  local dir = ev.dir or 0
  if dir == 0 then return 0 end
  local tab = S.tabs[S.activeTab]
  local tabType = tab and tab.type or "shell"

  if tabType == "shell" then
    if S.menuOpen or S.ctxOpen then return 0 end
    local okH, home = pcall(require, "shell.panels.home")
    if okH and home and home.isTiles(S, tab) then
      return home.handleScroll(S, tab, ev)
    end
    -- Wheel moves the file-list selection, exactly like Up/Down.
    local delta = dir > 0 and -1 or 1
    local newSel = math.max(1, math.min(#S.browser.files, S.browser.sel + delta))
    if newSel == S.browser.sel then return 0 end
    local prevSel, prevScroll = S.browser.sel, S.browser.scroll
    S.browser.sel = newSel
    if newSel <= S.browser.scroll then S.browser.scroll = newSel - 1 end
    if newSel > S.browser.scroll + S.LIST_H then S.browser.scroll = newSel - S.LIST_H end
    if S.browser.scroll == prevScroll and deps.drawFileListRow then
      deps.drawFileListRow(prevSel)
      deps.drawFileListRow(newSel)
      return 0
    end
    return 2

  elseif (tabType == "view" or tabType == "output") and tab then
    local content = tab.content or {}
    local viewH = S.H - 2
    local step = dir > 0 and -3 or 3
    local maxOff = math.max(0, #content - viewH)
    local newOff = math.max(0, math.min(maxOff, (tab.offset or 0) + step))
    if newOff == (tab.offset or 0) then return 0 end
    tab.offset = newOff
    return 1

  elseif tabType == "edit" and tab then
    local lines = tab.lines or { "" }
    local edH = S.H - 2
    local step = dir > 0 and -3 or 3
    tab.curRow = math.max(1, math.min(#lines, tab.curRow + step))
    tab.curCol = math.max(1, math.min(#(lines[tab.curRow] or "") + 1, tab.curCol))
    if tab.curRow < tab.viewTop then tab.viewTop = tab.curRow end
    if tab.curRow > tab.viewTop + edH - 1 then tab.viewTop = tab.curRow - edH + 1 end
    return 1

  elseif tab then
    -- Registered app tab (Desktop/Settings/…): dispatch to its onScroll.
    local ok, appsMod = pcall(require, "shell.panels.apps")
    if ok and appsMod then
      appsMod.ensureBuiltins()
      local app = appsMod.get(tabType)
      if app and app.onScroll then return app.onScroll(S, tab, ev) or 0 end
    end
  end
  return 0
end

-- ── Entry point ──────────────────────────────────────────────
-- Feed a raw signal tuple. Returns nil when the driver is missing or
-- the signal isn't a mouse event; otherwise (drawLevel[, result]).
function M.handle(S, deps, sig, addr, x, y, btn, player)
  local lib = M.available(S)
  if not lib then return nil end
  local ev = lib.parse(sig, addr, x, y, btn, player)
  if not ev then return nil end

  if ev.type == "click" then
    return handleClick(S, deps, ev)
  elseif ev.type == "scroll" then
    return handleScroll(S, deps, ev)
  elseif ev.type == "drag" then
    return handleDrag(S, deps, ev)
  elseif ev.type == "drop" then
    -- The gesture is over. The selection it produced stays; only the
    -- "we are mid-drag" flag goes away, so a later stray drag event
    -- (a different button, a driver hiccup) cannot extend it.
    S._drag = nil
    return 0
  end
  return 0
end

return M
