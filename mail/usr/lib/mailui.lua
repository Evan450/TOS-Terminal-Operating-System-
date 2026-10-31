local l="key_down"
local function j(a,b,c)
if c and a and a>=32 and a<127 then return false end;local e,d=pcall(require,"shell.keys")if e and d and d.is then
return d.is("quit",a,b)end;return a==17 or b==1 end
local function i()local c,b=pcall(require,"shell.keys")local a=c and b and b.label and
b.label("quit")or""
a=a:gsub(" / .*","")return a~=""and a or"^Q"end;local h=require("computer")local g=require("mail")local k={}
function k.run(a)a=a or{}local c=
a.display or a.D;local B=a.event or a.E;local y=a.me or"user"if not c then
return end;local f,u=c.getSize()local b=c.getTheme()
local function z(K)
if coroutine.isyieldable and
coroutine.isyieldable()then return coroutine.yield()end;if B and B.pull then return B.pull(K)end;return h.pullSignal(K)end
local function F(K,L)c.clear(b.bg)c.set(2,2,K,L or b.fg,b.bg)
c.set(2,4,"Press any key to return.",b.dim,b.bg)local M=h.uptime()+10;while h.uptime()<M do
local N=z(M-h.uptime())if N==l then break end end end;if not g.available()then
F("Mail unavailable (no network hardware?)",b.error)return end;local d=g.inboxBox(y)if not d then
F("Cannot open this inbox (owner or admin only).",b.error)return end;local function C()return
(d and d.list and d:list())or{}end;local function r()
g.tick()d=g.inboxBox(y)or d end;local s="list"local e=1
local t=0;local v=nil;local p={}local m=0;local n=u;local A=3;local w=n-A
local function D(K,M,N,L)local O=M or""
while true do
c.fill(1,L,f,1," ",b.fg,b.bg)c.set(1,L,K,b.highlight,b.bg)
local R=math.max(1,f-#K-1)local T=#O>R and O:sub(#O-R+1)or O
c.set(#K+1,L,T.."_",b.fg,b.bg)local S,U,P,Q=z()
if S==l then
if Q==28 then return O elseif j(P,Q,true)then return nil elseif Q==14 then
if#O>0 then O=O:sub(1,-2)end elseif P and P>=32 and P<127 and#O< (N or 256)then O=O..
string.char(P)end elseif S=="clipboard"and type(P)=="string"then
O=O..P:gsub("\n","")end end end
local function E(K,L)c.clear(b.bg)
c.set(1,1," Compose mail   (Enter = next field/line, "..i().." = cancel)",b.title,b.bg)
local O=D(" To (peer / alias / user@peer / * = all): ",K,64,3)if not O or O==""then return end;local Q=D(" Subject: ",L,100,5)if Q==nil then
return end
c.set(1,7," Body — Enter for a new line, a blank line sends, "..i().." cancels:",b.dim,b.bg)local M,N={},9
while#M<64 and N<=u-1 do local V=D("  ","",200,N)if V==nil then return end;if
V==""then break end;M[#M+1]=V;N=N+1 end
local T,U=g.resolveRecipient(O,a.aliases and a.aliases.resolve)
local R,P=g.send({to=T,user=U,fromUser=y,subject=Q,body=table.concat(M,"\n")})c.fill(1,u,f,1," ",b.fg,b.bg)
if R then
c.set(1,u,"Queued "..

tostring(R):sub(1,18).. (P and"  (sealed)"or"  (PLAINTEXT bulletin)"),P and b.highlight or b.warning)else
c.set(1,u,"Send failed: "..tostring(P),b.error)end;local S=h.uptime()+1.4;while h.uptime()<S do
z(S-h.uptime())end end
local function G()c.fill(1,1,f,1," ",b.menubar_fg,b.menubar_bg)local M=C()
local N=(d and
d.unread and d:unread())or 0;local K=g.pending()local O=" TOS Mail — "..y.." "
local L=string.format(" %d msg, %d unread%s%s ",
#M,N,K>0 and(", "..K.." sending")or"",
g.running()and""or", RECEIVE OFF")c.set(1,1,O,b.menubar_fg,b.menubar_bg)
c.set(math.max(1,f-#L+1),1,L,b.dim,b.menubar_bg)end
local function o()G()c.fill(1,2,f,1," ",b.fg,b.bg)local K=C()
if#K==0 then
c.set(2,A,"(inbox empty)",b.dim,b.bg)for L=A+1,n-1 do c.fill(1,L,f,1," ",b.fg,b.bg)end else if e>#K then e=#
K end;if e<1 then e=1 end;if e<=t then t=e-1 end;if e>t+w then t=e-w end;if t<0 then
t=0 end
for L=0,w-1 do local M=t+L+1;local N=A+L
if M<=#K then local P=K[M]
local O=g.inboxRow(P,M,f-1)if M==e then
c.set(1,N,c.fit and c.fit(O,f)or O,b.sel_fg,b.sel_bg)else
c.set(1,N,O,P.read and b.dim or b.fg,b.bg)end else
c.fill(1,N,f,1," ",b.fg,b.bg)end end end;c.fill(1,n,f,1," ",b.dim,b.menubar_bg)
c.set(1,n,
" [Enter] read  [c] compose  [r] reply  [d] delete  [R] refresh  "..i().." exit",b.dim,b.menubar_bg)end
local function I(K)local L={}
for M in
(tostring(K or"").."\n"):gmatch("(.-)\n")do if M==""then L[#L+1]=""else
while#M>0 do L[#L+1]=M:sub(1,f-1)M=M:sub(f)end end end;return L end
local function J(K)local L=d and d.get and d:get(K)if not L then return false end
if
d.markRead then pcall(function()d:markRead(K)end)end;v=K
local M={{"From:    "..g.senderName(L)..
(L.from and("  ("..
tostring(L.from):sub(1,12)..")")or""),b.fg},{
"Subject: "..
(L.subject~=""and L.subject or"(no subject)"),b.title},{"Sent:    "..
g.formatTs(L.ts).." (sender's uptime)",b.dim}}if not L.readable then
M[#M+1]={"[sealed — no shared secret to open this]",b.warning}end;p={}
for O,N in ipairs(M)do p[#p+1]=N end;p[#p+1]={"",b.fg}
for O,N in ipairs(I(L.body))do p[#p+1]={N,b.fg}end;m=0;s="read"return true end
local function x()G()local K=n-2
for L=0,K-1 do local N=2+L;local O=m+L+1
c.fill(1,N,f,1," ",b.fg,b.bg)local M=p[O]if M then
c.set(1,N,(type(M)=="table"and M[1]or tostring(M)),(
type(M)=="table"and M[2])or b.fg,b.bg)end end;c.fill(1,n,f,1," ",b.dim,b.menubar_bg)
c.set(1,n,
" [q/Esc] back  [r] reply  [d] delete  up/down scroll  "..i().." exit",b.dim,b.menubar_bg)end
local function q()c.clear(b.bg)if s=="read"then x()else o()end end;r()q()local H=h.uptime()
while true do local M,N,L,K=z(0.5)
if M==l then
if j(L,K,true)then break elseif s=="list"then local O=C()
if
K==200 then e=math.max(1,e-1)o()elseif K==208 then e=math.min(#O,e+1)o()elseif K==201 then e=math.max(1,
e-w)o()elseif K==209 then e=math.min(#O,e+w)o()elseif K==199 then e=1;o()elseif K==207 then e=
#O;o()elseif K==28 then if#O>0 and J(e)then q()else o()end elseif L==99 or L==67 then E()r()q()elseif
L==114 or L==82 then local P=O[e]
if P then
local Q=
(P.fromUser and P.fromUser~=""and P.fromUser)or
(P.from and("@"..tostring(P.from)))or""
local R=
(P.subject and not P.subject:match("^[Rr][Ee]:"))and("Re: "..P.subject)or
(P.subject or"")E(Q:gsub("^@",""),R)r()q()end elseif L==100 or L==68 then if#O>0 and d and d.delete then
pcall(function()d:delete(e)end)r()o()end end else local O=math.max(0,#p- (n-2))
if K==1 or L==113 then s="list"q()elseif K==200 then m=math.max(0,
m-1)x()elseif K==208 then m=math.min(O,m+1)x()elseif K==201 then
m=math.max(0,m- (n-2))x()elseif K==209 then m=math.min(O,m+ (n-2))x()elseif L==114 or L==82 then local P=
v and d and d.get and d:get(v)
if P then
local Q=(
P.fromUser and P.fromUser~=""and P.fromUser)or""
local R=
(P.subject and not P.subject:match("^[Rr][Ee]:"))and("Re: "..P.subject)or
(P.subject or"")E(Q,R)s="list"r()q()end elseif L==100 or L==68 then if v and d and d.delete then
pcall(function()d:delete(v)end)s="list"r()q()end end end elseif M=="tos_focus"then q()elseif M==nil then local O=h.uptime()
if O-H>=2 then H=O;r()if s=="list"then o()end end end end end;return k