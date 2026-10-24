-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: X25519 Diffie-Hellman (RFC 7748)                   ║
-- ║                                                            ║
-- ║  Same discipline as test_ed25519.lua, and for the same      ║
-- ║  reason: a key-agreement scheme that only agrees with       ║
-- ║  itself cannot agree with anyone else's implementation, so   ║
-- ║  the anchors are RFC 7748 Section 5.2's own scalarMult       ║
-- ║  vectors and Section 6.1's Alice/Bob Diffie-Hellman          ║
-- ║  example -- transcribed from the RFC's raw text, cross-      ║
-- ║  checked against its own redundant base-10 restatement of    ║
-- ║  the scalar and u-coordinate, and independently verified      ║
-- ║  against a from-scratch Python port of the RFC's pseudocode   ║
-- ║  before this file was written (2026-10-23). If you change     ║
-- ║  kernel/x25519.lua, this file is the review.                  ║
-- ║                                                            ║
-- ║  The iterated test vector (RFC 7748 Section 5.2) only runs    ║
-- ║  ONE pass: each pass is a full scalar multiplication, and      ║
-- ║  this is schoolbook-slow Lua (see x25519.lua's own COST        ║
-- ║  note) -- 1,000 or 1,000,000 passes would turn this suite      ║
-- ║  into a multi-minute wait for no more assurance than the       ║
-- ║  single-pass check already gives.                              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_x25519.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "\n    expected " .. tostring(expected)
      .. "\n    got      " .. tostring(actual))
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

local here = (arg and arg[0]) or "usr/lib/tests/test_x25519.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

-- x25519.lua requires kernel.curve25519field at load time; this harness
-- never touches package.path, so preload it the same manual way
-- test_ed25519.lua preloads kernel.sha512.
package.loaded["kernel.curve25519field"] = tryload("tos/kernel/curve25519field.lua")()
local x25519 = tryload("tos/kernel/x25519.lua")()

local function hex2bin(h)
  return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end
local function bin2hex(b)
  return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

print("=== X25519 (RFC 7748) Tests ===")
print()

test("KEY_LEN is 32", 32, x25519.KEY_LEN)
test("BASEPOINT is 32 bytes", 32, #x25519.BASEPOINT)
test("BASEPOINT is 9 followed by 31 zero bytes", "09" .. string.rep("00", 31),
  bin2hex(x25519.BASEPOINT))

-- ── Section 5.2: scalarMult test vectors ────────────────────────────
-- Both the scalar and u-coordinate hex below were cross-checked against
-- the RFC's own base-10 restatement of each (the scalar's restated value
-- is after RFC 7748's clamp, the u-coordinate's is the raw decode) before
-- being used here, so a transcription slip could not survive unnoticed.
do
  local k = hex2bin("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4")
  local u = hex2bin("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")
  local out, err = x25519.scalarMult(k, u)
  ok("TV1: scalarMult succeeds (" .. tostring(err) .. ")", out ~= nil)
  test("TV1: matches RFC 7748 Section 5.2's first vector",
    "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
    out and bin2hex(out))
end

do
  local k = hex2bin("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d")
  local u = hex2bin("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493")
  local out = x25519.scalarMult(k, u)
  test("TV2: matches RFC 7748 Section 5.2's second vector",
    "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957",
    out and bin2hex(out))
end

-- ── Section 5.2: the iterated vector, one pass only (see header) ───
do
  local ku = hex2bin("0900000000000000000000000000000000000000000000000000000000000000")
  local out = x25519.scalarMult(ku, ku)
  test("iterated vector, after one pass", "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079",
    out and bin2hex(out))
end

-- ── publicKey: scalarMult against the real base point ──────────────
do
  local priv = hex2bin("0900000000000000000000000000000000000000000000000000000000000000")
  local pub  = x25519.publicKey(priv)
  test("publicKey(priv) == scalarMult(priv, basepoint)",
    "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079",
    pub and bin2hex(pub))
end

-- ── Section 6.1: Alice and Bob, checked both directions ─────────────
do
  local a = hex2bin("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
  local b = hex2bin("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")

  local KA = x25519.publicKey(a)
  local KB = x25519.publicKey(b)
  test("Alice's public key matches RFC 7748 Section 6.1",
    "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", KA and bin2hex(KA))
  test("Bob's public key matches RFC 7748 Section 6.1",
    "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", KB and bin2hex(KB))

  local kAlice, errA = x25519.sharedSecret(a, KB)
  local kBob,   errB = x25519.sharedSecret(b, KA)
  ok("Alice derives a shared secret (" .. tostring(errA) .. ")", kAlice ~= nil)
  ok("Bob derives a shared secret (" .. tostring(errB) .. ")", kBob ~= nil)
  test("Alice's shared secret matches RFC 7748 Section 6.1",
    "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", kAlice and bin2hex(kAlice))
  test("Bob's shared secret matches RFC 7748 Section 6.1",
    "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", kBob and bin2hex(kBob))
  test("...and the two sides agree with each other, not just the RFC",
    kAlice, kBob)
end

-- ── Malformed input is refused, never raises ────────────────────────
do
  local ok1, err1 = x25519.scalarMult("short", x25519.BASEPOINT)
  test("a short scalar is refused, not an error", nil, ok1)
  ok("...with a reason", err1 ~= nil)
  local ok2 = x25519.scalarMult(x25519.BASEPOINT, "short")
  test("a short u-coordinate is refused, not an error", nil, ok2)
end

-- ── The all-zero degenerate output (RFC 7748 Section 6.1) ───────────
-- u = 0 is a known low-order point: RFC 7748 warns that scalarMult on an
-- input of small order collapses to the all-zero output regardless of
-- the scalar, and that a Diffie-Hellman caller MAY check for exactly
-- this. Verified independently in Python against the RFC's own
-- pseudocode before being asserted here.
do
  local zeroU = string.rep("\0", 32)
  local degenerate = x25519.scalarMult(x25519.BASEPOINT, zeroU)
  ok("scalarMult(_, 0) is recognized as all-zero", x25519._isAllZero(degenerate))
  local secret, err = x25519.sharedSecret(x25519.BASEPOINT, zeroU)
  test("sharedSecret refuses a degenerate result, not a fake secret", nil, secret)
  ok("...and explains why", err ~= nil and err:find("degenerate", 1, true) ~= nil)
end

-- ── generatePrivateKey: injected randomness, not a hidden dependency ─
do
  local calledWith
  local priv, err = x25519.generatePrivateKey(function(n) calledWith = n; return string.rep("Q", n) end)
  test("asks the injected source for KEY_LEN bytes", x25519.KEY_LEN, calledWith)
  test("returns exactly what the source gave", string.rep("Q", 32), priv)
  local badPriv, badErr = x25519.generatePrivateKey(function() return "too short" end)
  test("a source that shortchanges it is refused, not papered over", nil, badPriv)
  ok("...with a reason", badErr ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
