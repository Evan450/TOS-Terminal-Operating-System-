
local aS,aJ,aE,aK,aT,aB,aU="/init.lua","/tos/kernel/init.lua","Cancelled.","^(.+)/[^/]+$","filesystem","string","tablet"local ap=require("component")local aq=require("computer")
local aF=require("term")local ak=nil
pcall(function()ak=require(aT)end)local aC=ap.gpu;local function aj(a)
if aC and aC.setForeground then pcall(aC.setForeground,a)end end;local function am(a)aj(0x00FF00)
print("  + "..a)aj(0xFFFFFF)end;local function al(a)aj(0xFFFF00)
print("  ! "..a)aj(0xFFFFFF)end;local function as(a)aj(0xFF0000)
print("  X "..a)aj(0xFFFFFF)end
local function at(c,b,a)aj(0xFFFF00)
io.write(c)if b then aj(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then aj(0x888888)
io.write(" (default: "..a..")")end;aj(0xFFFFFF)io.write(": ")local d
if aF and
aF.read then local e,f=pcall(aF.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function au(a)local b=at(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local aV="1.5.0"
local aL={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local aW={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function aX()aj(0x00AAFF)for b,a in ipairs(aW)do print("   "..a)end
aj(0xFFFFFF)print()aj(0x00FF66)print("   Strata Systems LLC")
aj(0xFFFFFF)aj(0xAAAAAA)
print("   Terminal Operating System — Setup v"..aV)aj(0xFFFFFF)print()end
local function aY(a)if not ak then return nil end;if type(a)==aB and a~=""then local d=a:sub(-1)=="/"and
a:sub(1,-2)or a
if ak.exists(d..aJ)then return d end end;local b=
os.getenv and os.getenv("_")or nil
if b then
local d=b:match("^(.*)/[^/]+$")if d and d~=""and ak.exists(d..aJ)then return d end end;local c=aq.getBootAddress()
for d in ap.list(aT)do
if d~=c then
local f,e=pcall(ap.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(aJ)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then
if ak.mounts then local l,k=pcall(ak.mounts)if l and k then
for m,n in k do local o,p=m,n;if type(m)==
aB then o,p=n,m end;if type(o)=="table"and o.address==d then return
tostring(p)end end end end end end end;return nil end
local function aZ()local a={}a.totalMem=aq.totalMemory()a.freeMem=aq.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if aC then local d,e=aC.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=aq.getBootAddress()local am,b=pcall(ap.proxy,c)if not am or not b then
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
local function a_(a)aj(0x00AAFF)print("--- Hardware Detected ---")
aj(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))aj(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
al("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
al("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
al("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
al("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function aM(a)local c=a.."/tos/system_manifest.lua"if not ak.exists(c)then return nil,
"no manifest at "..c end
local d=io.open(c,"r")if not d then return nil,"cannot open manifest"end
local b=d:read("*a")d:close()if not b then return nil,"empty manifest"end
if
#b>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then local k,l=e.decode(b,{maxBytes=
256*1024})
if
k and type(k)=="table"then return k elseif k==nil then
al("manifest serialize.decode failed ("..
tostring(l).."); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function ba(b,a)if b then return true end;a=a or""
if ak.exists(a.."/etc/users.dat")then local c=io.open(a..
"/etc/users.dat","r")
if c then local d=c:read("*a")
c:close()
if d and#d>0 then
al("Existing TOS install detected (/etc/users.dat is populated).")
al("Re-installing will overwrite users, configuration, and the")
al("system tree but will NOT delete user data under /home or /tmp.")aj(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")aj(0xFFFFFF)local e=io.read()or""if e~="FORCE-WIPE"then
as("Install aborted by safety check.")return false end end end end;return true end
local function bb(a,b)local d=io.open(a,"r")if not d then return false,"open source"end
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
local function bc(b,c,a)a=a or""local d,e={},{}
for g,f in ipairs(c)do local h=a..f.path
if not ak.exists(h)then
d[#d+1]=h else local i=ak.size(b..f.path)or 0
local j=ak.size(h)or 0;if i~=j then
e[#e+1]=string.format("%s (src=%d dst=%d)",h,i,j)end end end;return d,e end;local aN=512
local function aO(d,e,b,c,a)a=a or""local f,g=0,{}
for i,h in ipairs(e)do local k=b(d..h.path)or 0;if
c(a..h.path)then
f=f+math.max(0,k- (b(a..h.path)or 0))else f=f+k+aN end
local j=h.path:match(aK)while j and j~=""and not g[j]do g[j]=true;if not c(a..j)then f=f+aN end
j=j:match(aK)end end;return f end
local function bd(a)
local d,b=pcall(ak.get,(a==nil or a=="")and"/"or a)if not d or not b then return nil end;local e,c=pcall(b.spaceTotal)
local f,g=pcall(b.spaceUsed)if not(e and f)or type(c)~="number"or c<=0 then
return nil end;return c-g end
local function be(a)local b,c={},nil;for e,d in ipairs(a)do
b[e]=(d.free==nil)or(d.free>=d.need)end;for d,e in ipairs(a)do
if e.isBoot and b[d]then c=d;break end end;if not c then
for d=1,#a do if b[d]then c=d;break end end end;return c,b end
local function bf(a)local b={positional={}}
for d,c in ipairs(a)do
if
c=="-h"or c=="--help"or c=="-?"or c=="/?"then b.help=true elseif c=="--configure"then b.configure=true elseif type(c)==
aB and c:sub(1,1)=="-"then b.unknown=b.unknown or c else b.positional[
#b.positional+1]=c end end;return b end
local function bg()local a={}if not(ak and ak.mounts)then return a end
local c,b=pcall(ak.mounts)if not c or type(b)~="function"then return a end
for d,e in b do local g,h=d,e;if
type(d)==aB then g,h=e,d end
local f=type(g)=="table"and g.address or nil
if f and type(h)==aB then a[f]=a[f]or{}a[f][#a[f]+1]=h end end;return a end
local function bh(a)
for c,b in ipairs(a)do if b:sub(1,5)=="/mnt/"then return b end end;for c,b in ipairs(a)do if b~="/"then return b end end;return nil end
local function az(a)if a>=1024*1024 then
return string.format("%.1f MB",a/1024/1024)end;return
string.format("%d KB",math.floor(a/1024))end
local function aP(a,b)local e=bg()local f=aq.getBootAddress()local g=
aq.tmpAddress and aq.tmpAddress()or nil;local h=
a:sub(-1)=="/"and a:sub(1,-2)or a;local c,d={},0
for i in ap.list(aT)do
local k,j=pcall(ap.proxy,i)local l,m=false,true;if k and j then l,m=pcall(j.isReadOnly)end
if
i~=g and k and j and l and not m then local o=e[i]or{}local p=i==f
local n=p and""or bh(o)local q=false;for s,r in ipairs(o)do if r==h then q=true end end
if q then elseif not n then d=d+1 else
local r={address=i,prefix=n,isBoot=p}local t,u=pcall(j.getLabel)r.label=t and u or nil
local v,s=pcall(j.spaceTotal)local w,x=pcall(j.spaceUsed)if
v and w and type(s)=="number"and s>0 then r.total,r.free=s,s-x end
local y,z=pcall(j.exists,aS)local A,B=pcall(j.exists,aJ)r.hasInit=y and z or false;r.hasTos=A and B or
false
r.need=b and aO(a,b,ak.size,ak.exists,n)or 0;c[#c+1]=r end end end
table.sort(c,function(i,j)if i.isBoot~=j.isBoot then return i.isBoot end;return
i.prefix<j.prefix end)return c,d end
local function aG(a)
local b=a.isBoot and"the boot drive"or("the drive at "..a.prefix)
if a.label and a.label~=""then b=b..' "'..a.label..'"'end;return b end
local function bi(a,b)local c,f=aP(a,b)if#c==0 then
return{address=aq.getBootAddress(),prefix="",isBoot=true,need=0}end;local d,e=be(c)
if#c==1 and d==1 then return c[1]end;aj(0x00AAFF)print("--- Where should TOS go? ---")
aj(0xFFFFFF)
for h,g in ipairs(c)do if g.isBoot and g.free and g.free<g.need then
al(string.format("The boot drive has %s free; TOS needs %s.",az(g.free),az(g.need)))end end
for h,g in ipairs(c)do
local j=string.format("  %d. %s%s",h,g.isBoot and"Boot drive"or g.prefix,
(g.label and
g.label~="")and('  "'..g.label..'"')or"")if e[h]then aj(0xFFFFFF)else aj(0x888888)end
print(j.. (
h==d and"   <- default"or""))
local k=
g.total and string.format("%s, %s free",az(g.total),az(g.free))or"size unknown"local i={}if g.hasTos then i[#i+1]="has TOS"elseif g.hasInit then i[#i+1]="has an OS"else
i[#i+1]="empty"end;if not e[h]then i[#i+1]="too small: needs "..
az(g.need)end
aj(0xAAAAAA)
print("     "..k.."; "..table.concat(i,", "))end;aj(0xFFFFFF)if f>0 then
al(f.." more drive(s) are not mounted, so they are not listed.")end
if not d then print()
as("None of these drives has room for TOS.")
al("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
al("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")return nil,"space"end;print()
while true do
local h=at("Install on which drive? (0 = cancel)",nil,tostring(d))local g=tonumber(h)if g==0 then return nil end
if g and c[g]then
if e[g]then return c[g]end
al("That drive is too small: TOS needs "..az(c[g].need)..".")else al("Type a number from the list.")end end end
local function bj()local b=aP("",nil)local a={}
for e,d in ipairs(b)do if d.hasTos then a[#a+1]=d end end;if#a==0 then
as("No drive holds a TOS installation to configure.")
al("Insert the TOS install disk to install it first.")return nil end;if
#a==1 then return a[1]end;aj(0x00AAFF)
print("--- Which TOS should be configured? ---")aj(0xFFFFFF)
for e,d in ipairs(a)do
print(string.format("  %d. %s%s",e,d.isBoot and"Boot drive"or d.prefix,
(
d.label and d.label~="")and('  "'..d.label..'"')or""))end;print()
while true do
local d=at("Configure which drive? (0 = cancel)",nil,"1")local c=tonumber(d)if c==0 then return nil end
if c and a[c]then return a[c]end;al("Type a number from the list.")end end
local function bk(b,a,c)a=a or""local e,j=c,nil;if not e then e,j=aM(b)end;if not e then
as("Cannot load install manifest: "..tostring(j))return false end;am("Manifest loaded: "..
#e.." files declared")
local i=aO(b,e,ak.size,ak.exists,a)local g=bd(a)
if g and i>g then print()
as(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
i/1024),math.floor(g/1024)))
al("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
al("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")al("holds TOS on its own.")return false,"space"end;if g then
am(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(i/1024),math.floor(g/1024)))end;print()
aj(0x00AAFF)print("--- Creating directories ---")aj(0xFFFFFF)
local k={}
for m,l in ipairs(e)do local n=l.path:match(aK)
while n and n~=""and not k[n]do
k[n]=true
if not ak.isDirectory(a..n)then ak.makeDirectory(a..n)end;n=n:match(aK)end end;for m,l in ipairs(aL)do if not ak.isDirectory(a..l)then
ak.makeDirectory(a..l)end end
am("Directory structure created")print()aj(0x00AAFF)
print("--- Copying system files ---")aj(0xFFFFFF)local h,d=0,0;local f={}
for m,l in ipairs(e)do local n=b..l.path;local o=a..l.path
if not
ak.exists(n)then d=d+1;f[#f+1]="missing on disk: "..l.path else
local p,q=bb(n,o)
if p then h=h+1 else d=d+1;f[#f+1]=l.path..": "..tostring(q)end end end;print()
if d==0 then am("Copied "..h.." files")else
as("Copied "..h..
" files, "..d.." FAILED:")for l=1,math.min(5,#f)do al("  "..f[l])end
if#f>5 then al("  (+"..
(#f-5).." more)")end end;print()
if d==0 then aj(0x00AAFF)print("--- Verifying copy ---")
aj(0xFFFFFF)local l,m=bc(b,e,a)
if#l==0 and#m==0 then
am("All "..#e.." files verified")else
if#l>0 then as(#l.." files MISSING after copy:")for n=1,math.min(5,
#l)do al("  "..l[n])end;d=d+#l end
if#m>0 then
as(#m.." files have WRONG SIZE after copy:")for n=1,math.min(5,#m)do al("  "..m[n])end;d=d+#m end end;print()end;return d==0 end;local aQ={"/bin","/boot","/lib"}local av="/init.lua.pre-tos"
local function bl(a)a=a or""if
not ak or not ak.exists(
a..aS)or ak.exists(a..av)then return false end
local c=io.open(a..aS,"r")if not c then return false end;local b=c:read("*a")c:close()if not b or b==""or
b:find("_TOS",1,true)then return false end
local d=io.open(a..av,"w")if not d then return false end;d:write(b)d:close()
return ak.exists(a..av)end
local function bm(a)a=a or""if not ak then return false end;for c,b in ipairs(aQ)do
if ak.exists(a..b)then return true end end;return false end
local function bn(a)a=a or""local b={}if not ak then return b end;for d,c in ipairs(aQ)do
if ak.exists(a..c)then
local e=pcall(ak.remove,a..c)if e and not ak.exists(a..c)then b[#b+1]=c end end end
if#b>0 and ak.exists(a..
av)then pcall(ak.remove,a..av)if not
ak.exists(a..av)then b[#b+1]=av end end;return b end
local function bo(a,b)
if ap.isAvailable("data")then local k,j=pcall(ap.data.sha256,a)
if k and
type(j)==aB and#j==32 then return
(j:gsub(".",function(l)
return("%02x"):format(l:byte())end))end end
local c=io.open(b.."/tos/kernel/sha256.lua","r")if not c then return nil end;local e=c:read("*a")c:close()
local f=e and
load(e,"=sha256","t",{string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,error=error,assert=assert,setmetatable=setmetatable})if not f then return nil end;local g,d=pcall(f)if not
(g and type(d)=="table"and d.hex)then return nil end
local h,i=pcall(d.hex,a)return h and i or nil end
local function bp(a)local d=a.."/bios.lua"if not ak.exists(d)then return end
local c=io.open(d,"r")
if not c then al("Could not read bios.lua")print()return end;local b=c:read("*a")c:close()if not b or#b==0 then
al("Empty bios.lua")print()return end;local e=bo(b,a)local g=e and
(e:sub(1,16).."...")or"(unavailable)"
aj(0xFFFF00)print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..g)aj(0xFFFFFF)
aj(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
aj(0xFFFFFF)local h=io.read()or""if h~="flash"then am("Skipped BIOS flash")
print()return end;local f=ap.list("eeprom")()
if f then
local i=ap.proxy(f)i.set(b)i.setLabel("TOS BIOS")
am("BIOS flashed! Label set to 'TOS BIOS'")else al("No EEPROM found")end;print()end
local function bq(a)local b={}aj(0x00AAFF)print("--- Device Setup ---")
aj(0xFFFFFF)print()print("What type of device is this?")
aj(0xAAAAAA)
print("  1. Computer  (desktop, tower with screen)")
print("  2. Tablet    (portable, battery-powered)")
print("  3. Server    (rack blade, typically headless)")aj(0xFFFFFF)local c=at("Choice",{"1","2","3"},"1")
if c=="2"then
b.device=aU;b.showBattery=true;b.powerSave=true
am("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
am("Server mode (headless boot, services auto-start)")print()aj(0xFFFF00)print("  Server rack checklist:")
aj(0xAAAAAA)
if a.hasModem or a.hasTunnel then am("Network card detected")else
al("No modem or linked card! The server will be unreachable.")
al("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
am("Headless (no GPU/screen) — normal for servers")else
al("GPU or screen detected — will boot headless anyway.")
al("Remove them to free rack slots, or choose Computer mode.")end;aj(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
am("Computer mode")end;print()
math.randomseed(math.floor(aq.uptime()*1000)+
aq.freeMemory())
b.hostname=at("Hostname",nil,"tos-"..string.format("%04x",math.random(0,0xFFFF)))am("Hostname: "..b.hostname)print()
aj(0x00AAFF)print("--- Security ---")aj(0xFFFFFF)print()
print("Security level:")aj(0xAAAAAA)
print("  1. Standard  (login + lockout after 5 failures)")print("  2. Relaxed   (login, no lockout)")
print("  3. Open      (allows guest access)")aj(0xFFFFFF)local d=at("Choice",{"1","2","3"},"1")
if d=="3"then
b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999;am("Security: Open")elseif d=="2"then
b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999;am("Security: Relaxed")else
b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5;am("Security: Standard")end;print()
if a.hasModem or a.hasTunnel then aj(0x00AAFF)
print("--- Network ---")aj(0xFFFFFF)print()
b.encryptComms=au("Encrypt network communications?")
am("Encryption: ".. (b.encryptComms and"on"or"off"))local e=at("Listen port",nil,"42")
b.listenPort=tonumber(e)or 42;am("Port: "..b.listenPort)print()else
b.encryptComms=true;b.listenPort=42 end
if b.device==aU then aj(0x00AAFF)print("--- Tablet Options ---")
aj(0xFFFFFF)print()b.lowBatWarn=
tonumber(at("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(at("Critical battery warning %",
nil,"5"))or 5
am("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end;b.verbose=au("Verbose boot? (shows debug messages)")
print()return b end
local function br(a,b)local c={"return {"}local d={}for f in pairs(a)do d[#d+1]=f end
table.sort(d)
for g,f in ipairs(d)do local h=a[f]if type(h)==aB then
c[#c+1]=string.format('  [%q] = %q,',f,h)else
c[#c+1]=string.format('  [%q] = %s,',f,tostring(h))end end;c[#c+1]="}"
local e=io.open((b or"").."/etc/tos.cfg","w")
if e then e:write(table.concat(c,"\n"))e:close()return true end;return false end;local ax=bf({...})aF.clear()aX()
if ax.help or ax.unknown then if ax.unknown and
not ax.help then
as("Unknown option: "..tostring(ax.unknown))print()end
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
print("            TOS reads as an install disk otherwise.)")return end;local aR=aZ()a_(aR)local aA=
(not ax.configure)and aY(ax.positional[1])or nil;local ay=aA~=nil
local ar,an="",nil;local aH;local aw=false;local aD=false
if ay then
am("Install disk found at: "..aA)print()aH=aM(aA)local a;an,a=bi(aA,aH)if not an then print()
if a~="space"then print(aE)end;return end;ar=an.prefix;print()aj(0xFFFF00)
if
an.isBoot then
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")else
print("TOS will be installed on "..aG(an)..".")
print("Its /init.lua will be replaced (the current one, if any, is kept")
print("there as /init.lua.pre-tos). The drive this machine boots from")
print("is not changed unless you choose that at the end.")end;aj(0xFFFFFF)print()
if not au("Continue?")then print(aE)return end;print()
if not ba(_G._FORCE_WIPE or false,ar)then return end;if bl(ar)then
am("Kept the previous /init.lua as "..ar..av)end;local b;aw,b=bk(aA,ar,aH)if b=="space"then print()
return end
if not aw then
as("Install file copy/verify did NOT fully succeed.")
al("BIOS flash will be skipped to avoid bricking the boot.")
al("You can retry installation; the partial files won't conflict.")
if not au("Continue to questionnaire anyway?")then print(aE)return end;print()end
if aw and bm(ar)then aj(0x00AAFF)print("--- Clean install ---")
aj(0xFFFFFF)aj(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
aj(0xFFFFFF)
aD=au("Remove OpenOS leftovers for a clean install?")
am(aD and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else aj(0xFFFF00)
print("No install disk detected - running in configuration mode.")aj(0xFFFFFF)an=bj()if not an then print(aE)return end;ar=an.prefix
print(
"Configuring the TOS on "..aG(an)..".")print()if not au("Continue?")then print(aE)return end
print()end;local ao=bq(aR)aj(0x00AAFF)print("--- Summary ---")
aj(0xAAAAAA)print("  Device:     "..ao.device)print("  Hostname:   "..
ao.hostname)
print("  Security:   ".. (ao.autoLockout and
"Standard"or
(ao.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (ao.encryptComms and"Yes"or"No"))
if ao.device==aU then
print("  Battery:    Warn at "..
ao.lowBatWarn.."% / "..ao.critBatWarn.."%")elseif ao.device=="server"then
print("  Headless:   "..
(ao.headless and"Yes"or"No"))
print("  Services:   "..
(ao.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (ao.verbose and"Yes"or"No"))if ay and aw then
print("  Clean inst: "..
(aD and"Yes (remove /bin, /boot, /lib)"or"No"))end;aj(0xFFFFFF)print()if not
au("Apply these settings?")then print(aE)return end;print()
aj(0x00AAFF)print("--- Applying configuration ---")aj(0xFFFFFF)
if
ak then for b,a in ipairs(aL)do if not ak.isDirectory(ar..a)then
ak.makeDirectory(ar..a)end end end;if br(ao,ar)then
am("Configuration saved to "..ar.."/etc/tos.cfg")else
al("Could not save config (defaults will be used)")end;am("Device profile: "..
ao.device)print()
if ay then if aw then bp(aA)else
al("Skipping BIOS flash: file copy did not fully verify.")al("Re-run install.lua to retry before flashing.")
print()end end;local aI=false
if ay and aw and an and not an.isBoot then aj(0x00AAFF)
print("--- Boot drive ---")aj(0xFFFFFF)
print("TOS is on "..aG(an)..", but this machine")
print("boots from a different drive, so it would start that system.")
if au("Boot from the TOS drive from now on?")then
local a,b=pcall(aq.setBootAddress,an.address)if a then aI=true
am("Boot drive set to "..an.address:sub(1,8))else
al("Could not set the boot drive: "..tostring(b))end end
if not aI then
al("The boot drive is unchanged. To switch later, run `lua` and type:")
print("  require('computer').setBootAddress('"..an.address.."')")end;print()end
if ay and aw and aD then aj(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")aj(0xFFFFFF)local a=bn(ar)
if#a>0 then
am("Removed: "..table.concat(a,", "))
al("OpenOS is no longer bootable on this drive — reboot into TOS.")else al("Nothing to remove (already clean).")end;print()end;aj(0x00AAFF)print("--- Installation Complete ---")
aj(0xFFFFFF)print()aj(0x00FF00)
if ay and aw then
if
an and not an.isBoot and not aI then
print("TOS is installed, but this machine still boots from another drive.")else print("TOS is installed! Reboot to start.")end elseif ay then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print("First boot asks you to set the root password before anything else.")if aD then aj(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")aj(0xFFFFFF)end
aj(0xFFFFFF)print()if au("Reboot now?")then aq.shutdown(true)end