local l=require("warhead.model")local k=l.D;local m={}
m.GOALS={tnt={name="Conventional (no fallout)",fires="TNT",w={TNT=1},min={TNT=75},cap="maxCustomTNTRadius"},nuke={name="Fission",fires="NUKE",w={NUKE=1,TNT=
1/2},min={TNT=16,NUKE=0.0001},cap="maxCustomNukeRadius"},hydro={name="Thermonuclear",fires="HYDRO",w={HYDRO=1,NUKE=
1/2,TNT=1/4},min={TNT=16,NUKE=100,HYDRO=0.0001},cap="maxCustomHydroRadius"},bale={name="Balefire",fires="BALE",w={BALE=1,HYDRO=
1/2,NUKE=1/4,TNT=1/8},min={TNT=16,NUKE=50,BALE=0.0001},cap="maxCustomBaleRadius"},schrab={name="Antimatter (FLEIJA-type)",fires="SCHRAB",w={SCHRAB=1,BALE=
1/2,HYDRO=1/4,NUKE=1/8,TNT=1/16},min={TNT=16,NUKE=50,SCHRAB=0.0001},cap="maxCustomSchrabRadius"},sol={name="Solinium (Blue Rinse)",fires="SOL",w={SOL=1,SCHRAB=
1/2,BALE=1/4,HYDRO=1/8,NUKE=1/16,TNT=1/32},min={TNT=16,NUKE=25,SOL=0.0001},cap="maxCustomSolRadius"}}m.ORDER={"tnt","nuke","hydro","bale","schrab","sol"}
local function o(c,b,a)
local d,e={},{}
for u,j in ipairs(k.INGREDIENTS)do
if j.stage==c then
local v=b and(b[j.key]or 0)or a;v=math.min(v,a)for u=1,v do
if j.m then if j.v>1 then e[#e+1]=j end else d[#d+1]=j end end end end
table.sort(d,function(j,u)return j.v>u.v end)
table.sort(e,function(j,u)return j.v>u.v end)local h,i={[0]=0},{[0]=1}for j,u in ipairs(d)do h[j]=h[j-1]+u.v end;for j,u in
ipairs(e)do i[j]=i[j-1]*u.v end;local f,g={[0]=0},{[0]={}}
for j=1,a do
local v,u=0,nil
for w=0,math.min(j-1,#e)do local x=j-w;if x<=#d then local y=h[x]*i[w]
if y>v+1e-9 then v,u=y,w end end end;f[j]=v
if u then local w={}for x=1,j-u do w[#w+1]=d[x]end
for x=1,u do w[#w+1]=e[x]end;g[j]=w else f[j],g[j]=f[j-1],g[j-1]end end;return f,g end;local q={HYDRO=100,BALE=50,SCHRAB=50,SOL=25}
local function r(a,e,b,c,d)local f={}
for x,w in ipairs(k.STAGES)do if a.w[w]and
(q[w]or 0)<=d then f[#f+1]=w end end;local function j(w)local x=a.min[w]or 0;if w=="NUKE"then x=math.max(x,d)end
return x end;local g,h={[0]={}},{}for w=0,c do g[0][w]=(w==0)and
0 or nil end
for w,x in ipairs(f)do g[w],h[w]={},{}
local z=e[x].val;local A=b[k.STAGE_CAP[x]]local y=j(x)
for B=0,c do local C,D
for E=0,B do local F=g[w-1][B-E]
if F~=
nil then local G=z[E]or 0;local H=(y<=0)and true or(G>=y)if
E==0 and y<=0 then H=true end;if H and(E==0 or G>0)then local I=F+
a.w[x]*math.min(G,A)
if C==nil or I>C+1e-9 then C,D=I,E end end end end;g[w][B],h[w][B]=C,D end end;local i=#f;local u=b[a.cap]local function v(w)local x=g[i][w]if x==nil then return nil end;return
l.toInt(math.min(x,u))end;return
{stages=f,dp=g,how=h,result=v,split=function(w)local x={}for y=i,1,-1 do
local z=h[y][w]x[f[y]]=z;w=w-z end;return x end}end
local function s(a,b)local c={}
for e,d in ipairs(k.STAGES)do local f=a[d]or 0;if f>0 then for e,g in ipairs(b[d].pick[f])do
c[#c+1]=g end end end;return c end
local function n(b,a)local c,d=l.stages(b,a)return l.customOutcome(c,a),c,d end
local function p(c,d)return
c.engine==d.engine and c.radius==d.radius and
(c.falloutAdd or 0)== (d.falloutAdd or 0)end
local function t(a,b,c,d)local e={}
for j,i in ipairs(a)do e[i.key]=(e[i.key]or 0)+1 end
local function h(i)if not b then return true end;return
(b[i.key]or 0)- (e[i.key]or 0)>0 end;local f={}for j,i in ipairs(k.INGREDIENTS)do f[i.stage]=f[i.stage]or{}
table.insert(f[i.stage],i)end;for j,i in pairs(f)do
table.sort(i,function(u,v)return u.v<v.v end)end
for j=1,#a do local i=a[j]
for v,u in ipairs(f[i.stage])do if
u.v>=i.v then break end;if u.m==i.m and h(u)then a[j]=u
if p(n(a,c),d)then
e[i.key]=e[i.key]-1;e[u.key]=(e[u.key]or 0)+1;break end;a[j]=i end end end;local g=1
while g<=#a do local i=table.remove(a,g)if p(n(a,c),d)then
e[i.key]=e[i.key]-1 else table.insert(a,g,i)g=g+1 end end;return a end
function m.design(c,b,a)a=a or{}b=l.conf(b)local e=m.GOALS[c]if not e then return nil,
"unknown kind of blast: "..tostring(c)end
local g=a.slots or k.CUSTOM_SLOTS;local i={}
for y,v in ipairs(k.STAGES)do local z,A=o(v,a.stock,g)i[v]={val=z,pick=A}end;local j={}local w=e.min.NUKE or 0;local u={w}
if e.w.NUKE then for y,v in ipairs({25,50,100})do if v>w then
u[#u+1]=v end end end;for y,v in ipairs(u)do j[#j+1]=r(e,i,b,g,v)end;local d
for y,v in ipairs(j)do local z
for A=0,g do
local B=v.result(A)if B and(z==nil or B>z)then z=B end end
if z then
local A=a.radius and math.min(a.radius,z)or z;for B=1,g do local C=v.result(B)
if C and C>=A then if
not d or C>d.r or(C==d.r and B<d.u)then d={r=C,u=B,run=v}end;break end end end end
if not d or d.r<=0 then return nil,
"the materials on hand cannot make a "..e.name:lower().." blast"end;if a.radius and d.r<a.radius then d.short=true end
local f=s(d.run.split(d.u),i)local h=n(f,b)if h.via~=e.fires or
(e.fires=="TNT"and h.engine~="mk5")then
return nil,"no design clears the mod's thresholds with these materials"end
f=t(f,a.stock,b,h)
if
a.salt and(e.fires=="NUKE"or e.fires=="HYDRO")then local v=a.stock
if v then v={}for z,A in pairs(a.stock)do v[z]=A end;for A,z in ipairs(f)do v[z.key]=(
v[z.key]or 0)-1 end end;local y=g-#f;if y>0 then local A,z=o("DIRTY",v,y)
for A,B in ipairs(z[y]or{})do f[#f+1]=B end end end;h=n(f,b)local x=l.stages(f,b)
return{slots=f,outcome=h,stages=x,short=d.short,goal=e}end
function m.designEuph(b,a)a=a or{}b=l.conf(b)local e=a.slots or k.CUSTOM_SLOTS
local c={}
local function h(u,j)local v={}
for z,y in ipairs(k.INGREDIENTS)do if y.stage==u and not y.m then local A=a.stock and
(a.stock[y.key]or 0)or e
for z=1,A do v[#v+1]=y end end end
table.sort(v,function(y,z)return y.v>z.v end)local w,x=0,{}
for z,y in ipairs(v)do if w>=j then break end;x[#x+1]=y;w=w+y.v end;if w<j then return nil end;return x end
for u,j in
ipairs({{"TNT",16},{"NUKE",50},{"SCHRAB",1},{"SOL",1}})do local v=h(j[1],j[2])if not v then
return nil,"not enough "..
k.STAGE_NAME[j[1]].." material to keep Anti Mass live"end
for u,w in ipairs(v)do c[#c+1]=w end end;local d={}
for u,j in ipairs(k.INGREDIENTS)do if j.stage=="EUPH"then local v=a.stock and
(a.stock[j.key]or 0)or e
for u=1,v do d[#d+1]=j end end end
table.sort(d,function(j,u)return j.key<u.key end)local f=math.min(e-#c,b.maxCustomEuphLvl)if f<=0 or#d==0 then return nil,
"no Euphemium on hand"end;for j=1,math.min(f,#d)do
c[#c+1]=d[j]end;local g=l.stages(c,b)
local i=l.customOutcome(g,b)
return{slots=c,outcome=i,stages=g,goal={name="Anti Mass",fires="EUPH"}}end;return m