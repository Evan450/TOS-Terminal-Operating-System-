





local scheduler = {}





local COMPUTE_BOUND_SOFT_MULTIPLIER = 2





local function _storagePreferenceMatches(assignment, manager)
  
  if not assignment.storage_preference or assignment.storage_preference == "" then
    return true
  end
  local storage = manager.storage or {}
  return storage.external_type == assignment.storage_preference
end

local function _dataLocalityBonus(_assignment, _manager)
  
  
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

  
  local score = 0
  score = score + free * 10                                 
  score = score + (manager.state == "active"   and 50 or 0) 
  score = score + (manager.state == "degraded" and 10 or 0) 

  if _storagePreferenceMatches(assignment, manager) and
     assignment.storage_preference and assignment.storage_preference ~= "" then
    score = score + 25                                      
  end

  local storage_used = snap.storage_used or 0
  score = score - storage_used * 20                         

  local queue_depth = snap.queue_depth or 0
  score = score - queue_depth * 2                           

  local errors_last_min = snap.errors_last_min or 0
  score = score - errors_last_min * 5                       

  score = score + _dataLocalityBonus(assignment, manager)   

  
  
  return score
end















function scheduler.pickDomain(assignment, managers, ctx)
  ctx = ctx or {}
  local budget     = ctx.host_thread_budget or 4
  local in_flight  = ctx.compute_bound_in_flight or 0

  
  if assignment.compute_profile == "compute_bound" then
    if in_flight >= budget * COMPUTE_BOUND_SOFT_MULTIPLIER then
      return nil, "thread_budget_saturated"
    end
  end

  
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
      
      eligible._last_reject = reject
    end
  end

  if #eligible == 0 then
    if not had_any then return nil, "no_managers_registered" end
    return nil, eligible._last_reject or "no_eligible_manager"
  end

  
  for _, e in ipairs(eligible) do
    e.score = _scoreDomain(assignment, e.manager, ctx)
  end

  
  
  
  table.sort(eligible, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local aq = (a.manager.last_snapshot and a.manager.last_snapshot.queue_depth) or 0
    local bq = (b.manager.last_snapshot and b.manager.last_snapshot.queue_depth) or 0
    if aq ~= bq then return aq < bq end
    return tostring(a.address) < tostring(b.address)
  end)

  return eligible[1].address
end






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



scheduler._internal = {
  scoreDomain               = _scoreDomain,
  storagePreferenceMatches  = _storagePreferenceMatches,
  freeCapacity              = _freeCapacity,
  COMPUTE_BOUND_SOFT_MULTIPLIER = COMPUTE_BOUND_SOFT_MULTIPLIER,
}

return scheduler
