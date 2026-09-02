local computer = require("computer")
local proc = {}

local STATE = {
  RUNNING  = "running",
  READY    = "ready",
  SLEEPING = "sleeping",
  TSR      = "tsr",
  DEAD     = "dead",
}

local processes = {}
local pidCounter = 0

local genCounter = 0
local currentPID = nil
local foregroundPID = nil

local displayForeground = {}

local INPUT_SIGNALS = {
  key_down = true, key_up = true, clipboard = true,
  touch = true, drag = true, drop = true, scroll = true,
}

local screenMod = nil
local function getScreen()
  if screenMod == nil then
    local ok, mod = pcall(require, "kernel.screen")
    screenMod = ok and mod or false
  end
  return screenMod or nil
end

local runnableCache = nil
local runnableDirty = true

local function invalidateRunnable() runnableDirty = true end

local listenerPID = nil

function proc.withListener(pid, fn, ...)

  local prev = listenerPID
  listenerPID = pid
  local ok, a, b, c, d = pcall(fn, ...)
  listenerPID = prev
  if not ok then error(a, 0) end
  return a, b, c, d
end

function proc.genOf(pid)
  local p = processes[pid]
  return p and p.gen or nil
end

local function effectiveCallerPID()
  if currentPID then return currentPID end
  if listenerPID then return listenerPID end
  return nil
end

local function rebuildRunnable()
  local pids = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then pids[#pids + 1] = pid end
  end

  local prio = {}
  for _, pid in ipairs(pids) do prio[pid] = processes[pid].priority or 5 end
  table.sort(pids, function(a, b) return prio[a] < prio[b] end)
  runnableCache = pids
  runnableDirty = false
end

local function buildInterestSet(decl)
  if type(decl) ~= "table" then return nil end
  local set = {}
  local any = false
  for k, v in pairs(decl) do
    if type(k) == "number" and type(v) == "string" then
      set[v] = true; any = true
    elseif type(k) == "string" and v == true then
      set[k] = true; any = true
    end
  end
  return any and set or nil
end

function proc.spawn(name, func, opts)
  opts = opts or {}

  repeat
    pidCounter = pidCounter + 1
  until processes[pidCounter] == nil
  local pid = pidCounter
  genCounter = genCounter + 1
  local gen = genCounter
  local co = coroutine.create(func)

  local parentProc = currentPID and processes[currentPID] or nil
  local inherit = (opts.inherit ~= false)

  local principal = opts.principal
  local token     = opts.token
  local cwd       = opts.cwd
  local stdin     = opts.stdin
  local stdout    = opts.stdout
  local stderr    = opts.stderr
  local display   = opts.display

  if inherit and parentProc then
    principal = principal or parentProc.principal
    token     = token     or parentProc.token
    cwd       = cwd       or parentProc.cwd
    stdin     = stdin     or parentProc.stdin
    stdout    = stdout    or parentProc.stdout
    stderr    = stderr    or parentProc.stderr
    display   = display   or parentProc.display
  end

  local caps = {}
  if opts.caps then
    for k, v in pairs(opts.caps) do caps[k] = v end
  elseif inherit and parentProc and parentProc.caps then
    for k, v in pairs(parentProc.caps) do caps[k] = v end
  end
  if inherit and parentProc then
    local parentCaps = parentProc.caps or {}
    for k in pairs(caps) do
      if not parentCaps[k] then caps[k] = nil end
    end
  end

  processes[pid] = {
    pid       = pid,
    gen       = gen,
    name      = name or ("proc_" .. pid),
    coroutine = co,
    state     = STATE.READY,
    tsr       = opts.tsr or false,
    priority  = opts.priority or 5,
    source    = opts.source or "user",
    created   = computer.uptime(),
    lastRun   = 0,
    cpuTime   = 0,

    cpuBudget = opts.cpuBudget,

    signalInterest = buildInterestSet(opts.signalInterest),

    background = opts.background,
    bgSince    = nil,
    bgTicks    = 0,

    signals   = {},
    sigHead   = 1,
    sigTail   = 0,
    env       = {},
    parent    = currentPID,

    principal = principal,
    token     = token,
    caps      = caps,
    cwd       = cwd or "/",
    stdin     = stdin,
    stdout    = stdout,
    stderr    = stderr,
    display   = display,
  }
  invalidateRunnable()
  return pid
end

local COOP_SLICE = 0.05

local function canYield()
  if coroutine.isyieldable then return coroutine.isyieldable() end
  local co, isMain = coroutine.running()

  if isMain == true then return false end
  return co ~= nil
end

function proc.yieldCooperative()
  local p = currentPID and processes[currentPID]
  if not p then return false end
  if not canYield() then return false end
  if computer.uptime() - (p._resumeStart or 0) < COOP_SLICE then return false end
  p._coopYield = true
  coroutine.yield()
  return true
end

proc._canYield = canYield

function proc.setSignalInterest(decl)
  local p = currentPID and processes[currentPID]
  if not p then return false, "no current process" end
  p.signalInterest = buildInterestSet(decl)
  return true
end

function proc.currentSession()
  local p = proc.current()
  return p and p.principal or nil
end

function proc.currentToken()
  local p = proc.current()
  return p and p.token or nil
end

function proc.current()
  return currentPID and processes[currentPID] or nil
end

function proc.get(pid) return processes[pid] end

function proc.list()
  local result = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then
      result[#result + 1] = {
        pid = p.pid, name = p.name, state = p.state,
        tsr = p.tsr, priority = p.priority,
        cpuTime = p.cpuTime, source = p.source,
        parent = p.parent,

        user = p.principal and p.principal.user or nil,
        cwd  = p.cwd,
        display = p.display,
        sigDropped = p.sigDropped or 0,
      }
    end
  end
  table.sort(result, function(a, b) return a.pid < b.pid end)
  return result
end

local function callerMayControl(caller, p)
  local callerTier = caller.principal and caller.principal.tier or 0
  if callerTier >= 3 then return true end
  local callerUser = caller.principal and caller.principal.user
  local targetUser = p.principal and p.principal.user
  if callerUser == nil or targetUser == nil then

    return callerTier >= 2 and caller.display ~= nil
       and caller.display == p.display
  end
  if callerTier >= 2 then
    return callerUser == targetUser or caller.display == p.display
  end
  return callerUser == targetUser
end

function proc.kill(pid, opts)
  local p = processes[pid]
  if not p then return false, "No such process" end

  local callerPid = effectiveCallerPID()
  if not callerPid then

    if not (type(opts) == "table" and opts.kernel) then
      return false, "Permission denied (no caller)"
    end
  else
    local caller = processes[callerPid]
    if caller and not callerMayControl(caller, p) then
      return false, "Permission denied"
    end
  end

  p.state = STATE.DEAD
  invalidateRunnable()

  if pid == foregroundPID then
    if p.parent and processes[p.parent] and processes[p.parent].state ~= STATE.DEAD then
      foregroundPID = p.parent
    else
      proc.cycleForeground()
    end
  end

  for dIdx, fgPid in pairs(displayForeground) do
    if fgPid == pid then
      if p.parent and processes[p.parent]
         and processes[p.parent].state ~= STATE.DEAD
         and processes[p.parent].display == dIdx then
        displayForeground[dIdx] = p.parent
      else
        displayForeground[dIdx] = nil
      end
    end
  end
  local event = require("kernel.event")
  event.removeSource("proc:" .. pid)
  return true
end

function proc.goTSR(pid)
  local targetPid = pid or currentPID
  local p = processes[targetPid]
  if not p then return false end

  local callerPid = effectiveCallerPID()
  if pid and callerPid and pid ~= callerPid then
    local caller = processes[callerPid]
    if caller and not callerMayControl(caller, p) then
      return false, "Permission denied"
    end
  end

  p.tsr = true; p.state = STATE.TSR
  return true
end

local MAX_SIGNAL_QUEUE = 256

local function sigCount(p)
  return p.sigTail - p.sigHead + 1
end

local function enqueueSignal(p, ...)

  if p.sigHead == nil then p.sigHead, p.sigTail = 1, #p.signals end

  if sigCount(p) >= MAX_SIGNAL_QUEUE then
    p.signals[p.sigHead] = nil
    p.sigHead = p.sigHead + 1
    p.sigDropped = (p.sigDropped or 0) + 1
  end
  p.sigTail = p.sigTail + 1
  p.signals[p.sigTail] = table.pack(...)

  if p.sigHead > 256 and p.sigHead <= p.sigTail + 1 then
    local newSignals = {}
    local j = 1
    for i = p.sigHead, p.sigTail do
      newSignals[j] = p.signals[i]
      j = j + 1
    end
    p.signals = newSignals
    p.sigTail = j - 1
    p.sigHead = 1
  elseif p.sigHead > p.sigTail then

    p.signals = {}
    p.sigHead, p.sigTail = 1, 0
  end
end

function proc.signal(pid, ...)
  local p = processes[pid]
  if not p or p.state == STATE.DEAD then return false end

  local callerPid = effectiveCallerPID()
  if not callerPid then
    return false, "Permission denied (no caller)"
  end
  if pid ~= callerPid then
    local caller = processes[callerPid]
    if caller and not callerMayControl(caller, p) then
      return false, "Permission denied"
    end
  end

  enqueueSignal(p, ...)
  return true
end

function proc.signalKernel(pid, ...)
  local p = processes[pid]
  if not p or p.state == STATE.DEAD then return false end
  enqueueSignal(p, ...)
  return true
end

function proc.setForeground(pid, displayIdx, opts)

  if opts and opts.kernel then
    if displayIdx then displayForeground[displayIdx] = pid
    else foregroundPID = pid end
    return true
  end

  local caller = currentPID and processes[currentPID] or nil
  if caller and displayIdx then
    local callerTier = caller.principal and caller.principal.tier or 0
    if callerTier < 3 and caller.display ~= displayIdx then
      return false, "Permission denied (wrong seat)"
    end
  end

  if caller and pid then
    local target = processes[pid]

    local ownChildSameSeat = target ~= nil
      and target.parent == currentPID
      and caller.display ~= nil
      and target.display == caller.display
    if target and not ownChildSameSeat
       and not callerMayControl(caller, target) then
      return false, "Permission denied (not your process)"
    end
  end
  if displayIdx then
    displayForeground[displayIdx] = pid
  else
    foregroundPID = pid
  end
  return true
end

function proc.getForeground(displayIdx)
  if displayIdx then
    return displayForeground[displayIdx] or foregroundPID
  end
  return foregroundPID
end

function proc.cycleForeground()
  local pids = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then pids[#pids + 1] = pid end
  end
  table.sort(pids)
  if #pids == 0 then foregroundPID = nil return end

  local idx = 1
  for i, pid in ipairs(pids) do
    if pid == foregroundPID then idx = i break end
  end
  idx = (idx % #pids) + 1
  foregroundPID = pids[idx]
  return foregroundPID
end

local PREEMPT_CRUMB = "/var/crash/preempt.txt"

function proc.preemptionAvailable()
  return type(debug) == "table" and type(debug.sethook) == "function"
end

local function preemptCrumb(p)
  pcall(function()
    local f = _G._TOS and _G._TOS.fs
    if not f or not f.writeFile then return end
    pcall(f.makeDirectory, "/var/crash")
    f.writeFile(PREEMPT_CRUMB,
      "pid=" .. tostring(p.pid) .. " name=" .. tostring(p.name or "?") ..
      " user=" .. tostring(p.principal and p.principal.user or "?") ..
      " uptime=" .. tostring(computer.uptime()) .. "\n" ..
      "This process exceeded its CPU budget and trapped the preemption\n" ..
      "error; if the machine then rebooted via the OC watchdog, it was\n" ..
      "the likely cause.\n")
  end)
end

local function clearPreemptCrumb()
  pcall(function()
    local f = _G._TOS and _G._TOS.fs
    if f and f.remove and f.exists and f.exists(PREEMPT_CRUMB) then
      f.remove(PREEMPT_CRUMB)
    end
  end)
end

local function starveHook()
  error("scheduler: preempted (wall-clock budget exceeded)", 0)
end

proc.BG_DIVISOR = 2
proc.BG_GRACE   = 30

function proc.bgShouldResume(policy, bgSeconds, bgTicks)
  bgSeconds = bgSeconds or 0
  bgTicks   = bgTicks or 0
  if policy == "freeze" then return false, "frozen" end

  if policy ~= "always" and bgSeconds >= proc.BG_GRACE then
    return false, "frozen"
  end
  return (bgTicks % proc.BG_DIVISOR) == 0, "drowsy"
end

local function markBackground(p, isForeground, now)
  if not p or not p.background then return end
  if isForeground then
    p.bgSince, p.bgTicks = nil, 0
  elseif not p.bgSince then
    p.bgSince, p.bgTicks = now or computer.uptime(), 0
  end
end

function proc.bgState(pid, now)
  local p = processes[pid]
  if not p or not p.background or not p.bgSince then return "live" end
  local _, state = proc.bgShouldResume(p.background,
    (now or computer.uptime()) - p.bgSince, p.bgTicks)
  return state
end

local function bgSkipped(p, pid, inputFgPID)
  if not p.background then return false end

  local seatFg = p.display and displayForeground[p.display] or nil
  if pid == seatFg or (not p.display and pid == foregroundPID)
     or pid == inputFgPID then
    markBackground(p, true)
    return false
  end

  if (p.sigTail or 0) >= (p.sigHead or 1) then return false end
  markBackground(p, false)
  local resume = proc.bgShouldResume(p.background,
    computer.uptime() - (p.bgSince or 0), p.bgTicks)
  p.bgTicks = p.bgTicks + 1
  return not resume
end

local function wakeSkipped(p, signal, isInput)
  if not p.signalInterest then return false end
  if p._coopYield then return false end
  if isInput or not signal or signal[1] == nil then return false end
  if p.sigHead == nil then p.sigHead, p.sigTail = 1, #p.signals end
  if p.sigTail >= p.sigHead then return false end
  return not p.signalInterest[signal[1]]
end

function proc.tick(signal)

  if runnableDirty then rebuildRunnable() end
  local pids = runnableCache

  local isInput = signal and signal[1] and INPUT_SIGNALS[signal[1]]

  local inputFgPID = foregroundPID
  if isInput and signal[2] then
    local scr = getScreen()
    if scr then
      local dIdx
      local sigType = signal[1]
      if sigType == "key_down" or sigType == "key_up" or sigType == "clipboard" then
        dIdx = scr.displayForKeyboard(signal[2])
      elseif sigType == "touch" or sigType == "drag" or sigType == "drop" or sigType == "scroll" then
        dIdx = scr.displayForScreen(signal[2])
      end
      if dIdx then
        inputFgPID = displayForeground[dIdx] or foregroundPID
      end
    end
  end

  for _, pid in ipairs(pids) do
    local p = processes[pid]
    if p and p.state ~= STATE.DEAD then
      local co = p.coroutine

      local coStatus = coroutine.status(co)
      if coStatus == "dead" then
        p.state = STATE.DEAD
        invalidateRunnable()
      elseif coStatus == "suspended" and wakeSkipped(p, signal, isInput) then

      elseif coStatus == "suspended" and bgSkipped(p, pid, inputFgPID) then

      elseif coStatus == "suspended" then
        currentPID = pid
        p.state = STATE.RUNNING
        local startTime = computer.uptime()

        p._resumeStart = startTime

        local resumeData = nil
        if p.sigHead == nil then p.sigHead, p.sigTail = 1, #p.signals end
        if p._coopYield then

          p._coopYield = false
        elseif p.sigTail >= p.sigHead then

          resumeData = p.signals[p.sigHead]
          p.signals[p.sigHead] = nil
          p.sigHead = p.sigHead + 1
        elseif isInput then

          if pid == inputFgPID then
            resumeData = signal
          end

        else

          resumeData = signal
        end

        --! PREEMPTION DOES NOT HAPPEN ON OPENCOMPUTERS. Everything below
        --! hangs off debug.sethook, and OC's sandbox does not export it:
        --! machine.lua's `debug = {` table is exactly getinfo, traceback,
        --! getlocal and getupvalue. The machine keeps sethook for its own
        --! "too long without yielding" deadline and does not hand guest code
        --! a way to disarm that. So `debug.sethook` is nil, the guard below
        --! is false, and no budget is ever armed.
        --!
        --! The comment that follows was written believing otherwise: it said
        --! the hook was available "on every Lua version OC ships" and that
        --! the wall-clock fallback therefore worked here. The reasoning about
        --! yielding across a C boundary is correct and worth keeping; the
        --! conclusion drawn from it is not.
        --!
        --! What actually bounds a runaway process on OC is the machine
        --! watchdog, which kills the WHOLE COMPUTER rather than the process
        --! -- which is precisely the "blast radius" this code was written to
        --! shrink, and does not. The preemptCrumb breadcrumb below still
        --! earns its keep for exactly that reason: on OC the watchdog reboot
        --! IS the outcome, so a note naming the culprit is the only thing
        --! that survives to explain it -- except that it too is only written
        --! from inside the hook, so it never fires either.
        --!
        --! Kept rather than deleted: it is correct on any host that does
        --! export sethook (every off-box test run, and the suite exercises
        --! it), and TOS is not exclusively an OC target in principle. But
        --! nothing may describe this as a live guarantee. (test_sethook_absent.lua)

        local PROC_WALL_BUDGET = 0.5

        local budget = (p.cpuBudget == nil) and PROC_WALL_BUDGET or p.cpuBudget
        local hookInstalled = false
        local hookFired = false
        if budget ~= math.huge and type(debug) == "table" and debug.sethook then
          local deadline = startTime + budget
          local ok2 = pcall(debug.sethook, co, function()
            if computer.uptime() > deadline then

              if not hookFired then
                hookFired = true
                p._preempted = true
                preemptCrumb(p)
                pcall(debug.sethook, starveHook, "", 1)
              end
              error("scheduler: process exceeded wall-clock budget (" ..
                budget .. "s)", 0)
            end
          end, "", 10000)
          if ok2 then hookInstalled = true end
        end

        local ok, result
        if resumeData then
          ok, result = coroutine.resume(co, table.unpack(resumeData, 1, resumeData.n or #resumeData))
        else
          ok, result = coroutine.resume(co)
        end

        if hookInstalled then
          pcall(debug.sethook, co)
        end
        if hookFired then

          clearPreemptCrumb()
        end

        p.cpuTime = p.cpuTime + (computer.uptime() - startTime)
        p.lastRun = computer.uptime()

        if not ok then
          p.state = STATE.DEAD
          p.error = tostring(result)
          invalidateRunnable()
        elseif coroutine.status(co) == "dead" then
          p.state = STATE.DEAD
          invalidateRunnable()
        else
          p.state = p.tsr and STATE.TSR or STATE.READY
        end
        currentPID = nil
      end
    end
  end

  for _, p in pairs(processes) do
    if p.state == STATE.DEAD and p.coroutine then
      p.coroutine = nil
    end
  end

  local deadPIDs = {}
  for pid, p in pairs(processes) do
    if p.state == STATE.DEAD then deadPIDs[#deadPIDs + 1] = pid end
  end
  if #deadPIDs > 3 then
    table.sort(deadPIDs)
    for i = 1, #deadPIDs - 3 do
      processes[deadPIDs[i]] = nil
    end
  end

  for dIdx, fgPid in pairs(displayForeground) do
    if not processes[fgPid] or processes[fgPid].state == STATE.DEAD then
      local deadP = processes[fgPid]
      if deadP and deadP.parent and processes[deadP.parent]
         and processes[deadP.parent].state ~= STATE.DEAD
         and processes[deadP.parent].display == dIdx then
        displayForeground[dIdx] = deadP.parent
      else
        displayForeground[dIdx] = nil
      end
    end
  end
end

function proc.yield()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
end

function proc.sleep(seconds)
  local deadline = computer.uptime() + seconds
  while computer.uptime() < deadline do
    if coroutine.isyieldable and coroutine.isyieldable() then
      coroutine.yield()
    else
      computer.pullSignal(math.min(0.05, deadline - computer.uptime()))
    end
  end
end

function proc.count()
  local alive = 0
  for _, p in pairs(processes) do
    if p.state ~= STATE.DEAD then alive = alive + 1 end
  end
  return alive
end

proc.STATE = STATE
return proc
