local h,g="shell.quitkey","string"local f=require("computer")local e={}
function e.parseInput(a)
a=a or""if a:match("^%s*$")then return{kind="empty"}end
local b,k=a:match("^/(%S+)%s*(.*)$")
if b then return{kind="command",name=b:lower(),arg=k}end;local c,d=a:match("^@([%w_%-]+):%s*(.+)$")if c and d then return
{kind="group",group=c:lower(),text=d}end
local i,j=a:match("^([^:%s]+):%s*(.+)$")
if i and j then return{kind="directed",target=i,text=j}end;return{kind="broadcast",text=a}end;e.GROUPS_PATH="/etc/chat-groups.cfg"e.MAX_GROUPS=32;e.MAX_MEMBERS=32
function e.validGroupName(a)return
type(a)==g and a~=""and#a<=24 and
a:match("^[%w_%-]+$")~=nil end
function e.normalizeGroups(a)local b={}if type(a)~="table"then return b end;local c=0
for d,i in pairs(a)do
if
type(d)==g and type(i)=="table"and c<e.MAX_GROUPS then
local j=d:lower()
if e.validGroupName(j)then local k,l={},{}for o,n in ipairs(i)do
if
type(n)==g and n~=""and not l[n]and#k<e.MAX_MEMBERS then l[n]=true;k[#k+1]=n end end;b[j]=k;c=c+1 end end end;return b end
function e.resolveGroup(a,b,c,d,i)local l=a and a[(b or""):lower()]if not l then
return nil end;local j,k,m,n={},{},{},{}for p,o in ipairs(l)do
local q=e.resolveTarget(c,o,d,i)
if q and not m[q]then m[q]=true;j[#j+1]=q;n[q]=o elseif not q then k[#k+1]=o end end
return j,k,n end
function e.loadGroups(a,c,b)b=b or e.GROUPS_PATH;if not
(a and c and a.exists and a.exists(b))then return{}end
local d=a.readFile(b)if type(d)~=g then return{}end
local i,j=pcall(c.decode,d,{maxBytes=16*1024})if not i then return{}end;return e.normalizeGroups(j)end
function e.saveGroups(b,c,d,a)a=a or e.GROUPS_PATH;if not(b and c)then
return false,"fs/serialize unavailable"end
return c.saveFile(b,a,e.normalizeGroups(d))end
function e.wrapLine(b,a)local c={}a=math.max(1,a or 1)
for d in
(tostring(b or"").."\n"):gmatch("(.-)\n")do if d==""then c[#c+1]=""else
while#d>0 do c[#c+1]=d:sub(1,a)d=d:sub(a+1)end end end;return c end
function e.resolveTarget(c,a,b,d)if not a or a==""then return nil end;b=b or 0;if d then local j,i=pcall(d,a)
if j and
type(i)==g then for l,k in ipairs(c or{})do if
k.address==i and(k.level or 0)>=b then return i end end end end
for j,i in ipairs(
c or{})do
if(i.level or 0)>=b then if i.address and
i.address:sub(1,#a)==a then return i.address end;if i.hostname and
i.hostname==a then return i.address end end end;return nil end
function e.run(a,b)local i=a.getDisplay()local p=a.getEvent()local j=a.getNet()
if not j then
if i then
local L,M=i.getSize()local J=i.getTheme()i.clear(J.bg)
i.set(2,2,"Chat unavailable: no network module",J.error,J.bg)i.set(2,4,"Press any key to return.",J.dim,J.bg)local K=
f.uptime()+10
while f.uptime()<K do
local N=f.pullSignal(K-f.uptime())if N=="key_down"or not N then break end end end;return end;local q=j.getProtocol()local k=j.getTrust()local n,y=i.getSize()
local c=i.getTheme()local r=j.getHostname()or"local"local t=1;local z=2;local E=y-1;local s=y
local A=E-z+1;local B=128;local m={}local l=""local u=nil
local function C(J)local K=math.floor(J/3600)local L=math.floor(
(J%3600)/60)local M=math.floor(J%60)return
string.format("%02d:%02d:%02d",K,L,M)end;local function d(J,K)m[#m+1]={text=J,color=K or c.fg,time=f.uptime()}
if#m>B then
local L={}for M=#m-B+1,#m do L[#L+1]=m[M]end;m=L end end;local function F()local J=0
for L,K in
ipairs(k.listPeers())do if K.level>=k.LEVEL.TRUSTED then J=J+1 end end;return J end
local function G()
i.fill(1,t,n,1," ",c.menubar_fg,c.menubar_bg)local K=" TOS Chat - "..r.." "
local J=" peers:"..F().."  /help  "..require(h).hint()..
"=Exit "i.set(1,t,K,c.menubar_fg,c.menubar_bg)
i.set(n-#J+1,t,J,c.dim,c.menubar_bg)end
local function D()local K=# (C(0).." ")local L=math.max(1,n-K)local J={}
for O,N in ipairs(m)do local P=
C(N.time).." "for Q,R in ipairs(e.wrapLine(N.text,L))do
J[#J+1]={prefix=
(Q==1)and P or string.rep(" ",K),text=R,color=N.color}end end;local M=math.max(1,#J-A+1)
for N=0,A-1 do local O=z+N;local P=M+N
i.fill(1,O,n,1," ",c.fg,c.bg)
if P>=1 and P<=#J then local Q=J[P]i.set(1,O,Q.prefix,c.dim,c.bg)i.set(
#Q.prefix+1,O,Q.text,Q.color,c.bg)end end end
local function o()i.fill(1,s,n,1," ",c.fg,c.bg)
i.set(1,s,"> ",c.highlight,c.bg)local K=n-3;local J=l;if#J>K then J=J:sub(#J-K+1)end
i.set(3,s,J,c.fg,c.bg)local L=3+math.min(#l,K)if L<=n then
i.set(L,s,"_",c.highlight,c.bg)end end;local function v()i.clear(c.bg)G()D()o()end
local function H(K,J)local N=
(k.getLevel and k.getLevel(J))or 0
if N<k.LEVEL.TRUSTED then return end;local L=K.payload or{}
local O=type(L.text)==g and L.text or""local M=k.getPeer(J)
local P=(M and M.hostname)or J:sub(1,8)d("["..P.."] "..O,c.border)D()o()if
_G._TOS and _G._TOS.audio then _G._TOS.audio.chat()end
local Q=q.makePacket(q.TYPE.MSG_ACK,{ref=K.seq},{to=J})j.send(J,Q)end;if p then u=j.on(q.TYPE.MSG,H)end
d("Chat started. Send messages to TRUSTED peers.",c.title)
d("  peer:message   to one peer (addr prefix or hostname)",c.dim)
d("  message        broadcast to all trusted peers",c.dim)
d("  /who  /mail peer text  /clear  /help   "..require(h).hint().."=exit",c.dim)d("",c.dim)local I=k.listPeers()local w=0
for K,J in ipairs(I)do
if
J.level>=k.LEVEL.TRUSTED then w=w+1;local L=J.hostname or"?"local M=J.address:sub(1,8)d("  "..M..
"  "..L,c.highlight)end end
if w==0 then d("  (no trusted peers)",c.warning)end;v()local x=true
while x do local K,M,J,L;if p and p.pull then K,M,J,L=p.pull(0.2)else
K,M,J,L=f.pullSignal(0.2)end
if K=="key_down"then
if
require(h).is(J,L,true)then x=false elseif L==28 then
if l~=""then local N=e.parseInput(l)
if N.kind=="command"then
local O,P=N.name,N.arg or""
if O=="quit"or O=="exit"then x=false elseif O=="clear"then m={}elseif O=="help"or O=="?"then
d("Commands:",c.title)
d("  peer:msg          send to one peer (addr-prefix or hostname)",c.dim)
d("  msg               broadcast to all trusted peers",c.dim)d("  /who              list trusted peers",c.dim)
d("  /mail peer text   send a store-and-forward mesh mail",c.dim)
d("  /clear  /help  "..require(h).hint().." exit",c.dim)elseif O=="who"then local Q=0
for M,R in ipairs(k.listPeers())do if R.level>=k.LEVEL.TRUSTED then Q=Q+1
d("  "..
R.address:sub(1,8).."  ".. (R.hostname or"?"),c.highlight)end end
if Q==0 then d("  (no trusted peers)",c.warning)end elseif O=="mail"then local Q,S=P:match("^(%S+)%s+(.+)$")
local T=Q and
e.resolveTarget(k.listPeers(),Q,k.LEVEL.TRUSTED,
j and j.aliases and j.aliases.resolve)local U,R=pcall(require,"mail")
if not Q or not S then
d("Usage: /mail <peer> <message>",c.warning)elseif not T then
d("Unknown peer: "..tostring(Q),c.error)elseif
not(U and type(R)=="table"and R.send)then
d("Mail add-on not installed (pkg install mail).",c.error)else
local W,V=R.send({to=T,fromUser=r,subject="(via chat)",body=S})
if W then
d("Mail queued to "..Q.. (V and""or" (plaintext)"),c.title)else d("Mail failed: "..tostring(V),c.error)end end else
d("Unknown command: /"..O.."  (try /help)",c.warning)end elseif N.kind=="directed"then
local O=e.resolveTarget(k.listPeers(),N.target,k.LEVEL.TRUSTED,j and j.aliases and
j.aliases.resolve)
if O then local P,Q=j.sendMessage(O,N.text)
if P then
d("["..r.."] "..N.text,c.title)else d("Send failed: "..tostring(Q),c.error)end else d("Unknown peer: "..N.target,c.error)end elseif N.kind=="broadcast"then local O=0;for M,P in ipairs(k.listPeers())do
if
P.level>=k.LEVEL.TRUSTED then j.sendMessage(P.address,N.text)O=O+1 end end;if O>0 then d("["..
r.."] "..N.text,c.title)else
d("No trusted peers to send to.",c.warning)end end;l=""v()end;o()elseif L==14 then if#l>0 then l=l:sub(1,-2)o()end elseif J and J>=32 and J<127 then l=l..
string.char(J)o()end elseif K=="clipboard"then local N=J
if type(N)==g then l=l..N:gsub("\n","")o()end elseif K=="tos_focus"then v()end end;if u and j.off then j.off(q.TYPE.MSG,u)end
d("Chat ended.",c.dim)end;return e