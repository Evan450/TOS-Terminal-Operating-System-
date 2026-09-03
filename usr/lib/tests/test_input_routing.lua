-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Multi-Screen Input Routing        ║
-- ║  Verifies keyboard vs touch signal dispatch logic   ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: run /usr/lib/tests/test_input_routing.lua

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

-- Simulate the input routing logic from kernel/process.lua
-- In OC:
--   key_down/key_up/clipboard: signal[2] = keyboard component address
--   touch/drag/drop/scroll:    signal[2] = screen component address

local KB_ADDR = "kb-1111-2222-3333"
local SCREEN_ADDR = "scr-aaaa-bbbb-cccc"

-- Mock screen module
local mockScreen = {
  displayForKeyboard = function(addr)
    if addr == KB_ADDR then return 2 end
    return nil
  end,
  displayForScreen = function(addr)
    if addr == SCREEN_ADDR then return 2 end
    return nil
  end,
}

-- This reproduces the routing logic from process.lua
local function resolveDisplay(sigType, sigAddr, scr)
  local dIdx
  if sigType == "key_down" or sigType == "key_up" or sigType == "clipboard" then
    dIdx = scr.displayForKeyboard(sigAddr)
  elseif sigType == "touch" or sigType == "drag" or sigType == "drop" or sigType == "scroll" then
    dIdx = scr.displayForScreen(sigAddr)
  end
  return dIdx
end

print("=== Input Routing Tests ===")
print()

-- Keyboard signals should use displayForKeyboard
test("key_down routes via displayForKeyboard",
  2, resolveDisplay("key_down", KB_ADDR, mockScreen))

test("key_up routes via displayForKeyboard",
  2, resolveDisplay("key_up", KB_ADDR, mockScreen))

test("clipboard routes via displayForKeyboard",
  2, resolveDisplay("clipboard", KB_ADDR, mockScreen))

-- Touch signals should use displayForScreen
test("touch routes via displayForScreen",
  2, resolveDisplay("touch", SCREEN_ADDR, mockScreen))

test("drag routes via displayForScreen",
  2, resolveDisplay("drag", SCREEN_ADDR, mockScreen))

test("drop routes via displayForScreen",
  2, resolveDisplay("drop", SCREEN_ADDR, mockScreen))

test("scroll routes via displayForScreen",
  2, resolveDisplay("scroll", SCREEN_ADDR, mockScreen))

-- Cross-check: keyboard addr should NOT resolve for touch signals
test("touch with keyboard addr returns nil",
  nil, resolveDisplay("touch", KB_ADDR, mockScreen))

-- Cross-check: screen addr should NOT resolve for keyboard signals
test("key_down with screen addr returns nil",
  nil, resolveDisplay("key_down", SCREEN_ADDR, mockScreen))

-- Unknown signal types should return nil (not crash)
test("unknown signal type returns nil",
  nil, resolveDisplay("modem_message", KB_ADDR, mockScreen))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
