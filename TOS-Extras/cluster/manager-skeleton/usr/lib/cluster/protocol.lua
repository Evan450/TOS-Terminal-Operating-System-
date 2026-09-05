-- ╔══════════════════════════════════════╗
-- ║  TOS Cluster Protocol v0.1           ║
-- ║  Master/Manager/Worker coordination  ║
-- ╚══════════════════════════════════════╝
-- Protocol scaffold for the Cluster spec v0.1. This module provides:
--   * version negotiation and compatibility checks (§3.4)
--   * reserved ports and timing constants (§2, §7)
--   * packet constructors for every new message type (§4)
--   * relay-envelope wrap/unwrap helpers (§1.3, §4.7)
--   * namespace validation for Public storage keys (§4.6)
--   * /etc/cluster.cfg loader (§1.3)
-- Daemon-level Master/Manager/Worker/StorageNode implementations live
-- in their own modules (see §12); this is the shared protocol core.

local cluster = {}

-- ============================================================
-- Version
-- ============================================================

-- Cluster protocol version is independent of TOS protocol.VERSION (§3.4).
-- Format: "MAJOR.MINOR" — strict major equality required, newer minors
-- must ignore unknown fields silently.
cluster.PROTOCOL_VERSION       = "1.0"
cluster.MIN_SUPPORTED_PROTOCOL = "1.0"

local function parseVersion(v)
  if type(v) ~= "string" then return nil end
  local maj, min = v:match("^(%d+)%.(%d+)$")
  if not maj then return nil end
  return tonumber(maj), tonumber(min)
end

--- Compare two version strings. Returns:
--   "compatible"       — same MAJOR, any MINOR
--   "version_mismatch" — different MAJOR
--   "malformed"        — unparseable version string
function cluster.checkVersion(theirs, mine)
  mine = mine or cluster.PROTOCOL_VERSION
  local ma, _ = parseVersion(mine)
  local tb, _ = parseVersion(theirs)
  if not ma or not tb then return "malformed" end
  if ma ~= tb then return "version_mismatch" end
  return "compatible"
end

-- ============================================================
-- Reserved ports (§2.1)
-- ============================================================

cluster.PORT = {
  CONTROL       = 2000,  -- Master ↔ Manager ↔ Storage Node (TOS protocol)
  WORKER_BASE   = 2001,  -- + domain_id = per-domain worker port
  PUBLIC_READ   = 2100,  -- unauthenticated read channel
  PUBLIC_WRITE  = 2101,  -- TOS-protocol write channel
}

--- Per-domain worker port (§2.1).
function cluster.workerPort(domainId)
  if type(domainId) ~= "number" or domainId < 0 then return nil end
  return cluster.PORT.WORKER_BASE + domainId
end

-- ============================================================
-- Timing & cadence defaults (§7)
-- ============================================================

cluster.TIMING = {
  HEARTBEAT_INTERVAL  = 5,      -- s; Manager → Master
  HEARTBEAT_DEGRADED  = 15,     -- s without HB → degraded
  HEARTBEAT_OFFLINE   = 30,     -- s without HB → offline
  WORKER_PING         = 10,     -- s; Manager → idle Worker
  TASK_TIMEOUT        = 60,     -- s; default per-task
  ASSIGNMENT_TIMEOUT  = 300,    -- s; default per-assignment
  TRUST_PENDING       = 300,    -- s; pending trust request TTL
  STORAGE_SWEEP       = 60,     -- s; expired-key sweep interval
  STORAGE_TTL_DEFAULT = 3600,   -- s; default key TTL
  STORAGE_TTL_MAX     = 86400,  -- s; max single lease window
  BOOTSTRAP_WINDOW    = 180,    -- s; Worker auto-accept window
  PEER_STATUS_INTERVAL = 10,    -- s; between configured relay pairs
  PEER_STATUS_DEAD    = 30,     -- s (3 missed) → relay peer marked down
  RELAY_TTL_DEFAULT   = 3,      -- hops
  -- #SEC H-18 — relay anti-amplification backstops.
  RELAY_SEEN_TTL      = 30,     -- s; dedup window for an inner payload
  RELAY_RATE_WINDOW   = 10,     -- s; per-upstream-peer forward rate window
  RELAY_RATE_MAX      = 30,     -- max forwards per peer per window
}

-- ============================================================
-- Packet constructors
--
-- Each returns a payload table intended to be wrapped by
-- protocol.makePacket(TYPE, payload, opts). We don't call
-- makePacket directly here to keep this module free of hard
-- protocol.lua dependencies — callers already hold it.
-- ============================================================

cluster.payload = {}

--- §4.1 CLUSTER_REGISTER payload
function cluster.payload.register(info)
  info = info or {}
  return {
    hostname         = info.hostname,
    profile          = info.profile,          -- "M3"|"M4"|"M8"|custom
    worker_count     = info.worker_count or 0,
    storage          = info.storage or { external_type = "none", external_capacity = 0 },
    has_console      = info.has_console or false,
    compute_capable  = info.compute_capable and true or false,
    cluster_protocol = info.cluster_protocol or cluster.PROTOCOL_VERSION,
    software_version = info.software_version or "0.0.0",
  }
end

--- §4.1 CLUSTER_REGISTER_ACK payload
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

--- §4.2 CLUSTER_HEARTBEAT payload (schema-locked plaintext-eligible type).
-- IMPORTANT: do NOT add job-derived fields here. See §3.3 schema lock.
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

--- §4.3 CLUSTER_ASSIGN payload
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

--- §4.4 CLUSTER_RESULT payload
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

--- §4.4 CLUSTER_RESULT_CHUNK payload
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

--- §4.7 PEER_STATUS payload (schema-locked plaintext-eligible type).
-- IMPORTANT: do NOT extend with any job-derived field. See §3.3 schema lock.
function cluster.payload.peerStatus(info)
  info = info or {}
  return {
    state            = info.state or "active",
    master_reachable = info.master_reachable and true or false,
    relay_hops       = info.relay_hops or 0,
    load             = info.load or 0,
  }
end

-- ============================================================
-- Relay envelope (§1.3, §4.7)
-- ============================================================

--- Wrap a serialized inner packet for relay forwarding. `inner` must already
-- be end-to-end encrypted by the caller with its Master secret — relay
-- peers never hold a key that can decrypt it.
function cluster.payload.relayForward(info)
  info = info or {}
  return {
    dest       = info.dest,
    path       = info.path or {},
    ttl        = info.ttl or cluster.TIMING.RELAY_TTL_DEFAULT,
    inner      = info.inner,             -- serialized + encrypted packet
    inner_type = info.inner_type,        -- plaintext hint ONLY; not authoritative
  }
end

-- #SEC H-18 — relay anti-amplification state. The loop check below only
-- inspects the attacker-supplied `path`, so a malicious source can strip
-- hops to dodge it and bounce a payload through us repeatedly. Two
-- independent backstops, neither of which trusts `path`:
--   1. a short-lived seen-set keyed on a hash of the inner payload, so a
--      node refuses to forward the same ciphertext twice within a window;
--   2. a per-upstream-peer forward rate limit, so one compromised relay
--      can't use us as an amplifier.
local _relaySeen = {}   -- payloadKey -> expiry uptime
local _relayRate = {}   -- peerAddr   -> { ws = windowStart, n = count }

local function relayNow()
  local ok, c = pcall(require, "computer")
  if ok and c and c.uptime then return c.uptime() end
  return (os.clock and os.clock()) or 0
end

-- Exact-match dedup key for the inner (already-encrypted) payload. We hash
-- when crypto is reachable purely to bound key size; the fallback uses the
-- raw bytes, which is still an EXACT equality test — not a truncated
-- fingerprint — so this never recreates the weak-fingerprint pattern.
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

-- Test/maintenance hook: clear all relay anti-amplification state.
function cluster._resetRelayState()
  _relaySeen = {}
  _relayRate = {}
end

--- Decide what a relay peer should do with an incoming RELAY_FORWARD.
-- Returns one of:
--   { action = "forward", envelope = <new envelope>, next_hop = <addr> }
--   { action = "deliver", envelope = <unchanged> }  -- we are the destination
--   { action = "fail", reason = "loop"|"ttl_exceeded"|"malformed"
--                              |"duplicate"|"rate_limited", envelope = <orig> }
-- @param envelope table: the incoming RELAY_FORWARD payload
-- @param selfAddr string: this node's modem address
-- @param routeTo  function|nil: optional fn(dest) → next hop addr (direct
--                 peers can route straight; `via` peers pass this through).
--                 If omitted, caller will handle next-hop selection from
--                 the returned envelope.
-- @param fromPeer string|nil: modem address of the immediate upstream sender,
--                 used for the per-peer rate limit. If omitted we fall back
--                 to the last hop recorded in `path`.
function cluster.relayHandle(envelope, selfAddr, routeTo, fromPeer)
  if type(envelope) ~= "table" then
    return { action = "fail", reason = "malformed" }
  end

  -- Loop detection: if we're already in the path, someone's misconfigured
  -- the topology. Drop immediately rather than forwarding into a cycle.
  local path = envelope.path or {}
  for i = 1, #path do
    if path[i] == selfAddr then
      return { action = "fail", reason = "loop", envelope = envelope }
    end
  end

  -- TTL: decrement on hop; if we've already hit zero, the previous hop
  -- shouldn't have sent it, but we fail defensively.
  local ttl = tonumber(envelope.ttl) or 0
  if ttl <= 0 then
    return { action = "fail", reason = "ttl_exceeded", envelope = envelope }
  end

  -- If we are the destination, deliver to local inbox (caller decrypts).
  -- Delivery to ourselves is not amplification, so it bypasses the relay
  -- dedup / rate-limit backstops below.
  if envelope.dest == selfAddr then
    return { action = "deliver", envelope = envelope }
  end

  -- #SEC H-18 — forwarding path only. Apply the anti-amplification
  -- backstops that do NOT trust the attacker-supplied `path`.
  local now = relayNow()
  relayPruneSeen(now)

  -- (1) Dedup on the inner payload. A payload we already forwarded inside
  -- the window is dropped regardless of what `path`/`ttl` now claim.
  local pk = relayPayloadKey(envelope)
  if _relaySeen[pk] and _relaySeen[pk] >= now then
    return { action = "fail", reason = "duplicate", envelope = envelope }
  end

  -- (2) Per-upstream-peer forward rate limit.
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

  -- Commit: record the payload so a second copy within the window is
  -- deduped, then forward.
  _relaySeen[pk] = now + cluster.TIMING.RELAY_SEEN_TTL

  -- Otherwise forward: append self to path, decrement TTL.
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

--- Reverse the path on a RELAY_FORWARD so a reply can source-route back.
-- Master uses this: it takes the `path` from the incoming envelope and
-- flips it to build the return envelope. Master holds no routing state.
function cluster.reversePath(path)
  if type(path) ~= "table" then return {} end
  local rev = {}
  local n = #path
  for i = 1, n do rev[i] = path[n - i + 1] end
  return rev
end

--- §4.7 RELAY_FAIL payload
function cluster.payload.relayFail(info)
  info = info or {}
  return {
    reason              = info.reason or "unreachable",
    failed_at           = info.failed_at,
    original_dest       = info.original_dest,
    original_inner_type = info.original_inner_type,
  }
end

-- ============================================================
-- Public-storage namespaces (§4.6)
-- ============================================================

cluster.NS = {
  JOB    = "job",    -- job-<id>/...    (Master or current-assignee Manager writes)
  DOMAIN = "domain", -- domain-<id>/... (owning Manager only writes)
  SHARED = "shared", -- shared/...      (Master only writes)
}

-- Parse a key into { ns, scope, subpath }. Returns nil on malformed keys.
--   "job-17/tasks/assignment-3"    → { ns="job",    scope=17, subpath="tasks/assignment-3" }
--   "domain-3/scratch/partial-17"  → { ns="domain", scope=3,  subpath="scratch/partial-17" }
--   "shared/manifest"              → { ns="shared", scope=nil,subpath="manifest" }
function cluster.parseKey(key)
  if type(key) ~= "string" or key == "" then return nil, "empty key" end
  -- Reject absolute paths and parent-escape attempts.
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

--- Is the given writer identity allowed to write to this key under §4.6?
--   writer: { role = "master"|"manager", domain_id = <n>, job_assignee = { [job_id]=true } }
-- Returns true | false, reason
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

-- ============================================================
-- Lightweight (non-TOS) read protocol on port 2100 (§3.2)
-- ============================================================

cluster.PUB_MAGIC = "PUB"

function cluster.pubGet(key, reqId)
  return { magic = cluster.PUB_MAGIC, op = "GET", key = key, req_id = reqId }
end

function cluster.pubList(prefix, reqId)
  return { magic = cluster.PUB_MAGIC, op = "LIST", prefix = prefix, req_id = reqId }
end

--- Validate an incoming public-read request. Rejects anything without the
-- correct magic, op, or with suspicious keys.
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

-- ============================================================
-- /etc/cluster.cfg loader (§1.3)
-- ============================================================

local CFG_PATH = "/etc/cluster.cfg"

local function mergeDefaults(cfg)
  cfg = cfg or {}
  cfg.master_path = cfg.master_path or "direct"
  -- relay_peer only meaningful when master_path == "via"; keep it nil otherwise
  if cfg.master_path ~= "via" then cfg.relay_peer = nil end
  cfg.encryption = cfg.encryption or {}
  -- v1 ships encryption-on-for-everything; plaintext_types is accepted but
  -- ignored here. Individual packet call sites honor the list if enabled.
  cfg.encryption.plaintext_types = cfg.encryption.plaintext_types or {}
  return cfg
end

--- Load /etc/cluster.cfg (or the provided path) via the kernel's safe
-- serialize.decode. Returns a config table (with defaults filled in) or
-- nil, err on failure. Missing file yields defaults, not an error —
-- the operator hasn't opted into a particular topology yet.
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

  -- Validate required fields when master_path == "via".
  if parsed.master_path == "via" then
    if type(parsed.relay_peer) ~= "string" or parsed.relay_peer == "" then
      return nil, "cluster.cfg: master_path='via' requires relay_peer"
    end
  elseif parsed.master_path and parsed.master_path ~= "direct" then
    return nil, "cluster.cfg: master_path must be 'direct' or 'via'"
  end

  return mergeDefaults(parsed)
end

-- ============================================================
-- Encryption policy (§3.3)
-- ============================================================

-- The schema lock described in §3.3. v1 ships with everything encrypted;
-- a future config option will allow opt-out for these types ONLY. Adding
-- any type not in this set constitutes a schema-review change.
cluster.PLAINTEXT_ELIGIBLE = {
  peer_st = true,   -- PEER_STATUS
  cl_hb   = true,   -- CLUSTER_HEARTBEAT
}

--- Should a packet of `msgType` be sent plaintext given config?
-- Default: false (encrypted). True only if both (a) type is eligible AND
-- (b) operator opted in via cluster.cfg.
function cluster.allowPlaintext(msgType, cfg)
  if not cluster.PLAINTEXT_ELIGIBLE[msgType] then return false end
  cfg = cfg or {}
  local list = cfg.encryption and cfg.encryption.plaintext_types or nil
  if type(list) ~= "table" then return false end
  -- list is the spec format: array of logical names like "PEER_STATUS".
  -- Accept both logical names and wire types for forward compat.
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
