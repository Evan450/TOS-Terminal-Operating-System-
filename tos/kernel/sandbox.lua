
local bf,bg,az,bh,bi,aR,bj,av,aS,aJ,bk,aE,bl,aw="access denied","compat.filesystem","compat.io","compat.process","compat.term","component","fs.write","function","kernel.fs","kernel.process","legacy","number","sandbox","string"local ax={}local aA=require("kernel.policyload")(bl)
local aT="kernel."local bm=aA.MODULE_PREFIXES;local aU=aA.MODULE_NAMES;local bn=aA.BLOCKED_MODULES
local aV,aK={},0;local bo=128
local function ay(a,b)local d=tostring(a).."|"..tostring(b)if aV[d]or aK>=
bo then return end;aV[d]=true;aK=aK+1
local c=package.loaded["kernel.log"]if c and c.warn then
pcall(c.warn,bl,"denied: "..
tostring(a).." wanted "..tostring(b))end end
local function aW()local a=package.loaded[aJ]
local b=a and a.current and a.current()return b and b.name or"?"end
local function bp(a)return type(a)==aw and a:sub(1,#aT)==aT end;local function bq(a)
for c,b in ipairs(bm)do if a:sub(1,#b)==b then return true end end;return false end;local function br(a)if
a:find("[^%w_.-]")then return false end
if a:sub(1,1)=="."then return false end;return true end;local function aB(a)local b={}for c,d in
pairs(a)do b[c]=d end;return b end;local aL=nil
do
local b,a=pcall(require,"unicode")if b and type(a)=="table"then aL=a end end
local function bs(b,a,...)a=type(a)
for c=1,select("#",...)do if a==select(c,...)then return end end
error(string.format("bad argument #%d (%s expected, got %s)",b,table.concat({...}," or "),a),3)end;local aX={}local aM=setmetatable({},{__mode="k"})
local bt={__tostring=function(a)return"exit "..
tostring(rawget(a,"code"))end,__metatable=false}
local function bu()
return
{time=os.time,date=os.date,clock=os.clock,difftime=os.difftime,sleep=function(a)local c,b=pcall(require,aJ)if
c and type(b)=="table"and type(b.sleep)==av then return
b.sleep(tonumber(a)or 0)end
error("os.sleep: the process scheduler is unavailable",2)end,exit=function(a)
error(setmetatable({[aX]=true,code=a},bt),0)end}end;local aF=nil
local function bv(a)if aF==nil then local c,b=pcall(require,"kernel.event")
aF=(c and
type(b)=="table"and type(b.reservedSignal)==av and
b.reservedSignal)or
false end;if
not aF then return true end;return aF(a)end
local bw={modem_message=true,tos_shutdown=true,tos_logout=true,tos_login_complete=true,tos_seat_changed=true,tos_shell_exited=true}local aY;local function aN()local a=package.loaded[aJ]
return
a and type(a.current)==av and a.current()or nil end;local function bx(a,b)local d=aN()local c;if d then
c=d.modemPorts else c=aY end;local e=c and c[a]
return e~=nil and e[b]~=nil end
local function aZ(a)local b=a[1]if not
bw[b]then return false end;return not
(b=="modem_message"and bx(a[2],a[4]))end
function ax.releasePorts(a)local b=a and a.modemPorts;if not b then return end;a.modemPorts=nil
local c=require(aR)
for e,d in pairs(b)do for f,g in pairs(d)do
if g==a then d[f]=nil;pcall(c.invoke,e,"close",f)end end end end
local function by()local a=package.loaded[aJ]if
a and type(a.inProcess)==av then return a.inProcess()end;return
(coroutine.isyieldable and
coroutine.isyieldable())and true or false end
local function a_(a)local b=require("computer")local c;if
type(a)==aE and a>=0 and a~=math.huge then c=b.uptime()+a end
if by()then
while true do
local f=table.pack(coroutine.yield())local g=f[1]
if g~=nil and not aZ(f)then return table.unpack(f,1,f.n)end;if c and b.uptime()>=c then return nil end end end;local d=3
local e=b.uptime()+ (
(type(a)==aE and a>=0 and a<d)and a or d)
while true do local g=e-b.uptime()if g<0 then return nil end
local f=table.pack(b.pullSignal(g))local h=f[1]if h==nil then return nil end;if not aZ(f)then
return table.unpack(f,1,f.n)end end end
local function bz()local a=require("computer")
return
{uptime=a.uptime,freeMemory=a.freeMemory,totalMemory=a.totalMemory,address=a.address,pullSignal=a_,pushSignal=function(b,...)if bv(b)then return end;return
a.pushSignal(b,...)end,energy=a.energy,maxEnergy=a.maxEnergy}end;ax._safePullSignal=a_;local ba=aA.BASE_COMPONENTS;local bA=aA.GATED_COMPONENTS
local aG={}local aH={}local aO=false
local function bb()if aO then return end;aO=true;local e,c=pcall(require,aS)
local f,g=pcall(require,"kernel.serialize")if not(e and f)then return end;local d="/etc/component_caps.cfg"if
not c.exists(d)then return end;local b=c.readFile(d)if not b or#b==0 or#b>8192 then
return end
local h,a=pcall(g.decode,b,{maxBytes=8192})if not h or type(a)~="table"then return end;if
type(a.base)=="table"then
for j,i in ipairs(a.base)do if
type(i)==aw and#i<=64 and i:match("^[%w_]+$")then aG[i]=true end end end
if
type(a.gated)=="table"then
for i,j in pairs(a.gated)do if
type(i)==aw and#i<=64 and
i:match("^[%w_]+$")and type(j)==aw and#j<=64 and j:match("^[%w_%.]+$")then
aH[i]=j end end end end
function ax.reloadComponentConfig()aG={}aH={}aO=false;bb()return aG,aH end
local function aC(a,b)if not a then return false end;bb()if ba[a]or aG[a]then return true end;local c=
bA[a]or aH[a]if c and b and b[c]then return true end;return false end;local bP=ba;local aP={gpu=true,screen=true,keyboard=true}
local function aQ()
local d,b=pcall(require,"kernel.screen")if not d or type(b)~="table"or not b.callerDevices then return
nil end
local e,a=pcall(b.callerDevices)if not e or type(a)~="table"then return nil end;if not a.gpu then
return nil end;local c={[a.gpu]=true}
if a.screen then c[a.screen]=true end;for g,f in ipairs(a.keyboards or{})do c[f]=true end;return c,a end
local function bB(a)local c,b=aQ()if not c then return nil end;if a=="gpu"then return b.gpu end;if
a=="screen"then return b.screen end;if a=="keyboard"then return
(b.keyboards or{})[1]end;return nil end;local bc=aA.SERVICE_PORTS
local function bC(a)local b=_G._TOS and _G._TOS.net;if b and
type(b.kernelPorts)==av then
return b.kernelPorts()[a]==true end;return a==42 end
local function bD(a,b,c)local g=a.address;local d=b[g]if not d then d={}b[g]=d end;local f={}
for h,i in pairs(a)do f[h]=i end
local function e(h,i)ay(aW(),"modem port "..tostring(h))return nil,"port "..
tostring(h).." "..i end
function f.open(h)
if type(h)~=aE then return e(h,"is not a number")end;h=math.floor(h)
if bC(h)then return e(h,"is the kernel's")end
if not c and bc[h]then return e(h,"belongs to "..bc[h])end;if d[h]then return a.open(h)end;if a.isOpen(h)then
return e(h,"is already in use")end;local i,j=a.open(h)
if i then
local k=not c and aN()or nil;d[h]=k or true;if k then k.modemPorts=b elseif not c then aY=b end end;return i,j end
function f.close(h)if h==nil then local i=false
for j in pairs(d)do d[j]=nil;a.close(j)i=true end;return i end;if type(h)~=aE then return
e(h,"is not a number")end;h=math.floor(h)if not d[h]then return
e(h,"is not yours")end;d[h]=nil;return a.close(h)end;return f end
local function bE(a,b)a=a or{}local c=require(aR)local d={}local h,f={},{}
local function e(i)
if not i or not i.address then return i end;local j=f[i.address]if not j then j=bD(i,h,b and b.service)
f[i.address]=j end;return j end;local function g(i,j)if not aP[j]then return false end;local k=aQ()if not k then return false end;return
not k[i]end
function d.list(i,j)
local l=c.list(i,j)local k=aQ()
return function()
while true do local m,n=l()if m==nil then return nil end
local o=k and aP[n]and not k[m]if aC(n,a)and not o then return m,n end end end end
function d.proxy(i)local j=c.type(i)if not aC(j,a)then return nil,bf end;if g(i,j)then
return nil,"not your seat"end
if j=="modem"then return e(c.proxy(i))end;return c.proxy(i)end;function d.type(i)return c.type(i)end
function d.slot(i)return c.slot(i)end;function d.get(i,j)local k=c.get(i,j)
if k then local l=c.type(k)if aC(l,a)then return k end end;return nil,bf end
function d.invoke(i,j,...)
local k=c.type(i)if not aC(k,a)then
ay(aW(),"component "..tostring(k))
error("sandbox: access denied to "..tostring(k))end;if g(i,k)then
error("sandbox: "..tostring(k)..
" belongs to another seat")end
if k=="modem"and
(j=="open"or j=="close")then return e(c.proxy(i))[j](...)end;return c.invoke(i,j,...)end
function d.isAvailable(i)if not aC(i,a)then return false end;return c.isAvailable(i)end
function d.getPrimary(i)if not aC(i,a)then return nil,bf end;if aP[i]then local j=bB(i)if j then
return c.proxy(j)end end;if i=="modem"then return
e(c.getPrimary(i))end;return c.getPrimary(i)end;return d end
local function bF(a)
local function b(c)local f,d=pcall(a.getPrimary,c)if f and d then return d end
local g,e=pcall(a.list,c,true)
if g and type(e)==av then local h=e()if h then return(a.proxy(h))end end;return nil end
return
setmetatable({},{__index=function(d,c)local e=a[c]if e~=nil then return e end
if type(c)==aw then return b(c)end;return nil end,__pairs=function()local c;return function()local d
c,d=next(a,c)return c,d end end,__newindex=function()
error("component view is read-only",2)end,__metatable=false})end;local bG={"/usr/lib","/usr/modules"}
local function bH(a)local b=a:gsub("%.","/")return{b..".lua",
b.."/init.lua"}end
local function bd(a)local b=nil;local c,d=pcall(require,aS)if c then b=d end;if not b then return nil end;for f,e in
ipairs(bG)do
for f,g in ipairs(bH(a))do local h=e.."/"..g;if b.exists(h)then return h end end end;return nil end
local function aD(a,b)if type(a)~="table"then return a end;local c=a
if b then c=function(e,d)if b[d]then return nil end
return a[d]end end
return
setmetatable({},{__index=c,__len=function()return#a end,__pairs=function()local d
return function()local e;repeat d,e=next(a,d)until
d==nil or not(b and b[d])return d,e end end,__call=function(d,...)return a(...)end,__metatable=false})end
local bI={[bi]={_gpuForCaps=true},[bh]={_forProgram=true}}
local bJ={"send","broadcast","on","off","onceFrom","offAll","waitFor","sendMessage","requestTrust","discover","getAddress","getHostname","isAvailable","modemCount"}
local function be(a)if type(a)~="table"then return a end;return
{addr=a.addr,lastSeen=a.lastSeen,hostname=a.hostname,device=a.device,trust=a.trust}end
local bK={"PING","PONG","HELLO","HELLO_ACK","INFO_REQ","INFO_RES","MSG","MSG_ACK","DENY","ERROR"}
local function aI(a,b)if type(a)~="table"then return a end;if b>16 then return nil end;local c={}
for d,e in next,a do if
type(d)~="table"then c[d]=aI(e,b+1)end end;return c end
local function bL(a)local b={}
for m,l in ipairs(bJ)do if type(a[l])==av then b[l]=a[l]end end
local j,f=pcall(function()return a.getProtocol and a.getProtocol()end)
local k=
j and type(f)=="table"and type(f.TYPE)=="table"and f.TYPE or{}local d={}
for m,l in ipairs(bK)do d[k[l]or l:lower()]=true end
local function e(l,m)return nil,
"net: programs may not "..m.." '"..tostring(l).."' packets"end;b.on,b.onceFrom,b.off,b.offAll,b.send,b.broadcast=nil,nil,nil,nil,nil,nil
local c={}
local function g(l,m)if m~=nil then c[l]=c[l]or{}c[l][m]=true end;return m end
local function h(l)return function(m,n)return l(aI(m,0),n)end end
if type(a.on)==av then
b.on=function(l,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=av then return nil,"net.on: callback must be a function"end;return g(l,a.on(l,h(m)))end end
if type(a.onceFrom)==av then
b.onceFrom=function(l,n,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=av then return nil,"net.onceFrom: callback must be a function"end;return g(l,a.onceFrom(l,n,h(m)))end end
if type(a.off)==av then
b.off=function(l,m)
if not(c[l]and c[l][m])then return false end;c[l][m]=nil;return a.off(l,m)end
b.offAll=function(l)if type(l)~="table"then return end;for n,m in ipairs(l)do if type(m)=="table"then
b.off(m.type,m.id)end end end end
if type(a.send)==av then
b.send=function(m,l,n)local o=aI(l,0)
if
type(o)~="table"or not d[o.type]then return
e(type(o)=="table"and o.type or type(l),"send")end;return a.send(m,o,n)end end
if type(a.broadcast)==av then
b.broadcast=function(l,m)local n=aI(l,0)
if type(n)~="table"or
not d[n.type]then return
e(type(n)=="table"and n.type or type(l),"broadcast")end;return a.broadcast(n,m)end end
local function i(l)local m={}for n,o in ipairs(type(l)=="table"and l or{})do
m[n]=be(o)end;return m end;if type(a.peers)==av then
b.peers=function()return i(a.peers())end end;if type(a.scan)==av then b.scan=function(l)
return i(a.scan(l))end end;if
type(a.findPeer)==av then
b.findPeer=function(l)return be(a.findPeer(l))end end
if type(a.getProtocol)==av then b.getProtocol=function()return
aD(a.getProtocol())end end
if type(a.status)==av then
b.status=function()local l,m=a.status(),{}
for o,n in pairs(
type(l)=="table"and l or{})do if type(n)~="table"then m[o]=n end end;return m end end;return b end;local bM={[az]=az,[bg]=az,["compat.shell_api"]=az}
local bN={sides="compat.sides",colors="compat.colors",keyboard="compat.keyboard",text="compat.text",serialization="compat.serialization",buffer="compat.buffer",term=bi,event="compat.event",shell="compat.shell_api",filesystem=bg,io=az,internet="compat.internet",robot="compat.robot",process=bh,note="compat.note"}
local function bO(a,c,b)local d={}local e={}if c then for g,h in pairs(c)do d[g]=h end end;local f
f=function(g)if type(g)~=
aw then
error("bad argument #1 to 'require' (string expected)",2)end;if d[g]~=nil then return d[g]end;if
bp(g)then ay(a.pkgName or a.name,"module "..g)
error(
"sandbox: cannot require kernel module '"..g.."'",2)end
if g=="unicode"then local i=
b and b.env and b.env.unicode;if i==nil then
error("sandbox: module 'unicode' is not available",2)end;d[g]=i;return i end;local h=bN[g]
if h then local k=_G._TOS;if k and k.compatDisabled then
error("sandbox: '"..g..
"' is OpenOS's, and the compat layer is off in this boot profile",2)end
local i=b and b.env;if
(g=="io"or g=="filesystem")and i and i[g]~=nil then d[g]=i[g]return i[g]end
local l,j=pcall(f,h)if not l then
error("sandbox: require('"..g..
"'): "..tostring(j):gsub("^sandbox: ",""),2)end;d[g]=j;return j end
if g=="compat.component"then local i=c and c.component;if not i then
ay(a.pkgName or a.name,"capability component")
error("sandbox: 'compat.component' needs the component capability",2)end;d[g]=i
return i end
if g=="compat.internet"and
not(a.caps and a.caps["internet"])then
ay(a.pkgName or a.name,"capability internet")
error("sandbox: 'compat.internet' needs the internet capability",2)end
do local i=bM[g]
if i and not
(a.caps and(a.caps[i]or a.caps[bk]))then
ay(a.pkgName or a.name,"capability "..i)
error("sandbox: '"..g.."' needs the "..i.." capability",2)end end
if g=="compat"and aU.compat then local k,i=pcall(require,"compat")if not k or type(i)~=
"table"then
error("sandbox: the compat layer is unavailable",2)end
local j={has=i.has,list=i.list}d[g]=j;return j end
if bn[g]then
if
not(a and a.allowUserLibs and bd(g))then
ay(a and(a.pkgName or a.name),"module "..g)
error("sandbox: module '"..g.."' is not available to sandboxed code",2)end end
if aU[g]or bq(g)then local i=require(g)local j=aD(i,bI[g])
if
g==bi and type(i)=="table"and type(i._gpuForCaps)==av then
local k=a and a.caps;j.gpu=function()return i._gpuForCaps(k)end
local l=i.read
j.read=function(...)
if a and a.flushForRead then a.flushForRead()else local m=aN()if m and m.beforeRead then
m.beforeRead("")end end;return l(...)end end
if
g==bh and type(i)=="table"and type(i._forProgram)==av then local k=i._forProgram(a and a.name,b and b.env)if type(k)==
"table"then j.info=k.info;j.running=k.running end end;d[g]=j;return j end
if br(g)then local i=bd(g)
if i then local k=_G._TOS and _G._TOS.users
if a.session and k and
k.canAccessAs then local s=k.canAccessAs(a.session,i,"r")if not s then
error(
"sandbox: access denied loading user lib '"..g.."'",2)end end;if a.allowUserLibs then local s=require(g)d[g]=s;return s end
local m=b and b.env;if type(m)~="table"then
error("sandbox: no environment to load user lib '"..g.."' into",2)end;if e[g]then
error("sandbox: circular require of '"..g.."'",2)end;local p,l=pcall(require,aS)
local n=p and
type(l)=="table"and l.readFile and l.readFile(i)if type(n)~=aw then
error("sandbox: cannot read user lib '"..g.."'",2)end;local o,q=load(n,"="..i,"t",m)if not o then
error(
"sandbox: cannot load user lib '"..g.."': "..tostring(q),2)end;e[g]=true;local r,j=pcall(o,g)
e[g]=nil;if not r then
error("sandbox: user lib '"..g.."' failed: "..tostring(j),2)end;if j==nil then j=true end;d[g]=j;return j end end
error("sandbox: module '"..g.."' is not on the allowed list",2)end;return f end
function ax.build(a)a=a or{}local c=a.caps or{}local l=a.session
local e=_G._TOS and _G._TOS.securefs
if not e then local t,u=pcall(require,"kernel.securefs")if t then e=u end end;local d=nil;if e and(c["fs.read"]or c[bj])then
d=e.forSession(l)end
local function n(t)
local v={"exists","isDirectory","list","readFile","size","lastModified","normalize","split","join","spaceTotal","spaceUsed","spaceFree","mounts","home","resolve"}local u={}
for x,w in ipairs(v)do local y=t[w]if type(y)==av then
u[w]=function(...)return y(...)end end end
if type(t.open)==av then
u.open=function(x,w,...)w=w or"r"
if
type(w)~=aw or w:find("[wa+]")then return nil,"fs.write capability required"end;return t.open(x,w,...)end end;return u end;local i=nil
local function o(...)local u={}
for v=1,select("#",...)do u[v]=tostring(select(v,...))end;local t=table.concat(u,"\t")if i then i(t)elseif a.stdout then a.stdout(t)elseif
type(print)==av then print(t)end end;local j=getmetatable("")local p=string;local function f(t)if t==nil then return false end;return
t==j or t==p end
local function q(t)
if type(t)==aw then return nil end;local u=getmetatable(t)if j~=nil and u==j then return nil end;return u end
local function r(v,u)if type(v)~="table"then
error("bad argument #1 to 'setmetatable' (table expected)",2)end
if u~=nil then if type(u)~="table"then
error("bad argument #2 to 'setmetatable' (nil or table expected)",2)end
if

f(u)or
f(rawget(u,"__index"))or f(rawget(u,"__newindex"))or f(rawget(u,"__metatable"))then
error("setmetatable: metatable referencing protected library denied",2)end end;return setmetatable(v,u)end;local s=aB(string)local g,h;if c[aR]then g=bF(bE(c,a))h=bz()end
local k={}if g then k.component=g end;if h then k.computer=h end;local m={}
local b={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,unpack=table.unpack,rawequal=rawequal,rawlen=rawlen,setmetatable=r,getmetatable=q,math=aB(math),string=s,table=aB(table),utf8=
utf8 and aB(utf8)or nil,coroutine=aB(coroutine),unicode=aL and aB(aL)or nil,checkArg=bs,print=o,require=bO(a,k,m)}m.env=b;b._G=b;b._ENV=b;b._VERSION=_VERSION;if d then
if c[bj]then b.fs=d else b.fs=n(d)end end
if c[az]then local t,u=pcall(require,az)
if t then b.io=aD(u)end;b.os=bu()local v,w=pcall(require,bg)if v then b.filesystem=aD(w)end end
if c[bk]then b.os=os;b.io=io;local u,t=pcall(require,"kernel.log")if
u and t and t.warn then
t.warn(bl,"Built env with legacy cap — full os/io exposed")end end
if c[az]and not c[bk]and type(a.stdout)==av and type(b.io)==
"table"then
local u,t=pcall(require,"compat.buffer")
if u and type(t)=="table"and type(t.new)==av then
local y,v=a.stdout,""
local function A(G)v=v..G;local H=1;while true do local I=v:find("\n",H,true)if not I then break end
y(v:sub(H,I-1))H=I+1 end;v=v:sub(H)end
local function B()return
t.new("w",{write=function(H,G)A(G)end,close=function()end})end;local x=b.io;local z,C=B(),B()local w={input=x.stdin,output=z}local function D(G)return
G==z or G==C or G==x.stdin end
local function E(H,G,I)if type(G)==aw then
local K,L=x.open(G,I)if not K then error(L,3)end;G=K end
local J=w[H]
if J~=G and not D(J)and type(J)=="table"and
type(J.close)==av then pcall(J.close,J)end;w[H]=G end
b.io=setmetatable({stdout=z,stderr=C,output=function(G)if G then E("output",G,"w")end;return w.output end,input=function(G)if
G then E("input",G,"r")end;return w.input end,write=function(...)return
w.output:write(...)end,read=function(...)return w.input:read(...)end,lines=function(G,...)if
G==nil then return w.input:lines()end
return x.lines(G,...)end,close=function(G)G=G or w.output
if D(G)then return true end;return G:close()end},{__index=x,__metatable=false})i=function(G)A(G.."\n")end
a.flushForRead=function()local G=v;v=""if a.beforeRead then
a.beforeRead(G)elseif G~=""then y(G)end end;local F=b.io.read
b.io.read=function(...)a.flushForRead()return F(...)end
aM[b]=function()if v~=""then local G=v;v=""y(G)end end end end;if c[aR]then b.component=g;b.computer=h end
if c["load"]then b.load=function(t,u,v,w)
return load(t,u,"t",b)end;b.loadstring=b.load end
if c["notify"]then local u,t=pcall(require,"kernel.notify")
if
u and t and t.post then local v={}
b.notify={post=function(w)
if type(w)~="table"then return nil,"spec must be a table"end;local x={}for B,C in pairs(w)do x[B]=C end;local y=a.pkgName
x.from=(type(y)==aw and
y:match("^[%w][%w%-]*$"))and y or"package"local z,A=t.post(x)if z~=nil then v[z]=true end;return z,A end,result=function(w)if
not v[w]then return nil end;return t.result(w)end}end end
if c["net"]then local u,t=pcall(require,"kernel.net")if u then b.net=
a.allowUserLibs and aD(t)or bL(t)end end
do local t=nil
for w in pairs(c)do
local x=type(w)==aw and w:match("^ipc:(.+)$")if x then t=t or{}t[x]=true end end;local v,u=false,nil
if t then v,u=pcall(require,"kernel.ipc")end
if v and u then
b.ipc={call=function(w,...)if not t[w]then
return nil,"this program may not reach '"..tostring(w).."'"end;return u.call(w,l,...)end}end end
if c["internet"]then local u,t=pcall(require,"kernel.internet")
if u and t then
b.internet={get=function(v,w)return
t.get(v,w)end,download=function(w,x,v)if not(c[bj]and d)then
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
if type(v)==aw and v:match("^[%w][%w%-]*$")then
b.crypto.secret=function()local w=
nil;local C,y=pcall(require,aJ)if C and y and y.currentSession then
w=y.currentSession()end
if not w then
local H=_G._TOS and _G._TOS.users
if not H then local I,J=pcall(require,"kernel.users")if I then H=J end end;if H and H.currentSession then w=H.currentSession()end end
local D=w and(w.isKernel or w.isLogin or
(type(w.tier)==aE and w.tier>=2))
if not D then return nil,"crypto.secret requires an admin session"end;local E,x=pcall(require,aS)
if not E or not x then return nil,"fs unavailable"end;local z="/var/pkg/secrets"local A=z.."/"..v
if x.exists(A)then local H=x.readFile(A)if H and
#H>=16 then return H end;return nil,"secret unreadable"end;if not x.exists(z)then x.makeDirectory(z)end
local B=t.salt(32)local F,G=x.writeFile(A,B)if not F then
return nil,"cannot store secret: "..tostring(G)end;return B end end end end;return b end
function ax.run(a,b,c,...)local e=ax.build(c)local d,f=load(a,b,"t",e)if not d then return false,
"compile error: "..tostring(f)end;return pcall(d,...)end
function ax.finish(a)local b=aM[a]if b then aM[a]=nil;pcall(b)end end
function ax.exitStatus(a)
if type(a)=="table"and rawget(a,aX)==true then
local b=rawget(a,"code")if b==nil then return true end;return b end;return nil end
function ax.describeEnd(b,a)
if b then local d=type(a)if d==aw or d==aE or d=="boolean"then return tostring(a),
false end;return nil end;local c=ax.exitStatus(a)
if c==nil then return tostring(a),true end;if c==true or c==0 then return nil end;return
"exited with status "..tostring(c),false end;return ax