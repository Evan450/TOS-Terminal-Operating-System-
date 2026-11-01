
local aU,aV,as,aW,aX,aH,aY,aZ,ap,a_,aI,aJ,ba,aK,bb,aq="access denied","compat.filesystem","compat.io","compat.process","compat.term","component","computer","fs.write","function","internet","kernel.fs","kernel.process","legacy","number","peripheral.inventory","string"local ar={}local aL="kernel."local bc={"compat.","peripheral."}
local bd={compat=true,["shell.keys"]=true}
local be={["debug"]=true,["package"]=true,["os"]=true,["io"]=true,[aH]=true,[aY]=true,["filesystem"]=true,["shell.init"]=true,["shell.ext"]=true,["shell.panels.init"]=true,["shell.panels.commands"]=true,["shell.panels.events"]=true,["shell.panels.executor"]=true,["shell.panels.state"]=true,["shell.panels.draw"]=true,["shell.panels.helpers"]=true,["shell.panels.filebrowser"]=true,["shell.panels.editor"]=true,["shell.panels.menus"]=true,["shell.panels.dialogs"]=true,["shell.panels.context"]=true,["shell.panels.keymap"]=true,["shell.panels.tabs"]=true,["shell.panels.widgets"]=true,["shell.panels.mouse"]=true,["shell.panels.ui"]=true,["shell.panels.desktop"]=true,["shell.panels.settingsapp"]=true,["shell.panels.apps"]=true,["shell.panels.monitorapp"]=true,["shell.panels.chatapp"]=true,["mail"]=true,["mailui"]=true,["mailapp"]=true,["rbmk-cmd"]=true,["rbmk-controld"]=true,["rbmk.core"]=true,["rbmk-skala"]=true,["rbmk.skala"]=true,["rbmk.wall"]=true,["shell.panels.takeover"]=true,["shell.login"]=true,["shell.chat"]=true,["shell.tutorial"]=true,["shell.syntax"]=true,["shell.panels"]=true,["shell"]=true,["bios"]=true,["init"]=true,["install"]=true,["system_manifest"]=true}local aM,aB={},0;local bf=128
local function at(a,b)
local d=tostring(a).."|"..tostring(b)if aM[d]or aB>=bf then return end;aM[d]=true;aB=aB+1
local c=package.loaded["kernel.log"]if c and c.warn then
pcall(c.warn,"sandbox","denied: "..
tostring(a).." wanted "..tostring(b))end end
local function bg()local a=package.loaded[aJ]
local b=a and a.current and a.current()return b and b.name or"?"end
local function bh(a)return type(a)==aq and a:sub(1,#aL)==aL end;local function bi(a)
for c,b in ipairs(bc)do if a:sub(1,#b)==b then return true end end;return false end;local function bj(a)if
a:find("[^%w_.-]")then return false end
if a:sub(1,1)=="."then return false end;return true end;local function au(a)local b={}for c,d in
pairs(a)do b[c]=d end;return b end;local aC=nil
do
local b,a=pcall(require,"unicode")if b and type(a)=="table"then aC=a end end
local function bk(b,a,...)a=type(a)
for c=1,select("#",...)do if a==select(c,...)then return end end
error(string.format("bad argument #%d (%s expected, got %s)",b,table.concat({...}," or "),a),3)end;local aN={}local aD=setmetatable({},{__mode="k"})
local bl={__tostring=function(a)return"exit "..
tostring(rawget(a,"code"))end,__metatable=false}
local function bm()
return
{time=os.time,date=os.date,clock=os.clock,difftime=os.difftime,sleep=function(a)local c,b=pcall(require,aJ)if
c and type(b)=="table"and type(b.sleep)==ap then return
b.sleep(tonumber(a)or 0)end
error("os.sleep: the process scheduler is unavailable",2)end,exit=function(a)
error(setmetatable({[aN]=true,code=a},bl),0)end}end;local ax=nil
local function bn(a)if ax==nil then local c,b=pcall(require,"kernel.event")
ax=(c and
type(b)=="table"and type(b.reservedSignal)==ap and
b.reservedSignal)or
false end;if
not ax then return true end;return ax(a)end
local aO={modem_message=true,tos_shutdown=true,tos_logout=true,tos_login_complete=true,tos_seat_changed=true,tos_shell_exited=true}
local function bo()local a=package.loaded[aJ]if
a and type(a.inProcess)==ap then return a.inProcess()end;return
(coroutine.isyieldable and
coroutine.isyieldable())and true or false end
local function aP(a)local b=require(aY)local c;if
type(a)==aK and a>=0 and a~=math.huge then c=b.uptime()+a end
if bo()then
while true do
local f=table.pack(coroutine.yield())local g=f[1]
if g~=nil and not aO[g]then return table.unpack(f,1,f.n)end;if c and b.uptime()>=c then return nil end end end;local d=3
local e=b.uptime()+ (
(type(a)==aK and a>=0 and a<d)and a or d)
while true do local g=e-b.uptime()if g<0 then return nil end
local f=table.pack(b.pullSignal(g))local h=f[1]if h==nil then return nil end;if not aO[h]then
return table.unpack(f,1,f.n)end end end
local function bp()local a=require(aY)
return
{uptime=a.uptime,freeMemory=a.freeMemory,totalMemory=a.totalMemory,address=a.address,pullSignal=aP,pushSignal=function(b,...)if bn(b)then return end;return
a.pushSignal(b,...)end,energy=a.energy,maxEnergy=a.maxEnergy}end;ar._safePullSignal=aP
local aQ={gpu=true,screen=true,keyboard=true,crafting=true,navigation=true,geolyzer=true,note_block=true,sign=true}
local bq={modem="peripheral.modem",tunnel="peripheral.modem",redstone="peripheral.redstone",robot="peripheral.robot",inventory_controller=bb,transposer=bb,tank_controller=bb,tape_drive="peripheral.tape",internet=a_,tractor_beam="peripheral.tractor",piston="peripheral.piston",hologram="peripheral.hologram",openprinter="peripheral.printer"}local ay={}local az={}local aE=false
local function aR()if aE then return end;aE=true;local e,c=pcall(require,aI)
local f,g=pcall(require,"kernel.serialize")if not(e and f)then return end;local d="/etc/component_caps.cfg"if
not c.exists(d)then return end;local b=c.readFile(d)if not b or#b==0 or#b>8192 then
return end
local h,a=pcall(g.decode,b,{maxBytes=8192})if not h or type(a)~="table"then return end;if
type(a.base)=="table"then
for j,i in ipairs(a.base)do if
type(i)==aq and#i<=64 and i:match("^[%w_]+$")then ay[i]=true end end end
if
type(a.gated)=="table"then
for i,j in pairs(a.gated)do if
type(i)==aq and#i<=64 and
i:match("^[%w_]+$")and type(j)==aq and#j<=64 and j:match("^[%w_%.]+$")then
az[i]=j end end end end
function ar.reloadComponentConfig()ay={}az={}aE=false;aR()return ay,az end
local function av(a,b)if not a then return false end;aR()if aQ[a]or ay[a]then return true end;local c=
bq[a]or az[a]if c and b and b[c]then return true end;return false end;local bD=aQ;local aF={gpu=true,screen=true,keyboard=true}
local function aG()
local d,b=pcall(require,"kernel.screen")if not d or type(b)~="table"or not b.callerDevices then return
nil end
local e,a=pcall(b.callerDevices)if not e or type(a)~="table"then return nil end;if not a.gpu then
return nil end;local c={[a.gpu]=true}
if a.screen then c[a.screen]=true end;for g,f in ipairs(a.keyboards or{})do c[f]=true end;return c,a end
local function br(a)local c,b=aG()if not c then return nil end;if a=="gpu"then return b.gpu end;if
a=="screen"then return b.screen end;if a=="keyboard"then return
(b.keyboards or{})[1]end;return nil end
local function bs(a)a=a or{}local b=require(aH)local c={}
local function d(e,f)if not aF[f]then return false end
local g=aG()if not g then return false end;return not g[e]end
function c.list(e,f)local h=b.list(e,f)local g=aG()
return
function()while true do local i,j=h()if i==nil then return nil end;local k=
g and aF[j]and not g[i]
if av(j,a)and not k then return i,j end end end end
function c.proxy(e)local f=b.type(e)if not av(f,a)then return nil,aU end;if d(e,f)then
return nil,"not your seat"end;return b.proxy(e)end;function c.type(e)return b.type(e)end
function c.slot(e)return b.slot(e)end;function c.get(e,f)local g=b.get(e,f)
if g then local h=b.type(g)if av(h,a)then return g end end;return nil,aU end
function c.invoke(e,f,...)
local g=b.type(e)if not av(g,a)then
at(bg(),"component "..tostring(g))
error("sandbox: access denied to "..tostring(g))end;if d(e,g)then
error("sandbox: "..tostring(g)..
" belongs to another seat")end;return b.invoke(e,f,...)end
function c.isAvailable(e)if not av(e,a)then return false end;return b.isAvailable(e)end
function c.getPrimary(e)if not av(e,a)then return nil,aU end;if aF[e]then local f=br(e)if f then
return b.proxy(f)end end;return b.getPrimary(e)end;return c end
local function bt(a)
local function b(c)local f,d=pcall(a.getPrimary,c)if f and d then return d end
local g,e=pcall(a.list,c,true)
if g and type(e)==ap then local h=e()if h then return(a.proxy(h))end end;return nil end
return
setmetatable({},{__index=function(d,c)local e=a[c]if e~=nil then return e end
if type(c)==aq then return b(c)end;return nil end,__pairs=function()local c;return function()local d
c,d=next(a,c)return c,d end end,__newindex=function()
error("component view is read-only",2)end,__metatable=false})end;local bu={"/usr/lib","/usr/modules"}
local function bv(a)local b=a:gsub("%.","/")return{b..".lua",
b.."/init.lua"}end
local function aS(a)local b=nil;local c,d=pcall(require,aI)if c then b=d end;if not b then return nil end;for f,e in
ipairs(bu)do
for f,g in ipairs(bv(a))do local h=e.."/"..g;if b.exists(h)then return h end end end;return nil end
local function aw(a,b)if type(a)~="table"then return a end;local c=a
if b then c=function(e,d)if b[d]then return nil end
return a[d]end end
return
setmetatable({},{__index=c,__len=function()return#a end,__pairs=function()local d
return function()local e;repeat d,e=next(a,d)until
d==nil or not(b and b[d])return d,e end end,__call=function(d,...)return a(...)end,__metatable=false})end
local bw={[aX]={_gpuForCaps=true},[aW]={_forProgram=true}}
local bx={"send","broadcast","on","off","onceFrom","offAll","waitFor","sendMessage","requestTrust","discover","getAddress","getHostname","isAvailable","modemCount"}
local function aT(a)if type(a)~="table"then return a end;return
{addr=a.addr,lastSeen=a.lastSeen,hostname=a.hostname,device=a.device,trust=a.trust}end
local by={"PING","PONG","HELLO","HELLO_ACK","INFO_REQ","INFO_RES","MSG","MSG_ACK","DENY","ERROR"}
local function aA(a,b)if type(a)~="table"then return a end;if b>16 then return nil end;local c={}
for d,e in next,a do if
type(d)~="table"then c[d]=aA(e,b+1)end end;return c end
local function bz(a)local b={}
for m,l in ipairs(bx)do if type(a[l])==ap then b[l]=a[l]end end
local j,f=pcall(function()return a.getProtocol and a.getProtocol()end)
local k=
j and type(f)=="table"and type(f.TYPE)=="table"and f.TYPE or{}local d={}
for m,l in ipairs(by)do d[k[l]or l:lower()]=true end
local function e(l,m)return nil,
"net: programs may not "..m.." '"..tostring(l).."' packets"end;b.on,b.onceFrom,b.off,b.offAll,b.send,b.broadcast=nil,nil,nil,nil,nil,nil
local c={}
local function g(l,m)if m~=nil then c[l]=c[l]or{}c[l][m]=true end;return m end
local function h(l)return function(m,n)return l(aA(m,0),n)end end
if type(a.on)==ap then
b.on=function(l,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=ap then return nil,"net.on: callback must be a function"end;return g(l,a.on(l,h(m)))end end
if type(a.onceFrom)==ap then
b.onceFrom=function(l,n,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=ap then return nil,"net.onceFrom: callback must be a function"end;return g(l,a.onceFrom(l,n,h(m)))end end
if type(a.off)==ap then
b.off=function(l,m)
if not(c[l]and c[l][m])then return false end;c[l][m]=nil;return a.off(l,m)end
b.offAll=function(l)if type(l)~="table"then return end;for n,m in ipairs(l)do if type(m)=="table"then
b.off(m.type,m.id)end end end end
if type(a.send)==ap then
b.send=function(m,l,n)local o=aA(l,0)
if
type(o)~="table"or not d[o.type]then return
e(type(o)=="table"and o.type or type(l),"send")end;return a.send(m,o,n)end end
if type(a.broadcast)==ap then
b.broadcast=function(l,m)local n=aA(l,0)
if type(n)~="table"or
not d[n.type]then return
e(type(n)=="table"and n.type or type(l),"broadcast")end;return a.broadcast(n,m)end end
local function i(l)local m={}for n,o in ipairs(type(l)=="table"and l or{})do
m[n]=aT(o)end;return m end;if type(a.peers)==ap then
b.peers=function()return i(a.peers())end end;if type(a.scan)==ap then b.scan=function(l)
return i(a.scan(l))end end;if
type(a.findPeer)==ap then
b.findPeer=function(l)return aT(a.findPeer(l))end end
if type(a.getProtocol)==ap then b.getProtocol=function()return
aw(a.getProtocol())end end
if type(a.status)==ap then
b.status=function()local l,m=a.status(),{}
for o,n in pairs(
type(l)=="table"and l or{})do if type(n)~="table"then m[o]=n end end;return m end end;return b end;local bA={[as]=as,[aV]=as,["compat.shell_api"]=as}
local bB={sides="compat.sides",colors="compat.colors",keyboard="compat.keyboard",text="compat.text",serialization="compat.serialization",buffer="compat.buffer",term=aX,event="compat.event",shell="compat.shell_api",filesystem=aV,io=as,internet="compat.internet",robot="compat.robot",process=aW,note="compat.note"}
local function bC(a,c,b)local d={}local e={}if c then for g,h in pairs(c)do d[g]=h end end;local f
f=function(g)if type(g)~=
aq then
error("bad argument #1 to 'require' (string expected)",2)end;if d[g]~=nil then return d[g]end;if
bh(g)then at(a.pkgName or a.name,"module "..g)
error(
"sandbox: cannot require kernel module '"..g.."'",2)end
if g=="unicode"then local i=
b and b.env and b.env.unicode;if i==nil then
error("sandbox: module 'unicode' is not available",2)end;d[g]=i;return i end;local h=bB[g]
if h then local k=_G._TOS;if k and k.compatDisabled then
error("sandbox: '"..g..
"' is OpenOS's, and the compat layer is off in this boot profile",2)end
local i=b and b.env;if
(g=="io"or g=="filesystem")and i and i[g]~=nil then d[g]=i[g]return i[g]end
local l,j=pcall(f,h)if not l then
error("sandbox: require('"..g..
"'): "..tostring(j):gsub("^sandbox: ",""),2)end;d[g]=j;return j end
if g=="compat.component"then local i=c and c.component;if not i then
at(a.pkgName or a.name,"capability component")
error("sandbox: 'compat.component' needs the component capability",2)end;d[g]=i
return i end
if
g=="compat.internet"and not(a.caps and a.caps[a_])then at(a.pkgName or a.name,"capability internet")
error("sandbox: 'compat.internet' needs the internet capability",2)end
do local i=bA[g]
if i and not
(a.caps and(a.caps[i]or a.caps[ba]))then
at(a.pkgName or a.name,"capability "..i)
error("sandbox: '"..g.."' needs the "..i.." capability",2)end end
if g=="compat"then local k,i=pcall(require,"compat")
if
not k or type(i)~="table"then error("sandbox: the compat layer is unavailable",2)end;local j={has=i.has,list=i.list}d[g]=j;return j end
if be[g]then
if
not(a and a.allowUserLibs and aS(g))then
at(a and(a.pkgName or a.name),"module "..g)
error("sandbox: module '"..g.."' is not available to sandboxed code",2)end end
if bd[g]or bi(g)then local i=require(g)local j=aw(i,bw[g])
if
g==aX and type(i)=="table"and type(i._gpuForCaps)==ap then
local k=a and a.caps;j.gpu=function()return i._gpuForCaps(k)end
local l=i.read
j.read=function(...)if a and a.flushForRead then a.flushForRead()end
return l(...)end end
if
g==aW and type(i)=="table"and type(i._forProgram)==ap then local k=i._forProgram(a and a.name,b and b.env)if type(k)==
"table"then j.info=k.info;j.running=k.running end end;d[g]=j;return j end
if bj(g)then local i=aS(g)
if i then local k=_G._TOS and _G._TOS.users
if a.session and k and
k.canAccessAs then local s=k.canAccessAs(a.session,i,"r")if not s then
error(
"sandbox: access denied loading user lib '"..g.."'",2)end end;if a.allowUserLibs then local s=require(g)d[g]=s;return s end
local m=b and b.env;if type(m)~="table"then
error("sandbox: no environment to load user lib '"..g.."' into",2)end;if e[g]then
error("sandbox: circular require of '"..g.."'",2)end;local p,l=pcall(require,aI)
local n=p and
type(l)=="table"and l.readFile and l.readFile(i)if type(n)~=aq then
error("sandbox: cannot read user lib '"..g.."'",2)end;local o,q=load(n,"="..i,"t",m)if not o then
error(
"sandbox: cannot load user lib '"..g.."': "..tostring(q),2)end;e[g]=true;local r,j=pcall(o,g)
e[g]=nil;if not r then
error("sandbox: user lib '"..g.."' failed: "..tostring(j),2)end;if j==nil then j=true end;d[g]=j;return j end end
error("sandbox: module '"..g.."' is not on the allowed list",2)end;return f end
function ar.build(a)a=a or{}local c=a.caps or{}local l=a.session
local e=_G._TOS and _G._TOS.securefs
if not e then local t,u=pcall(require,"kernel.securefs")if t then e=u end end;local d=nil;if e and(c["fs.read"]or c[aZ])then
d=e.forSession(l)end
local function n(t)
local v={"exists","isDirectory","list","readFile","size","lastModified","normalize","split","join","spaceTotal","spaceUsed","spaceFree","mounts","home","resolve"}local u={}
for x,w in ipairs(v)do local y=t[w]if type(y)==ap then
u[w]=function(...)return y(...)end end end
if type(t.open)==ap then
u.open=function(x,w,...)w=w or"r"
if
type(w)~=aq or w:find("[wa+]")then return nil,"fs.write capability required"end;return t.open(x,w,...)end end;return u end;local i=nil
local function o(...)local u={}
for v=1,select("#",...)do u[v]=tostring(select(v,...))end;local t=table.concat(u,"\t")if i then i(t)elseif a.stdout then a.stdout(t)elseif
type(print)==ap then print(t)end end;local j=getmetatable("")local p=string;local function f(t)if t==nil then return false end;return
t==j or t==p end
local function q(t)
if type(t)==aq then return nil end;local u=getmetatable(t)if j~=nil and u==j then return nil end;return u end
local function r(v,u)if type(v)~="table"then
error("bad argument #1 to 'setmetatable' (table expected)",2)end
if u~=nil then if type(u)~="table"then
error("bad argument #2 to 'setmetatable' (nil or table expected)",2)end
if

f(u)or
f(rawget(u,"__index"))or f(rawget(u,"__newindex"))or f(rawget(u,"__metatable"))then
error("setmetatable: metatable referencing protected library denied",2)end end;return setmetatable(v,u)end;local s=au(string)local g,h;if c[aH]then g=bt(bs(c))h=bp()end;local k={}if g then
k.component=g end;if h then k.computer=h end;local m={}
local b={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,unpack=table.unpack,rawequal=rawequal,rawlen=rawlen,setmetatable=r,getmetatable=q,math=au(math),string=s,table=au(table),utf8=
utf8 and au(utf8)or nil,coroutine=au(coroutine),unicode=aC and au(aC)or nil,checkArg=bk,print=o,require=bC(a,k,m)}m.env=b;b._G=b;b._ENV=b;b._VERSION=_VERSION;if d then
if c[aZ]then b.fs=d else b.fs=n(d)end end
if c[as]then local t,u=pcall(require,as)
if t then b.io=aw(u)end;b.os=bm()local v,w=pcall(require,aV)if v then b.filesystem=aw(w)end end
if c[ba]then b.os=os;b.io=io;local u,t=pcall(require,"kernel.log")if
u and t and t.warn then
t.warn("sandbox","Built env with legacy cap — full os/io exposed")end end
if c[as]and not c[ba]and type(a.stdout)==ap and type(b.io)==
"table"then
local u,t=pcall(require,"compat.buffer")
if u and type(t)=="table"and type(t.new)==ap then
local y,v=a.stdout,""
local function A(G)v=v..G;local H=1;while true do local I=v:find("\n",H,true)if not I then break end
y(v:sub(H,I-1))H=I+1 end;v=v:sub(H)end
local function B()return
t.new("w",{write=function(H,G)A(G)end,close=function()end})end;local x=b.io;local z,C=B(),B()local w={input=x.stdin,output=z}local function D(G)return
G==z or G==C or G==x.stdin end
local function E(H,G,I)if type(G)==aq then
local K,L=x.open(G,I)if not K then error(L,3)end;G=K end
local J=w[H]
if J~=G and not D(J)and type(J)=="table"and
type(J.close)==ap then pcall(J.close,J)end;w[H]=G end
b.io=setmetatable({stdout=z,stderr=C,output=function(G)if G then E("output",G,"w")end;return w.output end,input=function(G)if
G then E("input",G,"r")end;return w.input end,write=function(...)return
w.output:write(...)end,read=function(...)return w.input:read(...)end,lines=function(G,...)if
G==nil then return w.input:lines()end
return x.lines(G,...)end,close=function(G)G=G or w.output
if D(G)then return true end;return G:close()end},{__index=x,__metatable=false})i=function(G)A(G.."\n")end
a.flushForRead=function()local G=v;v=""if a.beforeRead then
a.beforeRead(G)elseif G~=""then y(G)end end;local F=b.io.read
b.io.read=function(...)a.flushForRead()return F(...)end
aD[b]=function()if v~=""then local G=v;v=""y(G)end end end end;if c[aH]then b.component=g;b.computer=h end
if c["load"]then b.load=function(t,u,v,w)
return load(t,u,"t",b)end;b.loadstring=b.load end
if c["notify"]then local u,t=pcall(require,"kernel.notify")
if
u and t and t.post then local v={}
b.notify={post=function(w)
if type(w)~="table"then return nil,"spec must be a table"end;local x={}for B,C in pairs(w)do x[B]=C end;local y=a.pkgName
x.from=(type(y)==aq and
y:match("^[%w][%w%-]*$"))and y or"package"local z,A=t.post(x)if z~=nil then v[z]=true end;return z,A end,result=function(w)if
not v[w]then return nil end;return t.result(w)end}end end
if c["net"]then local u,t=pcall(require,"kernel.net")if u then b.net=
a.allowUserLibs and aw(t)or bz(t)end end
do local t=nil
for w in pairs(c)do
local x=type(w)==aq and w:match("^ipc:(.+)$")if x then t=t or{}t[x]=true end end;local v,u=false,nil
if t then v,u=pcall(require,"kernel.ipc")end
if v and u then
b.ipc={call=function(w,...)if not t[w]then
return nil,"this program may not reach '"..tostring(w).."'"end;return u.call(w,l,...)end}end end
if c[a_]then local u,t=pcall(require,"kernel.internet")
if u and t then
b.internet={get=function(v,w)
return t.get(v,w)end,download=function(w,x,v)if not(c[aZ]and d)then
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
if type(v)==aq and v:match("^[%w][%w%-]*$")then
b.crypto.secret=function()local w=
nil;local C,y=pcall(require,aJ)if C and y and y.currentSession then
w=y.currentSession()end
if not w then
local H=_G._TOS and _G._TOS.users
if not H then local I,J=pcall(require,"kernel.users")if I then H=J end end;if H and H.currentSession then w=H.currentSession()end end
local D=w and(w.isKernel or w.isLogin or
(type(w.tier)==aK and w.tier>=2))
if not D then return nil,"crypto.secret requires an admin session"end;local E,x=pcall(require,aI)
if not E or not x then return nil,"fs unavailable"end;local z="/var/pkg/secrets"local A=z.."/"..v
if x.exists(A)then local H=x.readFile(A)if H and
#H>=16 then return H end;return nil,"secret unreadable"end;if not x.exists(z)then x.makeDirectory(z)end
local B=t.salt(32)local F,G=x.writeFile(A,B)if not F then
return nil,"cannot store secret: "..tostring(G)end;return B end end end end;return b end
function ar.run(a,b,c,...)local e=ar.build(c)local d,f=load(a,b,"t",e)if not d then return false,
"compile error: "..tostring(f)end;return pcall(d,...)end
function ar.finish(a)local b=aD[a]if b then aD[a]=nil;pcall(b)end end
function ar.exitStatus(a)
if type(a)=="table"and rawget(a,aN)==true then
local b=rawget(a,"code")if b==nil then return true end;return b end;return nil end
function ar.describeEnd(b,a)
if b then local d=type(a)if d==aq or d==aK or d=="boolean"then return tostring(a),
false end;return nil end;local c=ar.exitStatus(a)
if c==nil then return tostring(a),true end;if c==true or c==0 then return nil end;return
"exited with status "..tostring(c),false end;return ar