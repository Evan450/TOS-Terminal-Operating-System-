-- ╔══════════════════════════════════════╗
-- ║  TOS Chat Relay Service             ║
-- ║  Relay messages between peers       ║
-- ╚══════════════════════════════════════╝
-- Listens for MSG packets and:
--   1. Displays them via the kernel log (visible in `log` command)
--   2. Optionally relays to other TRUSTED peers (mesh mode)
--
-- Chat history is kept in a ring buffer for the `chat` command.

local running = false
local listenerID = nil
local HISTORY_SIZE = 64
local history = {}
local histHead = 1
local histCount = 0

local function recordMessage(from, text, timestamp)
  history[histHead] = {
    from = from,
    text = text,
    time = timestamp,
  }
  histHead = (histHead % HISTORY_SIZE) + 1
  if histCount < HISTORY_SIZE then histCount = histCount + 1 end
end

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  running = true

  local protocol = net.getProtocol()
  local computer = require("computer")

  listenerID = net.on(protocol.TYPE.MSG, function(remoteAddr, packet)
    if not running then return end
    local text = ""
    if packet.payload then
      text = type(packet.payload) == "string" and packet.payload
        or (packet.payload.text or tostring(packet.payload))
    end
    local hostname = "?"
    -- Try to resolve hostname from discovered peers
    local peer = net.findPeer(remoteAddr)
    if peer and peer.hostname then hostname = peer.hostname end

    recordMessage(hostname .. " (" .. remoteAddr:sub(1, 8) .. ")", text, computer.uptime())

    if _G._TOS and _G._TOS.log then
      _G._TOS.log("chat", "[" .. hostname .. "] " .. text)
    end
  end)
end

local function stop()
  running = false
  if listenerID then
    local net = _G._TOS and _G._TOS.net
    if net then
      local protocol = net.getProtocol()
      net.off(protocol.TYPE.MSG, listenerID)
    end
    listenerID = nil
  end
end

-- Expose history for the chat command
local function getHistory()
  if histCount == 0 then return {} end
  local result = {}
  local startIdx = histCount < HISTORY_SIZE and 1 or histHead
  for i = 0, histCount - 1 do
    local idx = ((startIdx - 1 + i) % HISTORY_SIZE) + 1
    if history[idx] then
      result[#result + 1] = history[idx]
    end
  end
  return result
end

return {
  start      = start,
  stop       = stop,
  deps       = {},
  restart    = true,
  caps       = { net = true },
  getHistory = getHistory,
}
