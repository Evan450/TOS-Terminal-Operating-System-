local H="the file stops early"local t={}
local v,x,u=string.byte,string.char,math.floor;local w=table.concat;t.MAX_CELLS=256*256
local D={0x00,0x33,0x66,0x99,0xCC,0xFF}local E={0x00,0x24,0x49,0x6D,0x92,0xB6,0xDB,0xFF}
local F={0x00,0x40,0x80,0xBF,0xFF}local y,B={},{}
do local a={}
for b=1,6 do for c=1,8 do for d=1,5 do
a[#a+1]=D[b]*65536+E[c]*256+F[d]end end end;for b=1,16 do a[#a+1]=b*0x0F0F0F end;table.sort(a)for b,d in ipairs(a)do y[
b-1]=d;B[d]=b-1 end end;t.PALETTE=y;local function C(a)local c=a%256;local d=(a-c)/256%256
return u(a/65536),u(d),c end;t.rgb=C
function t.to8(a,c,d)
local f=D[u(a*5/255+0.5)+1]local g=E[u(c*7/255+0.5)+1]local h=F[
u(d*4/255+0.5)+1]
local b=u(((a+c+d)/3)/15+0.5)if b<1 then b=1 elseif b>16 then b=16 end;local e=b*15;local i=(a-f)^2+ (c-g)^2+
(d-h)^2
local j=(a-e)^2+ (c-e)^2+ (d-e)^2;if j<i then return B[e*0x010101]end;return
B[f*65536+g*256+h]end;local G={}for a=0,255 do local c,d,e=C(y[a])
G[a]=u(c*0.299+d*0.587+e*0.114)end;t.LUMA=G
t.UPPER,t.LOWER,t.FULL="▀","▄","█"
function t.builder(a,b)local c={w=a,h=b,syms={},index={},cells={},lost=0}
function c:symbol(d)
local e=self.index[d]if e then return e end
if
#self.syms>=253 and d~=" "and d~="?"then self.lost=self.lost+1;return self:symbol("?")end;e=#self.syms+1;self.syms[e],self.index[d]=d,e;return e end;function c:set(d,e,f,g,h)
if d>=1 and d<=a and e>=1 and e<=b then self.cells[(e-1)*a+d]=
f*65536+g*256+h end end
function c:finish()
local h=self:symbol(" ")local i=h;local d,j={},self.cells;local e,f,g={},{},{}
for k=1,b do local l=(k-1)*a;for m=1,a do
local n=j[l+m]or i;local o=n%256;local p=(n-o)/256;local q=p%256
e[m],f[m],g[m]=x(u((p-q)/256)),x(u(q)),x(u(o))end
d[k]={bg=w(e),fg=w(f),sym=w(g)}end;return{w=a,h=b,syms=self.syms,rows=d,lost=self.lost}end;return c end
function t.pixelRow(a,b,c,d,e)local f,g,h={},{},{}
for i=1,c do local k,j=a[i],b[i]if k==j then f[i],g[i],h[i]=x(j),x(j),e else
f[i],g[i],h[i]=x(j),x(k),d end end;return{bg=w(f),fg=w(g),sym=w(h)}end
local function I(a,b)local c={pos=b}function c:u8()local d=v(a,self.pos)if not d then error(H,0)end;self.pos=
self.pos+1;return d end;function c:u16()
local d=self:u8()return d*256+self:u8()end
function c:char()
local d,e=self.pos,self:u8()local f=
(e<0x80 and 0)or(e<0xE0 and 1)or(e<0xF0 and 2)or 3;self.pos=d+f+1;if
self.pos-1 >#a then error(H,0)end;return a:sub(d,d+f)end;return c end
local function z(c,a,b)if b==0 then return a end;local e=b*256+a;local d=c[e]
if not d then local h,i,j=C(y[a])
local f=1-b/255;d=t.to8(h*f,i*f,j*f)c[e]=d end;return d end
local function J(a,c,d,e)local b={}
for f=1,e do
for g=1,d do local i,j,h=a:u8(),a:u8(),a:u8()local k=a:char()
if h==255 then
c:set(g,f,0,0,c:symbol(" "))else c:set(g,f,z(b,i,h),z(b,j,h),c:symbol(k))end end end end
local function K(a,d,c,e)local b={}
for f=1,a:u8()+c do local g=a:u8()
for f=1,a:u16()+c do local h=a:char()local i=
g==255 and d:symbol(" ")or d:symbol(h)
for f=1,a:u8()+c do
local j=a:u8()local k=g==255 and 0 or z(b,j,g)
for f=1,a:u8()+c do local l=a:u8()local m=
g==255 and 0 or z(b,l,g)
for f=1,a:u8()+c do local n=a:u8()+e;for f=1,a:u8()+c do d:set(
a:u8()+e,n,k,m,i)end end end end end end end;function t.method(a)
if type(a)=="string"and a:sub(1,4)=="OCIF"then return v(a,5)end end
function t.size(a)local b=t.method(a)
if b==5 then return v(a,6)*
256+v(a,7),v(a,8)*256+v(a,9),b elseif
b==6 or b==7 then return v(a,6),v(a,7),b elseif b==8 then return v(a,6)+1,v(a,7)+1,b end end
function t.decode(a)local c=t.method(a)if not c then return nil,"not a .pic file"end
if
c<5 or c>8 then return nil,
"OCIF method "..tostring(c).." is not one this reads (5 to 8)"end;if#a<9 then return nil,H end;local d,e=t.size(a)
if not d or d<1 or e<1 or d*e>
t.MAX_CELLS then return nil,
string.format("a %sx%s picture is not one this can hold",tostring(d),tostring(e))end;local f=t.builder(d,e)local g=I(a,c==5 and 10 or 8)
local h,i=pcall(function()
if c==5 then
J(g,f,d,e)else K(g,f,c==6 and 0 or 1,c==8 and 1 or 0)end end)if not h then return nil,tostring(i)end;return f:finish()end
local function A(a)local b={}for c in pairs(a)do b[#b+1]=c end;table.sort(b)return b end
function t.encode(a)local e,f=a.w,a.h;local c={"OCIF"}local function b(...)c[#c+1]=x(...)end
if
e>256 or f>256 then b(5,u(e/256),e%256,u(f/256),f%256)
for h=1,f do
local i=a.rows[h]for j=1,e do b(v(i.bg,j),v(i.fg,j),0)
c[#c+1]=a.syms[v(i.sym,j)]end end;return w(c)end;b(8,e-1,f-1)local d={}
for h=1,f do local i=a.rows[h]
for j=1,e do
local o,p,q=v(i.sym,j),v(i.bg,j),v(i.fg,j)local k=d[o]if not k then k={}d[o]=k end;local l=k[p]if not l then l={}k[p]=l end
local m=l[q]if not m then m={}l[q]=m end;local n=m[h]if not n then n={}m[h]=n end
n[#n+1]=j end end;local g=A(d)
b(0,0,u((#g-1)/256),(#g-1)%256)
for i,h in ipairs(g)do c[#c+1]=a.syms[h]local j=A(d[h])b(#j-1)
for i,k in ipairs(j)do
local l=A(d[h][k])b(k,#l-1)for i,m in ipairs(l)do local n=A(d[h][k][m])b(m,#n-1)
for i,o in ipairs(n)do
local p=d[h][k][m][o]b(o-1,#p-1)for q=1,#p do b(p[q]-1)end end end end end;return w(c)end
local function L(a)
for c,b in ipairs(a.syms)do if b~=t.UPPER and b~=t.LOWER and b~=t.FULL and
b~=" "then return false end end;return true end
function t.fit(a,b,c,d)local e=math.min(c/a,d/b)if e>=1 then return a,b end;return
math.max(1,u(a*e)),math.max(1,u(b*e))end
function t.scale(a,b,c)local j,e=a.w,a.h;local d={}local f={}for k=1,b do
f[k]=u((k-0.5)*j/b)+1 end
if L(a)then local l,m;local n={}local k=t.builder(1,1)
l,m=k:symbol(t.UPPER),k:symbol(" ")for M,N in ipairs(a.syms)do n[M]=N end;local r,s=x(l),x(m)
local function o(M,N)local P=M%2
local O=a.rows[u((M+1)/2)]
for Q=1,b do local S=f[Q]local R=n[v(O.sym,S)]
local T=R==t.FULL or
(R==t.UPPER and P==1)or(R==t.LOWER and P==0)N[Q]=v(T and O.fg or O.bg,S)end end;local p,q={},{}for M=1,c do
o(u((M-0.75)*e/c*2)+1,p)o(u((M-0.25)*e/c*2)+1,q)
d[M]=t.pixelRow(p,q,b,r,s)end
return{w=b,h=c,syms=k.syms,rows=d,lost=a.lost}end;local g,h,i={},{},{}
for k=1,c do
local l=a.rows[u((k-0.5)*e/c)+1]for m=1,b do local n=f[m]
g[m],h[m],i[m]=l.bg:sub(n,n),l.fg:sub(n,n),l.sym:sub(n,n)end
d[k]={bg=w(g),fg=w(h),sym=w(i)}end;return{w=b,h=c,syms=a.syms,rows=d,lost=a.lost}end;return t