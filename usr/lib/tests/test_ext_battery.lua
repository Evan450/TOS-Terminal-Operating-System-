-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `battery` on a machine with no battery      ║
-- ║                                                                ║
-- ║  kernel.power loads on EVERY machine — the module's whole      ║
-- ║  point is that the rest of the OS doesn't have to know whether ║
-- ║  it is running on a tablet. What it does NOT do is pretend a   ║
-- ║  desktop has a charge level: statusString() returns nil there, ║
-- ║  deliberately, so a status bar has nothing to draw.            ║
-- ║                                                                ║
-- ║  shell/ext.lua handed that nil straight to the output          ║
-- ║  function, which tostring()s whatever it is given — so the     ║
-- ║  answer to `battery` on an ordinary computer was the word      ║
-- ║  "nil". kernel/diag.lua already branched on the nil; only the  ║
-- ║  command didn't.                                               ║
-- ║                                                                ║
-- ║  Pinned here: all three shapes (no module / battery / no       ║
-- ║  battery) produce a non-empty line that is not "nil".          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ext_battery.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_ext_battery.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path

package.loaded["computer"] = { uptime = function() return 0 end,
  energy = function() return 100 end, maxEnergy = function() return 100 end,
  pullSignal = function() end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end }

local X = require("shell.ext")

print("=== `battery` output Tests ===")
print()

-- The output collector the shell would hand the command.
local function run(powerMod)
  local buf = {}
  X.battery({}, {
    K = { getPower = function() return powerMod end },
    o = function(text, color) buf[#buf + 1] = text end,
  })
  return buf
end

-- ── The real kernel.power, on a machine that is not a tablet ───────
-- Loaded unconfigured, exactly as a desktop boot leaves it: isTablet
-- is false, so statusString() answers nil.
local power = require("kernel.power")
power.init({ log = nil, config = nil })
test("the real power module reports no battery string on a computer",
  power.statusString() == nil)

do
  local buf = run(power)
  eq("one line of output", 1, #buf)
  test("it is a string", type(buf[1]) == "string")
  test("it is not the word 'nil' (" .. tostring(buf[1]) .. ")",
    tostring(buf[1]):lower() ~= "nil")
  test("...and not empty", tostring(buf[1]) ~= "")
  test("it says the machine runs on AC",
    tostring(buf[1]):upper():find("AC", 1, true) ~= nil)
end

-- ── A machine that DOES have a battery ─────────────────────────────
do
  local buf = run({ statusString = function() return "▓62%" end })
  eq("one line of output", 1, #buf)
  eq("the battery reading is passed through verbatim", "▓62%", buf[1])
end

-- ── No power module at all (RAM gate skipped it) ───────────────────
do
  local buf = run(nil)
  eq("one line of output", 1, #buf)
  eq("reported as unavailable", "N/A", buf[1])
end

-- ── The contract this depends on ───────────────────────────────────
-- If statusString ever starts answering on computers, the branch above
-- becomes dead rather than wrong — but the nil is the documented
-- behaviour, so pin it.
eq("power.level() still reports full on a computer", 100, power.level())
test("power.isActive() is false off a tablet", power.isActive() == false)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
