-- ╔══════════════════════════════════════╗
-- ║  TOS Chat Relay Service              ║
-- ║  Relay messages between peers        ║
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

  -- #SEC H20 — per-peer flood guard. Without this a TRUSTED peer can
  -- spew MSG packets and exhaust history + log budget for every machine
  -- on the network. We track a sliding window per source: > MAX_PER_WINDOW
  -- in WINDOW_SEC drops further messages from that peer silently.
  local rate = {}
  local WINDOW_SEC     = 5     -- sliding window length in seconds
  local MAX_PER_WINDOW = 20    -- packets per window before we drop
  local MAX_TEXT_LEN   = 512   -- ignore absurdly large bodies up front

  listenerID = net.on(protocol.TYPE.MSG, function(packet, remoteAddr)
    if not running then return end
    -- Rate-limit check (per remoteAddr).
    local now = computer.uptime()
    local entry = rate[remoteAddr]
    if not entry then
      -- #SEC L — bound the rate map: an attacker spoofing many source
      -- addresses would otherwise grow it without limit (memory leak over
      -- long uptimes). Evict the oldest-tracked peer past the cap.
      rate.__order = rate.__order or {}
      if #rate.__order >= 256 then
        local victim = table.remove(rate.__order, 1)
        if victim ~= nil then rate[victim] = nil end
      end
      rate.__order[#rate.__order + 1] = remoteAddr
      entry = { windowStart = now, count = 0 }
      rate[remoteAddr] = entry
    end
    if (now - entry.windowStart) > WINDOW_SEC then
      entry.windowStart = now
      entry.count = 0
    end
    entry.count = entry.count + 1
    if entry.count > MAX_PER_WINDOW then
      -- Don't even log — the log itself is a target for flooding.
      return
    end

    local text = ""
    if packet.payload then
      text = type(packet.payload) == "string" and packet.payload
        or (packet.payload.text or tostring(packet.payload))
    end
    if type(text) ~= "string" then text = tostring(text or "") end
    if #text > MAX_TEXT_LEN then text = text:sub(1, MAX_TEXT_LEN) end

    local hostname = "?"
    -- Try to resolve hostname from discovered peers
    local peer = net.findPeer(remoteAddr)
    if peer and peer.hostname then hostname = peer.hostname end

    recordMessage(hostname .. " (" .. remoteAddr:sub(1, 8) .. ")", text, now)

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
  user       = "_kernel_",
  getHistory = getHistory,
}
