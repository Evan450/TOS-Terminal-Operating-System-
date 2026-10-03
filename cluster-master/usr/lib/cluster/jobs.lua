







local computer = require("computer")

local jobs = {}







local INLINE_TASK_BUDGET = 4096




local storeRef, serializeRef

function jobs.setStore(store, serialize)
  storeRef, serializeRef = store, serialize
end














local MAX_TASKS_PER_ASSIGNMENT = 40 




local POLICY_ATTEMPTS = {
  safe = 5,
  once = 2,
  none = 1,
}

local function attemptsFor(policy)
  return POLICY_ATTEMPTS[policy or "safe"] or 1
end




local TERMINAL_ASSIGNMENT_STATES = {
  completed = true, failed = true, lost = true, cancelled = true,
}


local _allAssignmentsTerminal



local log
do
  local okK, mod = pcall(require, "kernel.log")
  if not (okK and mod and mod.info) then okK, mod = pcall(require, "log") end
  if okK and mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.jobs"





function jobs.splitIntoAssignments(job_id, jobSpec, stateRef)
  stateRef = stateRef or require("cluster.state")
  local tasks = jobSpec.tasks or {}
  local n_tasks = #tasks
  local compute_profile = jobSpec.compute_profile or "mixed"
  local retry_policy    = jobSpec.retry_policy or "safe"
  local deadline        = jobSpec.deadline or 0
  local priority        = jobSpec.priority or 5
  local storage_pref    = jobSpec.storage_preference
  local result_sink     = jobSpec.result_sink or "inline"

  
  
  
  
  local function placeTasks(slice, idx)
    if #slice == 0 then return slice, nil, nil end
    if not (storeRef and storeRef.available and storeRef.available()) then
      return slice, nil, nil
    end
    if not (serializeRef and serializeRef.encode) then return slice, nil, nil end
    local okEnc, blob = pcall(serializeRef.encode, slice)
    if not okEnc or type(blob) ~= "string" or #blob <= INLINE_TASK_BUDGET then
      return slice, nil, nil
    end
    local key = storeRef.tasksKey(job_id, idx)
    local ack, err = storeRef.put(key, blob)
    if not ack then
      log.warn(LOG_TAG, string.format(
        "job %d slice %d: %d bytes but Public write failed (%s); staying inline",
        job_id, idx, #blob, tostring(err)))
      return slice, nil, nil
    end
    log.info(LOG_TAG, string.format(
      "job %d slice %d: %d bytes -> %s", job_id, idx, #blob, key))
    return nil, "public://" .. key, ack.lease_id
  end

  local function mkAssignment(task_slice, idx)
    local inline, ref, lease = placeTasks(task_slice, idx)
    return {
      job_id          = job_id,
      priority        = priority,
      deadline        = deadline,
      retry_policy    = retry_policy,
      compute_profile = compute_profile,
      storage_preference = storage_pref,
      tasks_inline    = inline,         
      tasks_ref       = ref,
      tasks_lease     = lease,          
      inputs_inline   = jobSpec.inputs, 
      inputs_ref      = jobSpec.inputs_ref,
      result_sink     = result_sink,
      result_prefix   = result_sink == "public"
                        and string.format("public://job-%d/results/", job_id) or nil,
      split_index     = idx,            
      state           = "pending",
      attempts        = 0,
      max_attempts    = attemptsFor(retry_policy),
    }
  end

  local created = {}

  if n_tasks == 0 then
    
    
    
    
    
    local aid = stateRef.addAssignment(job_id, mkAssignment({}, 1))
    if aid then created[#created + 1] = aid end
  else
    
    
    
    
    local slice = {}
    local idx = 1
    for i = 1, n_tasks do
      slice[#slice + 1] = tasks[i]
      if #slice >= MAX_TASKS_PER_ASSIGNMENT then
        local aid = stateRef.addAssignment(job_id, mkAssignment(slice, idx))
        if aid then created[#created + 1] = aid end
        slice = {}
        idx = idx + 1
      end
    end
    if #slice > 0 then
      local aid = stateRef.addAssignment(job_id, mkAssignment(slice, idx))
      if aid then created[#created + 1] = aid end
    end
  end

  log.info(LOG_TAG, string.format("job %d split into %d assignment(s)", job_id, #created))
  return created
end





function jobs.pendingAssignments(stateRef)
  stateRef = stateRef or require("cluster.state")
  local out = {}
  
  
  
  for _, job in pairs(stateRef._data.jobs) do
    
    if job.state == "pending" or job.state == "running" then
      for _, a in pairs(job.assignments) do
        if a.state == "pending" then out[#out + 1] = a end
      end
    end
  end
  
  
  table.sort(out, function(a, b)
    local ap = a.priority or 5
    local bp = b.priority or 5
    if ap ~= bp then return ap > bp end
    local ad = (a.deadline and a.deadline > 0) and a.deadline or math.huge
    local bd = (b.deadline and b.deadline > 0) and b.deadline or math.huge
    if ad ~= bd then return ad < bd end
    return (a.assignment_id or 0) < (b.assignment_id or 0)
  end)
  return out
end





function jobs.dispatch(assignment, managerAddr, stateRef, netRef)
  stateRef = stateRef or require("cluster.state")
  if not netRef then netRef = require("cluster.net") end

  local now = computer.uptime()
  local prior_attempts = assignment.attempts or 0
  local ok_set, set_err = stateRef.setAssignmentState(assignment.job_id, assignment.assignment_id,
    "running", {
      dispatched_at = now,
      assigned_to   = managerAddr,
      attempts      = prior_attempts + 1,
    })
  if not ok_set then
    
    
    
    log.error(LOG_TAG, "dispatch: setAssignmentState failed for " ..
      tostring(assignment.assignment_id) .. ": " .. tostring(set_err))
    return false, set_err or "state_update_failed"
  end

  
  
  local job = stateRef.getJob(assignment.job_id)
  if job and job.state == "pending" then
    stateRef.setJobState(assignment.job_id, "running")
  end

  local ok, err = netRef.sendAssignment(managerAddr, assignment)
  if not ok then
    
    
    log.warn(LOG_TAG, string.format("send failed to %s: %s; requeuing asn %d",
      tostring(managerAddr), tostring(err), assignment.assignment_id))
    
    
    
    
    stateRef.setAssignmentState(assignment.job_id, assignment.assignment_id, "pending",
      { assigned_to = stateRef.CLEAR, attempts = prior_attempts })
    return false, "send_failed: " .. tostring(err)
  end

  stateRef.pushEvent("assignment_dispatched", {
    job_id = assignment.job_id,
    assignment_id = assignment.assignment_id,
    manager = managerAddr,
    attempt = assignment.attempts,
  })
  return true
end








local function _resolveAssignment(stateRef, assignment_id)
  for job_id, job in pairs(stateRef._data.jobs) do
    local a = job.assignments[assignment_id]
    if a then return job_id, a, job end
  end
  return nil
end

function jobs.onResult(assignment_id, payload, stateRef)
  stateRef = stateRef or require("cluster.state")
  local job_id, a, job = _resolveAssignment(stateRef, assignment_id)
  if not a then
    log.warn(LOG_TAG, "result for unknown assignment " .. tostring(assignment_id))
    return false, "no_such_assignment"
  end
  if TERMINAL_ASSIGNMENT_STATES[a.state] then
    
    
    
    
    
    
    
    
    log.warn(LOG_TAG, string.format(
      "duplicate result for asn %d, already %s; keeping the first",
      assignment_id, tostring(a.state)))
    stateRef.pushEvent("assignment_result_duplicate", {
      job_id = job_id, assignment_id = assignment_id,
      kept = a.state, discarded = payload.status or "ok",
    })
    return false, "duplicate_result"
  end
  if a.state ~= "running" then
    
    
    
    
    log.info(LOG_TAG, string.format("result for requeued asn %d in state %s; accepting",
      assignment_id, tostring(a.state)))
  end

  local status = payload.status or "ok"
  local newState
  if status == "ok" then
    newState = "completed"
  elseif status == "partial" then
    newState = "completed"   
  elseif status == "cancelled" then
    newState = "cancelled"
  else
    newState = "failed"
  end

  local extra = {
    completed_at = computer.uptime(),
    result = {
      status        = status,
      output_inline = payload.output_inline,
      output_ref    = payload.output_ref,
      errors        = payload.errors,
      stats         = payload.stats,
    },
  }

  stateRef.setAssignmentState(job_id, assignment_id, newState, extra)
  stateRef.pushEvent("assignment_result", {
    job_id = job_id, assignment_id = assignment_id, status = status,
  })

  
  if newState == "failed" and job and job.retry_policy ~= "none" then
    if (a.attempts or 0) < attemptsFor(job.retry_policy) then
      stateRef.setAssignmentState(job_id, assignment_id, "pending",
        { assigned_to = stateRef.CLEAR, retry_reason = "failed_result" })
      log.info(LOG_TAG, string.format(
        "retrying asn %d (attempt %d/%d)",
        assignment_id, (a.attempts or 0), attemptsFor(job.retry_policy)))
      return true
    end
  end

  
  if _allAssignmentsTerminal(job) then
    jobs.finalizeJob(job_id, stateRef)
  end
  return true
end

_allAssignmentsTerminal = function(job)
  if not job then return false end
  for _, a in pairs(job.assignments) do
    local st = a.state
    if st == "pending" or st == "running" then return false end
  end
  return true
end




local _resultChunkBuffer = {}

local function _gcChunkBuffer()
  local now = computer.uptime()
  for aid, entry in pairs(_resultChunkBuffer) do
    if now - (entry.last_touch or 0) > 300 then
      log.warn(LOG_TAG, "discarding stale chunk buffer for asn " .. tostring(aid))
      _resultChunkBuffer[aid] = nil
    end
  end
end

function jobs.onResultChunk(assignment_id, chunk_idx, chunk_total, data, final_stats, stateRef)
  _gcChunkBuffer()
  local entry = _resultChunkBuffer[assignment_id]
  if not entry then
    entry = { chunks = {}, expected = chunk_total, last_touch = computer.uptime() }
    _resultChunkBuffer[assignment_id] = entry
  end
  entry.chunks[chunk_idx] = data
  entry.last_touch = computer.uptime()
  if final_stats then entry.stats = final_stats end

  
  
  local have = 0
  for i = 1, entry.expected do
    if entry.chunks[i] ~= nil then have = have + 1 end
  end
  if have ~= entry.expected then return false, "incomplete" end

  local parts = {}
  for i = 1, entry.expected do parts[i] = entry.chunks[i] end
  local blob = table.concat(parts)
  _resultChunkBuffer[assignment_id] = nil

  return jobs.onResult(assignment_id, {
    status = "ok",
    output_inline = blob,
    stats = entry.stats,
  }, stateRef)
end

function jobs.onAssignmentTimeout(assignment_id, stateRef, netRef)
  stateRef = stateRef or require("cluster.state")
  if not netRef then netRef = require("cluster.net") end

  local job_id, a, job = _resolveAssignment(stateRef, assignment_id)
  if not a or a.state ~= "running" then return false, "wrong_state: not running" end

  
  if a.assigned_to then
    pcall(netRef.sendCancel, a.assigned_to, assignment_id)
  end

  stateRef.pushEvent("assignment_timeout", {
    job_id = job_id, assignment_id = assignment_id,
  })

  local policy = job and job.retry_policy or "safe"
  local budget = attemptsFor(policy)
  if policy ~= "none" and (a.attempts or 0) < budget then
    
    stateRef.setAssignmentState(job_id, assignment_id, "pending", {
      assigned_to = stateRef.CLEAR,
      retry_reason = "deadline_exceeded",
    })
    log.info(LOG_TAG, string.format(
      "asn %d timed out, requeued (attempts=%d/%d)",
      assignment_id, (a.attempts or 0), budget))
    return true
  end

  stateRef.setAssignmentState(job_id, assignment_id, "failed", {
    reason = "deadline_exceeded",
    completed_at = computer.uptime(),
  })
  if _allAssignmentsTerminal(job) then
    jobs.finalizeJob(job_id, stateRef)
  end
  return true
end

function jobs.onManagerOffline(domain_id, stateRef)
  stateRef = stateRef or require("cluster.state")
  local mgr = stateRef.getManagerByDomainId(domain_id)
  if not mgr then return end
  local addr = mgr.address

  
  
  local touched = 0
  for job_id, job in pairs(stateRef._data.jobs) do
    for aid, a in pairs(job.assignments) do
      if a.state == "running" and a.assigned_to == addr then
        local policy = job.retry_policy or "safe"
        local budget = attemptsFor(policy)
        if policy ~= "none" and (a.attempts or 0) < budget then
          stateRef.setAssignmentState(job_id, aid, "pending", {
            assigned_to = stateRef.CLEAR,
            retry_reason = "manager_offline",
          })
        else
          stateRef.setAssignmentState(job_id, aid, "lost", {
            reason = "manager_offline",
            completed_at = computer.uptime(),
          })
        end
        touched = touched + 1
      end
    end
  end
  stateRef.pushEvent("manager_offline_reassign", {
    domain_id = domain_id, affected = touched,
  })
  
  for job_id, job in pairs(stateRef._data.jobs) do
    if (job.state == "running" or job.state == "pending") and _allAssignmentsTerminal(job) then
      jobs.finalizeJob(job_id, stateRef)
    end
  end
end













local function releasePublicKeys(job_id, job)
  if not (storeRef and storeRef.available and storeRef.available()) then return 0 end
  local released = 0
  for _, a in pairs(job.assignments or {}) do
    if a.tasks_ref and a.tasks_lease then
      local key = a.tasks_ref:gsub("^public://", "")
      local ok = pcall(storeRef.release, key, a.tasks_lease)
      if ok then released = released + 1 end
    end
  end
  if released > 0 then
    log.info(LOG_TAG, string.format("job %d: released %d Public key(s)",
      job_id, released))
  end
  return released
end

function jobs.finalizeJob(job_id, stateRef)
  stateRef = stateRef or require("cluster.state")
  local job = stateRef.getJob(job_id)
  if not job then return false, "no_such_job" end

  pcall(releasePublicKeys, job_id, job)

  local completed, failed, lost, cancelled = 0, 0, 0, 0
  for _, a in pairs(job.assignments) do
    if a.state == "completed" then completed = completed + 1
    elseif a.state == "failed" then failed = failed + 1
    elseif a.state == "lost"   then lost   = lost   + 1
    elseif a.state == "cancelled" then cancelled = cancelled + 1
    end
  end

  local newState
  if cancelled > 0 and completed == 0 and failed == 0 and lost == 0 then
    newState = "cancelled"
  elseif failed == 0 and lost == 0 then
    newState = "done"
  elseif (job.retry_policy or "safe") == "none" then
    newState = "failed"
  else
    
    newState = (completed > 0) and "done" or "failed"
  end

  stateRef.setJobState(job_id, newState)
  stateRef.pushEvent("job_finalized", {
    job_id = job_id, state = newState,
    completed = completed, failed = failed, lost = lost, cancelled = cancelled,
  })
  log.info(LOG_TAG, string.format(
    "job %d finalized: %s (ok=%d fail=%d lost=%d cancel=%d)",
    job_id, newState, completed, failed, lost, cancelled))
  return true, newState
end


jobs._internal = {
  MAX_TASKS_PER_ASSIGNMENT = MAX_TASKS_PER_ASSIGNMENT,
  INLINE_TASK_BUDGET       = INLINE_TASK_BUDGET,
  releasePublicKeys        = function(...) return releasePublicKeys(...) end,
  POLICY_ATTEMPTS          = POLICY_ATTEMPTS,
  attemptsFor              = attemptsFor,
  resolveAssignment        = _resolveAssignment,
  allAssignmentsTerminal   = function(job) return _allAssignmentsTerminal(job) end,
  chunkBuffer              = _resultChunkBuffer,
}

return jobs
