local G="no_such_key"local u={}local B=3600;local H=86400;local L=".index"local I=192;local M=8;local v,E,C,J;local z,D
local A=0;local F;local w={}local x=0
function u.init(a)a=a or{}
v=a.fs or require("kernel.fs")E=a.computer or require("computer")C=a.serialize or
require("kernel.serialize")J=a.log or
{info=function()end,warn=function()end,error=function()end}
z=(a.root or
"/var/cluster-store"):gsub("/+$","")D=a.capacity or 0;F=a.leaseFn;w,x,A={},0,0;if v.makeDirectory then
pcall(v.makeDirectory,z)end;u.loadIndex()return true end;local function y()return E and E.uptime()or 0 end
function u.validateKey(a)
if
type(a)~="string"or a==""then return nil,"invalid_key: empty"end;if#a>I then return nil,"invalid_key: too long"end;if
a:sub(1,1)=="/"then return nil,"invalid_key: absolute"end;if
a:sub(-1)=="/"then return nil,"invalid_key: trailing separator"end;if
a:find("//")then return nil,"invalid_key: empty segment"end;local b={}
for c in
a:gmatch("[^/]+")do
if c==".."or c=="."then return nil,"invalid_key: relative segment"end;if not c:match("^[%w_%-%.]+$")then return nil,
"invalid_key: bad character in '"..c.."'"end
b[#b+1]=c end
if#b<2 then return nil,"invalid_key: needs <namespace>/<path>"end;if#b>M then return nil,"invalid_key: too deep"end;return b end
function u.pathFor(a)local b,c=u.validateKey(a)if not b then return nil,c end;return z.."/"..
table.concat(b,"/")end;function u.indexPath()return z.."/"..L end
function u.saveIndex()if not(v and C)then return false,
"not_initialized"end
local d=C.encode({index=w,used=x})local a,b=u.indexPath(),u.indexPath()..".tmp"local c;if v.writeFile then
c=v.writeFile(b,d)else local e=v.open(b,"w")
if e then e:write(d)e:close()c=true end end;if not c then
return false,"write_failed: index"end;if v.exists and v.exists(a)and v.remove then
pcall(v.remove,a)end
if v.rename then local e,f=v.rename(b,a)if not e then return false,"rename_failed: "..
tostring(f)end end;return true end
function u.loadIndex()w,x={},0
if not
(v and v.exists and v.exists(u.indexPath()))then return true,"cold_start"end
local b=v.readFile and v.readFile(u.indexPath())if not b or b==""then return true,"cold_start"end
local c,a=pcall(C.decode,b,{maxBytes=65536})
if
not c or type(a)~="table"or type(a.index)~="table"then
J.error("cluster.store","index unreadable; refusing to run with an empty one")return false,"decode_failed: index"end;w=a.index;x=tonumber(a.used)or 0;return true,"loaded"end
function u.capacity()if D and D>0 then return D end;if v and v.spaceTotal then
return v.spaceTotal(z)or 0 end;return 0 end;function u.used()return x end;function u.free()
return math.max(0,u.capacity()-x)end
local function N()if F then return F()end;A=A+1;return
string.format("%04x%02x",(math.floor(y()*
100)+A)%0xFFFF,A%0xFF)end
local function K(a,b)local c=a+ (b or B)local d=y()+H;return c>d and d or c end
function u.evict(a)local b=0;local d=y()for f,e in pairs(w)do
if e.expires_at and e.expires_at<=d then
local g=e.size or 0;if u._delete(f)then b=b+g end end end;if b>= (a or 0)then
return b end;local c={}for f,e in pairs(w)do
c[#c+1]={key=f,at=e.last_access or e.created or 0}end
table.sort(c,function(e,f)
if e.at~=f.at then return e.at<f.at end;return e.key<f.key end)
for f,e in ipairs(c)do if b>= (a or 0)then break end
local g=(w[e.key]or{}).size or 0;if u._delete(e.key)then b=b+g end end;return b end
function u._delete(a)local c=w[a]if not c then return false end;local b=u.pathFor(a)if b and v.exists and
v.exists(b)then pcall(v.remove,b)end;x=math.max(0,
x- (c.size or 0))w[a]=nil;return true end
function u.sweep()local b,a=y(),0
for d,c in pairs(w)do if c.expires_at and c.expires_at<=b then
if u._delete(d)then a=a+1 end end end;if a>0 then u.saveIndex()end;return a end
function u.put(a,c,b)b=b or{}local e,m=u.pathFor(a)if not e then return nil,m end;if
type(c)~="string"then return nil,"invalid_data: not a string"end
local d=w[a]
if d and b.overwrite==false then return nil,"exists: "..a end;local g=#c;local f=g- ((d and d.size)or 0)if f>
u.free()then u.evict(f-u.free())
if f>u.free()then return nil,"out_of_space: need "..f..", free "..
u.free()end end
local k=e:match("(.+)/[^/]+$")
if k and v.makeDirectory then pcall(v.makeDirectory,k)end;local h=e..".tmp"local i
if v.writeFile then i=v.writeFile(h,c)else local n=v.open(h,"w")if n then
n:write(c)n:close()i=true end end;if not i then return nil,"write_failed: "..a end
if v.exists and
v.exists(e)and v.remove then pcall(v.remove,e)end
if v.rename then local n,o=v.rename(h,e)if not n then
return nil,"rename_failed: "..tostring(o)end end;local j=y()
local l=(d and b.keep_lease)and d.lease_id or N()
w[a]={lease_id=l,expires_at=K(j,b.ttl and b.ttl>0 and b.ttl or B),size=g,created=(
d and d.created)or j,last_access=j}x=x+f;u.saveIndex()
return{key=a,lease_id=l,expires_at=w[a].expires_at,size_bytes=g}end
function u.get(a)local c,e=u.pathFor(a)if not c then return nil,e end;local b=w[a]
if not b then return nil,G end
if not(v.exists and v.exists(c))then w[a]=nil;x=math.max(0,x-
(b.size or 0))return nil,G end
if not b.expires_at or b.expires_at>y()then b.last_access=y()end;local d=v.readFile and v.readFile(c)if d==nil then
return nil,"read_failed: "..a end;return d end;function u.exists(a)return w[a]~=nil end
function u.list(a,b)a=a or""local c={}for d,e in pairs(w)do
if
d:sub(1,#a)==a then c[#c+1]={key=d,size=e.size,expires_at=e.expires_at}end end;table.sort(c,function(d,e)
return d.key<e.key end)if
b and#c>b then local d={}for e=1,b do d[e]=c[e]end;return d,true end;return c,
false end
function u.extend(a,b,c)local d=w[a]if not d then return nil,G end
if d.lease_id~=b then return nil,"lease_mismatch"end;d.expires_at=K(y(),c or B)d.last_access=y()u.saveIndex()return
{key=a,expires_at=d.expires_at}end
function u.release(a,b)local c=w[a]if not c then return nil,G end;if c.lease_id~=b then
return nil,"lease_mismatch"end;u._delete(a)u.saveIndex()return
{key=a,released=true}end
function u.stats()local a=0;for b in pairs(w)do a=a+1 end;return
{keys=a,used_bytes=x,capacity_bytes=u.capacity(),free_bytes=u.free(),root=z}end
u._internal={DEFAULT_TTL=B,MAX_LEASE=H,MAX_KEY=I,index=function()return w end,setUsed=function(a)x=a end}return u