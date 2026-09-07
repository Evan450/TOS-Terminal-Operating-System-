-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the worker bridge's two halves agree          ║
-- ║                                                                ║
-- ║  The Manager-side bridge (manager-skeleton/usr/lib/cluster/     ║
-- ║  worker.lua) and the OpenOS worker daemon (openos/              ║
-- ║  cluster-worker.lua) run on different machines, under different ║
-- ║  operating systems, and authenticate every frame to each other. ║
-- ║  Three things have to match exactly or nothing is ever          ║
-- ║  accepted, and each is DUPLICATED in both files because the     ║
-- ║  worker cannot require TOS code:                                ║
-- ║                                                                ║
-- ║    1. canonicalFrame  — the byte string the MAC is taken over   ║
-- ║    2. HMAC-SHA256     — the worker hand-rolls what kernel.crypto ║
-- ║                         provides on the TOS side                ║
-- ║    3. the VALUES sent — see below                               ║
-- ║                                                                ║
-- ║  (3) is the one that was actually broken. canonicalFrame writes ║
-- ║  a number with tostring, and Lua 5.3+ renders an integral float ║
-- ║  as "100.0" where Lua 5.2 renders it "100". OpenComputers ships ║
-- ║  both CPU architectures and OpenOS runs on either, so a worker  ║
-- ║  and a Manager on different CPUs canonicalized the same frame   ║
-- ║  differently and the MAC failed. Both sides sent                ║
-- ║  computer.uptime() in their PING/PONG, and uptime advances in   ║
-- ║  0.05 steps — so about one ping in twenty landed on an integral ║
-- ║  value and was silently dropped, and the worker went            ║
-- ║  "unresponsive" for no reason an operator could see.            ║
-- ║                                                                ║
-- ║  Nobody reads that field, so both sides now floor it. This test ║
-- ║  checks the property rather than the line: every frame either   ║
-- ║  side builds must canonicalize IDENTICALLY under both           ║
-- ║  architectures' number formatting.                              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua cluster/openos/test_cluster_worker_frames.lua   (from TOS-Extras)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local here = (arg and arg[0]) or "cluster/openos/test_cluster_worker_frames.lua"
local base = here:gsub("[^/\\]*$", "")          -- .../cluster/openos/
local EXTRAS = base .. "../../"                 -- TOS-Extras root

local function readFile(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("a"); f:close(); return s
end
local function firstOf(paths)
  for _, p in ipairs(paths) do local s = readFile(p); if s then return s, p end end
end

local TOS_SRC = firstOf({ EXTRAS .. "cluster/manager-skeleton/usr/lib/cluster/worker.lua",
                          "cluster/manager-skeleton/usr/lib/cluster/worker.lua" })
local WRK_SRC = firstOf({ EXTRAS .. "cluster/openos/cluster-worker.lua",
                          "cluster/openos/cluster-worker.lua" })
if not (TOS_SRC and WRK_SRC) then
  print("FAIL: could not read both sides of the bridge")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Lift a function out of a file's real source. Neither file can simply be
-- required here: one is a TOS kernel module, the other a daemon that opens
-- a modem and never returns. Slicing keeps the REAL implementation.
local SANDBOX = { string = string, table = table, math = math, type = type,
                  tostring = tostring, tonumber = tonumber, pairs = pairs,
                  ipairs = ipairs, select = select }
local function lift(src, fromPat, toPat, ret, name)
  local a = src:find(fromPat)
  if not a then return nil end
  local b = toPat and src:find(toPat, a) or nil
  local chunk = load(src:sub(a, b and b - 1 or nil) .. "\nreturn " .. ret, "=" .. name, "t", SANDBOX)
  if not chunk then return nil end
  local ok, v = pcall(chunk)
  return ok and v or nil
end

local canonTOS = lift(TOS_SRC, "local function canonicalFrame",
                      "\nlocal function sendFrame", "canonicalFrame", "tos-canon")
local canonWRK = lift(WRK_SRC, "local function canonicalFrame",
                      "\n%-%- Per%-frame nonce", "canonicalFrame", "wrk-canon")
local wrkCrypto = lift(WRK_SRC, "local function rrot", "local function canonicalFrame",
                       "{ hmac = hmacSha256, sha = sha256_hex, ct = ctEquals }", "wrk-crypto")

print("=== cluster worker bridge: both halves agree ===")
print()

test("the Manager side's canonicalFrame was found", type(canonTOS) == "function")
test("the OpenOS side's canonicalFrame was found", type(canonWRK) == "function")
test("the OpenOS side's crypto was found", type(wrkCrypto) == "table")
if not (canonTOS and canonWRK and wrkCrypto) then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

-- ── 1. The two canonicalizers ────────────────────────────────────
print()
print("-- canonicalFrame is the same function on both sides --")
local canonCases = {
  { "a flat frame",        { op = "PING", magic = "WRK" } },
  { "an integer field",    { op = "TASK", timeout = 30 } },
  { "a fractional field",  { op = "PONG", time = 100.5 } },
  { "a negative number",   { n = -3 } },
  { "booleans",            { ok = true, bad = false } },
  { "a nested table",      { op = "RESULT", out = { 1, 2, "three" } } },
  { "raw bytes in a value", { nonce = "\0\1\255\128rawnonce" } },
  { "mixed key types",     { [1] = "one", two = 2 } },
  { "an empty table",      {} },
  { "a deep nest",         { a = { b = { c = { d = "e" } } } } },
}
for _, c in ipairs(canonCases) do
  local a, b = canonTOS(c[2]), canonWRK(c[2])
  test("both agree on " .. c[1], a == b)
end
eq("the mac field is excluded from its own MAC", canonTOS({ op = "X" }),
   canonTOS({ op = "X", mac = "anything at all" }))
test("...on the OpenOS side too",
  canonWRK({ op = "X" }) == canonWRK({ op = "X", mac = "anything at all" }))

-- ── 2. The two crypto implementations ────────────────────────────
print()
print("-- the worker's hand-rolled HMAC is kernel.crypto's --")
package.path = EXTRAS .. "../TOS-Dev/tos/?.lua;" .. EXTRAS .. "../tos/?.lua;"
  .. "../TOS-Dev/tos/?.lua;../tos/?.lua;" .. package.path
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["computer"] = { uptime = function() return 0 end, address = function() return "x" end,
  freeMemory = function() return 900000 end, totalMemory = function() return 1000000 end }
local okK, K = pcall(require, "kernel.crypto")
test("kernel.crypto loads", okK and type(K) == "table")

eq("the worker's SHA-256 matches FIPS 180-4's own vector for \"abc\"",
   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
   wrkCrypto.sha("abc"))

if okK and K and K.hmac then
  local hmacCases = {
    { "a-shared-secret-16", "" },
    { "a-shared-secret-16", "abc" },
    { "a-long-shared-secret-of-decent-length", "{s2:ops4:PING}" },
    { string.rep("k", 64), string.rep("m", 200) },
    { string.rep("k", 65), "a key past the block size takes the hashed path" },
    { "sec", "raw\0bytes\255in\1the\128message" },
  }
  for i, c in ipairs(hmacCases) do
    test(("HMAC case %d agrees with kernel.crypto"):format(i), wrkCrypto.hmac(c[1], c[2]) == K.hmac(c[1], c[2]))
  end
  -- And end to end: a frame signed by the worker verifies on the TOS side.
  local secret = "a-long-shared-secret-of-decent-length"
  local frame = { magic = "WRK", op = "RESULT", task_id = 7, status = "ok",
                  output = "42", nonce = string.rep("a", 32) }
  frame.mac = wrkCrypto.hmac(secret, canonWRK(frame))
  test("a frame the worker signed verifies with kernel.crypto over the TOS canonical form",
    K.hmac(secret, canonTOS(frame)) == frame.mac)
  test("...and one byte of tampering breaks it", (function()
    local t = {}; for k, v in pairs(frame) do t[k] = v end
    t.output = "43"
    return K.hmac(secret, canonTOS(t)) ~= t.mac
  end)())
  test("the MAC is the 64 hex chars both sides length-check for", #frame.mac == 64)
end

-- ── 3. Architecture independence of what is actually sent ────────
print()
print("-- every frame survives BOTH Lua architectures --")
--! Lua 5.3+ keeps integers and floats apart, so tostring(100.0) is
--! "100.0"; Lua 5.2 has only floats and formats with %.14g, so the same
--! value prints "100". canonicalFrame uses tostring, so a value that
--! renders differently is a frame the two machines cannot agree on.
--! This renders each frame the way a 5.2 box would and demands the same
--! canonical string.
local function canon52(v)
  local t = type(v)
  if t == "number" then
    local s = string.format("%.14g", v)
    return "n" .. #s .. ":" .. s
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do if k ~= "mac" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = canon52(k) .. canon52(v[k]) end
    return "{" .. table.concat(parts) .. "}"
  end
  return canonTOS(v)
end
local function archSafe(frame) return canonTOS(frame) == canon52(frame) end

-- The checker has to be able to fail, or the rest of this section is noise.
test("the checker CATCHES an integral float (this is the bug)",
  not archSafe({ op = "PONG", time = 100.0 }))
test("...and passes the same value as an integer", archSafe({ op = "PONG", time = 100 }))

local now = 1234.0                      -- an uptime that landed on a whole second
local sentFrames = {
  { "PING (Manager -> worker)",  { op = "PING", time = math.floor(now) } },
  { "PONG (worker -> Manager)",  { op = "PONG", time = math.floor(now) } },
  { "REGISTER",                  { op = "REGISTER", hostname = "worker-1", capabilities = {} } },
  { "REGISTER_ACK",              { op = "REGISTER_ACK", accepted = true, domain_id = 0 } },
  { "TASK",                      { op = "TASK", task_id = 7, code = "return 1", timeout = 30 } },
  { "CANCEL",                    { op = "CANCEL", task_id = 7 } },
  { "RESULT",                    { op = "RESULT", task_id = 7, status = "ok", output = "42" } },
  { "PROGRESS",                  { op = "PROGRESS", task_id = 7, pct = 50 } },
}
for _, f in ipairs(sentFrames) do
  test(f[1] .. " canonicalizes the same on 5.2 and 5.3", archSafe(f[2]))
end

-- The two source files must not go back to sending a raw uptime.
for _, pair in ipairs({ { "the Manager side", TOS_SRC, 'op = "PING"' },
                        { "the OpenOS side",  WRK_SRC, 'op = "PONG"' } }) do
  local line = pair[2]:match("[^\n]*" .. pair[3]:gsub("%p", "%%%0") .. "[^\n]*")
  test(pair[1] .. " floors the time it sends (" .. tostring(line and line:gsub("^%s+", "") or "?") .. ")",
    line ~= nil and line:find("math.floor", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
