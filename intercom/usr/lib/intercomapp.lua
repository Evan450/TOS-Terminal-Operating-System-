local n="intercom"
local function o(a,b,c)
if c and a and a>=32 and a<127 then return false end;local e,d=pcall(require,"shell.keys")if e and d and d.is then
return d.is("quit",a,b)end;return a==17 or b==1 end
local function p()local c,b=pcall(require,"shell.keys")local a=c and b and b.label and
b.label("quit")or""
a=a:gsub(" / .*","")return a~=""and a or"^Q"end;local k=require("shell.panels.tabs")local j=require(n)local i={}local function l()return _G._TOS and
_G._TOS.fs end
function i.label()return"Intercom"end
function i.fitLine(a,b)a=tostring(a or"")b=b or 40;if#a>b then return
a:sub(1,math.max(1,b-1)).."~"end;return a end
function i.cueRow(a,b)b=b or 40
local c=(a.severity or"info"):sub(1,4):upper()
local d=string.format(" %-4s %-14s %s",c,a.name:sub(1,14),a.text)return i.fitLine(d,b)end
function i.open(a)local b=k.find(a,n)if b then a.activeTab=b;return a.tabs[b]end
local c={type=n,label=i.label(),sel=1,scroll=0,interval=2,cues={},errors={},log={},status=
nil}i.refresh(c)a.tabs[#a.tabs+1]=c;a.activeTab=#a.tabs
return c end
function i.refresh(a)local b=l()a.cues,a.errors=j.loadCatalog(b)
a.log=j.loadSpool(b)a.cfg=j.loadCfg(b)end
function i.draw(b,a)local e,c,g,w=b.D,b.T,b.W,b.H;local d=2;local h=w-1
e.fill(1,d,g,h-d+1," ",c.fg,c.bg)local f=math.max(24,math.floor(g*0.55))
local q=j.findDrive()local s=q and q.isReady and q.isReady()
local t=s and"TAPE READY"or(q and
"NO TAPE"or"NO DRIVE — text only")e.set(2,d,"Announcements",c.title,c.bg)
e.set(math.max(2,f-#t-1),d,t,
s and c.highlight or c.warning,c.bg)e.set(f,d,"| Heard",c.title,c.bg)local r=h-d-2;local u=1+
(a.scroll or 0)
for z=0,r-1 do local A=a.cues[u+z]
if A then local B=(u+z)==a.sel;local C=B and(
c.sel_fg or c.bg)or c.fg
local D=B and(c.sel_bg or
c.highlight)or c.bg;if B then e.fill(1,d+1+z,f-1,1," ",C,D)end;e.set(1,d+1+z,i.cueRow(A,
f-2),C,D)end end
if#a.cues==0 then
e.set(2,d+1,"No cues catalogued.",c.warning,c.bg)
e.set(2,d+2,"Describe the tape in "..j.CUES_PATH..":",c.dim,c.bg)
e.set(2,d+3,'fuel-low [0001] "Reactor fuel low." [0005] warn',c.dim,c.bg)end
for z,A in ipairs(a.errors)do if d+r-z>=d+1 then
e.set(2,d+r-z+1,("line %d: %s"):format(A.line,A.why):sub(1,
f-3),c.error,c.bg)end end;local v=r;local x=math.max(1,#a.log-v+1)
for z=0,v-1 do
local A=a.log[x+z]
if A then local B=A.severity or"info"
local C=

(B=="critical"or B=="alert")and c.error or(B=="warn")and c.warning or c.dim
e.set(f+2,d+1+z,i.fitLine(j.formatLine(A),g-f-2),C,c.bg)end end
local y=a.status or
"Enter announce  |  T test (local only)  |  R reload  |  "..p().." close"e.fill(1,h,g,1," ",c.fg,c.bg)
e.set(2,h,y:sub(1,g-2),a.statusColor or c.dim,c.bg)end;local function m(a)return a.cues[a.sel]end
function i.handleKey(d,a,b,c)local e=d.T
if o(b,c,true)then
k.close(d)return 3 elseif c==200 then a.sel=math.max(1,(a.sel or 1)-1)if a.sel<= (
a.scroll or 0)then a.scroll=a.sel-1 end
return 3 elseif c==208 then
a.sel=math.min(#a.cues,(a.sel or 1)+1)return 3 elseif b==114 or b==82 then i.refresh(a)
a.status="Catalog reloaded ("..#a.cues.." cues)."a.statusColor=e.highlight;return 3 elseif b==116 or b==84 then local f=m(a)
if not f then return 0 end;local g=j.announce({cue=f,localOnly=true})
a.status=g.played and
("Testing '"..f.name..
"' — playing here, nobody told.")or
("Test failed: ".. (g.errors[1]or"?"))
a.statusColor=g.played and e.highlight or e.error;return 3 elseif c==28 then local f=m(a)if not f then return 0 end;local g=j.announce({cue=f})
if g.sent then
a.status=
"Announced '"..f.name..
"' ("..f.severity..")"..
(g.played and" + tape"or" — text only")a.statusColor=e.highlight else
a.status="Not announced: ".. (g.errors[1]or"?")a.statusColor=e.error end;i.refresh(a)return 3 end;return 0 end
function i.handleScroll(c,a,b)local e=(b.dir or 0)>0 and-1 or 1
local d=math.max(0,math.min(math.max(0,
#a.cues-1),(a.scroll or 0)+e))if d==a.scroll then return 0 end;a.scroll=d;return 3 end
function i.tick(b,a)local c=# (a.log or{})a.log=j.loadSpool(l())if
#a.log~=c then return 3 end;return 0 end;return i