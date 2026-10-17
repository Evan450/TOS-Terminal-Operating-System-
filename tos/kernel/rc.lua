
local N,J,O,P,Q,R,S="component","string","function","_kernel_","%.lua$",".disabled","Unknown service: "local F={}local H="/etc/rc.d"local G={}local E=nil;local D=nil;local T=nil
local U={["fs.read"]=true,["fs.write"]=true,[N]=true,["net"]=true}
local V={["fs.read"]=true,["fs.write"]=true,[N]=true,["compat.io"]=true,["load"]=true,["net"]=true}
local K={["computer"]=true,[N]=true,["kernel.event"]=true,["kernel.log"]=true,["kernel.serialize"]=true,["kernel.config"]=true}
local function L(a)if type(a)~=J then
error("require: module name must be a string",2)end;if K[a]then return require(a)end
error(
"rc.d kernel service denied require('"..a.."') (#SEC CR-6)",2)end;local W=600;local function I()local b,a=pcall(require,"computer")
return(
b and type(a)=="table"and type(a.uptime)==O)and
a.uptime()or 0 end
local function X(a)
if
type(a)~="table"then local c={}for d,e in pairs(U)do c[d]=e end;return c end;local b={}for c,d in pairs(a)do local e;if type(c)=="number"and type(d)==J then e=d elseif
type(c)==J and d then e=c end
if e and V[e]then b[e]=true end end
return b end
local function Y(a)local c,b=pcall(require,"kernel.users")if not c or not b then
return nil,"users module unavailable"end
if not a then if _G._TOS and _G._TOS.bootSession then return
_G._TOS.bootSession end;if b.kernelSession then
return b.kernelSession()end;return nil,"no session available"end;if a==P then if b.kernelSession then return b.kernelSession()end;return nil,
"kernelSession unavailable"end
if
b.sessionFor then local d=b.sessionFor(a)if d then return d end end
if b.getUser then local d=b.getUser(a)if d and b.createSession then
local e=b.createSession(d)if e then return e end end end;return nil,"unknown user '"..tostring(a).."'"end;function F.init(a)E=a.fs;D=a.log;T=a.proc end
local function Z(a)local e,c,d={},{},{}
local function f(g)
if e[g]then return end
if d[g]then if D then
D.warn("rc","Circular dependency at '"..g.."' — breaking cycle")end;return end;d[g]=true;local h=a[g]
if h and h.deps then for j,i in ipairs(h.deps)do f(i)end end;d[g]=nil;e[g]=true;c[#c+1]=g end;local b={}for g in pairs(a)do b[#b+1]=g end;table.sort(b)for h,g in ipairs(b)do
f(g)end;return c end
local function _(a)a=a:gsub("%-%-%[(=*)%[.-%]%1%]","")local b={}
for c in
(a.."\n"):gmatch("([^\n]*)\n")do local d,e,f,g=1,false,false,#c
while d<=#c do local h=c:sub(d,d)
if
not e and not f and h=="-"and c:sub(d+1,d+1)=="-"then g=d-1;break end
if not f and h=="'"and c:sub(d-1,d-1)~="\\"then e=not e end
if not e and h=='"'and c:sub(d-1,d-1)~="\\"then f=not f end;d=d+1 end;b[#b+1]=c:sub(1,g)end;return table.concat(b,"\n")end
local function aa(a)local b={}local c=_(a)local d=c:match("caps%s*=%s*(%b{})")
if d then
local i,f=pcall(require,"kernel.serialize")local h,g=false,nil;if i and type(f)=="table"and f.decode then
h,g=pcall(f.decode,d)end
if h and type(g)=="table"then b.caps=g else
b.caps={}
for j in d:gmatch('"([%w%._]+)"')do b.caps[#b.caps+1]=j end
for j in d:gmatch("'([%w%._]+)'")do b.caps[#b.caps+1]=j end end end
b.user=a:match('user%s*=%s*"([%w_-]+)"')or a:match("user%s*=%s*'([%w_-]+)'")if b.user==P then b._kernelClaimed=true end
b.restart=
c:match("restart%s*=%s*true")and true or false
b.needs=c:match('needs%s*=%s*"([%w_]+)"')or c:match("needs%s*=%s*'([%w_]+)'")local e=c:match("maxRestart%s*=%s*(%d+)")if e then
b.maxRestart=tonumber(e)end;return b end
local ab={net={met=function()return _G._TOS~=nil and _G._TOS.net~=nil end,reason="needs network hardware",hint="add a network card or linked card and reboot"}}
local ac={["10-discoveryd"]=true,["20-chatrelay"]=true,["20-fileshare"]=true,["20-rshd"]=true}
local function ad(a)
for b in(a.."\n"):gmatch("([^\n]*)\n")do local d={}local c=1;local e,f=false,false
while c<=#b do
local g=b:sub(c,c)if
not e and not f and g=="-"and b:sub(c+1,c+1)=="-"then break end;if not f and g=="'"and
b:sub(c-1,c-1)~="\\"then e=not e end
if not e and g=='"'and b:sub(
c-1,c-1)~="\\"then f=not f end;d[#d+1]=g;c=c+1 end
if table.concat(d):find('"_kernel_"',1,true)or
table.concat(d):find("'_kernel_'",1,true)then return true end end;return false end
local function ae()
local a={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,rawequal=rawequal,rawlen=rawlen,setmetatable=setmetatable,getmetatable=getmetatable,math=math,string=string,table=table,utf8=utf8,coroutine=coroutine,print=print,require=L,_VERSION=_VERSION}
if _G._TOS then local b=_G._TOS
a._TOS=setmetatable({},{__index=b,__newindex=function(d,c)
error("_TOS is read-only from rc.d services (key="..tostring(c)..")",2)end,__metatable=false})end;a._G=a;return a end
local function M(a)local f,b;local d=H.."/"..a;local c=a:gsub(Q,"")if D then
D.info("rc","Loading: "..a)end;local e=E.readFile(d)
if e then local g=aa(e)
if g._kernelClaimed then
if not ac[c]then if D then
D.warn("rc",
"Refusing kernel-tier service '"..a.."': not in C2 allowlist; demoting to user-tier")end;g.user="root"elseif
not ad(e)then if D then
D.warn("rc","Refusing kernel-tier service '"..a.."': _kernel_ token only appears in comments")end;g.user="root"end end;local i=X(g.caps)local h=g.needs and ab[g.needs]
if
h and not h.met()then
G[c]={running=false,unavailable=h.reason,hint=h.hint,disabledAtBoot=E.exists(H.."/"..c..R),path=d,deps={},restart=false,caps=i,user=g.user,restartCount=0,maxRestart=0}if D then
D.info("rc","Not loading "..a..": "..h.reason)end;return G[c]end;local j,k=Y(g.user)
if not j then
b="Skipping '"..a.."': "..tostring(k)if D then D.warn("rc",b)end else local l;if g.user==P then l=ae()else
l=require("kernel.sandbox").build({caps=i,session=j,allowUserLibs=true})end
local m,n=load(e,"="..d,"t",l)
if m then local p,o=pcall(m)
if p then
if type(o)=="table"and o.start then
local q=E.exists(H.."/"..c..R)
G[c]={start=o.start,stop=o.stop,running=false,disabledAtBoot=q,path=d,deps=o.deps or{},restart=g.restart or(o.restart and true)or false,caps=i,user=g.user,restartCount=0,maxRestart=
g.maxRestart or o.maxRestart or 5}f=G[c]end else b="Error in "..a..": "..tostring(o)if D then
D.warn("rc",b)end end else
b="Syntax error in "..a..": "..tostring(n)if D then D.warn("rc",b)end end end end;return f,b end
function F.runAll()if not E then return end
if not E.exists(H)then E.makeDirectory(H)return end;local b=E.list(H)if not b then return end;local a={}
if type(b)=="table"then for e,d in ipairs(b)do if
d:match(Q)then a[#a+1]=d end end elseif type(b)==O then for d in b do if
d:match(Q)then a[#a+1]=d end end end;table.sort(a)for e,d in ipairs(a)do M(d)end;local c=Z(G)
for e,d in ipairs(c)do local f=G[d]
if
f and f.unavailable then elseif f and f.disabledAtBoot and not f.running then
if D then D.info("rc",
"Service registered (disabled): "..d)end elseif f and not f.running then local h,g=pcall(f.start)
if h then f.running=true
f.startedAt=I()
if D then D.info("rc","Service started: "..d)end else f.running=false;f.lastError=tostring(g)if D then
D.warn("rc","Service start failed: "..d..
": "..tostring(g))end end end end end
function F.stopAll()
for b,a in pairs(G)do
if a.running and a.stop then local c,d=pcall(a.stop)
if c then a.running=false;if D then D.info("rc",
"Service stopped: "..b)end else if D then
D.warn("rc",
"Service stop failed: "..b..": "..tostring(d))end end end end end
function F.start(a)local b=G[a]
if b and b.running then return false,"Already running"end;if
type(a)~=J or not a:match("^[%w_][%w_.%-]*$")or a:find("..",1,true)then
return false,S..tostring(a)end
if E and
E.exists(H.."/"..a..".lua")then local e,f=M(a..".lua")if not e then return false,f or
("Not a service: "..a)end;b=e;if b.unavailable then return false,
a..
" "..b.unavailable.." ("..b.hint..")"end elseif b then
G[a]=nil;b=nil end;if not b then return false,S..a end;local c,d=pcall(b.start)
if c then b.running=true
b.startedAt=I()b.restartCount=0;if b.disabledAtBoot and E then
pcall(E.remove,H.."/"..a..R)b.disabledAtBoot=false end;return true end;return false,tostring(d)end
function F.stop(a)local b=G[a]if not b then return false,S..a end;if not b.running then
return false,"Not running"end
if not b.stop then return false,"No stop handler"end;local c,d=pcall(b.stop)if c then b.running=false;return true end;return false,
tostring(d)end
function F.list()local a={}
for c,b in pairs(G)do
a[#a+1]={name=c,running=b.running,enabled=not b.disabledAtBoot,path=b.path,deps=b.deps,restart=b.restart,restartCount=b.restartCount,caps=b.caps,user=b.user,unavailable=b.unavailable}end
table.sort(a,function(c,d)return c.name<d.name end)return a end
function F.tryRestart(a)local b=G[a]if not b then return false end
if not b.restart then return false end
if b.startedAt and I()-b.startedAt>=W then b.restartCount=0 end
if b.restartCount>=b.maxRestart then if D then
D.warn("rc","Service '"..a..
"' exceeded max restarts ("..b.maxRestart..")")end;return false end;b.restartCount=b.restartCount+1;if D then
D.info("rc","Restarting service: "..a.." (attempt "..
b.restartCount..")")end;local c,d=pcall(b.start)if c then
b.running=true;b.startedAt=I()return true end;if D then
D.warn("rc","Restart failed: "..a..": "..
tostring(d))end;return false end
function F.supervise()
for b,a in pairs(G)do
if a.running and type(a.check)==O then
local c,d=pcall(a.check)if not c or not d then a.running=false
a.lastError=(not c)and tostring(d)or"check returned false"end end;if a.restart and not a.running and not a.disabledAtBoot then
F.tryRestart(b)end end end;function F.enable(a,b)if not E then return false end;if not E.exists(H)then
E.makeDirectory(H)end
return E.writeFile(H.."/"..a..".lua",b)end;function F.disable(a)if not
E then return false end;F.stop(a)return
E.remove(H.."/"..a..".lua")end
F._gatedKernelRequire=L;F._KERNEL_REQUIRE_ALLOW=K;return F