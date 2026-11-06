
local R,N,S,T,U,I,V,W,X="cancelled","missing_argument: domain_id","missing_argument: job_id","no_such_domain","no_such_job","number","offline","pairing_unsupported","string"local K=require("computer")local D={}local C,L,J,E;local M=false;local function O()
return
package.loaded["cluster.net"]or require("cluster.net")end
function D.bind(a,b,c,d)C=a;L=b;J=c;E=d;M=true end;function D.unbind()C,L,J,E=nil,nil,nil,nil;M=false end
local function F()if not M then
error("cluster daemon is not running (clusterd not started)",2)end end;local Y={compute_bound=true,io_bound=true,mixed=true}
local Z={safe=true,once=true,none=true}local _={inline=true,public=true}
local function aa(a)if type(a)~="table"then
return false,"invalid_spec: not a table"end
if
a.tasks~=nil and type(a.tasks)~="table"then return false,"invalid_tasks: not a table"end;if a.compute_profile and not Y[a.compute_profile]then
return false,
"invalid_compute_profile: "..tostring(a.compute_profile)end
if a.retry_policy and not
Z[a.retry_policy]then return false,
"invalid_retry_policy: "..tostring(a.retry_policy)end
if a.result_sink and not _[a.result_sink]then return false,"invalid_result_sink: "..
tostring(a.result_sink)end
if a.priority~=nil then local b=tonumber(a.priority)if not b or b<0 or b>9 then return false,
"invalid_priority: must be 0..9"end end;return true end;function D.now()return K.uptime()end
function D.status()F()
local a={managers={active=0,degraded=0,draining=0,offline=0},jobs={pending=0,running=0,done=0,failed=0,cancelled=0},storage=
nil,host_thread_budget=
E and E.getConfig and(E.getConfig().host_thread_budget)or nil,compute_bound_in_flight=C.computeBoundInFlight(),uptime=K.uptime()}
for c,b in pairs(C._data.managers)do local d=b.state or V;a.managers[d]=
(a.managers[d]or 0)+1 end;for c,b in pairs(C._data.jobs)do local d=b.state or"pending"a.jobs[d]=
(a.jobs[d]or 0)+1 end
if
C._data.storage_node then local b=C._data.storage_node
a.storage={configured=true,address=b.address,used_bytes=b.used,capacity_bytes=b.capacity,last_seen=b.last_seen}end;return a end;function D.listManagers(a)F()return C.listManagers(a)end;function D.getManager(a)
F()if not a then return nil,N end
return C.getManagerByDomainId(tonumber(a))end;function D.listJobs(a)F()
return C.listJobs(a)end
function D.getJob(a)F()if not a then return nil,S end
local c=C.getJob(tonumber(a))if not c then return nil,U end;local d={}for e,f in pairs(c)do d[e]=f end;local b={}for f,e in pairs(
c.assignments or{})do b[#b+1]=e end
table.sort(b,function(e,f)return
(
e.assignment_id or 0)< (f.assignment_id or 0)end)d.assignments_list=b;return d end
function D.storageStatus()F()local a=C._data.storage_node;if not a then return nil end;return
{address=a.address,used_bytes=a.used,capacity_bytes=a.capacity,last_seen=a.last_seen}end
function D.recentEvents(a)F()return C.recentEvents(a or 20)end
function D.submit(a)F()local e,f=aa(a)if not e then return nil,f end;if not
L.hasAnyActiveCapacity(C._data.managers)then
return nil,"no_eligible_manager: no active managers with free workers"end
local d,g,h=J.oversizedTask(a)
if d then return nil,
string.format("task_too_large: task %d is %d bytes; the most one can be is %d",d,g,h)end;local i,b=pcall(require,"users")
if i and b and not a.submitted_by then local j=
b.currentSession and b.currentSession()if j and j.user then
a.submitted_by=j.user end end;local c
C.withLock(function()c=C.createJob(a)J.splitIntoAssignments(c,a,C)end)return c end
function D.cancelJob(a)F()a=tonumber(a)if not a then return false,S end
local b=C.getJob(a)if not b then return false,U end
if
b.state=="done"or b.state=="failed"or b.state==R then return false,
"wrong_state: job already terminal, "..tostring(b.state)end;local c=O()
C.withLock(function()
for e,d in pairs(b.assignments)do if d.state=="running"and d.assigned_to then
pcall(c.sendCancel,d.assigned_to,e)end;if d.state=="pending"or
d.state=="running"then
C.setAssignmentState(a,e,R,{completed_at=K.uptime()})end end;C.setJobState(a,R)end)return true end
function D.retryJob(a)F()a=tonumber(a)if not a then return nil,S end;local b=C.getJob(a)if not b then return
nil,U end;if b.state~="failed"then
return nil,"wrong_state: only failed jobs can be retried (state="..
tostring(b.state)..")"end;local c
C.withLock(function()local d={}for e,f in pairs(
b.spec or{})do d[e]=f end
d.submitted_by=d.submitted_by or b.submitted_by;c=C.createJob(d)J.splitIntoAssignments(c,d,C)end)return c end
function D.drainManager(a)F()a=tonumber(a)if not a then return false,N end
local b=C.getManagerByDomainId(a)if not b then return false,T end;if b.state==V then
return false,"wrong_state: already offline"end;local c=O()
pcall(c.sendDrain,b.address)C.setManagerState(b.address,"draining")return true end
function D.undrainManager(a)F()a=tonumber(a)if not a then return false,N end
local b=C.getManagerByDomainId(a)if not b then return false,T end;if b.state~="draining"then
return false,"wrong_state: manager is not draining (state="..
tostring(b.state)..")"end
C.setManagerState(b.address,"active")return true end
function D.forgetManager(a)F()a=tonumber(a)if not a then return false,N end
local b=C.getManagerByDomainId(a)if not b then return false,T end;if b.state~=V then
return false,"wrong_state: refusing to forget online manager (state="..
tostring(b.state).."); drain first"end
C.withLock(function()
J.onManagerOffline(a,C)C.forgetManager(b.address)end)return true end
local ab={host_thread_budget={type=I,restart_required=false},heartbeat_interval={type=I,restart_required=true},heartbeat_degraded_after={type=I,restart_required=false},heartbeat_offline_after={type=I,restart_required=false},scheduler_tick_interval={type=I,restart_required=true},status_snapshot_interval={type=I,restart_required=true},heartbeat_sweep_interval={type=I,restart_required=true},storage_node_address={type=X,restart_required=false}}function D.startPairing()F()
if not E or not E.startPairing then return nil,W end;local a,b=E.startPairing()
return{code=a,expires_in=b-K.uptime()}end;function D.closePairing()
F()if not E or not E.closePairing then return false,W end
E.closePairing()return true end;function D.pairingInfo()
F()if not E or not E.pairingInfo then return nil,W end;return
E.pairingInfo()end
function D.getConfig()F()
local b=E and
E.getConfig and E.getConfig()or{}local a={}for c,d in pairs(b)do a[c]=d end;return a end
function D.setConfig(b,a)F()local c=ab[b]if not c then return false,
"invalid_key: unknown or read-only, "..tostring(b)end
if
c.type==I then local e=tonumber(a)
if not e then return false,"invalid_value: must be numeric"end;a=e elseif c.type==X then
if type(a)~=X then return false,"invalid_value: must be a string"end end;local d=E and E.getConfig and E.getConfig()
if d then d[b]=a end;return true,{restart_required=c.restart_required}end;local H,G=2,3;local P={[0]="GUEST",[1]="USER",[2]="ADMIN",[3]="ROOT"}
local ac={now=H,status=H,listManagers=H,getManager=H,listJobs=H,getJob=H,storageStatus=H,recentEvents=H,getConfig=H,submit=G,cancelJob=G,retryJob=G,drainManager=G,undrainManager=G,forgetManager=G,startPairing=G,closePairing=G,pairingInfo=G,setConfig=G}
local function Q(b,a)local c=ac[a]
if not c then return false,"unknown call: "..tostring(a)end;local d=b.tier or 0
if d<c then return false,
string.format("permission denied (need %s, have %s)",P[c],P[d]or tostring(d))end;return true end
function D.endpoint(b,a,...)if a=="may"then return Q(b,(...))end;local c,d=Q(b,a)
if not c then return false,d end;if a=="submit"and type((...))=="table"then
(...).submitted_by=b.user end;return true,D[a](...)end;return D