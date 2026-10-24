-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Ed25519 (RFC 8032), pure Lua 5.3               ║
-- ║                                                              ║
-- ║  Signature verification for package manifests. See           ║
-- ║  kernel/pkgsign.lua for what TOS actually does with it; this ║
-- ║  file is only the mathematics.                               ║
-- ║                                                              ║
-- ║  WHY WE DID NOT INVENT A SCHEME. RFC 8032 is the spec, and   ║
-- ║  the point of using it is that a manifest signed by any      ║
-- ║  other Ed25519 implementation verifies here and vice versa.  ║
-- ║  That property is only worth anything if this file is        ║
-- ║  RIGHT, so the module is pinned to the RFC's own test        ║
-- ║  vectors (usr/lib/tests/test_ed25519.lua). If you change a   ║
-- ║  line here, those vectors are the review.                    ║
-- ║                                                              ║
-- ║  WHY THE DATA CARD DOES NOT HELP. A T3 data card offers ECC  ║
-- ║  (generateKeyPair / ecdsa), but that is a DIFFERENT curve    ║
-- ║  and a different signature format — a manifest signed with   ║
-- ║  it could only ever be verified on another T3 box, which is  ║
-- ║  the opposite of what a publisher signature is for. The card ║
-- ║  cannot accelerate this either: it hashes SHA-256 and MD5    ║
-- ║  and Ed25519 needs SHA-512. So this is software, everywhere. ║
-- ║                                                              ║
-- ║  COST, because it is real and nobody should be surprised by  ║
-- ║  it: one verification is on the order of ten thousand field  ║
-- ║  multiplications. Measured off-box in the test file; on a    ║
-- ║  real OC machine expect SECONDS, not milliseconds. Hence:    ║
-- ║    * this module is LAZILY loaded — never at boot, only when ║
-- ║      a signature is actually present to check;               ║
-- ║    * verify() yields cooperatively so a slow verification    ║
-- ║      slows the SEAT and never trips OC's 5-second watchdog;  ║
-- ║    * callers cache the verdict rather than re-checking.      ║
-- ║                                                              ║
-- ║  NOT CONSTANT TIME, said plainly. Verification handles only  ║
-- ║  public data, so it does not need to be. Signing does touch  ║
-- ║  a secret scalar, and a determined attacker with a stopwatch ║
-- ║  inside the same Minecraft world is not a threat model this  ║
-- ║  pretends to cover — the adversary here is a floppy disk     ║
-- ║  claiming to be from someone it is not.                      ║
-- ║                                                              ║
-- ║  Pure: no component/computer/fs require, so the off-box      ║
-- ║  signer can load it under plain Lua 5.3.                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local sha512 = require("kernel.sha512")
local field  = require("kernel.curve25519field")

local ed25519 = {}

-- The field arithmetic (bignum + GF(2^255-19)) is shared with X25519
-- (kernel/curve25519field.lua) -- extracted out of this file with no
-- logic changes; everything below this point is unchanged from before
-- the extraction. Only what the Edwards-curve code below actually calls
-- is pulled in by name.
local yieldCoop     = field.yieldCoop
local bnZero        = field.bnZero
local bnFromInt     = field.bnFromInt
local bnCmp         = field.bnCmp
local bnAdd         = field.bnAdd
local bnSub         = field.bnSub
local bnShl         = field.bnShl
local bnMul         = field.bnMul
local bnBitLen      = field.bnBitLen
local bnBit         = field.bnBit
local bnMod         = field.bnMod
local bnFromBytesLE = field.bnFromBytesLE
local bnToBytesLE   = field.bnToBytesLE
local bnToBitsMSB   = field.bnToBitsMSB
local feNew         = field.feNew
local feCopy        = field.feCopy
local feAdd         = field.feAdd
local feSub         = field.feSub
local feNeg         = field.feNeg
local feMul         = field.feMul
local feSq          = field.feSq
local fePow         = field.fePow
local feFromBytes   = field.feFromBytes
local feToBytes     = field.feToBytes
local feIsZero      = field.feIsZero
local feEq          = field.feEq
local feIsNegative  = field.feIsNegative
local feInvert      = field.feInvert
local FE_ZERO       = field.FE_ZERO
local FE_ONE        = field.FE_ONE
local P_BN          = field.P_BN

-- ── Curve constants ──────────────────────────────────────────
-- Computed at load rather than transcribed. A 78-digit decimal constant
-- copied by hand is a class of bug this avoids entirely, and the cost is
-- roughly a tenth of one verification — paid once, and only when the
-- module is loaded at all, which is only when there is a signature.
local D, D2, SQRTM1

do
  local a = feNew(); a[1] = 121665
  local b = feNew(); b[1] = 121666
  D  = feMul(feNeg(a), feInvert(b))       -- d = -121665/121666
  D2 = feAdd(D, D)
  -- sqrt(-1) = 2^((p-1)/4). The exponent is built by dropping the two
  -- low bits rather than dividing — p-1 is divisible by 4, so there is
  -- no rounding question to get wrong.
  local pm1 = bnSub(P_BN, bnFromInt(1))
  local pm1_4 = bnZero()
  for i = bnBitLen(pm1) - 1, 2, -1 do
    pm1_4 = bnAdd(bnShl(pm1_4, 1), bnFromInt(bnBit(pm1, i)))
  end
  local two = feNew(); two[1] = 2
  SQRTM1 = fePow(two, bnToBitsMSB(pm1_4))
end

-- The group order L = 2^252 + 27742317777372353535851937790883648493,
-- little-endian, straight from RFC 8032.
local L_BN = bnFromBytesLE(string.char(
  0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
  0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10))

-- ============================================================
-- Points, in extended homogeneous coordinates (X:Y:Z:T)
-- ============================================================
-- x = X/Z, y = Y/Z, xy = T/Z. RFC 8032 §5.1.4.
--
-- ONE addition formula is used for both addition and doubling. It is
-- "unified" — correct for P+Q and for P+P — which costs a little speed
-- on the doublings and removes a whole second routine that could be
-- wrong only in the cases the vectors happen not to exercise.

local function ptIdentity()
  return { X = feCopy(FE_ZERO), Y = feCopy(FE_ONE),
           Z = feCopy(FE_ONE),  T = feCopy(FE_ZERO) }
end

local function ptAdd(p1, p2)
  local A = feMul(feSub(p1.Y, p1.X), feSub(p2.Y, p2.X))
  local B = feMul(feAdd(p1.Y, p1.X), feAdd(p2.Y, p2.X))
  local C = feMul(feMul(p1.T, D2), p2.T)
  local Dv = feMul(feAdd(p1.Z, p1.Z), p2.Z)
  local E = feSub(B, A)
  local F = feSub(Dv, C)
  local G = feAdd(Dv, C)
  local H = feAdd(B, A)
  return { X = feMul(E, F), Y = feMul(G, H), T = feMul(E, H), Z = feMul(F, G) }
end

--- [n]P for an MSB-first bit array. Plain double-and-add: no windowing,
--- no constant-time selection. Verification handles public data only;
--- see the header on why that is the honest posture here.
local function ptMul(bits, p)
  local q = ptIdentity()
  for i = 1, #bits do
    q = ptAdd(q, q)
    if bits[i] == 1 then q = ptAdd(q, p) end
    if (i % 16) == 0 then yieldCoop() end
  end
  return q
end

local function ptEncode(p)
  local zInv = feInvert(p.Z)
  local x = feMul(p.X, zInv)
  local y = feMul(p.Y, zInv)
  local s = feToBytes(y)
  local last = s:byte(32)
  if feIsNegative(x) then last = last | 0x80 end
  return s:sub(1, 31) .. string.char(last)
end

--- 32 bytes → point, or nil when the encoding is not a curve point.
-- A rejected point is a rejected SIGNATURE, never an error: a malformed
-- 32 bytes is exactly what a forged signature looks like.
local function ptDecode(s)
  if #s ~= 32 then return nil end
  local sign = (s:byte(32) >> 7) & 1
  local y = feFromBytes(s)

  -- A y that is not canonical (>= p) is refused rather than silently
  -- reduced: two distinct encodings verifying the same signature is
  -- malleability, and the RFC's own check list forbids it.
  do
    local yb = bnFromBytesLE(s:sub(1, 31) .. string.char(s:byte(32) & 0x7F))
    if bnCmp(yb, P_BN) >= 0 then return nil end
  end

  local y2 = feSq(y)
  local u  = feSub(y2, FE_ONE)              -- y^2 - 1
  local v  = feAdd(feMul(D, y2), FE_ONE)    -- d*y^2 + 1

  -- x = (u/v)^((p+3)/8), via u*v^3 * (u*v^7)^((p-5)/8)
  local v3 = feMul(feSq(v), v)
  local v7 = feMul(feSq(v3), v)
  local pm5_8 = bnZero()
  do
    local pm5 = bnSub(P_BN, bnFromInt(5))
    for i = bnBitLen(pm5) - 1, 3, -1 do
      pm5_8 = bnAdd(bnShl(pm5_8, 1), bnFromInt(bnBit(pm5, i)))
    end
  end
  local x = feMul(feMul(u, v3), fePow(feMul(u, v7), bnToBitsMSB(pm5_8)))

  local vx2 = feMul(v, feSq(x))
  if not feEq(vx2, u) then
    if feEq(vx2, feNeg(u)) then
      x = feMul(x, SQRTM1)
    else
      return nil                            -- not a square: no such point
    end
  end
  if feIsZero(x) and sign == 1 then return nil end
  if (feIsNegative(x) and 1 or 0) ~= sign then x = feNeg(x) end

  return { X = x, Y = y, Z = feCopy(FE_ONE), T = feMul(x, y) }
end

-- Base point, decoded from its canonical encoding rather than written
-- out as coordinates — one fewer transcribed constant, and it exercises
-- ptDecode on a value whose answer we know.
local B_POINT = ptDecode(string.char(
  0x58, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
  0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
  0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
  0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66))

-- ============================================================
-- The scheme
-- ============================================================

--- Clamp a 32-byte hash half into an Ed25519 secret scalar (RFC 8032
--- §5.1.5 step 2): clear the low 3 bits, clear the top bit, set bit 254.
local function clamp(b)
  local t = { b:byte(1, 32) }
  t[1]  = t[1] & 0xF8
  t[32] = (t[32] & 0x7F) | 0x40
  local out = {}
  for i = 1, 32 do out[i] = string.char(t[i]) end
  return table.concat(out)
end

--- Public key (32 bytes) for a 32-byte secret seed.
function ed25519.publickey(seed)
  if type(seed) ~= "string" or #seed ~= 32 then
    return nil, "secret key must be 32 bytes"
  end
  local h = sha512.raw(seed)
  local a = bnFromBytesLE(clamp(h:sub(1, 32)))
  return ptEncode(ptMul(bnToBitsMSB(a), B_POINT))
end

--- Sign `msg` with a 32-byte secret seed. Returns a 64-byte signature.
function ed25519.sign(msg, seed, pk)
  if type(seed) ~= "string" or #seed ~= 32 then
    return nil, "secret key must be 32 bytes"
  end
  msg = tostring(msg or "")
  local h = sha512.raw(seed)
  local aBytes = clamp(h:sub(1, 32))
  local prefix = h:sub(33, 64)
  if not pk then pk = ed25519.publickey(seed) end

  local r = bnMod(bnFromBytesLE(sha512.raw(prefix .. msg)), L_BN)
  local R = ptEncode(ptMul(bnToBitsMSB(r), B_POINT))
  local k = bnMod(bnFromBytesLE(sha512.raw(R .. pk .. msg)), L_BN)
  local a = bnFromBytesLE(aBytes)
  local S = bnMod(bnAdd(r, bnMul(k, a)), L_BN)
  return R .. bnToBytesLE(S, 32)
end

--- Verify a 64-byte signature over `msg` with a 32-byte public key.
-- Returns true, or false plus a reason. NEVER raises: a signature is
-- attacker-controlled input and every malformed shape has to be an
-- ordinary "no" rather than a crash in the installer.
function ed25519.verify(msg, sig, pk)
  if type(sig) ~= "string" or #sig ~= 64 then return false, "signature must be 64 bytes" end
  if type(pk) ~= "string" or #pk ~= 32 then return false, "public key must be 32 bytes" end
  msg = tostring(msg or "")

  local ok, result, why = pcall(function()
    local Rs = sig:sub(1, 32)
    local Ss = sig:sub(33, 64)

    -- S must be canonical, i.e. already reduced mod L. Accepting an
    -- unreduced S would let anyone turn one valid signature into many
    -- distinct ones over the same message.
    local S = bnFromBytesLE(Ss)
    if bnCmp(S, L_BN) >= 0 then return false, "signature S is not reduced" end

    local A = ptDecode(pk)
    if not A then return false, "public key is not a curve point" end
    local R = ptDecode(Rs)
    if not R then return false, "signature R is not a curve point" end

    local k = bnMod(bnFromBytesLE(sha512.raw(Rs .. pk .. msg)), L_BN)

    local lhs = ptMul(bnToBitsMSB(S), B_POINT)          -- [S]B
    local rhs = ptAdd(R, ptMul(bnToBitsMSB(k), A))      -- R + [k]A

    if ptEncode(lhs) == ptEncode(rhs) then return true end
    return false, "signature does not match"
  end)

  if not ok then return false, "malformed signature" end
  if result then return true end
  return false, why or "signature does not match"
end

-- Exposed for the test file only — not part of the module's contract.
ed25519._internal = {
  feMul = feMul, feInvert = feInvert, feToBytes = feToBytes,
  feFromBytes = feFromBytes, ptEncode = ptEncode, ptDecode = ptDecode,
  B = B_POINT, bnMod = bnMod, bnFromBytesLE = bnFromBytesLE, L = L_BN,
}

return ed25519
