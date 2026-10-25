
local aL,aM,an,aN,aO,aA,aP,aQ,ak,aR,aB,aS,aT,aC,aU,al="access denied","compat.filesystem","compat.io","compat.process","compat.term","component","computer","fs.write","function","internet","kernel.fs","kernel.process","legacy","number","peripheral.inventory","string"local am={}local aD="kernel."local aV={"compat.","peripheral."}
local aW={compat=true,["shell.keys"]=true}
local aX={["debug"]=true,["package"]=true,["os"]=true,["io"]=true,[aA]=true,[aP]=true,["filesystem"]=true,["shell.init"]=true,["shell.ext"]=true,["shell.panels.init"]=true,["shell.panels.commands"]=true,["shell.panels.events"]=true,["shell.panels.executor"]=true,["shell.panels.state"]=true,["shell.panels.draw"]=true,["shell.panels.helpers"]=true,["shell.panels.filebrowser"]=true,["shell.panels.editor"]=true,["shell.panels.menus"]=true,["shell.panels.dialogs"]=true,["shell.panels.context"]=true,["shell.panels.keymap"]=true,["shell.panels.tabs"]=true,["shell.panels.widgets"]=true,["shell.panels.mouse"]=true,["shell.panels.ui"]=true,["shell.panels.desktop"]=true,["shell.panels.settingsapp"]=true,["shell.panels.apps"]=true,["shell.panels.monitorapp"]=true,["shell.panels.chatapp"]=true,["mail"]=true,["mailui"]=true,["mailapp"]=true,["rbmk-cmd"]=true,["rbmk-controld"]=true,["rbmk.core"]=true,["rbmk-skala"]=true,["rbmk.skala"]=true,["rbmk.wall"]=true,["shell.panels.takeover"]=true,["shell.login"]=true,["shell.chat"]=true,["shell.tutorial"]=true,["shell.syntax"]=true,["shell.panels"]=true,["shell"]=true,["bios"]=true,["init"]=true,["install"]=true,["system_manifest"]=true}
local function aY(a)return type(a)==al and a:sub(1,#aD)==aD end;local function aZ(a)
for c,b in ipairs(aV)do if a:sub(1,#b)==b then return true end end;return false end;local function a_(a)if
a:find("[^%w_.-]")then return false end
if a:sub(1,1)=="."then return false end;return true end;local function ao(a)local b={}for c,d in
pairs(a)do b[c]=d end;return b end;local av=nil
do
local b,a=pcall(require,"unicode")if b and type(a)=="table"then av=a end end
local function ba(b,a,...)a=type(a)
for c=1,select("#",...)do if a==select(c,...)then return end end
error(string.format("bad argument #%d (%s expected, got %s)",b,table.concat({...}," or "),a),3)end;local aE={}local aw=setmetatable({},{__mode="k"})
local bb={__tostring=function(a)return"exit "..
tostring(rawget(a,"code"))end,__metatable=false}
local function bc()
return
{time=os.time,date=os.date,clock=os.clock,difftime=os.difftime,sleep=function(a)local c,b=pcall(require,aS)if
c and type(b)=="table"and type(b.sleep)==ak then return
b.sleep(tonumber(a)or 0)end
error("os.sleep: the process scheduler is unavailable",2)end,exit=function(a)
error(setmetatable({[aE]=true,code=a},bb),0)end}end;local ar=nil
local function bd(a)if ar==nil then local c,b=pcall(require,"kernel.event")
ar=(c and
type(b)=="table"and type(b.reservedSignal)==ak and
b.reservedSignal)or
false end;if
not ar then return true end;return ar(a)end
local aF={modem_message=true,tos_shutdown=true,tos_logout=true,tos_login_complete=true,tos_seat_changed=true,tos_shell_exited=true}
local function be()local a=package.loaded[aS]if
a and type(a.inProcess)==ak then return a.inProcess()end;return
(coroutine.isyieldable and
coroutine.isyieldable())and true or false end
local function aG(a)local b=require(aP)local c;if
type(a)==aC and a>=0 and a~=math.huge then c=b.uptime()+a end
if be()then
while true do
local f=table.pack(coroutine.yield())local g=f[1]
if g~=nil and not aF[g]then return table.unpack(f,1,f.n)end;if c and b.uptime()>=c then return nil end end end;local d=3
local e=b.uptime()+ (
(type(a)==aC and a>=0 and a<d)and a or d)
while true do local g=e-b.uptime()if g<0 then return nil end
local f=table.pack(b.pullSignal(g))local h=f[1]if h==nil then return nil end;if not aF[h]then
return table.unpack(f,1,f.n)end end end
local function bf()local a=require(aP)
return
{uptime=a.uptime,freeMemory=a.freeMemory,totalMemory=a.totalMemory,address=a.address,pullSignal=aG,pushSignal=function(b,...)if bd(b)then return end;return
a.pushSignal(b,...)end,energy=a.energy,maxEnergy=a.maxEnergy}end;am._safePullSignal=aG
local aH={gpu=true,screen=true,keyboard=true,crafting=true,navigation=true,geolyzer=true,note_block=true,sign=true}
local bg={modem="peripheral.modem",tunnel="peripheral.modem",redstone="peripheral.redstone",robot="peripheral.robot",inventory_controller=aU,transposer=aU,tank_controller=aU,tape_drive="peripheral.tape",internet=aR,tractor_beam="peripheral.tractor",piston="peripheral.piston",hologram="peripheral.hologram",openprinter="peripheral.printer"}local as={}local at={}local ax=false
local function aI()if ax then return end;ax=true;local e,c=pcall(require,aB)
local f,g=pcall(require,"kernel.serialize")if not(e and f)then return end;local d="/etc/component_caps.cfg"if
not c.exists(d)then return end;local b=c.readFile(d)if not b or#b==0 or#b>8192 then
return end
local h,a=pcall(g.decode,b,{maxBytes=8192})if not h or type(a)~="table"then return end;if
type(a.base)=="table"then
for j,i in ipairs(a.base)do if
type(i)==al and#i<=64 and i:match("^[%w_]+$")then as[i]=true end end end
if
type(a.gated)=="table"then
for i,j in pairs(a.gated)do if
type(i)==al and#i<=64 and
i:match("^[%w_]+$")and type(j)==al and#j<=64 and j:match("^[%w_%.]+$")then
at[i]=j end end end end
function am.reloadComponentConfig()as={}at={}ax=false;aI()return as,at end
local function ap(a,b)if not a then return false end;aI()if aH[a]or as[a]then return true end;local c=
bg[a]or at[a]if c and b and b[c]then return true end;return false end;local bt=aH;local ay={gpu=true,screen=true,keyboard=true}
local function az()
local d,b=pcall(require,"kernel.screen")if not d or type(b)~="table"or not b.callerDevices then return
nil end
local e,a=pcall(b.callerDevices)if not e or type(a)~="table"then return nil end;if not a.gpu then
return nil end;local c={[a.gpu]=true}
if a.screen then c[a.screen]=true end;for g,f in ipairs(a.keyboards or{})do c[f]=true end;return c,a end
local function bh(a)local c,b=az()if not c then return nil end;if a=="gpu"then return b.gpu end;if
a=="screen"then return b.screen end;if a=="keyboard"then return
(b.keyboards or{})[1]end;return nil end
local function bi(a)a=a or{}local b=require(aA)local c={}
local function d(e,f)if not ay[f]then return false end
local g=az()if not g then return false end;return not g[e]end
function c.list(e,f)local h=b.list(e,f)local g=az()
return
function()while true do local i,j=h()if i==nil then return nil end;local k=
g and ay[j]and not g[i]
if ap(j,a)and not k then return i,j end end end end
function c.proxy(e)local f=b.type(e)if not ap(f,a)then return nil,aL end;if d(e,f)then
return nil,"not your seat"end;return b.proxy(e)end;function c.type(e)return b.type(e)end
function c.slot(e)return b.slot(e)end;function c.get(e,f)local g=b.get(e,f)
if g then local h=b.type(g)if ap(h,a)then return g end end;return nil,aL end
function c.invoke(e,f,...)
local g=b.type(e)if not ap(g,a)then
error("sandbox: access denied to "..tostring(g))end;if d(e,g)then
error("sandbox: "..
tostring(g).." belongs to another seat")end;return b.invoke(e,f,...)end
function c.isAvailable(e)if not ap(e,a)then return false end;return b.isAvailable(e)end
function c.getPrimary(e)if not ap(e,a)then return nil,aL end;if ay[e]then local f=bh(e)if f then
return b.proxy(f)end end;return b.getPrimary(e)end;return c end
local function bj(a)
local function b(c)local f,d=pcall(a.getPrimary,c)if f and d then return d end
local g,e=pcall(a.list,c,true)
if g and type(e)==ak then local h=e()if h then return(a.proxy(h))end end;return nil end
return
setmetatable({},{__index=function(d,c)local e=a[c]if e~=nil then return e end
if type(c)==al then return b(c)end;return nil end,__pairs=function()local c;return function()local d
c,d=next(a,c)return c,d end end,__newindex=function()
error("component view is read-only",2)end,__metatable=false})end;local bk={"/usr/lib","/usr/modules"}
local function bl(a)local b=a:gsub("%.","/")return{b..".lua",
b.."/init.lua"}end
local function aJ(a)local b=nil;local c,d=pcall(require,aB)if c then b=d end;if not b then return nil end;for f,e in
ipairs(bk)do
for f,g in ipairs(bl(a))do local h=e.."/"..g;if b.exists(h)then return h end end end;return nil end
local function aq(a,b)if type(a)~="table"then return a end;local c=a
if b then c=function(e,d)if b[d]then return nil end
return a[d]end end
return
setmetatable({},{__index=c,__len=function()return#a end,__pairs=function()local d
return function()local e;repeat d,e=next(a,d)until
d==nil or not(b and b[d])return d,e end end,__call=function(d,...)return a(...)end,__metatable=false})end
local bm={[aO]={_gpuForCaps=true},[aN]={_forProgram=true}}
local bn={"send","broadcast","on","off","onceFrom","offAll","waitFor","sendMessage","requestTrust","discover","getAddress","getHostname","isAvailable","modemCount"}
local function aK(a)if type(a)~="table"then return a end;return
{addr=a.addr,lastSeen=a.lastSeen,hostname=a.hostname,device=a.device,trust=a.trust}end
local bo={"PING","PONG","HELLO","HELLO_ACK","INFO_REQ","INFO_RES","MSG","MSG_ACK","DENY","ERROR"}
local function au(a,b)if type(a)~="table"then return a end;if b>16 then return nil end;local c={}
for d,e in next,a do if
type(d)~="table"then c[d]=au(e,b+1)end end;return c end
local function bp(a)local b={}
for m,l in ipairs(bn)do if type(a[l])==ak then b[l]=a[l]end end
local j,f=pcall(function()return a.getProtocol and a.getProtocol()end)
local k=
j and type(f)=="table"and type(f.TYPE)=="table"and f.TYPE or{}local d={}
for m,l in ipairs(bo)do d[k[l]or l:lower()]=true end
local function e(l,m)return nil,
"net: programs may not "..m.." '"..tostring(l).."' packets"end;b.on,b.onceFrom,b.off,b.offAll,b.send,b.broadcast=nil,nil,nil,nil,nil,nil
local c={}
local function g(l,m)if m~=nil then c[l]=c[l]or{}c[l][m]=true end;return m end
local function h(l)return function(m,n)return l(au(m,0),n)end end
if type(a.on)==ak then
b.on=function(l,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=ak then return nil,"net.on: callback must be a function"end;return g(l,a.on(l,h(m)))end end
if type(a.onceFrom)==ak then
b.onceFrom=function(l,n,m)
if not d[l]then return e(l,"listen for")end
if type(m)~=ak then return nil,"net.onceFrom: callback must be a function"end;return g(l,a.onceFrom(l,n,h(m)))end end
if type(a.off)==ak then
b.off=function(l,m)
if not(c[l]and c[l][m])then return false end;c[l][m]=nil;return a.off(l,m)end
b.offAll=function(l)if type(l)~="table"then return end;for n,m in ipairs(l)do if type(m)=="table"then
b.off(m.type,m.id)end end end end
if type(a.send)==ak then
b.send=function(m,l,n)local o=au(l,0)
if
type(o)~="table"or not d[o.type]then return
e(type(o)=="table"and o.type or type(l),"send")end;return a.send(m,o,n)end end
if type(a.broadcast)==ak then
b.broadcast=function(l,m)local n=au(l,0)
if type(n)~="table"or
not d[n.type]then return
e(type(n)=="table"and n.type or type(l),"broadcast")end;return a.broadcast(n,m)end end
local function i(l)local m={}for n,o in ipairs(type(l)=="table"and l or{})do
m[n]=aK(o)end;return m end;if type(a.peers)==ak then
b.peers=function()return i(a.peers())end end;if type(a.scan)==ak then b.scan=function(l)
return i(a.scan(l))end end;if
type(a.findPeer)==ak then
b.findPeer=function(l)return aK(a.findPeer(l))end end
if type(a.getProtocol)==ak then b.getProtocol=function()return
aq(a.getProtocol())end end
if type(a.status)==ak then
b.status=function()local l,m=a.status(),{}
for o,n in pairs(
type(l)=="table"and l or{})do if type(n)~="table"then m[o]=n end end;return m end end;return b end;local bq={[an]=an,[aM]=an,["compat.shell_api"]=an}
local br={sides="compat.sides",colors="compat.colors",keyboard="compat.keyboard",text="compat.text",serialization="compat.serialization",buffer="compat.buffer",term=aO,event="compat.event",shell="compat.shell_api",filesystem=aM,io=an,internet="compat.internet",robot="compat.robot",process=aN,note="compat.note"}
local function bs(a,c,b)local d={}local e={}if c then for g,h in pairs(c)do d[g]=h end end;local f
f=function(g)if type(g)~=
al then
error("bad argument #1 to 'require' (string expected)",2)end;if d[g]~=nil then return d[g]end;if
aY(g)then
error("sandbox: cannot require kernel module '"..g.."'",2)end
if g=="unicode"then
local i=b and b.env and b.env.unicode;if i==nil then
error("sandbox: module 'unicode' is not available",2)end;d[g]=i;return i end;local h=br[g]
if h then local k=_G._TOS;if k and k.compatDisabled then
error("sandbox: '"..g..
"' is OpenOS's, and the compat layer is off in this boot profile",2)end
local i=b and b.env;if
(g=="io"or g=="filesystem")and i and i[g]~=nil then d[g]=i[g]return i[g]end
local l,j=pcall(f,h)if not l then
error("sandbox: require('"..g..
"'): "..tostring(j):gsub("^sandbox: ",""),2)end;d[g]=j;return j end
if g=="compat.component"then local i=c and c.component;if not i then
error("sandbox: 'compat.component' needs the component capability",2)end;d[g]=i;return i end;if
g=="compat.internet"and not(a.caps and a.caps[aR])then
error("sandbox: 'compat.internet' needs the internet capability",2)end
do local i=bq[g]if i and not
(
a.caps and(a.caps[i]or a.caps[aT]))then
error("sandbox: '"..g..
"' needs the "..i.." capability",2)end end
if g=="compat"then local k,i=pcall(require,"compat")
if
not k or type(i)~="table"then error("sandbox: the compat layer is unavailable",2)end;local j={has=i.has,list=i.list}d[g]=j;return j end
if aX[g]then if
not(a and a.allowUserLibs and aJ(g))then
error("sandbox: module '"..g.."' is not available to sandboxed code",2)end end
if aW[g]or aZ(g)then local i=require(g)local j=aq(i,bm[g])
if
g==aO and type(i)=="table"and type(i._gpuForCaps)==ak then
local k=a and a.caps;j.gpu=function()return i._gpuForCaps(k)end end
if
g==aN and type(i)=="table"and type(i._forProgram)==ak then local k=i._forProgram(a and a.name,b and b.env)if type(k)==
"table"then j.info=k.info;j.running=k.running end end;d[g]=j;return j end
if a_(g)then local i=aJ(g)
if i then local k=_G._TOS and _G._TOS.users
if a.session and k and
k.canAccessAs then local s=k.canAccessAs(a.session,i,"r")if not s then
error(
"sandbox: access denied loading user lib '"..g.."'",2)end end;if a.allowUserLibs then local s=require(g)d[g]=s;return s end
local m=b and b.env;if type(m)~="table"then
error("sandbox: no environment to load user lib '"..g.."' into",2)end;if e[g]then
error("sandbox: circular require of '"..g.."'",2)end;local p,l=pcall(require,aB)
local n=p and
type(l)=="table"and l.readFile and l.readFile(i)if type(n)~=al then
error("sandbox: cannot read user lib '"..g.."'",2)end;local o,q=load(n,"="..i,"t",m)if not o then
error(
"sandbox: cannot load user lib '"..g.."': "..tostring(q),2)end;e[g]=true;local r,j=pcall(o,g)
e[g]=nil;if not r then
error("sandbox: user lib '"..g.."' failed: "..tostring(j),2)end;if j==nil then j=true end;d[g]=j;return j end end
error("sandbox: module '"..g.."' is not on the allowed list",2)end;return f end
function am.build(a)a=a or{}local c=a.caps or{}local m=a.session
local e=_G._TOS and _G._TOS.securefs
if not e then local t,u=pcall(require,"kernel.securefs")if t then e=u end end;local d=nil;if e and(c["fs.read"]or c[aQ])then
d=e.forSession(m)end
local function n(t)
local v={"exists","isDirectory","list","readFile","size","lastModified","normalize","split","join","spaceTotal","spaceUsed","spaceFree","mounts","home","resolve"}local u={}
for x,w in ipairs(v)do local y=t[w]if type(y)==ak then
u[w]=function(...)return y(...)end end end
if type(t.open)==ak then
u.open=function(x,w,...)w=w or"r"
if
type(w)~=al or w:find("[wa+]")then return nil,"fs.write capability required"end;return t.open(x,w,...)end end;return u end;local i=nil
local function o(...)local u={}
for v=1,select("#",...)do u[v]=tostring(select(v,...))end;local t=table.concat(u,"\t")if i then i(t)elseif a.stdout then a.stdout(t)elseif
type(print)==ak then print(t)end end;local j=getmetatable("")local p=string;local function f(t)if t==nil then return false end;return
t==j or t==p end
local function q(t)
if type(t)==al then return nil end;local u=getmetatable(t)if j~=nil and u==j then return nil end;return u end
local function r(v,u)if type(v)~="table"then
error("bad argument #1 to 'setmetatable' (table expected)",2)end
if u~=nil then if type(u)~="table"then
error("bad argument #2 to 'setmetatable' (nil or table expected)",2)end
if

f(u)or
f(rawget(u,"__index"))or f(rawget(u,"__newindex"))or f(rawget(u,"__metatable"))then
error("setmetatable: metatable referencing protected library denied",2)end end;return setmetatable(v,u)end;local s=ao(string)local g,h;if c[aA]then g=bj(bi(c))h=bf()end;local k={}if g then
k.component=g end;if h then k.computer=h end;local l={}
local b={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,unpack=table.unpack,rawequal=rawequal,rawlen=rawlen,setmetatable=r,getmetatable=q,math=ao(math),string=s,table=ao(table),utf8=
utf8 and ao(utf8)or nil,coroutine=ao(coroutine),unicode=av and ao(av)or nil,checkArg=ba,print=o,require=bs(a,k,l)}l.env=b;b._G=b;b._ENV=b;b._VERSION=_VERSION;if d then
if c[aQ]then b.fs=d else b.fs=n(d)end end
if c[an]then local t,u=pcall(require,an)
if t then b.io=aq(u)end;b.os=bc()local v,w=pcall(require,aM)if v then b.filesystem=aq(w)end end
if c[aT]then b.os=os;b.io=io;local u,t=pcall(require,"kernel.log")if
u and t and t.warn then
t.warn("sandbox","Built env with legacy cap — full os/io exposed")end end
if c[an]and not c[aT]and type(a.stdout)==ak and type(b.io)==
"table"then
local u,t=pcall(require,"compat.buffer")
if u and type(t)=="table"and type(t.new)==ak then
local z,v=a.stdout,""
local function A(F)v=v..F;local G=1;while true do local H=v:find("\n",G,true)if not H then break end
z(v:sub(G,H-1))G=H+1 end;v=v:sub(G)end
local function B()return
t.new("w",{write=function(G,F)A(F)end,close=function()end})end;local x=b.io;local y,C=B(),B()local w={input=x.stdin,output=y}local function D(F)return
F==y or F==C or F==x.stdin end
local function E(G,F,H)if type(F)==al then
local J,K=x.open(F,H)if not J then error(K,3)end;F=J end
local I=w[G]
if I~=F and not D(I)and type(I)=="table"and
type(I.close)==ak then pcall(I.close,I)end;w[G]=F end
b.io=setmetatable({stdout=y,stderr=C,output=function(F)if F then E("output",F,"w")end;return w.output end,input=function(F)if
F then E("input",F,"r")end;return w.input end,write=function(...)return
w.output:write(...)end,read=function(...)return w.input:read(...)end,lines=function(F,...)if
F==nil then return w.input:lines()end
return x.lines(F,...)end,close=function(F)F=F or w.output
if D(F)then return true end;return F:close()end},{__index=x,__metatable=false})i=function(F)A(F.."\n")end;aw[b]=function()
if v~=""then local F=v;v=""z(F)end end end end;if c[aA]then b.component=g;b.computer=h end
if c["load"]then b.load=function(t,u,v,w)
return load(t,u,"t",b)end;b.loadstring=b.load end
if c["notify"]then local u,t=pcall(require,"kernel.notify")
if
u and t and t.post then local v={}
b.notify={post=function(w)
if type(w)~="table"then return nil,"spec must be a table"end;local x={}for B,C in pairs(w)do x[B]=C end;local y=a.pkgName
x.from=(type(y)==al and
y:match("^[%w][%w%-]*$"))and y or"package"local z,A=t.post(x)if z~=nil then v[z]=true end;return z,A end,result=function(w)if
not v[w]then return nil end;return t.result(w)end}end end
if c["net"]then local u,t=pcall(require,"kernel.net")if u then b.net=
a.allowUserLibs and aq(t)or bp(t)end end
if c[aR]then local u,t=pcall(require,"kernel.internet")
if u and t then
b.internet={get=function(v,w)
return t.get(v,w)end,download=function(w,x,v)if not(c[aQ]and d)then
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
if type(v)==al and v:match("^[%w][%w%-]*$")then
b.crypto.secret=function()local w=
nil;local C,y=pcall(require,aS)if C and y and y.currentSession then
w=y.currentSession()end
if not w then
local H=_G._TOS and _G._TOS.users
if not H then local I,J=pcall(require,"kernel.users")if I then H=J end end;if H and H.currentSession then w=H.currentSession()end end
local D=w and(w.isKernel or w.isLogin or
(type(w.tier)==aC and w.tier>=2))
if not D then return nil,"crypto.secret requires an admin session"end;local E,x=pcall(require,aB)
if not E or not x then return nil,"fs unavailable"end;local z="/var/pkg/secrets"local A=z.."/"..v
if x.exists(A)then local H=x.readFile(A)if H and
#H>=16 then return H end;return nil,"secret unreadable"end;if not x.exists(z)then x.makeDirectory(z)end
local B=t.salt(32)local F,G=x.writeFile(A,B)if not F then
return nil,"cannot store secret: "..tostring(G)end;return B end end end end;return b end
function am.run(a,b,c,...)local e=am.build(c)local d,f=load(a,b,"t",e)if not d then return false,
"compile error: "..tostring(f)end;return pcall(d,...)end
function am.finish(a)local b=aw[a]if b then aw[a]=nil;pcall(b)end end
function am.exitStatus(a)
if type(a)=="table"and rawget(a,aE)==true then
local b=rawget(a,"code")if b==nil then return true end;return b end;return nil end
function am.describeEnd(b,a)
if b then local d=type(a)if d==al or d==aC or d=="boolean"then return tostring(a),
false end;return nil end;local c=am.exitStatus(a)
if c==nil then return tostring(a),true end;if c==true or c==0 then return nil end;return
"exited with status "..tostring(c),false end;return am