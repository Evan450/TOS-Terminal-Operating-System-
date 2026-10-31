
local Z,al,Q,R,M="could not write ","internet module unavailable","package '","pkgremote","string"local K=require("kernel.fs")
local N=require("kernel.serialize")local J={}local L=nil;local P="/etc/pkg-repos.cfg"local O="/var/pkg/known-repos.cfg"local _=32
local am=8;local aa="/var/pkg/remote"local U=128*1024;local an=128*1024;local ae=512*1024
local af=64;local V=function()return false end
function J.init(a)a=a or{}L=a.log;if
type(a.validRepoHint)=="function"then V=a.validRepoHint end end
local function T()local a,b=pcall(require,"kernel.internet")if a then return b end;return nil end;local function ag(a)return
type(a)==M and#a<=32 and a:match("^[%w_%-]+$")~=nil end
local function S(a)if
type(a)~=M or a==""or#a>64 then return false end;if
#a==1 then return a:match("^%w$")~=nil end;return
a:match("^%w[%w%-]*%w$")~=nil end;J.validPkgName=S
function J.repos()local a={}if not K.exists(P)then return a end
local b=K.readFile(P)if not b then return a end
local e,c=pcall(N.decode,b,{maxBytes=16384})
if not e or type(c)~="table"then if L then
L.warn(R,"Corrupt "..P.."; ignoring")end;return a end;local d=T()
for g,f in ipairs(c)do
if type(f)=="table"and ag(f.name)and
type(f.url)==M then
local h=d and d.hostOf(f.url)or nil
if h then
a[#a+1]={name=f.name,url=(f.url:gsub("/+$","")),host=h,description=type(f.description)==M and
f.description or nil}elseif L then
L.warn(R,"Repo '"..tostring(f.name).."' has an unusable URL")end end end;return a end
local function ah(a)local b={}for d,c in ipairs(a)do
b[#b+1]={name=c.name,url=c.url,description=c.description}end;return
K.writeFileAtomic and
K.writeFileAtomic(P,N.encode(b))or K.writeFile(P,N.encode(b))end
function J.addRepo(a,b,c)
if not ag(a)then return false,"invalid repo name (letters, digits, _ and - only)"end;local e=T()if not e then return false,al end;local g,h=e.parseUrl(b)
if not g then return false,h end;local d=J.repos()local f=false
for k,j in ipairs(d)do if j.name==a then
j.url,j.description,f=(b:gsub("/+$","")),c,true end end;if not f then
d[#d+1]={name=a,url=(b:gsub("/+$","")),description=c}end;local i=ah(d)
if not i then return false,Z..P end
if L then L.info(R,"Repo '"..a.."' -> "..b)end;return true end
function J.removeRepo(a)local d,b,c=J.repos(),{},false;for f,e in ipairs(d)do
if e.name==a then c=true else b[#b+1]=e end end;if not c then
return false,"no such repo: "..tostring(a)end;if not ah(b)then return false,Z..P end
return true end
local function W()local a={}if not K.exists(O)then return a end;local b=K.readFile(O)if not b then
return a end;local d,c=pcall(N.decode,b,{maxBytes=16384})
if not d or
type(c)~="table"then if L then
L.warn(R,"Corrupt "..O.."; ignoring")end;return a end
for g,f in ipairs(c)do
if type(f)=="table"and V(f.url)then local e={}for g,h in ipairs(
type(f.from)=="table"and f.from or{})do if S(h)then
e[#e+1]=h end end
a[#a+1]={url=(f.url:gsub("/+$","")),from=e}end end;while#a>_ do table.remove(a,1)end;return a end
local function ab(a)local b={}
for e,d in ipairs(a)do b[#b+1]={url=d.url,from=d.from}end;local c=N.encode(b)
if K.writeFileAtomic then return K.writeFileAtomic(O,c)end;return K.writeFile(O,c)end;function J.known()return W()end
function J.learn(b,a)if type(b)~="table"then return 0 end
local c=W()local e={}for h,g in ipairs(J.repos())do e[g.url]=true end;local d=0
for h,g in
ipairs(b)do
if V(g)then local i=(g:gsub("/+$",""))
if not e[i]then local j;for h,k in ipairs(c)do
if k.url==i then j=k;break end end
if not j then j={url=i,from={}}c[#c+1]=j;d=d+1 end;if S(a)then local k=false;for h,l in ipairs(j.from)do if l==a then k=true end end
if
not k and#j.from<8 then j.from[#j.from+1]=a end end end end end;while#c>_ do table.remove(c,1)end;local f=ab(c)
if not f then return 0,Z..O end;if d>0 and L then
L.info(R,("Learned %d repo(s) from '%s' (known, not trusted)"):format(d,tostring(a)))end;return d end
function J.forget(a)local b=W()
if a=="all"then if not ab({})then return false,Z..O end;return true,#b end;local c=tonumber(a)if not c then local d=type(a)==M and(a:gsub("/+$",""))or
nil
for f,g in ipairs(b)do if g.url==d then c=f end end end
if
not c or not b[c]then return false,
"no known repo "..tostring(a).." (see 'pkg repo list')"end;table.remove(b,c)if not ab(b)then return false,Z..O end
return true,1 end
local function ao(a)if not V(a)then return nil end;a=(a:gsub("/+$",""))
local f,b=pcall(require,"kernel.crypto")local c=T()
if
not f or type(b)~="table"or type(b.hash)~="function"or not c then return nil end;local e=c.hostOf and c.hostOf(a)
local d=tostring(b.hash(a)or"")
if not e or not d:match("^%x+$")or#d<12 then return nil end
return{name="k"..d:sub(1,12),url=a,host=e,discovered=true}end
local function ap(b,a)local d,e,c={},{},{}for h,g in ipairs(b)do d[g.url]=true end
local function f(g)if
#c>=am or type(g)~=M then return end;local h=(g:gsub("/+$",""))
if d[h]or e[h]then return end;e[h]=true;local i=ao(h)if i then c[#c+1]=i end end
for h,g in ipairs(type(a)=="table"and a or{})do f(g)end;for h,g in ipairs(W())do f(g.url)end;return c end
local function ai(a)if type(a)~=M or a==""then return nil end
if#a>256 then return nil end;if a:find("[%c]")then return nil end
if a:find("\\",1,true)then return nil end;if a:sub(1,1)=="/"then return nil end
if a:find("://",1,true)then return nil end
if a:find("?",1,true)or a:find("#",1,true)then return nil end;if a:find("@",1,true)then return nil end;for b in a:gmatch("[^/]+")do if
b=="."or b==".."then return nil end end;return
(a:gsub("/+","/"))end;local X={}local Y={}local aj=64*1024
function J.index(a,b)b=b or{}local d=T()if not d then return nil,al end
if not
b.refresh and X[a.name]then return X[a.name].index end;local e=a.url.."/programs.cfg"local f,g=d.get(e,{maxBytes=U})if
not f then
return nil,"could not fetch "..e..": "..tostring(g)end
local h,c=pcall(N.decode,f,{maxBytes=U,maxCost=aj,maxKeys=1024})
if not h or type(c)~="table"then return nil,"repo '"..
a.name.."' returned an index that is not a table"end;X[a.name]={index=c}return c end;function J.clearCache()X={}Y={}end;local ac=4096
local function aq(b,a,c)if
not c.refresh and Y[a.name]~=nil then return Y[a.name]end
local f,g,d=b.get(a.url.."/programs.sig",{maxBytes=ac})local e
if type(f)==M then local h,i=pcall(N.decode,f,{maxBytes=ac})
e=(h and type(i)==
"table")and f or false else d=type(d)=="table"and d or{}local h=tonumber(d.status)or
tonumber(tostring(g):match("^HTTP (%d%d%d)"))
if
(h and
h>=400 and h<500)or(d.bytes or 0)>ac then e=false else
return nil,"could not ask repo '"..
a.name.."' whether it signs its index: "..
tostring(g).."  [E-501 ERR_NET_NO_ANSWER]"end end;Y[a.name]=e;return e end;local function ad(a)return type(a)==M and a or nil end
local function ak(a)
local b={}
for d,c in ipairs(type(a)=="table"and a or{})do local e=
type(c)=="table"and c.name or c;e=type(e)==M and
e:match("^%S+")if e and S(e)then b[#b+1]=e end end;return b end
function J.search(a)local b={}
for d,c in ipairs(J.repos())do local e,f=J.index(c,a)
if e then
for h,g in pairs(e)do
if type(h)==M and
type(g)=="table"and not g.hidden then
local i=ak(g.requires)
for j in
pairs(type(g.dependencies)=="table"and g.dependencies or{})do if S(j)then i[#i+1]=j end end
b[#b+1]={name=h,repo=c.name,description=g.description or g.note,version=g.version,category=ad(g.category),kind=ad(g.kind),author=ad(g.author),requires=i,recommends=ak(g.recommends)}end end elseif L then L.warn(R,tostring(f))end end
table.sort(b,function(c,d)return(c.name or"")< (d.name or"")end)return b end
function J.fetch(a,b)b=b or{}if not S(a)then
return nil,"not a package name: "..tostring(a):sub(1,64)..
"  [E-602 ERR_PKG_BAD_NAME]"end;local g=T()
if not g then return nil,al end;if not g.available()then local r=g.status()return nil,
r.reason or"internet is not available"end
local l=J.repos()
local q=b.discoveredPolicy~=nil and b.discoveredPolicy~="off"local k=q and ap(l,b.hints)or{}
if#l==0 and#k==0 then return nil,
"no remote repositories configured (see 'pkg repo add')"end;local c,d;local h={}for t,s in ipairs(l)do local r,u=J.index(s,b)
if
r and type(r[a])=="table"then c,d=s,r[a]break elseif not r then h[#h+1]=tostring(u)end end
if not d then
for t,s in
ipairs(k)do local r,u=J.index(s,b)if r and type(r[a])=="table"then c,d=s,r[a]break elseif not r then h[#h+
1]=tostring(u)end end end;local m,p
if d then local r,s=aq(g,c,b)if r==nil then return nil,s end
if r then
local u,w=g.get(c.url.."/programs.cfg",{maxBytes=U})local v,t=false,nil;if type(u)==M then
v,t=pcall(N.decode,u,{maxBytes=U,maxCost=aj,maxKeys=1024})end
if not
(v and type(t)=="table")then
return nil,"repo '"..
c.name.."' signs its index, and re-reading it failed: "..
tostring(w or"it did not decode")end;if type(t[a])~="table"then
return nil,Q..tostring(a)..
"' is no longer in repo '"..c.name.."''s signed index"end;m,p,d=u,r,t[a]end end
if not d then
local r=Q..tostring(a)..
"' is not in any configured repo".. (
#k>0 and(", nor in the "..
#k.." other repo(s) it was pointed to")or"")if#h>0 then
r=r.." ("..table.concat(h,"; ")..")"end
return nil,r.."  [E-601 ERR_PKG_NOT_FOUND]"end;if type(d.files)~="table"then
return nil,Q..a.."' declares no files"end
for r,s in pairs(d.files)do
if
type(r)~=M or type(s)~=M then
return nil,
Q..a..
"' in repo '"..c.name..
"' has a malformed file list (expected { [\"source/path\"] = \"/dest/dir\" }, got "..type(r).." -> "..
type(s)..")"end end;local e=K.join(aa,c.name.."."..a)local n=K.join(e,a)
pcall(K.remove,e)
if
not K.makeDirectory(e)or not K.makeDirectory(n)then return nil,"could not create staging directory "..n end;local function f(r)pcall(K.remove,e)return nil,r end;local o
if m then
o=
K.writeFile(K.join(e,"programs.cfg"),m)and K.writeFile(K.join(e,"programs.sig"),p)else
o=K.writeFile(K.join(e,"programs.cfg"),N.encode({[a]=d}))end
if not o then return f("could not stage the package index")end;local i,j=0,0
for r in pairs(d.files)do local s=ai(r:gsub("^:",""))
if
r:sub(1,1)==":"then return
f(Q..
a.."' uses an OPPM directory-copy entry ("..
tostring(r).."); TOS installs a declared file list")end
if not s then if L then
L.warn(R,"Refused unsafe source path from repo '"..c.name.."': "..tostring(r))end;return
f(Q..a..
"' declares an unsafe file path: "..tostring(r))end;i=i+1;if i>af then return
f(Q..a.."' exceeds the "..af.."-file limit")end
local w=c.url.."/"..s;local u=K.join(e,s)local t=u:match("^(.*)/[^/]+$")if t and t~=""then
K.makeDirectory(t)end;local x,y,v=g.download(w,u,{maxBytes=an})if not x then
return f(
"downloading "..s..": "..tostring(y))end
j=j+ ((v and v.bytes)or 0)
if j>ae then return
f(Q..a..
"' exceeds the "..math.floor(ae/1024).." KB total limit")end end;if i==0 then return
f(Q..a.."' listed no installable files")end;if L then
L.info(R,string.format("Fetched %s from %s (%d files, %d bytes)",a,c.name,i,j))end
return n,nil,{repo=c.name,url=c.url,files=i,bytes=j,discovered=
c.discovered and c.url or nil}end
function J.cleanup(a)if type(a)~=M then return end;local b=a:match("^("..
aa:gsub("%-","%%-").."/[^/]+)")if b then
pcall(K.remove,b)end end;J.STAGE_ROOT=aa;J.REPO_CFG=P;J.KNOWN_CFG=O;J.MAX_KNOWN=_;J._safeRepoPath=ai
return J