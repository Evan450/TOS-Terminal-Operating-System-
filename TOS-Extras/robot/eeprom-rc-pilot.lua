-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Robot EEPROM — RC Pilot                             ║
-- ║                                                          ║
-- ║  Burnable payload for OC robots and Computronics drones. ║
-- ║  Pairs with the `rc-pilot` add-on: a TOS host turns      ║
-- ║  WASD/arrow keys into frames on wireless port 7777 and   ║
-- ║  this loop turns them into robot.* / drone.* calls.      ║
-- ║                                                          ║
-- ║  Wire format (a Lua-literal string, parsed by pattern):  ║
-- ║    {magic="RCPILOT1",op="..",arg=n,nonce="hex",mac="hex"}║
-- ║    mac = HMAC-SHA256(secret, op.."|"..arg.."|"..nonce)   ║
-- ║  ops: move:f/b/l/r turn:l/r up down use:f swing:f        ║
-- ║       place:f select(arg=slot) stop ping (-> pong)       ║
-- ║                                                          ║
-- ║  Security: constant-time MAC check; a 64-nonce replay    ║
-- ║  window; no secret configured means NOTHING moves. Seed  ║
-- ║  the secret (16+ chars) with  eeprom.setData("...").     ║
-- ║                                                          ║
-- ║  SIZE IS THE CONSTRAINT. An EEPROM is 4096 bytes and     ║
-- ║  `flash` refuses anything larger; the previous version   ║
-- ║  was 6.9 KB with its comments stripped and could not be  ║
-- ║  burned at all. Everything below is written for the      ║
-- ║  stripped size (build/strip.lua --minify), which         ║
-- ║  test_rc_pilot.lua pins under 4096. Burn the STRIPPED    ║
-- ║  file: comments do not ship, but short names do.         ║
-- ╚══════════════════════════════════════════════════════════╝
local C,M=component,computer
local function f(t)for a in C.list(t)do return C.proxy(a)end end
local m,r,d,e=f("modem"),f("robot"),f("drone"),f("eeprom")
if not m then M.beep(200,1.5)while true do M.pullSignal(60)end end
-- Secret from the EEPROM data field; too short means unset, fail closed.
local S=e and e.getData and e.getData()
if type(S)~="string"or #S<16 then S=nil end
-- SHA-256 round constants as one hex string (half the bytes of a table).
local KS="428a2f9871374491b5c0fbcfe9b5dba53956c25b59f111f1923f82a4ab1c5ed5d807aa9812835b01243185be550c7dc372be5d7480deb1fe9bdc06a7c19bf174e49b69c1efbe47860fc19dc6240ca1cc2de92c6f4a7484aa5cb0a9dc76f988da983e5152a831c66db00327c8bf597fc7c6e00bf3d5a7914706ca63511429296727b70a852e1b21384d2c6dfc53380d13650a7354766a0abb81c2c92e92722c85a2bfe8a1a81a664bc24b8b70c76c51a3d192e819d6990624f40e3585106aa07019a4c1161e376c082748774c34b0bcb5391c0cb34ed8aa4a5b9cca4f682e6ff3748f82ee78a5636f84c878148cc7020890befffaa4506cebbef9a3f7c67178f2"
local K={}for i=1,64 do K[i]=tonumber(KS:sub(i*8-7,i*8),16)end
local function R(x,n)return((x>>n)|(x<<(32-n)))&0xFFFFFFFF end
-- Raw 32-byte SHA-256. string.pack/unpack do the byte work.
local function H(s)
local l=#s
s=s.."\128"..("\0"):rep((55-l)%64)..(">I8"):pack(l*8)
local a0,b0,c0,d0,e0,f0,g0,h0=0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
local w={}
for p=1,#s,64 do
for i=0,15 do w[i+1]=(">I4"):unpack(s,p+i*4)end
for i=17,64 do
local x,y=w[i-15],w[i-2]
w[i]=(w[i-16]+(R(x,7)~R(x,18)~(x>>3))+w[i-7]+(R(y,17)~R(y,19)~(y>>10)))&0xFFFFFFFF
end
local a,b,c,dd,ee,ff,g,h=a0,b0,c0,d0,e0,f0,g0,h0
for i=1,64 do
local t1=(h+(R(ee,6)~R(ee,11)~R(ee,25))+((ee&ff)~(~ee&g))+K[i]+w[i])&0xFFFFFFFF
local t2=((R(a,2)~R(a,13)~R(a,22))+((a&b)~(a&c)~(b&c)))&0xFFFFFFFF
h,g,ff,ee,dd,c,b,a=g,ff,ee,(dd+t1)&0xFFFFFFFF,c,b,a,(t1+t2)&0xFFFFFFFF
end
a0,b0,c0,d0,e0,f0,g0,h0=(a0+a)&0xFFFFFFFF,(b0+b)&0xFFFFFFFF,(c0+c)&0xFFFFFFFF,(d0+dd)&0xFFFFFFFF,(e0+ee)&0xFFFFFFFF,(f0+ff)&0xFFFFFFFF,(g0+g)&0xFFFFFFFF,(h0+h)&0xFFFFFFFF
end
return(">I4I4I4I4I4I4I4I4"):pack(a0,b0,c0,d0,e0,f0,g0,h0)
end
-- HMAC-SHA256 as lowercase hex, matching kernel.crypto.hmac on the host.
local function X(k,s)
if #k>64 then k=H(k)end
k=k..("\0"):rep(64-#k)
local i,o="",""
for j=1,64 do local b=k:byte(j)i=i..string.char(b~0x36)o=o..string.char(b~0x5C)end
return(H(o..H(i..s)):gsub(".",function(c)return("%02x"):format(c:byte())end))
end
-- Constant-time compare (no early exit on the first differing byte).
local function Q(a,b)
if #a~=#b then return false end
local x=0 for i=1,#a do x=x|(a:byte(i)~b:byte(i))end return x==0
end
-- Replay window: the last 64 nonces.
local N,O={},{}
local function seen(n)
if N[n]then return true end
N[n]=true O[#O+1]=n
if #O>64 then N[table.remove(O,1)]=nil end
end
-- Drone moves are vectors; robot moves are calls. Anything missing (a
-- drone asked to swing, a robot asked to select with no arg) errors
-- inside the pcall and is simply not done.
local V={["move:f"]={0,0,1},["move:b"]={0,0,-1},["move:l"]={-1,0,0},["move:r"]={1,0,0},up={0,1,0},down={0,-1,0},["turn:l"]={0,0,0},["turn:r"]={0,0,0},stop={0,0,0}}
local function go(op,g)pcall(function()
if op=="select"then r.select(math.max(1,math.min(g,16)))
elseif d then local v=V[op]if v then d.move(v[1],v[2],v[3])end
elseif op=="move:f"then r.forward()elseif op=="move:b"then r.back()
elseif op=="move:l"then r.turnLeft()r.forward()r.turnRight()
elseif op=="move:r"then r.turnRight()r.forward()r.turnLeft()
elseif op=="turn:l"then r.turnLeft()elseif op=="turn:r"then r.turnRight()
elseif op=="up"then r.up()elseif op=="down"then r.down()
elseif op=="use:f"then r.use()elseif op=="swing:f"then r.swing()
elseif op=="place:f"then r.place()end end)end
m.open(7777)
while true do
local s,_,from,port,_,x=M.pullSignal()
if s=="modem_message"and port==7777 and type(x)=="string"and S then
local op=x:match('op="([^"]+)"')
local g=tonumber(x:match('arg=([%-%d]+)')or"")
local n=x:match('nonce="([^"]+)"')
local c=x:match('mac="(%x+)"')
if x:match('magic="([^"]+)"')=="RCPILOT1"and op and n and c
and Q(X(S,op.."|"..tostring(g or"").."|"..n),c)and not seen(n)then
go(op,g)
if op=="ping"then m.send(from,port,'{magic="RCPILOT1",op="pong",arg='..math.floor(M.uptime())..'}')end
end
end
end
