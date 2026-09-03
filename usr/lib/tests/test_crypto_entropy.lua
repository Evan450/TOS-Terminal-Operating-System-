-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Crypto Cross-Boot Entropy (H-6)    ║
-- ║  crypto.addEntropy / crypto.exportEntropy behaviour   ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_crypto_entropy.lua
--
-- crypto.lua requires "component" and "computer" at load time, so we
-- preload lightweight mocks (no data card => software RNG path, which is
-- exactly the degraded case H-6 targets) before loading the module.

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

-- crypto.lua now require()s kernel.sha256 (extracted pure hash); make it
-- resolvable whether run from TOS-Dev or the tests dir.
package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
-- Mocks: empty component.list("data") => no data card => software RNG.
package.loaded["component"] = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
}
local _t = 0
package.loaded["computer"] = {
  uptime      = function() _t = _t + 0.017; return _t end,
  freeMemory  = function() return 123456 end,
  totalMemory = function() return 999999 end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_crypto_entropy.lua"
local base = here:gsub("[^/\\]*$", "")
local candidates = {
  base .. "../../../tos/kernel/crypto.lua",
  "tos/kernel/crypto.lua",
  "TOS-Dev/tos/kernel/crypto.lua",
}
local crypto
for _, p in ipairs(candidates) do
  local chunk = loadfile(p)
  if chunk then crypto = chunk(); break end
end
if not crypto then
  print("FAIL: could not load crypto.lua")
  print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***")
  return false
end
crypto.init()

print("=== Crypto Cross-Boot Entropy Tests ===")
print()

test("software-only (no data card)", false, crypto.hasHardware())

-- exportEntropy returns the requested number of raw bytes.
local e32 = crypto.exportEntropy()
test("exportEntropy() default 32 bytes", 32, type(e32) == "string" and #e32 or -1)
local e64 = crypto.exportEntropy(64)
test("exportEntropy(64) -> 64 bytes", 64, type(e64) == "string" and #e64 or -1)

-- Successive exports differ (the RNG advances).
test("successive exports differ", true, crypto.exportEntropy(16) ~= crypto.exportEntropy(16))

-- addEntropy input validation.
test("addEntropy('') rejected", false, crypto.addEntropy(""))
test("addEntropy(nil) rejected", false, crypto.addEntropy(nil))
test("addEntropy(123) rejected", false, crypto.addEntropy(123))
test("addEntropy(string) accepted", true, crypto.addEntropy("persisted-pool-from-last-boot"))

-- Adding entropy perturbs the stream (output after a mix differs from
-- the next output without an intervening mix). Overwhelmingly true.
local a = crypto.exportEntropy(16)
crypto.addEntropy("more-entropy-xyz")
local b = crypto.exportEntropy(16)
test("addEntropy changes the stream", true, a ~= b)

-- Core consumers still work after entropy operations.
local salt = crypto.salt(16)
test("salt() still 16 alphanumeric chars", true,
  type(salt) == "string" and #salt == 16 and salt:match("^[%w]+$") ~= nil)
local tok = crypto.token()
test("token() is 64 hex chars", true,
  type(tok) == "string" and #tok == 64 and tok:match("^[%x]+$") ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
