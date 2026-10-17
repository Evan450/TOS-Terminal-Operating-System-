local b={}
function b.init(a)a=a or{}if b._initCounts then if a.procSleep and b.setProcSleep then
b.setProcSleep(a.procSleep)end
return b._initCounts[1],b._initCounts[2]end
local e={["sides"]="compat.sides",["colors"]="compat.colors",["keyboard"]="compat.keyboard",["text"]="compat.text",["serialization"]="compat.serialization",["buffer"]="compat.buffer",["term"]="compat.term",["filesystem"]="compat.filesystem",["event"]="compat.event",["shell"]="compat.shell_api",["io"]="compat.io",["internet"]="compat.internet",["robot"]="compat.robot",["process"]="compat.process",["note"]="compat.note"}local c=0;local d=0
for f,g in pairs(e)do local h,i=pcall(require,g)if h then package.loaded[f]=i;c=
c+1 else d=d+1 end end
if package.loaded["io"]then _G.io=package.loaded["io"]end
do local f=require("component")
if not f.isAvailable then f.isAvailable=function(i)
local j=f.list(i)()return j~=nil end end
if not f.get then
f.get=function(i,j)
if type(i)~="string"then return nil,"invalid address"end
for k in f.list(j)do if k:sub(1,#i)==i then return k end end;return nil,"no such component"end end
if not f.getPrimary then
f.getPrimary=function(i)local j=f.list(i)()
if j then return f.proxy(j)end
return nil,"no primary "..tostring(i).." component"end end;local g=setmetatable({},{__mode="v"})
local h=setmetatable({},{__index=function(j,i)
if f[i]~=nil then return f[i]end;if g[i]then local l=pcall(f.type,g[i].address)if l then return g[i]end
g[i]=nil end;local k=f.list(i)()if k then
local l=f.proxy(k)g[i]=l;return l end;return nil end})package.loaded["compat.component"]=h end
if package.loaded["io"]then local f=package.loaded["io"]
_G.print=function(...)
local g=table.pack(...)for h=1,g.n do if h>1 then f.write("\t")end
f.write(tostring(g[h]))end;f.write("\n")end end;if not _G.os then _G.os={}end
do local f=require("computer")
local g=a.procSleep
_G.os.sleep=function(h)h=tonumber(h)or 0;if h<=0 then
if g then g(0)else f.pullSignal(0)end;return end
if g then g(h)else local i=f.uptime()+h;while
f.uptime()<i do local j=i-f.uptime()
f.pullSignal(math.min(j,0.5))end end end;function b.setProcSleep(h)g=h end end
if not _G.os.getenv then
local g={HOME="/home",SHELL="/tos/shell/init.lua",TERM="tos",PATH="/usr/bin:/bin"}local h,f=pcall(require,"kernel.env")
_G.os.getenv=function(i)if h and f.read then
local j=f.read(nil,i)if j then return j end end;return g[i]end
_G.os.setenv=function(i,j)
if h and f.write then f.write(nil,i,j)else g[i]=j end end end
if not _G.os.tmpname then
_G.os.tmpname=function()local h
local i,j=pcall(require,"kernel.crypto")if i then h=j end;local g;local k,l=pcall(require,"kernel.fs")if k then g=l end
for f=1,8 do local n;if h and
h.salt then n=h.salt(16)else
n=
tostring(require("computer").uptime()*1e6).."_"..
(tostring({}):match("0x(%x+)")or"fallback")end;local m=
"/tmp/tos_tmp_"..n
if g and g.exists then if not g.exists(m)then
pcall(g.writeFile,m,"")return m end else return m end end
error("os.tmpname: could not allocate unique tmp file")end end;b._initCounts={c,d}return c,d end;function b.has(a)return package.loaded[a]~=nil end
function b.list()
local a={}
local c={"sides","colors","keyboard","text","serialization","buffer","term","filesystem","event","shell","io"}for e,d in ipairs(c)do
a[#a+1]={name=d,loaded=package.loaded[d]~=nil}end;return a end;return b