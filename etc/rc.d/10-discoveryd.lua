local INTERVAL = 120

local running = false
local timerID = nil

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end
  local event = nil
  pcall(function() event = require("kernel.event") end)
  if not event then return end

  running = true

  pcall(net.discover)

  timerID = event.interval(INTERVAL, function()
    if not running then return end
    pcall(net.discover)
  end, "discoveryd")
end

local function stop()
  running = false
  if timerID then
    local ok, event = pcall(require, "kernel.event")
    if ok and event.cancelTimer then
      event.cancelTimer(timerID)
    end
    timerID = nil
  end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { net = true },
  user    = "_kernel_",
}
