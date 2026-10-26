local r,s,t,q="Device","Failed: ","status","unknown"local o=require("computer")
local m={}
local function n(a)local b=a.U;if b and a.st then local c=b.getSession(a.st)
if c then return c.user,c.tier end end;return q,0 end
function m.hostname(c,b)local a=b.K.getConfig()if not a then b.o("No config",0xFF0000)
return end
if c[1]then local g,f=n(b)if(f or 0)<2 then
b.o("Setting the hostname requires admin (it is this machine's name on the network).",0xFF0000)return end;local d=c[1]if#d>
32 or d:find("%c")then
b.o("Hostname must be 1-32 printable characters.",0xFF0000)return end
a.set("hostname",d)a.save()local e=b.K.getNet and b.K.getNet()if
e and e.setHostname then e.setHostname(d)end end
b.o("Device: "..a.deviceType()..
" | Host: ".. (a.get("hostname")or"?"))end
function m.config(c,b)local a=b.K.getConfig()
if not a then b.o("No config",0xFF0000)return end;for d,e in pairs(a.getAll())do
b.o(" "..d.." = "..tostring(e),0xC0C0C0)end end
function m.battery(c,b)local a=b.K.getPower()if not a then b.o("N/A")return end
local d=a.statusString()
if d then b.o(d)else b.o("AC power (no battery on this device)")end end;local p=nil
local function k(a)
local b=_G._TOS and _G._TOS.net and _G._TOS.net.aliases;if b and b.format then return b.format(a)end;if type(a)~="string"then
return"?"end;return a:sub(1,8).."..."end
local function l(a)if type(a)~="string"or a==""then return a end
local b=tonumber(a)if b and p and p[b]then return p[b].addr end;local c=
_G._TOS and _G._TOS.net and _G._TOS.net.aliases
if c and
c.resolve then local d=c.resolve(a)if d then return d end end;return a end
function m.net(c,b)local a=b.K.getNet()
if not a then b.o("No network",0xFF0000)return end
if not c[1]then b.o("net <subcommand>",0xFFFF00)
b.o("  status                       Show network state",0xAAAAAA)
b.o("  discover (or scan)           Broadcast ping",0xAAAAAA)
b.o("  peers                        List discovered peers",0xAAAAAA)
b.o("  servers                      Discovered hosts w/ device + last-seen",0xAAAAAA)
b.o("  trust <peer> [full]          Elevate peer to KNOWN / TRUSTED",0xAAAAAA)
b.o("  trust gen <peer>             Generate shared secret (admin)",0xAAAAAA)
b.o("  trust rekey <peer>           Accept a reinstalled peer's key (admin)",0xAAAAAA)
b.o("  trust setSecret <peer> <hex> Mirror a secret from peer (admin)",0xAAAAAA)
b.o("  trust showSecret <peer>      Show my secret with peer (admin)",0xAAAAAA)
b.o("  block <peer>                 Block a peer",0xAAAAAA)
b.o("  revoke <peer>                Drop peer back to UNKNOWN",0xAAAAAA)
b.o("  forget <peer>                Remove peer record entirely",0xAAAAAA)
b.o("  request <peer>               Ask a peer's admin for trust",0xAAAAAA)
b.o("  requests                     Show pending trust requests",0xAAAAAA)
b.o("  send <peer> <msg>            Send chat message",0xAAAAAA)
b.o("  alias add <name> <peer>      Name a peer (admin)",0xAAAAAA)
b.o("  alias rm  <name>             Remove an alias (admin)",0xAAAAAA)
b.o("  alias list                   Show all aliases",0xAAAAAA)
b.o("  alias show <peer>            Show the alias for a peer",0xAAAAAA)
b.o("  pair start                   Open pairing window (admin)",0xAAAAAA)
b.o("  pair <peer> <code>           Pair with peer using code (admin)",0xAAAAAA)
b.o(" <peer> = alias, full address, prefix, or scan-index (1..N)",0x888888)return end;local d=c[1]
if d=="servers"then local e=a.peers and a.peers()or{}if
#e==0 then b.o("No peers discovered yet.",0xAAAAAA)
b.o("Run 'net scan' to search the network.",0x888888)return end
b.o(string.format("%-10s %-8s %-6s %-5s %s","Hostname",r,"Trust","Seen","Address"),0xAAAAAA)local f={[-1]="BLK",[0]="UNK",[1]="KNW",[2]="TRS"}
local g=o.uptime()
for i,h in ipairs(e)do local j=g- (h.lastSeen or 0)local u
if j<60 then u=
math.floor(j).."s"elseif j<3600 then u=math.floor(j/60).."m"else u=math.floor(
j/3600).."h"end
b.o(string.format("%-10s %-8s %-6s %-5s %s",(h.hostname or"?"):sub(1,10),(
h.device or"?"):sub(1,8),f[h.trust]or"?",u,(h.addr or"?"):sub(1,12)))end;b.o(#e.." peer(s) found.",0x888888)elseif d==t then
local e=a.status()
b.o("Host: ".. (e.hostname or"?"))
b.o("Addr: ".. (e.address or"?"))
local g=a.modemCount and a.modemCount()or(e.hasModem and 1 or 0)
b.o("Modem: "..
(e.hasModem and"Yes"or"No").. (g>1 and
(" (x"..g..")")or"")..
(e.hasTunnel and" + Tunnel"or""))
b.o("Encrypted: ".. (e.encrypted and"Yes"or"No"))
b.o("Port: "..tostring(e.listenPort or"?"))if e.portOwner then
b.o("  (registered to "..
e.portOwner.." -- TOS traffic shares that network; TOS's own is 42)",0xFFFF00)end
local f=e.peers or{}
local h=
(f.unknown or 0)+ (f.known or 0)+ (f.trusted or 0)+ (f.blocked or 0)
b.o("Peers: "..h..
" (trusted:".. (f.trusted or 0)..
" known:".. (f.known or 0).." blocked:"..
(f.blocked or 0)..")")elseif d=="discover"or d=="scan"then b.o("Scanning...",0xFFFF00)
if
a.scan then local e=a.scan(3)
table.sort(e,function(f,g)return
tostring(f.addr or"")<tostring(g.addr or"")end)p=e
if#e>0 then
b.o(string.format(" %-3s %-20s %-4s %-8s %s","#","Peer","Trst",r,"Host"),0xAAAAAA)
for g,f in ipairs(e)do local h=f.trust or 0;local i=
({"BLK","UNK","KNW","TRS"})[h+2]or"?"
local j=
(h==2 and 0x55FF55)or(h==1 and
0xFFFF55)or(h==-1 and 0xFF5555)or 0xAAAAAA
b.o(string.format(" %2d. %-20s %-4s %-8s %s",g,k(f.addr),i,f.device or"?",f.hostname or""),j)end
b.o("Tip: 'net trust 1' references the first peer above.",0x888888)end;b.o(#e.." peer(s) responded.",0x00FF00)else
a.discover()b.o("Discovery broadcast sent.",0x00FF00)end elseif d=="peers"or d=="list"then
local e=a.peers and a.peers()or{}
if#e>0 then p=e
b.o(string.format(" %-3s %-20s %-4s %-8s %s","#","Peer","Trst",r,"Host"),0xAAAAAA)
for g,f in ipairs(e)do local h=f.trust or 0;local j=
({"BLK","UNK","KNW","TRS"})[h+2]or"?"
local u=
(h==2 and 0x55FF55)or(h==1 and
0xFFFF55)or(h==-1 and 0xFF5555)or 0xAAAAAA
b.o(string.format(" %2d. %-20s %-4s %-8s %s",g,k(f.addr),j,f.device or"?",f.hostname or""),u)
local i=a.getTrust and a.getTrust().getPeer(f.addr)if i and i.dhKeyChanged then
b.o("     new key since our secret was made: 'net trust rekey "..g.."'",0xFF5555)end end else local f=a.getTrust()
for h,g in ipairs(f.listPeers())do
b.o(string.format(" %-20s T%d %s%s",k(g.address),g.level,
g.hostname or"",g.keyChanged and"  (new key: net trust rekey)"or""))end end;if#e==0 then
b.o("  No peers discovered. Run 'net scan' first.",0xAAAAAA)end elseif d=="trust"then local f=a.getTrust()
local g,h=n(b)local e=c[2]
if e=="gen"or e=="generate"then local i=l(c[3])if not i then
b.o("Usage: net trust gen <peer>",0xFFFF00)return end;local j,u=f.generateSecret(g,i,h)
if j then
b.o(
"Generated shared secret for "..k(i).." ("..#j.." bytes)",0x00FF00)
b.o("Easier: run 'net pair start' on the peer and 'net pair "..k(i).." <code>' here.",0xAAAAAA)
b.o("Or copy: run `net trust setSecret <our-addr> <hex>` on the peer.",0xAAAAAA)local v={}
for w=1,#j do v[w]=string.format("%02x",j:byte(w))end
b.o("Secret (hex): "..table.concat(v),0xFFFF55)else b.o(s..tostring(u or q),0xFF0000)end elseif e=="setSecret"or e=="secret"then local u=l(c[3])local i=c[4]
if not u then
b.o("Usage: net trust setSecret <peer> <hex-string|->",0xFFFF00)
b.o("       Use - or empty to clear the secret.",0xAAAAAA)return end;local j
if not i or i==""or i=="-"then j=nil else if
#i%2 ~=0 or i:match("[^%x]")then
b.o("Bad hex string (need pairs of 0-9 a-f).",0xFF0000)return end;local x={}
for y=1,#i,2 do x[#x+1]=string.char(tonumber(i:sub(y,
y+1),16))end;j=table.concat(x)end;local v,w=f.setSecret(g,u,j,h)
if v then
b.o(j and"Secret set."or"Secret cleared.",0x00FF00)else b.o(s..tostring(w or q),0xFF0000)end elseif e=="rekey"then local i=l(c[3])if not i then
b.o("Usage: net trust rekey <peer>",0xFFFF00)return end;local j,u=f.rekey(g,i,h)
if j then
b.o(
"New shared secret derived from "..k(i).."'s current key.",0x00FF00)else b.o(s..tostring(u or q),0xFF0000)end elseif e=="showSecret"then local j=l(c[3])if not j then
b.o("Usage: net trust showSecret <peer>",0xFFFF00)return end;local i,v=f.getSecret(g,j,h)
if not i then b.o(
v or"no secret set",0xAAAAAA)return end;local u={}
for w=1,#i do u[w]=string.format("%02x",i:byte(w))end;b.o(table.concat(u),0xFFFF55)elseif e then local i=l(e)local j,u
if
c[3]=="full"then j,u=f.trustFull(g,i,h)else j,u=f.trustKnown(g,i,h)end
if j then
b.o("Trust updated for "..k(i)..".",0x00FF00)
if c[3]=="full"then
b.o("A shared secret is agreed by itself once the peer trusts this machine too.",0x888888)
b.o("No secret after that? 'net pair start' on the peer + 'net pair "..k(i).." <code>' here.",0x888888)end else b.o(u or"Trust update failed",0xFF0000)end else
b.o("Usage: net trust <gen|rekey|setSecret|showSecret|<addr> [full]>",0xFFFF00)end elseif d=="block"and c[2]then local f,g=n(b)local e=l(c[2])
local h,i=a.getTrust().block(f,e,g)
if h then b.o("Blocked "..k(e)..".",0x00FF00)else b.o(i or
"Block failed",0xFF0000)end elseif d=="revoke"and c[2]then local f,g=n(b)local e=l(c[2])
local h,i=a.getTrust().revoke(f,e,g)
if h then
b.o("Trust revoked for "..k(e).." (now UNKNOWN).",0x00FF00)else b.o(i or"Revoke failed",0xFF0000)end elseif d=="forget"and c[2]then local f,g=n(b)local e=l(c[2])
local h,i=a.getTrust().forget(f,e,g)
if h then
b.o("Forgot peer "..k(e).." (record removed).",0x00FF00)else b.o(i or"Forget failed",0xFF0000)end elseif d=="request"and c[2]then local e=l(c[2])local f,g=a.requestTrust(e)
if f then
b.o(
"Trust request sent to "..k(e)..".",0x00FF00)
b.o("Their admin sees it under 'net requests'.",0x888888)else b.o(g or"Request failed",0xFF0000)end elseif d=="requests"then
local f=a.getTrust().getPendingRequests()local e=0;for g,h in pairs(f)do e=e+1
b.o(string.format("  %-38s %s",k(g),h.hostname or"(no hostname)"),0xFFFF55)end;if e==0 then
b.o("No pending trust requests.",0xAAAAAA)else
b.o("Approve: net trust <peer> [full]   Refuse: net block <peer>",0x888888)end elseif
d=="send"and c[2]and c[3]then local e=l(c[2])
local f,g=a.sendMessage(e,table.concat(c," ",3))if f then b.o("Sent.",0x00FF00)else
b.o("Send failed: "..tostring(g or q),0xFF0000)end elseif d=="alias"then local f=
_G._TOS and _G._TOS.net and _G._TOS.net.aliases;if not f then
b.o("aliases module unavailable",0xFF0000)return end;local e=c[2]
if e=="add"or e=="set"then
local g=c[3]local h=l(c[4])if not g or not h then
b.o("Usage: net alias add <name> <peer>",0xFFFF00)return end;local i,j=f.set(g,h)
if i then
b.o(string.format("alias %s -> %s",g,k(h)),0x00FF00)else b.o(j or"alias failed",0xFF0000)end elseif e=="rm"or e=="remove"or e=="del"then local g=c[3]if not g then
b.o("Usage: net alias rm <name>",0xFFFF00)return end;local h,i=f.remove(g)
if h then
b.o("removed.",0x00FF00)else b.o(i or"remove failed",0xFF0000)end elseif e=="list"or e==nil then local g=f.list()if#g==0 then
b.o("No aliases defined.",0xAAAAAA)return end
b.o(string.format(" %-16s  %s","Alias","Address"),0xAAAAAA)for i,h in ipairs(g)do
b.o(string.format(" %-16s  %s",h.alias,h.address))end elseif e=="show"then local g=l(c[3])if not g then
b.o("Usage: net alias show <peer>",0xFFFF00)return end;local h=f.aliasOf(g)if h then
b.o(h.." -> "..g,0x00FF00)else
b.o("No alias for "..g:sub(1,12).."...",0xAAAAAA)end else
b.o("Usage: net alias <add|rm|list|show>",0xFFFF00)end elseif d=="pair"then
local f=a.getChatPair and a.getChatPair()or nil
if not f then b.o("chat-pair unavailable",0xFF0000)return end;local e=c[2]
if e~=t then local h,g=n(b)if(g or 0)<2 then
b.o("net pair requires admin",0xFF0000)return end end
if e=="start"then local g,h=f.startWindow()if not g then
b.o("could not open pairing window: "..tostring(h),0xFF0000)return end
local i=math.max(0,math.floor(h-o.uptime()))
b.o("Pairing window open for "..i.."s.",0xFFFF55)b.o("Type this on the OTHER peer:",0xAAAAAA)b.o(
"  net pair <our-addr-or-alias> "..g,0xFFFF00)
b.o("Pre-condition: both peers must already be TRUSTED on both sides.",0x888888)elseif e==t then local g=f.windowInfo()
if g then
b.o(string.format("Window open: %ds left, %d peers paired",math.floor(g.expires_in),g.paired),0xFFFF55)else b.o("No pairing window open.",0xAAAAAA)end elseif e=="close"or e=="cancel"then f.closeWindow()
b.o("Pairing window closed.",0x00FF00)elseif e and c[3]then local g=l(e)local h=c[3]
b.o("Pairing with "..k(g).."...",0xFFFF55)local i,j=f.connect(g,h,10)if i then
b.o("Paired. Shared secret installed on both sides.",0x00FF00)else
b.o("Pair failed: "..tostring(j),0xFF0000)end else
b.o("Usage: net pair start | net pair <peer> <code> | net pair status",0xFFFF00)end else b.o("Unknown: net "..d,0xFF0000)end end
function m.ping(c,b)local a=b.K.getNet()
if not a then b.o("No network",0xFF0000)return end;if not c[1]then a.discover()
b.o("Discovery ping broadcast. 'net peers' lists who answered.",0x00FF00)return end;local d=a.getProtocol and
a.getProtocol()if not d then
b.o("Network protocol unavailable",0xFF0000)return end;local e=l(c[1])
local g,h=false,o.uptime()
local f=a.onceFrom and a.onceFrom(d.TYPE.PONG,e,function()g=true end)local i,j=a.send(e,d.ping())if not i then
if f then a.off(d.TYPE.PONG,f)end
b.o("Ping failed: "..tostring(j or"send error"),0xFF0000)return end;if not f then
b.o("Ping sent.",0x00FF00)return end
a.waitFor(function()return g end,3)a.off(d.TYPE.PONG,f)
if g then
b.o(string.format("Reply from %s in %d ms.",k(e),math.floor((
o.uptime()-h)*1000+0.5)),0x00FF00)else
b.o("No reply from "..k(e).." within 3s.",0xFFFF00)end end
function m.audio(c,b)local a=_G._TOS and _G._TOS.audio;if not a then
b.o("Audio module not available.",0xFF0000)return end;local d=c[1]
if not d then
b.o("Audio: ".. (
a.isEnabled()and"ON"or"OFF").."  Volume: "..
string.format("%.0f%%",a.getVolume()*100),0xFFFF00)
b.o("  audio on|off         Enable/disable audio",0xAAAAAA)
b.o("  audio volume <0-100> Set volume level",0xAAAAAA)
b.o("  audio test           Play all beep codes",0xAAAAAA)return end
if d=="on"then a.setEnabled(true)local e=b.K.getConfig()if e then
e.set("audio",true)e.save()end;a.success()
b.o("Audio enabled.",0x00FF00)elseif d=="off"then a.setEnabled(false)local e=b.K.getConfig()if e then
e.set("audio",false)e.save()end
b.o("Audio disabled.",0xAAAAAA)elseif d=="volume"or d=="vol"then local e=tonumber(c[2])if not e then
b.o("Usage: audio volume <0-100>",0xAAAAAA)return end
e=math.max(0,math.min(100,e))a.setVolume(e/100)local f=b.K.getConfig()if f then
f.set("audioVolume",e/100)f.save()end;a.success()
b.o("Volume: "..string.format("%.0f%%",
a.getVolume()*100),0x00FF00)elseif d=="test"then local g,f=pcall(require,"kernel.process")
local function e(h)if
g and f and f.sleep then f.sleep(h)else o.pullSignal(h)end end;b.o("Testing beep codes...",0xFFFF00)
b.o("  success (1 beep):",0xAAAAAA)a.success()e(0.3)
b.o("  confirm (2 ascending):",0xAAAAAA)a.confirm()e(0.3)
b.o("  warning (2 beeps):",0xAAAAAA)a.warning()e(0.3)
b.o("  error (1 long low):",0xAAAAAA)a.error()e(0.3)b.o("  critical (3 low):",0xAAAAAA)
a.critical()e(0.3)b.o("  notify (1 quick high):",0xAAAAAA)
a.notify()e(0.3)b.o("  chat (2-tone chime):",0xAAAAAA)
a.chat()e(0.3)b.o("  shutdown (2 descending):",0xAAAAAA)
a.shutdown()e(0.3)
b.o("  boot complete (3 ascending):",0xAAAAAA)a.bootComplete()e(0.3)
b.o("Test complete.",0x00FF00)else b.o("Unknown: audio "..d,0xFF0000)
b.o("Usage: audio [on|off|volume|test]",0xAAAAAA)end end;return m