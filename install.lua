
local aR,aI,aC,aJ,aS,aD,aT="/init.lua","/tos/kernel/init.lua","Cancelled.","^(.+)/[^/]+$","filesystem","string","tablet"local aq=require("component")local ao=require("computer")
local aE=require("term")local aj=nil
pcall(function()aj=require(aS)end)local aA=aq.gpu;local function ai(a)
if aA and aA.setForeground then pcall(aA.setForeground,a)end end;local function al(a)ai(0x00FF00)
print("  + "..a)ai(0xFFFFFF)end;local function ak(a)ai(0xFFFF00)
print("  ! "..a)ai(0xFFFFFF)end;local function ar(a)ai(0xFF0000)
print("  X "..a)ai(0xFFFFFF)end
local function as(c,b,a)ai(0xFFFF00)
io.write(c)if b then ai(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then ai(0x888888)
io.write(" (default: "..a..")")end;ai(0xFFFFFF)io.write(": ")local d
if aE and
aE.read then local e,f=pcall(aE.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function at(a)local b=as(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local aU="1.5.0"
local aK={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local aV={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function aW()ai(0x00AAFF)for b,a in ipairs(aV)do print("   "..a)end
ai(0xFFFFFF)print()ai(0x00FF66)print("   Strata Systems LLC")
ai(0xFFFFFF)ai(0xAAAAAA)
print("   Terminal Operating System — Setup v"..aU)ai(0xFFFFFF)print()end
local function aX(a)if not aj then return nil end;if type(a)==aD and a~=""then local d=a:sub(-1)=="/"and
a:sub(1,-2)or a
if aj.exists(d..aI)then return d end end;local b=
os.getenv and os.getenv("_")or nil
if b then
local d=b:match("^(.*)/[^/]+$")if d and d~=""and aj.exists(d..aI)then return d end end;local c=ao.getBootAddress()
for d in aq.list(aS)do
if d~=c then
local f,e=pcall(aq.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(aI)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then
if aj.mounts then local l,k=pcall(aj.mounts)if l and k then
for m,n in k do local o,p=m,n;if type(m)==
aD then o,p=n,m end;if type(o)=="table"and o.address==d then return
tostring(p)end end end end end end end;return nil end
local function aY()local a={}a.totalMem=ao.totalMemory()a.freeMem=ao.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if aA then local d,e=aA.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=ao.getBootAddress()local al,b=pcall(aq.proxy,c)if not al or not b then
b={spaceTotal=function()return 0 end,spaceUsed=function()return 0 end}end
a.diskTotal=b.spaceTotal()
a.diskFree=math.max(0,a.diskTotal-b.spaceUsed())a.diskKB=math.floor(a.diskTotal/1024)a.diskFreeKB=math.floor(
a.diskFree/1024)
a.hasModem,a.hasWireless,a.hasTunnel,a.hasDataCard=false,false,false,false;a.hasGPU,a.hasScreen,a.hasKeyboard=false,false,false
for e,d in aq.list()do
if d=="modem"then
a.hasModem=true
pcall(function()a.hasWireless=aq.proxy(e).isWireless()end)elseif d=="tunnel"then a.hasTunnel=true elseif d=="data"then a.hasDataCard=true elseif d=="gpu"then a.hasGPU=true elseif d==
"screen"then a.hasScreen=true elseif d=="keyboard"then a.hasKeyboard=true end end;return a end
local function aZ(a)ai(0x00AAFF)print("--- Hardware Detected ---")
ai(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))ai(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
ak("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
ak("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
ak("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
ak("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function aL(a)local c=a.."/tos/system_manifest.lua"if not aj.exists(c)then return nil,
"no manifest at "..c end
local d=io.open(c,"r")if not d then return nil,"cannot open manifest"end
local b=d:read("*a")d:close()if not b then return nil,"empty manifest"end
if
#b>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then local k,l=e.decode(b,{maxBytes=
256*1024})
if
k and type(k)=="table"then return k elseif k==nil then
ak("manifest serialize.decode failed ("..
tostring(l).."); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function a_(b,a)if b then return true end;a=a or""
if aj.exists(a.."/etc/users.dat")then local c=io.open(a..
"/etc/users.dat","r")
if c then local d=c:read("*a")
c:close()
if d and#d>0 then
ak("Existing TOS install detected (/etc/users.dat is populated).")
ak("Re-installing will overwrite users, configuration, and the")
ak("system tree but will NOT delete user data under /home or /tmp.")ai(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")ai(0xFFFFFF)local e=io.read()or""if e~="FORCE-WIPE"then
ar("Install aborted by safety check.")return false end end end end;return true end
local function ba(a,b)local d=io.open(a,"r")if not d then return false,"open source"end
local c=io.open(b,"w")if not c then d:close()return false,"open dest"end
while true do
local e=d:read(4096)if not e then break end;local f,g,h=pcall(c.write,c,e)
if not f or not g then d:close()
pcall(c.close,c)return false,
"write: "..tostring(f and(h or"failed")or g)end end;d:close()
if c.flush then local e,f,g=pcall(c.flush,c)
if not e or not f then
pcall(c.close,c)return false,"write: "..
tostring(e and(g or"flush failed")or f)end end;c:close()return true end
local function bb(b,c,a)a=a or""local d,e={},{}
for g,f in ipairs(c)do local h=a..f.path
if not aj.exists(h)then
d[#d+1]=h else local i=aj.size(b..f.path)or 0
local j=aj.size(h)or 0;if i~=j then
e[#e+1]=string.format("%s (src=%d dst=%d)",h,i,j)end end end;return d,e end;local aM=512
local function aN(d,e,b,c,a)a=a or""local f,g=0,{}
for i,h in ipairs(e)do local k=b(d..h.path)or 0;if
c(a..h.path)then
f=f+math.max(0,k- (b(a..h.path)or 0))else f=f+k+aM end
local j=h.path:match(aJ)while j and j~=""and not g[j]do g[j]=true;if not c(a..j)then f=f+aM end
j=j:match(aJ)end end;return f end
local function bc(a)
local d,b=pcall(aj.get,(a==nil or a=="")and"/"or a)if not d or not b then return nil end;local e,c=pcall(b.spaceTotal)
local f,g=pcall(b.spaceUsed)if not(e and f)or type(c)~="number"or c<=0 then
return nil end;return c-g end
local function bd(a)local b,c={},nil;for e,d in ipairs(a)do
b[e]=(d.free==nil)or(d.free>=d.need)end;for d,e in ipairs(a)do
if e.isBoot and b[d]then c=d;break end end;if not c then
for d=1,#a do if b[d]then c=d;break end end end;return c,b end
local function be(a)local b={positional={}}
for d,c in ipairs(a)do
if
c=="-h"or c=="--help"or c=="-?"or c=="/?"then b.help=true elseif c=="--configure"then b.configure=true elseif type(c)==
aD and c:sub(1,1)=="-"then b.unknown=b.unknown or c else b.positional[
#b.positional+1]=c end end;return b end
local function bf()local a={}if not(aj and aj.mounts)then return a end
local c,b=pcall(aj.mounts)if not c or type(b)~="function"then return a end
for d,e in b do local g,h=d,e;if
type(d)==aD then g,h=e,d end
local f=type(g)=="table"and g.address or nil
if f and type(h)==aD then a[f]=a[f]or{}a[f][#a[f]+1]=h end end;return a end
local function bg(a)
for c,b in ipairs(a)do if b:sub(1,5)=="/mnt/"then return b end end;for c,b in ipairs(a)do if b~="/"then return b end end;return nil end
local function ay(a)if a>=1024*1024 then
return string.format("%.1f MB",a/1024/1024)end;return
string.format("%d KB",math.floor(a/1024))end
local function aO(a,b)local e=bf()local f=ao.getBootAddress()local g=
ao.tmpAddress and ao.tmpAddress()or nil;local h=
a:sub(-1)=="/"and a:sub(1,-2)or a;local c,d={},0
for i in aq.list(aS)do
local k,j=pcall(aq.proxy,i)local l,m=false,true;if k and j then l,m=pcall(j.isReadOnly)end
if
i~=g and k and j and l and not m then local o=e[i]or{}local p=i==f
local n=p and""or bg(o)local q=false;for s,r in ipairs(o)do if r==h then q=true end end
if q then elseif not n then d=d+1 else
local r={address=i,prefix=n,isBoot=p}local t,u=pcall(j.getLabel)r.label=t and u or nil
local v,s=pcall(j.spaceTotal)local w,x=pcall(j.spaceUsed)if
v and w and type(s)=="number"and s>0 then r.total,r.free=s,s-x end
local y,z=pcall(j.exists,aR)local A,B=pcall(j.exists,aI)r.hasInit=y and z or false;r.hasTos=A and B or
false
r.need=b and aN(a,b,aj.size,aj.exists,n)or 0;c[#c+1]=r end end end
table.sort(c,function(i,j)if i.isBoot~=j.isBoot then return i.isBoot end;return
i.prefix<j.prefix end)return c,d end
local function aF(a)
local b=a.isBoot and"the boot drive"or("the drive at "..a.prefix)
if a.label and a.label~=""then b=b..' "'..a.label..'"'end;return b end
local function bh(a,b)local c,f=aO(a,b)if#c==0 then
return{address=ao.getBootAddress(),prefix="",isBoot=true,need=0}end;local d,e=bd(c)
if#c==1 and d==1 then return c[1]end;ai(0x00AAFF)print("--- Where should TOS go? ---")
ai(0xFFFFFF)
for h,g in ipairs(c)do if g.isBoot and g.free and g.free<g.need then
ak(string.format("The boot drive has %s free; TOS needs %s.",ay(g.free),ay(g.need)))end end
for h,g in ipairs(c)do
local j=string.format("  %d. %s%s",h,g.isBoot and"Boot drive"or g.prefix,
(g.label and
g.label~="")and('  "'..g.label..'"')or"")if e[h]then ai(0xFFFFFF)else ai(0x888888)end
print(j.. (
h==d and"   <- default"or""))
local k=
g.total and string.format("%s, %s free",ay(g.total),ay(g.free))or"size unknown"local i={}if g.hasTos then i[#i+1]="has TOS"elseif g.hasInit then i[#i+1]="has an OS"else
i[#i+1]="empty"end;if not e[h]then i[#i+1]="too small: needs "..
ay(g.need)end
ai(0xAAAAAA)
print("     "..k.."; "..table.concat(i,", "))end;ai(0xFFFFFF)if f>0 then
ak(f.." more drive(s) are not mounted, so they are not listed.")end
if not d then print()
ar("None of these drives has room for TOS.")
ak("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
ak("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")return nil,"space"end;print()
while true do
local h=as("Install on which drive? (0 = cancel)",nil,tostring(d))local g=tonumber(h)if g==0 then return nil end
if g and c[g]then
if e[g]then return c[g]end
ak("That drive is too small: TOS needs "..ay(c[g].need)..".")else ak("Type a number from the list.")end end end
local function bi()local b=aO("",nil)local a={}
for e,d in ipairs(b)do if d.hasTos then a[#a+1]=d end end;if#a==0 then
ar("No drive holds a TOS installation to configure.")
ak("Insert the TOS install disk to install it first.")return nil end;if
#a==1 then return a[1]end;ai(0x00AAFF)
print("--- Which TOS should be configured? ---")ai(0xFFFFFF)
for e,d in ipairs(a)do
print(string.format("  %d. %s%s",e,d.isBoot and"Boot drive"or d.prefix,
(
d.label and d.label~="")and('  "'..d.label..'"')or""))end;print()
while true do
local d=as("Configure which drive? (0 = cancel)",nil,"1")local c=tonumber(d)if c==0 then return nil end
if c and a[c]then return a[c]end;ak("Type a number from the list.")end end
local function bj(b,a,c)a=a or""local e,j=c,nil;if not e then e,j=aL(b)end;if not e then
ar("Cannot load install manifest: "..tostring(j))return false end;al("Manifest loaded: "..
#e.." files declared")
local i=aN(b,e,aj.size,aj.exists,a)local g=bc(a)
if g and i>g then print()
ar(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
i/1024),math.floor(g/1024)))
ak("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
ak("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")ak("holds TOS on its own.")return false,"space"end;if g then
al(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(i/1024),math.floor(g/1024)))end;print()
ai(0x00AAFF)print("--- Creating directories ---")ai(0xFFFFFF)
local k={}
for m,l in ipairs(e)do local n=l.path:match(aJ)
while n and n~=""and not k[n]do
k[n]=true
if not aj.isDirectory(a..n)then aj.makeDirectory(a..n)end;n=n:match(aJ)end end;for m,l in ipairs(aK)do if not aj.isDirectory(a..l)then
aj.makeDirectory(a..l)end end
al("Directory structure created")print()ai(0x00AAFF)
print("--- Copying system files ---")ai(0xFFFFFF)local h,d=0,0;local f={}
for m,l in ipairs(e)do local n=b..l.path;local o=a..l.path
if not
aj.exists(n)then d=d+1;f[#f+1]="missing on disk: "..l.path else
local p,q=ba(n,o)
if p then h=h+1 else d=d+1;f[#f+1]=l.path..": "..tostring(q)end end end;print()
if d==0 then al("Copied "..h.." files")else
ar("Copied "..h..
" files, "..d.." FAILED:")for l=1,math.min(5,#f)do ak("  "..f[l])end
if#f>5 then ak("  (+"..
(#f-5).." more)")end end;print()
if d==0 then ai(0x00AAFF)print("--- Verifying copy ---")
ai(0xFFFFFF)local l,m=bb(b,e,a)
if#l==0 and#m==0 then
al("All "..#e.." files verified")else
if#l>0 then ar(#l.." files MISSING after copy:")for n=1,math.min(5,
#l)do ak("  "..l[n])end;d=d+#l end
if#m>0 then
ar(#m.." files have WRONG SIZE after copy:")for n=1,math.min(5,#m)do ak("  "..m[n])end;d=d+#m end end;print()end;return d==0 end;local aP={"/bin","/boot","/lib"}local au="/init.lua.pre-tos"
local function bk(a)a=a or""if
not aj or not aj.exists(
a..aR)or aj.exists(a..au)then return false end
local c=io.open(a..aR,"r")if not c then return false end;local b=c:read("*a")c:close()if not b or b==""or
b:find("_TOS",1,true)then return false end
local d=io.open(a..au,"w")if not d then return false end;d:write(b)d:close()
return aj.exists(a..au)end
local function bl(a)a=a or""if not aj then return false end;for c,b in ipairs(aP)do
if aj.exists(a..b)then return true end end;return false end
local function bm(a)a=a or""local b={}if not aj then return b end;for d,c in ipairs(aP)do
if aj.exists(a..c)then
local e=pcall(aj.remove,a..c)if e and not aj.exists(a..c)then b[#b+1]=c end end end
if#b>0 and aj.exists(a..
au)then pcall(aj.remove,a..au)if not
aj.exists(a..au)then b[#b+1]=au end end;return b end
local function bn(a)local d=a.."/bios.lua"if not aj.exists(d)then return end
local c=io.open(d,"r")
if not c then ak("Could not read bios.lua")print()return end;local b=c:read("*a")c:close()if not b or#b==0 then
ak("Empty bios.lua")print()return end;local e="(unavailable)"
do
local i,h=pcall(require,"kernel.crypto")if i and h and h.hash then local j=h.hash(b)
if j then e=j:sub(1,16).."..."end end end;ai(0xFFFF00)
print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..e)ai(0xFFFFFF)
ai(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
ai(0xFFFFFF)local g=io.read()or""if g~="flash"then al("Skipped BIOS flash")
print()return end;local f=aq.list("eeprom")()
if f then
local h=aq.proxy(f)h.set(b)h.setLabel("TOS BIOS")
al("BIOS flashed! Label set to 'TOS BIOS'")else ak("No EEPROM found")end;print()end
local function bo(a)local b={}ai(0x00AAFF)print("--- Device Setup ---")
ai(0xFFFFFF)print()print("What type of device is this?")
ai(0xAAAAAA)
print("  1. Computer  (desktop, tower with screen)")
print("  2. Tablet    (portable, battery-powered)")
print("  3. Server    (rack blade, typically headless)")ai(0xFFFFFF)local c=as("Choice",{"1","2","3"},"1")
if c=="2"then
b.device=aT;b.showBattery=true;b.powerSave=true
al("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
al("Server mode (headless boot, services auto-start)")print()ai(0xFFFF00)print("  Server rack checklist:")
ai(0xAAAAAA)
if a.hasModem or a.hasTunnel then al("Network card detected")else
ak("No modem or linked card! The server will be unreachable.")
ak("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
al("Headless (no GPU/screen) — normal for servers")else
ak("GPU or screen detected — will boot headless anyway.")
ak("Remove them to free rack slots, or choose Computer mode.")end;ai(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
al("Computer mode")end;print()
math.randomseed(math.floor(ao.uptime()*1000)+
ao.freeMemory())
b.hostname=as("Hostname",nil,"tos-"..string.format("%04x",math.random(0,0xFFFF)))al("Hostname: "..b.hostname)print()
ai(0x00AAFF)print("--- Security ---")ai(0xFFFFFF)print()
print("Security level:")ai(0xAAAAAA)
print("  1. Standard  (login + lockout after 5 failures)")print("  2. Relaxed   (login, no lockout)")
print("  3. Open      (allows guest access)")ai(0xFFFFFF)local d=as("Choice",{"1","2","3"},"1")
if d=="3"then
b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999;al("Security: Open")elseif d=="2"then
b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999;al("Security: Relaxed")else
b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5;al("Security: Standard")end;print()
if a.hasModem or a.hasTunnel then ai(0x00AAFF)
print("--- Network ---")ai(0xFFFFFF)print()
b.encryptComms=at("Encrypt network communications?")
al("Encryption: ".. (b.encryptComms and"on"or"off"))local e=as("Listen port",nil,"42")
b.listenPort=tonumber(e)or 42;al("Port: "..b.listenPort)print()else
b.encryptComms=true;b.listenPort=42 end
if b.device==aT then ai(0x00AAFF)print("--- Tablet Options ---")
ai(0xFFFFFF)print()b.lowBatWarn=
tonumber(as("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(as("Critical battery warning %",
nil,"5"))or 5
al("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end;b.verbose=at("Verbose boot? (shows debug messages)")
print()return b end
local function bp(a,b)local c={"return {"}local d={}for f in pairs(a)do d[#d+1]=f end
table.sort(d)
for g,f in ipairs(d)do local h=a[f]if type(h)==aD then
c[#c+1]=string.format('  [%q] = %q,',f,h)else
c[#c+1]=string.format('  [%q] = %s,',f,tostring(h))end end;c[#c+1]="}"
local e=io.open((b or"").."/etc/tos.cfg","w")
if e then e:write(table.concat(c,"\n"))e:close()return true end;return false end;local aw=be({...})aE.clear()aW()
if aw.help or aw.unknown then if aw.unknown and
not aw.help then
ar("Unknown option: "..tostring(aw.unknown))print()end
print("Copies TOS onto a drive, asks a few setup questions, and")print("offers to flash the TOS BIOS.")print()
print("Usage:")print("  install.lua [source-dir]")
print("  install.lua --configure")print("  install.lua --help")print()
print("Run it from an install disk (/mnt/<disk>/install.lua), or")
print("let bootstrap.lua stage a download for it.")print()
print("With more than one writable drive it asks which one TOS")
print("goes on; the boot drive is only the default. If the boot")
print("drive is too small it offers the others. TOS can then be")print("made the boot drive at the end.")print()
print("source-dir  a directory holding a TOS release, for")
print("            scripted installs. Normally found by itself.")print()
print("--configure  only change the settings of a TOS that")
print("            is already installed, on whichever drive")
print("            holds it. Also what happens with no")
print("            install disk. (A second drive that holds")
print("            TOS reads as an install disk otherwise.)")return end;local aQ=aY()aZ(aQ)local az=
(not aw.configure)and aX(aw.positional[1])or nil;local ax=az~=nil
local ap,am="",nil;local aG;local av=false;local aB=false
if ax then
al("Install disk found at: "..az)print()aG=aL(az)local a;am,a=bh(az,aG)if not am then print()
if a~="space"then print(aC)end;return end;ap=am.prefix;print()ai(0xFFFF00)
if
am.isBoot then
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")else
print("TOS will be installed on "..aF(am)..".")
print("Its /init.lua will be replaced (the current one, if any, is kept")
print("there as /init.lua.pre-tos). The drive this machine boots from")
print("is not changed unless you choose that at the end.")end;ai(0xFFFFFF)print()
if not at("Continue?")then print(aC)return end;print()
if not a_(_G._FORCE_WIPE or false,ap)then return end;if bk(ap)then
al("Kept the previous /init.lua as "..ap..au)end;local b;av,b=bj(az,ap,aG)if b=="space"then print()
return end
if not av then
ar("Install file copy/verify did NOT fully succeed.")
ak("BIOS flash will be skipped to avoid bricking the boot.")
ak("You can retry installation; the partial files won't conflict.")
if not at("Continue to questionnaire anyway?")then print(aC)return end;print()end
if av and bl(ap)then ai(0x00AAFF)print("--- Clean install ---")
ai(0xFFFFFF)ai(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
ai(0xFFFFFF)
aB=at("Remove OpenOS leftovers for a clean install?")
al(aB and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else ai(0xFFFF00)
print("No install disk detected - running in configuration mode.")ai(0xFFFFFF)am=bi()if not am then print(aC)return end;ap=am.prefix
print(
"Configuring the TOS on "..aF(am)..".")print()if not at("Continue?")then print(aC)return end
print()end;local an=bo(aQ)ai(0x00AAFF)print("--- Summary ---")
ai(0xAAAAAA)print("  Device:     "..an.device)print("  Hostname:   "..
an.hostname)
print("  Security:   ".. (an.autoLockout and
"Standard"or
(an.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (an.encryptComms and"Yes"or"No"))
if an.device==aT then
print("  Battery:    Warn at "..
an.lowBatWarn.."% / "..an.critBatWarn.."%")elseif an.device=="server"then
print("  Headless:   "..
(an.headless and"Yes"or"No"))
print("  Services:   "..
(an.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (an.verbose and"Yes"or"No"))if ax and av then
print("  Clean inst: "..
(aB and"Yes (remove /bin, /boot, /lib)"or"No"))end;ai(0xFFFFFF)print()if not
at("Apply these settings?")then print(aC)return end;print()
ai(0x00AAFF)print("--- Applying configuration ---")ai(0xFFFFFF)
if
aj then for b,a in ipairs(aK)do if not aj.isDirectory(ap..a)then
aj.makeDirectory(ap..a)end end end;if bp(an,ap)then
al("Configuration saved to "..ap.."/etc/tos.cfg")else
ak("Could not save config (defaults will be used)")end;al("Device profile: "..
an.device)print()
if ax then if av then bn(az)else
ak("Skipping BIOS flash: file copy did not fully verify.")ak("Re-run install.lua to retry before flashing.")
print()end end;local aH=false
if ax and av and am and not am.isBoot then ai(0x00AAFF)
print("--- Boot drive ---")ai(0xFFFFFF)
print("TOS is on "..aF(am)..", but this machine")
print("boots from a different drive, so it would start that system.")
if at("Boot from the TOS drive from now on?")then
local a,b=pcall(ao.setBootAddress,am.address)if a then aH=true
al("Boot drive set to "..am.address:sub(1,8))else
ak("Could not set the boot drive: "..tostring(b))end end
if not aH then
ak("The boot drive is unchanged. To switch later, run `lua` and type:")
print("  require('computer').setBootAddress('"..am.address.."')")end;print()end
if ax and av and aB then ai(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")ai(0xFFFFFF)local a=bm(ap)
if#a>0 then
al("Removed: "..table.concat(a,", "))
ak("OpenOS is no longer bootable on this drive — reboot into TOS.")else ak("Nothing to remove (already clean).")end;print()end;ai(0x00AAFF)print("--- Installation Complete ---")
ai(0xFFFFFF)print()ai(0x00FF00)
if ax and av then
if
am and not am.isBoot and not aH then
print("TOS is installed, but this machine still boots from another drive.")else print("TOS is installed! Reboot to start.")end elseif ax then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print("First boot asks you to set the root password before anything else.")if aB then ai(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")ai(0xFFFFFF)end
ai(0xFFFFFF)print()if at("Reboot now?")then ao.shutdown(true)end