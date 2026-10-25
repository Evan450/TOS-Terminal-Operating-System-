local ae,af,av,aj,ak,ap="bridge","cancelled","draining","inline","refuse","string"
local function aq(...)for a=1,select("#",...)
do local c,b=pcall(require,(select(a,...)))
if c and b then return b end end end;local ah=aq("kernel.fs","filesystem")
local ad=require("computer")local ai=aq("kernel.event","event")
local ac=require("kernel.net")local aa=require("kernel.net.protocol")local Y
do
local a=aq("kernel.log","log")if a and a.info then Y=a else
Y={info=function()end,warn=function()end,error=function()end}end end;local _="cluster.mgr"local ab={}local al=false;local X=nil;local W=nil;local am={}local an={}local ag={}local Z=nil
local ar=0;local as="/etc/cluster-manager.cfg"
local aC={master_address=nil,hostname=nil,compute_profile="mixed",worker_count=4,storage_type=nil,storage_capacity=nil,cluster_protocol="1.0",register_retry_seconds=10,min_heartbeat_seconds=2,max_heartbeat_seconds=30,worker_bridge_address=nil,worker_bridge_enabled=false,worker_bridge_domain=0,worker_bridge_secret=nil,worker_bridge_bootstrap=180,worker_bridge_mode="opt-in",task_timeout_seconds=30,task_execution=aj}
local function aD()
return
{registered=false,domain_id=nil,master_addr=nil,heartbeat_interval=5,last_register_try=0,workers_active=0,workers_busy=0,queue_depth=0,storage_used=0,errors_last_min=0,state="active",started_at=ad.uptime()}end
local function aE()if not ah.exists("/etc/hostname")then return nil end
local a=
ah.readFile and ah.readFile("/etc/hostname")if not a then return nil end;local b=a:match("[^\r\n]*")return b and
b:match("^%s*(.-)%s*$")or nil end
local function aF()local a={}for b,c in pairs(aC)do a[b]=c end
if ah.exists(as)then
local b=ah.readFile and ah.readFile(as)local c,d=b and load(b,"="..as,"t")
if c then local f,e=pcall(c)if f and type(e)==
"table"then for g,h in pairs(e)do a[g]=h end else
Y.error(_,"config did not return a table: "..
tostring(e))end else Y.error(_,
"config load failed: "..tostring(d))end end;if not a.hostname then a.hostname=aE()or"manager"end
return a end
local function aw(a,b)
return
{hostname=a.hostname,profile=a.compute_profile,worker_count=a.worker_count,storage={external_type=a.storage_type or"none",external_capacity=a.storage_capacity or 0},cluster_protocol=a.cluster_protocol,started_at=b.started_at}end;ab._registerPayload=aw
local function ax()if not X.master_address then
Y.error(_,"no master_address configured; cannot register")return false end;local a=aw(X,W)
local b=aa.makePacket(aa.TYPE.CLUSTER_REGISTER,a,{to=X.master_address})local c,d=ac.send(X.master_address,b)if not c then
Y.warn(_,"register send failed: "..tostring(d))return false end
W.last_register_try=ad.uptime()
Y.info(_,"CLUSTER_REGISTER sent to "..X.master_address:sub(1,8).."...")return true end
local function aG(b,a)local d=b.payload or{}if a~=X.master_address then
Y.warn(_,"register_ack from unexpected sender "..
tostring(a))return end;if not d.accepted then
Y.error(_,
"register rejected: "..tostring(d.reason))return end;W.registered=true
W.domain_id=d.domain_id;W.master_addr=a
local c=tonumber(d.heartbeat_interval)or 5
if c<X.min_heartbeat_seconds then c=X.min_heartbeat_seconds end
if c>X.max_heartbeat_seconds then c=X.max_heartbeat_seconds end;W.heartbeat_interval=c
Y.info(_,string.format("registered as domain %d (hb=%ds)",d.domain_id or-1,c))end
local function aH()
if not W.registered or not W.master_addr then return end
local a={state=W.state,workers_active=X.worker_count,workers_busy=W.workers_busy,queue_depth=W.queue_depth,storage_used=W.storage_used,errors_last_min=W.errors_last_min,uptime=ad.uptime()-W.started_at}if X.storage_type then a.external_type=X.storage_type end
local b=aa.makePacket(aa.TYPE.CLUSTER_HEARTBEAT,a,{to=W.master_addr})local c=pcall(ac.send,W.master_addr,b)
if c then W.errors_last_min=0 end end
local function aI(a)
if type(a)~="table"then return false,"payload not a table"end
if not a.assignment_id then return false,"missing assignment_id"end;if not a.job_id then return false,"missing job_id"end;if
a.tasks_inline~=nil and type(a.tasks_inline)~="table"then return false,
"tasks_inline not a list"end;if
a.tasks_inline and#a.tasks_inline>100 then
return false,"too many tasks_inline (>100)"end;return true end
local function ao(a,b,c)if not W.master_addr then return end
local d=aa.makePacket(aa.TYPE.CLUSTER_ASSIGN_ACK,{assignment_id=a,accepted=b and true or false,reason=c},{to=W.master_addr})pcall(ac.send,W.master_addr,d)end
local function at(a,b,c,d,e)if not W.master_addr then return end
local f=aa.makePacket(aa.TYPE.CLUSTER_RESULT,{assignment_id=a,status=b,output_inline=c,errors=d,stats=e},{to=W.master_addr})pcall(ac.send,W.master_addr,f)end
local function au(a,b)if type(a)~="table"or type(a.code)~=ap then
return nil,"malformed task"end
local f={_input=a.input,math=math,string=string,table=table,pairs=pairs,ipairs=ipairs,next=next,select=select,type=type,tostring=tostring,tonumber=tonumber,error=error,pcall=pcall,xpcall=xpcall}local d,g=load(a.code,"=cluster:task","t",f)if not d then return nil,
"compile: "..tostring(g)end
local c=coroutine.create(d)
if type(debug)=="table"and debug.sethook and b then
pcall(debug.sethook,c,function()
if
b.cancelled then error("cancelled by CLUSTER_CANCEL",0)end end,"",5000)end;local h,e=coroutine.resume(c)if
type(debug)=="table"and debug.sethook then pcall(debug.sethook,c)end
if not h then
local i=tostring(e)if i:find(af,1,true)then return nil,af end;return nil,"runtime: "..i end;return e end
local function ay(a,b,c)if c>0 then return af end;if b==0 then return"ok"end
if a>0 and b==a then return"failed"end;return"partial"end;ab._aggregateStatus=ay
local function az(a,b,d,c)local e=aj
if b then if
type(a)=="table"and a.via_bridge==true then e=ae elseif d=="prefer"then e=ae end end
if e==aj then if c==ak then return ak end;if c==ae then return b and ae or ak end end;return e end;ab._routeTask=az
local function aA(b,a,c)if(b or 0)==0 then return true end;if a==ak then
return false,"task_execution=refuse"end;if a==ae and not c then
return false,"task_execution=bridge and no worker bridge is up"end;return true end;ab._canAcceptTasks=aA
local function aJ()if not Z or not Z.mod or not Z.mod.list then return
nil end;local a={}
for c,b in ipairs(Z.mod.list())do if
b.state=="idle"then a[#a+1]=b.addr end end;if#a==0 then return nil end;ar=(ar%#a)+1;return a[ar]end
local function aB(a,b)
local d={total=a,done=0,errorCount=0,cancelledCount=0,outputs={},errors={},recorded={},finished=false}
local function e()if d.finished or d.done<d.total then return end
d.finished=true
b(ay(d.total,d.errorCount,d.cancelledCount),d.outputs,
d.errorCount>0 and d.errors or nil,{errorCount=d.errorCount,cancelledCount=d.cancelledCount})end
function d.record(c,g,f)if d.recorded[c]then return end;d.recorded[c]=true
d.outputs[c]=g
if f==af then d.cancelledCount=d.cancelledCount+1 elseif f then d.errors[c]=f;d.errorCount=
d.errorCount+1 end;d.done=d.done+1;e()end;if a<=0 then e()end;return d end;ab._newCollector=aB
local function aK(a)local b=a.status;if b=="ok"then return a.output,nil end;if
b==af then return a.output,af end
if b=="timeout"then return a.output,"timeout: "..
tostring(a.err or"")end;return a.output,a.err or b or"worker error"end
local function aL(a)local c=a.assignment_id;local e=a.tasks_inline or{}local f=ad.uptime()
local b=ag[c]
if not b then b={id=c,p=a,cancelled=false,bridgeTids={}}ag[c]=b end;b.pending=nil;if b.cancelled then ag[c]=nil
at(c,af,nil,nil,{duration=0,task_count=#e,error_count=0,cancelled_count=#e})return end;W.workers_busy=
W.workers_busy+1
b.collector=aB(#e,function(h,i,j,g)
W.workers_busy=math.max(0,W.workers_busy-1)
W.errors_last_min=W.errors_last_min+ (g.errorCount or 0)ag[c]=nil
at(c,h,i,j,{duration=ad.uptime()- (a.dispatched_at or f),task_count=#e,error_count=g.errorCount,cancelled_count=g.cancelledCount})end)if#e==0 then return end;local d=b.collector.record
for g,h in ipairs(e)do
if b.cancelled then
d(g,nil,af)else
local i=az(h,Z~=nil,X.worker_bridge_mode,X.task_execution)local j=(i==ae)and aJ()or nil
if i==ak then
d(g,nil,"refused by task_execution="..
tostring(X.task_execution))elseif j then
local k=Z.mod.dispatch(j,h.code,{inputs=h.input,timeout=X.task_timeout_seconds,on_result=function(m,n,l)b.bridgeTids[g]=nil;d(g,aK(l))end})
if k then b.bridgeTids[g]=k elseif X.task_execution==ae then
d(g,nil,"no idle worker and task_execution=bridge")else d(g,au(h,b))end elseif i==ae then d(g,au(h,b))else d(g,au(h,b))end end end end
local function aM(b,a)if a~=W.master_addr then
Y.warn(_,"assign from non-master "..tostring(a):sub(1,8))return end;local c=b.payload or{}
local e,f=aI(c)if not e then ao(c.assignment_id,false,f)return end
if W.state==
av then ao(c.assignment_id,false,av)return end
local g,d=aA(c.tasks_inline and#c.tasks_inline or 0,X.task_execution,Z~=nil)if not g then ao(c.assignment_id,false,d)
Y.info(_,"assignment refused: "..tostring(d))return end
ao(c.assignment_id,true)
ag[c.assignment_id]={id=c.assignment_id,p=c,cancelled=false,pending=true,bridgeTids={}}ai.timer(0.1,function()pcall(aL,c)end)end
local function aN(b,a)local d=b.payload or{}if a and a~=W.master_addr then
Y.warn(_,"cancel from non-master "..
tostring(a):sub(1,8).." ignored")return end
local c=ag[d.assignment_id]if not c then
at(d.assignment_id,af,nil,nil,{reason="cancel_for_unknown_inflight"})return end;c.cancelled=true;if c.pending then
Y.info(_,string.format("cancel before dispatch for assignment %s",tostring(d.assignment_id)))return end
if c.bridgeTids and
c.collector then for e,f in pairs(c.bridgeTids)do if Z and Z.mod and Z.mod.cancel then
pcall(Z.mod.cancel,f)end
c.collector.record(e,nil,af)end end
Y.info(_,string.format("cancel flagged for assignment %d",d.assignment_id))end;local function aO(b,a)if a~=W.master_addr then return end
Y.info(_,"drain requested")W.state=av end
local function aP()
if W.registered then return end;if
ad.uptime()-W.last_register_try<X.register_retry_seconds then return end;ax()end
local function aQ()if not W.registered then return end;local a=ad.uptime()if
a-
(W.last_heartbeat or 0)< (W.heartbeat_interval or 0)then return end;W.last_heartbeat=a;aH()end
function ab.start()if al then return true end;X=aF()W=aD()
if not X.master_address then
Y.error(_,"no master_address in /etc/cluster-manager.cfg; refusing to start")return false,"no master_address"end
local function a(b,c)local d=ac.on(b,c)am[#am+1]={type=b,id=d}end;a(aa.TYPE.CLUSTER_REGISTER_ACK,aG)
a(aa.TYPE.CLUSTER_ASSIGN,aM)a(aa.TYPE.CLUSTER_CANCEL,aN)
a(aa.TYPE.CLUSTER_DRAIN,aO)
an.register=ai.interval(X.register_retry_seconds,aP,"cluster-mgr.register")
an.heartbeat=ai.interval(X.min_heartbeat_seconds,aQ,"cluster-mgr.heartbeat")
if X.worker_bridge_enabled then local c,b=pcall(require,"cluster.worker")
if not c or not b then
Y.warn(_,"worker_bridge_enabled but cluster.worker module unavailable; running inline")else if b.init then pcall(b.init,{log=Y,event=ai})end
local d,e=b.setSecret(X.worker_bridge_secret)
if not d then
Y.error(_,"worker bridge disabled: "..tostring(e))else
local f,g=b.setDomainId(X.worker_bridge_domain or 0)
if not f then
Y.error(_,"worker bridge bind failed: "..tostring(g))else pcall(b.setBootstrap,X.worker_bridge_bootstrap)
Z={mod=b}
Y.info(_,string.format("worker bridge up (domain %d, mode '%s', %ds bootstrap)",X.worker_bridge_domain or 0,X.worker_bridge_mode,
X.worker_bridge_bootstrap or 0))end end end end
do local b=X.task_execution
if b~=aj and b~=ae and b~=ak then
Y.warn(_,"task_execution="..tostring(b)..
" is not a known policy; treating it as 'inline'")X.task_execution=aj;b=aj end
if b==aj then
if not
(type(debug)=="table"and type(debug.sethook)=="function")then
Y.warn(_,"task_execution=inline and mid-task cancellation is "..

"UNAVAILABLE here (OpenComputers withholds debug.sethook): a task "..
"that never returns cannot be stopped, and OC's watchdog will "..
"reboot this whole computer, every seat included. Set "..

"task_execution='bridge' (run tasks on an OpenOS worker) or ".."'refuse' (run none) in /etc/cluster-manager.cfg to bound it.")end elseif b==ae and not Z then
Y.warn(_,"task_execution=bridge but no worker bridge is up: "..
"every assignment carrying tasks will be refused until one is.")elseif b==ak then
Y.info(_,"task_execution=refuse: assignments carrying task code ".."are rejected; this Manager contributes presence and storage only.")end end;ax()al=true
Y.info(_,"started (master="..
X.master_address:sub(1,8).."...)")return true end
function ab.stop()if not al then return true end;for b,a in pairs(am)do
pcall(ac.off,a.type,a.id)end;am={}
for b,a in pairs(an)do pcall(ai.cancelTimer,a)end;an={}
if Z and Z.mod and Z.mod.stop then pcall(Z.mod.stop)end;Z=nil;al=false;W.registered=false;Y.info(_,"stopped")return true end;function ab.workers()
if not Z or not Z.mod or not Z.mod.list then return{}end;return Z.mod.list()end
function ab.status()if
not al then return{running=false}end;local a=0;if
Z and Z.mod and Z.mod.list then a=#Z.mod.list()end
return
{running=true,registered=W.registered,domain_id=W.domain_id,master_addr=W.master_addr,state=W.state,bridge_enabled=
Z~=nil,bridge_workers=a,cancel_midtask=(type(debug)=="table"and type(debug.sethook)=="function"),task_execution=X.task_execution,workers_active=X.worker_count,workers_busy=W.workers_busy,queue_depth=W.queue_depth,errors_last_min=W.errors_last_min,uptime=
ad.uptime()-W.started_at,inflight_assignments=(function()local b=0;for c in pairs(ag)do b=b+1 end;return b end)()}end;function ab.drain()W.state=av;return true end
function ab.undrain()W.state="active"return true end
function ab.pair(a,b,c)c=c or{}
if type(a)~=ap or#a<16 then return false,"invalid master address"end
if type(b)~=ap or#b<12 then return false,"pairing code looks too short"end;local d=require("kernel.crypto")
local f=require("kernel.net.trust")local g=d.hashPassword(b,"tos-cluster-pair-v1")local j=3
local m=pcall(f.setLevel,"root",a,f.LEVEL.TRUSTED,j)local n=pcall(f.setSecret,"root",a,g,j)
if not(m and n)then return false,
"could not update local trust DB (admin tier required?)"end
local e=ac.getAddress and ac.getAddress()or nil;if type(e)~=ap or#e<16 then
return false,"cannot determine this machine's modem address (no modem?)"end;local k=ad.uptime()
local o=d.hmac(g,
tostring(e).."|"..tostring(k))
local p=aa.makePacket(aa.TYPE.CLUSTER_PAIR_INIT,{mac=o,ts=k},{to=a})local h=false;local i=nil
local l=ac.on(aa.TYPE.CLUSTER_PAIR_CONFIRM,function(t,u)if u~=a then return end
local v=t.payload or{}if type(v.mac)~=ap or type(v.ts)~="number"then
i="malformed confirm"return end;local w=d.hmac(g,tostring(e)..
"|"..tostring(v.ts))if
d.ctEquals(w,v.mac)then h=true else i="MAC mismatch"end end)local q,r=pcall(ac.send,a,p)
if not q then
ac.off(aa.TYPE.CLUSTER_PAIR_CONFIRM,l)return false,"send failed: "..tostring(r)end;local s=ad.uptime()+10;while not h and ad.uptime()<s do
ai.pull(0.25)end
ac.off(aa.TYPE.CLUSTER_PAIR_CONFIRM,l)
if h then if W then W.master_addr=a end;return true,"paired"end;return false,
"no confirm received within 10s (local trust DB still updated; check net link). ".. (i or"")end;return ab