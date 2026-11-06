local O,J,T,K,C,F="cancelled","cluster.state","completed","failed","pending","running"
local D=require("computer")local y={}local L=4096;local A,E;function y.setStore(a,b)A,E=a,b end;local P=40;local M=5120
local Q={safe=5,once=2,none=1}local function G(a)return Q[a or"safe"]or 1 end
local U={completed=true,failed=true,lost=true,cancelled=true}local H;local z
do local b,a=pcall(require,"kernel.log")if not
(b and a and a.info)then b,a=pcall(require,"log")end;if
b and a and a.info then z=a else
z={info=function()end,warn=function()end,error=function()end}end end;local B="cluster.jobs"local function R(a)if not(E and E.encode)then return nil end
local c,b=pcall(E.encode,a)
return c and type(b)=="string"and#b or nil end
function y.oversizedTask(a)
if
type(a)~="table"or type(a.tasks)~="table"then return nil end
for b,c in ipairs(a.tasks)do local d=R(c)if d and d>M then return b,d,M end end end
function y.splitIntoAssignments(b,a,c)c=c or require(J)local e=a.tasks or{}local f=#e;local j=a.compute_profile or
"mixed"local g=a.retry_policy or"safe"local k=a.deadline or
0;local l=a.priority or 5;local m=a.storage_preference;local h=
a.result_sink or"inline"
local function n(o,p)if#o==0 then return o,nil,nil end;if not(
A and A.available and A.available())then
return o,nil,nil end;if not(E and E.encode)then
return o,nil,nil end;local t,q=pcall(E.encode,o)if
not t or type(q)~="string"or#q<=L then return o,nil,nil end
local r=A.tasksKey(b,p)local s,u=A.put(r,q)
if not s then
z.warn(B,string.format("job %d slice %d: %d bytes but Public write failed (%s); staying inline",b,p,#q,tostring(u)))return o,nil,nil end
z.info(B,string.format("job %d slice %d: %d bytes -> %s",b,p,#q,r))return nil,"public://"..r,s.lease_id end
local function i(p,o)local r,q,s=n(p,o)
return
{job_id=b,priority=l,deadline=k,retry_policy=g,compute_profile=j,storage_preference=m,tasks_inline=r,tasks_ref=q,tasks_lease=s,store_addr=q and A.address and A.address()or nil,inputs_inline=a.inputs,inputs_ref=a.inputs_ref,result_sink=h,result_prefix=

h=="public"and string.format("public://job-%d/results/",b)or nil,split_index=o,state=C,attempts=0,max_attempts=G(g)}end;local d={}
if f==0 then local o=c.addAssignment(b,i({},1))
if o then d[#d+1]=o end else local s=A and A.available and A.available()
local t=s and M or L;local o,p={},0;local q=1;local function r()local u=c.addAssignment(b,i(o,q))
if u then d[#d+1]=u end;o,p={},0;q=q+1 end
for u=1,f do
local v=R(e[u])or 0;if#o>0 and p+v>t then r()end;o[#o+1]=e[u]p=p+v;if#o>=P then r()end end;if#o>0 then r()end end
z.info(B,string.format("job %d split into %d assignment(s)",b,#d))return d end
function y.pendingAssignments(a)a=a or require(J)local b={}for d,c in pairs(a._data.jobs)do
if c.state==C or
c.state==F then for d,e in pairs(c.assignments)do
if e.state==C then b[#b+1]=e end end end end
table.sort(b,function(c,d)local e=
c.priority or 5;local f=d.priority or 5;if e~=f then return e>f end
local g=(c.deadline and
c.deadline>0)and c.deadline or math.huge;local h=(d.deadline and d.deadline>0)and d.deadline or
math.huge
if g~=h then return g<h end;return
(c.assignment_id or 0)< (d.assignment_id or 0)end)return b end
function y.dispatch(a,c,b,d)b=b or require(J)
if not d then d=require("cluster.net")end;local i=D.uptime()local f=a.attempts or 0
local j,h=b.setAssignmentState(a.job_id,a.assignment_id,F,{dispatched_at=i,assigned_to=c,attempts=f+1})
if not j then
z.error(B,"dispatch: setAssignmentState failed for "..
tostring(a.assignment_id)..": "..tostring(h))return false,h or"state_update_failed"end;local e=b.getJob(a.job_id)if e and e.state==C then
b.setJobState(a.job_id,F)end;local k,g=d.sendAssignment(c,a)
if not k then
if
tostring(g):find("too large",1,true)then
z.error(B,string.format("asn %d cannot fit in a packet; failing it",a.assignment_id))
b.setAssignmentState(a.job_id,a.assignment_id,K,{assigned_to=b.CLEAR,attempts=f,reason="packet_too_large",completed_at=D.uptime()})if e and H(e)then y.finalizeJob(a.job_id,b)end;return false,
"packet_too_large"end
z.warn(B,string.format("send failed to %s: %s; requeuing asn %d",tostring(c),tostring(g),a.assignment_id))
b.setAssignmentState(a.job_id,a.assignment_id,C,{assigned_to=b.CLEAR,attempts=f})return false,"send_failed: "..tostring(g)end
b.pushEvent("assignment_dispatched",{job_id=a.job_id,assignment_id=a.assignment_id,manager=c,attempt=a.attempts})return true end;local function N(a,b)
for d,c in pairs(a._data.jobs)do local e=c.assignments[b]if e then return d,e,c end end;return nil end
function y.onResult(a,c,b)b=b or
require(J)local f,d,g=N(b,a)
if not d then
z.warn(B,"result for unknown assignment "..tostring(a))return false,"no_such_assignment"end
if U[d.state]then
z.warn(B,string.format("duplicate result for asn %d, already %s; keeping the first",a,tostring(d.state)))
b.pushEvent("assignment_result_duplicate",{job_id=f,assignment_id=a,kept=d.state,discarded=c.status or"ok"})return false,"duplicate_result"end;if d.state~=F then
z.info(B,string.format("result for requeued asn %d in state %s; accepting",a,tostring(d.state)))end
local h=c.status or"ok"local e;if h=="ok"then e=T elseif h=="partial"then e=T elseif h==O then e=O else e=K end
local i={completed_at=D.uptime(),result={status=h,output_inline=c.output_inline,output_ref=c.output_ref,errors=c.errors,stats=c.stats}}b.setAssignmentState(f,a,e,i)
b.pushEvent("assignment_result",{job_id=f,assignment_id=a,status=h})
if e==K and g and g.retry_policy~="none"then
if(d.attempts or 0)<
G(g.retry_policy)then
b.setAssignmentState(f,a,C,{assigned_to=b.CLEAR,retry_reason="failed_result"})
z.info(B,string.format("retrying asn %d (attempt %d/%d)",a,(d.attempts or 0),G(g.retry_policy)))return true end end;if H(g)then y.finalizeJob(f,b)end;return true end
H=function(a)if not a then return false end;for c,b in pairs(a.assignments)do local d=b.state;if d==C or d==F then
return false end end;return true end;local I={}
local function V()local a=D.uptime()
for b,c in pairs(I)do if
a- (c.last_touch or 0)>300 then
z.warn(B,"discarding stale chunk buffer for asn "..tostring(b))I[b]=nil end end end
function y.onResultChunk(a,c,d,e,b,f)V()local g=I[a]if not g then
g={chunks={},expected=d,last_touch=D.uptime()}I[a]=g end;g.chunks[c]=e
g.last_touch=D.uptime()if b then g.stats=b end;local h=0
for k=1,g.expected do if g.chunks[k]~=nil then h=h+1 end end;if h~=g.expected then return false,"incomplete"end;local i={}for k=1,g.expected do
i[k]=g.chunks[k]end;local j=table.concat(i)I[a]=nil;return
y.onResult(a,{status="ok",output_inline=j,stats=g.stats},f)end
function y.onAssignmentTimeout(b,a,c)a=a or require(J)
if not c then c=require("cluster.net")end;local e,d,f=N(a,b)
if not d or d.state~=F then return false,"wrong_state: not running"end
if d.assigned_to then pcall(c.sendCancel,d.assigned_to,b)end
a.pushEvent("assignment_timeout",{job_id=e,assignment_id=b})local g=f and f.retry_policy or"safe"local h=G(g)
if g~="none"and(
d.attempts or 0)<h then
a.setAssignmentState(e,b,C,{assigned_to=a.CLEAR,retry_reason="deadline_exceeded"})
z.info(B,string.format("asn %d timed out, requeued (attempts=%d/%d)",b,(d.attempts or 0),h))return true end
a.setAssignmentState(e,b,K,{reason="deadline_exceeded",completed_at=D.uptime()})if H(f)then y.finalizeJob(e,a)end;return true end
function y.onManagerOffline(b,a)a=a or require(J)
local d=a.getManagerByDomainId(b)if not d then return end;local e=d.address;local c=0
for f,g in pairs(a._data.jobs)do
for i,h in
pairs(g.assignments)do
if h.state==F and h.assigned_to==e then
local j=g.retry_policy or"safe"local k=G(j)
if j~="none"and(h.attempts or 0)<k then
a.setAssignmentState(f,i,C,{assigned_to=a.CLEAR,retry_reason="manager_offline"})else
a.setAssignmentState(f,i,"lost",{reason="manager_offline",completed_at=D.uptime()})end;c=c+1 end end end
a.pushEvent("manager_offline_reassign",{domain_id=b,affected=c})
for g,f in pairs(a._data.jobs)do if
(f.state==F or f.state==C)and H(f)then y.finalizeJob(g,a)end end end
local function S(a,b)if
not(A and A.available and A.available())then return 0 end;local c=0
for e,d in pairs(b.assignments or{})do
if
d.tasks_ref and d.tasks_lease then
local f=d.tasks_ref:gsub("^public://","")local g=pcall(A.release,f,d.tasks_lease)if g then c=c+1 end end end;if c>0 then
z.info(B,string.format("job %d: released %d Public key(s)",a,c))end;return c end
function y.finalizeJob(a,b)b=b or require(J)local h=b.getJob(a)if not h then
return false,"no_such_job"end;pcall(S,a,h)local d,e,f,g=0,0,0,0
for j,i in pairs(h.assignments)do
if
i.state==T then d=d+1 elseif i.state==K then e=e+1 elseif i.state=="lost"then f=f+1 elseif i.state==O then g=g+1 end end;local c
if g>0 and d==0 and e==0 and f==0 then c=O elseif e==0 and f==0 then c="done"elseif(
h.retry_policy or"safe")=="none"then c=K else
c=(d>0)and"done"or K end;b.setJobState(a,c)
b.pushEvent("job_finalized",{job_id=a,state=c,completed=d,failed=e,lost=f,cancelled=g})
z.info(B,string.format("job %d finalized: %s (ok=%d fail=%d lost=%d cancel=%d)",a,c,d,e,f,g))return true,c end
y._internal={MAX_TASKS_PER_ASSIGNMENT=P,INLINE_TASK_BUDGET=L,releasePublicKeys=function(...)return S(...)end,POLICY_ATTEMPTS=Q,attemptsFor=G,resolveAssignment=N,allAssignmentsTerminal=function(a)return H(a)end,chunkBuffer=I}return y