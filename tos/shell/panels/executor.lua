local r,s,t,u="Error: ","kernel.pkg","kernel.screen","output"
local l=require("shell.panels.helpers")local n=nil
local function v()if n==nil then local a,b=pcall(require,"shell.panels.editor")n=a and b or
false end;return n or nil end;local o=function()end
do local b,a=pcall(require,"kernel.process")if b and a and
a.yieldCooperative then o=a.yieldCooperative end end;local m={}
local p={ps=true,df=true,mem=true,uptime=true,log=true,net=true,battery=true,lsdev=true}m.LIVE_SHORT=p
local function q(a)local f,c={},nil;local b,d=1,#a;local function e(h,i)
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
j==" "or j=="\t"or j=="'"or j=='"'or j=="\\"then break end;b=b+1 end;e(i,b-1)end end;g()return f end;m._tokenize=q
function m.build(a,b)local d=a.F;local c=a.T;local h=b.rp;local i=b.makeProgramEnv;local j=b.C
local function k(z,A,B,y,C)
local M,D=pcall(require,"kernel.process")
if not M or type(D)~="table"or not D.spawn then return false end;local F=a.displayIdx;if not F then return false end
local K=D.current and D.current()local I=K and K.pid;if not I then return false end;local N,E=pcall(require,t)E=
N and E or nil;local J=false
if y and E and E.fitDisplay then
local Q=y.mode=="min"and(a.W or 0)>=
y.width and(a.H or 0)>=y.height;if not Q then
local R=E.fitDisplay(F,{mode="size",w=y.width,h=y.height})J=R~=nil end end;local H={}
local function O(Q,R)H[#H+1]={tostring(Q),R or c.fg}end;local G
G=D.spawn("prog:"..z.."@"..F,function()local S,T=pcall(A,B,O)if not S then
H[#H+1]={r..tostring(T),c.error}end
if J and E and E.restore then pcall(E.restore,F)end
if a._program and a._program.pid==G then a._program=nil end;local U,Q=pcall(require,"shell.panels.tabs")if U and Q then
for W,V in
ipairs(a.tabs or{})do if V.type=="program"and V.pid==G then V.pid=nil;pcall(Q.close,a,W)
break end end end;if a.D and
a.D.invalidate then pcall(a.D.invalidate)end;if#H>0 then
a.outLines=l.expandBuf(a,H)end;local R=D.get and D.get(I)if R and
R.state~=D.STATE.DEAD then
D.setForeground(I,F,{kernel=true});(D.signalKernel or
D.signal)(I,"tos_focus")end end,{priority=3,source="user",principal=
l.sessionOf and l.sessionOf(a)or nil,token=a.st,display=F,background=C})if not G then if J and E and E.restore then pcall(E.restore,F)end;return
false end
a._program={pid=G,name=z,seat=F}local P,L=pcall(require,"shell.panels.tabs")if P and L then
pcall(L.create,a,"program",z,{pid=G,seat=F,prog=z,live=true})end;a.suspendIdleDraw=true;if
a.D and a.D.invalidate then pcall(a.D.invalidate)end
D.setForeground(G,F,{kernel=true})return true end
local function e(A,y,z)local D=q(A)if#D==0 then return""end;D=l.expandAlias(a,D)
if#D==0 then return""end;local B=D[1]:lower()
if z and B~="watch"then
for M=2,#D do if D[M]=="--live"or
(D[M]=="-f"and p[B])then table.remove(D,M)
table.insert(D,1,"watch")B="watch"break end end end;a.curCmd=B;if B~="why"then l.clearFailure(a)end;local E={}for M=2,#D do
E[#E+1]=D[M]end;local G={}local function C(M,N)G[#G+1]={tostring(M),N or c.fg}
if N==
c.error and B~="why"then l.noteFailure(a,B,M)end;o()end
if y and#y>0 then
if
B=="grep"and#E>=1 and not E[2]then local M=E[1]for N in y:gmatch("([^\n]*)\n?")do if
N:find(M,1,true)then C(N,c.fg)end end;return G elseif
B=="wc"and#E==0 then local M,N,O=0,0,#y;for P in y:gmatch("\n")do M=M+1 end;if
y:sub(-1)~="\n"then M=M+1 end;for P in y:gmatch("%S+")do N=N+1 end
C(string.format(" %d lines  %d words  %d bytes",M,N,O),c.fg)return G elseif B=="head"or B=="tail"then local M,N=10,false;for P,O in ipairs(E)do
if O=="-n"then M=
tonumber(E[P+1])or M elseif O:match("^%-%d+$")then M=tonumber(O:sub(2))elseif
E[P-1]~="-n"then N=true end end
if not
N then local O={}
for Q in(y.."\n"):gmatch("(.-)\n")do O[#O+1]=Q end
local P=B=="head"and 1 or math.max(1,#O-M+1)for Q=P,math.min(#O,P+M-1)do C(O[Q],c.fg)end;return G end end end;local F=j[B]
if F then local P,N=pcall(require,"shell.panels.commands")local O=
P and
type(N)=="table"and N.entry and N.entry(B)or nil;local M=O and
tonumber(O.tier)or 0
if M>0 then local Q=
l.liveTier and l.liveTier(a)or 0
if Q<M then
local R="Permission denied: '"..
B.."' needs "..
(
l.tierName and l.tierName(M)or("tier "..M)).."  [E-403 ERR_TIER_REQUIRED]"if l.fail then l.fail(a,R,C)else C(R,c.error)end
a.lastDenial={cmd=B,need=M,have=Q}return G end end end;local H=nil;local I=false;local J,K=false,"drowsy"
if not F then local N,M=false,nil;if l.mayHavePackages()then
N,M=pcall(require,s)end
if N and M and M.getCommand then F=M.getCommand(B)
I=F~=nil
if F and M.getCommandScreen then H=M.getCommandScreen(B)end
if F and M.getCommandFullscreen then J=M.getCommandFullscreen(B)if
M.getCommandBackground then K=M.getCommandBackground(B)end end end end;if F and J and z then if k(B,F,E,H,K)then return{}end end
local function L()if a.D and
a.D.invalidate then pcall(a.D.invalidate)end end
if F then local M=false
if H then
local P=H.mode=="min"and(a.W or 0)>=H.width and
(a.H or 0)>=H.height
if not P then local R,Q=pcall(require,t)
if R and Q and Q.fitDisplay then
local T,U,S=Q.fitDisplay(a.displayIdx,{mode="size",w=H.width,h=H.height})if T then M=true end;if S then C(S,c.warning)end end end end;local N,O=pcall(F,E,C)
if not N then C(r..tostring(O),c.error)end;if I then L()end
if M then local R,P=pcall(require,t)if R and P and P.restore then
pcall(P.restore,a.displayIdx)end
local S,Q=pcall(require,"shell.panels.state")
if S and Q and Q.recomputeLayout then pcall(Q.recomputeLayout,a)end end else local M=l.resolveProgram(d,B)
if M then
local N=l.safeModeRefusal and l.safeModeRefusal(M)
if N then if l.fail then l.fail(a,N,C)else C(N,c.error)end;return G end;local O=d.readFile(M)
if O then local Q,R=nil,nil;local S,P=false,nil;if l.mayHavePackages()then
S,P=pcall(require,s)end;if
S and type(P)=="table"and P.capsForFile then Q,R=P.capsForFile(M)end
local T=i{name=M,pkgName=R,caps=Q,stdout=function(W)
C(W,c.fg)end}local U,V=load(O,"="..M,"t",T)if U then
local W,X=pcall(U,table.unpack(E))l.reportProgramEnd(a,C,W,X,r,T)L()else
C("Compile error: "..tostring(V),c.error)end end else local Q,O=pcall(require,"shell.panels.commands")local P=Q and O.entry and
O.entry(B)or nil;local N=nil;if not P and
l.mayHavePackages()then local S,R=pcall(require,s)
if S and type(R)=="table"and
R.commandFailure then N=R.commandFailure(B)end end
if N then
C("'"..B..
"' is installed but could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)C(tostring(N),c.error)
C("Free some memory (close tabs, or reboot) and try again.",c.dim)elseif P then
C("'"..B.."' could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)
if a.lastOut and a.lastOut[1]then C(a.lastOut[1],c.error)
a.lastOut=nil else
C("Its command group failed to load — check `log` for the reason.",c.dim)end
C("Free some memory (close tabs, or reboot) and try again.",c.dim)else
C("Unknown command: "..B.."  [E-801 ERR_UNKNOWN_CMD]",c.error)C("Type 'help' for available commands.",c.dim)end
if _G._TOS.audio then _G._TOS.audio.warning()end end end;return G end;local w=8
local f=b.showOutput or
function(y,z)a.lastOut=nil;a.outLines=nil;local A=l.routeOutput(#y,w)
if
A=="status"then a.lastOut=y[1]elseif A=="inline"then a.outLines=y elseif A=="tab"then local B=v()if B then
B.openViewTab(a,y,z or u,true)else a.outLines=y end end end;local function g(y)local z=a.lastOut
if type(z)=="table"and z[1]then y[#y+1]=z;a.lastOut=nil end;return y end
local function x(y)a.lastOut=nil
local z=y:find("|",1,true)local A=y:find("[>]")or y:find("<")
if z or A then
local D,E=pcall(require,"kernel.pipe")
if D then local G=E.parse(y)local F=nil;local H={}
for J,I in ipairs(G)do local L=e(I.cmd,F)local K={}for N,M in ipairs(L)do
K[#K+1]=
type(M)=="table"and M[1]or tostring(M)end;F=table.concat(K,"\n")
if I.stdout and
I.stdout.type=="file"then local M=h(I.stdout.path)
if
l.canWrite(a,M)then local N,O;if I.stdout.append then N,O=d.appendFile(M,F.."\n")else
N,O=d.writeFile(M,F.."\n")end;l.refreshBrowser(a)if N then
a.lastOut={
"Output written to "..I.stdout.path,c.highlight}else
a.lastOut={"Not written: "..tostring(O or I.stdout.path),c.error}end end;return end;if J==#G then H=L end end;f(l.expandBuf(a,g(H)),u)return end end;local B=a._program;local C=e(y,nil,true)
if a._program and a._program~=B then return end
f(l.expandBuf(a,g(C)),y:match("^(%S+)")or u)end;a.execOne=e;return x end;return m