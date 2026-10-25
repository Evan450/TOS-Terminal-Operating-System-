local ag,ah,ai,ab="active","degraded","draining","offline"
local G=require("cluster.state")local ac=require("cluster.scheduler")
local M=require("cluster.jobs")local N=require("cluster.net")local ad=require("cluster.api")
local O=require("cluster.pair")local R=require("cluster.store_client")
local function Z(...)for a=1,select("#",...)do
local c,b=pcall(require,(select(a,...)))if c and b then return b end end end;local P=Z("kernel.event","event")
local L=Z("kernel.fs","filesystem")local _=require("computer")local J
do local a=Z("kernel.log","log")
if
a and a.info then J=a else local function b(c,d,e)
if io and io.stderr then io.stderr:write("["..
c.."]["..d.."] "..e.."\n")end end
J={info=function(c,d)b("I",c,d)end,warn=function(c,d)
b("W",c,d)end,error=function(c,d)b("E",c,d)end}end end;local K="clusterd"local H={}local Q=false;local S;local T;local U;local aa={}local V="/etc/cluster-master.cfg"
local W="/var/cluster/state.dat"local X="/var/cluster/status.dat"
local ae={host_thread_budget=4,heartbeat_interval=5,heartbeat_degraded_after=15,heartbeat_offline_after=30,scheduler_tick_interval=1,status_snapshot_interval=2,heartbeat_sweep_interval=5,encryption={plaintext_types={}},storage_node_address=nil,cluster_protocol="1.0",min_supported_protocol="1.0"}local I;H._cfg=nil
local function Y(a)local b={}for c,d in pairs(ae)do b[c]=d end;if type(a)=="table"then for c,d in pairs(a)do
b[c]=d end end
if type(a)=="table"and
type(a.encryption)=="table"then b.encryption={}for c,d in
pairs(ae.encryption)do b.encryption[c]=d end;for c,d in pairs(a.encryption)do
b.encryption[c]=d end end;return b end
local function aj()if not L.exists or not L.exists(V)then J.info(K,"no config at "..
V.."; using defaults")
return Y(nil)end
local b=L.readFile and L.readFile(V)local c,d=b and load(b,"="..V,"t")if not c then
J.error(K,"config load failed: "..
tostring(d).."; falling back to defaults")return Y(nil)end
local e,a=pcall(c)
if not e or type(a)~="table"then
J.error(K,"config did not return a table: "..tostring(a)..
"; falling back to defaults")return Y(nil)end;return Y(a)end
local function af()local a=W:match("(.+)/[^/]+$")if not a then return end
if L.exists and
not L.exists(a)then if L.makeDirectory then local b,c=pcall(L.makeDirectory,a)
if not b then J.warn(K,
"mkdir failed: "..tostring(c))end end end end
function H.start()if Q then return true end;J.info(K,"starting")I=aj()H._cfg=I;af()
G.init(W)local a,b=G.load(W)if not a then
J.error(K,"state load failed: "..tostring(b))end;if
I.storage_node_address and not G._data.storage_node then
G.setStorageNode({address=I.storage_node_address})end
do
local c,d=pcall(require,"kernel.serialize")
R.init({state=G,serialize=c and d or nil,log=J})M.setStore(R,c and d or nil)
if R.available()then
J.info(K,"public storage: "..
tostring(R.address()):sub(1,8))else
J.info(K,"public storage: none configured (assignments stay inline)")end end;do local c,d=pcall(require,"kernel.net.trust")if c then
O.init({trust=d})end end
aa=N.register({onRegister=function(c,d)
H._onRegister(c,d)end,onHeartbeat=function(c,d)H._onHeartbeat(c,d)end,onResult=function(c,d)
H._onResult(c,d)end,onResultChunk=function(c,d)H._onResultChunk(c,d)end,onAssignAck=function(c,d)
H._onAssignAck(c,d)end,onStatusRes=function(c,d)H._onStatusRes(c,d)end,onRelayFail=function(c,d)
H._onRelayFail(c,d)end,onPairInit=function(c,d)O.onPairInit(c,d)end})
S=P.interval(I.heartbeat_sweep_interval,function()H._onHeartbeatSweep()end,"clusterd.hbsweep")
U=P.interval(I.scheduler_tick_interval,function()H._onSchedulerTick()end,"clusterd.sched")
T=P.interval(I.status_snapshot_interval,function()H._onStatusSnapshot()end,"clusterd.status")ad.bind(G,ac,M,H)Q=true;J.info(K,"started")return true end
function H.stop()if not Q then return true end;J.info(K,"stopping")if S then
P.cancelTimer(S)S=nil end;if U then P.cancelTimer(U)U=nil end;if T then
P.cancelTimer(T)T=nil end;N.unregister(aa)aa={}
local a,b=pcall(G.save,W)if not a then
J.error(K,"final save failed: "..tostring(b))end;ad.unbind()H._cfg=nil;Q=false
J.info(K,"stopped")return true end;function H.isRunning()return Q end;function H.getConfig()return I end;function H.startPairing()return
O.startWindow()end
function H.closePairing()return O.closeWindow()end;function H.pairingInfo()return O.windowInfo()end;function H.pairingOpen()return
O.windowOpen()end
function H._onHeartbeatSweep()if not I then return end
local a=_.uptime()
for b,c in pairs(G._data.managers)do
local e=a- (c.last_heartbeat or a)local d=c.state
if e>I.heartbeat_offline_after and d~=ab then
G.setManagerState(b,ab)pcall(M.onManagerOffline,c.domain_id,G)elseif
e>I.heartbeat_degraded_after and d==ag then G.setManagerState(b,ah)elseif
e<=I.heartbeat_degraded_after and d==ah then G.setManagerState(b,ag)end
if d==ai then local f=false
for h,g in pairs(G._data.jobs)do
for h,i in pairs(g.assignments)do if i.state=="running"and
i.assigned_to==b then f=true;break end end;if f then break end end;if not f then G.setManagerState(b,ab)end end end end
function H._onSchedulerTick()if not I then return end;local a=_.uptime()
local c=M.pendingAssignments(G)
local b={compute_bound_in_flight=G.computeBoundInFlight(),host_thread_budget=I.host_thread_budget,uptime=a}
for e,d in ipairs(c)do b.compute_bound_in_flight=G.computeBoundInFlight()
local f,g=ac.pickDomain(d,G._data.managers,b)
if f then local h,i=M.dispatch(d,f,G,N)if not h then
J.warn(K,string.format("dispatch %d failed: %s",d.assignment_id or-1,tostring(i)))end elseif g and
g~="thread_budget_saturated"then end end
for e,d in pairs(G._data.jobs)do
for g,f in pairs(d.assignments)do
if
f.state=="running"and f.deadline and f.deadline>0 then if a>f.deadline then
pcall(M.onAssignmentTimeout,g,G,N)end end end end end
function H._onStatusSnapshot()
local a={time=_.uptime(),managers={active=0,degraded=0,draining=0,offline=0},jobs={pending=0,running=0,done=0,failed=0,cancelled=0},storage=nil,host_thread_budget=I and
I.host_thread_budget or nil,compute_bound_in_flight=G.computeBoundInFlight(),recent_events=G.recentEvents(10)}
for h,g in pairs(G._data.managers)do local i=g.state or ab;a.managers[i]=
(a.managers[i]or 0)+1 end;for h,g in pairs(G._data.jobs)do local i=g.state or"pending"a.jobs[i]=
(a.jobs[i]or 0)+1 end
if
G._data.storage_node then local g=G._data.storage_node
a.storage={address=g.address,capacity_bytes=g.capacity,used_bytes=g.used,last_seen=g.last_seen}end;local f=require("kernel.serialize")local e=f.encode(a)
local b=X..".tmp"af()local c,d
if L.writeFile then c,d=L.writeFile(b,e)else local g;g,d=L.open(b,"w")if g then
g:write(e)g:close()c=true end end;if not c then
J.warn(K,"status snapshot tmp write failed: "..tostring(d))return end;if L.exists and L.exists(X)and
L.remove then pcall(L.remove,X)end
if
L.rename then local g=pcall(L.rename,b,X)if not g then
J.warn(K,"status snapshot rename failed")end end end
local function ak(a)local f=I and I.min_supported_protocol or"1.0"
local function b(h)
local i,j=tostring(
h or""):match("^(%d+)%.(%d+)$")return tonumber(i),tonumber(j)end;local c,d=b(a)local e,g=b(f)
if not c or not d then return false,"version_malformed"end;if not e then return true end
if c~=e then return false,"version_mismatch"end;if d<g then return false,"version_mismatch"end;return true end
function H._onRegister(b,a)local c=b.payload or{}
if not c.hostname or not c.profile or not
c.worker_count then
J.warn(K,"CLUSTER_REGISTER missing required fields from "..tostring(a))
N.sendRegisterAck(a,nil,false,"incomplete_register")return end;local f,d=ak(c.cluster_protocol)
if not f then
J.warn(K,string.format("register rejected from %s: %s (their=%s, ours=%s)",tostring(a),d,tostring(c.cluster_protocol),tostring(
I and I.cluster_protocol)))
N.sendRegisterAck(a,nil,false,d,{master_protocol=I and I.cluster_protocol,min_supported_protocol=I and I.min_supported_protocol})return end
local e=G.withLock(function()return G.registerManager(a,c)end)
J.info(K,string.format("registered %s@%s as domain %d",c.hostname or"?",tostring(a):sub(1,8),e))
N.sendRegisterAck(a,e,true,nil,{heartbeat_interval=I and I.heartbeat_interval or 5,master_protocol=
I and I.cluster_protocol or"1.0",min_supported_protocol=I and I.min_supported_protocol or"1.0"})end
function H._onHeartbeat(b,a)local c=b.payload or{}
local e,f=G.updateManagerHeartbeat(a,c)if not e then
J.warn(K,"heartbeat from unknown "..tostring(a)..": "..tostring(f))return end;if c.state==ai then
G.setManagerState(a,ai)end;local d=G.getManager(a)if d and d.state==ah then
G.setManagerState(a,ag)end end
function H._onResult(a,b)local c=a.payload or{}if not c.assignment_id then
J.warn(K,"CLUSTER_RESULT missing assignment_id from "..
tostring(b))return end
G.withLock(function()
M.onResult(c.assignment_id,c,G)end)end
function H._onResultChunk(a,b)local c=a.payload or{}
if
not c.assignment_id or not c.chunk_idx or not c.chunk_total then return end
G.withLock(function()
M.onResultChunk(c.assignment_id,c.chunk_idx,c.chunk_total,c.data,c.final_stats,G)end)end
function H._onAssignAck(a,b)local c=a.payload or{}if not c.assignment_id then return end
if
c.accepted==false then
J.warn(K,string.format("manager %s rejected asn %d: %s",tostring(b):sub(1,8),c.assignment_id,tostring(c.reason)))
for d,e in pairs(G._data.jobs)do
if e.assignments[c.assignment_id]then
G.setAssignmentState(d,c.assignment_id,"pending",{assigned_to=G.CLEAR,retry_reason="manager_rejected"})break end end end end;function H._onStatusRes(b,a)
J.info(K,"status response from "..tostring(a):sub(1,8))end
function H._onRelayFail(a,b)local c=a.payload or{}
G.pushEvent("relay_fail",{reason=c.reason,failed_at=c.failed_at,original_dest=c.original_dest,original_inner_type=c.original_inner_type})
J.warn(K,string.format("RELAY_FAIL reason=%s at=%s (inner=%s)",tostring(c.reason),tostring(c.failed_at),tostring(c.original_inner_type)))end;return H