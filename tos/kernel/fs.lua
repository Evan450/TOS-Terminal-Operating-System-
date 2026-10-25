local r,q="No filesystem","invalid path"local z=require("component")local n={}
local p={}local v=nil;function n.init(a)v=a;p["/"]=v end
function n.normalize(a)
if a==nil or a==""then return"/"end;if type(a)~="string"then return nil end
if a:find("\0",1,true)then return nil end;a=a:gsub("\\","/")if a:sub(1,1)~="/"then a="/"..a end
local b={}for d in a:gmatch("[^/]+")do
if d==".."then b[#b]=nil elseif d~="."then b[#b+1]=d end end
local c="/"..table.concat(b,"/")return c end
function n.split(a)a=n.normalize(a)if not a then return nil,nil end
local b,c=a:match("^(.-)([^/]+)$")if not b or b==""then b="/"end;return b,c or""end;function n.join(...)local a={...}
return n.normalize(table.concat(a,"/"))end
function n.mount(a,b)a=n.normalize(a)if not a then return false,
"invalid mount path"end;if p[a]then
return false,"Already mounted at "..a end
if a~="/"and n.exists(a)then
if n.isDirectory(a)then
local c=n.list(a)
if type(c)=="table"and#c>0 then return false,
"Refusing to mount over non-empty directory: "..a end else return false,"Mount path is a file, not a directory: "..a end end;p[a]=b;return true end
function n.unmount(a)a=n.normalize(a)if not a then return false,q end;if a=="/"then
return false,"Cannot unmount root"end;local b=p[a]p[a]=nil
if type(b)=="table"and type(b.unmount)==
"function"then pcall(b.unmount)end;return true end
local function o(a)a=n.normalize(a)if not a then return nil end;local d="/"local c=1;for e in pairs(p)do
if#e>c then if
e=="/"or(a:sub(1,
#e)==e and
(#a==#e or a:sub(#e+1,#e+1)=="/"))then d=e;c=#e end end end
local b=a:sub(c+1)if b==""then b="/"end;if b:sub(1,1)~="/"then b="/"..b end;return p[d],b end
local function t(a)local b=n.normalize(a)if not b then return nil end
local c=b=="/"and"/"or b.."/"local d=nil;for e in pairs(p)do
if e~=b and#e>#c and e:sub(1,#c)==c then
local f=e:sub(#c+1):match("^[^/]+")if f then d=d or{}d[f.."/"]=true end end end;return d end
function n.exists(a)local b,d=o(a)if not b then return false end;local e,c=pcall(b.exists,d)if e and c then return
c end;return t(a)~=nil end
function n.isDirectory(a)local b,d=o(a)if not b then return false end
local e,c=pcall(b.isDirectory,d)if e and c then return c end;return t(a)~=nil end
function n.list(a)local c,e=o(a)if not c then return{}end;local f,b=pcall(c.list,e)if not f or
type(b)~="table"then b={}end;local d=t(a)
if d then local g,i={},{}for k,j in ipairs(b)do
g[#g+1]=j
i[(tostring(j):gsub("/$",""))]=true end;local h={}
for j in pairs(d)do if not
i[(j:gsub("/$",""))]then h[#h+1]=j end end;table.sort(h)for k,j in ipairs(h)do g[#g+1]=j end;return g end;return b end
function n.makeDirectory(a)local c=n.normalize(a)if not c then return false,q end;if c=="/"then return false,
"already exists"end;local b,d="",false
for e in c:gmatch("[^/]+")do
b=b.."/"..e
if n.exists(b)then if not n.isDirectory(b)then
return false,"not a directory: "..b end;d=false else local f,h=o(b)
if not f then return false,r end;local i,g=pcall(f.makeDirectory,h)
if not i then return false,tostring(g)end
if g==false then return false,"could not create "..b end;d=true end end;if not d then return false,"already exists"end;return true end
function n.remove(a)a=n.normalize(a)if not a then return false,q end;if p[a]then return false,
"Cannot delete a mount point (use umount)"end;local b,d=o(a)if
not b then return false,r end;local e,c=pcall(b.remove,d)if not e then
return false,tostring(c)end;return c end
function n.rename(a,b)a=n.normalize(a)b=n.normalize(b)
if not a or not b then return false,q end;if p[a]then return false,"Cannot rename a mount point"end
local c,e=o(a)local f,g=o(b)if not c then return false,"Source not found"end;if c~=f then return false,
"Cannot rename across filesystems"end
local h,d=pcall(c.rename,e,g)if not h then return false,tostring(d)end;return d end;function n.size(a)local b,c=o(a)if not b then return 0 end;local d,e=pcall(b.size,c)
return d and e or 0 end
function n.lastModified(a)local b,c=o(a)if not b then
return 0 end;local d,e=pcall(b.lastModified,c)return d and e or 0 end;local s=nil
local function w()if s==nil then local b,a=pcall(require,"kernel.process")
s=(b and a and
a.yieldCooperative)and a or false end;if s then
s.yieldCooperative()end end
function n.readFile(a)local b,e=o(a)if not b then return nil,r end;local g,h=pcall(b.exists,e)if not g or
not h then return nil,"File not found: "..a end
local d,i=b.open(e,"r")if not d then return nil,i end;local c={}
local j,f=pcall(function()repeat local k=b.read(d,4096)
if k then c[#c+1]=k end until not k;return table.concat(c)end)b.close(d)c=nil;if not j then return nil,tostring(f)end;return f end
local function u(a,b,c)local f,d,e=pcall(a.write,b,c)
if not f then return false,tostring(d)end;if d==false or(d==nil and e~=nil)then return false,
tostring(e or"write refused")end;return true end
function n.writeFile(a,b)local c,f=o(a)if not c then return false,r end
local d=f:match("^(.+)/[^/]+$")
if d and d~=""then local j,k=pcall(c.isDirectory,d)if not j or not k then
pcall(c.makeDirectory,d)end end;local e,g=c.open(f,"w")if not e then return false,g end;local h,i=u(c,e,b)
c.close(e)
if not h then return false,"Write failed: "..tostring(i)end;return true end
function n.appendFile(a,b)local c,e=o(a)if not c then return false,r end;local d,f=c.open(e,"a")if not d then
return false,f end;local g,h=u(c,d,b)c.close(d)if not g then return false,
"Write failed: "..tostring(h)end;return true end;local x=".tos-tmp"
function n.writeFileAtomic(a,b)a=n.normalize(a)if not a then return false,q end
local c=a..x;local d,e=n.writeFile(c,b)if not d then pcall(n.remove,c)return false,
e or"temp write failed"end;if n.exists(a)then
pcall(n.remove,a)
if n.exists(a)then pcall(n.remove,c)return false,"cannot replace target"end end
local f,g=n.rename(c,a)
if not f then return false,"rename failed: "..tostring(g)end;return true end
function n.recoverAtomic(a)local b,c=0,0
for e,d in ipairs(a or{})do d=n.normalize(d)
if d then local f=d..x
if n.exists(f)then if
n.exists(d)then pcall(n.remove,f)c=c+1 else local g,h=pcall(n.rename,f,d)
if g and h then b=b+1 end end end end end;return b,c end;local y=4096
function n.copyFile(a,b)a=n.normalize(a)b=n.normalize(b)if not a or not b then
return false,q end;if a==b then return true end;local c,h=o(a)local d,i=o(b)if
not c or not d then return false,r end;local j,k=pcall(c.exists,h)if not j or not k then return
false,"File not found: "..a end
local e=i:match("^(.+)/[^/]+$")
if e and e~=""then local C,D=pcall(d.isDirectory,e)if not C or not D then
pcall(d.makeDirectory,e)end end;local f,l=c.open(h,"r")if not f then return false,l end
local g,m=d.open(i,"w")if not g then pcall(c.close,f)return false,m end
local A,B=pcall(function()while true do
local C=c.read(f,y)if not C then return end;local D,E=u(d,g,C)
if not D then error(tostring(E),0)end;w()end end)pcall(c.close,f)pcall(d.close,g)
if not A then return false,tostring(B)end;return true end
function n.copy(a,b)a=n.normalize(a)b=n.normalize(b)
if not a or not b then return false,q end;if n.isDirectory(a)then return n.copyRecursive(a,b)end;return
n.copyFile(a,b)end
function n.copyRecursive(a,b)a=n.normalize(a)b=n.normalize(b)
if not a or not b then return false,q end
if not n.exists(a)then return false,"Source not found: "..a end;if not n.isDirectory(a)then return n.copy(a,b)end
if a=="/"or
b==a or b:sub(1,#a+1)==a.."/"then return false,
"Cannot copy a directory into itself"end;if not n.exists(b)then local f,g=n.makeDirectory(b)
if not f then return false,"Cannot create directory: "..
tostring(g)end end
local e=n.list(a)if not e then return false,"Cannot list source directory"end
local d,c=0,0
for g,f in ipairs(e)do w()local h=f:match("^(.-)/?$")or f
if h~=""then
local i=n.join(a,h)local j=n.join(b,h)
if n.isDirectory(i)then local k,l=n.copyRecursive(i,j)if k then d=d+1 else c=
c+1 end else if n.copyFile(i,j)then d=d+1 else c=c+1 end end end end;if c>0 then
return false,string.format("Copied %d items, %d failed",d,c)end;return true end
function n.open(a,b)local c,e=o(a)if not c then return nil,r end;local d,f=c.open(e,b or"r")if not d then return
nil,f end
return
{handle=d,proxy=c,read=function(h,g)return c.read(d,g or 4096)end,write=function(h,g)return
c.write(d,g)end,close=function(g)return c.close(d)end,seek=function(i,g,h)
return c.seek(d,g,h)end}end
function n.spaceTotal(a)local b=o(a or"/")if not b then return 0 end
local c,d=pcall(b.spaceTotal)return c and d or 0 end
function n.spaceUsed(a)local b=o(a or"/")if not b then return 0 end
local c,d=pcall(b.spaceUsed)return c and d or 0 end
function n.spaceFree(a)return n.spaceTotal(a)-n.spaceUsed(a)end
function n.mounts()local a={}
for c,b in pairs(p)do local d="Unnamed"
pcall(function()d=b.getLabel()or"Unnamed"end)local e,f=0,0
pcall(function()e=b.spaceTotal()end)pcall(function()f=b.spaceUsed()end)
local g=nil;if
type(b)=="table"and type(b.openHandles)=="function"then local i,h=pcall(b.openHandles)
if i and type(h)=="number"then g=h end end
a[#a+1]={mountPoint=c,label=d,address=b.address,total=e,used=f,openFiles=g}end;return a end;return n