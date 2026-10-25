local I="unknown"local x=require("rbmk.core")
local w=require("rbmk.skala")local y=require("rbmk.wall")local z={}
local function F(...)for a=1,select("#",...)do
local c,b=pcall(require,(select(a,...)))if c and b then return b end end end;local C=F("component")local D=F("computer")
local A=F("kernel.event","event")local E=F("kernel.screen")
function z.localSource(a)local b=require("rbmk-cmd")a=a or
b.loadCfg()local c=x.mergeLimits(a.limits)
local d=x.mergeGrid(a.grid)local j=b.activeProfile(a)
local e={kind="local",limits=c,grid=d,name=a.name or"rbmk"}local f,g
local function k()local l=b.candidates(j)if#l==0 then
return false,"no console found -- run `rbmk survey`"end;local m=l[1]
if a.address then for q,p in ipairs(l)do
if tostring(p.address):sub(1,
#a.address)==a.address then m=p end end end;g=x.bind(j,b.methodsOf(m.address))
local o,n=pcall(C.proxy,m.address)
if not o or not n then return false,"cannot open the console proxy"end;f=n;return true end;local h,i=0,nil
function e.poll(l)if not f then local r,s=k()
if not r then return
{name=e.name,level="scram",why={s},snap={},cols={},grid=d,limits=c,seq=h,at=l,stale=true}end end
h=h+1;local n,o=b.read(f,g)local m;if n.temp~=nil then i,m=l,0 else
m=i and(l-i)or(c.staleAfter+1)end;local p,q=x.evaluate(n,c,m)return
{name=e.name,level=p,why=q,snap=n,cols=o or
b.readColumns(f,g,d),grid=d,limits=c,seq=h,at=l,stale=(m> (c.staleAfter or 5)),binding=g}end;return e end
function z.netSource(a)a=a or{}local e=x.mergeLimits(a.limits)local c=
tonumber(a.telemetryPort)or x.TELEMETRY_PORT
local f={kind="net",limits=e,port=c}local b,g,h;local d={}
for i in
(C and C.list and C.list("modem")or function()return nil end)do local k,j=pcall(C.proxy,i)if k and j and j.open then pcall(j.open,c)
d[#d+1]=j end end;f.modems=#d
if A and A.on then
h=A.on("modem_message",function(j,j,j,i,j,...)if i~=c then return end
local k=x.decodeWire(...)if not k then return end;b=k;g=D and D.uptime()or 0 end,"rbmk.skala")end
function f.close()
if h and A and A.off then pcall(A.off,"modem_message",h)end;for j,i in ipairs(d)do pcall(i.close,c)end end
function f.poll(i)local l=x.frameStale(b and b.seq,g,i,e.staleAfter)
if
not b then
return
{name="(no signal)",level=I,why={#d==0 and"no modem on this machine"or
("listening on port "..c.." -- no frames yet")},snap={},cols={},grid=x.mergeGrid(a.grid),limits=e,seq=0,at=i,stale=true}end;local j,k={},x.mergeGrid(a.grid)
if b.cols then
local m,n=x.unpackColumns(b.cols,w.PARAMS)if m then j,k=m,x.mergeGrid(n)end end
return
{name=b.name,level=b.level,why=b.why or{},snap={temp=b.temp,flux=b.flux,steam=b.steam,water=b.water,rodDepth=b.rodDepth,fuel=b.fuel},cols=j,grid=k,limits=e,seq=b.seq,at=g,stale=l}end;return f end
local G={ok=0x00FF00,warn=0xFFAA00,scram=0xFF0000,unknown=0x888888}
local function H(a)local c,b=pcall(a.getTheme)
if c and type(b)=="table"then return b end
return{bg=0x000000,fg=0xFFFFFF,dim=0xAAAAAA,title=0x00AAFF,error=0xFF0000,warning=0xFFAA00}end
local function v(c,a,b,d,e,f)if a<1 or b<1 then return end;pcall(c.set,a,b,d,e,f)end
local function J(b,a,e,c,d,f)local g=e.W;v(b,1,1,string.rep(" ",g),a.fg,a.bg)
local l=string.format(" %s  INFORMATION OUTPUT ",(
c.name or"rbmk"):upper())v(b,1,1,l,a.title,a.bg)
local i=(c.level or I):upper()local j=G[c.level]or a.dim
if c.stale then i,j="STALE",0xFF00FF end;local k=" "..i.." "
v(b,math.max(1,g-#k+1),1,k,0x000000,j)local h=d.param
local m=string.format(" %s  %s%s   seq %d   %s",
y.page(d.page)and y.page(d.page).label or d.page,h and(h.key.." ")or"",h and h.label or
"",c.seq or 0,f=="net"and"REMOTE"or"LOCAL")v(b,1,2,string.rep(" ",g),a.dim,a.bg)
v(b,1,2,m:sub(1,g),a.dim,a.bg)end
local function K(c,b,a,e,d)local g=e.grid;local f=d.param;local h=x.columnIndex(e.cols)
v(c,1,a.rulerY,string.rep(" ",a.W),b.dim,b.bg)
for i=1,a.gridW do local j=a.mapX+ (i-1)*a.cellW;if a.cellW>=5 then
v(c,j,a.rulerY,string.format("%4d",i),b.dim,b.bg)elseif i%5 ==0 or i==1 then
v(c,j,a.rulerY,tostring(i),b.dim,b.bg)end end
for i=1,a.gridH do local j=a.mapY+ (i-1)
v(c,1,j,string.format("%"..a.rulerW.."d",i),b.dim,b.bg)
for k=1,a.gridW do local o=a.mapX+ (k-1)*a.cellW;local p=h[k..","..i]
local q=w.isChannel(k,i,g)local l,m,n
if not q then l,m,n=string.rep(" ",a.cellW),b.dim,b.bg elseif not p then
l=
a.numeric and"----"or string.rep("\226\150\145",math.min(a.cellW,4))m,n=w.COLOR_MISSING,b.bg else local r=p[f.field]
local s=select(1,w.bandOf(r,f,e.limits))if a.numeric then l,m,n=w.cellText(r),s,b.bg else
l,m,n=string.rep("\226\150\136",math.min(a.cellW,4)),s,b.bg end end;if a.numeric and#l<a.cellW then l=l.." "end
v(c,o,j,l,m,n)
if
d.cur and d.cur.x==k and d.cur.y==i and q then v(c,o,j,l:sub(1,a.cellW),0x000000,m)end end end end
local function L(c,a,b,e,d)if not b.railX then return end;local g,h=b.railX,b.railW
for i=b.rulerY,b.statusY-1 do v(c,g-1,i,string.rep(" ",
h+1),a.dim,a.bg)end;local f=b.rulerY
v(c,g,f,("PARAMETER"):sub(1,h),a.title,a.bg)f=f+2
for j,i in
ipairs(w.railRows(b,d.param and d.param.key))do local k,l=a.fg,a.bg;if i.selected then k,l=0x000000,a.title end
v(c,g,f,(" "..i.text..
string.rep(" ",h)):sub(1,h),k,l)f=f+1 end;f=f+1
if f+#w.BANDS+2 <b.statusY then
v(c,g,f,("SCALE"):sub(1,h),a.title,a.bg)f=f+1
for j,i in ipairs(w.legend(d.param,e.limits))do local k=i.name;if i.at then
k=string.format("%-7s%s",i.name,w.cellText(i.at))end
v(c,g,f,"\226\150\136 ",i.color,a.bg)v(c,g+2,f,k:sub(1,h-2),a.dim,a.bg)f=f+1 end end end
local function M(b,a,d,c,e)local f=d.rulerY;local g=3
v(b,g,f,"REACTOR PARAMETERS",a.title,a.bg)f=f+2
for j,i in ipairs(w.readout(c.snap,nil,e.param,c.limits))do
local k=w.param(i.key)
v(b,g,f,string.format("  %s  %-10s",i.key,k and k.label or""),a.fg,a.bg)v(b,g+16,f,i.text:sub(3),i.color,a.bg)f=f+1 end;f=f+1;v(b,g,f,"LIMITS",a.title,a.bg)f=f+1;local h={}for i in
pairs(c.limits or{})do h[#h+1]=i end;table.sort(h)for j,i in ipairs(h)do if f>=
d.statusY-1 then break end
v(b,g,f,string.format("  %-12s %s",i,tostring(c.limits[i])),a.dim,a.bg)f=f+1 end end
local function N(b,c,d,a,e)local f=d.rulerY+1;local g=G[a.level]or c.dim
if a.stale then g=0xFF00FF end
local h=a.stale and"TELEMETRY STALE"or(a.level or I):upper()
local i=math.max(2,math.floor((d.W-#h-4)/2))
v(b,i,f," "..string.rep(" ",#h+2).." ",0x000000,g)v(b,i,f+1,"  "..h.."  ",0x000000,g)
v(b,i,f+2," "..
string.rep(" ",#h+2).." ",0x000000,g)f=f+4;local j=a.why or{}
if#j==0 then
v(b,4,f,
a.stale and"No frames are arriving from the controller."or"No active warnings.",c.dim,c.bg)else for l,k in ipairs(j)do if f>=d.statusY-1 then break end
v(b,4,f,("* "..k):sub(1,d.W-5),g,c.bg)f=f+1 end end;if a.level=="scram"then f=f+1
v(b,4,f,"The SCRAM latch does not clear itself -- restart the service.",c.dim,c.bg)end end
local function O(b,a,c,e,d)local k=c.rulerY;local i=d.param
local o=d.series and d.series[i.key]or{}local f,g,p=y.range(o)
v(b,3,k,string.format("TREND  %s %s",i.key,i.label),a.title,a.bg)
v(b,3,k+1,p>0 and
string.format("%d samples   low %s   high %s",p,w.cellText(f),w.cellText(g))or"collecting...",a.dim,a.bg)local j=k+3;local l=math.max(3,c.statusY-j-1)
local m=math.max(10,c.W-8)local q=y.chart(o,m,l,f,g)
for h,n in ipairs(q)do local r=1-
((h-1)/math.max(1,l-1))
local s=select(1,w.bandOf(f and g and(f+r* (g-f))or
nil,i,e.limits))v(b,4,j+h-1,n,s,a.bg)end
if f and g then v(b,4+m+1,j,w.cellText(g),a.dim,a.bg)v(b,4+m+1,
j+l-1,w.cellText(f),a.dim,a.bg)end end
local function P(d,a,c,e,b,f)local g=c.statusY
v(d,1,g,string.rep("\226\148\128",c.W),a.dim,a.bg)local h=""
if b.page=="map"and b.cur then
local i=x.columnIndex(e.cols)[b.cur.x..","..b.cur.y]
h=string.format(" ch %d,%d %s ",b.cur.x,b.cur.y,i and(i.kind or"?")or"(not reported)")local j={}for l,k in ipairs(w.readout(e.snap,i,b.param,e.limits))do
j[#j+1]=k.text end
h=h..table.concat(j,"  ")else local i={}for k,j in ipairs(w.readout(e.snap,nil,b.param,e.limits))do
i[#i+1]=j.text end
h=" "..table.concat(i,"  ")end;v(d,1,g+1,string.rep(" ",c.W),a.fg,a.bg)
v(d,1,g+1,h:sub(1,c.W),a.fg,a.bg)
if f and g+2 <=c.H then
v(d,1,g+2,string.rep(" ",c.W),a.dim,a.bg)
v(d,1,g+2,(" N T X K G parameter   TAB page   arrows channel   Q quit"):sub(1,c.W),a.dim,a.bg)end end
function z.drawPane(a,b,c,d)d=d or{}local e=H(a)local g,h=a.getSize()
local f=w.layout(g,h,b.grid)
if not f.ok then pcall(a.clear,e.bg)
v(a,1,1,(
(b.name or"rbmk"):upper().."  "..
(b.stale and"STALE"or(b.level or"?"):upper())):sub(1,g),
G[b.level]or e.fg,e.bg)local i=3
for k,j in ipairs(w.readout(b.snap,nil,c.param,b.limits))do if i>h-2 then
break end;v(a,2,i,j.text,j.color,e.bg)i=i+1 end
v(a,1,h,(f.why or"screen too small"):sub(1,g),e.dim,e.bg)return f end;if a.beginFrame then pcall(a.beginFrame)end
pcall(a.clear,e.bg)J(a,e,f,b,c,d.srcKind)
if c.page=="map"then K(a,e,f,b,c)L(a,e,f,b,c)elseif
c.page=="panel"then M(a,e,f,b,c)elseif c.page=="alarms"then N(a,e,f,b,c)elseif c.page=="trend"then
O(a,e,f,b,c)end;P(a,e,f,b,c,d.interactive)
if a.endFrame then pcall(a.endFrame)end;return f end;local B={UP=200,DOWN=208,LEFT=203,RIGHT=205,TAB=15,ESC=1}
function z.run(a)a=a or{}local g=
a.display or a.D;local j=a.event or A
local m=a.o or function()end;if not g then m("No display available.")return end
local k=require("rbmk-cmd")local d=a.cfg or k.loadCfg()local n=a.mode or"auto"local e
if n=="net"then
e=z.netSource(d)elseif n=="local"then e=z.localSource(d)else
local s=k.candidates(k.activeProfile(d))
e=(#s>0)and z.localSource(d)or z.netSource(d)end;local f,i={},{}
if a.wallMode and E and E.list and E.displayProxy then
local s=E.list()
f=y.plan(#s,d.wall,function(t)return w.param(t)~=nil end)
for t,u in ipairs(s)do i[t]=E.displayProxy(u.index)or g end end;if#f==0 then
f=y.plan(1,d.wall,function(s)return w.param(s)~=nil end)i={g}end
local b={page=f[1].page,param=w.param(f[1].param)or
w.PARAMS[1],cur={x=1,y=1},series={}}
local function o(s)if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end;if j and j.pull then
return j.pull(s)end;return D.pullSignal(s)end
local p=math.max(0.25,tonumber(d.pollInterval)or 1)local l,h,c=true,0,nil
local q,r=pcall(function()
while l do local u=D.uptime()
if u>=h or not c then c=e.poll(u)or c
h=u+p;for V,U in ipairs(w.PARAMS)do
b.series[U.key]=y.push(b.series[U.key],c.snap and c.snap[U.field],240)end end;local R=y.effective(f,c.level,c.stale)
for U,V in ipairs(R)do
local W={page=(U==1)and(
V.overridden and V.page or b.page)or V.page,param=(
U==1)and b.param or
(w.param(V.param)or w.PARAMS[1]),cur=(U==1)and b.cur or nil,series=b.series}
z.drawPane(i[U]or g,c,W,{srcKind=e.kind,interactive=(U==1)})end;local S=math.max(0.05,h-D.uptime())local Q,T,t,s=o(S)
if
Q=="key_down"then
local U=(type(t)=="number"and t>0)and
string.char(t):upper()or""
if U=="Q"or s==B.ESC then l=false elseif w.param(U)then b.param=w.param(U)elseif s==B.TAB then
for V,W in
ipairs(y.PAGES)do if W.id==b.page then
b.page=y.PAGES[(V%#y.PAGES)+1].id;break end end elseif U>="1"and U<="4"and y.PAGES[tonumber(U)]then
b.page=y.PAGES[tonumber(U)].id elseif s==B.LEFT then b.cur.x=math.max(1,b.cur.x-1)elseif s==B.RIGHT then b.cur.x=math.min(c.grid.w,
b.cur.x+1)elseif s==B.UP then
b.cur.y=math.max(1,b.cur.y-1)elseif s==B.DOWN then b.cur.y=math.min(c.grid.h,b.cur.y+1)end;h=0 elseif Q=="touch"then local V,W=t,s;local X,Y=g.getSize()local Z=w.layout(X,Y,c.grid)
local U,_=w.cellAt(Z,V,W,c.grid)if U then b.cur.x,b.cur.y=U,_;h=0 end elseif Q=="interrupted"then l=false end end end)if e.close then pcall(e.close)end;for t,s in ipairs(i)do local u=H(s)
pcall(s.clear,u.bg)end;if not q then
m("Panel error: "..tostring(r))end end;return z