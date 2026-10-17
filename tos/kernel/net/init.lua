local X="string"local ag=require("component")
local S=require("computer")local N={}local Q=nil;local P=nil;local R=nil;local ar=8;local an=256
local function ao(a,d,b,c)if
type(b)~=X or type(c)~="number"then return true end;local e=a[d]
if not e then
a.__order=a.__order or{}if#a.__order>=an then local f=table.remove(a.__order,1)
if f~=nil then a[f]=nil end end
a.__order[#a.__order+1]=d;a[d]={epoch=b,maxSeq=c,retired={},retiredOrder={}}return true end;if e.epoch==b then
if c<=e.maxSeq then return false,"stale or replayed sequence"end;e.maxSeq=c;return true end
if
e.retired[b]then return false,"replayed packet from a retired epoch"end;e.retired[e.epoch]=true
e.retiredOrder[#e.retiredOrder+1]=e.epoch;if#e.retiredOrder>ar then
local f=table.remove(e.retiredOrder,1)e.retired[f]=nil end;e.epoch=b
e.maxSeq=c;return true end;N._seqCheck=ao;local T=nil;local _=nil;local ab=nil;local U={}local V=42;local Y=nil
local ah={[14]="Ethernet-over-OC",[148]="the GUI service",[4096]="MultICE / Minitel",[4378]="GERTi",[4379]="GERTi",[4662]="short messages",[9100]="the network print service",[9900]="Zorya BIOS LAN boot"}N.REGISTERED_PORTS=ah;function N.portOwner(a)return ah[a]end;local ae=true;local ac="tos"
local ak=false;local W={}local O=nil;local aa=nil;local af=nil;local al;local ad
function N.init(a)O=a.log;aa=a.config;af=a.event
Q=require("kernel.net.protocol")P=require("kernel.net.trust")
R=require("kernel.crypto")P.init({fs=a.fs,crypto=R,log=O,config=aa})
N._trustToken=
P.getBootstrapToken and P.getBootstrapToken()or nil
if aa then V=aa.get("listenPort")or 42
local g=aa.get("broadcastPort")
Y=(type(g)=="number"and g~=V)and g or nil;ae=aa.get("encryptComms")~=false;ac=aa.get("hostname")or
"tos"end
for h,g in ipairs({V,Y})do local i=g and ah[g]
if i and O then
O.warn("net",string.format(
"Port %d is registered to %s: TOS traffic will share ".."that network. TOS's own port is 42 (listenPort in /etc/tos.cfg).",g,i))end end;U={}
for g in ag.list("modem")do local i,h=pcall(ag.proxy,g)
if i and h then
pcall(h.open,V)if Y then pcall(h.open,Y)end;local j=false
pcall(function()j=h.isWireless()end)U[#U+1]={addr=g,proxy=h,wireless=j}if O then
O.info("net",string.format("Modem %d: %s [%s]",#U,
j and"wireless"or"wired",g:sub(1,8).."..."))end end end
if#U>0 then T=U[1].proxy;ab=U[1].addr;if O and#U>1 then
O.info("net",#U.." NICs active (multi-modem)")end
if O then
local g=
Y and("ports "..V..", "..Y)or("port "..V.." (single-port mode)")O.info("net","Listening on "..g)end end
for g in ag.list("tunnel")do local i,h=pcall(ag.proxy,g)if i and h then _=h;if O then
O.info("net","Linked card detected")end end;break end
if not T and not _ then if O then
O.warn("net","No network hardware detected")end;return false end;if af then
af.on("modem_message",function(k,l,g,h,i,j)N.handleIncoming(g,h,i,j)N.meshTick()end,"net")end;ak=true
local d,b=pcall(require,"kernel.net.chatpair")
if d and b and b.init then
b.init({crypto=R,protocol=Q,trust=P,log=O})N._chatpair=b
N.on(Q.TYPE.CHAT_PAIR_INIT,function(g,h)b.onPairInit(g,h)end)
if O then O.info("net","Chat-pair handler registered")end elseif O then
O.warn("net","chatpair module unavailable: "..tostring(b))end
local function e(g)local i,h="/var/lib/mesh","/var/lib/mesh/state.dat"
local j=require("kernel.serialize")
return
{load=function()if not(g and g.exists and g.exists(h))then
return nil end;return j.loadFile(g,h)end,save=function(k)if
not g then return end
if not g.exists(i)then g.makeDirectory(i)end;j.saveFile(g,h,k)end}end;local f,c=pcall(require,"kernel.net.meshctl")
if f and c then
c.init({crypto=R,serialize=require("kernel.serialize"),log=O,clock=function()return
S.uptime()end})
N._meshctl=c.new({myAddr=ab,clock=function()return S.uptime()end,freeMemory=S.freeMemory,store=e(a and a.fs or
(_G._TOS and _G._TOS.fs)),broadcast=function(h)local i=
(h.kind=="ack")and Q.TYPE.MESH_ACK or Q.TYPE.MESH
N.broadcast(Q.makePacket(i,h))end,secretFor=function(h)
return P._internalGetSecret and
P._internalGetSecret(h,N._trustToken)or nil end,log=O})
local function g(h)if type(h.payload)=="table"then
N._meshctl:onPacket(h.payload)end end;N.on(Q.TYPE.MESH,g)N.on(Q.TYPE.MESH_ACK,g)if O then
O.info("net","Mesh transport controller registered")end elseif O then
O.warn("net","mesh transport unavailable: "..tostring(c))end;if O then
O.info("net","Network initialized (zero-trust mode)")
O.info("net","Encryption: ".. (ae and"enabled"or"disabled"))end;return true end;function N.getChatPair()return N._chatpair end;function N.meshAvailable()
return N._meshctl~=nil end;function N.meshSend(a)if not N._meshctl then
return nil,"mesh not available (no network?)"end
return N._meshctl:send(a or{})end;function N.meshOn(a,b)if
not N._meshctl then return false,"mesh not available"end
N._meshctl:on(a,b)return true end
function N.meshOff(a)if
N._meshctl then N._meshctl:off(a)end end;function N.meshHasHandler(a)
return N._meshctl~=nil and N._meshctl:hasHandler(a)end
function N.meshPending()return N._meshctl and
N._meshctl:pending()or 0 end
function N.meshTick()if not N._meshctl then return end;local a=S.uptime()if a-
(N._lastMeshTick or 0)>=5 then N._lastMeshTick=a
N._meshctl:tick(a)end end;function N.isAvailable()return T~=nil or _~=nil end
function N.getAddress()return ab end;function N.getHostname()return ac end
function N.setHostname(a)if
type(a)~=X or a==""or#a>32 or a:find("%c")then
return false,"hostname must be 1-32 printable characters"end;ac=a;return true end;function N.modemCount()return#U end
local ap={ping=true,pong=true,hello=true,hello_ack=true,challenge=true,chall_res=true,deny=true,ch_pair_init=true,ch_pair_conf=true,cl_pair_init=true,cl_pair_conf=true}local as={mesh=true,mesh_ack=true}
function N.send(b,a,c)
if not T and not _ then return false,"No modem"end;c=c or V;a.from=ab;a.to=b;local g=P.getLevel(b)local h=ap[a.type]
if ae and g>=
P.LEVEL.TRUSTED and not h then
local i=P._internalGetSecret(b,N._trustToken)
if i and a.payload then local l=Q.serialize(a.payload)local j,k=R.encrypt(l,i)
a.payload=j;a.enc=k;N._bootEpoch=N._bootEpoch or R.salt(12)
N._sendSeq=N._sendSeq or{}N._sendSeq[b]=(N._sendSeq[b]or 0)+1
a.epoch=N._bootEpoch;a.seq=N._sendSeq[b]a.nonce=R.salt(16)
a.mac=R.hmac(i,table.concat({a.type or"",
a.to or"",k or"",a.epoch,tostring(a.seq),a.nonce,j},"\0"))elseif a.payload and not i then
if O then
O.warn("net",string.format("Refusing plaintext send to TRUSTED peer %s (%s): no shared secret; "..
"run 'net trust gen %s' as admin to provision one",b:sub(1,8),a.type or"?",b:sub(1,8)))end;return false,"TRUSTED peer has no shared secret; refusing plaintext send"end end;local d=Q.serialize(a)
if#d>Q.MAX_SIZE then return false,"Packet too large"end;local e,f
if T then e,f=pcall(T.send,b,c,d)else e,f=pcall(_.send,d)end
if not e then return false,"Send failed: "..tostring(f)end;return true end
function N.broadcast(b,a)if not T and not _ then return false,"No modem"end
a=a or Y or V;b.from=ab;local d=Q.serialize(b)local c=false;for f,e in ipairs(U)do
local g=pcall(e.proxy.broadcast,a,d)c=c or g end;if _ then local e=pcall(_.send,d)
c=c or e end
if not c then return false,"Broadcast failed on all NICs"end;return true end
function N.handleIncoming(a,d,b,c)if not ak then return end;local e,i=Q.deserialize(c)if not e then return end
local h,j=Q.validate(e)if not h then return end;P.seen(a)e.from=a;e._distance=b;local f=P.getLevel(a)
if
f==P.LEVEL.BLOCKED then if O then
O.debug("net","Dropped (BLOCKED): "..a:sub(1,8))end;return end
if not P.isAllowed(a,e.type)then
if e.type==Q.TYPE.TRUST_REQ then
local k=ad(
type(e.payload)=="table"and e.payload.hostname or nil)P.addPendingRequest(a,k)al(Q.TYPE.TRUST_REQ,e,a)
return end;if f>=P.LEVEL.KNOWN then
if
e.type~=Q.TYPE.DENY and e.type~=Q.TYPE.ERROR then local k=Q.deny("Insufficient trust level")N.send(a,k)end end;if O then
O.debug("net",string.format("Denied %s from %s (level: %s)",e.type,a:sub(1,8),P.levelName(f)))end;return end
if e.enc and f<P.LEVEL.TRUSTED then if O then
O.warn("net",string.format("Stripping enc flag on packet from non-TRUSTED peer %s (%s)",a:sub(1,8),
e.type or"?"))end;e.enc=nil;e.payload=
nil;return end;local g=false
if
e.enc and e.enc~=false and f>=P.LEVEL.TRUSTED then local l=P._internalGetSecret(a,N._trustToken)local k=nil;if
e.enc=="xor"and R.hasHardware and R.hasHardware()then
k="refusing XOR packet on AES-capable receiver (downgrade)"end
if not k then local m=e.nonce
local n=e.mac
if type(m)~=X or#m<8 or#m>64 then k="missing or malformed nonce"elseif
type(n)~=X or#n~=64 then k="missing or malformed MAC"elseif not l then k="no shared secret"else
local o=R.hmac(l,table.concat({
e.type or"",e.to or"",e.enc or"",tostring(e.epoch or""),tostring(e.seq or""),m,(
e.payload or"")},"\0"))if not R.ctEquals(o,n)then k="MAC mismatch"end end end;if not k then N._recvSeq=N._recvSeq or{}
local m,n=ao(N._recvSeq,a,e.epoch,tonumber(e.seq))if not m then k=n end end
if
not k then N._seenNonces=N._seenNonces or{}local m=N._seenNonces[a]
if not m then N._seenNonces.__order=
N._seenNonces.__order or{}local n=N._seenNonces.__order;if
#n>=an then local o=table.remove(n,1)
if o~=nil then N._seenNonces[o]=nil end end;n[#n+1]=a
m={order={},set={}}N._seenNonces[a]=m end
if m.set[e.nonce]then k="replayed nonce"else m.set[e.nonce]=true
m.order[#m.order+1]=e.nonce;local n=512;if#m.order>n then local o=table.remove(m.order,1)
m.set[o]=nil end end end
if not k then
if type(e.payload)~=X then k="enc flag set but payload is not ciphertext"else
local m=R.decrypt(e.payload,l,e.enc)
if not m then k="decryption failed (tampered or wrong key)"else local n=Q.deserialize(m)
if not
n then k="decrypted payload failed to deserialize"else e.payload=n;e.enc=false;g=true end end end end
if k then if O then
O.warn("net",string.format("Dropped enc packet from %s (%s): %s",a:sub(1,8),e.type or"?",k))end;return end end
if
not g and ae and f>=P.LEVEL.TRUSTED and not ap[e.type]and not as[e.type]then
local k=P._internalGetSecret(a,N._trustToken)
if k and k~=""then
if O then
O.warn("net",string.format("Dropped unsealed %s from TRUSTED peer %s: we share a secret, so it "..
"must arrive encrypted (a peer with encryptComms off, or a moved modem)",tostring(e.type),a:sub(1,8)))end;return end end
if e.type==Q.TYPE.PING then local k=Q.pong()
if aa and f>=P.LEVEL.KNOWN then k.payload=
k.payload or{}k.payload.device=aa.deviceType()end;N.send(a,k)N._recordPeer(a,e.payload)return end
if e.type==Q.TYPE.PONG then N._recordPeer(a,e.payload)end
if e.type==Q.TYPE.HELLO and f>=P.LEVEL.KNOWN then
local k=P.getPeer(a)if k and type(e.payload)=="table"then
k.hostname=ad(e.payload.hostname)end
local l=Q.helloAck(ac,_G._TOS.version)N.send(a,l)end
if e.type==Q.TYPE.HELLO_ACK and f>=P.LEVEL.KNOWN then
local k=P.getPeer(a)if k and type(e.payload)=="table"then
k.hostname=ad(e.payload.hostname)end end
if e.type==Q.TYPE.CHALLENGE then if f<P.LEVEL.TRUSTED then return end;N._challengeRate=
N._challengeRate or{}local n=S.uptime()
local q=N._challengeRate[a]or 0
if n-q<1.0 then if O then
O.warn("net","CHALLENGE throttled from "..a:sub(1,8))end;return end;N._challengeRate[a]=n
local m=P._internalGetSecret and
P._internalGetSecret(a,N._trustToken)or nil;if not m or m==""then return end
local k=e.payload and e.payload.nonce
if type(k)~=X or#k<8 or#k>64 then if O then
O.warn("net","Bad challenge nonce from "..a:sub(1,8))end;return end;local o=R.salt(16)local r,p=pcall(R.hmac,m,k.."|"..o)if
not r or not p then return end;local l=Q.challengeResponse(k,p)
l.payload=l.payload or{}l.payload.serverNonce=o;N.send(a,l)return end;al(e.type,e,a)end;local ai=nil
local function at(a)
if ai==nil then if not Q then return end
ai={[Q.TYPE.FILE_REQ]="kernel.net.transfer",[Q.TYPE.REMOTE_EXEC]="kernel.net.remote",[Q.TYPE.NETFS_REQ]="kernel.netfs"}end;local b=ai[a]if not b then return end;ai[a]=nil;local c,d=pcall(require,b)if not c and O then
O.warn("net",
"Lazy handler load failed ("..b.."): "..tostring(d))end end
al=function(a,b,c)at(a)
if W[a]then
for e,d in ipairs(W[a])do local f,g=pcall(d.cb,b,c)if not f and O then
O.warn("net","Listener error for "..
tostring(a)..": "..tostring(g))end end end
if W["*"]then
for e,d in ipairs(W["*"])do local f,g=pcall(d.cb,b,c)if not f and O then
O.warn("net","Catch-all listener error: "..
tostring(g))end end end end;local aq={}
local au={fileshare="kernel.net.transfer",rshd="kernel.net.remote",netfsd="kernel.netfs"}
function N.setServiceArm(a,b)aq[a]=b and true or false;local c=au[a]
if c and package and
package.loaded and package.loaded[c]then
local d=package.loaded[c]local e=d and(d.arm or d.setEnabled)if e then
e(b and true or false)end end end;function N.getServiceArm(a)return aq[a]==true end;local am=1
function N.on(a,b)if not W[a]then
W[a]={}end;local c=am;am=am+1;W[a][#W[a]+1]={cb=b,id=c}return c end
function N.off(a,b)if not W[a]then return false end;for c,d in ipairs(W[a])do if d.id==b then
table.remove(W[a],c)return true end end;return
false end
function N.onceFrom(a,b,c)local d=false;return
N.on(a,function(f,e)if d or e~=b then return end;d=true;c(f,e)end)end
function N.offAll(a)if type(a)~="table"then return end;for c,b in ipairs(a)do
if
type(b)=="table"and b.type and b.id then N.off(b.type,b.id)end end end
local function av()local a=package.loaded["kernel.process"]
if a and type(a.inProcess)==
"function"then return a.inProcess()end
return
(coroutine.isyieldable and coroutine.isyieldable())and true or false end
function N.waitFor(a,b)local c=S.uptime()+ (b or 10)
while not a()do if S.uptime()>=c then
return false end
if av()then coroutine.yield()else
local d=
(af and af.pull)and af or package.loaded["kernel.event"]if type(d)=="table"and type(d.pull)=="function"then
d.pull(0.5)else S.pullSignal(0.5)end end end;return true end;local aj={}local aw=60
local function ax(c,d,R)
if R and R.ctEquals then return R.ctEquals(c,d)end;if type(c)~=X or type(d)~=X then return false end
local a,b=#c,#d;local f=a>b and a or b;local e=a~b
for g=1,f do
local h=g<=a and c:byte(g)or 0;local i=g<=b and d:byte(g)or 0;e=e| (h~i)end;return e==0 end
function N.verifyPeer(a,b,c)if not Q then return false,"protocol unavailable"end;if
not a or a==""then return false,"no address"end;if not P then
return false,"trust manager unavailable"end;if not c then local m=aj[a]
if m and S.uptime()<m then return true end end;if
P.getLevel(a)<P.LEVEL.TRUSTED then return false,"peer not trusted"end
local f=P._internalGetSecret and
P._internalGetSecret(a,N._trustToken)or nil
if not f or f==""then return false,"no shared secret with peer"end;local d
if R.salt then d=R.salt(16)else local m={}for n=1,16 do
m[n]=string.char(math.random(0,255))end;d=table.concat(m)end;local g,h,e=false,nil,nil
local i=N.onceFrom(Q.TYPE.CHALLENGE_RES,a,function(m)
if
m.payload and m.payload.nonce==d then h=m.payload.proof;e=m.payload.serverNonce;g=true end end)local k,l=N.send(a,Q.challenge(d))
if not k then
N.off(Q.TYPE.CHALLENGE_RES,i)return false,"send failed: "..tostring(l)end;N.waitFor(function()return g end,b or 5)
N.off(Q.TYPE.CHALLENGE_RES,i)if not g then return false,"challenge timeout"end
if
type(e)~=X or#e<8 or#e>64 then return false,"bad server nonce"end;local j
do local n=d.."|"..e;local o,m=pcall(R.hmac,f,n)if not o or not m then
return false,"hmac failed"end;j=m end
if not ax(h,j,R)then if O then
O.warn("net","Challenge proof mismatch from "..a:sub(1,8))end;return false,"bad proof"end;aj[a]=S.uptime()+aw;return true end
function N.invalidateVerification(a)if a then aj[a]=nil else aj={}end end
function N.discover()local a=Q.ping()return N.broadcast(a,Y)end
function N.hello(a)local b=P.getLevel(a)if b<P.LEVEL.KNOWN then
return false,"Peer must be KNOWN to exchange hellos"end
local c=Q.hello(ac,_G._TOS.version)return N.send(a,c)end
function N.sendMessage(a,b)local e=P.getLevel(a)if e<P.LEVEL.TRUSTED then
return false,"Peer must be TRUSTED to send messages"end;local c=Q.message(b,ae)
local d,f=N.send(a,c)return d,f,d and c.seq or nil end
function N.requestTrust(a)local b=Q.trustRequest(ac)return N.send(a,b)end;function N.getTrust()return P end;local Z={}local ay=64
function ad(a)if type(a)~=X then return nil end
a=a:gsub("%c",""):sub(1,32)if a==""then return nil end;return a end
function N._recordPeer(a,b)if type(a)~=X then return end;local e=S.uptime()local f=
P and P.getLevel(a)or 0;local c=nil;local d=nil;if type(b)=="table"then
c=ad(b.hostname)d=ad(b.device)end;if P then local g=P.getPeer(a)if g then c=c or
ad(g.hostname)end end
if Z[a]==
nil then local g,h,i=0,nil,nil
for k,j in pairs(Z)do g=g+1
local l=(
((j.trust or 0)>0)and 1e12 or 0)+ (j.lastSeen or 0)if not i or l<i then h,i=k,l end end;if g>=ay and h then Z[h]=nil end end;Z[a]={addr=a,lastSeen=e,hostname=c,device=d,trust=f}end
function N.peers()local a={}for c,b in pairs(Z)do a[#a+1]=b end
table.sort(a,function(c,d)return
(c.hostname or"")< (d.hostname or"")end)return a end
function N.findPeer(a)if type(a)~=X or a==""then return nil end
if Z[a]then return Z[a]end
for c,b in pairs(Z)do if b.hostname and b.hostname==a then return b end end
for b,c in pairs(Z)do if b:sub(1,#a)==a then return c end end;return nil end
function N.scan(a)a=a or 3;local c={}
local d=N.on(Q.TYPE.PONG,function(f,e)N._recordPeer(e,f.payload)
c[e]=Z[e]end)N.discover()
N.waitFor(function()return false end,a)N.off(Q.TYPE.PONG,d)local b={}
for f,e in pairs(c)do b[#b+1]=e end;return b end;function N.getProtocol()return Q end
function N.status()local a=P.stats()
return
{available=N.isAvailable(),address=ab and(
ab:sub(1,8).."...")or"none",fullAddress=ab,hostname=ac,listenPort=V,portOwner=ah[V],encrypted=ae,hasModem=T~=nil,hasTunnel=_~=nil,peers=a}end
function N.shutdown()ak=false;if T then
pcall(function()T.close(V)if Y then T.close(Y)end end)end;if O then
O.info("net","Network shut down")end end;return N