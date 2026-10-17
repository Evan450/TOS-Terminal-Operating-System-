local v,q="normal","boolean"local m={}local p="/etc/boot.cfg"local t=8192
local u={"swap","power","net","theme","compat","audio","integrityCheck","jbod","services","cron","packages"}m.FEATURES=u
local o={minimal={description="Bare shell — skip every optional subsystem",verbosity="splash",features={swap=false,power=false,net=false,theme=false,compat=false,audio=false,integrityCheck=false,jbod=false,services=false,cron=false,packages=false}},normal={description="Default — optional subsystems load if RAM allows",verbosity="text",features={jbod=false}},full={description="Load every available subsystem (RAM permitting)",verbosity="text",features={swap=true,power=true,net=true,theme=true,compat=true,audio=true,integrityCheck=false,jbod=false,services=true,cron=true,packages=true}},diagnostic={description="Full + integrity check + verbose boot log",verbosity="verbose",features={swap=true,power=true,net=true,theme=true,compat=true,audio=true,integrityCheck=true,jbod=false,services=true,cron=true,packages=true}},safe={description="Safe Mode — kernel + shell only; no services/packages/net",verbosity="text",features={swap=false,power=false,net=false,theme=false,compat=false,audio=false,integrityCheck=false,jbod=false,services=false,cron=false,packages=false}}}m.PROFILES=o
m.PROFILE_ORDER={"minimal",v,"full","diagnostic","safe"}local w={"silent","splash","text","verbose"}
local r={silent=0,splash=1,text=2,verbose=3}m.VERBOSITY=w;local x={silent=4,splash=2,text=1,verbose=0}function m.echoMinLevel(a)
return x[a]or 1 end
local n={profile=v,verbosity=nil,showConfig=true,advanced={},cpuTier=nil,dataTier=nil,ui=nil,repair=false,ramGate=nil}
local function s(a)if type(a)~="table"then a={}end
if not o[a.profile]then a.profile=v end
if a.verbosity~=nil and not r[a.verbosity]then a.verbosity=nil end;if a.showConfig==nil then a.showConfig=true end;a.showConfig=
a.showConfig and true or false;local d={}if
type(a.advanced)=="table"then
for f,e in ipairs(u)do local g=a.advanced[e]if type(g)==q then d[e]=g end end end;a.advanced=d
local b=tonumber(a.cpuTier)
a.cpuTier=(b and b>=1 and b<=3)and math.floor(b)or nil;local c=tonumber(a.dataTier)a.dataTier=(c and c>=1 and c<=3)and
math.floor(c)or nil;if a.ui==
"panels"or a.ui=="tui"then a.ui="home"end
if
a.ui~="home"and a.ui~="cli"and a.ui~="split"then a.ui=nil end;a.repair=a.repair==true
if type(a.ramGate)~=q then a.ramGate=nil end;return a end;m._normalize=s
function m.load(a)
local b={profile=n.profile,verbosity=n.verbosity,showConfig=n.showConfig,advanced={},cpuTier=n.cpuTier,dataTier=n.dataTier,ui=n.ui,repair=n.repair,ramGate=n.ramGate}
if a and a.exists and a.exists(p)then local d,c=pcall(a.readFile,p)
if d and
type(c)=="string"and#c>0 and#c<=t then
local f,e=pcall(require,"kernel.serialize")
if f and e and e.decode then local g=e.decode(c,{maxBytes=t})if
type(g)=="table"then for h,i in pairs(g)do b[h]=i end end end end end;return s(b)end
function m.save(b,a)a=s(a)local d,c=pcall(require,"kernel.serialize")
if not
(d and c and c.encode)then return false,"serialize unavailable"end
local e=c.encode({profile=a.profile,verbosity=a.verbosity,showConfig=a.showConfig,advanced=a.advanced,cpuTier=a.cpuTier,dataTier=a.dataTier,ui=a.ui,repair=a.repair or nil,ramGate=a.ramGate})local f=b.writeFileAtomic or b.writeFile;return f(p,e)end
function m.verbosity(a)a=a or{}return a.verbosity or
(o[a.profile]or o.normal).verbosity end;function m.shows(a,b)return
(r[m.verbosity(a)]or 2)>= (r[b]or 0)end
function m.wants(a,b,c)a=a or{}local d=a.advanced and
a.advanced[b]if type(d)==q then return d end;local e=(o[a.profile]or
o.normal).features;if
type(e[b])==q then return e[b]end;return c~=false end;function m.ramOK(a,b)
if a and type(a.ramGate)==q then return a.ramGate end;return b~=false end
m.PANELS_MIN_KB=1536
function m.ui(a,b)local c=a and a.ui
if c=="cli"or c=="split"or c=="home"then return c end;if a and a.ramGate==true then return"home","auto"end;if type(b)==
"number"and b>0 and b<m.PANELS_MIN_KB then
return"cli","auto"end;return"home","auto"end;m.PATH=p;return m