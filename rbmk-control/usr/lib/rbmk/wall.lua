local f,e="alarms","number"local d={}d.VERSION="0.2.0"
d.PAGES={{id="map",label="CORE MAP",desc="per-channel readings, one parameter"},{id="panel",label="PARAMS",desc="reactor-wide scalars and limits"},{id=f,label="ALARMS",desc="active warnings and scram reasons"},{id="trend",label="TREND",desc="recent history of one parameter"}}
function d.page(a)if type(a)~="string"then return nil end;for c,b in ipairs(d.PAGES)do
if b.id==a then return b end end;return nil end
d.DEFAULT_ROTATION={{page="map",param="T"},{page="panel",param="T"},{page=f,param="T"},{page="trend",param="T"},{page="map",param="N"},{page="trend",param="N"}}
function d.plan(b,a,c)local g={}b=tonumber(b)or 0;if b<0 then b=0 end;a=
(type(a)=="table")and a or{}
for h=1,b do
local k=d.DEFAULT_ROTATION[((h-1)%
#d.DEFAULT_ROTATION)+1]
local i=(type(a[h])=="table")and a[h]or{}local l=d.page(i.page)and i.page or k.page
local j=i.param;if type(j)~="string"or(c and not c(j))then j=k.param else
j=j:upper()end
g[h]={seat=h,page=l,param=j,pinned=(i.pinned==true),configured=(type(a[h])==
"table")or nil,rejected=
(type(a[h])=="table"and
((i.page~=nil and not
d.page(i.page))or(i.param~=nil and c and
not c(i.param))))or nil}end;return g end
function d.effective(a,b,c)local g
if c then g="TELEMETRY STALE"elseif b=="scram"then g="SCRAM"end;if not g then return a,false,nil end;local h={}for k,j in ipairs(a)do
if j.pinned then h[k]=j else local i={}for l,m in pairs(j)do
i[l]=m end;i.page,i.overridden=f,g;h[k]=i end end
return h,true,g end
function d.push(a,c,b)a=a or{}b=b or 120
a[#a+1]=(type(c)==e)and c or false;while#a>b do table.remove(a,1)end;return a end
function d.range(a)local b,c,g
for i,h in ipairs(a or{})do if type(h)==e then g=(g or 0)+1
if not b or h<b then b=h end;if not c or h>c then c=h end end end;return b,c,g or 0 end
d.SPARK={"_","\226\150\129","\226\150\130","\226\150\131","\226\150\132","\226\150\133","\226\150\134","\226\150\135","\226\150\136"}
function d.spark(b,g,a,c)b=b or{}g=math.max(1,math.floor(g or 1))local i=math.max(1,
#b-g+1)if a==nil or c==nil then local j,k=d.range(b)a,c=a or j,c or
k end;local h={}
for j=i,#b do local k=b[j]
if type(k)~=e then h[#h+
1]=" "elseif not a or not c or c<=a then h[#h+1]=d.SPARK[5]else local l=(k-a)/
(c-a)if l<0 then l=0 elseif l>1 then l=1 end
h[#h+1]=d.SPARK[math.floor(l*
(#d.SPARK-1)+0.5)+1]end end;return table.concat(h)end
function d.chart(b,h,c,a,g)b=b or{}h=math.max(1,math.floor(h or 1))c=math.max(1,math.floor(
c or 1))if a==nil or g==nil then
local l,m=d.range(b)a,g=a or l,g or m end
local k=math.max(1,#b-h+1)local i={}
for l=k,#b do local m=b[l]
if type(m)~=e then i[#i+1]=false elseif not a or not g or g<=a then i[#i+1]=math.ceil(
c/2)else local n=(m-a)/ (g-a)
if n<0 then n=0 elseif n>1 then n=1 end;i[#i+1]=math.max(1,math.floor(n*c+0.5))end end;local j={}for l=1,c do local n=c-l+1;local m={}for o=1,#i do local p=i[o]m[o]=(p and p>=n)and"\226\150\136"or
" "end
j[l]=table.concat(m)end;return j end;return d