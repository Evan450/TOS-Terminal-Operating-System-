local n="string"local l=require("kernel.net.mesh")local k={}k.__index=k
k.RELAY_BUDGET=32;k.MAX_PAYLOAD=8192;k.RELAY_FLOOR=48*1024;k.FULL_EVERY=4;k.ORIGIN_MAX=16
k.DELIVERED_MAX=64;k.ORIGIN_TTL=3600;local m,o,p;local q=function()return 0 end
function k.init(a)a=a or{}
m=a.crypto
o=a.serialize or require("kernel.serialize")p=a.log;if a.clock then q=a.clock end end
function k.sealEnv(a,b)
if not(m and b and b~="")then a.sealed=nil;return a end;local f=o.encode(a.payload or{})local c,d=m.encrypt(f,b)local e=m.salt and
m.salt(16)or""a.sealed=c;a.encMethod=d;a.nonce=e
a.mac=m.hmac(b,table.concat({tostring(a.id),tostring(a.from),tostring(a.to),tostring(a.svc),
d or"",e,c},"\0"))a.payload=nil;return a end
function k.openEnv(a,b)
if not a.sealed then return a.payload or{},"plaintext"end
if not(m and b and b~="")then return nil,"sealed but no secret"end
local e=m.hmac(b,table.concat({tostring(a.id),tostring(a.from),tostring(a.to),tostring(a.svc),
a.encMethod or"",a.nonce or"",a.sealed},"\0"))local f=m.ctEquals or function(h,i)return h==i end
if not f(e,
a.mac or"")then return nil,"MAC mismatch (tampered or wrong key)"end;local c=m.decrypt(a.sealed,b,a.encMethod)if not c then
return nil,"decryption failed"end
local g,d=pcall(o.decode,c,{maxBytes=k.MAX_PAYLOAD+512})
if not g or type(d)~="table"then return nil,"corrupt sealed payload"end;return d,"sealed"end
local function r(a,b,c,d,e)if not(m and m.hmac and a and a~="")then
return nil end;return
m.hmac(a,table.concat({tostring(b),tostring(c),tostring(d),tostring(e)},"\0"))end;k._replyMac=r
function k.compose(a)a=a or{}
local b=l.newEnvelope(a.from,a.to,{id=a.id,seq=a.seq,ttl=a.ttl,fromUser=a.fromUser,user=a.user,ts=a.ts or q(),kind="msg"})b.svc=a.svc;b.payload=a.payload or{}
return k.sealEnv(b,a.secret)end
function k.ingest(a,b,e,f,c,d,g)local i=l.route(a,b,e,f)
if d then l.learnRoute(d,a,b,g)end;local h={dup=i.dup,forward=i.forward,out=i.out,deliver=false}if i.dup or not
i.deliver then return h end;if
a.kind=="ack"or a.kind=="probe"or a.kind=="want"then h.deliver=true;h.kind=a.kind
h.ackId=a.ackId;return h end;local v=
c and c(a.from)or nil;local j,u=k.openEnv(a,v)h.deliver=true
h.kind="msg"h.svc=a.svc
h.message={id=a.id,from=a.from,fromUser=a.fromUser,to=a.to,user=a.user,payload=j,ts=a.ts,sealed=(a.sealed~=nil),readable=(j~=nil),how=u}
if not j and p then
p.warn("mesh","Delivered sealed '"..tostring(a.svc)..
"' from "..
tostring(a.from):sub(1,8).." could not be opened: "..tostring(u))end
if a.to~=l.BROADCAST and a.to~=nil then h.ackTo=a.from end;return h end
local function t()local a=m and m.salt and m.salt(4)
if type(a)==n and#a>=4 then return
(a:sub(1,4):gsub(".",function(b)return
string.format("%02x",b:byte())end))end;return
string.format("%08x",math.floor((os.time and os.time()or 0)+
q()*1000)%0x100000000)end
function k.new(a)a=a or{}local b=setmetatable({},k)b.myAddr=a.myAddr;b.broadcast=a.broadcast or
function()end
b.secretFor=a.secretFor or function()return nil end;b.clock=a.clock or function()return 0 end;b.log=a.log
b.isForMe=
a.isForMe or function(c)return c.to==b.myAddr end;b.freeMemory=a.freeMemory;b.store=a.store;b.seen=l.newSeen()
b.outbox=l.newOutbox()b.routes=l.newRouteCache()b.delivered={set={},order={}}
b._handlers={}b._seq=0;b._epoch=t()b._relayWindow,b._relayCount=-1,0;b:_load()return b end;function k:on(a,b)self._handlers[a]=b end;function k:off(a)
self._handlers[a]=nil end
function k:hasHandler(a)return self._handlers[a]~=nil end
function k:_nextId(a)self._seq=self._seq+1;return
(a or"x")..":"..
tostring(self.myAddr)..":"..
self._epoch..":"..tostring(self._seq)end
function k:_mayRelay()local a=math.floor(self.clock())if a~=self._relayWindow then
self._relayWindow,self._relayCount=a,0 end;if self._relayCount>=k.RELAY_BUDGET then
return false end
self._relayCount=self._relayCount+1;return true end
local function s(a)if not a.freeMemory then return nil end;local c,b=pcall(a.freeMemory)if c and
type(b)=="number"then return b end;return nil end
function k:_canHold(a)local b=s(self)
if b==nil then return a<=l.RELAY_HOLD_BYTES end;return b-a>=k.RELAY_FLOOR end
function k:_memoryLow()local a=s(self)return a~=nil and a<k.RELAY_FLOOR end
function k:_noteDelivered(a)local b=self.delivered;if b.set[a]then return end;b.set[a]=true;b.order[#
b.order+1]=a;while#b.order>k.DELIVERED_MAX do b.set[table.remove(b.order,1)]=
nil end end
function k:_save()local a=self.store;if not(a and a.save)then return end
local c=self.clock()local b={}
for g,f in pairs(self.outbox.items)do if not f.relay then
b[#b+1]={env=f.env,rs=f.rs,probes=f.probes,left=f.deadline and(f.deadline-
c)or nil}end end
local d,e=pcall(a.save,{outbox=b,delivered=self.delivered.order})if not d and self.log then
self.log.warn("mesh","could not save mesh state: "..tostring(e))end end
function k:_load()local b=self.store;if not(b and b.load)then return end
local d,a=pcall(b.load)if not d or type(a)~="table"then return end
local c=self.clock()
for f,e in
ipairs(type(a.outbox)=="table"and a.outbox or{})do local g=type(e)=="table"and e.env or nil
if
type(g)=="table"and type(g.id)==n then
local i=tonumber(e.left)or k.ORIGIN_TTL
l.enqueue(self.outbox,g,{interval=l.RETRY_EVERY,deadline=c+i},c)local h=self.outbox.items[g.id]if h then h.rs=tonumber(e.rs)h.probes=
tonumber(e.probes)or 0 end
l.sawBefore(self.seen,g.id)end end
for f,e in
ipairs(type(a.delivered)=="table"and a.delivered or{})do if type(e)==n then self:_noteDelivered(e)end end end
function k:_reply(a,b,c)
local d=l.newEnvelope(self.myAddr,c,{id=self:_nextId(a:sub(1,1)),kind=a,ts=self.clock()})if a=="ack"then d.ackId=b else d.wantId=b end
d.mac=r(self.secretFor(c),a,b,self.myAddr,c)l.sawBefore(self.seen,d.id)self.broadcast(d)return d end
function k:_verifyReply(c,b,a)if a.from~=b.env.to then return false end;if not b.env.sealed then
return true end
local d=r(self.secretFor(b.env.to),c,b.env.id,a.from,a.to)
local e=(m and m.ctEquals)or function(f,g)return f==g end
return d~=nil and type(a.mac)==n and e(d,a.mac)end
function k:_resend(a)l.invalidateRoute(self.routes,a.env.to)a.rs=
(a.rs or 0)+1;a.probes=0;a.lastSent=self.clock()local b={}for c,d in pairs(a.env)do
b[c]=d end;b.rs=a.rs;b.path={}
l.sawBefore(self.seen,l.seenKey(b))self.broadcast(b)end
function k:_probe(a)
local b=l.newEnvelope(self.myAddr,a.env.to,{id=self:_nextId("p"),kind="probe",ts=self.clock()})b.probeId=a.env.id;l.sawBefore(self.seen,b.id)
self.broadcast(b)end
function k:_onAck(a)
local b=type(a.ackId)==n and self.outbox.items[a.ackId]if not b or b.relay then return end
if
not self:_verifyReply("ack",b,a)then if self.log then
self.log.warn("mesh","ignored an ACK that does not verify: "..tostring(a.ackId))end;return end;l.ack(self.outbox,a.ackId)self:_save()end
function k:_onProbe(a)local b=a.probeId
if type(b)~=n or#b>l.MAX_ID then return end
if self.delivered.set[b]then self:_reply("ack",b,a.from)elseif not
self.seen.set[b]then self:_reply("want",b,a.from)end end
function k:_onWant(a)
local b=type(a.wantId)==n and self.outbox.items[a.wantId]if not b or b.relay then return end;if
not self:_verifyReply("want",b,a)then return end
if b.lastSent and self.clock()-b.lastSent<
l.RETRY_EVERY/2 then return end;self:_resend(b)end
function k:send(a)a=a or{}if type(a.svc)~=n or a.svc==""then
return nil,"mesh send needs a service kind (svc)"end
local b=(a.to~=nil and a.to~=l.BROADCAST)local d=b and self.secretFor(a.to)or nil
if
not d and not a.allowPlaintext then
if b then return nil,
"no shared secret with "..
tostring(a.to):sub(1,8).."... — pair first (net pair) or allow plaintext explicitly"end;return nil,"broadcasts can't be sealed — allow plaintext explicitly"end;if b then local f=self:pending()
if f>=k.ORIGIN_MAX then return nil,"mesh outbox full: "..
f.." messages are still awaiting delivery"end end
local c=self:_nextId(a.svc:sub(1,1))
local e=k.compose({from=self.myAddr,to=a.to,svc=a.svc,fromUser=a.fromUser,user=a.user,payload=a.payload,secret=d,id=c,ttl=a.ttl,ts=self.clock()})
if b then local f=self.clock()
l.enqueue(self.outbox,e,{interval=l.RETRY_EVERY,deadline=f+k.ORIGIN_TTL},f)local g=self.outbox.items[c]if g then g.nextAt=f+l.RETRY_EVERY
g.lastSent=f end;self:_save()end;l.sawBefore(self.seen,c)self.broadcast(e)
return c, (d~=nil)end
function k:onPacket(a)
local c=type(a)=="table"and a.to~=l.BROADCAST and a.to~=nil
local b=k.ingest(a,self.myAddr,self.isForMe,self.seen,self.secretFor,self.routes,self.clock())
if
type(a)=="table"and a.kind=="ack"and type(a.ackId)==n then l.ackRelay(self.outbox,a.ackId)end
if b.forward and b.out then
if self:_mayRelay()then self.broadcast(b.out)if
a.kind=="msg"and c then
l.enqueue(self.outbox,b.out,{relay=true,canHold=function(d)return self:_canHold(d)end},self.clock())end elseif self.log then
self.log.warn("mesh","relay budget exceeded; dropping a forward")end end;if
b.dup and c and a.kind=="msg"and self.delivered.set[a.id]and self.isForMe(a)then
self:_reply("ack",a.id,a.from)end
if b.deliver then
if
b.kind=="ack"then self:_onAck(a)elseif b.kind=="probe"then self:_onProbe(a)elseif b.kind=="want"then
self:_onWant(a)elseif b.kind=="msg"and b.message then local d=false
if b.ackTo and
self.delivered.set[a.id]then d=true else local e=self._handlers[b.svc or""]
if e then
local f,g=pcall(e,b.message,a)d=f and g and true or false;if not f and self.log then
self.log.warn("mesh",
"'"..tostring(b.svc).."' handler error: "..tostring(g))end elseif self.log then
self.log.warn("mesh",
"no local service for mesh kind '"..
tostring(b.svc).."' (message from "..
tostring(a.from):sub(1,8).." dropped, not ACKed)")end
if d and b.ackTo then self:_noteDelivered(a.id)self:_save()end end
if b.ackTo and d then self:_reply("ack",a.id,b.ackTo)end;b.handled=d end end;return b end
function k:tick(a)a=a or self.clock()if self:_memoryLow()then
l.shedRelays(self.outbox,0)end;local b,c=l.dueItems(self.outbox,a)
for e,d in
ipairs(b)do if d.relay then self.broadcast(d.env)else
d.probes=(d.probes or 0)+1
if d.probes>=k.FULL_EVERY then self:_resend(d)else self:_probe(d)end end end;if c>0 then self:_save()end end
function k:routeFor(a)return l.routeFor(self.routes,a,self.clock())end
function k:invalidateRoute(a)l.invalidateRoute(self.routes,a)end;function k:pending()local a=0
for c,b in pairs(self.outbox.items)do if not b.relay then a=a+1 end end;return a end;return k