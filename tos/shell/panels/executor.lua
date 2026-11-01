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
local function k(B,C,D,A,E)
local O,F=pcall(require,r)
if not O or type(F)~="table"or not F.spawn then return false end;local H=a.displayIdx;if not H then return false end
local M=F.current and F.current()local K=M and M.pid;if not K then return false end;local P,G=pcall(require,w)G=
P and G or nil;local L=false
if A and G and G.fitDisplay then
local S=A.mode=="min"and(a.W or 0)>=
A.width and(a.H or 0)>=A.height;if not S then
local T=G.fitDisplay(H,{mode="size",w=A.width,h=A.height})L=T~=nil end end;local J={}
local function Q(S,T)J[#J+1]={tostring(S),T or c.fg}end;local I
I=F.spawn("prog:"..B.."@"..H,function()local U,V=pcall(C,D,Q)if not U then
J[#J+1]={u..tostring(V),c.error}end
if L and G and G.restore then pcall(G.restore,H)end
if a._program and a._program.pid==I then a._program=nil end;local W,S=pcall(require,"shell.panels.tabs")if W and S then
for Y,X in
ipairs(a.tabs or{})do if X.type=="program"and X.pid==I then X.pid=nil;pcall(S.close,a,Y)
break end end end;if a.D and
a.D.invalidate then pcall(a.D.invalidate)end;if#J>0 then
a.outLines=n.expandBuf(a,J)end;local T=F.get and F.get(K)if T and
T.state~=F.STATE.DEAD then
F.setForeground(K,H,{kernel=true});(F.signalKernel or
F.signal)(K,"tos_focus")end end,{priority=3,source="user",principal=
n.sessionOf and n.sessionOf(a)or nil,token=a.st,display=H,background=E})if not I then if L and G and G.restore then pcall(G.restore,H)end;return
false end
a._program={pid=I,name=B,seat=H}local R,N=pcall(require,"shell.panels.tabs")if R and N then
pcall(N.create,a,"program",B,{pid=I,seat=H,prog=B,live=true})end;a.suspendIdleDraw=true;if
a.D and a.D.invalidate then pcall(a.D.invalidate)end
F.setForeground(I,H,{kernel=true})return true end
local function e(B,A,C)
do local R,O=pcall(require,"kernel.env")local S,Q=pcall(require,r)
if R and
type(O)=="table"and O.read then
local P=S and type(Q)=="table"and
Q.current and Q.current()or nil;B=z(B,function(T)return O.read(P,T)end)end end;local G=t(B)if#G==0 then return""end;G=n.expandAlias(a,G)
if#G==0 then return""end;local D=G[1]:lower()
if C and D~="watch"then
for O=2,#G do if G[O]=="--live"or
(G[O]=="-f"and s[D])then table.remove(G,O)
table.insert(G,1,"watch")D="watch"break end end end;a.curCmd=D;if D~="why"then n.clearFailure(a)end;local F={}for O=2,#G do
F[#F+1]=G[O]end;a._plainPath=C;local I={}local function E(O,P)
I[#I+1]={tostring(O),P or c.fg}
if P==c.error and D~="why"then n.noteFailure(a,D,O)end;q()end
if A and#A>0 then
if
D=="cat"and#F==0 then
for O in(A.."\n"):gmatch("(.-)\n")do E(O,c.fg)end;return I elseif D=="grep"and#F>=1 and
(not F[2]or(F[1]=="-i"and not F[3]))then local O=F[1]=="-i"
local P=O and F[2]:lower()or F[1]
for Q in A:gmatch("([^\n]*)\n?")do if
(O and Q:lower()or Q):find(P,1,true)then E(Q,c.fg)end end;return I elseif D=="wc"and#F==0 then local O,P,Q=0,0,#A;for R in A:gmatch("\n")do O=O+1 end;if
A:sub(-1)~="\n"then O=O+1 end;for R in A:gmatch("%S+")do P=P+1 end
E(string.format(" %d lines  %d words  %d bytes",O,P,Q),c.fg)return I elseif D=="head"or D=="tail"then local O,P=10,false;for R,Q in ipairs(F)do
if Q=="-n"then O=
tonumber(F[R+1])or O elseif Q:match("^%-%d+$")then O=tonumber(Q:sub(2))elseif
F[R-1]~="-n"then P=true end end
if not
P then local Q={}
for S in(A.."\n"):gmatch("(.-)\n")do Q[#Q+1]=S end
local R=D=="head"and 1 or math.max(1,#Q-O+1)for S=R,math.min(#Q,R+O-1)do E(Q[S],c.fg)end;return I end end end;local H=j[D]
if H then local R,P=pcall(require,"shell.panels.commands")local Q=
R and
type(P)=="table"and P.entry and P.entry(D)or nil;local O=Q and
tonumber(Q.tier)or 0
if O>0 then local S=
n.liveTier and n.liveTier(a)or 0
if S<O then
local T="Permission denied: '"..
D.."' needs "..
(
n.tierName and n.tierName(O)or("tier "..O)).."  [E-403 ERR_TIER_REQUIRED]"if n.fail then n.fail(a,T,E)else E(T,c.error)end
a.lastDenial={cmd=D,need=O,have=S}return I end end end;local J=nil;local K=false;local L,M=false,"drowsy"
if not H then local P,O=false,nil;if n.mayHavePackages()then
P,O=pcall(require,v)end
if P and O and O.getCommand then H=O.getCommand(D)
K=H~=nil
if H and O.getCommandScreen then J=O.getCommandScreen(D)end
if H and O.getCommandFullscreen then L=O.getCommandFullscreen(D)if
O.getCommandBackground then M=O.getCommandBackground(D)end end end end;if H and L and C then if k(D,H,F,J,M)then return{}end end
local function N()if a.D and
a.D.invalidate then pcall(a.D.invalidate)end end
if H then local P=false
if J then
local T=J.mode=="min"and(a.W or 0)>=J.width and
(a.H or 0)>=J.height
if not T then local V,U=pcall(require,w)
if V and U and U.fitDisplay then
local X,Y,W=U.fitDisplay(a.displayIdx,{mode="size",w=J.width,h=J.height})if X then P=true end;if W then E(W,c.warning)end end end end;local Q,O=E,nil
if K and a._plainPath and a.programIO then local U,V=a.programIO(E)
Q=U;local W,T=pcall(require,r)
O=
W and type(T)=="table"and T.current and T.current()or nil;if O then O.beforeRead=V end end;local R,S=pcall(H,F,Q)if O then O.beforeRead=nil end;if not R then
E(u..tostring(S),c.error)end;if K then N()end
if P then local V,T=pcall(require,w)if
V and T and T.restore then pcall(T.restore,a.displayIdx)end
local W,U=pcall(require,"shell.panels.state")
if W and U and U.recomputeLayout then pcall(U.recomputeLayout,a)end end else local O=n.resolveProgram(d,D)
if O then
local P=n.safeModeRefusal and n.safeModeRefusal(O)
if P then if n.fail then n.fail(a,P,E)else E(P,c.error)end;return I end;local Q=d.readFile(O)
if Q then local S,T=nil,nil;local U,R=false,nil;if n.mayHavePackages()then
U,R=pcall(require,v)end;if
U and type(R)=="table"and R.capsForFile then S,T=R.capsForFile(O)end
local X,Y=a.programIO(E)
local V=i{name=O,pkgName=T,caps=S,stdout=X,beforeRead=Y}local W,Z=load(Q,"="..O,"t",V)if W then
local _,aa=pcall(W,table.unpack(F))n.reportProgramEnd(a,E,_,aa,u,V)N()else
E("Compile error: "..tostring(Z),c.error)end end else local S,Q=pcall(require,"shell.panels.commands")local R=S and Q.entry and
Q.entry(D)or nil;local P=nil;if not R and
n.mayHavePackages()then local U,T=pcall(require,v)
if U and type(T)=="table"and
T.commandFailure then P=T.commandFailure(D)end end
if P then
E("'"..D..
"' is installed but could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)E(tostring(P),c.error)
E("Free some memory (close tabs, or reboot) and try again.",c.dim)elseif R then
E("'"..D.."' could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)
if a.lastOut and a.lastOut[1]then E(a.lastOut[1],c.error)
a.lastOut=nil else
E("Its command group failed to load — check `log` for the reason.",c.dim)end
E("Free some memory (close tabs, or reboot) and try again.",c.dim)else
E("Unknown command: "..D.."  [E-801 ERR_UNKNOWN_CMD]",c.error)E("Type 'help' for available commands.",c.dim)end
if _G._TOS.audio then _G._TOS.audio.warning()end end end;return I end;local l=8
local g=b.showOutput or
function(A,B)a.lastOut=nil;a.outLines=nil;local C=n.routeOutput(#A,l)
if
C=="status"then a.lastOut=A[1]elseif C=="inline"then a.outLines=A elseif C=="tab"then local D=y()if D then
D.openViewTab(a,A,B or x,true)else a.outLines=A end end end;local function h(A)local B=a.lastOut
if type(B)=="table"and B[1]then A[#A+1]=B;a.lastOut=nil end;return A end
function a.programIO(A)
local B=a._plainPath;local C=B and b.liveLine or nil
local D=B and b.echoLine or nil;local function E(G,H)
if C then C(G,H)q()else A(G,H or a.T.fg)if D then D(G)end end end;local F=nil
if B and b.inputRow then
F=function(G)
if G~=""then E(G)end;local I,H=pcall(require,"compat.term")if I and type(H)=="table"then
H.setCursor(1,b.inputRow())end end end;return E,F end
local function m(A)a.lastOut=nil;local C=A:find("|",1,true)
local D=A:find("[>]")or A:find("<")
if C or D then local G,H=pcall(require,"kernel.pipe")
if G then local J=H.parse(A)
local I=nil;local K={}
for M,L in ipairs(J)do
if L.stdin and L.stdin.type=="file"then
local P=f(L.stdin.path)if not n.canRead(a,P)then
a.lastOut={"Cannot read: "..L.stdin.path,c.error}return end;I=
d.exists(P)and d.readFile(P)or nil;if not I then
a.lastOut={"No such file: "..L.stdin.path,c.error}return end;I=I:gsub("\n$","")end;local O=e(L.cmd,I)local N={}
for Q,P in ipairs(O)do N[#N+1]=type(P)=="table"and P[1]or
tostring(P)end;I=table.concat(N,"\n")
if
L.stdout and L.stdout.type=="file"then local P=f(L.stdout.path)
if n.canWrite(a,P)then local Q,R
if L.stdout.append then
Q,R=d.appendFile(P,I.."\n")else Q,R=d.writeFile(P,I.."\n")end;n.refreshBrowser(a)if Q then
a.lastOut={"Output written to "..L.stdout.path,c.highlight}else
a.lastOut={"Not written: "..tostring(R or L.stdout.path),c.error}end end;return end;if M==#J then K=O end end;g(n.expandBuf(a,h(K)),x)return end end;local E=a._program;local F=e(A,nil,true)
if a._program and a._program~=E then return end;local B=package.loaded["compat.term"]
if
b.repaint and B and B._screenTaken and B._screenTaken()then b.repaint()end
g(n.expandBuf(a,h(F)),A:match("^(%S+)")or x)end;a.execOne=e;return m end;return o