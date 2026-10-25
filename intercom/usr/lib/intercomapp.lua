local l="intercom"local i=require("shell.panels.tabs")
local h=require(l)local g={}local function j()return _G._TOS and _G._TOS.fs end;function g.label()return
"Intercom"end;function g.fitLine(a,b)a=tostring(a or"")b=b or 40
if#a>b then return a:sub(1,math.max(1,
b-1)).."~"end;return a end
function g.cueRow(a,b)
b=b or 40
local c=(a.severity or"info"):sub(1,4):upper()
local d=string.format(" %-4s %-14s %s",c,a.name:sub(1,14),a.text)return g.fitLine(d,b)end
function g.open(a)local b=i.find(a,l)if b then a.activeTab=b;return a.tabs[b]end
local c={type=l,label=g.label(),sel=1,scroll=0,interval=2,cues={},errors={},log={},status=
nil}g.refresh(c)a.tabs[#a.tabs+1]=c;a.activeTab=#a.tabs
return c end
function g.refresh(a)local b=j()a.cues,a.errors=h.loadCatalog(b)
a.log=h.loadSpool(b)a.cfg=h.loadCfg(b)end
function g.draw(b,a)local e,c,m,u=b.D,b.T,b.W,b.H;local d=2;local n=u-1
e.fill(1,d,m,n-d+1," ",c.fg,c.bg)local f=math.max(24,math.floor(m*0.55))
local o=h.findDrive()local q=o and o.isReady and o.isReady()
local r=q and"TAPE READY"or(o and
"NO TAPE"or"NO DRIVE — text only")e.set(2,d,"Announcements",c.title,c.bg)
e.set(math.max(2,f-#r-1),d,r,
q and c.highlight or c.warning,c.bg)e.set(f,d,"| Heard",c.title,c.bg)local p=n-d-2;local s=1+
(a.scroll or 0)
for x=0,p-1 do local y=a.cues[s+x]
if y then local z=(s+x)==a.sel;local A=z and(
c.sel_fg or c.bg)or c.fg
local B=z and(c.sel_bg or
c.highlight)or c.bg;if z then e.fill(1,d+1+x,f-1,1," ",A,B)end;e.set(1,d+1+x,g.cueRow(y,
f-2),A,B)end end
if#a.cues==0 then
e.set(2,d+1,"No cues catalogued.",c.warning,c.bg)
e.set(2,d+2,"Describe the tape in "..h.CUES_PATH..":",c.dim,c.bg)
e.set(2,d+3,'fuel-low [0001] "Reactor fuel low." [0005] warn',c.dim,c.bg)end
for x,y in ipairs(a.errors)do if d+p-x>=d+1 then
e.set(2,d+p-x+1,("line %d: %s"):format(y.line,y.why):sub(1,
f-3),c.error,c.bg)end end;local t=p;local v=math.max(1,#a.log-t+1)
for x=0,t-1 do
local y=a.log[v+x]
if y then local z=y.severity or"info"
local A=

(z=="critical"or z=="alert")and c.error or(z=="warn")and c.warning or c.dim
e.set(f+2,d+1+x,g.fitLine(h.formatLine(y),m-f-2),A,c.bg)end end
local w=a.status or"Enter announce  |  T test (local only)  |  R reload  |  ^Q close"e.fill(1,n,m,1," ",c.fg,c.bg)
e.set(2,n,w:sub(1,m-2),a.statusColor or c.dim,c.bg)end;local function k(a)return a.cues[a.sel]end
function g.handleKey(d,a,b,c)local e=d.T
if b==17 then
i.close(d)return 3 elseif c==200 then a.sel=math.max(1,(a.sel or 1)-1)if a.sel<= (
a.scroll or 0)then a.scroll=a.sel-1 end
return 3 elseif c==208 then
a.sel=math.min(#a.cues,(a.sel or 1)+1)return 3 elseif b==114 or b==82 then g.refresh(a)
a.status="Catalog reloaded ("..#a.cues.." cues)."a.statusColor=e.highlight;return 3 elseif b==116 or b==84 then local f=k(a)
if not f then return 0 end;local m=h.announce({cue=f,localOnly=true})
a.status=m.played and
("Testing '"..f.name..
"' — playing here, nobody told.")or
("Test failed: ".. (m.errors[1]or"?"))
a.statusColor=m.played and e.highlight or e.error;return 3 elseif c==28 then local f=k(a)if not f then return 0 end;local m=h.announce({cue=f})
if m.sent then
a.status=
"Announced '"..f.name..
"' ("..f.severity..")"..
(m.played and" + tape"or" — text only")a.statusColor=e.highlight else
a.status="Not announced: ".. (m.errors[1]or"?")a.statusColor=e.error end;g.refresh(a)return 3 end;return 0 end
function g.handleScroll(c,a,b)local e=(b.dir or 0)>0 and-1 or 1
local d=math.max(0,math.min(math.max(0,
#a.cues-1),(a.scroll or 0)+e))if d==a.scroll then return 0 end;a.scroll=d;return 3 end
function g.tick(b,a)local c=# (a.log or{})a.log=h.loadSpool(j())if
#a.log~=c then return 3 end;return 0 end;return g