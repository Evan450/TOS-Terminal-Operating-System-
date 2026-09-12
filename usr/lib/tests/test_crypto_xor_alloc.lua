-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the XOR fallback costs about what it carries  ║
-- ║                                                                ║
-- ║  A machine without a data card encrypts with crypto's XOR       ║
-- ║  fallback, and xorCipher built one string.char per byte, each   ║
-- ║  in its own table slot: ~16x the payload in heap for every      ║
-- ║  packet, on exactly the machines with the least RAM (Sep 2026   ║
-- ║  pentest, RAM pass). It now works 256 bytes at a time.          ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.crypto with no card, so the fallback is ║
-- ║  the path taken, and checks round-trips at the block edges.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_crypto_xor_alloc.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 1 end, freeMemory = function() return 500000 end,
  totalMemory = function() return 1000000 end, address = function() return "pc" end,
  energy = function() return 1 end, maxEnergy = function() return 1 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.log"] = { warn = function() end, info = function() end }

local crypto = require("kernel.crypto")
crypto.init()

print("=== XOR fallback: allocation and round-trips ===")
print()
test("no data card, so the fallback is the path under test", not crypto.hasHardware())

local SECRET = "0123456789abcdef0123456789abcdef"
local payload = string.rep("P", 8000)
crypto.encrypt("warm", SECRET)            -- first call logs once; keep it out of the count
collectgarbage(); collectgarbage(); collectgarbage("stop")
local before = collectgarbage("count")
local ct, method = crypto.encrypt(payload, SECRET)
local kb = collectgarbage("count") - before
collectgarbage("restart")
test("an 8 KB payload is encrypted with XOR", method == "xor" and #ct == #payload)
-- The floor for chunk-and-join is ~4x (the chunks, the join's growing
-- buffer, the result); the per-byte version was ~17x.
test(string.format("...allocating under 6x its size (%.1f KB for %d bytes; it was ~17x)", kb, #payload),
  kb * 1024 < 6 * #payload)

local seed = 99
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
local bad = 0
for _, len in ipairs({ 0, 1, 255, 256, 257, 511, 512, 513, 8000 }) do
  local chars = {}
  for i = 1, len do chars[i] = string.char(rnd(256)) end
  local pt = table.concat(chars)
  local c, m = crypto.encrypt(pt, SECRET)
  if crypto.decrypt(c, SECRET, m) ~= pt then bad = bad + 1; print("    round-trip failed at " .. len) end
end
test("random data round-trips at every block edge", bad == 0)
test("a different key does not decrypt it",
  crypto.decrypt(ct, "a-different-secret-0123456789abc", "xor") ~= payload)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
