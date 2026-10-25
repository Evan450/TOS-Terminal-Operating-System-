local t,o,p,n,q="kernel.fs","key_down","password","string","username"
local l=require("computer")
local function m(a)if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end;return
l.pullSignal(a or 0.5)end;local function k(a)local b=l.uptime()+a
while l.uptime()<b do m(b-l.uptime())end end
local function r()local x={}local a,B,b,C,h;local c,f;local u,i
do
local E,F=pcall(require,"kernel.i18n")if E then u=F end;local G,H=pcall(require,"kernel.ustr")if G then i=H end end
local function d(F,E,...)if u and u.t then return u.t(F,E,...)end;if select("#",...)>0 then
local G,H=pcall(string.format,E,...)if G then return H end end;return E end
local function g(E)if i then return i.width(E)end;return#tostring(E or"")end;local function v(E,F)if i then return i.fit(E,F)end
return tostring(E or""):sub(1,F)end
local function y(F,E)
local H=d("login.username","Username:")local I=d("login.password","Password:")
local G=math.max(g(H),g(I))local J=E-13;if G>J then G=J end;local K=F+2+G+1;local L=E- (2+G+1)-2
return H,I,G,K,L end
local function e(E,F)local I=a.getTheme()local H=I.bg;local Y=I.fg;local N=I.border;local P=I.title;local L=I.dim
a.clear(H)local G=2
local S=a.fit((_G._TOS and _G._TOS.version)or"?",9)local V,J=pcall(require,"kernel.logo")
if
V and J and J.MARK and f>=20 and c>= (J.MARK_W+2)then local _=
math.floor((c-J.MARK_W)/2)+1;for aa,ab in ipairs(J.MARK)do
a.set(_,G+aa-1,ab,P,H)end;G=G+#J.MARK
local Z=J.TAGLINE.."  v"..S
a.set(math.floor((c-#Z)/2)+1,G,Z,L,H)G=G+2 elseif f>=20 then
a.set(math.floor(c/2)-12,G,"========================",N,H)
a.set(math.floor(c/2)-12,G+1,"    T O S  Login        ",P,H)
a.set(math.floor(c/2)-12,G+2,"  Terminal OS v"..S,L,H)
a.set(math.floor(c/2)-12,G+3,"========================",N,H)G=G+5 else
a.set(math.floor(c/2)-8,G,"=== TOS Login ===",N,H)G=G+2 end;local O=math.min(40,c-4)local Q=8
local M=math.floor((c-O)/2)+1;local K=G+1;local R=I.panel_bg
a.dbox(M,K,O,Q,d("login.title","Authentication"),{bg=R,border=N,title=P})local W,X,T=y(M,O)a.set(M+2,K+2,v(W,T),L,R)
a.set(M+2,K+4,v(X,T),L,R)
if E then local Z=F and I.error or I.highlight
local _=math.floor((c-g(E))/2)a.set(math.max(1,_),K+Q+1,v(E,c-2),Z,H)end
if _G._TOS and _G._TOS.unsafeShutdown then
local Z=v(d("login.unsafe","! Last shutdown was unsafe (power loss) - data verified"),
c-2)local _=I.warning or I.error
local aa=math.floor((c-g(Z))/2)a.set(math.max(1,aa),K+Q+2,Z,_,H)end
local U=d("login.hint","Enter credentials (Ctrl+Q to cancel)")
a.set(math.max(1,math.floor((c-g(U))/2)),f-1,U,L,H)return M,K,O end
local function j(I,G,J,H,E,F)local K=a.getTheme()local M=(H==q)and(G+2)or(G+4)
local R,R,R,N,O=y(I,J)local P=F and K.input_bg or K.panel_bg
local Q=F and K.input_fg or K.dim;a.fill(N,M,O,1," ",Q,P)local L=E
if H==p then L=string.rep("*",#E)end;L=a.fit(L,O-1)a.set(N,M,L,Q,P)if F then
local S=N+math.min(#E,O-1)a.set(S,M,"_",K.highlight,P)end end
local function z(F,G,H,I,E)E=E or 20;local J=""
while true do j(F,G,H,I,J,true)local L,N,K,M=m(0.5)
if L==o then
if M==28 then return J elseif M==14 then if#J>0 then J=J:sub(1,
-2)end elseif K==17 then return nil elseif
K and K>=32 and K<127 and#J<E then J=J..string.char(K)end elseif L=="clipboard"then local O=K
if type(O)==n then J=J..O:sub(1,E-#J)end end end end
local function A(E,F)
E=(type(E)==n and E~="")and E or"root"F=type(F)==n and F or""local G=a.getTheme()local T=G.bg
local J=G.panel_bg;a.clear(T)local N=math.min(50,c-4)local R=12;local K=
math.floor((c-N)/2)+1
local H=math.floor((f-R)/2)+1
a.dbox(K,H,N,R,"First Boot Setup",{bg=J,border=G.title,title=G.title})a.set(K+2,H+2,"Welcome to TOS!",G.highlight,J)
a.set(K+2,H+
3,"Please set a new password for "..E..".",G.dim,J)a.set(K+2,H+5,"New password:",G.dim,J)
a.set(K+2,H+7,"Confirm:",G.dim,J)local L=K+16;local O=N-18;local I,M;local S=0
local function P(U)local V=l.uptime()
if not U and V<S then return false end;S=V+1;local W=b.getUser and b.getUser(E)return
W~=nil and not W.firstBoot end
local function Q()a.fill(K+2,H+9,N-4,2," ",G.dim,J)
a.set(K+2,H+9,("Set at another screen. Log in with it."):sub(1,
N-4),G.highlight,J)k(2)return false end
while true do a.fill(L,H+5,O,1," ",G.input_fg,G.input_bg)
a.set(L,H+5,"_",G.highlight,G.input_bg)I=""
while true do a.fill(L,H+5,O,1," ",G.input_fg,G.input_bg)
a.set(L,H+5,string.rep("*",
#I),G.input_fg,G.input_bg)a.set(L+#I,H+5,"_",G.highlight,G.input_bg)
local Y,Z,W,X=m(0.5)if P()then return Q()end;if Y==o then
if X==28 then break elseif X==14 then if#I>0 then I=I:sub(1,-2)end elseif
W and W>=32 and W<127 and#I<30 then I=I..string.char(W)end end end;M=""
while true do a.fill(L,H+7,O,1," ",G.input_fg,G.input_bg)
a.set(L,H+7,string.rep("*",
#M),G.input_fg,G.input_bg)a.set(L+#M,H+7,"_",G.highlight,G.input_bg)
local Y,Z,W,X=m(0.5)if P()then return Q()end;if Y==o then
if X==28 then break elseif X==14 then if#M>0 then M=M:sub(1,-2)end elseif
W and W>=32 and W<127 and#M<30 then M=M..string.char(W)end end end;local V=N-4
local function U(W,X)local Z,Y={},""
for _ in tostring(W):gmatch("%S+")do local aa=(Y=="")and _ or
(Y.." ".._)
if#aa<=V then Y=aa else if Y~=""then Z[#Z+1]=Y end;Y=
(#_<=V)and _ or _:sub(1,V)end end;if Y~=""then Z[#Z+1]=Y end
for _=0,1 do
a.fill(K+2,H+9+_,V,1," ",G.dim,J)if Z[_+1]then a.set(K+2,H+9+_,Z[_+1],X,J)end end end
if#I<6 then U("Password must be 6+ characters!",G.error)elseif I~=M then
U("Passwords don't match! Try again.",G.error)elseif P(true)then return Q()else local W,X=b.changePassword(E,E,F,I)
if W then
U("Password set! Starting TOS...",G.highlight)k(1.5)return true else local Y=tostring(X)
if Y:lower():find("read%-only")or
_G._TOS_ROOT_READONLY then
U("Disk is READ-ONLY — install to a writable drive (install.lua).",G.error)k(4)else U("Error: "..Y,G.error)end end end;a.fill(L,H+5,O,1," ",G.input_fg,J)
a.fill(L,H+7,O,1," ",G.input_fg,J)k(1.5)end end
local function D(E,F,G)local H=a.getTheme()
local I=d("login.guest","F2: Guest access")local J=E+math.floor((G-g(I))/2)a.set(math.max(1,J),
F+9,I,H.dim,H.bg)end
local function w(E)
local F=(_G._TOS and _G._TOS.securefs)or nil
if not F then pcall(function()F=require(t)end)end;if not F then return end;local G=nil;if b and b.getSession and E then
G=b.getSession(E)end
local I,H=pcall(require,"shell.tutorial")if I and H.shouldShow(F,G)then
H.run({D=a,F=F,U=b,st=E,W=c,H=f})end end
function x.run(E)a=E.display;B=E.event;b=E.users;C=E.proc;h=E.log;c,f=a.getSize()
local J=b.getUser("root")
if J and J.firstBoot then
local N=b.login("root","root",{setCurrent=false})
if N then local O=A("root","root")
if O then
if b.promoteAfterFirstBoot then
local P,Q=b.promoteAfterFirstBoot(N)if not P and h then
h.warn("auth","First-boot promotion refused: "..tostring(Q))end else local P=b.getSession(N)if P then
P.firstBoot=nil end end;w(N)return N end;if b.logout then pcall(b.logout,N)end end end
local K=b.guestEnabled and b.guestEnabled()or false;local G={2,5,15,60}local I="/var/lib/login_backoff.dat"local F={}local H={}
do
local O,N=pcall(require,t)local P,Q=pcall(require,"kernel.serialize")
if
O and P and N.exists(I)then local R=N.readFile(I)
if R then
local T,S=pcall(Q.decode,R,{maxBytes=8192})
if
T and type(S)=="table"and type(S.fails)=="table"then
for V,U in pairs(S.fails)do if
type(V)==n and type(U)=="number"and U>=0 then F[V]=math.floor(U)end end;if type(S.lastFailTs)=="table"then
for U,d in pairs(S.lastFailTs)do if type(U)==n and
type(d)=="number"then H[U]=d end end end end end end end
local function L()local O,N=pcall(require,t)
local P,Q=pcall(require,"kernel.serialize")if not(O and P)then return end;if not N.exists("/var/lib")then
pcall(N.makeDirectory,"/var/lib")end
pcall(N.writeFile,I,Q.encode({fails=F,lastFailTs=H}))end
local function M(N)local O=F[N]or 0;return G[math.min(O,#G)]or G[#G]end
while true do local P,Q,R=e()if K then D(P,Q,R)end;j(P,Q,R,p,"",false)local N=nil;local S=false
local T=false;local O=""
while true do j(P,Q,R,q,O,true)local W,X,U,V=m(0.5)
if W==o then
if V==28 then N=O;break elseif V==14 then if#O>0 then
O=O:sub(1,-2)end elseif U==17 then T=true;break elseif V==60 and K then S=true;break elseif
U and U>=32 and U<127 and#O<20 then O=O..string.char(U)end elseif W=="clipboard"then
if type(U)==n then O=O..U:sub(1,20-#O)end end end
if S then
e(d("login.guest_auth","Logging in as Guest..."),false)local U,V=b.guestLogin()
if U then local W=b.getSession(U)
e(d("login.welcome_guest","Welcome, Guest!"),false)
if _G._TOS and _G._TOS.audio then _G._TOS.audio.confirm()end;k(1)w(U)return U else e(V or"Guest login failed",true)
if
_G._TOS and _G._TOS.audio then _G._TOS.audio.error()end;k(2)end elseif T then
e(d("login.retry","Enter to retry, F10 to shut down"),false)
while true do local V,W,W,U=m(1)if V==o then
if U==28 then break elseif U==68 then return nil,"shutdown"end end end elseif N==""then j(P,Q,R,q,N,false)local V=z(P,Q,R,p,30)
local W,U=pcall(require,"shell.colophon")
if W and U and U.isTrigger(N,V)then
pcall(U.run,{W=c,H=f,theme=a.getTheme(),clear=function(X)a.clear(X)end,set=function(X,Y,Z,_,aa)
a.set(X,Y,Z,_,aa)end,pull=function(X)return(m(X))end,sleep=k,uptime=l.uptime,width=g})end elseif N and N~=""then j(P,Q,R,q,N,false)local U=z(P,Q,R,p,30)
if U then
e(d("login.authenticating","Authenticating..."),false)local V,W=b.login(N,U,{setCurrent=false})
if V then F[N]=0;H[N]=nil;L()
local X=b.getSession(V)
if not X then
e(d("login.session_error","Session error - please retry"),true)k(2)else
local Y=d("login.welcome","Welcome, %s!",X.displayName or N)e(Y,false)if _G._TOS and _G._TOS.audio then
_G._TOS.audio.confirm()end;k(1)if X.firstBoot then A(N,U)end;w(V)return V end else F[N]=(F[N]or 0)+1;H[N]=l.uptime()L()local X=M(N)
local Y=(W or
d("login.failed","Login failed")).. (
X>2 and d("login.wait"," — wait %ds",X)or"")e(Y,true)if _G._TOS and _G._TOS.audio then
_G._TOS.audio.error()end;if h and h.warn then
h.warn("auth",string.format("Failed login for %q (consecutive %d, backoff %ds)",N,F[N],X))end;k(X)end end end end end;return x end;local s=r()s.new=r;return s