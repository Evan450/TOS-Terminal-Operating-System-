
local K,P,ah,X,O="string","pkgremote","internet module unavailable","could not write ","package '"local I=require("kernel.fs")
local L=require("kernel.serialize")local H={}local J=nil;local N="/etc/pkg-repos.cfg"local M="/var/pkg/known-repos.cfg"local Y=32
local ai=8;local Z="/var/pkg/remote"local R=128*1024;local aj=128*1024;local ab=512*1024;local ac=64;local S=function()return
false end
function H.init(a)a=a or{}J=a.log;if
type(a.validRepoHint)=="function"then S=a.validRepoHint end end
local function Q()local a,b=pcall(require,"kernel.internet")if a then return b end;return nil end;local function ad(a)return
type(a)==K and#a<=32 and a:match("^[%w_%-]+$")~=nil end
local function T(a)if
type(a)~=K or a==""or#a>64 then return false end;if
#a==1 then return a:match("^%w$")~=nil end;return
a:match("^%w[%w%-]*%w$")~=nil end;H.validPkgName=T
function H.repos()local a={}if not I.exists(N)then return a end
local b=I.readFile(N)if not b then return a end
local e,c=pcall(L.decode,b,{maxBytes=16384})
if not e or type(c)~="table"then if J then
J.warn(P,"Corrupt "..N.."; ignoring")end;return a end;local d=Q()
for g,f in ipairs(c)do
if type(f)=="table"and ad(f.name)and
type(f.url)==K then
local h=d and d.hostOf(f.url)or nil
if h then
a[#a+1]={name=f.name,url=(f.url:gsub("/+$","")),host=h,description=type(f.description)==K and
f.description or nil}elseif J then
J.warn(P,"Repo '"..tostring(f.name).."' has an unusable URL")end end end;return a end
local function ae(a)local b={}for d,c in ipairs(a)do
b[#b+1]={name=c.name,url=c.url,description=c.description}end;return
I.writeFileAtomic and
I.writeFileAtomic(N,L.encode(b))or I.writeFile(N,L.encode(b))end
function H.addRepo(a,b,c)
if not ad(a)then return false,"invalid repo name (letters, digits, _ and - only)"end;local e=Q()if not e then return false,ah end;local g,h=e.parseUrl(b)
if not g then return false,h end;local d=H.repos()local f=false
for k,j in ipairs(d)do if j.name==a then
j.url,j.description,f=(b:gsub("/+$","")),c,true end end;if not f then
d[#d+1]={name=a,url=(b:gsub("/+$","")),description=c}end;local i=ae(d)
if not i then return false,X..N end
if J then J.info(P,"Repo '"..a.."' -> "..b)end;return true end
function H.removeRepo(a)local d,b,c=H.repos(),{},false;for f,e in ipairs(d)do
if e.name==a then c=true else b[#b+1]=e end end;if not c then
return false,"no such repo: "..tostring(a)end;if not ae(b)then return false,X..N end
return true end
local function U()local a={}if not I.exists(M)then return a end;local b=I.readFile(M)if not b then
return a end;local d,c=pcall(L.decode,b,{maxBytes=16384})
if not d or
type(c)~="table"then if J then
J.warn(P,"Corrupt "..M.."; ignoring")end;return a end
for g,f in ipairs(c)do
if type(f)=="table"and S(f.url)then local e={}for g,h in ipairs(
type(f.from)=="table"and f.from or{})do if T(h)then
e[#e+1]=h end end
a[#a+1]={url=(f.url:gsub("/+$","")),from=e}end end;while#a>Y do table.remove(a,1)end;return a end
local function _(a)local b={}
for e,d in ipairs(a)do b[#b+1]={url=d.url,from=d.from}end;local c=L.encode(b)
if I.writeFileAtomic then return I.writeFileAtomic(M,c)end;return I.writeFile(M,c)end;function H.known()return U()end
function H.learn(b,a)if type(b)~="table"then return 0 end
local c=U()local e={}for h,g in ipairs(H.repos())do e[g.url]=true end;local d=0
for h,g in
ipairs(b)do
if S(g)then local i=(g:gsub("/+$",""))
if not e[i]then local j;for h,k in ipairs(c)do
if k.url==i then j=k;break end end
if not j then j={url=i,from={}}c[#c+1]=j;d=d+1 end;if T(a)then local k=false;for h,l in ipairs(j.from)do if l==a then k=true end end
if
not k and#j.from<8 then j.from[#j.from+1]=a end end end end end;while#c>Y do table.remove(c,1)end;local f=_(c)
if not f then return 0,X..M end;if d>0 and J then
J.info(P,("Learned %d repo(s) from '%s' (known, not trusted)"):format(d,tostring(a)))end;return d end
function H.forget(a)local b=U()
if a=="all"then if not _({})then return false,X..M end;return true,#b end;local c=tonumber(a)if not c then local d=type(a)==K and(a:gsub("/+$",""))or
nil
for f,g in ipairs(b)do if g.url==d then c=f end end end
if
not c or not b[c]then return false,
"no known repo "..tostring(a).." (see 'pkg repo list')"end;table.remove(b,c)if not _(b)then return false,X..M end;return true,1 end
local function ak(a)if not S(a)then return nil end;a=(a:gsub("/+$",""))
local f,b=pcall(require,"kernel.crypto")local c=Q()
if
not f or type(b)~="table"or type(b.hash)~="function"or not c then return nil end;local e=c.hostOf and c.hostOf(a)
local d=tostring(b.hash(a)or"")
if not e or not d:match("^%x+$")or#d<12 then return nil end
return{name="k"..d:sub(1,12),url=a,host=e,discovered=true}end
local function al(b,a)local d,e,c={},{},{}for h,g in ipairs(b)do d[g.url]=true end
local function f(g)if
#c>=ai or type(g)~=K then return end;local h=(g:gsub("/+$",""))
if d[h]or e[h]then return end;e[h]=true;local i=ak(h)if i then c[#c+1]=i end end
for h,g in ipairs(type(a)=="table"and a or{})do f(g)end;for h,g in ipairs(U())do f(g.url)end;return c end
local function af(a)if type(a)~=K or a==""then return nil end
if#a>256 then return nil end;if a:find("[%c]")then return nil end
if a:find("\\",1,true)then return nil end;if a:sub(1,1)=="/"then return nil end
if a:find("://",1,true)then return nil end
if a:find("?",1,true)or a:find("#",1,true)then return nil end;if a:find("@",1,true)then return nil end;for b in a:gmatch("[^/]+")do if
b=="."or b==".."then return nil end end;return
(a:gsub("/+","/"))end;local V={}local W={}local ag=64*1024
function H.index(a,b)b=b or{}local d=Q()if not d then return nil,ah end
if not
b.refresh and V[a.name]then return V[a.name].index end;local e=a.url.."/programs.cfg"local f,g=d.get(e,{maxBytes=R})if
not f then
return nil,"could not fetch "..e..": "..tostring(g)end
local h,c=pcall(L.decode,f,{maxBytes=R,maxCost=ag,maxKeys=1024})
if not h or type(c)~="table"then return nil,"repo '"..
a.name.."' returned an index that is not a table"end;V[a.name]={index=c}return c end;function H.clearCache()V={}W={}end;local aa=4096
local function am(b,a,c)if
not c.refresh and W[a.name]~=nil then return W[a.name]end
local f,g,d=b.get(a.url.."/programs.sig",{maxBytes=aa})local e
if type(f)==K then local h,i=pcall(L.decode,f,{maxBytes=aa})
e=(h and type(i)==
"table")and f or false else d=type(d)=="table"and d or{}local h=tonumber(d.status)or
tonumber(tostring(g):match("^HTTP (%d%d%d)"))
if
(h and
h>=400 and h<500)or(d.bytes or 0)>aa then e=false else
return nil,"could not ask repo '"..
a.name.."' whether it signs its index: "..
tostring(g).."  [E-501 ERR_NET_NO_ANSWER]"end end;W[a.name]=e;return e end
function H.search(a)local b={}
for d,c in ipairs(H.repos())do local e,f=H.index(c,a)
if e then
for h,g in pairs(e)do if type(h)==K and
type(g)=="table"and not g.hidden then
b[#b+1]={name=h,repo=c.name,description=
g.description or g.note,version=g.version}end end elseif J then J.warn(P,tostring(f))end end
table.sort(b,function(c,d)return(c.name or"")< (d.name or"")end)return b end
function H.fetch(a,b)b=b or{}if not T(a)then
return nil,"not a package name: "..tostring(a):sub(1,64)..
"  [E-602 ERR_PKG_BAD_NAME]"end;local g=Q()
if not g then return nil,ah end;if not g.available()then local r=g.status()return nil,
r.reason or"internet is not available"end
local l=H.repos()
local q=b.discoveredPolicy~=nil and b.discoveredPolicy~="off"local k=q and al(l,b.hints)or{}
if#l==0 and#k==0 then return nil,
"no remote repositories configured (see 'pkg repo add')"end;local c,d;local h={}for t,s in ipairs(l)do local r,u=H.index(s,b)
if
r and type(r[a])=="table"then c,d=s,r[a]break elseif not r then h[#h+1]=tostring(u)end end
if not d then
for t,s in
ipairs(k)do local r,u=H.index(s,b)if r and type(r[a])=="table"then c,d=s,r[a]break elseif not r then h[#h+
1]=tostring(u)end end end;local m,p
if d then local r,s=am(g,c,b)if r==nil then return nil,s end
if r then
local u,w=g.get(c.url.."/programs.cfg",{maxBytes=R})local v,t=false,nil;if type(u)==K then
v,t=pcall(L.decode,u,{maxBytes=R,maxCost=ag,maxKeys=1024})end
if not
(v and type(t)=="table")then
return nil,"repo '"..
c.name.."' signs its index, and re-reading it failed: "..
tostring(w or"it did not decode")end;if type(t[a])~="table"then
return nil,O..tostring(a)..
"' is no longer in repo '"..c.name.."''s signed index"end;m,p,d=u,r,t[a]end end
if not d then
local r=O..tostring(a)..
"' is not in any configured repo".. (
#k>0 and(", nor in the "..
#k.." other repo(s) it was pointed to")or"")if#h>0 then
r=r.." ("..table.concat(h,"; ")..")"end
return nil,r.."  [E-601 ERR_PKG_NOT_FOUND]"end;if type(d.files)~="table"then
return nil,O..a.."' declares no files"end
for r,s in pairs(d.files)do
if
type(r)~=K or type(s)~=K then
return nil,
O..a..
"' in repo '"..c.name..
"' has a malformed file list (expected { [\"source/path\"] = \"/dest/dir\" }, got "..type(r).." -> "..
type(s)..")"end end;local e=I.join(Z,c.name.."."..a)local n=I.join(e,a)
pcall(I.remove,e)
if
not I.makeDirectory(e)or not I.makeDirectory(n)then return nil,"could not create staging directory "..n end;local function f(r)pcall(I.remove,e)return nil,r end;local o
if m then
o=
I.writeFile(I.join(e,"programs.cfg"),m)and I.writeFile(I.join(e,"programs.sig"),p)else
o=I.writeFile(I.join(e,"programs.cfg"),L.encode({[a]=d}))end
if not o then return f("could not stage the package index")end;local i,j=0,0
for r in pairs(d.files)do local s=af(r:gsub("^:",""))
if
r:sub(1,1)==":"then return
f(O..
a.."' uses an OPPM directory-copy entry ("..
tostring(r).."); TOS installs a declared file list")end
if not s then if J then
J.warn(P,"Refused unsafe source path from repo '"..c.name.."': "..tostring(r))end;return
f(O..a..
"' declares an unsafe file path: "..tostring(r))end;i=i+1;if i>ac then return
f(O..a.."' exceeds the "..ac.."-file limit")end
local w=c.url.."/"..s;local u=I.join(e,s)local t=u:match("^(.*)/[^/]+$")if t and t~=""then
I.makeDirectory(t)end;local x,y,v=g.download(w,u,{maxBytes=aj})if not x then
return f(
"downloading "..s..": "..tostring(y))end
j=j+ ((v and v.bytes)or 0)
if j>ab then return
f(O..a..
"' exceeds the "..math.floor(ab/1024).." KB total limit")end end;if i==0 then return
f(O..a.."' listed no installable files")end;if J then
J.info(P,string.format("Fetched %s from %s (%d files, %d bytes)",a,c.name,i,j))end
return n,nil,{repo=c.name,url=c.url,files=i,bytes=j,discovered=
c.discovered and c.url or nil}end
function H.cleanup(a)if type(a)~=K then return end;local b=a:match("^("..
Z:gsub("%-","%%-").."/[^/]+)")if b then
pcall(I.remove,b)end end;H.STAGE_ROOT=Z;H.REPO_CFG=N;H.KNOWN_CFG=M;H.MAX_KNOWN=Y;H._safeRepoPath=af;return H