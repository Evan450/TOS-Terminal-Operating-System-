local J,P,B,T="screen","string","number","kernel.display"
local G=require("component")local N=require("computer")local z={}local A={}local U={}local E=1;local V=false;local L=nil
local M={}local Q={}local R="auto"local I=0;local H,C=0,0;local function K()local a={}for b in pairs(A)do a[#a+1]=b end
table.sort(a)return a end
local function W(a)local b={}
local d,c=pcall(G.invoke,a,"getKeyboards")
if d and type(c)=="table"then for f,e in ipairs(c)do b[#b+1]=e end;return b end;return b end
local function X(a)if not a then return false end;local c,b=pcall(G.slot,a)
if not c then return true end;return b~=nil and b>=0 end
local function S(a)local b,c={},{}
for d in G.list(a)do if X(d)then b[#b+1]=d else c[#c+1]=d end end;table.sort(b)table.sort(c)if#b>0 then return b,c end;return c,{}end
function z._pair(a,b)local g={}for i,h in ipairs(b)do g[h]=true end;local f,c={},{}
for j,h in ipairs(a)do if h and g[h]and
not f[h]then f[h]=true;c[j]=h end end;local d={}
for i,h in ipairs(b)do if not f[h]then d[#d+1]=h end end;local e=1
for h=1,#a do if not c[h]and e<=#d then c[h]=d[e]e=e+1 end end;return c end
function z.init()A={}M={}Q={}local j,f=S("gpu")local b,g=S(J)local a={}for l,k in ipairs(j)do
a[#a+1]=G.proxy(k)end;local h={}
for k,l in ipairs(a)do local n,m=pcall(l.getScreen)h[k]=(n and
type(m)==P)and m or false end;local i=z._pair(h,b)local c={}for k=1,#a do
if i[k]then c[#c+1]={gpu=a[k],scr=i[k]}end end;if#c==0 then local k=G.list("gpu")()
local l=G.list(J)()
if k and l then c[1]={gpu=G.proxy(k),scr=l,label="Primary"}end end;local e={}
for l,k in
ipairs(c)do local m=U[k.scr]if m and not e[m]then k.idx=m;e[m]=true end end;for l,k in ipairs(c)do
if not k.idx then local m=1;while e[m]do m=m+1 end;k.idx=m;e[m]=true end;U[k.scr]=k.idx end
for l,k in
ipairs(c)do local m,n,o=k.gpu,k.scr,k.idx;pcall(m.bind,n)do
local t,u=z.gpuTarget(m,n,L or{mode="auto"})z.applyResolution(m,t,u)end
local q,r=m.getResolution()local s=m.getDepth()local p=W(n)
A[o]={gpu=m,screen=n,w=q,h=r,depth=s,label=k.label or("Screen "..o),keyboards=p}Q[n]=o;for l,t in ipairs(p)do M[t]=o end end;local d=K()
if#d>0 then local k=0;local l=S("keyboard")
for n,m in ipairs(l)do
if not M[m]then k=k+1;local o=d[
((k-1)%#d)+1]M[m]=o
A[o].keyboards=A[o].keyboards or{}A[o].keyboards[#A[o].keyboards+1]=m end end end
do local l,k=pcall(require,"kernel.log")
if l and k and k.info then
k.info(J,string.format("Seat init: %d displays paired from %d GPUs and %d screens (local-only)",
#d,#a,#b))
if#a<#b then
k.warn(J,string.format("Detected %d screens but only %d GPUs — %d screen(s) will sit unused. ".."Add a GPU card per additional seat.",
#b,#a,#b-#a))elseif#b<#a then
k.warn(J,string.format("Detected %d GPUs but only %d screens — %d GPU(s) idle.",#a,#b,#a-#b))end
if#g>0 or#f>0 then
k.warn(J,string.format("Component network is SHARED: %d remote screen(s) and %d remote GPU(s) "..
"belong to another computer cabled to this one.",#g,#f))
k.warn(J,"TOS uses only its own local hardware, but the other machine's OS "..
"may bind to THIS screen — OC has no ownership lock. Symptom: two "..

"systems drawing over each other. Fix: unplug the link, or give ".."each machine its own screen and keyboard.")end end end;if not A[E]then E=d[1]or 1 end;V=true;return#d end;local function D()if not V then z.init()end end
function z.count()D()return#K()end;function z.indices()D()return K()end;function z.active()D()
if not A[E]then E=K()[1]or 1 end;return A[E]end
function z.get(a)D()return A[a]end
function z.setActive(a)D()if A[a]then E=a;return true end;return false end
function z.rebuild()local a={}for e,f in pairs(A)do a[f.screen]=e end;z.init()local b={}for e,f in
pairs(A)do b[f.screen]=e end;local c,d={},{}for e,f in pairs(b)do
if not a[e]then c[#c+1]=f end end
for e,f in pairs(a)do if not b[e]then d[#d+1]=f end end;return c,d end
function z.next()D()local a=K()if#a==0 then return nil end;local b=1
for c,d in ipairs(a)do if d==E then b=c;break end end;E=a[(b%#a)+1]return A[E]end;function z.gpu()local a=z.active()return a and a.gpu end
function z.getResolution()
local a=z.active()if a then return a.w,a.h end;return 50,16 end
function z.onResized(a,b,c)D()local d=false
for f,e in ipairs(A)do
if a==nil or e.screen==a then local g,h=b,c
if e.gpu then
local k,i,j=pcall(e.gpu.getResolution)if k and i and j then g,h=i,j end end;if
type(g)==B and type(h)==B and g>0 and h>0 and(g~=e.w or h~=e.h)then e.w,e.h=g,h
d=true end end end
if d then z.invalidateAll()local f,e=pcall(require,T)if
f and e and e.refreshSize then pcall(e.refreshSize)end end;return d end;local F={colsPerBlock=10,rowsPerBlock=4,prefW=80,prefH=25}
local function O(a,b,c)if a<b then return b elseif a>c then return c else
return a end end
function z.specFromConfig(a)
local b={mode="auto",colsPerBlock=F.colsPerBlock,rowsPerBlock=F.rowsPerBlock,prefW=F.prefW,prefH=F.prefH}if not(a and a.get)then return b end
local e=a.get("screenRes")
if type(e)==P then local f=e:lower()
if f=="max"then b.mode="max"elseif f=="auto"then b.mode="auto"else
local g,i=f:match("^(%d+)%s*[x×]%s*(%d+)$")
if g then b.mode="size"b.w=tonumber(g)b.h=tonumber(i)end end end;local c=tonumber(a.get("screenColsPerBlock"))if
c and c>0 then b.colsPerBlock=c end
local d=tonumber(a.get("screenRowsPerBlock"))if d and d>0 then b.rowsPerBlock=d end;return b end
function z.chooseResolution(a,b,c,d,e)a=a or{mode="auto"}b=
(type(b)==B and b>0)and b or 50;c=
(type(c)==B and c>0)and c or 16;local h=a.mode or"auto"if h=="max"then
return b,c,nil end
if h=="size"then local k,l=a.w or b,a.h or c
local m,n=O(k,1,b),O(l,1,c)local o;if k>b or l>c then
o=string.format("requested %dx%d exceeds max %dx%d (using %dx%d)",k,l,b,c,m,n)end;return m,n,o end;local i=math.min(a.prefW or F.prefW,b)
local j=math.min(a.prefH or F.prefH,c)local f,g
if d and e and d>0 and e>0 then
f=math.floor(d*
(a.colsPerBlock or F.colsPerBlock)+0.5)
g=math.floor(e* (a.rowsPerBlock or F.rowsPerBlock)+
0.5)else f=a.prefW or F.prefW;g=a.prefH or F.prefH end;return O(f,i,b),O(g,j,c),nil end
function z.gpuTarget(a,b,c)if not a then return 50,16,"no gpu"end;local d,e=50,16
local j,f,g=pcall(a.maxResolution)if j and f and g then d,e=f,g end
if not b and a.getScreen then
local l,k=pcall(a.getScreen)if l and type(k)==P then b=k end end;local h,i
if b then local m,k,l=pcall(G.invoke,b,"getAspectRatio")if
m and type(k)==B and type(l)==B then h,i=k,l end end;return z.chooseResolution(c,d,e,h,i)end
function z.applyResolution(a,b,c)if not a then return false end;local d=(pcall(a.setResolution,b,c))==
true
if d then local f,e=pcall(require,T)if f and e and
e.refreshSize then pcall(e.refreshSize)end end;return d end;function z.setPolicy(a)L=a end;function z.getPolicy()return L end
function z.setBuffer(a)
if
a~="auto"and a~="on"and a~="off"then return false,"mode must be auto, on, or off"end;R=a;I=I+1;return true end;function z.invalidateAll()I=I+1 end;function z.bufferMode()return R end;function z.bufferStats()local a=H+C
return{skipped=H,emitted=C,total=a,ratio=
a>0 and(H/a)or 0}end
function z.resetBufferStats()H,C=0,0 end;function z._shadowWanted(a,b,c,d)if a=="off"then return false end;if a=="on"then
return(b or 0)> (c or 0)end
return(b or 0)> (c or 0)+ (d or 0)end
function z.fitDisplay(b,a)
D()local c=A[b]or z.active()if not c or not c.gpu then
return nil,nil,"no display"end;a=a or L or{mode="auto"}
local d,e,f=z.gpuTarget(c.gpu,c.screen,a)if z.applyResolution(c.gpu,d,e)then c.w,c.h=d,e end;return d,e,f end;function z.fit(a)return z.fitDisplay(E,a)end
function z.restore(a)return z.fitDisplay(a or E,L or
{mode="auto"})end
function z.list()D()local a={}for c,b in ipairs(K())do local e=A[b]
a[#a+1]={index=b,label=e.label,w=e.w,h=e.h,depth=e.depth,screen=e.screen,active=(b==E)}end;return a end
function z.setLabel(a,b)if A[a]then A[a].label=b;return true end;return false end;function z.displayForKeyboard(a)D()return M[a]end
function z.displayForScreen(a)D()return Q[a]end
function z.seatDevices(a)D()local b=A[a]if not b then return nil end;local c
if b.gpu then
local e,d=pcall(function()return b.gpu.address end)if e and type(d)==P then c=d end end;return{gpu=c,screen=b.screen,keyboards=b.keyboards or{}}end
function z.callerSeat()local c,a=pcall(require,"kernel.process")
if not c or
type(a)~="table"or not a.current then return nil end;local d,b=pcall(a.current)
if not d or type(b)~="table"then return nil end;return b.display end;function z.callerDevices()local a=z.callerSeat()if not a then return nil end
return z.seatDevices(a)end
function z._spanMatches(b,c,d,e,f,a,g,h,i)
for j=1,#a do local l=f+j-1;if
l<1 or l>i then return false end;local m=e+l;if b[m]~=a[j]or c[m]~=g or
d[m]~=h then return false end end;return true end
function z._diffWindow(b,c,d,e,f,a,g,h,i)local k=#a;local j,l;for m=1,k do local n=f+m-1;if n<1 or n>i then return 1,k end;local o=e+n
if b[o]~=
a[m]or c[o]~=g or d[o]~=h then j=j or m;l=m end end;return j,l end
function z._fillWindow(a,b,c,d,e,f,g,h,i,j,k)local l,o,m,n
for p=e,g do local q=(p-1)*k
for r=d,f do local s=q+r;if
a[s]~=h or b[s]~=i or c[s]~=j then
if not l then l,o,m,n=r,p,r,p else if r<l then l=r end;if r>m then m=r end;n=p end end end end;return l,o,m,n end
function z.displayProxy(a)D()local b=A[a]if not b then return nil end;local d={}local e,f=nil,nil;local _,aa=nil,nil
local w,o=nil,nil;local c,g=b.w,b.h;local k,m,l={},{},{}local ak="[\0-\127\194-\255][\128-\191]*"local function j()k,m,l={},{},{}e,f=nil,
nil;_,aa=nil,nil;w,o=nil,nil end;b._writerGen=
b._writerGen or 0;local x=b._writerGen;local h=0;local n=true
local function ab()if h==0 then n=true end
if
b._lastWriter~=d then b._lastWriter=d;b._writerGen=b._writerGen+1 end;if x~=b._writerGen then x=b._writerGen;j()end end
local function ad()b._lastWriter=nil;b._writerGen=b._writerGen+1;x=b._writerGen;j()n=true end;local q=function()end;local function t()
if b.w~=c or b.h~=g then c,g=b.w,b.h;j()q()end end;local ae=384*1024;local af=b.w*b.h*128
local ac
do local aq,ap=pcall(require,"kernel.hal")
if aq and ap and ap.freeMemory then ac=ap.freeMemory(
af+ae)else ac=
(N.freeMemory and N.freeMemory())or 0 end end;local ag=I
local function y()if I~=ag then ag=I;j()end;return z._shadowWanted(R,ac,af,ae)end;local i=nil;local r=false
local function al()local ap=b.gpu;return

not r and ap and ap.allocateBuffer and ap.setActiveBuffer and ap.bitblt and ap.freeBuffer end
q=function()if i then pcall(b.gpu.setActiveBuffer,0)
pcall(b.gpu.freeBuffer,i)i=nil end;h=0;n=true;e,f=nil,nil;w,o=nil,nil end
local function u(ap)if ap~=e then local aq=pcall(b.gpu.setForeground,ap)
if aq then e=ap else e,f=nil,nil end end end
local function s(ap)if ap~=f then local aq=pcall(b.gpu.setBackground,ap)
if aq then f=ap else e,f=nil,nil end end end;local ah=0;local Y=0;local am=1;local v={}
local function ai(ap,aq,ar,as)if h>0 then return end
local at=ar~=nil and v[ar]==nil;local au=as~=nil and v[as]==nil
if not(at or au)then return end;if not(b.gpu and b.gpu.get)then return end;if
ap<1 or ap>c or aq<1 or aq>g then return end
local ax,ay,av,aw=pcall(b.gpu.get,ap,aq)if not ax then return end;if at and type(av)==B then v[ar]=av end;if au and
type(aw)==B then v[as]=aw end end
local function aj(ap,aq)if h>0 then return false end;if not(b.gpu and b.gpu.get)then
return false end
if type(ap)~=B or type(aq)~=B then return false end
if ap<1 or ap>c or aq<1 or aq>g then return false end;local at=(aq-1)*c+ap;local au,ar=k[at],l[at]if au==nil or ar==nil then
return false end
local av=(N.uptime and N.uptime())or 0;if av-ah<am then return false end;ah=av
local aw,ax,ay,as=pcall(b.gpu.get,ap,aq)if not aw then return false end;if ax==au and as== (v[ar]or ar)then
return false end;j()Y=Y+1
if Y==1 then
local aA,az=pcall(require,"kernel.log")
if aA and az and az.warn then
pcall(az.warn,J,string.format("Display cache was wrong at col %d row %d (screen=%s, cache=%s) — "..
"dropped it and repainted. Something moved the glass without ".."declaring it.",ap,aq,
as and string.format("%06X",as)or"?",ar and
string.format("%06X",ar)or"?"))end end;return true end;function d.auditHits()return Y end;local Z=nil
local function an()
if Z==nil then
local aq,ap=pcall(require,"kernel.process")Z=(aq and ap and ap.yieldCooperative)and ap or
false end;if Z then Z.yieldCooperative()end end
function d.set(ap,aq,at,ar,as)if
type(ap)~=B or type(aq)~=B or type(at)~=P then return end;t()ab()
if not y()or aq<1 or aq>g then if ar then
u(ar)end;if as then s(as)end;local aD=pcall(b.gpu.set,ap,aq,at)if not aD then e,f=nil,
nil end;C=C+1;return end;local ax,ay=ar or e,as or f;local av={}
for aD in at:gmatch(ak)do av[#av+1]=aD end;local az=#av;local aA=(aq-1)*c
local au,aw=z._diffWindow(k,m,l,aA,ap,av,ax,ay,c)if au~=1 or aw~=az then local aD=(au~=1)and ap or(ap+az-1)
if
aj(aD,aq)then au,aw=z._diffWindow(k,m,l,aA,ap,av,ax,ay,c)end end;if not au then H=H+1
return end;if ar then u(ar)end;if as then s(as)end
local aB=
(au==1 and aw==az)and at or table.concat(av,"",au,aw)local aC=pcall(b.gpu.set,ap+au-1,aq,aB)
if not aC then e,f=nil,nil;j()return end;C=C+1
for aD=au,aw do local aE=ap+aD-1;if aE>=1 and aE<=c then local aF=aA+aE;k[aF]=av[aD]m[aF]=ax
l[aF]=ay end end;ai(ap+au-1,aq,ax,ay)end
function d.fill(as,at,au,av,ap,aq,ar)
if
type(as)~=B or type(at)~=B or type(au)~=B or type(av)~=B then return end;t()ab()ap=ap or" "
if not y()then if aq then u(aq)end;if ar then s(ar)end
local aH=pcall(b.gpu.fill,as,at,au,av,ap)if not aH then e,f=nil,nil end;C=C+1;return end;local aC,aD=aq or e,ar or f;local ay,az=math.max(1,as),math.max(1,at)local aA,aB=math.min(c,
as+au-1),math.min(g,at+av-1)
if ay>aA or az>
aB then if aq then u(aq)end;if ar then s(ar)end
local aH=pcall(b.gpu.fill,as,at,au,av,ap)if not aH then e,f=nil,nil end;C=C+1;return end;local aw,ax,aE,aF=z._fillWindow(k,m,l,ay,az,aA,aB,ap,aC,aD,c)
if not aw or
aw>ay or ax>az or aE<aA or aF<aB then
local aH,aI=aA,aB;if not aw or aw>ay or ax>az then aH,aI=ay,az end;if aj(aH,aI)then
aw,ax,aE,aF=z._fillWindow(k,m,l,ay,az,aA,aB,ap,aC,aD,c)end end;if not aw then H=H+1;return end;if aq then u(aq)end;if ar then s(ar)end;local aG=pcall(b.gpu.fill,aw,ax,
aE-aw+1,aF-ax+1,ap)if not aG then
e,f=nil,nil;j()return end;C=C+1
for aH=ax,aF do local aI=(aH-1)*c;for aJ=aw,aE do local aK=aI+aJ
k[aK]=ap;m[aK]=aC;l[aK]=aD end end;ai(aw,ax,aC,aD)end
function d.clear(ap)t()ab()if ap then s(ap)end
local aq=pcall(b.gpu.fill,1,1,c,g," ")if not aq then e,f=nil,nil;j()return end;if y()then local ar,as=e,ap or f;for at=1,c*g do k[at]=" "
m[at]=ar;l[at]=as end end end;function d.getSize()return b.w,b.h end
function d.beginFrame()if not al()then return false end
t()h=h+1;if h>1 then return true end;if not i then
local aq,a=pcall(b.gpu.allocateBuffer,c,g)
if not aq or type(a)~=B or a<=0 then r=true;h=0;return false end;i=a end
local ap=pcall(b.gpu.setActiveBuffer,i)if not ap then q()r=true;return false end;_,aa=e,f;e,f=w,o
if n then if
pcall(b.gpu.bitblt,i,1,1,c,g,0,1,1)then n=false else j()end end;return true end
function d.endFrame()if h==0 then return false end;h=h-1;if h>0 then return true end;local ap=false;if i then
ap=pcall(b.gpu.bitblt,0,1,1,c,g,i,1,1)end
local aq=pcall(b.gpu.setActiveBuffer,0)w,o=e,f;e,f=_,aa;if not aq then q()r=true end
if not ap then e,f=nil,nil;j()n=true;return false end;n=false;return true end;function d.hasBackbuffer()return i~=nil end
function d.getGpu()ad()q()return b.gpu end;function d.invalidate()j()end;function d.getGpuTier()local ap=b.depth or 1
if ap>=8 then return 3 elseif ap>=4 then return 2 else return 1 end end;function d.getGpuDepth()return
b.depth or 1 end
function d.dump()t()local az,aA,au=k,m,l
local as={lastFg=e,lastBg=f,frameDepth=h,pageStale=n,backbuffer=i~=nil,backBroken=r and true or false,writerGen=b._writerGen,myWriterGen=x,lastWriterIsMe=(
b._lastWriter==d),w=c,h=g}as.shadow=y()local aq=false
if b.gpu and b.gpu.get then
local aC=pcall(b.gpu.get,1,1)aq=aC and true or false end;local aw=(not aq)and as.shadow
local function at(aC,aD,aE)local aF=aC[#aC]if aF and aF.c==aE then
aF.to=aD else aC[#aC+1]={from=aD,to=aD,c=aE}end end;local ax,av,ay={},{},{}
for aC=1,g do an()local aE,aD={},(aC-1)*c;local aF,aG={},{}
for aH=1,c do local aI,aJ,aK;if aq then
local aL,aM,aN,aO=pcall(b.gpu.get,aH,aC)if aL then aI,aJ,aK=aM,aN,aO end elseif aw then
aI,aJ,aK=az[aD+aH],aA[aD+aH],au[aD+aH]end
aE[aH]=(
aI==nil or aI=="")and" "or aI;at(aF,aH,aK)at(aG,aH,aJ)end
ax[aC]=(table.concat(aE):gsub("%s+$",""))av[aC],ay[aC]=aF,aG end;local ar=nil;if as.shadow and next(au)~=nil then ar={}
for aC=1,g do local aE,aD=(aC-1)*c,{}for aF=1,c do at(aD,aF,au[
aE+aF])end;ar[aC]=aD end end
local function aB(aC,aD)if not
(aC and aD)then return nil end;local aE,aF=1,1
for aG=1,c do while aC[aE]and aC[aE].to<aG do aE=
aE+1 end
while aD[aF]and aD[aF].to<aG do aF=aF+1 end;local aI=aC[aE]and aC[aE].c;local aH=aD[aF]and aD[aF].c;if aH~=
nil and aI~=aH then return aG,aI,aH end end;return nil end;local ap=nil;if ar and aq then
for aC=1,g do local aD,aE,aF=aB(av[aC],ar[aC])if aD then ap=ap or{}
ap[#ap+1]={row=aC,col=aD,glass=aE,shadow=aF}end end end
local o=nil
if ap and i and aq then
if pcall(b.gpu.setActiveBuffer,i)then o={}
for aC=1,math.min(#ap,8)do
local aD=ap[aC].row;local aE={}for aF=1,c do local aG,aI,aI,aH=pcall(b.gpu.get,aF,aD)
at(aE,aF,aG and aH or nil)end;o[aD]=aE end
if not pcall(b.gpu.setActiveBuffer,0)then q()r=true end end end;return
{lines=ax,w=c,h=g,source=aq and"glass"or(aw and"shadow"or"empty"),bg=av,fg=ay,shadowBg=ar,disagree=ap,pageBg=o,state=as}end
d.getTheme=function()local aq,ap=pcall(require,T)if aq and ap and ap.getTheme then
return ap.getTheme()end;return
setmetatable({},{__index=function()return 0xFFFFFF end})end
d.c=function(ap)local aq=d.getTheme()return aq[ap]or 0xFFFFFF end;local ao,p=pcall(require,T)
if ao and p and p.withContext then
local ap={"scrollUp","box","dbox","hdivider","menuBar","statusBar","fkeyBar","fit","writeWrapped","dialog","menuBarEx","dropdown","isMonochrome","setTheme"}
for ar,aq in ipairs(ap)do
if p[aq]then
d[aq]=function(...)local at=table.pack(...)
local as=table.pack(pcall(p.withContext,b.gpu,b.w,b.h,function()return
p[aq](table.unpack(at,1,at.n))end))e,f=nil,nil;ad()if not as[1]then error(as[2],0)end;return
table.unpack(as,2,as.n)end end end;d.contextMenu=d.dropdown;d.BOX=p.BOX;d.THEME=p.THEME end;return d end;return z