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
-- Returns { dup, forward, out, deliver, kind, svc, message, ack, ackId }:
--   forward/out          re-broadcast `out`
--   deliver + kind=="msg"  dispatch `message` to the svc handler, then
--                          flood `ack` (unicast only) once handled
--   deliver + kind=="ack"  ackId was delivered; stop retrying it
function meshctl.ingest(env, selfAddr, isForMe, seen, secretFor)
  local r = mesh.route(env, selfAddr, isForMe, seen)
  local act = { dup = r.dup, forward = r.forward, out = r.out, deliver = false }
  if r.dup or not r.deliver then return act end

  if env.kind == "ack" then
    act.deliver = true
    act.kind = "ack"
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
    act.ack = mesh.newAck(env, selfAddr, { ts = clock() })
  end
  return act
end

-- ============================================================
-- Live controller
-- ============================================================

--- Create a controller. `deps`:
---   myAddr      string                       this node's modem address
---   broadcast   function(envelope)           flood an envelope to neighbours
---   secretFor   function(addr) -> secret|nil shared secret with a peer
---   clock       function() -> number         monotonic seconds
---   isForMe     function(env)  -> bool        (optional) does env.to target us
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
  self.seen       = mesh.newSeen()
  self.outbox     = mesh.newOutbox()
  self._handlers  = {}          -- svc name -> fn(message, env) -> handled
  self._seq       = 0
  self._relayWindow, self._relayCount = -1, 0
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
  return (prefix or "x") .. ":" .. tostring(self.myAddr) .. ":" .. tostring(self._seq)
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
  local id = self:_nextId(opts.svc:sub(1, 1))
  local env = meshctl.compose({
    from = self.myAddr, to = opts.to, svc = opts.svc,
    fromUser = opts.fromUser, user = opts.user,
    payload = opts.payload,
    secret = secret, id = id, ttl = opts.ttl, ts = self.clock(),
  })
  -- Keep a copy in the outbox for retry until ACKed (bulletins aren't
  -- ACKed, so don't pin them — flood once and let them go).
  if unicast then
    mesh.enqueue(self.outbox, env, { interval = mesh.RETRY_EVERY,
      deadline = self.clock() + 3600 }, self.clock())
  end
  -- Mark our own id seen so a returning flood doesn't echo back into us.
  mesh.sawBefore(self.seen, id)
  self.broadcast(env)
  return id, (secret ~= nil)
end

--- Handle an envelope handed up by the net layer (already past the trust
--- gate). Relays / delivers / processes ACKs. Returns the action table.
function meshctl:onPacket(env)
  local unicast = (env.to ~= mesh.BROADCAST and env.to ~= nil)
  local act = meshctl.ingest(env, self.myAddr, self.isForMe, self.seen, self.secretFor)

  -- Snoop ACKs that pass through us: stop re-flooding what they acknowledge.
  if env.kind == "ack" and env.ackId then mesh.ack(self.outbox, env.ackId) end

  -- Relay onward (rate-limited), with the store-and-forward relay hold.
  if act.forward and act.out then
    if self:_mayRelay() then
      self.broadcast(act.out)
      if env.kind == "msg" and unicast then
        mesh.enqueue(self.outbox, act.out, { relay = true }, self.clock())
      end
    elseif self.log then
      self.log.warn("mesh", "relay budget exceeded; dropping a forward")
    end
  end

  if act.deliver then
    if act.kind == "ack" then
      mesh.ack(self.outbox, act.ackId)          -- our message reached its target
    elseif act.kind == "msg" and act.message then
      local h = self._handlers[act.svc or ""]
      local handled = false
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
      -- ACK only what a service actually accepted: the sender keeps
      -- retrying otherwise, which is honest — nothing stored it here.
      if act.ack and handled then
        mesh.sawBefore(self.seen, act.ack.id)   -- don't echo our own ACK back in
        self.broadcast(act.ack)
      end
      act.handled = handled
    end
  end
  return act
end

--- Re-flood any message still awaiting an ACK whose retry interval has
--- come (and drop those past their deadline). Call periodically.
function meshctl:tick(now)
  now = now or self.clock()
  for _, env in ipairs(mesh.due(self.outbox, now)) do
    self.broadcast(env)
  end
end

--- How many of our sent messages are still unacknowledged.
function meshctl:pending()
  return mesh.pending(self.outbox)
end

return meshctl
