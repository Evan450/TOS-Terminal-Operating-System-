local B,D,C="no session","string","trash not initialized"local u={}local r=nil;local E=nil
local s=nil;local t=nil;local x=nil;local v=4*1024*1024;local A=256;local w=".trashmeta"
function u.init(a)r=a.securefs
E=a.fs;s=a.users;t=a.log
x=a.serialize or require("kernel.serialize")
if a.config and a.config.get then local b=a.config.get("trashMaxMB")
if
type(b)=="number"and b>0 then v=math.floor(b*1024*1024)end;local c=a.config.get("trashMaxItems")if
type(c)=="number"and c>0 then A=math.floor(c)end end end
local function y(a)if not a then return nil end;if
a.isKernel or a.isGuest or a.user=="guest"then return nil end;local b=a.home;if type(b)~=D or b==""or b==
"/"then return nil end;return b.."/.trash"end
local function F(a)local b=y(a)if not b or not r then return nil end;if not r.exists(b,a)then
r.makeDirectory(b,a)end;return b end
local function z(b,a)local d=r.list(b,a)if type(d)~="table"then return{}end;local c={}
for f,e in ipairs(d)do
local g=e:gsub("/$","")
if not g:find(w,1,true)then local h={name=g,path=b.."/"..g}
local i=h.path..w;if r.exists(i,a)then local j=r.readFile(i,a)
if j then
local l,k=pcall(x.decode,j,{maxBytes=4096})if l and type(k)=="table"then h.meta=k end end end;h.size=
r.size(h.path,a)or 0;c[#c+1]=h end end;return c end
local function G(d,a,b,c)local f=z(d,a)
table.sort(f,function(h,i)
local j=h.meta and h.meta.deletedAt or 0;local k=i.meta and i.meta.deletedAt or 0;if j==k then return
h.name<i.name end;return j<k end)local e=0;for i,h in ipairs(f)do e=e+h.size end;local g=#f
for i,h in ipairs(f)do if
(b<=0 and c<=0)and e<=v and g<=A then break end
r.remove(h.path..w,a)r.remove(h.path,a)e=e-h.size;g=g-1;b=b-h.size;c=c-1;if t then
t.info("trash",
"Auto-purged: ".. (h.meta and h.meta.origin or h.name))end end end
function u.put(b,a)if not r then return false,C end;a=a or
(s and s.currentSession())or nil
if not a then return false,B end;local e=F(a)
if not e then return false,"no trash for this session"end;local c=r.normalize(b)if not r.exists(c,a)then
return false,"source not found: "..c end;local function l(q)
return q:match("([^/]+)/?$")or"unnamed"end;local m=l(c)local i=
(os.time and os.time())or 0
local j=m.."~"..tostring(i)local d=e.."/"..j;local g=1;while r.exists(d,a)do d=e.."/"..j.."~"..g
g=g+1 end;local f=r.size(c,a)or 0
if f>v then return false,"file too large for trash ("..f..
" > "..v..")"end;G(e,a,f,1)local h,k=r.rename(c,d,a)if not h then h,k=r.copy(c,d,a)
if h then
r.remove(c,a)else return false,"trash move failed: "..tostring(k)end end
local n={origin=c,deletedAt=i,deletedBy=a.user,size=f}local o,p=r.writeFile(d..w,x.encode(n),a)if not o and t then
t.warn("trash",
"Couldn't write metadata for "..d..": "..tostring(p))end;if t then
t.info("trash","Trashed "..c.." -> "..d)end;return true,d end
function u.list(a)if not r then return{},C end;a=
a or(s and s.currentSession())or nil;if not a then return{},B end;local b=y(a)if not b or not
r.exists(b,a)then return{}end;local c=z(b,a)
table.sort(c,function(e,f)local g=e.meta and
e.meta.deletedAt or 0;local h=
f.meta and f.meta.deletedAt or 0;return g>h end)local d={}
for g,f in ipairs(c)do
d[g]={name=f.name,path=f.path,size=f.size,origin=f.meta and f.meta.origin or"?",deletedAt=f.meta and
f.meta.deletedAt or 0,deletedBy=f.meta and f.meta.deletedBy or"?"}end;return d end
local function H(b,a,c)if r.exists(b.."/"..a,c)then return a end;local d={}
for g,f in ipairs(z(b,c))do local e=f.meta and
f.meta.origin;if
type(e)==D and e:match("[^/]+$")==a then d[#d+1]=f.name end end;if#d==1 then return d[1]end;if#d==0 then
return nil,"no such trash entry: "..a end;table.sort(d)
return nil,"several trash entries are named "..a..": "..
table.concat(d,", ")end
function u.restore(a,b)if not r then return false,C end;b=b or{}local c=b.session or
(s and s.currentSession())or nil;if not c then return
false,B end;local f=y(c)
if not f then return false,"no trash for this session"end;local i,k=H(f,a,c)if not i then return false,k end;a=i;local e=f.."/"..a;local g=e..w
local d=b.dest
if not d then
if not r.exists(g,c)then return false,"metadata missing for "..
a.." — pass an explicit dest to restore"end;local m=r.readFile(g,c)
local n,l=pcall(x.decode,m,{maxBytes=4096})
if
not n or type(l)~="table"or type(l.origin)~=D then return false,"metadata corrupt for "..a end;d=l.origin end;d=r.normalize(d)
if r.exists(d,c)and not b.force then return false,
"destination exists; pass force=true to overwrite: "..d end;local h,j=r.rename(e,d,c)if not h then h,j=r.copy(e,d,c)
if h then r.remove(e,c)else return false,
"restore failed: "..tostring(j)end end;r.remove(g,c)
if t then t.info("trash",
"Restored "..a.." -> "..d)end;return true,d end
function u.empty(a)if not r then return false,C end;a=a or
(s and s.currentSession())or nil
if not a then return false,B end;local c=y(a)
if not c or not r.exists(c,a)then return true,0 end;local d=z(c,a)local b=0;for g,f in ipairs(d)do r.remove(f.path..w,a)if
r.remove(f.path,a)then b=b+1 end end
if t then t.info("trash",
"Emptied trash ("..b.." items)")end;return true,b end
function u.usage(a)if not r then return nil end;a=
a or(s and s.currentSession())or nil;if not a then return nil end;local b=y(a)
if not b or not
r.exists(b,a)then return{count=0,bytes=0,max_count=A,max_bytes=v}end;local d=z(b,a)local c=0;for g,f in ipairs(d)do c=c+f.size end;return
{count=#d,bytes=c,max_count=A,max_bytes=v}end
do local a=rawget(_G,"_TOS")if a and a.securefs and not r then
pcall(u.init,{securefs=a.securefs,fs=a.fs,users=a.users,log=a.logObj,serialize=x,config=a.config})end end;return u