
local bj,bk,aA,bl,bm,aM,aV,ax,bn,aW,aN,bo,aG,bp,az="access denied","compat.filesystem","compat.io","compat.process","compat.term","component","fs.write","function","internet","kernel.fs","kernel.process","legacy","number","sandbox","string"local ay={}local aC=require("kernel.policyload")(bp)
local aX="kernel."local bq=aC.MODULE_PREFIXES;local aY=aC.MODULE_NAMES;local br=aC.BLOCKED_MODULES
local aZ,aO={},0;local bs=128
local function aB(a,b)local d=tostring(a).."|"..tostring(b)if aZ[d]or aO>=
bs then return end;aZ[d]=true;aO=aO+1
local c=package.loaded["kernel.log"]if c and c.warn then
pcall(c.warn,bp,"denied: "..
tostring(a).." wanted "..tostring(b))end end
local function a_()local a=package.loaded[aN]
local b=a and a.current and a.current()return b and b.name or"?"end
local function bt(a)return type(a)==az and a:sub(1,#aX)==aX end;local function bu(a)
for c,b in ipairs(bq)do if a:sub(1,#b)==b then return true end end;return false end;local function bv(a)if
a:find("[^%w_.-]")then return false end
if a:sub(1,1)=="."then return false end;return true end;local function aD(a)local b={}for c,d in
pairs(a)do b[c]=d end;return b end;local aP=nil
do
local b,a=pcall(require,"unicode")if b and type(a)=="table"then aP=a end end
local function bw(b,a,...)a=type(a)
for c=1,select("#",...)do if a==select(c,...)then return end end
error(string.format("bad argument #%d (%s expected, got %s)",b,table.concat({...}," or "),a),3)end;local ba={}local aQ=setmetatable({},{__mode="k"})
local bx={__tostring=function(a)return"exit "..
tostring(rawget(a,"code"))end,__metatable=false}
local function by()
return
{time=os.time,date=os.date,clock=os.clock,difftime=os.difftime,sleep=function(a)local c,b=pcall(require,aN)if
c and type(b)=="table"and type(b.sleep)==ax then return
b.sleep(tonumber(a)or 0)end
error("os.sleep: the process scheduler is unavailable",2)end,exit=function(a)
error(setmetatable({[ba]=true,code=a},bx),0)end}end;local aH=nil
local function bz(a)if aH==nil then local c,b=pcall(require,"kernel.event")
aH=(c and
type(b)=="table"and type(b.reservedSignal)==ax and
b.reservedSignal)or
false end;if
not aH then return true end;return aH(a)end
local bA={modem_message=true,tos_shutdown=true,tos_logout=true,tos_login_complete=true,tos_seat_changed=true,tos_shell_exited=true}local bb;local function aR()local a=package.loaded[aN]
return
a and type(a.current)==ax and a.current()or nil end;local function bB(a,b)local d=aR()local c;if d then
c=d.modemPorts else c=bb end;local e=c and c[a]
return e~=nil and e[b]~=nil end
local function bc(a)local b=a[1]if not
bA[b]then return false end;return not
(b=="modem_message"and bB(a[2],a[4]))end
function ay.releasePorts(a)local b=a and a.modemPorts;if not b then return end;a.modemPorts=nil
local c=require(aM)
for e,d in pairs(b)do for f,g in pairs(d)do
if g==a then d[f]=nil;pcall(c.invoke,e,"close",f)end end end end
local function bC()local a=package.loaded[aN]if
a and type(a.inProcess)==ax then return a.inProcess()end;return
(coroutine.isyieldable and
coroutine.isyieldable())and true or false end
local function bd(a)local b=require("computer")local c;if
type(a)==aG and a>=0 and a~=math.huge then c=b.uptime()+a end
if bC()then
while true do
local f=table.pack(coroutine.yield())local g=f[1]
if g~=nil and not bc(f)then return table.unpack(f,1,f.n)end;if c and b.uptime()>=c then return nil end end end;local d=3
local e=b.uptime()+ (
(type(a)==aG and a>=0 and a<d)and a or d)
while true do local g=e-b.uptime()if g<0 then return nil end
local f=table.pack(b.pullSignal(g))local h=f[1]if h==nil then return nil end;if not bc(f)then
return table.unpack(f,1,f.n)end end end
local function bD()local a=require("computer")
return
{uptime=a.uptime,freeMemory=a.freeMemory,totalMemory=a.totalMemory,address=a.address,pullSignal=bd,pushSignal=function(b,...)if bz(b)then return end;return
a.pushSignal(b,...)end,energy=a.energy,maxEnergy=a.maxEnergy}end;ay._safePullSignal=bd;local be=aC.BASE_COMPONENTS;local bE=aC.GATED_COMPONENTS
local aI={}local aJ={}local aS=false
local function bf()if aS then return end;aS=true;local e,c=pcall(require,aW)
local f,g=pcall(require,"kernel.serialize")if not(e and f)then return end;local d="/etc/component_caps.cfg"if
not c.exists(d)then return end;local b=c.readFile(d)if not b or#b==0 or#b>8192 then
return end
local h,a=pcall(g.decode,b,{maxBytes=8192})if not h or type(a)~="table"then return end;if
type(a.base)=="table"then
for j,i in ipairs(a.base)do if
type(i)==az and#i<=64 and i:match("^[%w_]+$")then aI[i]=true end end end
if
type(a.gated)=="table"then
for i,j in pairs(a.gated)do if
type(i)==az and#i<=64 and
i:match("^[%w_]+$")and type(j)==az and#j<=64 and j:match("^[%w_%.]+$")then
aJ[i]=j end end end end
function ay.reloadComponentConfig()aI={}aJ={}aS=false;bf()return aI,aJ end
local function aE(a,b)if not a then return false end;bf()if be[a]or aI[a]then return true end;local c=
bE[a]or aJ[a]if c and b and b[c]then return true end;return false end;local bT=be;local aT={gpu=true,screen=true,keyboard=true}
local function aU()
local d,b=pcall(require,"kernel.screen")if not d or type(b)~="table"or not b.callerDevices then return
nil end
local e,a=pcall(b.callerDevices)if not e or type(a)~="table"then return nil end;if not a.gpu then
return nil end;local c={[a.gpu]=true}
if a.screen then c[a.screen]=true end;for g,f in ipairs(a.keyboards or{})do c[f]=true end;return c,a end
local function bF(a)local c,b=aU()if not c then return nil end;if a=="gpu"then return b.gpu end;if
a=="screen"then return b.screen end;if a=="keyboard"then return
(b.keyboards or{})[1]end;return nil end;local bg=aC.SERVICE_PORTS
local function bG(a)local b=_G._TOS and _G._TOS.net;if b and
type(b.kernelPorts)==ax then
return b.kernelPorts()[a]==true end;return a==42 end
local function bH(a,b,c)local g=a.address;local d=b[g]if not d then d={}b[g]=d end;local f={}
for h,i in pairs(a)do f[h]=i end
local function e(h,i)aB(a_(),"modem port "..tostring(h))return nil,"port "..
tostring(h).." "..i end
function f.open(h)
if type(h)~=aG then return e(h,"is not a number")end;h=math.floor(h)
if bG(h)then return e(h,"is the kernel's")end
if not c and bg[h]then return e(h,"belongs to "..bg[h])end;if d[h]then return a.open(h)end;if a.isOpen(h)then
return e(h,"is already in use")end;local i,j=a.open(h)
if i then
local k=not c and aR()or nil;d[h]=k or true;if k then k.modemPorts=b elseif not c then bb=b end end;return i,j end
function f.close(h)if h==nil then local i=false
for j in pairs(d)do d[j]=nil;a.close(j)i=true end;return i end;if type(h)~=aG then return
e(h,"is not a number")end;h=math.floor(h)if not d[h]then return
e(h,"is not yours")end;d[h]=nil;return a.close(h)end;return f end
local function bI(a,b)a=a or{}local c=require(aM)local d={}local h,f={},{}
local function e(i)
if not i or not i.address then return i end;local j=f[i.address]if not j then j=bH(i,h,b and b.service)
f[i.address]=j end;return j end;local function g(i,j)if not aT[j]then return false end;local k=aU()if not k then return false end;return
not k[i]end
function d.list(i,j)
local l=c.list(i,j)local k=aU()
return function()
while true do local m,n=l()if m==nil then return nil end
local o=k and aT[n]and not k[m]if aE(n,a)and not o then return m,n end end end end
function d.proxy(i)local j=c.type(i)if not aE(j,a)then return nil,bj end;if g(i,j)then
return nil,"not your seat"end
if j=="modem"then return e(c.proxy(i))end;return c.proxy(i)end;function d.type(i)return c.type(i)end
function d.slot(i)return c.slot(i)end;function d.get(i,j)local k=c.get(i,j)
if k then local l=c.type(k)if aE(l,a)then return k end end;return nil,bj end
function d.invoke(i,j,...)
local k=c.type(i)if not aE(k,a)then
aB(a_(),"component "..tostring(k))
error("sandbox: access denied to "..tostring(k))end;if g(i,k)then
error("sandbox: "..tostring(k)..
" belongs to another seat")end
if k=="modem"and
(j=="open"or j=="close")then return e(c.proxy(i))[j](...)end;return c.invoke(i,j,...)end
function d.isAvailable(i)if not aE(i,a)then return false end;return c.isAvailable(i)end
function d.getPrimary(i)if not aE(i,a)then return nil,bj end;if aT[i]then local j=bF(i)if j then
return c.proxy(j)end end;if i=="modem"then return
e(c.getPrimary(i))end;return c.getPrimary(i)end;return d end
local function bJ(a)
local function b(c)local f,d=pcall(a.getPrimary,c)if f and d then return d end
local g,e=pcall(a.list,c,true)
if g and type(e)==ax then local h=e()if h then return(a.proxy(h))end end;return nil end
return
setmetatable({},{__index=function(d,c)local e=a[c]if e~=nil then return e end
if type(c)==az then return b(c)end;return nil end,__pairs=function()local c;return function()local d
c,d=next(a,c)return c,d end end,__newindex=function()
error("component view is read-only",2)end,__metatable=false})end;local bK={"/usr/lib","/usr/modules"}
local function bL(a)local b=a:gsub("%.","/")return{b..".lua",
b.."/init.lua"}end
local function bh(a)local b=nil;local c,d=pcall(require,aW)if c then b=d end;if not b then return nil end;for f,e in
ipairs(bK)do
for f,g in ipairs(bL(a))do local h=e.."/"..g;if b.exists(h)then return h end end end;return nil end
local function aF(a,b)if type(a)~="table"then return a end;local c=a
if b then c=function(e,d)if b[d]then return nil end
return a[d]end end
return
setmetatable({},{__index=c,__len=function()return#a end,__pairs=function()local d
return function()local e;repeat d,e=next(a,d)until
d==nil or not(b and b[d])return d,e end end,__call=function(d,...)return a(...)end,__metatable=false})end
local bM={[bm]={_gpuForCaps=true},[bl]={_forProgram=true}}
local bN={"send","broadcast","on","off","onceFrom","offAll","waitFor","sendMessage","requestTrust","discover","getAddress","getHostname","isAvailable","modemCount"}
local function bi(a)if type(a)~="table"then return a end;return
{addr=a.addr,lastSeen=a.lastSeen,hostname=a.hostname,device=a.device,trust=a.trust}end
local bO={"PING","PONG","HELLO","HELLO_ACK","INFO_REQ","INFO_RES","MSG","MSG_ACK","DENY","ERROR"}
local function aK(a,b)if type(a)~="table"then return a end;if b>16 then return nil end;local c={}
for d,e in next,a do if
type(d)~="table"then c[d]=aK(e,b+1)end end;return c end
local function bP(a)local b={}
for m,l in ipairs(bN)do if type(a[l])==ax then b[l]=a[l]end end
local j,f=pcall(function()return a.getProtocol and a.getProtocol()end)
local k=
j and type(f)=="table"and type(f.TYPE)=="table"and f.TYPE or{}local d={}
for m,l in ipairs(bO)do d[k[l]or l:lower()]=true end
local function e(l,m)return nil,
"net: programs may not "..m.." '"..tostring(l).."' packets"end;b.on,b.onceFrom,b.off,b.offAll,b.send,b.broadcast=nil,nil,nil,nil,nil,nil
local c={}
local function g(l,m)if m~=nil then c[l]=c[l]or{}c[l][m]=true end;return m end
local function h(l)return function(m,n)return l(aK(m,0),n)end end
if type(a.on)==ax then
b.on=function(l,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=ax then return nil,"net.on: callback must be a function"end;return g(l,a.on(l,h(m)))end end
if type(a.onceFrom)==ax then
b.onceFrom=function(l,n,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=ax then return nil,"net.onceFrom: callback must be a function"end;return g(l,a.onceFrom(l,n,h(m)))end end
if type(a.off)==ax then
b.off=function(l,m)
if not(c[l]and c[l][m])then return false end;c[l][m]=nil;return a.off(l,m)end
b.offAll=function(l)if type(l)~="table"then return end;for n,m in ipairs(l)do if type(m)=="table"then
b.off(m.type,m.id)end end end end
if type(a.send)==ax then
b.send=function(m,l,n)local o=aK(l,0)
if
type(o)~="table"or not d[o.type]then return
e(type(o)=="table"and o.type or type(l),"send")end;return a.send(m,o,n)end end
if type(a.broadcast)==ax then
b.broadcast=function(l,m)local n=aK(l,0)
if type(n)~="table"or
not d[n.type]then return
e(type(n)=="table"and n.type or type(l),"broadcast")end;return a.broadcast(n,m)end end
local function i(l)local m={}for n,o in ipairs(type(l)=="table"and l or{})do
m[n]=bi(o)end;return m end;if type(a.peers)==ax then
b.peers=function()return i(a.peers())end end;if type(a.scan)==ax then b.scan=function(l)
return i(a.scan(l))end end;if
type(a.findPeer)==ax then
b.findPeer=function(l)return bi(a.findPeer(l))end end
if type(a.getProtocol)==ax then b.getProtocol=function()return
aF(a.getProtocol())end end
if type(a.status)==ax then
b.status=function()local l,m=a.status(),{}
for o,n in pairs(
type(l)=="table"and l or{})do if type(n)~="table"then m[o]=n end end;return m end end;return b end;local bQ={[aA]=aA,[bk]=aA,["compat.shell_api"]=aA}
local bR={sides="compat.sides",colors="compat.colors",keyboard="compat.keyboard",text="compat.text",serialization="compat.serialization",buffer="compat.buffer",term=bm,event="compat.event",shell="compat.shell_api",filesystem=bk,io=aA,internet="compat.internet",robot="compat.robot",process=bl,note="compat.note"}
local function bS(a,c,b)local d={}local e={}if c then for g,h in pairs(c)do d[g]=h end end;local f
f=function(g)if type(g)~=
az then
error("bad argument #1 to 'require' (string expected)",2)end;if d[g]~=nil then return d[g]end;if
bt(g)then aB(a.pkgName or a.name,"module "..g)
error(
"sandbox: cannot require kernel module '"..g.."'",2)end
if g=="unicode"then local i=
b and b.env and b.env.unicode;if i==nil then
error("sandbox: module 'unicode' is not available",2)end;d[g]=i;return i end;local h=bR[g]
if h then local k=_G._TOS;if k and k.compatDisabled then
error("sandbox: '"..g..
"' is OpenOS's, and the compat layer is off in this boot profile",2)end
local i=b and b.env;if
(g=="io"or g=="filesystem")and i and i[g]~=nil then d[g]=i[g]return i[g]end
local l,j=pcall(f,h)if not l then
error("sandbox: require('"..g..
"'): "..tostring(j):gsub("^sandbox: ",""),2)end;d[g]=j;return j end
if g=="compat.component"then local i=c and c.component;if not i then
aB(a.pkgName or a.name,"capability component")
error("sandbox: 'compat.component' needs the component capability",2)end;d[g]=i
return i end
if
g=="compat.internet"and not(a.caps and a.caps[bn])then aB(a.pkgName or a.name,"capability internet")
error("sandbox: 'compat.internet' needs the internet capability",2)end
do local i=bQ[g]
if i and not
(a.caps and(a.caps[i]or a.caps[bo]))then
aB(a.pkgName or a.name,"capability "..i)
error("sandbox: '"..g.."' needs the "..i.." capability",2)end end
if g=="compat"and aY.compat then local k,i=pcall(require,"compat")if not k or type(i)~=
"table"then
error("sandbox: the compat layer is unavailable",2)end
local j={has=i.has,list=i.list}d[g]=j;return j end
if br[g]then
if
not(a and a.allowUserLibs and bh(g))then
aB(a and(a.pkgName or a.name),"module "..g)
error("sandbox: module '"..g.."' is not available to sandboxed code",2)end end
if aY[g]or bu(g)then local i=require(g)local j=aF(i,bM[g])
if
g==bm and type(i)=="table"and type(i._gpuForCaps)==ax then
local k=a and a.caps;j.gpu=function()return i._gpuForCaps(k)end
local l=i.read
j.read=function(...)
if a and a.flushForRead then a.flushForRead()else local m=aR()if m and m.beforeRead then
m.beforeRead("")end end;return l(...)end end
if
g==bl and type(i)=="table"and type(i._forProgram)==ax then local k=i._forProgram(a and a.name,b and b.env)if type(k)==
"table"then j.info=k.info;j.running=k.running end end;d[g]=j;return j end
if bv(g)then local i=bh(g)
if i then local k=_G._TOS and _G._TOS.users
if a.session and k and
k.canAccessAs then local s=k.canAccessAs(a.session,i,"r")if not s then
error(
"sandbox: access denied loading user lib '"..g.."'",2)end end;if a.allowUserLibs then local s=require(g)d[g]=s;return s end
local m=b and b.env;if type(m)~="table"then
error("sandbox: no environment to load user lib '"..g.."' into",2)end;if e[g]then
error("sandbox: circular require of '"..g.."'",2)end;local p,l=pcall(require,aW)
local n=p and
type(l)=="table"and l.readFile and l.readFile(i)if type(n)~=az then
error("sandbox: cannot read user lib '"..g.."'",2)end;local o,q=load(n,"="..i,"t",m)if not o then
error(
"sandbox: cannot load user lib '"..g.."': "..tostring(q),2)end;e[g]=true;local r,j=pcall(o,g)
e[g]=nil;if not r then
error("sandbox: user lib '"..g.."' failed: "..tostring(j),2)end;if j==nil then j=true end;d[g]=j;return j end end
error("sandbox: module '"..g.."' is not on the allowed list",2)end;return f end
function ay.build(a)a=a or{}local c=a.caps or{}local l=a.session
local e=_G._TOS and _G._TOS.securefs
if not e then local t,u=pcall(require,"kernel.securefs")if t then e=u end end;local d=nil;if e and(c["fs.read"]or c[aV])then
d=e.forSession(l)end
local function n(t)
local v={"exists","isDirectory","list","readFile","size","lastModified","normalize","split","join","spaceTotal","spaceUsed","spaceFree","mounts","home","resolve"}local u={}
for x,w in ipairs(v)do local y=t[w]if type(y)==ax then
u[w]=function(...)return y(...)end end end
if type(t.open)==ax then
u.open=function(x,w,...)w=w or"r"
if
type(w)~=az or w:find("[wa+]")then return nil,"fs.write capability required"end;return t.open(x,w,...)end end;return u end;local i=nil
local function o(...)local u={}
for v=1,select("#",...)do u[v]=tostring(select(v,...))end;local t=table.concat(u,"\t")if i then i(t)elseif a.stdout then a.stdout(t)elseif
type(print)==ax then print(t)end end;local j=getmetatable("")local p=string;local function f(t)if t==nil then return false end;return
t==j or t==p end
local function q(t)
if type(t)==az then return nil end;local u=getmetatable(t)if j~=nil and u==j then return nil end;return u end
local function r(v,u)if type(v)~="table"then
error("bad argument #1 to 'setmetatable' (table expected)",2)end
if u~=nil then if type(u)~="table"then
error("bad argument #2 to 'setmetatable' (nil or table expected)",2)end
if

f(u)or
f(rawget(u,"__index"))or f(rawget(u,"__newindex"))or f(rawget(u,"__metatable"))then
error("setmetatable: metatable referencing protected library denied",2)end end;return setmetatable(v,u)end;local s=aD(string)local g,h;if c[aM]then g=bJ(bI(c,a))h=bD()end
local k={}if g then k.component=g end;if h then k.computer=h end;local m={}
local b={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,unpack=table.unpack,rawequal=rawequal,rawlen=rawlen,setmetatable=r,getmetatable=q,math=aD(math),string=s,table=aD(table),utf8=
utf8 and aD(utf8)or nil,coroutine=aD(coroutine),unicode=aP and aD(aP)or nil,checkArg=bw,print=o,require=bS(a,k,m)}m.env=b;b._G=b;b._ENV=b;b._VERSION=_VERSION;if d then
if c[aV]then b.fs=d else b.fs=n(d)end end
if c[aA]then local t,u=pcall(require,aA)
if t then b.io=aF(u)end;b.os=by()local v,w=pcall(require,bk)if v then b.filesystem=aF(w)end end
if c[bo]then b.os=os;b.io=io;local u,t=pcall(require,"kernel.log")if
u and t and t.warn then
t.warn(bp,"Built env with legacy cap — full os/io exposed")end end
if c[aA]and not c[bo]and type(a.stdout)==ax and type(b.io)==
"table"then
local u,t=pcall(require,"compat.buffer")
if u and type(t)=="table"and type(t.new)==ax then
local y,v=a.stdout,""
local function A(G)v=v..G;local H=1;while true do local I=v:find("\n",H,true)if not I then break end
y(v:sub(H,I-1))H=I+1 end;v=v:sub(H)end
local function B()return
t.new("w",{write=function(H,G)A(G)end,close=function()end})end;local x=b.io;local z,C=B(),B()local w={input=x.stdin,output=z}local function D(G)return
G==z or G==C or G==x.stdin end
local function E(H,G,I)if type(G)==az then
local K,L=x.open(G,I)if not K then error(L,3)end;G=K end
local J=w[H]
if J~=G and not D(J)and type(J)=="table"and
type(J.close)==ax then pcall(J.close,J)end;w[H]=G end
b.io=setmetatable({stdout=z,stderr=C,output=function(G)if G then E("output",G,"w")end;return w.output end,input=function(G)if
G then E("input",G,"r")end;return w.input end,write=function(...)return
w.output:write(...)end,read=function(...)return w.input:read(...)end,lines=function(G,...)if
G==nil then return w.input:lines()end
return x.lines(G,...)end,close=function(G)G=G or w.output
if D(G)then return true end;return G:close()end},{__index=x,__metatable=false})i=function(G)A(G.."\n")end
a.flushForRead=function()local G=v;v=""if a.beforeRead then
a.beforeRead(G)elseif G~=""then y(G)end end;local F=b.io.read
b.io.read=function(...)a.flushForRead()return F(...)end
aQ[b]=function()if v~=""then local G=v;v=""y(G)end end end end;if c[aM]then b.component=g;b.computer=h end
if c["load"]then b.load=function(t,u,v,w)
return load(t,u,"t",b)end;b.loadstring=b.load end
if c["notify"]then local u,t=pcall(require,"kernel.notify")
if
u and t and t.post then local v={}
b.notify={post=function(w)
if type(w)~="table"then return nil,"spec must be a table"end;local x={}for B,C in pairs(w)do x[B]=C end;local y=a.pkgName
x.from=(type(y)==az and
y:match("^[%w][%w%-]*$"))and y or"package"local z,A=t.post(x)if z~=nil then v[z]=true end;return z,A end,result=function(w)if
not v[w]then return nil end;return t.result(w)end}end end
if c["net"]then local u,t=pcall(require,"kernel.net")if u then b.net=
a.allowUserLibs and aF(t)or bP(t)end end
do local t=nil
for w in pairs(c)do
local x=type(w)==az and w:match("^ipc:(.+)$")if x then t=t or{}t[x]=true end end;local v,u=false,nil
if t then v,u=pcall(require,"kernel.ipc")end
if v and u then
b.ipc={call=function(w,...)if not t[w]then
return nil,"this program may not reach '"..tostring(w).."'"end;return u.call(w,l,...)end}end end
if c[bn]then local u,t=pcall(require,"kernel.internet")
if u and t then
b.internet={get=function(v,w)
return t.get(v,w)end,download=function(w,x,v)if not(c[aV]and d)then
return false,"internet.download needs the fs.write capability"end;local y={}
if type(v)=="table"then for A,z in
ipairs({"maxBytes","timeout","headers","method","body"})do y[z]=v[z]end end;y.fs=d;return t.download(w,x,y)end,socket=function(v,w)return
t.socket(v,w)end,status=function()return t.status()end,available=function()
return t.available()end}end end
if c["swap"]then local u,t=pcall(require,"kernel.swap")if u and t and t.table then
b.swap={table=function(v)return
t.table(v)end,freeTable=function(v)return t.freeTable(v)end,usage=t.usage}end end
if c["vault"]then local u,t=pcall(require,"kernel.vault")
if
u and t and t.encrypt and t.decrypt then
b.vault={encrypt=function(v,w,x)return t.encrypt(v,w,x)end,decrypt=function(v,w)return
t.decrypt(v,w)end,isEncrypted=function(v)return t.isEncrypted(v)end}end end
if c["crypto"]then local u,t=pcall(require,"kernel.crypto")
if
u and t and t.hmac then
b.crypto={hash=function(w)return t.hash(w)end,hmac=function(w,x)return t.hmac(w,x)end,ctEquals=function(w,x)return
t.ctEquals(w,x)end,random=function(w)return t.salt(w)end}local v=a.pkgName
if type(v)==az and v:match("^[%w][%w%-]*$")then
b.crypto.secret=function()local w=
nil;local C,y=pcall(require,aN)if C and y and y.currentSession then
w=y.currentSession()end
if not w then
local H=_G._TOS and _G._TOS.users
if not H then local I,J=pcall(require,"kernel.users")if I then H=J end end;if H and H.currentSession then w=H.currentSession()end end
local D=w and(w.isKernel or w.isLogin or
(type(w.tier)==aG and w.tier>=2))
if not D then return nil,"crypto.secret requires an admin session"end;local E,x=pcall(require,aW)
if not E or not x then return nil,"fs unavailable"end;local z="/var/pkg/secrets"local A=z.."/"..v
if x.exists(A)then local H=x.readFile(A)if H and
#H>=16 then return H end;return nil,"secret unreadable"end;if not x.exists(z)then x.makeDirectory(z)end
local B=t.salt(32)local F,G=x.writeFile(A,B)if not F then
return nil,"cannot store secret: "..tostring(G)end;return B end end end end;return b end
function ay.run(a,b,c,...)local e=ay.build(c)local d,f=load(a,b,"t",e)if not d then return false,
"compile error: "..tostring(f)end;return pcall(d,...)end
function ay.finish(a)local b=aQ[a]if b then aQ[a]=nil;pcall(b)end end
function ay.exitStatus(a)
if type(a)=="table"and rawget(a,ba)==true then
local b=rawget(a,"code")if b==nil then return true end;return b end;return nil end
function ay.describeEnd(b,a)
if b then local d=type(a)if d==az or d==aG or d=="boolean"then return tostring(a),
false end;return nil end;local c=ay.exitStatus(a)
if c==nil then return tostring(a),true end;if c==true or c==0 then return nil end;return
"exited with status "..tostring(c),false end
ay.AUDITABLE={"fs.read",aV,aM,aA,"load","net","swap",bn,"vault","crypto","notify"}
local function aL(a,c,d,e,b)
if type(a)==ax then return function(...)e(c,d)return a(...)end end;if type(a)~="table"then return a end;b=b or{}if b[a]then return b[a]end
if
getmetatable(a)==nil then local g={}b[a]=g;for h,i in pairs(a)do
g[h]=aL(i,c,d.."."..tostring(h),e,b)end;return g end
local f=setmetatable({},{__index=function(h,g)local i=a[g]
if type(i)==ax then return function(...)
e(c,d.."."..tostring(g))return i(...)end end;return i end,__newindex=function(i,g,h)a[g]=h end,__pairs=function()return
pairs(a)end,__len=function()return#a end})b[a]=f;return f end;ay._watched=aL
function ay.buildAudit(a,b)local d=a.caps or{}local c=ay.build(a)
for f,e in
ipairs(ay.AUDITABLE)do
if not d[e]then local g,h={},{}for j,k in pairs(d)do g[j]=k end;g[e]=true
for j,k in pairs(a)do h[j]=k end;h.caps=g;local i=ay.build(h)
for j,k in pairs(i)do local l=rawget(c,j)
if l==nil then
rawset(c,j,aL(k,e,tostring(j),b))elseif type(l)=="table"and type(k)=="table"and
getmetatable(l)==nil then local m
for n,o in pairs(k)do
if rawget(l,n)==nil then if not m then m={}for p,q in pairs(l)do
m[p]=q end end;m[n]=aL(o,e,tostring(j)..
"."..tostring(n),b)end end;if m then rawset(c,j,m)end end end end end;return c end;return ay