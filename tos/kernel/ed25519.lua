local aQ="string"local av=require("kernel.sha512")local am={}local aD
do
local b,a=pcall(require,"kernel.process")
if b and type(a)=="table"and
type(a.yieldCooperative)=="function"then aD=a.yieldCooperative else aD=function()end end end;local ae=24;local aR=1 <<ae;local aw=aR-1;local function ah()return{0}end;local function aE(b)while#b>1 and b[#b]==0 do b[#b]=
nil end;return b end
local function af(a)local b={}if
a==0 then return{0}end;while a>0 do b[#b+1]=a&aw;a=a>>ae end;return b end
local function ai(c,d)if#c~=#d then return#c<#d and-1 or 1 end
for a=#c,1,-1 do if c[a]~=d[a]then return
c[a]<d[a]and-1 or 1 end end;return 0 end
local function an(c,d)local b,a={},0;local e=math.max(#c,#d)for f=1,e do
local g=(c[f]or 0)+ (d[f]or 0)+a;b[f]=g&aw;a=g>>ae end
if a~=0 then b[e+1]=a end;return aE(b)end
local function ao(c,d)local b,a={},0;for e=1,#c do local f=c[e]- (d[e]or 0)-a
if f<0 then f=f+aR;a=1 else a=0 end;b[e]=f end;return aE(b)end
local function ap(b,c)if ai(b,ah())==0 then return ah()end;local e,f=c//ae,c%ae;local a={}
for g=1,e do a[g]=0 end;local d=0
for g=1,#b do local h=(b[g]<<f)|d;a[e+g]=h&aw;d=h>>ae end;if d~=0 then a[e+#b+1]=d end;return aE(a)end
local function aS(d,c)local a={}for b=1,#d+#c do a[b]=0 end
for b=1,#d do local e=0;local f=d[b]
if f~=0 then
for h=1,#c do local i=
a[b+h-1]+f*c[h]+e;a[b+h-1]=i&aw;e=i>>ae end;local g=b+#c
while e~=0 do local h=a[g]+e;a[g]=h&aw;e=h>>ae;g=g+1 end end end;return aE(a)end
local function aF(b)local a=b[#b]if a==0 and#b==1 then return 0 end;local c=(#b-1)*ae;while a>0 do
c=c+1;a=a>>1 end;return c end;local function aq(c,b)local a=c[(b//ae)+1]if not a then return 0 end
return(a>> (b%ae))&1 end
local function ar(b,c)
if ai(b,c)<0 then return b end;local a=ah()
for d=aF(b)-1,0,-1 do a=ap(a,1)
if aq(b,d)==1 then a=an(a,af(1))end;if ai(a,c)>=0 then a=ao(a,c)end end;return a end;local function ag(a)local b=ah()
for c=#a,1,-1 do b=ap(b,8)b=an(b,af(a:byte(c)))end;return b end
local function aT(b,c)local a={}for d=0,c-1 do local e=0;for f=0,7 do e=e| (
aq(b,d*8+f)<<f)end
a[d+1]=string.char(e)end;return table.concat(a)end
local function aj(b)local a={}for c=aF(b)-1,0,-1 do a[#a+1]=aq(b,c)end;return a end;local aU={0,26,51,77,102,128,153,179,204,230}
local aK={26,25,26,25,26,25,26,25,26,25}local aL={}local aV={}
for a=1,10 do aL[a]=1 <<aK[a]aV[a]=1 << (aK[a]-1)end;local function ax()return{0,0,0,0,0,0,0,0,0,0}end;local function as(a)return
{a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10]}end
local function ay(a)for b=1,2 do
for c=1,10 do local d=(
a[c]+aV[c])//aL[c]if c==10 then a[1]=a[1]+19*d else a[c+1]=a[
c+1]+d end;a[c]=a[c]-d*aL[c]end end;return a end
local function ak(a,b)local c={}for d=1,10 do c[d]=a[d]+b[d]end;return ay(c)end
local function az(a,b)local c={}for d=1,10 do c[d]=a[d]-b[d]end;return ay(c)end
local function aM(a)local b={}for c=1,10 do b[c]=-a[c]end;return ay(b)end
local function D(a,b)local c={0,0,0,0,0,0,0,0,0,0}
for d=0,9 do local e=a[d+1]
if e~=0 then local f=(d%2)==1;for g=0,9 do
local i=e*b[g+1]if f and(g%2)==1 then i=i*2 end;local h=d+g
if h>=10 then c[h-10+1]=c[h-10+1]+
19*i else c[h+1]=c[h+1]+i end end end end;return ay(c)end;local function aA(a)return D(a,a)end;local aW=ax()local al=ax()al[1]=1;local function aN(b,a)local c=as(al)
for d=1,#a do
c=aA(c)if a[d]==1 then c=D(c,b)end;if(d%32)==0 then aD()end end;return c end
local at=ao(ap(af(1),255),af(19))local function bd(a,b,c)local d=0
for e=0,c-1 do local f=b+e;local g=a:byte((f>>3)+1)d=d| (
((g>> (f&7))&1)<<e)end;return d end
local function aX(a)local b={}for c=1,10
do b[c]=bd(a,aU[c],aK[c])end;b[10]=b[10]&
((1 <<25)-1)return ay(b)end
local function aB(a)local b=aS(at,af(16))for c=1,10 do local d=a[c]
if d~=0 then local e=d<0;if e then d=-d end
local f=ap(af(d),aU[c])b=e and ao(b,f)or an(b,f)end end
return ar(b,at)end;local function aY(a)return aT(aB(a),32)end;local function be(a)
return ai(aB(a),ah())==0 end
local function aZ(c,d)return ai(aB(c),aB(d))==0 end;local function a_(a)return aq(aB(a),0)==1 end;local function aO(a)return
aN(a,aj(ao(at,af(2))))end;local aG,ba,bb
do local d=ax()d[1]=121665
local e=ax()e[1]=121666;aG=D(aM(d),aO(e))ba=ak(aG,aG)local f=ao(at,af(1))
local c=ah()
for a=aF(f)-1,2,-1 do c=an(ap(c,1),af(aq(f,a)))end;local g=ax()g[1]=2;bb=aN(g,aj(c))end
local au=ag(string.char(0xed,0xd3,0xf5,0x5c,0x1a,0x63,0x12,0x58,0xd6,0x9c,0xf7,0xa2,0xde,0xf9,0xde,0x14,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10))
local function bf()return{X=as(aW),Y=as(al),Z=as(al),T=as(aW)}end
local function aP(a,b)local c=D(az(a.Y,a.X),az(b.Y,b.X))
local d=D(ak(a.Y,a.X),ak(b.Y,b.X))local e=D(D(a.T,ba),b.T)local f=D(ak(a.Z,a.Z),b.Z)
local g=az(d,c)local h=az(f,e)local i=ak(f,e)local j=ak(d,c)return
{X=D(g,h),Y=D(i,j),T=D(g,j),Z=D(h,i)}end
local function aH(a,b)local c=bf()for d=1,#a do c=aP(c,c)if a[d]==1 then c=aP(c,b)end
if(d%16)==0 then aD()end end;return c end
local function aC(a)local c=aO(a.Z)local e=D(a.X,c)local f=D(a.Y,c)local d=aY(f)local b=d:byte(32)if
a_(e)then b=b|0x80 end
return d:sub(1,31)..string.char(b)end
local function aI(a)if#a~=32 then return nil end;local g=(a:byte(32)>>7)&1
local e=aX(a)
do
local l=ag(a:sub(1,31)..string.char(a:byte(32)&0x7F))if ai(l,at)>=0 then return nil end end;local h=aA(e)local c=az(h,al)local d=ak(D(aG,h),al)local i=D(aA(d),d)
local k=D(aA(i),d)local f=ah()do local l=ao(at,af(5))for m=aF(l)-1,3,-1 do
f=an(ap(f,1),af(aq(l,m)))end end
local b=D(D(c,i),aN(D(c,k),aj(f)))local j=D(d,aA(b))if not aZ(j,c)then
if aZ(j,aM(c))then b=D(b,bb)else return nil end end;if be(b)and g==1 then return nil end;if(
a_(b)and 1 or 0)~=g then b=aM(b)end;return
{X=b,Y=e,Z=as(al),T=D(b,e)}end
local aJ=aI(string.char(0x58,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66))
local function bc(a)local b={a:byte(1,32)}b[1]=b[1]&0xF8
b[32]=(b[32]&0x7F)|0x40;local c={}for d=1,32 do c[d]=string.char(b[d])end;return
table.concat(c)end
function am.publickey(a)
if type(a)~=aQ or#a~=32 then return nil,"secret key must be 32 bytes"end;local b=av.raw(a)local c=ag(bc(b:sub(1,32)))return
aC(aH(aj(c),aJ))end
function am.sign(a,b,c)
if type(b)~=aQ or#b~=32 then return nil,"secret key must be 32 bytes"end;a=tostring(a or"")local d=av.raw(b)local g=bc(d:sub(1,32))
local h=d:sub(33,64)if not c then c=am.publickey(b)end
local e=ar(ag(av.raw(h..a)),au)local f=aC(aH(aj(e),aJ))
local i=ar(ag(av.raw(f..c..a)),au)local j=ag(g)local k=ar(an(e,aS(i,j)),au)return f..aT(k,32)end
function am.verify(c,a,b)
if type(a)~=aQ or#a~=64 then return false,"signature must be 64 bytes"end
if type(b)~=aQ or#b~=32 then return false,"public key must be 32 bytes"end;c=tostring(c or"")
local d,e,f=pcall(function()local g=a:sub(1,32)local l=a:sub(33,64)
local h=ag(l)
if ai(h,au)>=0 then return false,"signature S is not reduced"end;local i=aI(b)
if not i then return false,"public key is not a curve point"end;local j=aI(g)
if not j then return false,"signature R is not a curve point"end;local m=ar(ag(av.raw(g..b..c)),au)
local n=aH(aj(h),aJ)local o=aP(j,aH(aj(m),i))if aC(n)==aC(o)then return true end;return false,
"signature does not match"end)if not d then return false,"malformed signature"end
if e then return true end;return false,f or"signature does not match"end
am._internal={feMul=D,feInvert=aO,feToBytes=aY,feFromBytes=aX,ptEncode=aC,ptDecode=aI,B=aJ,bnMod=ar,bnFromBytesLE=ag,L=au}return am