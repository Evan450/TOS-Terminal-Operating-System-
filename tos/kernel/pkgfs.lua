local M="kernel.cowfs"local x={}local B="/var/pkg/archive"local E,C;local v;local y,z={},{}local A={}local J
x.DIR=B
local function N()local a=_G._TOS and _G._TOS.kernel;return a and a.getCompress and
a.getCompress()or nil end;function x.entry(a,b)
return"\255\255\1"..string.pack(">I2",#a)..
a..string.pack(">I8",#b)..b end
local function F(b,c,a)local e,d={},0
while d<a do
local f=b.read(c,math.min(a-d,4096))if not f then break end;e[#e+1]=f;d=d+#f end;return table.concat(e)end
function x.scan(a,b,c)local d,h=a.open(b,"r")if not d then return nil,h end;local e=0;local f,g=true,nil
while true do
local i=F(a,d,5)if#i==0 then break end
if#i<5 or i:sub(1,3)~="\255\255\1"then f,g=false,
"not an mtar v1 archive at byte "..e;break end;local k=string.unpack(">I2",i,4)local j=F(a,d,k)local m=F(a,d,8)
if#j<k or
#m<8 then f,g=false,"truncated at byte "..e;break end;local l=string.unpack(">I8",m)e=e+5+k+8;for n in j:gmatch("[^/]+")do
if
n==".."then f,g=false,"unsafe path in archive: "..j end end;if not f then break end;c(j,e,l,d)
a.seek(d,"cur",l)e=e+l end;a.close(d)if f then return true end;return nil,g end
local function D(a)return a:match("^(.*)/[^/]*$")or""end
local function P(b,a,c,d)local g={archive=b,offset=c,len=d}y[a]=g;local f=D(a)while f~=""do if z[f]then break end
z[f]=true;f=D(f)end;return g end
local function G(a)local d,e=v.open(A[a.archive],"r")if not d then return nil,e end
v.seek(d,"set",a.offset)local b=F(v,d,a.len)v.close(d)
if#b~=a.len then return nil,"archive is short"end;local c=N()
if b:sub(1,4)=="TCZ1"or
(c and c.isPacked and c.isPacked(b))then if not c then
return nil,"this package needs a data card to read"end;return c.unpack(b)end;return b end;local w={address="pkgfs"}function w.getLabel()return"packages"end
function w.spaceTotal()return 0 end;function w.spaceUsed()return 0 end;function w.isReadOnly()return true end
function w.exists(a)return a=="/"or
y[a]~=nil or z[a]==true end;function w.isDirectory(a)return a=="/"or z[a]==true end
function w.size(a)
local b=y[a]if not b then return 0 end;if b.size then return b.size end;local c=G(b)
b.size=c and#c or 0;return b.size end;function w.lastModified()return 0 end
function w.list(a)
local c=a=="/"and"/"or(a.."/")local d,b={},{}
local function e(f,g)
if f:sub(1,#c)==c then local i=f:sub(#c+1)
local h=i:match("^[^/]+")
if h and not d[h]then d[h]=true
local j=g or i:find("/",1,true)~=nil;b[#b+1]=h.. (j and"/"or"")end end end;for f in pairs(y)do e(f,false)end;for f in pairs(z)do e(f,true)end
table.sort(b)return b end;local H,K={},1
function w.open(a,b)
if b and b:sub(1,1)~="r"then return nil,"read-only"end;local c=y[a]if not c then return nil,a end;local d,f=G(c)if not d then return nil,f end
local e=K;K=K+1;H[e]={data=d,pos=1}return e end
function w.read(a,b)local d=H[a]if not d or d.pos>#d.data then return nil end
local e=d.data:sub(d.pos,
d.pos+ (b or 4096)-1)d.pos=d.pos+#e;return e end
function w.seek(b,a,c)local d=H[b]if not d then return nil end;local e=
a=="set"and 0 or a=="end"and#d.data or d.pos-1;d.pos=e+ (c or 0)+
1;return d.pos-1 end;function w.close(a)H[a]=nil;return true end
function w.write()return nil,"read-only"end;function w.remove()return false end;function w.rename()return false end;function w.makeDirectory()
return false end;x.lower=w
local function L()if J then return true end;local a=require(M)
local b=a.new(w,a.sub(v,"/usr"),{label="/usr+packages"})local c,d=E.mount("/usr",b,{over=true})if not c then return nil,d end
J=b;return true end
local function I(a)for b,c in pairs(y)do if c.archive==a then y[b]=nil end end;for b in
pairs(z)do z[b]=nil end;for b in pairs(y)do local c=D(b)while c~=""and not z[c]do z[c]=true
c=D(c)end end;A[a]=nil end
local function O(a,b)A[a]=b
local c,d=x.scan(v,b,function(e,f,g)P(a,e,f,g)end)if not c then I(a)end;return c,d end
function x.init(a)E,C=a.fs,a.log;v=a.raw or E.rootProxy()end
function x.boot(a)x.init(a)if not v.exists(B)then return 0 end;local b=0
for d,c in
ipairs(v.list(B)or{})do local e=c:match("^(.+)%.mtar$")
if e then local f,g=O(e,B.."/"..c)if f then b=b+1 elseif C and
C.error then
pcall(C.error,"pkgfs",e.." did not load: "..tostring(g))end end end
if b>0 then local c,d=L()if not c and C and C.error then
pcall(C.error,"pkgfs","could not mount /usr: "..tostring(d))end end;return b end;function x.has(a)return A[a]~=nil end;function x.list()local a={}
for b in pairs(A)do a[#a+1]=b end;table.sort(a)return a end
function x.compact(a,b)local c=B..
"/"..a..".mtar"if A[a]then
return nil,"already compact: "..a end
if not v.exists(B)then v.makeDirectory(B)end;local d=c..".tmp"local e,m=v.open(d,"w")if not e then return nil,m end;local g=N()
local f,i=0,false;local j={}
for t,s in ipairs(b)do local u,R=E.readFile(s)
if not u then v.close(e)v.remove(d)return nil,
"cannot read "..s..": "..tostring(R)end;f=f+#u+512;j[s:sub(5)]=u;local Q=u
if g and g.pack then local S,T=g.pack(u)if S and
T=="deflate"then Q,i=S,true end end;if not v.write(e,x.entry(s:sub(5),Q))then v.close(e)
v.remove(d)return nil,"disk full"end end;v.close(e)local k=v.size(d)+512;if k>=f then v.remove(d)return nil,
"an archive would not be smaller"end;if v.exists(c)then
v.remove(c)end;if not v.rename(d,c)then v.remove(d)
return nil,"could not put the archive in place"end;local n,o=O(a,c)local h=o
if n then for s,t in pairs(j)do
local u=y[s]local Q=u and G(u)
if Q~=t then h="read-back differs for /usr"..s;break end end end;if h then I(a)v.remove(c)return nil,h end;local p,q=L()if not p then I(a)
v.remove(c)return nil,q end;local l=require(M)local r=l.sub(v,"/usr")
for t,s in
ipairs(b)do l.unhide(r,s:sub(5))v.remove(s)end
for t,s in ipairs(b)do local u=D(s)while u~="/usr"and u~=""do local Q=v.list(u)
if not Q or#Q>0 then break end;v.remove(u)u=D(u)end end;return true,{before=f,after=k,packed=i,files=#b}end
function x.expand(a)if not A[a]then return nil,"not compact: "..a end
local f,g=L()if not f then return nil,g end;local b=require(M).sub(v,"/usr")
local d={}
for h,i in pairs(y)do if
i.archive==a and J.exists(h)and not b.exists(h)then d[h]=i end end;local e={}
local function c()for i,h in ipairs(e)do b.remove(h)end end
for h,i in pairs(d)do local k,n=G(i)
if not k then c()return nil,h..": "..tostring(n)end;local j=""for q in D(h):gmatch("[^/]+")do j=j.."/"..q;if not b.exists(j)then
b.makeDirectory(j)end end
local l=h..".tmp"local m,o=b.open(l,"w")if not m then c()return nil,o end;e[#e+1]=l
local p=b.write(m,k)b.close(m)
if not p or b.size(l)~=#k then c()return nil,"disk full"end end
for h in pairs(d)do if not b.rename(h..".tmp",h)then c()
return nil,"could not put back /usr"..h end end;return x.drop(a)end
function x.drop(a)local b=A[a]if not b then return nil,"not compact: "..a end
I(a)v.remove(b)local c=require(M)
c.sweep(c.sub(v,"/usr"),w)return true end;return x