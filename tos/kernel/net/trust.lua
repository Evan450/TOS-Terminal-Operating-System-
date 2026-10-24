local Q="string"local L=require("computer")
local V=require("kernel.serialize")local F={}local E={BLOCKED=-1,UNKNOWN=0,KNOWN=1,TRUSTED=2}
local aa={[E.BLOCKED]={},[E.UNKNOWN]={ping=true,pong=true,cl_pair_init=true,cl_pair_conf=true},[E.KNOWN]={ping=true,pong=true,hello=true,hello_ack=true,info_req=true,info_res=true,trust_req=true,trust_ack=true,trust_deny=true,cl_pair_init=true,cl_pair_conf=true},[E.TRUSTED]={ping=true,pong=true,hello=true,hello_ack=true,info_req=true,info_res=true,trust_req=true,trust_ack=true,trust_deny=true,trust_rev=true,cl_pair_init=true,cl_pair_conf=true,msg=true,msg_ack=true,file_req=true,file_res=true,file_deny=true,challenge=true,chall_res=true,remote_exec=true,remote_res=true,cl_reg=true,cl_reg_ack=true,cl_hb=true,cl_asn=true,cl_asn_ack=true,cl_res=true,cl_res_chunk=true,cl_cancel=true,cl_drain=true,cl_st_req=true,cl_st_res=true,rly_fwd=true,rly_fail=true,peer_st=true,st_put=true,st_put_ack=true,st_put_chunk=true,st_ext=true,st_rel=true,st_list=true,st_list_res=true,st_err=true,ch_pair_init=true,ch_pair_conf=true,mesh=true,mesh_ack=true,nfs_req=true,nfs_res=true}}local G={}local S="/etc/trust.dat"local J=nil;local T;local ab=64;local I={}local ac=300;local ad=32;local N=nil
local M=nil;local H=nil;local ae=nil
local function O()if not N then return false end;local a={}
for d,c in pairs(G)do
a[d]={level=c.level,hostname=c.hostname,firstSeen=c.firstSeen,lastSeen=c.lastSeen,sharedSecret=c.sharedSecret,dhPub=c.dhPub,notes=c.notes}end;local b={peers=a,dh=J}return
(N.writeFileAtomic or N.writeFile)(S,V.encode(b))end
local function W(a)if type(a)~=Q then return nil end
a=a:gsub("%c",""):sub(1,32)if a==""then return nil end;return a end
local af={[E.BLOCKED]=true,[E.UNKNOWN]=true,[E.KNOWN]=true,[E.TRUSTED]=true}
local function ag()if not N or not N.exists(S)then return end
local b,c=N.readFile(S)if not b then return end;local a=V.decode(b)
if type(a)~="table"then return end
if a.peers~=nil or a.dh~=nil then G=a.peers or{}J=a.dh
if not
(type(J)=="table"and
type(J.priv)==Q and#J.priv==32 and type(J.pub)==
Q and#J.pub==32)then J=nil end else G=a end
for e,d in pairs(G)do if not af[d.level]then d.level=E.UNKNOWN end
d.hostname=W(d.hostname)d.firstSeen=d.firstSeen or 0;d.lastSeen=d.lastSeen or 0
if
type(d.dhPub)~=Q or#d.dhPub~=32 then d.dhPub=nil end end end
function F.init(a)N=a.fs;M=a.crypto;H=a.log;ae=a.config;ag()local b=0;for c in pairs(G)do b=b+1 end;if H then
H.info("trust",
"Trust manager initialized ("..b.." known peers)")end;return true end
local function K(a)if not a then return nil end;if G[a]then return a end;local b=nil
for c in pairs(G)do if c:sub(1,#a)==a then if
b then return nil end;b=c end end;return b end
function F.getLevel(a)if not a then return E.UNKNOWN end;a=K(a)local b=G[a]
if not b then return E.UNKNOWN end;return b.level end
function F.getPeer(a)if not a then return nil end;a=K(a)return G[a]end
function F.isAllowed(a,b)local c=F.getLevel(a)if c==E.BLOCKED then return false end
local d=aa[c]if not d then return false end;return d[b]==true end
function F.seen(a)
if not G[a]then local b=0
for d,c in pairs(G)do if c.level==E.UNKNOWN then b=b+1 end end
if b>=ab then local c,d=nil,math.huge;for f,e in pairs(G)do
if e.level==E.UNKNOWN and
(e.lastSeen or 0)<d then c=f;d=e.lastSeen or 0 end end
if c then G[c]=nil;if H then
H.debug("trust",
"Evicted old unknown peer: "..c:sub(1,8))end end end
G[a]={level=E.UNKNOWN,hostname=nil,firstSeen=L.uptime(),lastSeen=L.uptime()}else G[a].lastSeen=L.uptime()end end
function F.setLevel(d,a,b,c)c=c or 0
if c<2 then return false,"Admin privileges required to modify trust"end
local g={[E.BLOCKED]=true,[E.UNKNOWN]=true,[E.KNOWN]=true,[E.TRUSTED]=true}
if not g[b]then return false,"Invalid trust level: "..tostring(b)end;local e=K(a)
if e then a=e else
local h=type(a)==Q and#a==36 and
a:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil;if not h then
return false,"Ambiguous or invalid address: "..tostring(a)end end
if not G[a]then G[a]={firstSeen=L.uptime(),lastSeen=L.uptime()}end;local f=G[a].level or E.UNKNOWN;G[a].level=b;if b==E.TRUSTED and
f~=E.TRUSTED then T(a)end;O()
if H then
local h={[-1]="BLOCKED",[0]="UNKNOWN",[1]="KNOWN",[2]="TRUSTED"}
H.info("trust",string.format("Trust for %s: %s -> %s (by %s)",a:sub(1,8).."...",h[f]or"?",h[b]or"?",d))end;I[a]=nil;return true end
function F.trustKnown(a,b,c)return F.setLevel(a,b,E.KNOWN,c)end
function F.trustFull(a,b,c)return F.setLevel(a,b,E.TRUSTED,c)end
function F.block(a,b,c)return F.setLevel(a,b,E.BLOCKED,c)end
function F.revoke(a,b,c)return F.setLevel(a,b,E.UNKNOWN,c)end
function F.forget(c,a,b)if not a then return false,"No address"end;b=b or 0;if b<2 then return false,
"Admin privileges required"end;a=K(a)if not G[a]then
return false,"Peer not found"end;G[a]=nil;I[a]=nil;O()if H then
H.info("trust","Peer forgotten: "..a:sub(1,8).." (by "..c..
")")end;return true end
local function U(b,a,c)a=tonumber(a)or 0;if a<2 then
return false,"Admin privileges required to "..c end;if not b or b==""then
return false,"Actor required to "..c end;return true end
function F.setSecret(b,a,c,d)local e,f=U(b,d,"set peer secret")if not e then return false,f end
a=K(a)if not G[a]then return false,"Unknown peer"end
if
G[a].level<E.TRUSTED then return false,"Peer must be TRUSTED for shared secrets"end;G[a].sharedSecret=c;O()
pcall(function()local g=require("kernel.net")if
g and g.invalidateVerification then g.invalidateVerification(a)end end)if H then
H.info("trust","Shared secret "..
(c and"set"or"cleared").." for "..a:sub(1,8).."... (by "..
tostring(b)..")")end;return true end
function F.getSecret(b,a,c)local e,f=U(b,c,"read peer secret")if not e then return nil,f end
a=K(a)local d=G[a]if not d then return nil,"Unknown peer"end;if H then
H.info("trust","Secret read for "..
a:sub(1,8).."... (by "..tostring(b)..")")end;return d.sharedSecret end
function F.generateSecret(a,c,b)local e,f=U(a,b,"generate peer secret")
if not e then return nil,f end;if not M then return nil,"Crypto not available"end
local d=M.salt(32)local g,h=F.setSecret(a,c,d,b)if not g then return nil,h end;return d end;local R=nil;local function X()if R then return R end;local a,b=pcall(require,"kernel.x25519")
if a then R=b end;return R end
local function Y()
if J then return J end;local a=X()if not(a and M and M.salt)then return nil end
local d,b=pcall(a.generatePrivateKey,M.salt)if not(d and b)then return nil end;local e,c=pcall(a.publicKey,b)if not
(e and c)then return nil end;J={priv=b,pub=c}O()return J end
function F.getMyDhPublicKey()local a=Y()return a and a.pub or nil end
function T(a)local b=G[a]
if not b or b.sharedSecret or not b.dhPub then return end;if(b.level or 0)<E.TRUSTED then return end;local d=Y()local e=X()if not
(d and e)then return end
local f,c,g=pcall(e.sharedSecret,d.priv,b.dhPub)
if f and c then b.sharedSecret=c;O()if H then
H.info("trust","Diffie-Hellman secret established automatically with "..
a:sub(1,8).."...")end elseif H then
H.warn("trust","DH with "..
a:sub(1,8)..
"... did not produce a secret (falling back to manual pairing): "..tostring(f and g or c))end end
function F.noteDhPublicKey(a,b)if type(b)~=Q or#b~=32 then return end;a=K(a)
local c=a and G[a]if not c then return end;c.dhPub=b;T(a)end;local P=nil;local Z=false
function F._internalGetSecret(a,b)if not P or b~=P then return nil end;a=K(a)
local c=G[a]return c and c.sharedSecret or nil end
function F.getBootstrapToken()if Z then return nil end
if not P then if not M then return nil end;P=M.salt(64)end;Z=true;return P end;local function _()local a=L.uptime()
for b,c in pairs(I)do if a-c.time>ac then I[b]=nil end end end
function F.addPendingRequest(a,b)b=W(b)_()if I[a]then
I[a].time=L.uptime()I[a].hostname=b;return end;local c=0
for d in pairs(I)do c=c+1 end
if c>=ad then local d,e=nil,math.huge
for g,f in pairs(I)do if f.time<e then d=g;e=f.time end end;if d then I[d]=nil end end;I[a]={time=L.uptime(),hostname=b}if H then
H.info("trust","Trust request from "..a:sub(1,8).." (".. (b or
"unknown")..")")end end;function F.getPendingRequests()_()local a={}
for c,b in pairs(I)do a[c]={time=b.time,hostname=b.hostname}end;return a end;function F.clearPendingRequest(a)I[a]=
nil end
function F.listPeers()local a={}
for c,b in pairs(G)do
a[#a+1]={address=c,level=b.level,hostname=b.hostname,firstSeen=b.firstSeen,lastSeen=b.lastSeen,hasSecret=
b.sharedSecret~=nil,notes=b.notes}end
table.sort(a,function(c,d)
if c.level~=d.level then return c.level>d.level end
return(c.lastSeen or 0)> (d.lastSeen or 0)end)return a end
function F.stats()local a={blocked=0,unknown=0,known=0,trusted=0}
for c,b in pairs(G)do local d=b.level
if
d==E.BLOCKED then a.blocked=a.blocked+1 elseif d==E.KNOWN then a.known=a.known+1 elseif d==E.TRUSTED then a.trusted=
a.trusted+1 else a.unknown=a.unknown+1 end end;return a end
function F.levelName(a)
if a==E.BLOCKED then return"BLOCKED"elseif a==E.UNKNOWN then return"UNKNOWN"elseif a==E.KNOWN then return"KNOWN"elseif a==
E.TRUSTED then return"TRUSTED"else return"?"end end;F.resolveAddress=K;F.LEVEL=E;return F