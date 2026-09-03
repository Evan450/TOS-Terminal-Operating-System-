-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Login Backoff Schedule (H-5)       ║
-- ║  Pins the exponential-cooldown contract used by       ║
-- ║  users.login() so root (un-lockable) is still         ║
-- ║  rate-limited against online brute force.             ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_login_backoff.lua
--
-- NOTE: loginCooldown is a module-local in kernel/users.lua and the
-- module can't be loaded without the full kernel environment, so — per
-- the repo's existing test convention (see test_path_boundary.lua) —
-- this mirrors the schedule and asserts the intended behaviour. If the
-- constants in users.lua change, update both in lockstep.

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Mirror of kernel/users.lua loginCooldown (#SEC H-5).
local THROTTLE_AFTER = 3
local THROTTLE_BASE  = 5
local THROTTLE_CAP   = 300
local function loginCooldown(fails)
  fails = tonumber(fails) or 0
  if fails < THROTTLE_AFTER then return 0 end
  local c = THROTTLE_BASE * (2 ^ (fails - THROTTLE_AFTER))
  if c > THROTTLE_CAP then c = THROTTLE_CAP end
  return c
end

print("=== Login Backoff Schedule Tests ===")
print()

-- Free attempts: no cooldown below the threshold.
test("0 fails -> no cooldown", 0, loginCooldown(0))
test("1 fail  -> no cooldown", 0, loginCooldown(1))
test("2 fails -> no cooldown", 0, loginCooldown(2))

-- Exponential growth once backoff engages.
test("3 fails -> 5s",  5,   loginCooldown(3))
test("4 fails -> 10s", 10,  loginCooldown(4))
test("5 fails -> 20s", 20,  loginCooldown(5))
test("6 fails -> 40s", 40,  loginCooldown(6))
test("7 fails -> 80s", 80,  loginCooldown(7))
test("8 fails -> 160s", 160, loginCooldown(8))

-- Cap holds for large counts (root never hard-locks, so this matters).
test("9 fails -> capped 300s",   300, loginCooldown(9))
test("100 fails -> capped 300s", 300, loginCooldown(100))

-- Cooldown is always finite (no permanent lockout from backoff alone).
local finite = true
for f = THROTTLE_AFTER, 200 do
  local c = loginCooldown(f)
  if type(c) ~= "number" or c > THROTTLE_CAP then finite = false end
end
test("cooldown never exceeds cap", true, finite)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
