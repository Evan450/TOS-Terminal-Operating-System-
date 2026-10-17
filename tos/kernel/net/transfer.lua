local w,D,B="transfer","string"," bytes)"local H=require("computer")local u={}
local x=6144;local E=30;local s=nil;local v=nil;local y=nil;local F=nil;local t=nil;local G=nil;local r=nil;local z=nil;local A=nil
local C=false;function u.setEnabled(a)C=a and true or false end
function u.isEnabled()return C end
function u.init(a)s=a.net;v=a.fs;y=a.trust;F=a.crypto;t=a.log;G=a.event;z=a.securefs;A=a.users
r=require("kernel.net.protocol")if s then
s.on(r.TYPE.FILE_REQ,function(b,c)u.handleRequest(b,c)end)end;if t then
t.info(w,"File transfer module initialized")end;return true end
function u.request(a,b,c,d)if not s then return false,"Network not available"end;if not r then return false,
"Protocol not loaded"end;d=d or{}local h=d.session
local n=y.getLevel(a)
if n<y.LEVEL.TRUSTED then return false,"Peer is not TRUSTED"end
if s.verifyPeer then local I,J=s.verifyPeer(a)if not I then return false,
"Peer verification failed: "..tostring(J)end end;local e=v.normalize and v.normalize(c)or c
if
type(e)~=D or e==""or e=="/"then return false,"Invalid local path"end;local f=nil
if h and h.user then f=h.user elseif A and A.currentSession then
local I=A.currentSession()if I then f=I.user end end
if f and not f:match("^[%w_%-]+$")then f=nil end;local function j(J,I)return J:sub(1,#I)==I end;local i=false;if j(e,"/tmp/")then
i=true end;if j(e,"/public/")then i=true end;if f and
j(e,"/home/"..f.."/")then i=true end;if f=="root"and
(e=="/root"or j(e,"/root/"))then i=true end
if not i then return false,
"Refusing to write outside /tmp, /public, or /home/<you>: "..e end;local k=false;local l=false;local g="Timeout waiting for response"
local m={{type=r.TYPE.FILE_RES,id=s.onceFrom(r.TYPE.FILE_RES,a,function(I)
k=true;local J=I.payload or{}
if type(J.data)~=D then
g="Invalid response: data not a string"elseif J.path and J.path~=b then
g="Invalid response: path mismatch ("..tostring(J.path).." ~= "..
tostring(b)..")"elseif#J.data>x then
g="Response too large: "..#J.data.." bytes (max "..x..")"else local K,L;if z and h and z.writeFile then K,L=z.writeFile(c,J.data,h)else
K,L=v.writeFile(c,J.data)end
if K then l=true;if t then
t.info(w,"Received file: "..
b.." ("..tostring(J.size or#
J.data)..B)end else
g="Failed to write local file: "..tostring(L or c)end end end)},{type=r.TYPE.FILE_DENY,id=s.onceFrom(r.TYPE.FILE_DENY,a,function(I)
k=true;local J=I.payload or{}g=J.reason or"File request denied"end)}}local o=r.makePacket(r.TYPE.FILE_REQ,{path=b},{to=a})
local p,q=s.send(a,o)
if not p then s.offAll(m)return false,"Send failed: "..tostring(q)end;if t then
t.info(w,"Requested file: "..b.." from "..a:sub(1,8).."...")end
s.waitFor(function()return k end,E)s.offAll(m)if not k then return false,g end;if l then return true end
return false,g end
function u.handleRequest(b,a)if not s or not r then return end;if not C then return end
local g=y.getLevel(a)
if g<y.LEVEL.TRUSTED then if t then
t.warn(w,"FILE_REQ denied from non-trusted peer: "..a:sub(1,8).."...")end
local l=r.makePacket(r.TYPE.FILE_DENY,{reason="Insufficient trust level"},{to=a})s.send(a,l)return end
if s.verifyPeer then local l,m=s.verifyPeer(a)
if not l then if t then
t.warn(w,"Refusing FILE_REQ from "..a:sub(1,8)..
": "..tostring(m))end
local n=r.makePacket(r.TYPE.FILE_DENY,{reason="Insufficient trust level"},{to=a})s.send(a,n)return end end;local h=b.payload or{}local f=h.path
if not f or f==""then
local l=r.makePacket(r.TYPE.FILE_DENY,{reason="No file path specified"},{to=a})s.send(a,l)return end;local c=v.normalize(f)
if type(c)~=D or
(c:sub(1,8)~="/public/"and c~="/public")then
local l=r.makePacket(r.TYPE.FILE_DENY,{reason="Access restricted to /public/"},{to=a})s.send(a,l)return end
if not v.exists(c)then if t then
t.info(w,"FILE_REQ for missing file: "..c.." from "..a:sub(1,8))end
local l=r.makePacket(r.TYPE.FILE_DENY,{reason="File not found: "..c},{to=a})s.send(a,l)return end;local e=v.size and v.size(c)or nil
if
type(e)=="number"and e>x then if t then
t.info(w,"FILE_REQ denied (too large): "..c.." ("..e..B)end
local l=r.makePacket(r.TYPE.FILE_DENY,{reason="File too large for single transfer ("..e.." > "..x..
B},{to=a})s.send(a,l)return end;local d=v.readFile(c)if not d then
local l=r.makePacket(r.TYPE.FILE_DENY,{reason="Cannot read file: "..c},{to=a})s.send(a,l)return end
if#
d>x then if t then
t.info(w,"FILE_REQ denied post-read (too large): "..c.." ("..#d..B)end
local l=r.makePacket(r.TYPE.FILE_DENY,{reason=
"File too large for single transfer ("..#d.." > "..x..B},{to=a})s.send(a,l)return end;if t then
t.info(w,"Sending file: "..c.." ("..
#d.." bytes) to "..a:sub(1,8).."...")end
local i=r.makePacket(r.TYPE.FILE_RES,{path=c,data=d,size=#d},{to=a})local j,k=s.send(a,i)if not j and t then
t.warn(w,"Failed to send file response: "..tostring(k))end end
do local a=rawget(_G,"_TOS")
if a and a.net and not s then
local b,c=pcall(require,"kernel.crypto")
local d=pcall(u.init,{net=a.net,fs=a.fs,trust=a.net.getTrust and a.net.getTrust()or nil,crypto=
b and c or nil,log=a.logObj,event=a.event,securefs=a.securefs,users=a.users})if
d and a.net.getServiceArm and a.net.getServiceArm("fileshare")then u.setEnabled(true)end end end;return u