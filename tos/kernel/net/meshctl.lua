local mesh = require("kernel.net.mesh")

local meshctl = {}
meshctl.__index = meshctl

meshctl.RELAY_BUDGET = 32
meshctl.MAX_PAYLOAD  = 8192

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
meshctl.RELAY_FLOOR   = 48 * 1024
meshctl.FULL_EVERY    = 4
meshctl.ORIGIN_MAX    = 16
meshctl.DELIVERED_MAX = 64
meshctl.ORIGIN_TTL    = 3600

local crypto, serialize, log
local clock = function() return 0 end

function meshctl.init(modules)
  modules   = modules or {}
  crypto    = modules.crypto
  serialize = modules.serialize or require("kernel.serialize")
  log       = modules.log
  if modules.clock then clock = modules.clock end
end

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

  env.mac = crypto.hmac(secret, table.concat({
    tostring(env.id), tostring(env.from), tostring(env.to),
    tostring(env.svc), method or "", nonce, ct }, "\0"))
  env.payload = nil
  return env
end

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

local function replyMac(secret, kind, msgId, from, to)
  if not (crypto and crypto.hmac and secret and secret ~= "") then return nil end
  return crypto.hmac(secret, table.concat({
    tostring(kind), tostring(msgId), tostring(from), tostring(to) }, "\0"))
end
meshctl._replyMac = replyMac

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
    payload = content,
    ts = env.ts, sealed = (env.sealed ~= nil),
    readable = (content ~= nil), how = how,
  }
  if not content and log then
    log.warn("mesh", "Delivered sealed '" .. tostring(env.svc) .. "' from "
      .. tostring(env.from):sub(1, 8) .. " could not be opened: " .. tostring(how))
  end

  if env.to ~= mesh.BROADCAST and env.to ~= nil then
    act.ackTo = env.from
  end
  return act
end

local function bootEpoch()
  local raw = crypto and crypto.salt and crypto.salt(4)
  if type(raw) == "string" and #raw >= 4 then
    return (raw:sub(1, 4):gsub(".", function(c) return string.format("%02x", c:byte()) end))
  end
  return string.format("%08x", math.floor((os.time and os.time() or 0) + clock() * 1000) % 0x100000000)
end

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
  self._handlers  = {}
  self._seq       = 0
  self._epoch     = bootEpoch()
  self._relayWindow, self._relayCount = -1, 0
  self:_load()
  return self
end

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

function meshctl:_mayRelay()
  local sec = math.floor(self.clock())
  if sec ~= self._relayWindow then
    self._relayWindow, self._relayCount = sec, 0
  end
  if self._relayCount >= meshctl.RELAY_BUDGET then return false end
  self._relayCount = self._relayCount + 1
  return true
end

local function freeOf(self)
  if not self.freeMemory then return nil end
  local ok, free = pcall(self.freeMemory)
  if ok and type(free) == "number" then return free end
  return nil
end

function meshctl:_canHold(bytes)
  local free = freeOf(self)
  if free == nil then return bytes <= mesh.RELAY_HOLD_BYTES end
  return free - bytes >= meshctl.RELAY_FLOOR
end

function meshctl:_memoryLow()
  local free = freeOf(self)
  return free ~= nil and free < meshctl.RELAY_FLOOR
end

function meshctl:_noteDelivered(id)
  local d = self.delivered
  if d.set[id] then return end
  d.set[id] = true
  d.order[#d.order + 1] = id
  while #d.order > meshctl.DELIVERED_MAX do
    d.set[table.remove(d.order, 1)] = nil
  end
end

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

function meshctl:_reply(kind, msgId, to)
  local env = mesh.newEnvelope(self.myAddr, to, {
    id = self:_nextId(kind:sub(1, 1)), kind = kind, ts = self.clock() })
  if kind == "ack" then env.ackId = msgId else env.wantId = msgId end
  env.mac = replyMac(self.secretFor(to), kind, msgId, self.myAddr, to)
  mesh.sawBefore(self.seen, env.id)
  self.broadcast(env)
  return env
end

function meshctl:_verifyReply(kind, it, env)
  if env.from ~= it.env.to then return false end
  if not it.env.sealed then return true end
  local expect = replyMac(self.secretFor(it.env.to), kind, it.env.id, env.from, env.to)
  local eq = (crypto and crypto.ctEquals) or function(a, b) return a == b end
  return expect ~= nil and type(env.mac) == "string" and eq(expect, env.mac)
end

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

function meshctl:_onProbe(env)
  local id = env.probeId
  if type(id) ~= "string" or #id > mesh.MAX_ID then return end
  if self.delivered.set[id] then
    self:_reply("ack", id, env.from)
  elseif not self.seen.set[id] then
    self:_reply("want", id, env.from)
  end
end

function meshctl:_onWant(env)
  local it = type(env.wantId) == "string" and self.outbox.items[env.wantId]
  if not it or it.relay then return end
  if not self:_verifyReply("want", it, env) then return end
  if it.lastSent and self.clock() - it.lastSent < mesh.RETRY_EVERY / 2 then return end
  self:_resend(it)
end

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

  if unicast then
    local now = self.clock()
    mesh.enqueue(self.outbox, env, { interval = mesh.RETRY_EVERY,
      deadline = now + meshctl.ORIGIN_TTL }, now)
    local it = self.outbox.items[id]
    if it then it.nextAt = now + mesh.RETRY_EVERY; it.lastSent = now end
    self:_save()
  end

  mesh.sawBefore(self.seen, id)
  self.broadcast(env)
  return id, (secret ~= nil)
end

function meshctl:onPacket(env)
  local unicast = type(env) == "table" and env.to ~= mesh.BROADCAST and env.to ~= nil
  local act = meshctl.ingest(env, self.myAddr, self.isForMe, self.seen, self.secretFor)

  if type(env) == "table" and env.kind == "ack" and type(env.ackId) == "string" then
    mesh.ackRelay(self.outbox, env.ackId)
  end

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
        handled = true
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

      if act.ackTo and handled then
        self:_reply("ack", env.id, act.ackTo)
      end
      act.handled = handled
    end
  end
  return act
end

function meshctl:tick(now)
  now = now or self.clock()

  if self:_memoryLow() then mesh.shedRelays(self.outbox, 0) end
  local items, dropped = mesh.dueItems(self.outbox, now)
  for _, it in ipairs(items) do
    if it.relay then
      self.broadcast(it.env)
    else
      it.probes = (it.probes or 0) + 1
      if it.probes >= meshctl.FULL_EVERY then
        self:_resend(it)
      else
        self:_probe(it)
      end
    end
  end
  if dropped > 0 then self:_save() end
end

function meshctl:pending()
  local n = 0
  for _, it in pairs(self.outbox.items) do
    if not it.relay then n = n + 1 end
  end
  return n
end

return meshctl
