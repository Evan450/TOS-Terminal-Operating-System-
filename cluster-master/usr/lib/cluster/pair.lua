local w=require("computer")local x=require("kernel.crypto")
local y=require("kernel.net.protocol")local E=require("kernel.net")local s
do
local b,a=pcall(require,"kernel.log")
if not(b and a and a.info)then b,a=pcall(require,"log")end;if b and a and a.info then s=a else
s={info=function()end,warn=function()end,error=function()end}end end;local u="cluster.pair"local t={}local z=300;local A="ABCDEFGHJKMNPQRSTUVWXYZ23456789"local B=24
local r=nil;local v=nil;local C="root"
function t.init(a)v=a and a.trust or nil end;local F="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local function G()local a={}
local b=#A
while#a<B do local c=x.salt(64)
for d=1,#c do if#a>=B then break end
local f=F:find(c:sub(d,d),1,true)local e;if f then e=((f-1)%b)+1 else local g=c:byte(d)
if g<248 then e=(g%b)+1 end end
if e then a[#a+1]=A:sub(e,e)end end end;return table.concat(a)end
local function H(a)return x.hashPassword(a,"tos-cluster-pair-v1")end;local function D(a,b,c)return
x.hmac(a,tostring(b or"").."|"..tostring(c or 0))end
function t.startWindow()
local b=w.uptime()local a=G()
r={code=a,secret=H(a),opens_at=b,expires_at=b+z,paired_with={}}
s.info(u,"pairing window opened ("..z.."s)")return a,r.expires_at end
function t.closeWindow()r=nil;s.info(u,"pairing window closed")end;function t.windowOpen()if not r then return false end
if w.uptime()>r.expires_at then r=nil;return false end;return true end;function t.windowInfo()if
not t.windowOpen()then return nil end
return{expires_in=r.expires_at-w.uptime(),paired=
#r.paired_with}end
function t.onPairInit(b,a)if not
t.windowOpen()then
s.warn(u,"pair_init from "..
tostring(a):sub(1,8).." but no window open")return end
local c=b.payload or{}if type(c.mac)~="string"or type(c.ts)~="number"then
s.warn(u,
"malformed pair_init from "..tostring(a):sub(1,8))return end
for h,g in
ipairs(r.paired_with)do if g==a then
s.warn(u,"duplicate pair_init from "..tostring(a):sub(1,8))return end end;local e=D(r.secret,a,c.ts)if not x.ctEquals(e,c.mac)then
s.warn(u,
"pair_init MAC mismatch from "..tostring(a):sub(1,8))return end
if v then local g=3
pcall(v.setLevel,C,a,v.LEVEL.TRUSTED,g)pcall(v.setSecret,C,a,r.secret,g)end;r.paired_with[#r.paired_with+1]=a
s.info(u,"paired with "..
tostring(a):sub(1,12).."...")local d=w.uptime()
local f=y.makePacket(y.TYPE.CLUSTER_PAIR_CONFIRM,{mac=D(r.secret,a,d),ts=d},{to=a})pcall(E.send,a,f)end;return t