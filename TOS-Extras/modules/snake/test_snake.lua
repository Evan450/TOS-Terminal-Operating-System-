-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: snake/logic.lua                            ║
-- ║                                                              ║
-- ║  Pure rules, no hardware stubs. Movement, growth, the        ║
-- ║  reversal guard, wall + self collision (incl. the legal      ║
-- ║  tail-chase), food never landing on the snake, and the       ║
-- ║  difficulty ramp.                                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/snake/test_snake.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "modules/?.lua;modules/?/init.lua;" .. package.path
local L = require("snake.logic")

print("=== snake/logic Tests ===")
print()

-- ── Construction ───────────────────────────────────────────────────
do
  local s = L.newSnake(20, 10)
  eq("new snake has 3 segments", 3, #s.body)
  eq("starts alive", true, s.alive)
  eq("starts heading right", "right", s.dir)
  eq("starts with no score", 0, s.score)
  test("head is left of nothing (body trails behind)",
    s.body[1].x > s.body[2].x and s.body[2].x > s.body[3].x)
end

-- ── Movement ───────────────────────────────────────────────────────
do
  local s = L.newSnake(20, 10)
  local hx, hy = s.body[1].x, s.body[1].y
  local tail = s.body[#s.body]
  L.step(s, function() return 1 end)
  eq("head advanced one cell right", hx + 1, s.body[1].x)
  eq("row unchanged", hy, s.body[1].y)
  eq("length unchanged without food", 3, #s.body)
  test("the tail vacated", not (s.body[#s.body].x == tail.x and s.body[#s.body].y == tail.y))
end

-- ── Turning + the reversal guard ───────────────────────────────────
do
  local s = L.newSnake(20, 10)
  eq("can turn perpendicular", true, L.turn(s, "up"))
  L.step(s, function() return 1 end)
  eq("direction applied on the next step", "up", s.dir)

  local s2 = L.newSnake(20, 10)          -- heading right, 3 long
  eq("cannot reverse into your own neck", false, L.turn(s2, "left"))
  eq("direction unchanged after a refused turn", "right", s2.pendingDir)
  eq("unknown direction refused", false, L.turn(s2, "sideways"))
end

-- ── Walls kill ─────────────────────────────────────────────────────
do
  local s = L.newSnake(5, 5)
  for _ = 1, 10 do L.step(s, function() return 1 end) end
  eq("running into the wall kills", false, s.alive)
  local s2 = L.newSnake(6, 6)
  L.turn(s2, "up")
  for _ = 1, 10 do L.step(s2, function() return 1 end) end
  eq("the top wall kills too", false, s2.alive)
end

-- ── Eating grows + scores ──────────────────────────────────────────
do
  local s = L.newSnake(20, 10)
  local h = s.body[1]
  s.food = { x = h.x + 1, y = h.y }
  L.step(s, function() return 1 end)
  eq("eating grows the body", 4, #s.body)
  eq("eating scores", 1, s.score)
  eq("the grew flag is set for the UI", true, s.grew)
  test("new food was placed", s.food ~= nil)
  test("new food is NOT under the snake",
    not L.hits(s, s.food.x, s.food.y, false))
  L.step(s, function() return 1 end)
  eq("grew flag clears on the next tick", false, s.grew)
end

-- ── Self-collision, and the tail-chase exemption ───────────────────
do
  local s = L.newSnake(20, 10)
  s.body = {
    { x = 5, y = 5 }, { x = 6, y = 5 }, { x = 6, y = 6 },
    { x = 5, y = 6 }, { x = 4, y = 6 },
  }
  s.dir, s.pendingDir = "down", "down"    -- 5,5 -> 5,6 which is occupied
  L.step(s, function() return 1 end)
  eq("hitting your own body kills", false, s.alive)

  local s2 = L.newSnake(20, 10)
  s2.body = { { x = 5, y = 5 }, { x = 6, y = 5 }, { x = 6, y = 6 }, { x = 5, y = 6 } }
  s2.dir, s2.pendingDir = "down", "down"  -- 5,5 -> 5,6 == the tail
  L.step(s2, function() return 1 end)
  eq("following your own tail is legal", true, s2.alive)
end

-- ── Food placement + the full-board win ────────────────────────────
do
  local s = L.newSnake(3, 1)
  s.body = { { x = 1, y = 1 }, { x = 2, y = 1 } }
  L.placeFood(s, function(n) return n end)
  eq("food lands on the only free cell (x)", 3, s.food.x)
  eq("food lands on the only free cell (y)", 1, s.food.y)

  local full = L.newSnake(2, 1)
  full.body = { { x = 1, y = 1 }, { x = 2, y = 1 } }
  eq("a full board reports no room for food", false,
    L.placeFood(full, function() return 1 end))
end

-- ── Difficulty ramp ────────────────────────────────────────────────
do
  test("delay shrinks as the score climbs", L.snakeDelay(10) < L.snakeDelay(0))
  test("delay floors (stays playable)", L.snakeDelay(1000) >= 0.07)
  eq("the floor is exactly 0.07", 0.07, L.snakeDelay(1000))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
