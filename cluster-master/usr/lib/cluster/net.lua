








local net      = require("kernel.net")
local protocol = require("kernel.net.protocol")
local serialize = require("kernel.serialize")



local log
do
  local okK, mod = pcall(require, "kernel.log")
  if not (okK and mod and mod.info) then okK, mod = pcall(require, "log") end
  if okK and mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.net"

local netmod = {}







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











local _returnPaths = {}          

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

netmod._returnPaths = _returnPaths   







local function _sendToManager(manager_addr, msgType, payload)
  local pkt = protocol.makePacket(msgType, payload, { to = manager_addr })

  local hops = _returnPathFor(manager_addr)
  if hops and #hops > 0 then
    
    
    
    local reversed = {}
    for i = #hops, 1, -1 do reversed[#reversed + 1] = hops[i] end

    
    local next_hop = reversed[1]
    if not next_hop then return false, "empty_reverse_path" end

    local inner_blob = serialize.encode(pkt)
    local wrapper = protocol.makePacket(TYPE.RELAY_FORWARD, {
      dest       = manager_addr,
      path       = reversed,            
      ttl        = math.max(3, #reversed + 1),
      inner      = inner_blob,
      inner_type = msgType,
    }, { to = next_hop })

    return net.send(next_hop, wrapper)
  end

  return net.send(manager_addr, pkt)
end

function netmod.sendAssignment(managerAddr, assignment)
  
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
  
  
  
  
  return _sendToManager(managerAddr, TYPE.CLUSTER_REGISTER_ACK, payload)
end

function netmod.sendStatusReq(managerAddr)
  return _sendToManager(managerAddr, TYPE.CLUSTER_STATUS_REQ, {})
end











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

  
  
  --! #SEC — REFUSED, until a relayed packet can prove where it came from.
  --! The inner packet is `serialize.encode(pkt)`: no encryption, no MAC
  --! (cluster/protocol.lua's "end-to-end encrypted by the caller with its
  --! Master secret" describes a design, not this code). Its origin was
  --! read from the inner packet's own `from`, so ANY trusted Manager could
  --! wrap a CLUSTER_RESULT / HEARTBEAT / REGISTER "from" another Manager
  --! and have it accepted as that Manager's, and rewrite that Manager's
  --! remembered return path so the Master's next assignment for it went
  --! to the relay instead. Nothing legitimate is lost: no Manager sends
  --! RELAY_FORWARD (cluster.relayHandle has no caller), so the only
  --! relayed packet this handler has ever seen is a hand-made one. To turn
  --! relaying on, MAC the inner with the ORIGIN's Master secret and verify
  --! it here before trusting inner.from or recording a path.
  --! (test_cluster_relay_refused.lua)
  local RELAY_UNAUTHENTICATED = true
  add(TYPE.RELAY_FORWARD, function(packet, from)
    local p = packet and packet.payload
    if type(p) ~= "table" or not p.inner then
      log.warn(LOG_TAG, "malformed RELAY_FORWARD from " .. tostring(from))
      return
    end
    if RELAY_UNAUTHENTICATED then
      log.warn(LOG_TAG, "refusing RELAY_FORWARD from " .. tostring(from):sub(1, 8)
        .. ": relayed packets carry no origin authentication yet")
      return
    end
    local inner, derr = serialize.decode(p.inner)
    if not inner or type(inner) ~= "table" then
      log.warn(LOG_TAG, "relay inner decode failed: " .. tostring(derr))
      return
    end

    
    
    local origin = inner.from or (p.path and p.path[1])
    if origin and type(p.path) == "table" then
      _rememberReturnPath(origin, p.path)
    end

    
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




function netmod.hasRelayReturnPath(manager_addr)
  return _returnPathFor(manager_addr) ~= nil
end

return netmod
