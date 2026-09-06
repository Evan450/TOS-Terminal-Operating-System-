-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the ramp bar paints each cell ONCE           ║
-- ║                                                                ║
-- ║  ui.drawRampBar used to fill the whole row with the filler     ║
-- ║  glyph and then write the caps and the label over it. The      ║
-- ║  picture was right; the cost was not: to the seat proxy's      ║
-- ║  dirty-cell diff, every cap and label cell changed twice per   ║
-- ║  call (to "░", then back to its text), so the shell's 1 Hz     ║
-- ║  status-bar tick re-sent those cells across the OC bridge in   ║
-- ║  four calls every second even when the bar had not changed --  ║
-- ║  which is exactly the redundant repaint the shadow buffer      ║
-- ║  exists to remove, and the reason a "changed cells only"       ║
-- ║  window never helped this row: the caps at both ends always    ║
-- ║  differed, so the changed window was always the full row.      ║
-- ║                                                                ║
-- ║  Now the filler is drawn only where filler ends up, in         ║
-- ║  disjoint runs. Two things are pinned: the rendered row is     ║
-- ║  byte-for-byte what the old algorithm produced, and an         ║
-- ║  unchanged tick costs the GPU nothing.                         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ui_rampbar.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_ui_rampbar.lua"
local base = here:gsub("[^/\\]*$", "")

local fixture
for _, p in ipairs({ base .. "fixture_glass.lua",
    "usr/lib/tests/fixture_glass.lua", "TOS-Dev/usr/lib/tests/fixture_glass.lua" }) do
  local chunk = loadfile(p)
  if chunk then fixture = chunk(); break end
end
if not fixture then
  print("FAIL: could not load fixture_glass.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local G = fixture.newGlass(80, 25).install()
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path

local ui = require("shell.panels.ui")
local ustr = require("kernel.ustr")
local uwidth = ustr.width

print("=== ui.drawRampBar Tests ===")
print()

-- ── A row model that records exactly what a cell ends up holding ──
-- One cell per CHARACTER (the proxy and the hardware both count that way).
local UTF8 = "[\0-\127\194-\255][\128-\191]*"
local function newRow(W)
  local cells = {}
  for x = 1, W do cells[x] = { "\1", nil, nil } end   -- sentinel: never painted
  local D = {}
  function D.set(x, y, text, fg, bg)
    local i = 0
    for ch in text:gmatch(UTF8) do
      local cx = x + i
      if cx >= 1 and cx <= W then cells[cx] = { ch, fg, bg } end
      i = i + 1
    end
  end
  function D.fill(x, y, w, h, ch, fg, bg)
    for cx = x, x + w - 1 do
      if cx >= 1 and cx <= W then cells[cx] = { ch, fg, bg } end
    end
  end
  return D, cells
end
local function rowString(cells)
  local t = {}
  for x = 1, #cells do t[x] = cells[x][1] .. ":" .. tostring(cells[x][2]) .. ":" .. tostring(cells[x][3]) end
  return table.concat(t, " ")
end

-- The OLD algorithm, kept here as the oracle for what the row must look like.
local function oldRampBar(D, th, y, W, left, right, fg, bg)
  fg = fg or th.statusbar_fg or th.bar_fg or th.fg
  bg = bg or th.statusbar_bg or th.bar_bg or th.bg
  local cap = th.dim or fg
  D.fill(1, y, W, 1, "░", cap, bg)
  D.set(1, y, "▓▒░", cap, bg)
  if W > 6 then D.set(W - 2, y, "░▒▓", cap, bg) end
  local lt = ustr.fit(tostring(left or ""), math.max(0, W - 9))
  if uwidth(lt) > 0 then D.set(5, y, " " .. lt .. " ", fg, bg) end
  if right and #right > 0 then
    local rt = " " .. right .. " "
    local rx = W - 3 - #rt
    if rx > 5 + uwidth(lt) + 2 then D.set(rx, y, rt, fg, bg) end
  end
end

local TH = { statusbar_fg = 0xBFE3EE, statusbar_bg = 0x103C4E, dim = 0x556677, fg = 0xFFFFFF, bg = 0 }

print("-- renders exactly what the whole-row version rendered --")
local cases = {
  { "empty label",              80, "",                                   nil },
  { "short label",              80, "Clock:12:00:00 │ Mem:512K",          nil },
  { "label + right text",       80, "Disk:2.4M",                          "root" },
  { "right text that won't fit", 80, string.rep("x", 60),                 "a-long-right-hand-side" },
  { "label wider than the row",  80, string.rep("y", 120),                nil },
  { "narrow T1 row (50 cols)",   50, "Clock:12:00:00 │ Mem:512K",         "r" },
  { "unicode label",             80, "Файлы ▸ tiles",                     nil },
  { "row too narrow for a right cap (6 cols)", 6, "ab",                   nil },
}
for _, c in ipairs(cases) do
  local name, W, left, right = c[1], c[2], c[3], c[4]
  local Dold, oldCells = newRow(W)
  local Dnew, newCells = newRow(W)
  oldRampBar(Dold, TH, 1, W, left, right)
  ui.drawRampBar(Dnew, TH, 1, W, left, right)
  eq(name, rowString(oldCells), rowString(newCells))
  local untouched = 0
  for x = 1, W do if newCells[x][1] == "\1" then untouched = untouched + 1 end end
  eq(name .. ": every cell painted", 0, untouched)
end

-- ── And an unchanged tick is free ──────────────────────────────────
print()
print("-- an unchanged tick costs the GPU nothing --")
do
  local screen = require("kernel.screen")
  screen.init()
  local D = screen.displayProxy(1)
  local calls = 0
  local g = G.gpu
  local realSet, realFill, realFg, realBg = g.set, g.fill, g.setForeground, g.setBackground
  g.set = function(...) calls = calls + 1; return realSet(...) end
  g.fill = function(...) calls = calls + 1; return realFill(...) end
  g.setForeground = function(...) calls = calls + 1; return realFg(...) end
  g.setBackground = function(...) calls = calls + 1; return realBg(...) end

  ui.drawRampBar(D, TH, 25, 80, "Clock:12:00:00 │ Mem:512K", nil)
  test("the first paint reaches the glass", G.rowText(25):find("Mem:512K", 1, true) ~= nil)
  eq("...in the bar colour at the far end", TH.statusbar_bg, G.bgAt(80, 25))
  eq("...and under the label", TH.statusbar_bg, G.bgAt(10, 25))

  calls = 0
  G.clock = G.clock + 5
  ui.drawRampBar(D, TH, 25, 80, "Clock:12:00:00 │ Mem:512K", nil)
  eq("repainting the same bar makes no GPU draw or colour calls", 0, calls)

  calls = 0
  G.clock = G.clock + 5
  ui.drawRampBar(D, TH, 25, 80, "Clock:12:00:01 │ Mem:512K", nil)
  test("a one-digit change costs a single set (" .. calls .. " calls)", calls <= 2)
  test("...and the digit is on the glass", G.rowText(25):find("12:00:01", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
