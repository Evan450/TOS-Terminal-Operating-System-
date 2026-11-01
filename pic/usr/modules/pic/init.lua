local Z="^https?://"local P=require("component")
local N=require("computer")local F=require("pic.ocif")local O=require("pic.png")
local T=require("pic.convert")local Q=internet;local G={}local R,H=string.byte,math.floor;local K,L=255,0
local _=2*1024*1024;local I
do local a,b=pcall(require,"shell.keys")I=a and b or nil end;local function aa(b,a)if I and I.is then return I.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function U()
if
I and I.label then local a=I.label("quit")if a~=""then return a end end;return"^Q"end
local J={UP=200,DOWN=208,LEFT=203,RIGHT=205,PGUP=201,PGDN=209,HOME=199}local ab={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5}local function V(a,b,c)return
c>= (ab[
(b%4)*4+ (a%4)+1]+0.5)*16 end
local function W(c,b,a,d,e)local f=F.LUMA
if a==F.UPPER or a==
F.LOWER or a==F.FULL or a==" "then
local g,h=c,c
if a==F.FULL then g,h=b,b elseif a==F.UPPER then g=b elseif a==F.LOWER then h=b end;local i,j=V(d,e*2,f[g]),V(d,e*2+1,f[h])
if i and j then return K,K," "end;if i then return L,K,F.UPPER end;if j then return L,K,F.LOWER end;return L,L," "end;if f[c]>=128 then return K,L,a end;return L,K,a end;G.monoCell=W
function G.paint(a,b,f,c,g,i,d,j,k,e)local h,n=F.PALETTE,b.syms;local l,m
for o=0,j-1 do local p=b.rows[c+o]
if p then
local u,v,w=p.bg,p.fg,p.sym
local function t(x)local y=f+x;local z=R(w,y)if not z then return nil end;local A,B,C=R(u,y),R(v,y),n[z]if k then return
W(A,B,C,y,c+o)end;return A,B,C end;local s,r={},{}local q=0
while q<d do local z,D,C=t(q)if not z then break end;local E,A=q,{C}
local y=C~=" "and D or nil;q=q+1
while q<d do local al,aj,ak=t(q)if al~=z then break end;if ak~=" "then
if y==nil then y=aj elseif aj~=y then break end end;A[#A+1]=ak;q=q+1 end;local B=z*512+ (y or 256)local x=s[B]
if not x then x={}s[B]=x;r[#r+1]=B end;x[#x+1]=E;x[#x+1]=table.concat(A)end;table.sort(r)
for y,x in ipairs(r)do local z=x%512;local A=H((x-z)/512)if A~=m then
a.setBackground(h[A])m=A end
if z~=256 and z~=l then a.setForeground(h[z])l=z end;local B=s[x]for C=1,#B,2 do a.set(g+B[C],i+o,B[C+1])end end end;if e then e()end end end
local function S(a)
if a:match(Z)then
if type(Q)~="table"or type(Q.get)~="function"then return
nil,"no internet here: this needs an internet card"end;local d,e=Q.get(a,{maxBytes=_})
if not d then return nil,tostring(e)end;return d end;if
not(fs and fs.exists and fs.exists(a))then return nil,"no such file: "..a end
local c,b=pcall(fs.readFile,a)if not c or type(b)~="string"then return nil,
"cannot read "..a..": "..tostring(b)end;return b end
function G.decode(a,b)if F.method(a)then return F.decode(a)end;if O.is(a)then
return T.fromPNG(a,b)end;return nil,"not a picture this can read (.pic or .png)"end
local function ac(a)if a:match(Z)or not(fs and fs.isDirectory)then
return nil end;local c,d=pcall(fs.isDirectory,a)if not c or
not d then return nil end;local b={}for f,e in ipairs(fs.list(a)or{})do
local g=e:lower()
if g:match("%.pic$")or g:match("%.png$")then b[#b+1]=
(a:gsub("/+$","")).."/"..e end end
table.sort(b)return b end
local function ad()local d=P.list and P.list("gpu")()
if not d then return nil,"no GPU"end;local g,a=pcall(P.proxy,d)
if not g or not a then return nil,"cannot open the GPU"end;local c,e=a.getResolution()if not c or c<20 or e<5 then
return nil,"this screen is too small"end;local h,b=pcall(a.getDepth)
b=(h and type(b)==
"number")and b or 1;local f={gpu=a,W=c,H=e,depth=b,mono=b<=1}
if b==4 and a.getPaletteColor then local i={}
for j=0,15 do
local l,k=pcall(a.getPaletteColor,j)if l and type(k)=="number"then i[#i+1]=k end end;if#i==16 then f.palette=i end end;return f end
local function M(a)return a:match("([^/]+)/*$")or a end
local function X()local a=N.uptime()return function()local b=N.uptime()
if b-a>=1 then N.pullSignal(0)a=b end end end
local function ae()local a={N.pullSignal()}
if a[1]=="key_down"then return a[3],a[4],a[1]end;if a[1]=="interrupted"then return 17,nil,a[1]end;return nil,nil,a[1]end
local function Y(b,a,c)local h,v=ad()if not h then b("pic: "..v,0xFF6600)return end
local e,i,k=h.gpu,h.W,h.H;local g=c or 1;local q=true;local l=false;local f,d,s;local m,n=1,1;local u=X()local function t(w)
e.setBackground(0xFFFFFF)e.setForeground(0x000000)e.fill(1,k,i,1," ")
e.set(2,k,w:sub(1,i-2))end;local function r()
return i,q and k-1 or k end
local function o()local x,y=r()local z=M(a[g])t("Reading "..z)
local A,w=S(a[g])f,d,s=nil,nil,w
if A then local B=l and 2 or 1;local C=-1
f,w=G.decode(A,{maxW=x*B,maxH=y*B,depth=h.depth,palette=h.palette,progress=function(D,E)
local aj=H(D*100/E)if aj~=C and aj%5 ==0 then C=aj
t(string.format("Reading %s  %d%%",z,aj))end;u()end})s=w end
if f and not l then local B,C=F.fit(f.w,f.h,x,y)d=
(B==f.w and C==f.h)and f or F.scale(f,B,C)else d=f end;m,n=1,1 end
local function j()local w,x=r()e.setBackground(0x000000)
e.setForeground(0xFFFFFF)e.fill(1,1,i,k," ")local y=M(a[g])
if not d then e.set(2,2,("Cannot show "..y):sub(1,
i-2))e.set(2,3,tostring(s):sub(1,
i-2))else
local z,A=math.min(d.w,w),math.min(d.h,x)local B=math.max(0,H((w-d.w)/2))
local C=math.max(0,H((x-d.h)/2))G.paint(e,d,m,n,B+1,C+1,z,A,h.mono,u)end
if q then local z={y}if d then z[#z+1]=d.w.."x"..d.h end;if#a>1 then z[#z+1]=g.."/"..
#a end
z[#z+1]=
(l and"F Fit"or"F Full")..
" · B Bar".. (#a>1 and" · N Next · P Prev"or"").." · "..
U().." Quit"t(table.concat(z,"  "))end end
local function p(w,x)if not d then return end;local A,B=r()
local y=math.max(1,math.min(m+w,d.w-A+1))local z=math.max(1,math.min(n+x,d.h-B+1))if y~=m or z~=
n then m,n=y,z;j()end end;o()j()
while true do local x,w,y=ae()
if y=="tos_focus"then j()elseif x or w then local z=x and x>0 and
string.char(x):lower()or""local A,B=r()
if
aa(x,w)or z=="q"then break elseif w==J.LEFT then
p(-math.max(1,H(A/4)),0)elseif w==J.RIGHT then p(math.max(1,H(A/4)),0)elseif w==J.UP then p(0,-
math.max(1,H(B/4)))elseif w==J.DOWN then
p(0,math.max(1,H(B/4)))elseif w==J.HOME then
p(- (d and d.w or 0),- (d and d.h or 0))elseif z=="f"then l=not l;o()j()elseif z=="b"then q=not q;o()j()elseif
(z=="n"or w==J.PGDN)and#a>1 then g=g%#a+1;o()j()elseif(z=="p"or w==J.PGUP)and#a>1 then g=(g-2)%
#a+1;o()j()end end end;e.setBackground(0x000000)e.setForeground(0xFFFFFF)
e.fill(1,1,i,k," ")end
local function af(a)a("pic — pictures on a text screen",0xFFFF55)
a("  pic <file>                  show a .pic or a .png",0xFFFFFF)
a("  pic <directory>             show the pictures in it, N and P to move",0xFFFFFF)
a("  pic <http://...>            fetch one and show it",0xFFFFFF)
a("  pic info <file>             its format and size",0xFFFFFF)
a("  pic convert <in.png> <out.pic> [--width N] [--height N] [--tier 1|2|3] [--no-dither]",0xFFFFFF)
a("  Keys: F full size or fit, arrows pan, B bar, "..U().." quit",0xAAAAAA)end
local function ag(b,a)local d=b[2]
if not d then a("Which file?",0xFF5555)return end;local c,e=S(d)if not c then a(e,0xFF5555)return end
if F.method(c)then
local f,g,h=F.size(c)
a(string.format("%s: MineOS .pic (OCIF %d), %sx%s cells, %d bytes",M(d),h,tostring(f),tostring(g),#c),0xFFFFFF)elseif O.is(c)then local f,g=O.size(c)
a(string.format("%s: PNG, %sx%s pixels, %d bytes",M(d),tostring(f),tostring(g),#c),0xFFFFFF)else
a("Not a picture this can read (.pic or .png).",0xFF5555)end end
function G.parseConvert(a)local c={maxW=160,maxH=50,depth=8,dither=true}local d={}local b=2
while b<=#a do
local e=a[b]
if e=="--width"or e=="--height"or e=="--tier"then
local f=tonumber(a[b+1])if not f or f<1 then return nil,e.." needs a number"end
if
e=="--width"then c.maxW=f elseif e=="--height"then c.maxH=f elseif f<=1 then c.depth=1 elseif f==2 then c.depth=4 else c.depth=8 end;b=b+2 elseif e=="--no-dither"then c.dither=false;b=b+1 elseif e:sub(1,2)=="--"then return nil,
"unknown option "..e else d[#d+1]=e;b=b+1 end end;if#d~=2 then return nil,"pic convert <in.png> <out.pic>"end;return c,
d[1],d[2]end
local function ah(b,a)local d,e,i=G.parseConvert(b)if not d then a(e,0xFF5555)return end
local f,g=S(e)if not f then a(g,0xFF5555)return end;if not O.is(f)then
a(M(e).." is not a PNG.",0xFF5555)return end;local l=X()d.progress=function()l()end
local c;c,g=T.fromPNG(f,d)if not c then
a("Cannot convert: "..tostring(g),0xFF5555)return end;local j=F.encode(c)if not
(fs and fs.writeFile)then
a("Nothing here can write a file.",0xFF5555)return end
local k,h,m=pcall(fs.writeFile,i,j)if not k or h==false or h==nil then
a("Not saved: "..tostring(k and
(m or"the write was refused")or h),0xFF5555)return end
a(string.format("Wrote %s: %dx%d cells, %d bytes.",i,c.w,c.h,
#j),0x55FF55)end
local function ai(b,a)b=b or{}a=a or print;local c=b[1]if
not c or c=="help"or c=="--help"or c=="-h"then af(a)return end;if
c=="info"then ag(b,a)return end;if c=="convert"then ah(b,a)return end
local d=ac(c)
if d then if#d==0 then
a("No .pic or .png files in "..c,0xFF5555)return end;Y(a,d)return end;if not c:match(Z)and not
(fs and fs.exists and fs.exists(c))then
a("No such file: "..c,0xFF5555)return end;Y(a,{c})end;return{commands={pic=ai},text=G}