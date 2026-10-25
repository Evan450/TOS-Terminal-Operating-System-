local w,x="logout","settings"local s=require("shell.panels.ui")
local B=require("shell.panels.tabs")local r={}local D=24
local E={{id="files",label="Files",glyph="≡",kind="tab",hint="File browser and command prompt"},{id="monitor",label="Monitor",glyph="▒",cmd="monitor",hint="Live processes, services, memory"},{id="chat",label="Chat",glyph="»",cmd="chat",hint="Network chat"},{id="mail",label="Mail",glyph="@",cmd="mail",hint="Mesh email inbox"},{id=x,label="Settings",glyph="§",kind=x,hint="Theme, status bar, desktop, system"},{id="tapemenu",label="Tape Menu",glyph="▓",cmd="tape-menu",hint="Personal command menu from your identity tape"},{id="help",label="Help",glyph="?",cmd="help",hint="Command reference"},{id="tutorial",label="Tutorial",glyph="¶",cmd="tutorial",hint="Replay the welcome walkthrough"},{id=w,label="Log Out",glyph="«",kind=w,hint="End this session"}}
function r.buildApps(a)a=a or{}
local g=a.entry or function()return nil end;local h=a.needMet or function()return true end
local i=a.needs or{}local j=a.userTier or 0
local c=a.translate or function(l,k)return k end;local b={}local f={}
for l,k in ipairs(E)do local m=true
if a.home and k.kind=="tab"then m=false end;if m and k.cmd then f[k.cmd]=true;local n=g(k.cmd)if n and(n.tier or 0)>j then
m=false end
if m and not h(i[k.cmd])then m=false end end;if m then
b[#b+1]={id=k.id,kind=k.kind,cmd=k.cmd,glyph=k.glyph,label=c(
"desktop."..k.id,k.label),hint=c("desktop."..k.id..".hint",k.hint)}end end
for l,k in ipairs(a.personal or{})do if l>12 then break end
b[#b+1]={id="my:"..k.label,label=tostring(k.label):sub(1,12),glyph="◆",cmd=k.run,personal=true,hint=c("desktop.my.hint","From your ~/.launcher.cfg menu")}end;local d={}
for k in pairs(a.pkgCommands or{})do if
type(k)=="string"and not f[k]then d[#d+1]=k end end;table.sort(d)local e=0
for l,k in ipairs(d)do
if l<=D then
b[#b+1]={id="pkg:"..k,label=k:sub(1,12),glyph="•",cmd=k,pkg=true,hint=c("desktop.pkg.hint","Installed package command")}else e=e+1 end end;return b,e end
function r.resolveApp(a,b)local c=a and a[b]if not c then return{type="none"}end;if
c.kind=="tab"then return{type="tab"}end
if c.kind==x then return{type=x}end;if c.kind==w then return{type=w}end
if c.cmd then return{type="cmd",cmd=c.cmd}end;return{type="none"}end;local y=nil
local function F()if y==nil then local a,b=pcall(require,"kernel.ustr")
y=(a and b)or false end;return y or nil end;local function C(a,b)local c=F()if c and c.fit then return c.fit(a,b)end;return
tostring(a or""):sub(1,b)end
local function G(a)local b={userTier=
a.userTier or 0}
local h,c=pcall(require,"shell.panels.commands")
if h and c then b.entry=c.entry;b.needMet=c.needMet;b.needs=c.NEEDS end;local i,e=pcall(require,"kernel.i18n")
if i and e and e.t then b.translate=e.t end;b.personal={}
pcall(function()local o=(a.who=="root")and"/root"or
("/home/".. (a.who or""))
local n=o.."/.launcher.cfg"if
not(a.F and a.F.exists and a.F.exists(n))then return end
local k=a.F.readFile and a.F.readFile(n)if not k or#k==0 or#k>8192 then return end
local p,l=pcall(require,"kernel.serialize")local q,m=pcall(require,"shell.launcher")if not
(
p and l and l.decode and q and m and m.normalizeMenu)then return end
local I,J=pcall(l.decode,k,{maxBytes=8192})if not I then return end;local K=m.normalizeMenu(J)
for M,L in ipairs(K.items or{})do if
L.run then
b.personal[#b.personal+1]={label=L.label,run=L.run}end end end)b.pkgCommands={}local j,f=pcall(require,"shell.panels.helpers")local g,d=false,
nil
if not(j and f.mayHavePackages)or
f.mayHavePackages()then g,d=pcall(require,"kernel.pkg")end
if g and d and d.commands then local l,k=pcall(d.commands)if
l and type(k)=="table"then b.pkgCommands=k end end;return b end
function r.refresh(c,a,b)local d=G(c)d.home=b and b.home or false
local e,f=r.buildApps(d)a.apps=e;a.dropped=f;if not a.sel or a.sel>#e then a.sel=1 end end
function r.open(a,b)b=b or{}local f,c=pcall(require,"shell.panels.home")
if f and c and
c.enabled(a)then local g=c.tab(a)
if g then
if not b.background then for h,i in ipairs(a.tabs)do
if i==g then a.activeTab=h;break end end;c.setView(a,"tiles",g)end;c.refresh(a,g)return g end end;local e=B.find(a,"desktop")local d
if e then d=a.tabs[e]if not b.background then
a.activeTab=e end else local g=a.activeTab
d=B.create(a,"desktop","Desktop",{sel=1})if b.background then a.activeTab=g end end;r.refresh(a,d)return d end;local function z(a)
for b,c in ipairs(a.tabs)do if c.type=="shell"then return b end end;return 1 end
local function t(a)return
(a.tier or 1)<2 or a.W<46 or a.H<14 end
local function u(a)local b={x=2,y=4,w=a.W-2,h=math.max(3,a.H-5-2)}local c=(
a.W>=120)and 18 or 14
local d=(a.H>=40)and 5 or 4;return s.tileGrid(b,{tileW=c,tileH=d})end
local function v(a,b)if t(a)then return math.max(1,a.H-6)end;return u(a).perPage end
function r.drawHeader(a,b)local g,c,e=a.D,a.T,a.W;local h=
(a.SC and a.SC.get and a.SC.get("hostname"))or"tos"local f="--:--"
local i,d=pcall(os.date,"*t")
if i and d then f=string.format("%02d:%02d",d.hour,d.min)end
s.drawRail(g,c,2,e,{{label="⌂ ".. (a.who or"?").."@"..h},{text=f,at=
e-8}},{labelFg=c.title or c.fg})end
local function H(b,a)local g,c,e,h=b.D,b.T,b.W,b.H;local i=a.apps or{}local j=v(b,a)
local k=math.max(1,math.ceil(#i/j))
local n=math.floor(((a.sel or 1)-1)/j)+1;local o,l=pcall(require,"kernel.i18n")
local m=(o and l and l.t)or function(K,J,...)return

select("#",...)>0 and string.format(J,...)or J end;local f=i[a.sel]
local d=f and
((f.label or"").." — ".. (f.hint or""))or""
if a.dropped and a.dropped>0 then d=d..
m("desktop.more","   (+%d more via the prompt)",a.dropped)end
local p=(d~="")and{{label=C(d,e-8)}}or{}s.drawRail(g,c,h-1,e,p)
local q=m("desktop.keys","Enter Open · Arrows Move · 1-9 Quick · F2 Tabs · ^Q Shell")local I=(k>1)and(n.."/"..k)or nil
s.drawRampBar(g,c,h,e,q,I,
c.statusbar_fg or c.bar_fg,c.statusbar_bg or c.bar_bg)end
function r.draw(a,b)local d,c,e,j=a.D,a.T,a.W,a.H;if not b.apps then r.refresh(a,b)end;local h=
b.apps or{}d.fill(1,2,e,j-1," ",c.fg,c.bg)
r.drawHeader(a,b)local f=v(a,b)local g=b.sel or 1
local i=math.floor((g-1)/f)*f
if t(a)then
for k=1,f do local q=i+k;local p=h[q]if not p then break end;local l=3+k;local m=(q==g)local n=m and
(c.sel_fg or c.bg)or c.fg;local o=m and
(c.sel_bg or c.highlight)or c.bg
d.fill(1,l,e,1," ",n,o)
local I=(k<=9)and("["..k.."] ")or"    "d.set(2,l,I,m and n or c.dim,o)
d.set(6,l,p.glyph or"•",m and n or(
c.title or c.fg),o)
d.set(8,l,C(tostring(p.label),e-9),n,o)end else local k=u(a)
for l=1,k.perPage do local n=i+l;local m=h[n]if not m then break end;local o=s.tileRect(k,l)if o then
s.drawTile(d,c,o,{glyph=m.glyph,label=m.label,selected=(
n==g),dim=m.pkg})end end end;H(a,b)end
local function A(a,c,d,b)local e=r.resolveApp(c.apps,d)
if e.type=="tab"then a.activeTab=z(a)return 3 elseif
e.type==x then local g,f=pcall(require,"shell.panels.settingsapp")if g and f then
f.open(a)else
a.lastOut={"Settings unavailable: "..tostring(f),a.T.error}end;return 3 elseif e.type==w then
local g,f=pcall(require,"shell.panels.helpers")if g and f and f.logout then f.logout(a)else if a._sudo and a.sudoDrop then
pcall(a.sudoDrop)end
a.E.push("tos_logout",a.displayIdx)end
return 3,"exit"elseif e.type=="cmd"then a.activeTab=z(a)
if b and b.exec then b.exec(e.cmd)end;return 3 end;return 0 end
function r.handleKey(b,a,d,c,e)local g=a.apps or{}
if#g==0 then r.refresh(b,a)g=a.apps end;local f=a.sel or 1;local h=v(b,a)local i=t(b)and 1 or u(b).cols
if c==28 or d==
32 then return A(b,a,f,e)elseif d==17 then b.activeTab=z(b)return 3 elseif d==114 or d==82 then
r.refresh(b,a)return 3 elseif c==203 then if f>1 then a.sel=f-1;return 3 end elseif c==205 then
if f<#g then a.sel=f+1;return 3 end elseif c==200 then if f-i>=1 then a.sel=f-i;return 3 end elseif c==208 then
if f+i<=#g then a.sel=f+i;return 3 end elseif c==201 then a.sel=math.max(1,f-h)return 3 elseif c==209 then
a.sel=math.min(#g,f+h)return 3 elseif c==199 then a.sel=1;return 3 elseif c==207 then a.sel=#g;return 3 elseif d and d>=49 and d<=57 then local k=math.floor(
(f-1)/h)*h;local j=k+ (d-48)if g[j]then a.sel=j;return
A(b,a,j,e)end end;return 0 end
function r.handleClick(b,a,c,d)local h=a.apps or{}local f=v(b,a)local g=math.floor(((a.sel or 1)-1)/
f)*f;local e=nil;if t(b)then
local i=c.y-3;if i>=1 and i<=f then e=g+i end else local i=s.tileHit(u(b),c.x,c.y)if i then
e=g+i end end;if not e or
not h[e]then return 0 end;a.sel=e;if c.button==1 then return 3 end;return
A(b,a,e,d)end
function r.handleScroll(c,a,b)local e=a.apps or{}
local f=(b.dir or 0)>0 and-1 or 1
local d=math.max(1,math.min(#e,(a.sel or 1)+f))if d==a.sel then return 0 end;a.sel=d;return 3 end;return r