local s="no_storage_node"local x=require("computer")local m={}local t=10;local u=2101
local n,o,v,q,w
local function p(...)for a=1,select("#",...)do local c,b=pcall(require,(select(a,...)))if
c and b then return b end end end
function m.init(a)a=a or{}n=a.net or p("kernel.net")q=a.state or
p("cluster.state")
v=a.serialize or p("kernel.serialize")
w=a.log or p("kernel.log","log")or
{info=function()end,warn=function()end,error=function()end}
o=a.protocol or
(n and n.getProtocol and n.getProtocol())or p("kernel.net.protocol")return true end
function m.address()local a=q and q._data and q._data.storage_node;return a and
a.address or nil end;function m.available()
return m.address()~=nil and n~=nil and o~=nil end
local function r(b,c,a)local d=m.address()
if not d then return nil,s end;if not(n and o)then return nil,"no_network"end;local e,h,g=false,nil,nil
local f={}local function i(k,l)f[#f+1]={t=k,id=n.on(k,l)}end
i(o.TYPE.STORE_PUT_ACK,function(k,l)if
l~=d then return end;local y=k.payload or{}if y.key~=a then return end;e,h=true,y end)
i(o.TYPE.STORE_ERROR,function(k,l)if l~=d then return end;local y=k.payload or{}if
y.key~=nil and y.key~=a then return end;e,g=true,y.reason or"store_error"end)local j=n.send(d,o.makePacket(b,c,{to=d}),u)
if j==false then for l,k in
ipairs(f)do pcall(n.off,k.t,k.id)end;return nil,"send_failed"end
if n.waitFor then n.waitFor(function()return e end,t)end;for l,k in ipairs(f)do pcall(n.off,k.t,k.id)end
if g then return nil,g end;if not e then return nil,"timeout"end;return h end
function m.put(c,b,a)a=a or{}if not m.available()then return nil,s end;local d=
(type(b)=="string")and b or v.encode(b)return
r(o.TYPE.STORE_PUT,{key=c,data=d,ttl=
a.ttl or 0,overwrite=a.overwrite~=false},c)end
function m.release(a,b)if not m.available()then return nil,s end;return
r(o.TYPE.STORE_RELEASE,{key=a,lease_id=b},a)end
function m.extend(a,b,c)if not m.available()then return nil,s end;return
r(o.TYPE.STORE_LEASE_EXTEND,{key=a,lease_id=b,extend_by=c},a)end;function m.tasksKey(a,b)
return string.format("job-%d/tasks/assignment-%d",a,b)end;function m.inputsKey(a,b)return
string.format("job-%d/inputs/assignment-%d",a,b)end;function m.resultsPrefix(a)return
string.format("public://job-%d/results/",a)end
m._internal={WRITE_PORT=u,RPC_TIMEOUT=t,rpc=function(...)return
r(...)end}return m