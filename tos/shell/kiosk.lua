local k="string"local l={}
local o={allowed={"help","ls","cat","date","time","echo","whoami","logout"},banner="TOS Kiosk Mode",menu={},idleSeconds=60}local m="/etc/kiosk.cfg"local n=8192
local function p(a,b)local c={}for h,i in pairs(o)do c[h]=i end;if not a or not
a.exists(m,b)then return c end;local e=a.readFile(m,b)if
not e or#e==0 or#e>n then return c end
local f=require("kernel.serialize")local g,d=pcall(f.decode,e,{maxBytes=n})if
not g or type(d)~="table"then return c end
if type(d.allowed)=="table"then c.allowed={}for i,h in
ipairs(d.allowed)do
if
type(h)==k and h:match("^[%w_%-]+$")and#h<=32 then c.allowed[#c.allowed+1]=h end end end
if type(d.banner)==k and#d.banner<=200 then c.banner=d.banner end
if type(d.menu)=="table"then c.menu={}
for i,h in ipairs(d.menu)do
if

type(h)=="table"and
type(h.label)==k and#h.label<=60 and
type(h.cmd)==k and#h.cmd<=200 and not h.cmd:find("[\n\r]")then c.menu[#c.menu+1]={label=h.label,cmd=h.cmd}end;if#c.menu>=12 then break end end end;if
type(d.idleSeconds)=="number"and d.idleSeconds>=10 and d.idleSeconds<=3600 then
c.idleSeconds=d.idleSeconds end;return c end
local function q(a)local b={}for d,c in ipairs(a)do b[c:lower()]=true end;return b end;local function r(a,b)a.clear(b.bg)end
local function s(b,a,c)local d=b.getSize()b.fill(1,1,d,1," ",a.bar_fg or a.fg,
a.bar_bg or a.bg)
b.set(1,1," "..
c:sub(1,d-2),a.bar_fg or a.fg,a.bar_bg or a.bg)end
local function t(b,a,c,d)r(b,a)s(b,a,d)local e=3
b.set(2,e,"Available options:",a.title or a.fg,a.bg)e=e+2;for f,g in ipairs(c)do
b.set(2,e,string.format(" [%d] %s",f,g.label),a.fg,a.bg)e=e+1 end;if#c==0 then
b.set(2,e,"  (no menu items configured — use the prompt below)",
a.dim or a.fg,a.bg)e=e+1 end;e=e+1
b.set(2,e,"Type a command, or press a number for a menu item.",
a.dim or a.fg,a.bg)
b.set(2,e+1,"Press Ctrl+D to log out.",a.dim or a.fg,a.bg)return e+3 end
function l.run(a,b)
local d=a.getDisplay and a.getDisplay()or a.D or _G._TOS.display;local h=_G._TOS.users;local x=_G._TOS.securefs;local e=h.getSession(b)if not e then
return end;local f=p(x,e)local z=q(f.allowed)
local A=require("shell.panels.commands")local y=require("shell.panels.helpers")local c=d.getTheme()
local i,v=d.getSize()local g={}
local function j(E,F)g[#g+1]={tostring(E),F or c.fg}end
local w={K=a,U=h,F=x or _G._TOS.fs,P=_G._TOS.process or _G._TOS.proc,D=d,T=c,W=i,H=v,SC=_G._TOS.config,NM=_G._TOS.net,who=e.user,st=b,tier=e.tier,userTier=e.tier,cmdHistory={},lastOut=
nil}
local B={rp=function(E)if E:sub(1,1)=="/"then return E end
return(e.home or"/").."/"..E end,canRead=function(E,F)return y.canAccess(w,E,"r",F)end,canWrite=function(F,E)
if
E then E("Kiosk mode is read-only.",c.error or c.fg)end;return false end,canAccess=function(G,F,E)if F=="w"then
if E then E("Kiosk mode is read-only.",
c.error or c.fg)end;return false end
return y.canAccess(w,G,F,E)end,adminOnly=function()
return false end,rootOnly=function()return false end,refreshBrowser=function()end,makeProgramEnv=function()return{}end}local C=A.build(w,B)
local function D(E)g={}local F={}
for L in E:gmatch("%S+")do F[#F+1]=L end;if#F==0 then return end;local G=F[1]:lower()if not z[G]then j("Command not available in kiosk mode: "..G,
c.error or c.fg)
return end;local I=C[G]
if not I then j("Command unavailable.",c.warning or
c.fg)return end;local H={}for L=2,#F do H[#H+1]=F[L]end;local J,K=pcall(I,H,j)
if not J then j("Error: "..
tostring(K),c.error or c.fg)end end;local u=require("computer")
while true do local G=t(d,c,f.menu,f.banner)for I,J in
ipairs(g)do if G+I>v-2 then break end
d.set(2,G+I-1,J[1]:sub(1,i-3),J[2]or c.fg,c.bg)end;local F=v
d.fill(1,F,i,1," ",c.fg,c.bg)d.set(1,F,"kiosk> ",c.prompt or c.fg,c.bg)local E=""
local H=u.uptime()
while true do d.fill(8,F,i-8,1," ",c.fg,c.bg)
d.set(8,F,E.."_",c.fg,c.bg)local K,L,I,J=u.pullSignal(1)
if K=="key_down"then H=u.uptime()
if J==28 then break elseif J==14 then if#E>0 then E=E:sub(1,
-2)end elseif I==4 then if h.logout then h.logout(b)end;return elseif I and
I>=49 and I<=57 then local N=I-48;local M=f.menu[N]if M then E=M.cmd;break end elseif
I and I>=32 and I<127 and#E<80 then E=E..string.char(I)end else if u.uptime()-H>f.idleSeconds then E=""g={}break end end end;if#E>0 then D(E)end end end;return l