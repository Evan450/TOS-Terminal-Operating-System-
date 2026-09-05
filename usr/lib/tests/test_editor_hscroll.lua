-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the editor scrolls sideways                 ║
-- ║                                                                ║
-- ║  It used to draw every line as lineText:sub(1, editW) -- from  ║
-- ║  column 1, always -- and to SKIP drawing the cursor when it    ║
-- ║  fell past the right edge. So typing past the window looked    ║
-- ║  like the editor had stopped responding: the characters were   ║
-- ║  going in, nothing moved, and the cursor was gone.             ║
-- ║                                                                ║
-- ║  The window offset is pure arithmetic and exactly the kind     ║
-- ║  that is wrong by one, so the arithmetic is what is tested     ║
-- ║  here. Drawing itself needs a real GPU and is on the emulator  ║
-- ║  checklist.                                                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_editor_hscroll.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ", want " .. tostring(expected) .. ")",
    expected == actual)
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end

print("=== editor horizontal scrolling ===")
print()

-- ── The rule, mirrored from draw.lua ───────────────────────────────
--! Kept identical to the block in draw.lua on purpose, and the source
--! check below asserts that block still exists. This tests the RULE; the
--! source check stops the rule and the code drifting apart silently.
local function scrollFor(curCol, viewLeft, editW)
  viewLeft = viewLeft or 1
  if curCol < viewLeft then viewLeft = curCol end
  if curCol > viewLeft + editW - 1 then viewLeft = curCol - editW + 1 end
  if viewLeft < 1 then viewLeft = 1 end
  return viewLeft
end

local W = 20   -- a narrow window makes the edges easy to reason about

-- Nothing moves while the cursor is inside the window.
eq("cursor at col 1 stays at offset 1", 1, scrollFor(1, 1, W))
eq("cursor mid-window does not scroll", 1, scrollFor(10, 1, W))

-- THE off-by-one that made the cursor vanish: the last usable column is
-- viewLeft + editW - 1, not viewLeft + editW.
eq("cursor on the LAST visible column does not scroll", 1, scrollFor(W, 1, W))
eq("one past it scrolls by exactly one", 2, scrollFor(W + 1, 1, W))
eq("...and the cursor is then the last visible column",
  W + 1, scrollFor(W + 1, 1, W) + W - 1)

-- Scrolling back left.
eq("moving left of the window pulls it back", 5, scrollFor(5, 12, W))
eq("Home (col 1) returns to offset 1", 1, scrollFor(1, 40, W))
eq("the offset never goes below 1", 1, scrollFor(1, 1, W))

-- A long jump, e.g. End on a long line.
eq("End on a 200-col line shows the end", 200 - W + 1, scrollFor(200, 1, W))

-- Every column of a long line must be reachable AND visible.
do
  local lineLen, vl, bad = 200, 1, 0
  for c = 1, lineLen + 1 do
    vl = scrollFor(c, vl, W)
    if c < vl or c > vl + W - 1 then bad = bad + 1 end
  end
  test("walking a 200-col line keeps the cursor visible at every column ("
    .. bad .. " bad)", bad == 0)
end

-- And walking back leftwards.
do
  local vl, bad = scrollFor(200, 1, W), 0
  for c = 200, 1, -1 do
    vl = scrollFor(c, vl, W)
    if c < vl or c > vl + W - 1 then bad = bad + 1 end
  end
  test("...and walking back to column 1 too (" .. bad .. " bad)", bad == 0)
end

-- A screen that SHRANK must not strand the cursor: draw recomputes from
-- the new width, which is why the rule lives there.
eq("a narrower screen re-anchors the window", 90 - 10 + 1, scrollFor(90, 1, 10))

-- ── The code that must still implement it ──────────────────────────
do
  local d = findUp("tos/shell/panels/draw.lua")
  local e = findUp("tos/shell/panels/events.lua")
  local ed = findUp("tos/shell/panels/editor.lua")
  test("draw.lua readable", d ~= nil)
  test("events.lua readable", e ~= nil)
  test("editor.lua readable", ed ~= nil)

  if d then
    test("draw decides the offset",
      d:find("if tab.curCol > viewLeft + editW - 1 then", 1, true) ~= nil)
    test("the text slice starts at the offset, not column 1",
      d:find("lineText:sub(viewLeft, lastCol)", 1, true) ~= nil)
    test("no line is still drawn from column 1",
      d:find("lineText:sub(1, editW)", 1, true) == nil)
    test("the cursor is offset by the scroll",
      d:find("gutterW + (tab.curCol - viewLeft) + 1", 1, true) ~= nil)
    test("the selection overlay walks visible columns",
      d:find("for cix = viewLeft,", 1, true) ~= nil)
    test("an off-screen continuation is signalled at each edge",
      d:find('"<", T.dim', 1, true) ~= nil and d:find('">", T.dim', 1, true) ~= nil)
    --! The highlighter must see the WHOLE line: tokenizing only the
    --! visible slice can cut a string literal in half, and everything
    --! after it would then be coloured as code.
    test("syntax tokenizes the whole line, then clips",
      d:find("syn.tokenize(lineText)", 1, true) ~= nil and
      d:find("local from = math.max(col, viewLeft)", 1, true) ~= nil)
  end
  if e then
    test("the key handler does NOT compute the offset as well",
      e:find("tab.viewLeft = tab.curCol", 1, true) == nil)
  end
  if ed then
    test("a new edit tab starts at column 1", ed:find("viewLeft   = 1", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
