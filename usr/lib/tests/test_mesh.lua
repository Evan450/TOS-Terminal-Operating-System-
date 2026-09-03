-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: net.mesh (store-and-forward router)     ║
-- ║                                                            ║
-- ║  Exercises the pure engine — envelopes, the dedup cache,   ║
-- ║  the per-node route() decision, the retry outbox — and     ║
-- ║  then simulates a real 4-node line topology to prove a     ║
-- ║  message floods from one end to the other with no routing  ║
-- ║  table, dying after delivery instead of circulating.       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mesh.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local mesh = require("kernel.net.mesh")

print("=== net.mesh Tests ===")
print()

-- ── Envelopes ──────────────────────────────────────────────────────
local e = mesh.newEnvelope("A", "C", { id = "m1", subject = "hi", body = "yo", ttl = 5 })
eq("envelope keeps id", "m1", e.id)
eq("envelope default kind = mail", "mail", e.kind)
eq("envelope to", "C", e.to)
eq("envelope ttl", 5, e.ttl)
test("envelope path starts empty", #e.path == 0)
local b = mesh.newEnvelope("A", nil)
eq("nil to -> broadcast", mesh.BROADCAST, b.to)
local ack = mesh.newAck(e, "C")
eq("ack kind", "ack", ack.kind)
eq("ack targets the origin", "A", ack.to)
eq("ack references the id", "m1", ack.ackId)

-- ── Seen cache: dedup + bounded eviction ───────────────────────────
local seen = mesh.newSeen(3)
eq("first sight is not a dup", false, mesh.sawBefore(seen, "x"))
eq("second sight is a dup", true, mesh.sawBefore(seen, "x"))
mesh.sawBefore(seen, "y"); mesh.sawBefore(seen, "z")
mesh.sawBefore(seen, "w")          -- evicts oldest ("x")
eq("evicted id is forgotten (not a dup again)", false, mesh.sawBefore(seen, "x"))
test("cache stays bounded", #seen.order <= 3)

-- ── route(): deliver to me, stop flooding ──────────────────────────
do
  local s = mesh.newSeen()
  local env = mesh.newEnvelope("A", "B", { id = "d1", ttl = 4 })
  local r = mesh.route(env, "B", function() return true end, s)
  test("addressed to me -> deliver", r.deliver)
  test("unicast at destination -> no forward", not r.forward)
  test("not a dup", not r.dup)
end

-- ── route(): not for me, forward with ttl-1 + path append ──────────
do
  local s = mesh.newSeen()
  local env = mesh.newEnvelope("A", "C", { id = "f1", ttl = 4 })
  local r = mesh.route(env, "B", function() return false end, s)
  test("not for me -> no deliver", not r.deliver)
  test("not for me -> forward", r.forward)
  eq("forward spends one hop", 3, r.out.ttl)
  eq("forward appends self to path", "B", r.out.path[#r.out.path])
  eq("forwarded id unchanged", "f1", r.out.id)
end

-- ── route(): duplicate is dropped ──────────────────────────────────
do
  local s = mesh.newSeen()
  local env = mesh.newEnvelope("A", "C", { id = "dup1", ttl = 4 })
  mesh.route(env, "B", function() return false end, s)       -- first sight
  local r = mesh.route(env, "B", function() return false end, s)  -- again
  test("second sight -> dup", r.dup)
  test("dup -> no deliver, no forward", not r.deliver and not r.forward)
end

-- ── route(): ttl exhausted -> deliverable but not forwarded ────────
do
  local s = mesh.newSeen()
  local env = mesh.newEnvelope("A", "C", { id = "t0", ttl = 0 })
  local r = mesh.route(env, "B", function() return false end, s)
  test("ttl 0 -> not forwarded", not r.forward)
end

-- ── route(): broadcast delivers AND keeps flooding ─────────────────
do
  local s = mesh.newSeen()
  local env = mesh.newEnvelope("A", mesh.BROADCAST, { id = "bc1", ttl = 4 })
  local r = mesh.route(env, "B", function() return false end, s)
  test("broadcast -> deliver locally", r.deliver)
  test("broadcast -> still forward", r.forward)
end

-- ── route(): loop guard — self already on path -> no forward ───────
do
  local s = mesh.newSeen()
  local env = mesh.newEnvelope("A", "C", { id = "lp1", ttl = 4, path = { "B" } })
  local r = mesh.route(env, "B", function() return false end, s)
  test("self in path -> no forward", not r.forward)
end

-- ── Outbox: enqueue / due / ack / deadline / relay hold ────────────
do
  local ob = mesh.newOutbox()
  local env = mesh.newEnvelope("A", "C", { id = "o1", ttl = 4 })
  mesh.enqueue(ob, env, { interval = 30 }, 0)
  eq("pending after enqueue", 1, mesh.pending(ob))
  local d0 = mesh.due(ob, 0)
  eq("due immediately on enqueue", 1, #d0)
  local d1 = mesh.due(ob, 5)
  eq("not due again before interval", 0, #d1)
  local d2 = mesh.due(ob, 30)
  eq("due again after interval", 1, #d2)
  test("ack stops retries", mesh.ack(ob, "o1"))
  eq("pending after ack", 0, mesh.pending(ob))
  eq("nothing due after ack", 0, #mesh.due(ob, 100))

  -- duplicate enqueue keeps original schedule
  mesh.enqueue(ob, env, { interval = 30 }, 0)
  test("re-enqueue same id is ignored", not mesh.enqueue(ob, env, { interval = 30 }, 0))

  -- deadline drops the message
  local ob2 = mesh.newOutbox()
  mesh.enqueue(ob2, mesh.newEnvelope("A", "C", { id = "dl", ttl = 4 }),
    { interval = 10, deadline = 50 }, 0)
  mesh.due(ob2, 60)
  eq("past deadline -> dropped", 0, mesh.pending(ob2))

  -- relay hold gives a default deadline
  local ob3 = mesh.newOutbox()
  mesh.enqueue(ob3, mesh.newEnvelope("A", "C", { id = "rl", ttl = 4 }),
    { relay = true }, 0)
  mesh.due(ob3, mesh.RELAY_HOLD + 1)
  eq("relay copy expires after RELAY_HOLD", 0, mesh.pending(ob3))
end

-- ── End-to-end: 4-node line A—B—C—D, A mails D ─────────────────────
-- Each node hears only its immediate neighbours. We flood and count how
-- many times D delivers (must be exactly once) and confirm B/C relay.
do
  local nodes = { "A", "B", "C", "D" }
  local neighbours = { A = { "B" }, B = { "A", "C" }, C = { "B", "D" }, D = { "C" } }
  local seenOf = { A = mesh.newSeen(), B = mesh.newSeen(), C = mesh.newSeen(), D = mesh.newSeen() }
  local delivered = { A = 0, B = 0, C = 0, D = 0 }
  local relayed   = { A = 0, B = 0, C = 0, D = 0 }
  local isForMe = function(self) return function(env) return env.to == self end end

  -- A simple synchronous flood queue: {node, env} work items.
  local queue = {}
  local function broadcastFrom(node, env)
    for _, nb in ipairs(neighbours[node]) do queue[#queue + 1] = { nb, env } end
  end

  local origin = mesh.newEnvelope("A", "D", { id = "e2e", ttl = mesh.DEFAULT_TTL })
  broadcastFrom("A", origin)

  local guard = 0
  while #queue > 0 and guard < 1000 do
    guard = guard + 1
    local item = table.remove(queue, 1)
    local node, env = item[1], item[2]
    local r = mesh.route(env, node, isForMe(node), seenOf[node])
    if r.deliver then delivered[node] = delivered[node] + 1 end
    if r.forward then relayed[node] = relayed[node] + 1; broadcastFrom(node, r.out) end
  end

  eq("D delivered exactly once", 1, delivered.D)
  eq("A never delivered (it's the origin)", 0, delivered.A)
  test("B relayed the message", relayed.B >= 1)
  test("C relayed the message", relayed.C >= 1)
  test("flood terminated (no runaway loop)", guard < 1000)
  eq("D did not re-flood past the destination", 0, relayed.D)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
