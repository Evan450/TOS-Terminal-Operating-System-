local p,n="bad file handle","reserved name"local j={}local k=".cfsdel."j.WHITEOUT=k
local function l(a)
local b,c=a:match("^(.*)/([^/]*)$")if not b then return"",a end;return b,c end;local function m(a)
for b in a:gmatch("[^/]+")do if b:sub(1,#k)==k then return true end end;return false end
function j.new(b,a,c)c=c or{}
local d={}local f,i={},1;d.type="filesystem"
d.address=c.address or("cowfs:"..
tostring(b.address or"?"):sub(1,8))function d.getLabel()return c.label or"overlay"end;function d.spaceTotal()return
a.spaceTotal()end
function d.spaceUsed()return a.spaceUsed()end;function d.isReadOnly()
return a.isReadOnly and a.isReadOnly()or false end
local function g(v)local w,x=l(v)return w.."/"..k..x end;local function t(v)local w=v
while w~=""and w~="/"do if a.exists(g(w))then return true end;w=l(w)end;return false end;local function e(v)return not t(v)and
b.exists(v)==true end
function d.exists(v)if
v=="/"or v==""then return true end;if m(v)then return false end;return
a.exists(v)==true or e(v)end;function d.isDirectory(v)if v=="/"or v==""then return true end;if a.exists(v)then
return a.isDirectory(v)end
return e(v)and b.isDirectory(v)==true end
function d.size(v)if
a.exists(v)then return a.size(v)end;if e(v)then return b.size(v)end;return 0 end
function d.lastModified(v)if a.exists(v)then return a.lastModified(v)end;if e(v)then return
b.lastModified(v)end;return 0 end
function d.list(v)
if not d.exists(v)then return nil,"no such directory"end;local x,w,y={},{},{}
if a.exists(v)and a.isDirectory(v)then
for A,z in
ipairs(a.list(v)or{})do local B=z:gsub("/$","")if B:sub(1,#k)==k then y[B:sub(#k+1)]=true elseif not
x[B]then x[B]=true;w[#w+1]=z end end end;if e(v)and b.isDirectory(v)then
for A,z in ipairs(b.list(v)or{})do
local B=z:gsub("/$","")if not y[B]and not x[B]then x[B]=true;w[#w+1]=z end end end
table.sort(w)return w end;local function h(v)local w=l(v)
if w==""or w=="/"or a.exists(w)then return end;h(w)a.makeDirectory(w)
if a.exists(g(w))then a.remove(g(w))end end;local function s(v)if
a.exists(g(v))then a.remove(g(v))end end
function d.makeDirectory(v)if
m(v)then return false,n end;if d.exists(v)then return false end;h(v)s(v)return
a.makeDirectory(v)end
local function u(v)if a.exists(v)or not e(v)then return true end
local w,y=b.open(v,"r")if not w then return nil,y end;h(v)local x,z=a.open(v,"w")if not x then b.close(w)
return nil,z end;while true do local A=b.read(w,4096)if not A then break end
a.write(x,A)end;b.close(w)a.close(x)return true end
function d.open(v,w)w=w or"r"if m(v)then return nil,n end;local x,y,z
if w:sub(1,1)=="r"then if a.exists(v)then
x=a elseif e(v)then x=b else return nil,v end;y,z=x.open(v,w)else if
w:sub(1,1)=="a"then local B,C=u(v)if not B then return nil,C end end
h(v)x=a;y,z=a.open(v,w)if y then s(v)end end;if not y then return nil,z end;local A=i;i=i+1;f[A]={fs=x,h=y}return A end
function d.read(v,w)local x=f[v]if not x then return nil,p end;return x.fs.read(x.h,w)end
function d.write(v,w)local x=f[v]if not x then return nil,p end;return x.fs.write(x.h,w)end
function d.seek(v,w,x)local y=f[v]if not y then return nil,p end;return y.fs.seek(y.h,w,x)end;function d.close(v)local w=f[v]if not w then return false end;f[v]=nil
return w.fs.close(w.h)end;function d.openHandles()local v=0
for w in pairs(f)do v=v+1 end;return v end
function d.remove(v)
if v=="/"or v==""then return false end;if m(v)then return false,n end;local x=e(v)local y=d.isDirectory(v)
if y then
local z=d.list(v)if z and#z>0 then return false,"directory not empty"end end;local w=false;if a.exists(v)then w=a.remove(v)==true end
if x then
h(v)local z=a.open(g(v),"w")if not z then return false end;a.close(z)w=true end;return w end
function d.rename(v,w)if m(v)or m(w)then return false,n end;if
not d.exists(v)or d.exists(w)then return false end;if d.isDirectory(v)then if e(v)then return false,
"cannot rename a directory on the lower layer"end;return
a.rename(v,w)end
local x,y=u(v)if not x then return false,y end;h(w)
if not a.rename(v,w)then return false end;s(w)if b.exists(v)and not t(v)then local z=a.open(g(v),"w")if z then
a.close(z)end end;return true end
function d.changes()local v={}
local function w(x)
for z,y in ipairs(a.list(x)or{})do local B=y:gsub("/$","")
local A=(
x=="/"and""or x:gsub("/$","")).."/"..B
if B:sub(1,#k)==k then local C=l(A)
v[#v+1]={path=C.."/"..B:sub(#k+1),removed=true}elseif a.isDirectory(A)then w(A)else v[#v+1]={path=A}end end end;w("/")
table.sort(v,function(x,y)return x.path<y.path end)return v end;return d end
function j.wipe(b,a)a=a or"/"
for d,c in ipairs(b.list(a)or{})do local f=c:gsub("/$","")
local e=(
a=="/"and""or a:gsub("/$","")).."/"..f;if b.isDirectory(e)then j.wipe(b,e)end;b.remove(e)end end
function j.unhide(a,b)local c=b;while c~=""and c~="/"do local d,f=l(c)local e=d.."/"..k..f;if a.exists(e)then
a.remove(e)end;c=d end end
function j.sweep(b,c,a)a=a or"/"
for e,d in ipairs(b.list(a)or{})do local f=d:gsub("/$","")
local g=(a=="/"and
""or a:gsub("/$","")).."/"..f
if f:sub(1,#k)==k then local h=(a=="/"and""or a:gsub("/$","")).."/"..f:sub(
#k+1)if not
c.exists(h)then b.remove(g)end elseif b.isDirectory(g)then
j.sweep(b,c,g)end end end
function j.sub(a,b)
local function d(e)if e=="/"or e==""then return b end;return b..
(e:sub(1,1)=="/"and""or"/")..e end
local c={address=tostring(a.address)..":"..b}function c.exists(e)return a.exists(d(e))end;function c.isDirectory(e)return
a.isDirectory(d(e))end
function c.size(e)return a.size(d(e))end;function c.lastModified(e)return a.lastModified(d(e))end;function c.list(e)return
a.list(d(e))end
function c.makeDirectory(e)return a.makeDirectory(d(e))end;function c.remove(e)return a.remove(d(e))end;function c.rename(e,f)return
a.rename(d(e),d(f))end
function c.open(e,f)return a.open(d(e),f)end;c.read,c.write,c.seek,c.close=a.read,a.write,a.seek,a.close
c.spaceTotal,c.spaceUsed=a.spaceTotal,a.spaceUsed;function c.isReadOnly()
return a.isReadOnly and a.isReadOnly()or false end;return c end;j.CONFIG="/etc/overlay.cfg"local q="/tos-overlay"
local function r(a)return q.."/"..
tostring(a.address):sub(1,8)end
local function o(a,b)local c=a.open(b,"r")if not c then return nil end;local d={}while true do
local e=a.read(c,4096)if not e then break end;d[#d+1]=e end
a.close(c)return table.concat(d)end
function j.parseConfig(a)if type(a)~="string"then return nil end
local b=a:match("disk=([%x%-]+)")return b,b~=nil and a:match("reset=1")~=nil end
function j.saveConfig(a,b,c)local d=j.CONFIG..".tmp"local e,f=a.open(d,"w")
if not e then return nil,f end
local g=a.write(e,"disk="..
b.."\n".. (c and"reset=1\n"or""))a.close(e)
if not g then a.remove(d)return nil,"disk full"end;if a.exists(j.CONFIG)then a.remove(j.CONFIG)end;if not
a.rename(d,j.CONFIG)then a.remove(d)
return nil,"could not write "..j.CONFIG end;return true end
function j.boot(a,b,c)local e,f=b,false
if not e then e,f=j.parseConfig(o(a,j.CONFIG))end;if not e then return nil end;local t,d=pcall(c,e)if not t or not d then
return nil,{missing=e,reset=f}end;local g=r(a)if not d.exists(g)then
d.makeDirectory(g)end;local h=j.sub(d,g)local i=g..".drop"
local u=f or d.exists(i)if u then j.wipe(h)d.remove(i)end
local s=j.new(a,h,{address=a.address,label=
a.getLabel and a.getLabel()or nil})return s,{disk=e,reset=f,lower=a,upper=h,root=s,layerDisk=d,mark=i}end
function j.drop(a)local b,c=a.layerDisk.open(a.mark,"w")
if not b then return nil,c end;a.layerDisk.close(b)return true end
function j.merge(a)local b,d=a.lower,a.upper;local c=0
for f,e in ipairs(a.root.changes())do
if e.removed then if
b.exists(e.path)then b.remove(e.path)end else local i=l(e.path)if i~=""and not
b.exists(i)then b.makeDirectory(i)end
local s=o(d,e.path)if not s then return nil,"cannot read "..e.path end
local g=e.path..".tmp"local t,u=b.open(g,"w")if not t then return nil,tostring(u)end
local v=b.write(t,s)b.close(t)if not v or b.size(g)~=#s then b.remove(g)return nil,
"disk full at "..e.path end;if b.exists(e.path)then
b.remove(e.path)end;if not b.rename(g,e.path)then return nil,
"cannot replace "..e.path end end;c=c+1 end;return c end;return j