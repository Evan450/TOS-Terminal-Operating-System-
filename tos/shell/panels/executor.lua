local q,r,s="Error: ","kernel.screen","output"
local k=require("shell.panels.helpers")local m=nil
local function t()if m==nil then local a,b=pcall(require,"shell.panels.editor")m=a and b or
false end;return m or nil end;local n=function()end
do local b,a=pcall(require,"kernel.process")if b and a and
a.yieldCooperative then n=a.yieldCooperative end end;local l={}
local o={ps=true,df=true,mem=true,uptime=true,log=true,net=true,battery=true,lsdev=true}l.LIVE_SHORT=o
local function p(a)local f,c={},nil;local b,d=1,#a;local function e(h,i)
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
j==" "or j=="\t"or j=="'"or j=='"'or j=="\\"then break end;b=b+1 end;e(i,b-1)end end;g()return f end;l._tokenize=p
function l.build(a,b)local d=a.F;local c=a.T;local h=b.rp;local i=b.makeProgramEnv;local j=b.C
local function u(y,z,A,x,B)
local L,C=pcall(require,"kernel.process")
if not L or type(C)~="table"or not C.spawn then return false end;local E=a.displayIdx;if not E then return false end
local J=C.current and C.current()local H=J and J.pid;if not H then return false end;local M,D=pcall(require,r)D=
M and D or nil;local I=false
if x and D and D.fitDisplay then
local P=x.mode=="min"and(a.W or 0)>=
x.width and(a.H or 0)>=x.height;if not P then
local Q=D.fitDisplay(E,{mode="size",w=x.width,h=x.height})I=Q~=nil end end;local G={}
local function N(P,Q)G[#G+1]={tostring(P),Q or c.fg}end;local F
F=C.spawn("prog:"..y.."@"..E,function()local R,S=pcall(z,A,N)if not R then
G[#G+1]={q..tostring(S),c.error}end
if I and D and D.restore then pcall(D.restore,E)end
if a._program and a._program.pid==F then a._program=nil end;local T,P=pcall(require,"shell.panels.tabs")if T and P then
for V,U in
ipairs(a.tabs or{})do if U.type=="program"and U.pid==F then U.pid=nil;pcall(P.close,a,V)
break end end end;if a.D and
a.D.invalidate then pcall(a.D.invalidate)end;if#G>0 then
a.outLines=k.expandBuf(a,G)end;local Q=C.get and C.get(H)if Q and
Q.state~=C.STATE.DEAD then
C.setForeground(H,E,{kernel=true});(C.signalKernel or
C.signal)(H,"tos_focus")end end,{priority=3,source="user",principal=
k.sessionOf and k.sessionOf(a)or nil,token=a.st,display=E,background=B})if not F then if I and D and D.restore then pcall(D.restore,E)end;return
false end
a._program={pid=F,name=y,seat=E}local O,K=pcall(require,"shell.panels.tabs")if O and K then
pcall(K.create,a,"program",y,{pid=F,seat=E,prog=y,live=true})end;a.suspendIdleDraw=true;if
a.D and a.D.invalidate then pcall(a.D.invalidate)end
C.setForeground(F,E,{kernel=true})return true end
local function e(z,x,y)local C=p(z)if#C==0 then return""end;C=k.expandAlias(a,C)
if#C==0 then return""end;local A=C[1]:lower()
if y and A~="watch"then
for L=2,#C do if C[L]=="--live"or
(C[L]=="-f"and o[A])then table.remove(C,L)
table.insert(C,1,"watch")A="watch"break end end end;a.curCmd=A;if A~="why"then k.clearFailure(a)end;local E={}for L=2,#C do
E[#E+1]=C[L]end;local G={}local function B(L,M)G[#G+1]={tostring(L),M or c.fg}
if M==
c.error and A~="why"then k.noteFailure(a,A,L)end;n()end
if x and#x>0 then
if
A=="grep"and#E>=1 and not E[2]then local L=E[1]for M in x:gmatch("([^\n]*)\n?")do if
M:find(L,1,true)then B(M,c.fg)end end;return G elseif
A=="wc"and#E==0 then local L,M,N=0,0,#x;for O in x:gmatch("\n")do L=L+1 end;for O in x:gmatch("%S+")do M=
M+1 end
B(string.format(" %d lines  %d words  %d bytes",L,M,N),c.fg)return G end end;local D=j[A]
if D then local O,M=pcall(require,"shell.panels.commands")local N=
O and
type(M)=="table"and M.entry and M.entry(A)or nil;local L=N and
tonumber(N.tier)or 0
if L>0 then local P=
k.liveTier and k.liveTier(a)or 0
if P<L then
local Q="Permission denied: '"..
A.."' needs "..
(
k.tierName and k.tierName(L)or("tier "..L)).."  [E-403 ERR_TIER_REQUIRED]"if k.fail then k.fail(a,Q,B)else B(Q,c.error)end
a.lastDenial={cmd=A,need=L,have=P}return G end end end;local F=nil;local H=false;local I,J=false,"drowsy"
if not D then local M,L=false,nil;if k.mayHavePackages()then
M,L=pcall(require,"kernel.pkg")end
if M and L and L.getCommand then
D=L.getCommand(A)H=D~=nil
if D and L.getCommandScreen then F=L.getCommandScreen(A)end
if D and L.getCommandFullscreen then I=L.getCommandFullscreen(A)if
L.getCommandBackground then J=L.getCommandBackground(A)end end end end;if D and I and y then if u(A,D,E,F,J)then return{}end end
local function K()if a.D and
a.D.invalidate then pcall(a.D.invalidate)end end
if D then local L=false
if F then
local O=F.mode=="min"and(a.W or 0)>=F.width and
(a.H or 0)>=F.height
if not O then local Q,P=pcall(require,r)
if Q and P and P.fitDisplay then
local S,T,R=P.fitDisplay(a.displayIdx,{mode="size",w=F.width,h=F.height})if S then L=true end;if R then B(R,c.warning)end end end end;local M,N=pcall(D,E,B)
if not M then B(q..tostring(N),c.error)end;if H then K()end
if L then local Q,O=pcall(require,r)if Q and O and O.restore then
pcall(O.restore,a.displayIdx)end
local R,P=pcall(require,"shell.panels.state")
if R and P and P.recomputeLayout then pcall(P.recomputeLayout,a)end end else local L=k.resolveProgram(d,A)
if L then
local M=k.safeModeRefusal and k.safeModeRefusal(L)
if M then if k.fail then k.fail(a,M,B)else B(M,c.error)end;return G end;local N=d.readFile(L)
if N then local P,Q=nil,nil;local R,O=false,nil;if k.mayHavePackages()then
R,O=pcall(require,"kernel.pkg")end;if
R and type(O)=="table"and O.capsForFile then P,Q=O.capsForFile(L)end
local S=i{name=L,pkgName=Q,caps=P,stdout=function(V)
B(V,c.fg)end}local T,U=load(N,"="..L,"t",S)if T then
local V,W=pcall(T,table.unpack(E))k.reportProgramEnd(a,B,V,W,q,S)K()else
B("Compile error: "..tostring(U),c.error)end end else local N,M=pcall(require,"shell.panels.commands")local O=N and M.entry and
M.entry(A)or nil
if O then
B("'"..A..
"' could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]",c.error)
if a.lastOut and a.lastOut[1]then B(a.lastOut[1],c.error)
a.lastOut=nil else
B("Its command group failed to load — check `log` for the reason.",c.dim)end
B("Free some memory (close tabs, or reboot) and try again.",c.dim)else
B("Unknown command: "..A.."  [E-801 ERR_UNKNOWN_CMD]",c.error)B("Type 'help' for available commands.",c.dim)end
if _G._TOS.audio then _G._TOS.audio.warning()end end end;return G end;local v=8
local f=b.showOutput or
function(x,y)a.lastOut=nil;a.outLines=nil;local z=k.routeOutput(#x,v)
if
z=="status"then a.lastOut=x[1]elseif z=="inline"then a.outLines=x elseif z=="tab"then local A=t()if A then
A.openViewTab(a,x,y or s,true)else a.outLines=x end end end;local function g(x)local y=a.lastOut
if type(y)=="table"and y[1]then x[#x+1]=y end;return x end
local function w(x)a.lastOut=nil
local y=x:find("|",1,true)local z=x:find("[>]")or x:find("<")
if y or z then
local C,D=pcall(require,"kernel.pipe")
if C then local F=D.parse(x)local E=nil;local G={}
for I,H in ipairs(F)do local K=e(H.cmd,E)local J={}for M,L in ipairs(K)do
J[#J+1]=
type(L)=="table"and L[1]or tostring(L)end;E=table.concat(J,"\n")
if H.stdout and
H.stdout.type=="file"then local L=h(H.stdout.path)
if
k.canWrite(a,L)then local M,N;if H.stdout.append then M,N=d.appendFile(L,E.."\n")else
M,N=d.writeFile(L,E.."\n")end;k.refreshBrowser(a)if M then
a.lastOut={
"Output written to "..H.stdout.path,c.highlight}else
a.lastOut={"Not written: "..tostring(N or H.stdout.path),c.error}end end;return end;if I==#F then G=K end end;f(k.expandBuf(a,g(G)),s)return end end;local A=a._program;local B=e(x,nil,true)
if a._program and a._program~=A then return end
f(k.expandBuf(a,g(B)),x:match("^(%S+)")or s)end;a.execOne=e;return w end;return l