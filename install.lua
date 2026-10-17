local ap,aj,aq,ak="/tos/kernel/init.lua","^(.+)/[^/]+$","tablet","Cancelled."
local Y=require("component")local aa=require("computer")local ah=require("term")local U=nil;pcall(function()
U=require("filesystem")end)local af=Y.gpu;local function T(a)
if af and
af.setForeground then pcall(af.setForeground,a)end end;local function W(a)T(0x00FF00)
print("  + "..a)T(0xFFFFFF)end;local function V(a)T(0xFFFF00)
print("  ! "..a)T(0xFFFFFF)end;local function ab(a)T(0xFF0000)
print("  X "..a)T(0xFFFFFF)end
local function ac(c,b,a)T(0xFFFF00)
io.write(c)if b then T(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then T(0x888888)
io.write(" (default: "..a..")")end;T(0xFFFFFF)io.write(": ")local d;if
ah and ah.read then local e,f=pcall(ah.read)
if e then d=f;if d then d=d:gsub("\n$","")end end else d=io.read()end;if
not d or d==""then return a end;return d end
local function Z(a)local b=ac(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local ar="1.5.0"
local al={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local as={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function at()T(0x00AAFF)for b,a in ipairs(as)do print("   "..a)end
T(0xFFFFFF)print()T(0x00FF66)print("   Strata Systems LLC")
T(0xFFFFFF)T(0xAAAAAA)
print("   Terminal Operating System — Setup v"..ar)T(0xFFFFFF)print()end
local function au(a)if not U then return nil end
if type(a)=="string"and a~=""then local d=
a:sub(-1)=="/"and a:sub(1,-2)or a;if
U.exists(d..ap)then return d end end;local b=os.getenv and os.getenv("_")or nil
if b then
local d=b:match("^(.*)/[^/]+$")if d and d~=""and U.exists(d..ap)then return d end end;local c=aa.getBootAddress()
for d in Y.list("filesystem")do
if d~=c then
local f,e=pcall(Y.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(ap)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then if U.mounts then local l,k=pcall(U.mounts)
if l and k then for m,n in k do if n.address==d then return
tostring(m)end end end end end end end;return nil end
local function av()local a={}a.totalMem=aa.totalMemory()a.freeMem=aa.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if af then local d,e=af.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=aa.getBootAddress()local W,b=pcall(Y.proxy,c)if not W or not b then
b={spaceTotal=function()return 0 end,spaceUsed=function()return 0 end}end
a.diskTotal=b.spaceTotal()
a.diskFree=math.max(0,a.diskTotal-b.spaceUsed())a.diskKB=math.floor(a.diskTotal/1024)a.diskFreeKB=math.floor(
a.diskFree/1024)
a.hasModem,a.hasWireless,a.hasTunnel,a.hasDataCard=false,false,false,false;a.hasGPU,a.hasScreen,a.hasKeyboard=false,false,false
for e,d in Y.list()do
if d=="modem"then
a.hasModem=true
pcall(function()a.hasWireless=Y.proxy(e).isWireless()end)elseif d=="tunnel"then a.hasTunnel=true elseif d=="data"then a.hasDataCard=true elseif d=="gpu"then a.hasGPU=true elseif d==
"screen"then a.hasScreen=true elseif d=="keyboard"then a.hasKeyboard=true end end;return a end
local function aw(a)T(0x00AAFF)print("--- Hardware Detected ---")
T(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))T(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
V("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
V("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
V("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
V("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function ax(a)local c=a.."/tos/system_manifest.lua"if not U.exists(c)then return nil,
"no manifest at "..c end;local d=io.open(c,"r")if not d then return nil,
"cannot open manifest"end;local b=d:read("*a")
d:close()if not b then return nil,"empty manifest"end;if#b>256*1024 then return nil,
"manifest exceeds 256 KB sanity cap"end
local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then
local k,l=e.decode(b,{maxBytes=256*1024})
if k and type(k)=="table"then return k elseif k==nil then
V("manifest serialize.decode failed ("..tostring(l)..
"); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function ay(a)if a then return true end
if U.exists("/etc/users.dat")then
local b=io.open("/etc/users.dat","r")
if b then local c=b:read("*a")b:close()
if c and#c>0 then
V("Existing TOS install detected (/etc/users.dat is populated).")
V("Re-installing will overwrite users, configuration, and the")
V("system tree but will NOT delete user data under /home or /tmp.")T(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")T(0xFFFFFF)local d=io.read()or""if d~="FORCE-WIPE"then
ab("Install aborted by safety check.")return false end end end end;return true end
local function az(a,b)local c=io.open(a,"r")if not c then return false,"open source"end
local d=io.open(b,"w")if not d then c:close()return false,"open dest"end
while true do
local e=c:read(4096)if not e then break end
local f,g=pcall(function()d:write(e)end)
if not f then c:close()d:close()return false,"write: "..tostring(g)end end;c:close()d:close()return true end
local function aA(a,b)local c,d={},{}
for f,e in ipairs(b)do local g=e.path
if not U.exists(g)then c[#c+1]=g else
local h=U.size(a..g)or 0;local i=U.size(g)or 0;if h~=i then
d[#d+1]=string.format("%s (src=%d dst=%d)",g,h,i)end end end;return c,d end;local am=512
local function aB(c,d,a,b)local e,f=0,{}
for h,g in ipairs(d)do local j=a(c..g.path)or 0;if b(g.path)then
e=e+math.max(0,
j- (a(g.path)or 0))else e=e+j+am end
local i=g.path:match(aj)while i and i~=""and not f[i]do f[i]=true;if not b(i)then e=e+am end
i=i:match(aj)end end;return e end
local function aC()local c,a=pcall(U.get,"/")if not c or not a then return nil end
local d,b=pcall(a.spaceTotal)local e,f=pcall(a.spaceUsed)if
not(d and e)or type(b)~="number"or b<=0 then return nil end;return b-f end
local function aD(a)local d,i=ax(a)if not d then
ab("Cannot load install manifest: "..tostring(i))return false end;W("Manifest loaded: "..
#d.." files declared")
local g=aB(a,d,U.size,U.exists)local e=aC()
if e and g>e then print()
ab(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
g/1024),math.floor(e/1024)))
V("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
V("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")V("holds TOS on its own.")return false,"space"end;if e then
W(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(g/1024),math.floor(e/1024)))end;print()
T(0x00AAFF)print("--- Creating directories ---")T(0xFFFFFF)
local h={}
for k,j in ipairs(d)do local l=j.path:match(aj)while l and l~=""and not h[l]do
h[l]=true
if not U.isDirectory(l)then U.makeDirectory(l)end;l=l:match(aj)end end;for k,j in ipairs(al)do
if not U.isDirectory(j)then U.makeDirectory(j)end end
W("Directory structure created")print()T(0x00AAFF)
print("--- Copying system files ---")T(0xFFFFFF)local f,b=0,0;local c={}
for k,j in ipairs(d)do local l=a..j.path;local m=j.path
if
not U.exists(l)then b=b+1;c[#c+1]="missing on disk: "..j.path else local n,o=az(l,m)
if n then
f=f+1 else b=b+1;c[#c+1]=j.path..": "..tostring(o)end end end;print()
if b==0 then W("Copied "..f.." files")else
ab("Copied "..f.." files, "..b..
" FAILED:")for j=1,math.min(5,#c)do V("  "..c[j])end;if#c>5 then V("  (+".. (#c-5)..
" more)")end end;print()
if b==0 then T(0x00AAFF)print("--- Verifying copy ---")
T(0xFFFFFF)local j,k=aA(a,d)
if#j==0 and#k==0 then
W("All "..#d.." files verified")else
if#j>0 then ab(#j.." files MISSING after copy:")for l=1,math.min(5,
#j)do V("  "..j[l])end;b=b+#j end
if#k>0 then
ab(#k.." files have WRONG SIZE after copy:")for l=1,math.min(5,#k)do V("  "..k[l])end;b=b+#k end end;print()end;return b==0 end;local an={"/bin","/boot","/lib"}local _="/init.lua.pre-tos"
local function aE()
if not U or not
U.exists("/init.lua")or U.exists(_)then return false end;local b=io.open("/init.lua","r")if not b then return false end
local a=b:read("*a")b:close()
if not a or a==""or a:find("_TOS",1,true)then return false end;local c=io.open(_,"w")if not c then return false end;c:write(a)
c:close()return U.exists(_)end;local function aF()if not U then return false end
for b,a in ipairs(an)do if U.exists(a)then return true end end;return false end
local function aG()
local a={}if not U then return a end;for c,b in ipairs(an)do
if U.exists(b)then local d=pcall(U.remove,b)if d and not
U.exists(b)then a[#a+1]=b end end end
if
#a>0 and U.exists(_)then pcall(U.remove,_)if not U.exists(_)then a[#a+1]=_ end end;return a end
local function aH(a)local d=a.."/bios.lua"if not U.exists(d)then return end
local c=io.open(d,"r")
if not c then V("Could not read bios.lua")print()return end;local b=c:read("*a")c:close()if not b or#b==0 then
V("Empty bios.lua")print()return end;local e="(unavailable)"
do
local i,h=pcall(require,"kernel.crypto")if i and h and h.hash then local j=h.hash(b)
if j then e=j:sub(1,16).."..."end end end;T(0xFFFF00)
print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..e)T(0xFFFFFF)
T(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
T(0xFFFFFF)local g=io.read()or""if g~="flash"then W("Skipped BIOS flash")
print()return end;local f=Y.list("eeprom")()
if f then
local h=Y.proxy(f)h.set(b)h.setLabel("TOS BIOS")
W("BIOS flashed! Label set to 'TOS BIOS'")else V("No EEPROM found")end;print()end
local function aI(a)local b={}T(0x00AAFF)print("--- Device Setup ---")
T(0xFFFFFF)print()print("What type of device is this?")
T(0xAAAAAA)
print("  1. Computer  (desktop, tower with screen)")
print("  2. Tablet    (portable, battery-powered)")
print("  3. Server    (rack blade, typically headless)")T(0xFFFFFF)local c=ac("Choice",{"1","2","3"},"1")
if c=="2"then
b.device=aq;b.showBattery=true;b.powerSave=true
W("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
W("Server mode (headless boot, services auto-start)")print()T(0xFFFF00)print("  Server rack checklist:")
T(0xAAAAAA)
if a.hasModem or a.hasTunnel then W("Network card detected")else
V("No modem or linked card! The server will be unreachable.")
V("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
W("Headless (no GPU/screen) — normal for servers")else
V("GPU or screen detected — will boot headless anyway.")
V("Remove them to free rack slots, or choose Computer mode.")end;T(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
W("Computer mode")end;print()
math.randomseed(math.floor(aa.uptime()*1000)+
aa.freeMemory())
b.hostname=ac("Hostname",nil,"tos-"..string.format("%04x",math.random(0,0xFFFF)))W("Hostname: "..b.hostname)print()
T(0x00AAFF)print("--- Security ---")T(0xFFFFFF)print()
print("Security level:")T(0xAAAAAA)
print("  1. Standard  (login + lockout after 5 failures)")print("  2. Relaxed   (login, no lockout)")
print("  3. Open      (allows guest access)")T(0xFFFFFF)local d=ac("Choice",{"1","2","3"},"1")
if d=="3"then
b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999;W("Security: Open")elseif d=="2"then
b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999;W("Security: Relaxed")else
b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5;W("Security: Standard")end;print()
if a.hasModem or a.hasTunnel then T(0x00AAFF)
print("--- Network ---")T(0xFFFFFF)print()
b.encryptComms=Z("Encrypt network communications?")
W("Encryption: ".. (b.encryptComms and"on"or"off"))local e=ac("Listen port",nil,"42")
b.listenPort=tonumber(e)or 42;W("Port: "..b.listenPort)print()else
b.encryptComms=true;b.listenPort=42 end
if b.device==aq then T(0x00AAFF)print("--- Tablet Options ---")
T(0xFFFFFF)print()b.lowBatWarn=
tonumber(ac("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(ac("Critical battery warning %",
nil,"5"))or 5
W("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end;b.verbose=Z("Verbose boot? (shows debug messages)")
print()return b end
local function aJ(a)local b={"return {"}local c={}for e in pairs(a)do c[#c+1]=e end
table.sort(c)
for f,e in ipairs(c)do local g=a[e]if type(g)=="string"then
b[#b+1]=string.format('  [%q] = %q,',e,g)else
b[#b+1]=string.format('  [%q] = %s,',e,tostring(g))end end;b[#b+1]="}"local d=io.open("/etc/tos.cfg","w")if d then
d:write(table.concat(b,"\n"))d:close()return true end;return false end;ah.clear()at()local ao=av()aw(ao)local aK={...}local ai=au(aK[1])
local ae=ai~=nil;local ad=false;local ag=false
if ae then
W("Install disk found at: "..ai)print()T(0xFFFF00)
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")T(0xFFFFFF)print()
if not Z("Continue?")then print(ak)return end;print()
if not ay(_G._FORCE_WIPE or false)then return end;if aE()then
W("Kept the previous /init.lua as ".._)end;local a;ad,a=aD(ai)
if a=="space"then print()return end
if not ad then
ab("Install file copy/verify did NOT fully succeed.")
V("BIOS flash will be skipped to avoid bricking the boot.")
V("You can retry installation; the partial files won't conflict.")
if not Z("Continue to questionnaire anyway?")then print(ak)return end;print()end
if ad and aF()then T(0x00AAFF)print("--- Clean install ---")
T(0xFFFFFF)T(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
T(0xFFFFFF)ag=Z("Remove OpenOS leftovers for a clean install?")
W(
ag and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else T(0xFFFF00)
print("No install disk detected - running in configuration mode.")
print("TOS system files must already be present on the boot drive.")T(0xFFFFFF)print()
if not Z("Continue?")then print(ak)return end;print()end;local X=aI(ao)T(0x00AAFF)print("--- Summary ---")
T(0xAAAAAA)print("  Device:     "..X.device)print("  Hostname:   "..
X.hostname)
print("  Security:   "..
(
X.autoLockout and"Standard"or(X.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (X.encryptComms and"Yes"or"No"))
if X.device==aq then
print("  Battery:    Warn at "..
X.lowBatWarn.."% / "..X.critBatWarn.."%")elseif X.device=="server"then
print("  Headless:   ".. (X.headless and"Yes"or"No"))
print("  Services:   "..
(X.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (X.verbose and"Yes"or"No"))if ae and ad then
print("  Clean inst: "..
(ag and"Yes (remove /bin, /boot, /lib)"or"No"))end;T(0xFFFFFF)print()if not
Z("Apply these settings?")then print(ak)return end;print()
T(0x00AAFF)print("--- Applying configuration ---")T(0xFFFFFF)
if U then for b,a in
ipairs(al)do
if not U.isDirectory(a)then U.makeDirectory(a)end end end;if aJ(X)then W("Configuration saved to /etc/tos.cfg")else
V("Could not save config (defaults will be used)")end
W("Device profile: "..X.device)print()
if ae then if ad then aH(ai)else
V("Skipping BIOS flash: file copy did not fully verify.")V("Re-run install.lua to retry before flashing.")
print()end end
if ae and ad and ag then T(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")T(0xFFFFFF)local a=aG()
if#a>0 then
W("Removed: "..table.concat(a,", "))
V("OpenOS is no longer bootable on this drive — reboot into TOS.")else V("Nothing to remove (already clean).")end;print()end;T(0x00AAFF)print("--- Installation Complete ---")
T(0xFFFFFF)print()T(0x00FF00)
if ae and ad then
print("TOS is installed! Reboot to start.")elseif ae then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print("First boot asks you to set the root password before anything else.")if ag then T(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")T(0xFFFFFF)end
T(0xFFFFFF)print()if Z("Reboot now?")then aa.shutdown(true)end