local b={}
function b.aggregate(a)local d,c={},{}
for f,e in ipairs(a or{})do
if type(e)=="table"and e.key and(
tonumber(e.count)or 0)>0 then
local g=d[e.key]
if not g then
g={key=e.key,id=e.id,label=e.label or e.id or"?",total=0,stacks=0,sides={},_sideSeen={}}d[e.key]=g;c[#c+1]=g end
g.total=g.total+ (tonumber(e.count)or 0)g.stacks=g.stacks+1;local h=e.sideName
if h and not g._sideSeen[h]then
g._sideSeen[h]=true;g.sides[#g.sides+1]=h end end end
for f,e in ipairs(c)do e._sideSeen=nil;table.sort(e.sides)end
table.sort(c,function(e,f)
if e.total~=f.total then return e.total>f.total end;return(e.label or"")< (f.label or"")end)return c end
function b.applyWatches(a,c,d)a=a or{}c=c or{}d=d or{}local g={}
for i,h in ipairs(a)do g[h.key]=true
local j=tonumber(c[h.key])if j then h.min=j;h.low=h.total<j end end;local f={}
for h,i in pairs(c)do
if not g[h]and tonumber(i)then
f[#f+1]={key=h,id=h:match("^(.-)#")or h,label=
d[h]or h:match("^(.-)#")or h,total=0,stacks=0,sides={},min=tonumber(i),low=true,absent=true}end end
table.sort(f,function(h,i)
return(h.label or"")< (i.label or"")end)local e={}for i,h in ipairs(f)do e[#e+1]=h end
for i,h in ipairs(a)do e[#e+1]=h end;return e end
function b.lowStock(a)local c={}
for e,d in ipairs(a or{})do if d.low then c[#c+1]=d end end
table.sort(c,function(d,e)local f=(d.min or 0)- (d.total or 0)local g=(e.min or
0)- (e.total or 0)
if f~=g then return f>g end;return(d.label or"")< (e.label or"")end)return c end
function b.filter(c,a)if not a or a==""then return c or{}end
local e=tostring(a):lower()local d={}
for g,f in ipairs(c or{})do
local h=tostring(f.label or""):lower()local i=tostring(f.id or""):lower()if
h:find(e,1,true)or i:find(e,1,true)then d[#d+1]=f end end;return d end
function b.fmtCount(a)a=tonumber(a)or 0;if a<10000 then
return tostring(math.floor(a))end;if a<1000000 then
return string.format("%.1fk",a/1000)end
return string.format("%.1fM",a/1000000)end
function b.fmtStacks(c,a)c=tonumber(c)or 0;a=tonumber(a)or 64
if a<1 then a=64 end;if c<a then return tostring(math.floor(c))end;local d=math.floor(
c/a)local e=math.floor(c%a)
if e==0 then return d.."s"end;return d.."s+"..e end
function b.totals(a)local c,d,e=0,0,0;for g,f in ipairs(a or{})do
if not f.absent then
c=c+ (f.total or 0)e=e+ (f.stacks or 0)d=d+1 end end
return{items=c,distinct=d,slots=e}end
function b.encodeWatches(a,c)local d={}for f in pairs(a or{})do d[#d+1]=f end
table.sort(d)local e={}
for g,f in ipairs(d)do local h=tonumber(a[f])if h and not
tostring(f):find("[\t\n\r]")then
e[#e+1]=string.format("%s\t%d\t%s",f,math.floor(h),tostring((
c or{})[f]or""))end end;return table.concat(e,"\n")end
function b.decodeWatches(a)local c,d={},{}
for e in tostring(a or""):gmatch("[^\n]+")do
local f,h,g=e:match("^([^\t]+)\t(%-?%d+)\t?(.*)$")if f and h then local i=tonumber(h)
if i and i>=0 then c[f]=i;if g and g~=""then d[f]=g end end end end;return c,d end;return b