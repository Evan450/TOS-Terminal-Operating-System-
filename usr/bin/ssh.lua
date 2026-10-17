local o={...}if#o<2 then print("Usage: ssh <host> <command...>")
print("  host: hostname or address prefix of a trusted peer")return end;local l=_G._TOS and
_G._TOS.net;if not l then
print("Network not available.")return end;local q=o[1]
local r=table.concat(o," ",2)local m=l.findPeer(q)if not m then print("Unknown host: "..q)
print("Run 'net scan' to discover peers, then 'net trust <addr>' to trust them.")return end
local n=l.getProtocol()local p=false
local s={{type=n.TYPE.REMOTE_RES,id=l.onceFrom(n.TYPE.REMOTE_RES,m.addr,function(a)p=true
if a and a.payload then if a.payload.output then
print(a.payload.output)end;if a.payload.error then
print("Error: "..a.payload.error)end else print("(empty response)")end end)}}local t=n.makePacket(n.TYPE.REMOTE_EXEC,{cmd=r})
local u,v=l.send(m.addr,t)if not u then l.offAll(s)
print("Send failed: "..tostring(v))return end
print("Sent to "..
(m.hostname or m.addr:sub(1,8))..": "..r)print("Waiting for response...")
l.waitFor(function()return p end,10)l.offAll(s)if not p then
print("Timed out — no response from "..
(m.hostname or m.addr:sub(1,8)))end