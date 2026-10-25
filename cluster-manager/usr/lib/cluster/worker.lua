local ao,ap,au,Z,av="REGISTER_ACK","cworker","number","string","unresponsive"
local W=require("computer")local aq=require("component")
local ar=require("kernel.serialize")local ac=require("cluster.protocol")local U={}local Y,S=nil,nil;local as="WRK"
local al=nil;local V=nil;local ai=1;local am=1;local T={}local X={}local _=nil;local aa=nil;local an={}local aj={}local aw=1024
function U.setSecret(a)if
a==nil then aa=nil;return true end;if type(a)~=Z or#a<16 then return false,
"secret must be a string of at least 16 bytes"end
aa=a;return true end;local ae={}local af=nil;local ag=nil;local ah=nil;local ad={}
local function R(a,b,...)if not Y then return end
local c=string.format(b,...)
if a=="warn"and Y.warn then Y.warn(ap,c)elseif a=="info"and Y.info then
Y.info(ap,c)elseif a=="debug"and Y.debug then Y.debug(ap,c)end end
local function ak(a)local b=type(a)
if b==Z then return"s"..#a..":"..a elseif b==au then local c=tostring(a)return"n"..#c..
":"..c elseif b=="boolean"then return a and"bT"or"bF"elseif
b=="table"then local c={}for e in pairs(a)do if e~="mac"then c[#c+1]=e end end
table.sort(c,function(e,f)
local g,h=type(e),type(f)if g~=h then return g<h end;return e<f end)local d={}
for f,e in ipairs(c)do d[#d+1]=ak(e)..ak(a[e])end;return"{"..table.concat(d).."}"end;return"z"end
local function ab(b,a)if not V then return false,"domain_id not set"end;a.magic=as
if aa then
local f,e=pcall(require,"kernel.crypto")if f and e and e.hmac and e.salt then a.nonce=e.salt(16)
a.mac=e.hmac(aa,ak(a))end end;local d=ar.compact(a)local c=false;for f,e in ipairs(ad)do local g=pcall(e.send,b,V,d)
c=c or g end
if not c then return false,"send failed on all NICs"end;return true end
local function ax()ad={}for a in aq.list("modem")do local c,b=pcall(aq.proxy,a)
if c and b then ad[#ad+1]=b end end end
local function ay(a)for c,b in ipairs(ad)do pcall(b.open,a)end end
local function at(a)for c,b in ipairs(ad)do pcall(b.close,a)end end
local function az(a,b)local c=T[a]
if not c then
if not _ or W.uptime()>_ then
ab(a,{op=ao,accepted=false,reason="bootstrap window closed"})
R("warn","Rejected worker %s: bootstrap closed",a:sub(1,8))return end;local d=ai;ai=ai+1
T[a]={id=d,state="idle",hostname=tostring(b.hostname or"worker-"..d),capabilities=
type(b.capabilities)=="table"and b.capabilities or{},last_seen=W.uptime(),pings_missed=0,current_task=
nil,last_ping_sent=nil}ab(a,{op=ao,accepted=true,worker_id=d})
R("info","Registered worker %d (%s) at %s",d,T[a].hostname,a:sub(1,8))return end
if c.current_task then
ab(a,{op=ao,accepted=false,reason="task in flight; reboot will be honored after timeout"})
R("warn","Refusing re-REGISTER from %s: task %s still in flight",a:sub(1,8),tostring(c.current_task))return end;c.state="idle"c.last_seen=W.uptime()c.pings_missed=0;c.current_task=nil;c.last_ping_sent=
nil
c.hostname=tostring(b.hostname or c.hostname)
if type(b.capabilities)=="table"then c.capabilities=b.capabilities end;ab(a,{op=ao,accepted=true,worker_id=c.id})
R("info","Re-registered worker %d at %s",c.id,a:sub(1,8))end
local function aA(b,a)local d=T[b]if not d then return end;d.last_seen=W.uptime()d.pings_missed=0
local c=tonumber(a.task_id)if not c then return end;local e=X[c]
if not e or e.worker_addr~=b then return end
if d.current_task==c then d.current_task=nil;d.state="idle"end
local f={task_id=c,status=tostring(a.status or"ok"),output=type(a.output)==Z and a.output or"",err=
type(a.err)==Z and a.err or nil}local g=e.on_result;X[c]=nil;if g then pcall(g,b,c,f)end;if ah then
pcall(ah,b,c,f)end end
local function aB(b,a)local c=T[b]if not c then return end;c.last_seen=W.uptime()c.pings_missed=0
R("debug","Worker %s task %s: progress=%s %s",b:sub(1,8),tostring(a.task_id),tostring(a.progress),tostring(
a.msg or""))end
local function aC(a,b)local c=T[a]if not c then return end;c.last_seen=W.uptime()c.pings_missed=0;if
c.state==av then c.state=c.current_task and"busy"or"idle"
R("info","Worker %s recovered",a:sub(1,8))end end;local aD={REGISTER=az,RESULT=aA,PROGRESS=aB,PONG=aC}
local function aE(d,d,a,c,d,b)if c~=V then return end;if type(b)~=
Z then return end;if#b>8192 then
R("debug","Oversized frame from %s (%d bytes) dropped",a:sub(1,8),#b)return end
local g,e=pcall(ar.decode,b)if not g or type(e)~="table"then return end
if e.magic~=as then return end
if aa then local i,k=e.nonce,e.mac;if type(i)~=Z or#i<8 or#i>64 then
R("warn","WRK frame from %s missing/bad nonce",a:sub(1,8))return end;if
type(k)~=Z or#k~=64 then
R("warn","WRK frame from %s missing/bad mac",a:sub(1,8))return end
local l,j=pcall(require,"kernel.crypto")if not l or not j or not j.hmac then
R("warn","crypto unavailable; dropping WRK frame from %s",a:sub(1,8))return end
local m=j.hmac(aa,ak(e))if not j.ctEquals(m,k)then
R("warn","WRK frame from %s failed MAC",a:sub(1,8))return end;if an[i]then
R("warn","WRK frame from %s replayed nonce",a:sub(1,8))return end;an[i]=true;aj[#aj+1]=i;if
#aj>aw then local n=table.remove(aj,1)an[n]=nil end end;local h=e.op;local f=aD[h]if not f then return end;f(a,e)end
local function aF()local a=W.uptime()local b=ac.TIMING.WORKER_PING
for d,c in pairs(T)do
if c.state=="idle"then if not
c.last_ping_sent or(a-c.last_ping_sent)>=b then
ab(d,{op="PING",time=math.floor(a)})c.last_ping_sent=a end;local e=a- (
c.last_seen or 0)if
e>= (2*b)and c.state~=av then c.state=av
c.pings_missed=(c.pings_missed or 0)+1
R("warn","Worker %s unresponsive (%.0fs silent)",d:sub(1,8),e)end end end end
local function aG()local a=W.uptime()
for c,b in pairs(X)do
if(a-b.sent_at)>b.timeout then
local d=T[b.worker_addr]
if d and d.current_task==c then d.current_task=nil;d.state="idle"end;local e=b.on_result;X[c]=nil
local f={task_id=c,status="timeout",output="",err=string.format("task timed out after %ds",b.timeout)}if e then pcall(e,b.worker_addr,c,f)end;if ah then
pcall(ah,b.worker_addr,c,f)end
R("warn","Task %d on %s timed out",c,b.worker_addr:sub(1,8))end end end;function U.init(a)Y=a.log;S=a.event;return true end
function U.setDomainId(a)if
type(a)~=au or a<0 then return false,"invalid domain_id"end
if aa==nil then return false,

"refusing to bind: cluster shared secret not set ".."(set 'shared_secret' (16+ bytes) in /etc/cluster.cfg)"end
if V and V~=ac.workerPort(a)then at(V)T={}X={}ai=1 end;al=a;V=ac.workerPort(a)ax()ay(V)if S and#ae==0 then
local b=S.on("modem_message",aE,ap)ae[#ae+1]=b end;if
S and not af and S.interval then
af=S.interval(ac.TIMING.WORKER_PING,aF,"cworker:ping")end
if
S and not ag and S.interval then ag=S.interval(2,aG,"cworker:timeout")end;R("info","Bound to domain %d on port %d",a,V)return true end
function U.setBootstrap(a)a=a or ac.TIMING.BOOTSTRAP_WINDOW
if
type(a)~=au or a<=0 then _=nil;R("info","Bootstrap window closed")return true end;_=W.uptime()+a
R("info","Bootstrap window open for %ds",a)return true end
function U.isBootstrapOpen()return _~=nil and W.uptime()<=_ end
function U.list()local a={}for c,b in pairs(T)do
a[#a+1]={addr=c,id=b.id,state=b.state,hostname=b.hostname,last_seen=b.last_seen,current_task=b.current_task}end;return a end;function U.domainId()return al end;function U.workerPort()return V end
function U.dispatch(b,c,a)if type(b)~=Z then return nil,
"addr required"end;if type(c)~=Z or c==""then
return nil,"code required"end;a=a or{}local d=T[b]
if not d then return nil,"unknown worker"end;if d.state~="idle"then
return nil,"worker not idle: "..tostring(d.state)end
local f=tonumber(a.timeout)or ac.TIMING.TASK_TIMEOUT;local e=am;am=am+1
local g,h=ab(b,{op="TASK",task_id=e,code=c,inputs=type(a.inputs)=="table"and a.inputs or{},timeout=f})if not g then return nil,h end;d.state="busy"d.current_task=e
X[e]={worker_addr=b,sent_at=W.uptime(),timeout=f,code=c,on_result=
type(a.on_result)=="function"and a.on_result or nil}return e end
function U.cancel(a)local c=X[a]if not c then return false,"unknown task"end
ab(c.worker_addr,{op="CANCEL",task_id=a})local b=T[c.worker_addr]if b and b.current_task==a then b.current_task=nil
b.state="idle"end;X[a]=nil;return true end
function U.onResult(a)if type(a)~="function"and a~=nil then
return false,"callback must be function or nil"end;ah=a;return true end
function U.forget(a)local b=T[a]if not b then return false,"unknown worker"end;if b.current_task then X[b.current_task]=
nil end;T[a]=nil
R("info","Forgot worker %d (%s)",b.id,a:sub(1,8))return true end
function U.stop()if V then at(V)end
if S then if S.off then for b,a in ipairs(ae)do
pcall(S.off,"modem_message",a)end end;ae={}
if
S.cancelTimer then if af then pcall(S.cancelTimer,af)af=nil end;if ag then
pcall(S.cancelTimer,ag)ag=nil end end end;T={}X={}V=nil;al=nil;_=nil end;return U