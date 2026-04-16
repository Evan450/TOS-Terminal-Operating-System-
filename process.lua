-- TOS Kernel - Process Manager
-- Cooperative multitasking with foreground/background

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
local currentPID = nil
local foregroundPID = nil

-- Per-display foreground mapping: display index → PID.
-- When a keyboard event arrives from display N, we deliver it to
-- displayForeground[N] instead of the global foregroundPID.
-- Falls back to foregroundPID if unmapped.
local displayForeground = {}

-- Input signals that only go to foreground process
local INPUT_SIGNALS = {
  key_down = true, key_up = true, clipboard = true,
  touch = true, drag = true, drop = true, scroll = true,
}

-- Screen module reference (lazy-loaded to avoid circular deps at boot)
local screenMod = nil
local function getScreen()
  if screenMod == nil then
    local ok, mod = pcall(require, "kernel.screen")
    screenMod = ok and mod or false
  end
  return screenMod or nil
end

-- ============================================================
-- Process creation
-- ============================================================

function proc.spawn(name, func, opts)
  opts = opts or {}
  pidCounter = pidCounter + 1
  local pid = pidCounter
  local co = coroutine.create(func)

  -- Identity inheritance from parent (phase 4).
  -- A child cannot gain caps its parent lacked — intersection only.
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

  -- Capability intersection. Start from parent caps (or full when we are
  -- the root process) and remove anything the caller didn't request. A
  -- child never gains a cap its parent lacks.
  local caps = {}
  if opts.caps then
    for k, v in pairs(opts.caps) do caps[k] = v end
  elseif inherit and parentProc and parentProc.caps then
    for k, v in pairs(parentProc.caps) do caps[k] = v end
  end
  if inherit and parentProc and parentProc.caps then
    for k in pairs(caps) do
      if not parentProc.caps[k] then caps[k] = nil end
    end
  end

  processes[pid] = {
    pid       = pid,
    name      = name or ("proc_" .. pid),
    coroutine = co,
    state     = STATE.READY,
    tsr       = opts.tsr or false,
    priority  = opts.priority or 5,
    source    = opts.source or "user",
    created   = computer.uptime(),
    lastRun   = 0,
    cpuTime   = 0,
    signals   = {},
    env       = {},
    parent    = currentPID,

    -- Phase 4 identity fields
    principal = principal,
    token     = token,
    caps      = caps,
    cwd       = cwd or "/",
    stdin     = stdin,
    stdout    = stdout,
    stderr    = stderr,
    display   = display,
  }
  return pid
end

-- Return the session (principal) of the currently-running process, or
-- nil if none. Wired into securefs.sessionOf() in phase 1 so permission
-- checks follow the process's identity, not a global.
function proc.currentSession()
  local p = proc.current()
  return p and p.principal or nil
end

-- Return the capability set of the currently-running process, or an
-- empty table if unbound. Used by sandbox.build and future hooks.
function proc.currentCaps()
  local p = proc.current()
  return (p and p.caps) or {}
end

-- Return the token of the currently-running process.
function proc.currentToken()
  local p = proc.current()
  return p and p.token or nil
end

function proc.current()
  return currentPID and processes[currentPID] or nil
end

function proc.get(pid) return processes[pid] end

--- Return the display index assigned to a process, or nil.
function proc.displayOf(pid)
  local p = processes[pid]
  return p and p.display or nil
end

function proc.list()
  local result = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then
      result[#result + 1] = {
        pid = p.pid, name = p.name, state = p.state,
        tsr = p.tsr, priority = p.priority,
        cpuTime = p.cpuTime, source = p.source,
        parent = p.parent,
        -- Phase 4 identity fields
        user = p.principal and p.principal.user or nil,
        cwd  = p.cwd,
        display = p.display,
      }
    end
  end
  table.sort(result, function(a, b) return a.pid < b.pid end)
  return result
end

function proc.kill(pid)
  local p = processes[pid]
  if not p then return false, "No such process" end

  -- Permission check: enforce process ownership.
  -- Kernel-initiated kills (no currentPID) always succeed.
  local caller = currentPID and processes[currentPID] or nil
  if caller then
    local callerUser = caller.principal and caller.principal.user
    local callerTier = caller.principal and caller.principal.tier or 0
    local targetUser = p.principal and p.principal.user
    if callerTier < 3 then  -- not root
      if callerTier >= 2 then  -- admin: same-user or same-display
        if callerUser ~= targetUser and caller.display ~= p.display then
          return false, "Permission denied (cross-seat)"
        end
      else  -- regular user / guest: same-user only
        if callerUser ~= targetUser then
          return false, "Permission denied"
        end
      end
    end
  end

  p.state = STATE.DEAD
  -- If killed process was global foreground, switch to parent or first live
  if pid == foregroundPID then
    if p.parent and processes[p.parent] and processes[p.parent].state ~= STATE.DEAD then
      foregroundPID = p.parent
    else
      proc.cycleForeground()
    end
  end
  -- Clean per-display foreground refs to dead process
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
  local p = processes[pid or currentPID]
  if not p then return false end
  p.tsr = true; p.state = STATE.TSR
  return true
end

local MAX_SIGNAL_QUEUE = 256

function proc.signal(pid, ...)
  local p = processes[pid]
  if not p or p.state == STATE.DEAD then return false end
  if #p.signals >= MAX_SIGNAL_QUEUE then
    -- Drop oldest signal to make room
    table.remove(p.signals, 1)
  end
  p.signals[#p.signals + 1] = table.pack(...)
  return true
end

function proc.setForeground(pid, displayIdx)
  -- Permission: caller can only change foreground on their own display (unless root)
  local caller = currentPID and processes[currentPID] or nil
  if caller and displayIdx then
    local callerTier = caller.principal and caller.principal.tier or 0
    if callerTier < 3 and caller.display ~= displayIdx then
      return false, "Permission denied (wrong seat)"
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

--- Cycle foreground to next live process
function proc.cycleForeground()
  local pids = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then pids[#pids + 1] = pid end
  end
  table.sort(pids)
  if #pids == 0 then foregroundPID = nil return end
  -- Find current index and advance
  local idx = 1
  for i, pid in ipairs(pids) do
    if pid == foregroundPID then idx = i break end
  end
  idx = (idx % #pids) + 1
  foregroundPID = pids[idx]
  return foregroundPID
end

-- ============================================================
-- Scheduler
-- ============================================================

function proc.tick(signal)
  local pids = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then pids[#pids + 1] = pid end
  end
  table.sort(pids, function(a, b)
    return (processes[a].priority or 5) < (processes[b].priority or 5)
  end)

  -- Determine if this is an input signal (keyboard/mouse)
  local isInput = signal and signal[1] and INPUT_SIGNALS[signal[1]]

  -- Multi-screen: resolve which display this input belongs to, and
  -- which process is foreground on that display.
  -- OC signal layout: key_down/key_up/clipboard have keyboard addr in [2],
  -- while touch/drag/drop/scroll have screen addr in [2].
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
      if coroutine.status(co) == "dead" then
        p.state = STATE.DEAD
      elseif coroutine.status(co) == "suspended" then
        currentPID = pid
        p.state = STATE.RUNNING
        local startTime = computer.uptime()

        -- Determine what data to pass to this process
        local resumeData = nil
        if #p.signals > 0 then
          -- Process has queued signals - deliver those first
          resumeData = table.remove(p.signals, 1)
        elseif isInput then
          -- Input signals: ONLY to the foreground process on the
          -- relevant display (multi-screen) or the global foreground.
          if pid == inputFgPID then
            resumeData = signal
          end
          -- Background processes get nil (still resumed to do work)
        else
          -- Non-input signals (modem, component, timer): everyone
          resumeData = signal
        end

        local ok, result
        if resumeData then
          ok, result = coroutine.resume(co, table.unpack(resumeData, 1, resumeData.n or #resumeData))
        else
          ok, result = coroutine.resume(co)
        end

        p.cpuTime = p.cpuTime + (computer.uptime() - startTime)
        p.lastRun = computer.uptime()

        if not ok then
          p.state = STATE.DEAD
          p.error = tostring(result)
        elseif coroutine.status(co) == "dead" then
          p.state = STATE.DEAD
        else
          p.state = p.tsr and STATE.TSR or STATE.READY
        end
        currentPID = nil
      end
    end
  end

  -- Free coroutine refs on dead processes so they can be GC'd immediately
  for _, p in pairs(processes) do
    if p.state == STATE.DEAD and p.coroutine then
      p.coroutine = nil
    end
  end
  -- GC dead processes (keep last 3)
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

  -- Clean stale displayForeground entries pointing to dead/GC'd processes
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

--- Yield current process (safe from main thread)
function proc.yield()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
end

--- Sleep (yields repeatedly until deadline)
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
