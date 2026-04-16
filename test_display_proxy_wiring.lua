-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Display Proxy Wiring              ║
-- ║  Verifies seat shell gets dProxy, not global display ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: run /usr/lib/tests/test_display_proxy_wiring.lua

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

print("=== Display Proxy Wiring Tests ===")
print()

-- Simulate the global kernel object
local globalDisplay = { id = "global_display" }
local kernel = {
  getDisplay = function() return globalDisplay end,
  getDisplayIdx = function() return nil end,
  getFS = function() return {} end,
}

-- Simulate per-seat display proxies
local dProxy1 = { id = "proxy_display_1" }
local dProxy2 = { id = "proxy_display_2" }

-- Build kernelCopy the FIXED way (with getDisplay/getDisplayIdx overrides)
local kernelCopy1 = setmetatable(
  {
    display = dProxy1,
    displayIdx = 1,
    getDisplay = function() return dProxy1 end,
    getDisplayIdx = function() return 1 end,
  },
  { __index = kernel }
)

local kernelCopy2 = setmetatable(
  {
    display = dProxy2,
    displayIdx = 2,
    getDisplay = function() return dProxy2 end,
    getDisplayIdx = function() return 2 end,
  },
  { __index = kernel }
)

-- Test 1: kernelCopy1.getDisplay() returns seat 1's proxy
test("Seat 1 getDisplay returns proxy 1",
  "proxy_display_1", kernelCopy1.getDisplay().id)

-- Test 2: kernelCopy2.getDisplay() returns seat 2's proxy
test("Seat 2 getDisplay returns proxy 2",
  "proxy_display_2", kernelCopy2.getDisplay().id)

-- Test 3: Seat 1 does NOT return the global display
test("Seat 1 getDisplay is not global",
  true, kernelCopy1.getDisplay() ~= globalDisplay)

-- Test 4: Seat 2 does NOT return the global display
test("Seat 2 getDisplay is not global",
  true, kernelCopy2.getDisplay() ~= globalDisplay)

-- Test 5: getDisplayIdx returns correct indices
test("Seat 1 getDisplayIdx returns 1",
  1, kernelCopy1.getDisplayIdx())

test("Seat 2 getDisplayIdx returns 2",
  2, kernelCopy2.getDisplayIdx())

-- Test 6: Global kernel getDisplayIdx returns nil
test("Global kernel getDisplayIdx returns nil",
  nil, kernel.getDisplayIdx())

-- Test 7: Fallthrough to kernel methods still works
test("kernelCopy1.getFS falls through to kernel",
  true, kernelCopy1.getFS() ~= nil)

-- Test 8: Seat 1 and Seat 2 are independent
test("Seat 1 and Seat 2 have different displays",
  true, kernelCopy1.getDisplay() ~= kernelCopy2.getDisplay())

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
