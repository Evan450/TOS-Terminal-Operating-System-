-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: rc.d Kernel Require Gate (CR-6)    ║
-- ║  Kernel-tier services get a GATED require, not the    ║
-- ║  raw one — dangerous kernel modules are denied.       ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_kernel_require.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_rc_kernel_require.lua"
local base = here:gsub("[^/\\]*$", "")
local rc
for _, p in ipairs({ base .. "../../../tos/kernel/rc.lua", "tos/kernel/rc.lua",
    "TOS-Dev/tos/kernel/rc.lua" }) do
  local chunk = loadfile(p)
  if chunk then rc = chunk(); break end
end
if not rc or not rc._gatedKernelRequire then
  print("FAIL: could not load rc.lua / test hook missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local greq  = rc._gatedKernelRequire
local allow = rc._KERNEL_REQUIRE_ALLOW

-- Returns true if calling greq(name) was DENIED with the CR-6 message.
local function denied(name)
  local ok, err = pcall(greq, name)
  return (not ok) and type(err) == "string" and err:find("denied", 1, true) ~= nil
end

print("=== rc.d Kernel Require Gate Tests ===")
print()

-- Dangerous kernel modules must be denied.
test("require('kernel.process') denied", true, denied("kernel.process"))
test("require('kernel.users') denied",   true, denied("kernel.users"))
test("require('kernel.sandbox') denied", true, denied("kernel.sandbox"))
test("require('kernel.securefs') denied", true, denied("kernel.securefs"))
test("require('os') denied",  true, denied("os"))
test("require('debug') denied", true, denied("debug"))
test("require('package') denied", true, denied("package"))

-- Non-string argument errors (not via the allow path).
test("require(123) errors", true, (not (pcall(greq, 123))))

-- Allowlist contains the modules shipped services actually need...
test("allow includes kernel.event", true, allow["kernel.event"] == true)
test("allow includes computer",     true, allow["computer"] == true)
-- ...and excludes the dangerous ones.
test("allow excludes kernel.process",  nil, allow["kernel.process"])
test("allow excludes kernel.users",    nil, allow["kernel.users"])
test("allow excludes kernel.sandbox",  nil, allow["kernel.sandbox"])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
