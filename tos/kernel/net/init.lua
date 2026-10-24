local _,as="string","No modem"local ah=require("component")
local X=require("computer")local O={}local R=nil;local Q=nil;local S=nil;local at=8;local ao=256
local function ap(a,d,b,c)if
type(b)~=_ or type(c)~="number"then return true end;local e=a[d]
if not e then
a.__order=a.__order or{}if#a.__order>=ao then local f=table.remove(a.__order,1)
if f~=nil then a[f]=nil end end
a.__order[#a.__order+1]=d;a[d]={epoch=b,maxSeq=c,retired={},retiredOrder={}}return true end;if e.epoch==b then
if c<=e.maxSeq then return false,"stale or replayed sequence"end;e.maxSeq=c;return true end
if
e.retired[b]then return false,"replayed packet from a retired epoch"end;e.retired[e.epoch]=true
e.retiredOrder[#e.retiredOrder+1]=e.epoch;if#e.retiredOrder>at then
local f=table.remove(e.retiredOrder,1)e.retired[f]=nil end;e.epoch=b
e.maxSeq=c;return true end;O._seqCheck=ap;local T=nil;local U=nil;local aa=nil;local V={}local W=42;local Y=nil
local ai={[14]="Ethernet-over-OC",[148]="the GUI service",[4096]="MultICE / Minitel",[4378]="GERTi",[4379]="GERTi",[4662]="short messages",[9100]="the network print service",[9900]="Zorya BIOS LAN boot"}O.REGISTERED_PORTS=ai;function O.portOwner(a)return ai[a]end;local af=true;local ad="tos"
local al=false;local Z={}local P=nil;local ac=nil;local ag=nil;local am;local ae
function O.init(a)P=a.log;ac=a.config;ag=a.event
R=require("kernel.net.protocol")Q=require("kernel.net.trust")
S=require("kernel.crypto")Q.init({fs=a.fs,crypto=S,log=P,config=ac})
O._trustToken=
Q.getBootstrapToken and Q.getBootstrapToken()or nil
if ac then W=ac.get("listenPort")or 42
local g=ac.get("broadcastPort")
Y=(type(g)=="number"and g~=W)and g or nil;af=ac.get("encryptComms")~=false;ad=ac.get("hostname")or
"tos"end
for h,g in ipairs({W,Y})do local i=g and ai[g]
if i and P then
P.warn("net",string.format(
"Port %d is registered to %s: TOS traffic will share ".."that network. TOS's own port is 42 (listenPort in /etc/tos.cfg).",g,i))end end;V={}
for g in ah.list("modem")do local i,h=pcall(ah.proxy,g)
if i and h then
pcall(h.open,W)if Y then pcall(h.open,Y)end;local j=false
pcall(function()j=h.isWireless()end)V[#V+1]={addr=g,proxy=h,wireless=j}if P then
P.info("net",string.format("Modem %d: %s [%s]",#V,
j and"wireless"or"wired",g:sub(1,8).."..."))end end end
if#V>0 then T=V[1].proxy;aa=V[1].addr;if P and#V>1 then
P.info("net",#V.." NICs active (multi-modem)")end
if P then
local g=
Y and("ports "..W..", "..Y)or("port "..W.." (single-port mode)")P.info("net","Listening on "..g)end end
for g in ah.list("tunnel")do local i,h=pcall(ah.proxy,g)if i and h then U=h;if P then
P.info("net","Linked card detected")end end;break end
if not T and not U then if P then
P.warn("net","No network hardware detected")end;return false end;if ag then
ag.on("modem_message",function(k,l,g,h,i,j)O.handleIncoming(g,h,i,j)O.meshTick()end,"net")end;al=true
local d,b=pcall(require,"kernel.net.chatpair")
if d and b and b.init then
b.init({crypto=S,protocol=R,trust=Q,log=P})O._chatpair=b
O.on(R.TYPE.CHAT_PAIR_INIT,function(g,h)b.onPairInit(g,h)end)
if P then P.info("net","Chat-pair handler registered")end elseif P then
P.warn("net","chatpair module unavailable: "..tostring(b))end
local function e(g)local i,h="/var/lib/mesh","/var/lib/mesh/state.dat"
local j=require("kernel.serialize")
return
{load=function()if not(g and g.exists and g.exists(h))then
return nil end;return j.loadFile(g,h)end,save=function(k)if
not g then return end
if not g.exists(i)then g.makeDirectory(i)end;j.saveFile(g,h,k)end}end;local f,c=pcall(require,"kernel.net.meshctl")
if f and c then
c.init({crypto=S,serialize=require("kernel.serialize"),log=P,clock=function()return
X.uptime()end})
O._meshctl=c.new({myAddr=aa,clock=function()return X.uptime()end,freeMemory=X.freeMemory,store=e(a and a.fs or
(_G._TOS and _G._TOS.fs)),broadcast=function(h)local k=
(h.kind=="ack")and R.TYPE.MESH_ACK or R.TYPE.MESH
local j=R.makePacket(k,h)local i=h.to
if i and i~="*"then local l=O._meshctl:routeFor(i)
if l and l~=aa then
local m=O.sendToAddress(l,j)if m then return end;O._meshctl:invalidateRoute(i)end end;O.broadcast(j)end,secretFor=function(h)return

Q._internalGetSecret and Q._internalGetSecret(h,O._trustToken)or nil end,log=P})
local function g(h)if type(h.payload)=="table"then
O._meshctl:onPacket(h.payload)end end;O.on(R.TYPE.MESH,g)O.on(R.TYPE.MESH_ACK,g)if P then
P.info("net","Mesh transport controller registered")end elseif P then
P.warn("net","mesh transport unavailable: "..tostring(c))end;if P then
P.info("net","Network initialized (zero-trust mode)")
P.info("net","Encryption: ".. (af and"enabled"or"disabled"))end;return true end;function O.getChatPair()return O._chatpair end;function O.meshAvailable()
return O._meshctl~=nil end;function O.meshSend(a)if not O._meshctl then
return nil,"mesh not available (no network?)"end
return O._meshctl:send(a or{})end;function O.meshOn(a,b)if
not O._meshctl then return false,"mesh not available"end
O._meshctl:on(a,b)return true end
function O.meshOff(a)if
O._meshctl then O._meshctl:off(a)end end;function O.meshHasHandler(a)
return O._meshctl~=nil and O._meshctl:hasHandler(a)end
function O.meshPending()return O._meshctl and
O._meshctl:pending()or 0 end
function O.meshTick()if not O._meshctl then return end;local a=X.uptime()if a-
(O._lastMeshTick or 0)>=5 then O._lastMeshTick=a
O._meshctl:tick(a)end end;function O.isAvailable()return T~=nil or U~=nil end
function O.getAddress()return aa end;function O.getHostname()return ad end
function O.setHostname(a)if
type(a)~=_ or a==""or#a>32 or a:find("%c")then
return false,"hostname must be 1-32 printable characters"end;ad=a;return true end;function O.modemCount()return#V end
local aq={ping=true,pong=true,hello=true,hello_ack=true,challenge=true,chall_res=true,deny=true,ch_pair_init=true,ch_pair_conf=true,cl_pair_init=true,cl_pair_conf=true}local au={mesh=true,mesh_ack=true}
function O.send(b,a,c)
if not T and not U then return false,as end;c=c or W;a.from=aa;a.to=b;local g=Q.getLevel(b)local h=aq[a.type]
if af and g>=
Q.LEVEL.TRUSTED and not h then
local i=Q._internalGetSecret(b,O._trustToken)
if i and a.payload then local l=R.serialize(a.payload)local j,k=S.encrypt(l,i)
a.payload=j;a.enc=k;O._bootEpoch=O._bootEpoch or S.salt(12)
O._sendSeq=O._sendSeq or{}O._sendSeq[b]=(O._sendSeq[b]or 0)+1
a.epoch=O._bootEpoch;a.seq=O._sendSeq[b]a.nonce=S.salt(16)
a.mac=S.hmac(i,table.concat({a.type or"",
a.to or"",k or"",a.epoch,tostring(a.seq),a.nonce,j},"\0"))elseif a.payload and not i then
if P then
P.warn("net",string.format("Refusing plaintext send to TRUSTED peer %s (%s): no shared secret; "..
"run 'net trust gen %s' as admin to provision one",b:sub(1,8),a.type or"?",b:sub(1,8)))end;return false,"TRUSTED peer has no shared secret; refusing plaintext send"end end;local d=R.serialize(a)
if#d>R.MAX_SIZE then return false,"Packet too large"end;local e,f
if T then e,f=pcall(T.send,b,c,d)else e,f=pcall(U.send,d)end
if not e then return false,"Send failed: "..tostring(f)end;return true end
function O.broadcast(b,a)if not T and not U then return false,as end;a=a or Y or W
b.from=aa;local d=R.serialize(b)local c=false;for f,e in ipairs(V)do
local g=pcall(e.proxy.broadcast,a,d)c=c or g end;if U then local e=pcall(U.send,d)
c=c or e end
if not c then return false,"Broadcast failed on all NICs"end;return true end
function O.sendToAddress(c,b,a)if not T and not U then return false,as end;a=a or Y or W
b.from=aa;local e=R.serialize(b)local d=false;for g,f in ipairs(V)do
local h=pcall(f.proxy.send,c,a,e)d=d or h end;if U then local f=pcall(U.send,e)
d=d or f end
if not d then return false,"Send failed on all NICs"end;return true end
function O.handleIncoming(a,d,b,c)if not al then return end;local e,i=R.deserialize(c)if not e then return end
local h,j=R.validate(e)if not h then return end;Q.seen(a)e.from=a;e._distance=b;local f=Q.getLevel(a)
if
f==Q.LEVEL.BLOCKED then if P then
P.debug("net","Dropped (BLOCKED): "..a:sub(1,8))end;return end
if not Q.isAllowed(a,e.type)then
if e.type==R.TYPE.TRUST_REQ then
local k=ae(
type(e.payload)=="table"and e.payload.hostname or nil)Q.addPendingRequest(a,k)am(R.TYPE.TRUST_REQ,e,a)
return end;if f>=Q.LEVEL.KNOWN then
if
e.type~=R.TYPE.DENY and e.type~=R.TYPE.ERROR then local k=R.deny("Insufficient trust level")O.send(a,k)end end;if P then
P.debug("net",string.format("Denied %s from %s (level: %s)",e.type,a:sub(1,8),Q.levelName(f)))end;return end
if e.enc and f<Q.LEVEL.TRUSTED then if P then
P.warn("net",string.format("Stripping enc flag on packet from non-TRUSTED peer %s (%s)",a:sub(1,8),
e.type or"?"))end;e.enc=nil;e.payload=
nil;return end;local g=false
if
e.enc and e.enc~=false and f>=Q.LEVEL.TRUSTED then local l=Q._internalGetSecret(a,O._trustToken)local k=nil;if
e.enc=="xor"and S.hasHardware and S.hasHardware()then
k="refusing XOR packet on AES-capable receiver (downgrade)"end
if not k then local m=e.nonce
local n=e.mac
if type(m)~=_ or#m<8 or#m>64 then k="missing or malformed nonce"elseif
type(n)~=_ or#n~=64 then k="missing or malformed MAC"elseif not l then k="no shared secret"else
local o=S.hmac(l,table.concat({
e.type or"",e.to or"",e.enc or"",tostring(e.epoch or""),tostring(e.seq or""),m,(
e.payload or"")},"\0"))if not S.ctEquals(o,n)then k="MAC mismatch"end end end;if not k then O._recvSeq=O._recvSeq or{}
local m,n=ap(O._recvSeq,a,e.epoch,tonumber(e.seq))if not m then k=n end end
if
not k then O._seenNonces=O._seenNonces or{}local m=O._seenNonces[a]
if not m then O._seenNonces.__order=
O._seenNonces.__order or{}local n=O._seenNonces.__order;if
#n>=ao then local o=table.remove(n,1)
if o~=nil then O._seenNonces[o]=nil end end;n[#n+1]=a
m={order={},set={}}O._seenNonces[a]=m end
if m.set[e.nonce]then k="replayed nonce"else m.set[e.nonce]=true
m.order[#m.order+1]=e.nonce;local n=512;if#m.order>n then local o=table.remove(m.order,1)
m.set[o]=nil end end end
if not k then
if type(e.payload)~=_ then k="enc flag set but payload is not ciphertext"else
local m=S.decrypt(e.payload,l,e.enc)
if not m then k="decryption failed (tampered or wrong key)"else local n=R.deserialize(m)
if not
n then k="decrypted payload failed to deserialize"else e.payload=n;e.enc=false;g=true end end end end
if k then if P then
P.warn("net",string.format("Dropped enc packet from %s (%s): %s",a:sub(1,8),e.type or"?",k))end;return end end
if
not g and af and f>=Q.LEVEL.TRUSTED and not aq[e.type]and not au[e.type]then
local k=Q._internalGetSecret(a,O._trustToken)
if k and k~=""then
if P then
P.warn("net",string.format("Dropped unsealed %s from TRUSTED peer %s: we share a secret, so it "..
"must arrive encrypted (a peer with encryptComms off, or a moved modem)",tostring(e.type),a:sub(1,8)))end;return end end
if e.type==R.TYPE.PING then local k=R.pong()
if ac and f>=Q.LEVEL.KNOWN then k.payload=
k.payload or{}k.payload.device=ac.deviceType()end;O.send(a,k)O._recordPeer(a,e.payload)return end
if e.type==R.TYPE.PONG then O._recordPeer(a,e.payload)end
if e.type==R.TYPE.HELLO and f>=Q.LEVEL.KNOWN then
local k=Q.getPeer(a)
if k and type(e.payload)=="table"then
k.hostname=ae(e.payload.hostname)pcall(Q.noteDhPublicKey,a,e.payload.dhPub)end
local l=R.helloAck(ad,_G._TOS.version,Q.getMyDhPublicKey())O.send(a,l)end
if e.type==R.TYPE.HELLO_ACK and f>=Q.LEVEL.KNOWN then
local k=Q.getPeer(a)
if k and type(e.payload)=="table"then
k.hostname=ae(e.payload.hostname)pcall(Q.noteDhPublicKey,a,e.payload.dhPub)end end
if e.type==R.TYPE.CHALLENGE then if f<Q.LEVEL.TRUSTED then return end;O._challengeRate=
O._challengeRate or{}local n=X.uptime()
local q=O._challengeRate[a]or 0
if n-q<1.0 then if P then
P.warn("net","CHALLENGE throttled from "..a:sub(1,8))end;return end;O._challengeRate[a]=n
local m=Q._internalGetSecret and
Q._internalGetSecret(a,O._trustToken)or nil;if not m or m==""then return end
local k=e.payload and e.payload.nonce
if type(k)~=_ or#k<8 or#k>64 then if P then
P.warn("net","Bad challenge nonce from "..a:sub(1,8))end;return end;local o=S.salt(16)local r,p=pcall(S.hmac,m,k.."|"..o)if
not r or not p then return end;local l=R.challengeResponse(k,p)
l.payload=l.payload or{}l.payload.serverNonce=o;O.send(a,l)return end;am(e.type,e,a)end;local aj=nil
local function av(a)
if aj==nil then if not R then return end
aj={[R.TYPE.FILE_REQ]="kernel.net.transfer",[R.TYPE.REMOTE_EXEC]="kernel.net.remote",[R.TYPE.NETFS_REQ]="kernel.netfs"}end;local b=aj[a]if not b then return end;aj[a]=nil;local c,d=pcall(require,b)if not c and P then
P.warn("net",
"Lazy handler load failed ("..b.."): "..tostring(d))end end
am=function(a,b,c)av(a)
if Z[a]then
for e,d in ipairs(Z[a])do local f,g=pcall(d.cb,b,c)if not f and P then
P.warn("net","Listener error for "..
tostring(a)..": "..tostring(g))end end end
if Z["*"]then
for e,d in ipairs(Z["*"])do local f,g=pcall(d.cb,b,c)if not f and P then
P.warn("net","Catch-all listener error: "..
tostring(g))end end end end;local ar={}
local aw={fileshare="kernel.net.transfer",rshd="kernel.net.remote",netfsd="kernel.netfs"}
function O.setServiceArm(a,b)ar[a]=b and true or false;local c=aw[a]
if c and package and
package.loaded and package.loaded[c]then
local d=package.loaded[c]local e=d and(d.arm or d.setEnabled)if e then
e(b and true or false)end end end;function O.getServiceArm(a)return ar[a]==true end;local an=1
function O.on(a,b)if not Z[a]then
Z[a]={}end;local c=an;an=an+1;Z[a][#Z[a]+1]={cb=b,id=c}return c end
function O.off(a,b)if not Z[a]then return false end;for c,d in ipairs(Z[a])do if d.id==b then
table.remove(Z[a],c)return true end end;return
false end
function O.onceFrom(a,b,c)local d=false;return
O.on(a,function(f,e)if d or e~=b then return end;d=true;c(f,e)end)end
function O.offAll(a)if type(a)~="table"then return end;for c,b in ipairs(a)do
if
type(b)=="table"and b.type and b.id then O.off(b.type,b.id)end end end
local function ax()local a=package.loaded["kernel.process"]
if a and type(a.inProcess)==
"function"then return a.inProcess()end
return
(coroutine.isyieldable and coroutine.isyieldable())and true or false end
function O.waitFor(a,b)local c=X.uptime()+ (b or 10)
while not a()do if X.uptime()>=c then
return false end
if ax()then coroutine.yield()else
local d=
(ag and ag.pull)and ag or package.loaded["kernel.event"]if type(d)=="table"and type(d.pull)=="function"then
d.pull(0.5)else X.pullSignal(0.5)end end end;return true end;local ak={}local ay=60
local function az(c,d,S)
if S and S.ctEquals then return S.ctEquals(c,d)end;if type(c)~=_ or type(d)~=_ then return false end
local a,b=#c,#d;local f=a>b and a or b;local e=a~b
for g=1,f do
local h=g<=a and c:byte(g)or 0;local i=g<=b and d:byte(g)or 0;e=e| (h~i)end;return e==0 end
function O.verifyPeer(a,b,c)if not R then return false,"protocol unavailable"end;if
not a or a==""then return false,"no address"end;if not Q then
return false,"trust manager unavailable"end;if not c then local m=ak[a]
if m and X.uptime()<m then return true end end;if
Q.getLevel(a)<Q.LEVEL.TRUSTED then return false,"peer not trusted"end
local f=Q._internalGetSecret and
Q._internalGetSecret(a,O._trustToken)or nil
if not f or f==""then return false,"no shared secret with peer"end;local d
if S.salt then d=S.salt(16)else local m={}for n=1,16 do
m[n]=string.char(math.random(0,255))end;d=table.concat(m)end;local g,h,e=false,nil,nil
local i=O.onceFrom(R.TYPE.CHALLENGE_RES,a,function(m)
if
m.payload and m.payload.nonce==d then h=m.payload.proof;e=m.payload.serverNonce;g=true end end)local k,l=O.send(a,R.challenge(d))
if not k then
O.off(R.TYPE.CHALLENGE_RES,i)return false,"send failed: "..tostring(l)end;O.waitFor(function()return g end,b or 5)
O.off(R.TYPE.CHALLENGE_RES,i)if not g then return false,"challenge timeout"end
if
type(e)~=_ or#e<8 or#e>64 then return false,"bad server nonce"end;local j
do local n=d.."|"..e;local o,m=pcall(S.hmac,f,n)if not o or not m then
return false,"hmac failed"end;j=m end
if not az(h,j,S)then if P then
P.warn("net","Challenge proof mismatch from "..a:sub(1,8))end;return false,"bad proof"end;ak[a]=X.uptime()+ay;return true end
function O.invalidateVerification(a)if a then ak[a]=nil else ak={}end end
function O.discover()local a=R.ping()return O.broadcast(a,Y)end
function O.hello(a)local b=Q.getLevel(a)if b<Q.LEVEL.KNOWN then
return false,"Peer must be KNOWN to exchange hellos"end
local c=R.hello(ad,_G._TOS.version,Q.getMyDhPublicKey())return O.send(a,c)end
function O.sendMessage(a,b)local e=Q.getLevel(a)if e<Q.LEVEL.TRUSTED then
return false,"Peer must be TRUSTED to send messages"end;local c=R.message(b,af)
local d,f=O.send(a,c)return d,f,d and c.seq or nil end
function O.requestTrust(a)local b=R.trustRequest(ad)return O.send(a,b)end;function O.getTrust()return Q end;local ab={}local aA=64
function ae(a)if type(a)~=_ then return nil end
a=a:gsub("%c",""):sub(1,32)if a==""then return nil end;return a end
function O._recordPeer(a,b)if type(a)~=_ then return end;local e=X.uptime()local f=
Q and Q.getLevel(a)or 0;local c=nil;local d=nil;if type(b)=="table"then
c=ae(b.hostname)d=ae(b.device)end;if Q then local g=Q.getPeer(a)if g then c=c or
ae(g.hostname)end end
if ab[a]==
nil then local g,h,i=0,nil,nil
for k,j in pairs(ab)do g=g+1
local l=(
((j.trust or 0)>0)and 1e12 or 0)+ (j.lastSeen or 0)if not i or l<i then h,i=k,l end end;if g>=aA and h then ab[h]=nil end end;ab[a]={addr=a,lastSeen=e,hostname=c,device=d,trust=f}end
function O.peers()local a={}for c,b in pairs(ab)do a[#a+1]=b end
table.sort(a,function(c,d)return
(c.hostname or"")< (d.hostname or"")end)return a end
function O.findPeer(a)if type(a)~=_ or a==""then return nil end
if ab[a]then return ab[a]end
for c,b in pairs(ab)do if b.hostname and b.hostname==a then return b end end
for b,c in pairs(ab)do if b:sub(1,#a)==a then return c end end;return nil end
function O.scan(a)a=a or 3;local c={}
local d=O.on(R.TYPE.PONG,function(f,e)O._recordPeer(e,f.payload)
c[e]=ab[e]end)O.discover()
O.waitFor(function()return false end,a)O.off(R.TYPE.PONG,d)local b={}
for f,e in pairs(c)do b[#b+1]=e end;return b end;function O.getProtocol()return R end
function O.status()local a=Q.stats()
return
{available=O.isAvailable(),address=aa and(
aa:sub(1,8).."...")or"none",fullAddress=aa,hostname=ad,listenPort=W,portOwner=ai[W],encrypted=af,hasModem=T~=nil,hasTunnel=U~=nil,peers=a}end
function O.shutdown()al=false;if T then
pcall(function()T.close(W)if Y then T.close(Y)end end)end;if P then
P.info("net","Network shut down")end end;return O