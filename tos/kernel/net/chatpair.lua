local K="string"local M=require("computer")local G={}local H=nil;local I=nil;local J=nil
local N=nil;local O=nil;local L=nil;local D=nil;local F="chatpair"local S=300
local T="ABCDEFGHJKMNPQRSTUVWXYZ23456789"local U=24;local V="tos-chat-pair-v1"local E=nil;local W="root"local X=3
function G.init(a)H=a and a.crypto or
require("kernel.crypto")I=a and a.protocol or
require("kernel.net.protocol")
J=a and a.trust or nil;D=a and a.log or nil;N=a and a.net or nil end;local function Y()if N then return N end;local a,b=pcall(require,"kernel.net")if a then N=b end
return N end
local ad="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local function ae()local a,b={},#T
while#a<U do local c=H.salt(64)
for d=1,#c do if#a>=U then break end;local g=c:sub(d,d)
local f=ad:find(g,1,true)local e;if f then e=((f-1)%b)+1 else local h=c:byte(d)
if h<248 then e=(h%b)+1 end end
if e then a[#a+1]=T:sub(e,e)end end end;return table.concat(a)end;local function Z(a)return H.hashPassword(a,V)end
local function P(a,b,c,d)local e,f=tostring(b or""),tostring(
c or"")if e>f then e,f=f,e end;return
H.hmac(a,e.."|"..f.."|"..
tostring(d or 0))end;local Q=2
local function _()return
(H.salt(16):gsub(".",function(a)
return string.format("%02x",a:byte())end))end
local function R(a,b,c,d,e,f)local g,h=tostring(b or""),tostring(c or"")if g>h then g,h=h,g end;return
H.hmac(a,table.concat({"v2",g,h,tostring(
d or 0),tostring(e or""),tostring(f or"")},"|"))end
local function aa(a,b,c,d,e)local f,g=tostring(b or""),tostring(c or"")if f>g then f,g=g,f end;return
H.hmac(a,table.concat({V,"link",f,g,tostring(d),tostring(e)},"|"))end;local function ab(a)return
type(a)==K and#a>=16 and#a<=64 and not a:find("[^%x]")end
local function ac(a)if
not J then return false,"trust manager unavailable"end
local b=J.getLevel(a)if
b< (J.LEVEL and J.LEVEL.TRUSTED or 2)then
return false,"peer must be TRUSTED before pairing (run 'net trust <addr> full' first)"end;return true end
function G.startWindow()if not H then return nil,"chatpair not initialized"end
local b=M.uptime()local a=ae()
E={code=a,secret=Z(a),opens_at=b,expires_at=b+S,paired_with={}}if D then
D.info(F,"pairing window opened ("..S.."s)")end;return a,E.expires_at end;function G.closeWindow()E=nil
if D then D.info(F,"pairing window closed")end end
function G.windowOpen()if not E then return false end;if
M.uptime()>E.expires_at then E=nil;return false end;return true end;function G.windowInfo()if not G.windowOpen()then return nil end
return{expires_in=E.expires_at-M.uptime(),paired=
#E.paired_with}end;function G.setMeshSend(a)
O=a end
function G.onMeshPair(c,b,a)
if type(b)~="table"or type(a)~=K then return end
if c=="init"then
G.onPairInit({payload=b},a,function(d)
if O then pcall(O,a,"confirm",d.payload)end end)elseif c=="confirm"and L and L.peer==a then L.fn(b)end end
function G.onPairInit(c,a,b)
if not G.windowOpen()then if D then
D.warn(F,"pair_init from "..tostring(a):sub(1,8)..
" but no window open")end;return end;local d=c.payload or{}
if
type(d.mac)~=K or type(d.ts)~="number"then if D then
D.warn(F,"malformed pair_init from "..tostring(a):sub(1,8))end;return end;for s,r in ipairs(E.paired_with)do
if r==a then if D then
D.warn(F,"duplicate pair_init from "..tostring(a):sub(1,8))end;return end end
local l,m=ac(a)
if not l then if D then
D.warn(F,"pair_init from "..
tostring(a):sub(1,8).." refused: "..m)end;return end;local e=Y()
local f=e and e.getAddress and e.getAddress()or nil
if not f then if D then
D.warn(F,"pair_init: no local address; dropping")end;return end;local n=P(E.secret,f,a,d.ts)
if not H.ctEquals(n,d.mac)then if D then
D.warn(F,
"pair_init MAC mismatch from "..tostring(a):sub(1,8))end;return end;local g=(d.v==Q)
if
g and not
(ab(d.nonce)and type(d.mac2)==K and H.ctEquals(R(E.secret,f,a,d.ts,d.nonce,
nil),d.mac2))then if D then
D.warn(F,"pair_init v2 MAC mismatch from "..tostring(a):sub(1,8))end;return end;local i=g and _()or nil
local o=g and aa(E.secret,f,a,d.nonce,i)or E.secret;local p,q=J.setSecret(W,a,o,X)
if not p then if D then
D.warn(F,"setSecret failed for "..
tostring(a):sub(1,8)..": "..tostring(q))end;return end;E.paired_with[#E.paired_with+1]=a
if D then
D.info(F,"paired with "..
tostring(a):sub(1,12).."...")
if not g then
D.warn(F,tostring(a):sub(1,8)..
" paired with the older (v1) handshake: "..
"it shares this window's secret with any other v1 peer paired in it. ".."Update it and pair again.")end end;local j=M.uptime()local h={mac=P(E.secret,f,a,j),ts=j}
if g then h.v=Q
h.nonce=i;h.mac2=R(E.secret,f,a,j,d.nonce,i)end
local k=I.makePacket(I.TYPE.CHAT_PAIR_CONFIRM,h,{to=a})
if b then pcall(b,k)elseif e and e.send then pcall(e.send,a,k)end end
function G.connect(a,b,c)
if not H or not I or not J then return false,"chatpair not initialized"end
if type(a)~=K or a==""then return false,"peer address required"end
if type(b)~=K or#b<4 then return false,"pairing code required"end;local o,p=ac(a)if not o then return false,p end;local e=Y()if not e or not e.send or
not e.on or not e.off then
return false,"net module unavailable"end
local q=b:upper():gsub("[^%w]","")local f=Z(q)local j=M.uptime()
local g=e.getAddress and e.getAddress()or nil;if not g then return false,"no local address"end;local h,d=false,nil
local m=e.onceFrom(I.TYPE.CHAT_PAIR_CONFIRM,a,function(v)if
not h then d=v.payload;h=true end end)
L={peer=a,fn=function(v)if not h then d=v;h=true end end}local i=_()
local n=I.makePacket(I.TYPE.CHAT_PAIR_INIT,{mac=P(f,g,a,j),ts=j,v=Q,nonce=i,mac2=R(f,g,a,j,i,nil)},{to=a})local r,s=e.send(a,n)local k=false;if O then
k=(pcall(O,a,"init",n.payload))end
if not r and not k then
e.off(I.TYPE.CHAT_PAIR_CONFIRM,m)L=nil;return false,"send failed: "..tostring(s)end
e.waitFor(function()return h end,c or(k and 30 or 10))e.off(I.TYPE.CHAT_PAIR_CONFIRM,m)L=nil
if not h then return false,
"no confirmation (wrong code, window expired, or peer offline)"end
if type(d)~="table"or type(d.mac)~=K or
type(d.ts)~="number"then return false,"malformed confirm"end;local l
if d.v==Q then
if not
(ab(d.nonce)and type(d.mac2)==K and
H.ctEquals(R(f,g,a,d.ts,i,d.nonce),d.mac2))then
return false,"confirm MAC mismatch (wrong code or attacker on wire)"end;l=aa(f,g,a,i,d.nonce)else local v=P(f,g,a,d.ts)
if
not H.ctEquals(v,d.mac)then return false,"confirm MAC mismatch (wrong code or attacker on wire)"end;l=f
if D then
D.warn(F,a:sub(1,8).." answered with the older (v1) handshake; "..
"the link uses the pairing window's shared secret. Update it and pair again.")end end;local t,u=J.setSecret(W,a,l,X)if not t then return false,
"local setSecret failed: "..tostring(u)end
if D then D.info(F,"paired with "..
a:sub(1,12).."...")end;return true end;return G