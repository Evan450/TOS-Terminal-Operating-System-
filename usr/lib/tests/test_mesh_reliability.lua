-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a mesh message is delivered, or still held    ║
-- ║                                                                ║
-- ║  The operator's design (Sep 2026), after the relay-flood fix:   ║
-- ║  relays hold copies only while they have the room; the SENDER   ║
-- ║  keeps its copy and probes for delivery (ACK = have it, WANT =  ║
-- ║  send it); an ACK or WANT about a sealed message is MACed; both ║
-- ║  ends' state survives a reset; and message ids no longer repeat ║
-- ║  after a reboot (a receiver dropped the new ones as duplicates).║
-- ║  Drives the REAL kernel.net.mesh and kernel.net.meshctl.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mesh_reliability.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local serialize = require("kernel.serialize")
local mesh = require("kernel.net.mesh")
local meshctl = require("kernel.net.meshctl")

-- Toy cipher and content-sensitive MAC, as test_meshctl uses. The salt
-- changes on every call, as a real one does: a boot's id prefix comes
-- from it.
local function xorc(d, k)
  local b = k:byte(1) or 0
  local o = {}
  for i = 1, #d do o[i] = string.char((d:byte(i) ~ b) & 0xFF) end
  return table.concat(o)
end
local function digest(s)
  local h = 5381
  for i = 1, #s do h = ((h * 33) ~ s:byte(i)) & 0xFFFFFFFF end
  return string.format("%08x", h)
end
local saltN = 0
local fakeCrypto = {
  salt = function(n) saltN = saltN + 1; return string.rep(string.char(65 + saltN % 26), n or 16) end,
  encrypt = function(d, k) return xorc(d, k), "xor" end,
  decrypt = function(d, k) return xorc(d, k) end,
  hmac = function(k, m) return "MAC(" .. digest(k .. "\0" .. m) .. ")" end,
  ctEquals = function(a, b) return a == b end,
}
local TIME = 0
local clock = function() return TIME end
meshctl.init({ crypto = fakeCrypto, serialize = serialize, clock = clock })

-- A store that keeps what a real one would: whatever survives serialize.
local function memStore()
  local saved
  return { load = function() return saved end,
           save = function(st) saved = serialize.decode(serialize.encode(st)) end }
end

-- A small mesh: links, per-pair secrets, nodes that can go offline or be
-- reset, and a filter that can lose packets in flight.
local function buildNet(links, secrets, stores)
  local N = { ctl = {}, got = {}, online = {}, sent = {}, queue = {} }
  local function mk(node)
    N.sent[node] = N.sent[node] or {}
    local c = meshctl.new({ myAddr = node, clock = clock,
      broadcast = function(env)
        N.sent[node][#N.sent[node] + 1] = env
        for _, nb in ipairs(links[node]) do N.queue[#N.queue + 1] = { nb, env } end
      end,
      secretFor = function(peer) return secrets[node .. ">" .. peer] end,
      store = stores and stores[node] or nil })
    c:on("mail", function(m)     -- a mailbox that dedups by id, like mail's
      for _, x in ipairs(N.got[node]) do if x.id == m.id then return false end end
      N.got[node][#N.got[node] + 1] = m
      return true
    end)
    return c
  end
  for node in pairs(links) do N.got[node] = {}; N.online[node] = true; N.ctl[node] = mk(node) end
  function N.drain()
    local guard = 0
    while #N.queue > 0 and guard < 20000 do
      guard = guard + 1
      local it = table.remove(N.queue, 1)
      if N.online[it[1]] and not (N.drop and N.drop(it[2])) then N.ctl[it[1]]:onPacket(it[2]) end
    end
  end
  function N.reset(node) N.ctl[node] = mk(node) end
  function N.count(node, kind)
    local n = 0
    for _, e in ipairs(N.sent[node]) do if e.kind == kind then n = n + 1 end end
    return n
  end
  return N
end

local LINKS = { A = { "B" }, B = { "A", "C" }, C = { "B" } }
local SECRETS = { ["A>C"] = "AC", ["C>A"] = "AC" }       -- B, the relay, holds none
local function later() TIME = TIME + mesh.RETRY_EVERY + 1 end

print("=== a mesh message is delivered, or still held ===")
print()
print("-- the sender probes; a WANT brings the message --")
do
  TIME = 0
  local N = buildNet(LINKS, SECRETS)
  N.online.C = false
  N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "while you were out" } })
  N.drain()
  eq("undelivered: the sender holds it", 1, N.ctl.A:pending())
  later(); N.ctl.A:tick(); N.drain()
  eq("a retry is a probe", 1, N.count("A", "probe"))
  eq("...so the whole message has still gone out once", 1, N.count("A", "msg"))
  N.online.C = true
  later(); N.ctl.A:tick(); N.drain()
  eq("C, back online, got it once", 1, #N.got.C)
  eq("...because it asked for it (WANT)", 1, N.count("C", "want"))
  eq("...and the sender sent it whole once more for that", 2, N.count("A", "msg"))
  eq("...through a relay that had already seen the first flood", 0, #N.got.B)
  eq("C's ACK cleared the sender", 0, N.ctl.A:pending())
end

print()
print("-- a lost ACK: the next probe is answered from what was delivered --")
do
  TIME = 0
  local N = buildNet(LINKS, SECRETS)
  N.drop = function(env) return env.kind == "ack" end
  N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "the ACK goes missing" } })
  N.drain()
  N.drop = nil
  eq("C has it", 1, #N.got.C)
  eq("the sender, with no ACK, still holds it", 1, N.ctl.A:pending())
  later(); N.ctl.A:tick(); N.drain()
  eq("one probe later the sender is clear", 0, N.ctl.A:pending())
  eq("...without sending the message again", 1, N.count("A", "msg"))
  eq("...and C's mailbox was not asked twice", 1, #N.got.C)
end

print()
print("-- nobody in between can say it was delivered --")
do
  TIME = 0
  local N = buildNet(LINKS, SECRETS)
  N.online.C = false
  local id = N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "x" } })
  N.drain()
  N.ctl.A:onPacket({ id = "forged-1", kind = "ack", from = "C", to = "A", ackId = id, ttl = 4, path = {} })
  eq("an ACK without the pair's MAC does not clear the message", 1, N.ctl.A:pending())
  N.ctl.A:onPacket({ id = "forged-2", kind = "ack", from = "C", to = "A", ackId = id, ttl = 4, path = {},
    mac = "MAC(00000000)" })
  eq("...nor one with the wrong MAC", 1, N.ctl.A:pending())
  N.ctl.A:onPacket({ id = "forged-3", kind = "ack", from = "B", to = "A", ackId = id, ttl = 4, path = {} })
  eq("...nor one from a node that is not the receiver", 1, N.ctl.A:pending())
  local before = N.count("A", "msg")
  N.ctl.A:onPacket({ id = "forged-4", kind = "want", from = "B", to = "A", wantId = id, ttl = 4, path = {} })
  eq("a WANT from a node that is not the receiver re-sends nothing", before, N.count("A", "msg"))
end

print()
print("-- both ends survive a reset --")
do
  TIME = 0
  local stores = { A = memStore(), C = memStore() }
  local N = buildNet(LINKS, SECRETS, stores)
  N.online.C = false
  N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "sent before the crash" } })
  N.drain()
  N.reset("A")
  eq("the message awaiting delivery survived the sender's reset", 1, N.ctl.A:pending())
  N.online.C = true
  later(); N.ctl.A:tick(); N.drain()
  eq("...and reached C once C was back", 1, #N.got.C)
  eq("...clearing the sender", 0, N.ctl.A:pending())

  N.drop = function(env) return env.kind == "ack" end
  N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "second" } })
  N.drain()
  N.drop = nil
  N.reset("C")
  later(); N.ctl.A:tick(); N.drain()
  eq("a restarted receiver still knows what it delivered: the probe is ACKed", 0, N.ctl.A:pending())
  eq("...and the mailbox holds each message once", 2, #N.got.C)
end

print()
print("-- message ids do not repeat after a reboot --")
do
  TIME = 0
  local N = buildNet(LINKS, SECRETS)
  local id1 = N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "before" } })
  N.drain()
  N.reset("A")
  local id2 = N.ctl.A:send({ svc = "mail", to = "C", payload = { body = "after" } })
  N.drain()
  test("the first message after a reboot has a new id", id1 ~= id2)
  eq("...so C, which remembers the old one, delivers it", 2, #N.got.C)
end

print()
print("-- relays hold what they have room for, and let go under pressure --")
do
  TIME = 0
  local FREE = 1e6
  local R = meshctl.new({ myAddr = "R", clock = clock, broadcast = function() end,
    freeMemory = function() return FREE end })
  for i = 1, 12 do
    R:onPacket({ id = "big" .. i, kind = "msg", from = "a", to = "c", ttl = 4, path = {},
      svc = "mail", sealed = string.rep("s", 6000) })
  end
  eq("with room to spare a relay holds 6 KB copies, up to the cap", mesh.RELAY_HOLD_MAX,
    mesh.pending(R.outbox))
  FREE = 30 * 1024
  R:tick(TIME)
  eq("under the memory floor it lets them all go", 0, mesh.pending(R.outbox))
  R:onPacket({ id = "late", kind = "msg", from = "a", to = "c", ttl = 4, path = {},
    svc = "mail", sealed = "small" })
  eq("...and holds nothing new until there is room", 0, mesh.pending(R.outbox))
end

print()
print("-- the sender's own queue is bounded, and a send floods once --")
do
  TIME = 0
  local MAXO = meshctl.ORIGIN_MAX or 16
  local A = meshctl.new({ myAddr = "A", clock = clock, broadcast = function() end,
    secretFor = function() return "k" end })
  for i = 1, MAXO do A:send({ svc = "mail", to = "C", payload = { n = i } }) end
  local id, err = A:send({ svc = "mail", to = "C", payload = { n = "one too many" } })
  test("past " .. MAXO .. " awaiting delivery a new message is refused",
    id == nil and tostring(err):find("full", 1, true) ~= nil)

  local n = 0
  local B = meshctl.new({ myAddr = "B", clock = clock, broadcast = function() n = n + 1 end,
    secretFor = function() return "k" end })
  B:send({ svc = "mail", to = "C", payload = {} })
  B:tick(TIME)
  eq("the tick right after a send does not flood it again", 1, n)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
