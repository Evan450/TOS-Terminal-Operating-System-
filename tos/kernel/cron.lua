local x="kernel.users"local A=require("computer")
local y=require("kernel.serialize")local r={}local z="/etc/cron.dat"local q={}local v=1;local t=nil;local p=nil;local s=nil;local u=nil
local B={["fs.read"]=true,["fs.write"]=true,["component"]=true}
local function C(a)if not a then return nil end;local b=nil;local c,d=pcall(require,x)if c then b=d end
if
a.user and b then
if b.sessionFor then local e=b.sessionFor(a.user)if e then return e end end;if b.getUser and b.createSession then local e=b.getUser(a.user)if e then
return b.createSession(e)end end end
if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession end
if b and b.kernelSession then return b.kernelSession()end;return nil end;local function D(a)local b=require("kernel.sandbox")
return b.build({caps=B,session=a})end
function r.init(a)if u and s then
pcall(s.cancelTimer,u)u=nil end;t=a.fs;p=a.log;s=a.event
local b=y.loadFile(t,z)if b then q=b.jobs or{}v=b.nextID or 1 end
if s then u=s.interval(10,function()
r.tick()end,"kernel:cron")end;if p then local c=0;for d in pairs(q)do c=c+1 end
p.info("cron","Scheduler initialized ("..c.." jobs)")end;return true end
local function w()y.saveFile(t,z,{jobs=q,nextID=v})end
function r.add(d,b,a,c)if type(b)~="number"or b<=0 then
return nil,"Invalid interval (must be a positive number)"end
if
type(a)~="string"or a==""then return nil,"Script must be a non-empty string"end
if#a>16384 then return nil,"cron: script too large (max 16 KB)"end;c=c or{}local e,g=nil,0
do local j,i=pcall(require,x)
if j and i and i.currentSession then
local k=i.currentSession()if k then e=k.user;g=k.tier or 0 end end;if
not e and c.kernelMode and _G._TOS and _G._TOS.bootSession then e=_G._TOS.bootSession.user
g=_G._TOS.bootSession.tier or 3 end end
if not e then return nil,"cron: no identity available; refusing to schedule"end;local f=c.user or e
if f~=e and g<2 then return nil,
"cron: tier "..tostring(g).." cannot schedule jobs as '"..
tostring(f).."'"end
if f~=e then local l,i=pcall(require,x)
local j=l and i and i.getUser and i.getUser(f)local k=type(j)=="table"and j.tier or nil
if
type(k)=="number"and k>g then
return nil,"cron: tier "..
tostring(g).." cannot schedule jobs as '"..tostring(f)..
"' (that account outranks you)"end end
if a:sub(1,1)=="/"then local j,i=pcall(require,x)
if j and i and i.canAccessAs then local k;if
i.currentSession then k=i.currentSession()end;if k then
local l=i.canAccessAs(k,a,"r")
if not l then return nil,"cron: caller cannot read '"..a.."'"end end end end;local h=v;v=v+1
q[h]={name=d,interval=b,script=a,lastRun=0,enabled=true,user=f}w()if p then
p.info("cron",string.format("Added job: %s (every %ds, as %s)",d,b,tostring(f or"?")))end;return h end
function r.remove(a)if not q[a]then return false,"No such job"end;local b=q[a].name
q[a]=nil;w()
if p then p.info("cron","Removed job: "..b)end;return true end
function r.setEnabled(a,b)if not q[a]then return false end;q[a].enabled=b;w()return true end
function r.list()local a={}for c,b in pairs(q)do
a[#a+1]={id=c,name=b.name,interval=b.interval,lastRun=b.lastRun,enabled=b.enabled,script=(b.script or""):sub(1,60)}end
table.sort(a,function(c,d)return
c.id<d.id end)return a end
function r.tick()local c=A.uptime()local d={}
local b=_G._TOS and _G._TOS.securefs;local a
do local e,f=pcall(require,"kernel.process")if e then a=f end end
for f,e in pairs(q)do
if e.enabled and(c-e.lastRun)>=e.interval then
e.lastRun=c;local g=C(e)
if not g then if p then
p.warn("cron","Job '"..e.name..
"' skipped: no session for user '"..tostring(e.user).."'")end else
local l=(e.user or"__boot__")local i=d[l]if not i then i=D(g)d[l]=i end;local h,j;local k
if e.script:match("^/")then k="="..
e.script
if b and b.readFile then h,j=b.readFile(e.script,g)elseif t then
h=t.readFile(e.script)if not h then j="Cannot read: "..e.script end else
j="No filesystem available"end else k="=cron:"..e.name;h=e.script end
if not h then if p then
p.warn("cron","Job '"..e.name.."' read failed: "..tostring(j))end else local m,n=load(h,k,"t",i)
if not m then if p then
p.warn("cron",
"Job '"..e.name.."' compile error: "..tostring(n))end elseif a and a.spawn then
local o=a.spawn("cron:"..
(e.name or"?"),function()local E,F=pcall(m)if not E and p then
p.warn("cron","Job '"..e.name..
"' runtime error: "..tostring(F))end end,{source="cron",principal=g,priority=8,tsr=false})if p and o then
p.info("cron","Job '"..e.name.."' started as PID "..tostring(o))end else local o,E=pcall(m)if not o and p then
p.warn("cron",
"Job '"..e.name.."' failed: "..tostring(E))end end end end end end end
function r.shutdown()if u and s then s.cancelTimer(u)end end
do local a=rawget(_G,"_TOS")if
a and a.fs and not t and not a.cronDisabled then
pcall(r.init,{fs=a.fs,log=a.logObj,event=a.event})end end;return r