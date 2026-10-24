local R={}local ac
do local b,a=pcall(require,"kernel.process")
if
b and
type(a)=="table"and type(a.yieldCooperative)=="function"then ac=a.yieldCooperative else ac=function()end end end;R.yieldCoop=ac;local S=24;local al=1 <<S;local Y=al-1;local function U()return{0}end;local function Z(b)while
#b>1 and b[#b]==0 do b[#b]=nil end;return b end
local function T(a)
local b={}if a==0 then return{0}end;while a>0 do b[#b+1]=a&Y;a=a>>S end;return b end
local function V(c,d)if#c~=#d then return#c<#d and-1 or 1 end
for a=#c,1,-1 do if c[a]~=d[a]then return
c[a]<d[a]and-1 or 1 end end;return 0 end
local function ad(c,d)local b,a={},0;local e=math.max(#c,#d)for f=1,e do
local g=(c[f]or 0)+ (d[f]or 0)+a;b[f]=g&Y;a=g>>S end;if a~=0 then b[e+1]=a end;return
Z(b)end
local function _(c,d)local b,a={},0;for e=1,#c do local f=c[e]- (d[e]or 0)-a
if f<0 then f=f+al;a=1 else a=0 end;b[e]=f end;return Z(b)end
local function aa(b,c)if V(b,U())==0 then return U()end;local e,f=c//S,c%S;local a={}
for g=1,e do a[g]=0 end;local d=0
for g=1,#b do local h=(b[g]<<f)|d;a[e+g]=h&Y;d=h>>S end;if d~=0 then a[e+#b+1]=d end;return Z(a)end
local function am(d,c)local a={}for b=1,#d+#c do a[b]=0 end
for b=1,#d do local e=0;local f=d[b]
if f~=0 then
for h=1,#c do local i=
a[b+h-1]+f*c[h]+e;a[b+h-1]=i&Y;e=i>>S end;local g=b+#c;while e~=0 do local h=a[g]+e;a[g]=h&Y;e=h>>S;g=g+1 end end end;return Z(a)end
local function af(b)local a=b[#b]if a==0 and#b==1 then return 0 end;local c=(#b-1)*S;while a>0 do c=c+1;a=a>>
1 end;return c end;local function ab(c,b)local a=c[(b//S)+1]if not a then return 0 end
return(a>> (b%S))&1 end
local function an(b,c)if V(b,c)<0 then return b end
local a=U()for d=af(b)-1,0,-1 do a=aa(a,1)if ab(b,d)==1 then a=ad(a,T(1))end;if V(a,c)>=0 then
a=_(a,c)end end;return a end;local function av(a)local b=U()
for c=#a,1,-1 do b=aa(b,8)b=ad(b,T(a:byte(c)))end;return b end
local function ao(b,c)local a={}for d=0,c-1 do local e=0;for f=0,7 do e=e| (
ab(b,d*8+f)<<f)end
a[d+1]=string.char(e)end;return table.concat(a)end
local function ap(b)local a={}for c=af(b)-1,0,-1 do a[#a+1]=ab(b,c)end;return a end;local aq={0,26,51,77,102,128,153,179,204,230}
local ag={26,25,26,25,26,25,26,25,26,25}local ah={}local ar={}
for a=1,10 do ah[a]=1 <<ag[a]ar[a]=1 << (ag[a]-1)end;local function ai()return{0,0,0,0,0,0,0,0,0,0}end;local function as(a)return
{a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10]}end
local function W(a)for b=1,2 do
for c=1,10 do local d=(
a[c]+ar[c])//ah[c]if c==10 then a[1]=a[1]+19*d else a[c+1]=a[
c+1]+d end;a[c]=a[c]-d*ah[c]end end;return a end
local function aw(a,b)local c={}for d=1,10 do c[d]=a[d]+b[d]end;return W(c)end
local function ax(a,b)local c={}for d=1,10 do c[d]=a[d]-b[d]end;return W(c)end
local function ay(a)local b={}for c=1,10 do b[c]=-a[c]end;return W(b)end
local function aj(a,b)local c={0,0,0,0,0,0,0,0,0,0}
for d=0,9 do local e=a[d+1]
if e~=0 then local f=(d%2)==1;for g=0,9 do
local i=e*b[g+1]if f and(g%2)==1 then i=i*2 end;local h=d+g
if h>=10 then c[h-10+1]=c[h-10+1]+
19*i else c[h+1]=c[h+1]+i end end end end;return W(c)end;local function at(a)return aj(a,a)end;local az=ai()local ak=ai()ak[1]=1;local function au(b,a)local c=as(ak)
for d=1,#a do
c=at(c)if a[d]==1 then c=aj(c,b)end;if(d%32)==0 then ac()end end;return c end
local ae=_(aa(T(1),255),T(19))local function aA(a,b,c)local d=0
for e=0,c-1 do local f=b+e;local g=a:byte((f>>3)+1)d=d| (
((g>> (f&7))&1)<<e)end;return d end
local function aB(a)local b={}for c=1,10
do b[c]=aA(a,aq[c],ag[c])end;b[10]=b[10]&
((1 <<25)-1)return W(b)end
local function X(a)local b=am(ae,T(16))for c=1,10 do local d=a[c]
if d~=0 then local e=d<0;if e then d=-d end
local f=aa(T(d),aq[c])b=e and _(b,f)or ad(b,f)end end
return an(b,ae)end;local function aC(a)return ao(X(a),32)end
local function aD(a)return V(X(a),U())==0 end;local function aE(c,d)return V(X(c),X(d))==0 end;local function aF(a)
return ab(X(a),0)==1 end
local function aG(a)return au(a,ap(_(ae,T(2))))end;R.bnZero,R.bnTrim,R.bnFromInt,R.bnCmp=U,Z,T,V
R.bnAdd,R.bnSub,R.bnShl,R.bnMul=ad,_,aa,am;R.bnBitLen,R.bnBit,R.bnMod=af,ab,an
R.bnFromBytesLE,R.bnToBytesLE,R.bnToBitsMSB=av,ao,ap;R.feNew,R.feCopy,R.feCarry=ai,as,W
R.feAdd,R.feSub,R.feNeg,R.feMul,R.feSq,R.fePow=aw,ax,ay,aj,at,au;R.feFromBytes,R.feToBn,R.feToBytes=aB,X,aC
R.feIsZero,R.feEq,R.feIsNegative,R.feInvert=aD,aE,aF,aG;R.FE_ZERO,R.FE_ONE=az,ak;R.P_BN=ae;return R