local t="shell.keys"local q=require("shell.panels.ui")
local o=require("shell.panels.tabs")local u=require("shell.panels.helpers")local l={}local function r()local a=_G._TOS;return
a and a.kernel or nil end;function l.rowSelectable(a)return a~=nil and
a.kind~="header"end
function l.nextSelectable(b,a,c)local e=
#b;if e==0 then return a end;local d=a
for f=1,e do local g=d+c;if g<1 or g>e then return d end;d=g;if
l.rowSelectable(b[d])then return d end end;return a end;function l.firstSelectable(a)
for b,c in ipairs(a)do if l.rowSelectable(c)then return b end end;return 1 end
function l.refresh(b,a)local e=r()
local c=nil;if e and e.monitorList then
local g,h=pcall(e.monitorList,b.displayIdx,u.sessionOf(b))if g then c=h end end;local d=a.rows and a.rows[a.sel or
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

a.sel<1 or not l.rowSelectable(a.rows[a.sel])then a.sel=l.firstSelectable(a.rows)end end
function l.open(a)local c=o.find(a,"monitor")local b;if c then b=a.tabs[c]a.activeTab=c else
b=o.create(a,"monitor","Monitor",{sel=1,scroll=0,live=true,interval=2})end
l.refresh(a,b)return b end;local m=5;local function p(a)return math.max(1,a-m-1)end
local function v(a,b)local c=p(b)a.scroll=
a.scroll or 0;if#a.rows==0 then a.scroll=0;return end;if
a.sel<=a.scroll then a.scroll=a.sel-1 end;if a.sel>a.scroll+c then
a.scroll=a.sel-c end;local d=math.max(0,#a.rows-c)if
a.scroll>d then a.scroll=d end;if a.scroll<0 then a.scroll=0 end end
function l.draw(b,a)local d,c,e,f=b.D,b.T,b.W,b.H;if not a.rows then l.refresh(b,a)end
v(a,f)d.fill(1,2,e,f-1," ",c.fg,c.bg)
q.drawRail(d,c,2,e,{{label="§ System Monitor"}},{labelFg=
c.title or c.fg})if a.vitals then
d.set(2,3,a.vitals:sub(1,e-2),c.highlight or c.fg,c.bg)end
local i=string.format(" %-5s %-30s %-9s %-8s %6s","PID","Process","Owner","State","CPU")d.set(1,4,i:sub(1,e),c.dim,c.bg)local j=p(f)
for k=1,j do
local y=a.scroll+k;local x=m+k-1;local w=a.rows[y]
if w then local z=(y==a.sel)
if w.kind=="header"then local A=" ── ".. (w.text or
"").." "
local B=math.max(0,e-#A)
d.set(1,x,A..string.rep("─",B),c.title,c.bg)elseif w.kind=="proc"then local B=w.isFg and"*"or" "
local A=string.format("%s%-5d %-30s %-9s %-8s %5.1fs",B,w.pid,tostring(w.label):sub(1,30),tostring(w.owner):sub(1,9),tostring(w.state):sub(1,8),
w.cpu or 0)
if z then
d.fill(1,x,e,1," ",c.sel_fg or c.bg,c.sel_bg or c.highlight)
d.set(1,x,A:sub(1,e),c.sel_fg or c.bg,c.sel_bg or c.highlight)else local C=c.fg;if w.tsr or not w.canAct then C=c.dim end;if w.isFg then
C=c.highlight or c.fg end;d.set(1,x,A:sub(1,e),C,c.bg)end else
local B=w.status or(w.running and"running"or
(w.enabled==false and"disabled"or"stopped"))
local A=string.format("   %-33s %s",tostring(w.name):sub(1,33),B)
if z then
d.fill(1,x,e,1," ",c.sel_fg or c.bg,c.sel_bg or c.highlight)
d.set(1,x,A:sub(1,e),c.sel_fg or c.bg,c.sel_bg or c.highlight)else
d.set(1,x,A:sub(1,e),w.running and(c.highlight or c.fg)or c.dim,c.bg)end end end end;if a.msg then d.fill(1,f-1,e,1," ",c.fg,c.bg)
d.set(2,f-1,tostring(a.msg[1]):sub(1,
e-2),a.msg[2]or c.dim,c.bg)end
local h=a.rows[a.sel]local g
if h and h.kind=="svc"then
g="Enter Start/Stop · Arrows Move · R Refresh · "..
require(t).quitHint(b.who).." Close"else
g="Enter Switch · K Kill · T TSR · Arrows Move · R Refresh · "..
require(t).quitHint(b.who).." Close"end
q.drawRampBar(d,c,f,e,g,nil,c.statusbar_fg or c.bar_fg,c.statusbar_bg or c.bar_bg)end
local function n(a,b,c,e,d)local f=r()if not(f and f.monitorAct)then
b.msg={"Monitor actions unavailable.",a.T.error}return 3 end
local i,g,h=pcall(f.monitorAct,c,e)if not i then g,h=false,g end;if g then
b.msg=d and{d,a.T.highlight}or nil;if c=="switch"then a.suspendIdleDraw=true end else
b.msg={tostring(h or"action failed"),a.T.error}end
l.refresh(a,b)return 3 end
local function s(b,a)local c=a.rows and a.rows[a.sel]if not c then return 0 end
if
c.kind=="svc"then
return n(b,a,"svc",c.name,(c.running and"Stopping "or"Starting ")..
tostring(c.name))elseif c.kind=="proc"then return n(b,a,"switch",c.pid)end;return 0 end
function l.handleKey(b,a,d,c,e)if not a.rows then l.refresh(b,a)end;local f=a.rows
local g=p(b.H)
if require(t).isQuit(d,c,true,b.who)then o.close(b)return 3 elseif c==200 then a.sel=l.nextSelectable(f,a.sel,
-1)return 3 elseif c==208 then
a.sel=l.nextSelectable(f,a.sel,1)return 3 elseif c==201 then
for h=1,g do a.sel=l.nextSelectable(f,a.sel,-1)end;return 3 elseif c==209 then
for h=1,g do a.sel=l.nextSelectable(f,a.sel,1)end;return 3 elseif c==199 then a.sel=l.firstSelectable(f)a.scroll=0;return 3 elseif c==207 then a.sel=#f
if not
l.rowSelectable(f[a.sel])then a.sel=l.nextSelectable(f,a.sel,-1)end;return 3 elseif d==114 or d==82 then l.refresh(b,a)return 3 elseif c==28 then return s(b,a)elseif
d==107 or d==75 then local h=f[a.sel]
if h and h.kind=="proc"then if not h.canAct then
a.msg={"Not permitted.",b.T.warning}return 3 end;return
n(b,a,"kill",h.pid,"Killed PID "..h.pid)end elseif d==116 or d==84 then local h=f[a.sel]
if h and h.kind=="proc"then if not h.canAct then
a.msg={"Not permitted.",b.T.warning}return 3 end;return n(b,a,"tsr",h.pid)end end;return 0 end
function l.handleClick(c,a,b,d)if not a.rows then l.refresh(c,a)end;local e=(a.scroll or 0)+ (
b.y-m+1)local f=a.rows[e]if b.y>=m and f and
l.rowSelectable(f)then
if e==a.sel and b.button~=1 then return s(c,a)end;a.sel=e;return 3 end;return 0 end
function l.handleScroll(b,a,c)if not a.rows then l.refresh(b,a)end;local e=
(c.dir or 0)>0 and-1 or 1
local d=l.nextSelectable(a.rows,a.sel,e)if d==a.sel then return 0 end;a.sel=d;return 3 end;function l.tick(a,b)l.refresh(a,b)return 3 end;return l