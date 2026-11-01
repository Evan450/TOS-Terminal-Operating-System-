
local bg,aT,aP,aU,bh,aV,aL,bi="/init.lua","/tos/kernel/init.lua","Cancelled.","^(.+)/[^/]+$","filesystem","minimal","string","tablet"local az=require("component")local aA=require("computer")
local aQ=require("term")local as=nil
pcall(function()as=require(bh)end)local aM=az.gpu;local function ar(a)
if aM and aM.setForeground then pcall(aM.setForeground,a)end end;local function au(a)ar(0x00FF00)
print("  + "..a)ar(0xFFFFFF)end;local function at(a)ar(0xFFFF00)
print("  ! "..a)ar(0xFFFFFF)end;local function aB(a)ar(0xFF0000)
print("  X "..a)ar(0xFFFFFF)end;local aW={}
local function av(a,b)return aW[a]or b end
local function bj(a,b,c)local e={{code="en",name="English"}}local d={}
for f in b(a)do d[#d+1]=f end;table.sort(d)
for g,f in ipairs(d)do local i=f:match("^(%a+)%.lang$")local j=i and
c(a.."/"..f)local k=j and load(j,"="..f,"t",{})local l,h=false,
nil;if k then l,h=pcall(k)end
if l and type(h)=="table"and
type(h.strings)=="table"then local m=
type(h.meta)=="table"and h.meta or{}
e[#e+1]={code=i,name=tostring(m.name or i),strings=h.strings}end end;return e end
local function aC(c,b,a)ar(0xFFFF00)io.write(c)
if b then ar(0xAAAAAA)io.write(" ["..
table.concat(b,"/").."]")end;if a then ar(0x888888)
io.write(" (default: "..a..")")end;ar(0xFFFFFF)io.write(": ")local d
if aQ and
aQ.read then local e,f=pcall(aQ.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function aD(a)local b=aC(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local bk="1.5.0"
local aX={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local bl={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function bm()ar(0x00AAFF)for b,a in ipairs(bl)do print("   "..a)end
ar(0xFFFFFF)print()ar(0x00FF66)print("   Strata Systems LLC")
ar(0xFFFFFF)ar(0xAAAAAA)
print("   Terminal Operating System — Setup v"..bk)ar(0xFFFFFF)print()end
local function bn(a)if not as then return nil end;if type(a)==aL and a~=""then local d=a:sub(-1)=="/"and
a:sub(1,-2)or a
if as.exists(d..aT)then return d end end;local b=
os.getenv and os.getenv("_")or nil
if b then
local d=b:match("^(.*)/[^/]+$")if d and d~=""and as.exists(d..aT)then return d end end;local c=aA.getBootAddress()
for d in az.list(bh)do
if d~=c then
local f,e=pcall(az.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(aT)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then
if as.mounts then local l,k=pcall(as.mounts)if l and k then
for m,n in k do local o,p=m,n;if type(m)==
aL then o,p=n,m end;if type(o)=="table"and o.address==d then return
tostring(p)end end end end end end end;return nil end
local function bo()local a={}a.totalMem=aA.totalMemory()a.freeMem=aA.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if aM then local d,e=aM.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=aA.getBootAddress()local au,b=pcall(az.proxy,c)if not au or not b then
b={spaceTotal=function()return 0 end,spaceUsed=function()return 0 end}end
a.diskTotal=b.spaceTotal()
a.diskFree=math.max(0,a.diskTotal-b.spaceUsed())a.diskKB=math.floor(a.diskTotal/1024)a.diskFreeKB=math.floor(
a.diskFree/1024)
a.hasModem,a.hasWireless,a.hasTunnel,a.hasDataCard=false,false,false,false;a.hasGPU,a.hasScreen,a.hasKeyboard=false,false,false
for e,d in az.list()do
if d=="modem"then
a.hasModem=true
pcall(function()a.hasWireless=az.proxy(e).isWireless()end)elseif d=="tunnel"then a.hasTunnel=true elseif d=="data"then a.hasDataCard=true elseif d=="gpu"then a.hasGPU=true elseif d==
"screen"then a.hasScreen=true elseif d=="keyboard"then a.hasKeyboard=true end end;return a end
local function bp(a)ar(0x00AAFF)print("--- Hardware Detected ---")
ar(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))ar(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
at("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
at("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
at("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
at("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function aY(a)local c=a.."/tos/system_manifest.lua"if not as.exists(c)then return nil,
"no manifest at "..c end
local d=io.open(c,"r")if not d then return nil,"cannot open manifest"end
local b=d:read("*a")d:close()if not b then return nil,"empty manifest"end
if
#b>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then local k,l=e.decode(b,{maxBytes=
256*1024})
if
k and type(k)=="table"then return k elseif k==nil then
at("manifest serialize.decode failed ("..
tostring(l).."); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function bq(b,a)if b then return true end;a=a or""
if as.exists(a.."/etc/users.dat")then local c=io.open(a..
"/etc/users.dat","r")
if c then local d=c:read("*a")
c:close()
if d and#d>0 then
at("Existing TOS install detected (/etc/users.dat is populated).")
at("Re-installing will overwrite users, configuration, and the")
at("system tree but will NOT delete user data under /home or /tmp.")ar(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")ar(0xFFFFFF)local e=io.read()or""if e~="FORCE-WIPE"then
aB("Install aborted by safety check.")return false end end end end;return true end
local function br(a,b)local d=io.open(a,"r")if not d then return false,"open source"end
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
local function bs(b,c,a)a=a or""local d,e={},{}
for g,f in ipairs(c)do local h=a..f.path
if not as.exists(h)then
d[#d+1]=h else local i=as.size(b..f.path)or 0
local j=as.size(h)or 0;if i~=j then
e[#e+1]=string.format("%s (src=%d dst=%d)",h,i,j)end end end;return d,e end;local aZ=512
local function a_(d,e,b,c,a)a=a or""local f,g=0,{}
for i,h in ipairs(e)do local k=b(d..h.path)or 0;if
c(a..h.path)then
f=f+math.max(0,k- (b(a..h.path)or 0))else f=f+k+aZ end
local j=h.path:match(aU)while j and j~=""and not g[j]do g[j]=true;if not c(a..j)then f=f+aZ end
j=j:match(aU)end end;return f end
local function bt(a)
local d,b=pcall(as.get,(a==nil or a=="")and"/"or a)if not d or not b then return nil end;local e,c=pcall(b.spaceTotal)
local f,g=pcall(b.spaceUsed)if not(e and f)or type(c)~="number"or c<=0 then
return nil end;return c-g end
local function bu(a)local b,c={},nil;for e,d in ipairs(a)do
b[e]=(d.free==nil)or(d.free>=d.need)end;for d,e in ipairs(a)do
if e.isBoot and b[d]then c=d;break end end;if not c then
for d=1,#a do if b[d]then c=d;break end end end;return c,b end
local function bv(a)local b={positional={}}local c=1
while c<=#a do local d=a[c]
if
d=="-h"or d=="--help"or d=="-?"or d=="/?"then b.help=true elseif d=="--configure"then b.configure=true elseif
d=="--profile"then c=c+1;if a[c]==aV or a[c]=="full"then b.profile=a[c]else
b.unknown=b.unknown or("--profile "..
tostring(a[c]))end elseif type(d)==aL and d:sub(1,1)==
"-"then b.unknown=b.unknown or d else
b.positional[#b.positional+1]=d end;c=c+1 end;return b end;local function ba(a,b)if b~=aV then return a end;local c={}
for e,d in ipairs(a)do if d.floor then c[#c+1]=d end end;return c end
local function bw(a)
local b={"-- Written by install.lua: the files this profile installed.","return {"}
for d,c in ipairs(a)do
local e={string.format("path = %q",c.path),"critical = "..
tostring(c.critical==true)}if c.floor then e[#e+1]="floor = true"end;if c.hash then
e[#e+1]=string.format("hash = %q",c.hash)end;b[#b+1]="  { "..
table.concat(e,", ").." },"end;b[#b+1]="}"return table.concat(b,"\n").."\n"end
local function bx()local a={}if not(as and as.mounts)then return a end
local c,b=pcall(as.mounts)if not c or type(b)~="function"then return a end
for d,e in b do local g,h=d,e;if
type(d)==aL then g,h=e,d end
local f=type(g)=="table"and g.address or nil
if f and type(h)==aL then a[f]=a[f]or{}a[f][#a[f]+1]=h end end;return a end
local function by(a)
for c,b in ipairs(a)do if b:sub(1,5)=="/mnt/"then return b end end;for c,b in ipairs(a)do if b~="/"then return b end end;return nil end
local function aK(a)if a>=1024*1024 then
return string.format("%.1f MB",a/1024/1024)end;return
string.format("%d KB",math.floor(a/1024))end
local function bb(a,b)local e=bx()local f=aA.getBootAddress()local g=
aA.tmpAddress and aA.tmpAddress()or nil;local h=
a:sub(-1)=="/"and a:sub(1,-2)or a;local c,d={},0
for i in az.list(bh)do
local k,j=pcall(az.proxy,i)local l,m=false,true;if k and j then l,m=pcall(j.isReadOnly)end
if
i~=g and k and j and l and not m then local o=e[i]or{}local p=i==f
local n=p and""or by(o)local q=false;for s,r in ipairs(o)do if r==h then q=true end end
if q then elseif not n then d=d+1 else
local r={address=i,prefix=n,isBoot=p}local t,u=pcall(j.getLabel)r.label=t and u or nil
local v,s=pcall(j.spaceTotal)local w,x=pcall(j.spaceUsed)if
v and w and type(s)=="number"and s>0 then r.total,r.free=s,s-x end
local y,z=pcall(j.exists,bg)local A,B=pcall(j.exists,aT)r.hasInit=y and z or false;r.hasTos=A and B or
false
r.need=b and a_(a,b,as.size,as.exists,n)or 0;c[#c+1]=r end end end
table.sort(c,function(i,j)if i.isBoot~=j.isBoot then return i.isBoot end;return
i.prefix<j.prefix end)return c,d end
local function aR(a)
local b=a.isBoot and"the boot drive"or("the drive at "..a.prefix)
if a.label and a.label~=""then b=b..' "'..a.label..'"'end;return b end
local function bc(a,b)local c,f=bb(a,b)if#c==0 then
return{address=aA.getBootAddress(),prefix="",isBoot=true,need=0}end;local d,e=bu(c)
if#c==1 and d==1 then return c[1]end;ar(0x00AAFF)
print(av("install.where","--- Where should TOS go? ---"))ar(0xFFFFFF)
for h,g in ipairs(c)do if g.isBoot and g.free and g.free<g.need then
at(string.format("The boot drive has %s free; TOS needs %s.",aK(g.free),aK(g.need)))end end
for h,g in ipairs(c)do
local j=string.format("  %d. %s%s",h,g.isBoot and"Boot drive"or g.prefix,
(g.label and
g.label~="")and('  "'..g.label..'"')or"")if e[h]then ar(0xFFFFFF)else ar(0x888888)end
print(j.. (
h==d and"   <- default"or""))
local k=
g.total and string.format("%s, %s free",aK(g.total),aK(g.free))or"size unknown"local i={}if g.hasTos then i[#i+1]="has TOS"elseif g.hasInit then i[#i+1]="has an OS"else
i[#i+1]="empty"end;if not e[h]then i[#i+1]="too small: needs "..
aK(g.need)end
ar(0xAAAAAA)
print("     "..k.."; "..table.concat(i,", "))end;ar(0xFFFFFF)if f>0 then
at(f.." more drive(s) are not mounted, so they are not listed.")end
if not d then print()
aB("None of these drives has room for TOS.")
at("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
at("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")return nil,"space"end;print()
while true do
local h=aC(av("install.which_drive","Install on which drive? (0 = cancel)"),nil,tostring(d))local g=tonumber(h)if g==0 then return nil end
if g and c[g]then
if e[g]then return c[g]end
at("That drive is too small: TOS needs "..aK(c[g].need)..".")else at("Type a number from the list.")end end end
local function bz()local b=bb("",nil)local a={}
for e,d in ipairs(b)do if d.hasTos then a[#a+1]=d end end;if#a==0 then
aB("No drive holds a TOS installation to configure.")
at("Insert the TOS install disk to install it first.")return nil end;if
#a==1 then return a[1]end;ar(0x00AAFF)
print("--- Which TOS should be configured? ---")ar(0xFFFFFF)
for e,d in ipairs(a)do
print(string.format("  %d. %s%s",e,d.isBoot and"Boot drive"or d.prefix,
(
d.label and d.label~="")and('  "'..d.label..'"')or""))end;print()
while true do
local d=aC("Configure which drive? (0 = cancel)",nil,"1")local c=tonumber(d)if c==0 then return nil end
if c and a[c]then return a[c]end;at("Type a number from the list.")end end
local function bA(b,a,c)a=a or""local e,j=c,nil;if not e then e,j=aY(b)end;if not e then
aB("Cannot load install manifest: "..tostring(j))return false end;au("Manifest loaded: "..
#e.." files declared")
local i=a_(b,e,as.size,as.exists,a)local g=bt(a)
if g and i>g then print()
aB(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
i/1024),math.floor(g/1024)))
at("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
at("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")at("holds TOS on its own.")return false,"space"end;if g then
au(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(i/1024),math.floor(g/1024)))end;print()
ar(0x00AAFF)
print(av("install.dirs","--- Creating directories ---"))ar(0xFFFFFF)local k={}
for m,l in ipairs(e)do local n=l.path:match(aU)
while n and n~=""and
not k[n]do k[n]=true;if not as.isDirectory(a..n)then
as.makeDirectory(a..n)end;n=n:match(aU)end end;for m,l in ipairs(aX)do if not as.isDirectory(a..l)then
as.makeDirectory(a..l)end end
au("Directory structure created")print()ar(0x00AAFF)
print(av("install.copying","--- Copying system files ---"))ar(0xFFFFFF)local h,d=0,0;local f={}
for m,l in ipairs(e)do local n=b..l.path;local o=a..l.path
if not
as.exists(n)then d=d+1;f[#f+1]="missing on disk: "..l.path else
local p,q=br(n,o)
if p then h=h+1 else d=d+1;f[#f+1]=l.path..": "..tostring(q)end end end;print()
if d==0 then au("Copied "..h.." files")else
aB("Copied "..h..
" files, "..d.." FAILED:")for l=1,math.min(5,#f)do at("  "..f[l])end
if#f>5 then at("  (+"..
(#f-5).." more)")end end;print()
if d==0 then ar(0x00AAFF)
print(av("install.verifying","--- Verifying copy ---"))ar(0xFFFFFF)local l,m=bs(b,e,a)
if#l==0 and#m==0 then
au("All "..#e.." files verified")else
if#l>0 then aB(#l.." files MISSING after copy:")for n=1,math.min(5,
#l)do at("  "..l[n])end;d=d+#l end
if#m>0 then
aB(#m.." files have WRONG SIZE after copy:")for n=1,math.min(5,#m)do at("  "..m[n])end;d=d+#m end end;print()end;return d==0 end;local bd={"/bin","/boot","/lib"}local aG="/init.lua.pre-tos"
local function bB(a)a=a or""if
not as or not as.exists(
a..bg)or as.exists(a..aG)then return false end
local c=io.open(a..bg,"r")if not c then return false end;local b=c:read("*a")c:close()if not b or b==""or
b:find("_TOS",1,true)then return false end
local d=io.open(a..aG,"w")if not d then return false end;d:write(b)d:close()
return as.exists(a..aG)end
local function bC(a)a=a or""if not as then return false end;for c,b in ipairs(bd)do
if as.exists(a..b)then return true end end;return false end
local function bD(a)a=a or""local b={}if not as then return b end;for d,c in ipairs(bd)do
if as.exists(a..c)then
local e=pcall(as.remove,a..c)if e and not as.exists(a..c)then b[#b+1]=c end end end
if#b>0 and as.exists(a..
aG)then pcall(as.remove,a..aG)if not
as.exists(a..aG)then b[#b+1]=aG end end;return b end
local function bE(a,b)
if az.isAvailable("data")then local k,j=pcall(az.data.sha256,a)
if k and
type(j)==aL and#j==32 then return
(j:gsub(".",function(l)
return("%02x"):format(l:byte())end))end end
local c=io.open(b.."/tos/kernel/sha256.lua","r")if not c then return nil end;local e=c:read("*a")c:close()
local f=e and
load(e,"=sha256","t",{string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,error=error,assert=assert,setmetatable=setmetatable})if not f then return nil end;local g,d=pcall(f)if not
(g and type(d)=="table"and d.hex)then return nil end
local h,i=pcall(d.hex,a)return h and i or nil end
local function bF(a)local d=a.."/bios.lua"if not as.exists(d)then return end
local c=io.open(d,"r")
if not c then at("Could not read bios.lua")print()return end;local b=c:read("*a")c:close()if not b or#b==0 then
at("Empty bios.lua")print()return end;local e=bE(b,a)local g=e and
(e:sub(1,16).."...")or"(unavailable)"
ar(0xFFFF00)print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..g)ar(0xFFFFFF)
ar(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
ar(0xFFFFFF)local h=io.read()or""if h~="flash"then au("Skipped BIOS flash")
print()return end;local f=az.list("eeprom")()
if f then
local i=az.proxy(f)i.set(b)i.setLabel("TOS BIOS")
au("BIOS flashed! Label set to 'TOS BIOS'")else at("No EEPROM found")end;print()end
local function bG(a)local b={}ar(0x00AAFF)
print(av("install.device","--- Device Setup ---"))ar(0xFFFFFF)print()
print(av("install.device_q","What type of device is this?"))ar(0xAAAAAA)
print(av("install.device_1","  1. Computer  (desktop, tower with screen)"))
print(av("install.device_2","  2. Tablet    (portable, battery-powered)"))
print(av("install.device_3","  3. Server    (rack blade, typically headless)"))ar(0xFFFFFF)
local c=aC(av("install.choice","Choice"),{"1","2","3"},"1")
if c=="2"then b.device=bi;b.showBattery=true;b.powerSave=true
au("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
au("Server mode (headless boot, services auto-start)")print()ar(0xFFFF00)print("  Server rack checklist:")
ar(0xAAAAAA)
if a.hasModem or a.hasTunnel then au("Network card detected")else
at("No modem or linked card! The server will be unreachable.")
at("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
au("Headless (no GPU/screen) — normal for servers")else
at("GPU or screen detected — will boot headless anyway.")
at("Remove them to free rack slots, or choose Computer mode.")end;ar(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
au("Computer mode")end;print()
math.randomseed(math.floor(aA.uptime()*1000)+
aA.freeMemory())
b.hostname=aC(av("install.hostname","Hostname"),nil,"tos-"..
string.format("%04x",math.random(0,0xFFFF)))au("Hostname: "..b.hostname)print()
ar(0x00AAFF)
print(av("install.security","--- Security ---"))ar(0xFFFFFF)print()
print(av("install.security_q","Security level:"))ar(0xAAAAAA)
print(av("install.security_1","  1. Standard  (login + lockout after 5 failures)"))
print(av("install.security_2","  2. Relaxed   (login, no lockout)"))
print(av("install.security_3","  3. Open      (allows guest access)"))ar(0xFFFFFF)
local d=aC(av("install.choice","Choice"),{"1","2","3"},"1")
if d=="3"then b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999
au("Security: Open")elseif d=="2"then b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999
au("Security: Relaxed")else b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5
au("Security: Standard")end;print()
if a.hasModem or a.hasTunnel then ar(0x00AAFF)
print(av("install.network","--- Network ---"))ar(0xFFFFFF)print()
b.encryptComms=aD(av("install.encrypt","Encrypt network communications?"))
au("Encryption: ".. (b.encryptComms and"on"or"off"))
local e=aC(av("install.port","Listen port"),nil,"42")b.listenPort=tonumber(e)or 42
au("Port: "..b.listenPort)print()else b.encryptComms=true;b.listenPort=42 end
if b.device==bi then ar(0x00AAFF)print("--- Tablet Options ---")
ar(0xFFFFFF)print()b.lowBatWarn=
tonumber(aC("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(aC("Critical battery warning %",
nil,"5"))or 5
au("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end
b.verbose=aD(av("install.verbose","Verbose boot? (shows debug messages)"))print()return b end
local function bH(a,b)local c={"return {"}local d={}for f in pairs(a)do d[#d+1]=f end
table.sort(d)
for g,f in ipairs(d)do local h=a[f]if type(h)==aL then
c[#c+1]=string.format('  [%q] = %q,',f,h)else
c[#c+1]=string.format('  [%q] = %s,',f,tostring(h))end end;c[#c+1]="}"
local e=io.open((b or"").."/etc/tos.cfg","w")
if e then e:write(table.concat(c,"\n"))e:close()return true end;return false end;local aH=bv({...})aQ.clear()bm()
if aH.help or aH.unknown then if aH.unknown and
not aH.help then
aB("Unknown option: "..tostring(aH.unknown))print()end
print("Copies TOS onto a drive, asks a few setup questions, and")print("offers to flash the TOS BIOS.")print()
print("Usage:")
print("  install.lua [source-dir] [--profile minimal|full]")print("  install.lua --configure")
print("  install.lua --help")print()
print("Run it from an install disk (/mnt/<disk>/install.lua), or")
print("let bootstrap.lua stage a download for it.")print()
print("With more than one writable drive it asks which one TOS")
print("goes on; the boot drive is only the default. If the boot")
print("drive is too small it offers the others. TOS can then be")print("made the boot drive at the end.")print()
print("source-dir  a directory holding a TOS release, for")
print("            scripted installs. Normally found by itself.")print()
print("--profile   full is everything. minimal is the command line")
print("            and the core, for a small drive. If no drive")
print("            can hold the full system it offers this anyway.")print()
print("--configure  only change the settings of a TOS that")
print("            is already installed, on whichever drive")
print("            holds it. Also what happens with no")
print("            install disk. (A second drive that holds")
print("            TOS reads as an install disk otherwise.)")return end;local be=bo()bp(be)local aE=
(not aH.configure)and bn(aH.positional[1])or nil;local aI=aE~=nil;local bf
if aI and as.exists(
aE.."/usr/lang")then
local a=bj(aE.."/usr/lang",as.list,function(b)
local c=io.open(b,"r")if not c then return nil end;local d=c:read("*a")c:close()return d end)
if#a>1 then print()for c,d in ipairs(a)do
print("  "..c..". "..d.name)end;local b=
a[tonumber(aC("Language",nil,"1"))or 1]or a[1]if b.strings then aW=b.strings
bf=b.code end;print()end end;local ay,aw="",nil;local aJ;local aF=false;local aN=aH.profile;local aO=false
if aI then
au("Install disk found at: "..aE)print()local a=aY(aE)aJ=a and ba(a,aN)local b;aw,b=bc(aE,aJ)
if not aw and
b=="space"and not aN and a then print()
ar(0x00AAFF)print("--- A smaller install ---")ar(0xFFFFFF)
print("The minimal system is the command line and the core of TOS, with")print("no panels, and takes about 520 KB.")
if
aD(av("install.minimal_q","Try the minimal system instead?"))then aN=aV;aJ=ba(a,aN)print()aw,b=bc(aE,aJ)end end
if not aw then print()if b~="space"then print(aP)end;return end;ay=aw.prefix;print()ar(0xFFFF00)
if aw.isBoot then
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")else
print("TOS will be installed on "..aR(aw)..".")
print("Its /init.lua will be replaced (the current one, if any, is kept")
print("there as /init.lua.pre-tos). The drive this machine boots from")
print("is not changed unless you choose that at the end.")end;ar(0xFFFFFF)print()if not
aD(av("install.continue","Continue?"))then print(aP)return end
print()
if not bq(_G._FORCE_WIPE or false,ay)then return end;if bB(ay)then
au("Kept the previous /init.lua as "..ay..aG)end;local c;aF,c=bA(aE,ay,aJ)if c=="space"then print()
return end
if aF and aN==aV then
local d=ay.."/tos/system_manifest.lua"local e=io.open(d..".tmp","w")
local f=e and e:write(bw(aJ))if e then e:close()end
if f and as.size(d..".tmp")>0 then
as.remove(d)as.rename(d..".tmp",d)
au("Minimal system: "..#aJ.." files")else
at("Could not trim the manifest, so `verify` will list the rest as missing.")end;print()end
if not aF then
aB("Install file copy/verify did NOT fully succeed.")
at("BIOS flash will be skipped to avoid bricking the boot.")
at("You can retry installation; the partial files won't conflict.")
if not aD("Continue to questionnaire anyway?")then print(aP)return end;print()end
if aF and bC(ay)then ar(0x00AAFF)print("--- Clean install ---")
ar(0xFFFFFF)ar(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
ar(0xFFFFFF)
aO=aD("Remove OpenOS leftovers for a clean install?")
au(aO and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else ar(0xFFFF00)
print("No install disk detected - running in configuration mode.")ar(0xFFFFFF)aw=bz()if not aw then print(aP)return end;ay=aw.prefix
print(
"Configuring the TOS on "..aR(aw)..".")print()if
not aD(av("install.continue","Continue?"))then print(aP)return end;print()end;local ax=bG(be)ax.language=bf;ar(0x00AAFF)
print("--- Summary ---")ar(0xAAAAAA)
print("  Device:     "..ax.device)print("  Hostname:   "..ax.hostname)
print(
"  Security:   ".. (ax.autoLockout and"Standard"or
(ax.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (ax.encryptComms and"Yes"or"No"))
if ax.device==bi then
print("  Battery:    Warn at "..
ax.lowBatWarn.."% / "..ax.critBatWarn.."%")elseif ax.device=="server"then
print("  Headless:   "..
(ax.headless and"Yes"or"No"))
print("  Services:   "..
(ax.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (ax.verbose and"Yes"or"No"))if aI and aF then
print("  Clean inst: "..
(aO and"Yes (remove /bin, /boot, /lib)"or"No"))end;ar(0xFFFFFF)print()if not
aD("Apply these settings?")then print(aP)return end;print()
ar(0x00AAFF)print("--- Applying configuration ---")ar(0xFFFFFF)
if
as then for b,a in ipairs(aX)do if not as.isDirectory(ay..a)then
as.makeDirectory(ay..a)end end end;if bH(ax,ay)then
au("Configuration saved to "..ay.."/etc/tos.cfg")else
at("Could not save config (defaults will be used)")end;au("Device profile: "..
ax.device)print()
if aI then if aF then bF(aE)else
at("Skipping BIOS flash: file copy did not fully verify.")at("Re-run install.lua to retry before flashing.")
print()end end;local aS=false
if aI and aF and aw and not aw.isBoot then ar(0x00AAFF)
print("--- Boot drive ---")ar(0xFFFFFF)
print("TOS is on "..aR(aw)..", but this machine")
print("boots from a different drive, so it would start that system.")
if aD("Boot from the TOS drive from now on?")then
local a,b=pcall(aA.setBootAddress,aw.address)if a then aS=true
au("Boot drive set to "..aw.address:sub(1,8))else
at("Could not set the boot drive: "..tostring(b))end end
if not aS then
at("The boot drive is unchanged. To switch later, run `lua` and type:")
print("  require('computer').setBootAddress('"..aw.address.."')")end;print()end
if aI and aF and aO then ar(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")ar(0xFFFFFF)local a=bD(ay)
if#a>0 then
au("Removed: "..table.concat(a,", "))
at("OpenOS is no longer bootable on this drive — reboot into TOS.")else at("Nothing to remove (already clean).")end;print()end;ar(0x00AAFF)print("--- Installation Complete ---")
ar(0xFFFFFF)print()ar(0x00FF00)
if aI and aF then
if
aw and not aw.isBoot and not aS then
print("TOS is installed, but this machine still boots from another drive.")else
print(av("install.done","TOS is installed! Reboot to start."))end elseif aI then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print(av("install.first_boot","First boot asks you to set the root password before anything else."))if aO then ar(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")ar(0xFFFFFF)end
ar(0xFFFFFF)print()if aD(av("install.reboot_q","Reboot now?"))then
aA.shutdown(true)end