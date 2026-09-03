-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: KDF runs in software (#PERF)        ║
-- ║  - iterated password KDF/HMAC never calls the data    ║
-- ║    card (the ~150s-boot regression), only one-shot     ║
-- ║    crypto.hash does                                    ║
-- ║  - software SHA-256 / HMAC known-answer vectors        ║
-- ║  - v3 is the universal write format at PW_ROUNDS=256   ║
-- ║  - legacy formats still verify + flag rehash           ║
-- ║  - high-round v3 records migrate DOWN (rehash)         ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_kdf_software.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_kdf_software.lua"
local base = here:gsub("[^/\\]*$", "")
-- crypto.lua now require()s kernel.sha256 (extracted pure hash); make it
-- resolvable whether run from TOS-Dev or the tests dir.
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local function loadCrypto()
  for _, p in ipairs({ base .. "../../../tos/kernel/crypto.lua",
      "tos/kernel/crypto.lua", "TOS-Dev/tos/kernel/crypto.lua" }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- Helper: (re)load a fresh crypto module against a chosen component stub so
-- each mode starts clean (the module caches dataCard at init()).
local function freshCrypto(componentStub)
  package.loaded["component"] = componentStub
  local _t = 0
  package.loaded["computer"] = {
    uptime      = function() _t = _t + 0.013; return _t end,
    freeMemory  = function() return 123456 end,
    totalMemory = function() return 999999 end,
  }
  package.loaded["kernel.crypto"] = nil
  local chunk = loadCrypto()
  if not chunk then return nil end
  local crypto = chunk()
  crypto.init()
  return crypto
end

print("=== KDF Software-Path Tests ===")
print()

-- ── Software-only mode ──────────────────────────────────────────────
local sw = freshCrypto({
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
})
if not sw then
  print("FAIL: could not load crypto.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

test("software-only: hasHardware false", false, sw.hasHardware())

-- Known-answer: SHA-256("abc") and HMAC-SHA256(RFC 4231 case 2).
test("SHA-256(\"abc\") vector",
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  sw.hash("abc"))
test("HMAC-SHA256 RFC4231 case2 vector",
  "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  sw.hmac("Jefe", "what do ya want for nothing?"))

-- Universal v3 write format at 256 rounds.
local salt = "0123456789abcdef"
local stored = sw.hashPassword("hunter2", salt)
test("hashPassword emits v3$256$<64hex>", true,
  type(stored) == "string" and stored:match("^v3%$256%$%x+$") ~= nil
  and #(stored:match("^v3%$256%$(%x+)$") or "") == 64)

-- Round-trip: correct password verifies, fresh record needs no rehash.
local ok, rehash = sw.verifyPassword("hunter2", salt, stored)
test("verify correct password", true, ok)
test("fresh v3$256 needs no rehash", false, rehash)
test("verify wrong password fails", false, (sw.verifyPassword("nope", salt, stored)))

-- High-round v3 record (the legacy "hardware-accelerated" form) must still
-- verify AND be flagged for rehash so it migrates DOWN to 256. Reconstruct
-- pwInnerV3 via the public HMAC (use 1000 rounds to keep the test quick).
local function pwInnerV3(password, s, rounds)
  local key = s .. "\0tos.v3"
  local h = sw.hmac(key, password .. "\0" .. s)
  for i = 2, rounds do
    h = sw.hmac(key, h .. "\0" .. string.char(i & 0xFF, (i >> 8) & 0xFF))
  end
  return h
end
local hi = "v3$1000$" .. pwInnerV3("hunter2", salt, 1000)
local okH, rehashH = sw.verifyPassword("hunter2", salt, hi)
test("high-round v3 verifies", true, okH)
test("high-round v3 flagged for rehash (migrate down)", true, rehashH)

-- Legacy bare-hex (software-only stretched) record verifies + rehashes.
-- In software mode crypto.hash == sha256_hex, so we can reproduce it.
local function sw256(password, s, rounds)
  local h = sw.hash(s .. password .. "tos")
  for _ = 2, rounds do h = sw.hash(h .. s) end
  return h
end
local bare = sw256("hunter2", salt, 256)
local okB, rehashB = sw.verifyPassword("hunter2", salt, bare)
test("legacy bare-hex verifies", true, okB)
test("legacy bare-hex flagged for rehash", true, rehashB)

-- ── Data-card mode: the KDF must make ZERO card calls ───────────────
local shaCalls, randCalls = 0, 0
local fakeCard = {
  sha256 = function(_) shaCalls = shaCalls + 1; return string.rep("\0", 32) end,
  random = function(n) randCalls = randCalls + 1; return string.rep("\1", n or 1) end,
}
local hw = freshCrypto({
  list  = function()
    local done = false
    return function() if done then return nil end done = true; return "datacard-addr" end
  end,
  proxy = function() return fakeCard end,
})
test("data-card: hasHardware true", true, hw.hasHardware())

-- The regression: hashing a password / verifying must not touch the card's
-- sha256 (that was the ~20k-component-call, ~150s stall). The iterated KDF
-- runs entirely in software.
shaCalls = 0
local hwStored = hw.hashPassword("hunter2", salt)
test("hashPassword makes 0 data-card sha256 calls", 0, shaCalls)
shaCalls = 0
hw.verifyPassword("hunter2", salt, hwStored)
test("verifyPassword makes 0 data-card sha256 calls", 0, shaCalls)
shaCalls = 0
hw.sign("payload", "secret")           -- network MAC path
test("network MAC (sign) makes 0 data-card sha256 calls", 0, shaCalls)

-- Sanity: one-shot crypto.hash DOES still use the card (where it's cheap).
shaCalls = 0
hw.hash("bulk data")
test("one-shot crypto.hash still uses the card", true, shaCalls > 0)

print()
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed == 0 then print("*** ALL TESTS PASSED ***"); return true
else print("*** TESTS FAILED ***"); return false end
