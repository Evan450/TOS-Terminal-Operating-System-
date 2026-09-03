-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: the background lifecycle for full-screen programs      ║
-- ║                                                              ║
-- ║  Operator's policy for a program you switch away from:        ║
-- ║    live   — in front, resumed every tick                      ║
-- ║    drowsy — just backgrounded, every 2nd tick, so stepping     ║
-- ║             away for a second and coming back finds it        ║
-- ║             still running                                      ║
-- ║    frozen — backgrounded past the grace period: not resumed   ║
-- ║             at all                                             ║
-- ║  A package may override the middle: "always" never freezes,   ║
-- ║  "freeze" stops the moment you leave.                          ║
-- ║                                                              ║
-- ║  THE COMPATIBILITY GUARANTEE, tested hardest: a process with  ║
-- ║  NO declared policy is a service/shell/daemon, and its        ║
-- ║  scheduling must be bit-for-bit what it always was.           ║
-- ║                                                              ║
-- ║  And the escape hatch: a FROZEN process must still be         ║
-- ║  wakeable, or switching back to it could never work.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bg_lifecycle.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local clock = 0
package.loaded["computer"] = {
  uptime = function() return clock end,
  pullSignal = function() return nil end,
  pushSignal = function() end,
  freeMemory = function() return 1e6 end,
  totalMemory = function() return 1e6 end,
  address = function() return "test" end,
}
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end,
  type = function() return nil end,
}

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local proc = require("kernel.process")

print("=== background lifecycle: live / drowsy / frozen ===")
print()

local D, G = proc.BG_DIVISOR, proc.BG_GRACE
test("the scheduler exposes a divisor and a grace period ("
  .. tostring(D) .. ", " .. tostring(G) .. "s)",
  type(D) == "number" and D >= 2 and type(G) == "number" and G > 0)

-- ── The pure predicate ────────────────────────────────────────────
do
  -- Drowsy: resumed on every Dth tick, well inside the grace period.
  local resumed = 0
  for t = 0, 9 do
    if proc.bgShouldResume("drowsy", 1, t) then resumed = resumed + 1 end
  end
  eq("drowsy resumes 1 tick in " .. D .. " (10 ticks)", 10 // D, resumed)

  local _, s1 = proc.bgShouldResume("drowsy", 1, 0)
  eq("...and reports itself drowsy", "drowsy", s1)

  -- Past the grace period it stops entirely.
  test("drowsy freezes after the grace period",
    proc.bgShouldResume("drowsy", G, 0) == false)
  test("...and stays frozen on every tick",
    proc.bgShouldResume("drowsy", G + 100, 0) == false
    and proc.bgShouldResume("drowsy", G + 100, 1) == false)
  local _, s2 = proc.bgShouldResume("drowsy", G, 0)
  eq("...and reports itself frozen", "frozen", s2)

  -- Just inside the boundary is still drowsy: "leave for a second and
  -- come back and it's still running" is the whole point.
  test("just inside the grace period it is still running",
    proc.bgShouldResume("drowsy", G - 0.1, 0) == true)

  -- "always": the same reduced rate, but it never freezes.
  test("always still runs long past the grace period",
    proc.bgShouldResume("always", G * 10, 0) == true)
  local alwaysResumed = 0
  for t = 0, 9 do
    if proc.bgShouldResume("always", G * 10, t) then
      alwaysResumed = alwaysResumed + 1
    end
  end
  eq("...at the SAME reduced rate, not full speed", 10 // D, alwaysResumed)

  -- "freeze": stops immediately.
  test("freeze never runs, even at t=0",
    proc.bgShouldResume("freeze", 0, 0) == false)
  local _, s3 = proc.bgShouldResume("freeze", 0, 0)
  eq("...and says so", "frozen", s3)

  -- Defensive: nil/garbage inputs must not throw.
  test("nil counters are tolerated", (pcall(proc.bgShouldResume, "drowsy")))
  test("an unknown policy behaves like drowsy",
    proc.bgShouldResume("nonsense", 1, 0) == true
    and proc.bgShouldResume("nonsense", G, 0) == false)
end

-- ── Through the real scheduler ────────────────────────────────────
-- A program in the background must actually be resumed less often than
-- a policy-less process on the same ticks.
do
  clock = 0
  local programRuns, serviceRuns = 0, 0
  local program = proc.spawn("program", function()
    while true do programRuns = programRuns + 1; coroutine.yield() end
  end, { background = "drowsy" })
  local service = proc.spawn("service", function()
    while true do serviceRuns = serviceRuns + 1; coroutine.yield() end
  end)
  test("both processes spawned", program ~= nil and service ~= nil)

  -- Neither is foreground: the program is background from tick one.
  for _ = 1, 20 do proc.tick(nil) end

  test("the SERVICE ran every tick (" .. serviceRuns .. ")", serviceRuns >= 19)
  test("the PROGRAM ran at a reduced rate (" .. programRuns
    .. " vs " .. serviceRuns .. ")",
    programRuns > 0 and programRuns < serviceRuns)

  -- Push past the grace period: the program stops entirely, the
  -- service is untouched.
  local pBefore, sBefore = programRuns, serviceRuns
  clock = clock + G + 1
  for _ = 1, 20 do proc.tick(nil) end
  eq("past the grace period the program is FROZEN", pBefore, programRuns)
  test("...while the service keeps running", serviceRuns > sBefore)
  eq("bgState reports it frozen", "frozen", proc.bgState(program))

  -- THE ESCAPE HATCH: a frozen program must still be wakeable, or you
  -- could never switch back to it.
  proc.signalKernel(program, "tos_focus")
  proc.tick(nil)
  test("a directed signal wakes a FROZEN program", programRuns > pBefore)

  proc.kill(program, { kernel = true }); proc.kill(service, { kernel = true })
end

-- ── Foreground restores full rate ─────────────────────────────────
do
  clock = 0
  local runs = 0
  local pid = proc.spawn("fgprog", function()
    while true do runs = runs + 1; coroutine.yield() end
  end, { background = "drowsy" })
  proc.setForeground(pid, nil, { kernel = true })
  for _ = 1, 10 do proc.tick(nil) end
  test("a FOREGROUND program runs every tick (" .. runs .. ")", runs >= 9)
  eq("bgState reports it live", "live", proc.bgState(pid))
  proc.kill(pid, { kernel = true })
end

-- ── Foreground is a PER-SEAT question ─────────────────────────────
-- On a tick carrying no input, the scheduler's inputFgPID falls back to
-- the GLOBAL foreground. Asking only that question means a program in
-- front on seat 2 reads as backgrounded and runs at half rate while the
-- operator is looking straight at it.
do
  clock = 0
  local seat1Runs, seat2Runs = 0, 0
  local p1 = proc.spawn("seat1prog", function()
    while true do seat1Runs = seat1Runs + 1; coroutine.yield() end
  end, { background = "drowsy", display = 1 })
  local p2 = proc.spawn("seat2prog", function()
    while true do seat2Runs = seat2Runs + 1; coroutine.yield() end
  end, { background = "drowsy", display = 2 })

  -- Seat 1's program is in front on seat 1; seat 2's is in front on
  -- seat 2. BOTH are being watched, so both must run at full rate.
  proc.setForeground(p1, 1, { kernel = true })
  proc.setForeground(p2, 2, { kernel = true })
  for _ = 1, 12 do proc.tick(nil) end
  test("the program in front on seat 1 runs every tick (" .. seat1Runs .. ")",
    seat1Runs >= 11)
  test("the program in front on SEAT 2 also runs every tick ("
    .. seat2Runs .. ")", seat2Runs >= 11)
  eq("seat 2's program is live, not drowsy", "live", proc.bgState(p2))

  proc.kill(p1, { kernel = true }); proc.kill(p2, { kernel = true })
end

-- ── The compatibility guarantee ───────────────────────────────────
-- Nothing that predates this feature declares a policy, so nothing that
-- predates it may change behaviour.
do
  clock = 0
  local runs = 0
  local pid = proc.spawn("legacy", function()
    while true do runs = runs + 1; coroutine.yield() end
  end)   -- NO background option
  for _ = 1, 15 do proc.tick(nil) end
  test("a policy-less process is resumed every tick (" .. runs .. ")", runs >= 14)
  clock = clock + G * 10
  local before = runs
  for _ = 1, 10 do proc.tick(nil) end
  test("...and never freezes, however long it sits in the background",
    runs >= before + 9)
  eq("bgState calls it live", "live", proc.bgState(pid))
  proc.kill(pid, { kernel = true })
end

-- ── The manifest field ────────────────────────────────────────────
do
  local src
  for _, p in ipairs({ "tos/kernel/pkg.lua", "../../../tos/kernel/pkg.lua" }) do
    local h = io.open(p, "rb"); if h then src = h:read("*a"); h:close(); break end
  end
  test("pkg.lua readable", src ~= nil)
  if src then
    test("pkg exposes the declared policy",
      src:find("function pkg.getCommandBackground", 1, true) ~= nil)
    test("an undeclared or misspelt policy falls back to drowsy",
      src:find('return "drowsy"', 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
