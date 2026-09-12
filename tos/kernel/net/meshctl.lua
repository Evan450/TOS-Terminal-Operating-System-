-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Network - Mesh Transport Controller                   ║
-- ║                                                            ║
-- ║  Stage 5: the mesh is part of the INTEGRATED network, not  ║
-- ║  mail's private plumbing. This controller multiplexes any  ║
-- ║  number of SERVICES over one flood mesh: an envelope       ║
-- ║  carries a service name (`svc` — "mail", "chat", ...) and  ║
-- ║  an arbitrary payload TABLE, sealed end-to-end; services   ║
-- ║  register a delivery handler per svc via on()/off(). Mail  ║
-- ║  (an Extras package) is just the first tenant.             ║
-- ║                                                            ║
-- ║  Generalized from the old mailctl + the seal/ingest half   ║
-- ║  of net/mail.lua (mailbox semantics moved to the mail      ║
-- ║  package). Same reliability model: controlled flooding     ║
-- ║  (net/mesh.lua), store-and-forward retry until ACKed, a    ║
-- ║  per-second relay budget, TRUSTED-only hops at the trust   ║
-- ║  gate, blind relays (sealed payload rides through intact). ║
-- ║                                                            ║
-- ║  #SEC (review holdover, now at the TRANSPORT level):       ║
-- ║  REFUSE-PLAINTEXT BY DEFAULT. A unicast send with no       ║
-- ║  shared secret is an ERROR unless the caller passes        ║
-- ║  allowPlaintext — mesh messages are relayed by third       ║
-- ║  parties, so "silently ship it readable" was a footgun.    ║
-- ║  Broadcasts ("*") are inherently unsealable and likewise   ║
-- ║  need the explicit flag.                                   ║
-- ║                                                            ║
-- ║  Injected primitives (broadcast/secretFor/clock) keep it   ║
-- ║  unit-testable exactly like mailctl was.                   ║
-- ╚══════════════════════════════════════════════════════════╝

local mesh = require("kernel.net.mesh")

local meshctl = {}
meshctl.__index = meshctl

meshctl.RELAY_BUDGET = 32     -- max relays per second through this node
meshctl.MAX_PAYLOAD  = 8192   -- serialized payload cap (pre-seal)

--! Reliability (Sep 2026: the operator's design, after the relay-flood fix).
--!   * A relay keeps up to mesh.RELAY_HOLD_MAX passed-through copies while it
--!     has the memory for them, and sheds them, oldest first, as soon as free
--!     memory falls under RELAY_FLOOR. They are a courtesy, never a promise.
--!   * The SENDER is the one that promises. It keeps its own copy until the
--!     receiver acknowledges it, and instead of re-flooding the whole message
--!     every retry window it floods a small PROBE ("do you have <id>?"). The
--!     receiver answers ACK if it has it and WANT if it never saw it. Only a
--!     WANT -- or FULL_EVERY probes with no answer, which is also how an
--!     older node that ignores probes still gets its mail -- sends the whole
--!     message again, under a new resend counter so that relays which saw the
--!     first flood pass it on (mesh.seenKey).
--!   * An ACK or WANT about a sealed message carries a MAC under the secret
--!     the two ends share, so a node in between cannot say "delivered" for a
--!     message that was not, and leave it a ghost.
--!   * Both ends survive a reset: the sender's messages awaiting delivery and
--!     the receiver's recently delivered ids live in `store` (the kernel keeps
--!     them in /var/lib/mesh, admin-read-only). Message ids carry a per-boot
--!     prefix: they used to restart at the same numbers after a reboot, and a
--!     receiver that remembered the old ones dropped the new messages as
--!     duplicates.
--!   * Keeping its OWN side is enough for a node to hold a whole
--!     conversation: the other side is what it received.
--! (test_mesh_reliability.lua)
meshctl.RELAY_FLOOR   = 48 * 1024  -- free memory a relay keeps back from its holds
meshctl.FULL_EVERY    = 4          -- unanswered probes before the whole message again
meshctl.ORIGIN_MAX    = 16         -- our own messages awaiting delivery at once
meshctl.DELIVERED_MAX = 64         -- delivered ids remembered to answer probes
meshctl.ORIGIN_TTL    = 3600       -- seconds a sender keeps trying

-- Injected at init; defaulted so the pure logic still runs in tests.
local crypto, serialize, log
local clock = function() return 0 end

function meshctl.init(modules)
  modules   = modules or {}
  crypto    = modules.crypto
  serialize = modules.serialize or require("kernel.serialize")
  log       = modules.log
  if modules.clock then clock = modules.clock end
end

-- ============================================================
-- Sealing (end-to-end payload encryption, service-agnostic)
-- ============================================================

-- Move env.payload (a plain table) into an encrypted `sealed` blob bound
-- by a MAC. The envelope is mutated in place and returned. Routing fields
-- (id/from/to/svc/ttl/path) stay clear so blind relays can route it.
function meshctl.sealEnv(env, secret)
  if not (crypto and secret and secret ~= "") then
    env.sealed = nil
    return env
  end
  local plain = serialize.encode(env.payload or {})
  local ct, method = crypto.encrypt(plain, secret)
  local nonce = crypto.salt and crypto.salt(16) or ""
  env.sealed = ct
  env.encMethod = method
  env.nonce = nonce
  -- Bind id + endpoints + service so a captured blob can't be re-stapled
  -- onto a different envelope (or a different service) and replayed.
  env.mac = crypto.hmac(secret, table.concat({
    tostring(env.id), tostring(env.from), tostring(env.to),
    tostring(env.svc), method or "", nonce, ct }, "\0"))
  env.payload = nil          -- never ship plaintext alongside ciphertext
  return env
end

-- Decrypt a sealed envelope's payload with `secret`. Returns the payload
-- table on success, or nil + reason. A plaintext (unsealed) envelope
-- returns its payload as-is with how="plaintext".
function meshctl.openEnv(env, secret)
  if not env.sealed then
    return env.payload or {}, "plaintext"
  end
  if not (crypto and secret and secret ~= "") then
    return nil, "sealed but no secret"
  end
  local expect = crypto.hmac(secret, table.concat({
    tostring(env.id), tostring(env.from), tostring(env.to),
    tostring(env.svc), env.encMethod or "", env.nonce or "", env.sealed }, "\0"))
  local eq = crypto.ctEquals or function(a, b) return a == b end
  if not eq(expect, env.mac or "") then
    return nil, "MAC mismatch (tampered or wrong key)"
  end
  local plain = crypto.decrypt(env.sealed, secret, env.encMethod)
  if not plain then return nil, "decryption failed" end
  local ok, parsed = pcall(serialize.decode, plain, { maxBytes = meshctl.MAX_PAYLOAD + 512 })
  if not ok or type(parsed) ~= "table" then return nil, "corrupt sealed payload" end
  return parsed, "sealed"
end

-- The MAC on an ACK or WANT (see the reliability note above): the kind, the
-- message it answers and both endpoints, under the secret the ends share.
-- nil when they share none.
local function replyMac(secret, kind, msgId, from, to)
  if not (crypto and crypto.hmac and secret and secret ~= "") then return nil end
  return crypto.hmac(secret, table.concat({
    tostring(kind), tostring(msgId), tostring(from), tostring(to) }, "\0"))
end
meshctl._replyMac = replyMac   -- test hook

-- ============================================================
-- Compose
-- ============================================================

-- Build a ready-to-send envelope. `opts`:
--   from, to        node addresses ("*" / nil to = broadcast)
--   svc             service name ("mail", "chat", ...) — REQUIRED
--   fromUser, user  optional sender / recipient usernames
--   payload         plain table of service content
--   secret          shared secret with `to` (omit -> plaintext)
--   id, seq, ttl, ts  passed through to mesh.newEnvelope
function meshctl.compose(opts)
  opts = opts or {}
  local env = mesh.newEnvelope(opts.from, opts.to, {
    id = opts.id, seq = opts.seq, ttl = opts.ttl,
    fromUser = opts.fromUser, user = opts.user,
    ts = opts.ts or clock(),
    kind = "msg",
  })
  env.svc = opts.svc
  env.payload = opts.payload or {}
  return meshctl.sealEnv(env, opts.secret)
end

-- ============================================================
-- Ingest (the per-packet decision, service-agnostic)
-- ============================================================

-- Process an arriving envelope at `selfAddr` (mirrors the old mail.ingest).
-- Returns { dup, forward, out, deliver, kind, svc, message, ackId, ackTo }:
--   forward/out            re-broadcast `out`
--   deliver + kind=="msg"  dispatch `message` to the svc handler, then ACK
--                          it to `ackTo` (unicast only) once handled
--   deliver + kind=="ack" / "probe" / "want"  a reply about one of our
--                          messages, or a question about one we received
function meshctl.ingest(env, selfAddr, isForMe, seen, secretFor)
  local r = mesh.route(env, selfAddr, isForMe, seen)
  local act = { dup = r.dup, forward = r.forward, out = r.out, deliver = false }
  if r.dup or not r.deliver then return act end

  if env.kind == "ack" or env.kind == "probe" or env.kind == "want" then
    act.deliver = true
    act.kind = env.kind
    act.ackId = env.ackId
    return act
  end

  local secret = secretFor and secretFor(env.from) or nil
  local content, how = meshctl.openEnv(env, secret)
  act.deliver = true
  act.kind = "msg"
  act.svc = env.svc
  act.message = {
    id = env.id, from = env.from, fromUser = env.fromUser,
    to = env.to, user = env.user,
    payload = content,               -- nil when sealed-but-unopenable
    ts = env.ts, sealed = (env.sealed ~= nil),
    readable = (content ~= nil), how = how,
  }
  if not content and log then
    log.warn("mesh", "Delivered sealed '" .. tostring(env.svc) .. "' from "
      .. tostring(env.from):sub(1, 8) .. " could not be opened: " .. tostring(how))
  end
  -- Acknowledge unicast messages back to the origin (broadcasts aren't ACKed).
  if env.to ~= mesh.BROADCAST and env.to ~= nil then
    act.ackTo = env.from
  end
  return act
end

-- ============================================================
-- Live controller
-- ============================================================

-- A prefix for this boot's message ids (see the reliability note).
local function bootEpoch()
  local raw = crypto and crypto.salt and crypto.salt(4)
  if type(raw) == "string" and #raw >= 4 then
    return (raw:sub(1, 4):gsub(".", function(c) return string.format("%02x", c:byte()) end))
  end
  return string.format("%08x", math.floor((os.time and os.time() or 0) + clock() * 1000) % 0x100000000)
end

--- Create a controller. `deps`:
---   myAddr      string                       this node's modem address
---   broadcast   function(envelope)           flood an envelope to neighbours
---   secretFor   function(addr) -> secret|nil shared secret with a peer
---   clock       function() -> number         monotonic seconds
---   isForMe     function(env)  -> bool        (optional) does env.to target us
---   freeMemory  function() -> bytes           (optional) sizes the relay holds
---   store       { load = fn() -> state, save = fn(state) }  (optional)
---   log         table                         (optional)
function meshctl.new(deps)
  deps = deps or {}
  local self = setmetatable({}, meshctl)
  self.myAddr     = deps.myAddr
  self.broadcast  = deps.broadcast or function() end
  self.secretFor  = deps.secretFor or function() return nil end
  self.clock      = deps.clock or function() return 0 end
  self.log        = deps.log
  self.isForMe    = deps.isForMe or function(env)
    return env.to == self.myAddr
  end
  self.freeMemory = deps.freeMemory
  self.store      = deps.store
  self.seen       = mesh.newSeen()
  self.outbox     = mesh.newOutbox()
  self.delivered  = { set = {}, order = {} }
  self._handlers  = {}          -- svc name -> fn(message, env) -> handled
  self._seq       = 0
  self._epoch     = bootEpoch()
  self._relayWindow, self._relayCount = -1, 0
  self:_load()
  return self
end

--- Register the local delivery handler for a service kind. The handler
--- receives (message, env) and returns truthy when it accepted the
--- message — only then is the delivery ACKed back to the sender (an
--- uninstalled/failing service must not report "delivered").
function meshctl:on(svc, fn)
  self._handlers[svc] = fn
end

function meshctl:off(svc)
  self._handlers[svc] = nil
end

function meshctl:hasHandler(svc)
  return self._handlers[svc] ~= nil
end

function meshctl:_nextId(prefix)
  self._seq = self._seq + 1
  return (prefix or "x") .. ":" .. tostring(self.myAddr) .. ":" .. self._epoch
    .. ":" .. tostring(self._seq)
end

-- Token-bucket-ish relay cap: at most RELAY_BUDGET relays per wall second.
function meshctl:_mayRelay()
  local sec = math.floor(self.clock())
  if sec ~= self._relayWindow then
    self._relayWindow, self._relayCount = sec, 0
  end
  if self._relayCount >= meshctl.RELAY_BUDGET then return false end
  self._relayCount = self._relayCount + 1
  return true
end

-- Free memory, or nil when there is no probe (tests, the pure layer).
local function freeOf(self)
  if not self.freeMemory then return nil end
  local ok, free = pcall(self.freeMemory)
  if ok and type(free) == "number" then return free end
  return nil
end

-- May a relay hold `bytes` more? "As many as it can physically hold": what
-- would be left must stay over RELAY_FLOOR. Without a probe, mesh's cap.
function meshctl:_canHold(bytes)
  local free = freeOf(self)
  if free == nil then return bytes <= mesh.RELAY_HOLD_BYTES end
  return free - bytes >= meshctl.RELAY_FLOOR
end

function meshctl:_memoryLow()
  local free = freeOf(self)
  return free ~= nil and free < meshctl.RELAY_FLOOR
end

-- Remember that `id` was delivered here, for probes that ask later.
function meshctl:_noteDelivered(id)
  local d = self.delivered
  if d.set[id] then return end
  d.set[id] = true
  d.order[#d.order + 1] = id
  while #d.order > meshctl.DELIVERED_MAX do
    d.set[table.remove(d.order, 1)] = nil
  end
end

-- What a reset must not lose: our own messages still awaiting delivery
-- (relay copies are not ours to keep) and the ids we delivered. A deadline
-- is saved as time LEFT, because the clock restarts with the machine.
function meshctl:_save()
  local st = self.store
  if not (st and st.save) then return end
  local now = self.clock()
  local out = {}
  for _, it in pairs(self.outbox.items) do
    if not it.relay then
      out[#out + 1] = { env = it.env, rs = it.rs, probes = it.probes,
        left = it.deadline and (it.deadline - now) or nil }
    end
  end
  local okS, err = pcall(st.save, { outbox = out, delivered = self.delivered.order })
  if not okS and self.log then
    self.log.warn("mesh", "could not save mesh state: " .. tostring(err))
  end
end

function meshctl:_load()
  local st = self.store
  if not (st and st.load) then return end
  local okL, state = pcall(st.load)
  if not okL or type(state) ~= "table" then return end
  local now = self.clock()
  for _, rec in ipairs(type(state.outbox) == "table" and state.outbox or {}) do
    local env = type(rec) == "table" and rec.env or nil
    if type(env) == "table" and type(env.id) == "string" then
      local left = tonumber(rec.left) or meshctl.ORIGIN_TTL
      mesh.enqueue(self.outbox, env, { interval = mesh.RETRY_EVERY, deadline = now + left }, now)
      local it = self.outbox.items[env.id]
      if it then it.rs = tonumber(rec.rs); it.probes = tonumber(rec.probes) or 0 end
      mesh.sawBefore(self.seen, env.id)
    end
  end
  for _, id in ipairs(type(state.delivered) == "table" and state.delivered or {}) do
    if type(id) == "string" then self:_noteDelivered(id) end
  end
end

-- Answer about message `msgId` to `to`: ACK ("I have it") or WANT ("I do
-- not"), MACed under the secret we share with `to` when there is one.
function meshctl:_reply(kind, msgId, to)
  local env = mesh.newEnvelope(self.myAddr, to, {
    id = self:_nextId(kind:sub(1, 1)), kind = kind, ts = self.clock() })
  if kind == "ack" then env.ackId = msgId else env.wantId = msgId end
  env.mac = replyMac(self.secretFor(to), kind, msgId, self.myAddr, to)
  mesh.sawBefore(self.seen, env.id)
  self.broadcast(env)
  return env
end

-- Does a reply of `kind` about our message `it` come from its receiver?
-- For a sealed message it must carry the MAC only the receiver could make.
function meshctl:_verifyReply(kind, it, env)
  if env.from ~= it.env.to then return false end
  if not it.env.sealed then return true end
  local expect = replyMac(self.secretFor(it.env.to), kind, it.env.id, env.from, env.to)
  local eq = (crypto and crypto.ctEquals) or function(a, b) return a == b end
  return expect ~= nil and type(env.mac) == "string" and eq(expect, env.mac)
end

-- Our message, again, in full: a new resend counter so relays that saw the
-- earlier flood carry it (mesh.seenKey), same id so the receiver dedups it.
function meshctl:_resend(it)
  it.rs = (it.rs or 0) + 1
  it.probes = 0
  it.lastSent = self.clock()
  local out = {}
  for k, v in pairs(it.env) do out[k] = v end
  out.rs = it.rs
  out.path = {}
  mesh.sawBefore(self.seen, mesh.seenKey(out))
  self.broadcast(out)
end

function meshctl:_probe(it)
  local env = mesh.newEnvelope(self.myAddr, it.env.to, {
    id = self:_nextId("p"), kind = "probe", ts = self.clock() })
  env.probeId = it.env.id
  mesh.sawBefore(self.seen, env.id)
  self.broadcast(env)
end

-- An ACK for one of ours: clears it only if it verifies.
function meshctl:_onAck(env)
  local it = type(env.ackId) == "string" and self.outbox.items[env.ackId]
  if not it or it.relay then return end
  if not self:_verifyReply("ack", it, env) then
    if self.log then
      self.log.warn("mesh", "ignored an ACK that does not verify: " .. tostring(env.ackId))
    end
    return
  end
  mesh.ack(self.outbox, env.ackId)
  self:_save()
end

-- A probe about a message sent to us: ACK if we have it, WANT if we never
-- saw it. Seen but not delivered (no service took it): say nothing -- a
-- re-send would meet the same refusal, and the sender's FULL_EVERY re-send
-- covers the service coming back.
function meshctl:_onProbe(env)
  local id = env.probeId
  if type(id) ~= "string" or #id > mesh.MAX_ID then return end
  if self.delivered.set[id] then
    self:_reply("ack", id, env.from)
  elseif not self.seen.set[id] then
    self:_reply("want", id, env.from)
  end
end

-- The receiver says it never got one of ours: send it whole, once a window.
function meshctl:_onWant(env)
  local it = type(env.wantId) == "string" and self.outbox.items[env.wantId]
  if not it or it.relay then return end
  if not self:_verifyReply("want", it, env) then return end
  if it.lastSent and self.clock() - it.lastSent < mesh.RETRY_EVERY / 2 then return end
  self:_resend(it)
end

--- Compose, seal, queue and flood a new message. `opts`:
---   svc                  service name (REQUIRED)
---   to                   destination node address (or "*" for a bulletin)
---   user, fromUser       optional usernames
---   payload              plain table of service content
---   ttl                  hop-budget override
---   allowPlaintext       REQUIRED to send unsealed (#SEC — see header)
--- Returns (id, sealed) or (nil, reason).
function meshctl:send(opts)
  opts = opts or {}
  if type(opts.svc) ~= "string" or opts.svc == "" then
    return nil, "mesh send needs a service kind (svc)"
  end
  local unicast = (opts.to ~= nil and opts.to ~= mesh.BROADCAST)
  local secret = unicast and self.secretFor(opts.to) or nil
  if not secret and not opts.allowPlaintext then
    if unicast then
      return nil, "no shared secret with " .. tostring(opts.to):sub(1, 8)
        .. "... — pair first (net pair) or allow plaintext explicitly"
    end
    return nil, "broadcasts can't be sealed — allow plaintext explicitly"
  end
  -- The sender is what promises delivery, so what it holds is bounded: past
  -- ORIGIN_MAX a new message is refused, not queued.
  if unicast then
    local waiting = self:pending()
    if waiting >= meshctl.ORIGIN_MAX then
      return nil, "mesh outbox full: " .. waiting .. " messages are still awaiting delivery"
    end
  end
  local id = self:_nextId(opts.svc:sub(1, 1))
  local env = meshctl.compose({
    from = self.myAddr, to = opts.to, svc = opts.svc,
    fromUser = opts.fromUser, user = opts.user,
    payload = opts.payload,
    secret = secret, id = id, ttl = opts.ttl, ts = self.clock(),
  })
  -- Keep a copy until the receiver confirms it (bulletins aren't ACKed, so
  -- don't pin them — flood once and let them go). The first probe waits a
  -- full interval: the flood below IS the first attempt, and the next tick
  -- used to flood it all over again.
  if unicast then
    local now = self.clock()
    mesh.enqueue(self.outbox, env, { interval = mesh.RETRY_EVERY,
      deadline = now + meshctl.ORIGIN_TTL }, now)
    local it = self.outbox.items[id]
    if it then it.nextAt = now + mesh.RETRY_EVERY; it.lastSent = now end
    self:_save()
  end
  -- Mark our own id seen so a returning flood doesn't echo back into us.
  mesh.sawBefore(self.seen, id)
  self.broadcast(env)
  return id, (secret ~= nil)
end

--- Handle an envelope handed up by the net layer (already past the trust
--- gate). Relays / delivers / answers probes / processes ACKs. Returns the
--- action table.
function meshctl:onPacket(env)
  local unicast = type(env) == "table" and env.to ~= mesh.BROADCAST and env.to ~= nil
  local act = meshctl.ingest(env, self.myAddr, self.isForMe, self.seen, self.secretFor)

  -- Snoop ACKs that pass through us: a relay copy of what they acknowledge
  -- need not be re-flooded. Our OWN copies wait for an ACK we can verify.
  if type(env) == "table" and env.kind == "ack" and type(env.ackId) == "string" then
    mesh.ackRelay(self.outbox, env.ackId)
  end

  -- Relay onward (rate-limited), holding a copy while there is room for it.
  if act.forward and act.out then
    if self:_mayRelay() then
      self.broadcast(act.out)
      if env.kind == "msg" and unicast then
        mesh.enqueue(self.outbox, act.out, { relay = true,
          canHold = function(b) return self:_canHold(b) end }, self.clock())
      end
    elseif self.log then
      self.log.warn("mesh", "relay budget exceeded; dropping a forward")
    end
  end

  -- The same message again, already delivered here: the sender cannot have
  -- had our ACK, so say it again. The service is not asked twice.
  if act.dup and unicast and env.kind == "msg" and self.delivered.set[env.id]
     and self.isForMe(env) then
    self:_reply("ack", env.id, env.from)
  end

  if act.deliver then
    if act.kind == "ack" then
      self:_onAck(env)
    elseif act.kind == "probe" then
      self:_onProbe(env)
    elseif act.kind == "want" then
      self:_onWant(env)
    elseif act.kind == "msg" and act.message then
      local handled = false
      if act.ackTo and self.delivered.set[env.id] then
        handled = true                       -- a re-send of what we already have
      else
        local h = self._handlers[act.svc or ""]
        if h then
          local ok, res = pcall(h, act.message, env)
          handled = ok and res and true or false
          if not ok and self.log then
            self.log.warn("mesh", "'" .. tostring(act.svc) .. "' handler error: " .. tostring(res))
          end
        elseif self.log then
          self.log.warn("mesh", "no local service for mesh kind '"
            .. tostring(act.svc) .. "' (message from "
            .. tostring(env.from):sub(1, 8) .. " dropped, not ACKed)")
        end
        if handled and act.ackTo then
          self:_noteDelivered(env.id)
          self:_save()
        end
      end
      -- ACK only what a service actually accepted: the sender keeps
      -- retrying otherwise, which is honest — nothing stored it here.
      if act.ackTo and handled then
        self:_reply("ack", env.id, act.ackTo)
      end
      act.handled = handled
    end
  end
  return act
end

--- Probe for (or, now and then, re-send) our messages still awaiting an ACK
--- whose interval has come, re-flood relay copies, drop what is past its
--- deadline, and shed relay copies under memory pressure. Call periodically.
function meshctl:tick(now)
  now = now or self.clock()
  -- Relay copies are a courtesy: when memory runs short they all go.
  if self:_memoryLow() then mesh.shedRelays(self.outbox, 0) end
  local items, dropped = mesh.dueItems(self.outbox, now)
  for _, it in ipairs(items) do
    if it.relay then
      self.broadcast(it.env)
    else
      it.probes = (it.probes or 0) + 1
      if it.probes >= meshctl.FULL_EVERY then
        self:_resend(it)          -- nothing answered for a while: the whole message
      else
        self:_probe(it)
      end
    end
  end
  if dropped > 0 then self:_save() end
end

--- How many of our own sent messages are still unacknowledged (relay copies
--- are not ours).
function meshctl:pending()
  local n = 0
  for _, it in pairs(self.outbox.items) do
    if not it.relay then n = n + 1 end
  end
  return n
end

return meshctl
