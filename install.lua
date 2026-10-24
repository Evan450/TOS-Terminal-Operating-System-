
local aP,aG,aB,aH,aQ,aR,aD="filesystem","/tos/kernel/init.lua","string","^(.+)/[^/]+$","/init.lua","tablet","Cancelled."local ap=require("component")local an=require("computer")
local aC=require("term")local ai=nil
pcall(function()ai=require(aP)end)local az=ap.gpu;local function ah(a)
if az and az.setForeground then pcall(az.setForeground,a)end end;local function ak(a)ah(0x00FF00)
print("  + "..a)ah(0xFFFFFF)end;local function aj(a)ah(0xFFFF00)
print("  ! "..a)ah(0xFFFFFF)end;local function aq(a)ah(0xFF0000)
print("  X "..a)ah(0xFFFFFF)end
local function as(c,b,a)ah(0xFFFF00)
io.write(c)if b then ah(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then ah(0x888888)
io.write(" (default: "..a..")")end;ah(0xFFFFFF)io.write(": ")local d
if aC and
aC.read then local e,f=pcall(aC.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function ar(a)local b=as(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local aS="1.5.0"
local aI={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local aT={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function aU()ah(0x00AAFF)for b,a in ipairs(aT)do print("   "..a)end
ah(0xFFFFFF)print()ah(0x00FF66)print("   Strata Systems LLC")
ah(0xFFFFFF)ah(0xAAAAAA)
print("   Terminal Operating System — Setup v"..aS)ah(0xFFFFFF)print()end
local function aV(a)if not ai then return nil end;if type(a)==aB and a~=""then local d=a:sub(-1)=="/"and
a:sub(1,-2)or a
if ai.exists(d..aG)then return d end end;local b=
os.getenv and os.getenv("_")or nil
if b then
local d=b:match("^(.*)/[^/]+$")if d and d~=""and ai.exists(d..aG)then return d end end;local c=an.getBootAddress()
for d in ap.list(aP)do
if d~=c then
local f,e=pcall(ap.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(aG)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then
if ai.mounts then local l,k=pcall(ai.mounts)if l and k then
for m,n in k do local o,p=m,n;if type(m)==
aB then o,p=n,m end;if type(o)=="table"and o.address==d then return
tostring(p)end end end end end end end;return nil end
local function aW()local a={}a.totalMem=an.totalMemory()a.freeMem=an.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if az then local d,e=az.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=an.getBootAddress()local ak,b=pcall(ap.proxy,c)if not ak or not b then
b={spaceTotal=function()return 0 end,spaceUsed=function()return 0 end}end
a.diskTotal=b.spaceTotal()
a.diskFree=math.max(0,a.diskTotal-b.spaceUsed())a.diskKB=math.floor(a.diskTotal/1024)a.diskFreeKB=math.floor(
a.diskFree/1024)
a.hasModem,a.hasWireless,a.hasTunnel,a.hasDataCard=false,false,false,false;a.hasGPU,a.hasScreen,a.hasKeyboard=false,false,false
for e,d in ap.list()do
if d=="modem"then
a.hasModem=true
pcall(function()a.hasWireless=ap.proxy(e).isWireless()end)elseif d=="tunnel"then a.hasTunnel=true elseif d=="data"then a.hasDataCard=true elseif d=="gpu"then a.hasGPU=true elseif d==
"screen"then a.hasScreen=true elseif d=="keyboard"then a.hasKeyboard=true end end;return a end
local function aX(a)ah(0x00AAFF)print("--- Hardware Detected ---")
ah(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))ah(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
aj("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
aj("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
aj("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
aj("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function aJ(a)local c=a.."/tos/system_manifest.lua"if not ai.exists(c)then return nil,
"no manifest at "..c end
local d=io.open(c,"r")if not d then return nil,"cannot open manifest"end
local b=d:read("*a")d:close()if not b then return nil,"empty manifest"end
if
#b>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then local k,l=e.decode(b,{maxBytes=
256*1024})
if
k and type(k)=="table"then return k elseif k==nil then
aj("manifest serialize.decode failed ("..
tostring(l).."); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function aY(b,a)if b then return true end;a=a or""
if ai.exists(a.."/etc/users.dat")then local c=io.open(a..
"/etc/users.dat","r")
if c then local d=c:read("*a")
c:close()
if d and#d>0 then
aj("Existing TOS install detected (/etc/users.dat is populated).")
aj("Re-installing will overwrite users, configuration, and the")
aj("system tree but will NOT delete user data under /home or /tmp.")ah(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")ah(0xFFFFFF)local e=io.read()or""if e~="FORCE-WIPE"then
aq("Install aborted by safety check.")return false end end end end;return true end
local function aZ(a,b)local c=io.open(a,"r")if not c then return false,"open source"end
local d=io.open(b,"w")if not d then c:close()return false,"open dest"end
while true do
local e=c:read(4096)if not e then break end
local f,g=pcall(function()d:write(e)end)
if not f then c:close()d:close()return false,"write: "..tostring(g)end end;c:close()d:close()return true end
local function a_(b,c,a)a=a or""local d,e={},{}
for g,f in ipairs(c)do local h=a..f.path
if not ai.exists(h)then
d[#d+1]=h else local i=ai.size(b..f.path)or 0
local j=ai.size(h)or 0;if i~=j then
e[#e+1]=string.format("%s (src=%d dst=%d)",h,i,j)end end end;return d,e end;local aK=512
local function aL(d,e,b,c,a)a=a or""local f,g=0,{}
for i,h in ipairs(e)do local k=b(d..h.path)or 0;if
c(a..h.path)then
f=f+math.max(0,k- (b(a..h.path)or 0))else f=f+k+aK end
local j=h.path:match(aH)while j and j~=""and not g[j]do g[j]=true;if not c(a..j)then f=f+aK end
j=j:match(aH)end end;return f end
local function ba(a)
local d,b=pcall(ai.get,(a==nil or a=="")and"/"or a)if not d or not b then return nil end;local e,c=pcall(b.spaceTotal)
local f,g=pcall(b.spaceUsed)if not(e and f)or type(c)~="number"or c<=0 then
return nil end;return c-g end
local function bb(a)local b,c={},nil;for e,d in ipairs(a)do
b[e]=(d.free==nil)or(d.free>=d.need)end;for d,e in ipairs(a)do
if e.isBoot and b[d]then c=d;break end end;if not c then
for d=1,#a do if b[d]then c=d;break end end end;return c,b end
local function bc(a)local b={positional={}}
for d,c in ipairs(a)do
if
c=="-h"or c=="--help"or c=="-?"or c=="/?"then b.help=true elseif
type(c)==aB and c:sub(1,1)=="-"then b.unknown=b.unknown or c else
b.positional[#b.positional+1]=c end end;return b end
local function bd()local a={}if not(ai and ai.mounts)then return a end
local c,b=pcall(ai.mounts)if not c or type(b)~="function"then return a end
for d,e in b do local g,h=d,e;if
type(d)==aB then g,h=e,d end
local f=type(g)=="table"and g.address or nil
if f and type(h)==aB then a[f]=a[f]or{}a[f][#a[f]+1]=h end end;return a end
local function be(a)
for c,b in ipairs(a)do if b:sub(1,5)=="/mnt/"then return b end end;for c,b in ipairs(a)do if b~="/"then return b end end;return nil end
local function aw(a)if a>=1024*1024 then
return string.format("%.1f MB",a/1024/1024)end;return
string.format("%d KB",math.floor(a/1024))end
local function bf(a,b)local e=bd()local f=an.getBootAddress()local g=
an.tmpAddress and an.tmpAddress()or nil;local h=
a:sub(-1)=="/"and a:sub(1,-2)or a;local c,d={},0
for i in ap.list(aP)do
local k,j=pcall(ap.proxy,i)local l,m=false,true;if k and j then l,m=pcall(j.isReadOnly)end
if
i~=g and k and j and l and not m then local o=e[i]or{}local p=i==f
local n=p and""or be(o)local q=false;for s,r in ipairs(o)do if r==h then q=true end end
if q then elseif not n then d=d+1 else
local r={address=i,prefix=n,isBoot=p}local t,u=pcall(j.getLabel)r.label=t and u or nil
local v,s=pcall(j.spaceTotal)local w,x=pcall(j.spaceUsed)if
v and w and type(s)=="number"and s>0 then r.total,r.free=s,s-x end
local y,z=pcall(j.exists,aQ)local A,B=pcall(j.exists,aG)r.hasInit=y and z or false;r.hasTos=A and B or
false
r.need=b and aL(a,b,ai.size,ai.exists,n)or 0;c[#c+1]=r end end end
table.sort(c,function(i,j)if i.isBoot~=j.isBoot then return i.isBoot end;return
i.prefix<j.prefix end)return c,d end
local function aM(a)
local b=a.isBoot and"the boot drive"or("the drive at "..a.prefix)
if a.label and a.label~=""then b=b..' "'..a.label..'"'end;return b end
local function bg(a,b)local c,f=bf(a,b)if#c==0 then
return{address=an.getBootAddress(),prefix="",isBoot=true,need=0}end;local d,e=bb(c)
if#c==1 and d==1 then return c[1]end;ah(0x00AAFF)print("--- Where should TOS go? ---")
ah(0xFFFFFF)
for h,g in ipairs(c)do if g.isBoot and g.free and g.free<g.need then
aj(string.format("The boot drive has %s free; TOS needs %s.",aw(g.free),aw(g.need)))end end
for h,g in ipairs(c)do
local j=string.format("  %d. %s%s",h,g.isBoot and"Boot drive"or g.prefix,
(g.label and
g.label~="")and('  "'..g.label..'"')or"")if e[h]then ah(0xFFFFFF)else ah(0x888888)end
print(j.. (
h==d and"   <- default"or""))
local k=
g.total and string.format("%s, %s free",aw(g.total),aw(g.free))or"size unknown"local i={}if g.hasTos then i[#i+1]="has TOS"elseif g.hasInit then i[#i+1]="has an OS"else
i[#i+1]="empty"end;if not e[h]then i[#i+1]="too small: needs "..
aw(g.need)end
ah(0xAAAAAA)
print("     "..k.."; "..table.concat(i,", "))end;ah(0xFFFFFF)if f>0 then
aj(f.." more drive(s) are not mounted, so they are not listed.")end
if not d then print()
aq("None of these drives has room for TOS.")
aj("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
aj("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")return nil,"space"end;print()
while true do
local h=as("Install on which drive? (0 = cancel)",nil,tostring(d))local g=tonumber(h)if g==0 then return nil end
if g and c[g]then
if e[g]then return c[g]end
aj("That drive is too small: TOS needs "..aw(c[g].need)..".")else aj("Type a number from the list.")end end end
local function bh(b,a,c)a=a or""local e,j=c,nil;if not e then e,j=aJ(b)end;if not e then
aq("Cannot load install manifest: "..tostring(j))return false end;ak("Manifest loaded: "..
#e.." files declared")
local i=aL(b,e,ai.size,ai.exists,a)local g=ba(a)
if g and i>g then print()
aq(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
i/1024),math.floor(g/1024)))
aj("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
aj("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")aj("holds TOS on its own.")return false,"space"end;if g then
ak(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(i/1024),math.floor(g/1024)))end;print()
ah(0x00AAFF)print("--- Creating directories ---")ah(0xFFFFFF)
local k={}
for m,l in ipairs(e)do local n=l.path:match(aH)
while n and n~=""and not k[n]do
k[n]=true
if not ai.isDirectory(a..n)then ai.makeDirectory(a..n)end;n=n:match(aH)end end;for m,l in ipairs(aI)do if not ai.isDirectory(a..l)then
ai.makeDirectory(a..l)end end
ak("Directory structure created")print()ah(0x00AAFF)
print("--- Copying system files ---")ah(0xFFFFFF)local h,d=0,0;local f={}
for m,l in ipairs(e)do local n=b..l.path;local o=a..l.path
if not
ai.exists(n)then d=d+1;f[#f+1]="missing on disk: "..l.path else
local p,q=aZ(n,o)
if p then h=h+1 else d=d+1;f[#f+1]=l.path..": "..tostring(q)end end end;print()
if d==0 then ak("Copied "..h.." files")else
aq("Copied "..h..
" files, "..d.." FAILED:")for l=1,math.min(5,#f)do aj("  "..f[l])end
if#f>5 then aj("  (+"..
(#f-5).." more)")end end;print()
if d==0 then ah(0x00AAFF)print("--- Verifying copy ---")
ah(0xFFFFFF)local l,m=a_(b,e,a)
if#l==0 and#m==0 then
ak("All "..#e.." files verified")else
if#l>0 then aq(#l.." files MISSING after copy:")for n=1,math.min(5,
#l)do aj("  "..l[n])end;d=d+#l end
if#m>0 then
aq(#m.." files have WRONG SIZE after copy:")for n=1,math.min(5,#m)do aj("  "..m[n])end;d=d+#m end end;print()end;return d==0 end;local aN={"/bin","/boot","/lib"}local at="/init.lua.pre-tos"
local function bi(a)a=a or""if
not ai or not ai.exists(
a..aQ)or ai.exists(a..at)then return false end
local c=io.open(a..aQ,"r")if not c then return false end;local b=c:read("*a")c:close()if not b or b==""or
b:find("_TOS",1,true)then return false end
local d=io.open(a..at,"w")if not d then return false end;d:write(b)d:close()
return ai.exists(a..at)end
local function bj(a)a=a or""if not ai then return false end;for c,b in ipairs(aN)do
if ai.exists(a..b)then return true end end;return false end
local function bk(a)a=a or""local b={}if not ai then return b end;for d,c in ipairs(aN)do
if ai.exists(a..c)then
local e=pcall(ai.remove,a..c)if e and not ai.exists(a..c)then b[#b+1]=c end end end
if#b>0 and ai.exists(a..
at)then pcall(ai.remove,a..at)if not
ai.exists(a..at)then b[#b+1]=at end end;return b end
local function bl(a)local d=a.."/bios.lua"if not ai.exists(d)then return end
local c=io.open(d,"r")
if not c then aj("Could not read bios.lua")print()return end;local b=c:read("*a")c:close()if not b or#b==0 then
aj("Empty bios.lua")print()return end;local e="(unavailable)"
do
local i,h=pcall(require,"kernel.crypto")if i and h and h.hash then local j=h.hash(b)
if j then e=j:sub(1,16).."..."end end end;ah(0xFFFF00)
print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..e)ah(0xFFFFFF)
ah(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
ah(0xFFFFFF)local g=io.read()or""if g~="flash"then ak("Skipped BIOS flash")
print()return end;local f=ap.list("eeprom")()
if f then
local h=ap.proxy(f)h.set(b)h.setLabel("TOS BIOS")
ak("BIOS flashed! Label set to 'TOS BIOS'")else aj("No EEPROM found")end;print()end
local function bm(a)local b={}ah(0x00AAFF)print("--- Device Setup ---")
ah(0xFFFFFF)print()print("What type of device is this?")
ah(0xAAAAAA)
print("  1. Computer  (desktop, tower with screen)")
print("  2. Tablet    (portable, battery-powered)")
print("  3. Server    (rack blade, typically headless)")ah(0xFFFFFF)local c=as("Choice",{"1","2","3"},"1")
if c=="2"then
b.device=aR;b.showBattery=true;b.powerSave=true
ak("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
ak("Server mode (headless boot, services auto-start)")print()ah(0xFFFF00)print("  Server rack checklist:")
ah(0xAAAAAA)
if a.hasModem or a.hasTunnel then ak("Network card detected")else
aj("No modem or linked card! The server will be unreachable.")
aj("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
ak("Headless (no GPU/screen) — normal for servers")else
aj("GPU or screen detected — will boot headless anyway.")
aj("Remove them to free rack slots, or choose Computer mode.")end;ah(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
ak("Computer mode")end;print()
math.randomseed(math.floor(an.uptime()*1000)+
an.freeMemory())
b.hostname=as("Hostname",nil,"tos-"..string.format("%04x",math.random(0,0xFFFF)))ak("Hostname: "..b.hostname)print()
ah(0x00AAFF)print("--- Security ---")ah(0xFFFFFF)print()
print("Security level:")ah(0xAAAAAA)
print("  1. Standard  (login + lockout after 5 failures)")print("  2. Relaxed   (login, no lockout)")
print("  3. Open      (allows guest access)")ah(0xFFFFFF)local d=as("Choice",{"1","2","3"},"1")
if d=="3"then
b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999;ak("Security: Open")elseif d=="2"then
b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999;ak("Security: Relaxed")else
b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5;ak("Security: Standard")end;print()
if a.hasModem or a.hasTunnel then ah(0x00AAFF)
print("--- Network ---")ah(0xFFFFFF)print()
b.encryptComms=ar("Encrypt network communications?")
ak("Encryption: ".. (b.encryptComms and"on"or"off"))local e=as("Listen port",nil,"42")
b.listenPort=tonumber(e)or 42;ak("Port: "..b.listenPort)print()else
b.encryptComms=true;b.listenPort=42 end
if b.device==aR then ah(0x00AAFF)print("--- Tablet Options ---")
ah(0xFFFFFF)print()b.lowBatWarn=
tonumber(as("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(as("Critical battery warning %",
nil,"5"))or 5
ak("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end;b.verbose=ar("Verbose boot? (shows debug messages)")
print()return b end
local function bn(a,b)local c={"return {"}local d={}for f in pairs(a)do d[#d+1]=f end
table.sort(d)
for g,f in ipairs(d)do local h=a[f]if type(h)==aB then
c[#c+1]=string.format('  [%q] = %q,',f,h)else
c[#c+1]=string.format('  [%q] = %s,',f,tostring(h))end end;c[#c+1]="}"
local e=io.open((b or"").."/etc/tos.cfg","w")
if e then e:write(table.concat(c,"\n"))e:close()return true end;return false end;local ax=bc({...})aC.clear()aU()
if ax.help or ax.unknown then if ax.unknown and
not ax.help then
aq("Unknown option: "..tostring(ax.unknown))print()end
print("Copies TOS onto a drive, asks a few setup questions, and")print("offers to flash the TOS BIOS.")print()
print("Usage:")print("  install.lua [source-dir]")
print("  install.lua --help")print()
print("Run it from an install disk (/mnt/<disk>/install.lua), or")
print("let bootstrap.lua stage a download for it.")print()
print("With more than one writable drive it asks which one TOS")
print("goes on; the boot drive is only the default. If the boot")
print("drive is too small it offers the others. TOS can then be")print("made the boot drive at the end.")print()
print("source-dir  a directory holding a TOS release, for")
print("            scripted installs. Normally found by itself.")print()
print("With no install disk it only changes the settings of a")print("TOS that is already installed.")return end;local aO=aW()aX(aO)local ay=aV(ax.positional[1])local av=ay~=nil
local ao,am="",nil;local aE;local au=false;local aA=false
if av then
ak("Install disk found at: "..ay)print()aE=aJ(ay)local a;am,a=bg(ay,aE)if not am then print()
if a~="space"then print(aD)end;return end;ao=am.prefix;print()ah(0xFFFF00)
if
am.isBoot then
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")else
print("TOS will be installed on "..aM(am)..".")
print("Its /init.lua will be replaced (the current one, if any, is kept")
print("there as /init.lua.pre-tos). The drive this machine boots from")
print("is not changed unless you choose that at the end.")end;ah(0xFFFFFF)print()
if not ar("Continue?")then print(aD)return end;print()
if not aY(_G._FORCE_WIPE or false,ao)then return end;if bi(ao)then
ak("Kept the previous /init.lua as "..ao..at)end;local b;au,b=bh(ay,ao,aE)if b=="space"then print()
return end
if not au then
aq("Install file copy/verify did NOT fully succeed.")
aj("BIOS flash will be skipped to avoid bricking the boot.")
aj("You can retry installation; the partial files won't conflict.")
if not ar("Continue to questionnaire anyway?")then print(aD)return end;print()end
if au and bj(ao)then ah(0x00AAFF)print("--- Clean install ---")
ah(0xFFFFFF)ah(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
ah(0xFFFFFF)
aA=ar("Remove OpenOS leftovers for a clean install?")
ak(aA and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else ah(0xFFFF00)
print("No install disk detected - running in configuration mode.")
print("TOS system files must already be present on the boot drive.")ah(0xFFFFFF)print()
if not ar("Continue?")then print(aD)return end;print()end;local al=bm(aO)ah(0x00AAFF)print("--- Summary ---")
ah(0xAAAAAA)print("  Device:     "..al.device)print("  Hostname:   "..
al.hostname)
print("  Security:   ".. (al.autoLockout and
"Standard"or
(al.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (al.encryptComms and"Yes"or"No"))
if al.device==aR then
print("  Battery:    Warn at "..
al.lowBatWarn.."% / "..al.critBatWarn.."%")elseif al.device=="server"then
print("  Headless:   "..
(al.headless and"Yes"or"No"))
print("  Services:   "..
(al.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (al.verbose and"Yes"or"No"))if av and au then
print("  Clean inst: "..
(aA and"Yes (remove /bin, /boot, /lib)"or"No"))end;ah(0xFFFFFF)print()if not
ar("Apply these settings?")then print(aD)return end;print()
ah(0x00AAFF)print("--- Applying configuration ---")ah(0xFFFFFF)
if
ai then for b,a in ipairs(aI)do if not ai.isDirectory(ao..a)then
ai.makeDirectory(ao..a)end end end;if bn(al,ao)then
ak("Configuration saved to "..ao.."/etc/tos.cfg")else
aj("Could not save config (defaults will be used)")end;ak("Device profile: "..
al.device)print()
if av then if au then bl(ay)else
aj("Skipping BIOS flash: file copy did not fully verify.")aj("Re-run install.lua to retry before flashing.")
print()end end;local aF=false
if av and au and am and not am.isBoot then ah(0x00AAFF)
print("--- Boot drive ---")ah(0xFFFFFF)
print("TOS is on "..aM(am)..", but this machine")
print("boots from a different drive, so it would start that system.")
if ar("Boot from the TOS drive from now on?")then
local a,b=pcall(an.setBootAddress,am.address)if a then aF=true
ak("Boot drive set to "..am.address:sub(1,8))else
aj("Could not set the boot drive: "..tostring(b))end end
if not aF then
aj("The boot drive is unchanged. To switch later, run `lua` and type:")
print("  require('computer').setBootAddress('"..am.address.."')")end;print()end
if av and au and aA then ah(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")ah(0xFFFFFF)local a=bk(ao)
if#a>0 then
ak("Removed: "..table.concat(a,", "))
aj("OpenOS is no longer bootable on this drive — reboot into TOS.")else aj("Nothing to remove (already clean).")end;print()end;ah(0x00AAFF)print("--- Installation Complete ---")
ah(0xFFFFFF)print()ah(0x00FF00)
if av and au then
if
am and not am.isBoot and not aF then
print("TOS is installed, but this machine still boots from another drive.")else print("TOS is installed! Reboot to start.")end elseif av then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print("First boot asks you to set the root password before anything else.")if aA then ah(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")ah(0xFFFFFF)end
ah(0xFFFFFF)print()if ar("Reboot now?")then an.shutdown(true)end