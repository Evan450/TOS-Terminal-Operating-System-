local f={}f.DEFAULT_TTL=8;f.SEEN_MAX=512;f.RETRY_EVERY=30;f.RELAY_HOLD=120
f.BROADCAST="*"f.MAX_ID=96;f.MAX_TTL=16;f.RELAY_HOLD_MAX=8;f.RELAY_HOLD_BYTES=4096
f.MAX_RESEND=1000000
function f.newEnvelope(b,c,a)a=a or{}
return
{id=a.id or
(tostring(b).."#"..tostring(a.seq or 0)),kind=a.kind or"mail",from=b,to=c or f.BROADCAST,fromUser=a.fromUser,user=a.user,subject=a.subject or"",body=
a.body or"",ttl=a.ttl or f.DEFAULT_TTL,path=a.path or{},ts=a.ts,ackId=a.ackId}end
function f.newAck(b,c,a)a=a or{}return
f.newEnvelope(c,b.from,{id=a.id or("ack:"..tostring(b.id)),kind="ack",ackId=b.id,ttl=
a.ttl or f.DEFAULT_TTL,ts=a.ts})end
function f.newSeen(a)return{set={},order={},max=a or f.SEEN_MAX}end
function f.sawBefore(a,b)if b==nil then return false end;if a.set[b]then return true end
a.set[b]=true;a.order[#a.order+1]=b
if#a.order>a.max then
local c=table.remove(a.order,1)if c~=nil then a.set[c]=nil end end;return false end
function f.seenKey(a)if a.rs==nil then return a.id end;return a.id.."#"..
tostring(math.floor(a.rs))end;function f.inPath(a,b)
for d,c in ipairs(a.path or{})do if c==b then return true end end;return false end
local function g(a)local b=
tonumber(a.ttl)or 0;if b>f.MAX_TTL then b=f.MAX_TTL end;return b end
local function i(a)if type(a)~="table"then return false end;if type(a.id)~="string"or#a.id>
f.MAX_ID then return false end
local c=a.path;if
c~=nil and(type(c)~="table"or#c>f.MAX_TTL*2)then return false end;local b=a.rs;if
b~=nil and(type(b)~="number"or b<
0 or b>f.MAX_RESEND)then return false end;return true end
local function j(a,b)local c={}for e,k in pairs(a)do c[e]=k end;local d={}
for e,k in ipairs(a.path or{})do d[e]=k end;d[#d+1]=b;c.path=d;c.ttl=g(a)-1;return c end
function f.route(a,b,c,d)
if not i(a)then return{dup=false,deliver=false,forward=false}end;if f.sawBefore(d,f.seenKey(a))then
return{dup=true,deliver=false,forward=false}end
local k=(a.to==f.BROADCAST or a.to==nil)local l=k or(c and c(a))or false
local e={dup=false,deliver=l,forward=false}if l and not k then return e end;if g(a)>0 and not f.inPath(a,b)then
e.forward=true;e.out=j(a,b)end;return e end;function f.newOutbox()return{items={},seq=0}end
local function h(a)local b=0
for d,c in pairs(a)do if
type(c)=="string"then b=b+#c elseif type(c)=="table"then if d~="path"then return math.huge end
b=b+#c*48 end end;return b end;f._envBytes=h
function f.enqueue(b,c,a,d)a=a or{}if b.items[c.id]then return false end
d=d or 0
if a.relay then local n=h(c)local m
if n==math.huge then m=false elseif a.canHold then
m=a.canHold(n)and true or false else m=n<=f.RELAY_HOLD_BYTES end;if not m then return false end;local o,l=0,nil;for q,p in pairs(b.items)do
if p.relay then o=o+1;if
not l or
(p.order or 0)< (b.items[l].order or 0)then l=q end end end;if
o>=f.RELAY_HOLD_MAX and l then b.items[l]=nil end end;b.seq=(b.seq or 0)+1
local k=a.interval or f.RETRY_EVERY;local e=a.deadline
if e==nil and a.relay then e=d+f.RELAY_HOLD end
b.items[c.id]={env=c,tries=0,nextAt=d,interval=k,deadline=e,relay=a.relay or false,order=b.seq}return true end;function f.ack(b,a)if a==nil then return false end;local c=b.items[a]~=nil
b.items[a]=nil;return c end;function f.ackRelay(b,a)local c=a~=nil and
b.items[a]
if c and c.relay then b.items[a]=nil;return true end;return false end
function f.shedRelays(b,a)a=
a or 0;local c={}for k,e in pairs(b.items)do
if e.relay then c[#c+1]={k,e.order or 0}end end
table.sort(c,function(e,k)return e[2]<k[2]end)local d=0;for e=1,#c-a do b.items[c[e][1]]=nil;d=d+1 end;return d end
function f.dueItems(b,a)a=a or 0;local c,d={},0
for k,e in pairs(b.items)do
if
e.deadline~=nil and a>=e.deadline then b.items[k]=nil;d=d+1 elseif a>=e.nextAt then e.tries=e.tries+1
e.nextAt=a+e.interval;c[#c+1]=e end end;return c,d end;function f.due(a,b)local d=f.dueItems(a,b)local c={}for e,k in ipairs(d)do c[e]=k.env end
return c end;function f.pending(a)local b=0;for c in pairs(a.items)do b=
b+1 end;return b end;return f