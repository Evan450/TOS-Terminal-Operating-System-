-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Network - Mesh Router (store-and-forward core)       ║
-- ║                                                            ║
-- ║  The engine behind mesh email. There is NO central mail   ║
-- ║  server and NO routing table: a node only knows its       ║
-- ║  immediate radio neighbours. Messages reach a destination ║
-- ║  several hops away by CONTROLLED FLOODING — each node      ║
-- ║  re-broadcasts a message it hasn't seen before, decaying a ║
-- ║  hop budget (TTL) so it can't circulate forever, and       ║
-- ║  de-duplicating by message id so loops collapse.           ║
-- ║                                                            ║
-- ║  Reliability is STORE-AND-FORWARD: the origin keeps a copy ║
-- ║  in an outbox and re-floods it on a timer until an ACK     ║
-- ║  (itself flooded back the same way) arrives or a wall-     ║
-- ║  clock deadline passes. An intermediate node that happens  ║
-- ║  to relay a message also holds it briefly, so a recipient  ║
-- ║  that blinks back online still gets a re-flood.            ║
-- ║                                                            ║
-- ║  This module is PURE: no component/computer/securefs deps. ║
-- ║  The net layer feeds it ids, timestamps and an "is this    ║
-- ║  for me?" predicate; everything here is unit-testable.     ║
-- ╚══════════════════════════════════════════════════════════╝

local mesh = {}

mesh.DEFAULT_TTL   = 8     -- max hops a message may travel before it dies
mesh.SEEN_MAX      = 512   -- distinct message ids remembered for dedup
mesh.RETRY_EVERY   = 30    -- seconds between origin re-floods (default)
mesh.RELAY_HOLD    = 120   -- seconds a relay keeps a passed-through copy
mesh.BROADCAST     = "*"   -- `to` value meaning "everyone on the mesh"

-- ============================================================
-- Envelopes
-- ============================================================
-- An envelope is a plain table safe to serialize onto the wire:
--   id       unique message id (the net layer supplies it)
--   kind     "mail" | "ack"
--   from     origin node address          to      destination node addr | "*"
--   fromUser optional sender username      user    optional recipient username
--   subject  short line                    body    message text
--   ttl      remaining hop budget          path    node addrs already traversed
--   ts       origin timestamp (caller-stamped; the pure layer never clocks)
--   ackId    (kind=="ack") the id being acknowledged

--- Build a fresh outbound envelope. `id` MUST be unique per message; the
--- net layer derives it from (boot epoch + a monotonic counter). Falls
--- back to from#seq so the pure tests can build deterministic ids.
function mesh.newEnvelope(from, to, fields)
  fields = fields or {}
  return {
    id       = fields.id or (tostring(from) .. "#" .. tostring(fields.seq or 0)),
    kind     = fields.kind or "mail",
    from     = from,
    to       = to or mesh.BROADCAST,
    fromUser = fields.fromUser,
    user     = fields.user,
    subject  = fields.subject or "",
    body     = fields.body or "",
    ttl      = fields.ttl or mesh.DEFAULT_TTL,
    path     = fields.path or {},
    ts       = fields.ts,
    ackId    = fields.ackId,
  }
end

--- Build the ACK an origin expects back once delivery succeeds. The ACK
--- floods back addressed to the original sender's node.
function mesh.newAck(env, selfAddr, fields)
  fields = fields or {}
  return mesh.newEnvelope(selfAddr, env.from, {
    id    = fields.id or ("ack:" .. tostring(env.id)),
    kind  = "ack",
    ackId = env.id,
    ttl   = fields.ttl or mesh.DEFAULT_TTL,
    ts    = fields.ts,
  })
end

-- ============================================================
-- Seen-id cache (dedup / loop collapse)
-- ============================================================

function mesh.newSeen(max)
  return { set = {}, order = {}, max = max or mesh.SEEN_MAX }
end

--- Record `id`; return true if it had been seen before (a duplicate).
--- Evicts the oldest id once the cache is full so memory stays bounded.
function mesh.sawBefore(seen, id)
  if id == nil then return false end
  if seen.set[id] then return true end
  seen.set[id] = true
  seen.order[#seen.order + 1] = id
  if #seen.order > seen.max then
    local old = table.remove(seen.order, 1)
    if old ~= nil then seen.set[old] = nil end
  end
  return false
end

-- ============================================================
-- Routing decision
-- ============================================================

--- True if `addr` already appears in the envelope's traversed path.
function mesh.inPath(env, addr)
  for _, a in ipairs(env.path or {}) do if a == addr then return true end end
  return false
end

-- Copy an envelope for forwarding: spend one hop and append ourselves to
-- the path. EVERY field is carried unchanged — critically the sealed
-- content blob (sealed/mac/nonce/encMethod) the mail layer adds, which a
-- relay must pass through intact even though it can't read it. A relay
-- that copied only a known subset would silently strip the ciphertext.
local function copyForward(env, selfAddr)
  local out = {}
  for k, v in pairs(env) do out[k] = v end
  local path = {}
  for i, a in ipairs(env.path or {}) do path[i] = a end
  path[#path + 1] = selfAddr
  out.path = path
  out.ttl = (env.ttl or 0) - 1
  return out
end

--- Decide what a node at `selfAddr` should do with an arriving envelope.
--- `isForMe(env)` -> bool: the net layer resolves whether env.to targets
--- this node (its address, hostname, or an alias of it). `seen` is this
--- node's dedup cache.
---
--- Returns { dup, deliver, forward, out } where:
---   dup     this id was already processed (everything else false)
---   deliver hand the message to the local mailbox / ack handler
---   forward re-broadcast `out` (ttl already spent, path extended)
---   out     the envelope to re-broadcast (only when forward is true)
function mesh.route(env, selfAddr, isForMe, seen)
  if type(env) ~= "table" or env.id == nil then
    return { dup = false, deliver = false, forward = false }
  end
  if mesh.sawBefore(seen, env.id) then
    return { dup = true, deliver = false, forward = false }
  end

  local broadcast = (env.to == mesh.BROADCAST or env.to == nil)
  local mine = broadcast or (isForMe and isForMe(env)) or false
  local res = { dup = false, deliver = mine, forward = false }

  -- A unicast message that reached its destination stops here; no point
  -- flooding it onward. Broadcasts keep propagating so everyone hears them.
  if mine and not broadcast then
    return res
  end

  -- Otherwise relay it, if it has hops left and we'd not be revisiting a
  -- node already on its path (dedup handles loops too, but this keeps a
  -- message from bouncing straight back the way it came).
  if (env.ttl or 0) > 0 and not mesh.inPath(env, selfAddr) then
    res.forward = true
    res.out = copyForward(env, selfAddr)
  end
  return res
end

-- ============================================================
-- Store-and-forward outbox (origin reliability + relay hold)
-- ============================================================

function mesh.newOutbox()
  return { items = {} }
end

--- Queue an envelope for retry. `opts`:
---   interval  seconds between re-floods (default RETRY_EVERY)
---   deadline  absolute time after which we give up (default: never)
---   relay     true if we're only holding a passed-through copy (shorter
---             default deadline so relays don't hoard forever)
--- `now` stamps the first attempt window. A second enqueue of the same id
--- is ignored (keeps the original schedule).
function mesh.enqueue(ob, env, opts, now)
  opts = opts or {}
  if ob.items[env.id] then return false end
  now = now or 0
  local interval = opts.interval or mesh.RETRY_EVERY
  local deadline = opts.deadline
  if deadline == nil and opts.relay then deadline = now + mesh.RELAY_HOLD end
  ob.items[env.id] = {
    env = env, tries = 0, nextAt = now, interval = interval,
    deadline = deadline, relay = opts.relay or false,
  }
  return true
end

--- An ACK arrived (or we delivered locally): stop retrying this id.
function mesh.ack(ob, id)
  if id == nil then return false end
  local had = ob.items[id] ~= nil
  ob.items[id] = nil
  return had
end

--- Return the envelopes due for (re-)flooding at time `now`, advancing
--- their schedules, and drop any past their deadline. Caller broadcasts
--- whatever this returns.
function mesh.due(ob, now)
  now = now or 0
  local out = {}
  for id, it in pairs(ob.items) do
    if it.deadline ~= nil and now >= it.deadline then
      ob.items[id] = nil
    elseif now >= it.nextAt then
      it.tries = it.tries + 1
      it.nextAt = now + it.interval
      out[#out + 1] = it.env
    end
  end
  return out
end

--- How many messages are still awaiting delivery (diagnostics / `mail` UI).
function mesh.pending(ob)
  local n = 0
  for _ in pairs(ob.items) do n = n + 1 end
  return n
end

return mesh
