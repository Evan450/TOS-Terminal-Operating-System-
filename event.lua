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
-- Catch-all listeners (receive every event)
local globalListeners = {}

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
  local entry = { callback = callback, source = source or "unknown", id = timerNextID }
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

--- Register a catch-all listener
function event.onAny(callback, source)
  local entry = { callback = callback, source = source or "unknown", id = timerNextID }
  timerNextID = timerNextID + 1
  globalListeners[#globalListeners + 1] = entry
  return entry.id
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
  for i = #globalListeners, 1, -1 do
    if globalListeners[i].source == source then
      table.remove(globalListeners, i)
    end
  end
end

-- ============================================================
-- Timer support
-- ============================================================

--- Schedule a callback after `delay` seconds
-- @return number: Timer ID
function event.timer(delay, callback, source)
  local id = timerNextID
  timerNextID = timerNextID + 1
  timers[#timers + 1] = {
    deadline = computer.uptime() + delay,
    callback = callback,
    source   = source or "unknown",
    id       = id,
    interval = nil,
  }
  return id
end

--- Schedule a repeating callback
function event.interval(delay, callback, source)
  local id = timerNextID
  timerNextID = timerNextID + 1
  timers[#timers + 1] = {
    deadline = computer.uptime() + delay,
    callback = callback,
    source   = source or "unknown",
    id       = id,
    interval = delay,
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

  -- Check timers first
  local now = computer.uptime()
  local nextDeadline = now + timeout

  for i = #timers, 1, -1 do
    local t = timers[i]
    if now >= t.deadline then
      local ok, err = pcall(t.callback)
      if not ok then
        -- Log error but don't crash
        -- (kernel.log may not be available here, fail silently)
      end
      if t.interval then
        t.deadline = now + t.interval
      else
        table.remove(timers, i)
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
    -- calls from one-shot listeners don't skip entries during iteration)
    local stype = signal[1]
    if listeners[stype] then
      local snapshot = {table.unpack(listeners[stype])}
      for _, entry in ipairs(snapshot) do
        local ok, err = pcall(entry.callback, table.unpack(signal, 1, signal.n))
        if not ok then
          -- Silently handle errors to prevent cascade
        end
      end
    end

    -- Dispatch to global listeners
    for _, entry in ipairs(globalListeners) do
      pcall(entry.callback, table.unpack(signal, 1, signal.n))
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

--- Convenience: pull a named signal
function event.pullNamed(name, timeout)
  return event.pullFiltered(function(sig) return sig == name end, timeout)
end

-- Get listener counts (for debugging)
function event.stats()
  local count = 0
  for _, list in pairs(listeners) do
    count = count + #list
  end
  return {
    listeners = count,
    globalListeners = #globalListeners,
    timers = #timers,
  }
end

--- Push a custom signal into the OC event queue (wraps computer.pushSignal)
-- Used by the shell to emit tos_logout, tos_shutdown, etc.
function event.push(...)
  computer.pushSignal(...)
end

return event
