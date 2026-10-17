local B=require("computer")local w,D,E,F,C,v,x,G,H={},nil,nil,nil,nil,nil,nil,nil,nil;local I,J,y,z,A=80,25,"/","root",
nil;local K=nil
local function L()local b,a=pcall(B.totalMemory)return
(b and
type(a)=="number")and math.floor(a/1024)or nil end
local function M()local b,a=pcall(require,"kernel.bootcfg")
local c=_G._TOS and _G._TOS.bootcfg;if b and a and a.ui then return a.ui(c,L())end;return"home"end
local function N()return
{K=D,E=E,P=F,F=C,D=v,U=x,SC=G,NM=H,cwd=y,who=z,W=I,H=J,st=A,uiSplit=M()=="split",displayIdx=K,autoCLI=w._autoCLI,tuiFailed=w._tuiFailed}end
local function O()local b,a=pcall(require,"shell.cli")
if not b then
v.clear(v.c("bg"))
v.set(1,2,"CLI unavailable: "..tostring(a),v.c("error"),v.c("bg"))
v.set(1,3,"Reboot and hold S at POST for Safe Mode.",v.c("warning"),v.c("bg"))B.pullSignal(5)return"logout"end;local d=N()w._tuiFailed=nil;return a.run(d)end
local function P()local b,a=pcall(require,"shell.panels")
if not b then
v.clear(v.c("bg"))
v.set(1,2,"WARNING: TUI unavailable ("..tostring(a)..")",v.c("error"),v.c("bg"))
v.set(1,3,"Falling back to the command line.",v.c("warning"),v.c("bg"))B.pullSignal(2)w._tuiFailed=tostring(a)return nil end;return a.run(N())end
function w.run(a,b)D=a;A=b;E=a.getEvent()F=a.getProc()
C=a.getSecureFS()or a.getFS()v=a.getDisplay()x=a.getUsers()G=a.getConfig()
H=a.getNet()
K=a.getDisplayIdx and a.getDisplayIdx()or nil;I,J=v.getSize()z="root"if x and A then local f=x.getSession(A)
if f then z=f.user end end;y="/home/"..z
if not C.exists(y)then y="/"end;local d,e=M()local c=(d=="cli")and"cli"or"tui"
w._autoCLI=nil;if c=="cli"and e=="auto"then
local f,g=pcall(require,"kernel.bootcfg")
w._autoCLI={haveKB=L(),needKB=f and g.PANELS_MIN_KB or nil}end;for f=1,64 do local g
if
c=="cli"then g=O()if g=="tui"then c="tui"else return end else g=P()if g=="cli"or g==nil then c="cli"else
return end end end end;return w