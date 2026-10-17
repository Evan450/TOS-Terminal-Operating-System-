local y,t="keychain","no session"local o={}local s=nil;local p=nil;local n=nil;local u=nil;local q=nil
local r=setmetatable({},{__mode="k"})function o.init(a)s=a.vault or require("kernel.vault")
p=a.securefs;n=a.users
u=a.serialize or require("kernel.serialize")q=a.log end
local function v(a)if
not a or a.isKernel or a.isLogin then return nil end
if
not a.home or a.home==""or a.home=="/"then return nil end;return a.home.."/.keychain.vault"end
local function z(a,b)local d=v(a)
if not d or not p or not p.exists(d,a)then return{}end;local c=p.readFile(d,a)if not c or#c==0 then return{}end
if not
s.isEncrypted(c)then if q then
q.warn(y,"On-disk vault for "..a.user.." is malformed; ignoring")end;return nil,"keychain file malformed"end;local e,g=s.decrypt(c,b)if not e then return nil,g end
local h,f=pcall(u.decode,e,{maxBytes=65536})if not h or type(f)~="table"then
return nil,"keychain decoded but isn't a table"end;return f end
local function w(a,b,c)local d=v(a)if not d or not p then return false,"no path"end
local e=u.encode(b)
if#e>32768 then return false,"keychain too large (max 32 KB)"end;local f,g=s.encrypt(e,c,{requireStrong=true})if not f then return false,"encrypt failed: "..
tostring(g)end
return(
p.writeFileAtomic or p.writeFile)(d,f,a)end
function o.unlock(b,a)
a=a or(n and n.currentSession())or nil;if not a then return false,t end;if not s or not p then
return false,"keychain not initialized"end;local c,d=z(a,b)if not c then return false,d end
r[a]={master=b,slots=c}
if q then q.info(y,"Unlocked for "..a.user)end;return true end
function o.lock(a)
a=a or(n and n.currentSession())or nil;if not a then return end
if r[a]then local b=r[a]if b.slots then
for c in pairs(b.slots)do b.slots[c]=nil end end;b.master=nil;r[a]=nil end
if q then q.info(y,"Locked for "..a.user)end end
function o.isUnlocked(a)
a=a or(n and n.currentSession())or nil;if not a then return false end;return r[a]~=nil end
local function x(a)if not r[a]then return nil,"keychain locked"end;return r[a]end
function o.set(a,c,b)if type(a)~="string"or type(c)~="string"then return false,
"name and passphrase must be strings"end;if not
a:match("^[%w_%-%.]+$")or#a>64 then
return false,"name must be alphanum/_/-/. and <= 64 chars"end;if#c>1024 then
return false,"passphrase too long"end;b=
b or(n and n.currentSession())or nil;if not b then return false,t end
local d,e=x(b)if not d then return false,e end;local f=d.slots[a]d.slots[a]=c
local g,h=w(b,d.slots,d.master)if not g then d.slots[a]=f;return false,h end
if q then q.info(y,"Set slot '"..a..
"' for "..b.user)end;return true end
function o.get(b,a)
a=a or(n and n.currentSession())or nil;if not a then return nil,t end;local c,e=x(a)if not c then return nil,e end
local d=c.slots[b]if d==nil then return nil,"no such slot"end;return d end
function o.remove(b,a)
a=a or(n and n.currentSession())or nil;if not a then return false,t end;local c,d=x(a)if not c then return false,d end
local e=c.slots[b]c.slots[b]=nil;local f,g=w(a,c.slots,c.master)if not f then c.slots[b]=e;return false,
g end;return true end
function o.list(a)
a=a or(n and n.currentSession())or nil;if not a then return{}end;local c=r[a]if not c then return{}end;local b={}for d in pairs(c.slots)do
b[#b+1]=d end;table.sort(b)return b end
function o.rekey(c,b,a)
a=a or(n and n.currentSession())or nil;if not a then return false,t end;if not s or not p then
return false,"keychain not initialized"end;local d=v(a)if
not d or not p.exists(d,a)then return true end;local e,f=z(a,c)if not e then return false,
"rekey: "..tostring(f)end;local g,h=w(a,e,b)if not g then return false,"rekey: "..
tostring(h)end
for i,j in pairs(r)do if
type(i)=="table"and i.user==a.user then j.master=b end end;return true end;return o