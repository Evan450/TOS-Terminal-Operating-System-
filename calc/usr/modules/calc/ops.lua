local x="number"local m=require("calc.sheet")local n={}local o,r=m._key,m.unkey
local function s(b,a)
local c=b:match("^%$?%a+%$?%d+",a)if not c then return nil end;if b:sub(a+#c,a+#c):match("[%w_]")then
return nil end;if not m.parseRef(c)then return nil end
return c end
function n.rewrite(a,b,c)local g,d,h,f={},1,#a,false;local function e(i)g[#g+1]=i end
while d<=h do local i=a:sub(d,d)
if i==
'"'then local k=d+1
while k<=h do if a:sub(k,k)=='"'then
if a:sub(k+1,k+1)=='"'then k=k+2 else break end else k=k+1 end end;e(a:sub(d,k))d=k+1 elseif i:match("%d")or(i=="."and
a:sub(d+1,d+1):match("%d"))then local j=
a:match("^%d*%.?%d+",d)or a:match("^%d+",d)local k=a:match("^[eE][%+%-]?%d+",
d+#j)if k then j=j..k end;e(j)d=d+#j elseif i=="@"then local j=
a:match("^@[%a_][%w_]*",d)or"@"e(j)d=d+#j elseif i=="#"then local j=
a:match("^#%a+[#!]",d)or"#"e(j)d=d+#j elseif i=="$"or i:match("%a")then
local j=s(a,d)
if not j then local k=a:match("^[%a_][%w_]*",d)or i;e(k)d=d+#k else
local k=d+#j;local l=""if a:sub(k,k+1)==".."then l=".."elseif
a:sub(k,k)==":"or a:sub(k,k)=="."then l=a:sub(k,k)end;local y=
l~=""and s(a,k+#l)or nil;local B,C,z,A=m.parseRef(j)
if y then
local G,H,D,E=m.parseRef(y)local F,I,J,K=c(B,C,G,H,z,A,D,E)if F==nil then e(m.E_REF)f=true else local L=m.refName(F,I,z,A)..l..
m.refName(J,K,D,E)
if L~=j..l..y then f=true end;e(L)end
d=k+#l+#y else local D,E=b(B,C,z,A)if D==nil then e(m.E_REF)f=true else local F=m.refName(D,E,z,A)if F~=j then
f=true end;e(F)end;d=k end end else e(i)d=d+1 end end;return table.concat(g),f end;local function p(a,b)return
a>=1 and b>=1 and a<=m.MAX_COLS and b<=m.MAX_ROWS end
function n.shift(a,b,c)
local e=m.classify(a)if e~="formula"then return a end
local function d(f,g,h,i)local j=h and f or f+b
local k=i and g or g+c;if not p(j,k)then return nil end;return j,k end;return
(n.rewrite(a,d,function(f,g,h,i,j,k,l,y)local z,B=d(f,g,j,k)local A,C=d(h,i,l,y)
if not z or not A then return nil end;return z,B,A,C end))end
local function q(a,c,b)local d=0;for f,e in pairs(a.cells)do
if m.classify(e)=="formula"then local g,h=n.rewrite(e,c,b)if
h then a.cells[f]=g;d=d+1 end end end
for f,e in
pairs(a.names)do local g,h,i,j=b(e[1],e[2],e[3],e[4])if g then
a.names[f]={math.min(g,i),math.min(h,j),math.max(g,i),math.max(h,j)}else a.names[f]=nil end end;return d end
local function t(a,b,c,d,e)local f,g={},{}
for h=b,d do for i=c,e do local j=o(h,i)
f[#f+1]={c=h,r=i,raw=a.cells[j],fmt=a.fmt[j]}end end;return f end
function n.copy(e,f,g,h,i,a,b,c,d)c,d=c or a,d or b;local l,y=h-f+1,i-g+1;local z=t(e,f,g,h,i)local j={}
if
l==1 and y==1 then for A=a,c do for B=b,d do j[#j+1]={A,B}end end elseif y==1 then for A=b,d do
j[#j+1]={a,A}end elseif l==1 then for A=a,c do j[#j+1]={A,b}end else j[1]={a,b}end;local k=0
for B,A in ipairs(j)do local C,D=A[1]-f,A[2]-g
for B,E in ipairs(z)do local F,G=E.c+C,E.r+D;if p(F,G)then local H=E.raw and
n.shift(E.raw,C,D)or nil;m.set(e,F,G,H)
e.fmt[o(F,G)]=E.fmt;k=k+1 end end end;return k end
function n.move(a,b,c,f,g,d,e)local i,j=d-b,e-c;if i==0 and j==0 then return 0 end;local y,z=f-b+1,g-c+1
if not p(
d+y-1,e+z-1)then return nil,"the block would fall off the sheet"end
local function A(h,C)return h>=b and h<=f and C>=c and C<=g end
local function B(h,C)return h>=d and h<d+y and C>=e and C<e+z end
local function k(h,C)if A(h,C)then return h+i,C+j end;if B(h,C)then return nil end;return h,C end;local l=t(a,b,c,f,g)
q(a,k,function(h,C,D,E)local F,H=k(h,C)local G,I=k(D,E)
if not F or not G then return nil end;return F,H,G,I end)for C,h in ipairs(l)do local D=o(h.c,h.r)h.raw=a.cells[D]a.cells[D]=nil
a.fmt[D]=nil end
for C,h in ipairs(l)do
m.set(a,h.c+i,h.r+j,h.raw)a.fmt[o(h.c+i,h.r+j)]=h.fmt end;return#l end
local function u(a,c,b)local d,e={},{}for f,g in pairs(a.cells)do d[f]=g end
for g,h in pairs(a.fmt)do e[g]=h end;a.cells,a.fmt={},{}for f,g in pairs(d)do local i,j=r(f)local h,k=b(i,j)
if h then a.cells[o(h,k)]=g end end;for g,h in pairs(e)do local i,j=r(g)local f,k=b(i,j)if f then
a.fmt[o(f,k)]=h end end
if c=="col"then local f={}for g,h in
pairs(a.colw)do local i=b(g,1)if i then f[i]=h end end;a.colw=f end end
local function v(a)local function c(f,g)if a=="row"then return g end;return f end;local function b(g,h,f)
if a=="row"then return g,f end;return f,h end
local function d(g,h,f)f=f or 1
local function i(j,k)local l=c(j,k)
if l>=h then l=l+f end;local y,z=b(j,k,l)if not p(y,z)then return nil end;return y,z end
q(g,i,function(l,y,j,k)local A,C=i(l,y)local z,B=i(j,k)if not A then return nil end
if not z then z,B=b(j,k,
a=="row"and m.MAX_ROWS or m.MAX_COLS)end;return A,C,z,B end)u(g,a,i)end
local function e(h,f,g)g=g or 1;local i=f+g-1
local function j(k,l)local y=c(k,l)if y>=f and y<=i then return nil end;if y>i then
y=y-g end;return b(k,l,y)end
q(h,j,function(k,l,z,A)local y,B=c(k,l),c(z,A)if y>B then y,B=B,y end;local C=(y>=f and y<=i)and f or(y>i and y-
g or y)
local D=(
B>=f and B<=i)and(f-1)or(B>i and B-g or B)if C>D then return nil end;local E,F=b(k,l,C)local G,H=b(z,A,D)return E,F,G,H end)u(h,a,j)end;return d,e end;n.insertRows,n.deleteRows=v("row")n.insertCols,n.deleteCols=v("col")
local function w(c,d,e)local a=(c==
nil or c=="")and 3 or
(type(c)==x and 1 or 2)
local f=
(d==nil or d=="")and 3 or(type(d)==x and 1 or 2)if a~=f then return(a<f)and-1 or 1 end;if a==3 then return 0 end;if a==2 then
c,d=tostring(c):lower(),tostring(d):lower()end;if c==d then return 0 end;local b=c<d
if not e then b=not b end;return b and-1 or 1 end
function n.sort(a,c,d,e,f,g,h,b,i)local l=m.evaluator(a)local j={}for y=d,f do local z=l.get(g,y)
local A=b and l.get(b,y)or nil;if m.isErr(z)then z=z.e end;if m.isErr(A)then A=A.e end
j[#j+1]={r=y,k1=z,k2=A}end
for y=2,#j do
local A=j[y]local z=y-1
while z>=1 do local B=w(A.k1,j[z].k1,h~=false)if B==0 and b then B=w(A.k2,j[z].k2,i~=
false)end;if B<0 then j[z+1]=j[z]
z=z-1 else break end end;j[z+1]=A end;local k={}
for z,y in ipairs(j)do local A={}for B=c,e do local C=o(B,y.r)
A[B]={raw=a.cells[C],fmt=a.fmt[C]}end;k[#k+1]={from=y.r,cells=A}end
for z,y in ipairs(k)do local A=d+z-1;for B=c,e do local C=y.cells[B]local D=
C.raw and n.shift(C.raw,0,A-y.from)or nil;m.set(a,B,A,D)
a.fmt[o(B,A)]=C.fmt end end;return#j end
function n.fill(c,d,e,f,g,h,a,b)a=a or 1;local i,j=h,0
for k=d,f do for l=e,g do if b and
((a>=0 and i>b)or(a<0 and i<b))then return j end
m.set(c,k,l,m.toStr(i))j=j+1;i=i+a end end;return j end
function n.values(a,b,c,d,e,f,g)local i=m.evaluator(a)local h={}
for j=b,d do
for k=c,e do local l=i.get(j,k)local y
if l==nil then y=nil elseif
m.isErr(l)then y="'"..l.e elseif type(l)==x then y=m.toStr(l)else y="'"..tostring(l)end;h[#h+1]={c=f+ (j-b),r=g+ (k-c),raw=y}end end;for k,j in ipairs(h)do m.set(a,j.c,j.r,j.raw)end;return#h end;function n.erase(a,b,c,d,e)local f=0
for g=b,d do for h=c,e do
if a.cells[o(g,h)]then a.cells[o(g,h)]=nil;f=f+1 end end end;return f end
function n.format(a,b,c,d,e,f)for g=b,d
do for h=c,e do a.fmt[o(g,h)]=f end end end
function n.label(a,b,c,d,e,f)local g=0
for h=b,d do
for i=c,e do local j=a.cells[o(h,i)]if j then local k,l,y=m.classify(j)
if k=="label"and y~=
"REP"then a.cells[o(h,i)]=f..l;g=g+1 end end end end;return g end
function n.validName(a)
if
type(a)~="string"or not a:match("^%a[%w_]*$")or#a>15 then return false end;if m.parseRef(a)then return false end
if m.FUNCS[a:upper()]then return false end
if a:upper()=="TRUE"or a:upper()=="FALSE"then return false end;return true end;return n