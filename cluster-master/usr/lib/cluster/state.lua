local A,y,B="number","running","unknown_manager"
local function x(...)for a=1,select("#",...)do
local c,b=pcall(require,(select(a,...)))if c and b then return b end end end;local z=require("kernel.serialize")
local r=x("kernel.fs","filesystem")local t=require("computer")local C=x("kernel.event","event")local s
do
local a=x("kernel.log","log")if a and a.info then s=a else
s={info=function()end,warn=function()end,error=function()end}end end;local u="cluster.state"local q={}
q.CLEAR=setmetatable({},{__tostring=function()return"<clear>"end})
local function D()
return
{managers={},domain_id_counter=1,storage_node=nil,jobs={},job_id_counter=1,assignment_id_counter=1,_runtime={compute_bound_in_flight=0,events={},events_head=1,events_size=0,EVENTS_MAX=128,lock_held=false}}end;q._data=D()
function q.withLock(a,...)local b=q._data._runtime;local c=0
while b.lock_held do
local i,j=pcall(C.pull,0.05)
if not i then local k=t.uptime()+0.05;while t.uptime()<k do end end;c=c+1;if c>200 then
error("cluster.state: lock wait timed out (held by stuck caller)",2)end end;b.lock_held=true;local e={...}
local f,d,g,h=pcall(function()return a(table.unpack(e))end)b.lock_held=false;if not f then error(d,2)end;return d,g,h end;local w;function q.init(a)w=a end
local function E(a)
if type(a)~="table"then return false,"root not a table"end
if type(a.managers)~="table"then return false,"managers not a table"end
if type(a.jobs)~="table"then return false,"jobs not a table"end;if type(a.domain_id_counter)~=A then
return false,"domain_id_counter not a number"end
if
type(a.job_id_counter)~=A then return false,"job_id_counter not a number"end;if type(a.assignment_id_counter)~=A then
return false,"assignment_id_counter not a number"end;if a.storage_node~=nil and
type(a.storage_node)~="table"then
return false,"storage_node not a table"end;return true end
function q.load(a)a=a or w;if not a then return false,"no_state_path"end
if not r.exists or not
r.exists(a)then
s.info(u,"no persisted state at "..a.."; starting fresh")return true,"cold_start"end;local c
if r.readFile then c=r.readFile(a)else local i,k=r.open(a,"r")if not i then s.error(u,"open failed: "..
tostring(k))return false,
"read_failed: "..tostring(k)end
local l={}local j=0
while true do local m=i:read(4096)if not m or m==""then break end;j=j+1;l[j]=m end;i:close()c=table.concat(l)end;if not c or c==""then
s.warn(u,"state file empty; starting fresh")return true,"cold_start"end
local b,e=z.decode(c)
if not b then
s.error(u,"deserialize failed: "..tostring(e))return false,"decode_failed: "..tostring(e)end;local g,f=E(b)
if not g then
s.error(u,"bad state shape: "..f.."; REFUSING to overwrite in-memory state")return false,"bad_state_shape: "..f end;q._data.managers=b.managers;q._data.jobs=b.jobs
q._data.domain_id_counter=b.domain_id_counter;q._data.job_id_counter=b.job_id_counter
q._data.assignment_id_counter=b.assignment_id_counter;q._data.storage_node=b.storage_node;local h=t.uptime()local d=0;for j,i in
pairs(q._data.managers)do i.last_heartbeat=h;d=d+1 end
s.info(u,"loaded state: "..

tostring(d).." manager entries, "..
tostring(b.job_id_counter-1).." historical jobs")return true,"loaded"end
function q.save(a)a=a or w;if not a then return false,"no_state_path"end;local g={}for h,i in
pairs(q._data)do if h~="_runtime"then g[h]=i end end
local d=z.encode(g)local b=a..".tmp"local e=a:match("(.+)/[^/]+$")if e and r.exists and not
r.exists(e)then
if r.makeDirectory then r.makeDirectory(e)end end;local f,c;if r.writeFile then
f,c=r.writeFile(b,d)else local i;i,c=r.open(b,"w")
if i then i:write(d)i:close()f=true end end
if not f then s.error(u,"write tmp failed: "..
tostring(c))return false,"write_failed: "..
tostring(c)end
if r.exists and r.exists(a)and r.remove then pcall(r.remove,a)end
if r.rename then local i,h=r.rename(b,a)
if not i then
s.error(u,"rename failed: "..tostring(h))return false,"rename_failed: "..tostring(h)end else if r.writeFile then r.writeFile(a,d)end;if r.remove then
pcall(r.remove,b)end end;return true end
local function v()if not w then return end;local a,b=pcall(q.save,w)if not a then
s.error(u,"persist failed: "..tostring(b))end end
function q.registerManager(b,a)local e=t.uptime()local c=q._data.managers[b]local d;if c then
d=c.domain_id else d=q._data.domain_id_counter
q._data.domain_id_counter=q._data.domain_id_counter+1 end
q._data.managers[b]={hostname=a.hostname,domain_id=d,profile=a.profile,worker_count=a.worker_count,storage=
a.storage or{external_type="none",external_capacity=0},master_path=a.master_path or"direct",relay_peer=a.relay_peer,has_console=a.has_console,compute_capable=a.compute_capable,cluster_protocol=a.cluster_protocol,software_version=a.software_version,state="active",last_heartbeat=e,last_snapshot=
nil,registered_at=c and c.registered_at or e}v()
q.pushEvent(c and"manager_reregistered"or"manager_registered",{domain_id=d,hostname=a.hostname})return d end
function q.updateManagerHeartbeat(b,a)local c=q._data.managers[b]
if not c then return false,B end;c.last_snapshot=a;c.last_heartbeat=t.uptime()
if a and a.external_type then
if
not c.storage then c.storage={external_type="none",external_capacity=0}end
if c.storage.external_type~=a.external_type then
c.storage.external_type=a.external_type
q.pushEvent("manager_storage_change",{domain_id=c.domain_id,external_type=a.external_type})v()end end;return true end;local F={active=true,degraded=true,draining=true,offline=true}
function q.setManagerState(b,a)
if not
F[a]then return false,"invalid_state: "..tostring(a)end;local c=q._data.managers[b]if not c then return false,B end;if c.state==a then return
true end;local d=c.state;c.state=a
q.pushEvent("manager_state_change",{domain_id=c.domain_id,from=d,to=a})v()return true end
function q.forgetManager(a)local b=q._data.managers[a]if not b then return false,B end;q._data.managers[a]=
nil
q.pushEvent("manager_forgotten",{domain_id=b.domain_id,hostname=b.hostname})v()return true end
function q.listManagers(a)local b={}for d,c in pairs(q._data.managers)do
if(not a)or a(c)then local e={}for f,g in pairs(c)do
e[f]=g end;e.address=d;b[#b+1]=e end end
table.sort(b,function(c,d)
return(
c.domain_id or 0)< (d.domain_id or 0)end)return b end;function q.getManager(a)return q._data.managers[a]end
function q.getManagerByDomainId(a)for c,b in
pairs(q._data.managers)do
if b.domain_id==a then local d={}for e,f in pairs(b)do d[e]=f end;d.address=c;return d end end;return nil end
function q.createJob(a)local b=q._data.job_id_counter
q._data.job_id_counter=q._data.job_id_counter+1
q._data.jobs[b]={job_id=b,submitted_by=a.submitted_by or"?",submitted_at=t.uptime(),state="pending",compute_profile=a.compute_profile or"mixed",retry_policy=
a.retry_policy or"safe",storage_preference=a.storage_preference,result_sink=a.result_sink or"inline",assignments={},spec=a}v()
q.pushEvent("job_submitted",{job_id=b,by=a.submitted_by})return b end
function q.addAssignment(b,a)local d=q._data.jobs[b]if not d then
return nil,"no_such_job: "..tostring(b)end;local c=q._data.assignment_id_counter;q._data.assignment_id_counter=
q._data.assignment_id_counter+1;a.assignment_id=c;a.job_id=b;a.state=
a.state or"pending"a.attempts=a.attempts or 0
d.assignments[c]=a;v()return c end
function q.setAssignmentState(c,d,a,b)local f=q._data.jobs[c]
if not f then return false,"no_such_job"end;local e=f.assignments[d]
if not e then return false,"no_such_assignment"end;local g=e.state;e.state=a;if b then
for h,i in pairs(b)do if i==q.CLEAR then e[h]=nil else e[h]=i end end end
if f.compute_profile=="compute_bound"then
if
g~=y and a==y then q._data._runtime.compute_bound_in_flight=
q._data._runtime.compute_bound_in_flight+1 elseif
g==y and a~=y then
q._data._runtime.compute_bound_in_flight=math.max(0,q._data._runtime.compute_bound_in_flight-1)end end;v()return true end
function q.setJobState(b,a)local c=q._data.jobs[b]
if not c then return false,"no_such_job"end;c.state=a;if a=="done"or a=="failed"or a=="cancelled"then
c.completed_at=t.uptime()end;v()
q.pushEvent("job_state_change",{job_id=b,to=a})return true end
function q.listJobs(a)local b={}
for d,c in pairs(q._data.jobs)do
if(not a)or a(c)then local e,f=0,0
for d,g in
pairs(c.assignments)do f=f+1;if g.state=="completed"then e=e+1 end end
b[#b+1]={job_id=c.job_id,state=c.state,submitted_by=c.submitted_by,submitted_at=c.submitted_at,compute_profile=c.compute_profile,assignments=e.."/"..f}end end
table.sort(b,function(c,d)
return(c.job_id or 0)< (d.job_id or 0)end)return b end;function q.getJob(a)return q._data.jobs[a]end;function q.setStorageNode(a)
q._data.storage_node=a;v()
q.pushEvent("storage_configured",{address=a and a.address})end
function q.updateStorageUsage(a)if not
q._data.storage_node then return end
q._data.storage_node.used=a;q._data.storage_node.last_seen=t.uptime()end
function q.pushEvent(a,b)local c=q._data._runtime
c.events[c.events_head]={time=t.uptime(),kind=a,detail=b}
c.events_head=(c.events_head%c.EVENTS_MAX)+1
if c.events_size<c.EVENTS_MAX then c.events_size=c.events_size+1 end end
function q.recentEvents(a)local c=q._data._runtime
a=math.min(a or 20,c.events_size)local d={}local b=c.events_head-1;if b<1 then b=c.EVENTS_MAX end
for e=1,a do
local f=c.events[b]if f then d[#d+1]=f end;b=b-1;if b<1 then b=c.EVENTS_MAX end end;return d end
function q.incrementComputeBoundInFlight(a)
q._data._runtime.compute_bound_in_flight=
q._data._runtime.compute_bound_in_flight+ (a or 1)if q._data._runtime.compute_bound_in_flight<0 then
q._data._runtime.compute_bound_in_flight=0 end end
function q.computeBoundInFlight()return q._data._runtime.compute_bound_in_flight end;return q