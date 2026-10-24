-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster-storaged — the Storage Node daemon                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Answers the Public storage tier. Two listeners, deliberately split
-- the way the protocol spec splits them (§2.1, §2.2):
--
--   port 2101, TOS protocol, TRUSTED   — WRITES (STORE_PUT, extend,
--                                        release, list). Authenticated,
--                                        trust-gated, namespace-checked.
--   port 2100, raw framing, no trust   — READS (PUB GET / LIST). Cheap
--                                        enough that an OpenOS Worker
--                                        can hit it in ~20 lines, which
--                                        is the entire reason it is a
--                                        separate, dumber protocol.
--
-- Reads being unauthenticated is a SPEC DECISION (§2.2), not an
-- oversight here: everything in Public is readable by everyone by
-- design (§4.6's read column is "everyone"). Write authority is what
-- the namespace rules protect, and that lives on 2101.
--
-- WHO IS ALLOWED TO WRITE WHERE is cluster.protocol.canWrite (§4.6),
-- shared with the Manager rather than reimplemented -- two copies of a
-- security rule that must agree is exactly the drift this codebase has
-- been burned by before.

local storaged = {}

local store    = require("cluster.store")
local computer = require("computer")

local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local fs        = firstRequire("kernel.fs", "filesystem")
local event     = firstRequire("kernel.event", "event")
local component = firstRequire("component")
local serialize = require("kernel.serialize")
local log       = firstRequire("kernel.log", "log")
  or { info = function() end, warn = function() end, error = function() end }
local LOG_TAG = "cluster.storaged"

local net, protocol, cproto
local _cfg, _timers, _handlers = nil, {}, {}
local _running = false
-- What start() was handed (tests inject all three) or found on its own.
local _event, _modems, _rawSend, _pubListener = nil, {}, nil, nil

local DEFAULTS = {
  root            = "/var/cluster-store",
  capacity        = 0,        -- 0 = ask the filesystem
  write_port      = 2101,
  read_port       = 2100,
  sweep_interval  = 60,       -- §7: expired keys deleted on this cadence
  master          = nil,      -- address of the Master
  managers        = {},       -- [address] = domain_id
}

-- ============================================================
-- Config
-- ============================================================

function storaged.loadConfig(path)
  local cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  path = path or "/etc/cluster-storage.cfg"
  if fs and fs.exists and fs.exists(path) then
    local blob = fs.readFile and fs.readFile(path)
    if blob and blob ~= "" then
      local ok, parsed = pcall(serialize.decode, blob, { maxBytes = 8192 })
      if ok and type(parsed) == "table" then
        for k, v in pairs(parsed) do cfg[k] = v end
      else
        log.error(LOG_TAG, "malformed cluster-storage.cfg; using defaults")
      end
    end
  end
  _cfg = cfg
  return cfg
end

function storaged.config() return _cfg end

-- ============================================================
-- Writer identity (§4.6)
-- ============================================================

--- Resolve a peer address to the identity shape cluster.protocol.canWrite
--- expects. Identities are OPERATOR-DECLARED in the config, not learned
--- from the wire: a node that believed whatever a peer claimed about its
--- own domain_id would have no namespace isolation at all, since the
--- claim is the only thing the ACL turns on.
---
--- v1 does not populate `job_assignee`, so a Manager cannot write to
--- job-<id>/. That matches §4.6's own stated convention -- "Master
--- always writes assignment task lists and collected results to
--- job-<id>/" -- so nothing legitimate is blocked. Granting it would
--- need the Master to tell the node which Manager holds which job, and
--- inventing that flow here would be guessing at a protocol.
function storaged.writerFor(addr)
  if not _cfg then return nil, "not_configured" end
  if _cfg.master and addr == _cfg.master then
    return { role = "master" }
  end
  local dom = _cfg.managers and _cfg.managers[addr]
  if dom then
    return { role = "manager", domain_id = tonumber(dom), job_assignee = {} }
  end
  return nil, "unknown_writer"
end

-- ============================================================
-- Write plane (port 2101, TOS protocol, TRUSTED)
-- ============================================================

--! Replies go out on the node's DEFAULT port, not write_port. A request
--! is sent to write_port and so needs that port open HERE; the requester
--! (the Master) opens nothing but its own listen port, so a reply sent to
--! write_port would be addressed to a port nobody is listening on and
--! never arrive. kernel.net ignores the port on inbound TOS traffic, so
--! the type-keyed handlers hear the reply wherever it lands.
local function reply(to, kind, payload)
  if not (net and protocol) then return end
  net.send(to, protocol.makePacket(kind, payload, { to = to }))
end

local function storeError(to, key, reason)
  reply(to, protocol.TYPE.STORE_ERROR, { key = key, reason = reason })
end

--- Shared preamble for every write op: identify the peer, then ask
--- §4.6 whether it may write this key. One place, so a new op cannot
--- skip it.
local function authorize(from, key)
  local writer, werr = storaged.writerFor(from)
  if not writer then return nil, werr or "unknown_writer" end
  local ok, reason = cproto.canWrite(writer, key)
  if not ok then return nil, reason or "namespace_denied" end
  return writer
end

function storaged._onPut(packet, from)
  local p = packet.payload or {}
  if type(p.key) ~= "string" then return storeError(from, nil, "invalid_key: missing") end
  local writer, werr = authorize(from, p.key)
  if not writer then
    log.warn(LOG_TAG, "PUT denied for " .. tostring(from):sub(1, 8) .. ": " .. tostring(werr))
    return storeError(from, p.key, werr)
  end
  local ack, err = store.put(p.key, p.data or "", {
    ttl = tonumber(p.ttl), overwrite = p.overwrite ~= false,
  })
  if not ack then return storeError(from, p.key, err) end
  reply(from, protocol.TYPE.STORE_PUT_ACK, {
    key = ack.key, lease_id = ack.lease_id,
    expires_at = ack.expires_at, size_bytes = ack.size_bytes,
  })
end

function storaged._onExtend(packet, from)
  local p = packet.payload or {}
  local writer, werr = authorize(from, p.key or "")
  if not writer then return storeError(from, p.key, werr) end
  local res, err = store.extend(p.key, p.lease_id, tonumber(p.extend_by))
  if not res then return storeError(from, p.key, err) end
  reply(from, protocol.TYPE.STORE_PUT_ACK,
    { key = res.key, lease_id = p.lease_id, expires_at = res.expires_at })
end

function storaged._onRelease(packet, from)
  local p = packet.payload or {}
  local writer, werr = authorize(from, p.key or "")
  if not writer then return storeError(from, p.key, werr) end
  local res, err = store.release(p.key, p.lease_id)
  if not res then return storeError(from, p.key, err) end
  reply(from, protocol.TYPE.STORE_PUT_ACK, { key = p.key, released = true })
end

--- STORE_LIST is a read, but it arrives on the write plane because the
--- Master uses it for accounting. No namespace check: §4.6 makes every
--- namespace world-readable, and the PUB plane would serve the same
--- data to anyone regardless.
function storaged._onList(packet, from)
  local p = packet.payload or {}
  local keys, truncated = store.list(p.prefix or "", tonumber(p.limit) or 128)
  reply(from, protocol.TYPE.STORE_LIST_RES,
    { prefix = p.prefix, keys = keys, truncated = truncated })
end

-- ============================================================
-- Read plane (port 2100, lightweight framing, §3.2)
-- ============================================================
-- Not TOS packets: a bare serialized table with magic="PUB", so an
-- OpenOS Worker with no TOS stack can speak it. Anything that is not a
-- well-formed PUB request is dropped in silence -- this port is open to
-- untrusted callers, so it must not be usable as an error oracle.

function storaged._onPubMessage(fromAddr, rawData, viaAddr)
  if type(rawData) ~= "string" or #rawData > 8192 then return end
  local ok, msg = pcall(serialize.decode, rawData, { maxBytes = 8192 })
  if not ok or type(msg) ~= "table" then return end
  local valid = cproto.validatePubRequest(msg)
  if not valid then return end

  --! Answered on the modem that heard the request, as a bare serialized
  --! table: there is no TOS packet to build (the asker may be an OpenOS
  --! Worker with no TOS stack), and kernel.net has no raw-send to borrow.
  local function send(t)
    if _rawSend then _rawSend(viaAddr, fromAddr, _cfg.read_port, serialize.encode(t)) end
  end

  if msg.op == "GET" then
    local data, err = store.get(msg.key)
    if not data then
      return send({ magic = cproto.PUB_MAGIC, op = "RES", key = msg.key,
                    req_id = msg.req_id, err = err })
    end
    -- §3.2 carries chunk/total for oversized values. 6 KB keeps the
    -- reply inside the 8192-byte cap once framing is counted.
    local CHUNK = 6144
    if #data <= CHUNK then
      send({ magic = cproto.PUB_MAGIC, op = "RES", key = msg.key,
             req_id = msg.req_id, data = data, chunk = 1, total = 1 })
    else
      local total = math.ceil(#data / CHUNK)
      for i = 1, total do
        send({ magic = cproto.PUB_MAGIC, op = "RES", key = msg.key,
               req_id = msg.req_id, data = data:sub((i - 1) * CHUNK + 1, i * CHUNK),
               chunk = i, total = total })
      end
    end
  elseif msg.op == "LIST" then
    local rows = store.list(msg.prefix or "", 128)
    local keys = {}
    for i, r in ipairs(rows) do keys[i] = r.key end
    send({ magic = cproto.PUB_MAGIC, op = "LIST_RES",
           keys = keys, req_id = msg.req_id })
  end
end

-- ============================================================
-- Lifecycle
-- ============================================================

--- Every modem we can see, as proxies. Each is opened on both ports and
--- each can answer on the port it heard the question on.
local function collectModems(opts)
  if opts.modems then return opts.modems end
  local out = {}
  if component and component.list then
    for addr in component.list("modem") do
      local ok, px = pcall(component.proxy, addr)
      if ok and px then out[#out + 1] = { address = addr, proxy = px } end
    end
  end
  return out
end

function storaged.start(opts)
  opts = opts or {}
  if _running then return true end
  net      = opts.net or firstRequire("kernel.net")
  cproto   = opts.cproto or require("cluster.protocol")
  protocol = opts.protocol or (net and net.getProtocol and net.getProtocol())
    or firstRequire("kernel.net.protocol")
  if not (net and protocol and cproto) then
    return false, "no_network"
  end

  storaged.loadConfig(opts.config_path)
  local sok, serr = store.init({
    root = _cfg.root, capacity = _cfg.capacity,
    fs = fs, computer = computer, serialize = serialize, log = log,
  })
  if not sok then return false, serr end

  _event = opts.event or event
  _modems = collectModems(opts)
  _rawSend = opts.rawSend or function(via, to, port, blob)
    for _, m in ipairs(_modems) do
      if m.address == via and m.proxy and m.proxy.send then
        return pcall(m.proxy.send, to, port, blob)
      end
    end
  end

  --! The ports have to be OPENED. kernel.net opens exactly one (its
  --! listenPort) and a modem silently discards anything on a port it
  --! does not hold, so without this the Master's writes (sent to
  --! write_port) and every Worker's read (sent to read_port) go nowhere
  --! and nothing says so. A Tier-1 wireless card holds only one open
  --! port, so opening ours would evict TOS's own: that is a warning to
  --! put the node on a wired or Tier-2 modem, not something to hide.
  local opened = 0
  for _, m in ipairs(_modems) do
    local a = m.proxy and pcall(m.proxy.open, _cfg.write_port)
    local b = m.proxy and pcall(m.proxy.open, _cfg.read_port)
    if a and b then opened = opened + 1
    else log.warn(LOG_TAG, "modem " .. tostring(m.address):sub(1, 8)
      .. " could not open ports " .. tostring(_cfg.write_port) .. "/"
      .. tostring(_cfg.read_port) .. " (a Tier-1 wireless card holds only one)") end
  end
  if opened == 0 then
    log.error(LOG_TAG, "no modem has the storage ports open: nothing can reach this node")
  end

  if _event and _event.on then
    _pubListener = _event.on("modem_message", function(_, localAddr, remoteAddr, port, _, data)
      if port == _cfg.read_port then storaged._onPubMessage(remoteAddr, data, localAddr) end
    end, "cluster-storaged")
  end

  local T = protocol.TYPE
  local bind = {
    [T.STORE_PUT]          = storaged._onPut,
    [T.STORE_LEASE_EXTEND] = storaged._onExtend,
    [T.STORE_RELEASE]      = storaged._onRelease,
    [T.STORE_LIST]         = storaged._onList,
  }
  for kind, fn in pairs(bind) do
    _handlers[#_handlers + 1] = { kind = kind, id = net.on(kind, fn) }
  end

  -- The sweep is the only reason expiry happens at all (§5: best-effort,
  -- every 60 s). Without it a lease is advisory and the disk fills.
  if _event and _event.interval then
    _timers[#_timers + 1] = _event.interval(_cfg.sweep_interval or 60, function()
      local n = store.sweep()
      if n > 0 then log.info(LOG_TAG, "swept " .. n .. " expired key(s)") end
    end)
  end

  _running = true
  log.info(LOG_TAG, string.format("storage node up: root=%s capacity=%d",
    tostring(_cfg.root), store.capacity()))
  return true
end

function storaged.stop()
  for _, h in ipairs(_handlers) do pcall(net.off, h.kind, h.id) end
  _handlers = {}
  for _, t in ipairs(_timers) do
    if _event and _event.cancel then pcall(_event.cancel, t)
    elseif _event and _event.cancelTimer then pcall(_event.cancelTimer, t) end
  end
  _timers = {}
  if _pubListener and _event and _event.off then
    pcall(_event.off, "modem_message", _pubListener)
  end
  _pubListener = nil
  if _cfg then
    for _, m in ipairs(_modems) do
      if m.proxy then
        pcall(m.proxy.close, _cfg.write_port)
        pcall(m.proxy.close, _cfg.read_port)
      end
    end
  end
  _modems = {}
  _running = false
  store.saveIndex()
  return true
end

function storaged.isRunning() return _running end
function storaged.stats() return store.stats() end

storaged._internal = { DEFAULTS = DEFAULTS, setConfig = function(c) _cfg = c end }

return storaged
