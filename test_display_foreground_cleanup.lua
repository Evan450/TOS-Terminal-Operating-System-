-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Display Foreground Cleanup        ║
-- ║  Kill a foreground process, confirm seat recovers   ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: run /usr/lib/tests/test_display_foreground_cleanup.lua

local passed, failed = 0, 0

local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

print("=== Display Foreground Cleanup Tests ===")
print()

-- Simulate process state
local STATE = { RUNNING = "running", READY = "ready", DEAD = "dead" }
local processes = {}
local displayForeground = {}
local foregroundPID = nil

-- Simulate cleanup logic from proc.kill
local function simulateKill(pid)
  local p = processes[pid]
  if not p then return false end
  p.state = STATE.DEAD

  -- Global foreground cleanup
  if pid == foregroundPID then
    if p.parent and processes[p.parent] and processes[p.parent].state ~= STATE.DEAD then
      foregroundPID = p.parent
    else
      foregroundPID = nil
    end
  end

  -- Per-display foreground cleanup (the fix)
  for dIdx, fgPid in pairs(displayForeground) do
    if fgPid == pid then
      if p.parent and processes[p.parent]
         and processes[p.parent].state ~= STATE.DEAD
         and processes[p.parent].display == dIdx then
        displayForeground[dIdx] = p.parent
      else
        displayForeground[dIdx] = nil
      end
    end
  end

  return true
end

-- Setup: 2 displays, each with a shell process
processes[10] = { state = STATE.READY, display = 1, parent = nil }
processes[20] = { state = STATE.READY, display = 2, parent = nil }
processes[30] = { state = STATE.READY, display = 2, parent = 20 }  -- child on seat 2
displayForeground[1] = 10
displayForeground[2] = 30
foregroundPID = 10

-- Test 1: Kill foreground on seat 2 (PID 30). Should fall back to parent (PID 20)
simulateKill(30)
test("Kill seat 2 fg falls back to parent",
  20, displayForeground[2])
test("Seat 1 unaffected",
  10, displayForeground[1])

-- Test 2: Kill a process that is NOT foreground on any display
processes[40] = { state = STATE.READY, display = 1, parent = nil }
simulateKill(40)
test("Killing non-foreground process leaves seat 1 intact",
  10, displayForeground[1])
test("Killing non-foreground process leaves seat 2 intact",
  20, displayForeground[2])

-- Test 3: Kill foreground on seat 1 (PID 10) — no parent, should clear to nil
simulateKill(10)
test("Kill seat 1 fg with no parent clears to nil",
  nil, displayForeground[1])

-- Test 4: Kill foreground where parent is also dead
processes[50] = { state = STATE.READY, display = 2, parent = nil }
processes[60] = { state = STATE.READY, display = 2, parent = 50 }
displayForeground[2] = 60
simulateKill(50)  -- kill parent first
simulateKill(60)  -- kill child that was foreground
test("Kill fg whose parent is dead clears to nil",
  nil, displayForeground[2])

-- Test 5: Kill foreground where parent is on different display
processes[70] = { state = STATE.READY, display = 1, parent = nil }
processes[80] = { state = STATE.READY, display = 2, parent = 70 }  -- parent on different display
displayForeground[2] = 80
simulateKill(80)
test("Kill fg whose parent is on different display clears to nil",
  nil, displayForeground[2])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
