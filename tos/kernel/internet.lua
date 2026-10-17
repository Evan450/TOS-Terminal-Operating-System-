local D,E="internet","no internet card installed"
local x=require("component")local u=require("computer")local s={}local v=nil;local t=nil;local y=64*1024
local z=512*1024;local A=15;local J=3;local F=8;s.DEFAULT_MAX_BYTES=y;s.DEFAULT_TIMEOUT=A;function s.init(a)a=a or{}
v=a.log;t=a.config end;local G={http=true,https=true}
function s.parseUrl(a)
if
type(a)~="string"or a==""then return false,"empty URL"end;if#a>2048 then return false,"URL too long"end;if a:find("[%c]")then return false,
"URL contains control characters"end
local b,d=a:match("^(%a[%w+.-]*)://(.+)$")
if not b then return false,"URL must start with http:// or https://"end;b=b:lower()
if not G[b]then return false,
"unsupported scheme '"..b.."' (http and https only)"end;local c=d:match("^([^/?#]+)")or""if c==""then
return false,"URL has no host"end;if c:find("@",1,true)then
return false,"URL must not contain credentials"end
local e=c:match("^([^:]+)")or c;return true,b,e:lower()end
function s.hostOf(a)local b,d,c=s.parseUrl(a)if not b then return nil end;return c end
local function w()local a=x.list(D)()if not a then return nil end;local b,c=pcall(x.proxy,a)if not
b then return nil end;return c,a end
function s.status()
local a={present=false,http=false,tcp=false,enabled=s.isEnabled(),addr=nil,reason=nil}local b,c=w()if not b then a.reason=E;return a end;a.present=true;a.addr=
c and c:sub(1,8)or nil
a.http=(b.isHttpEnabled and
select(2,pcall(b.isHttpEnabled)))==true;a.tcp=
(b.isTcpEnabled and select(2,pcall(b.isTcpEnabled)))==true
if
not a.enabled then a.reason="disabled on this machine (config: internet = false)"elseif not a.http then
a.reason="the server has HTTP disabled for internet cards"end;return a end;function s.available()local a=s.status()
return a.present and a.http and a.enabled end
function s.isEnabled()if not t or not t.get then
return true end;local a=t.get(D)if a==nil then return true end
return a~=false and
a~="false"and a~="off"and a~=0 end
local function H(a)
local b=(a and tonumber(a.maxBytes))or
(t and t.get and tonumber(
t.get("internetMaxKB")or 0)*1024)or nil;if not b or b<=0 then b=y end;if b>z then b=z end;return math.floor(b)end
local function I(a)
local b=(a and tonumber(a.timeout))or
(t and t.get and tonumber(
t.get("internetTimeout")or 0))if not b or b<=0 then b=A end;return b end
local function B()local b,a=pcall(require,"kernel.process")if
b and a and a.yieldCooperative then a.yieldCooperative()end end
local function C(b,c,a)a=a or{}local n,o=s.parseUrl(b)if not n then return false,o end
local g=s.status()if not g.present then return false,E end
if not g.enabled then return false,g.reason end
if not g.http then return false,g.reason or"HTTP is not available"end;local h=w()if not h or not h.request then
return false,"internet card has no HTTP support"end;local k=H(a)local i=I(a)
local p,e,q=pcall(h.request,b,a.body,a.headers,a.method)
if not p then return false,"request failed: "..tostring(e)end
if not e then return false,tostring(q or"request refused")end;local d={bytes=0}local l=false;local function f()if not l then l=true
pcall(function()e.close()end)end end
local function r()if d.status or
not e.response then return end;local L,K,M,N=pcall(e.response)
if L and K then d.status=
tonumber(K)or K;d.message=M;d.headers=N end end;local m=u.uptime()+i;local j=0
while true do local M,K,L=pcall(e.read)if not M then f()return false,"read failed: "..
tostring(K)end;r()
if

type(d.status)=="number"and(d.status<200 or d.status>299)then f()return false,"HTTP "..
d.status.." "..tostring(d.message or""),d end
if K==nil then f()if L then return false,tostring(L),d end;return true,nil,d end
if#K>0 then d.bytes=d.bytes+#K
if d.bytes>k then f()
return false,
string.format(
"response exceeds the %d KB limit (raise it with the maxBytes option ".."or the internetMaxKB config key)",math.floor(
k/1024)),d end
if not c(K)then f()return false,"write failed while saving the response",d end;m=u.uptime()+i else B()end;j=j+1;if j%F==0 then B()end;if u.uptime()>m then f()return false,
"timed out after "..i.."s with no data",d end end end
function s.get(a,b)local c={}
local e,f,d=C(a,function(g)c[#c+1]=g;return true end,b)if not e then return nil,f,d end;return table.concat(c),nil,d end
function s.download(c,a,b)
local d=
(type(b)=="table"and type(b.fs)=="table"and b.fs)or(_G._TOS and _G._TOS.fs)or
require("kernel.fs")
if type(a)~="string"or a==""then return false,"no destination path"end;local e=a..".part"pcall(d.remove,e)local h,f={},0;local m=8*1024;local j=false
local function k()if
f==0 then return true end;local p=table.concat(h)h,f={},0;local o=false;if d.appendFile then
o=d.appendFile(e,p)end;if not o then j=true end;return o and true or false end
local i,l,g=C(c,function(o)h[#h+1]=o;f=f+#o;if f>=m then return k()end;return true end,b)
if i then if not k()then i,l=false,"write failed"end end
if not i or j then pcall(d.remove,e)return false,l or"write failed",g end;pcall(d.remove,a)local n=d.rename and d.rename(e,a)
if not n then
local o=d.readFile(e)
if not o or not d.writeFile(a,o)then pcall(d.remove,e)return false,
"could not finalize "..a,g end;pcall(d.remove,e)end;if v then
v.info(D,string.format("Downloaded %d bytes to %s",(g and g.bytes)or 0,a))end;return true,nil,g end
function s.socket(b,a)local c=s.status()if not c.present then return nil,E end;if not c.enabled then return nil,
c.reason end;if not c.tcp then
return nil,"the server has TCP sockets disabled for internet cards"end;local d=w()
if
not d or not d.connect then return nil,"internet card has no TCP support"end;local f=tostring(b)..
(a and(":"..tostring(a))or"")
local g,e,h=pcall(d.connect,f)if not g then return nil,tostring(e)end;if not e then return nil,
tostring(h or"connection refused")end;return e end;return s