
local function k()return
(_G._TOS and _G._TOS.securefs)or require("kernel.securefs")end;local j=require("kernel.env")local h={}local l="/"local i={}
local m={"/mnt/","/tmp/","/public/","/home/"}
local function n(a)local c=j.read(a,"PATH")or"/usr/bin:/bin"local b={}for d in
c:gmatch("[^:]+")do b[#b+1]=d end;return b end;function h.getWorkingDirectory()return l end
function h.setWorkingDirectory(a)l=k().normalize(a)end
function h.resolve(a,b,c)if not a then return nil end;c=c or 0;local d=k()if a:sub(1,1)=="/"then if d.exists(a)then
return a end;if b and d.exists(a..b)then return a..b end
return nil end;if i[a]and c<8 then return h.resolve(i[a],b,
c+1)end;local e=d.join(l,a)if
d.exists(e)then return e end;if b and d.exists(e..b)then return e..b end
for g,f in
ipairs(n())do local o=d.join(f,a)if d.exists(o)then return o end;if b and d.exists(o..b)then return
o..b end end;return nil end
function h.execute(a,...)local b=h.resolve(a,".lua")if not b then
return false,"Program not found: "..a end;local r=(a:sub(1,1)~="/")
if r then local x=_G._TOS and
_G._TOS.users;local y=
(x and x.pathKey)and x.pathKey(b)or b:lower()
for A,z in ipairs(m)do if
y:sub(1,#z)==z then
return false,"Refusing to PATH-resolve to user-writable location: "..b end end end;local g=k().readFile(b)
if not g then return false,"Cannot read: "..b end;local o=nil;local p=nil;local s,e=pcall(require,"kernel.users")if
s and e and e.currentSession then o=e.currentSession()end
local t,f=pcall(require,"kernel.process")
if t and f and f.current then local x=f.current()if x and x.caps then p=x.caps end end;local u,c=pcall(require,"kernel.sandbox")if not u or not c then return false,
"Sandbox unavailable"end;local v=p or
{["fs.read"]=true,["compat.io"]=true}
local j=c.build{session=o,caps=v}local q,w=load(g,"="..b,"t",j)if not q then
return false,"Compile error: "..tostring(w)end
local d=table.pack(pcall(q,...))
if not d[1]and c.exitStatus then local x=c.exitStatus(d[2])if x==true or x==0 then return
true end;if x~=nil then
return false,"exited with status "..tostring(x)end end;return table.unpack(d,1,d.n)end
function h.parse(...)local c=table.pack(...)local a={}local b={}
for d=1,c.n do local e=tostring(c[d])
if
e:sub(1,2)=="--"then local f,g=e:match("^%-%-([%w_%-]+)=?(.*)")if f then b[f]=
g~=""and g or true end elseif e:sub(1,1)=="-"then for f=2,#e do
b[e:sub(f,f)]=true end else a[#a+1]=e end end;return a,b end;function h.getAlias(a)return i[a]end;function h.setAlias(a,b)i[a]=b end;function h.aliases()local a={}for b,c in
pairs(i)do a[b]=c end;return a end
function h.getPath()return
j.read(nil,"PATH")or"/usr/bin:/bin"end;function h.setPath(a)j.setDefault("PATH",a)end;return h