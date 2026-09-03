-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: SHA-512 and Ed25519 (RFC 8032)                     ║
-- ║                                                            ║
-- ║  These are INTEROP tests, not self-consistency tests, and   ║
-- ║  the distinction is the whole point. A signature scheme     ║
-- ║  that only agrees with itself is a scheme nobody else can   ║
-- ║  verify — which would defeat the reason for using a         ║
-- ║  published standard at all. So the anchors are the          ║
-- ║  official vectors: FIPS 180-4 for SHA-512, RFC 8032 §7.1    ║
-- ║  for Ed25519. If you change kernel/ed25519.lua, this file   ║
-- ║  is the review.                                             ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ed25519.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_ed25519.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

local sha512 = tryload("tos/kernel/sha512.lua")()
package.loaded["kernel.sha512"] = sha512
-- kernel.process is deliberately absent: ed25519 must load and run
-- without it (early boot, and the off-box signer under plain Lua), with
-- the cooperative yield degrading to a no-op.
local ed = tryload("tos/kernel/ed25519.lua")()

local function hex2bin(h)
  return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end
local function bin2hex(b)
  return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

print("=== SHA-512 / Ed25519 Tests ===")
print()

-- ══════════════════════════════════════════════════════════════════════
-- SHA-512 — FIPS 180-4 vectors
-- ══════════════════════════════════════════════════════════════════════
do
  test("SHA-512 of empty string",
    "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
    .. "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
    sha512.hex(""))
  test("SHA-512 of 'abc'",
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
    .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    sha512.hex("abc"))
  -- 56 bytes: the padding boundary case — one byte more and the length
  -- field no longer fits in the same block.
  test("SHA-512 at the one-block padding boundary",
    "204a8fc6dda82f0a0ced7beb8e08a41657c16ef468b228a8279be331a703c335"
    .. "96fd15c13b1b07f9aa1d3bea57789ca031ad85c7a71dd70354ec631238ca3445",
    sha512.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
  -- 112 bytes: two blocks.
  test("SHA-512 across two blocks",
    "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018"
    .. "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909",
    sha512.hex("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
      .. "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"))
  -- The long FIPS vector. It is here because it is the one that catches
  -- a length-encoding bug (8,000,000 bits does not fit in 32) and,
  -- separately, because the naive `msg:byte(1, #msg)` this file's
  -- sibling sha256.lua uses would stack-overflow on it.
  test("SHA-512 of one million 'a'",
    "e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973eb"
    .. "de0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b",
    sha512.hex(string.rep("a", 1000000)))
  test("raw() returns 64 bytes", 64, #sha512.raw("abc"))
end

-- ══════════════════════════════════════════════════════════════════════
-- Ed25519 — RFC 8032 §7.1 vectors
-- ══════════════════════════════════════════════════════════════════════
local VECTORS = {
  { name = "TEST 1 (empty message)",
    sk  = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
    pk  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    msg = "",
    sig = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e0652249015"
       .. "55fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b" },
  { name = "TEST 2 (one byte)",
    sk  = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
    pk  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
    msg = "72",
    sig = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69d"
       .. "a085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00" },
  { name = "TEST 3 (two bytes)",
    sk  = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
    pk  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
    msg = "af82",
    sig = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3a"
       .. "c18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a" },
  { name = "TEST SHA(abc) (64-byte message)",
    sk  = "833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42",
    pk  = "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf",
    msg = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
       .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    sig = "dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b58"
       .. "909351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704" },
}

for _, v in ipairs(VECTORS) do
  local sk, pk = hex2bin(v.sk), hex2bin(v.pk)
  local msg, sig = hex2bin(v.msg), hex2bin(v.sig)
  test(v.name .. ": public key derives", v.pk, bin2hex(ed.publickey(sk)))
  -- Ed25519 signatures are DETERMINISTIC: the same key over the same
  -- message must produce the same 64 bytes every time, on every
  -- implementation. That is why the RFC can publish them at all, and
  -- checking it is what proves the nonce derivation matches.
  test(v.name .. ": signature matches byte for byte", v.sig, bin2hex(ed.sign(msg, sk, pk)))
  ok(v.name .. ": verifies", (ed.verify(msg, sig, pk)))
end

-- ══════════════════════════════════════════════════════════════════════
-- The refusals — what a forgery actually looks like
-- ══════════════════════════════════════════════════════════════════════
local v = VECTORS[3]
local sk, pk = hex2bin(v.sk), hex2bin(v.pk)
local msg, sig = hex2bin(v.msg), hex2bin(v.sig)

do
  ok("a changed message does not verify", not (ed.verify(msg .. "\0", sig, pk)))
  ok("a truncated message does not verify", not (ed.verify(msg:sub(1, 1), sig, pk)))
end

do
  -- Flip one bit in each half of the signature. R and S fail for
  -- different reasons and both have to fail.
  local flipR = string.char(sig:byte(1) ~ 1) .. sig:sub(2)
  local flipS = sig:sub(1, 40) .. string.char(sig:byte(41) ~ 1) .. sig:sub(42)
  ok("a flipped bit in R does not verify", not (ed.verify(msg, flipR, pk)))
  ok("a flipped bit in S does not verify", not (ed.verify(msg, flipS, pk)))
end

do
  -- Right signature, wrong signer. This is the property the whole
  -- feature exists for: the hash proves the disk is not corrupt, the
  -- signature proves who wrote it.
  local otherPk = hex2bin(VECTORS[2].pk)
  ok("another publisher's key does not verify", not (ed.verify(msg, sig, otherPk)))
end

do
  -- S must be canonical (already reduced mod L). An unreduced S would
  -- let anyone turn one valid signature into many distinct ones over the
  -- same message — malleability, and the RFC forbids it. An S of all
  -- 0xFF is trivially larger than L.
  local bigS = sig:sub(1, 32) .. string.rep("\255", 32)
  local accepted, why = ed.verify(msg, bigS, pk)
  ok("an unreduced S is refused", not accepted)
  ok("and the reason names S", tostring(why):find("S") ~= nil)
end

do
  -- Malformed input is an ordinary "no", never a crash: a signature is
  -- attacker-controlled, and an installer that throws on a bad one is a
  -- denial of service at best.
  ok("a short signature is refused", not (ed.verify(msg, "short", pk)))
  ok("a short key is refused", not (ed.verify(msg, sig, "short")))
  ok("a nil signature is refused", not (ed.verify(msg, nil, pk)))
  ok("a nil key is refused", not (ed.verify(msg, sig, nil)))
  ok("32 random bytes are not a signature", not (ed.verify(msg, string.rep("\7", 64), pk)))
  -- A key that is not a curve point at all.
  ok("a non-point public key is refused", not (ed.verify(msg, sig, string.rep("\255", 32))))
end

do
  -- Key generation refuses a wrong-sized seed rather than padding it.
  local k, err = ed.publickey("too short")
  test("publickey refuses a short seed", nil, k)
  ok("and says how long it wanted", tostring(err):find("32 bytes") ~= nil)
end

-- ══════════════════════════════════════════════════════════════════════
-- Round trip on data the size of a real manifest
-- ══════════════════════════════════════════════════════════════════════
do
  -- The official vectors are all short. A manifest is a few kilobytes,
  -- which crosses SHA-512 block boundaries inside the signing path.
  local body = string.rep("return { name = \"demo\", files = {} }\n", 100)
  local sig2 = ed.sign(body, sk, pk)
  test("signature is 64 bytes", 64, #sig2)
  ok("a manifest-sized message round-trips", (ed.verify(body, sig2, pk)))
  ok("...and one byte of tampering breaks it",
    not (ed.verify(body .. " ", sig2, pk)))
end

do
  -- The base point survives a decode/encode round trip. This exercises
  -- the square-root branch of point decompression, the modular
  -- inversion, and the canonical byte encoding all at once — and its
  -- expected value is published, so it is a real check rather than a
  -- restatement of the code.
  test("base point re-encodes to its published bytes",
    "5866666666666666666666666666666666666666666666666666666666666666",
    bin2hex(ed._internal.ptEncode(ed._internal.B)))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
