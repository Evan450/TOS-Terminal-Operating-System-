-- ╔══════════════════════════════════════╗
-- ║  TOS Discovery Daemon                ║
-- ║  Periodic network peer discovery     ║
-- ╚══════════════════════════════════════╝
-- Broadcasts a ping every `interval` seconds so other TOS nodes
-- on the LAN can find this machine. Also collects pong responses
-- to populate `net.peers()`.
--
-- Service table fields for rc.lua:
--   deps    = {}          (no dependencies, but needs net)
--   restart = true        (auto-restart if it crashes)
--   caps    = { net=true }

local INTERVAL = 120  -- seconds between discovery broadcasts

local running = false
local timerID = nil

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end
  local event = nil
  pcall(function() event = require("kernel.event") end)
  if not event then return end

  running = true

  -- Initial scan
  pcall(net.discover)

  -- Periodic broadcast
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
