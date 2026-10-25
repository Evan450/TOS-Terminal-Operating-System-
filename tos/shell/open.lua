local h,f="native","string"local e={}
e.SCORE={user=100,system=90,suits=60,native=50,plain=40,opens=20,text=10}
e.PLAIN={txt=true,text=true,lua=true,cfg=true,conf=true,ini=true,log=true,md=true,man=true,json=true,xml=true,sh=true}e.EDITOR="edit"e.SYSTEM_FILE="/etc/open.cfg"e.USER_FILE=".open.cfg"
e.HEAD_BYTES=4096
function e.ext(a)
local b=tostring(a or""):match("%.([%w]+)$")return b and b:lower()or nil end
local function g(c,b,a)
if type(a)~="table"or type(a.ext)~="table"then return nil end;local k,j={},0
for n,m in ipairs(a.ext)do if
type(m)==f and m:match("^[%w]+$")and#m<=8 then k[m:lower()]=true;j=j+1 end end;if j==0 then return nil end;local d=a.cmd
if
d==nil and type(b.commands)=="table"then for m in pairs(b.commands)do if d then d=false;break end;d=m end end
if type(d)~=f or type(b.commands)~="table"or
not b.commands[d]then return nil end;local i
if type(a.markers)=="table"then i={}
for n,m in ipairs(a.markers)do if
type(m)==f and#m>=2 and#m<=24 and not m:find("[%c]")then
i[#i+1]=m end end;if#i==0 then return nil end end;local l=(a.as==h)and h or"open"
return{pkg=c,cmd=d,exts=k,nExt=j,as=l,markers=i}end;e.cleanDecl=g
function e.declarations(a)a=a or{}local b,c={},{}
if a.manifests then for i,j in pairs(a.manifests)do b[i]=j;c[i]=(
j.enabled~=false)end elseif a.pkg and
a.pkg.list then for j,i in ipairs(a.pkg.list())do
b[i.name]=a.pkg.info(i.name)c[i.name]=i.enabled end elseif
a.kfs and a.serialize then local i="/var/pkg/installed"local k,j=pcall(a.kfs.list,i)
if k and
type(j)=="table"then
for m,l in ipairs(j)do local n=tostring(l):gsub("/$","")
if
n:match("^[%w_%-]+$")then
local p,o=pcall(a.serialize.loadFile,a.kfs,i.."/"..n.."/package.lua")
if
p and type(o)=="table"and o.name==n and o.handles then b[n]=o;local r=i.."/"..n.."/state"
local s,q=pcall(a.kfs.readFile,r)c[n]=not
(s and type(q)==f and q:sub(1,1)=="d")end end end end end;local d={}
for j,i in pairs(b)do
if c[j]and type(i)=="table"and
type(i.handles)=="table"then for l,k in ipairs(i.handles)do local m=g(j,i,k)
if m then d[#d+1]=m end end end end
table.sort(d,function(i,j)return i.pkg<j.pkg end)return d end
function e.parseDefaults(a)local b={ext={},hints=true}if type(a)~=f then return b end
for c in
(a.."\n"):gmatch("(.-)\r?\n")do local d,i=c:match("^%s*%.?([%w]+)%s+([%w_%-]+)%s*$")
if d and
d:lower()=="hints"then b.hints=(i:lower()~="off")elseif
d and#d<=8 then b.ext[d:lower()]=i end end;return b end
function e.serializeDefaults(a)local b,c={},{}for d in pairs(a.ext or{})do c[#c+1]=d end
table.sort(c)
for i,d in ipairs(c)do b[#b+1]=d.." "..a.ext[d]end;if a.hints==false then b[#b+1]="hints off"end;return
table.concat(b,"\n").. (#b>0 and"\n"or"")end
function e.markersMatch(a,b)if type(a)~=f or not b then return nil end;local c=0;for d in
(a.."\n"):gmatch("(.-)\n")do c=c+1;if c>200 then break end
for j,i in ipairs(b)do if d:sub(1,#i)==i then return i end end end;return nil end
function e.isText(a)return type(a)~=f or not a:find("%z")end
function e.rank(b,a)a=a or{}local c=e.ext(b)local j,i={},{}
local function d(k,m,l,n,o)local p=j[k]
if p and p.score>=l then return end
if p then p.score,p.why,p.pkg,p.spec=l,n,m,o else
p={cmd=k,pkg=m,score=l,why=n,spec=o or 99}j[k]=p;i[#i+1]=p end end
if c then
for l,k in ipairs(a.decls or{})do
if k.exts[c]then
if k.markers then
local m=e.markersMatch(a.head,k.markers)if m then
d(k.cmd,k.pkg,e.SCORE.suits,"it uses "..
k.pkg.."'s \""..m:gsub("%s+$","").."\"",k.nExt)end elseif k.as==h then
d(k.cmd,k.pkg,e.SCORE.native,
"."..c.." is "..k.pkg.."'s own format",k.nExt)else
d(k.cmd,k.pkg,e.SCORE.opens,k.pkg.." opens ."..c.." files",k.nExt)end end end end
if e.isText(a.head)then
if c and e.PLAIN[c]then
d(e.EDITOR,nil,e.SCORE.plain,"."..c.." is plain text",99)else d(e.EDITOR,nil,e.SCORE.text,"it is text")end end
for l,k in
ipairs({{a.system,e.SCORE.system,"this machine's choice"},{a.user,e.SCORE.user,"your choice"}})do
local m=c and k[1]and k[1].ext and k[1].ext[c]if m then local n=j[m]
if n then n.score,n.why=k[2],k[3].." for ."..c else d(m,nil,k[2],k[3]..
" for ."..c)end end end
table.sort(i,function(k,l)
if k.score~=l.score then return k.score>l.score end;if k.spec~=l.spec then return k.spec<l.spec end
return k.cmd<l.cmd end)return i end;function e.best(a,b)return e.rank(a,b)[1]end
function e.suggestion(b,a)a=a or{}if a.user and
a.user.hints==false then return nil end
local c=e.best(b,a)if c and c.cmd~=e.EDITOR then return c end;return nil end
function e.gather(a,c,d,b)local i={}local j=package.loaded["kernel.pkg"]
if
type(j)=="table"and j.list then i.pkg=j else local l=_G._TOS and _G._TOS.fs
local m,n=pcall(require,"kernel.serialize")
if type(l)=="table"and m then i.kfs,i.serialize=l,n end end
local function k(l)
if not(a and a.exists and a.readFile)then return nil end;local n,o=pcall(a.exists,l)if not n or not o then return nil end
local p,m=pcall(a.readFile,l)return p and type(m)==f and m or nil end;if b==nil and d then local l=k(d)
b=l and l:sub(1,e.HEAD_BYTES)or nil end;return
{decls=e.declarations(i),head=b,system=e.parseDefaults(k(e.SYSTEM_FILE)),user=e.parseDefaults(
c and k(c.."/"..e.USER_FILE)or nil)}end
function e.quote(a)if a:find("[%s\"'|<>]")then
return'"'..a:gsub('"','\\"')..'"'end;return a end;return e