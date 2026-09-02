local sha512 = require("kernel.sha512")

local ed25519 = {}

local yieldCoop
do
  local okP, procMod = pcall(require, "kernel.process")
  if okP and type(procMod) == "table" and type(procMod.yieldCooperative) == "function" then
    yieldCoop = procMod.yieldCooperative
  else
    yieldCoop = function() end
  end
end

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

local function bnToBitsMSB(a)
  local out = {}
  for i = bnBitLen(a) - 1, 0, -1 do out[#out + 1] = bnBit(a, i) end
  return out
end

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

local function feSq(f) return feMul(f, f) end

local FE_ZERO = feNew()
local FE_ONE  = feNew(); FE_ONE[1] = 1

local function fePow(f, bits)
  local r = feCopy(FE_ONE)
  for i = 1, #bits do
    r = feSq(r)
    if bits[i] == 1 then r = feMul(r, f) end

    if (i % 32) == 0 then yieldCoop() end
  end
  return r
end

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

local function feFromBytes(s)
  local h = {}
  for i = 1, 10 do h[i] = bitsAt(s, FE_OFF[i], FE_BITS[i]) end

  h[10] = h[10] & ((1 << 25) - 1)
  return feCarry(h)
end

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

local function feIsNegative(h) return bnBit(feToBn(h), 0) == 1 end

local function feInvert(f)

  return fePow(f, bnToBitsMSB(bnSub(P_BN, bnFromInt(2))))
end

local D, D2, SQRTM1

do
  local a = feNew(); a[1] = 121665
  local b = feNew(); b[1] = 121666
  D  = feMul(feNeg(a), feInvert(b))
  D2 = feAdd(D, D)

  local pm1 = bnSub(P_BN, bnFromInt(1))
  local pm1_4 = bnZero()
  for i = bnBitLen(pm1) - 1, 2, -1 do
    pm1_4 = bnAdd(bnShl(pm1_4, 1), bnFromInt(bnBit(pm1, i)))
  end
  local two = feNew(); two[1] = 2
  SQRTM1 = fePow(two, bnToBitsMSB(pm1_4))
end

local L_BN = bnFromBytesLE(string.char(
  0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
  0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10))

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

local function ptDecode(s)
  if #s ~= 32 then return nil end
  local sign = (s:byte(32) >> 7) & 1
  local y = feFromBytes(s)

  do
    local yb = bnFromBytesLE(s:sub(1, 31) .. string.char(s:byte(32) & 0x7F))
    if bnCmp(yb, P_BN) >= 0 then return nil end
  end

  local y2 = feSq(y)
  local u  = feSub(y2, FE_ONE)
  local v  = feAdd(feMul(D, y2), FE_ONE)

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
      return nil
    end
  end
  if feIsZero(x) and sign == 1 then return nil end
  if (feIsNegative(x) and 1 or 0) ~= sign then x = feNeg(x) end

  return { X = x, Y = y, Z = feCopy(FE_ONE), T = feMul(x, y) }
end

local B_POINT = ptDecode(string.char(
  0x58, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
  0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
  0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
  0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66))

local function clamp(b)
  local t = { b:byte(1, 32) }
  t[1]  = t[1] & 0xF8
  t[32] = (t[32] & 0x7F) | 0x40
  local out = {}
  for i = 1, 32 do out[i] = string.char(t[i]) end
  return table.concat(out)
end

function ed25519.publickey(seed)
  if type(seed) ~= "string" or #seed ~= 32 then
    return nil, "secret key must be 32 bytes"
  end
  local h = sha512.raw(seed)
  local a = bnFromBytesLE(clamp(h:sub(1, 32)))
  return ptEncode(ptMul(bnToBitsMSB(a), B_POINT))
end

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

function ed25519.verify(msg, sig, pk)
  if type(sig) ~= "string" or #sig ~= 64 then return false, "signature must be 64 bytes" end
  if type(pk) ~= "string" or #pk ~= 32 then return false, "public key must be 32 bytes" end
  msg = tostring(msg or "")

  local ok, result, why = pcall(function()
    local Rs = sig:sub(1, 32)
    local Ss = sig:sub(33, 64)

    local S = bnFromBytesLE(Ss)
    if bnCmp(S, L_BN) >= 0 then return false, "signature S is not reduced" end

    local A = ptDecode(pk)
    if not A then return false, "public key is not a curve point" end
    local R = ptDecode(Rs)
    if not R then return false, "signature R is not a curve point" end

    local k = bnMod(bnFromBytesLE(sha512.raw(Rs .. pk .. msg)), L_BN)

    local lhs = ptMul(bnToBitsMSB(S), B_POINT)
    local rhs = ptAdd(R, ptMul(bnToBitsMSB(k), A))

    if ptEncode(lhs) == ptEncode(rhs) then return true end
    return false, "signature does not match"
  end)

  if not ok then return false, "malformed signature" end
  if result then return true end
  return false, why or "signature does not match"
end

ed25519._internal = {
  feMul = feMul, feInvert = feInvert, feToBytes = feToBytes,
  feFromBytes = feFromBytes, ptEncode = ptEncode, ptDecode = ptDecode,
  B = B_POINT, bnMod = bnMod, bnFromBytesLE = bnFromBytesLE, L = L_BN,
}

return ed25519
