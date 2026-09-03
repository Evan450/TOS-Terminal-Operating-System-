-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: net.meshctl (the NATIVE mesh transport) ║
-- ║                                                            ║
-- ║  Stage 5: the mesh is part of the integrated network and   ║
-- ║  multiplexes SERVICES (mail, chat, …) over one flood mesh; ║
-- ║  mail is just a tenant (an Extras package). Replaces the   ║
-- ║  old test_mail + test_mailctl, which tested the same       ║
-- ║  machinery when it was mail-private.                       ║
-- ║                                                            ║
-- ║  Covers: seal/open round-trip + tamper/wrong-key/service-  ║
-- ║  rebinding rejection, the ingest decision, SERVICE         ║
-- ║  MULTIPLEXING (handlers only see their own kind), the      ║
-- ║  refuse-plaintext policy, ACK-only-when-a-service-accepted,║
-- ║  and a 3-node A—B—C run proving a sealed message crosses a ║
-- ║  BLIND relay, is delivered exactly once, and its ACK       ║
-- ║  floods back and clears the origin's outbox.               ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_meshctl.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local serialize = assert(loadfile("tos/kernel/serialize.lua"))()
package.loaded["kernel.serialize"] = serialize
local mesh    = require("kernel.net.mesh")
local meshctl = require("kernel.net.meshctl")

-- Toy reversible "cipher": XOR each byte with the first byte of the key.
-- Enough to prove seal/open + MAC wiring without real crypto cost.
local function xorc(d, k)
  local b = k:byte(1) or 0
  local o = {}
  for i = 1, #d do o[i] = string.char((d:byte(i) ~ b) & 0xFF) end
  return table.concat(o)
end
-- CONTENT-sensitive fake MAC (djb2-ish). The old mail tests hashed only
-- the message LENGTH, which silently passed any same-length swap — e.g.
-- re-stapling a sealed "mail" blob onto a "chat" envelope (both 4 chars).
-- The MAC binding is exactly what this test needs to prove, so the fake
-- has to react to content, not size.
local function digest(s)
  local h = 5381
  for i = 1, #s do h = ((h * 33) ~ s:byte(i)) & 0xFFFFFFFF end
  return string.format("%08x", h)
end
local fakeCrypto = {
  salt = function(n) return string.rep("N", n or 16) end,
  encrypt = function(d, k) return xorc(d, k), "xor" end,
  decrypt = function(d, k) return xorc(d, k) end,
  hmac = function(k, m) return "MAC(" .. digest(k .. "\0" .. m) .. ")" end,
  ctEquals = function(a, b) return a == b end,
}

local TIME = 0
local clock = function() return TIME end
meshctl.init({ crypto = fakeCrypto, serialize = serialize, clock = clock })

print("=== net.meshctl (mesh transport) Tests ===")
print()

-- ── seal / open round-trip ─────────────────────────────────────────
do
  local env = meshctl.compose({ from = "A", to = "B", svc = "mail",
    payload = { subject = "Hi", body = "secret stuff" }, secret = "k1", id = "s1" })
  test("sealed: payload removed from envelope", env.payload == nil)
  test("sealed: ciphertext present", type(env.sealed) == "string" and #env.sealed > 0)
  test("sealed: mac present", type(env.mac) == "string")
  eq("sealed: service stays in the CLEAR (relays route on it)", "mail", env.svc)
  local content, how = meshctl.openEnv(env, "k1")
  eq("open: how = sealed", "sealed", how)
  eq("open: payload round-trips (subject)", "Hi", content.subject)
  eq("open: payload round-trips (body)", "secret stuff", content.body)
end

-- ── tamper / wrong key / service re-binding are rejected ───────────
do
  local env = meshctl.compose({ from = "A", to = "B", svc = "mail",
    payload = { body = "x" }, secret = "k1", id = "s2" })
  local bad = meshctl.openEnv(env, "k2")
  test("wrong key -> nil", bad == nil)

  local t1 = {} for k, v in pairs(env) do t1[k] = v end
  t1.sealed = t1.sealed .. "!"
  test("tampered ciphertext -> nil", meshctl.openEnv(t1, "k1") == nil)

  -- The MAC binds the SERVICE too: a captured mail blob can't be
  -- re-stapled onto a chat envelope to fool a different handler.
  local t2 = {} for k, v in pairs(env) do t2[k] = v end
  t2.svc = "chat"
  test("service re-binding -> nil (MAC covers svc)", meshctl.openEnv(t2, "k1") == nil)
end

-- ── plaintext (no secret) still round-trips, flagged honestly ──────
do
  local env = meshctl.compose({ from = "A", to = "B", svc = "chat",
    payload = { body = "open text" }, id = "p1" })
  test("plaintext: no sealed blob", env.sealed == nil)
  local content, how = meshctl.openEnv(env, nil)
  eq("plaintext: how = plaintext", "plaintext", how)
  eq("plaintext: payload readable", "open text", content.body)
end

-- ── #SEC refuse-plaintext at the transport ─────────────────────────
do
  local sent = {}
  local ctl = meshctl.new({ myAddr = "A", clock = clock,
    broadcast = function(e) sent[#sent + 1] = e end,
    secretFor = function(p) return p == "PAIRED" and "k" or nil end })

  local id, err = ctl:send({ svc = "mail", to = "UNPAIRED", payload = { body = "hi" } })
  test("unicast with no shared secret is REFUSED", id == nil)
  test("refusal explains how to fix it",
    type(err) == "string" and err:find("pair") ~= nil)
  eq("refused send put nothing on the wire", 0, #sent)

  local id2 = ctl:send({ svc = "mail", to = "UNPAIRED", payload = { body = "hi" },
    allowPlaintext = true })
  test("explicit allowPlaintext sends", id2 ~= nil)

  local id3, err3 = ctl:send({ svc = "mail", to = "*", payload = { body = "all" } })
  test("broadcast without the flag is REFUSED (can't be sealed)", id3 == nil)
  test("broadcast refusal says why",
    type(err3) == "string" and err3:find("seal") ~= nil)
  test("broadcast WITH the flag sends",
    ctl:send({ svc = "mail", to = "*", payload = { body = "all" },
      allowPlaintext = true }) ~= nil)

  local id4, err4 = ctl:send({ to = "PAIRED", payload = {} })
  test("send without a service kind is refused", id4 == nil)
  test("missing-svc refusal explains", type(err4) == "string" and err4:find("svc") ~= nil)

  eq("a sealed send to a PAIRED peer reports sealed=true", true,
    select(2, ctl:send({ svc = "mail", to = "PAIRED", payload = { body = "hi" } })))
end

-- ── service multiplexing: handlers only see their own kind ─────────
do
  local sent = {}
  local ctl = meshctl.new({ myAddr = "ME", clock = clock,
    broadcast = function(e) sent[#sent + 1] = e end,
    secretFor = function() return "k" end })
  local gotMail, gotChat = {}, {}
  ctl:on("mail", function(m) gotMail[#gotMail + 1] = m; return true end)
  ctl:on("chat", function(m) gotChat[#gotChat + 1] = m; return true end)

  local function arrive(svc, id, body)
    ctl:onPacket(meshctl.compose({ from = "PEER", to = "ME", svc = svc,
      payload = { body = body }, secret = "k", id = id }))
  end
  arrive("mail", "m1", "a letter")
  arrive("chat", "c1", "a line")

  eq("mail handler got exactly its own message", 1, #gotMail)
  eq("chat handler got exactly its own message", 1, #gotChat)
  eq("mail payload arrived intact", "a letter", gotMail[1].payload.body)
  eq("chat payload arrived intact", "a line", gotChat[1].payload.body)
  test("registration is queryable", ctl:hasHandler("mail") and not ctl:hasHandler("ftp"))

  -- Unregistering stops delivery (an uninstalled add-on).
  ctl:off("mail")
  arrive("mail", "m2", "after uninstall")
  eq("after off(): no further delivery", 1, #gotMail)
end

-- ── ACK only when a service actually ACCEPTED the message ──────────
do
  local sent = {}
  local ctl = meshctl.new({ myAddr = "ME", clock = clock,
    broadcast = function(e) sent[#sent + 1] = e end,
    secretFor = function() return "k" end })

  -- No handler at all (add-on not installed): must NOT ACK — the sender
  -- keeps retrying, which is honest: nothing stored it here.
  ctl:onPacket(meshctl.compose({ from = "PEER", to = "ME", svc = "mail",
    payload = { body = "x" }, secret = "k", id = "n1" }))
  eq("no handler -> nothing ACKed", 0, #sent)

  -- Handler that refuses (storage full / duplicate): still no ACK.
  ctl:on("mail", function() return false end)
  ctl:onPacket(meshctl.compose({ from = "PEER", to = "ME", svc = "mail",
    payload = { body = "x" }, secret = "k", id = "n2" }))
  eq("refusing handler -> nothing ACKed", 0, #sent)

  -- Handler that accepts: exactly one ACK goes out.
  ctl:on("mail", function() return true end)
  ctl:onPacket(meshctl.compose({ from = "PEER", to = "ME", svc = "mail",
    payload = { body = "x" }, secret = "k", id = "n3" }))
  eq("accepting handler -> one ACK", 1, #sent)
  eq("the ACK is an ack envelope", "ack", sent[1] and sent[1].kind)
  eq("the ACK names the delivered id", "n3", sent[1] and sent[1].ackId)

  -- A throwing handler is contained (no ACK, no crash).
  ctl:on("mail", function() error("boom") end)
  local okCall = pcall(function()
    ctl:onPacket(meshctl.compose({ from = "PEER", to = "ME", svc = "mail",
      payload = { body = "x" }, secret = "k", id = "n4" }))
  end)
  test("a throwing handler doesn't crash the transport", okCall)
  eq("a throwing handler doesn't ACK", 1, #sent)
end

-- ── 3-node A — B — C: sealed delivery through a BLIND relay ────────
-- `links` is an adjacency map (broadcast reaches immediate neighbours
-- only); `secrets` is keyed "X>Y" = the secret X uses to talk to Y.
local function buildNet(links, secrets)
  local ctl, got = {}, {}
  local queue = {}
  for node in pairs(links) do got[node] = {} end
  for node in pairs(links) do
    ctl[node] = meshctl.new({
      myAddr = node,
      clock = clock,
      broadcast = function(env)
        for _, nb in ipairs(links[node]) do queue[#queue + 1] = { nb, env } end
      end,
      secretFor = function(peer) return secrets[node .. ">" .. peer] end,
    })
    local this = node
    ctl[node]:on("mail", function(m)
      -- De-dup like a real mailbox would, so "delivered exactly once" is
      -- a property of the transport and not of a permissive stub.
      for _, x in ipairs(got[this]) do if x.id == m.id then return false end end
      got[this][#got[this] + 1] = m
      return true
    end)
  end
  local function drain()
    local guard = 0
    while #queue > 0 and guard < 5000 do
      guard = guard + 1
      local it = table.remove(queue, 1)
      ctl[it[1]]:onPacket(it[2])
    end
    return guard
  end
  return ctl, got, drain, function() return #queue end
end

do
  local links = { A = { "B" }, B = { "A", "C" }, C = { "B" } }
  local secrets = { ["A>C"] = "AC", ["C>A"] = "AC" }   -- B holds no key
  local ctl, got, drain = buildNet(links, secrets)

  local id, sealed = ctl.A:send({ svc = "mail", to = "C",
    fromUser = "alice", user = "carol",
    payload = { subject = "Hello C", body = "across the mesh" } })
  test("send reports it sealed", sealed == true)
  eq("A has 1 pending before delivery", 1, ctl.A:pending())
  drain()

  eq("C delivered exactly once", 1, #got.C)
  eq("B never delivered (relay only)", 0, #got.B)
  eq("A never delivered its own message", 0, #got.A)
  local cm = got.C[1]
  test("C received the message", cm ~= nil)
  eq("C could OPEN it (endpoint holds the key)", true, cm and cm.readable)
  eq("payload survived the relay hop", "across the mesh", cm and cm.payload.body)
  eq("subject survived too", "Hello C", cm and cm.payload.subject)
  eq("recipient username carried", "carol", cm and cm.user)
  eq("ACK cleared A's outbox", 0, ctl.A:pending())
end

-- Blind relay: B must not be able to read what it forwards.
do
  local links = { A = { "B" }, B = { "A", "C" }, C = { "B" } }
  local secrets = { ["A>C"] = "AC", ["C>A"] = "AC", ["B>A"] = "WRONG", ["B>C"] = "WRONG" }
  local ctl, got, drain = buildNet(links, secrets)
  local seenAtB = nil
  ctl.B:on("mail", function(m) seenAtB = m; return true end)   -- B tries to read
  ctl.A:send({ svc = "mail", to = "C", payload = { body = "for C only" } })
  drain()
  test("relay B never had it delivered (not addressed to B)", seenAtB == nil)
  eq("C still got it", 1, #got.C)
  eq("C read it correctly", "for C only", got.C[1] and got.C[1].payload.body)
end

-- Retry: an offline C means the origin keeps the message pending and
-- re-floods when the retry window comes.
do
  local links = { A = { "B" }, B = { "A" } }               -- C absent
  local ctl, _, drain = buildNet(links, { ["A>C"] = "AC" })
  ctl.A:send({ svc = "mail", to = "C", payload = { body = "nobody home" } })
  drain()
  eq("undelivered message stays pending", 1, ctl.A:pending())
  local floods = 0
  local ctl2 = meshctl.new({ myAddr = "A", clock = clock,
    broadcast = function() floods = floods + 1 end,
    secretFor = function() return "k" end })
  ctl2:send({ svc = "mail", to = "C", payload = { body = "x" } })
  eq("initial flood", 1, floods)
  TIME = TIME + mesh.RETRY_EVERY + 1
  ctl2:tick()
  eq("re-flooded after the retry interval", 2, floods)
  TIME = 0
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
