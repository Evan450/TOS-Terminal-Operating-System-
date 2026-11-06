local n="string"local o={}
local p={allowed={"help","ls","cat","date","time","echo","whoami","logout"},banner="TOS Kiosk Mode",menu={},idleSeconds=60}local m="/etc/kiosk.cfg"local q=8192
local function l(a)local b,c=pcall(require,"kernel.log")if b then pcall(c.error,"kiosk",
m..": "..a)end;return
{allowed={},menu={},idleSeconds=p.idleSeconds,banner="This kiosk is out of order"}end
local function r(a,b)local d={}for h,i in pairs(p)do d[h]=i end;if not a or not a.exists(m,b)then
return d end;local e=a.readFile(m,b)if not e then
return l("cannot be read")end
if#e==0 or#e>q then return l("empty or too large")end;local f=require("kernel.serialize")
local g,c=pcall(f.decode,e,{maxBytes=q})
if not g or type(c)~="table"then return l("not a config table")end;if c.allowed~=nil and type(c.allowed)~="table"then return
l("`allowed` is not a list")end
if
type(c.allowed)=="table"then d.allowed={}
for i,h in ipairs(c.allowed)do if type(h)==n and
h:match("^[%w_%-]+$")and#h<=32 then
d.allowed[#d.allowed+1]=h end end end
if type(c.banner)==n and#c.banner<=200 then d.banner=c.banner end
if type(c.menu)=="table"then d.menu={}
for i,h in ipairs(c.menu)do
if

type(h)=="table"and
type(h.label)==n and#h.label<=60 and
type(h.cmd)==n and#h.cmd<=200 and not h.cmd:find("[\n\r]")then d.menu[#d.menu+1]={label=h.label,cmd=h.cmd}end;if#d.menu>=12 then break end end end;if
type(c.idleSeconds)=="number"and c.idleSeconds>=10 and c.idleSeconds<=3600 then
d.idleSeconds=c.idleSeconds end;return d end
local function s(a)local b={}for d,c in ipairs(a)do b[c:lower()]=true end;return b end;local function t(a,b)a.clear(b.bg)end
local function u(b,a,c)local d=b.getSize()b.fill(1,1,d,1," ",a.bar_fg or a.fg,
a.bar_bg or a.bg)
b.set(1,1," "..
c:sub(1,d-2),a.bar_fg or a.fg,a.bar_bg or a.bg)end
local function v(b,a,c,d)t(b,a)u(b,a,d)local e=3
b.set(2,e,"Available options:",a.title or a.fg,a.bg)e=e+2;for f,g in ipairs(c)do
b.set(2,e,string.format(" [%d] %s",f,g.label),a.fg,a.bg)e=e+1 end;if#c==0 then
b.set(2,e,"  (no menu items configured — use the prompt below)",
a.dim or a.fg,a.bg)e=e+1 end;e=e+1
b.set(2,e,"Type a command, or press a number for a menu item.",
a.dim or a.fg,a.bg)
b.set(2,e+1,"Press Ctrl+D to log out.",a.dim or a.fg,a.bg)return e+3 end
function o.run(a,b)
local d=a.getDisplay and a.getDisplay()or a.D or _G._TOS.display;local h=_G._TOS.users;local y=_G._TOS.securefs;local e=h.getSession(b)if not e then
return end;local f=r(y,e)local A=s(f.allowed)
local B=require("shell.panels.commands")local z=require("shell.panels.helpers")local c=d.getTheme()
local i,w=d.getSize()local g={}
local function j(F,G)g[#g+1]={tostring(F),G or c.fg}end
local x={K=a,U=h,F=y or _G._TOS.fs,P=_G._TOS.process or _G._TOS.proc,D=d,T=c,W=i,H=w,SC=_G._TOS.config,NM=_G._TOS.net,who=e.user,st=b,tier=e.tier,userTier=e.tier,cmdHistory={},lastOut=
nil}
local C={rp=function(F)if F:sub(1,1)=="/"then return F end
return(e.home or"/").."/"..F end,canRead=function(F,G)return z.canAccess(x,F,"r",G)end,canWrite=function(G,F)
if
F then F("Kiosk mode is read-only.",c.error or c.fg)end;return false end,canAccess=function(H,G,F)if G=="w"then
if F then F("Kiosk mode is read-only.",
c.error or c.fg)end;return false end
return z.canAccess(x,H,G,F)end,adminOnly=function()
return false end,rootOnly=function()return false end,refreshBrowser=function()end,makeProgramEnv=function()return{}end}local D=B.build(x,C)
local function E(F)g={}local G={}
for M in F:gmatch("%S+")do G[#G+1]=M end;if#G==0 then return end;local H=G[1]:lower()if not A[H]then j("Command not available in kiosk mode: "..H,
c.error or c.fg)
return end;local J=D[H]
if not J then j("Command unavailable.",c.warning or
c.fg)return end;local I={}for M=2,#G do I[#I+1]=G[M]end;local K,L=pcall(J,I,j)
if not K then j("Error: "..
tostring(L),c.error or c.fg)end end;local k=require("computer")
while true do local H=v(d,c,f.menu,f.banner)for J,K in
ipairs(g)do if H+J>w-2 then break end
d.set(2,H+J-1,K[1]:sub(1,i-3),K[2]or c.fg,c.bg)end;local G=w
d.fill(1,G,i,1," ",c.fg,c.bg)d.set(1,G,"kiosk> ",c.prompt or c.fg,c.bg)local F=""
local I=k.uptime()
while true do d.fill(8,G,i-8,1," ",c.fg,c.bg)
d.set(8,G,F.."_",c.fg,c.bg)local L,M,J,K=k.pullSignal(1)
if L=="key_down"then I=k.uptime()
if K==28 then break elseif K==14 then if#F>0 then F=F:sub(1,
-2)end elseif J==4 then if h.logout then h.logout(b)end;return elseif
J and
J>=49 and J<=57 and F==""and f.menu[J-48]then F=f.menu[J-48].cmd;break elseif
J and J>=32 and J<127 and#F<80 then F=F..string.char(J)end else if k.uptime()-I>f.idleSeconds then F=""g={}break end end end;if#F>0 then E(F)end end end;return o