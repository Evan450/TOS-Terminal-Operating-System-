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
mesh.RETRY_EVERY   = 30    -- seconds between an origin's probes (and relay re-floods)
mesh.RELAY_HOLD    = 120   -- seconds a relay keeps a passed-through copy
mesh.BROADCAST     = "*"   -- `to` value meaning "everyone on the mesh"

--! #SEC / #MEM (pentest, Sep 2026) — what a neighbour sends is bounded
--! before it is kept. Mesh traffic comes only from TRUSTED neighbours, but
--! every relay forwards to its own, so one bad node anywhere reaches every
--! relay. Nothing capped the relay holds: 40 unique 7 KB envelopes a
--! second for two minutes left a relay holding 3840 of them -- 28 MB --
--! and re-flooding them 13440 times. The dedup cache kept 512 ids of any
--! length (7 KB ids: 3.5 MB), and a ttl of 1e9 was honoured.
--!   * An id is a short string, a path a short list, and ttl a number,
--!     clamped to MAX_TTL. Anything else is dropped unrouted.
--!   * A relay holds at most RELAY_HOLD_MAX copies (the oldest goes). How
--!     big a copy it will hold is the caller's to say (meshctl: whatever
--!     free memory allows); without one, none bigger than RELAY_HOLD_BYTES.
--!     An envelope carrying a plaintext payload table is never held. The
--!     ORIGIN's own copies are untouched -- the origin is what retries.
--! (test_mesh_bounds.lua, test_mesh_reliability.lua)
mesh.MAX_ID           = 96       -- longest message id accepted (real ones are ~55)
mesh.MAX_TTL          = 16       -- hop-budget ceiling
mesh.RELAY_HOLD_MAX   = 8        -- relayed copies held at once
mesh.RELAY_HOLD_BYTES = 4096     -- largest copy held when no memory probe says more
mesh.MAX_RESEND       = 1000000  -- ceiling on an envelope's resend counter

-- ============================================================
-- Envelopes
-- ============================================================
-- An envelope is a plain table safe to serialize onto the wire:
--   id       unique message id (the net layer supplies it)
--   kind     "msg" | "ack" | "probe" | "want"
--   from     origin node address          to      destination node addr | "*"
--   fromUser optional sender username      user    optional recipient username
--   subject  short line                    body    message text
--   ttl      remaining hop budget          path    node addrs already traversed
--   ts       origin timestamp (caller-stamped; the pure layer never clocks)
--   ackId    (kind=="ack") the id being acknowledged
--   probeId  (kind=="probe") "do you have this id?"
--   wantId   (kind=="want") "I do not have this id -- send it"
--   rs       resend counter: a re-sent message floods under a new dedup key
--            (see seenKey) while keeping its id

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

--- The dedup key of an envelope: its id, plus its resend counter when it
--- has one. A sender re-sending a message bumps the counter, so relays that
--- saw the first flood pass the re-send on; the RECEIVER dedups delivery by
--- the id itself (meshctl's delivered set).
function mesh.seenKey(env)
  if env.rs == nil then return env.id end
  return env.id .. "#" .. tostring(math.floor(env.rs))
end

-- ============================================================
-- Routing decision
-- ============================================================

--- True if `addr` already appears in the envelope's traversed path.
function mesh.inPath(env, addr)
  for _, a in ipairs(env.path or {}) do if a == addr then return true end end
  return false
end

-- Hops an envelope may still travel: its ttl read as a number and clamped
-- to MAX_TTL. Missing or not a number is 0 -- deliverable, not relayed.
local function hopsOf(env)
  local t = tonumber(env.ttl) or 0
  if t > mesh.MAX_TTL then t = mesh.MAX_TTL end
  return t
end

-- An envelope worth routing at all (see MAX_ID above).
local function wellFormed(env)
  if type(env) ~= "table" then return false end
  if type(env.id) ~= "string" or #env.id > mesh.MAX_ID then return false end
  local p = env.path
  if p ~= nil and (type(p) ~= "table" or #p > mesh.MAX_TTL * 2) then return false end
  local rs = env.rs
  if rs ~= nil and (type(rs) ~= "number" or rs < 0 or rs > mesh.MAX_RESEND) then return false end
  return true
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
  out.ttl = hopsOf(env) - 1
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
  if not wellFormed(env) then
    return { dup = false, deliver = false, forward = false }
  end
  if mesh.sawBefore(seen, mesh.seenKey(env)) then
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
  if hopsOf(env) > 0 and not mesh.inPath(env, selfAddr) then
    res.forward = true
    res.out = copyForward(env, selfAddr)
  end
  return res
end

-- ============================================================
-- Store-and-forward outbox (origin reliability + relay hold)
-- ============================================================

function mesh.newOutbox()
  return { items = {}, seq = 0 }
end

-- What holding a relayed copy would pin: its strings and its path. A table
-- anywhere else is a plaintext payload of any size, so it is never held.
local function envBytes(env)
  local n = 0
  for k, v in pairs(env) do
    if type(v) == "string" then n = n + #v
    elseif type(v) == "table" then
      if k ~= "path" then return math.huge end
      n = n + #v * 48
    end
  end
  return n
end
mesh._envBytes = envBytes   -- test hook

--- Queue an envelope for retry. `opts`:
---   interval  seconds between re-floods (default RETRY_EVERY)
---   deadline  absolute time after which we give up (default: never)
---   relay     true if we're only holding a passed-through copy (shorter
---             default deadline so relays don't hoard forever)
---   canHold   (relay) function(bytes) -> may this node hold that much more?
---             Default: no more than RELAY_HOLD_BYTES.
--- `now` stamps the first attempt window. A second enqueue of the same id
--- is ignored (keeps the original schedule). A relay copy is held only if
--- it fits, and only the newest RELAY_HOLD_MAX are (see above).
function mesh.enqueue(ob, env, opts, now)
  opts = opts or {}
  if ob.items[env.id] then return false end
  now = now or 0
  if opts.relay then
    local bytes = envBytes(env)
    local fits
    if bytes == math.huge then fits = false
    elseif opts.canHold then fits = opts.canHold(bytes) and true or false
    else fits = bytes <= mesh.RELAY_HOLD_BYTES end
    if not fits then return false end
    local count, oldest = 0, nil
    for id, it in pairs(ob.items) do
      if it.relay then
        count = count + 1
        if not oldest or (it.order or 0) < (ob.items[oldest].order or 0) then oldest = id end
      end
    end
    if count >= mesh.RELAY_HOLD_MAX and oldest then ob.items[oldest] = nil end
  end
  ob.seq = (ob.seq or 0) + 1
  local interval = opts.interval or mesh.RETRY_EVERY
  local deadline = opts.deadline
  if deadline == nil and opts.relay then deadline = now + mesh.RELAY_HOLD end
  ob.items[env.id] = {
    env = env, tries = 0, nextAt = now, interval = interval,
    deadline = deadline, relay = opts.relay or false, order = ob.seq,
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

--- A passing ACK: a relay copy of what it acknowledges need not be
--- re-flooded. Never an origin's own copy -- that takes an ACK the origin
--- can verify (meshctl), not anything that merely says "ack".
function mesh.ackRelay(ob, id)
  local it = id ~= nil and ob.items[id]
  if it and it.relay then ob.items[id] = nil; return true end
  return false
end

--- Drop relay copies, oldest first, until at most `keep` remain. Returns how
--- many went. They are a courtesy, so memory pressure takes them first.
function mesh.shedRelays(ob, keep)
  keep = keep or 0
  local relays = {}
  for id, it in pairs(ob.items) do
    if it.relay then relays[#relays + 1] = { id, it.order or 0 } end
  end
  table.sort(relays, function(a, b) return a[2] < b[2] end)
  local n = 0
  for i = 1, #relays - keep do ob.items[relays[i][1]] = nil; n = n + 1 end
  return n
end

--- The outbox entries due at time `now`, their schedules advanced; any past
--- their deadline are dropped. Returns (items, droppedCount).
function mesh.dueItems(ob, now)
  now = now or 0
  local out, dropped = {}, 0
  for id, it in pairs(ob.items) do
    if it.deadline ~= nil and now >= it.deadline then
      ob.items[id] = nil
      dropped = dropped + 1
    elseif now >= it.nextAt then
      it.tries = it.tries + 1
      it.nextAt = now + it.interval
      out[#out + 1] = it
    end
  end
  return out, dropped
end

--- Return the envelopes due for (re-)flooding at time `now`, advancing
--- their schedules, and drop any past their deadline. Caller broadcasts
--- whatever this returns.
function mesh.due(ob, now)
  local items = mesh.dueItems(ob, now)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.env end
  return out
end

--- How many messages are still awaiting delivery (diagnostics / `mail` UI).
function mesh.pending(ob)
  local n = 0
  for _ in pairs(ob.items) do n = n + 1 end
  return n
end

return mesh
