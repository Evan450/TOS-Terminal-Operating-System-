
local al,aq,am,ar,as,at="string","key_down","number","Permission denied","kernel.event","suspended"local V=require("computer")local R={}
local T={RUNNING="running",READY="ready",SLEEPING="sleeping",TSR="tsr",DEAD="dead"}local S={}local aa=0;local af=0;local U=nil;local W=nil;local X={}
local au={key_down=true,key_up=true,clipboard=true,touch=true,drag=true,drop=true,scroll=true}local ag=15;local av=16;local Y={}local ab=0
local function aw(d,a,b,c)if type(a)~=al then return end;local e=Y[a]
if not e then if ab>=av then
Y,ab={},0 end;e={codes={},chars={},at=0}Y[a]=e;ab=ab+1 end;local f=V.uptime()
if e.at>0 and f-e.at>ag then e.codes,e.chars={},{}end;e.at=f;local g=(d==aq)or nil
if type(c)==am then e.codes[c]=g end;if type(b)==am and b>0 then e.chars[b]=g end end
function R.keyDown(a,b)local c,d
if type(a)==am then c=a elseif type(a)==al and a~=""then
local g,h=pcall(utf8.codepoint,a,1)if not g then return false end;c,d=h,true else return false end;local f=V.uptime()
local function e(g)if not g or(g.at>0 and f-g.at>ag)then return
false end;return
(d and g.chars or g.codes)[c]==true end;if type(b)=="table"then
for h,g in ipairs(b)do if e(Y[g])then return true end end;return false end;for h,g in pairs(Y)do
if e(g)then return true end end;return false end;R.KEY_STALE=ag;local ah=nil;local function ax()if ah==nil then
local a,b=pcall(require,"kernel.screen")ah=a and b or false end
return ah or nil end;local an=nil
local ai=true;local function Z()ai=true end;local _=nil
function R.withListener(a,b,...)local f=_;_=a;local g,e,h,i,j=pcall(b,...)_=f;if not g then
error(e,0)end;return e,h,i,j end;function R.genOf(a)local b=S[a]return b and b.gen or nil end
local function aj()if
U then return U end;if _ then return _ end;return nil end
local function ay()local a={}
for c,d in pairs(S)do if d.state~=T.DEAD then a[#a+1]=c end end;local b={}for d,c in ipairs(a)do b[c]=S[c].priority or 5 end
table.sort(a,function(c,d)return
b[c]<b[d]end)an=a;ai=false end
local function ao(a)if type(a)~="table"then return nil end;local b={}local c=false
for d,e in pairs(a)do if
type(d)==am and type(e)==al then b[e]=true;c=true elseif type(d)==al and e==true then
b[d]=true;c=true end end;return c and b or nil end
function R.spawn(b,c,a)a=a or{}repeat aa=aa+1 until S[aa]==nil;local f=aa;af=af+1;local o=af
local p=coroutine.create(c)local d=U and S[U]or nil;local g=(a.inherit~=false)
local h=a.principal;local i=a.token;local j=a.cwd;local k=a.stdin;local l=a.stdout;local m=a.stderr;local n=a.display
if
g and d then h=h or d.principal;i=i or d.token;j=j or d.cwd;k=k or d.stdin;l=
l or d.stdout;m=m or d.stderr;n=n or d.display end;local e={}
if a.caps then for q,r in pairs(a.caps)do e[q]=r end elseif g and d and d.caps then for q,r in
pairs(d.caps)do e[q]=r end end;if g and d then local q=d.caps or{}
for r in pairs(e)do if not q[r]then e[r]=nil end end end
S[f]={pid=f,gen=o,name=b or("proc_"..f),coroutine=p,state=T.READY,tsr=
a.tsr or false,priority=a.priority or 5,source=a.source or"user",created=V.uptime(),lastRun=0,cpuTime=0,cpuBudget=a.cpuBudget,signalInterest=ao(a.signalInterest),background=a.background,bgSince=
nil,bgTicks=0,signals={},sigHead=1,sigTail=0,env={},parent=U,principal=h,token=i,caps=e,cwd=j or"/",stdin=k,stdout=l,stderr=m,display=n}Z()return f end;local az=0.05
local function ac()
if coroutine.isyieldable then return coroutine.isyieldable()end;local a,b=coroutine.running()if b==true then return false end
return a~=nil end
function R.yieldCooperative()local a=U and S[U]if not a then return false end
if not ac()then return false end;if V.uptime()- (a._resumeStart or 0)<az then return
false end;a._coopYield=true
coroutine.yield()return true end;R._canYield=ac;function R.inProcess()
return U~=nil and S[U]~=nil and ac()end
function R.pause(a)local b=U and S[U]if not b or not ac()then
return false end
local c=V.uptime()+ (tonumber(a)or 0)
repeat b._coopYield=true;coroutine.yield()until V.uptime()>=c;return true end
function R.setSignalInterest(a)local b=U and S[U]
if not b then return false,"no current process"end;b.signalInterest=ao(a)return true end
function R.currentSession()local a=R.current()return a and a.principal or nil end
function R.currentToken()local a=R.current()return a and a.token or nil end;function R.current()return U and S[U]or nil end
function R.get(a)return S[a]end
function R.list()local a={}
for c,b in pairs(S)do
if b.state~=T.DEAD then
a[#a+1]={pid=b.pid,name=b.name,state=b.state,tsr=b.tsr,priority=b.priority,cpuTime=b.cpuTime,source=b.source,parent=b.parent,user=
b.principal and b.principal.user or nil,caps=(function()if
type(b.caps)~="table"then return nil end;local d={}for e,f in pairs(b.caps)do d[e]=f end
return d end)(),cwd=b.cwd,display=b.display,sigDropped=
b.sigDropped or 0}end end
table.sort(a,function(c,d)return c.pid<d.pid end)return a end
local function ad(a,b)
local c=a.principal and a.principal.tier or 0;if c>=3 then return true end
local d=a.principal and a.principal.user;local e=b.principal and b.principal.user;if d==nil or e==nil then
return
c>=2 and a.display~=nil and a.display==b.display end;if c>=2 then return
d==e or a.display==b.display end;return d==e end
function R.kill(a,b)local c=S[a]if not c then return false,"No such process"end;local e=aj()
if
not e then if not(type(b)=="table"and b.kernel)then return false,
"Permission denied (no caller)"end else
local f=S[e]if f and not ad(f,c)then return false,ar end end;c.state=T.DEAD;Z()if a==W then
if c.parent and S[c.parent]and
S[c.parent].state~=T.DEAD then W=c.parent else R.cycleForeground()end end
for f,g in pairs(X)do if g==a then
if c.parent and
S[c.parent]and S[c.parent].state~=T.DEAD and
S[c.parent].display==f then X[f]=c.parent else X[f]=nil end end end;local d=require(as)d.removeSource("proc:"..a)if d.purgeOwner then
d.purgeOwner(a)end;c._purged=true;return true end
function R.goTSR(a)local d=a or U;local b=S[d]if not b then return false end;local c=aj()
if a and c and a~=c then
local e=S[c]if e and not ad(e,b)then return false,ar end end;b.tsr=true;b.state=T.TSR;return true end;local aA=256
local function aB(a)return a.sigTail-a.sigHead+1 end
local function ae(a,...)
if a.sigHead==nil then a.sigHead,a.sigTail=1,#a.signals end
if aB(a)>=aA then a.signals[a.sigHead]=nil;a.sigHead=a.sigHead+1;a.sigDropped=(
a.sigDropped or 0)+1 end;a.sigTail=a.sigTail+1
a.signals[a.sigTail]=table.pack(...)
if a.sigHead>256 and a.sigHead<=a.sigTail+1 then local c={}local b=1;for d=a.sigHead,a.sigTail
do c[b]=a.signals[d]b=b+1 end;a.signals=c
a.sigTail=b-1;a.sigHead=1 elseif a.sigHead>a.sigTail then a.signals={}a.sigHead,a.sigTail=1,0 end end
function R.signal(a,...)local b=S[a]
if not b or b.state==T.DEAD then return false end;local c=aj()
if not c then return false,"Permission denied (no caller)"end
if a~=c then local d=S[c]if d and not ad(d,b)then return false,ar end end;ae(b,...)return true end
function R.signalKernel(a,...)local b=S[a]
if not b or b.state==T.DEAD then return false end;ae(b,...)return true end
function R.setForeground(a,b,c)
if c and c.kernel then if b then X[b]=a else W=a end;return true end;local d=U and S[U]or nil;if d and b then
local e=d.principal and d.principal.tier or 0
if e<3 and d.display~=b then return false,"Permission denied (wrong seat)"end end
if
d and a then local e=S[a]
local f=e~=nil and e.parent==U and d.display~=nil and e.display==
d.display;if e and not f and not ad(d,e)then
return false,"Permission denied (not your process)"end end;if b then X[b]=a else W=a end;return true end
function R.getForeground(a)if a then return X[a]or W end;return W end
function R.cycleForeground()local a={}
for c,d in pairs(S)do if d.state~=T.DEAD then a[#a+1]=c end end;table.sort(a)if#a==0 then W=nil;return end;local b=1;for c,d in ipairs(a)do
if d==W then b=c;break end end;b=(b%#a)+1;W=a[b]return W end;local ak="/var/crash/preempt.txt"function R.preemptionAvailable()
return type(debug)=="table"and
type(debug.sethook)=="function"end
local function aC(a)
pcall(function()
local b=_G._TOS and _G._TOS.fs;if not b or not b.writeFile then return end
pcall(b.makeDirectory,"/var/crash")
b.writeFile(ak,"pid="..
tostring(a.pid)..
" name="..
tostring(a.name or"?")..
" user="..
tostring(a.principal and
a.principal.user or"?")..
" uptime="..

tostring(V.uptime())..
"\n"..
"This process exceeded its CPU budget and trapped the preemption\n".."error; if the machine then rebooted via the OC watchdog, it was\n"..
"the likely cause.\n")end)end;local function aD()
pcall(function()local a=_G._TOS and _G._TOS.fs;if a and a.remove and a.exists and
a.exists(ak)then a.remove(ak)end end)end;local function aE()
error("scheduler: preempted (wall-clock budget exceeded)",0)end;R.BG_DIVISOR=2;R.BG_GRACE=30
function R.bgShouldResume(c,a,b)a=
a or 0;b=b or 0;if c=="freeze"then return false,"frozen"end;if
c~="always"and a>=R.BG_GRACE then return false,"frozen"end;return(b%
R.BG_DIVISOR)==0,"drowsy"end
local function ap(a,b,c)if not a or not a.background then return end
if b then
a.bgSince,a.bgTicks=nil,0 elseif not a.bgSince then a.bgSince,a.bgTicks=c or V.uptime(),0 end end
function R.bgState(a,b)local c=S[a]if
not c or not c.background or not c.bgSince then return"live"end
local e,d=R.bgShouldResume(c.background,
(b or V.uptime())-c.bgSince,c.bgTicks)return d end
local function aF(a,b,c)if not a.background then return false end
local d=a.display and X[a.display]or nil;if
b==d or(not a.display and b==W)or b==c then ap(a,true)return false end
if
(a.sigTail or 0)>= (a.sigHead or 1)then return false end;ap(a,false)
local e=R.bgShouldResume(a.background,V.uptime()- (a.bgSince or 0),a.bgTicks)a.bgTicks=a.bgTicks+1;return not e end
local function aG(a,b,c)if not a.signalInterest then return false end
if a._coopYield then return false end;if c or not b or b[1]==nil then return false end;if a.sigHead==nil then a.sigHead,a.sigTail=1,
#a.signals end;if
a.sigTail>=a.sigHead then return false end
return not a.signalInterest[b[1]]end
function R.tick(a)if ai then ay()end;local g=an;local b=a and a[1]and au[a[1]]if b and(
a[1]==aq or a[1]=="key_up")then
aw(a[1],a[2],a[3],a[4])end;local d=W
if b and a[2]then local h=ax()
if h then local j;local i=a[1]
if i==aq or i==
"key_up"or i=="clipboard"then
j=h.displayForKeyboard(a[2])elseif
i=="touch"or i=="drag"or i=="drop"or i=="scroll"then j=h.displayForScreen(a[2])end;if j then d=X[j]or W end end end
for i,h in ipairs(g)do local j=S[h]
if j and j.state~=T.DEAD then local k=j.coroutine
local l=coroutine.status(k)
if l=="dead"then j.state=T.DEAD;Z()elseif l==at and aG(j,a,b)then elseif l==at and aF(j,h,d)then elseif l==at then U=h
j.state=T.RUNNING;local n=V.uptime()j._resumeStart=n;local m=nil;if j.sigHead==nil then
j.sigHead,j.sigTail=1,#j.signals end
if j._coopYield then j._coopYield=false
if a and a[1]~=nil then local u
if b then u=(
h==d)else u=not
(j.signalInterest and not j.signalInterest[a[1]])end;if u then ae(j,table.unpack(a,1,a.n))end end elseif j.sigTail>=j.sigHead then
if a and a[1]~=nil then local u;if b then u=(h==d)else
u=not(j.signalInterest and not
j.signalInterest[a[1]])end;if u then
ae(j,table.unpack(a,1,a.n))end end;m=j.signals[j.sigHead]j.signals[j.sigHead]=nil;j.sigHead=j.sigHead+
1 elseif b then if h==d then m=a end else m=a end;local t=0.5
local o=(j.cpuBudget==nil)and t or j.cpuBudget;local s=false;local p=false
if o~=math.huge and type(debug)=="table"and
debug.sethook then local u=n+o
local v=pcall(debug.sethook,k,function()
if V.uptime()>u then
if not p then p=true
j._preempted=true;aC(j)pcall(debug.sethook,aE,"",1)end
error("scheduler: process exceeded wall-clock budget ("..o.."s)",0)end end,"",10000)if v then s=true end end;local q,r
if m then
q,r=coroutine.resume(k,table.unpack(m,1,m.n or#m))else q,r=coroutine.resume(k)end;if s then pcall(debug.sethook,k)end;if p then aD()end;j.cpuTime=
j.cpuTime+ (V.uptime()-n)
j.lastRun=V.uptime()
if not q then j.state=T.DEAD;j.error=tostring(r)Z()elseif
coroutine.status(k)=="dead"then j.state=T.DEAD;Z()else j.state=j.tsr and T.TSR or T.READY end;U=nil end end end;local f,e=nil,nil
for i,h in pairs(S)do
if h.state==T.DEAD then if h.coroutine then h.coroutine=nil end;if not
h._purged then h._purged=true;if f==nil then f,e=pcall(require,as)end
if f and
type(e)=="table"and e.purgeOwner then e.purgeOwner(i)end end end end;local c={}
for h,i in pairs(S)do if i.state==T.DEAD then c[#c+1]=h end end
if#c>3 then table.sort(c)for h=1,#c-3 do S[c[h]]=nil end end
for h,i in pairs(X)do
if not S[i]or S[i].state==T.DEAD then local j=S[i]if
j and j.parent and
S[j.parent]and S[j.parent].state~=T.DEAD and S[j.parent].display==h then
X[h]=j.parent else X[h]=nil end end end end
function R.yield()if R.inProcess()then return coroutine.yield()end end
function R.sleep(a)local b=V.uptime()+ (tonumber(a)or 0)
if
R.inProcess()then while V.uptime()<b do coroutine.yield()end;return end
while V.uptime()<b do local d=math.min(0.05,b-V.uptime())
local c=package.loaded[as]if type(c)=="table"and type(c.pull)=="function"then
c.pull(d)else V.pullSignal(d)end end end;function R.count()local a=0
for c,b in pairs(S)do if b.state~=T.DEAD then a=a+1 end end;return a end;R.STATE=T;return R