local h="string"local g={}g.DEFAULT_TTL=8;g.SEEN_MAX=512;g.RETRY_EVERY=30
g.RELAY_HOLD=120;g.BROADCAST="*"g.MAX_ID=96;g.MAX_TTL=16;g.RELAY_HOLD_MAX=8
g.RELAY_HOLD_BYTES=4096;g.MAX_RESEND=1000000;g.ROUTE_MAX=64;g.ROUTE_TTL=300
function g.newEnvelope(b,c,a)a=a or{}
return
{id=a.id or
(
tostring(b).."#"..tostring(a.seq or 0)),kind=a.kind or"mail",from=b,to=c or g.BROADCAST,fromUser=a.fromUser,user=a.user,subject=a.subject or"",body=
a.body or"",ttl=a.ttl or g.DEFAULT_TTL,path=a.path or{},ts=a.ts,ackId=a.ackId}end
function g.newAck(b,c,a)a=a or{}return
g.newEnvelope(c,b.from,{id=a.id or("ack:"..tostring(b.id)),kind="ack",ackId=b.id,ttl=
a.ttl or g.DEFAULT_TTL,ts=a.ts})end
function g.newSeen(a)return{set={},order={},max=a or g.SEEN_MAX}end
function g.sawBefore(a,b)if b==nil then return false end;if a.set[b]then return true end
a.set[b]=true;a.order[#a.order+1]=b
if#a.order>a.max then
local c=table.remove(a.order,1)if c~=nil then a.set[c]=nil end end;return false end
function g.seenKey(a)if a.rs==nil then return a.id end;return a.id.."#"..
tostring(math.floor(a.rs))end;function g.inPath(a,b)
for d,c in ipairs(a.path or{})do if c==b then return true end end;return false end
local function i(a)local b=
tonumber(a.ttl)or 0;if b>g.MAX_TTL then b=g.MAX_TTL end;return b end
local function k(a)if type(a)~="table"then return false end;if type(a.id)~=h or
#a.id>g.MAX_ID then return false end;local c=a.path;if
c~=nil and(type(c)~=
"table"or#c>g.MAX_TTL*2)then return false end;local b=a.rs;if
b~=nil and(type(b)~="number"or
b<0 or b>g.MAX_RESEND)then return false end;return true end
local function l(a,b)local c={}for e,f in pairs(a)do c[e]=f end;local d={}
for e,f in ipairs(a.path or{})do d[e]=f end;d[#d+1]=b;c.path=d;c.ttl=i(a)-1;return c end
function g.route(a,b,c,d)
if not k(a)then return{dup=false,deliver=false,forward=false}end;if g.sawBefore(d,g.seenKey(a))then
return{dup=true,deliver=false,forward=false}end
local f=(a.to==g.BROADCAST or a.to==nil)local m=f or(c and c(a))or false
local e={dup=false,deliver=m,forward=false}if m and not f then return e end;if i(a)>0 and not g.inPath(a,b)then
e.forward=true;e.out=l(a,b)end;return e end
function g.newRouteCache(a)return{map={},order={},max=a or g.ROUTE_MAX}end
function g.learnRoute(b,a,d,c)if
not(b and a and a.from and a.from~=d)then return end;if
type(a.from)~=h or#a.from>g.MAX_ID then return end;local f=a.path;if type(f)~="table"or#f==0 or#f>
g.MAX_TTL*2 then return end
local m=f[#f]if type(m)~=h or#m>g.MAX_ID then return end
if m==d then return end;local n=#f;local e=b.map[a.from]
if e then local o=c~=nil and e.at~=nil and
(c-e.at)>g.ROUTE_TTL
if not o and n>=e.hops then return end;e.nextHop,e.hops,e.at=m,n,c;return end;b.map[a.from]={nextHop=m,hops=n,at=c}
b.order[#b.order+1]=a.from
if#b.order>b.max then local o=table.remove(b.order,1)if
o~=nil and o~=a.from then b.map[o]=nil end end end
function g.routeFor(a,b,c)local d=a and a.map[b]if not d then return nil end
if
c~=nil and d.at~=nil and(c-d.at)>g.ROUTE_TTL then a.map[b]=nil;return nil end;return d.nextHop,d.hops end;function g.invalidateRoute(a,b)if a then a.map[b]=nil end end;function g.newOutbox()return
{items={},seq=0}end
local function j(a)local b=0;for d,c in pairs(a)do
if type(c)==h then b=b+#c elseif type(c)==
"table"then if d~="path"then return math.huge end;b=b+#c*48 end end;return b end;g._envBytes=j
function g.enqueue(b,c,a,d)a=a or{}if b.items[c.id]then return false end
d=d or 0
if a.relay then local o=j(c)local n
if o==math.huge then n=false elseif a.canHold then
n=a.canHold(o)and true or false else n=o<=g.RELAY_HOLD_BYTES end;if not n then return false end;local p,m=0,nil;for r,q in pairs(b.items)do
if q.relay then p=p+1;if
not m or
(q.order or 0)< (b.items[m].order or 0)then m=r end end end;if
p>=g.RELAY_HOLD_MAX and m then b.items[m]=nil end end;b.seq=(b.seq or 0)+1
local f=a.interval or g.RETRY_EVERY;local e=a.deadline
if e==nil and a.relay then e=d+g.RELAY_HOLD end
b.items[c.id]={env=c,tries=0,nextAt=d,interval=f,deadline=e,relay=a.relay or false,order=b.seq}return true end;function g.ack(b,a)if a==nil then return false end;local c=b.items[a]~=nil
b.items[a]=nil;return c end;function g.ackRelay(b,a)local c=a~=nil and
b.items[a]
if c and c.relay then b.items[a]=nil;return true end;return false end
function g.shedRelays(b,a)a=
a or 0;local c={}for f,e in pairs(b.items)do
if e.relay then c[#c+1]={f,e.order or 0}end end
table.sort(c,function(e,f)return e[2]<f[2]end)local d=0;for e=1,#c-a do b.items[c[e][1]]=nil;d=d+1 end;return d end
function g.dueItems(b,a)a=a or 0;local c,d={},0
for f,e in pairs(b.items)do
if
e.deadline~=nil and a>=e.deadline then b.items[f]=nil;d=d+1 elseif a>=e.nextAt then e.tries=e.tries+1
e.nextAt=a+e.interval;c[#c+1]=e end end;return c,d end;function g.due(a,b)local d=g.dueItems(a,b)local c={}for e,f in ipairs(d)do c[e]=f.env end
return c end;function g.pending(a)local b=0;for c in pairs(a.items)do b=
b+1 end;return b end;return g