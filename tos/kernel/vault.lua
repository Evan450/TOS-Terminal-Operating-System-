local vault = {}

local crypto = require("kernel.crypto")

local MAGIC_V1   = "TVAULT1\0"
local MAGIC_V2   = "TVAULT2\0"
local MAGIC      = MAGIC_V2
local HEADER_LEN = 8 + 4 + 2 + 16 + 16 + 4 + 64

local function packU16(n) return string.char(n & 0xFF, (n >> 8) & 0xFF) end
local function packU32(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
end
local function unpackU16(s, off) return s:byte(off) | (s:byte(off + 1) << 8), off + 2 end
local function unpackU32(s, off)
  return s:byte(off)
    | (s:byte(off + 1) << 8)
    | (s:byte(off + 2) << 16)
    | (s:byte(off + 3) << 24), off + 4
end

local function padAlgo(s)
  if #s >= 4 then return s:sub(1, 4) end
  return s .. string.rep("\0", 4 - #s)
end

local function deriveKey(passphrase, salt)
  local stretched = crypto.hashPassword(passphrase, salt)

  local _, _, hex = stretched:find("^v%d+%$%d+%$(%x+)$")
  hex = hex or stretched
  return hex:sub(1, 32)
end

local function splitKeys(baseKey)
  local encKey = crypto.hmac(baseKey, "tos.vault.enc.v2")
  local macKey = crypto.hmac(baseKey, "tos.vault.mac.v2")
  return encKey, macKey
end

function vault.encrypt(plaintext, passphrase, opts)
  opts = opts or {}
  if type(plaintext) ~= "string" or type(passphrase) ~= "string" then
    return nil, "vault.encrypt: plaintext and passphrase must be strings"
  end
  if #passphrase < 1 then return nil, "passphrase must be non-empty" end

  if opts.requireStrong and not (crypto.hasHardware and crypto.hasHardware()) then
    return nil, "vault.encrypt: strong encryption required but no data card present "
      .. "(refusing to protect secrets with the XOR fallback)"
  end

  local saltHex = crypto.salt(16)

  local iv = crypto._makeIv16 and crypto._makeIv16() or
    string.rep("\0", 16)

  local baseKey = deriveKey(passphrase, saltHex)
  local encKey, macKey = splitKeys(baseKey)
  local ct, algo = crypto.encrypt(plaintext, encKey)
  if not ct then return nil, "encryption failed" end

  if algo == "aes" then

    iv = ct:sub(1, 16)
    ct = ct:sub(17)
  elseif algo == "xor" then

  else
    return nil, "unknown algo: " .. tostring(algo)
  end

  local rounds = 0
  local body = padAlgo(algo) .. packU16(rounds) .. saltHex .. iv ..
    packU32(#ct) .. ct
  local mac = crypto.hmac(macKey, body)
  local blob = MAGIC .. padAlgo(algo) .. packU16(rounds) .. saltHex .. iv ..
    packU32(#ct) .. mac .. ct

  return blob, { algo = algo, ctLen = #ct, blobLen = #blob }
end

function vault.decrypt(blob, passphrase)
  if type(blob) ~= "string" or type(passphrase) ~= "string" then
    return nil, "vault.decrypt: blob and passphrase must be strings"
  end
  if #blob < HEADER_LEN then return nil, "blob too short" end

  local magic = blob:sub(1, 8)
  local isV2
  if magic == MAGIC_V2 then isV2 = true
  elseif magic == MAGIC_V1 then isV2 = false
  else return nil, "not a TOS vault blob" end

  local off = 8 + 1
  local algo = blob:sub(off, off + 3); off = off + 4

  algo = algo:gsub("\0+$", "")
  local _rounds; _rounds, off = unpackU16(blob, off)
  local salt = blob:sub(off, off + 15); off = off + 16
  local iv   = blob:sub(off, off + 15); off = off + 16
  local ctLen; ctLen, off = unpackU32(blob, off)
  local mac  = blob:sub(off, off + 63); off = off + 64
  if off + ctLen - 1 > #blob then return nil, "blob truncated" end
  local ct = blob:sub(off, off + ctLen - 1)

  local baseKey = deriveKey(passphrase, salt)

  local encKey, macKey
  if isV2 then
    encKey, macKey = splitKeys(baseKey)
  else
    encKey, macKey = baseKey, baseKey
  end

  local body = padAlgo(algo) .. packU16(_rounds) .. salt .. iv ..
    packU32(ctLen) .. ct
  local expected = crypto.hmac(macKey, body)
  if not crypto.ctEquals(expected, mac) then
    return nil, "MAC mismatch (wrong passphrase, or blob tampered with)"
  end

  local toDecrypt = (algo == "aes") and (iv .. ct) or ct
  local plaintext = crypto.decrypt(toDecrypt, encKey, algo)
  if not plaintext then return nil, "decryption failed (corrupt blob)" end
  return plaintext, { algo = algo, ctLen = ctLen, plaintextLen = #plaintext }
end

function vault.isEncrypted(s)
  if type(s) ~= "string" or #s < 8 then return false end
  local m = s:sub(1, 8)
  return m == MAGIC_V2 or m == MAGIC_V1
end

vault.MAGIC      = MAGIC
vault.MAGIC_V1   = MAGIC_V1
vault.MAGIC_V2   = MAGIC_V2
vault.HEADER_LEN = HEADER_LEN

return vault
