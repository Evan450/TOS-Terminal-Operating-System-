
local I,G,J,K,L,B,M,N,O="cancelled","missing_argument: domain_id","missing_argument: job_id","no_such_domain","no_such_job","number","offline","pairing_unsupported","string"local D=require("computer")local y={}local x,E,C,z;local F=false;local function H()
return
package.loaded["cluster.net"]or require("cluster.net")end
function y.bind(a,b,c,d)x=a;E=b;C=c;z=d;F=true end;function y.unbind()x,E,C,z=nil,nil,nil,nil;F=false end
local function A()if not F then
error("cluster daemon is not running (clusterd not started)",2)end end;local P={compute_bound=true,io_bound=true,mixed=true}
local Q={safe=true,once=true,none=true}local R={inline=true,public=true}
local function S(a)if type(a)~="table"then
return false,"invalid_spec: not a table"end
if
a.tasks~=nil and type(a.tasks)~="table"then return false,"invalid_tasks: not a table"end;if a.compute_profile and not P[a.compute_profile]then
return false,
"invalid_compute_profile: "..tostring(a.compute_profile)end
if a.retry_policy and not
Q[a.retry_policy]then return false,
"invalid_retry_policy: "..tostring(a.retry_policy)end
if a.result_sink and not R[a.result_sink]then return false,"invalid_result_sink: "..
tostring(a.result_sink)end
if a.priority~=nil then local b=tonumber(a.priority)if not b or b<0 or b>9 then return false,
"invalid_priority: must be 0..9"end end;return true end
function y.status()A()
local a={managers={active=0,degraded=0,draining=0,offline=0},jobs={pending=0,running=0,done=0,failed=0,cancelled=0},storage=nil,host_thread_budget=z and z.getConfig and
(z.getConfig().host_thread_budget)or nil,compute_bound_in_flight=x.computeBoundInFlight(),uptime=D.uptime()}
for c,b in pairs(x._data.managers)do local d=b.state or M;a.managers[d]=
(a.managers[d]or 0)+1 end;for c,b in pairs(x._data.jobs)do local d=b.state or"pending"a.jobs[d]=
(a.jobs[d]or 0)+1 end
if
x._data.storage_node then local b=x._data.storage_node
a.storage={configured=true,address=b.address,used_bytes=b.used,capacity_bytes=b.capacity,last_seen=b.last_seen}end;return a end;function y.listManagers(a)A()return x.listManagers(a)end;function y.getManager(a)
A()if not a then return nil,G end
return x.getManagerByDomainId(tonumber(a))end;function y.listJobs(a)A()
return x.listJobs(a)end
function y.getJob(a)A()if not a then return nil,J end
local c=x.getJob(tonumber(a))if not c then return nil,L end;local d={}for e,f in pairs(c)do d[e]=f end;local b={}for f,e in pairs(
c.assignments or{})do b[#b+1]=e end
table.sort(b,function(e,f)return
(
e.assignment_id or 0)< (f.assignment_id or 0)end)d.assignments_list=b;return d end
function y.storageStatus()A()local a=x._data.storage_node;if not a then return nil end;return
{address=a.address,used_bytes=a.used,capacity_bytes=a.capacity,last_seen=a.last_seen}end
function y.recentEvents(a)A()return x.recentEvents(a or 20)end
function y.submit(a)A()local d,e=S(a)if not d then return nil,e end;if not
E.hasAnyActiveCapacity(x._data.managers)then
return nil,"no_eligible_manager: no active managers with free workers"end
local f,b=pcall(require,"users")
if f and b and not a.submitted_by then
local g=b.currentSession and b.currentSession()if g and g.user then a.submitted_by=g.user end end;local c
x.withLock(function()c=x.createJob(a)C.splitIntoAssignments(c,a,x)end)return c end
function y.cancelJob(a)A()a=tonumber(a)if not a then return false,J end
local b=x.getJob(a)if not b then return false,L end
if
b.state=="done"or b.state=="failed"or b.state==I then return false,
"wrong_state: job already terminal, "..tostring(b.state)end;local c=H()
x.withLock(function()
for e,d in pairs(b.assignments)do if d.state=="running"and d.assigned_to then
pcall(c.sendCancel,d.assigned_to,e)end;if d.state=="pending"or
d.state=="running"then
x.setAssignmentState(a,e,I,{completed_at=D.uptime()})end end;x.setJobState(a,I)end)return true end
function y.retryJob(a)A()a=tonumber(a)if not a then return nil,J end;local b=x.getJob(a)if not b then return
nil,L end;if b.state~="failed"then
return nil,"wrong_state: only failed jobs can be retried (state="..
tostring(b.state)..")"end;local c
x.withLock(function()local d={}for e,f in pairs(
b.spec or{})do d[e]=f end
d.submitted_by=d.submitted_by or b.submitted_by;c=x.createJob(d)C.splitIntoAssignments(c,d,x)end)return c end
function y.drainManager(a)A()a=tonumber(a)if not a then return false,G end
local b=x.getManagerByDomainId(a)if not b then return false,K end;if b.state==M then
return false,"wrong_state: already offline"end;local c=H()
pcall(c.sendDrain,b.address)x.setManagerState(b.address,"draining")return true end
function y.undrainManager(a)A()a=tonumber(a)if not a then return false,G end
local b=x.getManagerByDomainId(a)if not b then return false,K end;if b.state~="draining"then
return false,"wrong_state: manager is not draining (state="..
tostring(b.state)..")"end
x.setManagerState(b.address,"active")return true end
function y.forgetManager(a)A()a=tonumber(a)if not a then return false,G end
local b=x.getManagerByDomainId(a)if not b then return false,K end;if b.state~=M then
return false,"wrong_state: refusing to forget online manager (state="..
tostring(b.state).."); drain first"end
x.withLock(function()
C.onManagerOffline(a,x)x.forgetManager(b.address)end)return true end
local T={host_thread_budget={type=B,restart_required=false},heartbeat_interval={type=B,restart_required=true},heartbeat_degraded_after={type=B,restart_required=false},heartbeat_offline_after={type=B,restart_required=false},scheduler_tick_interval={type=B,restart_required=true},status_snapshot_interval={type=B,restart_required=true},heartbeat_sweep_interval={type=B,restart_required=true},storage_node_address={type=O,restart_required=false}}function y.startPairing()A()
if not z or not z.startPairing then return nil,N end;local a,b=z.startPairing()
return{code=a,expires_in=b-D.uptime()}end;function y.closePairing()
A()if not z or not z.closePairing then return false,N end
z.closePairing()return true end;function y.pairingInfo()
A()if not z or not z.pairingInfo then return nil,N end;return
z.pairingInfo()end
function y.getConfig()A()
local b=z and
z.getConfig and z.getConfig()or{}local a={}for c,d in pairs(b)do a[c]=d end;return a end
function y.setConfig(b,a)A()local c=T[b]if not c then return false,
"invalid_key: unknown or read-only, "..tostring(b)end
if
c.type==B then local e=tonumber(a)
if not e then return false,"invalid_value: must be numeric"end;a=e elseif c.type==O then
if type(a)~=O then return false,"invalid_value: must be a string"end end;local d=z and z.getConfig and z.getConfig()
if d then d[b]=a end;return true,{restart_required=c.restart_required}end;return y