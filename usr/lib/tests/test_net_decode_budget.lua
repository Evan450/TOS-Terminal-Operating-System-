-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: one packet cannot make the decoder build more  ║
-- ║  than a bounded amount of heap                                   ║
-- ║                                                                  ║
-- ║  net.handleIncoming decodes every packet -- from any modem in    ║
-- ║  range, BLOCKED peers included -- before it checks anything.     ║
-- ║  protocol.deserialize passed only a byte cap, so 8 KB of         ║
-- ║  "{{},{},...}" built 2730 tables: 215 KB of heap on a 192-256 KB ║
-- ║  machine (Sep 2026 pentest). The decode now carries a budget.    ║
-- ║                                                                  ║
-- ║  Drives the REAL kernel.net.protocol and kernel.serialize, and   ║
-- ║  checks the largest real packets (a 128-row storage page, a      ║
-- ║  256-name netfs listing, a file chunk) still decode.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_decode_budget.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
local protocol = require("kernel.net.protocol")
local serialize = require("kernel.serialize")
local MAX = protocol.MAX_SIZE

-- Everything the call allocates, garbage included: the collector is off.
local function allocKB(fn)
  collectgarbage(); collectgarbage()
  local before = collectgarbage("count")
  collectgarbage("stop")
  local r1, r2 = fn()
  local used = collectgarbage("count") - before
  collectgarbage("restart")
  return used, r1, r2
end

local function fill(unit)
  return "{" .. string.rep(unit, math.floor((MAX - 2) / #unit)) .. "}"
end
local function build(gen)
  local parts, len, i = {}, 2, 0
  while true do
    i = i + 1
    local s = gen(i)
    if len + #s > MAX then break end
    parts[#parts + 1] = s; len = len + #s
  end
  return "{" .. table.concat(parts) .. "}"
end

-- The budget is 48 KB in Lua 5.3's sizes; 5.4 off-box counts a little
-- lower, and the slack covers the parse's own garbage.
local LIMIT_KB = 64

print("=== a hostile 8 KB packet is refused before it builds much ===")
print()
local head = '{magic="TOS",ver=1,type="ping",payload={'
local HOSTILE = {
  { "empty tables",          fill("{},") },
  { "nested pairs",          fill("{{}},") },
  { "numbers",               fill("1,") },
  { "distinct bare keys",    build(function(i) return "k" .. i .. "=1," end) },
  { "distinct bracket keys", build(function(i) return '["' .. i .. '"]=1,' end) },
  { "distinct strings",      build(function(i) return '"' .. i .. '",' end) },
  { "a valid header over a table flood",
    head .. string.rep("{},", math.floor((MAX - #head - 2) / 3)) .. "}}" },
}
for _, h in ipairs(HOSTILE) do
  local s = h[2]
  local kb, pkt = allocKB(function() return protocol.deserialize(s) end)
  test(string.format("%-34s %4d B: refused, %5.1f KB", h[1], #s, kb), pkt == nil and kb < LIMIT_KB)
end

print()
print("-- the largest real packets still decode --")
local FROM = "0123abcd-4567-89ef-0123-456789abcdef"
local function real(name, ptype, payload)
  local pkt = protocol.makePacket(ptype, payload)
  pkt.from = FROM
  local s = protocol.serialize(pkt)
  local kb, out = allocKB(function() return protocol.deserialize(s) end)
  test(string.format("%-34s %4d B: decodes (%4.1f KB)", name, #s, kb),
    #s <= MAX and out ~= nil and protocol.validate(out) == true)
  return out
end

local names = {}
for i = 1, 256 do names[i] = string.format("save_%04d.dat", i) end
local out = real("netfs listing, 256 names", protocol.TYPE.NETFS_RES,
  { id = 17, entries = names, truncated = true })
test("   ...every name arrives", out and out.payload.entries and #out.payload.entries == 256
  and out.payload.entries[256] == "save_0256.dat")

-- A storage page is up to 128 rows (storaged's default; the master never
-- asks for more). The costliest page that still fits ONE packet: as many
-- rows as fit, with the longest keys that let them.
local function page(n, keyLen)
  local r = {}
  for i = 1, n do
    local tag = tostring(i)
    r[i] = { key = string.rep("r", math.max(0, keyLen - #tag)) .. tag, size = 4096 + i, expires_at = 1700000000 + i }
  end
  local p = protocol.makePacket(protocol.TYPE.STORE_LIST_RES, { prefix = "jobs/", keys = r, truncated = true })
  p.from = FROM
  return r, #protocol.serialize(p)
end
local rows, nRows
for n = 128, 8, -8 do
  for keyLen = 40, 3, -1 do
    local r, size = page(n, keyLen)
    if size <= MAX then rows, nRows = r, n; break end
  end
  if rows then break end
end
out = real("storage page, " .. nRows .. " rows", protocol.TYPE.STORE_LIST_RES,
  { prefix = "jobs/", keys = rows, truncated = true })
test("   ...every row arrives", out and out.payload.keys and #out.payload.keys == nRows
  and out.payload.keys[nRows].size == 4096 + nRows)

real("file chunk, 6 KB", protocol.TYPE.FILE_RES,
  { path = "/home/alice/notes.txt", offset = 0, data = string.rep("abcdefgh", 768) })
real("cluster heartbeat", protocol.TYPE.CLUSTER_HEARTBEAT,
  { state = "idle", workers_active = 4, workers_busy = 1, queue_depth = 3,
    storage_used = 1234, errors_last_min = 0, uptime = 3600, external_type = "tape" })
real("mesh envelope, 7 KB sealed blob", protocol.TYPE.MESH,
  { svc = "mail", id = "m-1", ttl = 6, blob = string.rep("Zq9", 2333) })

print()
print("-- nothing else changes --")
test("serialize.decode without a budget still reads a big table (config files)",
  type(serialize.decode(fill("{},"))) == "table")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
