
local function e()return
(_G._TOS and _G._TOS.securefs)or require("kernel.securefs")end;local d={}function d.exists(a)return e().exists(a)end;function d.isDirectory(a)return
e().isDirectory(a)end;function d.makeDirectory(a)
return e().makeDirectory(a)end
function d.remove(a)return e().remove(a)end;function d.rename(a,b)return e().rename(a,b)end;function d.size(a)
return e().size(a)end
function d.lastModified(a)return e().lastModified(a)end
function d.list(a)local b,c=e().list(a)
if type(b)=="table"then local g=0;return
function()g=g+1;return b[g]end elseif type(b)=="function"then return b end;if b==nil and c~=nil then return nil,c end
return function()return nil end end
function d.open(b,a)a=a or"r"local c,g=e().open(b,a)if not c then return nil,g end;return c end;function d.copy(a,b)return e().copy(a,b)end;function d.canonical(a)
return e().normalize(a)end;function d.segments(a)local b={}
for c in a:gmatch("[^/]+")do b[#b+1]=c end;return b end;function d.path(a)
local b=a:match("^(.+/)[^/]+/?$")return b or"/"end;function d.name(a)return
a:match("([^/]+)/?$")or""end
function d.concat(...)return e().join(...)end
local function f(a,b)local h=require("component")local j,k=pcall(h.proxy,a)if not j or not k then return
nil end;local function l()
return nil,"raw filesystem access is disabled; use filesystem.open/list/etc."end;local i=false
do
local o,n=pcall(require,"kernel.users")
if o and n and n.currentSession and n.TIER then
local p=n.currentSession()if
p and(p.tier or 0)>= (n.TIER.ADMIN or 2)then i=true end end end;local c=a
if not i then local n=e()
if
n and type(n.opaqueMountId)=="function"then c=n.opaqueMountId(b,a)else
local p,o=pcall(require,"kernel.crypto")if p and o and o.hash then
c="fs:"..o.hash(b.."|"..a):sub(1,16)else c="fs:"..b end end end
local function g()local o,n=pcall(h.proxy,a)if o and n then return n end;return nil end
local m={address=c,mountPoint=b,type="filesystem",spaceTotal=function()local n=g()return n and n.spaceTotal()or 0 end,spaceUsed=function()
local n=g()return n and n.spaceUsed()or 0 end,getLabel=function()
local n=g()return n and n.getLabel()or""end,isReadOnly=function()
local n=g()return n and n.isReadOnly()or true end}
return
setmetatable(m,{__index=function(n,n)return l end,__newindex=function(n,n,n)
error("safe filesystem proxy is read-only",2)end,__metatable=false})end
function d.get(a)local g=e()a=g.normalize(a)local b,c,h=nil,nil,0
for j,i in ipairs(g.mounts())do
local k=i.mountPoint
if#k>h then if
k=="/"or(a:sub(1,#k)==k and
(#a==#k or a:sub(#k+1,#k+1)=="/"))then b=k;c=i.address;h=#k end end end;if c then local i=f(c,b)if i then return i,b end end;return nil end
function d.spaceTotal(a)return e().spaceTotal(a or"/")end;function d.spaceUsed(a)return e().spaceUsed(a or"/")end;function d.isLink()return
false end;return d