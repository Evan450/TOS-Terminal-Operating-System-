local e={}
local function d(a,b)return(a>>b)| (a<< (64-b))end
local f={0x428a2f98d728ae22,0x7137449123ef65cd,0xb5c0fbcfec4d3b2f,0xe9b5dba58189dbbc,0x3956c25bf348b538,0x59f111f1b605d019,0x923f82a4af194f9b,0xab1c5ed5da6d8118,0xd807aa98a3030242,0x12835b0145706fbe,0x243185be4ee4b28c,0x550c7dc3d5ffb4e2,0x72be5d74f27b896f,0x80deb1fe3b1696b1,0x9bdc06a725c71235,0xc19bf174cf692694,0xe49b69c19ef14ad2,0xefbe4786384f25e3,0x0fc19dc68b8cd5b5,0x240ca1cc77ac9c65,0x2de92c6f592b0275,0x4a7484aa6ea6e483,0x5cb0a9dcbd41fbd4,0x76f988da831153b5,0x983e5152ee66dfab,0xa831c66d2db43210,0xb00327c898fb213f,0xbf597fc7beef0ee4,0xc6e00bf33da88fc2,0xd5a79147930aa725,0x06ca6351e003826f,0x142929670a0e6e70,0x27b70a8546d22ffc,0x2e1b21385c26c926,0x4d2c6dfc5ac42aed,0x53380d139d95b3df,0x650a73548baf63de,0x766a0abb3c77b2a8,0x81c2c92e47edaee6,0x92722c851482353b,0xa2bfe8a14cf10364,0xa81a664bbc423001,0xc24b8b70d0f89791,0xc76c51a30654be30,0xd192e819d6ef5218,0xd69906245565a910,0xf40e35855771202a,0x106aa07032bbd1b8,0x19a4c116b8d2d0c8,0x1e376c085141ab53,0x2748774cdf8eeb99,0x34b0bcb5e19b48a8,0x391c0cb3c5c95a63,0x4ed8aa4ae3418acb,0x5b9cca4f7763e373,0x682e6ff3d6b2b8a3,0x748f82ee5defb2fc,0x78a5636f43172f60,0x84c87814a1f0ab72,0x8cc702081a6439ec,0x90befffa23631e28,0xa4506cebde82bde9,0xbef9a3f7b2c67915,0xc67178f2e372532b,0xca273eceea26619c,0xd186b8c721c0c207,0xeada7dd6cde0eb1e,0xf57d4f7fee6ed178,0x06f067aa72176fba,0x0a637dc5a2c898a6,0x113f9804bef90dae,0x1b710b35131c471b,0x28db77f523047d84,0x32caab7b40c72493,0x3c9ebe0a15c9bebc,0x431d67c49c100d4c,0x4cc5d4becb3e42b6,0x597f299cfc657e2a,0x5fcb6fab3ad6faec,0x6c44198c4a475817}
function e.hex(a)return
(e.raw(a):gsub(".",function(b)return string.format("%02x",b:byte())end))end
function e.raw(a)local t=#a*8;local g=112- ((#a+1)%128)
if g<0 then g=g+128 end;local q={}
for m=15,0,-1 do q[#q+1]=string.char(
(m<8)and((t>> (m*8))&0xFF)or 0)end;local s=a..
"\128"..string.rep("\0",g)..table.concat(q)
local h,i,j,k,l,n,o,p=0x6a09e667f3bcc908,0xbb67ae8584caa73b,0x3c6ef372fe94f82b,0xa54ff53a5f1d36f1,0x510e527fade682d1,0x9b05688c2b3e6c1f,0x1f83d9abfb41bd6b,0x5be0cd19137e2179;local c={}
for m=1,#s,128 do for C=0,15 do local D=m+C*8;local E,F,G,H,I,J,K,L=s:byte(D,D+7)
c[C+1]=
(E<<56)| (F<<48)| (G<<40)| (H<<32)| (I<<24)| (
J<<16)| (K<<8)|L end
for C=16,79 do local D,E=c[
C-15+1],c[C-2+1]
local F=d(D,1)~d(D,8)~ (D>>7)local G=d(E,19)~d(E,61)~ (E>>6)c[C+1]=
c[C-16+1]+F+c[C-7+1]+G end;local u,w,x,A,v,y,z,B=h,i,j,k,l,n,o,p
for C=1,80 do local E=d(v,14)~d(v,18)~d(v,41)local F=(
v&y)~ ((~v)&z)local D=B+E+F+f[C]+c[C]local G=
d(u,28)~d(u,34)~d(u,39)
local H=(u&w)~ (u&x)~ (w&x)local I=G+H;B=z;z=y;y=v;v=A+D;A=x;x=w;w=u;u=D+I end;h=h+u;i=i+w;j=j+x;k=k+A;l=l+v;n=n+y;o=o+z;p=p+B end;local r={}local function b(m)for u=7,0,-1 do
r[#r+1]=string.char((m>> (u*8))&0xFF)end end;b(h)
b(i)b(j)b(k)b(l)b(n)b(o)b(p)return table.concat(r)end;return e