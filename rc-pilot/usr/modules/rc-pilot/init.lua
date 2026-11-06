local s="string"local t=require("component")
local r=require("computer")local o
do local a,b=pcall(require,"shell.keys")o=a and b or nil end;local function v(b,a)if o and o.is then return o.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function w()
if
o and o.label then local a=o.label("quit")if a~=""then return a end end;return"^Q"end;local u={}local p=7777
local x="RCPILOT1"local q=crypto;if not(q and q.hmac)then
local a,b=pcall(require,"kernel.crypto")if a then q=b end end;local function y(a)return
(q.random or q.salt)(a)end
local function z()return
(y(16):gsub(".",function(a)return
("%02x"):format(a:byte())end))end
local function A(b,a,c)local d=z()
local e=b.."|"..tostring(a or"").."|"..d;local f=q.hmac(c,e)local g=
a and("arg="..tostring(a)..",")or""return
string.format('{magic="%s",op="%s",%snonce="%s",mac="%s"}',x,b,g,d,f)end
local function B(b,a)local c=_G._TOS and _G._TOS.keychain
if c and c.isUnlocked and
c.isUnlocked(a)then local e="rc:".. (b or""):sub(1,8)
local d=c.get(e,a)if d then return d end end;return nil end
u.commands={rc=function(b,a)a=a or print;local g=b[1]
if not g then
a("Usage: rc <robot-address> | rc scan")
a("  `rc scan` lists the robots in range, with their addresses.")
a("  The robot must be running the rc-pilot EEPROM. rc asks for the")
a("  shared secret, or takes it from 'rc <addr> --secret <secret>'.")
a("  The robot's chip image is /usr/share/rc-pilot/eeprom-rc-pilot.lua:")
a("  swap a blank EEPROM in, `flash` that file, and swap yours back.")return end;local i=t.list("modem")()
if not i then a("No modem")return end;local e=t.proxy(i)if not e.isWireless or not e.isWireless()then
a("Modem is not wireless. RC pilot needs a wireless modem.")return end
local function j()
local l,m=e.open(p)if l==nil then
a("Cannot listen on port "..p..": "..tostring(m))return false end;return true end
if g=="scan"then if not j()then return end
e.broadcast(p,'{magic="RCPILOT1",op="who"}')a("Asking who is in range...")local m,l={},0
local n=r.uptime()+3
while true do local D=n-r.uptime()if D<=0 then break end
local F,H,C,G,H,E=r.pullSignal(D)
if
F=="modem_message"and G==p and type(E)==s and not m[C]then local I,J=E:match('op="here",keyed=(%a+),kind="(%a+)"')if I then
m[C]=true;l=l+1
a("  "..
C.."  "..J..
(I=="true"and""or"  (no secret on its chip: it will ignore you)"))end end end;e.close(p)if l==0 then
a("Nothing answered. Is the robot on, in range, and running the rc-pilot chip?")end;return end;local c=nil;local f=_G._TOS or{}
local h=f.trust or(f.net and f.net.trust)
if h and h.listPeers then local l,m=pcall(h.listPeers)
for C,n in ipairs(l and m or{})do local D=
n.address or n.addr;if type(D)==s and D:sub(1,#g)==g then c=D
break end end end;c=c or g;if#c<16 then
a("Target address looks too short. Give the robot's full modem address.")return end;local d
for l=2,#b do
if b[l]=="--secret"and
b[l+1]then d=b[l+1]
a("Note: --secret puts the shared secret in this seat's command history.")
a("      Leave --secret off and rc asks for it, without showing it.")end end;if not d then
local l=f.users and f.users.currentSession and f.users.currentSession()d=B(c,l)end
if not d then
local m,l=pcall(require,"compat.term")
if
m and type(l)=="table"and type(l.read)=="function"then
a("Shared secret for "..c:sub(1,8).."... (not echoed): ")local C,n=pcall(l.read,nil,false,nil,"*")if C and type(n)==s then
d=n:gsub("[\r\n]+$","")end end end
if not d or#d<16 then
a("No shared secret (16+ characters). Run rc again and type it when")
a("asked, or, for a script only:  rc <addr> --secret <secret>")return end;if not j()then return end
a("RC pilot active. Target: "..c:sub(1,12).."...")
a("Keys: WASD/arrows | Q/E turn | Space/Shift up/down | F use | X break | B place | 1-9 slot | P ping | "..w().." quit")
local function k(m,l)if l==17 or l==200 then return"move:f"end;if l==31 or l==208 then
return"move:b"end;if l==30 or l==203 then return"move:l"end;if l==32 or
l==205 then return"move:r"end;if l==16 then return"turn:l"end;if l==18 then return
"turn:r"end;if l==57 then return"up"end
if l==42 then return"down"end;if l==33 then return"use:f"end;if l==45 then return"swing:f"end;if l==48 then
return"place:f"end;if l==25 then return"ping"end
if l>=2 and l<=10 then return"select",l-1 end;return nil end
while true do local l,D,m,n,D,C=r.pullSignal(0.5)
if l=="key_down"then local E,F=m,n;if v(E,F)or E==3 then
e.close(p)a("RC pilot exited.")return end
local G,H=k(E,F)if G then e.send(c,p,A(G,H,d))end elseif l=="modem_message"then local E=C;if
type(E)==s then local F=E:match('op="pong",arg=(%d+)')if F then
a("  pong @ uptime="..F)end end end end end}return u