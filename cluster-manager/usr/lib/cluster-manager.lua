





























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
  
  
  local mod = firstRequire("kernel.log", "log")
  if mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.mgr"

local mgr = {}





local _running   = false
local _cfg       = nil     
local _state     = nil     
local _listeners = {}      
local _timers    = {}      
local _inflight  = {}      
local _bridge    = nil     
local _rrCursor  = 0       

local CONFIG_PATH = "/etc/cluster-manager.cfg"

local DEFAULT_CFG = {
  master_address           = nil,            
  hostname                 = nil,            
  compute_profile          = "mixed",        
  worker_count             = 4,
  
  
  
  
  storage_type             = nil,            
  storage_capacity         = nil,            
  cluster_protocol         = "1.0",
  
  register_retry_seconds   = 10,
  
  
  min_heartbeat_seconds    = 2,
  max_heartbeat_seconds    = 30,
  
  
  worker_bridge_address    = nil,

  
  
  
  
  
  
  
  worker_bridge_enabled    = false,
  worker_bridge_domain     = 0,        
  worker_bridge_secret     = nil,      
  worker_bridge_bootstrap  = 180,      
  
  
  worker_bridge_mode       = "opt-in",
  task_timeout_seconds     = 30,       

  --! WHERE THE MASTER'S TASK CODE MAY RUN. An operator decision, because
  --! the honest answer depends on what the machine is for.
  --!
  --! An assignment carries Lua source. It arrives from a TRUSTED peer --
  --! the Master this Manager paired with -- so this is not a question of
  --! hostile code; it is a question of what a RUNAWAY costs. Mid-task
  --! cancellation needs debug.sethook, which OpenComputers withholds, so
  --! a task that never returns cannot be stopped: inline tasks run inside
  --! a kernel timer callback, and the machine keeps going until OC's
  --! watchdog reboots the WHOLE COMPUTER, taking every seat on it.
  --!
  --!   "inline"  run tasks on this Manager. The default, and what every
  --!             build before this one did. A runaway reboots this box.
  --!   "bridge"  never run task code here; hand every task to an OpenOS
  --!             worker over the bridge. A runaway takes out that worker,
  --!             which is a machine whose only job is running tasks. This
  --!             needs worker_bridge_enabled and at least one worker; an
  --!             assignment arriving with no idle worker is rejected
  --!             rather than run here.
  --!   "refuse"  run nothing. Assignments carrying task code are rejected
  --!             at ACK time with a reason the Master can schedule
  --!             around. Strictest, and the right setting for a Manager
  --!             that exists to contribute storage or presence rather
  --!             than compute.
  --!
  --! The default stays "inline" so an upgrade changes nothing on its own;
  --! start() warns once, loudly, when it is running unbounded, and
  --! mgr.status().task_execution reports the live setting.
  task_execution           = "inline",
}





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
    state               = "active",   
    started_at          = computer.uptime(),
  }
end




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








local function registerPayload(cfg, st)
  return {
    hostname         = cfg.hostname,
    profile          = cfg.compute_profile,
    worker_count     = cfg.worker_count,
    
    
    
    
    
    
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
    
    
    return
  end
  _state.registered          = true
  _state.domain_id           = p.domain_id
  _state.master_addr         = from
  
  local hb = tonumber(p.heartbeat_interval) or 5
  if hb < _cfg.min_heartbeat_seconds then hb = _cfg.min_heartbeat_seconds end
  if hb > _cfg.max_heartbeat_seconds then hb = _cfg.max_heartbeat_seconds end
  _state.heartbeat_interval = hb
  log.info(LOG_TAG, string.format("registered as domain %d (hb=%ds)",
    p.domain_id or -1, hb))
end





local function sendHeartbeat()
  if not _state.registered or not _state.master_addr then return end
  
  
  
  local snap = {
    state           = _state.state,
    workers_active  = _cfg.worker_count,
    workers_busy    = _state.workers_busy,
    queue_depth     = _state.queue_depth,
    storage_used    = _state.storage_used,
    errors_last_min = _state.errors_last_min,
    uptime          = computer.uptime() - _state.started_at,
  }
  
  
  if _cfg.storage_type then
    snap.external_type = _cfg.storage_type
  end
  local pkt = protocol.makePacket(protocol.TYPE.CLUSTER_HEARTBEAT, snap,
    { to = _state.master_addr })
  local ok = pcall(net.send, _state.master_addr, pkt)
  if ok then _state.errors_last_min = 0 end
end








local function validateAssignment(p)
  if type(p) ~= "table" then return false, "payload not a table" end
  if not p.assignment_id then return false, "missing assignment_id" end
  if not p.job_id        then return false, "missing job_id" end
  if p.tasks_inline ~= nil and type(p.tasks_inline) ~= "table" then
    return false, "tasks_inline not a list"
  end
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









--! Two flavours, and only ONE of them exists on OpenComputers:
--!   1. Between tasks: dispatchAssignment checks `cancelled` before
--!      each task, and a cancel that lands before the dispatch timer
--!      fires runs nothing at all. This works everywhere.
--!   2. Mid-task, via the hook. OC's sandbox does not export
--!      debug.sethook (see TODO.txt, "THE BUDGETS THAT DO NOT EXIST"),
--!      so on every real machine the guard below is false and a task in
--!      `while true do end` runs until OC's watchdog reboots the whole
--!      computer -- and since inline tasks run inside a kernel timer
--!      callback, every seat on the box is frozen while it runs. The
--!      hook stays so the off-box suite exercises it, and
--!      mgr.status().cancel_midtask says which world this is.







local function runOneTask(task, inflight)
  if type(task) ~= "table" or type(task.code) ~= "string" then
    return nil, "malformed task"
  end
  
  
  
  
  local env = {
    _input = task.input,
    math    = math, string = string, table = table,
    pairs   = pairs, ipairs = ipairs, next = next, select = select,
    type    = type, tostring = tostring, tonumber = tonumber,
    error   = error, pcall = pcall, xpcall = xpcall,
  }
  local fn, lerr = load(task.code, "=cluster:task", "t", env)
  if not fn then return nil, "compile: " .. tostring(lerr) end

  
  local co = coroutine.create(fn)
  
  
  
  
  
  if type(debug) == "table" and debug.sethook and inflight then
    pcall(debug.sethook, co, function()
      if inflight.cancelled then
        error("cancelled by CLUSTER_CANCEL", 0)
      end
    end, "", 5000)
  end

  local ok, result = coroutine.resume(co)
  
  
  
  if type(debug) == "table" and debug.sethook then
    pcall(debug.sethook, co)
  end

  if not ok then
    
    
    local msg = tostring(result)
    if msg:find("cancelled", 1, true) then
      return nil, "cancelled"
    end
    return nil, "runtime: " .. msg
  end
  return result
end










local function aggregateStatus(total, errorCount, cancelledCount)
  if cancelledCount > 0 then return "cancelled" end
  if errorCount == 0 then return "ok" end
  if total > 0 and errorCount == total then return "failed" end
  return "partial"
end
mgr._aggregateStatus = aggregateStatus






local function routeTask(task, bridgeAvailable, mode, policy)
  local want = "inline"
  if bridgeAvailable then
    if type(task) == "table" and task.via_bridge == true then want = "bridge"
    elseif mode == "prefer" then want = "bridge" end
  end
  if want == "inline" then
    if policy == "refuse" then return "refuse" end
    if policy == "bridge" then
      
      return bridgeAvailable and "bridge" or "refuse"
    end
  end
  return want
end
mgr._routeTask = routeTask




local function canAcceptTasks(taskCount, policy, bridgeAvailable)
  if (taskCount or 0) == 0 then return true end          
  if policy == "refuse" then return false, "task_execution=refuse" end
  if policy == "bridge" and not bridgeAvailable then
    return false, "task_execution=bridge and no worker bridge is up"
  end
  return true
end
mgr._canAcceptTasks = canAcceptTasks


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
  if total <= 0 then maybeFinish() end   
  return c
end
mgr._newCollector = newCollector


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
  
  
  local inflight = _inflight[id]
  if not inflight then
    inflight = { id = id, p = p, cancelled = false, bridgeTids = {} }
    _inflight[id] = inflight
  end
  inflight.pending = nil
  if inflight.cancelled then
    
    _inflight[id] = nil
    sendResult(id, "cancelled", nil, nil,
      { duration = 0, task_count = #tasks, error_count = 0, cancelled_count = #tasks })
    return
  end
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

  
  if #tasks == 0 then return end

  local record = inflight.collector.record
  for i, task in ipairs(tasks) do
    if inflight.cancelled then
      record(i, nil, "cancelled")
    else
      local route = routeTask(task, _bridge ~= nil, _cfg.worker_bridge_mode, _cfg.task_execution)
      local addr = (route == "bridge") and pickIdleWorker() or nil
      if route == "refuse" then
        
        record(i, nil, "refused by task_execution=" .. tostring(_cfg.task_execution))
      elseif addr then
        local tid = _bridge.mod.dispatch(addr, task.code, {
          inputs  = task.input,
          timeout = _cfg.task_timeout_seconds,
          on_result = function(_wa, _tid, result)
            inflight.bridgeTids[i] = nil
            record(i, workerResultToErr(result))
          end,
        })
        if tid then
          inflight.bridgeTids[i] = tid          
        elseif _cfg.task_execution == "bridge" then
          
          
          record(i, nil, "no idle worker and task_execution=bridge")
        else
          
          record(i, runOneTask(task, inflight))
        end
      elseif route == "bridge" then
        
        
        
        record(i, runOneTask(task, inflight))
      else
        record(i, runOneTask(task, inflight))
      end
    end
  end
  
  
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
  
  
  
  local canRun, whyNot = canAcceptTasks(p.tasks_inline and #p.tasks_inline or 0,
    _cfg.task_execution, _bridge ~= nil)
  if not canRun then
    sendAssignAck(p.assignment_id, false, whyNot)
    log.info(LOG_TAG, "assignment refused: " .. tostring(whyNot))
    return
  end
  sendAssignAck(p.assignment_id, true)
  --! Inflight from the ACK onward, not from the dispatch. The dispatch
  --! runs one event-loop cycle later, and a CLUSTER_CANCEL landing in
  --! that window used to find nothing inflight: it reported "cancelled"
  --! to the Master, and then the timer fired and ran the assignment
  --! anyway, reporting a SECOND result. The pending record makes the
  --! cancel land on the assignment it was meant for.
  _inflight[p.assignment_id] = { id = p.assignment_id, p = p, cancelled = false,
                                 pending = true, bridgeTids = {} }
  
  
  event.timer(0.1, function() pcall(dispatchAssignment, p) end)
end

local function onCancel(packet, from)
  
  
  
  
  
  
  
  
  
  
  
  local p = packet.payload or {}
  
  
  
  if from and from ~= _state.master_addr then
    log.warn(LOG_TAG, "cancel from non-master " .. tostring(from):sub(1, 8) .. " ignored")
    return
  end
  local in_f = _inflight[p.assignment_id]
  if not in_f then
    
    
    
    
    sendResult(p.assignment_id, "cancelled", nil, nil,
      { reason = "cancel_for_unknown_inflight" })
    return
  end
  in_f.cancelled = true
  if in_f.pending then
    
    
    log.info(LOG_TAG, string.format("cancel before dispatch for assignment %s",
      tostring(p.assignment_id)))
    return
  end
  
  
  
  
  
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





local function registerTick()
  if _state.registered then return end
  if computer.uptime() - _state.last_register_try < _cfg.register_retry_seconds then
    return
  end
  sendRegister()
end

local function heartbeatTick()
  if not _state.registered then return end
  
  
  
  
  local now = computer.uptime()
  if now - (_state.last_heartbeat or 0) < (_state.heartbeat_interval or 0) then return end
  _state.last_heartbeat = now
  sendHeartbeat()
end





function mgr.start()
  if _running then return true end
  _cfg = loadConfig()
  _state = freshState()
  if not _cfg.master_address then
    log.error(LOG_TAG, "no master_address in /etc/cluster-manager.cfg; refusing to start")
    return false, "no master_address"
  end

  
  local function add(typeStr, cb)
    local id = net.on(typeStr, cb)
    _listeners[#_listeners + 1] = { type = typeStr, id = id }
  end
  add(protocol.TYPE.CLUSTER_REGISTER_ACK, onRegisterAck)
  add(protocol.TYPE.CLUSTER_ASSIGN,       onAssign)
  add(protocol.TYPE.CLUSTER_CANCEL,       onCancel)
  add(protocol.TYPE.CLUSTER_DRAIN,        onDrain)

  
  
  _timers.register = event.interval(_cfg.register_retry_seconds,
    registerTick, "cluster-mgr.register")
  
  
  _timers.heartbeat = event.interval(_cfg.min_heartbeat_seconds,
    heartbeatTick, "cluster-mgr.heartbeat")

  
  
  
  
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

  
  
  
  do
    local pol = _cfg.task_execution
    if pol ~= "inline" and pol ~= "bridge" and pol ~= "refuse" then
      log.warn(LOG_TAG, "task_execution=" .. tostring(pol)
        .. " is not a known policy; treating it as 'inline'")
      _cfg.task_execution = "inline"; pol = "inline"
    end
    if pol == "inline" then
      if not (type(debug) == "table" and type(debug.sethook) == "function") then
        log.warn(LOG_TAG, "task_execution=inline and mid-task cancellation is "
          .. "UNAVAILABLE here (OpenComputers withholds debug.sethook): a task "
          .. "that never returns cannot be stopped, and OC's watchdog will "
          .. "reboot this whole computer, every seat included. Set "
          .. "task_execution='bridge' (run tasks on an OpenOS worker) or "
          .. "'refuse' (run none) in /etc/cluster-manager.cfg to bound it.")
      end
    elseif pol == "bridge" and not _bridge then
      log.warn(LOG_TAG, "task_execution=bridge but no worker bridge is up: "
        .. "every assignment carrying tasks will be refused until one is.")
    elseif pol == "refuse" then
      log.info(LOG_TAG, "task_execution=refuse: assignments carrying task code "
        .. "are rejected; this Manager contributes presence and storage only.")
    end
  end

  
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
  
  if _bridge and _bridge.mod and _bridge.mod.stop then
    pcall(_bridge.mod.stop)
  end
  _bridge = nil
  _running = false
  _state.registered = false
  log.info(LOG_TAG, "stopped")
  return true
end


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
    
    cancel_midtask      = (type(debug) == "table" and type(debug.sethook) == "function"),
    
    task_execution      = _cfg.task_execution,
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











function mgr.pair(masterAddr, code, opts)
  opts = opts or {}
  if type(masterAddr) ~= "string" or #masterAddr < 16 then
    return false, "invalid master address"
  end
  if type(code) ~= "string" or #code < 12 then
    return false, "pairing code looks too short"
  end
  
  
  
  local crypto = require("kernel.crypto")
  local trustMod = require("kernel.net.trust")

  
  
  local secret = crypto.hashPassword(code, "tos-cluster-pair-v1")

  
  
  
  local TIER_ROOT = 3
  local ok1 = pcall(trustMod.setLevel, "root", masterAddr, trustMod.LEVEL.TRUSTED, TIER_ROOT)
  local ok2 = pcall(trustMod.setSecret, "root", masterAddr, secret, TIER_ROOT)
  if not (ok1 and ok2) then
    return false, "could not update local trust DB (admin tier required?)"
  end

  --! BOTH MACs COVER THE MANAGER'S OWN ADDRESS. The Master verifies the
  --! init with macForCode(secret, from, ts) where `from` is what it saw
  --! on the wire -- this machine's modem address -- and signs its
  --! confirm the same way. This side used to MAC over the MASTER's
  --! address in both places, so every pairing died at "pair_init MAC
  --! mismatch" on the Master, and had the Master ever answered, the
  --! confirm would have failed here too. The comment beside the old
  --! check even said "the address it covers is OUR address" and then
  --! used the other one. net.getAddress() is the clean way to get our
  --! modem address that the old fallback comment said did not exist.
  --! (test_cluster_pairing.lua drives the real Master pair module
  --! against this function.)
  local selfAddr = net.getAddress and net.getAddress() or nil
  if type(selfAddr) ~= "string" or #selfAddr < 16 then
    return false, "cannot determine this machine's modem address (no modem?)"
  end
  local ts = computer.uptime()
  local mac = crypto.hmac(secret, tostring(selfAddr) .. "|" .. tostring(ts))
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
    local expected = crypto.hmac(secret, tostring(selfAddr) .. "|" .. tostring(p.ts))
    if crypto.ctEquals(expected, p.mac) then
      got_confirm = true
    else
      confirm_err = "MAC mismatch"
    end
  end)

  local ok_send, send_err = pcall(net.send, masterAddr, init)
  if not ok_send then
    net.off(protocol.TYPE.CLUSTER_PAIR_CONFIRM, listenerId)
    return false, "send failed: " .. tostring(send_err)
  end

  
  local deadline = computer.uptime() + 10
  while not got_confirm and computer.uptime() < deadline do
    event.pull(0.25)
  end
  net.off(protocol.TYPE.CLUSTER_PAIR_CONFIRM, listenerId)

  if got_confirm then
    
    
    if _state then _state.master_addr = masterAddr end
    return true, "paired"
  end
  
  
  
  return false, "no confirm received within 10s (local trust DB still updated; check net link). " ..
    (confirm_err or "")
end

return mgr
