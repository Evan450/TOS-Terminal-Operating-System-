-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Vault Crypto Hardening (CR-7)      ║
-- ║  - V2 split enc/mac subkeys roundtrip                 ║
-- ║  - requireStrong fails closed on software-only box    ║
-- ║  - MAC tamper detection                               ║
-- ║  - V1 (legacy single-key) blobs still decrypt         ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_vault_crypto.lua

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
-- No data card => software/XOR path (the degraded case CR-7 targets).
package.loaded["component"] = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
}
local _t = 0
package.loaded["computer"] = {
  uptime      = function() _t = _t + 0.013; return _t end,
  freeMemory  = function() return 123456 end,
  totalMemory = function() return 999999 end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_vault_crypto.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local crypto = loadMod("crypto.lua")
if crypto then package.loaded["kernel.crypto"] = crypto end
local vault = loadMod("vault.lua")
if not crypto or not vault then
  print("FAIL: could not load crypto.lua / vault.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
crypto.init()

print("=== Vault Crypto Hardening Tests ===")
print()

test("software-only (no data card)", false, crypto.hasHardware())

-- V2 roundtrip (no requireStrong: software path allowed).
local secret = "the quick brown fox jumps over the lazy dog"
local blob, info = vault.encrypt(secret, "passphrase-123")
test("encrypt returns a blob", true, type(blob) == "string" and #blob > 0)
test("blob is V2 magic", true, blob and blob:sub(1, 8) == vault.MAGIC_V2)
test("isEncrypted recognizes blob", true, vault.isEncrypted(blob))
local dec = vault.decrypt(blob, "passphrase-123")
test("roundtrip decrypts to plaintext", secret, dec)
test("wrong passphrase -> nil", nil, (vault.decrypt(blob, "wrong-pass")))

-- requireStrong must fail closed on a software-only box.
local sBlob, sErr = vault.encrypt(secret, "pp", { requireStrong = true })
test("requireStrong fails closed (no blob)", nil, sBlob)
test("requireStrong gives an error message", true, type(sErr) == "string" and #sErr > 0)

-- Tamper detection: flip a ciphertext byte -> MAC mismatch.
local tampered = blob:sub(1, #blob - 1) ..
  string.char((blob:byte(#blob) ~ 0xFF) & 0xFF)
test("tampered blob -> nil", nil, (vault.decrypt(tampered, "passphrase-123")))

-- ── V1 (legacy single-key) backward compatibility ──────────────────
-- Rebuild a V1 blob exactly like the pre-CR-7 code did (one key for both
-- cipher and MAC) and confirm the new decrypt still opens it.
local function packU16(n) return string.char(n & 0xFF, (n >> 8) & 0xFF) end
local function packU32(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
end
local function padAlgo(s)
  if #s >= 4 then return s:sub(1, 4) end
  return s .. string.rep("\0", 4 - #s)
end
local function deriveKeyV1(passphrase, salt)
  local stretched = crypto.hashPassword(passphrase, salt)
  local hex = stretched:match("^v%d+%$%d+%$(%x+)$") or stretched
  return hex:sub(1, 32)
end
local function buildV1(plaintext, passphrase)
  local saltHex = crypto.salt(16)
  local iv = crypto._makeIv16 and crypto._makeIv16() or string.rep("\0", 16)
  local key = deriveKeyV1(passphrase, saltHex)
  local ct, algo = crypto.encrypt(plaintext, key)
  if algo == "aes" then iv = ct:sub(1, 16); ct = ct:sub(17) end
  local rounds = 0
  local body = padAlgo(algo) .. packU16(rounds) .. saltHex .. iv .. packU32(#ct) .. ct
  local mac = crypto.hmac(key, body)
  return "TVAULT1\0" .. padAlgo(algo) .. packU16(rounds) .. saltHex .. iv ..
    packU32(#ct) .. mac .. ct
end
local v1blob = buildV1(secret, "legacy-pass")
test("V1 blob has V1 magic", true, v1blob:sub(1, 8) == vault.MAGIC_V1)
test("isEncrypted recognizes V1", true, vault.isEncrypted(v1blob))
test("V1 blob decrypts (back-compat)", secret, (vault.decrypt(v1blob, "legacy-pass")))
test("V1 wrong passphrase -> nil", nil, (vault.decrypt(v1blob, "nope")))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
