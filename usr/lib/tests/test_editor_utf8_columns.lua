-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the editor counts what the screen counts      ║
-- ║                                                                ║
-- ║  kernel.screen paints one CHARACTER per cell; the editor did    ║
-- ║  its column arithmetic in BYTES. On  local s = "café" -- naïve  ║
-- ║  draw.lua thought the line was 28 columns and the screen        ║
-- ║  painted 26, so from the first non-ASCII character the clip     ║
-- ║  window, the scroll, the ">" marker, the cursor and the         ║
-- ║  selection were all off (AUDIT 5). Left/right stepped one BYTE, ║
-- ║  so the cursor could sit inside é and Backspace deleted half of ║
-- ║  it. And a click on a horizontally scrolled line ignored the    ║
-- ║  scroll altogether.                                             ║
-- ║                                                                ║
-- ║  Drives the REAL textcol, draw.lua (editTab, painting into a    ║
-- ║  fake screen that splits text into cells the way kernel.screen  ║
-- ║  does) and mouse.lua (click, drag, wheel). events.lua's key     ║
-- ║  branches are checked by source, as test_editor_hscroll does.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_editor_utf8_columns.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, want, got)
  test(name .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")", want == got)
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }

local tc = require("shell.panels.textcol")

print("=== the editor counts what the screen counts ===")
print()

-- ── textcol ──────────────────────────────────────────────────
print("-- textcol --")
local CAFE = "caf\195\169"          -- café: é is C3 A9
eq("ASCII: cells are bytes", 5, tc.cells("hello"))
eq("café is 4 cells (5 bytes)", 4, tc.cells(CAFE))
eq("the cell after é", 5, tc.cellOf(CAFE, 6))
eq("é's cell", 4, tc.cellOf(CAFE, 4))
eq("cell 5 is past the end: byte 6", 6, tc.colOf(CAFE, 5))
eq("cell 4 starts at byte 4", 4, tc.colOf(CAFE, 4))
eq("right from é skips both bytes", 6, tc.nextCol(CAFE, 4))
eq("left from the end lands on é's first byte", 4, tc.prevCol(CAFE, 6))
eq("slice of cells 3..4", "f\195\169", tc.slice(CAFE, 3, 4))
-- A three-byte character and a four-byte one.
local BOX = "\226\148\128x"           -- ─x
eq("a box-drawing glyph is one cell", 2, tc.cells(BOX))
eq("...and right steps all three bytes", 4, tc.nextCol(BOX, 1))
local EMOJI = "\240\159\152\128!"     -- U+1F600 then !
eq("a four-byte character is one cell", 2, tc.cells(EMOJI))
-- Bytes that are not UTF-8 stay visible and reachable, one cell each.
local LATIN1 = "a\233b"               -- é in Latin-1: a lone E9
eq("a lone E9 is one cell", 3, tc.cells(LATIN1))
eq("...shown as ?", "a?b", tc.slice(LATIN1, 1, 3))
eq("...and the cursor can step over it", 3, tc.nextCol(LATIN1, 2))
eq("a stray continuation byte too", "?x", tc.slice("\169x", 1, 2))
eq("a truncated sequence at the end", "ab?", tc.slice("ab\195", 1, 3))

-- ── draw.lua's editTab, against a cell-keeping screen ───────
print()
print("-- what the editor draws --")
local draw = require("shell.panels.draw")
local W, H = 30, 8
local cells = {}
local function key(x, y) return y * 1000 + x end
local function screenSplit(s)
  -- kernel.screen's rule: one character per cell.
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\255][\128-\191]*") do out[#out + 1] = ch end
  return out
end
local D = {
  set = function(x, y, s, fg, bg)
    for i, ch in ipairs(screenSplit(s)) do cells[key(x + i - 1, y)] = { ch = ch, fg = fg, bg = bg } end
  end,
  fill = function(x, y, w, h, ch, fg, bg)
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do cells[key(xx, yy)] = { ch = ch, fg = fg, bg = bg } end end
  end,
}
local T = setmetatable({ fg = 1, bg = 2, dim = 3, title = 4, sel_fg = 5, sel_bg = 6,
  bar_fg = 7, bar_bg = 8 }, { __index = function() return 9 end })
local function row(y, x1, x2)
  local out = {}
  for x = x1 or 1, x2 or W do out[#out + 1] = (cells[key(x, y)] or { ch = " " }).ch end
  return table.concat(out)
end
local function render(tab, tier)
  cells = {}
  local S = { D = D, T = T, W = W, H = H, tier = tier or 1, padW = string.rep(" ", W) }
  draw.editTab(S, tab)
  return S
end
local function newTab(lines, o)
  o = o or {}
  return { type = "edit", lines = lines, curRow = o.row or 1, curCol = o.col or 1,
           viewTop = 1, viewLeft = o.viewLeft or 1, label = "t", path = o.path,
           selAnchor = o.sel }
end

-- Tier 1: no gutter, no syntax -- the plain path.
local LINE = 'local s = "' .. CAFE .. '" -- na\195\175ve'   -- the AUDIT's example
eq("the AUDIT line is 27 bytes", 27, #LINE)
eq("...and 25 cells", 25, tc.cells(LINE))
local tab = newTab({ LINE }, { col = 1 })
render(tab)
eq("it is drawn whole, in 25 cells", LINE, row(2, 1, 25))
test("no '>' on a line that fits", (cells[key(W, 2)] or {}).ch ~= ">")

-- The cursor after é sits in the cell after é, not two cells later.
tab = newTab({ CAFE }, { col = 6 })
render(tab)
test("the cursor after café is drawn in cell 5", (cells[key(5, 2)] or {}).bg == T.sel_bg)
test("...and é is untouched in cell 4", (cells[key(4, 2)] or {}).ch == "\195\169")
test("...the status bar says Col 5", row(H, 1, W):find("Col 5", 1, true) ~= nil)

-- Scrolling: a narrow window, cursor at the end of a long accented line.
local LONG = string.rep(CAFE, 10)            -- 40 cells, 50 bytes
tab = newTab({ LONG }, { col = #LONG + 1 })
render(tab)
eq("the view scrolls by cells: 41 - 30 + 1", 12, tab.viewLeft)
test("the cursor is in the last column", (cells[key(W, 2)] or {}).bg == T.sel_bg)
test("the text before it is the line's last 29 cells",
  row(2, 2, W - 1) == tc.slice(LONG, 13, 40))
test("'<' marks the hidden left part", (cells[key(1, 2)] or {}).ch == "<")
tab = newTab({ LONG }, { col = 1 })
render(tab)
test("from column 1, '>' says there is more", (cells[key(W, 2)] or {}).ch == ">")
test("and the visible text is the first 29 cells, whole characters",
  row(2, 1, W - 1) == tc.slice(LONG, 1, 29))

-- Selection paints whole characters at the cells they occupy.
tab = newTab({ CAFE }, { col = 6, sel = { row = 1, col = 4 } })
render(tab)
test("selecting é paints é in its own cell", (cells[key(4, 2)] or {}).ch == "\195\169"
  and (cells[key(4, 2)] or {}).bg == T.sel_bg)
test("...and not the cell before it", (cells[key(3, 2)] or {}).bg ~= T.sel_bg)

-- Invalid bytes are drawn as ? and keep their cell.
tab = newTab({ LATIN1 }, { col = 1 })
render(tab)
eq("a Latin-1 é shows as ?", "a?b", row(2, 1, 3))

-- Tier 2: gutter + syntax highlighting, code-position UTF-8.
local CODE = "local caf\195\169 = 1"
tab = newTab({ CODE }, { col = #CODE + 1, path = "x.lua" })
render(tab, 2)
local gut = 3                                  -- "1 " plus one: max(#"1", 2) + 1
eq("highlighted code is drawn in its cells", CODE, row(2, gut + 1, gut + tc.cells(CODE)))
test("the cursor is right after the 1", (cells[key(gut + tc.cells(CODE) + 1, 2)] or {}).bg == T.sel_bg)

-- ── mouse.lua: click, drag and wheel map cells to bytes ─────
print()
print("-- the mouse --")
local mouse = require("shell.panels.mouse")
-- The real Extras driver when it is beside us, as test_panels_mouse does;
-- otherwise the minimal parse that driver performs.
local driver
local dchunk = loadfile("../TOS-Extras/modules/mouse/usr/lib/mouse.lua")
if dchunk then driver = dchunk() else
  driver = { parse = function(name, _, x, y, k)
    if name == "touch" then return { type = "click", x = x, y = y, button = k or 0 } end
    if name == "scroll" then return { type = "scroll", x = x, y = y, dir = (k or 0) >= 0 and 1 or -1 } end
    if name == "drag" or name == "drop" then return { type = name, x = x, y = y } end
  end }
end
local function mouseS(t)
  return { W = W, H = H, tier = 1, tabs = { t }, activeTab = 1,
           _mouseLib = driver, D = D, T = T }
end
local deps = setmetatable({}, { __index = function() return function() end end })

tab = newTab({ CAFE .. "xyz" }, { col = 1 })
local S = mouseS(tab)
mouse.handle(S, deps, "touch", "scr", 5, 2, 0)
eq("a click on the cell after é puts the cursor after é", 6, tab.curCol)
mouse.handle(S, deps, "touch", "scr", 4, 2, 0)
eq("a click on é puts the cursor on é's first byte", 4, tab.curCol)

-- A scrolled view: the click is a column of the WINDOW, plus the scroll.
tab = newTab({ LONG }, { col = 1, viewLeft = 11 })
S = mouseS(tab)
mouse.handle(S, deps, "touch", "scr", 1, 2, 0)
eq("clicking the first column of a view scrolled to cell 11 lands on cell 11",
  11, tc.cellOf(LONG, tab.curCol))

-- Drag extends a selection to the right cell.
tab = newTab({ CAFE .. "xyz" }, { col = 1 })
S = mouseS(tab)
mouse.handle(S, deps, "touch", "scr", 1, 2, 0)
mouse.handle(S, deps, "drag", "scr", 5, 2, 0)
eq("dragging to the cell after é ends the selection after é", 6, tab.curCol)

-- The wheel keeps the column the operator sees.
local lines = { "abcdef" }
for i = 2, 6 do lines[i] = CAFE .. "zz" end
tab = newTab(lines, { col = 6 })              -- cell 6 on "abcdef"
S = mouseS(tab)
mouse.handle(S, deps, "scroll", "scr", 5, 3, -1)
eq("wheel down to an accented line keeps cell 6 (byte 7 there)", 7, tab.curCol)

-- ── events.lua: the key branches use the same map ───────────
print()
print("-- the keys (by source) --")
do
  local h = io.open("tos/shell/panels/events.lua", "rb")
  local ev = h and h:read("*a"); if h then h:close() end
  test("events.lua readable", ev ~= nil)
  ev = ev or ""
  test("left steps back a whole character",
    ev:find("tab.curCol = tc.prevCol(lines[tab.curRow], tab.curCol)", 1, true) ~= nil)
  test("right steps over a whole character",
    ev:find("tab.curCol = tc.nextCol(lines[tab.curRow], tab.curCol)", 1, true) ~= nil)
  test("Backspace removes a whole character",
    ev:find("local p = tc.prevCol(l, tab.curCol)", 1, true) ~= nil)
  test("Delete removes a whole character",
    ev:find("l:sub(tc.nextCol(l, tab.curCol))", 1, true) ~= nil)
  test("up/down keep the visible column",
    ev:find("tab.curCol = tc.colOf(lines[tab.curRow] or \"\", cell)", 1, true) ~= nil)
  test("no one-byte step left in the editor's arrows",
    ev:find("if tab.curCol > 1 then tab.curCol = tab.curCol - 1", 1, true) == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
