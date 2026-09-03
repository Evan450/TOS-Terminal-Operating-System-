-- TOS OpenOS Compatibility - event API
-- Wraps TOS kernel.event to provide the OpenOS event interface.
-- OpenOS programs use require("event") for event handling.

local kEvent = require("kernel.event")
local computer = require("computer")

local event = {}

-- Track callback -> { [signal] = id, ... } for event.ignore() support.
--
-- OpenOS identifies a listener by the (NAME, CALLBACK) PAIR, not by the
-- callback alone — lib/core/full_event.lua matches
-- `handler.key == name and handler.callback == callback` in both listen
-- and ignore. This map used to be keyed on the callback only, one entry
-- deep, which broke the ordinary case of one handler serving several
-- signals two ways at once:
--   event.listen("touch", f); event.listen("drag", f)
--     -> the second call saw f already present and returned false without
--        registering, so `drag` silently never fired;
--   event.ignore("touch", f)
--     -> removed whatever single signal f was mapped to, which could be a
--        different one entirely.
-- (test_compat_event.lua)
local callbackMap = {}
setmetatable(callbackMap, { __mode = "k" })  -- Weak keys: allow GC of callbacks

-- #SEC C5/C14 — signals that must never be visible to a sandboxed program.
-- A program with the compat event API previously could `event.listen` for
-- `modem_message` (see every inbound packet in plaintext), `key_down`
-- (keystroke-log every other seat), `clipboard` (sniff pastes), or any
-- of the internal `tos_*` lifecycle events (spoof login completion or
-- shutdown). They are intercepted here before reaching kernel.event.on
-- so the kernel layer can keep its low-level callers (rc.d, panels) on
-- the same API without losing the filter.
local SENSITIVE_SIGNALS = {
  modem_message      = true,
  key_down           = true,
  key_up             = true,
  clipboard          = true,
  tos_login_complete = true,
  tos_logout         = true,
  tos_shutdown       = true,
  tos_seat_changed   = true,
  tos_shell_exited   = true,
}

local function isSensitive(name)
  return type(name) == "string" and SENSITIVE_SIGNALS[name] == true
end

--- Pull a signal with optional timeout and filter.
-- OpenOS signature: event.pull([timeout: number], [name: string], ...) -> ...
-- If first arg is a number, it's timeout. If first arg is a string, it's filter name.
function event.pull(...)
  local args = table.pack(...)
  local timeout = math.huge
  local filterName = nil
  local argStart = 1

  if args.n >= 1 and type(args[1]) == "number" then
    timeout = args[1]
    argStart = 2
  end
  if args.n >= argStart and type(args[argStart]) == "string" then
    filterName = args[argStart]
  end

  if filterName then
    -- #SEC C5: a sandboxed program shouldn't be able to drain sensitive
    -- signals out of the event queue by pulling for them by name either.
    if isSensitive(filterName) then
      -- Block until the (non-arriving for this caller) signal would have
      -- fired or timeout, so callers get the same "no event" behaviour
      -- they'd get filtering against any other unmatched name. Drop the
      -- timeout to math.min(timeout, 0) for an immediate return — the
      -- caller is asking for something they're not entitled to.
      return nil
    end
    return kEvent.pullFiltered(function(sig)
      return sig == filterName
    end, timeout)
  else
    -- Unfiltered pull. #SEC M-2 — the old code returned the bare signal
    -- NAME for a sensitive signal (payload stripped). That still leaked
    -- WHICH sensitive signal fired and WHEN — a timing oracle for
    -- tos_login_complete / key_down — and returned instantly with no
    -- yield, so a program looping on pull() could spin the scheduler. We
    -- now DISCARD sensitive signals entirely and keep waiting within the
    -- caller's deadline, so the event stream looks (to this caller) as if
    -- the sensitive signals never happened. kEvent.pull blocks/yields per
    -- iteration, so there is no busy-loop.
    local deadline = (timeout == math.huge) and math.huge
      or (computer.uptime() + timeout)
    while true do
      local remaining = (deadline == math.huge) and math.huge
        or (deadline - computer.uptime())
      if remaining < 0 then return nil end
      local sig = table.pack(kEvent.pull(remaining))
      if not sig[1] then return nil end           -- timed out, nothing pulled
      if not isSensitive(sig[1]) then
        return table.unpack(sig, 1, sig.n)         -- normal signal: deliver
      end
      -- sensitive: drop it and continue waiting until the deadline.
    end
  end
end

--- Listen for a signal (persistent handler).
function event.listen(name, callback)
  -- #SEC C5: deny sandboxed code from subscribing to signals that would
  -- otherwise grant cross-process surveillance or boot-flow spoofing.
  if isSensitive(name) then return false, "signal '" .. tostring(name) .. "' is not available to user programs" end
  if type(name) ~= "string" or type(callback) ~= "function" then return false end
  -- Duplicate is a no-op only for the SAME signal (OpenOS behaviour); the
  -- same callback on another signal is a new, legitimate registration.
  local entries = callbackMap[callback]
  if entries and entries[name] then return false end
  local id = kEvent.on(name, callback, "compat:event")
  if not entries then entries = {}; callbackMap[callback] = entries end
  entries[name] = id
  return true
end

--- Remove a listener registered for (name, callback), matching OpenOS.
function event.ignore(name, callback)
  if type(name) ~= "string" or type(callback) ~= "function" then return false end
  local entries = callbackMap[callback]
  local id = entries and entries[name]
  if not id then return false end
  local removed = kEvent.off(name, id)
  entries[name] = nil
  if next(entries) == nil then callbackMap[callback] = nil end
  return removed or false
end

--- Register a one-shot listener.
function event.listenOnce(name, callback)
  -- #SEC C5: same denylist as event.listen.
  if isSensitive(name) then return false, "signal '" .. tostring(name) .. "' is not available to user programs" end
  kEvent.once(name, callback, "compat:event")
  return true
end

--- Register a timer (one-shot delayed callback).
-- @return number: Timer ID
function event.timer(interval, callback, times)
  times = times or 1
  if times == math.huge then
    -- Repeating
    return kEvent.interval(interval, callback, "compat:timer")
  else
    -- One-shot (or limited repeats)
    local count = 0
    local id
    id = kEvent.interval(interval, function()
      count = count + 1
      callback()
      if count >= times then
        kEvent.cancelTimer(id)
      end
    end, "compat:timer")
    return id
  end
end

--- Cancel a timer.
function event.cancel(id)
  return kEvent.cancelTimer(id)
end

--- Push an event into the queue.
function event.push(name, ...)
  -- #SEC C14: prevent sandboxed code from synthesizing kernel control
  -- signals (tos_login_complete, tos_shutdown, etc.). Permitting the push
  -- would let the kernel main loop honour an attacker-supplied token or
  -- shut the machine down at will. Pushing a regular signal still works.
  if isSensitive(name) then return false, "signal '" .. tostring(name) .. "' cannot be pushed by user programs" end
  kEvent.push(name, ...)
  return true
end

--- Get computer uptime
function event.uptime()
  return computer.uptime()
end

return event
