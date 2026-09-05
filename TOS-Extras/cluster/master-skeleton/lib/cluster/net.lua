-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.net — Packet handlers for the Master                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Registers net.on() handlers for every cluster message type.
-- Handlers do minimal inline work — they validate packet shape,
-- dispatch to clusterd callback handlers, and enqueue jobs for the
-- scheduler tick. Heavy lifting lives in the scheduler and jobs
-- modules.

local net      = require("kernel.net")
local protocol = require("kernel.net.protocol")
local serialize = require("kernel.serialize")

-- Best-effort log hook. kernel.log first — bare "log" resolves nowhere
-- on TOS, which made these logs silently vanish.
local log
do
  local okK, mod = pcall(require, "kernel.log")
  if not (okK and mod and mod.info) then okK, mod = pcall(require, "log") end
  if okK and mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.net"

local netmod = {}

-- Cluster-specific message type constants. These extend protocol.TYPE;
-- we alias to the real strings defined in kernel.net.protocol so the
-- net layer's type-level validation still gates them at receive.
-- If the TOS protocol module doesn't know a given cluster type
-- (e.g. running against an older kernel), fall back to the spec's
-- friendly names so tests can still exercise the logic.
local function _ptype(cluster_name, fallback)
  if protocol.TYPE and protocol.TYPE[cluster_name] then
    return protocol.TYPE[cluster_name]
  end
  return fallback
end

local TYPE = {
  CLUSTER_REGISTER     = _ptype("CLUSTER_REGISTER",     "cluster_register"),
  CLUSTER_REGISTER_ACK = _ptype("CLUSTER_REGISTER_ACK", "cluster_register_ack"),
  CLUSTER_HEARTBEAT    = _ptype("CLUSTER_HEARTBEAT",    "cluster_heartbeat"),
  CLUSTER_ASSIGN       = _ptype("CLUSTER_ASSIGN",       "cluster_assign"),
  CLUSTER_ASSIGN_ACK   = _ptype("CLUSTER_ASSIGN_ACK",   "cluster_assign_ack"),
  CLUSTER_RESULT       = _ptype("CLUSTER_RESULT",       "cluster_result"),
  CLUSTER_RESULT_CHUNK = _ptype("CLUSTER_RESULT_CHUNK", "cluster_result_chunk"),
  CLUSTER_CANCEL       = _ptype("CLUSTER_CANCEL",       "cluster_cancel"),
  CLUSTER_DRAIN        = _ptype("CLUSTER_DRAIN",        "cluster_drain"),
  CLUSTER_STATUS_REQ   = _ptype("CLUSTER_STATUS_REQ",   "cluster_status_req"),
  CLUSTER_STATUS_RES   = _ptype("CLUSTER_STATUS_RES",   "cluster_status_res"),
  CLUSTER_PAIR_INIT    = _ptype("CLUSTER_PAIR_INIT",    "cluster_pair_init"),
  CLUSTER_PAIR_CONFIRM = _ptype("CLUSTER_PAIR_CONFIRM", "cluster_pair_conf"),
  RELAY_FORWARD        = _ptype("RELAY_FORWARD",        "relay_forward"),
  RELAY_FAIL           = _ptype("RELAY_FAIL",           "relay_fail"),
}
netmod.TYPE = TYPE

-- ============================================================
-- Return-path bookkeeping for relay-originated traffic
-- ============================================================
-- When a packet arrives wrapped in RELAY_FORWARD, the envelope's `path`
-- describes the hops it took. Master's reply is source-routed back: we
-- remember the path per originating address so outbound helpers can
-- wrap replies in a matching RELAY_FORWARD going the other way.
--
-- Entries age out after 5 minutes of quiet; this matters only for
-- Managers that go offline mid-assignment.
local _returnPaths = {}          -- [manager_addr] = { hops = {...}, last_seen = uptime }

local computer = require("computer")

local function _rememberReturnPath(manager_addr, path)
  if not manager_addr or type(path) ~= "table" then return end
  _returnPaths[manager_addr] = {
    hops      = path,
    last_seen = computer.uptime(),
  }
end

local function _returnPathFor(manager_addr)
  local e = _returnPaths[manager_addr]
  if not e then return nil end
  if computer.uptime() - e.last_seen > 300 then
    _returnPaths[manager_addr] = nil
    return nil
  end
  return e.hops
end

netmod._returnPaths = _returnPaths   -- exposed for test & diagnostic

-- ============================================================
-- Outbound packet helpers
-- ============================================================

--- Build and send a packet, wrapping in RELAY_FORWARD if the destination
-- has a known return path. Returns (ok, err).
local function _sendToManager(manager_addr, msgType, payload)
  local pkt = protocol.makePacket(msgType, payload, { to = manager_addr })

  local hops = _returnPathFor(manager_addr)
  if hops and #hops > 0 then
    -- Source-routed reply: wrap inner packet in RELAY_FORWARD along the
    -- reverse of the original path. The relay path we send TO is the
    -- reverse of the path the inbound packet TRAVERSED.
    local reversed = {}
    for i = #hops, 1, -1 do reversed[#reversed + 1] = hops[i] end

    -- The first hop on the reverse path is our next-hop relay peer.
    local next_hop = reversed[1]
    if not next_hop then return false, "empty_reverse_path" end

    local inner_blob = serialize.encode(pkt)
    local wrapper = protocol.makePacket(TYPE.RELAY_FORWARD, {
      dest       = manager_addr,
      path       = reversed,            -- hops the reply will traverse
      ttl        = math.max(3, #reversed + 1),
      inner      = inner_blob,
      inner_type = msgType,
    }, { to = next_hop })

    return net.send(next_hop, wrapper)
  end

  return net.send(manager_addr, pkt)
end

function netmod.sendAssignment(managerAddr, assignment)
  -- CLUSTER_ASSIGN payload per §4.3.
  local payload = {
    assignment_id   = assignment.assignment_id,
    job_id          = assignment.job_id,
    priority        = assignment.priority or 5,
    deadline        = assignment.deadline or 0,
    retry_policy    = assignment.retry_policy or "safe",
    compute_profile = assignment.compute_profile or "mixed",
    tasks_inline    = assignment.tasks_inline,
    tasks_ref       = assignment.tasks_ref,
    inputs_inline   = assignment.inputs_inline,
    inputs_ref      = assignment.inputs_ref,
    result_sink     = assignment.result_sink or "inline",
    result_prefix   = assignment.result_prefix,
  }
  return _sendToManager(managerAddr, TYPE.CLUSTER_ASSIGN, payload)
end

function netmod.sendCancel(managerAddr, assignment_id)
  return _sendToManager(managerAddr, TYPE.CLUSTER_CANCEL, {
    assignment_id = assignment_id,
  })
end

function netmod.sendDrain(managerAddr)
  return _sendToManager(managerAddr, TYPE.CLUSTER_DRAIN, {})
end

function netmod.sendRegisterAck(managerAddr, domain_id, accepted, reason, extra)
  extra = extra or {}
  local payload = {
    accepted               = accepted and true or false,
    reason                 = reason,
    domain_id              = accepted and domain_id or nil,
    worker_port            = accepted and (2001 + (domain_id or 0)) or nil,
    heartbeat_interval     = extra.heartbeat_interval or 5,
    master_protocol        = extra.master_protocol or "1.0",
    min_supported_protocol = extra.min_supported_protocol or "1.0",
  }
  -- Register replies are sent directly; the Manager's relay path is
  -- not yet known when it first registers (or, if the register was
  -- relay-routed, we already stashed the return path via the relay
  -- unwrap, and _sendToManager will use it automatically).
  return _sendToManager(managerAddr, TYPE.CLUSTER_REGISTER_ACK, payload)
end

function netmod.sendStatusReq(managerAddr)
  return _sendToManager(managerAddr, TYPE.CLUSTER_STATUS_REQ, {})
end

-- ============================================================
-- Register / unregister listeners
-- ============================================================

--- Wire net.on() listeners for every cluster message type.
-- @param handlers table: callbacks injected by clusterd. Keys:
--          onRegister, onHeartbeat, onResult, onResultChunk,
--          onAssignAck, onStatusRes, onRelayFail, onCancelEcho.
--        Missing keys degrade to a no-op + warning.
-- @return table: list of { type, id } rows to pass back to unregister().
function netmod.register(handlers)
  handlers = handlers or {}

  local function getH(name)
    return handlers[name] or function()
      log.warn(LOG_TAG, "no handler bound for " .. name)
    end
  end

  local onRegister     = getH("onRegister")
  local onHeartbeat    = getH("onHeartbeat")
  local onResult       = getH("onResult")
  local onResultChunk  = getH("onResultChunk")
  local onAssignAck    = getH("onAssignAck")
  local onStatusRes    = getH("onStatusRes")
  local onRelayFail    = getH("onRelayFail")
  -- CLUSTER-6 — pairing handshake listener. clusterd binds this to
  -- the pair module's onPairInit so the trust DB gets updated when
  -- a Manager presents a valid pairing code.
  local onPairInit     = getH("onPairInit")

  local registered = {}

  local function add(typeStr, cb)
    local id = net.on(typeStr, cb)
    registered[#registered + 1] = { type = typeStr, id = id }
  end

  add(TYPE.CLUSTER_REGISTER, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then
      log.warn(LOG_TAG, "malformed CLUSTER_REGISTER from " .. tostring(from))
      return
    end
    local ok, err = pcall(onRegister, packet, from)
    if not ok then log.error(LOG_TAG, "onRegister threw: " .. tostring(err)) end
  end)

  add(TYPE.CLUSTER_HEARTBEAT, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then return end
    local ok, err = pcall(onHeartbeat, packet, from)
    if not ok then log.error(LOG_TAG, "onHeartbeat threw: " .. tostring(err)) end
  end)

  add(TYPE.CLUSTER_RESULT, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then return end
    local ok, err = pcall(onResult, packet, from)
    if not ok then log.error(LOG_TAG, "onResult threw: " .. tostring(err)) end
  end)

  add(TYPE.CLUSTER_RESULT_CHUNK, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then return end
    local ok, err = pcall(onResultChunk, packet, from)
    if not ok then log.error(LOG_TAG, "onResultChunk threw: " .. tostring(err)) end
  end)

  add(TYPE.CLUSTER_ASSIGN_ACK, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then return end
    local ok, err = pcall(onAssignAck, packet, from)
    if not ok then log.error(LOG_TAG, "onAssignAck threw: " .. tostring(err)) end
  end)

  add(TYPE.CLUSTER_STATUS_RES, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then return end
    local ok, err = pcall(onStatusRes, packet, from)
    if not ok then log.error(LOG_TAG, "onStatusRes threw: " .. tostring(err)) end
  end)

  add(TYPE.CLUSTER_PAIR_INIT, function(packet, from)
    if type(packet) ~= "table" or type(packet.payload) ~= "table" then return end
    local ok, err = pcall(onPairInit, packet, from)
    if not ok then log.error(LOG_TAG, "onPairInit threw: " .. tostring(err)) end
  end)

  -- RELAY_FORWARD arrives at Master when a Manager's relay path
  -- terminates here. We unwrap the inner packet and re-dispatch by type.
  add(TYPE.RELAY_FORWARD, function(packet, from)
    local p = packet and packet.payload
    if type(p) ~= "table" or not p.inner then
      log.warn(LOG_TAG, "malformed RELAY_FORWARD from " .. tostring(from))
      return
    end
    local inner, derr = serialize.decode(p.inner)
    if not inner or type(inner) ~= "table" then
      log.warn(LOG_TAG, "relay inner decode failed: " .. tostring(derr))
      return
    end

    -- Remember the originating Manager's return path so outbound
    -- replies retrace the same hops.
    local origin = inner.from or (p.path and p.path[1])
    if origin and type(p.path) == "table" then
      _rememberReturnPath(origin, p.path)
    end

    -- Re-dispatch the inner packet according to its type.
    local inner_from = origin or from
    local t = inner.type
    if t == TYPE.CLUSTER_REGISTER then
      pcall(onRegister, inner, inner_from)
    elseif t == TYPE.CLUSTER_HEARTBEAT then
      pcall(onHeartbeat, inner, inner_from)
    elseif t == TYPE.CLUSTER_RESULT then
      pcall(onResult, inner, inner_from)
    elseif t == TYPE.CLUSTER_RESULT_CHUNK then
      pcall(onResultChunk, inner, inner_from)
    elseif t == TYPE.CLUSTER_ASSIGN_ACK then
      pcall(onAssignAck, inner, inner_from)
    elseif t == TYPE.CLUSTER_STATUS_RES then
      pcall(onStatusRes, inner, inner_from)
    else
      log.warn(LOG_TAG, "relay inner type not routable at Master: " .. tostring(t))
    end
  end)

  add(TYPE.RELAY_FAIL, function(packet, from)
    local ok, err = pcall(onRelayFail, packet, from)
    if not ok then log.error(LOG_TAG, "onRelayFail threw: " .. tostring(err)) end
  end)

  log.info(LOG_TAG, "registered " .. tostring(#registered) .. " listener(s)")
  return registered
end

function netmod.unregister(registered)
  if not registered then return end
  for _, entry in ipairs(registered) do
    if entry and entry.type and entry.id then
      net.off(entry.type, entry.id)
    end
  end
end

-- Diagnostic helper: check whether we have a live return path for a
-- given Manager. Useful from the api module when an operator runs
-- `cluster managers <id>`.
function netmod.hasRelayReturnPath(manager_addr)
  return _returnPathFor(manager_addr) ~= nil
end

return netmod
