local J,Q,R,I="invalid_export: ","invalid_path","no_such_handle","string"local z={}
local G=4096;local S=10;local T=30;local O=16;local P=120;local U=256;local N=256;local B,A,E,D,C,K
function z.init(a)a=a or{}B=a.net;A=a.fs
E=a.trust;D=a.log;K=a.computer or require("computer")
C=a.protocol or(B and
B.getProtocol and B.getProtocol())
if not C then local b,c=pcall(require,"kernel.net.protocol")if b then C=c end end;if B and C then
B.on(C.TYPE.NETFS_REQ,function(b,c)z.handleRequest(b,c)end)end;if D and D.info then
D.info("netfs","netfs module initialized")end;return true end;local L=false;function z.setEnabled(a)L=a and true or false end;function z.isEnabled()return
L end;z.EXPORTS_PATH="/etc/netfs-exports.cfg"local H={}
function z._validateExports(a)
if
type(a)~="table"then return nil,"invalid_config: not a table"end;local b,c={},{}
for e,d in ipairs(a)do local h="entry "..e;if type(d)~="table"then return nil,
J..h.." not a table"end;if type(d.name)~=I or not
d.name:match("^[%w_%-]+$")then return nil,
J..h.." needs a [%w_-] name"end
if
c[d.name]then return nil,"invalid_export: duplicate name "..d.name end;if type(d.path)~=I or d.path==""then return nil,
J..d.name.." needs a path"end
local g=d.mode or"ro"if g~="ro"and g~="rw"then
return nil,J..d.name.." mode must be ro or rw"end;if d.allow~=nil and
type(d.allow)~="table"then
return nil,J..d.name.." allow must be a list"end
local f=A and A.normalize and
A.normalize(d.path)or d.path;if type(f)~=I or f==""then return nil,
J..d.name.." path does not normalize"end
f=f:gsub("/+$","")if f==""then f="/"end;if f=="/"then
return nil,J..d.name.." refuses to export /"end;c[d.name]=true
b[#b+1]={name=d.name,path=f,mode=g,allow=d.allow or{}}end;return b end;function z.setExports(a)H=a or{}end;function z.getExports()return H end
function z.loadExports(a,b)
a=a or A
if not
(a and a.exists and a.exists(z.EXPORTS_PATH))then H={}return true,"no_exports"end;local c=a.readFile(z.EXPORTS_PATH)if not c or c==""then H={}
return true,"no_exports"end
local f=b or require("kernel.serialize")local g,d=pcall(f.decode,c,{maxBytes=8192})
if not g or
type(d)~="table"then return false,"decode_failed: netfs-exports.cfg"end;local e,h=z._validateExports(d)if not e then return false,h end;H=e;return true end
function z.arm(a)local b,c=true,nil;if a then b,c=z.loadExports(A)
if not b and D and D.warn then D.warn("netfs",
"not serving: "..tostring(c))end end;L=
(a and b)and true or false;if not L then H={}end;return b,c end;function z._findExport(a)for c,b in ipairs(H)do if b.name==a then return b end end
return nil end
function z._accessOk(a,b,c)if not a then
return false,"no_such_export"end
if c and a.mode~="rw"then return false,"read_only_export"end;local d=false
for f,e in ipairs(a.allow)do if e==b then d=true;break end
if e=="*paired*"then if
E and E.getLevel and
E.LEVEL and E.getLevel(b)>=E.LEVEL.TRUSTED then d=true;break end end end;if not d then return false,"not_allowed"end;return true end
function z._confine(b,a)if type(a)~=I or#a>U then return nil,Q end
if a==""then a="/"end;if a:sub(1,1)~="/"then a="/"..a end
local c=A and A.normalize and
A.normalize(b.path..a)or nil;if type(c)~=I or c==""then return nil,Q end
if c~=b.path and
c:sub(1,#b.path+1)~=b.path.."/"then return nil,Q end;return c end;local F={}local M=1
local function V(a)
for c,b in pairs(F)do
for e,d in pairs(b)do if a- (d.last or 0)>P then
pcall(function()if
d.h and d.h.close then d.h:close()end end)b[e]=nil end end;if next(b)==nil then F[c]=nil end end end
local function W(a)local b=0;for c in pairs(F[a]or{})do b=b+1 end;return b end
function z._dispatch(c,a,b)a=a or{}local e=K and K.uptime()or 0;V(e)
if c=="space"then
local f=z._findExport(a.share)local g,h=z._accessOk(f,b,false)if not g then return{err=h}end;return
{total=A.spaceTotal and
A.spaceTotal(f.path)or 0,used=
A.spaceUsed and A.spaceUsed(f.path)or 0,read_only=f.mode~="rw"}end
if c=="stat"then local g=z._findExport(a.share)
local h,i=z._accessOk(g,b,false)if not h then return{err=i}end;local f,j=z._confine(g,a.path)if not f then
return{err=j}end
if not A.exists(f)then return{exists=false}end;return
{exists=true,is_dir=A.isDirectory(f)and true or false,size=A.size and A.size(f)or 0,mtime=
A.lastModified and A.lastModified(f)or 0}end
if c=="list"then local g=z._findExport(a.share)
local j,k=z._accessOk(g,b,false)if not j then return{err=k}end;local h,l=z._confine(g,a.path)if not h then
return{err=l}end;local f=A.list(h)
if type(f)~="table"then return{entries={}}end;local i={}for m=1,math.min(#f,N)do i[m]=f[m]end
return{entries=i,truncated=#f>N}end
if c=="mkdir"then local f=z._findExport(a.share)
local h,i=z._accessOk(f,b,true)if not h then return{err=i}end;local g,j=z._confine(f,a.path)if not g then
return{err=j}end;return
{ok=A.makeDirectory(g)and true or false}end
if c=="remove"then local f=z._findExport(a.share)
local h,i=z._accessOk(f,b,true)if not h then return{err=i}end;local g,j=z._confine(f,a.path)if not g then
return{err=j}end
return{ok=A.remove(g)and true or false}end
if c=="rename"then local f=z._findExport(a.share)
local i,j=z._accessOk(f,b,true)if not i then return{err=j}end;local g,k=z._confine(f,a.path)if not g then
return{err=k}end;local h,l=z._confine(f,a.to)if not h then return{err=l}end;return{ok=
A.rename(g,h)and true or false}end
if c=="open"then local f=a.mode or"r"local m={r=true,rb=true}
local i={w=true,wb=true,a=true,ab=true}if type(f)~=I or not(m[f]or i[f])then
return{err="bad_mode"}end;local n=i[f]==true
local g=z._findExport(a.share)local o,p=z._accessOk(g,b,n)if not o then return{err=p}end
local j,q=z._confine(g,a.path)if not j then return{err=q}end
if W(b)>=O then return{err="too_many_handles"}end;local k,r=A.open(j,f)if not k then
return{err="open_failed: "..tostring(r)}end;local l=M;M=M+1;F[b]=F[b]or{}
F[b][l]={h=k,export=g,mode=f,last=e}return{handle_id=l}end
local d=a.handle_id and F[b]and F[b][a.handle_id]
if c=="read"then if not d then return{err=R}end;d.last=e
local f=tonumber(a.n)or G;if f>G then f=G end;local g=d.h:read(f)if g==nil then return{eof=true}end;return
{data=g,eof=false}end
if c=="write"then if not d then return{err=R}end;if d.export.mode~="rw"then return
{err="read_only_export"}end;d.last=e;local f=a.data;if
type(f)~=I then return{err="invalid_data"}end;if#f>G then return
{err="chunk_too_large"}end;local g=d.h:write(f)return{ok=g and true or false,written=
#f}end
if c=="close"then if not d then return{ok=true}end
pcall(function()d.h:close()end)F[b][a.handle_id]=nil;return{ok=true}end;if c=="seek"then if not d then return{err=R}end;d.last=e
return{pos=d.h:seek(a.whence or"set",
tonumber(a.offset)or 0)}end;return
{err="unknown_op"}end
function z.handleRequest(b,a)if not(B and C)then return end;if not L then return end
local function c()
local f=C.makePacket(C.TYPE.NETFS_RES,{req_id=
b and b.payload and b.payload.req_id,err="denied"},{to=a})B.send(a,f)end
if not(E and E.getLevel and E.LEVEL)then return c()end
if E.getLevel(a)<E.LEVEL.TRUSTED then if D and D.warn then
D.warn("netfs","request from non-trusted peer "..
tostring(a):sub(1,8))end;return c()end
if B.verifyPeer then local f=B.verifyPeer(a)
if not f then if D and D.warn then
D.warn("netfs","verification failed for "..
tostring(a):sub(1,8))end;return c()end end;local d=b.payload or{}local e=z._dispatch(d.op,d,a)
e.req_id=d.req_id
B.send(a,C.makePacket(C.TYPE.NETFS_RES,e,{to=a}))end
local function X(a)local b=0
return
function(d,c)if not(B and C)then return nil,"no_network"end;b=b+1;local f=b
c.op=d;c.req_id=f;local e,g=false,nil
local h=B.on(C.TYPE.NETFS_RES,function(j,k)if k~=a then return end
local l=j.payload or{}if l.req_id~=f then return end;e,g=true,l end)
local i=B.send(a,C.makePacket(C.TYPE.NETFS_REQ,c,{to=a}))
if not i then B.off(C.TYPE.NETFS_RES,h)return nil,"send_failed"end;B.waitFor(function()return e end,S)
B.off(C.TYPE.NETFS_RES,h)if not e then return nil,"timeout"end;return g end end
function z.attach(c,a,b)b=b or{}local m=b.transport or X(c)local d={}
d.address="netfs:"..
tostring(c):sub(1,8)..":"..tostring(a)
function d.getLabel()return"netfs("..tostring(a)..")"end
local function e(o,n)n=n or{}n.share=a;local p,q=m(o,n)
if not p then return nil,q or"no_reply"end;if p.err then return nil,p.err end;return p end;d._call=e;local l,g=-math.huge,nil
local function i()
local n=K and K.uptime()or 0;if g and(n-l)<T then return g end;local o=e("space")if o then g=o;l=n end;return g end
function d.spaceTotal()local n=i()return n and n.total or 0 end;function d.spaceUsed()local n=i()return n and n.used or 0 end
function d.isReadOnly()
local n=i()return n and n.read_only or false end;local function h(n)local o=e("stat",{path=n})return o end
function d.exists(n)
local o=h(n)return o~=nil and o.exists==true end
function d.isDirectory(n)local o=h(n)return o~=nil and o.is_dir==true end;function d.size(n)local o=h(n)return o and o.size or 0 end;function d.lastModified(n)
local o=h(n)return o and o.mtime or 0 end;function d.list(n)
local o=e("list",{path=n})return o and o.entries or{}end
function d.makeDirectory(n)
local o=e("mkdir",{path=n})return o~=nil and o.ok==true end;function d.remove(n)local o=e("remove",{path=n})
return o~=nil and o.ok==true end
function d.rename(n,o)
local p=e("rename",{path=n,to=o})if not p then return false end;return p.ok==true end;local f,j={},1
function d.open(o,n)n=n or"r"local p,r=e("open",{path=o,mode=n})if not p then
return nil,r end;local q=j;j=j+1
f[q]={remote=p.handle_id,mode=n,buf="",pos=1,eof=false,wbuf={},wlen=0}return q end
function d.read(p,o)local n=f[p]if not n then return nil end;o=tonumber(o)or G
while(
#n.buf-n.pos+1)<o and not n.eof do
local t=e("read",{handle_id=n.remote,n=G})
if not t or t.eof or not t.data then n.eof=true;break end;n.buf=n.buf:sub(n.pos)..t.data;n.pos=1 end;local q=#n.buf-n.pos+1;if q<=0 then return nil end
local r=o<q and o or q;local s=n.buf:sub(n.pos,n.pos+r-1)n.pos=n.pos+r;return s end
local function k(n)if n.wlen==0 then return true end;local o=table.concat(n.wbuf)
n.wbuf,n.wlen={},0
while#o>0 do local q=o:sub(1,G)o=o:sub(G+1)
local p=e("write",{handle_id=n.remote,data=q})if not p or p.ok~=true then return false end end;return true end
function d.write(o,n)local p=f[o]if not p then return false end
if type(n)~=I then return false end;p.wbuf[#p.wbuf+1]=n;p.wlen=p.wlen+#n
if p.wlen>=G then return k(p)end;return true end
function d.close(n)local o=f[n]if not o then return true end;local p=k(o)
e("close",{handle_id=o.remote})f[n]=nil;return p end
function d.seek(n,o,p)local q=f[n]if not q then return nil end;k(q)
local r=e("seek",{handle_id=q.remote,whence=o,offset=p})q.buf,q.pos,q.eof="",1,false;return r and r.pos or nil end;return d end
z._internal={BLOCK=G,MAX_HANDLES=O,MAX_LIST=N,HANDLE_IDLE=P,handles=function()return F end,resetHandles=function()F={}M=1 end}
do local a=rawget(_G,"_TOS")
if a and a.net and not B then
local b=pcall(z.init,{net=a.net,fs=a.fs,trust=a.net.getTrust and
a.net.getTrust()or nil,log=a.logObj})if
b and a.net.getServiceArm and a.net.getServiceArm("netfsd")then z.arm(true)end end end;return z