local E,F="string"," bytes"local v=require("kernel.curve25519field")
local x,y,w,z,G=v.feAdd,v.feSub,v.feMul,v.feSq,v.feInvert;local H,I=v.feFromBytes,v.feToBytes;local J,A,K=v.feNew,v.feCopy,v.yieldCoop
local L,B=v.FE_ZERO,v.FE_ONE;local u={}u.KEY_LEN=32;local C=J()C[1]=121665;u.BASEPOINT=string.char(9)..
string.rep("\0",31)
local function M(a)local b={a:byte(1,32)}b[1]=
b[1]&0xF8;b[32]=(b[32]&0x7F)|0x40;local c={}for d=1,32 do
c[d]=string.char(b[d])end;return table.concat(c)end
local function N(b,a)local c=b:byte((a//8)+1)return(c>> (a%8))&1 end
function u.scalarMult(a,b)if type(a)~=E or#a~=u.KEY_LEN then return nil,
"scalar must be "..u.KEY_LEN..F end;if type(b)~=E or
#b~=u.KEY_LEN then
return nil,"u-coordinate must be "..u.KEY_LEN..F end;local i=M(a)local h=H(b)local j=h
local c=A(B)local d=A(L)local e=A(h)local f=A(B)local g=0
for k=254,0,-1 do local m=N(i,k)g=g~m
if g==1 then c,e=e,c;d,f=f,d end;g=m;local n=x(c,d)local l=z(n)local o=y(c,d)local p=z(o)local q=y(l,p)local t=x(e,f)
local O=y(e,f)local r=w(O,n)local s=w(t,o)e=z(x(r,s))f=w(j,z(y(r,s)))c=w(l,p)
d=w(q,x(l,w(C,q)))if(k%16)==0 then K()end end;if g==1 then c,e=e,c;d,f=f,d end;return I(w(c,G(d)))end
local function D(a)local b=0;for c=1,#a do b=b|a:byte(c)end;return b==0 end;u._isAllZero=D
function u.generatePrivateKey(a)local b=a(u.KEY_LEN)if
type(b)~=E or#b~=u.KEY_LEN then
return nil,"randomBytes did not return "..u.KEY_LEN..F end;return b end
function u.publicKey(a)return u.scalarMult(a,u.BASEPOINT)end
function u.sharedSecret(a,b)local c,d=u.scalarMult(a,b)if not c then return nil,d end
if D(c)then return nil,
"peer's public key produced a degenerate (all-zero) shared secret"end;return c end;return u