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

local ed25519 = {}

-- ============================================================
-- Cooperative yielding
-- ============================================================
-- Resolved once, lazily, and tolerated absent: this module must load
-- under plain Lua for the off-box signer and during early boot.
local yieldCoop
do
  local okP, procMod = pcall(require, "kernel.process")
  if okP and type(procMod) == "table" and type(procMod.yieldCooperative) == "function" then
    yieldCoop = procMod.yieldCooperative
  else
    yieldCoop = function() end
  end
end

-- ============================================================
-- Minimal bignum — 24-bit limbs, little-endian, non-negative
-- ============================================================
-- Needed for exactly three jobs, none of them on the hot path:
--   * turning a field element back into canonical bytes,
--   * reducing a scalar mod L when SIGNING,
--   * producing the bit strings of the fixed exponents below.
-- It is schoolbook and slow on purpose. The field arithmetic further
-- down is where the speed has to live; here, obvious correctness is
-- worth more than cleverness.

local BN_BITS = 24
local BN_BASE = 1 << BN_BITS
local BN_MASK = BN_BASE - 1

local function bnZero() return { 0 } end

local function bnTrim(a)
  while #a > 1 and a[#a] == 0 do a[#a] = nil end
  return a
end

local function bnFromInt(n)
  local a = {}
  if n == 0 then return { 0 } end
  while n > 0 do a[#a + 1] = n & BN_MASK; n = n >> BN_BITS end
  return a
end

local function bnCmp(a, b)
  if #a ~= #b then return #a < #b and -1 or 1 end
  for i = #a, 1, -1 do
    if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
  end
  return 0
end

local function bnAdd(a, b)
  local out, carry = {}, 0
  local n = math.max(#a, #b)
  for i = 1, n do
    local s = (a[i] or 0) + (b[i] or 0) + carry
    out[i] = s & BN_MASK
    carry = s >> BN_BITS
  end
  if carry ~= 0 then out[n + 1] = carry end
  return bnTrim(out)
end

--- a - b, requires a >= b.
local function bnSub(a, b)
  local out, borrow = {}, 0
  for i = 1, #a do
    local s = a[i] - (b[i] or 0) - borrow
    if s < 0 then s = s + BN_BASE; borrow = 1 else borrow = 0 end
    out[i] = s
  end
  return bnTrim(out)
end

local function bnShl(a, n)
  if bnCmp(a, bnZero()) == 0 then return bnZero() end
  local limbShift, bitShift = n // BN_BITS, n % BN_BITS
  local out = {}
  for i = 1, limbShift do out[i] = 0 end
  local carry = 0
  for i = 1, #a do
    local v = (a[i] << bitShift) | carry
    out[limbShift + i] = v & BN_MASK
    carry = v >> BN_BITS
  end
  if carry ~= 0 then out[limbShift + #a + 1] = carry end
  return bnTrim(out)
end

local function bnMul(a, b)
  local out = {}
  for i = 1, #a + #b do out[i] = 0 end
  for i = 1, #a do
    local carry = 0
    local ai = a[i]
    if ai ~= 0 then
      for j = 1, #b do
        local t = out[i + j - 1] + ai * b[j] + carry
        out[i + j - 1] = t & BN_MASK
        carry = t >> BN_BITS
      end
      local k = i + #b
      while carry ~= 0 do
        local t = out[k] + carry
        out[k] = t & BN_MASK
        carry = t >> BN_BITS
        k = k + 1
      end
    end
  end
  return bnTrim(out)
end

local function bnBitLen(a)
  local top = a[#a]
  if top == 0 and #a == 1 then return 0 end
  local n = (#a - 1) * BN_BITS
  while top > 0 do n = n + 1; top = top >> 1 end
  return n
end

local function bnBit(a, i)
  local limb = a[(i // BN_BITS) + 1]
  if not limb then return 0 end
  return (limb >> (i % BN_BITS)) & 1
end

--- a mod m, by binary long division. O(bits(a)) subtractions — fine for
--- the handful of places this is used, and impossible to get subtly wrong
--- in the way a Barrett or Montgomery reduction can be.
local function bnMod(a, m)
  if bnCmp(a, m) < 0 then return a end
  local r = bnZero()
  for i = bnBitLen(a) - 1, 0, -1 do
    r = bnShl(r, 1)
    if bnBit(a, i) == 1 then r = bnAdd(r, bnFromInt(1)) end
    if bnCmp(r, m) >= 0 then r = bnSub(r, m) end
  end
  return r
end

local function bnFromBytesLE(s)
  local a = bnZero()
  for i = #s, 1, -1 do
    a = bnShl(a, 8)
    a = bnAdd(a, bnFromInt(s:byte(i)))
  end
  return a
end

local function bnToBytesLE(a, n)
  local out = {}
  for i = 0, n - 1 do
    local byte = 0
    for b = 0, 7 do byte = byte | (bnBit(a, i * 8 + b) << b) end
    out[i + 1] = string.char(byte)
  end
  return table.concat(out)
end

--- Bits of `a`, most significant first, as an array of 0/1. Used to drive
--- the exponentiation ladder.
local function bnToBitsMSB(a)
  local out = {}
  for i = bnBitLen(a) - 1, 0, -1 do out[#out + 1] = bnBit(a, i) end
  return out
end

-- ============================================================
-- Field arithmetic mod p = 2^255 - 19
-- ============================================================
-- Representation: ten signed limbs at radix 2^25.5 — limb i carries
-- 26 bits when i is even and 25 when i is odd, so the ten of them span
-- exactly 255 bits. This is ref10's layout, and the reason for the odd
-- fractional radix is the reason it is worth the trouble: 255 divides
-- evenly by 25.5, so a product that spills past limb 9 wraps back to
-- limb 0 multiplied by exactly 19 (because 2^255 ≡ 19 mod p). Any
-- whole-number radix leaves the wrap misaligned and the fold factor
-- becomes large enough to overflow a 64-bit accumulator.
--
-- Multiplication is written as a plain double loop rather than the
-- unrolled 100-term expression ref10 uses. It computes the same thing
-- and the scaling rules are derivable in two lines (see fieldMul), which
-- matters more here than the last few percent of speed: an unrolled
-- expression with one transposed index is a bug that passes every test
-- except the ones you did not think to write.

local FE_OFF   = { 0, 26, 51, 77, 102, 128, 153, 179, 204, 230 }
local FE_BITS  = { 26, 25, 26, 25, 26, 25, 26, 25, 26, 25 }
local FE_POW   = {}
local FE_HALF  = {}
for i = 1, 10 do
  FE_POW[i]  = 1 << FE_BITS[i]
  FE_HALF[i] = 1 << (FE_BITS[i] - 1)
end

local function feNew() return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } end

local function feCopy(f)
  return { f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10] }
end

--- Propagate carries so every limb sits inside its radix.
-- Two passes: the first can push a carry out of limb 9, which folds back
-- into limb 0 times 19 and may itself need carrying along.
--
-- Note `//` and not `>>`. Lua 5.3's right shift is LOGICAL, so a negative
-- limb shifted right becomes an enormous positive number; floor division
-- is the arithmetic shift this needs. Limbs here are genuinely signed —
-- subtraction does not normalise — so this distinction is load-bearing
-- rather than pedantic.
local function feCarry(h)
  for _ = 1, 2 do
    for i = 1, 10 do
      local c = (h[i] + FE_HALF[i]) // FE_POW[i]
      if i == 10 then
        h[1] = h[1] + 19 * c
      else
        h[i + 1] = h[i + 1] + c
      end
      h[i] = h[i] - c * FE_POW[i]
    end
  end
  return h
end

local function feAdd(f, g)
  local h = {}
  for i = 1, 10 do h[i] = f[i] + g[i] end
  return feCarry(h)
end

local function feSub(f, g)
  local h = {}
  for i = 1, 10 do h[i] = f[i] - g[i] end
  return feCarry(h)
end

local function feNeg(f)
  local h = {}
  for i = 1, 10 do h[i] = -f[i] end
  return feCarry(h)
end

--- f * g mod p.
-- Limb i has weight 2^ceil(25.5*i). So the product f[i]*g[j] has weight
-- 2^(ceil(25.5i)+ceil(25.5j)), and the limb it belongs in, i+j, has
-- weight 2^ceil(25.5(i+j)). Those agree EXCEPT when i and j are both
-- odd: then each ceil added a half, i+j is even so its own ceil adds
-- none, and the term is one power of two too heavy — hence the doubling.
-- Anything landing past limb 9 has an extra factor of 2^255 ≡ 19.
local function feMul(f, g)
  local h = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  for i = 0, 9 do
    local fi = f[i + 1]
    if fi ~= 0 then
      local iOdd = (i % 2) == 1
      for j = 0, 9 do
        local t = fi * g[j + 1]
        if iOdd and (j % 2) == 1 then t = t * 2 end
        local k = i + j
        if k >= 10 then
          h[k - 10 + 1] = h[k - 10 + 1] + 19 * t
        else
          h[k + 1] = h[k + 1] + t
        end
      end
    end
  end
  return feCarry(h)
end

-- Squaring is multiplication by self. A dedicated routine would save
-- perhaps a third of the multiplies, and would be a second intricate
-- function to keep correct; the vectors are easier to trust this way.
local function feSq(f) return feMul(f, f) end

local FE_ZERO = feNew()
local FE_ONE  = feNew(); FE_ONE[1] = 1

--- Raise f to an exponent given as an MSB-first bit array.
local function fePow(f, bits)
  local r = feCopy(FE_ONE)
  for i = 1, #bits do
    r = feSq(r)
    if bits[i] == 1 then r = feMul(r, f) end
    -- ~255 iterations of ~9 field multiplications: this is where a
    -- verification actually spends its time, so it is where the seat
    -- gets handed back.
    if (i % 32) == 0 then yieldCoop() end
  end
  return r
end

-- ── Byte conversion ──────────────────────────────────────────
local P_BN = bnSub(bnShl(bnFromInt(1), 255), bnFromInt(19))

local function bitsAt(s, start, n)
  local v = 0
  for k = 0, n - 1 do
    local bit = start + k
    local byte = s:byte((bit >> 3) + 1)
    v = v | (((byte >> (bit & 7)) & 1) << k)
  end
  return v
end

--- 32 little-endian bytes → field element. Bit 255 is IGNORED here: in
--- Ed25519 it is the sign of x, not part of y, and its removal is the
--- caller's business.
local function feFromBytes(s)
  local h = {}
  for i = 1, 10 do h[i] = bitsAt(s, FE_OFF[i], FE_BITS[i]) end
  -- Clear the bit that belongs to the sign flag, then carry so the
  -- limbs are in range.
  h[10] = h[10] & ((1 << 25) - 1)
  return feCarry(h)
end

--- Field element → the bignum it represents, fully reduced mod p.
-- Limbs are signed, so the sum is accumulated starting from a large
-- multiple of p — 16p is comfortably above the largest magnitude ten
-- carried limbs can subtract — and then reduced. Slower than ref10's
-- conditional-subtract dance and much harder to get wrong.
local function feToBn(h)
  local acc = bnMul(P_BN, bnFromInt(16))
  for i = 1, 10 do
    local v = h[i]
    if v ~= 0 then
      local neg = v < 0
      if neg then v = -v end
      local t = bnShl(bnFromInt(v), FE_OFF[i])
      acc = neg and bnSub(acc, t) or bnAdd(acc, t)
    end
  end
  return bnMod(acc, P_BN)
end

local function feToBytes(h) return bnToBytesLE(feToBn(h), 32) end

local function feIsZero(h) return bnCmp(feToBn(h), bnZero()) == 0 end
local function feEq(a, b) return bnCmp(feToBn(a), feToBn(b)) == 0 end

--- Low bit of the canonical representative — Ed25519's "is x negative".
local function feIsNegative(h) return bnBit(feToBn(h), 0) == 1 end

local function feInvert(f)
  -- f^(p-2)
  return fePow(f, bnToBitsMSB(bnSub(P_BN, bnFromInt(2))))
end

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
