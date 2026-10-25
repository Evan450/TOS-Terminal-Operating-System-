local A={}local D=require("cluster.store")
local X=require("computer")
local function J(...)for a=1,select("#",...)do local c,b=pcall(require,(select(a,...)))if
c and b then return b end end end;local K=J("kernel.fs","filesystem")
local Y=J("kernel.event","event")local O=J("component")local P=require("kernel.serialize")
local H=
J("kernel.log","log")or{info=function()end,warn=function()end,error=function()end}local L="cluster.storaged"local F,E,G;local B,Q,R=nil,{},{}local S=false;local C,M,U,T=nil,{},nil,nil
local W={root="/var/cluster-store",capacity=0,write_port=2101,read_port=2100,sweep_interval=60,master=
nil,managers={}}
function A.loadConfig(a)local b={}for c,d in pairs(W)do b[c]=d end
a=a or"/etc/cluster-storage.cfg"
if K and K.exists and K.exists(a)then
local c=K.readFile and K.readFile(a)
if c and c~=""then local e,d=pcall(P.decode,c,{maxBytes=8192})if e and
type(d)=="table"then for f,g in pairs(d)do b[f]=g end else
H.error(L,"malformed cluster-storage.cfg; using defaults")end end end;B=b;return b end;function A.config()return B end
function A.writerFor(a)
if not B then return nil,"not_configured"end
if B.master and a==B.master then return{role="master"}end;local b=B.managers and B.managers[a]if b then return
{role="manager",domain_id=tonumber(b),job_assignee={}}end;return nil,
"unknown_writer"end;local function N(a,b,c)if not(F and E)then return end
F.send(a,E.makePacket(b,c,{to=a}))end;local function I(a,b,c)
N(a,E.TYPE.STORE_ERROR,{key=b,reason=c})end
local function V(a,b)local c,d=A.writerFor(a)if not c then return nil,
d or"unknown_writer"end;local e,f=G.canWrite(c,b)if not e then return nil,f or
"namespace_denied"end;return c end
function A._onPut(b,a)local c=b.payload or{}if type(c.key)~="string"then return
I(a,nil,"invalid_key: missing")end;local f,e=V(a,c.key)if
not f then
H.warn(L,"PUT denied for "..
tostring(a):sub(1,8)..": "..tostring(e))return I(a,c.key,e)end
local d,g=D.put(c.key,
c.data or"",{ttl=tonumber(c.ttl),overwrite=c.overwrite~=false})if not d then return I(a,c.key,g)end
N(a,E.TYPE.STORE_PUT_ACK,{key=d.key,lease_id=d.lease_id,expires_at=d.expires_at,size_bytes=d.size_bytes})end
function A._onExtend(b,a)local c=b.payload or{}local e,f=V(a,c.key or"")if not e then
return I(a,c.key,f)end
local d,g=D.extend(c.key,c.lease_id,tonumber(c.extend_by))if not d then return I(a,c.key,g)end
N(a,E.TYPE.STORE_PUT_ACK,{key=d.key,lease_id=c.lease_id,expires_at=d.expires_at})end
function A._onRelease(b,a)local c=b.payload or{}local d,e=V(a,c.key or"")if not d then
return I(a,c.key,e)end;local f,g=D.release(c.key,c.lease_id)if not f then return
I(a,c.key,g)end
N(a,E.TYPE.STORE_PUT_ACK,{key=c.key,released=true})end
function A._onList(a,b)local c=a.payload or{}
local d,e=D.list(c.prefix or"",tonumber(c.limit)or 128)
N(b,E.TYPE.STORE_LIST_RES,{prefix=c.prefix,keys=d,truncated=e})end
function A._onPubMessage(b,a,c)if type(a)~="string"or#a>8192 then return end
local f,d=pcall(P.decode,a,{maxBytes=8192})if not f or type(d)~="table"then return end
local g=G.validatePubRequest(d)if not g then return end;local function e(h)
if U then U(c,b,B.read_port,P.encode(h))end end
if d.op=="GET"then local h,j=D.get(d.key)
if not h then return
e({magic=G.PUB_MAGIC,op="RES",key=d.key,req_id=d.req_id,err=j})end;local i=6144
if#h<=i then
e({magic=G.PUB_MAGIC,op="RES",key=d.key,req_id=d.req_id,data=h,chunk=1,total=1})else local k=math.ceil(#h/i)for l=1,k do
e({magic=G.PUB_MAGIC,op="RES",key=d.key,req_id=d.req_id,data=h:sub((l-1)*i+1,l*i),chunk=l,total=k})end end elseif d.op=="LIST"then local i=D.list(d.prefix or"",128)local h={}for j,k in ipairs(i)do
h[j]=k.key end
e({magic=G.PUB_MAGIC,op="LIST_RES",keys=h,req_id=d.req_id})end end
local function Z(a)if a.modems then return a.modems end;local b={}if O and O.list then
for c in O.list("modem")do
local e,d=pcall(O.proxy,c)if e and d then b[#b+1]={address=c,proxy=d}end end end;return b end
function A.start(a)a=a or{}if S then return true end
F=a.net or J("kernel.net")G=a.cproto or require("cluster.protocol")
E=

a.protocol or(F and F.getProtocol and F.getProtocol())or J("kernel.net.protocol")
if not(F and E and G)then return false,"no_network"end;A.loadConfig(a.config_path)
local d,e=D.init({root=B.root,capacity=B.capacity,fs=K,computer=X,serialize=P,log=H})if not d then return false,e end;C=a.event or Y;M=Z(a)
U=a.rawSend or function(g,h,i,j)
for l,k in ipairs(M)do if
k.address==g and k.proxy and k.proxy.send then
return pcall(k.proxy.send,h,i,j)end end end;local c=0
for h,g in ipairs(M)do
local i=g.proxy and pcall(g.proxy.open,B.write_port)
local j=g.proxy and pcall(g.proxy.open,B.read_port)
if i and j then c=c+1 else
H.warn(L,"modem "..
tostring(g.address):sub(1,8).." could not open ports "..

tostring(B.write_port).."/"..
tostring(B.read_port).." (a Tier-1 wireless card holds only one)")end end;if c==0 then
H.error(L,"no modem has the storage ports open: nothing can reach this node")end;if C and C.on then
T=C.on("modem_message",function(k,g,h,i,k,j)if
i==B.read_port then A._onPubMessage(h,j,g)end end,"cluster-storaged")end
local b=E.TYPE
local f={[b.STORE_PUT]=A._onPut,[b.STORE_LEASE_EXTEND]=A._onExtend,[b.STORE_RELEASE]=A._onRelease,[b.STORE_LIST]=A._onList}
for g,h in pairs(f)do R[#R+1]={kind=g,id=F.on(g,h)}end
if C and C.interval then
Q[#Q+1]=C.interval(B.sweep_interval or 60,function()local g=D.sweep()if g>0 then
H.info(L,
"swept "..g.." expired key(s)")end end)end;S=true
H.info(L,string.format("storage node up: root=%s capacity=%d",tostring(B.root),D.capacity()))return true end
function A.stop()for b,a in ipairs(R)do pcall(F.off,a.kind,a.id)end
R={}
for b,a in ipairs(Q)do if C and C.cancel then pcall(C.cancel,a)elseif C and C.cancelTimer then
pcall(C.cancelTimer,a)end end;Q={}
if T and C and C.off then pcall(C.off,"modem_message",T)end;T=nil;if B then
for b,a in ipairs(M)do if a.proxy then pcall(a.proxy.close,B.write_port)
pcall(a.proxy.close,B.read_port)end end end;M={}S=false
D.saveIndex()return true end;function A.isRunning()return S end;function A.stats()return D.stats()end;A._internal={DEFAULTS=W,setConfig=function(a)
B=a end}return A