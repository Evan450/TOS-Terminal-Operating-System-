local aK="bad handle"local X={}X._VERSION="1.2.0"local aA="TBFS"local aB=1;local af=64;local Z=8
local ao,ae,Y=0,1,2;local aL=48;local ag=1
local function aM(a)
local b=a.getSectorSize and a.getSectorSize()or 512
local c=a.getCapacity and a.getCapacity()or(b*1024)b=math.max(64,math.floor(b))
local d=math.floor(c/b)return b,d end;local aN=4
local function at(d,a,b,c)local f=d.cache;if not f then return end;local g=f.map[a]f.tick=f.tick+1;if g then
g.data,g.used=b,f.tick;if c then g.dirty=true end;return end
if f.n>=aN then local e,h;for j,i in
pairs(f.map)do
if not i.dirty and(not h or i.used<h)then e,h=j,i.used end end
if e then f.map[e]=nil;f.n=f.n-1 end end;f.map[a]={data=b,used=f.tick,dirty=c or nil}f.n=f.n+1 end
local function ad(a,c,d)if c<0 or c>=a.totalBlocks then
error("readBlock out of range: "..tostring(c),2)end;local e=a.cache
if e then local f=e.map[c]if f then e.tick=
e.tick+1;f.used=e.tick;return f.data end end;local b=a.drive.readSector(c+1)
if type(b)~="string"then b=""end
if#b<a.ss then b=b..string.rep("\0",a.ss-#b)end;b=b:sub(1,a.ss)if d~=false then at(a,c,b)end;return b end
local function aO(a)local b=a.cache;if
not b or not b.dirtyCount or b.dirtyCount==0 then return end;local c={}for d,e in pairs(b.map)do
if e.dirty then c[#c+1]=d end end;table.sort(c)
for e,d in ipairs(c)do local f=b.map[d]a.drive.writeSector(
d+1,f.data)f.dirty=nil end;b.dirtyCount=0 end
local function an(a)a.batchDepth=(a.batchDepth or 0)+1 end;local function aj(a)a.batchDepth=a.batchDepth-1
if a.batchDepth<=0 then a.batchDepth=0;aO(a)end end
local function aa(a,c,d,e)if
c<0 or c>=a.totalBlocks then
error("writeBlock out of range: "..tostring(c),2)end
if#d<a.ss then d=d..
string.rep("\0",a.ss-#d)elseif#d>a.ss then d=d:sub(1,a.ss)end;local b=a.cache
if e and b and(a.batchDepth or 0)>0 then local f=
b.map[c]and b.map[c].dirty;at(a,c,d,true)if not f then b.dirtyCount=(
b.dirtyCount or 0)+1 end
return end;a.drive.writeSector(c+1,d)
if b and(c<a.dataStart or
(b.map[c]~=nil))then local f=b.map[c]
if
f and f.dirty then f.dirty=nil;b.dirtyCount=b.dirtyCount-1 end;at(a,c,d)end end
local function aP(a)local b=(a.label or""):sub(1,32)
return
string.pack("<c4 I1 I2 I4 I4 I4 I4 I4 I4 I4 I4 I4 I4 I1 s2",aA,aB,a.ss,a.totalBlocks,a.bitmapStart,a.bitmapBlocks,a.inodeStart,a.inodeCount,a.inodeBlocks,
a.bootStart or 0,a.bootBlocks or 0,a.dataStart,a.freeBlocks,a.clean and 1 or 0,b)end
local function aQ(a)
local c,d,b,e,f,g,h,i,j,k,l,m,n,o,p,q=pcall(string.unpack,"<c4 I1 I2 I4 I4 I4 I4 I4 I4 I4 I4 I4 I4 I1 s2",a)if not c or d~=aA then return nil,"not a TBFS volume"end
if b~=aB then return nil,
"unsupported TBFS version "..tostring(b)end
return
{ss=e,totalBlocks=f,bitmapStart=g,bitmapBlocks=h,inodeStart=i,inodeCount=j,inodeBlocks=k,bootStart=l,bootBlocks=m,dataStart=n,freeBlocks=o,clean=(p==1),label=q}end
local function _(a)
aa(a,0,aP({ss=a.ss,totalBlocks=a.totalBlocks,bitmapStart=a.bitmapStart,bitmapBlocks=a.bitmapBlocks,inodeStart=a.inodeStart,inodeCount=a.inodeCount,inodeBlocks=a.inodeBlocks,bootStart=a.bootStart,bootBlocks=a.bootBlocks,dataStart=a.dataStart,freeBlocks=a.freeBlocks,clean=a.clean,label=a.label}))a.superDirty=false end;local function au(a)if a.superDirty then _(a)end end
local function aC(a,b)local c=b;local d=c>>3;local e=a.bitmapStart+ (d//
a.ss)local f=d%a.ss;return e,f, (c&7)end;local function av(a,b)local c,d,e=aC(a,b)local f=ad(a,c)local g=f:byte(d+1)or 0
return(g>>e)&1 end
local function ah(a,b,c)local g,e,h=aC(a,b)
local f=ad(a,g)local d=f:byte(e+1)or 0;if c==1 then d=d| (1 <<h)else d=d&
(~ (1 <<h)&0xFF)end
aa(a,g,f:sub(1,e)..string.char(d)..f:sub(
e+2),true)end
local function aR(a,b)if a.freeBlocks<=0 then return nil end
local c,e=a.dataStart,a.totalBlocks-1
local function d(g)
if g>=c and g<=e and av(a,g)==0 then ah(a,g,1)
a.freeBlocks=a.freeBlocks-1;a.allocHint=g;a.superDirty=true;return g end;return nil end;if b and d(b+1)then return b+1 end;local f=a.allocHint or c;for g=f,e do local h=d(g)if h then
return h end end
for g=c,f-1 do local h=d(g)if h then return h end end;return nil end
local function aD(a,c)if c==0 then return end;if av(a,c)==1 then ah(a,c,0)a.freeBlocks=a.freeBlocks+1
a.superDirty=true end end;local function aE(a,b)local c=a.ss//af;local d=b;local e=a.inodeStart+ (d//c)local f=(d%c)*af;return
e,f end
local function ab(a,b)local g,e=aE(a,b)
local h=ad(a,g)local d=h:sub(e+1,e+af)
local i,j,k,l,m=string.unpack("<I1 I1 I4 I4 I4",d)local f={}local c=15
for p=1,Z do f[p]=string.unpack("<I4",d,c)c=c+4 end;local n=string.unpack("<I4",d,c)c=c+4
local o=string.unpack("<I4",d,c)
return{num=b,type=i,flags=j,size=k,mtime=l,blocks=m,direct=f,indirect=n,double=o}end
local function ac(b,a)
local c={string.pack("<I1 I1 I4 I4 I4",a.type,a.flags or 0,a.size or 0,a.mtime or 0,a.blocks or 0)}for h=1,Z do
c[#c+1]=string.pack("<I4",a.direct[h]or 0)end
c[#c+1]=string.pack("<I4",a.indirect or 0)c[#c+1]=string.pack("<I4",a.double or 0)
local d=table.concat(c)d=d..string.rep("\0",af-#d)local e,f=aE(b,a.num)
local g=ad(b,e)
aa(b,e,g:sub(1,f)..d:sub(1,af)..g:sub(f+af+1))end
local function aF(a,b)
for c=ag,a.inodeCount-1 do local d=ab(a,c)
if d.type==ao then
local e={num=c,type=b,flags=0,size=0,mtime=a.now(),blocks=0,direct={},indirect=0,double=0}for f=1,Z do e.direct[f]=0 end;ac(a,e)return e end end;return nil end;local function aG(a)return a.ss//4 end;local function ak(a,b,c)local d=ad(a,b)return
(string.unpack("<I4",d,c*4+1))end;local function ap(a,b,c,d)local e=ad(a,b)
local f=c*4
aa(a,b,e:sub(1,f)..string.pack("<I4",d)..e:sub(f+5),true)end;local function ai(c,d,e,f)local a=c.journal;if a then
a[#a+1]={d,e,f}end end
local function aH(a,b,c,d)local e=aG(a)local function g()
return a.allocHint end
local function f(h)local i=aR(a,h)if i then
b.blocks=(b.blocks or 0)+1;b._dirty=true;ai(a,"blk",i)end;return i end
if c<Z then
if b.direct[c+1]==0 and d then
local i=f(c>0 and b.direct[c]~=0 and
b.direct[c]or g())if not i then return nil end;b.direct[c+1]=i;ai(a,"direct",c+1)
return i,true end;local h=b.direct[c+1]return h~=0 and h or nil end;c=c-Z
if c<e then
if b.indirect==0 then if not d then return nil end;local i=f(g())
if not i then return nil end;aa(a,i,string.rep("\0",a.ss),true)b.indirect=i
ai(a,"ind")end;local h=ak(a,b.indirect,c)
if h==0 and d then h=f(b.indirect)
if not h then return nil end;ap(a,b.indirect,c,h)ai(a,"ptr",b.indirect,c)return h,true end;return h~=0 and h or nil end;c=c-e
if c<e*e then
if b.double==0 then if not d then return nil end;local l=f(g())
if not l then return nil end;aa(a,l,string.rep("\0",a.ss),true)b.double=l
ai(a,"dbl")end;local j,k=c//e,c%e;local h=ak(a,b.double,j)
if h==0 then if not d then return nil end
h=f(b.double)if not h then return nil end
aa(a,h,string.rep("\0",a.ss),true)ap(a,b.double,j,h)ai(a,"ptr",b.double,j)end;local i=ak(a,h,k)if i==0 and d then i=f(h)if not i then return nil end;ap(a,h,k,i)
ai(a,"ptr",h,k)return i,true end;return
i~=0 and i or nil end;return nil end
local function aS(c,a,b)
for d=#b,1,-1 do local e,f,g=b[d][1],b[d][2],b[d][3]
if e=="blk"then aD(c,f)
a.blocks=a.blocks-1 elseif e=="direct"then a.direct[f]=0 elseif e=="ind"then a.indirect=0 elseif e=="dbl"then a.double=0 else
ap(c,f,g,0)end end end
local function aw(c,a,b)local d=aG(c)local e=a.blocks;local f=0;for g=1,Z do if a.direct[g]~=0 then
b(a.direct[g],"data")end end;if a.indirect~=0 then
b(a.indirect,"meta")
for g=0,d-1 do local h=ak(c,a.indirect,g)if h~=0 then b(h,"data")end end end
if a.double~=0 then
b(a.double,"meta")for g=0,d-1 do local h=ak(c,a.double,g)
if h~=0 then b(h,"meta")for i=0,d-1 do local j=ak(c,h,i)if j~=0 then
b(j,"data")end end end end end;return e,f end
local function ax(b,a)an(b)aw(b,a,function(c)aD(b,c)end)aj(b)a.blocks=0
a.size=0;for c=1,Z do a.direct[c]=0 end;a.indirect=0;a.double=0 end
local function ay(b,c,d,a)if d>=c.size then return""end;a=math.min(a,c.size-d)local f={}local e=d;local g=(
c.type==Y)
while a>0 do local l=e//b.ss;local h=e%b.ss;local k=aH(b,c,l,false)
local i
if k then
i=ad(b,k,g):sub(h+1,h+math.min(a,b.ss-h))else i=string.rep("\0",math.min(a,b.ss-h))end;f[#f+1]=i;local j=#i;if j==0 then break end;e=e+j;a=a-j end;return table.concat(f)end
local function aq(a,b,c,d)local i=#d;local e=a.ss;an(a)local h=c//e;local j,k={},{}
if i>0 then local m=(c+i-1)//e;local l={}
a.journal=l
for n=h,m do local o,p=aH(a,b,n,true)if not o then a.journal=nil;aS(a,b,l)aj(a)
return false,"out of space"end;j[n-h+1],k[n-h+1]=o,p end;a.journal=nil end;local f,g=c,1
while g<=i do local q=f//e;local m=f%e;local o=q-h+1;local p=j[o]local r=e-m
local l=d:sub(g,g+r-1)local n
if#l==e then n=l elseif k[o]then n=string.rep("\0",m)..
l..string.rep("\0",e-m-#l)else
local s=ad(a,p,b.type==Y)n=s:sub(1,m)..l..s:sub(m+#l+1)end;aa(a,p,n)f=f+#l;g=g+#l end;aj(a)if f>b.size then b.size=f end;b.mtime=a.now()return true end
local function ar(b,a)local d=ay(b,a,0,a.size)local e,c={},1
while c+5 <=#d+1 do local f=d:byte(c)
if not f then break end;local g=d:sub(c+1,c+f)
local h=string.unpack("<I4",d,c+1+f)if f>0 then e[#e+1]={name=g,inode=h,off=c-1}end
c=c+1+f+4 end;return e end;local function aI(a,b,c)
for e,d in ipairs(ar(a,b))do if d.name==c then return d.inode,d.off end end;return nil end
local function az(b,a,c,d)
a=ab(b,a.num)if#c>aL then return false,"name too long"end
if aI(b,a,c)then return false,"exists"end
local e=string.char(#c)..c..string.pack("<I4",d)local f,g=aq(b,a,a.size,e)if not f then return false,g end;ac(b,a)return true end
local function aJ(b,a,c)a=ab(b,a.num)local d={}
for g,f in ipairs(ar(b,a))do if f.name~=c then
d[#d+1]=
string.char(#f.name)..f.name..string.pack("<I4",f.inode)end end;ax(b,a)a.size=0;if#d>0 then local e,f=aq(b,a,0,table.concat(d))if not e then return
false,f end end;ac(b,a)return
true end
local function as(a)local b={}
for c in tostring(a or""):gmatch("[^/]+")do if c==".."then b[#b]=nil elseif c~="."and
c~=""then b[#b+1]=c end end;return b end
local function al(a,b)local f=as(b)local c=ab(a,ag)local d,e=c,nil
for h,g in ipairs(f)do if c.type~=Y then
return nil,nil,nil,"not a directory"end;d=c;e=g;local i=aI(a,c,g)if not i then
if h==#f then return nil,d,e end;return nil,nil,nil,"no such path"end
c=ab(a,i)end;return c,d,e end
function X.plan(b,a)a=a or{}local d,c=aM(b)
if c<8 then return nil,"drive too small for TBFS"end;local i=math.max(1,math.ceil(c/ (d*8)))local n=d*c
local e=math.max(16,math.floor(
n/ (a.inodeRatio or 4096)))local j=d//af;local f=math.max(1,math.ceil(e/j))e=f*j;local g=0
if
a.bootBytes and a.bootBytes>0 then g=math.ceil(a.bootBytes/d)end;local k=1;local l=k+i;local m=l+f;local h=m+g;if h>=c then
return nil,"drive too small for metadata + boot region"end;return
{ss=d,totalBlocks=c,bitmapStart=k,bitmapBlocks=i,inodeStart=l,inodeCount=e,inodeBlocks=f,bootStart=m,bootBlocks=g,dataStart=h,dataBlocks=c-h}end
function X.blocksFor(b,a)a=a or 512
local c=math.ceil((tonumber(b)or 0)/a)if c<=Z then return c end;local e=a//4;local d,f=1,c-Z-e;if f>0 then
d=d+1+math.ceil(f/e)end;return c+d end
function X.format(b,a)a=a or{}local c,f=X.plan(b,a)if not c then return false,f end
local g,h,d=c.ss,c.totalBlocks,c.dataStart;c.drive,c.freeBlocks,c.clean=b,0,true
c.label=(a.label or"tbfs"):sub(1,32)c.now=a.now or function()return 0 end;c.allocHint=d
c.cache={map={},n=0,tick=0}for i=0,d-1 do aa(c,i,string.rep("\0",g))end;c.freeBlocks=
h-d;an(c)for i=0,d-1 do ah(c,i,1)end;aj(c)
local e={num=ag,type=Y,flags=0,size=0,mtime=c.now(),blocks=0,direct={},indirect=0,double=0}for j=1,Z do e.direct[j]=0 end;ac(c,e)_(c)return true end
local function am(b,a)a=a or{}local d=b.readSector(1)if type(d)~="string"then
return nil,"cannot read drive"end;local c,e=aQ(d)if not c then return nil,e end
local f={cache={map={},n=0,tick=0},drive=b,ss=c.ss,totalBlocks=c.totalBlocks,bitmapStart=c.bitmapStart,bitmapBlocks=c.bitmapBlocks,inodeStart=c.inodeStart,inodeCount=c.inodeCount,inodeBlocks=c.inodeBlocks,bootStart=c.bootStart,bootBlocks=c.bootBlocks,dataStart=c.dataStart,freeBlocks=c.freeBlocks,clean=c.clean,label=c.label,now=
a.now or function()return 0 end,allocHint=c.dataStart}return f end
function X.mount(a,b)local c,h=am(a,b)if not c then return nil,h end;c.clean=false;_(c)local e,g={},1;local function f(i)
local j=select(1,al(c,i))return j end;local d={}d.address=a.address
d.type="filesystem"function d.getLabel()return c.label end;function d.setLabel(i)
c.label=tostring(i or""):sub(1,32)_(c)return c.label end
function d.isReadOnly()return false end;function d.spaceTotal()
return(c.totalBlocks-c.dataStart)*c.ss end;function d.spaceUsed()
return(
(c.totalBlocks-c.dataStart)-c.freeBlocks)*c.ss end
function d.exists(i)return f(i)~=nil end
function d.isDirectory(i)local j=f(i)return j~=nil and j.type==Y end;function d.size(i)local j=f(i)
return(j and j.type==ae)and j.size or 0 end;function d.lastModified(i)local j=f(i)
return j and j.mtime or 0 end
function d.list(i)local j=f(i)
if not j or j.type~=Y then return{}end;local k={}
for m,l in ipairs(ar(c,j))do local n=ab(c,l.inode)k[#k+1]=l.name..
(n.type==Y and"/"or"")end;return k end
function d.makeDirectory(i)local k=as(i)if#k==0 then return true end;local j=""
for m,l in ipairs(k)do j=j.."/"..l
local n,o,p=al(c,j)
if n then if n.type~=Y then return false end else
if not o or not p then return false end;local q=aF(c,Y)if not q then return false end;local r=az(c,o,p,q.num)if not r then
q.type=ao;ac(c,q)return false end end end;au(c)return true end
function d.remove(i)local j,k,l=al(c,i)
if not j or not k or not l then return false end
if j.type==Y then for n,m in ipairs(ar(c,j))do
d.remove((i:gsub("/+$","")).."/"..m.name)end end;ax(c,j)j.type=ao;ac(c,j)aJ(c,k,l)_(c)return true end
function d.rename(j,i)local k,p,m=al(c,j)if not k or not m then return false end
if k.type==Y then
local r,s=as(j),as(i)local t=#s>=#r
for u=1,#r do if s[u]~=r[u]then t=false;break end end;if t and#s==#r then return true end;if t then return false end end;local l,n,o=al(c,i)if not n or not o then return false end;if
l and l.num==k.num then return true end;if l then d.remove(i)end
local q=az(c,n,o,k.num)if not q then return false end;aJ(c,p,m)_(c)return true end
function d.open(j,i)i=(i or"r"):gsub("b","")local k,l,m=al(c,j)
if i=="r"then if not k or
k.type~=ae then return nil,"no such file"end else
if not k then if not l or not m then return
nil,"bad path"end;k=aF(c,ae)
if not k then return nil,"no inodes"end
if not az(c,l,m,k.num)then k.type=ao;ac(c,k)return nil,"cannot link"end elseif k.type~=ae then return nil,"is a directory"end;if i=="w"then ax(c,k)ac(c,k)end end;local n=g;g=g+1
e[n]={node=k,mode=i,pos=(i=="a")and k.size or 0}return n end
function d.read(i,j)local k=e[i]if not k then return nil,aK end
if k.pos>=k.node.size then return nil end
local l=ay(c,k.node,k.pos,math.min(j,k.node.size-k.pos))k.pos=k.pos+#l;return l end
function d.write(j,i)local k=e[j]if not k then return false,aK end;if k.mode=="r"then
return false,"read-only handle"end;local l,h=aq(c,k.node,k.pos,i)if not l then au(c)
return false,h end;k.pos=k.pos+#i;ac(c,k.node)au(c)return true end
function d.seek(k,j,i)local l=e[k]if not l then return nil,aK end;i=i or 0
if j=="set"then l.pos=i elseif j=="cur"then l.pos=
l.pos+i elseif j=="end"then l.pos=l.node.size+i end;if l.pos<0 then l.pos=0 end;return l.pos end;function d.close(i)
if i==nil or e[i]==nil then return false,"bad file descriptor"end;e[i]=nil;return true end;function d.openHandles()
local i=0;for j in pairs(e)do i=i+1 end;return i end;function d.sync()
c.clean=true;_(c)c.clean=false;_(c)end
function d.unmount()c.clean=true;_(c)end;return d,c end
function X.stats(a,b)local c,h=am(a,b)if not c then return nil,h end;local f,g=0,0;local d,e=0,0
for j=ag,c.inodeCount-1 do
local k=ab(c,j)
if k.type==ae or k.type==Y then if k.type==ae then f=f+1 else g=g+1 end
local l=nil
aw(c,k,function(m,n)
if n=="data"then if l~=nil then d=d+1;if m~=l+1 then e=e+1 end end;l=m end end)end end;local i=(d>0)and(e/d)or 0
return
{label=c.label,sectorSize=c.ss,totalBlocks=c.totalBlocks,freeBlocks=c.freeBlocks,usedBlocks=
(c.totalBlocks-c.dataStart)-c.freeBlocks,dataBlocks=c.totalBlocks-c.dataStart,inodeCount=c.inodeCount,files=f,dirs=g,clean=c.clean,fragmentation=i,fragJumps=e,fragSteps=d}end
function X.check(b,a)a=a or{}local c,j=am(b,a)if not c then return nil,j end
local g=(not a.repair)and
type(a.yield)=="function"and a.yield or nil;local d={}local e={}
local function k(l)
if l<c.dataStart or l>=c.totalBlocks then d[#d+1]=
"pointer out of range: "..l;return end;e[l]=(e[l]or 0)+1;if e[l]>1 then
d[#d+1]="block "..l.." double-allocated"end end
for l=ag,c.inodeCount-1 do if g then g()end;local m=ab(c,l)if m.type==ae or m.type==Y then aw(c,m,function(n)
k(n)end)end end;local h,f=0,0
for l=c.dataStart,c.totalBlocks-1 do local m=av(c,l)if m==1 then h=h+1 end;if
m==1 and not e[l]then f=f+1 end
if m==0 and e[l]then d[#d+1]="block "..
l.." referenced but marked free"end end;if f>0 then
d[#d+1]=f.." leaked block(s) (used-bit set, unreferenced)"end;if not c.clean then
d[#d+1]="volume was not cleanly unmounted"end;local i=false
if a.repair then an(c)for m=0,c.dataStart-1 do
ah(c,m,1)end;local l=0;for m=c.dataStart,c.totalBlocks-1 do if e[m]then ah(c,m,1)else ah(c,m,0)
l=l+1 end end;aj(c)
c.freeBlocks=l;c.clean=true;_(c)i=true end;return
{ok=(#d==0),problems=d,repaired=i,leaked=f,referenced=c.totalBlocks-c.dataStart-c.freeBlocks}end
function X.defrag(b,a)a=a or{}local f=X.stats(b,a)
if not f then return nil,"not a TBFS volume"end;local c=am(b,a)local d={}
for h=ag,c.inodeCount-1 do local i=ab(c,h)if
i.type==ae or i.type==Y then d[h]=ay(c,i,0,i.size)end end;an(c)for h=c.dataStart,c.totalBlocks-1 do ah(c,h,0)end;aj(c)c.freeBlocks=
c.totalBlocks-c.dataStart;c.allocHint=c.dataStart;local e=0
for h=ag,c.inodeCount-1
do
if d[h]~=nil then local i=ab(c,h)for l=1,Z do i.direct[l]=0 end;i.indirect=0
i.double=0;i.blocks=0;i.size=0;local j,k=aq(c,i,0,d[h])if not j then return nil,
"defrag rewrite failed: "..tostring(k)end;ac(c,i)
e=e+i.blocks end end;c.clean=true;_(c)local g=X.stats(b,a)return
{moved=e,before=f.fragmentation,after=g and g.fragmentation or 0}end
X.BOOTSTRAP=[==[
-- TBFS stage-2 bootstrap (loaded from the boot region by the EEPROM).
local component = component or require("component")
local computer  = computer  or require("computer")
-- The TOS BIOS hands us the exact drive it read this blob from — trust it
-- first: getBootAddress may still point at a managed FS (fresh deploy) and
-- a blind first-drive scan could mount the wrong volume on a multi-drive box.
local addr = _G._TBFS_BOOT_DRIVE
_G._TBFS_BOOT_DRIVE = nil
if not addr then addr = computer.getBootAddress and computer.getBootAddress() end
local drive
if addr and component.type and component.type(addr) == "drive" then
  drive = component.proxy(addr)
else
  for a in component.list("drive") do drive = component.proxy(a); break end
end
if not drive then error("TBFS boot: no drive component") end
local root, mErr = blockfs.mount(drive)
if not root then error("TBFS boot: mount failed: " .. tostring(mErr)) end
-- init.lua prefers this global over proxying a managed boot filesystem,
-- so the unmanaged root reaches the kernel unchanged.
_G._TOS_UNMANAGED_ROOT = root
local h = root.open("/init.lua", "r")
if not h then error("TBFS boot: /init.lua not found on root") end
local parts = {}
while true do local c = root.read(h, 8192); if not c then break end; parts[#parts + 1] = c end
root.close(h)
local fn, lErr = load(table.concat(parts), "=/init.lua", "t")
if not fn then error("TBFS boot: init load error: " .. tostring(lErr)) end
return fn()
]==]
function X.bootBlob(b,a)a=a or X.BOOTSTRAP;return
"local blockfs = (function()\n"..b.."\nend)()\n"..a end
function X.writeBoot(b,a)local c,g=am(b)if not c then return false,g end
if
(c.bootBlocks or 0)==0 then return false,"volume has no boot region (format with bootBytes)"end;local e=c.bootBlocks*c.ss-4
if#a>e then return false,string.format("boot blob too large (%d > %d bytes)",
#a,e)end;local f=string.pack("<I4",#a)..a;local d=1;for h=c.bootStart,
c.bootStart+c.bootBlocks-1 do aa(c,h,f:sub(d,d+c.ss-1))d=d+c.ss;if d>
#f then break end end
return true end
function X.readBoot(a)local b,f=am(a)if not b then return nil,f end;if
(b.bootBlocks or 0)==0 then return nil,"no boot region"end;local c={}
for g=b.bootStart,b.bootStart+
b.bootBlocks-1 do c[#c+1]=ad(b,g)end;local d=table.concat(c)local e=string.unpack("<I4",d)if e==0 or
e>#d-4 then return nil,"no boot blob written"end;return
d:sub(5,4+e)end
function X.isBootable(a)local b=X.readBoot(a)return b~=nil and#b>0 end;return X