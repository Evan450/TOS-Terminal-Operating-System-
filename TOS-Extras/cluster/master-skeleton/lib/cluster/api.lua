-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.api — In-process API for the `cluster` CLI          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Bridge between the operator-facing CLI (`cluster`) and the daemon
-- (`clusterd`). The CLI requires this module and calls its functions
-- directly; because TOS is cooperative, they share address space within
-- the user's shell process for read operations. For write operations
-- the API acquires the state lock (state.withLock) before mutating.
--
-- Design rule: this module is the ONLY entrypoint the CLI uses. It
-- exists so that the CLI can't accidentally touch state directly —
-- making the (daemon, CLI) contract explicit and small.

local computer = require("computer")

local api = {}

local _state, _scheduler, _jobs, _clusterd
local _bound = false

-- Lazy require for cluster.net so this module loads even when the
-- daemon hasn't been started (e.g. CLI autoloaded during shell init).
local function _netmod()
  return package.loaded["cluster.net"] or require("cluster.net")
end

-- ============================================================
-- Binding
-- ============================================================

function api.bind(state, scheduler, jobs, clusterd)
  _state     = state
  _scheduler = scheduler
  _jobs      = jobs
  _clusterd  = clusterd
  _bound     = true
end

function api.unbind()
  _state, _scheduler, _jobs, _clusterd = nil, nil, nil, nil
  _bound = false
end

local function _requireBound()
  if not _bound then
    error("cluster daemon is not running (clusterd not started)", 2)
  end
end

-- ============================================================
-- Job spec validation
-- ============================================================

local VALID_PROFILES = { compute_bound = true, io_bound = true, mixed = true }
local VALID_POLICIES = { safe = true, once = true, none = true }
local VALID_SINKS    = { inline = true, public = true }

local function _validateJobSpec(spec)
  if type(spec) ~= "table" then return false, "invalid_spec: not a table" end
  if spec.tasks ~= nil and type(spec.tasks) ~= "table" then
    return false, "invalid_tasks: not a table"
  end
  if spec.compute_profile and not VALID_PROFILES[spec.compute_profile] then
    return false, "invalid_compute_profile: " .. tostring(spec.compute_profile)
  end
  if spec.retry_policy and not VALID_POLICIES[spec.retry_policy] then
    return false, "invalid_retry_policy: " .. tostring(spec.retry_policy)
  end
  if spec.result_sink and not VALID_SINKS[spec.result_sink] then
    return false, "invalid_result_sink: " .. tostring(spec.result_sink)
  end
  if spec.priority ~= nil then
    local p = tonumber(spec.priority)
    if not p or p < 0 or p > 9 then
      return false, "invalid_priority: must be 0..9"
    end
  end
  return true
end

-- ============================================================
-- Inspection (read-only; no lock needed for simple reads)
-- ============================================================

function api.status()
  _requireBound()
  local s = {
    managers = { active = 0, degraded = 0, draining = 0, offline = 0 },
    jobs     = { pending = 0, running = 0, done = 0, failed = 0, cancelled = 0 },
    storage  = nil,
    host_thread_budget      = _clusterd and _clusterd.getConfig and
                              (_clusterd.getConfig().host_thread_budget) or nil,
    compute_bound_in_flight = _state.computeBoundInFlight(),
    uptime                  = computer.uptime(),
  }
  for _, m in pairs(_state._data.managers) do
    local st = m.state or "offline"
    s.managers[st] = (s.managers[st] or 0) + 1
  end
  for _, j in pairs(_state._data.jobs) do
    local st = j.state or "pending"
    s.jobs[st] = (s.jobs[st] or 0) + 1
  end
  if _state._data.storage_node then
    local sn = _state._data.storage_node
    s.storage = {
      configured     = true,
      address        = sn.address,
      used_bytes     = sn.used,
      capacity_bytes = sn.capacity,
      last_seen      = sn.last_seen,
    }
  end
  return s
end

function api.listManagers(filter)
  _requireBound()
  return _state.listManagers(filter)
end

function api.getManager(domain_id)
  _requireBound()
  if not domain_id then return nil, "missing_argument: domain_id" end
  return _state.getManagerByDomainId(tonumber(domain_id))
end

function api.listJobs(filter)
  _requireBound()
  return _state.listJobs(filter)
end

function api.getJob(job_id)
  _requireBound()
  if not job_id then return nil, "missing_argument: job_id" end
  -- Answers the same condition the same way api.retryJob does. These two
  -- used to disagree — bare nil here, `nil, "no such job"` there — which
  -- is exactly the ambiguity a caller cannot code against.
  local j = _state.getJob(tonumber(job_id))
  if not j then return nil, "no_such_job" end
  -- Return a shallow copy of the job with assignments as a sorted array
  -- for easier CLI display.
  local out = {}
  for k, v in pairs(j) do out[k] = v end
  local arr = {}
  for _, a in pairs(j.assignments or {}) do arr[#arr + 1] = a end
  table.sort(arr, function(a, b) return (a.assignment_id or 0) < (b.assignment_id or 0) end)
  out.assignments_list = arr
  return out
end

function api.storageStatus()
  _requireBound()
  local sn = _state._data.storage_node
  if not sn then return nil end
  return {
    address        = sn.address,
    used_bytes     = sn.used,
    capacity_bytes = sn.capacity,
    last_seen      = sn.last_seen,
  }
end

function api.recentEvents(n)
  _requireBound()
  return _state.recentEvents(n or 20)
end

-- ============================================================
-- Job management (mutating; require lock)
-- ============================================================

function api.submit(jobSpec)
  _requireBound()
  local ok, err = _validateJobSpec(jobSpec)
  if not ok then return nil, err end

  -- Fast refusal if there's no capacity at all.
  if not _scheduler.hasAnyActiveCapacity(_state._data.managers) then
    return nil, "no_eligible_manager: no active managers with free workers"
  end

  -- Fill in who submitted this for audit, if caller didn't set it.
  local okUsers, users = pcall(require, "users")
  if okUsers and users and not jobSpec.submitted_by then
    local sess = users.currentSession and users.currentSession()
    if sess and sess.user then jobSpec.submitted_by = sess.user end
  end

  local job_id
  _state.withLock(function()
    job_id = _state.createJob(jobSpec)
    _jobs.splitIntoAssignments(job_id, jobSpec, _state)
  end)
  return job_id
end

function api.cancelJob(job_id)
  _requireBound()
  job_id = tonumber(job_id)
  if not job_id then return false, "missing_argument: job_id" end
  local job = _state.getJob(job_id)
  if not job then return false, "no_such_job" end
  if job.state == "done" or job.state == "failed" or job.state == "cancelled" then
    return false, "wrong_state: job already terminal, " .. tostring(job.state)
  end

  local net = _netmod()
  _state.withLock(function()
    for aid, a in pairs(job.assignments) do
      if a.state == "running" and a.assigned_to then
        pcall(net.sendCancel, a.assigned_to, aid)
      end
      if a.state == "pending" or a.state == "running" then
        _state.setAssignmentState(job_id, aid, "cancelled",
          { completed_at = computer.uptime() })
      end
    end
    _state.setJobState(job_id, "cancelled")
  end)
  return true
end

function api.retryJob(job_id)
  _requireBound()
  job_id = tonumber(job_id)
  if not job_id then return nil, "missing_argument: job_id" end
  local job = _state.getJob(job_id)
  if not job then return nil, "no_such_job" end
  if job.state ~= "failed" then
    return nil, "wrong_state: only failed jobs can be retried (state=" .. tostring(job.state) .. ")"
  end
  -- Deep-copy the spec, reset submitted_at implicitly via createJob.
  local new_id
  _state.withLock(function()
    local fresh = {}
    for k, v in pairs(job.spec or {}) do fresh[k] = v end
    fresh.submitted_by = fresh.submitted_by or job.submitted_by
    new_id = _state.createJob(fresh)
    _jobs.splitIntoAssignments(new_id, fresh, _state)
  end)
  return new_id
end

-- ============================================================
-- Manager management (mutating)
-- ============================================================

function api.drainManager(domain_id)
  _requireBound()
  domain_id = tonumber(domain_id)
  if not domain_id then return false, "missing_argument: domain_id" end
  local m = _state.getManagerByDomainId(domain_id)
  if not m then return false, "no_such_domain" end
  if m.state == "offline" then return false, "wrong_state: already offline" end

  local net = _netmod()
  pcall(net.sendDrain, m.address)
  _state.setManagerState(m.address, "draining")
  return true
end

function api.undrainManager(domain_id)
  _requireBound()
  domain_id = tonumber(domain_id)
  if not domain_id then return false, "missing_argument: domain_id" end
  local m = _state.getManagerByDomainId(domain_id)
  if not m then return false, "no_such_domain" end
  if m.state ~= "draining" then
    return false, "wrong_state: manager is not draining (state=" .. tostring(m.state) .. ")"
  end
  _state.setManagerState(m.address, "active")
  return true
end

function api.forgetManager(domain_id)
  _requireBound()
  domain_id = tonumber(domain_id)
  if not domain_id then return false, "missing_argument: domain_id" end
  local m = _state.getManagerByDomainId(domain_id)
  if not m then return false, "no_such_domain" end
  if m.state ~= "offline" then
    return false, "wrong_state: refusing to forget online manager (state=" .. tostring(m.state) ..
                  "); drain first"
  end
  _state.withLock(function()
    _jobs.onManagerOffline(domain_id, _state)
    _state.forgetManager(m.address)
  end)
  return true
end

-- ============================================================
-- Config
-- ============================================================

-- Keys the operator can tune at runtime. Keys marked restart_required
-- take effect only after `rc restart clusterd`.
local TUNABLE_KEYS = {
  host_thread_budget       = { type = "number", restart_required = false },
  heartbeat_interval       = { type = "number", restart_required = true  },
  heartbeat_degraded_after = { type = "number", restart_required = false },
  heartbeat_offline_after  = { type = "number", restart_required = false },
  scheduler_tick_interval  = { type = "number", restart_required = true  },
  status_snapshot_interval = { type = "number", restart_required = true  },
  heartbeat_sweep_interval = { type = "number", restart_required = true  },
  storage_node_address     = { type = "string", restart_required = false },
}

-- ============================================================
-- Pairing (CLUSTER-6)
-- ============================================================

--- Start a pairing window on the daemon.
--- Returns { code, expires_in } on success, or nil, err.
--- The window is returned as a table rather than as (code, expires_in):
--- the second slot of a `value, err` function is the error slot, and
--- filling it with a number on success meant no caller could read it
--- without already knowing the outcome.
function api.startPairing()
  _requireBound()
  if not _clusterd or not _clusterd.startPairing then
    return nil, "pairing_unsupported"
  end
  local code, expires_at = _clusterd.startPairing()
  return { code = code, expires_in = expires_at - computer.uptime() }
end

--- Close the active pairing window without waiting for expiry.
function api.closePairing()
  _requireBound()
  if not _clusterd or not _clusterd.closePairing then
    return false, "pairing_unsupported"
  end
  _clusterd.closePairing()
  return true
end

--- Inspect the pairing window. Returns { expires_in, paired } if one is
--- open, bare nil if none is (absence, not failure), or nil, err if the
--- daemon has no pairing support at all.
function api.pairingInfo()
  _requireBound()
  if not _clusterd or not _clusterd.pairingInfo then
    return nil, "pairing_unsupported"
  end
  return _clusterd.pairingInfo()
end

function api.getConfig()
  _requireBound()
  local cfg = _clusterd and _clusterd.getConfig and _clusterd.getConfig() or {}
  -- Return a shallow copy so the caller can't mutate the live config.
  local out = {}
  for k, v in pairs(cfg) do out[k] = v end
  return out
end

function api.setConfig(key, value)
  _requireBound()
  local spec = TUNABLE_KEYS[key]
  if not spec then
    return false, "invalid_key: unknown or read-only, " .. tostring(key)
  end
  if spec.type == "number" then
    local n = tonumber(value)
    if not n then return false, "invalid_value: must be numeric" end
    value = n
  elseif spec.type == "string" then
    if type(value) ~= "string" then return false, "invalid_value: must be a string" end
  end
  local cfg = _clusterd and _clusterd.getConfig and _clusterd.getConfig()
  if cfg then cfg[key] = value end
  return true, { restart_required = spec.restart_required }
end

return api
