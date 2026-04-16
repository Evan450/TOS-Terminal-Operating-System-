-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Seat-Local Foreground Control     ║
-- ║  Confirm fg only affects the caller's seat          ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: run /usr/lib/tests/test_seat_local_fg.lua

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

print("=== Seat-Local Foreground Tests ===")
print()

-- Simulate displayForeground and foregroundPID (from process.lua)
local displayForeground = {}
local foregroundPID = 1

local function setForeground(pid, displayIdx)
  if displayIdx then
    displayForeground[displayIdx] = pid
  else
    foregroundPID = pid
  end
end

local function getForeground(displayIdx)
  if displayIdx then
    return displayForeground[displayIdx] or foregroundPID
  end
  return foregroundPID
end

-- Setup: 2 seats
setForeground(10, 1)  -- PID 10 is foreground on seat 1
setForeground(20, 2)  -- PID 20 is foreground on seat 2

-- Test 1: getForeground with displayIdx returns per-seat value
test("Seat 1 foreground is PID 10",
  10, getForeground(1))
test("Seat 2 foreground is PID 20",
  20, getForeground(2))

-- Test 2: Setting foreground on seat 1 does not affect seat 2
setForeground(15, 1)
test("Seat 1 changed to PID 15",
  15, getForeground(1))
test("Seat 2 still PID 20",
  20, getForeground(2))

-- Test 3: Setting foreground on seat 2 does not affect seat 1
setForeground(25, 2)
test("Seat 2 changed to PID 25",
  25, getForeground(2))
test("Seat 1 still PID 15",
  15, getForeground(1))

-- Test 4: No displayIdx sets global foreground
setForeground(99)
test("Global foreground set to 99",
  99, getForeground())

-- Test 5: Seats still independent of global
test("Seat 1 still PID 15 after global change",
  15, getForeground(1))
test("Seat 2 still PID 25 after global change",
  25, getForeground(2))

-- Test 6: Unmapped display falls back to global
test("Seat 3 (unmapped) falls back to global",
  99, getForeground(3))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
