-- share - Request or list shared files from a trusted peer
-- Usage: share <host> [path]
--   share <host>          List /public/ on the remote peer
--   share <host> <path>   Request a specific file

local args = {...}
if #args < 1 then
  print("Usage: share <host> [path]")
  print("  Request files from a trusted peer's /public/ directory.")
  return
end

local net = _G._TOS and _G._TOS.net
if not net then
  print("Network not available.")
  return
end

local target = args[1]
local path = args[2] or "/public/"

-- Resolve target
local peer = net.findPeer(target)
if not peer then
  print("Unknown host: " .. target)
  return
end

local protocol = net.getProtocol()
local computer = require("computer")

-- Send file request
local pkt = protocol.makePacket(protocol.TYPE.FILE_REQ, {
  path = path,
})
local ok, err = net.send(peer.addr, pkt)
if not ok then
  print("Send failed: " .. tostring(err))
  return
end

print("Requesting " .. path .. " from " .. (peer.hostname or peer.addr:sub(1, 8)) .. "...")

-- Wait for FILE_RES or FILE_DENY
local gotResponse = false

local resId = net.on(protocol.TYPE.FILE_RES, function(remoteAddr, respPkt)
  if remoteAddr == peer.addr then
    gotResponse = true
    if respPkt.payload then
      if respPkt.payload.listing then
        -- Directory listing
        print("Files in " .. path .. ":")
        for _, name in ipairs(respPkt.payload.listing) do
          print("  " .. name)
        end
      elseif respPkt.payload.data then
        -- File contents
        print("--- " .. path .. " ---")
        print(respPkt.payload.data)
        print("--- end ---")
      else
        print("(empty response)")
      end
    end
  end
end)

local denyId = net.on(protocol.TYPE.FILE_DENY, function(remoteAddr, respPkt)
  if remoteAddr == peer.addr then
    gotResponse = true
    local reason = respPkt.payload and respPkt.payload.reason or "Access denied"
    print("Denied: " .. reason)
  end
end)

local deadline = computer.uptime() + 10
while computer.uptime() < deadline and not gotResponse do
  if coroutine.isyieldable and coroutine.isyieldable() then
    coroutine.yield()
  else
    computer.pullSignal(0.5)
  end
end

net.off(protocol.TYPE.FILE_RES, resId)
net.off(protocol.TYPE.FILE_DENY, denyId)

if not gotResponse then
  print("Timed out — no response from " .. (peer.hostname or peer.addr:sub(1, 8)))
end
