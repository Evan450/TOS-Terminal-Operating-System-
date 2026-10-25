local r,n="shared","string"local l={}l.PROTOCOL_VERSION="1.0"
l.MIN_SUPPORTED_PROTOCOL="1.0"
local function q(a)if type(a)~=n then return nil end
local b,c=a:match("^(%d+)%.(%d+)$")if not b then return nil end;return tonumber(b),tonumber(c)end
function l.checkVersion(b,a)a=a or l.PROTOCOL_VERSION;local c,e=q(a)local d,e=q(b)if not c or not d then return
"malformed"end;if c~=d then return"version_mismatch"end;return
"compatible"end
l.PORT={CONTROL=2000,WORKER_BASE=2001,PUBLIC_READ=2100,PUBLIC_WRITE=2101}
function l.workerPort(a)if type(a)~="number"or a<0 then return nil end;return
l.PORT.WORKER_BASE+a end
l.TIMING={HEARTBEAT_INTERVAL=5,HEARTBEAT_DEGRADED=15,HEARTBEAT_OFFLINE=30,WORKER_PING=10,TASK_TIMEOUT=60,ASSIGNMENT_TIMEOUT=300,TRUST_PENDING=300,STORAGE_SWEEP=60,STORAGE_TTL_DEFAULT=3600,STORAGE_TTL_MAX=86400,BOOTSTRAP_WINDOW=180,PEER_STATUS_INTERVAL=10,PEER_STATUS_DEAD=30,RELAY_TTL_DEFAULT=3,RELAY_SEEN_TTL=30,RELAY_RATE_WINDOW=10,RELAY_RATE_MAX=30}l.payload={}
function l.payload.register(a)a=a or{}
return
{hostname=a.hostname,profile=a.profile,worker_count=a.worker_count or 0,storage=a.storage or
{external_type="none",external_capacity=0},has_console=a.has_console or false,compute_capable=a.compute_capable and true or false,cluster_protocol=
a.cluster_protocol or l.PROTOCOL_VERSION,software_version=a.software_version or"0.0.0"}end
function l.payload.registerAck(a)a=a or{}
return
{accepted=a.accepted and true or false,reason=a.reason,domain_id=a.domain_id,worker_port=a.worker_port,heartbeat_interval=
a.heartbeat_interval or l.TIMING.HEARTBEAT_INTERVAL,master_protocol=a.master_protocol or l.PROTOCOL_VERSION,min_supported_protocol=
a.min_supported_protocol or l.MIN_SUPPORTED_PROTOCOL}end
function l.payload.heartbeat(a)a=a or{}
return
{domain_id=a.domain_id,state=a.state or"active",workers_total=a.workers_total or 0,workers_active=a.workers_active or 0,workers_busy=
a.workers_busy or 0,queue_depth=a.queue_depth or 0,assignments_running=a.assignments_running or{},compute_capable=
a.compute_capable and true or false,storage_used=a.storage_used or 0,errors_last_min=a.errors_last_min or 0,uptime=a.uptime or 0}end
function l.payload.assign(a)a=a or{}
return
{assignment_id=a.assignment_id,job_id=a.job_id,priority=a.priority or 5,deadline=a.deadline or 0,retry_policy=a.retry_policy or"safe",tasks_inline=a.tasks_inline,tasks_ref=a.tasks_ref,inputs_inline=a.inputs_inline,inputs_ref=a.inputs_ref,result_sink=
a.result_sink or"inline",result_prefix=a.result_prefix}end
function l.payload.result(a)a=a or{}
return
{assignment_id=a.assignment_id,status=a.status or"ok",output_inline=a.output_inline,output_ref=a.output_ref,errors=a.errors or{},stats=a.stats or
{}}end
function l.payload.resultChunk(a)a=a or{}return
{assignment_id=a.assignment_id,chunk_idx=a.chunk_idx or 0,chunk_total=a.chunk_total or 1,data=a.data or"",final_stats=a.final_stats}end
function l.payload.peerStatus(a)a=a or{}return
{state=a.state or"active",master_reachable=a.master_reachable and true or false,relay_hops=
a.relay_hops or 0,load=a.load or 0}end
function l.payload.relayForward(a)a=a or{}return
{dest=a.dest,path=a.path or{},ttl=a.ttl or l.TIMING.RELAY_TTL_DEFAULT,inner=a.inner,inner_type=a.inner_type}end;local m={}local o={}
local function s()local b,a=pcall(require,"computer")if b and a and a.uptime then return
a.uptime()end;return
(os.clock and os.clock())or 0 end
local function t(a)local b=a.inner
local d=tostring(a.dest).."\0"..
(type(b)==n and b or tostring(b))local e,c=pcall(require,"kernel.crypto")
if e and c and c.hash then
local g,f=pcall(c.hash,d)if g and type(f)==n then return f end end;return d end
local function u(a)for b,c in pairs(m)do if c<a then m[b]=nil end end end;function l._resetRelayState()m={}o={}end
function l.relayHandle(a,b,c,d)if type(a)~="table"then return
{action="fail",reason="malformed"}end;local f=a.path or{}for y=1,#f
do
if f[y]==b then return{action="fail",reason="loop",envelope=a}end end
local j=tonumber(a.ttl)or 0
if j<=0 then return{action="fail",reason="ttl_exceeded",envelope=a}end;if a.dest==b then return{action="deliver",envelope=a}end
local g=s()u(g)local i=t(a)if m[i]and m[i]>=g then
return{action="fail",reason="duplicate",envelope=a}end;local k=d or f[#f]or"?"
local e=o[k]if not e or(g-e.ws)>=l.TIMING.RELAY_RATE_WINDOW then
e={ws=g,n=0}o[k]=e end
if
e.n>=l.TIMING.RELAY_RATE_MAX then return{action="fail",reason="rate_limited",envelope=a}end;e.n=e.n+1;m[i]=g+l.TIMING.RELAY_SEEN_TTL;local h={}for y=1,#f do
h[y]=f[y]end;h[#h+1]=b
local x={dest=a.dest,path=h,ttl=j-1,inner=a.inner,inner_type=a.inner_type}local w=nil;if type(c)=="function"then w=c(a.dest)end;return
{action="forward",envelope=x,next_hop=w}end
function l.reversePath(a)if type(a)~="table"then return{}end;local b={}local c=#a;for d=1,c do
b[d]=a[c-d+1]end;return b end
function l.payload.relayFail(a)a=a or{}return
{reason=a.reason or"unreachable",failed_at=a.failed_at,original_dest=a.original_dest,original_inner_type=a.original_inner_type}end;l.NS={JOB="job",DOMAIN="domain",SHARED=r}
function l.parseKey(a)if
type(a)~=n or a==""then return nil,"empty key"end;if a:sub(1,1)=="/"then
return nil,"absolute key"end
if a:find("%.%./")or a:find("/%.%.$")or
a==".."then return nil,"parent-escape in key"end;local b,d=a:match("^([^/]+)/(.*)$")
if not b then return nil,"no namespace segment"end
if b==l.NS.SHARED then return{ns=r,scope=nil,subpath=d}end;local c,e=b:match("^(job)%-(%d+)$")if not c then
c,e=b:match("^(domain)%-(%d+)$")end;if not c then
return nil,"unknown namespace: "..tostring(b)end
return{ns=c,scope=tonumber(e),subpath=d}end
function l.canWrite(a,b)local c,d=l.parseKey(b)if not c then return false,d end;a=a or{}if c.ns==r then if
a.role=="master"then return true end
return false,"namespace_denied: shared requires master"end
if c.ns=="domain"then
if a.role==
"manager"and a.domain_id==c.scope then return true end;return false,"namespace_denied: domain-<id> requires owning Manager"end
if c.ns=="job"then if a.role=="master"then return true end;if a.role=="manager"and
a.job_assignee and a.job_assignee[c.scope]then
return true end;return false,
"namespace_denied: job-<id> requires Master or assigned Manager"end;return false,"namespace_denied: unknown namespace"end;l.PUB_MAGIC="PUB"function l.pubGet(a,b)
return{magic=l.PUB_MAGIC,op="GET",key=a,req_id=b}end;function l.pubList(a,b)return
{magic=l.PUB_MAGIC,op="LIST",prefix=a,req_id=b}end
function l.validatePubRequest(a)if
type(a)~="table"then return false,"not a table"end;if
a.magic~=l.PUB_MAGIC then return false,"bad magic"end
if
a.op~="GET"and a.op~="LIST"then return false,"unknown op: "..tostring(a.op)end
if a.op=="GET"then
if type(a.key)~=n or a.key==""then return false,"GET needs key"end else
if type(a.prefix)~=n then return false,"LIST needs prefix"end end;return true end;local v="/etc/cluster.cfg"
local function p(a)a=a or{}
a.master_path=a.master_path or"direct"if a.master_path~="via"then a.relay_peer=nil end
a.encryption=a.encryption or{}
a.encryption.plaintext_types=a.encryption.plaintext_types or{}return a end
function l.loadConfig(b,a)a=a or v
if not b or not b.exists(a)then return p({})end;local d=b.readFile(a)if not d then return p({})end
local e=require("kernel.serialize")local f,c=pcall(e.decode,d)if not f or type(c)~="table"then
return nil,
"malformed cluster.cfg: "..tostring(c or"not a table")end
if c.master_path=="via"then
if
type(c.relay_peer)~=n or c.relay_peer==""then return nil,
"cluster.cfg: master_path='via' requires relay_peer"end elseif c.master_path and c.master_path~="direct"then return nil,
"cluster.cfg: master_path must be 'direct' or 'via'"end;return p(c)end;l.PLAINTEXT_ELIGIBLE={peer_st=true,cl_hb=true}
function l.allowPlaintext(b,a)if not
l.PLAINTEXT_ELIGIBLE[b]then return false end;a=a or{}
local c=a.encryption and
a.encryption.plaintext_types or nil;if type(c)~="table"then return false end
local d=({peer_st="PEER_STATUS",cl_hb="CLUSTER_HEARTBEAT"})[b]
for e=1,#c do if c[e]==d or c[e]==b then return true end end;return false end;return l