local u,v,r,w,x="Error: ","kernel.pkg","kernel.process","kernel.screen","output"
local n=require("shell.panels.helpers")local p=nil
local function y()if p==nil then local a,b=pcall(require,"shell.panels.editor")p=a and b or
false end;return p or nil end;local q=function()end
do local b,a=pcall(require,r)if b and a and a.yieldCooperative then
q=a.yieldCooperative end end;local o={}
local s={ps=true,df=true,mem=true,uptime=true,log=true,net=true,battery=true,lsdev=true}o.LIVE_SHORT=s
local function z(a,b)if not a:find("$",1,true)then return a end
local d,c,f,e={},1,#a,false
while c<=f do local h=a:sub(c,c)if h=="'"then e=not e end;local g,i
if h=="$"and not e then
g=a:match("^%$([%a_][%w_]*)",c)if g then i=c+#g else g=a:match("^%${([%a_][%w_]*)}",c)
if g then i=c+#g+2 end end end;local j=g and b(g)
if j~=nil then d[#d+1]=tostring(j)c=i+1 else d[#d+1]=h;c=c+1 end end;return table.concat(d)end
local function t(a)local f,c={},nil;local b,d=1,#a;local function e(h,i)
if i>=h then c=c or{}c[#c+1]=a:sub(h,i)end end;local function g()
if c then f[#f+1]=table.concat(c)c=nil end end
while b<=d do local h=a:sub(b,b)
if h==" "or h=="\t"then
g()b=b+1 elseif h=="'"then c=c or{}b=b+1;local i=a:find("'",b,true)if i then e(b,i-1)b=i+1 else
e(b,d)b=d+1 end elseif h=='"'then c=c or{}b=b+1;local i=b;while
b<=d and a:sub(b,b)~='"'do
if a:sub(b,b)=='\\'and b<d then e(i,b-1)e(b+1,b+1)b=b+2;i=b else b=b+1 end end;e(i,b-1)if b<=d then
b=b+1 end elseif h=='\\'and b<d then c=c or{}e(b+1,b+1)b=b+2 else c=c or{}local i=b
b=b+1
while b<=d do local j=a:sub(b,b)if
j==" "or j=="\t"or j=="'"or j=='"'or j=="\\"then break end;b=b+1 end;e(i,b-1)end end;g()return f end;o._tokenize=t
function o.build(a,b)local d=a.F;local c=a.T;local f=b.rp;local i=b.makeProgramEnv;local j=b.C
local function k(C,D,E,B,F)
local P,G=pcall(require,r)
if not P or type(G)~="table"or not G.spawn then return false end;local I=a.displayIdx;if not I then return false end
local N=G.current and G.current()local L=N and N.pid;if not L then return false end;local Q,H=pcall(require,w)H=
Q and H or nil;local M=false
if B and H and H.fitDisplay then
local T=B.mode=="min"and(a.W or 0)>=
B.width and(a.H or 0)>=B.height;if not T then
local U=H.fitDisplay(I,{mode="size",w=B.width,h=B.height})M=U~=nil end end;local K={}
local function R(T,U)K[#K+1]={tostring(T),U or c.fg}end;local J
J=G.spawn("prog:"..C.."@"..I,function()local V,W=pcall(D,E,R)if not V then
K[#K+1]={u..tostring(W),c.error}end
if M and H and H.restore then pcall(H.restore,I)end
if a._program and a._program.pid==J then a._program=nil end;local X,T=pcall(require,"shell.panels.tabs")if X and T then
for Z,Y in
ipairs(a.tabs or{})do if Y.type=="program"and Y.pid==J then Y.pid=nil;pcall(T.close,a,Z)
break end end end;if a.D and
a.D.invalidate then pcall(a.D.invalidate)end;if#K>0 then
a.outLines=n.expandBuf(a,K)end;local U=G.get and G.get(L)if U and
U.state~=G.STATE.DEAD then
G.setForeground(L,I,{kernel=true});(G.signalKernel or
G.signal)(L,"tos_focus")end end,{priority=3,source="user",principal=
n.sessionOf and n.sessionOf(a)or nil,token=a.st,display=I,background=F})if not J then if M and H and H.restore then pcall(H.restore,I)end;return
false end
a._program={pid=J,name=C,seat=I}local S,O=pcall(require,"shell.panels.tabs")if S and O then
pcall(O.create,a,"program",C,{pid=J,seat=I,prog=C,live=true})end;a.suspendIdleDraw=true;if
a.D and a.D.invalidate then pcall(a.D.invalidate)end
G.setForeground(J,I,{kernel=true})return true end
local function e(C,B,D)
do local S,Q=pcall(require,"kernel.env")local T,R=pcall(require,r)
if S and
type(Q)=="table"and Q.read then
local P=T and type(R)=="table"and
R.current and R.current()or nil;C=z(C,function(U)return Q.read(P,U)end)end end;local H=t(C)if#H==0 then return""end;H=n.expandAlias(a,H)
if#H==0 then return""end;local E=H[1]:lower()
if D and E~="watch"then
for P=2,#H do if H[P]=="--live"or
(H[P]=="-f"and s[E])then table.remove(H,P)
table.insert(H,1,"watch")E="watch"break end end end;a.curCmd=E;if E~="why"then n.clearFailure(a)end;local G={}for P=2,#H do
G[#G+1]=H[P]end;a._plainPath=D;local J={}local function F(P,Q)
J[#J+1]={tostring(P),Q or c.fg}
if Q==c.error and E~="why"then n.noteFailure(a,E,P)end;q()end
if B and#B>0 then
if
E=="cat"and#G==0 then
for P in(B.."\n"):gmatch("(.-)\n")do F(P,c.fg)end;return J elseif E=="grep"and#G>=1 and
(not G[2]or(G[1]=="-i"and not G[3]))then local P=G[1]=="-i"
local Q=P and G[2]:lower()or G[1]
for R in B:gmatch("([^\n]*)\n?")do if
(P and R:lower()or R):find(Q,1,true)then F(R,c.fg)end end;return J elseif E=="wc"and#G==0 then local P,Q,R=0,0,#B;for S in B:gmatch("\n")do P=P+1 end;if
B:sub(-1)~="\n"then P=P+1 end;for S in B:gmatch("%S+")do Q=Q+1 end
F(string.format(" %d lines  %d words  %d bytes",P,Q,R),c.fg)return J elseif E=="head"or E=="tail"then local P,Q=10,false;for S,R in ipairs(G)do
if R=="-n"then P=
tonumber(G[S+1])or P elseif R:match("^%-%d+$")then P=tonumber(R:sub(2))elseif
G[S-1]~="-n"then Q=true end end
if not
Q then local R={}
for T in(B.."\n"):gmatch("(.-)\n")do R[#R+1]=T end
local S=E=="head"and 1 or math.max(1,#R-P+1)for T=S,math.min(#R,S+P-1)do F(R[T],c.fg)end;return J end end end;local I=j[E]
if I then local S,Q=pcall(require,"shell.panels.commands")local R=
S and
type(Q)=="table"and Q.entry and Q.entry(E)or nil;local P=R and
tonumber(R.tier)or 0
if P>0 then local T=
n.liveTier and n.liveTier(a)or 0
if T<P then
local U="Permission denied: '"..
E.."' needs "..
(
n.tierName and n.tierName(P)or("tier "..P)).."  [E-403 ERR_TIER_REQUIRED]"if n.fail then n.fail(a,U,F)else F(U,c.error)end
a.lastDenial={cmd=E,need=P,have=T}return J end end end;local K=nil;local L=false;local M,N=false,"drowsy"
if not I then local Q,P=false,nil;if n.mayHavePackages()then
Q,P=pcall(require,v)end
if Q and P and P.getCommand then I=P.getCommand(E)
L=I~=nil
if I and P.getCommandScreen then K=P.getCommandScreen(E)end
if I and P.getCommandFullscreen then M=P.getCommandFullscreen(E)if
P.getCommandBackground then N=P.getCommandBackground(E)end end end end;if I and M and D then if k(E,I,G,K,N)then return{}end end
local function O()if a.D and
a.D.invalidate then pcall(a.D.invalidate)end end
if I then local Q=false
if K then
local U=K.mode=="min"and(a.W or 0)>=K.width and
(a.H or 0)>=K.height
if not U then local W,V=pcall(require,w)
if W and V and V.fitDisplay then
local Y,Z,X=V.fitDisplay(a.displayIdx,{mode="size",w=K.width,h=K.height})if Y then Q=true end;if X then F(X,c.warning)end end end end;local R,P=F,nil
if a._plainPath and a.programIO then local U,V=a.programIO(F)R=U;if L then
local X,W=pcall(require,r)P=
X and type(W)=="table"and W.current and W.current()or nil
if P then P.beforeRead=V end end end;local S,T=pcall(I,G,R)if P then P.beforeRead=nil end;if not S then
F(u..tostring(T),c.error)end;if L then O()end
if Q then local W,U=pcall(require,w)if
W and U and U.restore then pcall(U.restore,a.displayIdx)end
local X,V=pcall(require,"shell.panels.state")
if X and V and V.recomputeLayout then pcall(V.recomputeLayout,a)end end else local P=n.resolveProgram(d,E)
if P then
local Q=n.safeModeRefusal and n.safeModeRefusal(P)
if Q then if n.fail then n.fail(a,Q,F)else F(Q,c.error)end;return J end;local R=d.readFile(P)
if R then local T,U=nil,nil;local V,S=false,nil;if n.mayHavePackages()then
V,S=pcall(require,v)end;if
V and type(S)=="table"and S.capsForFile then T,U=S.capsForFile(P)end
local Y,Z=a.programIO(F)
local W=i{name=P,pkgName=U,caps=T,stdout=Y,beforeRead=Z}local X,_=load(R,"="..P,"t",W)if X then
local aa,ab=pcall(X,table.unpack(G))n.reportProgramEnd(a,F,aa,ab,u,W)O()else
F("Compile error: "..tostring(_),c.error)end end else local T,R=pcall(require,"shell.panels.commands")local S=T and R.entry and
R.entry(E)or nil;local Q=nil;if not S and
n.mayHavePackages()then local V,U=pcall(require,v)
if V and type(U)=="table"and
U.commandFailure then Q=U.commandFailure(E)end end
if Q then
F("'"..E..
"' is installed but could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)F(tostring(Q),c.error)
F("Free some memory (close tabs, or reboot) and try again.",c.dim)elseif S then
F("'"..E.."' could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)
if a.lastOut and a.lastOut[1]then F(a.lastOut[1],c.error)
a.lastOut=nil else
F("Its command group failed to load — check `log` for the reason.",c.dim)end
F("Free some memory (close tabs, or reboot) and try again.",c.dim)else
F("Unknown command: "..E.."  [E-801 ERR_UNKNOWN_CMD]",c.error)F("Type 'help' for available commands.",c.dim)end
if _G._TOS.audio then _G._TOS.audio.warning()end end end;return J end;local l=8
local g=b.showOutput or
function(B,C)a.lastOut=nil;a.outLines=nil;local D=n.routeOutput(#B,l)
if
D=="status"then a.lastOut=B[1]elseif D=="inline"then a.outLines=B elseif D=="tab"then local E=y()if E then
E.openViewTab(a,B,C or x,true)else a.outLines=B end end end;local function h(B)local C=a.lastOut
if type(C)=="table"and C[1]then B[#B+1]=C;a.lastOut=nil end;return B end
function a.programIO(B)
local C=a._plainPath;local D=C and b.liveLine or nil
local E=C and b.echoLine or nil;local J,F=pcall(require,"computer")local K=
J and type(F)=="table"and F.uptime or os.clock;local G=-1;local function H(L,M,N)
if D then D(L,M)q()else B(L,
M or a.T.fg)if E then local O=K()
if N or O-G>=0.25 then G=O;E(L)end end end end;local I=nil
if C and
b.inputRow then
I=function(L)if L~=""then H(L,nil,true)end
local N,M=pcall(require,"compat.term")
if N and type(M)=="table"then M.setCursor(1,b.inputRow())end end end;return H,I end
local function m(B)local C=nil
for D=1,#B-1 do local E=B:sub(D,D)
if C then if E==C then C=nil end elseif E=='"'or E=="'"then C=E else
local F=B:sub(D,D+1)if F=="&&"or F=="||"then return F end end end;return nil end
local function A(B)a.lastOut=nil;local D=m(B)if D then
a.lastOut={"TOS runs one command per line, and has no "..
D..". Type the commands one at a time.",c.error}return end
local E=B:find("|",1,true)local F=B:find("[>]")or B:find("<")
if E or F then
local I,J=pcall(require,"kernel.pipe")
if I then local L=J.parse(B)local K=nil;local M={}
for O,N in ipairs(L)do
if
N.stdin and N.stdin.type=="file"then local R=f(N.stdin.path)if not n.canRead(a,R)then
a.lastOut={"Cannot read: "..N.stdin.path,c.error}return end;K=
d.exists(R)and d.readFile(R)or nil;if not K then
a.lastOut={"No such file: "..N.stdin.path,c.error}return end;K=K:gsub("\n$","")end;local Q=e(N.cmd,K)local P={}
for S,R in ipairs(Q)do P[#P+1]=type(R)=="table"and R[1]or
tostring(R)end;K=table.concat(P,"\n")
if
N.stdout and N.stdout.type=="file"then local R=f(N.stdout.path)
if n.canWrite(a,R)then local S,T
if N.stdout.append then
S,T=d.appendFile(R,K.."\n")else S,T=d.writeFile(R,K.."\n")end;n.refreshBrowser(a)if S then
a.lastOut={"Output written to "..N.stdout.path,c.highlight}else
a.lastOut={"Not written: "..tostring(T or N.stdout.path),c.error}end end;return end;if O==#L then M=Q end end;g(n.expandBuf(a,h(M)),x)return end end;local G=a._program;local H=e(B,nil,true)
if a._program and a._program~=G then return end;local C=package.loaded["compat.term"]
if
b.repaint and C and C._screenTaken and C._screenTaken()then b.repaint()end
g(n.expandBuf(a,h(H)),B:match("^(%S+)")or x)end;a.execOne=e;return A end;return o