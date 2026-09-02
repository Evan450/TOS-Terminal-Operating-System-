local mesh = require("kernel.net.mesh")

local meshctl = {}
meshctl.__index = meshctl

meshctl.RELAY_BUDGET = 32
meshctl.MAX_PAYLOAD  = 8192

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
    payload = content,
    ts = env.ts, sealed = (env.sealed ~= nil),
    readable = (content ~= nil), how = how,
  }
  if not content and log then
    log.warn("mesh", "Delivered sealed '" .. tostring(env.svc) .. "' from "
      .. tostring(env.from):sub(1, 8) .. " could not be opened: " .. tostring(how))
  end

  if env.to ~= mesh.BROADCAST and env.to ~= nil then
    act.ack = mesh.newAck(env, selfAddr, { ts = clock() })
  end
  return act
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
  self.seen       = mesh.newSeen()
  self.outbox     = mesh.newOutbox()
  self._handlers  = {}
  self._seq       = 0
  self._relayWindow, self._relayCount = -1, 0
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
  return (prefix or "x") .. ":" .. tostring(self.myAddr) .. ":" .. tostring(self._seq)
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

  if unicast then
    mesh.enqueue(self.outbox, env, { interval = mesh.RETRY_EVERY,
      deadline = self.clock() + 3600 }, self.clock())
  end

  mesh.sawBefore(self.seen, id)
  self.broadcast(env)
  return id, (secret ~= nil)
end

function meshctl:onPacket(env)
  local unicast = (env.to ~= mesh.BROADCAST and env.to ~= nil)
  local act = meshctl.ingest(env, self.myAddr, self.isForMe, self.seen, self.secretFor)

  if env.kind == "ack" and env.ackId then mesh.ack(self.outbox, env.ackId) end

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
      mesh.ack(self.outbox, act.ackId)
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

      if act.ack and handled then
        mesh.sawBefore(self.seen, act.ack.id)
        self.broadcast(act.ack)
      end
      act.handled = handled
    end
  end
  return act
end

function meshctl:tick(now)
  now = now or self.clock()
  for _, env in ipairs(mesh.due(self.outbox, now)) do
    self.broadcast(env)
  end
end

function meshctl:pending()
  return mesh.pending(self.outbox)
end

return meshctl
