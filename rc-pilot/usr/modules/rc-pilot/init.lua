local t="string"local r=require("component")
local u=require("computer")local o
do local a,b=pcall(require,"shell.keys")o=a and b or nil end;local function v(b,a)if o and o.is then return o.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function w()
if
o and o.label then local a=o.label("quit")if a~=""then return a end end;return"^Q"end;local s={}local q=7777
local x="RCPILOT1"local p=crypto;if not(p and p.hmac)then
local a,b=pcall(require,"kernel.crypto")if a then p=b end end;local function y(a)return
(p.random or p.salt)(a)end
local function z()return
(y(16):gsub(".",function(a)return
("%02x"):format(a:byte())end))end
local function A(b,a,c)local d=z()
local e=b.."|"..tostring(a or"").."|"..d;local f=p.hmac(c,e)local g=
a and("arg="..tostring(a)..",")or""return
string.format('{magic="%s",op="%s",%snonce="%s",mac="%s"}',x,b,g,d,f)end
local function B(b,a)local c=_G._TOS and _G._TOS.keychain
if c and c.isUnlocked and
c.isUnlocked(a)then local e="rc:".. (b or""):sub(1,8)
local d=c.get(e,a)if d then return d end end;return nil end
s.commands={rc=function(b,a)a=a or print;local g=b[1]
if not g then
a("Usage: rc <robot-address-prefix>")
a("  The robot must be running the rc-pilot EEPROM and have a")
a("  shared secret either in your keychain (slot 'rc:<addr>')")
a("  or passed via 'rc <addr> --secret <secret>'.")
a("  The robot's chip image is /usr/share/rc-pilot/eeprom-rc-pilot.lua:")
a("  swap a blank EEPROM in, `flash` that file, and swap yours back.")return end;local i=r.list("modem")()
if not i then a("No modem")return end;local f=r.proxy(i)if not f.isWireless or not f.isWireless()then
a("Modem is not wireless. RC pilot needs a wireless modem.")return end;local c=nil
local e=_G._TOS or{}local h=e.trust or(e.net and e.net.trust)
if h and
h.listPeers then local k,l=pcall(h.listPeers)
for C,n in ipairs(k and l or{})do
local m=n.address or n.addr;if type(m)==t and m:sub(1,#g)==g then c=m;break end end end;c=c or g
if#c<16 then
a("Target address looks too short. Give the robot's full modem address")
a("(a prefix only works for a peer TOS already knows about).")return end;local d
for k=2,#b do
if b[k]=="--secret"and b[k+1]then d=b[k+1]
a("Note: --secret puts the shared secret in this seat's command history.")
a("      Prefer the keychain:  keychain set rc:"..c:sub(1,8))end end;if not d then
local k=e.users and e.users.currentSession and e.users.currentSession()d=B(c,k)end
if not d then
local l,k=pcall(require,"compat.term")
if
l and type(k)=="table"and type(k.read)=="function"then
a("Shared secret for "..c:sub(1,8).."... (not echoed): ")local n,m=pcall(k.read,nil,false,nil,"*")if n and type(m)==t then
d=m:gsub("[\r\n]+$","")end end end
if not d or#d<16 then
a("No shared secret (16+ characters). Either add it to the keychain:")a("  keychain set rc:"..c:sub(1,8))
a("or, for a script only:  rc <addr> --secret <secret>")return end;f.open(q)
a("RC pilot active. Target: "..c:sub(1,12).."...")
a("Keys: WASD/arrows | Q/E turn | Space/Shift up/down | F use | X break | B place | 1-9 slot | P ping | "..w().." quit")
local function j(l,k)if k==17 or k==200 then return"move:f"end;if k==31 or k==208 then
return"move:b"end;if k==30 or k==203 then return"move:l"end;if k==32 or
k==205 then return"move:r"end;if k==16 then return"turn:l"end;if k==18 then return
"turn:r"end;if k==57 then return"up"end
if k==42 then return"down"end;if k==33 then return"use:f"end;if k==45 then return"swing:f"end;if k==48 then
return"place:f"end;if k==25 then return"ping"end
if k>=2 and k<=10 then return"select",k-1 end;return nil end
while true do local k,C,l,m,C,n=u.pullSignal(0.5)
if k=="key_down"then local D,E=l,m;if v(D,E)or D==3 then
f.close(q)a("RC pilot exited.")return end
local F,G=j(D,E)if F then f.send(c,q,A(F,G,d))end elseif k=="modem_message"then local D=n;if
type(D)==t then local E=D:match('op="pong",arg=(%d+)')if E then
a("  pong @ uptime="..E)end end end end end}return s