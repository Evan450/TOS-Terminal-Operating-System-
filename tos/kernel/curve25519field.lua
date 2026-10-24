-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Curve25519 field arithmetic, pure Lua 5.3        ║
-- ║                                                              ║
-- ║  The prime field GF(2^255 - 19), and nothing curve-specific.  ║
-- ║  Ed25519 (kernel/ed25519.lua, signatures) and X25519           ║
-- ║  (kernel/x25519.lua, Diffie-Hellman key agreement) are two     ║
-- ║  DIFFERENT curves -- Edwards and Montgomery -- but RFC 8032    ║
-- ║  and RFC 7748 both build them over this same prime, so the     ║
-- ║  field math underneath is identical. Extracted out of          ║
-- ║  ed25519.lua (2026-10-23, Area 1 of a network/UI redesign)     ║
-- ║  with ZERO logic changes -- every function here is copied      ║
-- ║  verbatim -- so that x25519.lua is not left to either           ║
-- ║  duplicate ~350 lines of security-critical arithmetic or        ║
-- ║  reach into ed25519's `_internal`, which that module's own      ║
-- ║  comment says is "exposed for the test file only -- not part    ║
-- ║  of the module's contract". test_ed25519.lua (pinned to RFC     ║
-- ║  8032's own vectors) re-verifies byte-for-byte after this move  ║
-- ║  that nothing changed.                                          ║
-- ║                                                                  ║
-- ║  Pure: no component/computer/fs require, so the off-box signer  ║
-- ║  and any off-box key-agreement tooling can load it under plain  ║
-- ║  Lua 5.3.                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝

local F = {}

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
F.yieldCoop = yieldCoop

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
    -- verification (or a Diffie-Hellman scalar multiplication) actually
    -- spends its time, so it is where the seat gets handed back.
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
--- Ed25519 it is the sign of x, not part of y, and in X25519 it is not
--- part of the field element at all (RFC 7748 §5 masks it too); either
--- way its removal is the caller's business.
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

F.bnZero, F.bnTrim, F.bnFromInt, F.bnCmp = bnZero, bnTrim, bnFromInt, bnCmp
F.bnAdd, F.bnSub, F.bnShl, F.bnMul = bnAdd, bnSub, bnShl, bnMul
F.bnBitLen, F.bnBit, F.bnMod = bnBitLen, bnBit, bnMod
F.bnFromBytesLE, F.bnToBytesLE, F.bnToBitsMSB = bnFromBytesLE, bnToBytesLE, bnToBitsMSB

F.feNew, F.feCopy, F.feCarry = feNew, feCopy, feCarry
F.feAdd, F.feSub, F.feNeg, F.feMul, F.feSq, F.fePow = feAdd, feSub, feNeg, feMul, feSq, fePow
F.feFromBytes, F.feToBn, F.feToBytes = feFromBytes, feToBn, feToBytes
F.feIsZero, F.feEq, F.feIsNegative, F.feInvert = feIsZero, feEq, feIsNegative, feInvert
F.FE_ZERO, F.FE_ONE = FE_ZERO, FE_ONE
F.P_BN = P_BN

return F
