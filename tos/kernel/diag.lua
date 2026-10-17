local t=require("computer")local v=require("component")local s={}
local w={ok="ok",info="info",warn="warn",err="err"}s.SEVERITY=w
local function r(a)if a>=1048576 then
return string.format("%.1f MB",a/1048576)end;if a>=1024 then
return string.format("%.1f KB",a/1024)end;return tostring(a).." B"end;local function u(a,b)if not a or a<=0 then return 0 end;return
math.floor((b or 0)*100/a)end
local function x(a)local b=
t.totalMemory()or 0;local e=t.freeMemory()or 0;local f=b-e
local c=u(b,f)local d="ok"if c>90 then d="err"elseif c>75 then d="warn"end
a(string.format("memory: %s used / %s total (%d%%)",r(f),r(b),c),d)if e<16384 then
a("  free memory critically low (< 16 KB)","err")end end
local function y(a)local c=_G._TOS and _G._TOS.fs;if not c or not c.mounts then
a("disks: kernel.fs not available","warn")return end;local b=c.mounts()
if
not b or#b==0 then a("disks: no mounts visible","warn")return end
a(string.format("disks: %d mount(s)",#b),"info")
if _G._TOS_ROOT_READONLY then
a("  ROOT FILESYSTEM IS READ-ONLY — no change made here survives a reboot","err")
a("  (users, logs, packages and settings are all discarded; install to a","err")
a("   writable drive with install.lua, or unprotect this one)","err")end
for e,d in ipairs(b)do local f=u(d.total,d.used)local g="ok"
if f>95 then g="err"elseif f>85 then g="warn"end
a(string.format("  %-16s %s / %s (%d%%)",d.mountPoint,r(d.used or 0),r(d.total or 0),f),g)end end
local function z(a)local b={}local d=0
for f,e in v.list()do b[e]=(b[e]or 0)+1;d=d+1 end
a(string.format("peripherals: %d connected",d),"info")local c={}for e in pairs(b)do c[#c+1]=e end;table.sort(c)for f,e in ipairs(c)do
a(string.format("  %-22s x %d",e,b[e]),"ok")end;if not b.gpu then
a("  no GPU detected","err")end;if not b.screen then
a("  no screen detected","err")end;if not b.eeprom then
a("  no EEPROM detected (BIOS reflash blocked)","warn")end;if not b.filesystem then
a("  no filesystem detected","err")end end
local function A(a)local c=_G._TOS and _G._TOS.rc;if not c or not c.list then
a("services: rc module not available","info")return end;local b=c.list()if not b or#b==0 then
a("services: none registered","info")return end
a(string.format("services: %d registered",#b),"info")
for e,d in ipairs(b)do
local f=d.running and"ok"or
(
(d.unavailable or d.enabled==false)and"info"or"warn")
a(string.format("  %-20s %s",d.name or"?",

d.running and"running"or(d.unavailable and
("not loaded: "..d.unavailable))or(d.enabled==false and"disabled")or"stopped"),f)end end
local function B(a)local b=_G._TOS and _G._TOS.users;if not b or not b.list then
a("users: user module not available","warn")return end;local e=b.list()
a(string.format("users: %d account(s)",
#e),"info")local c,d=0,0;for g,f in ipairs(e)do if f.locked then c=c+1 end
if b.getUser then
local h=b.getUser(f.username)if h and h.firstBoot then d=d+1 end end end;if c>0 then
a("  "..
c.." account(s) locked","warn")end;if d>0 then
a("  "..
d.." account(s) still on firstBoot (password unchanged)","err")end end
local function C(a)local d=_G._TOS and _G._TOS.logObj;if not d or not d.recent then
a("log: kernel.log not available","warn")return end;local f=d.recent(50)local b,c=0,0;for h,g in
ipairs(f)do
if g.level and g.level>=3 then b=b+1 elseif g.level==2 then c=c+1 end end;local e="ok"
if b>0 then e="err"elseif c>0 then e="warn"end
a(string.format("log: %d errors, %d warnings in last 50 entries",b,c),e)end
local function D(a)local d=_G._TOS and _G._TOS.users;if not d then
a("security: users unavailable","warn")return end
local b=_G._TOS and _G._TOS.kernel
if b and b.verifyManifestHash then local f,e=b.verifyManifestHash()
if f then
a("security: manifest hash matches EEPROM anchor","ok")elseif e and e:find("no anchored hash")then
a("security: manifest hash not anchored in EEPROM "..
"(optional hardening — run 'verify anchor' as admin)","warn")else
a("security: manifest hash MISMATCH — "..tostring(e),"err")end end
local c=_G._TOS and _G._TOS.net and _G._TOS.net.trust;if c and c.list then local e=c.list()local f=#e
a(string.format("security: %d trust-DB peers",f),"info")end end
local function E(a)local d,b=pcall(require,"kernel.notify")if
not d or not b or not b.depth then return end;local c=b.depth()if c==0 then return end
a(string.format("notices: %d dialog(s) waiting to be shown",c),
c>=b.MAX_QUEUE and"warn"or"info")end
local function F(a)local e=_G._TOS and _G._TOS.trash
local c=_G._TOS and _G._TOS.users;if not e or not c then return end;local f=
c.currentSession and c.currentSession()or nil;if not f then return end
local b=e.usage(f)if not b then return end;local d="ok"
if b.count>b.max_count*0.9 then d="warn"end;if b.bytes>b.max_bytes*0.9 then d="warn"end
a(string.format("trash: %d/%d items, %d/%d bytes",b.count,b.max_count,b.bytes,b.max_bytes),d)end
local function G(a)local d=_G._TOS or{}
a(string.format("boot: session #%d",d.bootCount or 0),"info")
if d.unsafeShutdown then
a("  last shutdown was UNSAFE (power loss / forced off)","warn")else a("  last shutdown clean","ok")end;local b=d.fs
if
b and b.exists and b.readFile and b.exists("/var/crash/preempt.txt")then local e=b.readFile("/var/crash/preempt.txt")local f=e and
e:match("^[^\n]*")or"?"
a("  runaway process before last reboot: "..f,"warn")
a("    (details: /var/crash/preempt.txt — delete after reviewing)","info")end;local c=d.power
if c and c.statusString then local e=c.statusString()if e then local f=
c.level and c.level()or 100
a("  battery: "..e,f<=5 and"err"or(
f<=15 and"warn"or"ok"))end end end
local H={{name="memory",fn=x},{name="power",fn=G},{name="disks",fn=y},{name="peripherals",fn=z},{name="services",fn=A},{name="users",fn=B},{name="log",fn=C},{name="notices",fn=E},{name="security",fn=D},{name="trash",fn=F}}
function s.run(b,a)a=a or{}local c={ok=0,info=0,warn=0,err=0}local function d(f,e)e=e or"info"
c[e]=(c[e]or 0)+1;b(f,e)end
for f,e in ipairs(H)do
if
not a.only or a.only==e.name then local g,h=pcall(e.fn,d)if not g then
d(e.name..": check failed: "..tostring(h),"err")end end end;return c end;return s