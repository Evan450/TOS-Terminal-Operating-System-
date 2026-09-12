-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: hardware AES actually engages                 ║
-- ║                                                                ║
-- ║  OpenComputers' Tier 2 data card is AES-128: Ocelot's            ║
-- ║  DataCard$Tier2 throws "expected a 128-bit AES key" for any key ║
-- ║  that is not 16 bytes, and the same for the IV. TOS handed it   ║
-- ║  the raw 32-character peer secret, so every encrypt raised,     ║
-- ║  the pcall hid it, and every "aes" packet went out as XOR --    ║
-- ║  which a carded receiver refuses as a downgrade (Sep 2026       ║
-- ║  pentest). The fake card below enforces OC's two length checks  ║
-- ║  and nothing else, so it tells the truth about the seam.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_crypto_aes_key.lua   (from TOS-Dev)

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
local sha256hex = require("kernel.sha256").hex
local function rawHex(h) return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end)) end
local function xorWith(data, k)
  local out = {}
  for i = 1, #data do
    out[i] = string.char(data:byte(i) ~ k:byte(((i - 1) % #k) + 1))
  end
  return table.concat(out)
end

local seenKeyLen = nil
local card = {
  encrypt = function(data, key, iv)
    if type(key) ~= "string" or #key ~= 16 then error("expected a 128-bit AES key") end
    if type(iv) ~= "string" or #iv ~= 16 then error("expected a 128-bit AES IV") end
    seenKeyLen = #key
    return xorWith(data, key .. iv)
  end,
  decrypt = function(data, key, iv)
    if type(key) ~= "string" or #key ~= 16 then error("expected a 128-bit AES key") end
    if type(iv) ~= "string" or #iv ~= 16 then error("expected a 128-bit AES IV") end
    return xorWith(data, key .. iv)
  end,
  sha256 = function(d) return rawHex(sha256hex(d)) end,
  -- Varying bytes: a constant card RNG makes every salt() identical.
  random = (function()
    local ctr = 0
    return function(n)
      local out = {}
      for i = 1, n do ctr = (ctr * 73 + 41) % 256; out[i] = string.char(ctr) end
      return table.concat(out)
    end
  end)(),
}
package.loaded["component"] = {
  list  = function(kind) local done = false
    return function() if kind == "data" and not done then done = true; return "card1", "data" end end end,
  proxy = function() return card end,
}

local crypto = require("kernel.crypto")
crypto.init()

print("=== hardware AES engages with a real peer secret ===")
print()
local SECRET = crypto.salt(32)          -- what trust.generateSecret mints
test("the peer secret is 32 characters, as trust mints it", #SECRET == 32)
local ct, method = crypto.encrypt("attack at dawn", SECRET)
test("encrypt uses AES, not the XOR fallback (got " .. tostring(method) .. ")", method == "aes")
test("the card was handed a 16-byte key", seenKeyLen == 16)
test("the same secret decrypts it", crypto.decrypt(ct, SECRET, "aes") == "attack at dawn")
test("a different secret does not",
  crypto.decrypt(ct, "a-different-secret-0123456789abc", "aes") ~= "attack at dawn")
local hexSecret = sha256hex("a pairing code")     -- chatpair-style 64-char secret
local ct2, m2 = crypto.encrypt("hello", hexSecret)
test("a 64-character secret engages AES too", m2 == "aes" and crypto.decrypt(ct2, hexSecret, "aes") == "hello")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
