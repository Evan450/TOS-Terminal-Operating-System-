-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.state — Cluster state store                         ║
-- ║  In-memory master state + load/save to persistence           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- State persistence strategy: write-through on mutations, NOT journaled.
-- Losing the last ~500ms on crash is acceptable; losing the fact that a
-- Manager exists is not. Mutations that change registry membership or
-- job state call save() synchronously. Heartbeat updates do not — they're
-- rebuilt from the next heartbeat round on restart.

-- Boot-order-proof requires (#FIX round-1 "cluster services error on
-- boot"): the OpenOS "filesystem"/"event" aliases don't exist yet when
-- rc.d loads this via clusterd — prefer the TOS kernel modules, keep
-- the OpenOS names as fallbacks for off-box tests.
local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local serialize = require("kernel.serialize")
local fs        = firstRequire("kernel.fs", "filesystem")
local computer  = require("computer")
local event     = firstRequire("kernel.event", "event")

-- Best-effort log — not critical to state correctness.
local log
do
  local mod = firstRequire("kernel.log", "log")
  if mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.state"

local state = {}

-- Sentinel for "unset this field". `{ assigned_to = nil }` is an EMPTY
-- table in Lua: the key is never created, so the pairs() walk in
-- setAssignmentState never visits it and the old value silently survives.
-- Every requeue path meant to clear the assignee and none of them did,
-- which left pending assignments still naming the Manager they had just
-- been taken off — the "MGR" column in `cluster jobs`. Callers that mean
-- "delete this key" pass state.CLEAR.
state.CLEAR = setmetatable({}, { __tostring = function() return "<clear>" end })

-- ============================================================
-- In-memory state (the canonical data; see §0.5.4 of the spec)
-- ============================================================

local function freshData()
  return {
    managers = {},                     -- [address] = { hostname, domain_id, ... }
    domain_id_counter = 1,

    storage_node = nil,                -- { address, capacity, used, last_seen } or nil

    jobs = {},                         -- [job_id] = { ... }
    job_id_counter = 1,
    assignment_id_counter = 1,

    -- Runtime-only; NOT persisted
    _runtime = {
      compute_bound_in_flight = 0,
      events = {},                     -- ring buffer; see pushEvent
      events_head = 1,
      events_size = 0,
      EVENTS_MAX = 128,
      lock_held = false,               -- cooperative lock for CLI ↔ daemon
    },
  }
end

state._data = freshData()

-- ============================================================
-- Cooperative lock
-- ============================================================
-- Because TOS is cooperative, "acquiring" a lock means checking a flag
-- and yielding until it clears. Any state mutation that spans multiple
-- yield points MUST wrap in state.withLock().

function state.withLock(fn, ...)
  local rt = state._data._runtime
  local waited = 0
  while rt.lock_held do
    -- Cooperative yield; 50ms is short enough that contention doesn't
    -- stall the CLI visibly but long enough that we aren't busy-looping.
    local ok, pull = pcall(event.pull, 0.05)
    if not ok then
      -- event.pull missing — bare sleep as fallback
      local deadline = computer.uptime() + 0.05
      while computer.uptime() < deadline do end
    end
    waited = waited + 1
    -- Safety valve: if we've waited ~10s the other holder is wedged.
    if waited > 200 then
      error("cluster.state: lock wait timed out (held by stuck caller)", 2)
    end
  end
  rt.lock_held = true
  local args = {...}
  local ok, r1, r2, r3 = pcall(function() return fn(table.unpack(args)) end)
  rt.lock_held = false
  if not ok then error(r1, 2) end
  return r1, r2, r3
end

-- ============================================================
-- Persistence
-- ============================================================

local _statePath  -- set by init()

function state.init(statePath)
  _statePath = statePath
end

--- Validate enough of the persisted shape that downstream code doesn't
-- have to defensively nil-check every field. Returns (ok, reason).
--
-- The reasons here are deliberately prose, not codes: this is a private
-- helper and its reason is the *detail* half of the caller's error.
-- state.load wraps them as "bad_state_shape: <reason>", so the stable
-- code is minted once at the public boundary rather than seven times
-- here. See error-conventions.md §4.
local function validateShape(d)
  if type(d) ~= "table" then return false, "root not a table" end
  if type(d.managers) ~= "table" then return false, "managers not a table" end
  if type(d.jobs) ~= "table" then return false, "jobs not a table" end
  if type(d.domain_id_counter) ~= "number" then return false, "domain_id_counter not a number" end
  if type(d.job_id_counter) ~= "number" then return false, "job_id_counter not a number" end
  if type(d.assignment_id_counter) ~= "number" then return false, "assignment_id_counter not a number" end
  if d.storage_node ~= nil and type(d.storage_node) ~= "table" then
    return false, "storage_node not a table"
  end
  return true
end

function state.load(path)
  path = path or _statePath
  if not path then return false, "no_state_path" end
  if not fs.exists or not fs.exists(path) then
    log.info(LOG_TAG, "no persisted state at " .. path .. "; starting fresh")
    -- Success, but the caller needs to tell a first boot from a restore:
    -- a Master that came up with no managers because the file was absent
    -- is a different situation from one that restored an empty registry.
    return true, "cold_start"
  end

  local data
  if fs.readFile then
    data = fs.readFile(path)
  else
    local h, err = fs.open(path, "r")
    if not h then
      log.error(LOG_TAG, "open failed: " .. tostring(err))
      return false, "read_failed: " .. tostring(err)
    end
    local parts = {}
    local n = 0
    while true do
      local chunk = h:read(4096)
      if not chunk or chunk == "" then break end
      n = n + 1
      parts[n] = chunk
    end
    h:close()
    data = table.concat(parts)
  end

  if not data or data == "" then
    log.warn(LOG_TAG, "state file empty; starting fresh")
    return true, "cold_start"
  end

  local decoded, err = serialize.decode(data)
  if not decoded then
    log.error(LOG_TAG, "deserialize failed: " .. tostring(err))
    return false, "decode_failed: " .. tostring(err)
  end

  local ok, reason = validateShape(decoded)
  if not ok then
    log.error(LOG_TAG, "bad state shape: " .. reason .. "; REFUSING to overwrite in-memory state")
    return false, "bad_state_shape: " .. reason
  end

  -- Merge persisted fields; leave _runtime untouched.
  state._data.managers               = decoded.managers
  state._data.jobs                   = decoded.jobs
  state._data.domain_id_counter      = decoded.domain_id_counter
  state._data.job_id_counter         = decoded.job_id_counter
  state._data.assignment_id_counter  = decoded.assignment_id_counter
  state._data.storage_node           = decoded.storage_node

  -- Mark every loaded Manager as "unknown heartbeat" until one arrives.
  -- This prevents the sweep from immediately declaring everyone offline
  -- using the pre-restart last_heartbeat timestamp.
  local now = computer.uptime()
  local mgr_count = 0
  for _, m in pairs(state._data.managers) do
    m.last_heartbeat = now
    mgr_count = mgr_count + 1
    -- Keep state as-is; if they don't heartbeat we'll demote them.
  end

  log.info(LOG_TAG, "loaded state: " .. tostring(mgr_count) ..
    " manager entries, " .. tostring(decoded.job_id_counter - 1) .. " historical jobs")
  return true, "loaded"
end

function state.save(path)
  path = path or _statePath
  if not path then return false, "no_state_path" end

  -- Build a shallow copy of _data without _runtime. We copy top-level
  -- keys only; the nested tables are referenced (serialize will walk them).
  local out = {}
  for k, v in pairs(state._data) do
    if k ~= "_runtime" then out[k] = v end
  end

  local blob = serialize.encode(out)
  local tmp = path .. ".tmp"

  -- Ensure parent dir exists (/var/cluster)
  local dir = path:match("(.+)/[^/]+$")
  if dir and fs.exists and not fs.exists(dir) then
    if fs.makeDirectory then fs.makeDirectory(dir) end
  end

  local ok, err
  if fs.writeFile then
    ok, err = fs.writeFile(tmp, blob)
  else
    local h
    h, err = fs.open(tmp, "w")
    if h then
      h:write(blob); h:close(); ok = true
    end
  end
  if not ok then
    log.error(LOG_TAG, "write tmp failed: " .. tostring(err))
    return false, "write_failed: " .. tostring(err)
  end

  -- Atomic replace: remove old if exists, rename tmp into place.
  if fs.exists and fs.exists(path) and fs.remove then
    pcall(fs.remove, path)
  end
  if fs.rename then
    local rok, rerr = fs.rename(tmp, path)
    if not rok then
      log.error(LOG_TAG, "rename failed: " .. tostring(rerr))
      return false, "rename_failed: " .. tostring(rerr)
    end
  else
    -- No rename support? fall back to write-directly and cleanup.
    if fs.writeFile then fs.writeFile(path, blob) end
    if fs.remove then pcall(fs.remove, tmp) end
  end

  return true
end

-- Called by every mutating function that changes persistent state.
-- Consolidated here so we can add debouncing later if disk I/O becomes
-- a cost concern.
local function persist()
  if not _statePath then return end
  local ok, err = pcall(state.save, _statePath)
  if not ok then log.error(LOG_TAG, "persist failed: " .. tostring(err)) end
end

-- ============================================================
-- Manager operations
-- ============================================================

function state.registerManager(address, reg)
  local now = computer.uptime()
  local existing = state._data.managers[address]

  local domain_id
  if existing then
    -- Re-registration after Manager restart: preserve domain_id, refresh fields.
    domain_id = existing.domain_id
  else
    domain_id = state._data.domain_id_counter
    state._data.domain_id_counter = state._data.domain_id_counter + 1
  end

  state._data.managers[address] = {
    hostname         = reg.hostname,
    domain_id        = domain_id,
    profile          = reg.profile,
    worker_count     = reg.worker_count,
    storage          = reg.storage or { external_type = "none", external_capacity = 0 },
    master_path      = reg.master_path or "direct",
    relay_peer       = reg.relay_peer,
    has_console      = reg.has_console,
    compute_capable  = reg.compute_capable,
    cluster_protocol = reg.cluster_protocol,
    software_version = reg.software_version,
    state            = "active",
    last_heartbeat   = now,
    last_snapshot    = nil,
    registered_at    = existing and existing.registered_at or now,
  }

  persist()
  state.pushEvent(existing and "manager_reregistered" or "manager_registered",
                  { domain_id = domain_id, hostname = reg.hostname })
  return domain_id
end

function state.updateManagerHeartbeat(address, snapshot)
  local m = state._data.managers[address]
  if not m then return false, "unknown_manager" end
  m.last_snapshot = snapshot
  m.last_heartbeat = computer.uptime()
  -- NOT persisted — pure runtime telemetry.

  -- ...with one exception. A Manager can gain or lose external storage
  -- without re-registering (operator bolts a RAID on, edits the config,
  -- restarts the service — or pulls the tape drive). The heartbeat carries
  -- the currently-declared type (§4.2 external_type); fold it into the
  -- persisted record, because that — not last_snapshot — is what the
  -- scheduler reads for storage-preference matching (§9). Persist only on
  -- an actual change: this runs every heartbeat_interval seconds.
  if snapshot and snapshot.external_type then
    if not m.storage then
      m.storage = { external_type = "none", external_capacity = 0 }
    end
    if m.storage.external_type ~= snapshot.external_type then
      m.storage.external_type = snapshot.external_type
      state.pushEvent("manager_storage_change",
        { domain_id = m.domain_id, external_type = snapshot.external_type })
      persist()
    end
  end
  return true
end

local VALID_MANAGER_STATES = {
  active = true, degraded = true, draining = true, offline = true,
}

function state.setManagerState(address, newState)
  if not VALID_MANAGER_STATES[newState] then
    return false, "invalid_state: " .. tostring(newState)
  end
  local m = state._data.managers[address]
  if not m then return false, "unknown_manager" end
  if m.state == newState then return true end

  local prev = m.state
  m.state = newState
  state.pushEvent("manager_state_change",
    { domain_id = m.domain_id, from = prev, to = newState })
  persist()
  return true
end

function state.forgetManager(address)
  local m = state._data.managers[address]
  if not m then return false, "unknown_manager" end

  -- Any running assignments on this Manager are left behind — caller
  -- (jobs.onManagerOffline) is responsible for marking them lost first.
  state._data.managers[address] = nil
  state.pushEvent("manager_forgotten", { domain_id = m.domain_id, hostname = m.hostname })
  persist()
  return true
end

function state.listManagers(filter)
  local out = {}
  for addr, m in pairs(state._data.managers) do
    if (not filter) or filter(m) then
      -- Shallow copy with address stitched in so the CLI can key on it.
      local row = {}
      for k, v in pairs(m) do row[k] = v end
      row.address = addr
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b) return (a.domain_id or 0) < (b.domain_id or 0) end)
  return out
end

function state.getManager(address)
  return state._data.managers[address]
end

function state.getManagerByDomainId(domain_id)
  for addr, m in pairs(state._data.managers) do
    if m.domain_id == domain_id then
      local row = {}
      for k, v in pairs(m) do row[k] = v end
      row.address = addr
      return row
    end
  end
  return nil
end

-- ============================================================
-- Job operations
-- ============================================================

function state.createJob(spec)
  local job_id = state._data.job_id_counter
  state._data.job_id_counter = state._data.job_id_counter + 1

  state._data.jobs[job_id] = {
    job_id          = job_id,
    submitted_by    = spec.submitted_by or "?",
    submitted_at    = computer.uptime(),
    state           = "pending",
    compute_profile = spec.compute_profile or "mixed",
    retry_policy    = spec.retry_policy or "safe",
    storage_preference = spec.storage_preference,
    result_sink     = spec.result_sink or "inline",
    assignments     = {},
    spec            = spec,        -- kept for retry
  }
  persist()
  state.pushEvent("job_submitted", { job_id = job_id, by = spec.submitted_by })
  return job_id
end

function state.addAssignment(job_id, assignment)
  local j = state._data.jobs[job_id]
  if not j then return nil, "no_such_job: " .. tostring(job_id) end

  local aid = state._data.assignment_id_counter
  state._data.assignment_id_counter = state._data.assignment_id_counter + 1
  assignment.assignment_id = aid
  assignment.job_id = job_id
  assignment.state = assignment.state or "pending"
  assignment.attempts = assignment.attempts or 0
  j.assignments[aid] = assignment
  persist()
  return aid
end

function state.setAssignmentState(job_id, assignment_id, newState, extra)
  local j = state._data.jobs[job_id]
  if not j then return false, "no_such_job" end
  local a = j.assignments[assignment_id]
  if not a then return false, "no_such_assignment" end

  local prev = a.state
  a.state = newState
  if extra then
    for k, v in pairs(extra) do
      if v == state.CLEAR then a[k] = nil else a[k] = v end
    end
  end

  -- Bookkeeping for the compute-bound cap.
  if j.compute_profile == "compute_bound" then
    if prev ~= "running" and newState == "running" then
      state._data._runtime.compute_bound_in_flight =
        state._data._runtime.compute_bound_in_flight + 1
    elseif prev == "running" and newState ~= "running" then
      state._data._runtime.compute_bound_in_flight =
        math.max(0, state._data._runtime.compute_bound_in_flight - 1)
    end
  end

  persist()
  return true
end

function state.setJobState(job_id, newState)
  local j = state._data.jobs[job_id]
  if not j then return false, "no_such_job" end
  j.state = newState
  if newState == "done" or newState == "failed" or newState == "cancelled" then
    j.completed_at = computer.uptime()
  end
  persist()
  state.pushEvent("job_state_change", { job_id = job_id, to = newState })
  return true
end

function state.listJobs(filter)
  local out = {}
  for _, j in pairs(state._data.jobs) do
    if (not filter) or filter(j) then
      -- Produce a row with an assignments counter summary for table
      -- output. Full detail is via state.getJob.
      local done, total = 0, 0
      for _, a in pairs(j.assignments) do
        total = total + 1
        if a.state == "completed" then done = done + 1 end
      end
      out[#out + 1] = {
        job_id          = j.job_id,
        state           = j.state,
        submitted_by    = j.submitted_by,
        submitted_at    = j.submitted_at,
        compute_profile = j.compute_profile,
        assignments     = done .. "/" .. total,
      }
    end
  end
  table.sort(out, function(a, b) return (a.job_id or 0) < (b.job_id or 0) end)
  return out
end

function state.getJob(job_id)
  return state._data.jobs[job_id]
end

-- ============================================================
-- Storage node
-- ============================================================

function state.setStorageNode(info)
  state._data.storage_node = info
  persist()
  state.pushEvent("storage_configured", { address = info and info.address })
end

function state.updateStorageUsage(used_bytes)
  if not state._data.storage_node then return end
  state._data.storage_node.used = used_bytes
  state._data.storage_node.last_seen = computer.uptime()
  -- NOT persisted — runtime telemetry.
end

-- ============================================================
-- Event ring buffer
-- ============================================================

function state.pushEvent(kind, detail)
  local rt = state._data._runtime
  rt.events[rt.events_head] = {
    time = computer.uptime(),
    kind = kind,
    detail = detail,
  }
  rt.events_head = (rt.events_head % rt.EVENTS_MAX) + 1
  if rt.events_size < rt.EVENTS_MAX then
    rt.events_size = rt.events_size + 1
  end
end

function state.recentEvents(n)
  local rt = state._data._runtime
  n = math.min(n or 20, rt.events_size)
  local out = {}
  -- Walk backward from the most recently written slot.
  local cursor = rt.events_head - 1
  if cursor < 1 then cursor = rt.EVENTS_MAX end
  for _ = 1, n do
    local ev = rt.events[cursor]
    if ev then out[#out + 1] = ev end
    cursor = cursor - 1
    if cursor < 1 then cursor = rt.EVENTS_MAX end
  end
  return out
end

-- ============================================================
-- Counters
-- ============================================================

function state.incrementComputeBoundInFlight(delta)
  state._data._runtime.compute_bound_in_flight =
    state._data._runtime.compute_bound_in_flight + (delta or 1)
  if state._data._runtime.compute_bound_in_flight < 0 then
    state._data._runtime.compute_bound_in_flight = 0
  end
end

function state.computeBoundInFlight()
  return state._data._runtime.compute_bound_in_flight
end

return state
