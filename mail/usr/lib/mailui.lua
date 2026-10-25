local h="key_down"local f=require("computer")local e=require("mail")
local g={}
function g.run(a)a=a or{}local c=a.display or a.D;local z=a.event or a.E
local w=a.me or"user"if not c then return end;local j,s=c.getSize()local b=c.getTheme()
local function x(I)if
coroutine.isyieldable and coroutine.isyieldable()then
return coroutine.yield()end
if z and z.pull then return z.pull(I)end;return f.pullSignal(I)end
local function D(I,J)c.clear(b.bg)c.set(2,2,I,J or b.fg,b.bg)
c.set(2,4,"Press any key to return.",b.dim,b.bg)local K=f.uptime()+10;while f.uptime()<K do
local L=x(K-f.uptime())if L==h then break end end end;if not e.available()then
D("Mail unavailable (no network hardware?)",b.error)return end;local d=e.inboxBox(w)if not d then
D("Cannot open this inbox (owner or admin only).",b.error)return end;local function A()return
(d and d.list and d:list())or{}end;local function p()
e.tick()d=e.inboxBox(w)or d end;local q="list"local i=1
local r=0;local t=nil;local n={}local k=0;local l=s;local y=3;local u=l-y
local function B(I,K,L,J)local M=K or""
while true do
c.fill(1,J,j,1," ",b.fg,b.bg)c.set(1,J,I,b.highlight,b.bg)
local O=math.max(1,j-#I-1)local R=#M>O and M:sub(#M-O+1)or M
c.set(#I+1,J,R.."_",b.fg,b.bg)local P,S,N,Q=x()
if P==h then
if Q==28 then return M elseif N==17 then return nil elseif Q==14 then if#M>0 then M=M:sub(1,-2)end elseif N and
N>=32 and N<127 and#M< (L or 256)then M=M..
string.char(N)end elseif P=="clipboard"and type(N)=="string"then
M=M..N:gsub("\n","")end end end
local function C(I,J)c.clear(b.bg)
c.set(1,1," Compose mail   (Enter = next field/line, ^Q = cancel)",b.title,b.bg)
local M=B(" To (peer / alias / user@peer / * = all): ",I,64,3)if not M or M==""then return end;local O=B(" Subject: ",J,100,5)if O==nil then
return end
c.set(1,7," Body — Enter for a new line, a blank line sends, ^Q cancels:",b.dim,b.bg)local K,L={},9
while#K<64 and L<=s-1 do local T=B("  ","",200,L)if T==nil then return end;if
T==""then break end;K[#K+1]=T;L=L+1 end
local R,S=e.resolveRecipient(M,a.aliases and a.aliases.resolve)
local P,N=e.send({to=R,user=S,fromUser=w,subject=O,body=table.concat(K,"\n")})c.fill(1,s,j,1," ",b.fg,b.bg)
if P then
c.set(1,s,"Queued "..

tostring(P):sub(1,18).. (N and"  (sealed)"or"  (PLAINTEXT bulletin)"),N and b.highlight or b.warning)else
c.set(1,s,"Send failed: "..tostring(N),b.error)end;local Q=f.uptime()+1.4;while f.uptime()<Q do
x(Q-f.uptime())end end
local function E()c.fill(1,1,j,1," ",b.menubar_fg,b.menubar_bg)local K=A()
local L=(d and
d.unread and d:unread())or 0;local I=e.pending()local M=" TOS Mail — "..w.." "
local J=string.format(" %d msg, %d unread%s%s ",
#K,L,I>0 and(", "..I.." sending")or"",
e.running()and""or", RECEIVE OFF")c.set(1,1,M,b.menubar_fg,b.menubar_bg)
c.set(math.max(1,j-#J+1),1,J,b.dim,b.menubar_bg)end
local function m()E()c.fill(1,2,j,1," ",b.fg,b.bg)local I=A()
if#I==0 then
c.set(2,y,"(inbox empty)",b.dim,b.bg)for J=y+1,l-1 do c.fill(1,J,j,1," ",b.fg,b.bg)end else if i>#I then i=#
I end;if i<1 then i=1 end;if i<=r then r=i-1 end;if i>r+u then r=i-u end;if r<0 then
r=0 end
for J=0,u-1 do local K=r+J+1;local L=y+J
if K<=#I then local N=I[K]
local M=e.inboxRow(N,K,j-1)if K==i then
c.set(1,L,c.fit and c.fit(M,j)or M,b.sel_fg,b.sel_bg)else
c.set(1,L,M,N.read and b.dim or b.fg,b.bg)end else
c.fill(1,L,j,1," ",b.fg,b.bg)end end end;c.fill(1,l,j,1," ",b.dim,b.menubar_bg)
c.set(1,l," [Enter] read  [c] compose  [r] reply  [d] delete  [R] refresh  ^Q exit",b.dim,b.menubar_bg)end
local function G(I)local J={}
for K in
(tostring(I or"").."\n"):gmatch("(.-)\n")do if K==""then J[#J+1]=""else
while#K>0 do J[#J+1]=K:sub(1,j-1)K=K:sub(j)end end end;return J end
local function H(I)local J=d and d.get and d:get(I)if not J then return false end
if
d.markRead then pcall(function()d:markRead(I)end)end;t=I
local K={{"From:    "..e.senderName(J)..
(J.from and("  ("..
tostring(J.from):sub(1,12)..")")or""),b.fg},{
"Subject: "..
(J.subject~=""and J.subject or"(no subject)"),b.title},{"Sent:    "..
e.formatTs(J.ts).." (sender's uptime)",b.dim}}if not J.readable then
K[#K+1]={"[sealed — no shared secret to open this]",b.warning}end;n={}
for M,L in ipairs(K)do n[#n+1]=L end;n[#n+1]={"",b.fg}
for M,L in ipairs(G(J.body))do n[#n+1]={L,b.fg}end;k=0;q="read"return true end
local function v()E()local I=l-2
for J=0,I-1 do local L=2+J;local M=k+J+1
c.fill(1,L,j,1," ",b.fg,b.bg)local K=n[M]if K then
c.set(1,L,(type(K)=="table"and K[1]or tostring(K)),(
type(K)=="table"and K[2])or b.fg,b.bg)end end;c.fill(1,l,j,1," ",b.dim,b.menubar_bg)
c.set(1,l," [q/Esc] back  [r] reply  [d] delete  up/down scroll  ^Q exit",b.dim,b.menubar_bg)end
local function o()c.clear(b.bg)if q=="read"then v()else m()end end;p()o()local F=f.uptime()
while true do local K,L,I,J=x(0.5)
if K==h then
if I==17 then break elseif q=="list"then local M=A()
if J==200 then i=math.max(1,
i-1)m()elseif J==208 then i=math.min(#M,i+1)m()elseif J==201 then
i=math.max(1,i-u)m()elseif J==209 then i=math.min(#M,i+u)m()elseif J==199 then i=1;m()elseif J==207 then i=#M;m()elseif J==28 then if
#M>0 and H(i)then o()else m()end elseif I==99 or I==67 then C()p()o()elseif I==114 or I==82 then
local N=M[i]
if N then
local O=
(N.fromUser and N.fromUser~=""and N.fromUser)or
(N.from and("@"..tostring(N.from)))or""
local P=
(N.subject and not N.subject:match("^[Rr][Ee]:"))and("Re: "..N.subject)or
(N.subject or"")C(O:gsub("^@",""),P)p()o()end elseif I==100 or I==68 then if#M>0 and d and d.delete then
pcall(function()d:delete(i)end)p()m()end end else local M=math.max(0,#n- (l-2))
if J==1 or I==113 then q="list"o()elseif J==200 then k=math.max(0,
k-1)v()elseif J==208 then k=math.min(M,k+1)v()elseif J==201 then
k=math.max(0,k- (l-2))v()elseif J==209 then k=math.min(M,k+ (l-2))v()elseif I==114 or I==82 then local N=
t and d and d.get and d:get(t)
if N then
local O=(
N.fromUser and N.fromUser~=""and N.fromUser)or""
local P=
(N.subject and not N.subject:match("^[Rr][Ee]:"))and("Re: "..N.subject)or
(N.subject or"")C(O,P)q="list"p()o()end elseif I==100 or I==68 then if t and d and d.delete then
pcall(function()d:delete(t)end)q="list"p()o()end end end elseif K=="tos_focus"then o()elseif K==nil then local M=f.uptime()
if M-F>=2 then F=M;p()if q=="list"then m()end end end end end;return g