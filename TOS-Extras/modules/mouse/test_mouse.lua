-- ╔══════════════════════════════════════════════════════╗
-- ║  Test: mouse driver (pure parse + hit-testing)        ║
-- ║                                                        ║
-- ║  The driver's parse() and hit() are pure, so they      ║
-- ║  unit-test off-box. pull() (which calls pullSignal) is  ║
-- ║  exercised against a stubbed computer.                  ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua modules/mouse/test_mouse.lua   (from TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "modules/mouse/test_mouse.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. rel, "modules/mouse/" .. rel,
      "TOS-Extras/modules/mouse/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

local mouse = tryload("usr/lib/mouse.lua")()

print("=== Mouse Driver Tests ===")
print()

-- ── parse() maps each raw OC signal to a normalized event ────────────
do
  local e = mouse.parse("touch", "scr", 5, 7, 0, "Steve")
  test("touch -> click type", "click", e.type)
  test("touch x", 5, e.x)
  test("touch y", 7, e.y)
  test("touch button (left=0)", 0, e.button)
  test("touch carries screen", "scr", e.screen)
  test("touch carries player", "Steve", e.player)
end

do
  local e = mouse.parse("touch", "scr", 1, 1, 1)
  test("right-click button=1", 1, e.button)
end

do
  local e = mouse.parse("drag", "scr", 3, 4, 0)
  test("drag -> drag type", "drag", e.type)
  local d = mouse.parse("drop", "scr", 9, 9, 0)
  test("drop -> drop type", "drop", d.type)
end

do
  local up = mouse.parse("scroll", "scr", 2, 2, 1)
  test("scroll up -> dir +1", 1, up.dir)
  local down = mouse.parse("scroll", "scr", 2, 2, -1)
  test("scroll down -> dir -1", -1, down.dir)
  test("scroll type", "scroll", up.type)
end

-- ── non-mouse signals return nil (so loops can ignore them) ──────────
test("key_down -> nil", nil, mouse.parse("key_down", "kb", 0, 28))
test("modem_message -> nil", nil, mouse.parse("modem_message", "m", 1, 2))
test("nil signal -> nil", nil, mouse.parse(nil))
test("isMouse(touch)", true, mouse.isMouse("touch"))
test("isMouse(key_down)", false, mouse.isMouse("key_down"))

-- ── hit-testing ──────────────────────────────────────────────────────
do
  local regions = {
    mouse.region(3, 6, 9, 3, "red"),
    mouse.region(14, 6, 9, 3, "green"),
    mouse.region(25, 6, 9, 3, "quit"),
  }
  test("inside top-left corner",  "red",   (mouse.hit(regions, 3, 6)))
  test("inside bottom-right",     "red",   (mouse.hit(regions, 11, 8)))   -- x:3..11, y:6..8
  test("just past right edge",    nil,     (mouse.hit(regions, 12, 6)))
  test("just below bottom edge",  nil,     (mouse.hit(regions, 3, 9)))
  test("green button",            "green", (mouse.hit(regions, 18, 7)))
  test("quit button",             "quit",  (mouse.hit(regions, 30, 7)))
  test("miss between buttons",    nil,     (mouse.hit(regions, 13, 7)))
  test("inside() direct true",    true,    mouse.inside(regions[1], 5, 7))
  test("inside() direct false",   false,   mouse.inside(regions[1], 50, 7))
end

-- ── pull() against a stubbed computer: skips non-mouse, returns mouse ─
do
  local queue = {
    { "key_down", "kb", 0, 28 },     -- ignored
    { "timer", 1 },                  -- ignored
    { "touch", "scr", 4, 5, 0, "P" } -- the one we want
  }
  local t = 0
  package.loaded["computer"] = {
    uptime = function() t = t + 0.01; return t end,
    pullSignal = function() return table.unpack(table.remove(queue, 1) or {}) end,
  }
  -- reload the lib so its require("computer") picks up our stub
  package.loaded["mouse"] = nil
  local m2 = tryload("usr/lib/mouse.lua")()
  local ev = m2.pull(5)
  test("pull skips non-mouse, returns click", "click", ev and ev.type)
  test("pull returns the touch coords", 4, ev and ev.x)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
