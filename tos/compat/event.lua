local kEvent = require("kernel.event")
local computer = require("computer")

local event = {}

local callbackMap = {}
setmetatable(callbackMap, { __mode = "k" })

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

    if isSensitive(filterName) then

      return nil
    end
    return kEvent.pullFiltered(function(sig)
      return sig == filterName
    end, timeout)
  else

    local deadline = (timeout == math.huge) and math.huge
      or (computer.uptime() + timeout)
    while true do
      local remaining = (deadline == math.huge) and math.huge
        or (deadline - computer.uptime())
      if remaining < 0 then return nil end
      local sig = table.pack(kEvent.pull(remaining))
      if not sig[1] then return nil end
      if not isSensitive(sig[1]) then
        return table.unpack(sig, 1, sig.n)
      end

    end
  end
end

function event.listen(name, callback)

  if isSensitive(name) then return false, "signal '" .. tostring(name) .. "' is not available to user programs" end
  if type(name) ~= "string" or type(callback) ~= "function" then return false end

  local entries = callbackMap[callback]
  if entries and entries[name] then return false end
  local id = kEvent.on(name, callback, "compat:event")
  if not entries then entries = {}; callbackMap[callback] = entries end
  entries[name] = id
  return true
end

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

function event.listenOnce(name, callback)

  if isSensitive(name) then return false, "signal '" .. tostring(name) .. "' is not available to user programs" end
  kEvent.once(name, callback, "compat:event")
  return true
end

function event.timer(interval, callback, times)
  times = times or 1
  if times == math.huge then

    return kEvent.interval(interval, callback, "compat:timer")
  else

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

function event.cancel(id)
  return kEvent.cancelTimer(id)
end

function event.push(name, ...)

  if isSensitive(name) then return false, "signal '" .. tostring(name) .. "' cannot be pushed by user programs" end
  kEvent.push(name, ...)
  return true
end

function event.uptime()
  return computer.uptime()
end

return event
