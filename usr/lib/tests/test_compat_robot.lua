-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Test: compat/robot.lua, and two bugs under it                     ║
-- ║                                                                    ║
-- ║  Drives the REAL compat.robot through the REAL                     ║
-- ║  kernel.peripheral.robot onto a fake component proxy that records   ║
-- ║  the exact argument LIST it was called with, count included. The   ║
-- ║  count matters: both bugs pinned here were about which slot an     ║
-- ║  argument landed in, and a recorder that only looked at values     ║
-- ║  would have missed them.                                           ║
-- ║                                                                    ║
-- ║  What the mod actually accepts (Agent.scala @Callback docs, the    ║
-- ║  only authority):                                                  ║
-- ║    swing(side[, face=side[, sneaky=false]])                        ║
-- ║    use  (side[, face=side[, sneaky=false[, duration=0]]])          ║
-- ║    place(side[, face=side[, sneaky=false]])                        ║
-- ║                                                                    ║
-- ║  BUG 1: robot.use passed `sneaking or false` as argument 2 — a     ║
-- ║  BOOLEAN where the mod checks for the integer `face`, on every     ║
-- ║  call, including calls that asked for no sneaking. So `use` raised ║
-- ║  bad-argument on a real robot whatever you gave it.                ║
-- ║  BUG 2: robot.durability called p.durabilityLevel(), which does    ║
-- ║  not exist in OpenComputers, inside a pcall whose failure branch   ║
-- ║  returned "no tool equipped" — so every robot reported an empty    ║
-- ║  tool slot, including robots holding a tool.                       ║
-- ║                                                                    ║
-- ║  Neither was visible off-box before, because a mock proxy answers  ║
-- ║  to any method name with any arguments. This one does not.         ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_robot.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " (expected " .. tostring(expected) ..
          ", got " .. tostring(actual) .. ")")
  end
end

package.path = "tos/?.lua;" .. package.path

-- ── The fake robot ────────────────────────────────────────
local last          -- { method, n, [1], [2], ... } of the most recent call
local selectedSlot = 4
local hasDurability = true

local function record(method)
  return function(...)
    last = { method = method, n = select("#", ...), ... }
    if method == "select" and select("#", ...) == 0 then return selectedSlot end
    return true
  end
end

local fake = {
  move = record("move"), turn = record("turn"),
  swing = record("swing"), use = record("use"), place = record("place"),
  detect = record("detect"), drop = record("drop"), suck = record("suck"),
  select = record("select"), count = record("count"), space = record("space"),
  inventorySize = record("inventorySize"), name = record("name"),
  compare = record("compare"), compareTo = record("compareTo"),
  transferTo = record("transferTo"),
  tankCount = record("tankCount"), tankLevel = record("tankLevel"),
  tankSpace = record("tankSpace"), selectTank = record("selectTank"),
  getLightColor = record("getLightColor"),
  setLightColor = record("setLightColor"),
}
fake.durability = function() return 0.75 end

package.loaded["kernel.hal"] = {
  proxy = function(ctype) return ctype == "robot" and fake or nil end,
}

-- A process holding the cap, so getProxy()'s per-call check passes.
local withCap    = { pid = 1, name = "prog", caps = { ["peripheral.robot"] = true } }
local withoutCap = { pid = 2, name = "prog", caps = {} }
local current    = withCap
package.loaded["kernel.process"] = { current = function() return current end }

local robot = require("compat.robot")

-- Assert the last recorded call: method, arg count, then each argument.
local function called(label, method, n, ...)
  local want = { n = select("#", ...), ... }
  local ok = last and last.method == method and last.n == n
  if ok then
    for i = 1, n do
      if last[i] ~= want[i] then ok = false; break end
    end
  end
  if ok then passed = passed + 1; print("  PASS: " .. label)
  else
    failed = failed + 1
    local got = "(nothing)"
    if last then
      local parts = {}
      for i = 1, last.n do parts[#parts + 1] = tostring(last[i]) end
      got = last.method .. "(" .. table.concat(parts, ", ") .. ")  [n=" ..
            last.n .. "]"
    end
    print("  FAIL: " .. label .. " — got " .. got)
  end
end

print("── movement maps to the right sides ──")
robot.forward();   called("forward is move(3)",  "move", 1, 3)
robot.back();      called("back is move(2)",     "move", 1, 2)
robot.up();        called("up is move(1)",       "move", 1, 1)
robot.down();      called("down is move(0)",     "move", 1, 0)
robot.turnLeft();  called("turnLeft is turn(false)",  "turn", 1, false)
robot.turnRight(); called("turnRight is turn(true)",  "turn", 1, true)

print("── turnAround is two turns the same way ──")
do
  local turns = 0
  local realTurn = fake.turn
  fake.turn = function(...) turns = turns + 1; return realTurn(...) end
  robot.turnAround()
  eq("two turns", 2, turns)
  called("both to the left", "turn", 1, false)
  fake.turn = realTurn
end

print("── the directional variants ──")
robot.detect();     called("detect is detect(3)",      "detect", 1, 3)
robot.detectUp();   called("detectUp is detect(1)",    "detect", 1, 1)
robot.detectDown(); called("detectDown is detect(0)",  "detect", 1, 0)
robot.compare();     called("compare is compare(3)",     "compare", 1, 3)
robot.compareUp();   called("compareUp is compare(1)",   "compare", 1, 1)
robot.compareDown(); called("compareDown is compare(0)", "compare", 1, 0)
robot.swingDown();   called("swingDown is swing(0)",     "swing", 1, 0)
robot.swingUp();     called("swingUp is swing(1)",       "swing", 1, 1)
robot.swing();       called("swing is swing(3)",         "swing", 1, 3)
robot.dropUp(5);     called("dropUp(5) is drop(1, 5)",   "drop", 2, 1, 5)
robot.dropDown(2);   called("dropDown(2) is drop(0, 2)", "drop", 2, 0, 2)
robot.suck(7);       called("suck(7) is suck(3, 7)",     "suck", 2, 3, 7)
robot.suckDown();    called("suckDown() still names the side", "suck", 2, 0, 64)
robot.placeUp();     called("placeUp is place(1)",       "place", 1, 1)

print("── BUG 1: no boolean may land in the mod's `face` slot ──")
robot.use()
called("use() passes the side ALONE (was: use(3, false))", "use", 1, 3)
test("...and argument 2 is not a boolean", type(last[2]) ~= "boolean")
robot.use(nil, true)
called("use(nil, true) sneaks in slot 3", "use", 3, 3, 3, true)
test("...with a NUMBER in the face slot", type(last[2]) == "number")
robot.useDown(nil, true)
called("useDown sneaks on the bottom side", "use", 3, 0, 0, true)
robot.use(2, true, 1.5)
called("a duration goes in slot 4", "use", 4, 3, 2, true, 1.5)
robot.swing(2, true)
called("swing's face and sneaky are slots 2 and 3", "swing", 3, 3, 2, true)
robot.placeDown(1, true)
called("place likewise", "place", 3, 0, 1, true)

print("── BUG 2: durability asks for the method the mod has ──")
eq("a tool reads 0.75", 0.75, robot.durability())
do
  local saved = fake.durability
  fake.durability = function() return nil, "no tool equipped" end
  local v, why = robot.durability()
  test("an empty slot still says so", v == nil and why == "no tool equipped")
  fake.durability = nil     -- a proxy that has no durability() at all
  local v2, why2 = robot.durability()
  test("a proxy without the method reports THAT, not 'no tool equipped'",
       v2 == nil and tostring(why2):find("durability", 1, true) ~= nil
       and tostring(why2) ~= "no tool equipped")
  fake.durability = saved
end

print("── inventory ──")
robot.select(3);      called("select(3)", "select", 1, 3)
eq("select() reads the current slot", selectedSlot, robot.select())
robot.count(2);       called("count(2)", "count", 1, 2)
robot.space(2);       called("space(2)", "space", 1, 2)
robot.compareTo(2);   called("compareTo(2)", "compareTo", 1, 2)
robot.transferTo(2, 9); called("transferTo(2, 9)", "transferTo", 2, 2, 9)
robot.transferTo(2);  called("transferTo(2) sends the stack", "transferTo", 1, 2)
robot.inventorySize(); called("inventorySize()", "inventorySize", 0)
test("select(0) is refused",  robot.select(0) == nil)
test("select(-1) is refused", robot.select(-1) == nil)

print("── tanks and the status light ──")
robot.tankCount();       called("tankCount()", "tankCount", 0)
robot.tankLevel();       called("tankLevel() uses the selected tank", "tankLevel", 0)
robot.tankLevel(2);      called("tankLevel(2)", "tankLevel", 1, 2)
robot.tankSpace(2);      called("tankSpace(2)", "tankSpace", 1, 2)
robot.selectTank(2);     called("selectTank(2)", "selectTank", 1, 2)
robot.getLightColor();   called("getLightColor()", "getLightColor", 0)
robot.setLightColor(0x00FF00)
called("setLightColor(0x00FF00)", "setLightColor", 1, 0x00FF00)

print("── the capability is still what decides ──")
current = withoutCap
do
  local v, why = robot.forward()
  test("no cap, no movement", v == nil and why == "no robot component")
  local d = robot.durability()
  test("no cap, no durability either", d == nil)
end
current = withCap
test("and it works again with the cap", robot.forward() == true)

print("── level() is honest about the experience upgrade ──")
eq("no experience component reachable under this cap: 0", 0, robot.level())

print("── every name in the OpenOS robot API exists ──")
do
  -- The API as the mod's own reference implementation spells it.
  local API = {
    "name", "level", "getLightColor", "setLightColor",
    "detect", "detectUp", "detectDown",
    "inventorySize", "select", "count", "space", "compareTo", "transferTo",
    "compare", "compareUp", "compareDown",
    "drop", "dropUp", "dropDown", "suck", "suckUp", "suckDown",
    "place", "placeUp", "placeDown",
    "durability", "swing", "swingUp", "swingDown",
    "use", "useUp", "useDown",
    "forward", "back", "up", "down",
    "turnLeft", "turnRight", "turnAround",
    "tankCount", "selectTank", "tankLevel", "tankSpace",
  }
  local missing = {}
  for _, fn in ipairs(API) do
    if type(robot[fn]) ~= "function" then missing[#missing + 1] = fn end
  end
  test("no gaps in the surface", #missing == 0)
  if #missing > 0 then print("    missing: " .. table.concat(missing, ", ")) end
end

print("")
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
print("All tests passed.")
