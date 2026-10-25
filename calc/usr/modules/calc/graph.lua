local g=require("calc.sheet")local e={}e.SERIES={"a","b","c"}
e.BAR={full="\226\150\136",half="\226\150\132"}e.MONO_BAR={a="#",b="=",c="%"}e.POINT={a="*",b="o",c="+"}
function e.values(b,c,a,d)if not a or
a==""then return nil end;local j,l,m,n
if b.names[a:upper()]then
local o=b.names[a:upper()]j,l,m,n=o[1],o[2],o[3],o[4]else j,l,m,n=g.parseRange(a)end;if not j then return nil end;local k={}local i=0
if(n-l)>= (m-j)then
for o=l,n do for p=j,m do i=i+1
local q=c.get(p,o)
if d then k[i]=
(q~=nil and not g.isErr(q))and g.toStr(q)or""else k[i]=
type(q)=="number"and q or nil end end end else
for o=j,m do for p=l,n do i=i+1;local q=c.get(o,p)
if d then
k[i]=
(q~=nil and not g.isErr(q))and g.toStr(q)or""else k[i]=type(q)=="number"and q or nil end end end end;k.n=i;return k end
function e.collect(a,b)local d=a.graph or{}
local c={type=d.type or"bar",title1=d.title1,title2=d.title2,series={}}c.x=e.values(a,b,d.x,true)local i=c.x and c.x.n or 0
for k,j in
ipairs(e.SERIES)do local l=e.values(a,b,d[j])if l then
c.series[#c.series+1]={key=j,v=l}if l.n>i then i=l.n end end end;c.n=i;return c end
local function h(a)if a<=0 then return 0 end
local b=10^math.floor(math.log(a,10))
for d,c in ipairs({1,2,5,10})do if c*b>=a-1e-9 then return c*b end end;return 10*b end;e.niceCeil=h
local function f(a)local b;if math.abs(a)>=1e6 then b=string.format("%.3g",a)elseif a==
math.floor(a)then b=string.format("%d",a)else
b=string.format("%.2f",a)end;return b end
function e.render(a,b,c,d)
if#a.series==0 then return nil,"no data range: set A (and B, C) first"end;if a.n==0 then return nil,"the data ranges are empty"end
local p,v={},{}for k=1,c do p[k]={}v[k]={}for B=1,b do p[k][B]=" "end end;local function j(k,B,C,D)
if
k>=1 and k<=b and B>=1 and B<=c then p[B][k]=C;v[B][k]=D end end
local function q(k,B,C,D)local E=0;for F in
C:gmatch("[%z\1-\127\194-\244][\128-\191]*")do j(k+E,B,F,D)E=E+1 end end;local l=1
for B,k in ipairs({a.title1,a.title2})do if k and k~=""then
q(math.max(1,
math.floor((b-#k)/2)+1),l,k:sub(1,b),"title")l=l+1 end end;if l>1 then l=l+1 end;local i,m=0,0;for B,k in ipairs(a.series)do
for C=1,a.n do local D=k.v[C]if D then if D<i then i=D end;if D>m then
m=D end end end end;m=h(m)
i=-h(-i)if m==i then m=i+1 end;local t=math.max(#f(m),#f(i))+1;local n=t+
2;local r=c-2;local x=r-l+1;if x<3 or b-n<a.n then
return nil,"the screen is too small for this graph"end;local z=b-n+1;local function w(k)return r-
(k-i)/ (m-i)* (x-1)end;for k=l,r do
j(n-1,k,"|","axis")end;local o=math.floor(w(0)+0.5)for k=n,b do
j(k,o,"-","axis")end;j(n-1,o,"+","axis")q(1,l,
string.rep(" ",t-#f(m))..f(m),"axis")
q(1,r,string.rep(" ",
t-#f(i))..f(i),"axis")if o~=l and o~=r then
q(1,o,string.rep(" ",t-1).."0","axis")end;local s=math.floor(z/a.n)
local A=#a.series
if a.type=="line"then
for B,k in ipairs(a.series)do local C,D
for E=1,a.n do local F=k.v[E]
if F then local G=n+ (E-1)*s+
math.floor(s/2)local H=math.floor(w(F)+0.5)
if C then local I=math.max(math.abs(
G-C),math.abs(H-D))
for J=1,I-1 do local L=C+math.floor((
G-C)*J/I+0.5)local K=D+math.floor((
H-D)*J/I+0.5)if p[K]and
p[K][L]==" "then j(L,K,".",k.key)end end end;j(G,H,e.POINT[k.key],k.key)C,D=G,H else C,D=nil,nil end end end else local k=math.max(1,math.floor((s-1)/A))
for C,B in
ipairs(a.series)do
for D=1,a.n do local E=B.v[D]
if E and E~=0 then local G=n+ (D-1)*s+ (C-1)*k
local F=w(E)
local H=d and e.MONO_BAR[B.key]or e.BAR.full
local I=d and e.MONO_BAR[B.key]or e.BAR.half
if E>0 then local J=math.floor(F+0.5)for K=o-1,J,-1 do
for L=G,G+k-1 do j(L,K,H,B.key)end end
if F-math.floor(F)>=0.25 and F-
math.floor(F)<0.75 then for K=G,G+k-1 do
j(K,math.floor(F),I,B.key)end end else
for J=o+1,math.floor(F+0.5)do for K=G,G+k-1 do j(K,J,H,B.key)end end end end end end end;if a.x then
for k=1,a.n do
local B=(a.x[k]or""):sub(1,math.max(1,s-1))q(n+ (k-1)*s,r+1,B,"axis")end end;local u=n
for B,k in ipairs(a.series)do
local C=
a.type=="line"and e.POINT[k.key]or(d and e.MONO_BAR[k.key]or
e.BAR.full)j(u,c,C,k.key)q(u+2,c,k.key:upper(),"axis")u=u+5 end;local y={}for k=1,c do y[k]=table.concat(p[k])end;return y,v end;return e