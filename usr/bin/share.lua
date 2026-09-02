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

local peer = net.findPeer(target)
if not peer then
  print("Unknown host: " .. target)
  return
end

local protocol = net.getProtocol()

local gotResponse = false
local listeners = {
  { type = protocol.TYPE.FILE_RES,
    id   = net.onceFrom(protocol.TYPE.FILE_RES, peer.addr, function(respPkt)
      gotResponse = true
      if respPkt.payload then
        if respPkt.payload.listing then
          print("Files in " .. path .. ":")
          for _, name in ipairs(respPkt.payload.listing) do print("  " .. name) end
        elseif respPkt.payload.data then
          print("--- " .. path .. " ---")
          print(respPkt.payload.data)
          print("--- end ---")
        else
          print("(empty response)")
        end
      end
    end) },
  { type = protocol.TYPE.FILE_DENY,
    id   = net.onceFrom(protocol.TYPE.FILE_DENY, peer.addr, function(respPkt)
      gotResponse = true
      local reason = respPkt.payload and respPkt.payload.reason or "Access denied"
      print("Denied: " .. reason)
    end) },
}

local pkt = protocol.makePacket(protocol.TYPE.FILE_REQ, { path = path })
local ok, err = net.send(peer.addr, pkt)
if not ok then
  net.offAll(listeners)
  print("Send failed: " .. tostring(err))
  return
end

print("Requesting " .. path .. " from " .. (peer.hostname or peer.addr:sub(1, 8)) .. "...")

net.waitFor(function() return gotResponse end, 10)
net.offAll(listeners)

if not gotResponse then
  print("Timed out — no response from " .. (peer.hostname or peer.addr:sub(1, 8)))
end
