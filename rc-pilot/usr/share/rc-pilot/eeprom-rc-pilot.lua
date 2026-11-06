local E,w=component,computer
local function x(a)for b in E.list(a)do return E.proxy(b)end end;local y,d,A,B=x("modem"),x("robot"),x("drone"),x("eeprom")if not y then
w.beep(200,1.5)while true do w.pullSignal(60)end end;local f=
B and B.getData and B.getData()if
type(f)~="string"or#f<16 then f=nil;w.beep(400,.3)end
local G="428a2f9871374491b5c0fbcfe9b5dba53956c25b59f111f1923f82a4ab1c5ed5d807aa9812835b01243185be550c7dc372be5d7480deb1fe9bdc06a7c19bf174e49b69c1efbe47860fc19dc6240ca1cc2de92c6f4a7484aa5cb0a9dc76f988da983e5152a831c66db00327c8bf597fc7c6e00bf3d5a7914706ca63511429296727b70a852e1b21384d2c6dfc53380d13650a7354766a0abb81c2c92e92722c85a2bfe8a1a81a664bc24b8b70c76c51a3d192e819d6990624f40e3585106aa07019a4c1161e376c082748774c34b0bcb5391c0cb34ed8aa4a5b9cca4f682e6ff3748f82ee78a5636f84c878148cc7020890befffaa4506cebbef9a3f7c67178f2"local F={}
for a=1,64 do F[a]=tonumber(G:sub(a*8-7,a*8),16)end;local function e(a,b)
return((a>>b)| (a<< (32-b)))&0xFFFFFFFF end
local function C(a)local o=#a
a=a.."\128"..
("\0"):rep((55-o)%64).. (">I8"):pack(o*8)
local c,g,h,i,j,k,m,n=0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19;local b={}
for l=1,#a,64 do
for N=0,15 do b[N+1]=(">I4"):unpack(a,l+N*4)end;for N=17,64 do local O,P=b[N-15],b[N-2]
b[N]=(b[N-16]+
(e(O,7)~e(O,18)~ (O>>3))+b[N-7]+
(e(P,17)~e(P,19)~ (P>>10)))&0xFFFFFFFF end
local p,r,s,v,q,t,u,M=c,g,h,i,j,k,m,n
for N=1,64 do
local O=
(M+ (e(q,6)~e(q,11)~e(q,25))+
((q&t)~ (~q&u))+F[N]+b[N])&0xFFFFFFFF
local P=((e(p,2)~e(p,13)~e(p,22))+
((p&r)~ (p&s)~ (r&s)))&0xFFFFFFFF;M,u,t,q,v,s,r,p=u,t,q,(v+O)&0xFFFFFFFF,s,r,p,(O+P)&0xFFFFFFFF end
c,g,h,i,j,k,m,n=(c+p)&0xFFFFFFFF,(g+r)&0xFFFFFFFF,(h+s)&0xFFFFFFFF,(i+v)&0xFFFFFFFF,(
j+q)&0xFFFFFFFF,(k+t)&0xFFFFFFFF,(m+u)&0xFFFFFFFF,(n+M)&0xFFFFFFFF end
return(">I4I4I4I4I4I4I4I4"):pack(c,g,h,i,j,k,m,n)end
local function H(a,b)if#a>64 then a=C(a)end;a=a.. ("\0"):rep(64-#a)
local c,g="",""
for h=1,64 do local i=a:byte(h)c=c..string.char(i~0x36)g=g..string.char(
i~0x5C)end;return
(C(g..C(c..b)):gsub(".",function(h)
return("%02x"):format(h:byte())end))end
local function I(c,g)if#c~=#g then return false end;local a=0;for b=1,#c do
a=a| (c:byte(b)~g:byte(b))end;return a==0 end;local D,z={},{}
local function J(a)if D[a]then return true end;D[a]=true;z[#z+1]=a;if#z>64 then D[table.remove(z,1)]=
nil end end
local K={["move:f"]={0,0,1},["move:b"]={0,0,-1},["move:l"]={-1,0,0},["move:r"]={1,0,0},up={0,1,0},down={0,-1,0},["turn:l"]={0,0,0},["turn:r"]={0,0,0},stop={0,0,0}}
local function L(a,b)
pcall(function()
if a=="select"then
d.select(math.max(1,math.min(b,16)))elseif A then local c=K[a]if c then A.move(c[1],c[2],c[3])end elseif a=="move:f"then
d.move(3)elseif a=="move:b"then d.move(2)elseif a=="move:l"then d.turn(false)d.move(3)
d.turn(true)elseif a=="move:r"then d.turn(true)d.move(3)d.turn(false)elseif a=="turn:l"then
d.turn(false)elseif a=="turn:r"then d.turn(true)elseif a=="up"then d.move(1)elseif a=="down"then d.move(0)elseif
a=="use:f"then d.use(3)elseif a=="swing:f"then d.swing(3)elseif a=="place:f"then d.place(3)end end)end;y.open(7777)
while true do local g,h,c,b,h,a=w.pullSignal()
if
g=="modem_message"and b==7777 and type(a)=="string"and
a:match('magic="([^"]+)"')=="RCPILOT1"then
if a:find('op="who"',1,true)then
y.send(c,b,
'{magic="RCPILOT1",op="here",keyed='..tostring(f~=nil)..
',kind="'.. (A and"drone"or"robot")..'"}')elseif f then local i=a:match('op="([^"]+)"')
local k=tonumber(a:match('arg=([%-%d]+)')or"")local j=a:match('nonce="([^"]+)"')
local l=a:match('mac="(%x+)"')
if i and j and l and
I(H(f,i.."|"..tostring(k or"").."|"..j),l)and not J(j)then
L(i,k)if i=="ping"then
y.send(c,b,'{magic="RCPILOT1",op="pong",arg='..math.floor(w.uptime())..'}')end end end end end