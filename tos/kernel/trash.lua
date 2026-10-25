local z,A="no session","trash not initialized"local s={}local p=nil;local B=nil;local q=nil;local r=nil
local v=nil;local t=4*1024*1024;local x=256;local u=".trashmeta"
function s.init(a)p=a.securefs;B=a.fs
q=a.users;r=a.log
v=a.serialize or require("kernel.serialize")
if a.config and a.config.get then local b=a.config.get("trashMaxMB")
if
type(b)=="number"and b>0 then t=math.floor(b*1024*1024)end;local c=a.config.get("trashMaxItems")if
type(c)=="number"and c>0 then x=math.floor(c)end end end
local function w(a)if not a then return nil end;if
a.isKernel or a.isGuest or a.user=="guest"then return nil end;local b=a.home;if
type(b)~="string"or b==""or b=="/"then return nil end
return b.."/.trash"end
local function C(a)local b=w(a)if not b or not p then return nil end;if not p.exists(b,a)then
p.makeDirectory(b,a)end;return b end
local function y(b,a)local d=p.list(b,a)if type(d)~="table"then return{}end;local c={}
for f,e in ipairs(d)do
local g=e:gsub("/$","")
if not g:find(u,1,true)then local h={name=g,path=b.."/"..g}
local i=h.path..u;if p.exists(i,a)then local j=p.readFile(i,a)
if j then
local l,k=pcall(v.decode,j,{maxBytes=4096})if l and type(k)=="table"then h.meta=k end end end;h.size=
p.size(h.path,a)or 0;c[#c+1]=h end end;return c end
local function D(d,a,b,c)local f=y(d,a)
table.sort(f,function(h,i)
local j=h.meta and h.meta.deletedAt or 0;local k=i.meta and i.meta.deletedAt or 0;if j==k then return
h.name<i.name end;return j<k end)local e=0;for i,h in ipairs(f)do e=e+h.size end;local g=#f
for i,h in ipairs(f)do if
(b<=0 and c<=0)and e<=t and g<=x then break end
p.remove(h.path..u,a)p.remove(h.path,a)e=e-h.size;g=g-1;b=b-h.size;c=c-1;if r then
r.info("trash",
"Auto-purged: ".. (h.meta and h.meta.origin or h.name))end end end
function s.put(b,a)if not p then return false,A end;a=a or
(q and q.currentSession())or nil
if not a then return false,z end;local e=C(a)
if not e then return false,"no trash for this session"end;local c=p.normalize(b)if not p.exists(c,a)then
return false,"source not found: "..c end;local function l(F)
return F:match("([^/]+)/?$")or"unnamed"end;local m=l(c)local i=
(os.time and os.time())or 0
local j=m.."~"..tostring(i)local d=e.."/"..j;local g=1;while p.exists(d,a)do d=e.."/"..j.."~"..g
g=g+1 end;local f=p.size(c,a)or 0
if f>t then return false,"file too large for trash ("..f..
" > "..t..")"end;D(e,a,f,1)local h,k=p.rename(c,d,a)if not h then h,k=p.copy(c,d,a)
if h then
p.remove(c,a)else return false,"trash move failed: "..tostring(k)end end
local n={origin=c,deletedAt=i,deletedBy=a.user,size=f}local o,E=p.writeFile(d..u,v.encode(n),a)if not o and r then
r.warn("trash",
"Couldn't write metadata for "..d..": "..tostring(E))end;if r then
r.info("trash","Trashed "..c.." -> "..d)end;return true,d end
function s.list(a)if not p then return{},A end;a=
a or(q and q.currentSession())or nil;if not a then return{},z end;local b=w(a)if not b or not
p.exists(b,a)then return{}end;local c=y(b,a)
table.sort(c,function(e,f)local g=e.meta and
e.meta.deletedAt or 0;local h=
f.meta and f.meta.deletedAt or 0;return g>h end)local d={}
for g,f in ipairs(c)do
d[g]={name=f.name,path=f.path,size=f.size,origin=f.meta and f.meta.origin or"?",deletedAt=f.meta and
f.meta.deletedAt or 0,deletedBy=f.meta and f.meta.deletedBy or"?"}end;return d end
function s.restore(a,b)if not p then return false,A end;b=b or{}local c=b.session or
(q and q.currentSession())or nil;if not c then return
false,z end;local h=w(c)
if not h then return false,"no trash for this session"end;local e=h.."/"..a;local f=e..u;if not p.exists(e,c)then return false,
"no such trash entry: "..a end;local d=b.dest
if not d then
if not
p.exists(f,c)then return false,
"metadata missing for "..a.." — pass an explicit dest to restore"end;local k=p.readFile(f,c)
local l,j=pcall(v.decode,k,{maxBytes=4096})
if
not l or type(j)~="table"or type(j.origin)~="string"then return false,"metadata corrupt for "..a end;d=j.origin end;d=p.normalize(d)
if p.exists(d,c)and not b.force then return false,
"destination exists; pass force=true to overwrite: "..d end;local g,i=p.rename(e,d,c)if not g then g,i=p.copy(e,d,c)
if g then p.remove(e,c)else return false,
"restore failed: "..tostring(i)end end;p.remove(f,c)
if r then r.info("trash",
"Restored "..a.." -> "..d)end;return true,d end
function s.empty(a)if not p then return false,A end;a=a or
(q and q.currentSession())or nil
if not a then return false,z end;local c=w(a)
if not c or not p.exists(c,a)then return true,0 end;local d=y(c,a)local b=0;for g,f in ipairs(d)do p.remove(f.path..u,a)if
p.remove(f.path,a)then b=b+1 end end
if r then r.info("trash",
"Emptied trash ("..b.." items)")end;return true,b end
function s.usage(a)if not p then return nil end;a=
a or(q and q.currentSession())or nil;if not a then return nil end;local b=w(a)
if not b or not
p.exists(b,a)then return{count=0,bytes=0,max_count=x,max_bytes=t}end;local d=y(b,a)local c=0;for g,f in ipairs(d)do c=c+f.size end;return
{count=#d,bytes=c,max_count=x,max_bytes=t}end
do local a=rawget(_G,"_TOS")if a and a.securefs and not p then
pcall(s.init,{securefs=a.securefs,fs=a.fs,users=a.users,log=a.logObj,serialize=v,config=a.config})end end;return s