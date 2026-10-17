local n="string"local m={}local o=64
local function p(a,d,e,b,c)if d>e then
error("serialization exceeds max depth "..e,0)end;local f=type(a)
if f==n then
return string.format("%q",a)elseif f=="number"then return tostring(a)elseif f=="boolean"then return tostring(a)elseif f=="table"then
c=c or{}
if c[a]then error("cycle detected in table serialization",0)end;c[a]=true;local g={}
local i=b and string.rep("  ",d+1)or""local j=b and string.rep("  ",d)or""
local h=b and",\n"or","
for k,l in pairs(a)do local y
if type(k)==n then
y="["..string.format("%q",k).."]"elseif type(k)=="number"then y="["..k.."]"else y="["..
string.format("%q",tostring(k)).."]"end;local z=b and" = "or"="
g[#g+1]=i..y..z..p(l,d+1,e,b,c)end;c[a]=nil;if b then return
"{\n"..table.concat(g,h).."\n"..j.."}"else
return"{"..table.concat(g,h).."}"end end;return"nil"end;function m.encode(a)return"return "..p(a,0,o,true)end;function m.compact(a)return
p(a,0,o,false)end;local q=o;local r=10000;local t,u,v,s=72,32,48,32
local function w(a,b)local c=1;local d=#a
local h=0;local j=b and b.maxCost;local z=b and b.maxKeys;local A,B,k=0,0,nil;local function l(I)A=A+I
if A>j then error(
"Decode budget exceeded ("..j..")")end end
local function e()
while c<=d do local I=a:byte(c)
if
I==32 or I==9 or I==10 or I==13 then c=c+1 elseif
I==45 and a:byte(c+1)==45 then c=c+2;local J
if a:byte(c)==91 then local K,L=c+1,0
while a:byte(K)==61 do L=L+1;K=K+1 end;if a:byte(K)==91 then J=L;c=K+1 end end;if J then local K="]"..string.rep("=",J).."]"
local L=a:find(K,c,true)c=L and(L+#K)or(d+1)else
while c<=d and a:byte(c)~=10 do c=c+1 end end else break end end end
local function D()e()return c<=d and a:sub(c,c)or nil end;local function i(I)e()if c<=d and a:sub(c,c)==I then c=c+1;return true end
return false end;local function y(I)
if not i(I)then error("Expected '"..I..
"' at position "..c)end end
local function f(I)e()
if a:sub(c,c+#I-1)==I then local K=
c+#I;if K>d then c=K;return true end;local J=a:byte(K)if
not(

(J>=48 and J<=57)or(J>=65 and J<=90)or(J>=97 and J<=122)or J==95)then c=K;return true end end;return false end;local g
local function E()e()local J=a:sub(c,c)if J~='"'and J~="'"then
error("Expected string at position "..c)end;c=c+1
local K=(J=='"')and'["\\]'or"['\\]"local I=nil
while true do local L=a:find(K,c)if not L then c=d+1;break end;local M=
(L>c)and a:sub(c,L-1)or nil
if a:byte(L)~=92 then c=L+1
if not I then return M or""end;if M then I[#I+1]=M end;return table.concat(I)end;I=I or{}if M then I[#I+1]=M end;c=L
do c=c+1;if c>d then
error("Unterminated escape")end;local N=a:sub(c,c)
if N=="n"then I[#I+1]="\n"elseif N=="t"then
I[#I+1]="\t"elseif N=="r"then I[#I+1]="\r"elseif N=="\\"then I[#I+1]="\\"elseif N=='"'then I[#I+1]='"'elseif N=="'"then
I[#I+1]="'"elseif N=="a"then I[#I+1]="\a"elseif N=="b"then I[#I+1]="\b"elseif N=="f"then I[#I+1]="\f"elseif N=="v"then
I[#I+1]="\v"elseif N=="\n"or N=="\r"then I[#I+1]="\n"elseif N:match("%d")then local O=N
for P=1,2 do
local Q=a:sub(c+1,c+1)if Q:match("%d")then O=O..Q;c=c+1 else break end end;I[#I+1]=string.char(tonumber(O))elseif N=="x"then
local O=a:sub(c+1,c+2)c=c+2;I[#I+1]=string.char(tonumber(O,16))else
I[#I+1]=N end;c=c+1 end end;error("Unterminated string")end
local function C()e()local K=c;if a:sub(c,c)=="-"then c=c+1 end
if a:sub(c,c+1)=="0x"or a:sub(c,c+
1)=="0X"then c=c+2;while c<=d and
a:sub(c,c):match("[%da-fA-F]")do c=c+1 end else while c<=d and
a:sub(c,c):match("%d")do c=c+1 end;if
c<=d and a:sub(c,c)=="."then c=c+1
while c<=d and a:sub(c,c):match("%d")do c=c+1 end end
if c<=d and(a:sub(c,c)=="e"or
a:sub(c,c)=="E")then c=c+1;if
c<=d and(
a:sub(c,c)=="+"or a:sub(c,c)=="-")then c=c+1 end;while
c<=d and a:sub(c,c):match("%d")do c=c+1 end end end;local J=a:sub(K,c-1)local I=tonumber(J)if not I then
error("Invalid number: "..J)end
if
I~=I or I==math.huge or I==-math.huge then error("non-finite number rejected: "..J)end;return I end
local function F()e()local J=c;if c>d then return nil end;local I=a:byte(c)if not
((I>=65 and I<=90)or(
I>=97 and I<=122)or I==95)then return nil end;c=c+1
while
c<=d do I=a:byte(c)if

(I>=48 and I<=57)or(I>=65 and I<=90)or(I>=97 and I<=122)or I==95 then c=c+1 else break end end;local K=a:sub(J,c-1)e()
if c<=d and a:byte(c)==61 then return K end;c=J;return nil end
local function G()y("{")h=h+1;if h>q then
error("Max table nesting depth exceeded ("..q..")")end;if j then l(t)end;local I={}local J=1;local K=0
while true do if i("}")then
h=h-1;return I end;K=K+1;if K>r then
error("Max table entries exceeded ("..r..")")end;local L,M;local N=false;if D()=="["then i("[")L=g()y("]")
e()y("=")M=g()else local O=F()
if O then y("=")L=O;M=g()else M=g()L=J;J=J+1;N=true end end;if L~=nil and
rawget(I,L)~=nil then
error("Duplicate key in table literal at position "..c)end
if j then l(N and u or v)if
type(M)==n then l(s+#M)end;if type(L)==n then k=k or{}
if not k[L]then k[L]=true;B=B+1;if z and
B>z then
error("Too many distinct keys ("..z..")")end;l(s+32+#L)end end end;I[L]=M;if not i(",")then i(";")end end end
g=function()e()
if c>d then error("Unexpected end of input")end;local I=a:sub(c,c)
if I=="{"then return G()elseif I=='"'or I=="'"then return E()elseif I=="-"then local J=c+1 <=d and
a:sub(c+1,c+1)or""e()if J:match("[%d.]")then return C()elseif
f("-inf")then
error("non-finite number (-inf) rejected at position "..c)else return C()end elseif
I:match("%d")then return C()elseif f("true")then return true elseif f("false")then return false elseif f("nil")then return nil elseif
f("inf")or f("math.huge")then
error("non-finite number (inf) rejected at position "..c)elseif f("nan")then
error("non-finite number (nan) rejected at position "..c)else
error("Unexpected character '"..I.."' at position "..c)end end;local function H()e()f("return")return g()end;return
{parse=H,skipWS=e,pos=function()return c end}end;local x=256*1024
function m.decode(a,b)
if not a or a==""then return nil,"empty input"end;if type(a)~=n then return nil,"input must be a string"end;local c=(b and
b.maxBytes)or x
if#a>c then return nil,"input too large ("..
#a.." > "..c..")"end;if a:match("^%s*$")then return nil,"empty input"end;local e=a
local f,d=pcall(function()
local g=w(e,b)return g.parse()end)if not f then return nil,tostring(d)end;return d end
function m.loadFile(a,b)if not a or not a.exists(b)then return nil end
local c,d=a.readFile(b)if not c then return nil,d end;return m.decode(c)end
function m.saveFile(a,b,c)if not a then return false,"FS not initialized"end
local d=m.encode(c)if a.writeFileAtomic then return a.writeFileAtomic(b,d)end;return
a.writeFile(b,d)end;return m