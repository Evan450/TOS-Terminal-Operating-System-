local C,A,D="number","running","unknown_manager"
local function y(...)for a=1,select("#",...)do
local c,b=pcall(require,(select(a,...)))if c and b then return b end end end;local B=require("kernel.serialize")
local s=y("kernel.fs","filesystem")local v=require("computer")local E=y("kernel.event","event")local t
do
local a=y("kernel.log","log")if a and a.info then t=a else
t={info=function()end,warn=function()end,error=function()end}end end;local w="cluster.state"local r={}
r.CLEAR=setmetatable({},{__tostring=function()return"<clear>"end})
local function F()
return
{managers={},domain_id_counter=1,storage_node=nil,jobs={},job_id_counter=1,assignment_id_counter=1,_runtime={compute_bound_in_flight=0,events={},events_head=1,events_size=0,EVENTS_MAX=128,lock_held=false}}end;r._data=F()
function r.withLock(a,...)local b=r._data._runtime;local c=0
while b.lock_held do
local i,j=pcall(E.pull,0.05)
if not i then local k=v.uptime()+0.05;while v.uptime()<k do end end;c=c+1;if c>200 then
error("cluster.state: lock wait timed out (held by stuck caller)",2)end end;b.lock_held=true;local e={...}
local f,d,g,h=pcall(function()return a(table.unpack(e))end)b.lock_held=false;if not f then error(d,2)end;return d,g,h end;local x;function r.init(a)x=a end
local function G(a)
if type(a)~="table"then return false,"root not a table"end
if type(a.managers)~="table"then return false,"managers not a table"end
if type(a.jobs)~="table"then return false,"jobs not a table"end;if type(a.domain_id_counter)~=C then
return false,"domain_id_counter not a number"end
if
type(a.job_id_counter)~=C then return false,"job_id_counter not a number"end;if type(a.assignment_id_counter)~=C then
return false,"assignment_id_counter not a number"end;if a.storage_node~=nil and
type(a.storage_node)~="table"then
return false,"storage_node not a table"end;return true end
function r.load(a)a=a or x;if not a then return false,"no_state_path"end
if not s.exists or not
s.exists(a)then
t.info(w,"no persisted state at "..a.."; starting fresh")return true,"cold_start"end;local c
if s.readFile then c=s.readFile(a)else local i,k=s.open(a,"r")if not i then t.error(w,"open failed: "..
tostring(k))return false,
"read_failed: "..tostring(k)end
local l={}local j=0
while true do local m=i:read(4096)if not m or m==""then break end;j=j+1;l[j]=m end;i:close()c=table.concat(l)end;if not c or c==""then
t.warn(w,"state file empty; starting fresh")return true,"cold_start"end
local b,e=B.decode(c)
if not b then
t.error(w,"deserialize failed: "..tostring(e))return false,"decode_failed: "..tostring(e)end;local g,f=G(b)
if not g then
t.error(w,"bad state shape: "..f.."; REFUSING to overwrite in-memory state")return false,"bad_state_shape: "..f end;r._data.managers=b.managers;r._data.jobs=b.jobs
r._data.domain_id_counter=b.domain_id_counter;r._data.job_id_counter=b.job_id_counter
r._data.assignment_id_counter=b.assignment_id_counter;r._data.storage_node=b.storage_node;local h=v.uptime()local d=0;for j,i in
pairs(r._data.managers)do i.last_heartbeat=h;d=d+1 end
t.info(w,"loaded state: "..

tostring(d).." manager entries, "..
tostring(b.job_id_counter-1).." historical jobs")return true,"loaded"end
function r.save(a)a=a or x;if not a then return false,"no_state_path"end;local g={}for h,i in
pairs(r._data)do if h~="_runtime"then g[h]=i end end
local d=B.encode(g)local b=a..".tmp"local e=a:match("(.+)/[^/]+$")if e and s.exists and not
s.exists(e)then
if s.makeDirectory then s.makeDirectory(e)end end;local f,c;if s.writeFile then
f,c=s.writeFile(b,d)else local i;i,c=s.open(b,"w")
if i then i:write(d)i:close()f=true end end
if not f then t.error(w,"write tmp failed: "..
tostring(c))return false,"write_failed: "..
tostring(c)end
if s.exists and s.exists(a)and s.remove then pcall(s.remove,a)end
if s.rename then local i,h=s.rename(b,a)
if not i then
t.error(w,"rename failed: "..tostring(h))return false,"rename_failed: "..tostring(h)end else if s.writeFile then s.writeFile(a,d)end;if s.remove then
pcall(s.remove,b)end end;return true end;local z=false
local function u()if not x then return end;local a,b=pcall(r.save,x)
if not a and not z then t.warn(w,
"save deferred: "..tostring(b))end;z=not a end;function r.flush()if z then u()end end
function r.registerManager(b,a)local e=v.uptime()
local c=r._data.managers[b]local d
if c then d=c.domain_id else d=r._data.domain_id_counter;r._data.domain_id_counter=
r._data.domain_id_counter+1 end
r._data.managers[b]={hostname=a.hostname,domain_id=d,profile=a.profile,worker_count=a.worker_count,storage=a.storage or{external_type="none",external_capacity=0},master_path=
a.master_path or"direct",relay_peer=a.relay_peer,has_console=a.has_console,compute_capable=a.compute_capable,cluster_protocol=a.cluster_protocol,software_version=a.software_version,state="active",last_heartbeat=e,last_snapshot=nil,registered_at=
c and c.registered_at or e}u()
r.pushEvent(c and"manager_reregistered"or"manager_registered",{domain_id=d,hostname=a.hostname})return d end
function r.updateManagerHeartbeat(b,a)local c=r._data.managers[b]
if not c then return false,D end;c.last_snapshot=a;c.last_heartbeat=v.uptime()
if a and a.external_type then
if
not c.storage then c.storage={external_type="none",external_capacity=0}end
if c.storage.external_type~=a.external_type then
c.storage.external_type=a.external_type
r.pushEvent("manager_storage_change",{domain_id=c.domain_id,external_type=a.external_type})u()end end;return true end;local H={active=true,degraded=true,draining=true,offline=true}
function r.setManagerState(b,a)
if not
H[a]then return false,"invalid_state: "..tostring(a)end;local c=r._data.managers[b]if not c then return false,D end;if c.state==a then return
true end;local d=c.state;c.state=a
r.pushEvent("manager_state_change",{domain_id=c.domain_id,from=d,to=a})u()return true end
function r.forgetManager(a)local b=r._data.managers[a]if not b then return false,D end;r._data.managers[a]=
nil
r.pushEvent("manager_forgotten",{domain_id=b.domain_id,hostname=b.hostname})u()return true end
function r.listManagers(a)local b={}for d,c in pairs(r._data.managers)do
if(not a)or a(c)then local e={}for f,g in pairs(c)do
e[f]=g end;e.address=d;b[#b+1]=e end end
table.sort(b,function(c,d)
return(
c.domain_id or 0)< (d.domain_id or 0)end)return b end;function r.getManager(a)return r._data.managers[a]end
function r.getManagerByDomainId(a)for c,b in
pairs(r._data.managers)do
if b.domain_id==a then local d={}for e,f in pairs(b)do d[e]=f end;d.address=c;return d end end;return nil end
function r.createJob(a)local b=r._data.job_id_counter
r._data.job_id_counter=r._data.job_id_counter+1
r._data.jobs[b]={job_id=b,submitted_by=a.submitted_by or"?",submitted_at=v.uptime(),state="pending",compute_profile=a.compute_profile or"mixed",retry_policy=
a.retry_policy or"safe",storage_preference=a.storage_preference,result_sink=a.result_sink or"inline",assignments={},spec=a}u()
r.pushEvent("job_submitted",{job_id=b,by=a.submitted_by})return b end
function r.addAssignment(b,a)local d=r._data.jobs[b]if not d then
return nil,"no_such_job: "..tostring(b)end;local c=r._data.assignment_id_counter;r._data.assignment_id_counter=
r._data.assignment_id_counter+1;a.assignment_id=c;a.job_id=b;a.state=
a.state or"pending"a.attempts=a.attempts or 0
d.assignments[c]=a;u()return c end
function r.setAssignmentState(c,d,a,b)local f=r._data.jobs[c]
if not f then return false,"no_such_job"end;local e=f.assignments[d]
if not e then return false,"no_such_assignment"end;local g=e.state;e.state=a;if b then
for h,i in pairs(b)do if i==r.CLEAR then e[h]=nil else e[h]=i end end end
if f.compute_profile=="compute_bound"then
if
g~=A and a==A then r._data._runtime.compute_bound_in_flight=
r._data._runtime.compute_bound_in_flight+1 elseif
g==A and a~=A then
r._data._runtime.compute_bound_in_flight=math.max(0,r._data._runtime.compute_bound_in_flight-1)end end;u()return true end
function r.setJobState(b,a)local c=r._data.jobs[b]
if not c then return false,"no_such_job"end;c.state=a;if a=="done"or a=="failed"or a=="cancelled"then
c.completed_at=v.uptime()end;u()
r.pushEvent("job_state_change",{job_id=b,to=a})return true end
function r.listJobs(a)local b={}
for d,c in pairs(r._data.jobs)do
if(not a)or a(c)then local e,f=0,0
for d,g in
pairs(c.assignments)do f=f+1;if g.state=="completed"then e=e+1 end end
b[#b+1]={job_id=c.job_id,state=c.state,submitted_by=c.submitted_by,submitted_at=c.submitted_at,compute_profile=c.compute_profile,assignments=e.."/"..f}end end
table.sort(b,function(c,d)
return(c.job_id or 0)< (d.job_id or 0)end)return b end;function r.getJob(a)return r._data.jobs[a]end;function r.setStorageNode(a)
r._data.storage_node=a;u()
r.pushEvent("storage_configured",{address=a and a.address})end
function r.updateStorageUsage(a)if not
r._data.storage_node then return end
r._data.storage_node.used=a;r._data.storage_node.last_seen=v.uptime()end
function r.pushEvent(a,b)local c=r._data._runtime
c.events[c.events_head]={time=v.uptime(),kind=a,detail=b}
c.events_head=(c.events_head%c.EVENTS_MAX)+1
if c.events_size<c.EVENTS_MAX then c.events_size=c.events_size+1 end end
function r.recentEvents(a)local c=r._data._runtime
a=math.min(a or 20,c.events_size)local d={}local b=c.events_head-1;if b<1 then b=c.EVENTS_MAX end
for e=1,a do
local f=c.events[b]if f then d[#d+1]=f end;b=b-1;if b<1 then b=c.EVENTS_MAX end end;return d end
function r.incrementComputeBoundInFlight(a)
r._data._runtime.compute_bound_in_flight=
r._data._runtime.compute_bound_in_flight+ (a or 1)if r._data._runtime.compute_bound_in_flight<0 then
r._data._runtime.compute_bound_in_flight=0 end end
function r.computeBoundInFlight()return r._data._runtime.compute_bound_in_flight end;return r