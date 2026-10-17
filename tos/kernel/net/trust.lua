local D=require("computer")local L=require("kernel.serialize")
local z={}local y={BLOCKED=-1,UNKNOWN=0,KNOWN=1,TRUSTED=2}
local P={[y.BLOCKED]={},[y.UNKNOWN]={ping=true,pong=true,cl_pair_init=true,cl_pair_conf=true},[y.KNOWN]={ping=true,pong=true,hello=true,hello_ack=true,info_req=true,info_res=true,trust_req=true,trust_ack=true,trust_deny=true,cl_pair_init=true,cl_pair_conf=true},[y.TRUSTED]={ping=true,pong=true,hello=true,hello_ack=true,info_req=true,info_res=true,trust_req=true,trust_ack=true,trust_deny=true,trust_rev=true,cl_pair_init=true,cl_pair_conf=true,msg=true,msg_ack=true,file_req=true,file_res=true,file_deny=true,challenge=true,chall_res=true,remote_exec=true,remote_res=true,cl_reg=true,cl_reg_ack=true,cl_hb=true,cl_asn=true,cl_asn_ack=true,cl_res=true,cl_res_chunk=true,cl_cancel=true,cl_drain=true,cl_st_req=true,cl_st_res=true,rly_fwd=true,rly_fail=true,peer_st=true,st_put=true,st_put_ack=true,st_put_chunk=true,st_ext=true,st_rel=true,st_list=true,st_list_res=true,st_err=true,ch_pair_init=true,ch_pair_conf=true,mesh=true,mesh_ack=true,nfs_req=true,nfs_res=true}}local A={}local I="/etc/trust.dat"local Q=64;local C={}local R=300;local S=32;local F=nil;local G=nil;local B=nil
local T=nil
local function J()if not F then return false end;local a={}for c,b in pairs(A)do
a[c]={level=b.level,hostname=b.hostname,firstSeen=b.firstSeen,lastSeen=b.lastSeen,sharedSecret=b.sharedSecret,notes=b.notes}end;return
(
F.writeFileAtomic or F.writeFile)(I,L.encode(a))end
local function M(a)if type(a)~="string"then return nil end
a=a:gsub("%c",""):sub(1,32)if a==""then return nil end;return a end
local U={[y.BLOCKED]=true,[y.UNKNOWN]=true,[y.KNOWN]=true,[y.TRUSTED]=true}
local function V()if not F or not F.exists(I)then return end
local a,c=F.readFile(I)if not a then return end;local b=L.decode(a)
if type(b)~="table"then return end;A=b
for e,d in pairs(A)do if not U[d.level]then d.level=y.UNKNOWN end
d.hostname=M(d.hostname)d.firstSeen=d.firstSeen or 0;d.lastSeen=d.lastSeen or 0 end end
function z.init(a)F=a.fs;G=a.crypto;B=a.log;T=a.config;V()local b=0;for c in pairs(A)do b=b+1 end;if B then
B.info("trust",
"Trust manager initialized ("..b.." known peers)")end;return true end
local function E(a)if not a then return nil end;if A[a]then return a end;local b=nil
for c in pairs(A)do if c:sub(1,#a)==a then if
b then return nil end;b=c end end;return b end
function z.getLevel(a)if not a then return y.UNKNOWN end;a=E(a)local b=A[a]
if not b then return y.UNKNOWN end;return b.level end
function z.getPeer(a)if not a then return nil end;a=E(a)return A[a]end
function z.isAllowed(a,b)local c=z.getLevel(a)if c==y.BLOCKED then return false end
local d=P[c]if not d then return false end;return d[b]==true end
function z.seen(a)
if not A[a]then local b=0
for d,c in pairs(A)do if c.level==y.UNKNOWN then b=b+1 end end
if b>=Q then local c,d=nil,math.huge;for f,e in pairs(A)do
if e.level==y.UNKNOWN and
(e.lastSeen or 0)<d then c=f;d=e.lastSeen or 0 end end
if c then A[c]=nil;if B then
B.debug("trust",
"Evicted old unknown peer: "..c:sub(1,8))end end end
A[a]={level=y.UNKNOWN,hostname=nil,firstSeen=D.uptime(),lastSeen=D.uptime()}else A[a].lastSeen=D.uptime()end end
function z.setLevel(d,a,b,c)c=c or 0
if c<2 then return false,"Admin privileges required to modify trust"end
local f={[y.BLOCKED]=true,[y.UNKNOWN]=true,[y.KNOWN]=true,[y.TRUSTED]=true}
if not f[b]then return false,"Invalid trust level: "..tostring(b)end;local e=E(a)
if e then a=e else
local h=type(a)=="string"and#a==36 and
a:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil;if not h then
return false,"Ambiguous or invalid address: "..tostring(a)end end
if not A[a]then A[a]={firstSeen=D.uptime(),lastSeen=D.uptime()}end;local g=A[a].level or y.UNKNOWN;A[a].level=b;J()
if B then
local h={[-1]="BLOCKED",[0]="UNKNOWN",[1]="KNOWN",[2]="TRUSTED"}
B.info("trust",string.format("Trust for %s: %s -> %s (by %s)",a:sub(1,8).."...",h[g]or"?",h[b]or"?",d))end;C[a]=nil;return true end
function z.trustKnown(a,b,c)return z.setLevel(a,b,y.KNOWN,c)end
function z.trustFull(a,b,c)return z.setLevel(a,b,y.TRUSTED,c)end
function z.block(a,b,c)return z.setLevel(a,b,y.BLOCKED,c)end
function z.revoke(a,b,c)return z.setLevel(a,b,y.UNKNOWN,c)end
function z.forget(c,a,b)if not a then return false,"No address"end;b=b or 0;if b<2 then return false,
"Admin privileges required"end;a=E(a)if not A[a]then
return false,"Peer not found"end;A[a]=nil;C[a]=nil;J()if B then
B.info("trust","Peer forgotten: "..a:sub(1,8).." (by "..c..
")")end;return true end
local function K(b,a,c)a=tonumber(a)or 0;if a<2 then
return false,"Admin privileges required to "..c end;if not b or b==""then
return false,"Actor required to "..c end;return true end
function z.setSecret(b,a,c,d)local e,f=K(b,d,"set peer secret")if not e then return false,f end
a=E(a)if not A[a]then return false,"Unknown peer"end
if
A[a].level<y.TRUSTED then return false,"Peer must be TRUSTED for shared secrets"end;A[a].sharedSecret=c;J()
pcall(function()local g=require("kernel.net")if
g and g.invalidateVerification then g.invalidateVerification(a)end end)if B then
B.info("trust","Shared secret "..
(c and"set"or"cleared").." for "..a:sub(1,8).."... (by "..
tostring(b)..")")end;return true end
function z.getSecret(b,a,c)local e,f=K(b,c,"read peer secret")if not e then return nil,f end
a=E(a)local d=A[a]if not d then return nil,"Unknown peer"end;if B then
B.info("trust","Secret read for "..
a:sub(1,8).."... (by "..tostring(b)..")")end;return d.sharedSecret end
function z.generateSecret(a,c,b)local e,f=K(a,b,"generate peer secret")
if not e then return nil,f end;if not G then return nil,"Crypto not available"end
local d=G.salt(32)local g,h=z.setSecret(a,c,d,b)if not g then return nil,h end;return d end;local H=nil;local N=false
function z._internalGetSecret(a,b)if not H or b~=H then return nil end;a=E(a)
local c=A[a]return c and c.sharedSecret or nil end
function z.getBootstrapToken()if N then return nil end
if not H then if not G then return nil end;H=G.salt(64)end;N=true;return H end;local function O()local a=D.uptime()
for b,c in pairs(C)do if a-c.time>R then C[b]=nil end end end
function z.addPendingRequest(a,b)b=M(b)O()if C[a]then
C[a].time=D.uptime()C[a].hostname=b;return end;local c=0
for d in pairs(C)do c=c+1 end
if c>=S then local d,e=nil,math.huge
for g,f in pairs(C)do if f.time<e then d=g;e=f.time end end;if d then C[d]=nil end end;C[a]={time=D.uptime(),hostname=b}if B then
B.info("trust","Trust request from "..a:sub(1,8).." (".. (b or
"unknown")..")")end end;function z.getPendingRequests()O()local a={}
for c,b in pairs(C)do a[c]={time=b.time,hostname=b.hostname}end;return a end;function z.clearPendingRequest(a)C[a]=
nil end
function z.listPeers()local a={}
for c,b in pairs(A)do
a[#a+1]={address=c,level=b.level,hostname=b.hostname,firstSeen=b.firstSeen,lastSeen=b.lastSeen,hasSecret=
b.sharedSecret~=nil,notes=b.notes}end
table.sort(a,function(c,d)
if c.level~=d.level then return c.level>d.level end
return(c.lastSeen or 0)> (d.lastSeen or 0)end)return a end
function z.stats()local a={blocked=0,unknown=0,known=0,trusted=0}
for c,b in pairs(A)do local d=b.level
if
d==y.BLOCKED then a.blocked=a.blocked+1 elseif d==y.KNOWN then a.known=a.known+1 elseif d==y.TRUSTED then a.trusted=
a.trusted+1 else a.unknown=a.unknown+1 end end;return a end
function z.levelName(a)
if a==y.BLOCKED then return"BLOCKED"elseif a==y.UNKNOWN then return"UNKNOWN"elseif a==y.KNOWN then return"KNOWN"elseif a==
y.TRUSTED then return"TRUSTED"else return"?"end end;z.resolveAddress=E;z.LEVEL=y;return z