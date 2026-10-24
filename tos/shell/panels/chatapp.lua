local z="No such group: @"local r=require("computer")
local u=require("shell.panels.ui")local s=require("shell.panels.tabs")
local q=require("shell.chat")local p={}local v=128;function p.label(a)
if(a or 0)>0 then return"Chat("..a..")"end;return"Chat"end
function p.addMessage(a,b,c)local d=a.messages
d[#d+1]={text=b,color=c,time=
r.uptime and r.uptime()or 0}
if#d>v then local e={}for f=#d-v+1,#d do e[#e+1]=d[f]end;a.messages=e end end;local function w(a)a=math.floor(a or 0)
return string.format("%02d:%02d:%02d",math.floor(a/3600),math.floor((
a%3600)/60),a%60)end
local function t(a)local b={}
for d,c in
ipairs((a and
a.listPeers and a.listPeers())or{})do if(c.level or 0)>=
((a.LEVEL and a.LEVEL.TRUSTED)or 2)then b[#b+1]=c end end;return b end
local function x()local a,b=pcall(require,"kernel.fs")
local c,d=pcall(require,"kernel.serialize")if a and c then return b,d end end;local function y()local a,b=x()return q.loadGroups(a,b)end;local function A(a)local b,c=x()if
not b then return false,"filesystem unavailable"end;return
q.saveGroups(b,c,a)end
function p.open(a)
local g=s.find(a,"chat")if g then local i=a.tabs[g]a.activeTab=g;return i end
local b=s.create(a,"chat","Chat",{messages={},input="",unread=0,scroll=0,live=true,interval=0.3})local d=a.T;local c=a.NM;if not c then
p.addMessage(b,"Chat unavailable: no network module.",d.error)return b end
p.addMessage(b,"Chat started. Send messages to TRUSTED peers.",d.title)
p.addMessage(b,"  peer:message   to one peer (addr prefix or hostname)",d.dim)
p.addMessage(b,"  message        broadcast to all trusted peers",d.dim)
p.addMessage(b,"  /who  /mail peer text  /clear  /help   ^Q closes the tab",d.dim)p.addMessage(b,"",d.dim)
local h=t(c.getTrust and c.getTrust())for j,i in ipairs(h)do
p.addMessage(b,"  "..tostring(i.address):sub(1,8).."  "..
(i.hostname or"?"),d.highlight)end;if#h==0 then
p.addMessage(b,"  (no trusted peers)",d.warning)end
local f=c.getProtocol and c.getProtocol()local e=c.getTrust and c.getTrust()
if f and e and c.on then
b._listenerId=c.on(f.TYPE.MSG,function(j,i)
local m=(
e.getLevel and e.getLevel(i))or 0;if m<e.LEVEL.TRUSTED then return end;local k=j.payload or{}
local n=
type(k.text)=="string"and k.text or""local l=e.getPeer and e.getPeer(i)local o=(l and l.hostname)or
tostring(i):sub(1,8)
p.addMessage(b,"["..o.."] "..n,a.T.border)b._dirty=true
if a.tabs[a.activeTab]~=b then
b.unread=(b.unread or 0)+1;b.label=p.label(b.unread)end;if _G._TOS and _G._TOS.audio then
pcall(_G._TOS.audio.chat)end;if c.send and f.makePacket then
pcall(function()
c.send(i,f.makePacket(f.TYPE.MSG_ACK,{ref=j.seq},{to=i}))end)end end)end;return b end
function p.onClose(b,a)local c=b.NM
if
a._listenerId and c and c.off and c.getProtocol then local d=c.getProtocol()if d then
pcall(c.off,d.TYPE.MSG,a._listenerId)end;a._listenerId=nil end
if a._ackListenerId and c and c.off and c.getProtocol then
local d=c.getProtocol()
if d then pcall(c.off,d.TYPE.MSG_ACK,a._ackListenerId)end;a._ackListenerId=nil end end
function p.draw(a,b)local d,c,e,f=a.D,a.T,a.W,a.H;d.fill(1,2,e,f-1," ",c.fg,c.bg)local n=
(a.NM and
a.NM.getHostname and a.NM.getHostname())or"local"
local o=#t(a.NM and
a.NM.getTrust and a.NM.getTrust())
u.drawRail(d,c,2,e,{{label="§ Chat — "..n},{text="peers:"..o}},{labelFg=
c.title or c.fg})local j,E=3,f-2;local i=E-j+1;local k=# (w(0).." ")
local F=math.max(1,e-k)local g={}
for I,H in ipairs(b.messages or{})do local J=w(H.time).." "for K,L in
ipairs(q.wrapLine(H.text,F))do
g[#g+1]={prefix=(K==1)and J or string.rep(" ",k),text=L,color=H.color}end end;local l=math.max(0,#g-i)
if(b.scroll or 0)>l then b.scroll=l end
local G=math.max(1,#g-i+1- (b.scroll or 0))
for H=0,i-1 do local I=g[G+H]if I then local J=j+H;d.set(1,J,I.prefix,c.dim,c.bg)
d.set(#
I.prefix+1,J,I.text,I.color or c.fg,c.bg)end end;d.set(1,f-1,"> ",c.highlight,c.bg)local m=e-3
local h=b.input or""if#h>m then h=h:sub(#h-m+1)end
d.set(3,f-1,h.."_",c.fg,c.bg)
u.drawRampBar(d,c,f,e,"Enter Send · peer:msg Direct · /help · PgUp/Dn Scroll · ^Q Close",nil,c.statusbar_fg or c.bar_fg,
c.statusbar_bg or c.bar_bg)b.unread=0;b.label=p.label(0)b._dirty=false end
local function B(b,a)local c,e=b.T,b.NM;local h=a.input or""a.input=""local d=q.parseInput(h)if d.kind==
"empty"then return end;if not e then
p.addMessage(a,"No network.",c.error)return end
local f=e.getTrust and e.getTrust()
local g=(e.getHostname and e.getHostname())or"local"
if d.kind=="command"then local i,j=d.name,d.arg or""
if i=="quit"or i=="exit"then
s.close(b)elseif i=="clear"then a.messages={}elseif i=="help"or i=="?"then
p.addMessage(a,"Commands:",c.title)
p.addMessage(a,"  peer:msg          send to one peer (addr-prefix or hostname)",c.dim)
p.addMessage(a,"  @group:msg        send to everyone in a group",c.dim)
p.addMessage(a,"  msg               broadcast to all trusted peers",c.dim)
p.addMessage(a,"  /who              list trusted peers",c.dim)
p.addMessage(a,"  /group            list groups (new/add/rm/del to edit)",c.dim)
p.addMessage(a,"  /mail peer text   send a store-and-forward mesh mail",c.dim)
p.addMessage(a,"  /clear  /help  ^Q closes the tab",c.dim)elseif i=="group"then local k,E=j:match("^(%S*)%s*(.*)$")
k=(k or""):lower()local l,F=E:match("^(%S*)%s*(.*)$")local m=y()
local function o()local G={}for H in
(F or""):gmatch("%S+")do G[#G+1]=H end;return G end
local function n(G)local H,I=A(m)if H then p.addMessage(a,G,c.title)else
p.addMessage(a,"Could not save groups: "..
tostring(I),c.error)end end
if k==""or k=="list"then local G={}for H in pairs(m)do G[#G+1]=H end
table.sort(G)
if#G==0 then
p.addMessage(a,"No groups yet.  /group new <name> <peer...>",c.warning)else for I,H in ipairs(G)do local J=m[H]
p.addMessage(a,"  @"..H.."  ("..
#J..")  "..table.concat(J," "),c.highlight)end
p.addMessage(a,"Send to one with  @<name>: your message",c.dim)end elseif not q.validGroupName(l or"")then
p.addMessage(a,"Group names are letters, digits, _ and - (max 24).",c.error)elseif k=="new"then if m[l:lower()]then
p.addMessage(a,"@"..l:lower().." already exists.",c.warning)else m[l:lower()]=o()
n("Created @"..l:lower()..".")end elseif k=="add"or k==
"rm"or k=="remove"then local G=m[l:lower()]
if not G then p.addMessage(a,
z..l:lower(),c.error)else local H=o()
if#H==0 then
p.addMessage(a,
"Usage: /group "..k.." <name> <peer...>",c.warning)else local I=0
for K,J in ipairs(H)do
if k=="add"then local L=false
for K,M in ipairs(G)do if M==J then L=true end end;if not L then G[#G+1]=J;I=I+1 end else for L=#G,1,-1 do if G[L]==J then table.remove(G,L)I=
I+1 end end end end
n(string.format("@%s: %d member(s) %s.",l:lower(),I,k=="add"and"added"or"removed"))end end elseif k=="del"or k=="delete"then if not m[l:lower()]then
p.addMessage(a,z..l:lower(),c.error)else m[l:lower()]=nil
n("Deleted @"..l:lower()..".")end else
p.addMessage(a,"Usage: /group [list|new|add|rm|del] ...",c.warning)end elseif i=="who"then local k=t(f)for m,l in ipairs(k)do
p.addMessage(a,"  "..
tostring(l.address):sub(1,8).."  ".. (l.hostname or"?"),c.highlight)end;if#k==0 then
p.addMessage(a,"  (no trusted peers)",c.warning)end elseif i=="mail"then
local k,m=j:match("^(%S+)%s+(.+)$")
local n=k and f and
q.resolveTarget(f.listPeers(),k,f.LEVEL.TRUSTED,e and e.aliases and e.aliases.resolve)local o,l=pcall(require,"mail")
if not k or not m then
p.addMessage(a,"Usage: /mail <peer> <message>",c.warning)elseif not n then
p.addMessage(a,"Unknown peer: "..tostring(k),c.error)elseif
not(o and type(l)=="table"and l.send)then
p.addMessage(a,"Mail add-on not installed (pkg install mail).",c.error)else
local F,E=l.send({to=n,fromUser=g,subject="(via chat)",body=m})if F then
p.addMessage(a,"Mail queued to "..k.. (E and""or" (plaintext)"),c.title)else
p.addMessage(a,"Mail failed: "..tostring(E),c.error)end end else
p.addMessage(a,"Unknown command: /"..i.."  (try /help)",c.warning)end elseif d.kind=="group"then local l=y()
local i,j,k=q.resolveGroup(l,d.group,(f and f.listPeers())or{},
f and f.LEVEL.TRUSTED or 2,e and e.aliases and e.aliases.resolve)
if not i then
p.addMessage(a,z..d.group.."  (/group to list)",c.error)elseif#i==0 then
p.addMessage(a,"@"..d.group.." has nobody reachable right now.",c.warning)for o,n in ipairs(j)do
p.addMessage(a,"  unreachable: "..n,c.dim)end else local m={}
p.addMessage(a,"["..g.." -> @"..
d.group.."] "..d.text,c.title)
for E,o in ipairs(i)do
local F=(k and k[o])or tostring(o):sub(1,8)
local G,H,I=e.sendMessage(o,"@"..d.group.." "..d.text)if G then m[#m+1]={addr=o,seq=I,name=F}else
p.addMessage(a,"  not sent to "..
F..": "..tostring(H),c.warning)end end;for E,o in ipairs(j)do
p.addMessage(a,"  unreachable: "..o,c.dim)end;local n=#i+#j
if#m==0 then
p.addMessage(a,string.format("  delivered to 0 of %d member(s)",n),c.warning)else
p.watchAcks(b,a,{group=d.group,sent=m,total=n,deadline=(r.uptime and r.uptime()or 0)+p.ACK_WAIT})end end elseif d.kind=="directed"then
local i=f and q.resolveTarget(f.listPeers(),d.target,f.LEVEL.TRUSTED,e and e.aliases and
e.aliases.resolve)
if i then local j,k=e.sendMessage(i,d.text)if j then
p.addMessage(a,"["..g.."] "..d.text,c.title)else
p.addMessage(a,"Send failed: "..tostring(k),c.error)end else p.addMessage(a,"Unknown peer: "..
d.target,c.error)end else local i=t(f)
if#i==0 then
p.addMessage(a,"No trusted peers to send to.",c.warning)else local j,k=0,nil
for m,l in ipairs(i)do local n,o=e.sendMessage(l.address,d.text)if n then j=j+1 elseif not
k then k=o end end;if j>0 then
p.addMessage(a,"["..g.."] "..d.text,c.title)end
if j<#i then
p.addMessage(a,string.format("  delivered to %d of %d peer(s)",j,#i),c.warning)
if k then p.addMessage(a,"  "..tostring(k),c.error)if
tostring(k):find("shared secret",1,true)then
p.addMessage(a,"  run: net trust gen <addr>   (as admin)",c.dim)end end end end end end
function p.handleKey(c,a,b,d,e)
if b==17 then s.close(c)return 3 elseif d==28 then B(c,a)a.scroll=0;return 3 elseif d==14 then
if#
(a.input or"")>0 then a.input=a.input:sub(1,-2)end;return 3 elseif d==201 then
a.scroll=(a.scroll or 0)+math.max(1,c.H-5)return 3 elseif d==209 then
a.scroll=math.max(0,(a.scroll or 0)-math.max(1,c.H-5))return 3 elseif b and b>=32 and b<127 then
if# (a.input or"")<200 then a.input=(a.input or
"")..string.char(b)end;return 3 end;return 0 end
function p.handleScroll(c,a,b)local e=(b.dir or 0)>0 and 1 or-1;local d=math.max(0,(
a.scroll or 0)+e*2)if d==a.scroll then
return 0 end;a.scroll=d;return 3 end
local C={critical="error",alert="error",warn="warning",notice="highlight",info="dim"}
local function D(b,a)local f,c=pcall(require,"intercom")if not
(f and type(c)=="table"and c.since)then return false end;local e=b.T
if
a._annSeen==nil then local i,j=pcall(c.highWater)a._annSeen=(i and j)or 0;return false end;local g,d,h=pcall(c.since,a._annSeen)if
not g or type(d)~="table"then return false end;if#d==0 then return false end;a._annSeen=h;for j,i in
ipairs(d)do
p.addMessage(a,"*** "..c.formatLine(i),
e[C[i.severity or"info"]or"dim"]or e.fg)end;return true end;p.ACK_WAIT=4
function p.watchAcks(b,a,c)a._acks=a._acks or{}
a._acks[#a._acks+1]=c;local d=b.NM
local e=d and d.getProtocol and d.getProtocol()
if a._ackListenerId or not(e and d.on)then return end
a._ackListenerId=d.on(e.TYPE.MSG_ACK,function(f,g)
local h=
type(f)=="table"and type(f.payload)=="table"and f.payload.ref or nil
for j,i in ipairs(a._acks or{})do for j,k in ipairs(i.sent)do
if k.addr==g and not k.got and(h==nil or
h==k.seq)then k.got=true;a._dirty=true end end end end)end
function p.settleAcks(a,b)
if not a._acks or#a._acks==0 then return false end;local c,d,e=a._theme or{},{},false
for g,f in ipairs(a._acks)do local h,i=0,true;for g,j in ipairs(f.sent)do if j.got then h=h+
1 else i=false end end
if i or
b>=f.deadline then
p.addMessage(a,string.format("  @%s: delivered to %d of %d member(s)",f.group,h,f.total),(
h==f.total)and c.highlight or c.warning)
for g,j in ipairs(f.sent)do if not j.got then
p.addMessage(a,"  no answer from "..j.name,c.dim)end end;e=true else d[#d+1]=f end end;a._acks=d;return e end
function p.tick(b,a)local c=D(b,a)a._theme=b.T
local d=p.settleAcks(a,r.uptime and r.uptime()or 0)if a._dirty or c or d then return 3 end;return 0 end;return p