local computer = require("computer")

local event = {}

local listeners = {}

local timers = {}
local timerNextID = 1

local timerErrPending, timerErrTotal = 0, 0
local timerErrLast, timerErrSource = nil, nil

local function noteTimerError(t, err)
  timerErrPending = timerErrPending + 1
  timerErrTotal = timerErrTotal + 1
  timerErrLast = tostring(err)
  timerErrSource = t and t.source or "unknown"
end

function event.timerErrors()
  return timerErrTotal, timerErrLast, timerErrSource
end

local procModCache = nil
local function getProc()
  if not procModCache then
    local okP, m = pcall(require, "kernel.process")
    if okP then procModCache = m end
  end
  return procModCache
end

function event.on(signal, callback, source)
  if not listeners[signal] then
    listeners[signal] = {}
  end

  local regPid = nil
  local regGen = nil
  local procMod = getProc()
  if procMod and procMod.current then
    local cur = procMod.current()
    if cur then
      regPid = cur.pid
      regGen = procMod.genOf and procMod.genOf(cur.pid) or nil
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

function event.once(signal, callback, source)
  local id
  id = event.on(signal, function(...)
    event.off(signal, id)
    return callback(...)
  end, source)
  return id
end

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

function event.removeSource(source)
  for signal, list in pairs(listeners) do
    for i = #list, 1, -1 do
      if list[i].source == source then
        table.remove(list, i)
      end
    end
  end
end

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

function event.timer(delay, callback, source)
  local id = timerNextID
  timerNextID = timerNextID + 1
  local regPid, regGen = captureRegPid()
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

function event.interval(delay, callback, source)
  local id = timerNextID
  timerNextID = timerNextID + 1
  local regPid, regGen = captureRegPid()
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

function event.cancelTimer(id)
  for i, t in ipairs(timers) do
    if t.id == id then
      table.remove(timers, i)
      return true
    end
  end
  return false
end

function event.pull(timeout)
  timeout = timeout or 0.5

  if timerErrPending > 0 then
    local lg = package.loaded and package.loaded["kernel.log"]
    if lg and lg.warn then
      pcall(lg.warn, "event", "timer callback errors: +" .. timerErrPending
        .. " (total " .. timerErrTotal .. "), last ["
        .. tostring(timerErrSource) .. "]: " .. tostring(timerErrLast))
      timerErrPending = 0
    end
  end

  local now = computer.uptime()
  local nextDeadline = now + timeout

  local procMod = getProc()
  for i = #timers, 1, -1 do
    local t = timers[i]
    if now >= t.deadline then

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

  local waitTime = math.max(0, math.min(timeout, nextDeadline - computer.uptime()))

  local signal = table.pack(computer.pullSignal(waitTime))

  if signal[1] then

    local stype = signal[1]

    local function dispatchOne(entry, ...)
      if procMod and procMod.withListener and entry.regPid then

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

function event.push(...)
  computer.pushSignal(...)
end

return event
