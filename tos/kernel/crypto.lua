local ae,af,K="crypto","kernel.log","string"local X=require("component")
local O=require("computer")local H={}local I=nil;local S=false;function H.init()
local a,b=pcall(function()
for c in X.list("data")do I=X.proxy(c)S=true;return end end)return S end
function H.hasHardware()return S end
local function ag(a)local b=5381;for c=1,#a do
b=((b<<5)+b+a:byte(c))&0xFFFFFFFF end;return b end
local function ah(a)local b=0x811C9DC5;for c=1,#a do b=b~a:byte(c)
b=(b*0x01000193)&0xFFFFFFFF end;return b end
local function am(a)local b=ag(a)local c=ah(a)return string.format("%08x%08x",b,c)end;local L=require("kernel.sha256").hex
function H.hash(a)
if I then
local c,b=pcall(function()
local e=I.sha256(a)local d={}
for f=1,#e do d[#d+1]=string.format("%02x",e:byte(f))end;return table.concat(d)end)if c and b then return b end end;return L(a)end
local function P(c,d)if type(c)~=K or type(d)~=K then return false end
local a,b=#c,#d;local f=a>b and a or b;local e=a~b
for g=1,f do
local h=g<=a and c:byte(g)or 0;local i=g<=b and d:byte(g)or 0;e=e| (h~i)end;return e==0 end;H.ctEquals=P;local T=256;local function Y()return T end;local function ai(b,a)local c=H.hash(a..b)
local d=H.hash(c..a.."tos")return d end
local function aj(b,a,c)
local d=L(a..b.."tos")for e=2,(c or T)do d=L(d..a)end;return d end;local M;local function ak(a,b,c)local e=b.."tos"local d=M(e,a)
for f=2,c do d=M(e,d..
string.char(f&0xFF,(f>>8)&0xFF))end;return d end
local function Z(b,a,c)
local e=a.."\0tos.v3"local d=M(e,b.."\0"..a)for f=2,c do
d=M(e,d.."\0"..
string.char(f&0xFF,(f>>8)&0xFF))end;return d end;function H.hashPassword(a,b)local c=Y()
return"v3$"..tostring(c).."$"..Z(a,b,c)end
function H.verifyPassword(b,c,a)
if type(a)~=K then return false,false end;if type(b)~=K then return false,false end
if type(c)~=K then return false,false end;local f,d=a:match("^v3%$(%d+)%$(%x+)$")
if f and d and#d==64 then
local h=tonumber(f)if h and h>=1 and h<=100000 then
if P(Z(b,c,h),d)then local i=Y()return true, (h~=i)end end;return false,false end;local g,e=a:match("^v2%$(%d+)%$(%x+)$")
if g and e and#e==64 then
local h=tonumber(g)if h and h>=1 and h<=100000 then
if P(ak(b,c,h),e)then return true,true end end;return false,false end
if#a==64 then if P(aj(b,c,T),a)then return true,true end;if P(ai(b,c),a)then
return true,true end;return false,false end
if#a==16 then
pcall(function()local h=require(af)if h and h.warn then
h.warn(ae,"Refused legacy 16-hex hash; account must be reset")end end)return false,false end;return false,false end;local J=0;local N=0
local function Q()N=N+1
local b=table.concat({tostring(O.uptime()),tostring(O.freeMemory()),tostring(
O.totalMemory and O.totalMemory()or 0),tostring(N),tostring(J),tostring({})},"|")local c=L(b)local a=0
for d=1,16 do a=
((a<<4)|tonumber(c:sub(d,d),16))&0xFFFFFFFFFFFFFFFF end;if a==0 then a=0xDEADBEEFCAFEBABE end;J=a end
local function U()if J==0 then Q()end;local a=J;a=a~ (a>>12)a=a&0xFFFFFFFFFFFFFFFF;a=a~
(a<<25)a=a&0xFFFFFFFFFFFFFFFF;a=a~ (a>>27)
a=a&0xFFFFFFFFFFFFFFFF;J=a
return(a*0x2545F4914F6CDD1D)&0xFFFFFFFFFFFFFFFF end
function H.addEntropy(a)if type(a)~=K or a==""then return false end
local c=L(a.."|"..tostring(J)..
"|"..tostring(N))local b=0
for d=1,16 do b=((b<<4)|tonumber(c:sub(d,d),16))&
0xFFFFFFFFFFFFFFFF end;J=(J~b)&0xFFFFFFFFFFFFFFFF;if J==0 then
J=(b~=0)and b or 0xA5A5A5A5A5A5A5A5 end;N=N+1;return true end
function H.exportEntropy(a)a=
(type(a)=="number"and a>0)and math.floor(a)or 32;Q()local b={}for c=1,a do b[c]=string.char(U()&
0xFF)end
return table.concat(b)end;local _=false
local function al()if _ or I then return end;_=true
pcall(function()local a=require(af)if a and a.warn then
a.warn(ae,"No data card — session tokens/salts use the software RNG (degraded; not a CSPRNG)")end end)end
function H.salt(a)a=a or 16
local c="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"local b=#c;local function e(h)if h>=248 then return nil end
return c:sub((h%b)+1,(h%b)+1)end;local f=0xFFFFFFFFFFFFFFF0;local function g()
while true do local h=U()if
math.ult(h,f)then return c:sub((h%b)+1,(h%b)+1)end end end
if I then local i={}local h=1
while h<=a do
local k,j=pcall(I.random,a*2)if not k or not j then break end;for l=1,#j do if h>a then break end;local m=e(j:byte(l))if m then
i[h]=m;h=h+1 end end end;if h>a then return table.concat(i)end end;Q()local d={}for h=1,a do d[h]=g()end;return table.concat(d)end;local V=0
function H.token()al()V=V+1;return
H.hash(H.salt(32)..H.salt(16)..tostring(O.uptime())..
tostring(V))end
local function aa(a,b)local e=#b;local g={b:byte(1,e)}local c,f={},{}local d=#a
for h=1,d,256 do local k=
(h+255 <d)and(h+255)or d;local i=0;for j=h,k do i=i+1;f[i]=a:byte(j)~
g[((j-1)%e)+1]end
c[#c+1]=string.char(table.unpack(f,1,i))end;return table.concat(c)end;local ab=false
local function ac()if I then local c,b=pcall(I.random,16)if
c and type(b)==K and#b==16 then return b end end
Q()local a={}for b=1,2 do local c=U()for d=56,0,-8 do
a[#a+1]=string.char((c>>d)&0xFF)end end;return
table.concat(a)end;H._makeIv16=ac
local function ad(a)local b=L(a)return
(b:sub(1,32):gsub("..",function(c)return
string.char(tonumber(c,16))end))end
function H.encrypt(a,b)
if I then
local e,d=pcall(function()local f=ac()local g=I.encrypt(a,ad(b),f)return f..g end)if e and d then return d,"aes"end end
if not ab then ab=true
pcall(function()local d=require(af)if d then
d.warn(ae,"No data card — encryption falling back to XOR (not secure)")end end)end;local c=H.hash(b)return aa(a,c),"xor"end
function H.decrypt(a,b,c)if type(a)~=K or type(b)~=K then return nil end
if
c=="aes"then if not I then return nil end;if#a<17 then return nil end
local e,d=pcall(function()local f=a:sub(1,16)
local g=a:sub(17)return I.decrypt(g,ad(b),f)end)if e and d then return d end;return nil end;if c=="xor"then local d=H.hash(b)return aa(a,d)end;return nil end;function H.checksum(a)return H.hash(a)end;local R=64;local function W(a)return L(a)end
M=function(a,b)
if
#a>R then local j=W(a)local i={}for k=1,32 do
i[k]=string.char(tonumber(j:sub(k*2-1,k*2),16))end;a=table.concat(i)end;if#a<R then a=a..string.rep("\0",R-#a)end
local c,d={},{}for j=1,R do local i=a:byte(j)c[j]=string.char(i~0x36)
d[j]=string.char(i~0x5C)end
local f,g=table.concat(c),table.concat(d)local h=W(f..b)local e={}for j=1,32 do
e[j]=string.char(tonumber(h:sub(j*2-1,j*2),16))end
return W(g..table.concat(e))end;H.hmac=M;function H.sign(a,b)return M(b or"",a or"")end;return H