local ad,R="Unknown peer","string"local N=require("computer")
local _=require("kernel.serialize")local H={}local G={BLOCKED=-1,UNKNOWN=0,KNOWN=1,TRUSTED=2}
local ae={[G.BLOCKED]={},[G.UNKNOWN]={ping=true,pong=true,cl_pair_init=true,cl_pair_conf=true},[G.KNOWN]={ping=true,pong=true,hello=true,hello_ack=true,info_req=true,info_res=true,trust_req=true,trust_ack=true,trust_deny=true,cl_pair_init=true,cl_pair_conf=true},[G.TRUSTED]={ping=true,pong=true,hello=true,hello_ack=true,info_req=true,info_res=true,trust_req=true,trust_ack=true,trust_deny=true,trust_rev=true,cl_pair_init=true,cl_pair_conf=true,msg=true,msg_ack=true,file_req=true,file_res=true,file_deny=true,challenge=true,chall_res=true,remote_exec=true,remote_res=true,cl_reg=true,cl_reg_ack=true,cl_hb=true,cl_asn=true,cl_asn_ack=true,cl_res=true,cl_res_chunk=true,cl_cancel=true,cl_drain=true,cl_st_req=true,cl_st_res=true,rly_fwd=true,rly_fail=true,peer_st=true,st_put=true,st_put_ack=true,st_put_chunk=true,st_ext=true,st_rel=true,st_list=true,st_list_res=true,st_err=true,ch_pair_init=true,ch_pair_conf=true,mesh=true,mesh_ack=true,nfs_req=true,nfs_res=true}}local I={}local W="/etc/trust.dat"local L=nil;local X;local T=nil;local af=64;local K={}local ag=300;local ah=32
local P=nil;local O=nil;local J=nil;local ai=nil
local function Q()if not P then return false end;local a={}
for d,c in pairs(I)do
a[d]={level=c.level,hostname=c.hostname,firstSeen=c.firstSeen,lastSeen=c.lastSeen,sharedSecret=c.sharedSecret,dhPub=c.dhPub,secretDhPub=c.secretDhPub,dhKeyChanged=c.dhKeyChanged,notes=c.notes}end;local b={peers=a,dh=L}return
(P.writeFileAtomic or P.writeFile)(W,_.encode(b))end
local function aa(a)if type(a)~=R then return nil end
a=a:gsub("%c",""):sub(1,32)if a==""then return nil end;return a end
local aj={[G.BLOCKED]=true,[G.UNKNOWN]=true,[G.KNOWN]=true,[G.TRUSTED]=true}
local function ak()if not P or not P.exists(W)then return end
local b,c=P.readFile(W)if not b then return end;local a=_.decode(b)
if type(a)~="table"then return end
if a.peers~=nil or a.dh~=nil then I=a.peers or{}L=a.dh
if not
(type(L)=="table"and
type(L.priv)==R and#L.priv==32 and type(L.pub)==
R and#L.pub==32)then L=nil end else I=a end
for e,d in pairs(I)do if not aj[d.level]then d.level=G.UNKNOWN end
d.hostname=aa(d.hostname)d.firstSeen=d.firstSeen or 0;d.lastSeen=d.lastSeen or 0
if
type(d.dhPub)~=R or#d.dhPub~=32 then d.dhPub=nil end;if
type(d.secretDhPub)~=R or#d.secretDhPub~=32 then d.secretDhPub=nil end;d.dhKeyChanged=
d.dhKeyChanged==true or nil end end
function H.init(a)P=a.fs;O=a.crypto;J=a.log;ai=a.config;ak()local b=0;for c in pairs(I)do b=b+1 end;if J then
J.info("trust",
"Trust manager initialized ("..b.." known peers)")end;return true end
local function M(a)if not a then return nil end;if I[a]then return a end;local b=nil
for c in pairs(I)do if c:sub(1,#a)==a then if
b then return nil end;b=c end end;return b end
function H.getLevel(a)if not a then return G.UNKNOWN end;a=M(a)local b=I[a]
if not b then return G.UNKNOWN end;return b.level end
function H.getPeer(a)if not a then return nil end;a=M(a)return I[a]end
function H.isAllowed(a,b)local c=H.getLevel(a)if c==G.BLOCKED then return false end
local d=ae[c]if not d then return false end;return d[b]==true end
function H.seen(a)
if not I[a]then local b=0
for d,c in pairs(I)do if c.level==G.UNKNOWN then b=b+1 end end
if b>=af then local c,d=nil,math.huge;for f,e in pairs(I)do
if e.level==G.UNKNOWN and
(e.lastSeen or 0)<d then c=f;d=e.lastSeen or 0 end end
if c then I[c]=nil;if J then
J.debug("trust",
"Evicted old unknown peer: "..c:sub(1,8))end end end
I[a]={level=G.UNKNOWN,hostname=nil,firstSeen=N.uptime(),lastSeen=N.uptime()}else I[a].lastSeen=N.uptime()end end
function H.setLevel(d,a,b,c)c=c or 0
if c<2 then return false,"Admin privileges required to modify trust"end
local g={[G.BLOCKED]=true,[G.UNKNOWN]=true,[G.KNOWN]=true,[G.TRUSTED]=true}
if not g[b]then return false,"Invalid trust level: "..tostring(b)end;local f=M(a)
if f then a=f else
local h=type(a)==R and#a==36 and
a:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil;if not h then
return false,"Ambiguous or invalid address: "..tostring(a)end end
if not I[a]then I[a]={firstSeen=N.uptime(),lastSeen=N.uptime()}end;local e=I[a].level or G.UNKNOWN;I[a].level=b;if b==G.TRUSTED and
e~=G.TRUSTED then X(a)end;Q()
if J then
local h={[-1]="BLOCKED",[0]="UNKNOWN",[1]="KNOWN",[2]="TRUSTED"}
J.info("trust",string.format("Trust for %s: %s -> %s (by %s)",a:sub(1,8).."...",h[e]or"?",h[b]or"?",d))end;K[a]=nil
if b>=G.KNOWN and b>e and T then pcall(T,a)end;return true end;function H.setHelloSender(a)if T or type(a)~="function"then return false end
T=a;return true end;function H.trustKnown(a,b,c)return
H.setLevel(a,b,G.KNOWN,c)end;function H.trustFull(a,b,c)return
H.setLevel(a,b,G.TRUSTED,c)end;function H.block(a,b,c)return
H.setLevel(a,b,G.BLOCKED,c)end;function H.revoke(a,b,c)return
H.setLevel(a,b,G.UNKNOWN,c)end
function H.forget(c,a,b)if not a then
return false,"No address"end;b=b or 0
if b<2 then return false,"Admin privileges required"end;a=M(a)if not I[a]then return false,"Peer not found"end;I[a]=nil
K[a]=nil;Q()if J then
J.info("trust","Peer forgotten: "..a:sub(1,8).." (by "..c..")")end;return true end
local function U(b,a,c)a=tonumber(a)or 0;if a<2 then
return false,"Admin privileges required to "..c end;if not b or b==""then
return false,"Actor required to "..c end;return true end
function H.setSecret(b,a,c,d)local e,f=U(b,d,"set peer secret")if not e then return false,f end
a=M(a)if not I[a]then return false,ad end;if I[a].level<G.TRUSTED then return false,
"Peer must be TRUSTED for shared secrets"end
I[a].sharedSecret=c;I[a].secretDhPub=nil;I[a].dhKeyChanged=nil;Q()
pcall(function()
local g=require("kernel.net")
if g and g.invalidateVerification then g.invalidateVerification(a)end end)if J then
J.info("trust","Shared secret "..
(c and"set"or"cleared").." for "..a:sub(1,8).."... (by "..
tostring(b)..")")end;return true end
function H.getSecret(b,a,c)local e,f=U(b,c,"read peer secret")if not e then return nil,f end
a=M(a)local d=I[a]if not d then return nil,ad end;if J then
J.info("trust","Secret read for "..a:sub(1,8).."... (by "..
tostring(b)..")")end;return d.sharedSecret end
function H.generateSecret(a,c,b)local e,f=U(a,b,"generate peer secret")
if not e then return nil,f end;if not O then return nil,"Crypto not available"end
local d=O.salt(32)local g,h=H.setSecret(a,c,d,b)if not g then return nil,h end;return d end;local V=nil;local function Y()if V then return V end;local a,b=pcall(require,"kernel.x25519")
if a then V=b end;return V end
local function Z()
if L then return L end;local a=Y()if not(a and O and O.salt)then return nil end
local d,b=pcall(a.generatePrivateKey,O.salt)if not(d and b)then return nil end;local e,c=pcall(a.publicKey,b)if not
(e and c)then return nil end;L={priv=b,pub=c}Q()return L end
function H.getMyDhPublicKey()local a=Z()return a and a.pub or nil end
function X(a)local b=I[a]
if not b or b.sharedSecret or not b.dhPub then return end;if(b.level or 0)<G.TRUSTED then return end;local d=Z()local e=Y()if not
(d and e)then return end
local f,c,g=pcall(e.sharedSecret,d.priv,b.dhPub)
if f and c then b.sharedSecret=c;b.secretDhPub=b.dhPub;b.dhKeyChanged=nil;Q()if J then
J.info("trust",
"Diffie-Hellman secret established automatically with "..a:sub(1,8).."...")end elseif J then
J.warn("trust","DH with "..
a:sub(1,8)..
"... did not produce a secret (falling back to manual pairing): "..tostring(f and g or c))end end
function H.noteDhPublicKey(a,b)if type(b)~=R or#b~=32 then return end;a=M(a)
local c=a and I[a]if not c then return end;local d=c.dhPub;c.dhPub=b
if c.sharedSecret and d and d~=b then
if
c.secretDhPub==b then c.dhKeyChanged=nil elseif not c.dhKeyChanged then c.dhKeyChanged=true
if J then
J.warn("trust","Peer "..

a:sub(1,8)..
"... has a new identity key"..
" (reinstalled?). The secret we share "..

(
c.secretDhPub and"came from its old key and no longer matches"or"was set by hand and may be gone on its side")..
": 'net trust rekey "..a:sub(1,8).."' to accept the new key.")end end;Q()return end;X(a)end
function H.rekey(b,a,c)local i,j=U(b,c,"re-derive peer secret")
if not i then return false,j end;a=M(a)local d=a and I[a]if not d then return false,ad end
if(d.level or 0)<
G.TRUSTED then return false,"Peer must be TRUSTED for shared secrets"end
if not d.dhPub then return false,"No key from this peer yet (it has not said hello)"end;local f,g=Z(),Y()if not(f and g)then
return false,"Diffie-Hellman is not available on this machine"end
local h,e,k=pcall(g.sharedSecret,f.priv,d.dhPub)if not(h and e)then return false,
"Key exchange failed: "..tostring(h and k or e)end
local l,m=H.setSecret(b,a,e,c)if not l then return false,m end;d.secretDhPub=d.dhPub;Q()return true end;local S=nil;local ab=false
function H._internalGetSecret(a,b)if not S or b~=S then return nil end;a=M(a)
local c=I[a]return c and c.sharedSecret or nil end
function H.getBootstrapToken()if ab then return nil end
if not S then if not O then return nil end;S=O.salt(64)end;ab=true;return S end;local function ac()local a=N.uptime()
for b,c in pairs(K)do if a-c.time>ag then K[b]=nil end end end
function H.addPendingRequest(a,b)b=aa(b)ac()
if
K[a]then K[a].time=N.uptime()K[a].hostname=b;return end;local c=0;for d in pairs(K)do c=c+1 end
if c>=ah then local d,e=nil,math.huge;for g,f in pairs(K)do if f.time<e then d=g
e=f.time end end;if d then K[d]=nil end end;K[a]={time=N.uptime(),hostname=b}if J then
J.info("trust","Trust request from "..a:sub(1,8).." (".. (b or
"unknown")..")")end end
function H.getPendingRequests()ac()local a={}for c,b in pairs(K)do
a[c]={time=b.time,hostname=b.hostname}end;return a end;function H.clearPendingRequest(a)K[a]=nil end
function H.listPeers()local a={}
for c,b in pairs(I)do
a[#a+1]={address=c,level=b.level,hostname=b.hostname,firstSeen=b.firstSeen,lastSeen=b.lastSeen,hasSecret=
b.sharedSecret~=nil,keyChanged=b.dhKeyChanged==true,notes=b.notes}end
table.sort(a,function(c,d)
if c.level~=d.level then return c.level>d.level end
return(c.lastSeen or 0)> (d.lastSeen or 0)end)return a end
function H.stats()local a={blocked=0,unknown=0,known=0,trusted=0}
for c,b in pairs(I)do local d=b.level
if
d==G.BLOCKED then a.blocked=a.blocked+1 elseif d==G.KNOWN then a.known=a.known+1 elseif d==G.TRUSTED then a.trusted=
a.trusted+1 else a.unknown=a.unknown+1 end end;return a end
function H.levelName(a)
if a==G.BLOCKED then return"BLOCKED"elseif a==G.UNKNOWN then return"UNKNOWN"elseif a==G.KNOWN then return"KNOWN"elseif a==
G.TRUSTED then return"TRUSTED"else return"?"end end;H.resolveAddress=M;H.LEVEL=G;return H