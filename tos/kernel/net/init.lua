local au,aa="No modem","string"local ai=require("component")
local U=require("computer")local P={}local S=nil;local Q=nil;local T=nil;local av=8;local ap=256
local function aq(a,d,b,c)if
type(b)~=aa or type(c)~="number"then return true end;local e=a[d]
if not e then
a.__order=a.__order or{}if#a.__order>=ap then local f=table.remove(a.__order,1)
if f~=nil then a[f]=nil end end
a.__order[#a.__order+1]=d;a[d]={epoch=b,maxSeq=c,retired={},retiredOrder={}}return true end;if e.epoch==b then
if c<=e.maxSeq then return false,"stale or replayed sequence"end;e.maxSeq=c;return true end
if
e.retired[b]then return false,"replayed packet from a retired epoch"end;e.retired[e.epoch]=true
e.retiredOrder[#e.retiredOrder+1]=e.epoch;if#e.retiredOrder>av then
local f=table.remove(e.retiredOrder,1)e.retired[f]=nil end;e.epoch=b
e.maxSeq=c;return true end;P._seqCheck=aq;local V=nil;local W=nil;local ab=nil;local X={}local Y=42;local Z=nil
local aj={[14]="Ethernet-over-OC",[148]="the GUI service",[4096]="MultICE / Minitel",[4378]="GERTi",[4379]="GERTi",[4662]="short messages",[9100]="the network print service",[9900]="Zorya BIOS LAN boot"}P.REGISTERED_PORTS=aj;function P.portOwner(a)return aj[a]end;local ag=true;local ae="tos"
local am=false;local _={}local R=nil;local ad=nil;local ah=nil;local an;local af
function P.init(a)R=a.log;ad=a.config;ah=a.event
S=require("kernel.net.protocol")Q=require("kernel.net.trust")
T=require("kernel.crypto")Q.init({fs=a.fs,crypto=T,log=R,config=ad})
P._trustToken=
Q.getBootstrapToken and Q.getBootstrapToken()or nil;if Q.setHelloSender then
Q.setHelloSender(function(g)return P.hello(g)end)end
if ad then
Y=ad.get("listenPort")or 42;local g=ad.get("broadcastPort")Z=
(type(g)=="number"and g~=Y)and g or nil;ag=
ad.get("encryptComms")~=false
ae=ad.get("hostname")or"tos"end
for h,g in ipairs({Y,Z})do local i=g and aj[g]
if i and R then
R.warn("net",string.format(
"Port %d is registered to %s: TOS traffic will share ".."that network. TOS's own port is 42 (listenPort in /etc/tos.cfg).",g,i))end end;X={}
for g in ai.list("modem")do local i,h=pcall(ai.proxy,g)
if i and h then
pcall(h.open,Y)if Z then pcall(h.open,Z)end;local j=false
pcall(function()j=h.isWireless()end)X[#X+1]={addr=g,proxy=h,wireless=j}if R then
R.info("net",string.format("Modem %d: %s [%s]",#X,
j and"wireless"or"wired",g:sub(1,8).."..."))end end end
if#X>0 then V=X[1].proxy;ab=X[1].addr;if R and#X>1 then
R.info("net",#X.." NICs active (multi-modem)")end
if R then
local g=
Z and("ports "..Y..", "..Z)or("port "..Y.." (single-port mode)")R.info("net","Listening on "..g)end end
for g in ai.list("tunnel")do local i,h=pcall(ai.proxy,g)if i and h then W=h;if R then
R.info("net","Linked card detected")end end;break end
if not V and not W then if R then
R.warn("net","No network hardware detected")end;return false end;if ah then
ah.on("modem_message",function(k,l,g,h,i,j)P.handleIncoming(g,h,i,j)P.meshTick()end,"net")end;am=true
local d,b=pcall(require,"kernel.net.chatpair")
if d and b and b.init then
b.init({crypto=T,protocol=S,trust=Q,log=R})P._chatpair=b
P.on(S.TYPE.CHAT_PAIR_INIT,function(g,h)b.onPairInit(g,h)end)
if R then R.info("net","Chat-pair handler registered")end elseif R then
R.warn("net","chatpair module unavailable: "..tostring(b))end
local function e(g)local i,h="/var/lib/mesh","/var/lib/mesh/state.dat"
local j=require("kernel.serialize")
return
{load=function()if not(g and g.exists and g.exists(h))then
return nil end;return j.loadFile(g,h)end,save=function(k)if
not g then return end
if not g.exists(i)then g.makeDirectory(i)end;j.saveFile(g,h,k)end}end;local f,c=pcall(require,"kernel.net.meshctl")
if f and c then
c.init({crypto=T,serialize=require("kernel.serialize"),log=R,clock=function()return
U.uptime()end})
P._meshctl=c.new({myAddr=ab,clock=function()return U.uptime()end,freeMemory=U.freeMemory,store=e(a and a.fs or
(_G._TOS and _G._TOS.fs)),broadcast=function(h)local k=
(h.kind=="ack")and S.TYPE.MESH_ACK or S.TYPE.MESH
local j=S.makePacket(k,h)local i=h.to
if i and i~="*"then local l=P._meshctl:routeFor(i)
if l and l~=ab then
local m=P.sendToAddress(l,j)if m then return end;P._meshctl:invalidateRoute(i)end end;P.broadcast(j)end,secretFor=function(h)return

Q._internalGetSecret and Q._internalGetSecret(h,P._trustToken)or nil end,log=R})
local function g(h)if type(h.payload)=="table"then
P._meshctl:onPacket(h.payload)end end;P.on(S.TYPE.MESH,g)P.on(S.TYPE.MESH_ACK,g)if R then
R.info("net","Mesh transport controller registered")end elseif R then
R.warn("net","mesh transport unavailable: "..tostring(c))end;if R then
R.info("net","Network initialized (zero-trust mode)")
R.info("net","Encryption: ".. (ag and"enabled"or"disabled"))end;return true end;function P.getChatPair()return P._chatpair end;function P.meshAvailable()
return P._meshctl~=nil end;function P.meshSend(a)if not P._meshctl then
return nil,"mesh not available (no network?)"end
return P._meshctl:send(a or{})end;function P.meshOn(a,b)if
not P._meshctl then return false,"mesh not available"end
P._meshctl:on(a,b)return true end
function P.meshOff(a)if
P._meshctl then P._meshctl:off(a)end end;function P.meshHasHandler(a)
return P._meshctl~=nil and P._meshctl:hasHandler(a)end
function P.meshPending()return P._meshctl and
P._meshctl:pending()or 0 end
function P.meshTick()if not P._meshctl then return end;local a=U.uptime()if a-
(P._lastMeshTick or 0)>=5 then P._lastMeshTick=a
P._meshctl:tick(a)end end;function P.isAvailable()return V~=nil or W~=nil end
function P.getAddress()return ab end;function P.getHostname()return ae end
function P.setHostname(a)if
type(a)~=aa or a==""or#a>32 or a:find("%c")then
return false,"hostname must be 1-32 printable characters"end;ae=a;return true end;function P.modemCount()return#X end
local ar={ping=true,pong=true,hello=true,hello_ack=true,challenge=true,chall_res=true,deny=true,ch_pair_init=true,ch_pair_conf=true,cl_pair_init=true,cl_pair_conf=true}local aw={mesh=true,mesh_ack=true}
local function as(...)local a={"tosmac2"}
for b=1,select("#",...)do local c=tostring(
(select(b,...))or"")a[#a+1]=#c..":"..c end;return table.concat(a)end
function P.send(b,a,c)if not V and not W then return false,au end;c=c or Y;a.from=ab;a.to=b
local g=Q.getLevel(b)local h=ar[a.type]
if ag and g>=Q.LEVEL.TRUSTED and not h then
local i=Q._internalGetSecret(b,P._trustToken)
if i and a.payload then local l=S.serialize(a.payload)local j,k=T.encrypt(l,i)
a.payload=j;a.enc=k;P._bootEpoch=P._bootEpoch or T.salt(12)
P._sendSeq=P._sendSeq or{}P._sendSeq[b]=(P._sendSeq[b]or 0)+1
a.epoch=P._bootEpoch;a.seq=P._sendSeq[b]a.nonce=T.salt(16)a.macv=2
a.mac=T.hmac(i,as(a.type,a.to,k,a.epoch,a.seq,a.nonce,j))elseif a.payload and not i then
if R then
R.warn("net",string.format("Refusing plaintext send to TRUSTED peer %s (%s): no shared secret; "..
"run 'net trust gen %s' as admin to provision one",b:sub(1,8),a.type or"?",b:sub(1,8)))end;P._helloAsked=P._helloAsked or{}local j=U.uptime()if j- (P._helloAsked[b]or-
math.huge)>=30 then
P._helloAsked[b]=j;pcall(P.hello,b)end;return false,
"TRUSTED peer has no shared secret; refusing plaintext send"end end;local d=S.serialize(a)
if#d>S.MAX_SIZE then return false,"Packet too large"end;local e,f
if V then e,f=pcall(V.send,b,c,d)else e,f=pcall(W.send,d)end
if not e then return false,"Send failed: "..tostring(f)end;return true end
function P.broadcast(b,a)if not V and not W then return false,au end;a=a or Z or Y
b.from=ab;local d=S.serialize(b)local c=false;for f,e in ipairs(X)do
local g=pcall(e.proxy.broadcast,a,d)c=c or g end;if W then local e=pcall(W.send,d)
c=c or e end
if not c then return false,"Broadcast failed on all NICs"end;return true end
function P.sendToAddress(c,b,a)if not V and not W then return false,au end;a=a or Z or Y
b.from=ab;local e=S.serialize(b)local d=false;for g,f in ipairs(X)do
local h=pcall(f.proxy.send,c,a,e)d=d or h end;if W then local f=pcall(W.send,e)
d=d or f end
if not d then return false,"Send failed on all NICs"end;return true end
function P.handleIncoming(a,d,b,c)if not am then return end;local e,i=S.deserialize(c)if not e then return end
local h,j=S.validate(e)if not h then return end;Q.seen(a)e.from=a;e._distance=b;local f=Q.getLevel(a)
if
f==Q.LEVEL.BLOCKED then if R then
R.debug("net","Dropped (BLOCKED): "..a:sub(1,8))end;return end
if not Q.isAllowed(a,e.type)then
if e.type==S.TYPE.TRUST_REQ then
local k=af(
type(e.payload)=="table"and e.payload.hostname or nil)Q.addPendingRequest(a,k)an(S.TYPE.TRUST_REQ,e,a)
return end;if f>=Q.LEVEL.KNOWN then
if
e.type~=S.TYPE.DENY and e.type~=S.TYPE.ERROR then local k=S.deny("Insufficient trust level")P.send(a,k)end end;if R then
R.debug("net",string.format("Denied %s from %s (level: %s)",e.type,a:sub(1,8),Q.levelName(f)))end;return end
if e.enc and f<Q.LEVEL.TRUSTED then if R then
R.warn("net",string.format("Stripping enc flag on packet from non-TRUSTED peer %s (%s)",a:sub(1,8),
e.type or"?"))end;e.enc=nil;e.payload=
nil;return end;local g=false
if
e.enc and e.enc~=false and f>=Q.LEVEL.TRUSTED then local l=Q._internalGetSecret(a,P._trustToken)local k=nil;if
e.enc=="xor"and T.hasHardware and T.hasHardware()then
k="refusing XOR packet on AES-capable receiver (downgrade)"end
if not k then local m=e.nonce
local n=e.mac
if type(m)~=aa or#m<8 or#m>64 then k="missing or malformed nonce"elseif
type(n)~=aa or#n~=64 then k="missing or malformed MAC"elseif not l then k="no shared secret"else
local o
if e.macv==2 then
o=as(e.type,e.to,e.enc,e.epoch,e.seq,m,e.payload)else
o=table.concat({e.type or"",e.to or"",e.enc or"",tostring(e.epoch or""),tostring(e.seq or""),m,(
e.payload or"")},"\0")end;local p=T.hmac(l,o)
if not T.ctEquals(p,n)then k="MAC mismatch"end end end;if not k then P._recvSeq=P._recvSeq or{}
local m,n=aq(P._recvSeq,a,e.epoch,tonumber(e.seq))if not m then k=n end end
if
not k then P._seenNonces=P._seenNonces or{}local m=P._seenNonces[a]
if not m then P._seenNonces.__order=
P._seenNonces.__order or{}local n=P._seenNonces.__order;if
#n>=ap then local o=table.remove(n,1)
if o~=nil then P._seenNonces[o]=nil end end;n[#n+1]=a
m={order={},set={}}P._seenNonces[a]=m end
if m.set[e.nonce]then k="replayed nonce"else m.set[e.nonce]=true
m.order[#m.order+1]=e.nonce;local n=512;if#m.order>n then local o=table.remove(m.order,1)
m.set[o]=nil end end end
if not k then
if type(e.payload)~=aa then k="enc flag set but payload is not ciphertext"else
local m=T.decrypt(e.payload,l,e.enc)
if not m then k="decryption failed (tampered or wrong key)"else local n=S.deserialize(m)
if not
n then k="decrypted payload failed to deserialize"else e.payload=n;e.enc=false;g=true end end end end
if k then if R then
R.warn("net",string.format("Dropped enc packet from %s (%s): %s",a:sub(1,8),e.type or"?",k))end;return end end
if
not g and ag and f>=Q.LEVEL.TRUSTED and not ar[e.type]and not aw[e.type]then
local k=Q._internalGetSecret(a,P._trustToken)
if k and k~=""then
if R then
R.warn("net",string.format("Dropped unsealed %s from TRUSTED peer %s: we share a secret, so it "..
"must arrive encrypted (a peer with encryptComms off, or a moved modem)",tostring(e.type),a:sub(1,8)))end;return end end
if e.type==S.TYPE.PING then local k=S.pong()
if ad and f>=Q.LEVEL.KNOWN then k.payload=
k.payload or{}k.payload.device=ad.deviceType()end;P.send(a,k)P._recordPeer(a,e.payload)return end
if e.type==S.TYPE.PONG then P._recordPeer(a,e.payload)end
if e.type==S.TYPE.HELLO and f>=Q.LEVEL.KNOWN then
local k=Q.getPeer(a)
if k and type(e.payload)=="table"then
k.hostname=af(e.payload.hostname)pcall(Q.noteDhPublicKey,a,e.payload.dhPub)end
local l=S.helloAck(ae,_G._TOS.version,Q.getMyDhPublicKey())P.send(a,l)end
if e.type==S.TYPE.HELLO_ACK and f>=Q.LEVEL.KNOWN then
local k=Q.getPeer(a)
if k and type(e.payload)=="table"then
k.hostname=af(e.payload.hostname)pcall(Q.noteDhPublicKey,a,e.payload.dhPub)end end
if e.type==S.TYPE.CHALLENGE then if f<Q.LEVEL.TRUSTED then return end;P._challengeRate=
P._challengeRate or{}local n=U.uptime()
local q=P._challengeRate[a]or 0
if n-q<1.0 then if R then
R.warn("net","CHALLENGE throttled from "..a:sub(1,8))end;return end;P._challengeRate[a]=n
local m=Q._internalGetSecret and
Q._internalGetSecret(a,P._trustToken)or nil;if not m or m==""then return end
local k=e.payload and e.payload.nonce
if type(k)~=aa or#k<8 or#k>64 then if R then
R.warn("net","Bad challenge nonce from "..a:sub(1,8))end;return end;local o=T.salt(16)local r,p=pcall(T.hmac,m,k.."|"..o)if
not r or not p then return end;local l=S.challengeResponse(k,p)
l.payload=l.payload or{}l.payload.serverNonce=o;P.send(a,l)return end;an(e.type,e,a)end;local ak=nil
local function ax(a)
if ak==nil then if not S then return end
ak={[S.TYPE.FILE_REQ]="kernel.net.transfer",[S.TYPE.REMOTE_EXEC]="kernel.net.remote",[S.TYPE.NETFS_REQ]="kernel.netfs"}end;local b=ak[a]if not b then return end;ak[a]=nil;local c,d=pcall(require,b)if not c and R then
R.warn("net",
"Lazy handler load failed ("..b.."): "..tostring(d))end end
an=function(a,b,c)ax(a)
if _[a]then
for e,d in ipairs(_[a])do local f,g=pcall(d.cb,b,c)if not f and R then
R.warn("net","Listener error for "..
tostring(a)..": "..tostring(g))end end end
if _["*"]then
for e,d in ipairs(_["*"])do local f,g=pcall(d.cb,b,c)if not f and R then
R.warn("net","Catch-all listener error: "..
tostring(g))end end end end;local at={}
local ay={fileshare="kernel.net.transfer",rshd="kernel.net.remote",netfsd="kernel.netfs"}
function P.setServiceArm(a,b)at[a]=b and true or false;local c=ay[a]
if c and package and
package.loaded and package.loaded[c]then
local d=package.loaded[c]local e=d and(d.arm or d.setEnabled)if e then
e(b and true or false)end end end;function P.getServiceArm(a)return at[a]==true end;local ao=1
function P.on(a,b)if not _[a]then
_[a]={}end;local c=ao;ao=ao+1;_[a][#_[a]+1]={cb=b,id=c}return c end
function P.off(a,b)if not _[a]then return false end;for c,d in ipairs(_[a])do if d.id==b then
table.remove(_[a],c)return true end end;return
false end
function P.onceFrom(a,b,c)local d=false;return
P.on(a,function(f,e)if d or e~=b then return end;d=true;c(f,e)end)end
function P.offAll(a)if type(a)~="table"then return end;for c,b in ipairs(a)do
if
type(b)=="table"and b.type and b.id then P.off(b.type,b.id)end end end
local function az()local a=package.loaded["kernel.process"]
if a and type(a.inProcess)==
"function"then return a.inProcess()end
return
(coroutine.isyieldable and coroutine.isyieldable())and true or false end
function P.waitFor(a,b)local c=U.uptime()+ (b or 10)
while not a()do if U.uptime()>=c then
return false end
if az()then coroutine.yield()else
local d=
(ah and ah.pull)and ah or package.loaded["kernel.event"]if type(d)=="table"and type(d.pull)=="function"then
d.pull(0.5)else U.pullSignal(0.5)end end end;return true end;local al={}local aA=60
local function aB(c,d,T)
if T and T.ctEquals then return T.ctEquals(c,d)end;if type(c)~=aa or type(d)~=aa then return false end
local a,b=#c,#d;local f=a>b and a or b;local e=a~b
for g=1,f do
local h=g<=a and c:byte(g)or 0;local i=g<=b and d:byte(g)or 0;e=e| (h~i)end;return e==0 end
function P.verifyPeer(a,b,c)if not S then return false,"protocol unavailable"end;if
not a or a==""then return false,"no address"end;if not Q then
return false,"trust manager unavailable"end;if not c then local m=al[a]
if m and U.uptime()<m then return true end end;if
Q.getLevel(a)<Q.LEVEL.TRUSTED then return false,"peer not trusted"end
local f=Q._internalGetSecret and
Q._internalGetSecret(a,P._trustToken)or nil
if not f or f==""then return false,"no shared secret with peer"end;local d
if T.salt then d=T.salt(16)else local m={}for n=1,16 do
m[n]=string.char(math.random(0,255))end;d=table.concat(m)end;local g,h,e=false,nil,nil
local i=P.onceFrom(S.TYPE.CHALLENGE_RES,a,function(m)
if
m.payload and m.payload.nonce==d then h=m.payload.proof;e=m.payload.serverNonce;g=true end end)local k,l=P.send(a,S.challenge(d))
if not k then
P.off(S.TYPE.CHALLENGE_RES,i)return false,"send failed: "..tostring(l)end;P.waitFor(function()return g end,b or 5)
P.off(S.TYPE.CHALLENGE_RES,i)if not g then return false,"challenge timeout"end
if
type(e)~=aa or#e<8 or#e>64 then return false,"bad server nonce"end;local j
do local n=d.."|"..e;local o,m=pcall(T.hmac,f,n)if not o or not m then
return false,"hmac failed"end;j=m end
if not aB(h,j,T)then if R then
R.warn("net","Challenge proof mismatch from "..a:sub(1,8))end;return false,"bad proof"end;al[a]=U.uptime()+aA;return true end
function P.invalidateVerification(a)if a then al[a]=nil else al={}end end
function P.discover()local a=S.ping()return P.broadcast(a,Z)end
function P.hello(a)local b=Q.getLevel(a)if b<Q.LEVEL.KNOWN then
return false,"Peer must be KNOWN to exchange hellos"end
local c=S.hello(ae,_G._TOS.version,Q.getMyDhPublicKey())return P.send(a,c)end
function P.sendMessage(a,b)local e=Q.getLevel(a)if e<Q.LEVEL.TRUSTED then
return false,"Peer must be TRUSTED to send messages"end;local c=S.message(b,ag)
local d,f=P.send(a,c)return d,f,d and c.seq or nil end
function P.requestTrust(a)local b=S.trustRequest(ae)return P.send(a,b)end;function P.getTrust()return Q end;local ac={}local aC=64;function af(a)
if type(a)~=aa then return nil end;a=a:gsub("%c",""):sub(1,32)
if a==""then return nil end;return a end
function P._recordPeer(a,b)if
type(a)~=aa then return end;local e=U.uptime()
local f=Q and Q.getLevel(a)or 0;local c=nil;local d=nil
if type(b)=="table"then c=af(b.hostname)d=af(b.device)end
if Q then local g=Q.getPeer(a)if g then c=c or af(g.hostname)end end
if ac[a]==nil then local g,h,i=0,nil,nil
for k,j in pairs(ac)do g=g+1
local l=(
((j.trust or 0)>0)and 1e12 or 0)+ (j.lastSeen or 0)if not i or l<i then h,i=k,l end end;if g>=aC and h then ac[h]=nil end end;ac[a]={addr=a,lastSeen=e,hostname=c,device=d,trust=f}end
function P.peers()local a={}
for c,b in pairs(ac)do
local d=Q and Q.getPeer and Q.getPeer(c)if d and d.level~=nil then b.trust=d.level end;a[#a+1]=b end
table.sort(a,function(c,d)
return(c.hostname or"")< (d.hostname or"")end)return a end
function P.findPeer(a)if type(a)~=aa or a==""then return nil end
if ac[a]then return ac[a]end
for c,b in pairs(ac)do if b.hostname and b.hostname==a then return b end end
for b,c in pairs(ac)do if b:sub(1,#a)==a then return c end end;return nil end
function P.scan(a)a=a or 3;local c={}
local d=P.on(S.TYPE.PONG,function(f,e)P._recordPeer(e,f.payload)
c[e]=ac[e]end)P.discover()
P.waitFor(function()return false end,a)P.off(S.TYPE.PONG,d)local b={}
for f,e in pairs(c)do b[#b+1]=e end;return b end;function P.getProtocol()return S end
function P.status()local a=Q.stats()
return
{available=P.isAvailable(),address=ab and(
ab:sub(1,8).."...")or"none",fullAddress=ab,hostname=ae,listenPort=Y,portOwner=aj[Y],encrypted=ag,hasModem=V~=nil,hasTunnel=W~=nil,peers=a}end
function P.shutdown()am=false;if V then
pcall(function()V.close(Y)if Z then V.close(Z)end end)end;if R then
R.info("net","Network shut down")end end;return P