local g=require("kernel.serialize")local e={}
local function h(a)local b=0x811C9DC5;for c=1,#a do b=
(b~a:byte(c))&0xFFFFFFFF
b=(b*0x01000193)&0xFFFFFFFF end;return b end
function e.makePool(a)local b={}
b.address=a[1]and a[1].address or"jbod"
function b.getLabel()return"JBOD("..tostring(#a)..")"end;function b.isReadOnly()
for k,j in ipairs(a)do if j.isReadOnly()then return true end end;return false end;function b.spaceTotal()local j=0
for l,k in
ipairs(a)do j=j+ (k.spaceTotal()or 0)end;return j end
function b.spaceUsed()local j=0;for l,k in ipairs(a)do j=j+ (
k.spaceUsed()or 0)end;return j end;function b.exists(j)
for l,k in ipairs(a)do if k.exists(j)then return true end end;return false end;function b.isDirectory(j)
for l,k in ipairs(a)do if
k.exists(j)and k.isDirectory(j)then return true end end;return false end
function b.size(j)for l,k in
ipairs(a)do
if k.exists(j)and not k.isDirectory(j)then return k.size(j)end end;return 0 end
function b.lastModified(j)local k=0
for m,l in ipairs(a)do if l.exists(j)then local n=l.lastModified(j)or 0;if
n>k then k=n end end end;return k end
function b.list(j)local l={}local k={}
for o,n in ipairs(a)do local m;local q,p=pcall(n.list,j)if
q and type(p)=="table"then m=p end
if m then for o,r in ipairs(m)do local s=r:gsub("/$","")if not l[s]then l[s]=true
k[#k+1]=r end end end end;return k end
function b.makeDirectory(j)local k=false
for m,l in ipairs(a)do if not l.exists(j)then
local n=pcall(l.makeDirectory,j)if n then k=true end else k=true end end;return k end
local function d(j)for o,n in ipairs(a)do
if n.exists(j)and not n.isDirectory(j)then return n end end;local k,l=nil,-1;for o,n in ipairs(a)do
if
not n.isReadOnly()then local p=n.spaceTotal()or 0;local q=n.spaceUsed()or 0
local m=p-q;if m>l then l=m;k=n end end end
return k end
local function i(j,k)local l={member=j,h=k}
function l:read(m)return self.member.read(self.h,m)end
function l:write(m)return self.member.write(self.h,m)end
function l:close()return self.member.close(self.h)end
function l:seek(m,n)return self.member.seek(self.h,m,n)end;return l end
function b.open(k,j)j=j or"r"
if j:find("[wa]")or j:find("%+")then local l=d(k)if not l then return nil,
"no writable pool member"end;local m,n=l.open(k,j)if not m then
return nil,n end;return i(l,m)end;for m,l in ipairs(a)do
if l.exists(k)and not l.isDirectory(k)then
local n,o=l.open(k,j)if not n then return nil,o end;return i(l,n)end end;return nil,
"file not found in pool"end
function b.read(j,k)return j and j.member.read(j.h,k)end
function b.write(j,k)return j and j.member.write(j.h,k)end
function b.close(j)return j and j.member.close(j.h)end
function b.seek(j,k,l)return j and j.member.seek(j.h,k,l)end
function b.remove(j)local k=false;local l=true;for o,n in ipairs(a)do
if n.exists(j)then k=true;local m=pcall(n.remove,j)if
not m or n.exists(j)then l=false end end end
if not k then return false end;return l end
function b.rename(j,k)local l=nil
for r,q in ipairs(a)do if q.exists(j)then l=q;break end end;if not l then return false,"source not found in pool"end;local m=d(k)if
l==m then return l.rename(j,k)end;if l.isDirectory(j)then return false,
"cross-member directory rename not supported"end
local n=l.open(j,"r")if not n then return false,"cannot open source"end;local o={}repeat
local q=l.read(n,4096)if q then o[#o+1]=q end until not q;l.close(n)
local p=m.open(k,"w")if not p then return false,"cannot open dest"end
m.write(p,table.concat(o))m.close(p)pcall(l.remove,j)return true end;local c={}function c.members()return a end;function c.addMember(j)a[#a+1]=j end;function c.removeMember(j)
for k,l in
ipairs(a)do if l.address==j then table.remove(a,k)return true end end;return false end
function c.stats()
local j={members=#a,total=0,used=0,free=0}
for l,k in ipairs(a)do
j.total=j.total+ (k.spaceTotal()or 0)j.used=j.used+ (k.spaceUsed()or 0)end;j.free=j.total-j.used;return j end;return b,c end;local f="/etc/jbod.cfg"
function e.loadConfig(a)if not a.exists(f)then return nil end
local b=a.readFile(f)if not b then return nil end
local d,c=pcall(g.decode,b,{maxBytes=8192})if not d or type(c)~="table"then return nil end;return c end;function e.saveConfig(a,b)return
(a.writeFileAtomic or a.writeFile)(f,g.encode(b))end
e.CONFIG_PATH=f;return e