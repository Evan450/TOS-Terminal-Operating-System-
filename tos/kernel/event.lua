-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Event System           ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")

local event = {}

-- Registered listeners: signal_name -> { {callback, source}, ... }
local listeners = {}
-- One-shot timers: { deadline, callback, id }
local timers = {}
local timerNextID = 1

-- Timer-callback error accounting (#REV review finding #7). Callback
-- errors can't crash the pump and kernel.log may not be loaded at fire
-- time (boot order), so they used to vanish entirely — a chronically
-- crashing cron or net retry timer was invisible. Count them here and
-- flush into log.warn lazily on the next pull once the log resolves.
local timerErrPending, timerErrTotal = 0, 0
local timerErrLast, timerErrSource = nil, nil

local function noteTimerError(t, err)
  timerErrPending = timerErrPending + 1
  timerErrTotal = timerErrTotal + 1
  timerErrLast = tostring(err)
  timerErrSource = t and t.source or "unknown"
end

--- Timer-callback error vitals (for doctor/monitor).
-- @return number, string|nil, string|nil: total errors, last error, its source
function event.timerErrors()
  return timerErrTotal, timerErrLast, timerErrSource
end

-- Cached kernel.process ref. event loads before process at boot, so this
-- can't be a top-level require; resolve lazily and cache on first success
-- (retrying is cheap and only happens in the early-boot window). Saves a
-- pcall(require, ...) on every event.pull dispatch — the hottest loop in
-- the system.
local procModCache = nil
local function getProc()
  if not procModCache then
    local okP, m = pcall(require, "kernel.process")
    if okP then procModCache = m end
  end
  return procModCache
end

-- ============================================================
-- Listener management
-- ============================================================

--- Register a listener for a specific signal type
-- @param signal string: Signal name (e.g., "key_down", "modem_message")
-- @param callback function: Handler function(signal, ...)
-- @param source string: (optional) Identifier for who registered this
-- @return number: Listener ID for removal
function event.on(signal, callback, source)
  if not listeners[signal] then
    listeners[signal] = {}
  end
  -- #SEC H13 — record the registering process's PID so the dispatcher
  -- can re-enter the callback with the right caller context (proc.kill,
  -- proc.signal will see the registering PID, not nil-kernel).
  local regPid = nil
  local regGen = nil
  local procMod = getProc()
  if procMod and procMod.current then
    local cur = procMod.current()
    if cur then
      regPid = cur.pid
      regGen = procMod.genOf and procMod.genOf(cur.pid) or nil  -- #SEC M-11
    end
  end
  local entry = {
    callback = callback,
    source   = source or "unknown",
    id       = timerNextID,
    regPid   = regPid,
    regGen   = regGen,
  }
  timerNextID = timerNextID + 1
  listeners[signal][#listeners[signal] + 1] = entry
  return entry.id
end

--- Register a one-time listener (auto-removes after firing)
function event.once(signal, callback, source)
  local id
  id = event.on(signal, function(...)
    event.off(signal, id)
    return callback(...)
  end, source)
  return id
end

--- Remove a listener by signal + id
function event.off(signal, id)
  if not listeners[signal] then return end
  for i, entry in ipairs(listeners[signal]) do
    if entry.id == id then
      table.remove(listeners[signal], i)
      return true
    end
  end
  return false
end

--- Remove all listeners registered by a source
function event.removeSource(source)
  for signal, list in pairs(listeners) do
    for i = #list, 1, -1 do
      if list[i].source == source then
        table.remove(list, i)
      end
    end
  end
end

-- ============================================================
-- Timer support
-- ============================================================

-- #SEC H31 — capture the registering process so the firing context
-- matches proc.signal/proc.kill expectations. Same idea as event.on.
-- #SEC M-11 — return BOTH the registering PID and its spawn generation
-- so the dispatcher can detect PID reuse before re-entering the callback.
local function captureRegPid()
  local procMod = getProc()
  if procMod and procMod.current then
    local cur = procMod.current()
    if cur then
      local gen = procMod.genOf and procMod.genOf(cur.pid) or nil
      return cur.pid, gen
    end
  end
  return nil, nil
end

--- Schedule a callback after `delay` seconds
-- @return number: Timer ID
function event.timer(delay, callback, source)
  local id = timerNextID
  timerNextID = timerNextID + 1
  local regPid, regGen = captureRegPid()  -- #SEC M-11
  timers[#timers + 1] = {
    deadline = computer.uptime() + delay,
    callback = callback,
    source   = source or "unknown",
    id       = id,
    interval = nil,
    regPid   = regPid,
    regGen   = regGen,
  }
  return id
end

--- Schedule a repeating callback
function event.interval(delay, callback, source)
  local id = timerNextID
  timerNextID = timerNextID + 1
  local regPid, regGen = captureRegPid()  -- #SEC M-11
  timers[#timers + 1] = {
    deadline = computer.uptime() + delay,
    callback = callback,
    source   = source or "unknown",
    id       = id,
    interval = delay,
    regPid   = regPid,
    regGen   = regGen,
  }
  return id
end

--- Cancel a timer
function event.cancelTimer(id)
  for i, t in ipairs(timers) do
    if t.id == id then
      table.remove(timers, i)
      return true
    end
  end
  return false
end

-- ============================================================
-- Core event loop
-- ============================================================

--- Pull one event, dispatch to listeners, handle timers
-- @param timeout number: Max seconds to wait (default 0.5)
-- @return string, ...: The signal and its arguments
function event.pull(timeout)
  timeout = timeout or 0.5

  -- Lazy flush of accumulated timer-callback errors. Deliberately here
  -- rather than at fire time: no boot-order dependency on kernel.log,
  -- and a rapid-fire crashing timer produces one summarizing line per
  -- pull instead of a log flood.
  if timerErrPending > 0 then
    local lg = package.loaded and package.loaded["kernel.log"]
    if lg and lg.warn then
      pcall(lg.warn, "event", "timer callback errors: +" .. timerErrPending
        .. " (total " .. timerErrTotal .. "), last ["
        .. tostring(timerErrSource) .. "]: " .. tostring(timerErrLast))
      timerErrPending = 0
    end
  end

  -- Check timers first
  local now = computer.uptime()
  local nextDeadline = now + timeout

  local procMod = getProc()
  for i = #timers, 1, -1 do
    local t = timers[i]
    if now >= t.deadline then
      -- #SEC H31 — fire timer under registering PID's context so
      -- proc.signal/kill called from the callback see that PID's
      -- tier rather than kernel's.
      -- #SEC M-11 — if the registering process has died or its PID was
      -- reused by a different spawn (generation mismatch), the timer is
      -- stale: drop it WITHOUT firing, so its callback never runs under a
      -- wrong/new principal.
      local stale = t.regPid ~= nil and t.regGen ~= nil and procMod
        and procMod.genOf and (procMod.genOf(t.regPid) ~= t.regGen)
      if stale then
        table.remove(timers, i)
      else
        if procMod and procMod.withListener and t.regPid then
          local ok, err = pcall(procMod.withListener, t.regPid, t.callback)
          if not ok then noteTimerError(t, err) end
        else
          local ok, err = pcall(t.callback)
          if not ok then
            -- Don't crash the pump — but don't lose it either: count it
            -- and let the next pull flush into the log (see below).
            noteTimerError(t, err)
          end
        end
        if t.interval then
          t.deadline = now + t.interval
        else
          table.remove(timers, i)
        end
      end
    else
      if t.deadline < nextDeadline then
        nextDeadline = t.deadline
      end
    end
  end

  -- Calculate remaining wait time
  local waitTime = math.max(0, math.min(timeout, nextDeadline - computer.uptime()))

  -- Pull signal from OC
  local signal = table.pack(computer.pullSignal(waitTime))

  if signal[1] then
    -- Dispatch to specific listeners (snapshot the list so that event.off
    -- calls from one-shot listeners don't skip entries during iteration).
    -- #SEC H13 — each listener fires under its registering PID context
    -- via proc.withListener, so proc.signal/kill called from the
    -- callback see that PID's tier (not nil-kernel).
    local stype = signal[1]
    -- procMod was resolved once above the timer loop (same pull call).
    local function dispatchOne(entry, ...)
      if procMod and procMod.withListener and entry.regPid then
        -- #SEC M-11 — skip if the registering process is gone or its PID
        -- was reused by a different spawn. Running the callback under the
        -- new occupant's principal is the cross-principal hazard.
        if entry.regGen ~= nil and procMod.genOf
           and procMod.genOf(entry.regPid) ~= entry.regGen then
          return false
        end
        local ok = pcall(procMod.withListener, entry.regPid, entry.callback, ...)
        return ok
      end
      return pcall(entry.callback, ...)
    end
    if listeners[stype] then
      local snapshot = {table.unpack(listeners[stype])}
      for _, entry in ipairs(snapshot) do
        dispatchOne(entry, table.unpack(signal, 1, signal.n))
      end
    end
  end

  return table.unpack(signal, 1, signal.n)
end

--- Pull a specific signal type, with timeout
function event.pullFiltered(filter, timeout)
  local deadline = computer.uptime() + (timeout or math.huge)
  while true do
    local remaining = deadline - computer.uptime()
    if remaining <= 0 then return nil end
    local sig = table.pack(event.pull(remaining))
    if sig[1] and (not filter or filter(table.unpack(sig, 1, sig.n))) then
      return table.unpack(sig, 1, sig.n)
    end
  end
end

--- Push a custom signal into the OC event queue (wraps computer.pushSignal)
-- Used by the shell to emit tos_logout, tos_shutdown, etc.
function event.push(...)
  computer.pushSignal(...)
end

return event
