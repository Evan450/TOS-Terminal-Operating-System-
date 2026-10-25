local u=require("kernel.net")
local s=require("kernel.net.protocol")local w=require("kernel.serialize")local o
do
local b,a=pcall(require,"kernel.log")
if not(b and a and a.info)then b,a=pcall(require,"log")end;if b and a and a.info then o=a else
o={info=function()end,warn=function()end,error=function()end}end end;local p="cluster.net"local r={}local function q(a,b)
if s.TYPE and s.TYPE[a]then return s.TYPE[a]end;return b end
local n={CLUSTER_REGISTER=q("CLUSTER_REGISTER","cluster_register"),CLUSTER_REGISTER_ACK=q("CLUSTER_REGISTER_ACK","cluster_register_ack"),CLUSTER_HEARTBEAT=q("CLUSTER_HEARTBEAT","cluster_heartbeat"),CLUSTER_ASSIGN=q("CLUSTER_ASSIGN","cluster_assign"),CLUSTER_ASSIGN_ACK=q("CLUSTER_ASSIGN_ACK","cluster_assign_ack"),CLUSTER_RESULT=q("CLUSTER_RESULT","cluster_result"),CLUSTER_RESULT_CHUNK=q("CLUSTER_RESULT_CHUNK","cluster_result_chunk"),CLUSTER_CANCEL=q("CLUSTER_CANCEL","cluster_cancel"),CLUSTER_DRAIN=q("CLUSTER_DRAIN","cluster_drain"),CLUSTER_STATUS_REQ=q("CLUSTER_STATUS_REQ","cluster_status_req"),CLUSTER_STATUS_RES=q("CLUSTER_STATUS_RES","cluster_status_res"),CLUSTER_PAIR_INIT=q("CLUSTER_PAIR_INIT","cluster_pair_init"),CLUSTER_PAIR_CONFIRM=q("CLUSTER_PAIR_CONFIRM","cluster_pair_conf"),RELAY_FORWARD=q("RELAY_FORWARD","relay_forward"),RELAY_FAIL=q("RELAY_FAIL","relay_fail")}r.TYPE=n;local v={}local x=require("computer")
local function z(a,b)if
not a or type(b)~="table"then return end;v[a]={hops=b,last_seen=x.uptime()}end
local function y(a)local b=v[a]if not b then return nil end;if x.uptime()-b.last_seen>300 then v[a]=
nil;return nil end;return b.hops end;r._returnPaths=v
local function t(a,b,c)local e=s.makePacket(b,c,{to=a})local d=y(a)
if d and#d>0 then
local f={}for j=#d,1,-1 do f[#f+1]=d[j]end;local g=f[1]if not g then
return false,"empty_reverse_path"end;local h=w.encode(e)
local i=s.makePacket(n.RELAY_FORWARD,{dest=a,path=f,ttl=math.max(3,#f+1),inner=h,inner_type=b},{to=g})return u.send(g,i)end;return u.send(a,e)end
function r.sendAssignment(b,a)
local c={assignment_id=a.assignment_id,job_id=a.job_id,priority=a.priority or 5,deadline=a.deadline or 0,retry_policy=a.retry_policy or"safe",compute_profile=
a.compute_profile or"mixed",tasks_inline=a.tasks_inline,tasks_ref=a.tasks_ref,inputs_inline=a.inputs_inline,inputs_ref=a.inputs_ref,result_sink=a.result_sink or"inline",result_prefix=a.result_prefix}return t(b,n.CLUSTER_ASSIGN,c)end
function r.sendCancel(a,b)return t(a,n.CLUSTER_CANCEL,{assignment_id=b})end;function r.sendDrain(a)return t(a,n.CLUSTER_DRAIN,{})end
function r.sendRegisterAck(d,c,b,e,a)a=
a or{}
local f={accepted=b and true or false,reason=e,domain_id=b and c or nil,worker_port=
b and(2001+ (c or 0))or nil,heartbeat_interval=a.heartbeat_interval or 5,master_protocol=a.master_protocol or"1.0",min_supported_protocol=
a.min_supported_protocol or"1.0"}return t(d,n.CLUSTER_REGISTER_ACK,f)end
function r.sendStatusReq(a)return t(a,n.CLUSTER_STATUS_REQ,{})end
function r.register(a)a=a or{}local function c(A)
return a[A]or function()
o.warn(p,"no handler bound for "..A)end end;local e=c("onRegister")
local f=c("onHeartbeat")local g=c("onResult")local h=c("onResultChunk")
local i=c("onAssignAck")local j=c("onStatusRes")local k=c("onRelayFail")
local l=c("onPairInit")local d={}
local function b(A,B)local C=u.on(A,B)d[#d+1]={type=A,id=C}end
b(n.CLUSTER_REGISTER,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then
o.warn(p,"malformed CLUSTER_REGISTER from "..tostring(B))return end
local C,D=pcall(e,A,B)if not C then
o.error(p,"onRegister threw: "..tostring(D))end end)
b(n.CLUSTER_HEARTBEAT,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then return end;local C,D=pcall(f,A,B)
if not C then o.error(p,"onHeartbeat threw: "..
tostring(D))end end)
b(n.CLUSTER_RESULT,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then return end;local C,D=pcall(g,A,B)
if not C then o.error(p,"onResult threw: "..
tostring(D))end end)
b(n.CLUSTER_RESULT_CHUNK,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then return end;local C,D=pcall(h,A,B)
if not C then o.error(p,"onResultChunk threw: "..
tostring(D))end end)
b(n.CLUSTER_ASSIGN_ACK,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then return end;local C,D=pcall(i,A,B)
if not C then o.error(p,"onAssignAck threw: "..
tostring(D))end end)
b(n.CLUSTER_STATUS_RES,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then return end;local C,D=pcall(j,A,B)
if not C then o.error(p,"onStatusRes threw: "..
tostring(D))end end)
b(n.CLUSTER_PAIR_INIT,function(A,B)if
type(A)~="table"or type(A.payload)~="table"then return end;local C,D=pcall(l,A,B)
if not C then o.error(p,"onPairInit threw: "..
tostring(D))end end)local m=true
b(n.RELAY_FORWARD,function(B,A)local D=B and B.payload;if
type(D)~="table"or not D.inner then
o.warn(p,"malformed RELAY_FORWARD from "..tostring(A))return end;if m then
o.warn(p,"refusing RELAY_FORWARD from "..
tostring(A):sub(1,8)..": relayed packets carry no origin authentication yet")return end
local C,H=w.decode(D.inner)if not C or type(C)~="table"then
o.warn(p,"relay inner decode failed: "..tostring(H))return end;local G=C.from or
(D.path and D.path[1])if
G and type(D.path)=="table"then z(G,D.path)end;local F=G or A;local E=C.type
if
E==n.CLUSTER_REGISTER then pcall(e,C,F)elseif E==n.CLUSTER_HEARTBEAT then pcall(f,C,F)elseif E==n.CLUSTER_RESULT then
pcall(g,C,F)elseif E==n.CLUSTER_RESULT_CHUNK then pcall(h,C,F)elseif E==n.CLUSTER_ASSIGN_ACK then
pcall(i,C,F)elseif E==n.CLUSTER_STATUS_RES then pcall(j,C,F)else
o.warn(p,"relay inner type not routable at Master: "..tostring(E))end end)
b(n.RELAY_FAIL,function(A,B)local C,D=pcall(k,A,B)if not C then
o.error(p,"onRelayFail threw: "..tostring(D))end end)
o.info(p,"registered "..tostring(#d).." listener(s)")return d end
function r.unregister(a)if not a then return end;for c,b in ipairs(a)do if b and b.type and b.id then
u.off(b.type,b.id)end end end;function r.hasRelayReturnPath(a)return y(a)~=nil end;return r