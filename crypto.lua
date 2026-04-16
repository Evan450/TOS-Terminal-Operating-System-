-- ╔══════════════════════════════════════╗
-- ║  TOS Security - Crypto Module        ║
-- ║  Software hashing + optional HW      ║
-- ╚══════════════════════════════════════╝
-- Priority: RELIABILITY over speed.
-- Uses data card (SHA-256) if available,
-- falls back to software DJB2+FNV1a dual hash.

local component = require("component")
local computer = require("computer")

local crypto = {}

-- ============================================================
-- Hardware detection
-- ============================================================
local dataCard = nil
local hwCrypto = false

function crypto.init()
  -- Check for data card (Tier 1 has md5, Tier 2+ has sha256, encrypt)
  local ok, _ = pcall(function()
    for addr in component.list("data") do
      dataCard = component.proxy(addr)
      hwCrypto = true
      return
    end
  end)
  return hwCrypto
end

function crypto.hasHardware()
  return hwCrypto
end

-- ============================================================
-- Software hash (no dependencies)
-- Combines DJB2 + FNV-1a for reasonable collision resistance.
-- NOT cryptographically secure, but sufficient for password
-- protection in a Minecraft environment.
-- ============================================================

-- DJB2 hash
local function djb2(str)
  local hash = 5381
  for i = 1, #str do
    -- hash * 33 + byte, keep within Lua integer range
    hash = ((hash << 5) + hash + str:byte(i)) & 0xFFFFFFFF
  end
  return hash
end

-- FNV-1a hash
local function fnv1a(str)
  local hash = 0x811C9DC5  -- FNV offset basis (32-bit)
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    hash = (hash * 0x01000193) & 0xFFFFFFFF  -- FNV prime
  end
  return hash
end

--- Software hash: returns 16-char hex string from dual hash
local function softHash(data)
  local h1 = djb2(data)
  local h2 = fnv1a(data)
  return string.format("%08x%08x", h1, h2)
end

-- ============================================================
-- Software SHA-256 (Lua 5.3 bitwise ops)
-- Returns 64-char lowercase hex, matching dataCard.sha256 -> hex.
-- ============================================================

local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF end

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
}

local function tohex32(x) return string.format("%08x", x & 0xFFFFFFFF) end

local function sha256_hex(msg)
  local bytes = { msg:byte(1, #msg) }
  local bitLen = (#bytes) * 8

  -- append 0x80
  bytes[#bytes + 1] = 0x80
  -- pad with zeros until length ≡ 56 (mod 64)
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end
  -- append 64-bit big-endian length
  local hi = math.floor(bitLen / 2^32)
  local lo = bitLen & 0xFFFFFFFF
  bytes[#bytes + 1] = (hi >> 24) & 0xFF
  bytes[#bytes + 1] = (hi >> 16) & 0xFF
  bytes[#bytes + 1] = (hi >>  8) & 0xFF
  bytes[#bytes + 1] = (hi      ) & 0xFF
  bytes[#bytes + 1] = (lo >> 24) & 0xFF
  bytes[#bytes + 1] = (lo >> 16) & 0xFF
  bytes[#bytes + 1] = (lo >>  8) & 0xFF
  bytes[#bytes + 1] = (lo      ) & 0xFF

  local h0,h1,h2,h3,h4,h5,h6,h7 =
    0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19

  local w = {}

  for chunk = 1, #bytes, 64 do
    -- message schedule
    for i = 0, 15 do
      local j = chunk + i*4
      w[i+1] =
        ((bytes[j]   << 24) |
         (bytes[j+1] << 16) |
         (bytes[j+2] <<  8) |
         (bytes[j+3]      )) & 0xFFFFFFFF
    end
    for i = 16, 63 do
      local s0 = (rrot(w[i-15+1], 7) ~ rrot(w[i-15+1], 18) ~ (w[i-15+1] >> 3)) & 0xFFFFFFFF
      local s1 = (rrot(w[i-2+1], 17) ~ rrot(w[i-2+1], 19) ~ (w[i-2+1] >> 10)) & 0xFFFFFFFF
      w[i+1] = (w[i-16+1] + s0 + w[i-7+1] + s1) & 0xFFFFFFFF
    end

    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7

    for i = 0, 63 do
      local S1  = (rrot(e, 6) ~ rrot(e,11) ~ rrot(e,25)) & 0xFFFFFFFF
      local ch  = ((e & f) ~ ((~e) & g)) & 0xFFFFFFFF
      local t1  = (h + S1 + ch + K[i+1] + w[i+1]) & 0xFFFFFFFF
      local S0  = (rrot(a, 2) ~ rrot(a,13) ~ rrot(a,22)) & 0xFFFFFFFF
      local maj = ((a & b) ~ (a & c) ~ (b & c)) & 0xFFFFFFFF
      local t2  = (S0 + maj) & 0xFFFFFFFF

      h = g
      g = f
      f = e
      e = (d + t1) & 0xFFFFFFFF
      d = c
      c = b
      b = a
      a = (t1 + t2) & 0xFFFFFFFF
    end

    h0 = (h0 + a) & 0xFFFFFFFF
    h1 = (h1 + b) & 0xFFFFFFFF
    h2 = (h2 + c) & 0xFFFFFFFF
    h3 = (h3 + d) & 0xFFFFFFFF
    h4 = (h4 + e) & 0xFFFFFFFF
    h5 = (h5 + f) & 0xFFFFFFFF
    h6 = (h6 + g) & 0xFFFFFFFF
    h7 = (h7 + h) & 0xFFFFFFFF
  end

  return tohex32(h0)..tohex32(h1)..tohex32(h2)..tohex32(h3)..tohex32(h4)..tohex32(h5)..tohex32(h6)..tohex32(h7)
end

-- ============================================================
-- Public hashing API
-- ============================================================

--- Hash a string. Uses SHA-256 if data card available, else software hash.
-- @param data string: Data to hash
-- @return string: Hex-encoded hash
function crypto.hash(data)
  if dataCard then
    local ok, result = pcall(function()
      local raw = dataCard.sha256(data)
      local hex = {}
      for i = 1, #raw do
        hex[#hex + 1] = string.format("%02x", raw:byte(i))
      end
      return table.concat(hex)
    end)
    if ok and result then return result end
  end

  -- Software SHA-256 fallback (stable across boots)
  return sha256_hex(data)
end

--- Hash a password with a salt
-- @param password string: The password
-- @param salt string: The salt (use crypto.salt() to generate)
-- @return string: Salted hash
function crypto.hashPassword(password, salt)
  -- Double-hash with salt for basic stretching
  local pass1 = crypto.hash(salt .. password)
  local pass2 = crypto.hash(pass1 .. salt .. "tos")
  return pass2
end

--- Verify a password against a stored hash
function crypto.verifyPassword(password, salt, storedHash)
  if type(storedHash) ~= "string" then return false end

  -- New/standard: SHA-256-based (64 hex)
  if #storedHash == 64 then
    return crypto.hashPassword(password, salt) == storedHash
  end

  -- Legacy: softHash-based (16 hex)
  if #storedHash == 16 then
    local pass1 = softHash(salt .. password)
    local pass2 = softHash(pass1 .. salt .. "tos")
    return pass2 == storedHash
  end

  return false
end

-- ============================================================
-- Salt / token generation
-- ============================================================

--- Generate a random salt string
-- Uses data card random() for hardware entropy when available,
-- falls back to math.random seeded from uptime + free memory.
function crypto.salt(length)
  length = length or 16
  -- If data card is available, use its hardware random bytes
  if dataCard then
    local ok, raw = pcall(dataCard.random, length)
    if ok and raw then
      -- Convert raw bytes to alphanumeric characters
      local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      local result = {}
      for i = 1, #raw do
        local b = raw:byte(i)
        result[i] = chars:sub((b % #chars) + 1, (b % #chars) + 1)
      end
      return table.concat(result)
    end
  end
  -- Fallback: seed math.random with available entropy + a counter to avoid collisions
  if not crypto._saltCounter then crypto._saltCounter = 0 end
  crypto._saltCounter = crypto._saltCounter + 1
  local seed = math.floor(computer.uptime() * 1000000) + computer.freeMemory() + crypto._saltCounter
  math.randomseed(seed % 0x7FFFFFFF)
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local result = {}
  for i = 1, length do
    local idx = math.random(1, #chars)
    result[i] = chars:sub(idx, idx)
  end
  return table.concat(result)
end

--- Generate a session token
function crypto.token()
  return crypto.hash(crypto.salt(32) .. tostring(computer.uptime()))
end

-- ============================================================
-- Simple XOR cipher for network messages
-- NOT secure against determined attackers, but prevents
-- casual packet sniffing on MC servers.
-- On Tier 2+ data card, uses real AES if available.
-- ============================================================

--- XOR encrypt/decrypt (symmetric)
local function xorCipher(data, key)
  local result = {}
  local keyLen = #key
  for i = 1, #data do
    local keyByte = key:byte(((i - 1) % keyLen) + 1)
    result[i] = string.char(data:byte(i) ~ keyByte)
  end
  return table.concat(result)
end

--- Encrypt data with a shared key
function crypto.encrypt(data, key)
  if dataCard then
    -- Try hardware encryption (Tier 2 data card)
    local ok, result = pcall(function()
      -- Data card encrypt uses AES
      local iv = crypto.salt(16)  -- 16-byte IV
      local encrypted = dataCard.encrypt(data, key, iv)
      -- Prepend IV so we can decrypt later
      return iv .. encrypted
    end)
    if ok and result then
      return result, "aes"
    end
  end
  -- Fallback: XOR cipher with hashed key
  local hashedKey = crypto.hash(key)
  return xorCipher(data, hashedKey), "xor"
end

--- Decrypt data with a shared key
function crypto.decrypt(data, key, method)
  if method == "aes" and dataCard then
    local ok, result = pcall(function()
      local iv = data:sub(1, 16)
      local ciphertext = data:sub(17)
      return dataCard.decrypt(ciphertext, key, iv)
    end)
    if ok and result then return result end
  end
  -- XOR decrypt (same as encrypt)
  local hashedKey = crypto.hash(key)
  return xorCipher(data, hashedKey)
end

-- ============================================================
-- Data integrity
-- ============================================================

--- Compute a checksum for data integrity verification
function crypto.checksum(data)
  return string.format("%08x", fnv1a(data))
end

--- Sign data (hash + checksum for tampering detection)
function crypto.sign(data, secret)
  return crypto.hash(data .. secret)
end

--- Verify a signature
function crypto.verifySignature(data, signature, secret)
  return crypto.sign(data, secret) == signature
end

return crypto
