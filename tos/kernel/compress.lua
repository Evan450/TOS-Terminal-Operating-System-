local F,z="compress","string"local A=require("component")local s={}local v="TCZ1"
local B=1;local C=4096;local G=256;local w=nil;local t=false;local u=nil;local function y(a)
return string.char((a>>24)&0xFF,(a>>16)&0xFF,(
a>>8)&0xFF,a&0xFF)end;local function H(a)return
string.char((a>>8)&0xFF,a&0xFF)end;local function D(b,a)
local e,f,g,h=b:byte(a,a+3)return
((e<<24)| (f<<16)| (g<<8)|h)&0xFFFFFFFF end;local function I(b,a)local c,d=b:byte(a,
a+1)return(c<<8)|d end
function s.init(a)a=a or
{}u=a.log or u;w,t=nil,false;local b
do
local d,c=pcall(require,"kernel.datacard")if d and c and c.detect then b=c.detect()end end
if not b then b={present=false,caps={},name=nil}
pcall(function()
for c in A.list("data")do
local d=A.proxy(c)
if d then b.present=true
b.caps={deflate=d.deflate~=nil and d.inflate~=nil}b.proxy=d
b.name=b.caps.deflate and"data card"or"data card (no deflate)"return end end end)end
if b and b.present and b.caps.deflate then w,t=b.proxy,true end
if u and u.info then
if t then
u.info(F,"Data card present ("..
(b.name or"?")..") — deflate/inflate available")elseif b and b.present then
u.info(F,"Data card present ("..
(b.name or"?")..") but no deflate/inflate — compression store-only")else
u.info(F,"No data card — compression disabled (store-only)")end end;return t end;function s.available()return t end;function s.isPacked(a)return
type(a)==z and#a>=9 and a:sub(1,4)==v end
local function J(a)return v..string.char(0)..
y(#a)..a end;local x=nil
local function E()if x==nil then local b,a=pcall(require,"kernel.process")
x=(b and a and
a.yieldCooperative)and a or false end;if x then
x.yieldCooperative()end end
function s.pack(a)if type(a)~=z then return nil,"data must be a string"end
local b=#a
if t and b>=G then local d,e,f={},0,true;for h=1,b,C do E()local j=a:sub(h,h+C-1)
local k,i=pcall(w.deflate,j)if not k or type(i)~=z then f=false;break end;d[#d+1]=i
e=e+#i end
local g=11+4*#d
if f and(e+g)<b then local h={v,string.char(B),y(b),H(#d)}for k,j in
ipairs(d)do h[#h+1]=y(#j)h[#h+1]=j end
local i=table.concat(h)return i,"deflate",b,#i end end;local c=J(a)return c,"stored",b,#c end
function s.unpack(a)
if not s.isPacked(a)then return nil,"not a TCZ blob"end;local f=a:byte(5)local d=D(a,6)
if(f&B)==0 then local h=a:sub(10)if#h~=d then
return nil,"stored length mismatch"end;return h end;if not t then return nil,"data card required to decompress"end;if#
a<11 then return nil,"truncated blob"end;local b=10;local g=I(a,b)b=b+2
local c={}
for h=1,g do E()if b+3 >#a then return nil,"truncated blob"end;local i=D(a,b)b=b+4;local j=a:sub(b,
b+i-1)b=b+i
if#j~=i then return nil,"truncated chunk"end;local l,k=pcall(w.inflate,j)if not l or type(k)~=z then
return nil,"inflate failed"end;c[#c+1]=k end;local e=table.concat(c)
if#e~=d then return nil,"length mismatch after inflate"end;return e end;s.MAGIC=v;return s