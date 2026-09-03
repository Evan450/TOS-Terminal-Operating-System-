-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: a file-list row paints its WHOLE width   ║
-- ║                                                            ║
-- ║  Reported from the emulator as a cursor that "shows up      ║
-- ║  partly in one place and fully in the other" — a fragment   ║
-- ║  of the selection bar left behind on the row you moved      ║
-- ║  AWAY from, which cleared as soon as anything repainted     ║
-- ║  that cell.                                                 ║
-- ║                                                            ║
-- ║  Cause: renderFileListRow built its line from the COLUMN    ║
-- ║  widths and then only truncated it — `line:sub(1, W)` —     ║
-- ║  never padding to W. The widths summed to 79 on an 80-      ║
-- ║  column screen, in BOTH layout branches, so column 80 was   ║
-- ║  never written and kept whatever colour it already had.     ║
-- ║  Deselecting repainted 1..79 and left the old highlight in  ║
-- ║  the last cell.                                             ║
-- ║                                                            ║
-- ║  The fix pads rather than re-deriving the arithmetic, so a  ║
-- ║  future column-layout change cannot reintroduce this by     ║
-- ║  being off by one again. This test pins the INVARIANT —     ║
-- ║  every column gets written — not the arithmetic.            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_filelist_row.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }

local okD, draw = pcall(require, "shell.panels.draw")
if not okD then
  print("FAIL: could not load shell.panels.draw: " .. tostring(draw))
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

--- Render one row and report the set of columns actually written.
local function columnsTouched(W, tier, files, sel)
  local covered = {}
  local D = {
    set = function(x, y, s)
      for i = x, x + #s - 1 do covered[i] = true end
    end,
    fill = function(x, y, w)
      for i = x, x + w - 1 do covered[i] = true end
    end,
  }
  local T = setmetatable({}, { __index = function() return 0 end })
  local S = {
    D = D, T = T, W = W, H = 25, tier = tier,
    LIST_TOP = 3, LIST_H = #files, padW = string.rep(" ", W),
    browser = { scroll = 0, sel = sel or 1, files = files },
  }
  draw.fileListRow(S, 1)
  local missing = {}
  for c = 1, W do
    if not covered[c] then missing[#missing + 1] = c end
  end
  return missing
end

print("=== file-list row coverage Tests ===")
print()

local DIR  = { { name = "etc", dir = true } }
local FILE = { { name = "LICENSE.txt", dir = false, sz = 34816 } }

-- Both layout branches, because the arithmetic was short in BOTH and
-- checking one would have proved nothing about the other. tier >= 3 with
-- W >= 80 takes the extra-columns path; anything else does not.
print("-- every column is written --")
for _, case in ipairs({
  { w = 80, tier = 2, what = "80 cols, tier 2 (no extra columns)" },
  { w = 80, tier = 3, what = "80 cols, tier 3 (extra columns)" },
  { w = 50, tier = 1, what = "50 cols, tier 1 (narrow)" },
  { w = 50, tier = 3, what = "50 cols, tier 3 (narrow, no extras)" },
  { w = 160, tier = 3, what = "160 cols, tier 3 (wide)" },
}) do
  for _, files in ipairs({ DIR, FILE }) do
    local kind = files[1].dir and "dir" or "file"
    local missing = columnsTouched(case.w, case.tier, files)
    test(case.what .. " / " .. kind .. ": no unwritten columns"
      .. (#missing > 0 and (" [missing " .. #missing .. ", first "
          .. tostring(missing[1]) .. "]") or ""),
      #missing == 0)
  end
end

-- A selected row is the one that actually shows the bug: it paints a
-- background colour, so any cell it misses keeps that colour after the
-- selection moves away.
print()
print("-- the selected row specifically --")
do
  local files = { { name = "etc", dir = true }, { name = "home", dir = true } }
  local missing = columnsTouched(80, 2, files, 1)
  test("selected row covers all 80 columns", #missing == 0)
end

-- Out-of-range rows already used D.fill(1, y, W, 1, ...) and were fine;
-- pin that so a "tidy-up" cannot make them match the broken path.
print()
print("-- blank rows past the end --")
do
  local covered = {}
  local D = {
    set = function(x, y, s) for i = x, x + #s - 1 do covered[i] = true end end,
    fill = function(x, y, w) for i = x, x + w - 1 do covered[i] = true end end,
  }
  local T = setmetatable({}, { __index = function() return 0 end })
  local S = {
    D = D, T = T, W = 80, H = 25, tier = 2,
    LIST_TOP = 3, LIST_H = 5, padW = string.rep(" ", 80),
    browser = { scroll = 0, sel = 1, files = { { name = "only", dir = true } } },
  }
  draw.fileListRow(S, 3)   -- past the end of the list
  local missing = 0
  for c = 1, 80 do if not covered[c] then missing = missing + 1 end end
  test("an empty row is cleared across the full width", missing == 0)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
