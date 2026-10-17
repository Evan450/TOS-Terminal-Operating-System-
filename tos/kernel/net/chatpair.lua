local I="string"local J=require("computer")local F={}local E=nil;local G=nil;local H=nil
local K=nil;local B=nil;local D="chatpair"local O=300;local P="ABCDEFGHJKMNPQRSTUVWXYZ23456789"local Q=24
local R="tos-chat-pair-v1"local C=nil;local S="root"local T=3
function F.init(a)
E=a and a.crypto or require("kernel.crypto")
G=a and a.protocol or require("kernel.net.protocol")H=a and a.trust or nil;B=a and a.log or nil
K=a and a.net or nil end;local function U()if K then return K end;local a,b=pcall(require,"kernel.net")if a then K=b end
return K end
local _="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local function aa()local a,b={},#P
while#a<Q do local c=E.salt(64)
for d=1,#c do if#a>=Q then break end;local g=c:sub(d,d)
local f=_:find(g,1,true)local e;if f then e=((f-1)%b)+1 else local h=c:byte(d)
if h<248 then e=(h%b)+1 end end
if e then a[#a+1]=P:sub(e,e)end end end;return table.concat(a)end;local function V(a)return E.hashPassword(a,R)end
local function L(a,b,c,d)local e,f=tostring(b or""),tostring(
c or"")if e>f then e,f=f,e end;return
E.hmac(a,e.."|"..f.."|"..
tostring(d or 0))end;local M=2
local function W()return
(E.salt(16):gsub(".",function(a)
return string.format("%02x",a:byte())end))end
local function N(a,b,c,d,e,f)local g,h=tostring(b or""),tostring(c or"")if g>h then g,h=h,g end;return
E.hmac(a,table.concat({"v2",g,h,tostring(
d or 0),tostring(e or""),tostring(f or"")},"|"))end
local function X(a,b,c,d,e)local f,g=tostring(b or""),tostring(c or"")if f>g then f,g=g,f end;return
E.hmac(a,table.concat({R,"link",f,g,tostring(d),tostring(e)},"|"))end;local function Y(a)return
type(a)==I and#a>=16 and#a<=64 and not a:find("[^%x]")end
local function Z(a)if not H then return
false,"trust manager unavailable"end
local b=H.getLevel(a)if
b< (H.LEVEL and H.LEVEL.TRUSTED or 2)then
return false,"peer must be TRUSTED before pairing (run 'net trust <addr> full' first)"end;return true end
function F.startWindow()if not E then return nil,"chatpair not initialized"end
local b=J.uptime()local a=aa()
C={code=a,secret=V(a),opens_at=b,expires_at=b+O,paired_with={}}if B then
B.info(D,"pairing window opened ("..O.."s)")end;return a,C.expires_at end;function F.closeWindow()C=nil
if B then B.info(D,"pairing window closed")end end
function F.windowOpen()if not C then return false end;if
J.uptime()>C.expires_at then C=nil;return false end;return true end;function F.windowInfo()if not F.windowOpen()then return nil end
return{expires_in=C.expires_at-J.uptime(),paired=
#C.paired_with}end
function F.onPairInit(b,a)
if not
F.windowOpen()then if B then
B.warn(D,"pair_init from "..
tostring(a):sub(1,8).." but no window open")end;return end;local c=b.payload or{}
if
type(c.mac)~=I or type(c.ts)~="number"then if B then
B.warn(D,"malformed pair_init from "..tostring(a):sub(1,8))end;return end;for r,q in ipairs(C.paired_with)do
if q==a then if B then
B.warn(D,"duplicate pair_init from "..tostring(a):sub(1,8))end;return end end
local j,k=Z(a)
if not j then if B then
B.warn(D,"pair_init from "..
tostring(a):sub(1,8).." refused: "..k)end;return end;local d=U()
local e=d and d.getAddress and d.getAddress()or nil
if not e then if B then
B.warn(D,"pair_init: no local address; dropping")end;return end;local l=L(C.secret,e,a,c.ts)
if not E.ctEquals(l,c.mac)then if B then
B.warn(D,
"pair_init MAC mismatch from "..tostring(a):sub(1,8))end;return end;local f=(c.v==M)
if
f and not
(Y(c.nonce)and type(c.mac2)==I and E.ctEquals(N(C.secret,e,a,c.ts,c.nonce,
nil),c.mac2))then if B then
B.warn(D,"pair_init v2 MAC mismatch from "..tostring(a):sub(1,8))end;return end;local h=f and W()or nil
local m=f and X(C.secret,e,a,c.nonce,h)or C.secret;local n,o=H.setSecret(S,a,m,T)
if not n then if B then
B.warn(D,"setSecret failed for "..
tostring(a):sub(1,8)..": "..tostring(o))end;return end;C.paired_with[#C.paired_with+1]=a
if B then
B.info(D,"paired with "..
tostring(a):sub(1,12).."...")
if not f then
B.warn(D,tostring(a):sub(1,8)..
" paired with the older (v1) handshake: "..
"it shares this window's secret with any other v1 peer paired in it. ".."Update it and pair again.")end end;local i=J.uptime()local g={mac=L(C.secret,e,a,i),ts=i}
if f then g.v=M
g.nonce=h;g.mac2=N(C.secret,e,a,i,c.nonce,h)end
local p=G.makePacket(G.TYPE.CHAT_PAIR_CONFIRM,g,{to=a})if d and d.send then pcall(d.send,a,p)end end
function F.connect(a,b,c)
if not E or not G or not H then return false,"chatpair not initialized"end
if type(a)~=I or a==""then return false,"peer address required"end
if type(b)~=I or#b<4 then return false,"pairing code required"end;local m,n=Z(a)if not m then return false,n end;local e=U()
if
not e or not e.send or not e.on or not e.off then return false,"net module unavailable"end;local o=b:upper():gsub("[^%w]","")local f=V(o)
local i=J.uptime()
local g=e.getAddress and e.getAddress()or nil;if not g then return false,"no local address"end;local j,d=false,nil
local l=e.onceFrom(G.TYPE.CHAT_PAIR_CONFIRM,a,function(u)
d=u.payload;j=true end)local h=W()
local p=G.makePacket(G.TYPE.CHAT_PAIR_INIT,{mac=L(f,g,a,i),ts=i,v=M,nonce=h,mac2=N(f,g,a,i,h,nil)},{to=a})local q,r=e.send(a,p)
if not q then
e.off(G.TYPE.CHAT_PAIR_CONFIRM,l)return false,"send failed: "..tostring(r)end;e.waitFor(function()return j end,c or 10)
e.off(G.TYPE.CHAT_PAIR_CONFIRM,l)
if not j then return false,"no confirmation (wrong code, window expired, or peer offline)"end
if type(d)~="table"or type(d.mac)~=I or
type(d.ts)~="number"then return false,"malformed confirm"end;local k
if d.v==M then
if not
(Y(d.nonce)and type(d.mac2)==I and
E.ctEquals(N(f,g,a,d.ts,h,d.nonce),d.mac2))then
return false,"confirm MAC mismatch (wrong code or attacker on wire)"end;k=X(f,g,a,h,d.nonce)else local u=L(f,g,a,d.ts)
if
not E.ctEquals(u,d.mac)then return false,"confirm MAC mismatch (wrong code or attacker on wire)"end;k=f
if B then
B.warn(D,a:sub(1,8).." answered with the older (v1) handshake; "..
"the link uses the pairing window's shared secret. Update it and pair again.")end end;local s,t=H.setSecret(S,a,k,T)if not s then return false,
"local setSecret failed: "..tostring(t)end
if B then B.info(D,"paired with "..
a:sub(1,12).."...")end;return true end;return F