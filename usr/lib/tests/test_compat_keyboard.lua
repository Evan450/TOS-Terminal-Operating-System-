-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: keyboard.isKeyDown works, and per seat        ║
-- ║                                                                ║
-- ║  AUDIT 5, H-03. compat.keyboard called                          ║
-- ║  component.keyboard.isKeyDown -- a method the OC keyboard       ║
-- ║  component does not have (it only emits key_down / key_up;      ║
-- ║  OpenOS tracks held keys in software). It raised on every       ║
-- ║  machine WITH a keyboard, so isControlDown -- OpenOS's Ctrl-C   ║
-- ║  test -- crashed a ported program on its interrupt path. And it ║
-- ║  asked the PRIMARY keyboard: another seat's, on two seats.      ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.process (proc.tick is where held keys   ║
-- ║  are now tracked) and the REAL compat.keyboard.                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_keyboard.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
local clock = 100
package.loaded["computer"] = { uptime = function() return clock end,
  pullSignal = function() end }
-- A keyboard component exactly as OC has one: no isKeyDown method at all.
package.loaded["component"] = {
  isAvailable = function(t) return t == "keyboard" end,
  keyboard = { address = "kb1" },
  list = function() return function() end end,
}
local KB1, KB2 = "kb1", "kb2"
local callerSeat = nil
package.loaded["kernel.screen"] = {
  displayForKeyboard = function(kb) return ({ kb1 = 1, kb2 = 2 })[kb] end,
  displayForScreen = function() return nil end,
  callerSeat = function() return callerSeat end,
  seatDevices = function(i)
    if i == 1 then return { keyboards = { KB1 } } end
    if i == 2 then return { keyboards = { KB2 } } end
    return nil
  end,
}

local proc = require("kernel.process")
local keyboard = require("compat.keyboard")
local K = keyboard.keys
local function press(kb, ch, code) proc.tick(table.pack("key_down", kb, ch, code, "player")) end
local function release(kb, ch, code) proc.tick(table.pack("key_up", kb, ch, code, "player")) end

print("=== keyboard.isKeyDown ===")
print()
print("-- it answers, and never raises --")
local ok, v = pcall(keyboard.isControlDown)
test("isControlDown does not raise on a machine with a keyboard", ok)
test("...and answers a boolean (false: nothing held)", v == false)
test("isShiftDown / isAltDown answer false too",
  keyboard.isShiftDown() == false and keyboard.isAltDown() == false)

print()
print("-- held keys follow key_down / key_up --")
press(KB1, 0, K.lcontrol)
test("Ctrl held on the machine's only seat reads as held", keyboard.isControlDown() == true)
press(KB1, 97, K.a)
test("a scancode reads as held", keyboard.isKeyDown(K.a) == true)
test("...and so does its character", keyboard.isKeyDown("a") == true)
release(KB1, 97, K.a)
test("released, it is not", keyboard.isKeyDown(K.a) == false and keyboard.isKeyDown("a") == false)
test("a key never pressed is not held", keyboard.isKeyDown(K.z) == false)
test("junk arguments answer false", keyboard.isKeyDown(nil) == false
  and keyboard.isKeyDown({}) == false and keyboard.isKeyDown("") == false)

print()
print("-- each seat sees its own keyboard --")
callerSeat = 1
test("seat 1 sees its own Ctrl", keyboard.isControlDown() == true)
callerSeat = 2
test("seat 2 does NOT see seat 1's Ctrl", keyboard.isControlDown() == false)
press(KB2, 0, K.lshift)
test("seat 2 sees its own Shift", keyboard.isShiftDown() == true)
callerSeat = 1
test("...and seat 1 does not", keyboard.isShiftDown() == false)
callerSeat = 7
test("a seat that cannot be resolved holds nothing (never the whole machine)",
  keyboard.isControlDown() == false and keyboard.isShiftDown() == false)
callerSeat = nil
release(KB1, 0, K.lcontrol)
release(KB2, 0, K.lshift)
test("releases clear both", keyboard.isControlDown() == false and keyboard.isShiftDown() == false)

print()
print("-- a lost key_up does not wedge a key forever --")
press(KB1, 0, K.lcontrol)
clock = clock + proc.KEY_STALE + 1
test("a keyboard idle past KEY_STALE reads as all-released", keyboard.isControlDown() == false)
press(KB1, 99, K.c)
test("...and the next key starts clean (no phantom Ctrl+C)",
  keyboard.isControlDown() == false and keyboard.isKeyDown(K.c) == true)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
