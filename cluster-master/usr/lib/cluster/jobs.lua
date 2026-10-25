local K,F,P,H,A,C="cancelled","cluster.state","completed","failed","pending","running"
local B=require("computer")local w={}local L=4096;local z,I;function w.setStore(a,b)z,I=a,b end;local M=40
local N={safe=5,once=2,none=1}local function D(a)return N[a or"safe"]or 1 end
local Q={completed=true,failed=true,lost=true,cancelled=true}local G;local x
do local b,a=pcall(require,"kernel.log")if not
(b and a and a.info)then b,a=pcall(require,"log")end;if
b and a and a.info then x=a else
x={info=function()end,warn=function()end,error=function()end}end end;local y="cluster.jobs"
function w.splitIntoAssignments(a,b,c)c=c or require(F)
local f=b.tasks or{}local g=#f;local j=b.compute_profile or"mixed"
local h=b.retry_policy or"safe"local k=b.deadline or 0;local l=b.priority or 5;local m=b.storage_preference;local i=
b.result_sink or"inline"
local function n(o,p)if#o==0 then return o,nil,nil end;if not(
z and z.available and z.available())then
return o,nil,nil end;if not(I and I.encode)then
return o,nil,nil end;local t,q=pcall(I.encode,o)if
not t or type(q)~="string"or#q<=L then return o,nil,nil end
local r=z.tasksKey(a,p)local s,u=z.put(r,q)
if not s then
x.warn(y,string.format("job %d slice %d: %d bytes but Public write failed (%s); staying inline",a,p,#q,tostring(u)))return o,nil,nil end
x.info(y,string.format("job %d slice %d: %d bytes -> %s",a,p,#q,r))return nil,"public://"..r,s.lease_id end
local function e(p,o)local q,r,s=n(p,o)
return
{job_id=a,priority=l,deadline=k,retry_policy=h,compute_profile=j,storage_preference=m,tasks_inline=q,tasks_ref=r,tasks_lease=s,inputs_inline=b.inputs,inputs_ref=b.inputs_ref,result_sink=i,result_prefix=i=="public"and
string.format("public://job-%d/results/",a)or nil,split_index=o,state=A,attempts=0,max_attempts=D(h)}end;local d={}
if g==0 then local o=c.addAssignment(a,e({},1))
if o then d[#d+1]=o end else local o={}local p=1;for q=1,g do o[#o+1]=f[q]
if#o>=M then
local r=c.addAssignment(a,e(o,p))if r then d[#d+1]=r end;o={}p=p+1 end end;if#o>0 then
local q=c.addAssignment(a,e(o,p))if q then d[#d+1]=q end end end
x.info(y,string.format("job %d split into %d assignment(s)",a,#d))return d end
function w.pendingAssignments(a)a=a or require(F)local b={}for d,c in pairs(a._data.jobs)do
if c.state==A or
c.state==C then for d,e in pairs(c.assignments)do
if e.state==A then b[#b+1]=e end end end end
table.sort(b,function(c,d)local e=
c.priority or 5;local f=d.priority or 5;if e~=f then return e>f end
local g=(c.deadline and
c.deadline>0)and c.deadline or math.huge;local h=(d.deadline and d.deadline>0)and d.deadline or
math.huge
if g~=h then return g<h end;return
(c.assignment_id or 0)< (d.assignment_id or 0)end)return b end
function w.dispatch(a,c,b,d)b=b or require(F)
if not d then d=require("cluster.net")end;local i=B.uptime()local e=a.attempts or 0
local j,f=b.setAssignmentState(a.job_id,a.assignment_id,C,{dispatched_at=i,assigned_to=c,attempts=e+1})
if not j then
x.error(y,"dispatch: setAssignmentState failed for "..
tostring(a.assignment_id)..": "..tostring(f))return false,f or"state_update_failed"end;local g=b.getJob(a.job_id)if g and g.state==A then
b.setJobState(a.job_id,C)end;local k,h=d.sendAssignment(c,a)
if not k then
x.warn(y,string.format("send failed to %s: %s; requeuing asn %d",tostring(c),tostring(h),a.assignment_id))
b.setAssignmentState(a.job_id,a.assignment_id,A,{assigned_to=b.CLEAR,attempts=e})return false,"send_failed: "..tostring(h)end
b.pushEvent("assignment_dispatched",{job_id=a.job_id,assignment_id=a.assignment_id,manager=c,attempt=a.attempts})return true end;local function J(a,b)
for d,c in pairs(a._data.jobs)do local e=c.assignments[b]if e then return d,e,c end end;return nil end
function w.onResult(a,c,b)b=b or
require(F)local f,d,g=J(b,a)
if not d then
x.warn(y,"result for unknown assignment "..tostring(a))return false,"no_such_assignment"end
if Q[d.state]then
x.warn(y,string.format("duplicate result for asn %d, already %s; keeping the first",a,tostring(d.state)))
b.pushEvent("assignment_result_duplicate",{job_id=f,assignment_id=a,kept=d.state,discarded=c.status or"ok"})return false,"duplicate_result"end;if d.state~=C then
x.info(y,string.format("result for requeued asn %d in state %s; accepting",a,tostring(d.state)))end
local h=c.status or"ok"local e;if h=="ok"then e=P elseif h=="partial"then e=P elseif h==K then e=K else e=H end
local i={completed_at=B.uptime(),result={status=h,output_inline=c.output_inline,output_ref=c.output_ref,errors=c.errors,stats=c.stats}}b.setAssignmentState(f,a,e,i)
b.pushEvent("assignment_result",{job_id=f,assignment_id=a,status=h})
if e==H and g and g.retry_policy~="none"then
if(d.attempts or 0)<
D(g.retry_policy)then
b.setAssignmentState(f,a,A,{assigned_to=b.CLEAR,retry_reason="failed_result"})
x.info(y,string.format("retrying asn %d (attempt %d/%d)",a,(d.attempts or 0),D(g.retry_policy)))return true end end;if G(g)then w.finalizeJob(f,b)end;return true end
G=function(a)if not a then return false end;for c,b in pairs(a.assignments)do local d=b.state;if d==A or d==C then
return false end end;return true end;local E={}
local function R()local a=B.uptime()
for b,c in pairs(E)do if
a- (c.last_touch or 0)>300 then
x.warn(y,"discarding stale chunk buffer for asn "..tostring(b))E[b]=nil end end end
function w.onResultChunk(a,c,d,e,b,f)R()local g=E[a]if not g then
g={chunks={},expected=d,last_touch=B.uptime()}E[a]=g end;g.chunks[c]=e
g.last_touch=B.uptime()if b then g.stats=b end;local h=0
for k=1,g.expected do if g.chunks[k]~=nil then h=h+1 end end;if h~=g.expected then return false,"incomplete"end;local i={}for k=1,g.expected do
i[k]=g.chunks[k]end;local j=table.concat(i)E[a]=nil;return
w.onResult(a,{status="ok",output_inline=j,stats=g.stats},f)end
function w.onAssignmentTimeout(b,a,c)a=a or require(F)
if not c then c=require("cluster.net")end;local e,d,f=J(a,b)
if not d or d.state~=C then return false,"wrong_state: not running"end
if d.assigned_to then pcall(c.sendCancel,d.assigned_to,b)end
a.pushEvent("assignment_timeout",{job_id=e,assignment_id=b})local g=f and f.retry_policy or"safe"local h=D(g)
if g~="none"and(
d.attempts or 0)<h then
a.setAssignmentState(e,b,A,{assigned_to=a.CLEAR,retry_reason="deadline_exceeded"})
x.info(y,string.format("asn %d timed out, requeued (attempts=%d/%d)",b,(d.attempts or 0),h))return true end
a.setAssignmentState(e,b,H,{reason="deadline_exceeded",completed_at=B.uptime()})if G(f)then w.finalizeJob(e,a)end;return true end
function w.onManagerOffline(b,a)a=a or require(F)
local d=a.getManagerByDomainId(b)if not d then return end;local e=d.address;local c=0
for f,g in pairs(a._data.jobs)do
for i,h in
pairs(g.assignments)do
if h.state==C and h.assigned_to==e then
local j=g.retry_policy or"safe"local k=D(j)
if j~="none"and(h.attempts or 0)<k then
a.setAssignmentState(f,i,A,{assigned_to=a.CLEAR,retry_reason="manager_offline"})else
a.setAssignmentState(f,i,"lost",{reason="manager_offline",completed_at=B.uptime()})end;c=c+1 end end end
a.pushEvent("manager_offline_reassign",{domain_id=b,affected=c})
for g,f in pairs(a._data.jobs)do if
(f.state==C or f.state==A)and G(f)then w.finalizeJob(g,a)end end end
local function O(a,b)if
not(z and z.available and z.available())then return 0 end;local c=0
for e,d in pairs(b.assignments or{})do
if
d.tasks_ref and d.tasks_lease then
local f=d.tasks_ref:gsub("^public://","")local g=pcall(z.release,f,d.tasks_lease)if g then c=c+1 end end end;if c>0 then
x.info(y,string.format("job %d: released %d Public key(s)",a,c))end;return c end
function w.finalizeJob(a,b)b=b or require(F)local h=b.getJob(a)if not h then
return false,"no_such_job"end;pcall(O,a,h)local d,e,f,g=0,0,0,0
for j,i in pairs(h.assignments)do
if
i.state==P then d=d+1 elseif i.state==H then e=e+1 elseif i.state=="lost"then f=f+1 elseif i.state==K then g=g+1 end end;local c
if g>0 and d==0 and e==0 and f==0 then c=K elseif e==0 and f==0 then c="done"elseif(
h.retry_policy or"safe")=="none"then c=H else
c=(d>0)and"done"or H end;b.setJobState(a,c)
b.pushEvent("job_finalized",{job_id=a,state=c,completed=d,failed=e,lost=f,cancelled=g})
x.info(y,string.format("job %d finalized: %s (ok=%d fail=%d lost=%d cancel=%d)",a,c,d,e,f,g))return true,c end
w._internal={MAX_TASKS_PER_ASSIGNMENT=M,INLINE_TASK_BUDGET=L,releasePublicKeys=function(...)return O(...)end,POLICY_ATTEMPTS=N,attemptsFor=D,resolveAssignment=J,allAssignmentsTerminal=function(a)return G(a)end,chunkBuffer=E}return w