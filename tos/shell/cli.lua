local h,i,g="bar_bg","bar_fg","warning"local k=require("computer")local j={}
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
function j.run(a)local c=l(a)local b,u,I=c.D,c.F,c.K;local e,m=c.W,c.H
local n=require("shell.panels.helpers")local f=3
local function w()if f<=m-2 then return end;local J=b.getGpu and b.getGpu()
if J then local K=pcall(J.copy,1,4,e,
m-5,0,-1)if K then
pcall(J.fill,1,m-2,e,1," ")f=m-2;return end end;b.fill(1,3,e,m-4," ",b.c("fg"),b.c("bg"))f=3 end;local o=nil;local function C(J,K)if not o then return end;o[#o+1]={J,K}
if#o>m then table.remove(o,1)end end;local y
local function d(J,K)local L=(J==nil)and""or
tostring(J)local M=n.wrapLine(L,e)for O,N in ipairs(M)do w()
b.fill(1,f,e,1," ",b.c("fg"),b.c("bg"))
if N~=""then b.set(1,f,N,K or b.c("fg"),b.c("bg"))end;f=f+1 end end
y=function()if not o then return end;for K,J in ipairs(o)do d(J[1],J[2])end end
local function D()b.fill(1,1,e,1," ",b.c(i),b.c(h))
b.set(2,1,(" TOS CLI  ·  "..c.who..
"  ·  type 'tui' for the full interface"):sub(1,
e-2),b.c(i),b.c(h))b.fill(1,m,e,1," ",b.c(i),b.c(h))
b.set(2,m,(" [tui] TUI   [help] Commands   [exit] Log out"):sub(1,
e-2),b.c(i),b.c(h))end;local function p()b.clear(b.c("bg"))D()f=3 end;local x
local function z()if
coroutine.isyieldable and coroutine.isyieldable()then
return coroutine.yield()end;return k.pullSignal(0.25)end
local function q(K,J,L)L=L or 256;local M,N="",1;local O=#c.cmdHistory+1
local P=math.min(f,m-1)
local function Q()w()P=math.min(f,m-1)
local U=J and string.rep("*",#M)or M;local S=K..U;local R=0;if#S>=e then R=#S-e+1 end
b.fill(1,P,e,1," ",b.c("fg"),b.c("bg"))
b.set(1,P,S:sub(R+1,R+e),b.c("fg"),b.c("bg"))local T=#K+N-R;if T>=1 and T<=e then local V=U:sub(N,N)if V==""then V=" "end
b.set(T,P,V,b.c("bg"),b.c("highlight"))end end;Q()
while true do local T,U,S,R=z()
if T=="key_down"then
if R==28 then
b.fill(1,P,e,1," ",b.c("fg"),b.c("bg"))
b.set(1,P,(K.. (J and string.rep("*",#M)or M)):sub(1,e),b.c("dim"),b.c("bg"))f=P+1;return M elseif
R==1 or require("shell.quitkey").is(S,R,true)then if J then return nil end;M,N="",1 elseif R==14 then if N>1 then M=M:sub(1,N-2)..M:sub(N)N=
N-1 end elseif R==211 then if N<=#M then
M=M:sub(1,N-1)..M:sub(N+1)end elseif R==203 then N=math.max(1,N-1)elseif R==205 then
N=math.min(#M+1,N+1)elseif R==199 then N=1 elseif R==207 then N=#M+1 elseif R==200 and not J then if O>1 then O=O-1
M=c.cmdHistory[O]or""N=#M+1 end elseif R==208 and not J then if O<=#c.cmdHistory then O=O+1;M=
c.cmdHistory[O]or""N=#M+1 end elseif
R==15 and not J then local W=require("shell.panels.commands")
local V=n.completeCmdline(M,W.commandNames(),function(X)return
u.list(X)end)if V and V~=M then M=V;N=#M+1 end elseif
S and S>=32 and S<127 and#M<L then
M=M:sub(1,N-1)..string.char(S)..M:sub(N)N=N+1 end;Q()elseif T=="tos_focus"then p()if x then x()end;Q()elseif T=="interrupted"then return nil end end end;local E=require("shell.panels.commands")
local F=require("shell.panels.executor")
local A=require("shell.progenv").builder(c)
local function r(K,J)if J and J~="output"then
d("── "..tostring(J).." ──",b.c("dim"))end
for M,L in ipairs(K or{})do if type(L)=="table"then
d(L[1],L[2])else d(tostring(L))end end end;local v
v={rp=function(J)return n.resolvePath(c,J)end,canRead=function(J,K)
return n.canRead(c,J,K)end,canWrite=function(J,K)return n.canWrite(c,J,K)end,canAccess=function(J,K,L)return
n.canAccess(c,J,K,L)end,rootOnly=function(J)return n.rootOnly(c,J)end,adminOnly=function(J)return
n.adminOnly(c,J)end,makeProgramEnv=A,refreshBrowser=function()return n.refreshBrowser(c)end,loadFiles=function(J)return
n.loadFiles(c,J)end,tabs=c.tabs,pullSignal=z,openViewTab=function(J,K)r(J,K)end,openLiveTab=function(J,K,L)local N,M=pcall(K)if N and type(M)==
"table"then r(M,J)end
d(
"(Once: a live view needs the full interface, 'tui'. Run it again to".." refresh.)",b.c("dim"))end,openEditTab=function(J)
d(
"The editor needs the full interface. Type 'tui' then 'edit "..tostring(J).."'.",b.c(g))end,createTab=function()
d("Tabs need the full interface — type 'tui'.",b.c(g))return nil end,promptInput=function(J,K,L)return q(tostring(J or"> "),L and true or
false,K)end,alert=function(J)
d(tostring(J),b.c(g))return true end,confirm=function(J)
local K=q(tostring(J).." [y/N]: ",false,4)
return K~=nil and K:lower():sub(1,1)=="y"end,confirmTyped=function(J,K)if J then
d(tostring(J),b.c(g))end
local L=q('Type "'..tostring(K)..'" to confirm: ',false,32)return L==K end,dialog=function(J)
J=J or{}
if J.title then d(tostring(J.title),b.c("title"))end;for N,M in ipairs(J.lines or{})do d(tostring(M))end;if
J.text then d(tostring(J.text))end;if J.message then for M in(
tostring(J.message).."\n"):gmatch("(.-)\n")do
d(M)end end
local K=J.buttons
if type(K)=="table"and#K>0 then for N,O in ipairs(K)do
d("  "..N..". "..tostring(O))end
local M=tonumber(q("Choice: ",false,4)or"")return(M and K[M])and M or#K end
local L=q((J.prompt or"OK?").." [y/N]: ",false,4)return
(L~=nil and L:lower():sub(1,1)=="y")and 1 or 2 end,drawAll=function()
p()y()end,drawOutRow=function(J,K)if J then d(J,K)end end}local B=E.build(c,v)v.C=B
local G=F.build(c,{rp=v.rp,makeProgramEnv=A,C=B,showOutput=function(J,K)r(J,nil)end,liveLine=function(J,K)d(J,K)C(J,K)end,repaint=function()
p()end,inputRow=function()w()local J=f;f=f+1;return J end})local s=nil
local H={tui=function()s="tui"end,exit=function()s="logout"end,cls=function()p()end,clear=function()p()end}p()d("TOS CLI",b.c("title"))
d("Every command the full interface has, loaded as you use them.",b.c("dim"))
d("'help' lists them · 'tui' returns to the full interface · 'exit' logs out",b.c("dim"))local t=a.autoCLI
if t and t.haveKB and t.needKB then
d(string.format(
"Started at the command line: this machine has %d KB of memory ".."and the full interface needs %d KB.",t.haveKB,t.needKB),b.c(g))
d("'tui' opens it anyway · 'bootsettings ui panels' makes it the default",b.c("dim"))end
if a.tuiFailed then local u=a.F
if u and u.exists and
not u.exists("/tos/shell/panels.lua")then
d("This is a minimal install, so the full interface is not on this disk.",b.c(g))else
d("The full interface could not start: "..tostring(a.tuiFailed),b.c("error"))
d("This is the command line instead · 'tui' tries again",b.c("dim"))end end;d("")
x=function()
if c.outLines then r(c.outLines,nil)c.outLines=nil end
if c.lastOut then
if type(c.lastOut)=="table"then
d(c.lastOut[1],c.lastOut[2])else d(tostring(c.lastOut))end;c.lastOut=nil end end
while true do local K=(c._sudo and"[sudo] "or"")..
c.who..":"..c.cwd.."$ "local J=q(K,false)if J==
nil then J=""end;J=J:match("^%s*(.-)%s*$")
if J~=""then c.cmdHistory[
#c.cmdHistory+1]=J;c.lastOut=nil;c.outLines=nil
local L=H[J]
if L then L()else o={}local M,N=pcall(G,J)o=nil
if not M then
d("Error: "..tostring(N),b.c("error"))else if c.outLines then r(c.outLines,nil)c.outLines=nil end
if
c.lastOut then
if type(c.lastOut)=="table"then
d(c.lastOut[1],c.lastOut[2])else d(tostring(c.lastOut))end;c.lastOut=nil end;if c._exitTo=="tui"then s="tui"end;c._exitTo=nil end end end;if s then if c.sudoDrop then pcall(c.sudoDrop)end
b.clear(b.c("bg"))return s end end end;return j