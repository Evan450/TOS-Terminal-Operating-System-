local s={}local t=nil;local C=nil;local D=nil;local A=nil;local v=nil;local B=false;local u="/var/swap"local G=4096
local H=65536;local I=16;local x=G*1024;local w={}local y=0;local z=0
local E=setmetatable({},{__mode="k"})local function J()z=z+1;return u.."/s"..z end
function s.init(a)a=a or{}t=a.fs or t;C=
a.serialize or require("kernel.serialize")
D=a.log;A=a.config;v=a.compress or v;B=
(v and v.available and v.available())or false;if not t then
return false,"fs module required"end;if A and A.get then local b=A.get("swapMaxKB")
if
type(b)=="number"and b>0 then x=math.floor(b)*1024 end end
if t.spaceFree then
local c=(t.spaceFree(u)or
t.spaceFree("/")or 0)local b=c-H;if b<0 then b=0 end;if x>b then x=b end end;if not t.exists(u)then t.makeDirectory(u)end
s.clear()if D then
D.info("swap","Disk swap ready at "..u..
" (cap "..math.floor(x/1024).." KB"..
(B and", compressed"or"")..")")end;return true end
function s.clear()if not t then return end
if not t.exists(u)then t.makeDirectory(u)else local a=t.list(u)or
{}for c,b in ipairs(a)do local d=b:gsub("/$","")if d~=""then
pcall(t.remove,u.."/"..d)end end end;w={}y=0 end
function s.store(a,b)if not t then return false,"swap not initialized"end;if
type(a)~="string"then return false,"key must be a string"end;if b==nil then
s.free(a)return true end;local h,c=pcall(C.encode,b)if not h then return false,"serialize failed: "..
tostring(c)end;if B then
local k=v.pack(c)if k then c=k end end;local e=#c;local d=w[a]
local f=d and d.bytes or 0;if(y-f+e)>x then return false,
"swap full (cap "..math.floor(x/1024).." KB)"end;local g=
(d and d.file)or J()local i,j=t.writeFile(g,c)if not i then return false,
j or"write failed"end;y=y-f+e;w[a]={file=g,bytes=e}
return true end
function s.fetch(a)if not t then return nil end;local c=w[a]if not c then return nil end
local b=t.readFile(c.file)if not b then return nil end;if B and v and v.isPacked(b)then b=v.unpack(b)if not b then
return nil end end
local d=C.decode(b,{maxBytes=x+1024})return d end
function s.free(a)local b=w[a]if not b then return false end;pcall(t.remove,b.file)y=y-
b.bytes;w[a]=nil;return true end;function s.has(a)return w[a]~=nil end;function s.keys()local a={}
for b in pairs(w)do a[#a+1]=b end;table.sort(a)return a end
function s.usage()
local a=0;for b in pairs(w)do a=a+1 end;return{bytes=y,count=a,max=x}end
local function F(b,a)local c=type(a)
if c=="number"then return b.."n"..tostring(a)end;if c=="string"then return b.."s"..a end;return nil end
function s.table(a)a=a or{}local e=tonumber(a.hot)or I;if e<1 then e=1 end;z=z+1;local g="t"..
z..":"local b={}local c={}local d={}local function h(j)for k=1,#c do
if c[k]==j then table.remove(c,k)return end end end
local function f(j)
h(j)table.insert(c,1,j)while#c>e do local k=table.remove(c)
if k then b[k]=nil end end end
local i=setmetatable({},{__index=function(k,j)local l=F(g,j)if not l then return nil end
if b[l]~=nil then f(l)return b[l]end;local m=s.fetch(l)if m~=nil then b[l]=m;f(l)end;return m end,__newindex=function(l,j,k)
local m=F(g,j)if not m then
error("swap.table: unsupported key type "..type(j),2)end;if k==nil then s.free(m)b[m]=nil;d[m]=nil;h(m)
return end;local n,o=s.store(m,k)if not n then
error("swap.table: "..tostring(o),2)end;d[m]=j;b[m]=k;f(m)end,__len=function()
local j=0;for k in pairs(d)do j=j+1 end;return j end,__pairs=function(j)local k={}for m,n in
pairs(d)do k[#k+1]={s=m,k=n}end;local l=0;return
function()l=l+1;local m=k[l]
if not m then return nil end;local n=b[m.s]if n==nil then n=s.fetch(m.s)end;return m.k,n end end})E[i]={keyset=d}return i end
function s.freeTable(a)local b=E[a]if not b then return false,"not a swap table"end;for c in
pairs(b.keyset)do s.free(c)end;E[a]=nil;return true end;s.SWAP_DIR=u;return s