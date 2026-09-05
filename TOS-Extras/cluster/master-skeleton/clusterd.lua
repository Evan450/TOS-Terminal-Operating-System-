-- ╔══════════════════════════════════════════════════════════════╗
-- ║  clusterd — Cluster control-plane daemon (Master)            ║
-- ║  TOS service; started by /etc/rc.d/clusterd.lua              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Lifecycle (as a TOS rc service):
--   start() — wire up state, net listeners, scheduler tick; return
--   stop()  — persist state, tear down listeners; return
--
-- The daemon does not block start()/stop(); it registers callbacks
-- with TOS's event system and yields control. The "loop" is actually
-- the TOS event scheduler dispatching modem_message and timer events.

local state     = require("cluster.state")
local scheduler = require("cluster.scheduler")
local jobs      = require("cluster.jobs")
local netmod    = require("cluster.net")
local api       = require("cluster.api")
-- CLUSTER-6 — operator-driven trust bootstrap. Wired into the daemon
-- so the pair window survives across CLI invocations (the window
-- lives in the daemon's address space, not the operator's shell).
local pair      = require("cluster.pair")
local storecli  = require("cluster.store_client")

-- Boot-order-proof requires (#FIX round-1 "cluster services error on
-- boot"): rc.d services load BEFORE the OpenOS compat layer registers
-- the "filesystem"/"event" module aliases, so requiring those names at
-- load time killed this service on every boot ("Module not found:
-- filesystem"). Prefer the TOS kernel modules (whose API this file
-- already calls: event.interval/cancelTimer, fs.exists/writeFile);
-- keep the OpenOS names as fallbacks for off-box tests and ports.
local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local event    = firstRequire("kernel.event", "event")
local fs       = firstRequire("kernel.fs", "filesystem")
local computer = require("computer")

-- TOS rotating file logger (kernel.log on TOS). Fall back to
-- stderr-prefixed stubs so unit/integration tests don't need a full
-- kernel — io-guarded, since `io` doesn't exist at rc.d time either.
local log
do
  local mod = firstRequire("kernel.log", "log")
  if mod and mod.info then log = mod else
    local function emit(lvl, tag, m)
      if io and io.stderr then
        io.stderr:write("[" .. lvl .. "][" .. tag .. "] " .. m .. "\n")
      end
    end
    log = {
      info  = function(tag, m) emit("I", tag, m) end,
      warn  = function(tag, m) emit("W", tag, m) end,
      error = function(tag, m) emit("E", tag, m) end,
    }
  end
end
local LOG_TAG = "clusterd"

local clusterd = {}

-- ============================================================
-- Internal handles
-- ============================================================

local _running = false
local _timer_heartbeat_sweep  -- timer id: scan for stale Managers
local _timer_state_snapshot   -- timer id: write /var/cluster/status.dat
local _timer_scheduler_tick   -- timer id: run scheduler pass
local _net_listeners = {}     -- net.on() ids to tear down on stop

-- ============================================================
-- Configuration
-- ============================================================

local CONFIG_PATH   = "/etc/cluster-master.cfg"
local STATE_PATH    = "/var/cluster/state.dat"
local STATUS_PATH   = "/var/cluster/status.dat"

local DEFAULT_CFG = {
  host_thread_budget       = 4,
  heartbeat_interval       = 5,
  heartbeat_degraded_after = 15,
  heartbeat_offline_after  = 30,
  scheduler_tick_interval  = 1,
  status_snapshot_interval = 2,
  heartbeat_sweep_interval = 5,
  encryption               = { plaintext_types = {} },
  storage_node_address     = nil,
  cluster_protocol         = "1.0",
  min_supported_protocol   = "1.0",
}

local cfg  -- loaded in start()
clusterd._cfg = nil  -- exposed post-start for api.getConfig()

local function _mergeDefaults(loaded)
  local out = {}
  for k, v in pairs(DEFAULT_CFG) do out[k] = v end
  if type(loaded) == "table" then
    for k, v in pairs(loaded) do out[k] = v end
  end
  -- Nested encryption table: merge rather than replace so partial
  -- overrides don't blank plaintext_types.
  if type(loaded) == "table" and type(loaded.encryption) == "table" then
    out.encryption = {}
    for k, v in pairs(DEFAULT_CFG.encryption) do out.encryption[k] = v end
    for k, v in pairs(loaded.encryption) do out.encryption[k] = v end
  end
  return out
end

local function loadConfig()
  if not fs.exists or not fs.exists(CONFIG_PATH) then
    log.info(LOG_TAG, "no config at " .. CONFIG_PATH .. "; using defaults")
    return _mergeDefaults(nil)
  end
  -- fs.readFile + load, NOT loadfile: that global doesn't exist at
  -- rc.d time (compat registers it later, if at all). Text-only load.
  local src = fs.readFile and fs.readFile(CONFIG_PATH)
  local chunk, err = src and load(src, "=" .. CONFIG_PATH, "t")
  if not chunk then
    log.error(LOG_TAG, "config load failed: " .. tostring(err) ..
                       "; falling back to defaults")
    return _mergeDefaults(nil)
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    log.error(LOG_TAG, "config did not return a table: " .. tostring(result) ..
                       "; falling back to defaults")
    return _mergeDefaults(nil)
  end
  return _mergeDefaults(result)
end

-- ============================================================
-- Ensure /var/cluster exists
-- ============================================================

local function _ensureStateDir()
  local dir = STATE_PATH:match("(.+)/[^/]+$")
  if not dir then return end
  if fs.exists and not fs.exists(dir) then
    if fs.makeDirectory then
      local ok, err = pcall(fs.makeDirectory, dir)
      if not ok then log.warn(LOG_TAG, "mkdir failed: " .. tostring(err)) end
    end
  end
end

-- ============================================================
-- Start / stop
-- ============================================================

function clusterd.start()
  if _running then return true end
  log.info(LOG_TAG, "starting")

  cfg = loadConfig()
  clusterd._cfg = cfg

  _ensureStateDir()

  -- 1. Load persisted state (managers, jobs, counters)
  state.init(STATE_PATH)
  local ok, lerr = state.load(STATE_PATH)
  if not ok then
    log.error(LOG_TAG, "state load failed: " .. tostring(lerr))
    -- Continue; state.load keeps the fresh in-memory state on failure.
  end

  -- Re-hydrate storage node from config if it wasn't in persisted state.
  if cfg.storage_node_address and not state._data.storage_node then
    state.setStorageNode({ address = cfg.storage_node_address })
  end

  -- Public storage, if there is any. jobs.lua asks store_client whether a
  -- node is CONFIGURED before every spill decision, so handing it the
  -- client unconditionally is safe: with no storage_node_address the
  -- client reports unavailable and every assignment stays inline, which
  -- is exactly how the cluster behaved before this existed.
  do
    local okSer, ser = pcall(require, "kernel.serialize")
    -- No `net` handed in on purpose: store_client wants the KERNEL net
    -- (it speaks to the Storage Node on port 2101), not cluster.net,
    -- which exists to talk to Managers and would source-route through a
    -- relay path that has nothing to do with storage.
    storecli.init({ state = state, serialize = okSer and ser or nil, log = log })
    jobs.setStore(storecli, okSer and ser or nil)
    if storecli.available() then
      log.info(LOG_TAG, "public storage: " .. tostring(storecli.address()):sub(1, 8))
    else
      log.info(LOG_TAG, "public storage: none configured (assignments stay inline)")
    end
  end

  -- CLUSTER-6 — initialize the pair module with a handle to trust so
  -- it can flip new peers to TRUSTED on a successful pair.
  do
    local okT, trustMod = pcall(require, "kernel.net.trust")
    if okT then pair.init({ trust = trustMod }) end
  end

  -- 2. Inject handler callbacks and wire net listeners.
  -- CLUSTER-6 — onPairInit dispatches to the pair module.
  _net_listeners = netmod.register({
    onRegister     = function(p, from) clusterd._onRegister(p, from)     end,
    onHeartbeat    = function(p, from) clusterd._onHeartbeat(p, from)    end,
    onResult       = function(p, from) clusterd._onResult(p, from)       end,
    onResultChunk  = function(p, from) clusterd._onResultChunk(p, from)  end,
    onAssignAck    = function(p, from) clusterd._onAssignAck(p, from)    end,
    onStatusRes    = function(p, from) clusterd._onStatusRes(p, from)    end,
    onRelayFail    = function(p, from) clusterd._onRelayFail(p, from)    end,
    onPairInit     = function(p, from) pair.onPairInit(p, from)          end,
  })

  -- 3. Start recurring timers. event.interval is the canonical TOS API
  --    for "call me every N seconds" — event.timer is single-shot.
  _timer_heartbeat_sweep = event.interval(
    cfg.heartbeat_sweep_interval,
    function() clusterd._onHeartbeatSweep() end,
    "clusterd.hbsweep")
  _timer_scheduler_tick  = event.interval(
    cfg.scheduler_tick_interval,
    function() clusterd._onSchedulerTick() end,
    "clusterd.sched")
  _timer_state_snapshot  = event.interval(
    cfg.status_snapshot_interval,
    function() clusterd._onStatusSnapshot() end,
    "clusterd.status")

  -- 4. Expose the in-process API for the CLI.
  api.bind(state, scheduler, jobs, clusterd)

  _running = true
  log.info(LOG_TAG, "started")
  return true
end

function clusterd.stop()
  if not _running then return true end
  log.info(LOG_TAG, "stopping")

  if _timer_heartbeat_sweep then event.cancelTimer(_timer_heartbeat_sweep); _timer_heartbeat_sweep = nil end
  if _timer_scheduler_tick  then event.cancelTimer(_timer_scheduler_tick);  _timer_scheduler_tick  = nil end
  if _timer_state_snapshot  then event.cancelTimer(_timer_state_snapshot);  _timer_state_snapshot  = nil end

  netmod.unregister(_net_listeners)
  _net_listeners = {}

  local ok, err = pcall(state.save, STATE_PATH)
  if not ok then log.error(LOG_TAG, "final save failed: " .. tostring(err)) end

  api.unbind()
  clusterd._cfg = nil

  _running = false
  log.info(LOG_TAG, "stopped")
  return true
end

function clusterd.isRunning() return _running end
function clusterd.getConfig() return cfg end

-- CLUSTER-6 — pairing surface, called by the cluster CLI (which lives
-- in the operator's shell process, NOT inside the daemon, but talks to
-- the daemon via this module's exported handles).
function clusterd.startPairing()    return pair.startWindow()           end
function clusterd.closePairing()    return pair.closeWindow()           end
function clusterd.pairingInfo()     return pair.windowInfo()            end
function clusterd.pairingOpen()     return pair.windowOpen()            end

-- ============================================================
-- Timer handlers
-- ============================================================

function clusterd._onHeartbeatSweep()
  if not cfg then return end
  local now = computer.uptime()
  for addr, m in pairs(state._data.managers) do
    local since = now - (m.last_heartbeat or now)
    local prev  = m.state

    if since > cfg.heartbeat_offline_after and prev ~= "offline" then
      state.setManagerState(addr, "offline")
      -- Best-effort reassign / mark-lost for this Manager's work.
      pcall(jobs.onManagerOffline, m.domain_id, state)
    elseif since > cfg.heartbeat_degraded_after and prev == "active" then
      state.setManagerState(addr, "degraded")
    elseif since <= cfg.heartbeat_degraded_after and prev == "degraded" then
      state.setManagerState(addr, "active")
    end

    -- Draining manager that has finished all work → offline per §6.1.
    if prev == "draining" then
      local any = false
      for _, j in pairs(state._data.jobs) do
        for _, a in pairs(j.assignments) do
          if a.state == "running" and a.assigned_to == addr then
            any = true; break
          end
        end
        if any then break end
      end
      if not any then
        state.setManagerState(addr, "offline")
      end
    end
  end
end

function clusterd._onSchedulerTick()
  if not cfg then return end
  local now = computer.uptime()

  -- 1. Dispatch pending assignments.
  local pending = jobs.pendingAssignments(state)
  local ctx = {
    compute_bound_in_flight = state.computeBoundInFlight(),
    host_thread_budget      = cfg.host_thread_budget,
    uptime                  = now,
  }
  for _, a in ipairs(pending) do
    -- Refresh ctx.compute_bound_in_flight after each dispatch so the cap
    -- is enforced within a single tick as well as across ticks.
    ctx.compute_bound_in_flight = state.computeBoundInFlight()
    local addr, reason = scheduler.pickDomain(a, state._data.managers, ctx)
    if addr then
      local ok_d, derr = jobs.dispatch(a, addr, state, netmod)
      if not ok_d then
        log.warn(LOG_TAG, string.format("dispatch %d failed: %s",
          a.assignment_id or -1, tostring(derr)))
      end
    elseif reason and reason ~= "thread_budget_saturated" then
      -- Noisy reasons are expected in steady state; log only the first
      -- occurrence per minute would be nicer but good-enough for now.
    end
  end

  -- 2. Enforce deadlines on running assignments.
  for _, job in pairs(state._data.jobs) do
    for aid, a in pairs(job.assignments) do
      if a.state == "running" and a.deadline and a.deadline > 0 then
        -- deadline stored as absolute seconds-since-epoch-style number.
        -- We keep parity with the spec (§4.3) and compare against the
        -- uptime equivalent the Manager computed.
        if now > a.deadline then
          pcall(jobs.onAssignmentTimeout, aid, state, netmod)
        end
      end
    end
  end
end

function clusterd._onStatusSnapshot()
  -- Compact snapshot for /var/cluster/status.dat. Readable by CLI even
  -- if the daemon is wedged — this is the "what's the cluster doing?"
  -- fast path.
  local snap = {
    time              = computer.uptime(),
    managers          = { active = 0, degraded = 0, draining = 0, offline = 0 },
    jobs              = { pending = 0, running = 0, done = 0, failed = 0, cancelled = 0 },
    storage           = nil,
    host_thread_budget      = cfg and cfg.host_thread_budget or nil,
    compute_bound_in_flight = state.computeBoundInFlight(),
    recent_events     = state.recentEvents(10),
  }
  for _, m in pairs(state._data.managers) do
    local s = m.state or "offline"
    snap.managers[s] = (snap.managers[s] or 0) + 1
  end
  for _, j in pairs(state._data.jobs) do
    local s = j.state or "pending"
    snap.jobs[s] = (snap.jobs[s] or 0) + 1
  end
  if state._data.storage_node then
    local sn = state._data.storage_node
    snap.storage = {
      address        = sn.address,
      capacity_bytes = sn.capacity,
      used_bytes     = sn.used,
      last_seen      = sn.last_seen,
    }
  end

  -- Atomic write via .tmp + rename.
  local serialize = require("kernel.serialize")
  local blob = serialize.encode(snap)
  local tmp  = STATUS_PATH .. ".tmp"

  _ensureStateDir()
  local ok, err
  if fs.writeFile then
    ok, err = fs.writeFile(tmp, blob)
  else
    local h
    h, err = fs.open(tmp, "w")
    if h then h:write(blob); h:close(); ok = true end
  end
  if not ok then
    log.warn(LOG_TAG, "status snapshot tmp write failed: " .. tostring(err))
    return
  end
  if fs.exists and fs.exists(STATUS_PATH) and fs.remove then
    pcall(fs.remove, STATUS_PATH)
  end
  if fs.rename then
    local rok = pcall(fs.rename, tmp, STATUS_PATH)
    if not rok then
      log.warn(LOG_TAG, "status snapshot rename failed")
    end
  end
end

-- ============================================================
-- Event handlers (called by cluster.net on packet receipt)
-- ============================================================

--- Cluster protocol version negotiation (§3.4). Returns (ok, reason).
--  Major mismatch → hard reject. Minor mismatch → accept (best-effort).
local function _versionCompatible(manager_ver)
  local min = cfg and cfg.min_supported_protocol or "1.0"
  local function split(v)
    local a, b = tostring(v or ""):match("^(%d+)%.(%d+)$")
    return tonumber(a), tonumber(b)
  end
  local mmaj, mmin = split(manager_ver)
  local rmaj, rmin = split(min)
  if not mmaj or not mmin then return false, "version_malformed" end
  if not rmaj then return true end
  if mmaj ~= rmaj then return false, "version_mismatch" end
  if mmin < rmin then return false, "version_mismatch" end
  return true
end

function clusterd._onRegister(packet, from)
  local reg = packet.payload or {}
  if not reg.hostname or not reg.profile or not reg.worker_count then
    log.warn(LOG_TAG, "CLUSTER_REGISTER missing required fields from " .. tostring(from))
    netmod.sendRegisterAck(from, nil, false, "incomplete_register")
    return
  end

  local vok, vreason = _versionCompatible(reg.cluster_protocol)
  if not vok then
    log.warn(LOG_TAG, string.format(
      "register rejected from %s: %s (their=%s, ours=%s)",
      tostring(from), vreason, tostring(reg.cluster_protocol),
      tostring(cfg and cfg.cluster_protocol)))
    netmod.sendRegisterAck(from, nil, false, vreason, {
      master_protocol        = cfg and cfg.cluster_protocol,
      min_supported_protocol = cfg and cfg.min_supported_protocol,
    })
    return
  end

  local domain_id = state.withLock(function()
    return state.registerManager(from, reg)
  end)

  log.info(LOG_TAG, string.format("registered %s@%s as domain %d",
    reg.hostname or "?", tostring(from):sub(1, 8), domain_id))

  netmod.sendRegisterAck(from, domain_id, true, nil, {
    heartbeat_interval     = cfg and cfg.heartbeat_interval or 5,
    master_protocol        = cfg and cfg.cluster_protocol or "1.0",
    min_supported_protocol = cfg and cfg.min_supported_protocol or "1.0",
  })
end

function clusterd._onHeartbeat(packet, from)
  local snap = packet.payload or {}
  local ok, err = state.updateManagerHeartbeat(from, snap)
  if not ok then
    -- A heartbeat from a Manager we don't know about means they weren't
    -- properly registered (or we restarted). Ignore; they'll time out
    -- their CLUSTER_REGISTER and retry.
    log.warn(LOG_TAG, "heartbeat from unknown " .. tostring(from) ..
                      ": " .. tostring(err))
    return
  end
  -- If the snapshot says they're draining, reflect that.
  if snap.state == "draining" then
    state.setManagerState(from, "draining")
  end
  -- Fresh heartbeat → consider un-degrading.
  local m = state.getManager(from)
  if m and m.state == "degraded" then
    state.setManagerState(from, "active")
  end
end

function clusterd._onResult(packet, from)
  local p = packet.payload or {}
  if not p.assignment_id then
    log.warn(LOG_TAG, "CLUSTER_RESULT missing assignment_id from " .. tostring(from))
    return
  end
  state.withLock(function()
    jobs.onResult(p.assignment_id, p, state)
  end)
end

function clusterd._onResultChunk(packet, from)
  local p = packet.payload or {}
  if not p.assignment_id or not p.chunk_idx or not p.chunk_total then return end
  state.withLock(function()
    jobs.onResultChunk(p.assignment_id, p.chunk_idx, p.chunk_total,
                       p.data, p.final_stats, state)
  end)
end

function clusterd._onAssignAck(packet, from)
  local p = packet.payload or {}
  if not p.assignment_id then return end
  -- Rejected assignments go back to pending so the scheduler picks a
  -- different domain next tick.
  if p.accepted == false then
    log.warn(LOG_TAG, string.format(
      "manager %s rejected asn %d: %s",
      tostring(from):sub(1, 8), p.assignment_id, tostring(p.reason)))
    -- Find the job_id the assignment belongs to.
    for job_id, job in pairs(state._data.jobs) do
      if job.assignments[p.assignment_id] then
        state.setAssignmentState(job_id, p.assignment_id, "pending", {
          assigned_to = state.CLEAR,
          retry_reason = "manager_rejected",
        })
        break
      end
    end
  end
end

function clusterd._onStatusRes(packet, from)
  -- For v1 we don't track pending status queries; just log. The api
  -- layer can plumb correlation_ids through later.
  log.info(LOG_TAG, "status response from " .. tostring(from):sub(1, 8))
end

function clusterd._onRelayFail(packet, from)
  local p = packet.payload or {}
  state.pushEvent("relay_fail", {
    reason       = p.reason,
    failed_at    = p.failed_at,
    original_dest = p.original_dest,
    original_inner_type = p.original_inner_type,
  })
  log.warn(LOG_TAG, string.format(
    "RELAY_FAIL reason=%s at=%s (inner=%s)",
    tostring(p.reason), tostring(p.failed_at), tostring(p.original_inner_type)))
end

return clusterd
