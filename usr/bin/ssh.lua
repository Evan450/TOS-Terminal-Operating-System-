-- ssh - Remote command execution on a trusted TOS peer
-- Usage: ssh <host> <command...>
--
-- Sends a REMOTE_EXEC packet to the specified host (hostname or
-- address prefix) and waits for the REMOTE_RES response.
-- The peer must be at TRUSTED level.

local args = {...}
if #args < 2 then
  print("Usage: ssh <host> <command...>")
  print("  host: hostname or address prefix of a trusted peer")
  return
end

local net = _G._TOS and _G._TOS.net
if not net then
  print("Network not available.")
  return
end

local target = args[1]
local cmd = table.concat(args, " ", 2)

-- Resolve target to address
local peer = net.findPeer(target)
if not peer then
  print("Unknown host: " .. target)
  print("Run 'net scan' to discover peers, then 'net trust <addr>' to trust them.")
  return
end

local protocol = net.getProtocol()

-- Register listener BEFORE sending so a fast peer can't reply before
-- we're listening. net.onceFrom does the peer-address filter and
-- de-duplicates duplicate / late responses for us.
local gotResponse = false
local listeners = {
  { type = protocol.TYPE.REMOTE_RES,
    id   = net.onceFrom(protocol.TYPE.REMOTE_RES, peer.addr, function(respPkt)
      gotResponse = true
      if respPkt and respPkt.payload then
        if respPkt.payload.output then print(respPkt.payload.output) end
        if respPkt.payload.error  then print("Error: " .. respPkt.payload.error) end
      else
        print("(empty response)")
      end
    end) },
}

local pkt = protocol.makePacket(protocol.TYPE.REMOTE_EXEC, { cmd = cmd })
local ok, err = net.send(peer.addr, pkt)
if not ok then
  net.offAll(listeners)
  print("Send failed: " .. tostring(err))
  return
end

print("Sent to " .. (peer.hostname or peer.addr:sub(1, 8)) .. ": " .. cmd)
print("Waiting for response...")

net.waitFor(function() return gotResponse end, 10)
net.offAll(listeners)

if not gotResponse then
  print("Timed out — no response from " .. (peer.hostname or peer.addr:sub(1, 8)))
end
