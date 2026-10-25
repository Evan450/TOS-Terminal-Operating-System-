local h,f,g="_kernel_","header","kernel"local e={}
function e.describe(a)
local b=(a and a.name)or"?"local c=b:match("^login@(%d+)$")if c then
return"Login broker — seat "..c end;local d,i=b:match("^shell:(.+)@(%d+)$")
if d then return
"Shell — "..d.." (seat "..i..")"end;if a and(a.user==h or a.source==g)then
return b.."  (kernel)"end;return b end
function e.kindTag(a)local b=(a and a.name)or""
if b:match("^shell:")then return"shell"end;if b:match("^login@")then return"sys"end;if a and
(a.user==h or a.source==g)then return"sys"end;return"user"end
function e.memBar(c,b,a)a=math.max(1,math.floor(a or 10))if
not b or b<=0 then return string.rep("?",a)end
local d=(c or 0)/b;if d<0 then d=0 elseif d>1 then d=1 end;local i=math.floor(d*a+0.5)
if i>a then i=a end
return string.rep("#",i)..string.rep("-",a-i)end
function e.fmtUptime(a)a=math.floor(tonumber(a)or 0)if a<0 then a=0 end;local c=math.floor(
a/3600)
local b=math.floor((a%3600)/60)local d=a%60
if c>0 then return string.format("%dh%02dm",c,b)end
if b>0 then return string.format("%dm%02ds",b,d)end;return string.format("%ds",d)end
function e.buildRows(b,a)local c={}
for i,d in ipairs(b or{})do c[#c+1]={kind="proc",p=d}end
if a and#a>0 then c[#c+1]={kind=f,text="Services"}for i,d in ipairs(a)do
c[#c+1]={kind="svc",s=d}end end;return c end
function e.nextSelectable(a,b,c)local i=#a;if i==0 then return b end;local d=b
for j=1,i do local k=d+c
if k<1 or k>i then return d end;d=k;if a[d]and a[d].kind~=f then return d end end;return b end
function e.svcStatus(a)a=a or{}if a.running then return"running"end
if a.unavailable then return"not loaded: "..
tostring(a.unavailable)end;if a.enabled==false then return"disabled"end;return"stopped"end
function e.svcToggle(b,a,c)local m=a.running and"stop"or"start"
local i=b and b[m]local j,d,n;if i then j,d,n=pcall(i,a.name)end;local k=j==true and d~=false and
d~=nil
local o=(not i and"rc unavailable")or(not j and
tostring(d))or tostring(n or"refused")local p,l=pcall(require,"kernel.log")
if p and l and l.info then
l.info(g,
(
k and((a.running and
"Stopped ")or"Started ")or("Could not "..m.." "))..
tostring(a.name).." from monitor by "..tostring(c or g)..
(k and""or(": "..o)))end;if k then return true end;return false,o end
function e.textRows(a,b)local c={}local function d(i,j)c[#c+1]={text=i,tone=j}end
for j,i in
ipairs(e.buildRows(a,b))do
if i.kind=="proc"then local k=i.p
d(string.format("%-5s %-5s %s",tostring(k.pid or"?"),e.kindTag(k),e.describe(k)),"proc")elseif i.kind==f then
d("-- ".. (i.text or"").." --",f)elseif i.kind=="svc"then local k=i.s or{}
d(string.format("  %-22s [%s]",tostring(k.name or"?"),e.svcStatus(k)),"svc")end end
if#c==0 then d("(no visible processes)","dim")end;return c end
function e.canAct(b,c,d,a)if(b or 0)>=3 then return true end
if a.user==h then return false end;if(b or 0)>=2 then
return(not a.display)or a.display==d end
return a.user~=nil and a.user==c end;function e.firstSelectable(a)for b,c in ipairs(a)do if c.kind~=f then return b end end
return 1 end;return e