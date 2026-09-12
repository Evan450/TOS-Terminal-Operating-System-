local mesh = {}

mesh.DEFAULT_TTL   = 8
mesh.SEEN_MAX      = 512
mesh.RETRY_EVERY   = 30
mesh.RELAY_HOLD    = 120
mesh.BROADCAST     = "*"

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
mesh.MAX_ID           = 96
mesh.MAX_TTL          = 16
mesh.RELAY_HOLD_MAX   = 8
mesh.RELAY_HOLD_BYTES = 4096
mesh.MAX_RESEND       = 1000000

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

function mesh.seenKey(env)
  if env.rs == nil then return env.id end
  return env.id .. "#" .. tostring(math.floor(env.rs))
end

function mesh.inPath(env, addr)
  for _, a in ipairs(env.path or {}) do if a == addr then return true end end
  return false
end

local function hopsOf(env)
  local t = tonumber(env.ttl) or 0
  if t > mesh.MAX_TTL then t = mesh.MAX_TTL end
  return t
end

local function wellFormed(env)
  if type(env) ~= "table" then return false end
  if type(env.id) ~= "string" or #env.id > mesh.MAX_ID then return false end
  local p = env.path
  if p ~= nil and (type(p) ~= "table" or #p > mesh.MAX_TTL * 2) then return false end
  local rs = env.rs
  if rs ~= nil and (type(rs) ~= "number" or rs < 0 or rs > mesh.MAX_RESEND) then return false end
  return true
end

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

  if mine and not broadcast then
    return res
  end

  if hopsOf(env) > 0 and not mesh.inPath(env, selfAddr) then
    res.forward = true
    res.out = copyForward(env, selfAddr)
  end
  return res
end

function mesh.newOutbox()
  return { items = {}, seq = 0 }
end

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
mesh._envBytes = envBytes

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

function mesh.ack(ob, id)
  if id == nil then return false end
  local had = ob.items[id] ~= nil
  ob.items[id] = nil
  return had
end

function mesh.ackRelay(ob, id)
  local it = id ~= nil and ob.items[id]
  if it and it.relay then ob.items[id] = nil; return true end
  return false
end

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

function mesh.due(ob, now)
  local items = mesh.dueItems(ob, now)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.env end
  return out
end

function mesh.pending(ob)
  local n = 0
  for _ in pairs(ob.items) do n = n + 1 end
  return n
end

return mesh
