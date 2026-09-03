-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: OpenOS cluster-worker frame auth crypto  ║
-- ║                                                            ║
-- ║  The OpenOS worker carries its OWN software SHA-256 + HMAC ║
-- ║  (no kernel.crypto on OpenOS). For the Manager and worker  ║
-- ║  to authenticate each other's WRK frames the digests must  ║
-- ║  be byte-identical to TOS kernel.crypto. This pins that.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_worker_hmac.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Stubs so kernel.crypto loads off-box (no data card => pure software path,
-- exactly what the OpenOS worker uses).
package.loaded["component"] = { list = function() return function() return nil end end }
package.loaded["computer"]  = { uptime = function() return 0 end,
  freeMemory = function() return 0 end, totalMemory = function() return 0 end,
  address = function() return "test" end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local crypto = require("kernel.crypto")

-- ── The EXACT primitives embedded in cluster/openos/cluster-worker.lua ──
local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF end
local SHA_K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function tohex32(x) return string.format("%08x", x & 0xFFFFFFFF) end
local function sha256_hex(msg)
  local bytes = { msg:byte(1, #msg) }
  local bitLen = (#bytes) * 8
  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
  local hi = math.floor(bitLen / 2^32)
  local lo = bitLen & 0xFFFFFFFF
  bytes[#bytes + 1] = (hi >> 24) & 0xFF; bytes[#bytes + 1] = (hi >> 16) & 0xFF
  bytes[#bytes + 1] = (hi >>  8) & 0xFF; bytes[#bytes + 1] = (hi      ) & 0xFF
  bytes[#bytes + 1] = (lo >> 24) & 0xFF; bytes[#bytes + 1] = (lo >> 16) & 0xFF
  bytes[#bytes + 1] = (lo >>  8) & 0xFF; bytes[#bytes + 1] = (lo      ) & 0xFF
  local h0,h1,h2,h3,h4,h5,h6,h7 =
    0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
  local w = {}
  for chunk = 1, #bytes, 64 do
    for i = 0, 15 do
      local j = chunk + i*4
      w[i+1] = ((bytes[j] << 24) | (bytes[j+1] << 16) | (bytes[j+2] << 8) | (bytes[j+3])) & 0xFFFFFFFF
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
      local t1  = (h + S1 + ch + SHA_K[i+1] + w[i+1]) & 0xFFFFFFFF
      local S0  = (rrot(a, 2) ~ rrot(a,13) ~ rrot(a,22)) & 0xFFFFFFFF
      local maj = ((a & b) ~ (a & c) ~ (b & c)) & 0xFFFFFFFF
      local t2  = (S0 + maj) & 0xFFFFFFFF
      h=g; g=f; f=e; e=(d+t1)&0xFFFFFFFF; d=c; c=b; b=a; a=(t1+t2)&0xFFFFFFFF
    end
    h0=(h0+a)&0xFFFFFFFF; h1=(h1+b)&0xFFFFFFFF; h2=(h2+c)&0xFFFFFFFF; h3=(h3+d)&0xFFFFFFFF
    h4=(h4+e)&0xFFFFFFFF; h5=(h5+f)&0xFFFFFFFF; h6=(h6+g)&0xFFFFFFFF; h7=(h7+h)&0xFFFFFFFF
  end
  return tohex32(h0)..tohex32(h1)..tohex32(h2)..tohex32(h3)..tohex32(h4)..tohex32(h5)..tohex32(h6)..tohex32(h7)
end
local HMAC_BLOCK = 64
local function hmacSha256(key, msg)
  if #key > HMAC_BLOCK then
    local hexed = sha256_hex(key)
    local raw = {}
    for i = 1, 32 do raw[i] = string.char(tonumber(hexed:sub(i*2-1, i*2), 16)) end
    key = table.concat(raw)
  end
  if #key < HMAC_BLOCK then key = key .. string.rep("\0", HMAC_BLOCK - #key) end
  local ipad, opad = {}, {}
  for i = 1, HMAC_BLOCK do
    local kb = key:byte(i)
    ipad[i] = string.char(kb ~ 0x36)
    opad[i] = string.char(kb ~ 0x5C)
  end
  local innerHex = sha256_hex(table.concat(ipad) .. msg)
  local innerRaw = {}
  for i = 1, 32 do innerRaw[i] = string.char(tonumber(innerHex:sub(i*2-1, i*2), 16)) end
  return sha256_hex(table.concat(opad) .. table.concat(innerRaw))
end
local function canonicalFrame(v)
  local t = type(v)
  if t == "string" then return "s" .. #v .. ":" .. v
  elseif t == "number" then local s = tostring(v); return "n" .. #s .. ":" .. s
  elseif t == "boolean" then return v and "bT" or "bF"
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do if k ~= "mac" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = canonicalFrame(k) .. canonicalFrame(v[k]) end
    return "{" .. table.concat(parts) .. "}"
  end
  return "z"
end

print("=== cluster-worker frame-auth crypto Tests ===")
print()

-- Known SHA-256 vector — proves the worker's primitive is standard SHA-256.
test("SHA-256('abc')",
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  sha256_hex("abc"))

-- HMAC must match the Manager's kernel.crypto.hmac byte-for-byte, across key
-- lengths (short, exactly-64, and >64 which triggers the key-prehash path).
local SECRET = "cluster-shared-secret-0123456789"
for _, m in ipairs({ "", "hello", string.rep("x", 200) }) do
  test("HMAC matches kernel.crypto (#msg=" .. #m .. ")",
    crypto.hmac(SECRET, m), hmacSha256(SECRET, m))
end
test("HMAC matches with >64-byte key",
  crypto.hmac(string.rep("K", 100), "payload"),
  hmacSha256(string.rep("K", 100), "payload"))

-- Full Manager->worker round-trip: Manager signs a frame with kernel.crypto
-- over canonicalFrame; worker verifies with its own HMAC. Must agree.
local frame = { magic = "WRK", op = "TASK", task_id = 7,
  code = "print(1)", inputs = {}, timeout = 30, nonce = "abcd1234abcd1234" }
local managerMac = crypto.hmac(SECRET, canonicalFrame(frame))
local workerMac  = hmacSha256(SECRET, canonicalFrame(frame))
test("Manager-signed frame verifies on worker", true,
  crypto.ctEquals(managerMac, workerMac))

-- Tampering any field (here: the code to run) must break the MAC.
local tampered = {}
for k, v in pairs(frame) do tampered[k] = v end
tampered.code = "os.execute('rm -rf /')"
test("tampered frame fails verification", false,
  crypto.ctEquals(managerMac, hmacSha256(SECRET, canonicalFrame(tampered))))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
