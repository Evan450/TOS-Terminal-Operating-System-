local al,am,aC,ar,as,ap="bridge","cancelled","draining","inline","refuse","string"
local function ao(...)for a=1,select("#",...)
do local c,b=pcall(require,(select(a,...)))
if c and b then return b end end end;local aq=ao("kernel.fs","filesystem")
local aj=require("computer")local ak=ao("kernel.event","event")
local ai=require("kernel.net")local ag=require("kernel.net.protocol")local ad
do
local a=ao("kernel.log","log")if a and a.info then ad=a else
ad={info=function()end,warn=function()end,error=function()end}end end;local af="cluster.mgr"local ah={}local at=false;local ac=nil;local ab=nil;local au={}local av={}local an={}
local ae=nil;local ay=0;local az="/etc/cluster-manager.cfg"
local aM={master_address=nil,hostname=nil,compute_profile="mixed",worker_count=4,storage_type=nil,storage_capacity=nil,cluster_protocol="1.0",register_retry_seconds=10,min_heartbeat_seconds=2,max_heartbeat_seconds=30,worker_bridge_address=nil,worker_bridge_enabled=false,worker_bridge_domain=0,worker_bridge_secret=nil,worker_bridge_bootstrap=180,worker_bridge_mode="opt-in",task_timeout_seconds=30,task_execution=ar}
local function aN()
return
{registered=false,domain_id=nil,master_addr=nil,heartbeat_interval=5,last_register_try=0,workers_active=0,workers_busy=0,queue_depth=0,storage_used=0,errors_last_min=0,state="active",started_at=aj.uptime()}end
local function aO()if not aq.exists("/etc/hostname")then return nil end
local a=
aq.readFile and aq.readFile("/etc/hostname")if not a then return nil end;local b=a:match("[^\r\n]*")return b and
b:match("^%s*(.-)%s*$")or nil end
local function aP()local a={}for b,c in pairs(aM)do a[b]=c end
if aq.exists(az)then
local b=aq.readFile and aq.readFile(az)local c,d=b and load(b,"="..az,"t")
if c then local f,e=pcall(c)if f and type(e)==
"table"then for g,h in pairs(e)do a[g]=h end else
ad.error(af,"config did not return a table: "..
tostring(e))end else
ad.error(af,
"config load failed: "..tostring(d))end end;if not a.hostname then a.hostname=aO()or"manager"end
return a end
local function aD(a,b)
return
{hostname=a.hostname,profile=a.compute_profile,worker_count=a.worker_count,storage={external_type=a.storage_type or"none",external_capacity=a.storage_capacity or 0},cluster_protocol=a.cluster_protocol,started_at=b.started_at}end;ah._registerPayload=aD
local function aE()if not ac.master_address then
ad.error(af,"no master_address configured; cannot register")return false end
local a=aD(ac,ab)
local b=ag.makePacket(ag.TYPE.CLUSTER_REGISTER,a,{to=ac.master_address})local c,d=ai.send(ac.master_address,b)if not c then ad.warn(af,"register send failed: "..
tostring(d))
return false end
ab.last_register_try=aj.uptime()
ad.info(af,"CLUSTER_REGISTER sent to "..ac.master_address:sub(1,8).."...")return true end
local function aQ(b,a)local d=b.payload or{}if a~=ac.master_address then
ad.warn(af,"register_ack from unexpected sender "..
tostring(a))return end;if not d.accepted then
ad.error(af,
"register rejected: "..tostring(d.reason))return end;ab.registered=true
ab.domain_id=d.domain_id;ab.master_addr=a
local c=tonumber(d.heartbeat_interval)or 5
if c<ac.min_heartbeat_seconds then c=ac.min_heartbeat_seconds end
if c>ac.max_heartbeat_seconds then c=ac.max_heartbeat_seconds end;ab.heartbeat_interval=c
ad.info(af,string.format("registered as domain %d (hb=%ds)",d.domain_id or-1,c))end
local function aR()
if not ab.registered or not ab.master_addr then return end
local a={state=ab.state,workers_active=ac.worker_count,workers_busy=ab.workers_busy,queue_depth=ab.queue_depth,storage_used=ab.storage_used,errors_last_min=ab.errors_last_min,uptime=aj.uptime()-ab.started_at}if ac.storage_type then a.external_type=ac.storage_type end
local b=ag.makePacket(ag.TYPE.CLUSTER_HEARTBEAT,a,{to=ab.master_addr})local c=pcall(ai.send,ab.master_addr,b)
if c then ab.errors_last_min=0 end end
local function aS(a)
if type(a)~="table"then return false,"payload not a table"end
if not a.assignment_id then return false,"missing assignment_id"end;if not a.job_id then return false,"missing job_id"end;if
a.tasks_inline~=nil and type(a.tasks_inline)~="table"then return false,
"tasks_inline not a list"end;if
a.tasks_inline and#a.tasks_inline>100 then
return false,"too many tasks_inline (>100)"end
if a.tasks_ref~=nil and
(
type(a.tasks_ref)~=ap or type(a.store_addr)~=ap)then return false,"tasks_ref needs a store_addr"end;return true end
local function aw(a,b,c)if not ab.master_addr then return end
local d=ag.makePacket(ag.TYPE.CLUSTER_ASSIGN_ACK,{assignment_id=a,accepted=b and true or false,reason=c},{to=ab.master_addr})pcall(ai.send,ab.master_addr,d)end
local function ax(a,b,c,d,e)if not ab.master_addr then return end
local f=ag.makePacket(ag.TYPE.CLUSTER_RESULT,{assignment_id=a,status=b,output_inline=c,errors=d,stats=e},{to=ab.master_addr})pcall(ai.send,ab.master_addr,f)end
local function aA(a,b)if type(a)~="table"or type(a.code)~=ap then
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
local i=tostring(e)if i:find(am,1,true)then return nil,am end;return nil,"runtime: "..i end;return e end
local function aF(a,b,c)if c>0 then return am end;if b==0 then return"ok"end
if a>0 and b==a then return"failed"end;return"partial"end;ah._aggregateStatus=aF
local function aG(a,b,d,c)local e=ar
if b then if
type(a)=="table"and a.via_bridge==true then e=al elseif d=="prefer"then e=al end end
if e==ar then if c==as then return as end;if c==al then return b and al or as end end;return e end;ah._routeTask=aG
local function aH(b,a,c)if(b or 0)==0 then return true end;if a==as then
return false,"task_execution=refuse"end;if a==al and not c then
return false,"task_execution=bridge and no worker bridge is up"end;return true end;ah._canAcceptTasks=aH
local function aT()if
not ae or not ae.mod or not ae.mod.list then return nil end;local a={}
for c,b in ipairs(ae.mod.list())do if
b.state=="idle"then a[#a+1]=b.addr end end;if#a==0 then return nil end;ay=(ay%#a)+1;return a[ay]end
local function aI(a,b)
local d={total=a,done=0,errorCount=0,cancelledCount=0,outputs={},errors={},recorded={},finished=false}
local function e()if d.finished or d.done<d.total then return end
d.finished=true
b(aF(d.total,d.errorCount,d.cancelledCount),d.outputs,
d.errorCount>0 and d.errors or nil,{errorCount=d.errorCount,cancelledCount=d.cancelledCount})end
function d.record(c,g,f)if d.recorded[c]then return end;d.recorded[c]=true
d.outputs[c]=g
if f==am then d.cancelledCount=d.cancelledCount+1 elseif f then d.errors[c]=f;d.errorCount=
d.errorCount+1 end;d.done=d.done+1;e()end;if a<=0 then e()end;return d end;ah._newCollector=aI
local function aU(a)local b=a.status;if b=="ok"then return a.output,nil end;if
b==am then return a.output,am end
if b=="timeout"then return a.output,"timeout: "..
tostring(a.err or"")end;return a.output,a.err or b or"worker error"end;local aV=15
local function aW(b,a)local i=ao("cluster.protocol")
local d=ao("kernel.serialize")local e=ao("component")
local n=e and e.list and e.list("modem")()local c=n and e.proxy(n)if not(i and d and c)then
return a(nil,"no_modem")end;local f=i.PORT.PUBLIC_READ
local o=b.tasks_ref:gsub("^public://","")local p=b.assignment_id
for s in e.list("modem")do
if s==b.store_addr then
local t=ao("cluster.store")if not t then return a(nil,"no local store")end
local u,w=t.get(o)
if not u then return a(nil,"store: "..tostring(w))end;local x,v=pcall(d.decode,u)
if x and type(v)=="table"then return a(v)end;return a(nil,"tasks did not decode")end end;local k=false
if c.isOpen and not c.isOpen(f)then k=c.open(f)end;local l,m,j,g={},0,nil,nil
local function h(s,t)
if j then ak.off("modem_message",j)j=nil end;if g then ak.cancelTimer(g)g=nil end;if k then pcall(c.close,f)
k=false end;a(s,t)end
j=ak.on("modem_message",function(v,v,s,t,v,u)if t~=f or s~=b.store_addr then return end
local y,w=pcall(d.decode,u,{maxBytes=8192})if

not y or type(w)~="table"or w.magic~=i.PUB_MAGIC or w.op~="RES"or w.req_id~=p then return end
if w.err then return h(nil,"store: "..
tostring(w.err))end
if type(w.data)~=ap or l[w.chunk or 1]then return end;l[w.chunk or 1]=w.data;m=m+1
if m< (w.total or 1)then return end;local z,x=pcall(d.decode,table.concat(l))if z and
type(x)=="table"then return h(x)end
h(nil,"tasks did not decode")end,"cluster-mgr.tasks")
g=ak.timer(aV,function()g=nil;h(nil,"timed out")end)
local q,r=pcall(c.send,b.store_addr,f,d.encode(i.pubGet(o,p)))if not q then h(nil,tostring(r))end end
local function aJ(a)local c=a.assignment_id;local e=a.tasks_inline or{}local f=aj.uptime()
local b=an[c]
if not b then b={id=c,p=a,cancelled=false,bridgeTids={}}an[c]=b end;b.pending=nil;if b.cancelled then an[c]=nil
ax(c,am,nil,nil,{duration=0,task_count=#e,error_count=0,cancelled_count=#e})return end;ab.workers_busy=
ab.workers_busy+1
b.collector=aI(#e,function(h,i,j,g)
ab.workers_busy=math.max(0,ab.workers_busy-1)
ab.errors_last_min=ab.errors_last_min+ (g.errorCount or 0)an[c]=nil
ax(c,h,i,j,{duration=aj.uptime()- (a.dispatched_at or f),task_count=#e,error_count=g.errorCount,cancelled_count=g.cancelledCount})end)if#e==0 then return end;local d=b.collector.record
for g,h in ipairs(e)do
if b.cancelled then
d(g,nil,am)else
local i=aG(h,ae~=nil,ac.worker_bridge_mode,ac.task_execution)local j=(i==al)and aT()or nil
if i==as then
d(g,nil,"refused by task_execution="..
tostring(ac.task_execution))elseif j then
local k=ae.mod.dispatch(j,h.code,{inputs=h.input,timeout=ac.task_timeout_seconds,on_result=function(m,n,l)b.bridgeTids[g]=nil;d(g,aU(l))end})
if k then b.bridgeTids[g]=k elseif ac.task_execution==al then
d(g,nil,"no idle worker and task_execution=bridge")else d(g,aA(h,b))end elseif i==al then d(g,aA(h,b))else d(g,aA(h,b))end end end end
local function aX(b,a)if a~=ab.master_addr then
ad.warn(af,"assign from non-master "..tostring(a):sub(1,8))return end;local c=b.payload or{}
local e,f=aS(c)if not e then aw(c.assignment_id,false,f)return end
if
ab.state==aC then aw(c.assignment_id,false,aC)return end
local g,d=aH(c.tasks_inline and#c.tasks_inline or 0,ac.task_execution,ae~=nil)if not g then aw(c.assignment_id,false,d)
ad.info(af,"assignment refused: "..tostring(d))return end
aw(c.assignment_id,true)
an[c.assignment_id]={id=c.assignment_id,p=c,cancelled=false,pending=true,bridgeTids={}}
ak.timer(0.1,function()if not c.tasks_ref then return pcall(aJ,c)end
aW(c,function(h,i)if h then
c.tasks_inline=h;return pcall(aJ,c)end
ad.warn(af,"assignment "..

tostring(c.assignment_id)..": cannot read its tasks: "..tostring(i))an[c.assignment_id]=nil
ax(c.assignment_id,"failed",nil,{"cannot read tasks: "..tostring(i)},{duration=0,task_count=0,error_count=1,cancelled_count=0})end)end)end
local function aY(b,a)local d=b.payload or{}if a and a~=ab.master_addr then
ad.warn(af,"cancel from non-master "..
tostring(a):sub(1,8).." ignored")return end
local c=an[d.assignment_id]if not c then
ax(d.assignment_id,am,nil,nil,{reason="cancel_for_unknown_inflight"})return end;c.cancelled=true;if c.pending then
ad.info(af,string.format("cancel before dispatch for assignment %s",tostring(d.assignment_id)))return end
if c.bridgeTids and
c.collector then for e,f in pairs(c.bridgeTids)do if ae and ae.mod and ae.mod.cancel then
pcall(ae.mod.cancel,f)end
c.collector.record(e,nil,am)end end
ad.info(af,string.format("cancel flagged for assignment %d",d.assignment_id))end;local function aZ(b,a)if a~=ab.master_addr then return end
ad.info(af,"drain requested")ab.state=aC end
local function a_()
if ab.registered then return end;if
aj.uptime()-ab.last_register_try<ac.register_retry_seconds then return end;aE()end
local function ba()if not ab.registered then return end;local a=aj.uptime()if
a-
(ab.last_heartbeat or 0)< (ab.heartbeat_interval or 0)then return end;ab.last_heartbeat=a;aR()end
function ah.start()if at then return true end;ac=aP()ab=aN()
if not ac.master_address then
ad.error(af,"no master_address in /etc/cluster-manager.cfg; refusing to start")return false,"no master_address"end
local function a(b,c)local d=ai.on(b,c)au[#au+1]={type=b,id=d}end;a(ag.TYPE.CLUSTER_REGISTER_ACK,aQ)
a(ag.TYPE.CLUSTER_ASSIGN,aX)a(ag.TYPE.CLUSTER_CANCEL,aY)
a(ag.TYPE.CLUSTER_DRAIN,aZ)
av.register=ak.interval(ac.register_retry_seconds,a_,"cluster-mgr.register")
av.heartbeat=ak.interval(ac.min_heartbeat_seconds,ba,"cluster-mgr.heartbeat")
if ac.worker_bridge_enabled then local c,b=pcall(require,"cluster.worker")
if
not c or not b then
ad.warn(af,"worker_bridge_enabled but cluster.worker module unavailable; running inline")else
if b.init then pcall(b.init,{log=ad,event=ak})end;local d,e=b.setSecret(ac.worker_bridge_secret)
if not d then
ad.error(af,
"worker bridge disabled: "..tostring(e))else
local f,g=b.setDomainId(ac.worker_bridge_domain or 0)
if not f then
ad.error(af,"worker bridge bind failed: "..tostring(g))else pcall(b.setBootstrap,ac.worker_bridge_bootstrap)
ae={mod=b}
ad.info(af,string.format("worker bridge up (domain %d, mode '%s', %ds bootstrap)",ac.worker_bridge_domain or 0,ac.worker_bridge_mode,
ac.worker_bridge_bootstrap or 0))end end end end
do local b=ac.task_execution
if b~=ar and b~=al and b~=as then
ad.warn(af,"task_execution="..
tostring(b).." is not a known policy; treating it as 'inline'")ac.task_execution=ar;b=ar end
if b==ar then
if not
(type(debug)=="table"and type(debug.sethook)=="function")then
ad.warn(af,"task_execution=inline and mid-task cancellation is "..

"UNAVAILABLE here (OpenComputers withholds debug.sethook): a task "..
"that never returns cannot be stopped, and OC's watchdog will "..
"reboot this whole computer, every seat included. Set "..

"task_execution='bridge' (run tasks on an OpenOS worker) or ".."'refuse' (run none) in /etc/cluster-manager.cfg to bound it.")end elseif b==al and not ae then
ad.warn(af,"task_execution=bridge but no worker bridge is up: "..
"every assignment carrying tasks will be refused until one is.")elseif b==as then
ad.info(af,"task_execution=refuse: assignments carrying task code ".."are rejected; this Manager contributes presence and storage only.")end end;aE()at=true
ad.info(af,"started (master="..
ac.master_address:sub(1,8).."...)")return true end
function ah.stop()if not at then return true end;for b,a in pairs(au)do
pcall(ai.off,a.type,a.id)end;au={}
for b,a in pairs(av)do pcall(ak.cancelTimer,a)end;av={}
if ae and ae.mod and ae.mod.stop then pcall(ae.mod.stop)end;ae=nil;at=false;ab.registered=false;ad.info(af,"stopped")return true end
function ah.workers()
if not ae or not ae.mod or not ae.mod.list then return{}end;return ae.mod.list()end
function ah.status()if not at then return{running=false}end;local a=0;if ae and ae.mod and
ae.mod.list then a=#ae.mod.list()end
return
{running=true,registered=ab.registered,domain_id=ab.domain_id,master_addr=ab.master_addr,state=ab.state,bridge_enabled=
ae~=nil,bridge_workers=a,cancel_midtask=(type(debug)=="table"and type(debug.sethook)=="function"),task_execution=ac.task_execution,workers_active=ac.worker_count,workers_busy=ab.workers_busy,queue_depth=ab.queue_depth,errors_last_min=ab.errors_last_min,uptime=
aj.uptime()-ab.started_at,inflight_assignments=(function()local b=0;for c in pairs(an)do b=b+1 end;return b end)()}end;local aK,aB=2,3;local aL={[0]="GUEST",[1]="USER",[2]="ADMIN",[3]="ROOT"}
local bb={status=aK,workers=aK,drain=aB,undrain=aB,pair=aB}
function ah.endpoint(b,a,...)local c=bb[a]if not c then
return false,"unknown call: "..tostring(a)end;local d=b.tier or 0;if d<c then
return false,string.format("permission denied (need %s, have %s)",aL[c],
aL[d]or tostring(d))end
return true,ah[a](...)end
do local b,a=pcall(require,"kernel.ipc")if b and type(a)=="table"then
a.register("cluster-manager",ah.endpoint,"cluster-manager")end end;function ah.drain()ab.state=aC;return true end;function ah.undrain()ab.state="active"
return true end
function ah.pair(a,b,c)c=c or{}if type(a)~=ap or#a<16 then return false,
"invalid master address"end
if
type(b)~=ap or#b<12 then return false,"pairing code looks too short"end;local d=require("kernel.crypto")
local f=require("kernel.net.trust")local g=d.hashPassword(b,"tos-cluster-pair-v1")local j=3
local m=pcall(f.setLevel,"root",a,f.LEVEL.TRUSTED,j)local n=pcall(f.setSecret,"root",a,g,j)
if not(m and n)then return false,
"could not update local trust DB (admin tier required?)"end
local e=ai.getAddress and ai.getAddress()or nil;if type(e)~=ap or#e<16 then
return false,"cannot determine this machine's modem address (no modem?)"end;local k=aj.uptime()
local o=d.hmac(g,
tostring(e).."|"..tostring(k))
local p=ag.makePacket(ag.TYPE.CLUSTER_PAIR_INIT,{mac=o,ts=k},{to=a})local h=false;local i=nil
local l=ai.on(ag.TYPE.CLUSTER_PAIR_CONFIRM,function(t,u)if u~=a then return end
local v=t.payload or{}if type(v.mac)~=ap or type(v.ts)~="number"then
i="malformed confirm"return end;local w=d.hmac(g,tostring(e)..
"|"..tostring(v.ts))if
d.ctEquals(w,v.mac)then h=true else i="MAC mismatch"end end)local q,r=pcall(ai.send,a,p)
if not q then
ai.off(ag.TYPE.CLUSTER_PAIR_CONFIRM,l)return false,"send failed: "..tostring(r)end;local s=aj.uptime()+10;while not h and aj.uptime()<s do
ak.pull(0.25)end
ai.off(ag.TYPE.CLUSTER_PAIR_CONFIRM,l)
if h then if ab then ab.master_addr=a end;return true,"paired"end;return false,
"no confirm received within 10s (local trust DB still updated; check net link). ".. (i or"")end;return ah