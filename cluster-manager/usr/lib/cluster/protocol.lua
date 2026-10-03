













local cluster = {}








cluster.PROTOCOL_VERSION       = "1.0"
cluster.MIN_SUPPORTED_PROTOCOL = "1.0"

local function parseVersion(v)
  if type(v) ~= "string" then return nil end
  local maj, min = v:match("^(%d+)%.(%d+)$")
  if not maj then return nil end
  return tonumber(maj), tonumber(min)
end





function cluster.checkVersion(theirs, mine)
  mine = mine or cluster.PROTOCOL_VERSION
  local ma, _ = parseVersion(mine)
  local tb, _ = parseVersion(theirs)
  if not ma or not tb then return "malformed" end
  if ma ~= tb then return "version_mismatch" end
  return "compatible"
end





cluster.PORT = {
  CONTROL       = 2000,  
  WORKER_BASE   = 2001,  
  PUBLIC_READ   = 2100,  
  PUBLIC_WRITE  = 2101,  
}


function cluster.workerPort(domainId)
  if type(domainId) ~= "number" or domainId < 0 then return nil end
  return cluster.PORT.WORKER_BASE + domainId
end





cluster.TIMING = {
  HEARTBEAT_INTERVAL  = 5,      
  HEARTBEAT_DEGRADED  = 15,     
  HEARTBEAT_OFFLINE   = 30,     
  WORKER_PING         = 10,     
  TASK_TIMEOUT        = 60,     
  ASSIGNMENT_TIMEOUT  = 300,    
  TRUST_PENDING       = 300,    
  STORAGE_SWEEP       = 60,     
  STORAGE_TTL_DEFAULT = 3600,   
  STORAGE_TTL_MAX     = 86400,  
  BOOTSTRAP_WINDOW    = 180,    
  PEER_STATUS_INTERVAL = 10,    
  PEER_STATUS_DEAD    = 30,     
  RELAY_TTL_DEFAULT   = 3,      
  
  RELAY_SEEN_TTL      = 30,     
  RELAY_RATE_WINDOW   = 10,     
  RELAY_RATE_MAX      = 30,     
}










cluster.payload = {}


function cluster.payload.register(info)
  info = info or {}
  return {
    hostname         = info.hostname,
    profile          = info.profile,          
    worker_count     = info.worker_count or 0,
    storage          = info.storage or { external_type = "none", external_capacity = 0 },
    has_console      = info.has_console or false,
    compute_capable  = info.compute_capable and true or false,
    cluster_protocol = info.cluster_protocol or cluster.PROTOCOL_VERSION,
    software_version = info.software_version or "0.0.0",
  }
end


function cluster.payload.registerAck(info)
  info = info or {}
  return {
    accepted               = info.accepted and true or false,
    reason                 = info.reason,
    domain_id              = info.domain_id,
    worker_port            = info.worker_port,
    heartbeat_interval     = info.heartbeat_interval or cluster.TIMING.HEARTBEAT_INTERVAL,
    master_protocol        = info.master_protocol or cluster.PROTOCOL_VERSION,
    min_supported_protocol = info.min_supported_protocol or cluster.MIN_SUPPORTED_PROTOCOL,
  }
end



function cluster.payload.heartbeat(info)
  info = info or {}
  return {
    domain_id           = info.domain_id,
    state               = info.state or "active",
    workers_total       = info.workers_total or 0,
    workers_active      = info.workers_active or 0,
    workers_busy        = info.workers_busy or 0,
    queue_depth         = info.queue_depth or 0,
    assignments_running = info.assignments_running or {},
    compute_capable     = info.compute_capable and true or false,
    storage_used        = info.storage_used or 0,
    errors_last_min     = info.errors_last_min or 0,
    uptime              = info.uptime or 0,
  }
end


function cluster.payload.assign(info)
  info = info or {}
  return {
    assignment_id = info.assignment_id,
    job_id        = info.job_id,
    priority      = info.priority or 5,
    deadline      = info.deadline or 0,
    retry_policy  = info.retry_policy or "safe",
    tasks_inline  = info.tasks_inline,
    tasks_ref     = info.tasks_ref,
    inputs_inline = info.inputs_inline,
    inputs_ref    = info.inputs_ref,
    result_sink   = info.result_sink or "inline",
    result_prefix = info.result_prefix,
  }
end


function cluster.payload.result(info)
  info = info or {}
  return {
    assignment_id = info.assignment_id,
    status        = info.status or "ok",
    output_inline = info.output_inline,
    output_ref    = info.output_ref,
    errors        = info.errors or {},
    stats         = info.stats or {},
  }
end


function cluster.payload.resultChunk(info)
  info = info or {}
  return {
    assignment_id = info.assignment_id,
    chunk_idx     = info.chunk_idx or 0,
    chunk_total   = info.chunk_total or 1,
    data          = info.data or "",
    final_stats   = info.final_stats,
  }
end



function cluster.payload.peerStatus(info)
  info = info or {}
  return {
    state            = info.state or "active",
    master_reachable = info.master_reachable and true or false,
    relay_hops       = info.relay_hops or 0,
    load             = info.load or 0,
  }
end








function cluster.payload.relayForward(info)
  info = info or {}
  return {
    dest       = info.dest,
    path       = info.path or {},
    ttl        = info.ttl or cluster.TIMING.RELAY_TTL_DEFAULT,
    inner      = info.inner,             
    inner_type = info.inner_type,        
  }
end









local _relaySeen = {}   
local _relayRate = {}   

local function relayNow()
  local ok, c = pcall(require, "computer")
  if ok and c and c.uptime then return c.uptime() end
  return (os.clock and os.clock()) or 0
end





local function relayPayloadKey(envelope)
  local inner = envelope.inner
  local basis = tostring(envelope.dest) .. "\0"
    .. (type(inner) == "string" and inner or tostring(inner))
  local ok, crypto = pcall(require, "kernel.crypto")
  if ok and crypto and crypto.hash then
    local okh, h = pcall(crypto.hash, basis)
    if okh and type(h) == "string" then return h end
  end
  return basis
end

local function relayPruneSeen(now)
  for k, expiry in pairs(_relaySeen) do
    if expiry < now then _relaySeen[k] = nil end
  end
end


function cluster._resetRelayState()
  _relaySeen = {}
  _relayRate = {}
end
















function cluster.relayHandle(envelope, selfAddr, routeTo, fromPeer)
  if type(envelope) ~= "table" then
    return { action = "fail", reason = "malformed" }
  end

  
  
  local path = envelope.path or {}
  for i = 1, #path do
    if path[i] == selfAddr then
      return { action = "fail", reason = "loop", envelope = envelope }
    end
  end

  
  
  local ttl = tonumber(envelope.ttl) or 0
  if ttl <= 0 then
    return { action = "fail", reason = "ttl_exceeded", envelope = envelope }
  end

  
  
  
  if envelope.dest == selfAddr then
    return { action = "deliver", envelope = envelope }
  end

  
  
  local now = relayNow()
  relayPruneSeen(now)

  
  
  local pk = relayPayloadKey(envelope)
  if _relaySeen[pk] and _relaySeen[pk] >= now then
    return { action = "fail", reason = "duplicate", envelope = envelope }
  end

  
  local peer = fromPeer or path[#path] or "?"
  local rate = _relayRate[peer]
  if not rate or (now - rate.ws) >= cluster.TIMING.RELAY_RATE_WINDOW then
    rate = { ws = now, n = 0 }
    _relayRate[peer] = rate
  end
  if rate.n >= cluster.TIMING.RELAY_RATE_MAX then
    return { action = "fail", reason = "rate_limited", envelope = envelope }
  end
  rate.n = rate.n + 1

  
  
  _relaySeen[pk] = now + cluster.TIMING.RELAY_SEEN_TTL

  
  local newPath = {}
  for i = 1, #path do newPath[i] = path[i] end
  newPath[#newPath + 1] = selfAddr

  local newEnvelope = {
    dest       = envelope.dest,
    path       = newPath,
    ttl        = ttl - 1,
    inner      = envelope.inner,
    inner_type = envelope.inner_type,
  }

  local nextHop = nil
  if type(routeTo) == "function" then
    nextHop = routeTo(envelope.dest)
  end

  return { action = "forward", envelope = newEnvelope, next_hop = nextHop }
end




function cluster.reversePath(path)
  if type(path) ~= "table" then return {} end
  local rev = {}
  local n = #path
  for i = 1, n do rev[i] = path[n - i + 1] end
  return rev
end


function cluster.payload.relayFail(info)
  info = info or {}
  return {
    reason              = info.reason or "unreachable",
    failed_at           = info.failed_at,
    original_dest       = info.original_dest,
    original_inner_type = info.original_inner_type,
  }
end





cluster.NS = {
  JOB    = "job",    
  DOMAIN = "domain", 
  SHARED = "shared", 
}





function cluster.parseKey(key)
  if type(key) ~= "string" or key == "" then return nil, "empty key" end
  
  if key:sub(1, 1) == "/" then return nil, "absolute key" end
  if key:find("%.%./") or key:find("/%.%.$") or key == ".." then
    return nil, "parent-escape in key"
  end

  local head, rest = key:match("^([^/]+)/(.*)$")
  if not head then return nil, "no namespace segment" end

  if head == cluster.NS.SHARED then
    return { ns = "shared", scope = nil, subpath = rest }
  end

  local ns, scope = head:match("^(job)%-(%d+)$")
  if not ns then ns, scope = head:match("^(domain)%-(%d+)$") end
  if not ns then return nil, "unknown namespace: " .. tostring(head) end

  return { ns = ns, scope = tonumber(scope), subpath = rest }
end




function cluster.canWrite(writer, key)
  local parsed, err = cluster.parseKey(key)
  if not parsed then return false, err end
  writer = writer or {}

  if parsed.ns == "shared" then
    if writer.role == "master" then return true end
    return false, "namespace_denied: shared requires master"
  end

  if parsed.ns == "domain" then
    if writer.role == "manager" and writer.domain_id == parsed.scope then
      return true
    end
    return false, "namespace_denied: domain-<id> requires owning Manager"
  end

  if parsed.ns == "job" then
    if writer.role == "master" then return true end
    if writer.role == "manager"
       and writer.job_assignee
       and writer.job_assignee[parsed.scope] then
      return true
    end
    return false, "namespace_denied: job-<id> requires Master or assigned Manager"
  end

  return false, "namespace_denied: unknown namespace"
end





cluster.PUB_MAGIC = "PUB"

function cluster.pubGet(key, reqId)
  return { magic = cluster.PUB_MAGIC, op = "GET", key = key, req_id = reqId }
end

function cluster.pubList(prefix, reqId)
  return { magic = cluster.PUB_MAGIC, op = "LIST", prefix = prefix, req_id = reqId }
end



function cluster.validatePubRequest(msg)
  if type(msg) ~= "table" then return false, "not a table" end
  if msg.magic ~= cluster.PUB_MAGIC then return false, "bad magic" end
  if msg.op ~= "GET" and msg.op ~= "LIST" then
    return false, "unknown op: " .. tostring(msg.op)
  end
  if msg.op == "GET" then
    if type(msg.key) ~= "string" or msg.key == "" then
      return false, "GET needs key"
    end
  else
    if type(msg.prefix) ~= "string" then return false, "LIST needs prefix" end
  end
  return true
end





local CFG_PATH = "/etc/cluster.cfg"

local function mergeDefaults(cfg)
  cfg = cfg or {}
  cfg.master_path = cfg.master_path or "direct"
  
  if cfg.master_path ~= "via" then cfg.relay_peer = nil end
  cfg.encryption = cfg.encryption or {}
  
  
  cfg.encryption.plaintext_types = cfg.encryption.plaintext_types or {}
  return cfg
end





function cluster.loadConfig(fs, path)
  path = path or CFG_PATH
  if not fs or not fs.exists(path) then
    return mergeDefaults({})
  end
  local data = fs.readFile(path)
  if not data then return mergeDefaults({}) end
  local serialize = require("kernel.serialize")
  local ok, parsed = pcall(serialize.decode, data)
  if not ok or type(parsed) ~= "table" then
    return nil, "malformed cluster.cfg: " .. tostring(parsed or "not a table")
  end

  
  if parsed.master_path == "via" then
    if type(parsed.relay_peer) ~= "string" or parsed.relay_peer == "" then
      return nil, "cluster.cfg: master_path='via' requires relay_peer"
    end
  elseif parsed.master_path and parsed.master_path ~= "direct" then
    return nil, "cluster.cfg: master_path must be 'direct' or 'via'"
  end

  return mergeDefaults(parsed)
end








cluster.PLAINTEXT_ELIGIBLE = {
  peer_st = true,   
  cl_hb   = true,   
}




function cluster.allowPlaintext(msgType, cfg)
  if not cluster.PLAINTEXT_ELIGIBLE[msgType] then return false end
  cfg = cfg or {}
  local list = cfg.encryption and cfg.encryption.plaintext_types or nil
  if type(list) ~= "table" then return false end
  
  
  local logical = ({
    peer_st = "PEER_STATUS",
    cl_hb   = "CLUSTER_HEARTBEAT",
  })[msgType]
  for i = 1, #list do
    if list[i] == logical or list[i] == msgType then return true end
  end
  return false
end

return cluster
