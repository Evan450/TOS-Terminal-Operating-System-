local h,i,g="bar_fg","bar_bg","warning"local k=require("computer")local j={}
local function l(a)
local b={}b.K,b.E,b.P,b.F=a.K,a.E,a.P,a.F;b.D,b.U,b.SC,b.NM=a.D,a.U,a.SC,a.NM
b.st=a.st
b.displayIdx=a.displayIdx or
(a.K and a.K.getDisplayIdx and a.K.getDisplayIdx())or nil;b.W,b.H=a.W,a.H;b.T=b.D.getTheme()b.tier=b.D.getGpuTier()b.cwd=
a.cwd or"/"b.who=a.who or"root"b.userTier=0;if b.U and b.st then
local c=b.U.getSession(b.st)
if c then b.userTier=c.tier or 0;b.who=c.user or b.who end end
b.MENU_ROW,b.RAIL_ROW,b.LIST_TOP=1,2,3;b.SUM_ROW,b.OUT_ROW,b.CMD_ROW,b.STAT_ROW=b.H,b.H,b.H,b.H
b.LIST_H=math.max(1,b.H-4)b.padW=string.rep(" ",b.W)b.cmdline,b.cmdCursor="",1
b.cmdHistory,b.cmdHistIdx={},0;b.lastOut=nil;b.clipboard=nil
b.browser={path=b.cwd,sel=1,scroll=0,files={}}b.tabs={{type="shell",label="CLI"}}b.activeTab=1
b.KEYS=require("shell.panels.keymap")b.isCLI=true;return b end
function j.run(a)local c=l(a)local b,z,F=c.D,c.F,c.K;local e,n=c.W,c.H
local m=require("shell.panels.helpers")local f=3
local function v()if f<=n-2 then return end;local G=b.getGpu and b.getGpu()
if G then local H=pcall(G.copy,1,4,e,
n-5,0,-1)if H then
pcall(G.fill,1,n-2,e,1," ")f=n-2;return end end;b.fill(1,3,e,n-4," ",b.c("fg"),b.c("bg"))f=3 end
local function d(G,H)local I=(G==nil)and""or tostring(G)
local J=m.wrapLine(I,e)for L,K in ipairs(J)do v()b.fill(1,f,e,1," ",b.c("fg"),b.c("bg"))
if K~=
""then b.set(1,f,K,H or b.c("fg"),b.c("bg"))end;f=f+1 end end
local function A()b.fill(1,1,e,1," ",b.c(h),b.c(i))
b.set(2,1,(" TOS CLI  ·  "..c.who..
"  ·  type 'tui' for the full interface"):sub(1,
e-2),b.c(h),b.c(i))b.fill(1,n,e,1," ",b.c(h),b.c(i))
b.set(2,n,(" [tui] TUI   [help] Commands   [exit] Log out"):sub(1,
e-2),b.c(h),b.c(i))end;local function o()b.clear(b.c("bg"))A()f=3 end;local u
local function w()if
coroutine.isyieldable and coroutine.isyieldable()then
return coroutine.yield()end;return k.pullSignal(0.25)end
local function p(H,G,I)I=I or 256;local J,K="",1;local L=#c.cmdHistory+1
local M=math.min(f,n-1)
local function N()v()M=math.min(f,n-1)
local R=G and string.rep("*",#J)or J;local P=H..R;local O=0;if#P>=e then O=#P-e+1 end
b.fill(1,M,e,1," ",b.c("fg"),b.c("bg"))
b.set(1,M,P:sub(O+1,O+e),b.c("fg"),b.c("bg"))local Q=#H+K-O;if Q>=1 and Q<=e then local S=R:sub(K,K)if S==""then S=" "end
b.set(Q,M,S,b.c("bg"),b.c("highlight"))end end;N()
while true do local Q,R,P,O=w()
if Q=="key_down"then
if O==28 then
b.fill(1,M,e,1," ",b.c("fg"),b.c("bg"))
b.set(1,M,(H.. (G and string.rep("*",#J)or J)):sub(1,e),b.c("dim"),b.c("bg"))f=M+1;return J elseif O==1 or P==17 then if G then return nil end;J,K="",1 elseif O==14 then if K>1 then J=J:sub(1,K-2)..
J:sub(K)K=K-1 end elseif O==211 then if K<=#J then J=J:sub(1,K-1)..J:sub(
K+1)end elseif O==203 then
K=math.max(1,K-1)elseif O==205 then K=math.min(#J+1,K+1)elseif O==199 then K=1 elseif O==207 then K=#J+1 elseif O==200 and not G then if
L>1 then L=L-1;J=c.cmdHistory[L]or""K=#J+1 end elseif O==
208 and not G then if L<=#c.cmdHistory then L=L+1
J=c.cmdHistory[L]or""K=#J+1 end elseif O==15 and not G then
local T=require("shell.panels.commands")
local S=m.completeCmdline(J,T.commandNames(),function(U)return z.list(U)end)if S and S~=J then J=S;K=#J+1 end elseif
P and P>=32 and P<127 and#J<I then
J=J:sub(1,K-1)..string.char(P)..J:sub(K)K=K+1 end;N()elseif Q=="tos_focus"then o()if u then u()end;N()elseif Q=="interrupted"then return nil end end end;local B=require("shell.panels.commands")
local C=require("shell.panels.executor")
local x=require("shell.progenv").builder(c)
local function q(H,G)if G and G~="output"then
d("── "..tostring(G).." ──",b.c("dim"))end
for J,I in ipairs(H or{})do if type(I)=="table"then
d(I[1],I[2])else d(tostring(I))end end end;local t
t={rp=function(G)return m.resolvePath(c,G)end,canRead=function(G,H)
return m.canRead(c,G,H)end,canWrite=function(G,H)return m.canWrite(c,G,H)end,canAccess=function(G,H,I)return
m.canAccess(c,G,H,I)end,rootOnly=function(G)return m.rootOnly(c,G)end,adminOnly=function(G)return
m.adminOnly(c,G)end,makeProgramEnv=x,refreshBrowser=function()return m.refreshBrowser(c)end,loadFiles=function(G)return
m.loadFiles(c,G)end,tabs=c.tabs,pullSignal=w,openViewTab=function(G,H)q(G,H)end,openLiveTab=function(G,H,I)local K,J=pcall(H)if K and type(J)==
"table"then q(J,G)end
d("(one-shot: live views need the TUI — 'watch "..
tostring(G).."' repeats it here)",b.c("dim"))end,openEditTab=function(G)
d(
"The editor needs the full interface. Type 'tui' then 'edit "..tostring(G).."'.",b.c(g))end,createTab=function()
d("Tabs need the full interface — type 'tui'.",b.c(g))return nil end,promptInput=function(G,H,I)return p(tostring(G or"> "),I and true or
false,H)end,alert=function(G)
d(tostring(G),b.c(g))return true end,confirm=function(G)
local H=p(tostring(G).." [y/N]: ",false,4)
return H~=nil and H:lower():sub(1,1)=="y"end,confirmTyped=function(G,H)if G then
d(tostring(G),b.c(g))end
local I=p('Type "'..tostring(H)..'" to confirm: ',false,32)return I==H end,dialog=function(G)
G=G or{}
if G.title then d(tostring(G.title),b.c("title"))end;for J,I in ipairs(G.lines or{})do d(tostring(I))end;if
G.text then d(tostring(G.text))end;local H=p(
(G.prompt or"OK?").." [y/N]: ",false,4)return
(H~=nil and
H:lower():sub(1,1)=="y")and 1 or 2 end,drawAll=function()
o()end,drawOutRow=function(G,H)if G then d(G,H)end end}local y=B.build(c,t)t.C=y
local D=C.build(c,{rp=t.rp,makeProgramEnv=x,C=y,showOutput=function(G,H)q(G,nil)end})local r=nil
local E={tui=function()r="tui"end,exit=function()r="logout"end,cls=function()o()end,clear=function()o()end}o()d("TOS CLI",b.c("title"))
d("Every command the full interface has, loaded as you use them.",b.c("dim"))
d("'help' lists them · 'tui' returns to the full interface · 'exit' logs out",b.c("dim"))local s=a.autoCLI
if s and s.haveKB and s.needKB then
d(string.format(
"Started at the command line: this machine has %d KB of memory ".."and the full interface needs %d KB.",s.haveKB,s.needKB),b.c(g))
d("'tui' opens it anyway · 'bootsettings ui panels' makes it the default",b.c("dim"))end
if a.tuiFailed then
d("The full interface could not start: "..tostring(a.tuiFailed),b.c("error"))
d("This is the command line instead · 'tui' tries again",b.c("dim"))end;d("")
u=function()
if c.outLines then q(c.outLines,nil)c.outLines=nil end
if c.lastOut then
if type(c.lastOut)=="table"then
d(c.lastOut[1],c.lastOut[2])else d(tostring(c.lastOut))end;c.lastOut=nil end end
while true do local H=(c._sudo and"[sudo] "or"")..
c.who..":"..c.cwd.."$ "local G=p(H,false)if G==
nil then G=""end;G=G:match("^%s*(.-)%s*$")
if G~=""then c.cmdHistory[
#c.cmdHistory+1]=G;c.lastOut=nil;c.outLines=nil
local I=E[G]
if I then I()else local J,K=pcall(D,G)
if not J then
d("Error: "..tostring(K),b.c("error"))else if c.outLines then q(c.outLines,nil)c.outLines=nil end
if
c.lastOut then
if type(c.lastOut)=="table"then
d(c.lastOut[1],c.lastOut[2])else d(tostring(c.lastOut))end;c.lastOut=nil end;if c._exitTo=="tui"then r="tui"end;c._exitTo=nil end end end;if r then if c.sudoDrop then pcall(c.sudoDrop)end
b.clear(b.c("bg"))return r end end end;return j