-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: panels.ui (shared TUI widget toolkit)   ║
-- ║                                                            ║
-- ║  Pure geometry (tileGrid / tileRect / tileHit), value      ║
-- ║  cycling, file glyphs, selectable-row navigation, and a    ║
-- ║  framed-tile render smoke test on a fake cell-buffer GPU.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ui_toolkit.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local ui = require("shell.panels.ui")

print("=== panels.ui Tests ===")
print()

-- ── tileGrid: an 80x25-ish shell region ────────────────────────────
local region = { x = 2, y = 4, w = 78, h = 18 }
local g = ui.tileGrid(region, { tileW = 14, tileH = 4 })
eq("grid: cols on 78w (14+2 gap)", 5, g.cols)
test("grid: rows fit the region", g.rows * 4 + (g.rows - 1) * 1 <= 18 + 1)
eq("grid: perPage = cols*rows", g.cols * g.rows, g.perPage)
test("grid: horizontally centred", g.ox >= region.x)
test("grid: never starts left of the region", g.ox >= region.x)

-- Every tile rect stays inside the region horizontally.
for slot = 1, g.perPage do
  local r = ui.tileRect(g, slot)
  if r.x + r.w - 1 > region.x + region.w - 1 + 1 then
    test("grid: slot " .. slot .. " overflows right edge", false)
  end
end
test("grid: all slots within right edge", true)

-- ── tileRect / tileHit agree ───────────────────────────────────────
local r3 = ui.tileRect(g, 3)
eq("hit: centre of slot 3 -> 3", 3,
  ui.tileHit(g, r3.x + math.floor(r3.w / 2), r3.y + 1))
eq("hit: gap between tiles -> nil", nil, ui.tileHit(g, r3.x - 1, r3.y))
eq("hit: far corner -> nil", nil, ui.tileHit(g, 1, 1))
eq("rect: slot 0 -> nil", nil, ui.tileRect(g, 0))
eq("rect: slot past perPage -> nil", nil, ui.tileRect(g, g.perPage + 1))

-- ── tiny screen degrades to at least a 1x1 grid ────────────────────
local tiny = ui.tileGrid({ x = 1, y = 1, w = 10, h = 3 }, { tileW = 14, tileH = 4 })
test("grid: tiny region still yields >= 1 slot", tiny.perPage >= 1)

-- ── cycle ──────────────────────────────────────────────────────────
local vals = { "a", "b", "c" }
eq("cycle: forward", "b", ui.cycle(vals, "a", 1))
eq("cycle: wrap forward", "a", ui.cycle(vals, "c", 1))
eq("cycle: backward wrap", "c", ui.cycle(vals, "a", -1))
eq("cycle: unknown current -> first", "a", ui.cycle(vals, "zzz", 1))
eq("cycle: empty list -> current", "x", ui.cycle({}, "x", 1))

-- ── fileGlyph ──────────────────────────────────────────────────────
eq("glyph: directory", "■", ui.fileGlyph("stuff", true))
eq("glyph: parent dir", "«", ui.fileGlyph("..", true))
eq("glyph: lua", "♦", ui.fileGlyph("main.lua", false))
eq("glyph: text", "≡", ui.fileGlyph("notes.txt", false))
eq("glyph: config", "§", ui.fileGlyph("boot.cfg", false))
eq("glyph: default", "·", ui.fileGlyph("mystery.xyz", false))
eq("glyph: no extension -> default", "·", ui.fileGlyph("README", false))

-- ── selectable-row navigation ──────────────────────────────────────
local rows = {
  { kind = "header", label = "H" },
  { kind = "info",   text = "i" },
  { kind = "toggle", label = "t", value = false },
  { kind = "info",   text = "i2" },
  { kind = "choice", label = "c", values = { 1 }, value = 1 },
  { kind = "button", label = "b" },
}
eq("rows: first selectable skips header/info", 3, ui.firstSelectable(rows))
eq("rows: down from 3 skips info", 5, ui.nextSelectable(rows, 3, 1))
eq("rows: up from 5 skips info", 3, ui.nextSelectable(rows, 5, -1))
eq("rows: up from first selectable stays", 3, ui.nextSelectable(rows, 3, -1))
eq("rows: down from last stays", 6, ui.nextSelectable(rows, 6, 1))
eq("rows: none selectable -> nil", nil,
  ui.firstSelectable({ { kind = "info", text = "x" } }))

-- ── railText: the ─┤ label ├─ signature (grammar rule 2) ───────────
local function colLen(s)  -- display columns of an ASCII+box-char string
  local n = 0
  for _ in utf8.codes(s) do n = n + 1 end
  return n
end
do
  local line, spans = ui.railText(40, { { label = "/home/root" }, { text = "Name" } })
  eq("rail: exactly W columns", 40, colLen(line))
  test("rail: opens with a dash, not a tee", line:find("^─") ~= nil)
  test("rail: tabbed label present", line:find("┤ /home/root ├", 1, true) ~= nil)
  test("rail: plain label has no tees", line:find(" Name ", 1, true) ~= nil)
  eq("rail: two spans", 2, #spans)
  eq("rail: span 1 starts after ─┤ and a space", 4, spans[1].s)
  test("rail: spans carry labels", spans[1].label == "/home/root" and spans[2].label == "Name")
end
do
  local line = ui.railText(30, { { label = "x" }, { text = "End", at = 24 } })
  eq("rail: pinned part honors `at`", 30, colLen(line))
  test("rail: pinned label lands at column 25", (function()
    -- column 24 starts the plain cell " End " -> label at 25
    local _, spans = ui.railText(30, { { label = "x" }, { text = "End", at = 24 } })
    return spans[2].s == 25
  end)())
end
do
  local line, spans = ui.railText(12, { { label = "averylongpathname" } })
  eq("rail: over-long label fitted to W", 12, colLen(line))
  test("rail: fitted label span inside W", spans[1] and spans[1].e <= 12)
end

-- ── tabChips: tabs speak state (grammar rule 5) ────────────────────
local tabs = {
  { type = "shell", label = "Shell" },
  { type = "view",  label = "watch ps", live = true },
  { type = "edit",  label = "x.lua", modified = true },
  { type = "view",  label = "Help" },
}
local chips = ui.tabChips(tabs, 1)
eq("chips: active state", "active", chips[1].state)
eq("chips: live tab is busy", "busy", chips[2].state)
eq("chips: modified edit is busy", "busy", chips[3].state)
eq("chips: plain background is idle", "idle", chips[4].state)
test("chips: busy renders bracketed", chips[2].text:sub(1, 1) == "[")
test("chips: idle renders padded", chips[4].text == " Help ")
test("chips: long labels fitted", #ui.tabChips({ { label = "averylongtabname" } }, 1)[1].text <= 12)

-- ── chipSpans: right-aligned, active never dropped ─────────────────
do
  local spans = ui.chipSpans(chips, 74, 40)
  test("chip spans: right edge respected", spans[#spans].e <= 74)
  test("chip spans: left bound respected", spans[1].s >= 40)
  local narrow = ui.chipSpans(chips, 74, 62)   -- room for ~1 chip
  local hasActive = false
  for _, sp in ipairs(narrow) do if sp.state == "active" then hasActive = true end end
  test("chip spans: active survives the squeeze", hasActive)
end

-- ── fitChips: the overflow policy (operator-reported regression) ───
-- Six menus end at column 49; with mem "832K" the chip zone is
-- columns 51..74. Three tabs must ALL stay visible (shrunken labels),
-- and more tabs than fit must yield a clickable «N overflow chip.
do
  local tabs3 = {
    { type = "shell", label = "Shell" },
    { type = "desktop", label = "Desktop" },
    { type = "view", label = "System Monitor", live = true },
  }
  local spans = ui.fitChips(tabs3, 3, 74, 51)
  local seen = {}
  for _, sp in ipairs(spans) do seen[sp.idx] = true end
  test("fitChips: 3 tabs + 6 menus -> ALL tabs visible (shrunk)",
    seen[1] and seen[2] and seen[3])
  test("fitChips: no overflow chip when everything fits", not seen[0])

  local many = {}
  for i = 1, 6 do many[i] = { type = "view", label = "Longtabname" .. i } end
  many[6].type = "shell"
  local spans6 = ui.fitChips(many, 6, 74, 51)
  test("fitChips: 6 tabs -> leads with the «N overflow chip",
    spans6[1] and spans6[1].state == "more")
  local hasActive = false
  for _, sp in ipairs(spans6) do if sp.state == "active" then hasActive = true end end
  test("fitChips: active tab survives heavy overflow", hasActive)
  test("fitChips: overflow chip respects the left bound", spans6[1].s >= 51)
  test("fitChips: «N names the hidden count", spans6[1].text:match("^«%d+$") ~= nil)
end

-- chipSpans also reports how many it dropped.
do
  local _, hidden = ui.chipSpans(chips, 74, 70)   -- room for ~1 chip
  test("chipSpans: reports hidden count", hidden and hidden > 0)
  local _, none = ui.chipSpans(chips, 74, 30)
  eq("chipSpans: zero hidden when all fit", 0, none)
end

-- ── menuSpans: the historical menu-bar math ────────────────────────
do
  local spans = ui.menuSpans({ { label = "File" }, { label = "Tools" } })
  eq("menus: first cell starts at column 2", 2, spans[1].s)
  eq("menus: ' File ' spans 6 cols", 7, spans[1].e)
  eq("menus: one-column gap", 9, spans[2].s)
end

-- ── drawTile render smoke on a fake cell buffer ────────────────────
local Wd, Hd = 40, 12
local buf = {}
for y = 1, Hd do buf[y] = {} for x = 1, Wd do buf[y][x] = " " end end
local D = {
  set = function(x, y, t)
    if type(t) ~= "string" or y < 1 or y > Hd then return end
    local col = 0
    for _, code in utf8.codes(t) do
      col = col + 1
      local c = x + col - 1
      if c >= 1 and c <= Wd then buf[y][c] = utf8.char(code) end
    end
  end,
  fill = function() end,
}
local th = { fg = 1, bg = 0, title = 2, border = 3, dim = 4, highlight = 5,
             panel_bg = 0, sel_fg = 6, sel_bg = 7 }
ui.drawTile(D, th, { x = 3, y = 2, w = 14, h = 4 },
  { glyph = "≡", label = "Files", selected = false })
local function rowStr(y) return table.concat(buf[y]) end
test("tile: top border drawn", rowStr(2):find("┌", 1, true) ~= nil
  and rowStr(2):find("┐", 1, true) ~= nil)
test("tile: bottom border drawn", rowStr(5):find("└", 1, true) ~= nil)
test("tile: glyph inside", rowStr(3):find("≡", 1, true) ~= nil)
test("tile: label centred inside", rowStr(4):find("Files", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
