
local P,Q,R,S,T,U,K="%.lua$",".disabled","Unknown service: ","_kernel_","component","function","string"local G={}local I="/etc/rc.d"local H={}local F=nil;local E=nil;local V=nil
local W={["fs.read"]=true,["fs.write"]=true,[T]=true,["net"]=true}
local X={["fs.read"]=true,["fs.write"]=true,[T]=true,["compat.io"]=true,["load"]=true,["net"]=true}
local L={["computer"]=true,[T]=true,["kernel.event"]=true,["kernel.log"]=true,["kernel.serialize"]=true,["kernel.config"]=true}
local function M(a)if type(a)~=K then
error("require: module name must be a string",2)end;if L[a]then return require(a)end
error(
"rc.d kernel service denied require('"..a.."') (#SEC CR-6)",2)end;local Y=600;local function J()local b,a=pcall(require,"computer")
return(
b and type(a)=="table"and type(a.uptime)==U)and
a.uptime()or 0 end
local function Z(a)
if
type(a)~="table"then local c={}for d,e in pairs(W)do c[d]=e end;return c end;local b={}for c,d in pairs(a)do local e;if type(c)=="number"and type(d)==K then e=d elseif
type(c)==K and d then e=c end
if e and X[e]then b[e]=true end end
return b end
local function _(a)local c,b=pcall(require,"kernel.users")if not c or not b then
return nil,"users module unavailable"end
if not a then if _G._TOS and _G._TOS.bootSession then return
_G._TOS.bootSession end;if b.kernelSession then
return b.kernelSession()end;return nil,"no session available"end;if a==S then if b.kernelSession then return b.kernelSession()end;return nil,
"kernelSession unavailable"end
if
b.sessionFor then local d=b.sessionFor(a)if d then return d end end
if b.getUser then local d=b.getUser(a)if d and b.createSession then
local e=b.createSession(d)if e then return e end end end;return nil,"unknown user '"..tostring(a).."'"end;function G.init(a)F=a.fs;E=a.log;V=a.proc end
local function aa(a)local e,c,d={},{},{}
local function f(g)
if e[g]then return end
if d[g]then if E then
E.warn("rc","Circular dependency at '"..g.."' — breaking cycle")end;return end;d[g]=true;local h=a[g]
if h and h.deps then for j,i in ipairs(h.deps)do f(i)end end;d[g]=nil;e[g]=true;c[#c+1]=g end;local b={}for g in pairs(a)do b[#b+1]=g end;table.sort(b)for h,g in ipairs(b)do
f(g)end;return c end
local function ab(a)a=a:gsub("%-%-%[(=*)%[.-%]%1%]","")local b={}
for c in
(a.."\n"):gmatch("([^\n]*)\n")do local d,e,f,g=1,false,false,#c
while d<=#c do local h=c:sub(d,d)
if
not e and not f and h=="-"and c:sub(d+1,d+1)=="-"then g=d-1;break end
if not f and h=="'"and c:sub(d-1,d-1)~="\\"then e=not e end
if not e and h=='"'and c:sub(d-1,d-1)~="\\"then f=not f end;d=d+1 end;b[#b+1]=c:sub(1,g)end;return table.concat(b,"\n")end
local function ac(a)local b={}local c=ab(a)local d=c:match("caps%s*=%s*(%b{})")
if d then
local i,f=pcall(require,"kernel.serialize")local h,g=false,nil;if i and type(f)=="table"and f.decode then
h,g=pcall(f.decode,d)end
if h and type(g)=="table"then b.caps=g else
b.caps={}
for j in d:gmatch('"([%w%._]+)"')do b.caps[#b.caps+1]=j end
for j in d:gmatch("'([%w%._]+)'")do b.caps[#b.caps+1]=j end end end
b.user=a:match('user%s*=%s*"([%w_-]+)"')or a:match("user%s*=%s*'([%w_-]+)'")if b.user==S then b._kernelClaimed=true end
b.restart=
c:match("restart%s*=%s*true")and true or false
b.needs=c:match('needs%s*=%s*"([%w_]+)"')or c:match("needs%s*=%s*'([%w_]+)'")local e=c:match("maxRestart%s*=%s*(%d+)")if e then
b.maxRestart=tonumber(e)end;return b end
local ad={net={met=function()return _G._TOS~=nil and _G._TOS.net~=nil end,reason="needs network hardware",hint="add a network card or linked card and reboot"}}
local ae={["10-discoveryd"]=true,["20-chatrelay"]=true,["20-fileshare"]=true,["20-rshd"]=true}
local function af(a)
for b in(a.."\n"):gmatch("([^\n]*)\n")do local d={}local c=1;local e,f=false,false
while c<=#b do
local g=b:sub(c,c)if
not e and not f and g=="-"and b:sub(c+1,c+1)=="-"then break end;if not f and g=="'"and
b:sub(c-1,c-1)~="\\"then e=not e end
if not e and g=='"'and b:sub(
c-1,c-1)~="\\"then f=not f end;d[#d+1]=g;c=c+1 end
if table.concat(d):find('"_kernel_"',1,true)or
table.concat(d):find("'_kernel_'",1,true)then return true end end;return false end
local function ag()
local a={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,rawequal=rawequal,rawlen=rawlen,setmetatable=setmetatable,getmetatable=getmetatable,math=math,string=string,table=table,utf8=utf8,coroutine=coroutine,print=print,require=M,_VERSION=_VERSION}
if _G._TOS then local b=_G._TOS
a._TOS=setmetatable({},{__index=b,__newindex=function(d,c)
error("_TOS is read-only from rc.d services (key="..tostring(c)..")",2)end,__metatable=false})end;a._G=a;return a end
local function N(a)local f,b;local d=I.."/"..a;local c=a:gsub(P,"")if E then
E.info("rc","Loading: "..a)end;local e=F.readFile(d)
if e then local g=ac(e)
if g._kernelClaimed then
if not ae[c]then if E then
E.warn("rc",
"Refusing kernel-tier service '"..a.."': not in C2 allowlist; demoting to user-tier")end;g.user="root"elseif
not af(e)then if E then
E.warn("rc","Refusing kernel-tier service '"..a.."': _kernel_ token only appears in comments")end;g.user="root"end end;local i=Z(g.caps)local h=g.needs and ad[g.needs]
if
h and not h.met()then
H[c]={running=false,unavailable=h.reason,hint=h.hint,disabledAtBoot=F.exists(I.."/"..c..Q),path=d,deps={},restart=false,caps=i,user=g.user,restartCount=0,maxRestart=0}if E then
E.info("rc","Not loading "..a..": "..h.reason)end;return H[c]end;local j,k=_(g.user)
if not j then
b="Skipping '"..a.."': "..tostring(k)if E then E.warn("rc",b)end else local l;if g.user==S then l=ag()else
l=require("kernel.sandbox").build({caps=i,session=j,allowUserLibs=true})end
local m,n=load(e,"="..d,"t",l)
if m then local p,o=pcall(m)
if p then
if type(o)=="table"and o.start then
local q=F.exists(I.."/"..c..Q)
H[c]={start=o.start,stop=o.stop,running=false,disabledAtBoot=q,path=d,deps=o.deps or{},restart=g.restart or(o.restart and true)or false,caps=i,user=g.user,restartCount=0,maxRestart=
g.maxRestart or o.maxRestart or 5}f=H[c]end else b="Error in "..a..": "..tostring(o)if E then
E.warn("rc",b)end end else
b="Syntax error in "..a..": "..tostring(n)if E then E.warn("rc",b)end end end end;return f,b end
function G.runAll()if not F then return end
if not F.exists(I)then F.makeDirectory(I)return end;local b=F.list(I)if not b then return end;local a={}
if type(b)=="table"then for e,d in ipairs(b)do if
d:match(P)then a[#a+1]=d end end elseif type(b)==U then for d in b do if
d:match(P)then a[#a+1]=d end end end;table.sort(a)for e,d in ipairs(a)do N(d)end;local c=aa(H)
for e,d in ipairs(c)do
local f=H[d]
if f and f.unavailable then elseif f and f.disabledAtBoot and not f.running then
if E then E.info("rc",
"Service registered (disabled): "..d)end elseif f and not f.running then local h,g=pcall(f.start)
if h then f.running=true
f.startedAt=J()
if E then E.info("rc","Service started: "..d)end else f.running=false;f.lastError=tostring(g)if E then
E.warn("rc","Service start failed: "..d..
": "..tostring(g))end end end end end
function G.stopAll()
for b,a in pairs(H)do
if a.running and a.stop then local c,d=pcall(a.stop)
if c then a.running=false;if E then E.info("rc",
"Service stopped: "..b)end else if E then
E.warn("rc",
"Service stop failed: "..b..": "..tostring(d))end end end end end
local function O(a)if H[a]then return a end;for b in pairs(H)do
if b:match("^%d+%-(.+)$")==a then return b end end;return a end
function G.start(a)a=O(a)local b=H[a]
if b and b.running then return false,"Already running"end;if
type(a)~=K or not a:match("^[%w_][%w_.%-]*$")or a:find("..",1,true)then
return false,R..tostring(a)end
if F and
F.exists(I.."/"..a..".lua")then local e,f=N(a..".lua")if not e then return false,f or
("Not a service: "..a)end;b=e;if b.unavailable then return false,
a..
" "..b.unavailable.." ("..b.hint..")"end elseif b then
H[a]=nil;b=nil end;if not b then return false,R..a end;local c,d=pcall(b.start)
if c then b.running=true
b.startedAt=J()b.restartCount=0;if b.disabledAtBoot and F then
pcall(F.remove,I.."/"..a..Q)b.disabledAtBoot=false end;return true end;return false,tostring(d)end
function G.stop(a)a=O(a)local b=H[a]if not b then return false,R..a end;if not b.running then
return false,"Not running"end
if not b.stop then return false,"No stop handler"end;local c,d=pcall(b.stop)if c then b.running=false;return true end;return false,
tostring(d)end
function G.list()local a={}
for c,b in pairs(H)do
a[#a+1]={name=c,running=b.running,enabled=not b.disabledAtBoot,path=b.path,deps=b.deps,restart=b.restart,restartCount=b.restartCount,caps=b.caps,user=b.user,unavailable=b.unavailable}end
table.sort(a,function(c,d)return c.name<d.name end)return a end
function G.tryRestart(a)local b=H[a]if not b then return false end
if not b.restart then return false end
if b.startedAt and J()-b.startedAt>=Y then b.restartCount=0 end
if b.restartCount>=b.maxRestart then if E then
E.warn("rc","Service '"..a..
"' exceeded max restarts ("..b.maxRestart..")")end;return false end;b.restartCount=b.restartCount+1;if E then
E.info("rc","Restarting service: "..a.." (attempt "..
b.restartCount..")")end;local c,d=pcall(b.start)if c then
b.running=true;b.startedAt=J()return true end;if E then
E.warn("rc","Restart failed: "..a..": "..
tostring(d))end;return false end
function G.supervise()
for b,a in pairs(H)do
if a.running and type(a.check)==U then
local c,d=pcall(a.check)if not c or not d then a.running=false
a.lastError=(not c)and tostring(d)or"check returned false"end end;if a.restart and not a.running and not a.disabledAtBoot then
G.tryRestart(b)end end end;function G.enable(a,b)if not F then return false end;if not F.exists(I)then
F.makeDirectory(I)end
return F.writeFile(I.."/"..a..".lua",b)end;function G.disable(a)if not
F then return false end;G.stop(a)return
F.remove(I.."/"..a..".lua")end
G._gatedKernelRequire=M;G._KERNEL_REQUIRE_ALLOW=L;return G