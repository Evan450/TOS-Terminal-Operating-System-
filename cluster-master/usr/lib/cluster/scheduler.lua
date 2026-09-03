-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.scheduler — Domain selection for assignments        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Implements §9 of the protocol spec. The scheduler is stateless
-- between calls — all state lives in cluster.state.

local scheduler = {}

-- Upper bound on the compute-bound soft cap. The spec (§9.1) says the
-- cap "may exceed... by a small margin (up to 2× is a reasonable
-- implementation default)". Past that we treat it as saturated so a
-- single bad submission can't monopolize the cluster.
local COMPUTE_BOUND_SOFT_MULTIPLIER = 2

-- ============================================================
-- Internal: scoring
-- ============================================================

local function _storagePreferenceMatches(assignment, manager)
  -- No preference → anything matches.
  if not assignment.storage_preference or assignment.storage_preference == "" then
    return true
  end
  local storage = manager.storage or {}
  return storage.external_type == assignment.storage_preference
end

local function _dataLocalityBonus(_assignment, _manager)
  -- v2 — see §9 last row. Reserved for when we track which domain a
  -- job's inputs already live on. No data, no bonus.
  return 0
end

local function _freeCapacity(manager)
  local snap = manager.last_snapshot
  if not snap then return 0 end
  local active = snap.workers_active or 0
  local busy   = snap.workers_busy   or 0
  local free   = active - busy
  if free < 0 then free = 0 end
  return free
end

local function _scoreDomain(assignment, manager, ctx)
  local snap = manager.last_snapshot or {}
  local free = _freeCapacity(manager)

  -- Weight order comes from §9's Weight column (high → low).
  local score = 0
  score = score + free * 10                                 -- high: free capacity
  score = score + (manager.state == "active"   and 50 or 0) -- gating boost
  score = score + (manager.state == "degraded" and 10 or 0) -- keep but prefer active

  if _storagePreferenceMatches(assignment, manager) and
     assignment.storage_preference and assignment.storage_preference ~= "" then
    score = score + 25                                      -- medium: storage match bonus
  end

  local storage_used = snap.storage_used or 0
  score = score - storage_used * 20                         -- medium: fullness penalty

  local queue_depth = snap.queue_depth or 0
  score = score - queue_depth * 2                           -- medium: queue depth penalty

  local errors_last_min = snap.errors_last_min or 0
  score = score - errors_last_min * 5                       -- low: flap penalty

  score = score + _dataLocalityBonus(assignment, manager)   -- low (v2): locality

  -- Tiny address-derived jitter is added by the tie-breaker in
  -- pickDomain, not here — keep _scoreDomain pure/deterministic.
  return score
end

-- ============================================================
-- Public API
-- ============================================================

--- Select the best Manager domain to run an assignment on.
-- Returns the Manager address (string) or nil if no suitable domain exists.
-- @param assignment table: assignment record (job_id, compute_profile, retry_policy, ...)
-- @param managers  table: full state.managers table ([address] = manager_record)
-- @param ctx       table: runtime context
--                         { compute_bound_in_flight = <n>,
--                           host_thread_budget      = <n>,
--                           uptime                  = <n> }
-- @return string|nil address of chosen Manager, nil if none viable
-- @return string|nil reason for skipping (if nil returned)
function scheduler.pickDomain(assignment, managers, ctx)
  ctx = ctx or {}
  local budget     = ctx.host_thread_budget or 4
  local in_flight  = ctx.compute_bound_in_flight or 0

  -- 1. Compute-bound soft cap (§9.1). 2× is the documented upper margin.
  if assignment.compute_profile == "compute_bound" then
    if in_flight >= budget * COMPUTE_BOUND_SOFT_MULTIPLIER then
      return nil, "thread_budget_saturated"
    end
  end

  -- 2. Filter to viable Managers.
  local eligible = {}
  local had_any  = false
  for addr, m in pairs(managers or {}) do
    had_any = true
    local snap = m.last_snapshot
    local viable = true
    local reject = nil

    if m.state ~= "active" and m.state ~= "degraded" then
      viable = false; reject = "state:" .. tostring(m.state)
    elseif not snap then
      -- No telemetry yet → we have no idea of capacity. Skip until a
      -- heartbeat lands.
      viable = false; reject = "no_snapshot"
    elseif _freeCapacity(m) <= 0 then
      viable = false; reject = "no_free_workers"
    elseif (snap.storage_used or 0) >= 0.95 then
      viable = false; reject = "storage_full"
    elseif not _storagePreferenceMatches(assignment, m) then
      viable = false; reject = "storage_pref_mismatch"
    end

    if viable then
      eligible[#eligible + 1] = { address = addr, manager = m }
    else
      -- Tracked only for the "no eligible" reason aggregation below.
      eligible._last_reject = reject
    end
  end

  if #eligible == 0 then
    if not had_any then return nil, "no_managers_registered" end
    return nil, eligible._last_reject or "no_eligible_manager"
  end

  -- 3. Score each.
  for _, e in ipairs(eligible) do
    e.score = _scoreDomain(assignment, e.manager, ctx)
  end

  -- 4. Pick the highest score.
  --    Tie-break: lower queue_depth first, then deterministic by address
  --    (string compare) so identical fleets don't stampede the same node.
  table.sort(eligible, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local aq = (a.manager.last_snapshot and a.manager.last_snapshot.queue_depth) or 0
    local bq = (b.manager.last_snapshot and b.manager.last_snapshot.queue_depth) or 0
    if aq ~= bq then return aq < bq end
    return tostring(a.address) < tostring(b.address)
  end)

  return eligible[1].address
end

-- ============================================================
-- Availability helpers (used by jobs module to decide whether to queue
-- or reject at submission time)
-- ============================================================

function scheduler.hasAnyActiveCapacity(managers)
  for _, m in pairs(managers or {}) do
    if (m.state == "active" or m.state == "degraded") and _freeCapacity(m) > 0 then
      return true
    end
  end
  return false
end

function scheduler.totalFreeCapacity(managers)
  local total = 0
  for _, m in pairs(managers or {}) do
    if m.state == "active" or m.state == "degraded" then
      total = total + _freeCapacity(m)
    end
  end
  return total
end

-- Expose internals for unit testing / introspection. Not part of the
-- contract; consumers should only call the public functions above.
scheduler._internal = {
  scoreDomain               = _scoreDomain,
  storagePreferenceMatches  = _storagePreferenceMatches,
  freeCapacity              = _freeCapacity,
  COMPUTE_BOUND_SOFT_MULTIPLIER = COMPUTE_BOUND_SOFT_MULTIPLIER,
}

return scheduler
