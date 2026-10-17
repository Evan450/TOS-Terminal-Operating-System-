local C,t="aliases","string"local r={}local u=nil;local D=nil;local y=nil;local v=nil;local x=nil
local w="/etc/peer_aliases.dat"local q={}local s={}
function r.init(a)u=a.fs;D=a.securefs;y=a.users;v=a.log;x=a.serialize or
require("kernel.serialize")r._load()end
function r._load()q,s={},{}if not u or not u.exists or not u.exists(w)then
return end;local a=u.readFile(w)
if not a or#a==0 then return end;local c,b=pcall(x.decode,a,{maxBytes=16384})if not c or
type(b)~="table"then if v then
v.warn(C,"Corrupt alias file at "..w)end;return end
for e,d in
pairs(b)do if
type(e)==t and type(d)=="table"and type(d.alias)==t and type(d.address)==t then q[e]=d
s[d.address]=e end end end
local function z()if not u then return false,"fs unavailable"end;return
(u.writeFileAtomic or u.writeFile)(w,x.encode(q))end
local function A()local b,c={},{}for a,d in pairs(q)do b[a]=d end;for a,d in pairs(s)do c[a]=d end;return b,c end
local function B(a)
local b=y or(_G._TOS and _G._TOS.users)
if not b or not b.currentSession or not b.TIER then return true end;local c=b.currentSession()
if not c then return false,"no session"end;if c.isKernel then return true end
if
(c.tier or 0)< (b.TIER.ADMIN or 2)then return false,"alias "..a.." requires admin tier"end;return true end
local function E(a)if type(a)~=t then return false,"not a string"end;if#a<1 or#a>32 then return
false,"alias must be 1-32 chars"end
if not
a:match("^[%w_%-]+$")then return false,"alias must be alphanumeric + _ + -"end;return true end
local function F(a)if type(a)~=t then return false,"not a string"end;if#a<8 or#a>64 then return
false,"address looks malformed"end
if not
a:match("^[%w%-]+$")then return false,"address has odd chars"end;return true end
function r.set(b,a)local f,g=B("set")if not f then return false,g end;local h,i=E(b)
if not h then return false,i end;local j,k=F(a)if not j then return false,k end;local c=b:lower()local l,m=A()local d=q[c]if d and
d.address~=a then s[d.address]=nil end;local e=s[a]if
e and e~=c then q[e]=nil end;q[c]={alias=b,address=a}s[a]=c;local n,o=z()
if not n then q,s=l,m;return
false,"persist: "..tostring(o)end;if v then
v.info(C,string.format("aliased %s -> %s",b,a:sub(1,12).."..."))end;return true end
function r.remove(a)local d,e=B("remove")if not d then return false,e end;if type(a)~=t then return false,
"alias is not a string"end;local b=a:lower()local c=q[b]if
not c then return false,"no such alias"end;local f,g=A()q[b]=nil
s[c.address]=nil;local h,i=z()
if not h then q,s=f,g;return false,"persist: "..tostring(i)end;if v then v.info(C,"removed alias "..a)end
return true end
function r.addressOf(a)if type(a)~=t then return nil end;local b=q[a:lower()]return
b and b.address or nil end
function r.aliasOf(a)if type(a)~=t then return nil end;local b=s[a]return
b and q[b]and q[b].alias or nil end
function r.list()local a={}
for c,b in pairs(q)do a[#a+1]={alias=b.alias,address=b.address}end
table.sort(a,function(c,d)
return c.alias:lower()<d.alias:lower()end)return a end
function r.resolve(a)if type(a)~=t or a==""then return nil,"empty"end
local c=r.addressOf(a)if c then return c end;if
a:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")then return a end;local b={}for d in pairs(s)do if
d:sub(1,#a)==a then b[#b+1]=d end end;if#b==1 then return
b[1]end
if#b>1 then return nil,"ambiguous prefix matches multiple aliases"end
return nil,"no alias and no known peer matches '"..a.."'"end
function r.format(a)if type(a)~=t then return"?"end;local b=a:sub(1,8).."..."
local c=r.aliasOf(a)if c then return c.." ("..b..")"end;return b end;return r