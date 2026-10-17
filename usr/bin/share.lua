local q={...}if#q<1 then print("Usage: share <host> [path]")
print("  Request files from a trusted peer's /public/ directory.")return end;local l=_G._TOS and
_G._TOS.net;if not l then
print("Network not available.")return end;local r=q[1]local o=q[2]or"/public/"
local m=l.findPeer(r)
if not m then print("Unknown host: "..r)return end;local n=l.getProtocol()local p=false
local s={{type=n.TYPE.FILE_RES,id=l.onceFrom(n.TYPE.FILE_RES,m.addr,function(a)p=true
if
a.payload then
if a.payload.listing then print("Files in "..o..":")for c,b in
ipairs(a.payload.listing)do print("  "..b)end elseif a.payload.data then print("--- "..
o.." ---")print(a.payload.data)
print("--- end ---")else print("(empty response)")end end end)},{type=n.TYPE.FILE_DENY,id=l.onceFrom(n.TYPE.FILE_DENY,m.addr,function(a)
p=true
local b=a.payload and a.payload.reason or"Access denied"print("Denied: "..b)end)}}local t=n.makePacket(n.TYPE.FILE_REQ,{path=o})
local u,v=l.send(m.addr,t)if not u then l.offAll(s)
print("Send failed: "..tostring(v))return end
print("Requesting "..o.." from "..
(m.hostname or m.addr:sub(1,8)).."...")l.waitFor(function()return p end,10)l.offAll(s)if
not p then
print("Timed out — no response from ".. (m.hostname or m.addr:sub(1,8)))end