local u,y="the compressed data is damaged","the file stops early"local t={}
local s,v=string.byte,math.floor;t.MAX_SIDE=8192
local function w(a,b)local d,c,e={},{},{}for f=0,15 do d[f]=0 end;for f=0,b-1 do
d[a[f]]=d[a[f]]+1 end;c[1]=0;for f=1,14 do c[f+1]=c[f]+d[f]end
for f=0,b-1 do
local g=a[f]if g~=0 then e[c[g]]=f;c[g]=c[g]+1 end end;return{count=d,symbol=e}end
local D={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local E={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local F={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local G={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}local H={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}local A,B
local function C(b,a,c)
local e,f=0,0
local function d(m)local n,o=0,1
for p=1,m do
if f==0 then e=s(b,a)if not e then error(y,0)end;a=a+1;f=8 end;local q=e%2;e=(e-q)/2;f=f-1;n=n+q*o;o=o*2 end;return n end
local function h(m)local n,o,p=0,0,0;local q,r=m.count,m.symbol
for K=1,15 do if f==0 then e=s(b,a)if not e then error(y,0)end;a=
a+1;f=8 end;local M=e%2;e=(e-M)/2;f=f-1;n=n+M
local L=q[K]if n-L<o then return r[p+ (n-o)]end;p=p+L;o=(o+L)*2;n=n*2 end;error(u,0)end;local k,g,i={},0,0
local function j(m)k[g]=m;g=(g+1)%32768;i=i+1;return c(m)end
local function l(m,n)
while true do local o=h(m)
if o<256 then if j(o)then return true end elseif o==256 then return false else o=o-256;local p=D[o]if not p then
error(u,0)end;local L=p+d(E[o])local q=h(n)+1;local r=F[q]
if not r then error(u,0)end;local K=r+d(G[q])if K>i then error(u,0)end;for M=1,L do if
j(k[(g-K)%32768])then return true end end end end end
while true do local n=d(1)local m=d(2)
if m==0 then f=0;local q,o=s(b,a,a+1)if not o then error(y,0)end;local p=q+
o*256;a=a+4;for r=0,p-1 do local K=s(b,a+r)if not K then error(y,0)end;if j(K)then
return end end;a=a+p elseif m==1 then
if not A then local o={}for q=0,143 do
o[q]=8 end;for q=144,255 do o[q]=9 end;for q=256,279 do o[q]=7 end
for q=280,287 do o[q]=8 end;A=w(o,288)local p={}for q=0,29 do p[q]=5 end;B=w(p,30)end;if l(A,B)then return end elseif m==2 then local p,r,N=d(5)+257,d(5)+1,d(4)+4;local K={}
for P=0,18 do K[P]=0 end;for P=1,N do K[H[P]]=d(3)end;local O=w(K,19)local q,o={},0
while o<p+r do local P=h(O)
if P<16 then
q[o]=P;o=o+1 else local R,Q=0,0;if P==16 then if o==0 then error(u,0)end;R=q[o-1]Q=3+d(2)elseif P==17 then Q=3+
d(3)else Q=11+d(7)end;if o+Q>
p+r then error(u,0)end;for S=1,Q do q[o]=R;o=o+1 end end end;local L,M={},{}for P=0,p-1 do L[P]=q[P]end;for P=0,r-1 do M[P]=q[p+P]end;if
l(w(L,p),w(M,r))then return end else error(u,0)end;if n==1 then return end end end;t.inflate=C
local function x(b,a)local f,g,h,e=s(b,a,a+3)if not e then error(y,0)end;return f*16777216+
g*65536+h*256+e end;function t.is(a)return
type(a)=="string"and a:sub(1,8)=="\137PNG\r\n\26\n"end
function t.size(a)if
t.is(a)and#a>=24 then return x(a,17),x(a,21)end end;local z={[0]=1,[2]=3,[3]=1,[4]=2,[6]=4}
local function I(d,e,f)local g=d+e-f;local a,b,c=g-d,g-e,g-f;if a<0 then
a=-a end;if b<0 then b=-b end;if c<0 then c=-c end
if a<=b and a<=c then return d end;if b<=c then return e end;return f end
local function J(c,d,e,b,a)local h=z[c]
if d<8 then local i=8/d;local j=2^d;local l=j-1
local function k(m)local o=m-1;local p=o%i
local n=a[(o-p)/i+1]n=v(n/2^ ((i-1-p)*d))%j;return n end
if c==3 then return
function(m)local n=e[k(m)]if not n then return 0,0,0,255 end;return n[1],n[2],n[3],n[4]end end
return function(m)local o=k(m)if b and b.grey==o then return 0,0,0,0 end
local n=v(o*255/l)return n,n,n,255 end end;local f=d==16 and 2 or 1;local g=h*f
if c==3 then
return function(i)local j=e[a[i]]
if not j then return 0,0,0,255 end;return j[1],j[2],j[3],j[4]end elseif c==0 then
return function(i)local j=a[(i-1)*g+1]
if b and b.grey==j then return 0,0,0,0 end;return j,j,j,255 end elseif c==4 then return
function(i)local k=(i-1)*g;local j=a[k+1]return j,j,j,a[k+f+1]end elseif c==2 then
return
function(i)local j=(i-1)*g;local k,l,m=a[j+1],a[j+f+1],a[
j+2*f+1]if
b and b.r==k and b.g==l and b.b==m then return 0,0,0,0 end;return k,l,m,255 end end
return function(i)local j=(i-1)*g
return a[j+1],a[j+f+1],a[j+2*f+1],a[j+3*f+1]end end
function t.read(a,b,d,c)if not t.is(a)then return nil,"not a PNG file"end;local i,g,l,e
local j,r=nil,nil;local m={}local n=9
local O,P=pcall(function()
while true do local U=x(a,n)local V=a:sub(n+4,n+7)local T=n+8;if T+U-1 >#a then
error(y,0)end
if V=="IHDR"then i,g=x(a,T),x(a,T+4)local X,Y,Z,_,W=s(a,T+8,T+12)
l,e=X,Y;if not W or Z~=0 or _~=0 then
error("this PNG uses a method nothing writes",0)end;if W~=0 then
error("interlaced PNGs are not supported: save it without interlacing",0)end
if not z[e]or i<1 or g<1 or i>
t.MAX_SIDE or g>t.MAX_SIDE then
error(string.format("a %dx%d PNG of colour type %d is not one this can read",i,g,e),0)end elseif V=="PLTE"then j={}for W=0,v(U/3)-1 do local X,Y,Z=s(a,T+W*3,T+W*3+2)
j[W]={X,Y,Z,255}end elseif V=="tRNS"then
if e==3 and j then for W=0,U-1 do if j[W]then
j[W][4]=s(a,T+W)end end elseif e==0 and U>=2 then r={grey=l==16 and s(a,T)or
s(a,T+1)}elseif e==2 and U>=6 then
local W=l==16 and 0 or 1;r={r=s(a,T+W),g=s(a,T+2+W),b=s(a,T+4+W)}end elseif V=="IDAT"then m[#m+1]=a:sub(T,T+U-1)elseif V=="IEND"then return end;n=T+U+4 end end)if not O then return nil,tostring(P)end;if not i then
return nil,"this PNG has no header"end
if e==3 and not j then return nil,"this PNG has no palette"end;if#m==0 then return nil,"this PNG has no picture in it"end;local o=math.max(1,v(
z[e]*l/8))
local K=math.ceil(i*z[e]*l/8)local M=b and b(i,g)local N=table.concat(m)m=nil
if
(s(N,1)or 0)%16 ~=8 then return nil,"this PNG is not compressed the usual way"end;local p,q={},{}for T=1,K do q[T]=0 end;local Q=J(e,l,j,r,p)local k,f,h=1,0,nil
local function R(T)
if not h then h=T;return false end;f=f+1;local U=f>o and p[f-o]or 0;local V=q[f]
if h==1 then T=(T+U)%256 elseif
h==2 then T=(T+V)%256 elseif h==3 then T=(T+v((U+V)/2))%256 elseif h==4 then
T=(T+I(U,V,f>
o and q[f-o]or 0))%256 elseif h~=0 then error(u,0)end;p[f]=T
if f==K then if not M or M[k]then d(k,Q)end;if c then c(k,g)end
for W=1,K do q[W]=p[W]end;k,f,h=k+1,0,nil;if k>g then return true end end;return false end;local S,L=pcall(C,N,3,R)
if not S then
if type(L)=="string"and
L:find("not enough memory",1,true)then return nil,"not enough memory to unpack this PNG"end;return nil,tostring(L)end;if k<=g then return nil,"the picture ends early"end;return true end;return t