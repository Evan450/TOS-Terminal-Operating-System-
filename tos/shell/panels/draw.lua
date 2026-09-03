-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Drawing                          ║
-- ║  All TUI rendering: tabs, menus, file list, editor   ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local helpers = require("shell.panels.helpers")
local widgets = require("shell.panels.widgets")
local ui = require("shell.panels.ui")
local selMod = require("shell.panels.selection")

local M = {}

-- Width-aware string helpers. Several rows here carry text that is not
-- ASCII — translated command output, a tile hint, the ▸ in the view
-- legend — and byte math on those slices a UTF-8 character in half and
-- leaves the GPU a broken cell. Declared up here because the rail draws
-- before the output row does.
local function ustrLib()
  local ok, u = pcall(require, "kernel.ustr")
  return (ok and u) or nil
end
local function ufitRow(s, cols)
  local u = ustrLib()
  if u and u.fit then return u.fit(s, cols) end
  return tostring(s or ""):sub(1, cols)
end
local function uwidthRow(s)
  local u = ustrLib()
  if u and u.width then return u.width(s) end
  return #tostring(s or "")
end


-- Menu bar definitions.
-- #REV — reorganized so each item sits where it logically belongs, and the
-- system is MODULAR: any item may carry `action = "run:<command>"` to run an
-- arbitrary shell command, and per-user items from ~/.menu.cfg are merged in
-- by buildMenuDefs(). The old File→Quit was removed (power actions live under
-- System now); F10 still opens the power menu directly.
--
-- Action conventions:
--   action = "<name>"      a built-in handled by menus.execute
--   action = "run:<cmd>"   run <cmd> through the shell executor (modular)
local BASE_MENUS = {
  { label = "File", items = {
    { label = "New File",      action = "newfile" },
    { label = "New Directory", action = "mkdir",   key = "F7" },
    { label = "Rename",        action = "rename" },
    { label = "Delete",        action = "delete",  key = "F8" },
    { sep = true },
    { label = "Refresh",       action = "refresh" },
  }},
  { label = "View", items = {
    { label = "View File",     action = "viewfile", key = "F3" },
    { label = "Edit File",     action = "editfile" },
  }},
  { label = "Tools", items = {
    { label = "Lua REPL",      action = "lua" },
    { label = "Verify System", action = "verify" },
    { label = "Flash EEPROM",  action = "flash" },
    { sep = true },
    -- Added 2026-08-11. The bar had not been touched since it was
    -- written, so a year of new commands were reachable only by typing
    -- them — which for a discovery surface is the whole failure.
    { label = "Packages",      action = "run:pkg" },
    { label = "Repair (SRM)",  action = "run:srm" },
    { label = "Diagnostics",   action = "run:doctor" },
  }},
  { label = "System", items = {
    { label = "Desktop",    action = "run:desktop" },
    { label = "Processes",  action = "ps" },
    { label = "Memory",     action = "mem" },
    { label = "Hardware",   action = "hw" },
    { label = "Disk Usage", action = "df" },
    { label = "System Log", action = "log" },
    { sep = true },
    -- The other interface. It is a first-class way to use the machine,
    -- not a fallback, so it belongs in a menu rather than only in the
    -- quit prompt.
    { label = "CLI Mode",   action = "run:cli" },
    { sep = true },
    { label = "Log Out",    action = "logout" },
    { label = "Reboot",     action = "reboot" },
    { label = "Shut Down",  action = "shutdown" },
  }},
  { label = "Settings", items = {
    { label = "Settings App", action = "run:settings" },
    { label = "Theme",      action = "run:theme list" },
    { label = "Status Bar", action = "statusbar_cfg" },
    { label = "Menu Bar",   action = "run:menu" },
    { label = "Boot Settings", action = "run:bootsettings" },
  }},
  -- Help is the rightmost menu by convention. Every entry maps to an
  -- existing guest-accessible command (help/man/tutorial/about) or, for
  -- "Keyboard Shortcuts", opens a read-only key reference — so the menu is
  -- safe for any tier and exists purely to make discovery easier for new
  -- users who don't yet know the function-key bindings.
  { label = "Help", items = {
    { label = "Quick Help",         action = "help",     key = "F1" },
    { label = "Keyboard Shortcuts", action = "keyhelp" },
    { label = "Manual Pages",       action = "man" },
    { sep = true },
    { label = "Tutorial",           action = "tutorial" },
    { label = "About TOS",          action = "about" },
  }},
}

-- Back-compat default (callers that don't build a per-session copy).
M.menuDefs = BASE_MENUS

-- Deep-ish copy of the base menus (so per-session custom items don't leak
-- across seats by mutating a shared table).
local function cloneMenus()
  local out = {}
  for _, menu in ipairs(BASE_MENUS) do
    local m = { label = menu.label, items = {} }
    for _, it in ipairs(menu.items) do
      local c = {}
      for k, v in pairs(it) do c[k] = v end
      m.items[#m.items + 1] = c
    end
    out[#out + 1] = m
  end
  return out
end

-- ============================================================
-- Operator control over the bar
-- ============================================================
--! Two files, applied in this order, both decoded as DATA (never
--! load()ed — a menu config can arrive on a floppy in someone's home
--! directory):
--!
--!   /etc/menu.cfg    system-wide. Admin-writable via securefs, so it is
--!                    the machine's bar: every user sees it.
--!   ~/.menu.cfg      per-user, layered on top.
--!
--! Each file is a LIST OF EDITS, and the reason it is edits rather than a
--! whole replacement bar is that a replacement goes stale the moment TOS
--! adds a command — which is exactly how the built-in set came to be a
--! year out of date. An edit list survives an upgrade.
--!
--!   { label = "Tetris", cmd = "tetris", menu = "Tools" }   -- add (legacy shape)
--!   { add    = "Tetris", cmd = "tetris", menu = "Tools", after = "Lua REPL" }
--!   { remove = "Flash EEPROM" }              -- an item, by label
--!   { remove = "Help", menu = true }         -- a whole top-level menu
--!   { rename = "Tools", to = "Utilities" }   -- a menu or an item
--!   { move   = "Desktop", menu = "Tools" }   -- item to another menu
--!   { menu   = "Reactor", after = "System" } -- a new empty top-level menu
--!
--! The legacy add shape is kept working byte-for-byte: `menu` config
--! files written before this existed must not break, and an operator who
--! only ever wanted "put my command in a drop-down" should not have to
--! learn the rest of it.

local function findMenu(menus, label)
  for i, m in ipairs(menus) do
    if m.label == label then return m, i end
  end
end

local function findItem(menus, label)
  for _, m in ipairs(menus) do
    for i, it in ipairs(m.items) do
      if it.label == label then return it, i, m end
    end
  end
end

--- Apply one edit to `menus`. Unknown or malformed edits are IGNORED
--- rather than fatal: a typo in a menu config must not cost the operator
--- their menu bar, which is the surface they would use to fix it.
local function applyEdit(menus, e)
  if type(e) ~= "table" then return end
  local function str(v, max)
    return (type(v) == "string" and #v > 0 and #v <= (max or 24)) and v or nil
  end

  -- ── remove ───────────────────────────────────────────────
  if e.remove ~= nil then
    local target = str(e.remove, 32)
    if not target then return end
    if e.menu == true then
      local _, idx = findMenu(menus, target)
      if idx then table.remove(menus, idx) end
    else
      local _, idx, owner = findItem(menus, target)
      if owner then table.remove(owner.items, idx) end
    end
    return
  end

  -- ── rename ───────────────────────────────────────────────
  if e.rename ~= nil then
    local from, to = str(e.rename, 32), str(e.to, 24)
    if not (from and to) then return end
    local m = findMenu(menus, from)
    if m then m.label = to; return end
    local it = findItem(menus, from)
    if it then it.label = to end
    return
  end

  -- ── move an item to another menu ──────────────────────────
  if e.move ~= nil then
    local target, dest = str(e.move, 32), str(e.menu, 24)
    if not (target and dest) then return end
    local it, idx, owner = findItem(menus, target)
    local into = findMenu(menus, dest)
    if it and owner and into then
      table.remove(owner.items, idx)
      into.items[#into.items + 1] = it
    end
    return
  end

  -- ── a new empty top-level menu ────────────────────────────
  if e.menu ~= nil and e.cmd == nil and e.label == nil and e.add == nil then
    local name = str(e.menu, 24)
    if not name or findMenu(menus, name) then return end
    local newM = { label = name, items = {} }
    local _, at = findMenu(menus, str(e.after, 24) or "")
    if at then table.insert(menus, at + 1, newM)
    else table.insert(menus, math.max(1, #menus), newM) end   -- before Help
    return
  end

  -- ── add an item (the legacy shape, plus `after` placement) ─
  local label = str(e.add, 24) or str(e.label, 24)
  local cmd   = (type(e.cmd) == "string" and #e.cmd > 0 and #e.cmd <= 200) and e.cmd or nil
  if not (label and cmd) then return end
  local target = findMenu(menus, e.menu or "")
  if not target then
    target = findMenu(menus, "Custom")
    if not target then
      target = { label = "Custom", items = {} }
      table.insert(menus, math.max(1, #menus), target)   -- before Help
    end
  end
  local item = { label = label, action = "run:" .. cmd }
  local _, at, owner = findItem(menus, str(e.after, 32) or "")
  if at and owner == target then
    table.insert(target.items, at + 1, item)
  else
    target.items[#target.items + 1] = item
  end
end

local function applyConfig(menus, S, path)
  if not (S and S.F and S.F.exists and S.F.exists(path)) then return end
  local data = S.F.readFile(path)
  local okS, ser = pcall(require, "kernel.serialize")
  if not (data and okS and ser and ser.decode) then return end
  local okD, list = pcall(ser.decode, data, { maxBytes = 8192 })
  if not okD or type(list) ~= "table" then return end
  for _, e in ipairs(list) do applyEdit(menus, e) end
end

--- Build the menu set for a session: the built-ins, then the machine's
--- /etc/menu.cfg, then the user's ~/.menu.cfg.
function M.buildMenuDefs(S)
  local menus = cloneMenus()
  applyConfig(menus, S, "/etc/menu.cfg")
  if S and S.who then
    local home = (S.who == "root") and "/root" or ("/home/" .. S.who)
    applyConfig(menus, S, home .. "/.menu.cfg")
  end
  -- A bar with nothing on it is unusable and unfixable from the UI. If
  -- an edit list removed everything, fall back to the built-ins and let
  -- the operator try again — the alternative is a machine you have to
  -- repair from another seat.
  if #menus == 0 then return cloneMenus() end
  return menus
end

-- Exposed so `menu` can preview an edit list without a live session, and
-- so the test can drive the rules directly.
M._applyEdit = applyEdit

-- ── Row 1: the merged top bar ─────────────────────────────────
-- Menus (dim) on the left, ░ ramp filler, tab CHIPS on the right
-- (inverse = active, [brackets] = busy, plain = idle — grammar rule
-- 5), free memory at the far right. The menu and chip SPANS are
-- stored on S at draw time (S._menuSpans / S._tabSpans) and the mouse
-- reads those, so click targets can never drift from the pixels.
function M.topBar(S)
  local D, T, W = S.D, S.T, S.W
  local bfg = T.menubar_fg or T.bar_fg or T.fg
  local bbg = T.menubar_bg or T.bar_bg or T.bg
  D.fill(1, 1, W, 1, " ", bfg, bbg)

  -- Menus (dim; the open/focused one inverts).
  --! `dim` IS NOT ALWAYS LEGIBLE ON A BAR. T1 collapses the palette to
  --! 1-bit and sets dim = 0xFFFFFF, while menubar_bg is also white — so
  --! every inactive menu label used to be drawn white-on-white and simply
  --! vanish. Found while mocking the rework against the real theme
  --! tables. Fall back to the bar's own foreground whenever dim collides
  --! with the bar's background; this is theme-general, so a future preset
  --! that picks the same two colours can't reintroduce it.
  local mdim = (T.dim and T.dim ~= bbg) and T.dim or bfg
  local menuDefs = S.menuDefs or M.menuDefs
  local mSpans = ui.menuSpans(menuDefs)
  local activeIdx = S.menuOpen or (S.menuFocused and S.menuIdx or nil)
  for i, sp in ipairs(mSpans) do
    if menuDefs[i] then menuDefs[i]._x = sp.s end   -- dropdown anchor
    if i == activeIdx then
      D.set(sp.s, 1, sp.text, T.sel_fg or bbg, T.sel_bg or T.highlight)
    else
      D.set(sp.s, 1, sp.text, mdim, bbg)
    end
  end
  S._menuSpans = mSpans
  local menuEnd = #mSpans > 0 and mSpans[#mSpans].e or 1

  -- Free memory, far right (machine ASCII).
  local mem = math.floor(computer.freeMemory() / 1024) .. "K"
  D.set(W - #mem, 1, mem, mdim, bbg)

  -- Let apps update their own chip state first (the program app marks
  -- itself busy while its process is still being scheduled, and closes
  -- its tab if the process is gone). Cheap: only apps defining
  -- `refresh` do anything, and today that is only the program app.
  do
    local okA, appsMod = pcall(require, "shell.panels.apps")
    if okA and appsMod and appsMod.refreshTabs then
      pcall(appsMod.refreshTabs, S)
    end
  end

  -- Tab chips, right-aligned before the memory readout. fitChips
  -- shrinks labels under pressure and, when tabs STILL overflow the
  -- row (six menus leave only ~24 columns on 80 wide), leads with a
  -- clickable «N chip — every tab stays mouse-reachable.
  local spans = ui.fitChips(S.tabs, S.activeTab, W - #mem - 2, menuEnd + 2)
  for _, sp in ipairs(spans) do
    if sp.state == "active" then
      D.set(sp.s, 1, sp.text, T.sel_fg or bbg, T.sel_bg or T.highlight)
    elseif sp.state == "busy" then
      D.set(sp.s, 1, sp.text, T.title or bfg, bbg)
    elseif sp.state == "more" then
      D.set(sp.s, 1, sp.text, T.highlight or T.title or bfg, bbg)
    else
      D.set(sp.s, 1, sp.text, bfg, bbg)
    end
  end
  S._tabSpans = spans

  -- ░ ramp filler between the menu zone and the chips (edges only).
  local fillS = menuEnd + 2
  local fillE = ((spans[1] and spans[1].s) or (W - #mem - 1)) - 2
  if fillE >= fillS then
    D.set(fillS, 1, string.rep("░", fillE - fillS + 1), mdim, bbg)
  end
end
-- Back-compat aliases (older callers named the two rows separately).
M.tabBar = M.topBar
function M.menuBar(S) end  -- folded into topBar

-- ── Row 2: the path + columns rail ────────────────────────────
function M.rail(S)
  local T, W = S.T, S.W
  local SZ_W = 7
  local extraCols = S.tier >= 3 and W >= 80
  local typeW = extraCols and 6 or 0
  local nameW = extraCols and (W - SZ_W - typeW - 4) or (W - SZ_W - 3)
  local sizeAt = nameW + SZ_W - 3
  local parts = {
    { label = S.browser.path },
    { text = "Name" },
  }
  -- The way BACK to the tiles, named in the rail rather than the chip
  -- zone: free columns, and the rail is already where this surface
  -- answers "where am I". Skipped in split mode, where F2 still cycles
  -- tabs and there is no other view of this tab to offer.
  local okH, home = pcall(require, "shell.panels.home")
  local viewPart = nil
  if okH and home and home.enabled(S) then
    local label = home.viewKeyLabel(S) .. " \226\150\184 tiles"
    -- Columns, not bytes — the ▸ is three bytes and one cell, and this
    -- has to land clear of the Size column or the whole header shifts.
    local at = sizeAt - (uwidthRow(label) + 5)
    if at > 14 then
      viewPart = { label = label, at = at }
      parts[#parts + 1] = viewPart
    end
  end
  parts[#parts + 1] = { text = "Size", at = sizeAt }
  if extraCols then
    parts[#parts + 1] = { text = "Type", at = nameW + SZ_W + 2 }
  end
  local spans = ui.drawRail(S.D, T, S.RAIL_ROW, W, parts, { labelFg = T.title or T.fg })
  -- Record where the toggle legend landed so a click on it does what it
  -- says. The span comes from the same call that drew the pixels, so it
  -- can't drift from the rendering.
  if okH and home then
    home.markToggle(S, S.RAIL_ROW, nil, nil)
    for i, p in ipairs(parts) do
      if p == viewPart and spans[i] then
        home.markToggle(S, S.RAIL_ROW, spans[i].s, spans[i].e)
      end
    end
  end
end

-- ── Summary rail above the output row ─────────────────────────
-- States facts (item count + free space on this mount) instead of
-- leaving a dead separator; the free-space figure is cached by
-- helpers.loadFiles so this draw never touches the filesystem.
--
-- SAME ROW IN BOTH VIEWS. Only the facts differ (items vs tiles) —
-- keeping the row itself shared is what stops the bottom of the screen
-- from moving when F2 is pressed.
function M.sumRail(S, text)
  local txt = text
  if not txt then
    local files = S.browser.files or {}
    local n = #files
    if files[1] and files[1].name == ".." then n = n - 1 end
    txt = n .. " items"
    if S.browser.freeStr then txt = txt .. " · " .. S.browser.freeStr .. " free" end
  end
  ui.drawRail(S.D, S.T, S.SUM_ROW, S.W, { { label = txt } })
end

-- Layout for the file-list columns. Centralized so fileList() and
-- fileListRow() agree on widths instead of redoing the math twice.
local function fileListLayout(S)
  local W = S.W
  local SZ_W = 7
  local extraCols = S.tier >= 3 and W >= 80
  local typeW = extraCols and 6 or 0
  local nameW = extraCols and (W - SZ_W - typeW - 4) or (W - SZ_W - 3)
  return SZ_W, typeW, nameW, extraCols
end

local function renderFileListRow(S, fi, y, SZ_W, typeW, nameW, extraCols)
  local D, T, W = S.D, S.T, S.W
  if fi < 1 or fi > #S.browser.files then
    D.fill(1, y, W, 1, " ", T.bg, T.bg)
    return
  end
  local f = S.browser.files[fi]
  local name = f.dir and ("[" .. f.name .. "]") or f.name
  local szStr = f.dir and " <DIR> " or helpers.padL(helpers.fmtSz(f.sz), SZ_W)
  -- Two columns of the name field belong to the type glyph + a space.
  -- The line itself stays pure ASCII (all padding math is byte==column);
  -- the multi-byte glyph is overlaid with its own single-cell set below.
  name = name:sub(1, nameW - 2)
  local namePad = "   " .. helpers.padR(name, nameW - 2)
  local line
  if extraCols then
    local ext = f.dir and "dir" or (f.name:match("%.(%w+)$") or "")
    line = namePad .. " " .. szStr .. " " .. helpers.padR(ext:sub(1, typeW), typeW)
  else
    line = namePad .. " " .. szStr
  end
  local fg, bg
  if fi == S.browser.sel then
    fg, bg = T.sel_fg, T.sel_bg
  else
    fg, bg = helpers.fileColor(S, f), T.bg
  end
  -- PAD to W, don't just truncate to it. The column widths above sum to
  -- W-1 (both branches: 3+nameW-2+1+SZ_W, and the same plus 1+typeW), so
  -- a bare `line:sub(1, W)` left the last column of every row unwritten.
  -- On an unselected row nothing showed; on a SELECTED one that cell kept
  -- the highlight colour, and deselecting repainted 1..W-1 and left it
  -- behind -- reported as a cursor "partly in one place and fully in the
  -- other", which cleared the moment anything repainted that cell.
  --
  -- Padding rather than correcting the arithmetic on purpose: the widths
  -- are derived in fileListLayout from tier and W, and a future column
  -- added there would otherwise be free to be off by one all over again.
  -- The invariant worth holding is "a row paints its whole width", and
  -- that is what test_filelist_row.lua pins.
  D.set(1, y, (line .. S.padW):sub(1, W), fg, bg)
  if W >= 4 then
    D.set(2, y, ui.fileGlyph(f.name, f.dir), fg, bg)
  end
end

function M.fileList(S)
  local SZ_W, typeW, nameW, extraCols = fileListLayout(S)
  for row = 1, S.LIST_H do
    local fi = S.browser.scroll + row
    local y  = S.LIST_TOP + row - 1
    renderFileListRow(S, fi, y, SZ_W, typeW, nameW, extraCols)
  end
end

-- Redraw a single file-list row by file index. Used to repaint just
-- the previously and newly selected rows when arrow-key navigation
-- doesn't move the scroll window — saving a full list redraw.
-- No-op if `fi` is outside the visible window.
function M.fileListRow(S, fi)
  local row = fi - S.browser.scroll
  if row < 1 or row > S.LIST_H then return end
  local SZ_W, typeW, nameW, extraCols = fileListLayout(S)
  renderFileListRow(S, fi, S.LIST_TOP + row - 1, SZ_W, typeW, nameW, extraCols)
end

function M.outRow(S, text, color)
  local D, T, W = S.D, S.T, S.W
  -- Whatever was on this row is gone, including any click target the
  -- legend left behind. A caller that draws a legend re-marks it AFTER
  -- this returns.
  if S._viewToggleSpans then S._viewToggleSpans[S.OUT_ROW] = nil end
  local s = ufitRow(text and tostring(text) or "", W)
  D.set(1, S.OUT_ROW, s .. S.padW:sub(1, math.max(0, W - uwidthRow(s))),
    color or T.dim, T.bg)
end

-- Function-key legend shown on the output row when the shell is idle (no
-- command result to display). Classic file-manager affordance: it makes the
-- F-key bindings discoverable without adding a screen row, and disappears the
-- moment a command produces output (S.lastOut). Width-responsive — entries are
-- dropped from the right on narrow screens so it never wraps or truncates a
-- key mid-label.
local HINT_PARTS = {
  "F1 Help", "F3 View", "F5 Copy", "F6 Move",
  "F7 New", "F8 Del", "F9 Menu", "F10 Quit", "Tab Complete",
}
function M.idleHint(S)
  local D, T, W = S.D, S.T, S.W
  local parts = HINT_PARTS
  -- On Home the flip to tiles is the second thing the legend says, right
  -- after Help — it is the key an operator most needs told about, since
  -- the surface it reaches is no longer a visible tab chip. The label is
  -- read from the live bind, never spelled "F2" here, so rebinding
  -- `view` in /etc/keys.cfg re-labels the legend too.
  local okH, home = pcall(require, "shell.panels.home")
  local flip = nil
  if okH and home and home.enabled(S) then
    flip = home.viewKeyLabel(S) .. " Tiles"
    parts = { HINT_PARTS[1], flip }
    for i = 2, #HINT_PARTS do parts[#parts + 1] = HINT_PARTS[i] end
    home.markToggle(S, S.OUT_ROW, nil, nil)
  end
  local sep, s = "  ", ""
  for _, part in ipairs(parts) do
    local cand = (s == "") and (" " .. part) or (s .. sep .. part)
    if #cand > W then break end
    -- Clickable, like the rail's copy of it. All ASCII here, so byte
    -- offsets are column offsets.
    if flip and part == flip then home.markToggle(S, S.OUT_ROW, #cand - #part + 1, #cand) end
    s = cand
  end
  local padded = (s .. S.padW):sub(1, W)
  D.set(1, S.OUT_ROW, padded, T.dim, T.bg)
end

--- Where the prompt row's pieces land: (promptText, px, avail, hs, cur).
--- Shared by the renderer and by the mouse, so a click can never land on
--- a different character than the one drawn there — the same rule the
--- menu and tab-chip spans already follow.
function M.cmdGeom(S)
  local W = S.W
  local host = S.SC and S.SC.get("hostname") or "tos"
  -- Elevated-shell indicator (sudo -s): a "[sudo]" marker + the classic
  -- "#" prompt sigil so an operator can never forget they're elevated.
  local elevated = S._sudo ~= nil
  local mark  = elevated and "[sudo] " or ""
  local sigil = elevated and "# " or "$ "
  local pr   = mark .. S.who .. "@" .. host .. ":" .. S.cwd .. sigil
  if #pr > math.floor(W / 2) then pr = mark .. S.who .. sigil end
  local px    = #pr + 1
  local avail = W - #pr                       -- columns for cmdline + cursor cell
  if avail < 1 then avail = 1 end
  local cl    = S.cmdline
  local cur   = S.cmdCursor or (#cl + 1)
  if cur < 1 then cur = 1 elseif cur > #cl + 1 then cur = #cl + 1 end
  local hs    = helpers.cmdScroll(#cl, cur, avail)
  return pr, px, avail, hs, cur, elevated
end

--- The command-line index a screen column points at, or nil when the
--- column is left of the prompt text.
function M.cmdIndexAt(S, x)
  local _, px, avail, hs = M.cmdGeom(S)
  if not x or x < px then return nil end
  if x > px + avail - 1 then x = px + avail - 1 end
  local i = (x - px) + 1 + hs
  return math.max(1, math.min(#S.cmdline + 1, i))
end

function M.cmdRow(S)
  local D, T, W = S.D, S.T, S.W
  local pr, px, avail, hs, cur, elevated = M.cmdGeom(S)
  local cl = S.cmdline
  local visible = cl:sub(hs + 1, hs + avail)
  local trail   = S.padW:sub(1, math.max(0, avail - #visible))
  D.set(1,  S.CMD_ROW, pr,               T.highlight, T.bg)
  -- Recolour just the "[sudo]" marker so it stands out from the prompt.
  if elevated then D.set(1, S.CMD_ROW, "[sudo]", T.warning, T.bg) end
  D.set(px, S.CMD_ROW, visible .. trail, T.fg,        T.bg)
  -- Selection: inverse over the selected run, drawn BEFORE the cursor so
  -- the cursor still shows inside it. One cell at a time because the run
  -- is a slice of a line that is itself already horizontally scrolled —
  -- doing the arithmetic once per character is cheaper to get right than
  -- clipping a substring against the visible window.
  local selFrom, selTo = selMod.range(S.cmdSel, cur)
  if selFrom then
    local sfg = T.sel_fg or T.bg
    local sbg = T.sel_bg or T.highlight
    for i = selFrom, selTo - 1 do
      local x = px + (i - 1) - hs
      if x >= px and x <= W then
        D.set(x, S.CMD_ROW, cl:sub(i, i), sfg, sbg)
      end
    end
  end

  -- Cursor: an inverse-video block over the char it sits on (or a "_" at the
  -- end of the line). Drawn last so it overlays the text.
  local curCol = px + ((cur - 1) - hs)
  if curCol >= px and curCol <= W then
    local under = (cur <= #cl) and cl:sub(cur, cur) or "_"
    if under == " " then under = "_" end
    D.set(curCol, S.CMD_ROW, under, T.bg, T.highlight)
  end
end

function M.statusBar(S, widgetDefs)
  local D, T, W = S.D, S.T, S.W
  local wlist = widgets.getWidgetList(S)
  local parts = {}
  for _, wname in ipairs(wlist) do
    local fn = widgetDefs[wname]
    if fn then
      local ok2, val = pcall(fn)
      if ok2 and val then
        parts[#parts + 1] = wname:sub(1, 1):upper() .. wname:sub(2) .. ":" .. val
      end
    end
  end
  ui.drawRampBar(D, T, S.STAT_ROW, W, table.concat(parts, " │ "), nil,
    T.statusbar_fg, T.statusbar_bg)
end

function M.viewTab(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local content = tab.content or {}
  local gutterW = S.tier >= 2 and (#tostring(#content) + 1) or 0
  local viewW = W - gutterW
  local viewH = H - 2

  D.fill(1, 2, W, viewH, " ", T.fg, T.bg)
  for i = 1, viewH do
    local li = tab.offset + i
    if li <= #content then
      local e   = content[li]
      local txt = type(e) == "table" and e[1] or tostring(e)
      local col = type(e) == "table" and e[2] or T.fg

      if gutterW > 0 then
        D.set(1, 1 + i, helpers.formatLineNum(li, gutterW), T.dim, T.bg)
      end

      if tab.searchTerm and #tab.searchTerm > 0 then
        local pos = txt:find(tab.searchTerm, 1, true)
        if pos then
          D.set(gutterW + 1, 1 + i, txt:sub(1, viewW), col, T.bg)
          local matchText = txt:sub(pos, pos + #tab.searchTerm - 1)
          if pos <= viewW then
            D.set(gutterW + pos, 1 + i, matchText:sub(1, viewW - pos + 1), T.sel_fg, T.sel_bg)
          end
        else
          D.set(gutterW + 1, 1 + i, txt:sub(1, viewW), col, T.bg)
        end
      else
        D.set(gutterW + 1, 1 + i, txt:sub(1, viewW), col, T.bg)
      end

      -- Selection is WHOLE LINES here. A view buffer has no cursor to
      -- position within a line, and the thing an operator wants from a
      -- scrollback is "those lines of output", so the granularity that
      -- matches the intent is also the one that needs no new machinery.
      if tab.selAnchor and selMod.lineRange(tab.selAnchor, tab.selCur or tab.selAnchor) then
        local from, to = selMod.lineRange(tab.selAnchor, tab.selCur or tab.selAnchor)
        if li >= from and li <= to then
          D.set(gutterW + 1, 1 + i,
            (txt .. S.padW):sub(1, viewW), T.sel_fg or T.bg, T.sel_bg or T.highlight)
        end
      end
    end
  end
  local shown = math.min(viewH, math.max(0, #content - tab.offset))
  local searchInfo = tab.searchTerm and (" [/" .. tab.searchTerm .. "]") or ""
  local okH, home = pcall(require, "shell.panels.home")
  local cyc = (okH and home) and home.cycleKeyLabel(S) or "F2"
  local info = string.format("%d-%d / %d%s  [^Q]Close [^F]Find [%s]Tab",
    tab.offset + 1, tab.offset + shown, #content, searchInfo, cyc)
  ui.drawRampBar(D, T, H, W, info, nil, T.bar_fg, T.bar_bg)
end

function M.editTab(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local lines = tab.lines or { "" }
  local edH = H - 2
  local gutterW = S.tier >= 2 and (math.max(#tostring(#lines), 2) + 1) or 0
  local editW = W - gutterW
  local isLua = tab.path and tab.path:match("%.lua$")
  local syn = isLua and widgets.getSyntax(S)

  D.fill(1, 2, W, edH, " ", T.fg, T.bg)
  for i = 1, edH do
    local li = tab.viewTop + i - 1
    if li <= #lines then
      local lineText = lines[li]
      local y = 1 + i

      if gutterW > 0 then
        local lnColor = li == tab.curRow and T.title or T.dim
        D.set(1, y, helpers.formatLineNum(li, gutterW), lnColor, T.bg)
      end

      if syn then
        local tokens = syn.tokenize(lineText)
        local x = gutterW + 1
        for _, tok in ipairs(tokens) do
          local tokText = tok.text
          if x - gutterW - 1 + #tokText > editW then
            tokText = tokText:sub(1, editW - (x - gutterW - 1))
          end
          if #tokText > 0 then
            local tc = syn.tokenColor(tok.type, T)
            D.set(x, y, tokText, tc, T.bg)
            x = x + #tokText
          end
          if x > W then break end
        end
      else
        D.set(gutterW + 1, y, lineText:sub(1, editW), T.fg, T.bg)
      end
    end
  end

  -- Selection: inverse over every selected cell, painted over whatever
  -- the syntax highlighter just drew. It runs after the text loop rather
  -- than inside it so the highlighter keeps its own colour logic and
  -- knows nothing about selections.
  if tab.selAnchor then
    local sfg = T.sel_fg or T.bg
    local sbg = T.sel_bg or T.highlight
    local here = { row = tab.curRow, col = tab.curCol }
    for i = 1, edH do
      local li = tab.viewTop + i - 1
      local lineText = lines[li]
      if lineText then
        for cix = 1, math.min(#lineText, editW) do
          if selMod.contains(tab.selAnchor, here, li, cix) then
            D.set(gutterW + cix, 1 + i, lineText:sub(cix, cix), sfg, sbg)
          end
        end
        -- A selection that runs past the end of a line covers the
        -- newline; show that as one highlighted cell so a multi-line
        -- selection doesn't look ragged.
        if #lineText < editW
           and selMod.contains(tab.selAnchor, here, li, #lineText + 1) then
          D.set(gutterW + #lineText + 1, 1 + i, " ", sfg, sbg)
        end
      end
    end
  end

  -- Cursor
  local cy = tab.curRow - tab.viewTop + 2
  if cy >= 2 and cy < 2 + edH then
    local curX = gutterW + tab.curCol
    if curX <= W then
      local char = (lines[tab.curRow] or ""):sub(tab.curCol, tab.curCol)
      if char == "" then char = " " end
      D.set(curX, cy, char, T.sel_fg, T.sel_bg)
    end
  end

  -- Status bar
  local mod = tab.modified and " [+]" or ""
  local searchInfo = tab.searchTerm and (" [/" .. tab.searchTerm .. "]") or ""
  local stat = string.format("%s%s  Ln %d, Col %d%s  [^S]Save [^F]Find [^Q]Close",
    tab.label, mod, tab.curRow, tab.curCol, searchInfo)
  ui.drawRampBar(D, T, H, W, stat, nil, T.bar_fg, T.bar_bg)
end

-- Home. The bottom four rows — summary rail, output, prompt, status —
-- are drawn identically whichever view is up; only the middle changes.
-- That symmetry is the design, not an accident of the code: press F2 and
-- nothing below row H-3 moves, so the prompt is never somewhere else and
-- a command's output lands where the last one did.
function M.shell(S, widgetDefs)
  local okH, home = pcall(require, "shell.panels.home")
  local tab = S.tabs[S.activeTab]
  local tiles = okH and home and home.isTiles(S, tab)

  if tiles then
    home.drawHeader(S, tab)
    home.drawBand(S, tab)
    home.drawTiles(S, tab)
    M.sumRail(S, home.summaryText(S, tab))
  else
    S._homeBand = nil
    M.rail(S)
    M.fileList(S)
    M.sumRail(S)
  end

  -- Command output takes the row from the legend, so the legend's click
  -- target has to go with it — a span left behind would make a click on
  -- someone's `df` output flip the view. outRow clears it; the two
  -- legends re-mark it after they have actually drawn.
  if okH and home then home.markToggle(S, S.OUT_ROW, nil, nil) end
  if S.outLines and #S.outLines > 0 then M.outLines(S)
  elseif S.lastOut then M.outRow(S, S.lastOut[1], S.lastOut[2])
  elseif tiles then
    local txt, ts, te = home.hintText(S, tab)
    M.outRow(S, txt, S.T.dim)
    home.markToggle(S, S.OUT_ROW, ts, te)
  else M.idleHint(S) end
  M.cmdRow(S)
  M.statusBar(S, widgetDefs)
end

-- A short multi-line command result shown INLINE — a transient region just
-- above the prompt, drawn over the bottom of the file list — instead of
-- opening a whole tab for a few lines (the executor gates long output to a
-- real scrollable tab). Cleared on the next keypress (events.lua), which
-- redraws the list. Grows upward from OUT_ROW and never overruns the list top.
function M.outLines(S)
  local D, T, W = S.D, S.T, S.W
  local lines = S.outLines
  if not lines or #lines == 0 then return end
  -- Never grow past the top of the CONTENT region. In the files view
  -- that is the list; on tiles it is one row lower, because the band
  -- rail carrying the page counter has to survive a long result.
  local top = S.LIST_TOP
  local okH, home = pcall(require, "shell.panels.home")
  if okH and home and home.isTiles(S) then top = S.TILE_TOP end
  local n = math.min(#lines, S.OUT_ROW - top + 1)
  local top = S.OUT_ROW - n + 1
  for i = 1, n do
    local e = lines[i] or { "", T.fg }
    D.set(1, top + i - 1, (tostring(e[1] or "") .. S.padW):sub(1, W),
      e[2] or T.fg, T.bg)
  end
end

-- The whole-screen redraw. This is the ONE natural frame boundary in an
-- otherwise immediate-mode TUI, so it is where the seat's hardware
-- backbuffer (when it has one) opens and closes: every draw below lands
-- on the off-screen page and reaches the glass in a single bitblt, which
-- kills the tearing you'd otherwise see mid-redraw on a busy screen.
--
-- endFrame MUST run even if drawing throws — an unclosed frame leaves the
-- GPU pointed at an invisible page and the seat looks dead. Hence the
-- pcall + rethrow rather than a plain call pair. S.D is a seat proxy on a
-- multi-seat rig and plain kernel.display elsewhere; only the former has
-- the frame API, so both are probed for.
function M.all(S, widgetDefs)
  local framed = S.D and S.D.beginFrame and S.D.beginFrame()
  if not framed then return M._allBody(S, widgetDefs) end
  local ok, err = pcall(M._allBody, S, widgetDefs)
  S.D.endFrame()
  if not ok then error(err, 0) end
end

function M._allBody(S, widgetDefs)
  M.topBar(S)
  local tab = S.tabs[S.activeTab]
  -- Core built-in tab kinds stay inline (shell, file viewer, editor); every
  -- other tab type is drawn by its registered app (see shell.panels.apps).
  -- A new interactive tab now registers an app instead of adding a branch
  -- here AND in events.lua.
  if not tab or tab.type == "shell" then
    M.shell(S, widgetDefs)
  elseif tab.type == "view" or tab.type == "output" then
    M.viewTab(S, tab)
  elseif tab.type == "edit" then
    M.editTab(S, tab)
  else
    local ok, apps = pcall(require, "shell.panels.apps")
    if ok and apps then
      apps.ensureBuiltins()
      local app = apps.get(tab.type)
      if app and app.draw then app.draw(S, tab) end
    end
  end
end

function M.menuDropdown(S)
  if not S.menuOpen then return end
  local def = (S.menuDefs or M.menuDefs)[S.menuOpen]
  if not def then return end
  local x = def._x or 2
  S.D.dropdown(x, S.MENU_ROW + 1, def.items, S.menuSel)
end

function M.contextMenu(S)
  if not S.ctxOpen then return end
  S.D.dropdown(S.ctxX, S.ctxY, S.ctxItems, S.ctxSel)
end

return M
