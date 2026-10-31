local J="unknown"
local function K(a,b,c)
if c and a and a>=32 and a<127 then return false end;local e,d=pcall(require,"shell.keys")if e and d and d.is then
return d.is("quit",a,b)end;return a==17 or b==1 end;local y=require("rbmk.core")local x=require("rbmk.skala")
local z=require("rbmk.wall")local A={}
local function G(...)for a=1,select("#",...)do
local c,b=pcall(require,(select(a,...)))if c and b then return b end end end;local D=G("component")local E=G("computer")
local B=G("kernel.event","event")local F=G("kernel.screen")
function A.localSource(a)local b=require("rbmk-cmd")a=a or
b.loadCfg()local c=y.mergeLimits(a.limits)
local d=y.mergeGrid(a.grid)local j=b.activeProfile(a)
local e={kind="local",limits=c,grid=d,name=a.name or"rbmk"}local f,g
local function k()local l=b.candidates(j)if#l==0 then
return false,"no console found -- run `rbmk survey`"end;local m=l[1]
if a.address then for q,p in ipairs(l)do
if tostring(p.address):sub(1,
#a.address)==a.address then m=p end end end;g=y.bind(j,b.methodsOf(m.address))
local o,n=pcall(D.proxy,m.address)
if not o or not n then return false,"cannot open the console proxy"end;f=n;return true end;local h,i=0,nil
function e.poll(l)if not f then local r,s=k()
if not r then return
{name=e.name,level="scram",why={s},snap={},cols={},grid=d,limits=c,seq=h,at=l,stale=true}end end
h=h+1;local n,o=b.read(f,g)local m;if n.temp~=nil then i,m=l,0 else
m=i and(l-i)or(c.staleAfter+1)end;local p,q=y.evaluate(n,c,m)return
{name=e.name,level=p,why=q,snap=n,cols=o or
b.readColumns(f,g,d),grid=d,limits=c,seq=h,at=l,stale=(m> (c.staleAfter or 5)),binding=g}end;return e end
function A.netSource(a)a=a or{}local e=y.mergeLimits(a.limits)local c=
tonumber(a.telemetryPort)or y.TELEMETRY_PORT
local f={kind="net",limits=e,port=c}local b,g,h;local d={}
for i in
(D and D.list and D.list("modem")or function()return nil end)do local k,j=pcall(D.proxy,i)if k and j and j.open then pcall(j.open,c)
d[#d+1]=j end end;f.modems=#d
if B and B.on then
h=B.on("modem_message",function(j,j,j,i,j,...)if i~=c then return end
local k=y.decodeWire(...)if not k then return end;b=k;g=E and E.uptime()or 0 end,"rbmk.skala")end
function f.close()
if h and B and B.off then pcall(B.off,"modem_message",h)end;for j,i in ipairs(d)do pcall(i.close,c)end end
function f.poll(i)local l=y.frameStale(b and b.seq,g,i,e.staleAfter)
if
not b then
return
{name="(no signal)",level=J,why={#d==0 and"no modem on this machine"or
("listening on port "..c.." -- no frames yet")},snap={},cols={},grid=y.mergeGrid(a.grid),limits=e,seq=0,at=i,stale=true}end;local j,k={},y.mergeGrid(a.grid)
if b.cols then
local m,n=y.unpackColumns(b.cols,x.PARAMS)if m then j,k=m,y.mergeGrid(n)end end
return
{name=b.name,level=b.level,why=b.why or{},snap={temp=b.temp,flux=b.flux,steam=b.steam,water=b.water,rodDepth=b.rodDepth,fuel=b.fuel},cols=j,grid=k,limits=e,seq=b.seq,at=g,stale=l}end;return f end
local H={ok=0x00FF00,warn=0xFFAA00,scram=0xFF0000,unknown=0x888888}
local function I(a)local c,b=pcall(a.getTheme)
if c and type(b)=="table"then return b end
return{bg=0x000000,fg=0xFFFFFF,dim=0xAAAAAA,title=0x00AAFF,error=0xFF0000,warning=0xFFAA00}end
local function w(c,a,b,d,e,f)if a<1 or b<1 then return end;pcall(c.set,a,b,d,e,f)end
local function L(b,a,e,c,d,f)local g=e.W;w(b,1,1,string.rep(" ",g),a.fg,a.bg)
local l=string.format(" %s  INFORMATION OUTPUT ",(
c.name or"rbmk"):upper())w(b,1,1,l,a.title,a.bg)
local i=(c.level or J):upper()local j=H[c.level]or a.dim
if c.stale then i,j="STALE",0xFF00FF end;local k=" "..i.." "
w(b,math.max(1,g-#k+1),1,k,0x000000,j)local h=d.param
local m=string.format(" %s  %s%s   seq %d   %s",
z.page(d.page)and z.page(d.page).label or d.page,h and(h.key.." ")or"",h and h.label or
"",c.seq or 0,f=="net"and"REMOTE"or"LOCAL")w(b,1,2,string.rep(" ",g),a.dim,a.bg)
w(b,1,2,m:sub(1,g),a.dim,a.bg)end
local function M(c,b,a,e,d)local g=e.grid;local f=d.param;local h=y.columnIndex(e.cols)
w(c,1,a.rulerY,string.rep(" ",a.W),b.dim,b.bg)
for i=1,a.gridW do local j=a.mapX+ (i-1)*a.cellW;if a.cellW>=5 then
w(c,j,a.rulerY,string.format("%4d",i),b.dim,b.bg)elseif i%5 ==0 or i==1 then
w(c,j,a.rulerY,tostring(i),b.dim,b.bg)end end
for i=1,a.gridH do local j=a.mapY+ (i-1)
w(c,1,j,string.format("%"..a.rulerW.."d",i),b.dim,b.bg)
for k=1,a.gridW do local o=a.mapX+ (k-1)*a.cellW;local p=h[k..","..i]
local q=x.isChannel(k,i,g)local l,m,n
if not q then l,m,n=string.rep(" ",a.cellW),b.dim,b.bg elseif not p then
l=
a.numeric and"----"or string.rep("\226\150\145",math.min(a.cellW,4))m,n=x.COLOR_MISSING,b.bg else local r=p[f.field]
local s=select(1,x.bandOf(r,f,e.limits))if a.numeric then l,m,n=x.cellText(r),s,b.bg else
l,m,n=string.rep("\226\150\136",math.min(a.cellW,4)),s,b.bg end end;if a.numeric and#l<a.cellW then l=l.." "end
w(c,o,j,l,m,n)
if
d.cur and d.cur.x==k and d.cur.y==i and q then w(c,o,j,l:sub(1,a.cellW),0x000000,m)end end end end
local function N(c,a,b,e,d)if not b.railX then return end;local g,h=b.railX,b.railW
for i=b.rulerY,b.statusY-1 do w(c,g-1,i,string.rep(" ",
h+1),a.dim,a.bg)end;local f=b.rulerY
w(c,g,f,("PARAMETER"):sub(1,h),a.title,a.bg)f=f+2
for j,i in
ipairs(x.railRows(b,d.param and d.param.key))do local k,l=a.fg,a.bg;if i.selected then k,l=0x000000,a.title end
w(c,g,f,(" "..i.text..
string.rep(" ",h)):sub(1,h),k,l)f=f+1 end;f=f+1
if f+#x.BANDS+2 <b.statusY then
w(c,g,f,("SCALE"):sub(1,h),a.title,a.bg)f=f+1
for j,i in ipairs(x.legend(d.param,e.limits))do local k=i.name;if i.at then
k=string.format("%-7s%s",i.name,x.cellText(i.at))end
w(c,g,f,"\226\150\136 ",i.color,a.bg)w(c,g+2,f,k:sub(1,h-2),a.dim,a.bg)f=f+1 end end end
local function O(b,a,d,c,e)local f=d.rulerY;local g=3
w(b,g,f,"REACTOR PARAMETERS",a.title,a.bg)f=f+2
for j,i in ipairs(x.readout(c.snap,nil,e.param,c.limits))do
local k=x.param(i.key)
w(b,g,f,string.format("  %s  %-10s",i.key,k and k.label or""),a.fg,a.bg)w(b,g+16,f,i.text:sub(3),i.color,a.bg)f=f+1 end;f=f+1;w(b,g,f,"LIMITS",a.title,a.bg)f=f+1;local h={}for i in
pairs(c.limits or{})do h[#h+1]=i end;table.sort(h)for j,i in ipairs(h)do if f>=
d.statusY-1 then break end
w(b,g,f,string.format("  %-12s %s",i,tostring(c.limits[i])),a.dim,a.bg)f=f+1 end end
local function P(b,c,d,a,e)local f=d.rulerY+1;local g=H[a.level]or c.dim
if a.stale then g=0xFF00FF end
local h=a.stale and"TELEMETRY STALE"or(a.level or J):upper()
local i=math.max(2,math.floor((d.W-#h-4)/2))
w(b,i,f," "..string.rep(" ",#h+2).." ",0x000000,g)w(b,i,f+1,"  "..h.."  ",0x000000,g)
w(b,i,f+2," "..
string.rep(" ",#h+2).." ",0x000000,g)f=f+4;local j=a.why or{}
if#j==0 then
w(b,4,f,
a.stale and"No frames are arriving from the controller."or"No active warnings.",c.dim,c.bg)else for l,k in ipairs(j)do if f>=d.statusY-1 then break end
w(b,4,f,("* "..k):sub(1,d.W-5),g,c.bg)f=f+1 end end;if a.level=="scram"then f=f+1
w(b,4,f,"The SCRAM latch does not clear itself -- restart the service.",c.dim,c.bg)end end
local function Q(b,a,c,e,d)local k=c.rulerY;local i=d.param
local o=d.series and d.series[i.key]or{}local f,g,p=z.range(o)
w(b,3,k,string.format("TREND  %s %s",i.key,i.label),a.title,a.bg)
w(b,3,k+1,p>0 and
string.format("%d samples   low %s   high %s",p,x.cellText(f),x.cellText(g))or"collecting...",a.dim,a.bg)local j=k+3;local l=math.max(3,c.statusY-j-1)
local m=math.max(10,c.W-8)local q=z.chart(o,m,l,f,g)
for h,n in ipairs(q)do local r=1-
((h-1)/math.max(1,l-1))
local s=select(1,x.bandOf(f and g and(f+r* (g-f))or
nil,i,e.limits))w(b,4,j+h-1,n,s,a.bg)end
if f and g then w(b,4+m+1,j,x.cellText(g),a.dim,a.bg)w(b,4+m+1,
j+l-1,x.cellText(f),a.dim,a.bg)end end
local function R(d,a,c,e,b,f)local g=c.statusY
w(d,1,g,string.rep("\226\148\128",c.W),a.dim,a.bg)local h=""
if b.page=="map"and b.cur then
local i=y.columnIndex(e.cols)[b.cur.x..","..b.cur.y]
h=string.format(" ch %d,%d %s ",b.cur.x,b.cur.y,i and(i.kind or"?")or"(not reported)")local j={}for l,k in ipairs(x.readout(e.snap,i,b.param,e.limits))do
j[#j+1]=k.text end
h=h..table.concat(j,"  ")else local i={}for k,j in ipairs(x.readout(e.snap,nil,b.param,e.limits))do
i[#i+1]=j.text end
h=" "..table.concat(i,"  ")end;w(d,1,g+1,string.rep(" ",c.W),a.fg,a.bg)
w(d,1,g+1,h:sub(1,c.W),a.fg,a.bg)
if f and g+2 <=c.H then
w(d,1,g+2,string.rep(" ",c.W),a.dim,a.bg)
w(d,1,g+2,(" N T X K G parameter   TAB page   arrows channel   Q quit"):sub(1,c.W),a.dim,a.bg)end end
function A.drawPane(a,b,c,d)d=d or{}local e=I(a)local g,h=a.getSize()
local f=x.layout(g,h,b.grid)
if not f.ok then pcall(a.clear,e.bg)
w(a,1,1,(
(b.name or"rbmk"):upper().."  "..
(b.stale and"STALE"or(b.level or"?"):upper())):sub(1,g),
H[b.level]or e.fg,e.bg)local i=3
for k,j in ipairs(x.readout(b.snap,nil,c.param,b.limits))do if i>h-2 then
break end;w(a,2,i,j.text,j.color,e.bg)i=i+1 end
w(a,1,h,(f.why or"screen too small"):sub(1,g),e.dim,e.bg)return f end;if a.beginFrame then pcall(a.beginFrame)end
pcall(a.clear,e.bg)L(a,e,f,b,c,d.srcKind)
if c.page=="map"then M(a,e,f,b,c)N(a,e,f,b,c)elseif
c.page=="panel"then O(a,e,f,b,c)elseif c.page=="alarms"then P(a,e,f,b,c)elseif c.page=="trend"then
Q(a,e,f,b,c)end;R(a,e,f,b,c,d.interactive)
if a.endFrame then pcall(a.endFrame)end;return f end;local C={UP=200,DOWN=208,LEFT=203,RIGHT=205,TAB=15,ESC=1}
function A.run(a)a=a or{}local g=
a.display or a.D;local j=a.event or B
local m=a.o or function()end;if not g then m("No display available.")return end
local k=require("rbmk-cmd")local d=a.cfg or k.loadCfg()local n=a.mode or"auto"local e
if n=="net"then
e=A.netSource(d)elseif n=="local"then e=A.localSource(d)else
local s=k.candidates(k.activeProfile(d))
e=(#s>0)and A.localSource(d)or A.netSource(d)end;local f,i={},{}
if a.wallMode and F and F.list and F.displayProxy then
local s=F.list()
f=z.plan(#s,d.wall,function(t)return x.param(t)~=nil end)
for t,u in ipairs(s)do i[t]=F.displayProxy(u.index)or g end end;if#f==0 then
f=z.plan(1,d.wall,function(s)return x.param(s)~=nil end)i={g}end
local b={page=f[1].page,param=x.param(f[1].param)or
x.PARAMS[1],cur={x=1,y=1},series={}}
local function o(s)if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end;if j and j.pull then
return j.pull(s)end;return E.pullSignal(s)end
local p=math.max(0.25,tonumber(d.pollInterval)or 1)local l,h,c=true,0,nil
local q,r=pcall(function()
while l do local u=E.uptime()
if u>=h or not c then c=e.poll(u)or c
h=u+p;for W,V in ipairs(x.PARAMS)do
b.series[V.key]=z.push(b.series[V.key],c.snap and c.snap[V.field],240)end end;local S=z.effective(f,c.level,c.stale)
for V,W in ipairs(S)do
local X={page=(V==1)and(
W.overridden and W.page or b.page)or W.page,param=(
V==1)and b.param or
(x.param(W.param)or x.PARAMS[1]),cur=(V==1)and b.cur or nil,series=b.series}
A.drawPane(i[V]or g,c,X,{srcKind=e.kind,interactive=(V==1)})end;local T=math.max(0.05,h-E.uptime())local v,U,t,s=o(T)
if
v=="key_down"then
local V=(type(t)=="number"and t>0)and
string.char(t):upper()or""
if V=="Q"or s==C.ESC or K(t,s,true)then l=false elseif x.param(V)then
b.param=x.param(V)elseif s==C.TAB then
for W,X in ipairs(z.PAGES)do if X.id==b.page then
b.page=z.PAGES[(W%#z.PAGES)+1].id;break end end elseif V>="1"and V<="4"and z.PAGES[tonumber(V)]then
b.page=z.PAGES[tonumber(V)].id elseif s==C.LEFT then b.cur.x=math.max(1,b.cur.x-1)elseif s==C.RIGHT then b.cur.x=math.min(c.grid.w,
b.cur.x+1)elseif s==C.UP then
b.cur.y=math.max(1,b.cur.y-1)elseif s==C.DOWN then b.cur.y=math.min(c.grid.h,b.cur.y+1)end;h=0 elseif v=="touch"then local W,X=t,s;local Y,Z=g.getSize()local _=x.layout(Y,Z,c.grid)
local V,aa=x.cellAt(_,W,X,c.grid)if V then b.cur.x,b.cur.y=V,aa;h=0 end elseif v=="interrupted"then l=false end end end)if e.close then pcall(e.close)end;for t,s in ipairs(i)do local u=I(s)
pcall(s.clear,u.bg)end;if not q then
m("Panel error: "..tostring(r))end end;return A