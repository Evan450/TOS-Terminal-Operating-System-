-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: rows are measured in CELLS, not bytes        ║
-- ║                                                                ║
-- ║  On the headless machine, `pkg verify-sig` on a tampered       ║
-- ║  package printed                                               ║
-- ║    Signature: DOES NOT VERIFY — signature does not match   ──  ║
-- ║  with two cells of the file panel's border left at the end of  ║
-- ║  the line. The inline output padded each line with spaces and  ║
-- ║  cut it with `:sub(1, W)`, which counts BYTES: "—" is three    ║
-- ║  bytes in one cell, so the row came up two cells short and the ║
-- ║  old contents showed through. The file list did the same with  ║
-- ║  an accented name, and the viewer's `txt:sub(1, viewW)` could  ║
-- ║  cut a character in half at the right edge.                    ║
-- ║                                                                ║
-- ║  Counts what reaches the screen the way the screen paints it:  ║
-- ║  one character per cell (shell.panels.textcol).                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_draw_cells.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }

local tc = require("shell.panels.textcol")
local okD, draw = pcall(require, "shell.panels.draw")
test("draw loads", okD, draw)
if not okD then
  print("*** TESTS FAILED ***"); os.exit(1)
end

local T = setmetatable({}, { __index = function() return 0 end })

--- A screen that remembers, per row, which cells were written and what
--- text each set() carried.
local function screen()
  local rows, texts = {}, {}
  local D = {}
  function D.set(x, y, s)
    s = tostring(s)
    texts[#texts + 1] = { x = x, y = y, s = s }
    rows[y] = rows[y] or {}
    for c = x, x + tc.cells(s) - 1 do rows[y][c] = true end
  end
  function D.fill(x, y, w, h)
    for r = y, y + (h or 1) - 1 do
      rows[r] = rows[r] or {}
      for c = x, x + w - 1 do rows[r][c] = true end
    end
  end
  local function missing(y, W)
    local out = {}
    for c = 1, W do if not (rows[y] and rows[y][c]) then out[#out + 1] = c end end
    return out
  end
  local function valid(s)
    local _, disps = tc.units(s)
    for i, d in ipairs(disps) do
      local starts = select(1, tc.units(s))
      if d == "?" and s:sub(starts[i], starts[i]) ~= "?" then return false end
    end
    return true
  end
  return D, missing, texts, valid
end

print("=== rows are measured in cells ===")

-- ── The inline output area ────────────────────────────────────────
print("-- command output --")
do
  local D, missing = screen()
  local W = 80
  local S = { D = D, T = T, W = W, H = 25, padW = string.rep(" ", W),
              LIST_TOP = 3, TILE_TOP = 4, OUT_ROW = 24,
              outLines = { { "Signature: DOES NOT VERIFY — signature does not match", 0 } } }
  draw.outLines(S)
  local gap = missing(24, W)
  test("a line with an em dash paints the whole row", #gap == 0, table.concat(gap, ","))
end

-- ── A file-list row ───────────────────────────────────────────────
print("-- the file list --")
for _, case in ipairs({ { w = 80, tier = 3 }, { w = 80, tier = 2 }, { w = 50, tier = 1 } }) do
  local D, missing = screen()
  local S = { D = D, T = T, W = case.w, H = 25, tier = case.tier,
              LIST_TOP = 3, LIST_H = 1, padW = string.rep(" ", case.w),
              browser = { scroll = 0, sel = 1, files = { { name = "résumé — notes.txt", dir = false, sz = 1234 } } } }
  draw.fileListRow(S, 1)
  local gap = missing(3, case.w)
  test(("an accented name's row is painted to the edge (%d cols, tier %d)"):format(case.w, case.tier),
    #gap == 0, table.concat(gap, ","))
end

-- ── The viewer ────────────────────────────────────────────────────
print("-- the viewer --")
do
  local D, _, texts, valid = screen()
  local W = 80
  -- One line, so the tier-2 gutter is 2 cells and the text gets 78: byte
  -- 78 falls inside the em dash.
  local line = string.rep("a", 77) .. "—" .. "b"
  local S = { D = D, T = T, W = W, H = 25, tier = 2, padW = string.rep(" ", W) }
  local tab = { type = "view", content = { { line, 0 } }, offset = 0 }
  draw.viewTab(S, tab)
  local drawn
  for _, t in ipairs(texts) do
    if t.y == 2 and t.x == 3 then drawn = t.s end
  end
  test("the viewer drew the line", drawn ~= nil)
  if drawn then
    test("...without cutting a character in half", valid(drawn), drawn:sub(-4):byte(1, -1))
    test("...and filling its 78 cells", tc.cells(drawn) == 78, tc.cells(drawn))
  end
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
