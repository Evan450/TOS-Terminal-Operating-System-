local p=require("shell.panels.ui")
local n=require("shell.panels.tabs")local s=require("shell.panels.helpers")local k={}local function q()local a=_G._TOS;return
a and a.kernel or nil end;function k.rowSelectable(a)return a~=nil and
a.kind~="header"end
function k.nextSelectable(b,a,c)local e=
#b;if e==0 then return a end;local d=a
for f=1,e do local g=d+c;if g<1 or g>e then return d end;d=g;if
k.rowSelectable(b[d])then return d end end;return a end;function k.firstSelectable(a)
for b,c in ipairs(a)do if k.rowSelectable(c)then return b end end;return 1 end
function k.refresh(b,a)local e=q()
local c=nil;if e and e.monitorList then
local g,h=pcall(e.monitorList,b.displayIdx,s.sessionOf(b))if g then c=h end end;local d=a.rows and a.rows[a.sel or
0]or nil;a.rows=(c and
c.rows)or{}
a.vitals=c and c.vitals or nil;if not c then
a.msg={"System monitor data unavailable.",b.T.error}end;local f=nil
if d then
for h,g in ipairs(a.rows)do
if
(d.kind=="proc"and g.kind==
"proc"and g.pid==d.pid)or
(d.kind=="svc"and g.kind=="svc"and g.name==d.name)then f=h;break end end end;a.sel=f or math.min(a.sel or 1,#a.rows)
if

a.sel<1 or not k.rowSelectable(a.rows[a.sel])then a.sel=k.firstSelectable(a.rows)end end
function k.open(a)local c=n.find(a,"monitor")local b;if c then b=a.tabs[c]a.activeTab=c else
b=n.create(a,"monitor","Monitor",{sel=1,scroll=0,live=true,interval=2})end
k.refresh(a,b)return b end;local l=5;local function o(a)return math.max(1,a-l-1)end
local function t(a,b)local c=o(b)a.scroll=
a.scroll or 0;if#a.rows==0 then a.scroll=0;return end;if
a.sel<=a.scroll then a.scroll=a.sel-1 end;if a.sel>a.scroll+c then
a.scroll=a.sel-c end;local d=math.max(0,#a.rows-c)if
a.scroll>d then a.scroll=d end;if a.scroll<0 then a.scroll=0 end end
function k.draw(b,a)local d,c,e,f=b.D,b.T,b.W,b.H;if not a.rows then k.refresh(b,a)end
t(a,f)d.fill(1,2,e,f-1," ",c.fg,c.bg)
p.drawRail(d,c,2,e,{{label="§ System Monitor"}},{labelFg=
c.title or c.fg})if a.vitals then
d.set(2,3,a.vitals:sub(1,e-2),c.highlight or c.fg,c.bg)end
local i=string.format(" %-5s %-30s %-9s %-8s %6s","PID","Process","Owner","State","CPU")d.set(1,4,i:sub(1,e),c.dim,c.bg)local j=o(f)
for u=1,j do
local x=a.scroll+u;local w=l+u-1;local v=a.rows[x]
if v then local y=(x==a.sel)
if v.kind=="header"then local z=" ── ".. (v.text or
"").." "
local A=math.max(0,e-#z)
d.set(1,w,z..string.rep("─",A),c.title,c.bg)elseif v.kind=="proc"then local A=v.isFg and"*"or" "
local z=string.format("%s%-5d %-30s %-9s %-8s %5.1fs",A,v.pid,tostring(v.label):sub(1,30),tostring(v.owner):sub(1,9),tostring(v.state):sub(1,8),
v.cpu or 0)
if y then
d.fill(1,w,e,1," ",c.sel_fg or c.bg,c.sel_bg or c.highlight)
d.set(1,w,z:sub(1,e),c.sel_fg or c.bg,c.sel_bg or c.highlight)else local B=c.fg;if v.tsr or not v.canAct then B=c.dim end;if v.isFg then
B=c.highlight or c.fg end;d.set(1,w,z:sub(1,e),B,c.bg)end else
local A=v.status or(v.running and"running"or
(v.enabled==false and"disabled"or"stopped"))
local z=string.format("   %-33s %s",tostring(v.name):sub(1,33),A)
if y then
d.fill(1,w,e,1," ",c.sel_fg or c.bg,c.sel_bg or c.highlight)
d.set(1,w,z:sub(1,e),c.sel_fg or c.bg,c.sel_bg or c.highlight)else
d.set(1,w,z:sub(1,e),v.running and(c.highlight or c.fg)or c.dim,c.bg)end end end end;if a.msg then d.fill(1,f-1,e,1," ",c.fg,c.bg)
d.set(2,f-1,tostring(a.msg[1]):sub(1,
e-2),a.msg[2]or c.dim,c.bg)end
local h=a.rows[a.sel]local g
if h and h.kind=="svc"then
g="Enter Start/Stop · Arrows Move · R Refresh · ^Q Close"else g="Enter Switch · K Kill · T TSR · Arrows Move · R Refresh · ^Q Close"end
p.drawRampBar(d,c,f,e,g,nil,c.statusbar_fg or c.bar_fg,c.statusbar_bg or c.bar_bg)end
local function m(a,b,c,e,d)local f=q()if not(f and f.monitorAct)then
b.msg={"Monitor actions unavailable.",a.T.error}return 3 end
local i,g,h=pcall(f.monitorAct,c,e)if not i then g,h=false,g end;if g then
b.msg=d and{d,a.T.highlight}or nil;if c=="switch"then a.suspendIdleDraw=true end else
b.msg={tostring(h or"action failed"),a.T.error}end
k.refresh(a,b)return 3 end
local function r(b,a)local c=a.rows and a.rows[a.sel]if not c then return 0 end
if
c.kind=="svc"then
return m(b,a,"svc",c.name,(c.running and"Stopping "or"Starting ")..
tostring(c.name))elseif c.kind=="proc"then return m(b,a,"switch",c.pid)end;return 0 end
function k.handleKey(b,a,d,c,e)if not a.rows then k.refresh(b,a)end;local f=a.rows
local g=o(b.H)
if require("shell.keys").isQuit(d,c,true,b.who)then
n.close(b)return 3 elseif c==200 then a.sel=k.nextSelectable(f,a.sel,-1)return 3 elseif c==208 then
a.sel=k.nextSelectable(f,a.sel,1)return 3 elseif c==201 then
for h=1,g do a.sel=k.nextSelectable(f,a.sel,-1)end;return 3 elseif c==209 then
for h=1,g do a.sel=k.nextSelectable(f,a.sel,1)end;return 3 elseif c==199 then a.sel=k.firstSelectable(f)a.scroll=0;return 3 elseif c==207 then a.sel=#f
if not
k.rowSelectable(f[a.sel])then a.sel=k.nextSelectable(f,a.sel,-1)end;return 3 elseif d==114 or d==82 then k.refresh(b,a)return 3 elseif c==28 then return r(b,a)elseif
d==107 or d==75 then local h=f[a.sel]
if h and h.kind=="proc"then if not h.canAct then
a.msg={"Not permitted.",b.T.warning}return 3 end;return
m(b,a,"kill",h.pid,"Killed PID "..h.pid)end elseif d==116 or d==84 then local h=f[a.sel]
if h and h.kind=="proc"then if not h.canAct then
a.msg={"Not permitted.",b.T.warning}return 3 end;return m(b,a,"tsr",h.pid)end end;return 0 end
function k.handleClick(c,a,b,d)if not a.rows then k.refresh(c,a)end;local e=(a.scroll or 0)+ (
b.y-l+1)local f=a.rows[e]if b.y>=l and f and
k.rowSelectable(f)then
if e==a.sel and b.button~=1 then return r(c,a)end;a.sel=e;return 3 end;return 0 end
function k.handleScroll(b,a,c)if not a.rows then k.refresh(b,a)end;local e=
(c.dir or 0)>0 and-1 or 1
local d=k.nextSelectable(a.rows,a.sel,e)if d==a.sel then return 0 end;a.sel=d;return 3 end;function k.tick(a,b)k.refresh(a,b)return 3 end;return k