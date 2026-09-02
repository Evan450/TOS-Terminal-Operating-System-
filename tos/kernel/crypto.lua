local component = require("component")
local computer = require("computer")

local crypto = {}

local dataCard = nil
local hwCrypto = false

function crypto.init()

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

local function djb2(str)
  local hash = 5381
  for i = 1, #str do

    hash = ((hash << 5) + hash + str:byte(i)) & 0xFFFFFFFF
  end
  return hash
end

local function fnv1a(str)
  local hash = 0x811C9DC5
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    hash = (hash * 0x01000193) & 0xFFFFFFFF
  end
  return hash
end

local function softHash(data)
  local h1 = djb2(data)
  local h2 = fnv1a(data)
  return string.format("%08x%08x", h1, h2)
end

local sha256_hex = require("kernel.sha256").hex

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

  return sha256_hex(data)
end

local function ctEquals(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local la, lb = #a, #b
  local n = la > lb and la or lb
  local diff = la ~ lb
  for i = 1, n do
    local ba = i <= la and a:byte(i) or 0
    local bb = i <= lb and b:byte(i) or 0
    diff = diff | (ba ~ bb)
  end
  return diff == 0
end
crypto.ctEquals = ctEquals

local PW_ROUNDS = 256
local function effectiveRounds()
  return PW_ROUNDS
end

local function hashPasswordLegacy(password, salt)
  local pass1 = crypto.hash(salt .. password)
  local pass2 = crypto.hash(pass1 .. salt .. "tos")
  return pass2
end

local function hashPasswordSw256(password, salt, rounds)
  local h = sha256_hex(salt .. password .. "tos")
  for _ = 2, (rounds or PW_ROUNDS) do
    h = sha256_hex(h .. salt)
  end
  return h
end

local hmacSha256
local function pwInner(password, salt, rounds)

  local key = salt .. "tos"
  local h = hmacSha256(key, password)
  for i = 2, rounds do
    h = hmacSha256(key, h .. string.char(i & 0xFF, (i >> 8) & 0xFF))
  end
  return h
end

local function pwInnerV3(password, salt, rounds)

  local key = salt .. "\0tos.v3"
  local h = hmacSha256(key, password .. "\0" .. salt)
  for i = 2, rounds do
    h = hmacSha256(key, h .. "\0" .. string.char(i & 0xFF, (i >> 8) & 0xFF))
  end
  return h
end

function crypto.hashPassword(password, salt)
  local rounds = effectiveRounds()

  return "v3$" .. tostring(rounds) .. "$" .. pwInnerV3(password, salt, rounds)
end

function crypto.verifyPassword(password, salt, storedHash)

  if type(storedHash) ~= "string" then return false, false end
  if type(password) ~= "string"   then return false, false end
  if type(salt) ~= "string"       then return false, false end

  local v3Rounds, v3Hex = storedHash:match("^v3%$(%d+)%$(%x+)$")
  if v3Rounds and v3Hex and #v3Hex == 64 then
    local rounds = tonumber(v3Rounds)
    if rounds and rounds >= 1 and rounds <= 100000 then
      if ctEquals(pwInnerV3(password, salt, rounds), v3Hex) then

        local cur = effectiveRounds()
        return true, (rounds ~= cur)
      end
    end
    return false, false
  end

  local roundsStr, hex = storedHash:match("^v2%$(%d+)%$(%x+)$")
  if roundsStr and hex and #hex == 64 then
    local rounds = tonumber(roundsStr)
    if rounds and rounds >= 1 and rounds <= 100000 then
      if ctEquals(pwInner(password, salt, rounds), hex) then
        return true, true
      end
    end
    return false, false
  end

  if #storedHash == 64 then

    if ctEquals(hashPasswordSw256(password, salt, PW_ROUNDS), storedHash) then
      return true, true
    end

    if ctEquals(hashPasswordLegacy(password, salt), storedHash) then
      return true, true
    end
    return false, false
  end

  if #storedHash == 16 then

    pcall(function()
      local logMod = require("kernel.log")
      if logMod and logMod.warn then
        logMod.warn("crypto", "Refused legacy 16-hex hash; account must be reset")
      end
    end)
    return false, false
  end

  return false, false
end

local _rngState = 0
local _rngCounter = 0
local function rngMixEntropy()
  _rngCounter = _rngCounter + 1

  local pool = table.concat({
    tostring(computer.uptime()),
    tostring(computer.freeMemory()),
    tostring(computer.totalMemory and computer.totalMemory() or 0),
    tostring(_rngCounter),
    tostring(_rngState),
    tostring({}),
  }, "|")
  local h = sha256_hex(pool)

  local s = 0
  for i = 1, 16 do
    s = ((s << 4) | tonumber(h:sub(i, i), 16)) & 0xFFFFFFFFFFFFFFFF
  end
  if s == 0 then s = 0xDEADBEEFCAFEBABE end
  _rngState = s
end

local function rngNext()
  if _rngState == 0 then rngMixEntropy() end

  local x = _rngState
  x = x ~ (x >> 12); x = x & 0xFFFFFFFFFFFFFFFF
  x = x ~ (x << 25); x = x & 0xFFFFFFFFFFFFFFFF
  x = x ~ (x >> 27); x = x & 0xFFFFFFFFFFFFFFFF
  _rngState = x
  return (x * 0x2545F4914F6CDD1D) & 0xFFFFFFFFFFFFFFFF
end

function crypto.addEntropy(seed)
  if type(seed) ~= "string" or seed == "" then return false end
  local mixed = sha256_hex(seed .. "|" .. tostring(_rngState) .. "|" .. tostring(_rngCounter))
  local s = 0
  for i = 1, 16 do
    s = ((s << 4) | tonumber(mixed:sub(i, i), 16)) & 0xFFFFFFFFFFFFFFFF
  end
  _rngState = (_rngState ~ s) & 0xFFFFFFFFFFFFFFFF
  if _rngState == 0 then _rngState = (s ~= 0) and s or 0xA5A5A5A5A5A5A5A5 end
  _rngCounter = _rngCounter + 1
  return true
end

function crypto.exportEntropy(n)
  n = (type(n) == "number" and n > 0) and math.floor(n) or 32
  rngMixEntropy()
  local out = {}
  for i = 1, n do
    out[i] = string.char(rngNext() & 0xFF)
  end
  return table.concat(out)
end

local _rngDegradedWarned = false
local function warnDegradedRng()
  if _rngDegradedWarned or dataCard then return end
  _rngDegradedWarned = true
  pcall(function()
    local logMod = require("kernel.log")
    if logMod and logMod.warn then
      logMod.warn("crypto",
        "No data card — session tokens/salts use the software RNG (degraded; not a CSPRNG)")
    end
  end)
end

function crypto.salt(length)
  length = length or 16
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local nChars = #chars

  local function pickFromByte(b)

    if b >= 248 then return nil end
    return chars:sub((b % nChars) + 1, (b % nChars) + 1)
  end

  local RNG_LIMIT = 0xFFFFFFFFFFFFFFF0
  local function pickFromRng()
    while true do
      local r = rngNext()
      if math.ult(r, RNG_LIMIT) then
        return chars:sub((r % nChars) + 1, (r % nChars) + 1)
      end
    end
  end

  if dataCard then
    local result = {}
    local idx = 1
    while idx <= length do
      local ok, raw = pcall(dataCard.random, length * 2)
      if not ok or not raw then break end
      for i = 1, #raw do
        if idx > length then break end
        local pick = pickFromByte(raw:byte(i))
        if pick then result[idx] = pick; idx = idx + 1 end
      end
    end
    if idx > length then return table.concat(result) end

  end

  rngMixEntropy()
  local result = {}
  for i = 1, length do
    result[i] = pickFromRng()
  end
  return table.concat(result)
end

local _tokenCounter = 0
function crypto.token()
  warnDegradedRng()
  _tokenCounter = _tokenCounter + 1
  return crypto.hash(crypto.salt(32)
    .. crypto.salt(16)
    .. tostring(computer.uptime())
    .. tostring(_tokenCounter))
end

local function xorCipher(data, key)
  local result = {}
  local keyLen = #key
  for i = 1, #data do
    local keyByte = key:byte(((i - 1) % keyLen) + 1)
    result[i] = string.char(data:byte(i) ~ keyByte)
  end
  return table.concat(result)
end

local _xorWarned = false

local function makeIv16()
  if dataCard then
    local ok, raw = pcall(dataCard.random, 16)
    if ok and type(raw) == "string" and #raw == 16 then
      return raw
    end
  end
  rngMixEntropy()
  local out = {}
  for i = 1, 2 do
    local n = rngNext()
    for shift = 56, 0, -8 do
      out[#out + 1] = string.char((n >> shift) & 0xFF)
    end
  end
  return table.concat(out)
end
crypto._makeIv16 = makeIv16

function crypto.encrypt(data, key)
  if dataCard then

    local ok, result = pcall(function()

      local iv = makeIv16()
      local encrypted = dataCard.encrypt(data, key, iv)

      return iv .. encrypted
    end)
    if ok and result then
      return result, "aes"
    end
  end

  if not _xorWarned then
    _xorWarned = true
    pcall(function()
      local log = require("kernel.log")
      if log then
        log.warn("crypto", "No data card — encryption falling back to XOR (not secure)")
      end
    end)
  end
  local hashedKey = crypto.hash(key)
  return xorCipher(data, hashedKey), "xor"
end

function crypto.decrypt(data, key, method)
  if type(data) ~= "string" or type(key) ~= "string" then
    return nil
  end
  if method == "aes" then
    if not dataCard then return nil end
    if #data < 17 then return nil end
    local ok, result = pcall(function()
      local iv = data:sub(1, 16)
      local ciphertext = data:sub(17)
      return dataCard.decrypt(ciphertext, key, iv)
    end)
    if ok and result then return result end
    return nil
  end
  if method == "xor" then
    local hashedKey = crypto.hash(key)
    return xorCipher(data, hashedKey)
  end

  return nil
end

function crypto.checksum(data)
  return crypto.hash(data)
end

local HMAC_BLOCK = 64

local function shaHex(s)
  return sha256_hex(s)
end

hmacSha256 = function(key, msg)

  if #key > HMAC_BLOCK then
    local hexed = shaHex(key)

    local raw = {}
    for i = 1, 32 do
      raw[i] = string.char(tonumber(hexed:sub(i * 2 - 1, i * 2), 16))
    end
    key = table.concat(raw)
  end
  if #key < HMAC_BLOCK then
    key = key .. string.rep("\0", HMAC_BLOCK - #key)
  end
  local ipad, opad = {}, {}
  for i = 1, HMAC_BLOCK do
    local kb = key:byte(i)
    ipad[i] = string.char(kb ~ 0x36)
    opad[i] = string.char(kb ~ 0x5C)
  end
  local ipadS, opadS = table.concat(ipad), table.concat(opad)

  local innerHex = shaHex(ipadS .. msg)
  local innerRaw = {}
  for i = 1, 32 do
    innerRaw[i] = string.char(tonumber(innerHex:sub(i * 2 - 1, i * 2), 16))
  end
  return shaHex(opadS .. table.concat(innerRaw))
end
crypto.hmac = hmacSha256

function crypto.sign(data, secret)
  return hmacSha256(secret or "", data or "")
end

return crypto
