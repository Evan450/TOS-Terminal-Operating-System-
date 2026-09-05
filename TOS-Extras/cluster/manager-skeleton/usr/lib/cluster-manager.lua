-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster-manager — Manager daemon                            ║
-- ║                                                              ║
-- ║  Spec reference: cluster-protocol-spec-draft.md §§3, 4, 6    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Lifecycle:
--   1. Load /etc/cluster-manager.cfg (Master address, worker count,
--      compute profile, etc.).
--   2. Wait for TOS net layer to be up.
--   3. Send CLUSTER_REGISTER to the Master via the trusted-peer path.
--   4. On CLUSTER_REGISTER_ACK: cache the assigned domain_id and the
--      Master-provided heartbeat_interval.
--   5. Start heartbeat timer.
--   6. Listen for CLUSTER_ASSIGN packets. For each assignment:
--        * Validate locally (size, tasks-count, deadline).
--        * Either accept (ACK then dispatch) or reject (ACK + reason).
--        * Run the tasks (locally on this machine for TOS-workers,
--          or hand off to the OpenOS worker bridge on port 2001+id).
--        * Send CLUSTER_RESULT back when done.
--   7. Handle CLUSTER_CANCEL and CLUSTER_DRAIN per spec.

-- Boot-order-proof requires (#FIX round-1 "cluster services error on
-- boot"): rc.d services load BEFORE the OpenOS compat layer registers
-- the "filesystem"/"event" module aliases, so requiring those names at
-- load time killed this service on every boot ("Module not found:
-- filesystem") — TOS booted fine, the daemon just never ran. The TOS
-- kernel modules are always up by the time rc.d loads (and their API is
-- what this file actually calls: event.interval/cancelTimer, fs.exists/
-- readFile) — prefer them; keep the OpenOS names as fallbacks so off-box
-- tests and OpenOS ports still resolve.
local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local fs       = firstRequire("kernel.fs", "filesystem")
local computer = require("computer")
local event    = firstRequire("kernel.event", "event")
local net      = require("kernel.net")
local protocol = require("kernel.net.protocol")

local log
do
  -- kernel.log first: bare "log" resolves nowhere on TOS, which left the
  -- daemon running with silent no-op logs.
  local mod = firstRequire("kernel.log", "log")
  if mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.mgr"

local mgr = {}

-- ============================================================
-- Module state
-- ============================================================

local _running   = false
local _cfg       = nil     -- merged config (see DEFAULT_CFG)
local _state     = nil     -- run-time state (domain_id, master_addr, ...)
local _listeners = {}      -- net.on() ids to tear down on stop
local _timers    = {}      -- timer ids to cancel on stop
local _inflight  = {}      -- [assignment_id] = { tasks, started_at, ... }
local _bridge    = nil     -- { mod = cluster.worker } when the v2 bridge is up
local _rrCursor  = 0       -- round-robin cursor over idle workers

local CONFIG_PATH = "/etc/cluster-manager.cfg"

local DEFAULT_CFG = {
  master_address           = nil,            -- REQUIRED: hex address of Master
  hostname                 = nil,            -- defaults to /etc/hostname
  compute_profile          = "mixed",        -- "compute_bound" | "io_bound" | "mixed"
  worker_count             = 4,
  -- External storage attached to this node (a RAID block, a tape drive, a
  -- JBOD pool). The Master's scheduler matches a job's storage_preference
  -- against this (§9), so nil means "no external storage" and any job that
  -- names a preference will skip us.
  storage_type             = nil,            -- "raid"|"tape"|"jbod"|"floppy"|"drive"
  storage_capacity         = nil,            -- bytes; operator-declared, 0 if unknown
  cluster_protocol         = "1.0",
  -- How often to retry CLUSTER_REGISTER while we're unregistered.
  register_retry_seconds   = 10,
  -- Lower bound on heartbeat interval — Master suggests one in the ACK,
  -- but we clamp here so a misconfigured Master can't ask us to flood.
  min_heartbeat_seconds    = 2,
  max_heartbeat_seconds    = 30,
  -- Optional: address of a worker bridge (OpenOS worker process) on
  -- the same OC network. If nil, the Manager runs tasks inline.
  worker_bridge_address    = nil,

  -- ── CLUSTER v2 — OpenOS worker bridge (port 2001 + domain) ──────────
  -- When enabled, the Manager registers OpenOS worker machines (the
  -- cluster/openos/cluster-worker.lua daemon) and hands them tasks instead
  -- of running everything inline. Frames are HMAC-authenticated with
  -- worker_bridge_secret (#SEC H21/CR-3 — the SAME 16+ byte secret each
  -- worker's /etc/cluster-worker.cfg carries). Off by default: a Manager
  -- with no workers keeps running tasks inline exactly as before.
  worker_bridge_enabled    = false,
  worker_bridge_domain     = 0,        -- worker port = 2001 + this
  worker_bridge_secret     = nil,      -- REQUIRED when enabled (16+ bytes)
  worker_bridge_bootstrap  = 180,      -- seconds the register window stays open
  -- "opt-in"  → only tasks flagged task.via_bridge run on a worker.
  -- "prefer"  → every task runs on a worker when one is idle (else inline).
  worker_bridge_mode       = "opt-in",
  task_timeout_seconds     = 30,       -- per worker-dispatched task
}

-- ============================================================
-- Helpers
-- ============================================================

local function freshState()
  return {
    registered          = false,
    domain_id           = nil,
    master_addr         = nil,
    heartbeat_interval  = 5,
    last_register_try   = 0,
    workers_active      = 0,
    workers_busy        = 0,
    queue_depth         = 0,
    storage_used        = 0,
    errors_last_min     = 0,
    state               = "active",   -- one of: active, degraded, draining, offline
    started_at          = computer.uptime(),
  }
end

-- fs.readFile + load, NOT io.open/loadfile: neither of those globals
-- exists at rc.d time (compat registers them later, and only when the
-- compat stage runs at all). Text-only load, same as the kernel's rule.
local function loadHostname()
  if not fs.exists("/etc/hostname") then return nil end
  local data = fs.readFile and fs.readFile("/etc/hostname")
  if not data then return nil end
  local name = data:match("[^\r\n]*")
  return name and name:match("^%s*(.-)%s*$") or nil
end

local function loadConfig()
  local out = {}
  for k, v in pairs(DEFAULT_CFG) do out[k] = v end
  if fs.exists(CONFIG_PATH) then
    local src = fs.readFile and fs.readFile(CONFIG_PATH)
    local chunk, err = src and load(src, "=" .. CONFIG_PATH, "t")
    if chunk then
      local ok, result = pcall(chunk)
      if ok and type(result) == "table" then
        for k, v in pairs(result) do out[k] = v end
      else
        log.error(LOG_TAG, "config did not return a table: " .. tostring(result))
      end
    else
      log.error(LOG_TAG, "config load failed: " .. tostring(err))
    end
  end
  if not out.hostname then out.hostname = loadHostname() or "manager" end
  return out
end

-- ============================================================
-- Registration
-- ============================================================

-- Build the §4.1 CLUSTER_REGISTER payload. Pure (cfg + state in, table
-- out) so the storage declaration is unit-testable without a network —
-- see TOS-Dev/usr/lib/tests/test_cluster_storage_pref.lua.
local function registerPayload(cfg, st)
  return {
    hostname         = cfg.hostname,
    profile          = cfg.compute_profile,
    worker_count     = cfg.worker_count,
    -- §4.1. The scheduler reads storage.external_type when matching a
    -- job's storage_preference, and state.registerManager only ever fills
    -- that field from THIS payload. Omitting it left every Manager looking
    -- like external_type="none" forever, so any job naming a preference was
    -- rejected cluster-wide with storage_pref_mismatch. Declared here at
    -- register time; refreshed in-place by the heartbeat (§4.2).
    storage          = {
      external_type     = cfg.storage_type or "none",
      external_capacity = cfg.storage_capacity or 0,
    },
    cluster_protocol = cfg.cluster_protocol,
    started_at       = st.started_at,
  }
end
mgr._registerPayload = registerPayload

local function sendRegister()
  if not _cfg.master_address then
    log.error(LOG_TAG, "no master_address configured; cannot register")
    return false
  end
  local payload = registerPayload(_cfg, _state)
  local pkt = protocol.makePacket(protocol.TYPE.CLUSTER_REGISTER, payload,
    { to = _cfg.master_address })
  local ok, err = net.send(_cfg.master_address, pkt)
  if not ok then
    log.warn(LOG_TAG, "register send failed: " .. tostring(err))
    return false
  end
  _state.last_register_try = computer.uptime()
  log.info(LOG_TAG, "CLUSTER_REGISTER sent to " ..
    _cfg.master_address:sub(1, 8) .. "...")
  return true
end

local function onRegisterAck(packet, from)
  local p = packet.payload or {}
  if from ~= _cfg.master_address then
    log.warn(LOG_TAG, "register_ack from unexpected sender " .. tostring(from))
    return
  end
  if not p.accepted then
    log.error(LOG_TAG, "register rejected: " .. tostring(p.reason))
    -- Stay un-registered; the retry timer will try again periodically
    -- in case the Master's policy changes (e.g. operator un-bans us).
    return
  end
  _state.registered          = true
  _state.domain_id           = p.domain_id
  _state.master_addr         = from
  -- Clamp heartbeat interval to our local bounds.
  local hb = tonumber(p.heartbeat_interval) or 5
  if hb < _cfg.min_heartbeat_seconds then hb = _cfg.min_heartbeat_seconds end
  if hb > _cfg.max_heartbeat_seconds then hb = _cfg.max_heartbeat_seconds end
  _state.heartbeat_interval = hb
  log.info(LOG_TAG, string.format("registered as domain %d (hb=%ds)",
    p.domain_id or -1, hb))
end

-- ============================================================
-- Heartbeat
-- ============================================================

local function sendHeartbeat()
  if not _state.registered or not _state.master_addr then return end
  -- Build a status snapshot. Counters get reset by the operator-side
  -- (errors_last_min) on every send; if we drop a heartbeat the Master
  -- just sees the next one with the accumulated count.
  local snap = {
    state           = _state.state,
    workers_active  = _cfg.worker_count,
    workers_busy    = _state.workers_busy,
    queue_depth     = _state.queue_depth,
    storage_used    = _state.storage_used,
    errors_last_min = _state.errors_last_min,
    uptime          = computer.uptime() - _state.started_at,
  }
  -- If we have a configured external storage (a tape drive, a JBOD
  -- pool, etc.), advertise its type so the scheduler can match jobs.
  if _cfg.storage_type then
    snap.external_type = _cfg.storage_type
  end
  local pkt = protocol.makePacket(protocol.TYPE.CLUSTER_HEARTBEAT, snap,
    { to = _state.master_addr })
  local ok = pcall(net.send, _state.master_addr, pkt)
  if ok then _state.errors_last_min = 0 end
end

-- ============================================================
-- Assignment intake + execution
-- ============================================================

--- Validate an incoming assignment. Returns (true) to accept, or
--- (false, reason) to reject. Cheap checks only — the Manager will
--- ACK before starting execution.
local function validateAssignment(p)
  if type(p) ~= "table" then return false, "payload not a table" end
  if not p.assignment_id then return false, "missing assignment_id" end
  if not p.job_id        then return false, "missing job_id" end
  if p.tasks_inline and #p.tasks_inline > 100 then
    return false, "too many tasks_inline (>100)"
  end
  return true
end

local function sendAssignAck(assignment_id, accepted, reason)
  if not _state.master_addr then return end
  local pkt = protocol.makePacket(protocol.TYPE.CLUSTER_ASSIGN_ACK, {
    assignment_id = assignment_id,
    accepted      = accepted and true or false,
    reason        = reason,
  }, { to = _state.master_addr })
  pcall(net.send, _state.master_addr, pkt)
end

local function sendResult(assignment_id, status, output, errors, stats)
  if not _state.master_addr then return end
  local pkt = protocol.makePacket(protocol.TYPE.CLUSTER_RESULT, {
    assignment_id = assignment_id,
    status        = status,
    output_inline = output,
    errors        = errors,
    stats         = stats,
  }, { to = _state.master_addr })
  pcall(net.send, _state.master_addr, pkt)
end

-- CLUSTER-7 — task cancellation primitive.
-- Each inflight entry carries a `cancelled` flag. We run task bodies
-- in a coroutine with a debug.sethook installed by the SCHEDULER (not
-- by the task itself — the task's env doesn't expose `debug` at all,
-- mirroring the M31 preemption pattern in kernel.process). The hook
-- checks the flag every N instructions and raises `error("cancelled")`
-- to terminate the coroutine when the flag flips.
--
-- This means two flavors of cancellation work:
--   1. Between-tasks: dispatchAssignment checks `_inflight[id].cancelled`
--      after each task and bails before starting the next.
--   2. Mid-task: the hook fires inside the task's VM loop and errors
--      out, even if the task is in `while true do end`.

--- Execute one inline task. Each task is a Lua table of the shape
--- { code = "<lua source>", input = <any> }. The code runs in a
--- sandboxed env with the input bound as `_input`. Output is whatever
--- the chunk returns.
--- @param task table — task spec
--- @param inflight table — _inflight[id] record (so the hook can read .cancelled)
local function runOneTask(task, inflight)
  if type(task) ~= "table" or type(task.code) ~= "string" then
    return nil, "malformed task"
  end
  -- Tight sandbox — no fs, no component, no net. Just math/string/etc.
  -- Tasks that need real I/O should be dispatched to the OpenOS worker
  -- bridge instead (where the OpenOS sandbox is more permissive by
  -- design).
  local env = {
    _input = task.input,
    math    = math, string = string, table = table,
    pairs   = pairs, ipairs = ipairs, next = next, select = select,
    type    = type, tostring = tostring, tonumber = tonumber,
    error   = error, pcall = pcall, xpcall = xpcall,
  }
  local fn, lerr = load(task.code, "=cluster:task", "t", env)
  if not fn then return nil, "compile: " .. tostring(lerr) end

  -- CLUSTER-7 — run inside a coroutine so the hook can yank us out.
  local co = coroutine.create(fn)
  -- Install the cancellation hook from OUR (kernel-managed) side.
  -- 5000 instructions ≈ "check every few VM ops on OC" — small enough
  -- that cancellation latency is fast, large enough that the overhead
  -- is negligible. error() across the C boundary is allowed (unlike
  -- coroutine.yield from a count hook).
  if type(debug) == "table" and debug.sethook and inflight then
    pcall(debug.sethook, co, function()
      if inflight.cancelled then
        error("cancelled by CLUSTER_CANCEL", 0)
      end
    end, "", 5000)
  end

  local ok, result = coroutine.resume(co)
  -- Tear down the hook unconditionally — leaving it set on a now-dead
  -- coroutine wouldn't fire, but the test discipline of "every hook
  -- gets torn down" makes future refactors safer.
  if type(debug) == "table" and debug.sethook then
    pcall(debug.sethook, co)
  end

  if not ok then
    -- Distinguish "cancelled" from real errors so the caller can
    -- report status="cancelled" instead of status="failed".
    local msg = tostring(result)
    if msg:find("cancelled", 1, true) then
      return nil, "cancelled"
    end
    return nil, "runtime: " .. msg
  end
  return result
end

-- CLUSTER v2 — assignment dispatch can now run each task EITHER inline on
-- the Manager OR on a registered OpenOS worker over the authenticated bridge.
-- Worker dispatch is asynchronous (results arrive in later event-loop ticks),
-- so the assignment is finished by a callback once every task has reported,
-- not by a straight-line loop. The two pure helpers below are unit-tested.

--- Dominant status for an assignment from its per-task tallies. Cancellation
--- wins (the operator asked us to stop); else ok / failed (all errored) /
--- partial. Shared by the inline and bridge result paths.
local function aggregateStatus(total, errorCount, cancelledCount)
  if cancelledCount > 0 then return "cancelled" end
  if errorCount == 0 then return "ok" end
  if total > 0 and errorCount == total then return "failed" end
  return "partial"
end
mgr._aggregateStatus = aggregateStatus

--- Where a task runs: "bridge" (an OpenOS worker) or "inline" (the Manager).
--- Bridge only when one is up AND the task opts in (via_bridge) or the
--- Manager policy prefers it. Inline is the safe, I/O-free default.
local function routeTask(task, bridgeAvailable, mode)
  if not bridgeAvailable then return "inline" end
  if type(task) == "table" and task.via_bridge == true then return "bridge" end
  if mode == "prefer" then return "bridge" end
  return "inline"
end
mgr._routeTask = routeTask

--- Round-robin pick of an idle bridge worker, or nil if none/no bridge.
local function pickIdleWorker()
  if not _bridge or not _bridge.mod or not _bridge.mod.list then return nil end
  local idle = {}
  for _, w in ipairs(_bridge.mod.list()) do
    if w.state == "idle" then idle[#idle + 1] = w.addr end
  end
  if #idle == 0 then return nil end
  _rrCursor = (_rrCursor % #idle) + 1
  return idle[_rrCursor]
end

--- A per-assignment result COLLECTOR. State-free w.r.t. the module (takes
--- the task count + an onDone callback), so it unit-tests in isolation.
--- collector.record(i, res, err) is idempotent PER INDEX — a worker result
--- racing a cancel for the same task can't double-count, and the assignment
--- finishes exactly once (onDone) when every task has reported. err shapes:
--- nil = ok, "cancelled" = cancelled, anything else = an error string.
local function newCollector(total, onDone)
  local c = {
    total = total, done = 0, errorCount = 0, cancelledCount = 0,
    outputs = {}, errors = {}, recorded = {}, finished = false,
  }
  local function maybeFinish()
    if c.finished or c.done < c.total then return end
    c.finished = true
    onDone(aggregateStatus(c.total, c.errorCount, c.cancelledCount),
      c.outputs, c.errorCount > 0 and c.errors or nil,
      { errorCount = c.errorCount, cancelledCount = c.cancelledCount })
  end
  function c.record(i, res, err)
    if c.recorded[i] then return end
    c.recorded[i] = true
    c.outputs[i] = res
    if err == "cancelled" then
      c.cancelledCount = c.cancelledCount + 1
    elseif err then
      c.errors[i] = err
      c.errorCount = c.errorCount + 1
    end
    c.done = c.done + 1
    maybeFinish()
  end
  if total <= 0 then maybeFinish() end   -- empty assignment finishes now
  return c
end
mgr._newCollector = newCollector

-- Map an OpenOS worker RESULT frame's status to our (res, err) shape.
local function workerResultToErr(result)
  local s = result.status
  if s == "ok"        then return result.output, nil end
  if s == "cancelled" then return result.output, "cancelled" end
  if s == "timeout"   then return result.output, "timeout: " .. tostring(result.err or "") end
  return result.output, result.err or s or "worker error"
end

local function dispatchAssignment(p)
  local id = p.assignment_id
  local tasks = p.tasks_inline or {}
  local started_at = computer.uptime()
  local inflight = { id = id, p = p, cancelled = false, bridgeTids = {} }
  _inflight[id] = inflight
  _state.workers_busy = _state.workers_busy + 1

  inflight.collector = newCollector(#tasks,
    function(status, outputs, errors, tallies)
      _state.workers_busy   = math.max(0, _state.workers_busy - 1)
      _state.errors_last_min = _state.errors_last_min + (tallies.errorCount or 0)
      _inflight[id] = nil
      sendResult(id, status, outputs, errors, {
        duration        = computer.uptime() - (p.dispatched_at or started_at),
        task_count      = #tasks,
        error_count     = tallies.errorCount,
        cancelled_count = tallies.cancelledCount,
      })
    end)

  -- Empty assignment already finished inside newCollector.
  if #tasks == 0 then return end

  local record = inflight.collector.record
  for i, task in ipairs(tasks) do
    if inflight.cancelled then
      record(i, nil, "cancelled")
    else
      local route = routeTask(task, _bridge ~= nil, _cfg.worker_bridge_mode)
      local addr = (route == "bridge") and pickIdleWorker() or nil
      if addr then
        local tid = _bridge.mod.dispatch(addr, task.code, {
          inputs  = task.input,
          timeout = _cfg.task_timeout_seconds,
          on_result = function(_wa, _tid, result)
            inflight.bridgeTids[i] = nil
            record(i, workerResultToErr(result))
          end,
        })
        if tid then
          inflight.bridgeTids[i] = tid          -- finished later by the callback
        else
          -- Worker went busy/away between pick and dispatch — run inline.
          record(i, runOneTask(task, inflight))
        end
      else
        record(i, runOneTask(task, inflight))
      end
    end
  end
  -- All-inline assignments finished on the last record(); bridge tasks finish
  -- via their callbacks. record() is idempotent, so nothing double-fires.
end

local function onAssign(packet, from)
  if from ~= _state.master_addr then
    log.warn(LOG_TAG, "assign from non-master " .. tostring(from):sub(1, 8))
    return
  end
  local p = packet.payload or {}
  local ok, why = validateAssignment(p)
  if not ok then
    sendAssignAck(p.assignment_id, false, why)
    return
  end
  if _state.state == "draining" then
    sendAssignAck(p.assignment_id, false, "draining")
    return
  end
  sendAssignAck(p.assignment_id, true)
  -- Run in a separate event-loop cycle so this handler returns fast
  -- (the spec mandates an ACK within a heartbeat interval).
  event.timer(0.1, function() pcall(dispatchAssignment, p) end)
end

local function onCancel(packet, from)
  -- CLUSTER-7 — REAL cancellation: flip the inflight record's
  -- `cancelled` flag. The hook installed by runOneTask reads the flag
  -- every ~5000 VM instructions and raises error("cancelled") to yank
  -- the running task body. dispatchAssignment then propagates the
  -- "cancelled" status all the way to the Master via sendResult.
  --
  -- We do NOT clear _inflight here. That happens at the END of
  -- dispatchAssignment after the task loop unwinds, so the bookkeeping
  -- stays consistent regardless of where the cancellation lands
  -- (between tasks vs. mid-task vs. just after the last task finished
  -- legitimately).
  local p = packet.payload or {}
  local in_f = _inflight[p.assignment_id]
  if not in_f then
    -- The Master cancelled an assignment we don't have inflight. Could
    -- be a stale cancel arriving after we already finished. Send a
    -- best-effort cancelled-shaped result back so the Master's view
    -- doesn't sit in "running" forever, matching the old behaviour.
    sendResult(p.assignment_id, "cancelled", nil, nil,
      { reason = "cancel_for_unknown_inflight" })
    return
  end
  if from and from ~= _state.master_addr then
    log.warn(LOG_TAG, "cancel from non-master " .. tostring(from):sub(1, 8) .. " ignored")
    return
  end
  in_f.cancelled = true
  -- CLUSTER v2 — tasks already out on a worker won't be stopped by the
  -- inline sethook, so cancel them on the bridge and record each as
  -- cancelled. recordTaskResult is per-index idempotent, so a worker result
  -- that races this cancel is harmless, and finishing the assignment no
  -- longer depends on a callback that may never arrive after a bridge cancel.
  if in_f.bridgeTids and in_f.collector then
    for i, tid in pairs(in_f.bridgeTids) do
      if _bridge and _bridge.mod and _bridge.mod.cancel then
        pcall(_bridge.mod.cancel, tid)
      end
      in_f.collector.record(i, nil, "cancelled")
    end
  end
  log.info(LOG_TAG, string.format("cancel flagged for assignment %d", p.assignment_id))
end

local function onDrain(packet, from)
  if from ~= _state.master_addr then return end
  log.info(LOG_TAG, "drain requested")
  _state.state = "draining"
end

-- ============================================================
-- Timer ticks
-- ============================================================

local function registerTick()
  if _state.registered then return end
  if computer.uptime() - _state.last_register_try < _cfg.register_retry_seconds then
    return
  end
  sendRegister()
end

local function heartbeatTick()
  if not _state.registered then return end
  sendHeartbeat()
end

-- ============================================================
-- Public API
-- ============================================================

function mgr.start()
  if _running then return true end
  _cfg = loadConfig()
  _state = freshState()
  if not _cfg.master_address then
    log.error(LOG_TAG, "no master_address in /etc/cluster-manager.cfg; refusing to start")
    return false, "no master_address"
  end

  -- Register packet listeners.
  local function add(typeStr, cb)
    local id = net.on(typeStr, cb)
    _listeners[#_listeners + 1] = { type = typeStr, id = id }
  end
  add(protocol.TYPE.CLUSTER_REGISTER_ACK, onRegisterAck)
  add(protocol.TYPE.CLUSTER_ASSIGN,       onAssign)
  add(protocol.TYPE.CLUSTER_CANCEL,       onCancel)
  add(protocol.TYPE.CLUSTER_DRAIN,        onDrain)

  -- Start timers. Registration retry runs more aggressively than the
  -- heartbeat — once we're up, the heartbeat takes over.
  _timers.register = event.interval(_cfg.register_retry_seconds,
    registerTick, "cluster-mgr.register")
  -- Heartbeat ticks at min_heartbeat_seconds initially; we re-use the
  -- same timer slot but the actual send is gated on registered=true.
  _timers.heartbeat = event.interval(_cfg.min_heartbeat_seconds,
    heartbeatTick, "cluster-mgr.heartbeat")

  -- CLUSTER v2 — bring up the OpenOS worker bridge if configured. Failures
  -- here are non-fatal: the Manager falls back to inline execution and logs
  -- why, rather than refusing to start. setDomainId default-denies without a
  -- valid shared secret (#SEC CR-3), so a misconfigured bridge stays off.
  if _cfg.worker_bridge_enabled then
    local okW, cworker = pcall(require, "cluster.worker")
    if not okW or not cworker then
      log.warn(LOG_TAG, "worker_bridge_enabled but cluster.worker module unavailable; running inline")
    else
      if cworker.init then pcall(cworker.init, { log = log, event = event }) end
      local sOk, sErr = cworker.setSecret(_cfg.worker_bridge_secret)
      if not sOk then
        log.error(LOG_TAG, "worker bridge disabled: " .. tostring(sErr))
      else
        local dOk, dErr = cworker.setDomainId(_cfg.worker_bridge_domain or 0)
        if not dOk then
          log.error(LOG_TAG, "worker bridge bind failed: " .. tostring(dErr))
        else
          pcall(cworker.setBootstrap, _cfg.worker_bridge_bootstrap)
          _bridge = { mod = cworker }
          log.info(LOG_TAG, string.format(
            "worker bridge up (domain %d, mode '%s', %ds bootstrap)",
            _cfg.worker_bridge_domain or 0, _cfg.worker_bridge_mode,
            _cfg.worker_bridge_bootstrap or 0))
        end
      end
    end
  end

  -- Try first register immediately (don't wait for the timer).
  sendRegister()

  _running = true
  log.info(LOG_TAG, "started (master=" .. _cfg.master_address:sub(1, 8) .. "...)")
  return true
end

function mgr.stop()
  if not _running then return true end
  for _, l in pairs(_listeners) do
    pcall(net.off, l.type, l.id)
  end
  _listeners = {}
  for _, tid in pairs(_timers) do pcall(event.cancelTimer, tid) end
  _timers = {}
  -- CLUSTER v2 — tear the worker bridge down (closes its port + timers).
  if _bridge and _bridge.mod and _bridge.mod.stop then
    pcall(_bridge.mod.stop)
  end
  _bridge = nil
  _running = false
  _state.registered = false
  log.info(LOG_TAG, "stopped")
  return true
end

--- Snapshot of the OpenOS worker bridge (empty list when the bridge is off).
function mgr.workers()
  if not _bridge or not _bridge.mod or not _bridge.mod.list then return {} end
  return _bridge.mod.list()
end

function mgr.status()
  if not _running then return { running = false } end
  local bridge_workers = 0
  if _bridge and _bridge.mod and _bridge.mod.list then
    bridge_workers = #_bridge.mod.list()
  end
  return {
    running             = true,
    registered          = _state.registered,
    domain_id           = _state.domain_id,
    master_addr         = _state.master_addr,
    state               = _state.state,
    bridge_enabled      = _bridge ~= nil,
    bridge_workers      = bridge_workers,
    workers_active      = _cfg.worker_count,
    workers_busy        = _state.workers_busy,
    queue_depth         = _state.queue_depth,
    errors_last_min     = _state.errors_last_min,
    uptime              = computer.uptime() - _state.started_at,
    inflight_assignments = (function()
      local n = 0; for _ in pairs(_inflight) do n = n + 1 end; return n
    end)(),
  }
end

function mgr.drain()  _state.state = "draining"; return true end
function mgr.undrain() _state.state = "active";   return true end

-- ============================================================
-- CLUSTER-6 — Pairing (Manager side)
-- ============================================================
-- Operator-facing helper. Called by the cluster-manager CLI's `pair`
-- subcommand. Takes the Master's address and the pairing code shown on
-- the Master's screen by `cluster pair start`. Derives the same secret
-- the Master derived, applies it to the LOCAL trust DB at TRUSTED
-- level, and sends CLUSTER_PAIR_INIT carrying a MAC the Master can
-- verify. On a successful CLUSTER_PAIR_CONFIRM reply the Manager is
-- ready for normal CLUSTER_REGISTER traffic.
function mgr.pair(masterAddr, code, opts)
  opts = opts or {}
  if type(masterAddr) ~= "string" or #masterAddr < 16 then
    return false, "invalid master address"
  end
  if type(code) ~= "string" or #code < 12 then
    return false, "pairing code looks too short"
  end
  -- Lazy-load the crypto module — pair is called from the CLI before
  -- mgr.start() has wired up state, so we don't want to require it at
  -- module load time.
  local crypto = require("kernel.crypto")
  local trustMod = require("kernel.net.trust")

  -- Same derivation as the Master side. Domain-separated so a vault
  -- passphrase reuse can't double as a cluster trust secret.
  local secret = crypto.hashPassword(code, "tos-cluster-pair-v1")

  -- Apply locally FIRST so even if the round-trip fails, the operator
  -- can re-run `cluster pair` later and resume from the Manager side
  -- via `net trust gen` (the Manager already has the right secret).
  local TIER_ROOT = 3
  local ok1 = pcall(trustMod.setLevel, "root", masterAddr, trustMod.LEVEL.TRUSTED, TIER_ROOT)
  local ok2 = pcall(trustMod.setSecret, "root", masterAddr, secret, TIER_ROOT)
  if not (ok1 and ok2) then
    return false, "could not update local trust DB (admin tier required?)"
  end

  -- Send CLUSTER_PAIR_INIT. Use a one-shot listener for the confirm
  -- with a 10-second deadline.
  local ts = computer.uptime()
  local mac = crypto.hmac(secret, tostring(masterAddr) .. "|" .. tostring(ts))
  local init = protocol.makePacket(protocol.TYPE.CLUSTER_PAIR_INIT, {
    mac = mac,
    ts  = ts,
  }, { to = masterAddr })

  local got_confirm = false
  local confirm_err = nil
  local listenerId = net.on(protocol.TYPE.CLUSTER_PAIR_CONFIRM, function(packet, from)
    if from ~= masterAddr then return end
    local p = packet.payload or {}
    if type(p.mac) ~= "string" or type(p.ts) ~= "number" then
      confirm_err = "malformed confirm"; return
    end
    local expected = crypto.hmac(secret,
      -- Master MACs over OUR address + their timestamp. We're the
      -- recipient of that MAC, so the address it covers is OUR address
      -- (computed by the kernel from our local modem addr).
      tostring(_state and _state.master_addr or masterAddr) .. "|" ..
      tostring(p.ts))
    -- The exchange is symmetric in the sense that BOTH sides know
    -- which address each MAC covers. The simplest test that's robust
    -- against asymmetric address-knowledge: try matching against our
    -- modem address.
    if crypto.ctEquals(expected, p.mac) then
      got_confirm = true
    else
      -- Fall back: maybe the master MACed over our outbound address
      -- as it appeared at receive — try a sniff of the inbound source.
      -- Without a clean way to get our own modem address from here,
      -- just accept any MAC that matches the timestamp shape. The
      -- crypto.ctEquals above is the canonical check.
      confirm_err = "MAC mismatch"
    end
  end)

  local ok_send, send_err = pcall(net.send, masterAddr, init)
  if not ok_send then
    net.off(protocol.TYPE.CLUSTER_PAIR_CONFIRM, listenerId)
    return false, "send failed: " .. tostring(send_err)
  end

  -- Wait up to 10 seconds for the confirm.
  local deadline = computer.uptime() + 10
  while not got_confirm and computer.uptime() < deadline do
    event.pull(0.25)
  end
  net.off(protocol.TYPE.CLUSTER_PAIR_CONFIRM, listenerId)

  if got_confirm then
    -- Stash the master_address into the running cfg if we're already
    -- started, so the next REGISTER goes to the right place.
    if _state then _state.master_addr = masterAddr end
    return true, "paired"
  end
  -- Even on timeout the LOCAL trust DB is set correctly — the operator
  -- can verify with `net trust list` and proceed manually if the
  -- confirm got lost in a transient network hiccup.
  return false, "no confirm received within 10s (local trust DB still updated; check net link). " ..
    (confirm_err or "")
end

return mgr
