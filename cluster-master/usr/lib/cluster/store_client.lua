
















local computer = require("computer")

local store_client = {}

local RPC_TIMEOUT = 10       
local WRITE_PORT  = 2101     

local net, protocol, serialize, stateRef, log

local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end

function store_client.init(deps)
  deps      = deps or {}
  net       = deps.net or firstRequire("kernel.net")
  stateRef  = deps.state or firstRequire("cluster.state")
  serialize = deps.serialize or firstRequire("kernel.serialize")
  log       = deps.log or firstRequire("kernel.log", "log")
    or { info = function() end, warn = function() end, error = function() end }
  protocol  = deps.protocol or (net and net.getProtocol and net.getProtocol())
    or firstRequire("kernel.net.protocol")
  return true
end


function store_client.address()
  local sn = stateRef and stateRef._data and stateRef._data.storage_node
  return sn and sn.address or nil
end

function store_client.available()
  return store_client.address() ~= nil and net ~= nil and protocol ~= nil
end




local function rpc(kind, payload, key)
  local addr = store_client.address()
  if not addr then return nil, "no_storage_node" end
  if not (net and protocol) then return nil, "no_network" end

  local done, ack, errReason = false, nil, nil
  local ids = {}
  local function listen(t, fn)
    ids[#ids + 1] = { t = t, id = net.on(t, fn) }
  end
  listen(protocol.TYPE.STORE_PUT_ACK, function(pkt, from)
    if from ~= addr then return end
    local p = pkt.payload or {}
    if p.key ~= key then return end
    done, ack = true, p
  end)
  listen(protocol.TYPE.STORE_ERROR, function(pkt, from)
    if from ~= addr then return end
    local p = pkt.payload or {}
    if p.key ~= nil and p.key ~= key then return end
    done, errReason = true, p.reason or "store_error"
  end)

  local sent = net.send(addr, protocol.makePacket(kind, payload, { to = addr }),
    WRITE_PORT)
  if sent == false then
    for _, e in ipairs(ids) do pcall(net.off, e.t, e.id) end
    return nil, "send_failed"
  end

  if net.waitFor then net.waitFor(function() return done end, RPC_TIMEOUT) end
  for _, e in ipairs(ids) do pcall(net.off, e.t, e.id) end

  if errReason then return nil, errReason end
  if not done then return nil, "timeout" end
  return ack
end




function store_client.put(key, value, opts)
  opts = opts or {}
  if not store_client.available() then return nil, "no_storage_node" end
  local blob = (type(value) == "string") and value or serialize.encode(value)
  return rpc(protocol.TYPE.STORE_PUT, {
    key = key, data = blob,
    ttl = opts.ttl or 0,
    overwrite = opts.overwrite ~= false,
  }, key)
end



function store_client.release(key, lease_id)
  if not store_client.available() then return nil, "no_storage_node" end
  return rpc(protocol.TYPE.STORE_RELEASE, { key = key, lease_id = lease_id }, key)
end

function store_client.extend(key, lease_id, seconds)
  if not store_client.available() then return nil, "no_storage_node" end
  return rpc(protocol.TYPE.STORE_LEASE_EXTEND,
    { key = key, lease_id = lease_id, extend_by = seconds }, key)
end









function store_client.tasksKey(job_id, split_index)
  return string.format("job-%d/tasks/assignment-%d", job_id, split_index)
end

function store_client.inputsKey(job_id, split_index)
  return string.format("job-%d/inputs/assignment-%d", job_id, split_index)
end

function store_client.resultsPrefix(job_id)
  return string.format("public://job-%d/results/", job_id)
end

store_client._internal = {
  WRITE_PORT  = WRITE_PORT,
  RPC_TIMEOUT = RPC_TIMEOUT,
  rpc         = function(...) return rpc(...) end,
}

return store_client
