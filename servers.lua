-- servers - List discovered TOS servers on the network
-- Usage: servers
--
-- Shows all discovered peers with their device type, hostname,
-- trust level, and last-seen time.

local net = _G._TOS and _G._TOS.net
if not net then
  print("Network not available.")
  return
end

local computer = require("computer")
local peers = net.peers and net.peers() or {}

if #peers == 0 then
  print("No peers discovered yet.")
  print("Run 'net scan' to search the network.")
  return
end

print(string.format("%-10s %-8s %-6s %-5s %s",
  "Hostname", "Device", "Trust", "Seen", "Address"))
print(string.rep("-", 52))

local trustLabels = { [-1] = "BLK", [0] = "UNK", [1] = "KNW", [2] = "TRS" }
local now = computer.uptime()

for _, peer in ipairs(peers) do
  local age = now - (peer.lastSeen or 0)
  local ageStr
  if age < 60 then ageStr = math.floor(age) .. "s"
  elseif age < 3600 then ageStr = math.floor(age / 60) .. "m"
  else ageStr = math.floor(age / 3600) .. "h" end

  print(string.format("%-10s %-8s %-6s %-5s %s",
    (peer.hostname or "?"):sub(1, 10),
    (peer.device or "?"):sub(1, 8),
    trustLabels[peer.trust] or "?",
    ageStr,
    (peer.addr or "?"):sub(1, 12)))
end

print()
print(#peers .. " peer(s) found.")
