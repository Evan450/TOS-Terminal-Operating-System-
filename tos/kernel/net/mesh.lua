local mesh = {}

mesh.DEFAULT_TTL   = 8
mesh.SEEN_MAX      = 512
mesh.RETRY_EVERY   = 30
mesh.RELAY_HOLD    = 120
mesh.BROADCAST     = "*"

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

function mesh.newSeen(max)
  return { set = {}, order = {}, max = max or mesh.SEEN_MAX }
end

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

function mesh.inPath(env, addr)
  for _, a in ipairs(env.path or {}) do if a == addr then return true end end
  return false
end

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

  if mine and not broadcast then
    return res
  end

  if (env.ttl or 0) > 0 and not mesh.inPath(env, selfAddr) then
    res.forward = true
    res.out = copyForward(env, selfAddr)
  end
  return res
end

function mesh.newOutbox()
  return { items = {} }
end

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

function mesh.ack(ob, id)
  if id == nil then return false end
  local had = ob.items[id] ~= nil
  ob.items[id] = nil
  return had
end

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

function mesh.pending(ob)
  local n = 0
  for _ in pairs(ob.items) do n = n + 1 end
  return n
end

return mesh
