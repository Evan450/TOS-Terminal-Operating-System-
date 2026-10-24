local as="string"local aa=require("kernel.sha512")
local U=require("kernel.curve25519field")local Y={}local aI=U.yieldCoop;local at=U.bnZero;local ag=U.bnFromInt;local au=U.bnCmp;local am=U.bnAdd
local av=U.bnSub;local aw=U.bnShl;local aJ=U.bnMul;local ax=U.bnBitLen;local ay=U.bnBit;local ab=U.bnMod
local W=U.bnFromBytesLE;local aK=U.bnToBytesLE;local Z=U.bnToBitsMSB;local an=U.feNew;local ac=U.feCopy;local X=U.feAdd
local ad=U.feSub;local ao=U.feNeg;local V=U.feMul;local ah=U.feSq;local az=U.fePow;local aA=U.feFromBytes
local aB=U.feToBytes;local aL=U.feIsZero;local aC=U.feEq;local aD=U.feIsNegative;local ap=U.feInvert;local aE=U.FE_ZERO
local ae=U.FE_ONE;local aq=U.P_BN;local ai,aF,aG
do local d=an()d[1]=121665;local e=an()e[1]=121666
ai=V(ao(d),ap(e))aF=X(ai,ai)local f=av(aq,ag(1))local c=at()for a=ax(f)-1,2,-1 do
c=am(aw(c,1),ag(ay(f,a)))end;local g=an()g[1]=2;aG=az(g,Z(c))end
local _=W(string.char(0xed,0xd3,0xf5,0x5c,0x1a,0x63,0x12,0x58,0xd6,0x9c,0xf7,0xa2,0xde,0xf9,0xde,0x14,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10))
local function aM()return{X=ac(aE),Y=ac(ae),Z=ac(ae),T=ac(aE)}end
local function ar(a,b)local c=V(ad(a.Y,a.X),ad(b.Y,b.X))
local d=V(X(a.Y,a.X),X(b.Y,b.X))local e=V(V(a.T,aF),b.T)local f=V(X(a.Z,a.Z),b.Z)
local g=ad(d,c)local h=ad(f,e)local i=X(f,e)local j=X(d,c)
return{X=V(g,h),Y=V(i,j),T=V(g,j),Z=V(h,i)}end
local function aj(a,b)local c=aM()for d=1,#a do c=ar(c,c)if a[d]==1 then c=ar(c,b)end
if(d%16)==0 then aI()end end;return c end
local function af(a)local c=ap(a.Z)local e=V(a.X,c)local f=V(a.Y,c)local d=aB(f)local b=d:byte(32)if
aD(e)then b=b|0x80 end
return d:sub(1,31)..string.char(b)end
local function ak(a)if#a~=32 then return nil end;local g=(a:byte(32)>>7)&1
local e=aA(a)
do
local l=W(a:sub(1,31)..string.char(a:byte(32)&0x7F))if au(l,aq)>=0 then return nil end end;local h=ah(e)local c=ad(h,ae)local d=X(V(ai,h),ae)local i=V(ah(d),d)
local k=V(ah(i),d)local f=at()do local l=av(aq,ag(5))for m=ax(l)-1,3,-1 do
f=am(aw(f,1),ag(ay(l,m)))end end
local b=V(V(c,i),az(V(c,k),Z(f)))local j=V(d,ah(b))if not aC(j,c)then
if aC(j,ao(c))then b=V(b,aG)else return nil end end;if aL(b)and g==1 then return nil end;if(
aD(b)and 1 or 0)~=g then b=ao(b)end;return
{X=b,Y=e,Z=ac(ae),T=V(b,e)}end
local al=ak(string.char(0x58,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66))
local function aH(a)local b={a:byte(1,32)}b[1]=b[1]&0xF8
b[32]=(b[32]&0x7F)|0x40;local c={}for d=1,32 do c[d]=string.char(b[d])end;return
table.concat(c)end
function Y.publickey(a)
if type(a)~=as or#a~=32 then return nil,"secret key must be 32 bytes"end;local b=aa.raw(a)local c=W(aH(b:sub(1,32)))return
af(aj(Z(c),al))end
function Y.sign(a,b,c)
if type(b)~=as or#b~=32 then return nil,"secret key must be 32 bytes"end;a=tostring(a or"")local d=aa.raw(b)local g=aH(d:sub(1,32))
local h=d:sub(33,64)if not c then c=Y.publickey(b)end
local e=ab(W(aa.raw(h..a)),_)local f=af(aj(Z(e),al))
local i=ab(W(aa.raw(f..c..a)),_)local j=W(g)local k=ab(am(e,aJ(i,j)),_)return f..aK(k,32)end
function Y.verify(c,a,b)
if type(a)~=as or#a~=64 then return false,"signature must be 64 bytes"end
if type(b)~=as or#b~=32 then return false,"public key must be 32 bytes"end;c=tostring(c or"")
local d,e,f=pcall(function()local g=a:sub(1,32)local l=a:sub(33,64)
local h=W(l)
if au(h,_)>=0 then return false,"signature S is not reduced"end;local i=ak(b)
if not i then return false,"public key is not a curve point"end;local j=ak(g)
if not j then return false,"signature R is not a curve point"end;local m=ab(W(aa.raw(g..b..c)),_)
local n=aj(Z(h),al)local o=ar(j,aj(Z(m),i))if af(n)==af(o)then return true end;return false,
"signature does not match"end)if not d then return false,"malformed signature"end
if e then return true end;return false,f or"signature does not match"end
Y._internal={feMul=V,feInvert=ap,feToBytes=aB,feFromBytes=aA,ptEncode=af,ptDecode=ak,B=al,bnMod=ab,bnFromBytesLE=W,L=_}return Y