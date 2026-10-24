local f="string"local e=require("computer")local d={}
function d.parseInput(a)a=a or""if
a:match("^%s*$")then return{kind="empty"}end
local b,j=a:match("^/(%S+)%s*(.*)$")
if b then return{kind="command",name=b:lower(),arg=j}end;local c,g=a:match("^@([%w_%-]+):%s*(.+)$")if c and g then return
{kind="group",group=c:lower(),text=g}end
local h,i=a:match("^([^:%s]+):%s*(.+)$")
if h and i then return{kind="directed",target=h,text=i}end;return{kind="broadcast",text=a}end;d.GROUPS_PATH="/etc/chat-groups.cfg"d.MAX_GROUPS=32;d.MAX_MEMBERS=32
function d.validGroupName(a)return
type(a)==f and a~=""and#a<=24 and
a:match("^[%w_%-]+$")~=nil end
function d.normalizeGroups(a)local b={}if type(a)~="table"then return b end;local c=0
for g,h in pairs(a)do
if
type(g)==f and type(h)=="table"and c<d.MAX_GROUPS then
local i=g:lower()
if d.validGroupName(i)then local j,k={},{}for m,l in ipairs(h)do
if
type(l)==f and l~=""and not k[l]and#j<d.MAX_MEMBERS then k[l]=true;j[#j+1]=l end end;b[i]=j;c=c+1 end end end;return b end
function d.resolveGroup(a,b,c,g,h)local k=a and a[(b or""):lower()]if not k then
return nil end;local i,j,l,m={},{},{},{}for o,n in ipairs(k)do
local p=d.resolveTarget(c,n,g,h)
if p and not l[p]then l[p]=true;i[#i+1]=p;m[p]=n elseif not p then j[#j+1]=n end end
return i,j,m end
function d.loadGroups(a,c,b)b=b or d.GROUPS_PATH;if not
(a and c and a.exists and a.exists(b))then return{}end
local g=a.readFile(b)if type(g)~=f then return{}end
local h,i=pcall(c.decode,g,{maxBytes=16*1024})if not h then return{}end;return d.normalizeGroups(i)end
function d.saveGroups(b,c,g,a)a=a or d.GROUPS_PATH;if not(b and c)then
return false,"fs/serialize unavailable"end
return c.saveFile(b,a,d.normalizeGroups(g))end
function d.wrapLine(b,a)local c={}a=math.max(1,a or 1)
for g in
(tostring(b or"").."\n"):gmatch("(.-)\n")do if g==""then c[#c+1]=""else
while#g>0 do c[#c+1]=g:sub(1,a)g=g:sub(a+1)end end end;return c end
function d.resolveTarget(c,a,b,g)if not a or a==""then return nil end;b=b or 0;if g then local i,h=pcall(g,a)
if i and
type(h)==f then for k,j in ipairs(c or{})do if
j.address==h and(j.level or 0)>=b then return h end end end end
for i,h in ipairs(
c or{})do
if(h.level or 0)>=b then if h.address and
h.address:sub(1,#a)==a then return h.address end;if h.hostname and
h.hostname==a then return h.address end end end;return nil end
function d.run(a,b)local h=a.getDisplay()local o=a.getEvent()local i=a.getNet()
if not i then
if h then
local K,L=h.getSize()local I=h.getTheme()h.clear(I.bg)
h.set(2,2,"Chat unavailable: no network module",I.error,I.bg)h.set(2,4,"Press any key to return.",I.dim,I.bg)local J=
e.uptime()+10
while e.uptime()<J do
local M=e.pullSignal(J-e.uptime())if M=="key_down"or not M then break end end end;return end;local p=i.getProtocol()local j=i.getTrust()local m,x=h.getSize()
local c=h.getTheme()local q=i.getHostname()or"local"local s=1;local y=2;local D=x-1;local r=x
local z=D-y+1;local A=128;local l={}local k=""local t=nil
local function B(I)local J=math.floor(I/3600)local K=math.floor(
(I%3600)/60)local L=math.floor(I%60)return
string.format("%02d:%02d:%02d",J,K,L)end;local function g(I,J)l[#l+1]={text=I,color=J or c.fg,time=e.uptime()}
if#l>A then
local K={}for L=#l-A+1,#l do K[#K+1]=l[L]end;l=K end end;local function E()local I=0
for K,J in
ipairs(j.listPeers())do if J.level>=j.LEVEL.TRUSTED then I=I+1 end end;return I end
local function F()
h.fill(1,s,m,1," ",c.menubar_fg,c.menubar_bg)local J=" TOS Chat - "..q.." "
local I=" peers:"..E().."  /help  ^Q=Exit "h.set(1,s,J,c.menubar_fg,c.menubar_bg)
h.set(m-#I+1,s,I,c.dim,c.menubar_bg)end
local function C()local J=# (B(0).." ")local K=math.max(1,m-J)local I={}
for N,M in ipairs(l)do local O=
B(M.time).." "for P,Q in ipairs(d.wrapLine(M.text,K))do
I[#I+1]={prefix=
(P==1)and O or string.rep(" ",J),text=Q,color=M.color}end end;local L=math.max(1,#I-z+1)
for M=0,z-1 do local N=y+M;local O=L+M
h.fill(1,N,m,1," ",c.fg,c.bg)
if O>=1 and O<=#I then local P=I[O]h.set(1,N,P.prefix,c.dim,c.bg)h.set(
#P.prefix+1,N,P.text,P.color,c.bg)end end end
local function n()h.fill(1,r,m,1," ",c.fg,c.bg)
h.set(1,r,"> ",c.highlight,c.bg)local J=m-3;local I=k;if#I>J then I=I:sub(#I-J+1)end
h.set(3,r,I,c.fg,c.bg)local K=3+math.min(#k,J)if K<=m then
h.set(K,r,"_",c.highlight,c.bg)end end;local function u()h.clear(c.bg)F()C()n()end
local function G(J,I)local M=
(j.getLevel and j.getLevel(I))or 0
if M<j.LEVEL.TRUSTED then return end;local K=J.payload or{}
local N=type(K.text)==f and K.text or""local L=j.getPeer(I)
local O=(L and L.hostname)or I:sub(1,8)g("["..O.."] "..N,c.border)C()n()if
_G._TOS and _G._TOS.audio then _G._TOS.audio.chat()end
local P=p.makePacket(p.TYPE.MSG_ACK,{ref=J.seq},{to=I})i.send(I,P)end;if o then t=i.on(p.TYPE.MSG,G)end
g("Chat started. Send messages to TRUSTED peers.",c.title)
g("  peer:message   to one peer (addr prefix or hostname)",c.dim)
g("  message        broadcast to all trusted peers",c.dim)
g("  /who  /mail peer text  /clear  /help   ^Q=exit",c.dim)g("",c.dim)local H=j.listPeers()local v=0
for J,I in ipairs(H)do
if
I.level>=j.LEVEL.TRUSTED then v=v+1;local K=I.hostname or"?"local L=I.address:sub(1,8)g("  "..L..
"  "..K,c.highlight)end end
if v==0 then g("  (no trusted peers)",c.warning)end;u()local w=true
while w do local J,L,I,K;if o and o.pull then J,L,I,K=o.pull(0.2)else
J,L,I,K=e.pullSignal(0.2)end
if J=="key_down"then
if I==17 then w=false elseif K==28 then
if k~=""then
local M=d.parseInput(k)
if M.kind=="command"then local N,O=M.name,M.arg or""
if N=="quit"or N=="exit"then
w=false elseif N=="clear"then l={}elseif N=="help"or N=="?"then g("Commands:",c.title)
g("  peer:msg          send to one peer (addr-prefix or hostname)",c.dim)
g("  msg               broadcast to all trusted peers",c.dim)g("  /who              list trusted peers",c.dim)
g("  /mail peer text   send a store-and-forward mesh mail",c.dim)g("  /clear  /help  ^Q exit",c.dim)elseif N=="who"then local P=0
for L,Q in
ipairs(j.listPeers())do if Q.level>=j.LEVEL.TRUSTED then P=P+1
g("  "..Q.address:sub(1,8).."  "..
(Q.hostname or"?"),c.highlight)end end
if P==0 then g("  (no trusted peers)",c.warning)end elseif N=="mail"then local P,R=O:match("^(%S+)%s+(.+)$")
local S=P and
d.resolveTarget(j.listPeers(),P,j.LEVEL.TRUSTED,
i and i.aliases and i.aliases.resolve)local T,Q=pcall(require,"mail")
if not P or not R then
g("Usage: /mail <peer> <message>",c.warning)elseif not S then
g("Unknown peer: "..tostring(P),c.error)elseif
not(T and type(Q)=="table"and Q.send)then
g("Mail add-on not installed (pkg install mail).",c.error)else
local V,U=Q.send({to=S,fromUser=q,subject="(via chat)",body=R})
if V then
g("Mail queued to "..P.. (U and""or" (plaintext)"),c.title)else g("Mail failed: "..tostring(U),c.error)end end else
g("Unknown command: /"..N.."  (try /help)",c.warning)end elseif M.kind=="directed"then
local N=d.resolveTarget(j.listPeers(),M.target,j.LEVEL.TRUSTED,i and i.aliases and
i.aliases.resolve)
if N then local O,P=i.sendMessage(N,M.text)
if O then
g("["..q.."] "..M.text,c.title)else g("Send failed: "..tostring(P),c.error)end else g("Unknown peer: "..M.target,c.error)end elseif M.kind=="broadcast"then local N=0;for L,O in ipairs(j.listPeers())do
if
O.level>=j.LEVEL.TRUSTED then i.sendMessage(O.address,M.text)N=N+1 end end;if N>0 then g("["..
q.."] "..M.text,c.title)else
g("No trusted peers to send to.",c.warning)end end;k=""u()end;n()elseif K==14 then if#k>0 then k=k:sub(1,-2)n()end elseif I and I>=32 and I<127 then k=k..
string.char(I)n()end elseif J=="clipboard"then local M=I
if type(M)==f then k=k..M:gsub("\n","")n()end elseif J=="tos_focus"then u()end end;if t and i.off then i.off(p.TYPE.MSG,t)end
g("Chat ended.",c.dim)end;return d