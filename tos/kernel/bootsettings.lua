local n="advanced"local j={}local k=require("kernel.bootcfg")local i="auto"local function l(a,b)if a==
(b or i)then return nil end;return a end
function j.ramLabel(a)
local d,b=pcall(require,"kernel.hal")
if not d or not b or not b.ramSummary then return nil end
local e,c=pcall(function()if a then return a()end;local f=require("computer")
local g=math.floor(((f.totalMemory and
f.totalMemory())or 0)/
1024)local h=b.ramBanks()or 0
return{totalKB=g,modules=h,sticks=b.ramSticks()}end)if
not e or type(c)~="table"or(c.totalKB or 0)<=0 then return nil end;return
b.ramSummary(c.sticks,c.totalKB,c.modules)end
local function o(a)
local b={{key="profile",label="Profile (what loads)",group="basic",values={"minimal","normal","full","diagnostic","safe"},get=function(d)
return d.profile end,set=function(d,e)d.profile=e end,show=function(c)return
(c=="safe")and"SAFE MODE"or c end},{key="verbosity",label="Verbosity (what it says)",group="basic",values={i,"silent","splash","text","verbose"},get=function(d)return
d.verbosity or i end,set=function(d,e)d.verbosity=l(e)end,show=function(c)
return c end},{key="ui",label="Interface (all seats)",group="basic",values={i,"home","split","cli"},get=function(d)return
d.ui or i end,set=function(d,e)d.ui=l(e)end,show=function(c)
if c==i then return
string.format("auto (panels from %d KB, else CLI)",k.PANELS_MIN_KB)end;if c=="cli"then return"CLI shell"end;if c=="split"then
return"panels (split: Shell + Desktop)"end;return"panels (Home: one tab, two views)"end},{key="repair",label="Self-repair next boot",group="basic",values={false,true},get=function(d)return
d.repair==true end,set=function(d,e)d.repair=e end,show=function(c)return c and"RUN ONCE"or
"off"end},{key="showConfig",label="Show this screen at boot",group="basic",values={true,false},get=function(d)return
d.showConfig and true or false end,set=function(d,e)
d.showConfig=e end,show=function(c)return c and"on"or"off"end},{key="cpuTier",label="CPU tier (override)",group=n,values={i,1,2,3},get=function(d)return
d.cpuTier or i end,set=function(d,e)d.cpuTier=l(e)end,show=function(c)return(c==i)and
"auto (detect)"or("Tier "..c)end},{key="dataTier",label="Data Card tier (override)",group=n,values={i,1,2,3},get=function(d)return
d.dataTier or i end,set=function(d,e)d.dataTier=l(e)end,show=function(c)
return
(c==i)and"auto (detect)"or("Tier "..c)end},{key="ramGate",label=
a and("RAM for extras ["..a.."]")or"RAM for extras (override)",group=n,values={i,true,false},get=function(d)if
d.ramGate==nil then return i end;return d.ramGate end,set=function(d,e)
d.ramGate=l(e)end,show=function(c)if c==i then return"auto (measure)"end;return c and"always load"or
"never load"end}}
for d,c in ipairs(k.FEATURES)do
b[#b+1]={key="adv."..c,label="  + "..c,group=n,values={i,true,false},get=function(e)
local f=e.advanced and e.advanced[c]if f==nil then return i end;return f end,set=function(e,f)e.advanced=
e.advanced or{}e.advanced[c]=l(f)end,show=function(e)if
e==i then return"auto"end;return e and"on"or"off"end}end;return b end
function j.fields(a,b)a=k._normalize(a or{})local c={}for e,d in ipairs(o(b))do
c[#c+1]={key=d.key,label=d.label,group=d.group,value=d.show(d.get(a))}end;return c end
function j.cycle(a,b,c)local g=o()local d=g[b]if not d then return a end;local h=d.get(a)local f=d.values;local e=1;for q,r in
ipairs(f)do if r==h then e=q;break end end;e=
((e-1+ (c or 1))%#f)+1;d.set(a,f[e])return k._normalize(a)end
function j.cycleKey(a,b,c)local d=o()
for e,g in ipairs(d)do if g.key==b then return j.cycle(a,e,c)end end;return k._normalize(a)end
local function p(a,c,b)local d={}for f,e in ipairs(j.fields(a,b))do
if e.group=="basic"then d[#d+1]=e end end
if c then
d[#d+1]={header=true,label="Advanced - boot overrides & manual device checks"}
for f,e in ipairs(j.fields(a,b))do if e.group==n then d[#d+1]=e end end end;return d end
local function m(b,a,c)local d=#b;for e=1,d do a=((a-1+c)%d)+1;if b[a]and not b[a].header then
return a end end;return a end
function j.run(b,a)b=k._normalize(b or{})local c=1;local e=0;local g=false;local f=false;local d=a.color or function()
return 0xFFFFFF end;local h,q=nil,nil
local r=j.ramLabel(a.ramProbe)
while true do a.clear()
a.set(2,1,"TOS Boot Settings",d("title"))
a.set(2,2,"/etc/boot.cfg - applies on next boot",d("dim"))local s=p(b,f,r)
if c>#s or(s[c]and s[c].header)then c=m(s,1,0)if
s[c]and s[c].header then c=m(s,c,1)end end;local v=nil
if g and a.sysinfo then
local C=tostring(b.cpuTier).."/"..tostring(b.dataTier)if not h or q~=C then
h=a.sysinfo.gather(nil,{cpuTier=b.cpuTier,dataTier=b.dataTier})q=C end
v=a.sysinfo.rows(h)end;local w=4;local y=a.H or 25;local A=
v and math.min(#v+1,math.floor(y/2))or 0;local t=(y-w+1)-3-A;if
t<4 then t=4 end;if t>#s then t=#s end;if c-e>t then e=c-t end;if c-e<1 then
e=math.max(0,c-1)end;if e>#s-t then e=math.max(0,#s-t)end
for C=1,t do
local E=e+C;local D=s[E]if not D then break end;local F=w+C-1
if D.header then
a.set(2,F,"-- "..D.label,d("title"))else local G=(E==c)and d("section")or d("dim")
a.set(2,F,((
E==c and"> "or"  ")..D.label):sub(1,31),G)
a.set(34,F,D.value,(E==c)and d("value")or d("dim"))end end;if e>0 then a.set(46,w,"^ more",d("title"))end
if
e+t<#s then a.set(46,w+t-1,"v more",d("title"))end;local z=w+t+1
a.set(2,z,"Up/Down: select   Left/Right or Space: change",d("dim"))
a.set(2,z+1,("[S] save   [R] save+reboot   [A] advanced %s   [H] hardware   [Q] cancel"):format(
f and"shown"or"hidden"),d("dim"))
if v then local C=z+3
for E,D in ipairs(v)do if C>=y then break end;if D.role=="section"then
a.set(2,C,"-- "..D.value,d("title"))else
a.set(4,C,
(D.label~=""and(D.label..": ")or"  ")..D.value,d(D.role))end;C=C+1 end end;local B,u,x=a.readKey()
if x==200 then c=m(s,c,-1)elseif x==208 then c=m(s,c,1)elseif x==203 then if
s[c]and s[c].key then j.cycleKey(b,s[c].key,-1)end elseif
x==205 or u==32 then
if s[c]and s[c].key then j.cycleKey(b,s[c].key,1)end elseif u==115 or u==83 then return"save",b elseif u==114 or u==82 then return"reboot",b elseif u==97 or u==65 then
f=not f elseif u==104 or u==72 then g=not g elseif u==113 or u==81 or x==1 then return"cancel",b end end end;return j