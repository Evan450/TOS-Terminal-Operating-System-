
local bm,bn,bj,bt,bu,bv,bw,bM,bx,by,bN,bf,bO="/init.lua","/tos/kernel/init.lua","Cancelled.","Choice","^(.*)/[^/]+$","^(.+)/[^/]+$","delete","filesystem","install.choice","minimal","number","string","tablet"local aT=require("component")local aV=require("computer")
local bk=require("term")local aL=nil
pcall(function()aL=require(bM)end)local bg=aT.gpu;local function aK(a)
if bg and bg.setForeground then pcall(bg.setForeground,a)end end;local function aO(a)aK(0x00FF00)
print("  + "..a)aK(0xFFFFFF)end;local function aM(a)aK(0xFFFF00)
print("  ! "..a)aK(0xFFFFFF)end;local function ba(a)aK(0xFF0000)
print("  X "..a)aK(0xFFFFFF)end;local bz={}
local function aN(a,b)return bz[a]or b end
local function bP(a,b,c)local e={{code="en",name="English"}}local d={}
for f in b(a)do d[#d+1]=f end;table.sort(d)
for g,f in ipairs(d)do local i=f:match("^(%a+)%.lang$")local j=i and
c(a.."/"..f)local k=j and load(j,"="..f,"t",{})local l,h=false,
nil;if k then l,h=pcall(k)end
if l and type(h)=="table"and
type(h.strings)=="table"then local m=
type(h.meta)=="table"and h.meta or{}
e[#e+1]={code=i,name=tostring(m.name or i),strings=h.strings}end end;return e end
local function aW(c,b,a)aK(0xFFFF00)io.write(c)
if b then aK(0xAAAAAA)io.write(" ["..
table.concat(b,"/").."]")end;if a then aK(0x888888)
io.write(" (default: "..a..")")end;aK(0xFFFFFF)io.write(": ")local d
if bk and
bk.read then local e,f=pcall(bk.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function aX(a)local b=aW(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local bo="discover"local bl=false
local bA="dcdafa5342333048be0ad519911a6bd1ecffefcffde73879a4e246fc20d7fd8b"local bQ="1.5.0"
local bB={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local bR={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function bS()aK(0x00AAFF)for b,a in ipairs(bR)do print("   "..a)end
aK(0xFFFFFF)print()aK(0x00FF66)print("   Strata Systems LLC")
aK(0xFFFFFF)aK(0xAAAAAA)
print("   Terminal Operating System — Setup v"..bQ)aK(0xFFFFFF)print()end
local function bT(a)if not aL then return nil end;if type(a)==bf and a~=""then local d=a:sub(-1)=="/"and
a:sub(1,-2)or a
if aL.exists(d..bn)then return d end end;local b=
os.getenv and os.getenv("_")or nil
if b then local d=b:match(bu)if d and d~=""and aL.exists(
d..bn)then return d end end;local c=aV.getBootAddress()
for d in aT.list(bM)do
if d~=c then
local f,e=pcall(aT.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(bn)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then
if aL.mounts then local l,k=pcall(aL.mounts)if l and k then
for m,n in k do local o,p=m,n;if type(m)==
bf then o,p=n,m end;if type(o)=="table"and o.address==d then return
tostring(p)end end end end end end end;return nil end
local function bU()local a={}a.totalMem=aV.totalMemory()a.freeMem=aV.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if bg then local d,e=bg.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=aV.getBootAddress()local aO,b=pcall(aT.proxy,c)if not aO or not b then
b={spaceTotal=function()return 0 end,spaceUsed=function()return 0 end}end
a.diskTotal=b.spaceTotal()
a.diskFree=math.max(0,a.diskTotal-b.spaceUsed())a.diskKB=math.floor(a.diskTotal/1024)a.diskFreeKB=math.floor(
a.diskFree/1024)
a.hasModem,a.hasWireless,a.hasTunnel,a.hasDataCard=false,false,false,false;a.hasGPU,a.hasScreen,a.hasKeyboard=false,false,false
for e,d in aT.list()do
if d=="modem"then
a.hasModem=true
pcall(function()a.hasWireless=aT.proxy(e).isWireless()end)elseif d=="tunnel"then a.hasTunnel=true elseif d=="data"then a.hasDataCard=true elseif d=="gpu"then a.hasGPU=true elseif d==
"screen"then a.hasScreen=true elseif d=="keyboard"then a.hasKeyboard=true end end;return a end
local function bV(a)aK(0x00AAFF)print("--- Hardware Detected ---")
aK(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))aK(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
aM("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
aM("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
aM("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
aM("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function bC(a)local c=a.."/tos/system_manifest.lua"if not aL.exists(c)then return nil,
"no manifest at "..c end
local d=io.open(c,"r")if not d then return nil,"cannot open manifest"end
local b=d:read("*a")d:close()if not b then return nil,"empty manifest"end
if
#b>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then local k,l=e.decode(b,{maxBytes=
256*1024})
if
k and type(k)=="table"then return k elseif k==nil then
aM("manifest serialize.decode failed ("..
tostring(l).."); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function bW(b,a)if b then return true end;a=a or""
if aL.exists(a.."/etc/users.dat")then local c=io.open(a..
"/etc/users.dat","r")
if c then local d=c:read("*a")
c:close()
if d and#d>0 then
aM("Existing TOS install detected (/etc/users.dat is populated).")
aM("Re-installing will overwrite users, configuration, and the")
aM("system tree but will NOT delete user data under /home or /tmp.")aK(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")aK(0xFFFFFF)local e=io.read()or""if e~="FORCE-WIPE"then
ba("Install aborted by safety check.")return false end end end end;return true end
local function bX(a,b)local d=io.open(a,"r")if not d then return false,"open source"end
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
local function bY(c,d,a,b)a=a or""local e,f={},{}
for h,g in ipairs(d)do local i=a..g.path
if not aL.exists(i)then
e[#e+1]=i else
local j=(b and b[g.path])or aL.size(c..g.path)or 0;local k=aL.size(i)or 0;if j~=k then
f[#f+1]=string.format("%s (src=%d dst=%d)",i,j,k)end end end;return e,f end;local bD=512
local function bE(d,e,b,c,a)a=a or""local f,g=0,{}
for i,h in ipairs(e)do local k=b(d..h.path)or 0;if
c(a..h.path)then
f=f+math.max(0,k- (b(a..h.path)or 0))else f=f+k+bD end
local j=h.path:match(bv)while j and j~=""and not g[j]do g[j]=true;if not c(a..j)then f=f+bD end
j=j:match(bv)end end;return f end
local function bp(c,d)
local e,a=pcall(aL.get,(c==nil or c=="")and"/"or c)
local f,b=pcall(aL.get,(d==nil or d=="")and"/"or d)return
e and f and a and b and a.address==b.address or false end
local function bZ(a)
local d,b=pcall(aL.get,(a==nil or a=="")and"/"or a)if not d or not b then return nil end;local e,c=pcall(b.spaceTotal)
local f,g=pcall(b.spaceUsed)
if not(e and f)or type(c)~=bN or c<=0 then return nil end;return c-g end
local function b_(a)local b,c={},nil;for e,d in ipairs(a)do
b[e]=(d.free==nil)or(d.free>=d.need)end;for d,e in ipairs(a)do
if e.isBoot and b[d]then c=d;break end end;if not c then
for d=1,#a do if b[d]then c=d;break end end end;return c,b end
local function ca(a)local b={positional={}}local c=1
while c<=#a do local d=a[c]
if
d=="-h"or d=="--help"or d=="-?"or d=="/?"then b.help=true elseif d=="--configure"then b.configure=true elseif d==
"--temporary"then b.temporary=true elseif d=="--profile"then c=c+1;if a[c]==by or a[c]=="full"then
b.profile=a[c]else
b.unknown=b.unknown or("--profile "..tostring(a[c]))end elseif type(d)==bf and d:sub(1,1)==
"-"then b.unknown=b.unknown or d else
b.positional[#b.positional+1]=d end;c=c+1 end;return b end;local function bF(a,b)if b~=by then return a end;local c={}
for e,d in ipairs(a)do if d.floor then c[#c+1]=d end end;return c end
local function cb(a)
local b={"-- Written by install.lua: the files this profile installed.","return {"}
for d,c in ipairs(a)do
local e={string.format("path = %q",c.path),"critical = "..
tostring(c.critical==true)}if c.floor then e[#e+1]="floor = true"end;if c.hash then
e[#e+1]=string.format("hash = %q",c.hash)end;b[#b+1]="  { "..
table.concat(e,", ").." },"end;b[#b+1]="}"return table.concat(b,"\n").."\n"end
local function cc()local a={}if not(aL and aL.mounts)then return a end
local c,b=pcall(aL.mounts)if not c or type(b)~="function"then return a end
for d,e in b do local g,h=d,e;if
type(d)==bf then g,h=e,d end
local f=type(g)=="table"and g.address or nil
if f and type(h)==bf then a[f]=a[f]or{}a[f][#a[f]+1]=h end end;return a end
local function cd(a)
for c,b in ipairs(a)do if b:sub(1,5)=="/mnt/"then return b end end;for c,b in ipairs(a)do if b~="/"then return b end end;return nil end
local function be(a)if a>=1024*1024 then
return string.format("%.1f MB",a/1024/1024)end;return
string.format("%d KB",math.floor(a/1024))end
local function bG(a,b)local e=cc()local f=aV.getBootAddress()local g=
aV.tmpAddress and aV.tmpAddress()or nil;local h=
a:sub(-1)=="/"and a:sub(1,-2)or a;local c,d={},0
for i in aT.list(bM)do
local k,j=pcall(aT.proxy,i)local l,m=false,true;if k and j then l,m=pcall(j.isReadOnly)end
if
i~=g and k and j and l and not m then local o=e[i]or{}local p=i==f
local n=p and""or cd(o)local q=false;for s,r in ipairs(o)do if r==h then q=true end end
if q then elseif not n then d=d+1 else
local r={address=i,prefix=n,isBoot=p}local t,u=pcall(j.getLabel)r.label=t and u or nil
local v,s=pcall(j.spaceTotal)local w,x=pcall(j.spaceUsed)if
v and w and type(s)==bN and s>0 then r.total,r.free=s,s-x end
local y,z=pcall(j.exists,bm)local A,B=pcall(j.exists,bn)r.hasInit=y and z or false;r.hasTos=A and B or
false
r.need=b and bE(a,b,aL.size,aL.exists,n)or 0;if bl and bp(a,n)then r.need=0 end;c[#c+1]=r end end end
table.sort(c,function(i,j)if i.isBoot~=j.isBoot then return i.isBoot end;return
i.prefix<j.prefix end)return c,d end
local function bq(a)
local b=a.isBoot and"the boot drive"or("the drive at "..a.prefix)
if a.label and a.label~=""then b=b..' "'..a.label..'"'end;return b end
local function bH(a,b)local c,f=bG(a,b)if#c==0 then
return{address=aV.getBootAddress(),prefix="",isBoot=true,need=0}end;local d,e=b_(c)
if#c==1 and d==1 then return c[1]end;aK(0x00AAFF)
print(aN("install.where","--- Where should TOS go? ---"))aK(0xFFFFFF)
for h,g in ipairs(c)do if g.isBoot and g.free and g.free<g.need then
aM(string.format("The boot drive has %s free; TOS needs %s.",be(g.free),be(g.need)))end end
for h,g in ipairs(c)do
local j=string.format("  %d. %s%s",h,g.isBoot and"Boot drive"or g.prefix,
(g.label and
g.label~="")and('  "'..g.label..'"')or"")if e[h]then aK(0xFFFFFF)else aK(0x888888)end
print(j.. (
h==d and"   <- default"or""))
local k=
g.total and string.format("%s, %s free",be(g.total),be(g.free))or"size unknown"local i={}if g.hasTos then i[#i+1]="has TOS"elseif g.hasInit then i[#i+1]="has an OS"else
i[#i+1]="empty"end;if not e[h]then i[#i+1]="too small: needs "..
be(g.need)end
aK(0xAAAAAA)
print("     "..k.."; "..table.concat(i,", "))end;aK(0xFFFFFF)if f>0 then
aM(f.." more drive(s) are not mounted, so they are not listed.")end
if not d then print()
ba("None of these drives has room for TOS.")
aM("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
aM("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")return nil,"space"end;print()
while true do
local h=aW(aN("install.which_drive","Install on which drive? (0 = cancel)"),nil,tostring(d))local g=tonumber(h)if g==0 then return nil end
if g and c[g]then
if e[g]then return c[g]end
aM("That drive is too small: TOS needs "..be(c[g].need)..".")else aM("Type a number from the list.")end end end
local function ce()local b=bG("",nil)local a={}
for e,d in ipairs(b)do if d.hasTos then a[#a+1]=d end end;if#a==0 then
ba("No drive holds a TOS installation to configure.")
aM("Insert the TOS install disk to install it first.")return nil end;if
#a==1 then return a[1]end;aK(0x00AAFF)
print("--- Which TOS should be configured? ---")aK(0xFFFFFF)
for e,d in ipairs(a)do
print(string.format("  %d. %s%s",e,d.isBoot and"Boot drive"or d.prefix,
(
d.label and d.label~="")and('  "'..d.label..'"')or""))end;print()
while true do
local d=aW("Configure which drive? (0 = cancel)",nil,"1")local c=tonumber(d)if c==0 then return nil end
if c and a[c]then return a[c]end;aM("Type a number from the list.")end end
local function cf(b,a,c)a=a or""local e,k=c,nil;if not e then e,k=bC(b)end;if not e then
ba("Cannot load install manifest: "..tostring(k))return false end;aO("Manifest loaded: "..
#e.." files declared")
local h=bE(b,e,aL.size,aL.exists,a)local j=bl and bp(b,a)if j then h=0 end;local g=bZ(a)
if g and h>g then print()
ba(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
h/1024),math.floor(g/1024)))
aM("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
aM("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")aM("holds TOS on its own.")return false,"space"end;if g then
aO(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(h/1024),math.floor(g/1024)))end;print()
aK(0x00AAFF)
print(aN("install.dirs","--- Creating directories ---"))aK(0xFFFFFF)local l={}
for o,n in ipairs(e)do local p=n.path:match(bv)
while p and p~=""and
not l[p]do l[p]=true;if not aL.isDirectory(a..p)then
aL.makeDirectory(a..p)end;p=p:match(bv)end end;for o,n in ipairs(bB)do if not aL.isDirectory(a..n)then
aL.makeDirectory(a..n)end end
aO("Directory structure created")print()aK(0x00AAFF)
print(aN("install.copying","--- Copying system files ---"))aK(0xFFFFFF)local i,d=0,0;local f={}local m=j and{}or nil
for o,n in ipairs(e)do
local q=b..n.path;local p=a..n.path
if not aL.exists(q)then d=d+1
f[#f+1]="missing on disk: "..n.path else local r,s
if j then m[n.path]=aL.size(q)
if aL.exists(p)then aL.remove(p)end;r=aL.rename(q,p)and aL.exists(p)end;if not r then r,s=bX(q,p)end;if r then i=i+1 else d=d+1
f[#f+1]=n.path..": "..tostring(s)end end end;print()
if d==0 then aO("Copied "..i.." files")else
ba("Copied "..i..
" files, "..d.." FAILED:")for n=1,math.min(5,#f)do aM("  "..f[n])end
if#f>5 then aM("  (+"..
(#f-5).." more)")end end;print()
if d==0 then aK(0x00AAFF)
print(aN("install.verifying","--- Verifying copy ---"))aK(0xFFFFFF)local n,o=bY(b,e,a,m)
if#n==0 and#o==0 then aO("All "..
#e.." files verified")else
if#n>0 then
ba(#n.." files MISSING after copy:")for p=1,math.min(5,#n)do aM("  "..n[p])end;d=d+#n end
if#o>0 then
ba(#o.." files have WRONG SIZE after copy:")for p=1,math.min(5,#o)do aM("  "..o[p])end;d=d+#o end end;print()end;return d==0 end;local bI={"/bin","/boot","/lib"}local aY="/init.lua.pre-tos"
local function cg(a)a=a or""if
not aL or not aL.exists(
a..bm)or aL.exists(a..aY)then return false end
local c=io.open(a..bm,"r")if not c then return false end;local b=c:read("*a")c:close()if not b or b==""or
b:find("_TOS",1,true)then return false end
local d=io.open(a..aY,"w")if not d then return false end;d:write(b)d:close()
return aL.exists(a..aY)end;local bJ="/openos"
local function ch(a)for c,b in
ipairs({"/home","/mnt","/tmp","/dev","/openos",bm})do
if a==b or a:sub(1,#b+1)==b.."/"then return false end end
if
a:find("tos%-netinstall")or a=="/bootstrap.lua"then return false end;return true end
local function ci(a)a=a or""local b={}
local function c(d)
local f,e=pcall(aL.list,(a..d)==""and"/"or(a..d))if not f or not e then return end
for g in e do local h=(d=="/"and""or d).."/"..
tostring(g):gsub("/$","")if ch(h)and bp(a..
h,a)then
if aL.isDirectory(a..h)then c(h)else b[#b+1]=h end end end end;c("/")return b end
local function cj(a,b,c)local e={}for g,f in ipairs(c or{})do e[f.path]=true end;local d={}
for g,f in
ipairs(b or{})do if
not e[f]and aL.exists(a..f)and not aL.isDirectory(a..f)then d[#d+1]=f end end;return d end
local function ck(a,b,c)local e,f=0,{}
for h,g in ipairs(b)do local j
if c=="move"then local l=a..bJ..g;local k=l:match(bu)if k and not
aL.exists(k)then aL.makeDirectory(k)end;j=aL.rename(
a..g,l)else j=aL.remove(a..g)end;if j then e=e+1 end;local i=g:match(bu)
while i and i~=""do f[i]=true;i=i:match(bu)end end;local d={}for g in pairs(f)do d[#d+1]=g end
table.sort(d,function(g,h)return#g>#h end)
for h,g in ipairs(d)do local j,i=pcall(aL.list,a..g)
local k=j and i and i()==nil;if k then aL.remove(a..g)end end;return e end
local function cl(a)a=a or""if not aL then return false end;for c,b in ipairs(bI)do
if aL.exists(a..b)then return true end end;return false end
local function cm(a)a=a or""local b={}if not aL then return b end;for d,c in ipairs(bI)do
if aL.exists(a..c)then
local e=pcall(aL.remove,a..c)if e and not aL.exists(a..c)then b[#b+1]=c end end end
if#b>0 and aL.exists(a..
aY)then pcall(aL.remove,a..aY)if not
aL.exists(a..aY)then b[#b+1]=aY end end;return b end
local function cn(a,b)
if aT.isAvailable("data")then local k,j=pcall(aT.data.sha256,a)
if k and
type(j)==bf and#j==32 then return
(j:gsub(".",function(l)
return("%02x"):format(l:byte())end))end end
local c=io.open(b.."/tos/kernel/sha256.lua","r")if not c then return nil end;local e=c:read("*a")c:close()
local f=e and
load(e,"=sha256","t",{string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,error=error,assert=assert,setmetatable=setmetatable})if not f then return nil end;local g,d=pcall(f)if not
(g and type(d)=="table"and d.hex)then return nil end
local h,i=pcall(d.hex,a)return h and i or nil end
local function co(b,a)if type(a)~=bN or a<=0 then return nil end
if b>a then return
string.format(
"This BIOS is %d bytes and the EEPROM holds %d:\n".."it is the unminified source, not a release build.",b,a)end;return nil end
local function cp(a)local e=a.."/bios.lua"if not aL.exists(e)then return end
local d=io.open(e,"r")
if not d then aM("Could not read bios.lua")print()return end;local b=d:read("*a")d:close()if not b or#b==0 then
aM("Empty bios.lua")print()return end
local c=aT.list("eeprom")()local f,g=false,nil
if c then f,g=pcall(aT.invoke,c,"getSize")end;local h=co(#b,f and g or nil)
if h then
for l in h:gmatch("[^\n]+")do aM(l)end
aM("Skipping the BIOS flash. The BIOS this machine has boots TOS too; flash")
aM("a release's bios.lua later if you want TOS's own (flash /bios.lua).")print()return end;local i=cn(b,a)
local j=i and(i:sub(1,16).."...")or"(unavailable)"aK(0xFFFF00)
print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..j)aK(0xFFFFFF)
aK(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
aK(0xFFFFFF)local k=io.read()or""if k~="flash"then aO("Skipped BIOS flash")
print()return end
if c then local l=aT.proxy(c)
local m,n=pcall(l.set,b)
if m then pcall(l.setLabel,"TOS BIOS")
aO("BIOS flashed! Label set to 'TOS BIOS'")else
aM("The EEPROM refused the BIOS ("..tostring(n).."); it was left as it was.")end else aM("No EEPROM found")end;print()end
local function cq(a)local b={}aK(0x00AAFF)
print(aN("install.device","--- Device Setup ---"))aK(0xFFFFFF)print()
print(aN("install.device_q","What type of device is this?"))aK(0xAAAAAA)
print(aN("install.device_1","  1. Computer  (desktop, tower with screen)"))
print(aN("install.device_2","  2. Tablet    (portable, battery-powered)"))
print(aN("install.device_3","  3. Server    (rack blade, typically headless)"))aK(0xFFFFFF)local c=aW(aN(bx,bt),{"1","2","3"},"1")
if
c=="2"then b.device=bO;b.showBattery=true;b.powerSave=true
aO("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
aO("Server mode (headless boot, services auto-start)")print()aK(0xFFFF00)print("  Server rack checklist:")
aK(0xAAAAAA)
if a.hasModem or a.hasTunnel then aO("Network card detected")else
aM("No modem or linked card! The server will be unreachable.")
aM("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
aO("Headless (no GPU/screen) — normal for servers")else
aM("GPU or screen detected — will boot headless anyway.")
aM("Remove them to free rack slots, or choose Computer mode.")end;aK(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
aO("Computer mode")end;print()
math.randomseed(math.floor(aV.uptime()*1000)+
aV.freeMemory())
b.hostname=aW(aN("install.hostname","Hostname"),nil,"tos-"..
string.format("%04x",math.random(0,0xFFFF)))aO("Hostname: "..b.hostname)print()
aK(0x00AAFF)
print(aN("install.security","--- Security ---"))aK(0xFFFFFF)print()
print(aN("install.security_q","Security level:"))aK(0xAAAAAA)
print(aN("install.security_1","  1. Standard  (login + lockout after 5 failures)"))
print(aN("install.security_2","  2. Relaxed   (login, no lockout)"))
print(aN("install.security_3","  3. Open      (allows guest access)"))aK(0xFFFFFF)local d=aW(aN(bx,bt),{"1","2","3"},"1")
if
d=="3"then b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999
aO("Security: Open")elseif d=="2"then b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999
aO("Security: Relaxed")else b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5
aO("Security: Standard")end;print()
print(aN("install.accounts_q","Who may add, remove and change user accounts?"))aK(0xAAAAAA)
print(aN("install.accounts_1","  1. Root only"))
print(aN("install.accounts_2","  2. Root, and admins for ordinary accounts"))aK(0xFFFFFF)
b.accountAdmins=aW(aN(bx,bt),{"1","2"},"1")=="2"
aO(b.accountAdmins and"Accounts: root, and admins for ordinary accounts"or
"Accounts: root only")print()
print(aN("install.trust_1","The Optional Utilities are signed by their publisher. Trusting"))
print(aN("install.trust_2","the key makes them install as trusted; `pkg trust` undoes it."))
b.trustOfficial=aX(aN("install.trust_q","Trust the Optional Utilities publisher?"))
aO(b.trustOfficial and"Optional Utilities key: trusted"or"Optional Utilities key: not trusted")print()
if a.hasModem or a.hasTunnel then aK(0x00AAFF)
print(aN("install.network","--- Network ---"))aK(0xFFFFFF)print()
b.encryptComms=aX(aN("install.encrypt","Encrypt network communications?"))
aO("Encryption: ".. (b.encryptComms and"on"or"off"))
local e=aW(aN("install.port","Listen port"),nil,"42")b.listenPort=tonumber(e)or 42
aO("Port: "..b.listenPort)print()else b.encryptComms=true;b.listenPort=42 end
if b.device==bO then aK(0x00AAFF)print("--- Tablet Options ---")
aK(0xFFFFFF)print()b.lowBatWarn=
tonumber(aW("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(aW("Critical battery warning %",
nil,"5"))or 5
aO("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end
b.verbose=aX(aN("install.verbose","Verbose boot? (shows debug messages)"))print()return b end
local function cr(a,b)local c={"return {"}local d={}for f in pairs(a)do d[#d+1]=f end
table.sort(d)
for g,f in ipairs(d)do local h=a[f]if type(h)==bf then
c[#c+1]=string.format('  [%q] = %q,',f,h)else
c[#c+1]=string.format('  [%q] = %s,',f,tostring(h))end end;c[#c+1]="}"
local e=io.open((b or"").."/etc/tos.cfg","w")
if e then e:write(table.concat(c,"\n"))e:close()return true end;return false end;local bc=ca({...})bl=bc.temporary==true;local br,aZ,bb;bk.clear()bS()
if
bc.help or bc.unknown then
if bc.unknown and not bc.help then ba("Unknown option: "..
tostring(bc.unknown))print()end
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
print("            TOS reads as an install disk otherwise.)")return end;local bK=bU()bV(bK)local aS=
(not bc.configure)and bT(bc.positional[1])or nil;local a_=aS~=nil;local bL
if a_ and aL.exists(
aS.."/usr/lang")then
local a=bP(aS.."/usr/lang",aL.list,function(b)
local c=io.open(b,"r")if not c then return nil end;local d=c:read("*a")c:close()return d end)
if#a>1 then print()for c,d in ipairs(a)do
print("  "..c..". "..d.name)end;local b=
a[tonumber(aW("Language",nil,"1"))or 1]or a[1]if b.strings then bz=b.strings
bL=b.code end;print()end end;local aP,aQ="",nil;local bd;local aU=false;local bh=bc.profile;local bi=false
if a_ then
aO("Install disk found at: "..aS)print()local a=bC(aS)bd=a and bF(a,bh)local b;aQ,b=bH(aS,bd)
if not aQ and
b=="space"and not bh and a then print()
aK(0x00AAFF)print("--- A smaller install ---")aK(0xFFFFFF)
print("The minimal system is the command line and the core of TOS, with")print("no panels, and takes about 520 KB.")
if
aX(aN("install.minimal_q","Try the minimal system instead?"))then bh=by;bd=bF(a,bh)print()aQ,b=bH(aS,bd)end end
if not aQ then print()if b~="space"then print(bj)end;return end;aP=aQ.prefix;print()aK(0xFFFF00)
if aQ.isBoot then
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")else
print("TOS will be installed on "..bq(aQ)..".")
print("Its /init.lua will be replaced (the current one, if any, is kept")
print("there as /init.lua.pre-tos). The drive this machine boots from")
print("is not changed unless you choose that at the end.")end;aK(0xFFFFFF)print()if not
aX(aN("install.continue","Continue?"))then print(bj)return end
print()
if not bW(_G._FORCE_WIPE or false,aP)then return end;if cg(aP)then
aO("Kept the previous /init.lua as "..aP..aY)end;if
aL and not aL.exists(aP..bn)then br=ci(aP)end;local c;aU,c=cf(aS,aP,bd)if c=="space"then
print()return end
if aU and bh==by then
local d=aP.."/tos/system_manifest.lua"local e=io.open(d..".tmp","w")
local f=e and e:write(cb(bd))if e then e:close()end
if f and aL.size(d..".tmp")>0 then
aL.remove(d)aL.rename(d..".tmp",d)
aO("Minimal system: "..#bd.." files")else
aM("Could not trim the manifest, so `verify` will list the rest as missing.")end;print()end
if not aU then
ba("Install file copy/verify did NOT fully succeed.")
aM("BIOS flash will be skipped to avoid bricking the boot.")
aM("You can retry installation; the partial files won't conflict.")
if not aX("Continue to questionnaire anyway?")then print(bj)return end;print()end;aZ=aU and br and cj(aP,br,bd)or nil
if
aZ and#aZ>0 then aK(0x00AAFF)
print(aN("install.old","--- The old system ---"))aK(0xFFFFFF)aK(0xAAAAAA)
print(#aZ..
aN("install.old_n"," of the previous system's files are still on this drive,"))
print(aN("install.old_why","among TOS's own (/etc, /usr, /bin, /lib). Your /home is not counted."))
print(aN("install.old_1","  1. Leave them where they are"))
print(aN("install.old_2","  2. Move them into /openos, out of TOS's way"))
print(aN("install.old_3","  3. Delete them"))aK(0xFFFFFF)local d=aW(aN(bx,bt),{"1","2","3"},"2")
bb=(d==
"2"and"move")or(d=="3"and bw)or nil
aO(
bb=="move"and"The old system goes into /openos before reboot"or bb==bw and
"The old system is deleted before reboot"or"Leaving the old system's files where they are")print()elseif aU and cl(aP)then aK(0x00AAFF)
print("--- Clean install ---")aK(0xFFFFFF)aK(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
aK(0xFFFFFF)
bi=aX("Remove OpenOS leftovers for a clean install?")
aO(bi and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else aK(0xFFFF00)
print("No install disk detected - running in configuration mode.")aK(0xFFFFFF)aQ=ce()if not aQ then print(bj)return end;aP=aQ.prefix
print(
"Configuring the TOS on "..bq(aQ)..".")print()if
not aX(aN("install.continue","Continue?"))then print(bj)return end;print()end;local aR=cq(bK)aR.language=bL;aK(0x00AAFF)
print("--- Summary ---")aK(0xAAAAAA)
print("  Device:     "..aR.device)print("  Hostname:   "..aR.hostname)
print(
"  Security:   ".. (aR.autoLockout and"Standard"or
(aR.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (aR.encryptComms and"Yes"or"No"))
if aR.device==bO then
print("  Battery:    Warn at "..
aR.lowBatWarn.."% / "..aR.critBatWarn.."%")elseif aR.device=="server"then
print("  Headless:   "..
(aR.headless and"Yes"or"No"))
print("  Services:   "..
(aR.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (aR.verbose and"Yes"or"No"))
if a_ and aU and aZ and#aZ>0 then
print("  Old system: "..
(
bb=="move"and"move into /openos"or bb==bw and bw or"leave in place"))elseif a_ and aU then
print("  Clean inst: "..
(bi and"Yes (remove /bin, /boot, /lib)"or"No"))end;aK(0xFFFFFF)print()if not aX("Apply these settings?")then
print(bj)return end;print()aK(0x00AAFF)
print("--- Applying configuration ---")aK(0xFFFFFF)
if aL then for b,a in ipairs(bB)do if not aL.isDirectory(aP..a)then
aL.makeDirectory(aP..a)end end end;local cs=aR.trustOfficial;aR.trustOfficial=nil;if cr(aR,aP)then aO("Configuration saved to "..
aP.."/etc/tos.cfg")else
aM("Could not save config (defaults will be used)")end
if cs then
local a=aP.."/etc/pkg_trust.cfg"
if aL and aL.exists(a)then
aM("A trust store is already there; to add the key, once TOS is up:")aM("  pkg trust add "..bo.." "..bA)else
local b=io.open(a,"w")
if b then
b:write("return {\n  keys = {\n    [\""..
bo.."\"] = \""..bA.."\",\n  },\n}\n")b:close()
aO("Trusted the Optional Utilities key as '"..bo.."'")else
aM("Could not write "..a.."; trust it later with pkg trust add")end end end;aO("Device profile: "..aR.device)print()
if a_ then if aU then
cp(aS)else
aM("Skipping BIOS flash: file copy did not fully verify.")aM("Re-run install.lua to retry before flashing.")
print()end end;local bs=false
if a_ and aU and aQ and not aQ.isBoot then aK(0x00AAFF)
print("--- Boot drive ---")aK(0xFFFFFF)
print("TOS is on "..bq(aQ)..", but this machine")
print("boots from a different drive, so it would start that system.")
if aX("Boot from the TOS drive from now on?")then
local a,b=pcall(aV.setBootAddress,aQ.address)if a then bs=true
aO("Boot drive set to "..aQ.address:sub(1,8))else
aM("Could not set the boot drive: "..tostring(b))end end
if not bs then
aM("The boot drive is unchanged. To switch later, run `lua` and type:")
print("  require('computer').setBootAddress('"..aQ.address.."')")end;print()end
if a_ and aU and bi then aK(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")aK(0xFFFFFF)local a=cm(aP)
if#a>0 then
aO("Removed: "..table.concat(a,", "))
aM("OpenOS is no longer bootable on this drive — reboot into TOS.")else aM("Nothing to remove (already clean).")end;print()end
if a_ and aU and bb and aZ and#aZ>0 then aK(0x00AAFF)
print(aN("install.old","--- The old system ---"))aK(0xFFFFFF)local a=ck(aP,aZ,bb)
if
aP~=nil and aL.exists(aP..aY)then if bb=="move"then aL.rename(aP..aY,aP..bJ..bm)else
aL.remove(aP..aY)end end
aO(string.format(bb=="move"and"Moved %d file(s) into /openos"or"Deleted %d file(s)",a))if a<#aZ then
aM((#aZ-a).." could not be "..
(bb=="move"and"moved"or"deleted"))end;print()end
if
bl and a_ and aU and aS and aS:find("tos%-netinstall")then
local function a(b)
if aL.isDirectory(b)then local d,c=pcall(aL.list,b)
if d and c then local e={}
for f in c do e[#e+1]=f end;for g,f in ipairs(e)do
a(b.."/"..tostring(f):gsub("/$",""))end end end;pcall(aL.remove,b)end;a(aS)
if aL.exists(aS)then
aM("Could not remove the download at "..
aS.."; delete it to reclaim the space.")else aO("Removed the download at "..aS)end;print()end;aK(0x00AAFF)print("--- Installation Complete ---")
aK(0xFFFFFF)print()aK(0x00FF00)
if a_ and aU then
if
aQ and not aQ.isBoot and not bs then
print("TOS is installed, but this machine still boots from another drive.")else
print(aN("install.done","TOS is installed! Reboot to start."))end elseif a_ then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print(aN("install.first_boot","First boot asks you to set the root password before anything else."))if bi then aK(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")aK(0xFFFFFF)end
aK(0xFFFFFF)print()if aX(aN("install.reboot_q","Reboot now?"))then
aV.shutdown(true)end