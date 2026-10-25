local e=require("calc.sheet")local d={}d.CHAR_PX=5;d.SPACE_PX=3;d.GAP_PX=3
function d.headerParts(a,b)
a=tostring(
a or""):gsub("#",tostring(b or 1))local c={}
for g in(a.."|"):gmatch("([^|]*)|")do c[#c+1]=g end;if#c==1 then return c[1],"",""end;return c[1]or"",c[2]or"",c[3]or""end
local function f(a,g,c,b,h)local i=b(a)if i>c then local j=""for k in a:gmatch("[%z\1-\127\194-\244][\128-\191]*")do if b(j..k)>c then
break end;j=j..k end
return j,b(j)end;return a,i,g end
function d.fileRow(a,b,c,g,h)local i={}
for j=g,h do local l=e.width(a,j)local k,n=e.cellText(a,b,j,c,l)if#k>l then
k=k:sub(1,l)end;local m=l-#k
if n=="R"then k=string.rep(" ",m)..k elseif n=="C"then local o=math.floor(
m/2)
k=string.rep(" ",o)..k..string.rep(" ",m-o)else k=k..string.rep(" ",m)end;i[#i+1]=k end
return(table.concat(i," "):gsub("%s+$",""))end
function d.pixelRow(b,c,g,h,a)local i,j="",0
for l,k in ipairs(h)do
local q,n=e.cellText(b,c,k.c,g,e.width(b,k.c))local o,p=f(q,n,k.w,a)local m=k.x
if n=="R"then m=k.x+k.w-p elseif n=="C"then m=k.x+math.floor((k.w-p)/
2)end;if o~=""then
if m>j then
local r=math.floor((m-j)/d.SPACE_PX+0.5)i=i..string.rep(" ",r)j=a(i)end;i=i..o;j=a(i)end end;return(i:gsub("%s+$",""))end
function d.formulaLines(a,b,c,g,h)local i={}
for j=c,h do
for k=b,g do local l=a.cells[e._key(k,j)]if l then
local m=a.fmt[e._key(k,j)]
i[#i+1]=e.refName(k,j)..": "..
(m and("("..m..") ")or"")..l end end end;return i end
function d.pages(b,j,g,h,c,i,a)a=a or{}local o=a.target or"file"local p=a.perPage or
(o=="file"and 0 or 20)local r=
(a.header and a.header~="")and 2 or 0
local s=(a.footer and
a.footer~="")and 2 or 0
local t=(p>0)and math.max(1,p-r-s)or math.huge
local l=a.measure or function(u)return#u*d.CHAR_PX end;local m=a.maxWidth or 164;local k={}
if a.formulas then
k[1]=d.formulaLines(b,g,h,c,i)elseif o=="file"then local u={}
for v=h,i do u[#u+1]=d.fileRow(b,j,v,g,c)end;k[1]=u else local u=g
while u<=c do local v,w={},0
while u<=c do local y=e.width(b,u)*d.CHAR_PX;if#v>0 and
w+y>m then break end
v[#v+1]={c=u,x=w,w=math.min(y,m)}w=w+y+d.GAP_PX;u=u+1 end;local x={}for y=h,i do x[#x+1]=d.pixelRow(b,j,y,v,l)end
k[#k+1]=x end end;local n={}
local function q(u,v)local z=v=="head"and a.header or a.footer;if not z or
z==""then return end;local A,x,y=d.headerParts(z,#n+1)local w
if
o=="file"then local B=0;for E=g,c do B=B+e.width(b,E)+1 end;local C=math.max(0,math.floor((B-
#x)/2)-#A)w=
A..string.rep(" ",C)..x
local D=math.max(1,B-#w-#y)
w=(w..string.rep(" ",D)..y):gsub("%s+$","")else w=A
local function B(C,D)
local E=math.max(1,math.floor((C-l(w))/d.SPACE_PX+0.5))w=w..string.rep(" ",E)..D end
if x~=""then B(math.floor((m-l(x))/2),x)end;if y~=""then B(m-l(y),y)end end
if v=="head"then u[#u+1]=w;u[#u+1]=""else u[#u+1]=""u[#u+1]=w end end
for v,u in ipairs(k)do local w=#u;while w>0 and u[w]==""do w=w-1 end;if w==0 then w=1 end
local x=1
repeat local y={}q(y,"head")local z=0
while x<=w and z<t do y[#y+1]=u[x]x=x+1;z=z+1 end;q(y,"foot")n[#n+1]=y until x>w end;return n end
function d.toText(a)local b={}for c,g in ipairs(a)do if c>1 then b[#b+1]="\f"end
for i,h in ipairs(g)do b[#b+1]=h end end;return
table.concat(b,"\n").."\n"end
function d.toWrite(b,a)local c={}if a and a~=""then c[1]=".title "..a end
for g,h in ipairs(b)do if g>1 then c[
#c+1]=".page"end;for j,i in ipairs(h)do
if i:sub(1,1)=="."then i="."..i end;c[#c+1]=i end end;return table.concat(c,"\n").."\n"end;return d