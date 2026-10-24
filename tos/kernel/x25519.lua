-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - X25519 (RFC 7748), pure Lua 5.3                  ║
-- ║                                                              ║
-- ║  Diffie-Hellman key agreement over Curve25519's Montgomery     ║
-- ║  form. Lets any two TOS nodes derive a shared secret           ║
-- ║  automatically -- no Tier-3 data card required (OC's hardware  ║
-- ║  ECDH is a different, incompatible curve anyway -- see          ║
-- ║  ed25519.lua's header) and no pre-shared secret to type in by   ║
-- ║  hand on both ends. See kernel/net/trust.lua for how the        ║
-- ║  handshake actually gets triggered and cached.                  ║
-- ║                                                              ║
-- ║  WHY WE DID NOT INVENT A SCHEME, again. Same reasoning as       ║
-- ║  ed25519.lua: RFC 7748 is the spec, pinned to its OWN official   ║
-- ║  test vectors (usr/lib/tests/test_x25519.lua) -- the Section    ║
-- ║  5.2 scalarMult vectors (including the iterated one, 1 pass      ║
-- ║  only; 1,000/1,000,000 passes are each one more full scalar      ║
-- ║  multiplication and this is schoolbook-slow Lua, see COST        ║
-- ║  below) and the Section 6.1 Alice/Bob Diffie-Hellman example,    ║
-- ║  checked both directions (X25519(a, X25519(b,9)) ==               ║
-- ║  X25519(b, X25519(a,9))) and against an independent Python        ║
-- ║  reference built straight from the RFC's own pseudocode before    ║
-- ║  a line of this file was written (2026-10-23).                    ║
-- ║                                                              ║
-- ║  THE FIELD MATH IS SHARED with ed25519.lua (Edwards form, RFC    ║
-- ║  8032) via kernel/curve25519field.lua -- both curves live over    ║
-- ║  the same prime p = 2^255-19, so the field arithmetic is          ║
-- ║  identical even though the curve-level formulas below (the        ║
-- ║  Montgomery ladder) are specific to this one and written fresh.   ║
-- ║                                                              ║
-- ║  COST: a full scalarMult is ~255 ladder steps, each several       ║
-- ║  field multiplications -- the same order of magnitude as one       ║
-- ║  Ed25519 verification (also ~255 steps). Expect SECONDS on real    ║
-- ║  OC hardware, same as ed25519.lua's own measured expectation.      ║
-- ║  This is why net/trust.lua only ever runs this ONCE per peer       ║
-- ║  (to derive the shared secret) and caches the result -- never      ║
-- ║  per message. The ladder yields cooperatively (yieldCoop, every    ║
-- ║  16 steps) so it slows the SEAT, not the 5-second watchdog.        ║
-- ║                                                              ║
-- ║  NOT CONSTANT TIME, said plainly, same posture as ed25519.lua:    ║
-- ║  RFC 7748 §5's cswap is written here as an ordinary conditional    ║
-- ║  swap, not the constant-time masked one the RFC shows as an        ║
-- ║  OPTION ("SHOULD be implemented in constant time") for             ║
-- ║  implementations defending against a timing attacker sharing       ║
-- ║  the same CPU. Nothing in a Minecraft world offers that            ║
-- ║  vantage point, and both ends of this handshake are, by            ║
-- ║  definition, machines that already trust each other enough to      ║
-- ║  be pairing in the first place.                                    ║
-- ║                                                              ║
-- ║  Pure: no component/computer/fs require, so it loads under         ║
-- ║  plain Lua wherever curve25519field.lua does.                      ║
-- ╚══════════════════════════════════════════════════════════════╝

local field = require("kernel.curve25519field")

local feAdd, feSub, feMul, feSq, feInvert = field.feAdd, field.feSub, field.feMul, field.feSq, field.feInvert
local feFromBytes, feToBytes = field.feFromBytes, field.feToBytes
local feNew, feCopy, yieldCoop = field.feNew, field.feCopy, field.yieldCoop
local FE_ZERO, FE_ONE = field.FE_ZERO, field.FE_ONE

local x25519 = {}

x25519.KEY_LEN = 32

-- a24 = (486662 - 2) / 4 = 121665, RFC 7748 §5 (the curve25519 constant;
-- X448 uses a different one, which this module does not implement).
local A24 = feNew(); A24[1] = 121665

--- The base point's u-coordinate, encoded per RFC 7748 §6.1: a byte with
--- value 9, followed by 31 zero bytes.
x25519.BASEPOINT = string.char(9) .. string.rep("\0", 31)

--- Clamp a 32-byte scalar (RFC 7748 §5, decodeScalar25519's byte-level
--- part): clear the low 3 bits of the first byte, clear the top bit and
--- set bit 6 of the last. Returns the clamped 32 bytes (decoding to an
--- integer is folded into the ladder below via scalarBit, not done here).
local function clampScalar(k)
  local t = { k:byte(1, 32) }
  t[1]  = t[1] & 0xF8
  t[32] = (t[32] & 0x7F) | 0x40
  local out = {}
  for i = 1, 32 do out[i] = string.char(t[i]) end
  return table.concat(out)
end

--- Bit `i` (0 = least significant) of a 32-byte little-endian string.
local function scalarBit(kBytes, i)
  local byte = kBytes:byte((i // 8) + 1)
  return (byte >> (i % 8)) & 1
end

--- The Montgomery ladder, RFC 7748 §5, verbatim (variable names match the
--- RFC so the two can be read side by side). `cswap` is an ordinary
--- conditional swap -- see the header's NOT CONSTANT TIME note. Returns
--- 32 bytes, or nil + reason on malformed input.
function x25519.scalarMult(kBytes, uBytes)
  if type(kBytes) ~= "string" or #kBytes ~= x25519.KEY_LEN then
    return nil, "scalar must be " .. x25519.KEY_LEN .. " bytes"
  end
  if type(uBytes) ~= "string" or #uBytes ~= x25519.KEY_LEN then
    return nil, "u-coordinate must be " .. x25519.KEY_LEN .. " bytes"
  end

  local k = clampScalar(kBytes)
  -- feFromBytes already masks bit 255 (its own doc comment: "ignored
  -- here"), which is exactly RFC 7748 §5's required mask for X25519's
  -- u-coordinate decode -- no separate step needed.
  local u = feFromBytes(uBytes)

  local x1 = u
  local x2 = feCopy(FE_ONE)
  local z2 = feCopy(FE_ZERO)
  local x3 = feCopy(u)
  local z3 = feCopy(FE_ONE)
  local swap = 0

  for t = 254, 0, -1 do
    local kt = scalarBit(k, t)
    swap = swap ~ kt
    if swap == 1 then
      x2, x3 = x3, x2
      z2, z3 = z3, z2
    end
    swap = kt

    local A  = feAdd(x2, z2)
    local AA = feSq(A)
    local B  = feSub(x2, z2)
    local BB = feSq(B)
    local E  = feSub(AA, BB)
    local C  = feAdd(x3, z3)
    local D  = feSub(x3, z3)
    local DA = feMul(D, A)
    local CB = feMul(C, B)
    x3 = feSq(feAdd(DA, CB))
    z3 = feMul(x1, feSq(feSub(DA, CB)))
    x2 = feMul(AA, BB)
    z2 = feMul(E, feAdd(AA, feMul(A24, E)))

    -- ~255 iterations of ~6 field multiplications: the same order of
    -- cost as one Ed25519 verification, and the same reason to hand the
    -- seat back periodically instead of running it all in one breath.
    if (t % 16) == 0 then yieldCoop() end
  end
  if swap == 1 then
    x2, x3 = x3, x2
    z2, z3 = z3, z2
  end

  return feToBytes(feMul(x2, feInvert(z2)))
end

--- Does `secret` (the output of scalarMult) look like the all-zero
--- degenerate output RFC 7748 §6.1 warns a small-order input point
--- produces? Checked by ORing every byte together, the RFC's own
--- suggested approach ("eliminates standard side-channels"); this
--- module does not otherwise claim side-channel resistance (see the
--- header), but there is no reason to skip a trivial free one.
local function isAllZero(bytes32)
  local acc = 0
  for i = 1, #bytes32 do acc = acc | bytes32:byte(i) end
  return acc == 0
end
x25519._isAllZero = isAllZero   -- test hook

--- A fresh private scalar: `randomBytes(n)` must return n cryptographically
--- random bytes (injected rather than required, so this module stays as
--- dependency-free as curve25519field.lua -- the caller already has
--- kernel.crypto's RNG, see net/trust.lua). Returns 32 raw bytes; callers
--- pass them through scalarMult directly, which does its own clamping.
function x25519.generatePrivateKey(randomBytes)
  local raw = randomBytes(x25519.KEY_LEN)
  if type(raw) ~= "string" or #raw ~= x25519.KEY_LEN then
    return nil, "randomBytes did not return " .. x25519.KEY_LEN .. " bytes"
  end
  return raw
end

--- The public key for a private scalar: scalarMult(priv, basepoint).
function x25519.publicKey(priv)
  return x25519.scalarMult(priv, x25519.BASEPOINT)
end

--- The Diffie-Hellman shared secret for our private scalar and the
--- peer's public key. Returns nil, reason if `theirPublic` produced the
--- all-zero degenerate output (RFC 7748 §6.1: a small-order input point
--- -- either a malicious peer or a corrupted key, never a real one)
--- rather than handing the caller a "shared secret" every peer who sends
--- the same small-order point would also derive.
function x25519.sharedSecret(myPriv, theirPublic)
  local secret, err = x25519.scalarMult(myPriv, theirPublic)
  if not secret then return nil, err end
  if isAllZero(secret) then
    return nil, "peer's public key produced a degenerate (all-zero) shared secret"
  end
  return secret
end

return x25519
