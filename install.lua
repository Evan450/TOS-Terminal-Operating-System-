
local bk,bl,bh,br,bs,bt,bu,bK,bv,bw,bd,bL="/init.lua","/tos/kernel/init.lua","Cancelled.","Choice","^(.*)/[^/]+$","^(.+)/[^/]+$","delete","filesystem","install.choice","minimal","string","tablet"local aS=require("component")local aT=require("computer")
local bi=require("term")local aJ=nil
pcall(function()aJ=require(bK)end)local be=aS.gpu;local function aI(a)
if be and be.setForeground then pcall(be.setForeground,a)end end;local function aM(a)aI(0x00FF00)
print("  + "..a)aI(0xFFFFFF)end;local function aK(a)aI(0xFFFF00)
print("  ! "..a)aI(0xFFFFFF)end;local function aZ(a)aI(0xFF0000)
print("  X "..a)aI(0xFFFFFF)end;local bx={}
local function aL(a,b)return bx[a]or b end
local function bM(a,b,c)local e={{code="en",name="English"}}local d={}
for f in b(a)do d[#d+1]=f end;table.sort(d)
for g,f in ipairs(d)do local i=f:match("^(%a+)%.lang$")local j=i and
c(a.."/"..f)local k=j and load(j,"="..f,"t",{})local l,h=false,
nil;if k then l,h=pcall(k)end
if l and type(h)=="table"and
type(h.strings)=="table"then local m=
type(h.meta)=="table"and h.meta or{}
e[#e+1]={code=i,name=tostring(m.name or i),strings=h.strings}end end;return e end
local function aU(c,b,a)aI(0xFFFF00)io.write(c)
if b then aI(0xAAAAAA)io.write(" ["..
table.concat(b,"/").."]")end;if a then aI(0x888888)
io.write(" (default: "..a..")")end;aI(0xFFFFFF)io.write(": ")local d
if bi and
bi.read then local e,f=pcall(bi.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function aV(a)local b=aU(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end;local bm="discover"local bj=false
local by="dcdafa5342333048be0ad519911a6bd1ecffefcffde73879a4e246fc20d7fd8b"local bN="1.5.0"
local bz={"/tos","/tos/kernel","/tos/kernel/net","/tos/shell","/tos/compat","/tos/peripheral","/tos/shell/panels","/etc","/etc/rc.d","/home","/public","/root","/usr","/usr/bin","/usr/lib","/usr/modules","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/tmp"}
local bO={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function bP()aI(0x00AAFF)for b,a in ipairs(bO)do print("   "..a)end
aI(0xFFFFFF)print()aI(0x00FF66)print("   Strata Systems LLC")
aI(0xFFFFFF)aI(0xAAAAAA)
print("   Terminal Operating System — Setup v"..bN)aI(0xFFFFFF)print()end
local function bQ(a)if not aJ then return nil end;if type(a)==bd and a~=""then local d=a:sub(-1)=="/"and
a:sub(1,-2)or a
if aJ.exists(d..bl)then return d end end;local b=
os.getenv and os.getenv("_")or nil
if b then local d=b:match(bs)if d and d~=""and aJ.exists(
d..bl)then return d end end;local c=aT.getBootAddress()
for d in aS.list(bK)do
if d~=c then
local f,e=pcall(aS.proxy,d)if not f then e=nil end
local g,h=pcall(function()return e and e.exists(bl)end)
local i,j=pcall(function()return e and e.exists("/install.lua")end)
if g and i and h and j then
if aJ.mounts then local l,k=pcall(aJ.mounts)if l and k then
for m,n in k do local o,p=m,n;if type(m)==
bd then o,p=n,m end;if type(o)=="table"and o.address==d then return
tostring(p)end end end end end end end;return nil end
local function bR()local a={}a.totalMem=aT.totalMemory()a.freeMem=aT.freeMemory()a.memKB=math.floor(
a.totalMem/1024)if be then local d,e=be.maxResolution()
a.maxW,a.maxH=d,e
if d>=160 then a.gpuTier=3 elseif d>=80 then a.gpuTier=2 else a.gpuTier=1 end end
local c=aT.getBootAddress()local aM,b=pcall(aS.proxy,c)if not aM or not b then
b={spaceTotal=function()return 0 end,spaceUsed=function()return 0 end}end
a.diskTotal=b.spaceTotal()
a.diskFree=math.max(0,a.diskTotal-b.spaceUsed())a.diskKB=math.floor(a.diskTotal/1024)a.diskFreeKB=math.floor(
a.diskFree/1024)
a.hasModem,a.hasWireless,a.hasTunnel,a.hasDataCard=false,false,false,false;a.hasGPU,a.hasScreen,a.hasKeyboard=false,false,false
for e,d in aS.list()do
if d=="modem"then
a.hasModem=true
pcall(function()a.hasWireless=aS.proxy(e).isWireless()end)elseif d=="tunnel"then a.hasTunnel=true elseif d=="data"then a.hasDataCard=true elseif d=="gpu"then a.hasGPU=true elseif d==
"screen"then a.hasScreen=true elseif d=="keyboard"then a.hasKeyboard=true end end;return a end
local function bS(a)aI(0x00AAFF)print("--- Hardware Detected ---")
aI(0xAAAAAA)
print(string.format("  RAM:      %dKB total (%dKB free)",a.memKB,math.floor(a.freeMem/1024)))
print(string.format("  GPU:      Tier %d (%dx%d max)",a.gpuTier or 1,a.maxW or 50,a.maxH or 16))
print(string.format("  Disk:     %dKB total (%dKB free)",a.diskKB,a.diskFreeKB))
print(string.format("  Network:  %s",a.hasModem and
(a.hasWireless and"Wireless"or"Wired")or"None"))
if a.hasTunnel then print("  Tunnel:   Linked card detected")end
print(string.format("  Crypto:   %s",a.hasDataCard and"Hardware (data card)"or"Software"))aI(0xFFFFFF)print()local b=a.hasModem or a.hasTunnel
if
a.memKB<1024 or(b and a.memKB<1280)then
if b then
aK("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")else
aK("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")end
aK("With less its commands do not load, or it does not boot.")elseif a.memKB<1536 then
aK("TOS will start at the command line: the full interface needs 1.5 MB.")end;print()end
local function bA(a)local c=a.."/tos/system_manifest.lua"if not aJ.exists(c)then return nil,
"no manifest at "..c end
local d=io.open(c,"r")if not d then return nil,"cannot open manifest"end
local b=d:read("*a")d:close()if not b then return nil,"empty manifest"end
if
#b>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local h,e=pcall(require,"kernel.serialize")
if h and e and e.decode then local k,l=e.decode(b,{maxBytes=
256*1024})
if
k and type(k)=="table"then return k elseif k==nil then
aK("manifest serialize.decode failed ("..
tostring(l).."); falling back to constrained load()")end end;local g,i=load(b,"=manifest","t",{})if not g then return nil,
"manifest parse error: "..tostring(i)end;local j,f=pcall(g)
if
not j then return nil,"manifest run error: "..tostring(f)end
if type(f)~="table"then return nil,"manifest did not return a table"end;return f end
local function bT(b,a)if b then return true end;a=a or""
if aJ.exists(a.."/etc/users.dat")then local c=io.open(a..
"/etc/users.dat","r")
if c then local d=c:read("*a")
c:close()
if d and#d>0 then
aK("Existing TOS install detected (/etc/users.dat is populated).")
aK("Re-installing will overwrite users, configuration, and the")
aK("system tree but will NOT delete user data under /home or /tmp.")aI(0xFFFF00)
io.write("Type FORCE-WIPE to confirm: ")aI(0xFFFFFF)local e=io.read()or""if e~="FORCE-WIPE"then
aZ("Install aborted by safety check.")return false end end end end;return true end
local function bU(a,b)local d=io.open(a,"r")if not d then return false,"open source"end
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
local function bV(c,d,a,b)a=a or""local e,f={},{}
for h,g in ipairs(d)do local i=a..g.path
if not aJ.exists(i)then
e[#e+1]=i else
local j=(b and b[g.path])or aJ.size(c..g.path)or 0;local k=aJ.size(i)or 0;if j~=k then
f[#f+1]=string.format("%s (src=%d dst=%d)",i,j,k)end end end;return e,f end;local bB=512
local function bC(d,e,b,c,a)a=a or""local f,g=0,{}
for i,h in ipairs(e)do local k=b(d..h.path)or 0;if
c(a..h.path)then
f=f+math.max(0,k- (b(a..h.path)or 0))else f=f+k+bB end
local j=h.path:match(bt)while j and j~=""and not g[j]do g[j]=true;if not c(a..j)then f=f+bB end
j=j:match(bt)end end;return f end
local function bn(c,d)
local e,a=pcall(aJ.get,(c==nil or c=="")and"/"or c)
local f,b=pcall(aJ.get,(d==nil or d=="")and"/"or d)return
e and f and a and b and a.address==b.address or false end
local function bW(a)
local d,b=pcall(aJ.get,(a==nil or a=="")and"/"or a)if not d or not b then return nil end;local e,c=pcall(b.spaceTotal)
local f,g=pcall(b.spaceUsed)if not(e and f)or type(c)~="number"or c<=0 then
return nil end;return c-g end
local function bX(a)local b,c={},nil;for e,d in ipairs(a)do
b[e]=(d.free==nil)or(d.free>=d.need)end;for d,e in ipairs(a)do
if e.isBoot and b[d]then c=d;break end end;if not c then
for d=1,#a do if b[d]then c=d;break end end end;return c,b end
local function bY(a)local b={positional={}}local c=1
while c<=#a do local d=a[c]
if
d=="-h"or d=="--help"or d=="-?"or d=="/?"then b.help=true elseif d=="--configure"then b.configure=true elseif d==
"--temporary"then b.temporary=true elseif d=="--profile"then c=c+1;if a[c]==bw or a[c]=="full"then
b.profile=a[c]else
b.unknown=b.unknown or("--profile "..tostring(a[c]))end elseif type(d)==bd and d:sub(1,1)==
"-"then b.unknown=b.unknown or d else
b.positional[#b.positional+1]=d end;c=c+1 end;return b end;local function bD(a,b)if b~=bw then return a end;local c={}
for e,d in ipairs(a)do if d.floor then c[#c+1]=d end end;return c end
local function bZ(a)
local b={"-- Written by install.lua: the files this profile installed.","return {"}
for d,c in ipairs(a)do
local e={string.format("path = %q",c.path),"critical = "..
tostring(c.critical==true)}if c.floor then e[#e+1]="floor = true"end;if c.hash then
e[#e+1]=string.format("hash = %q",c.hash)end;b[#b+1]="  { "..
table.concat(e,", ").." },"end;b[#b+1]="}"return table.concat(b,"\n").."\n"end
local function b_()local a={}if not(aJ and aJ.mounts)then return a end
local c,b=pcall(aJ.mounts)if not c or type(b)~="function"then return a end
for d,e in b do local g,h=d,e;if
type(d)==bd then g,h=e,d end
local f=type(g)=="table"and g.address or nil
if f and type(h)==bd then a[f]=a[f]or{}a[f][#a[f]+1]=h end end;return a end
local function ca(a)
for c,b in ipairs(a)do if b:sub(1,5)=="/mnt/"then return b end end;for c,b in ipairs(a)do if b~="/"then return b end end;return nil end
local function bc(a)if a>=1024*1024 then
return string.format("%.1f MB",a/1024/1024)end;return
string.format("%d KB",math.floor(a/1024))end
local function bE(a,b)local e=b_()local f=aT.getBootAddress()local g=
aT.tmpAddress and aT.tmpAddress()or nil;local h=
a:sub(-1)=="/"and a:sub(1,-2)or a;local c,d={},0
for i in aS.list(bK)do
local k,j=pcall(aS.proxy,i)local l,m=false,true;if k and j then l,m=pcall(j.isReadOnly)end
if
i~=g and k and j and l and not m then local o=e[i]or{}local p=i==f
local n=p and""or ca(o)local q=false;for s,r in ipairs(o)do if r==h then q=true end end
if q then elseif not n then d=d+1 else
local r={address=i,prefix=n,isBoot=p}local t,u=pcall(j.getLabel)r.label=t and u or nil
local v,s=pcall(j.spaceTotal)local w,x=pcall(j.spaceUsed)if
v and w and type(s)=="number"and s>0 then r.total,r.free=s,s-x end
local y,z=pcall(j.exists,bk)local A,B=pcall(j.exists,bl)r.hasInit=y and z or false;r.hasTos=A and B or
false
r.need=b and bC(a,b,aJ.size,aJ.exists,n)or 0;if bj and bn(a,n)then r.need=0 end;c[#c+1]=r end end end
table.sort(c,function(i,j)if i.isBoot~=j.isBoot then return i.isBoot end;return
i.prefix<j.prefix end)return c,d end
local function bo(a)
local b=a.isBoot and"the boot drive"or("the drive at "..a.prefix)
if a.label and a.label~=""then b=b..' "'..a.label..'"'end;return b end
local function bF(a,b)local c,f=bE(a,b)if#c==0 then
return{address=aT.getBootAddress(),prefix="",isBoot=true,need=0}end;local d,e=bX(c)
if#c==1 and d==1 then return c[1]end;aI(0x00AAFF)
print(aL("install.where","--- Where should TOS go? ---"))aI(0xFFFFFF)
for h,g in ipairs(c)do if g.isBoot and g.free and g.free<g.need then
aK(string.format("The boot drive has %s free; TOS needs %s.",bc(g.free),bc(g.need)))end end
for h,g in ipairs(c)do
local j=string.format("  %d. %s%s",h,g.isBoot and"Boot drive"or g.prefix,
(g.label and
g.label~="")and('  "'..g.label..'"')or"")if e[h]then aI(0xFFFFFF)else aI(0x888888)end
print(j.. (
h==d and"   <- default"or""))
local k=
g.total and string.format("%s, %s free",bc(g.total),bc(g.free))or"size unknown"local i={}if g.hasTos then i[#i+1]="has TOS"elseif g.hasInit then i[#i+1]="has an OS"else
i[#i+1]="empty"end;if not e[h]then i[#i+1]="too small: needs "..
bc(g.need)end
aI(0xAAAAAA)
print("     "..k.."; "..table.concat(i,", "))end;aI(0xFFFFFF)if f>0 then
aK(f.." more drive(s) are not mounted, so they are not listed.")end
if not d then print()
aZ("None of these drives has room for TOS.")
aK("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
aK("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")return nil,"space"end;print()
while true do
local h=aU(aL("install.which_drive","Install on which drive? (0 = cancel)"),nil,tostring(d))local g=tonumber(h)if g==0 then return nil end
if g and c[g]then
if e[g]then return c[g]end
aK("That drive is too small: TOS needs "..bc(c[g].need)..".")else aK("Type a number from the list.")end end end
local function cb()local b=bE("",nil)local a={}
for e,d in ipairs(b)do if d.hasTos then a[#a+1]=d end end;if#a==0 then
aZ("No drive holds a TOS installation to configure.")
aK("Insert the TOS install disk to install it first.")return nil end;if
#a==1 then return a[1]end;aI(0x00AAFF)
print("--- Which TOS should be configured? ---")aI(0xFFFFFF)
for e,d in ipairs(a)do
print(string.format("  %d. %s%s",e,d.isBoot and"Boot drive"or d.prefix,
(
d.label and d.label~="")and('  "'..d.label..'"')or""))end;print()
while true do
local d=aU("Configure which drive? (0 = cancel)",nil,"1")local c=tonumber(d)if c==0 then return nil end
if c and a[c]then return a[c]end;aK("Type a number from the list.")end end
local function cc(b,a,c)a=a or""local e,k=c,nil;if not e then e,k=bA(b)end;if not e then
aZ("Cannot load install manifest: "..tostring(k))return false end;aM("Manifest loaded: "..
#e.." files declared")
local h=bC(b,e,aJ.size,aJ.exists,a)local j=bj and bn(b,a)if j then h=0 end;local g=bW(a)
if g and h>g then print()
aZ(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",math.ceil(
h/1024),math.floor(g/1024)))
aK("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
aK("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")aK("holds TOS on its own.")return false,"space"end;if g then
aM(string.format("Space: TOS needs %d KB, and %d KB is free",math.ceil(h/1024),math.floor(g/1024)))end;print()
aI(0x00AAFF)
print(aL("install.dirs","--- Creating directories ---"))aI(0xFFFFFF)local l={}
for o,n in ipairs(e)do local p=n.path:match(bt)
while p and p~=""and
not l[p]do l[p]=true;if not aJ.isDirectory(a..p)then
aJ.makeDirectory(a..p)end;p=p:match(bt)end end;for o,n in ipairs(bz)do if not aJ.isDirectory(a..n)then
aJ.makeDirectory(a..n)end end
aM("Directory structure created")print()aI(0x00AAFF)
print(aL("install.copying","--- Copying system files ---"))aI(0xFFFFFF)local i,d=0,0;local f={}local m=j and{}or nil
for o,n in ipairs(e)do
local q=b..n.path;local p=a..n.path
if not aJ.exists(q)then d=d+1
f[#f+1]="missing on disk: "..n.path else local r,s
if j then m[n.path]=aJ.size(q)
if aJ.exists(p)then aJ.remove(p)end;r=aJ.rename(q,p)and aJ.exists(p)end;if not r then r,s=bU(q,p)end;if r then i=i+1 else d=d+1
f[#f+1]=n.path..": "..tostring(s)end end end;print()
if d==0 then aM("Copied "..i.." files")else
aZ("Copied "..i..
" files, "..d.." FAILED:")for n=1,math.min(5,#f)do aK("  "..f[n])end
if#f>5 then aK("  (+"..
(#f-5).." more)")end end;print()
if d==0 then aI(0x00AAFF)
print(aL("install.verifying","--- Verifying copy ---"))aI(0xFFFFFF)local n,o=bV(b,e,a,m)
if#n==0 and#o==0 then aM("All "..
#e.." files verified")else
if#n>0 then
aZ(#n.." files MISSING after copy:")for p=1,math.min(5,#n)do aK("  "..n[p])end;d=d+#n end
if#o>0 then
aZ(#o.." files have WRONG SIZE after copy:")for p=1,math.min(5,#o)do aK("  "..o[p])end;d=d+#o end end;print()end;return d==0 end;local bG={"/bin","/boot","/lib"}local aW="/init.lua.pre-tos"
local function cd(a)a=a or""if
not aJ or not aJ.exists(
a..bk)or aJ.exists(a..aW)then return false end
local c=io.open(a..bk,"r")if not c then return false end;local b=c:read("*a")c:close()if not b or b==""or
b:find("_TOS",1,true)then return false end
local d=io.open(a..aW,"w")if not d then return false end;d:write(b)d:close()
return aJ.exists(a..aW)end;local bH="/openos"
local function ce(a)for c,b in
ipairs({"/home","/mnt","/tmp","/dev","/openos",bk})do
if a==b or a:sub(1,#b+1)==b.."/"then return false end end
if
a:find("tos%-netinstall")or a=="/bootstrap.lua"then return false end;return true end
local function cf(a)a=a or""local b={}
local function c(d)
local f,e=pcall(aJ.list,(a..d)==""and"/"or(a..d))if not f or not e then return end
for g in e do local h=(d=="/"and""or d).."/"..
tostring(g):gsub("/$","")if ce(h)and bn(a..
h,a)then
if aJ.isDirectory(a..h)then c(h)else b[#b+1]=h end end end end;c("/")return b end
local function cg(a,b,c)local e={}for g,f in ipairs(c or{})do e[f.path]=true end;local d={}
for g,f in
ipairs(b or{})do if
not e[f]and aJ.exists(a..f)and not aJ.isDirectory(a..f)then d[#d+1]=f end end;return d end
local function ch(a,b,c)local e,f=0,{}
for h,g in ipairs(b)do local j
if c=="move"then local l=a..bH..g;local k=l:match(bs)if k and not
aJ.exists(k)then aJ.makeDirectory(k)end;j=aJ.rename(
a..g,l)else j=aJ.remove(a..g)end;if j then e=e+1 end;local i=g:match(bs)
while i and i~=""do f[i]=true;i=i:match(bs)end end;local d={}for g in pairs(f)do d[#d+1]=g end
table.sort(d,function(g,h)return#g>#h end)
for h,g in ipairs(d)do local j,i=pcall(aJ.list,a..g)
local k=j and i and i()==nil;if k then aJ.remove(a..g)end end;return e end
local function ci(a)a=a or""if not aJ then return false end;for c,b in ipairs(bG)do
if aJ.exists(a..b)then return true end end;return false end
local function cj(a)a=a or""local b={}if not aJ then return b end;for d,c in ipairs(bG)do
if aJ.exists(a..c)then
local e=pcall(aJ.remove,a..c)if e and not aJ.exists(a..c)then b[#b+1]=c end end end
if#b>0 and aJ.exists(a..
aW)then pcall(aJ.remove,a..aW)if not
aJ.exists(a..aW)then b[#b+1]=aW end end;return b end
local function ck(a,b)
if aS.isAvailable("data")then local k,j=pcall(aS.data.sha256,a)
if k and
type(j)==bd and#j==32 then return
(j:gsub(".",function(l)
return("%02x"):format(l:byte())end))end end
local c=io.open(b.."/tos/kernel/sha256.lua","r")if not c then return nil end;local e=c:read("*a")c:close()
local f=e and
load(e,"=sha256","t",{string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,error=error,assert=assert,setmetatable=setmetatable})if not f then return nil end;local g,d=pcall(f)if not
(g and type(d)=="table"and d.hex)then return nil end
local h,i=pcall(d.hex,a)return h and i or nil end
local function cl(a)local d=a.."/bios.lua"if not aJ.exists(d)then return end
local c=io.open(d,"r")
if not c then aK("Could not read bios.lua")print()return end;local b=c:read("*a")c:close()if not b or#b==0 then
aK("Empty bios.lua")print()return end;local e=ck(b,a)local g=e and
(e:sub(1,16).."...")or"(unavailable)"
aI(0xFFFF00)print("A TOS BIOS was found on the install disk.")
print("Flashing it replaces your current EEPROM code.")
print("  size:        "..#b.." bytes")print("  SHA-256:     "..g)aI(0xFFFFFF)
aI(0xFFFF00)io.write('Type "flash" to confirm BIOS reflash: ')
aI(0xFFFFFF)local h=io.read()or""if h~="flash"then aM("Skipped BIOS flash")
print()return end;local f=aS.list("eeprom")()
if f then
local i=aS.proxy(f)i.set(b)i.setLabel("TOS BIOS")
aM("BIOS flashed! Label set to 'TOS BIOS'")else aK("No EEPROM found")end;print()end
local function cm(a)local b={}aI(0x00AAFF)
print(aL("install.device","--- Device Setup ---"))aI(0xFFFFFF)print()
print(aL("install.device_q","What type of device is this?"))aI(0xAAAAAA)
print(aL("install.device_1","  1. Computer  (desktop, tower with screen)"))
print(aL("install.device_2","  2. Tablet    (portable, battery-powered)"))
print(aL("install.device_3","  3. Server    (rack blade, typically headless)"))aI(0xFFFFFF)local c=aU(aL(bv,br),{"1","2","3"},"1")
if
c=="2"then b.device=bL;b.showBattery=true;b.powerSave=true
aM("Tablet mode (battery monitoring on)")elseif c=="3"then b.device="server"b.headless=true;b.autoServices=true
aM("Server mode (headless boot, services auto-start)")print()aI(0xFFFF00)print("  Server rack checklist:")
aI(0xAAAAAA)
if a.hasModem or a.hasTunnel then aM("Network card detected")else
aK("No modem or linked card! The server will be unreachable.")
aK("Insert a network card in the rack before rebooting.")end
if not a.hasGPU and not a.hasScreen then
aM("Headless (no GPU/screen) — normal for servers")else
aK("GPU or screen detected — will boot headless anyway.")
aK("Remove them to free rack slots, or choose Computer mode.")end;aI(0xFFFFFF)else b.device="computer"b.showBattery=false;b.powerSave=false
aM("Computer mode")end;print()
math.randomseed(math.floor(aT.uptime()*1000)+
aT.freeMemory())
b.hostname=aU(aL("install.hostname","Hostname"),nil,"tos-"..
string.format("%04x",math.random(0,0xFFFF)))aM("Hostname: "..b.hostname)print()
aI(0x00AAFF)
print(aL("install.security","--- Security ---"))aI(0xFFFFFF)print()
print(aL("install.security_q","Security level:"))aI(0xAAAAAA)
print(aL("install.security_1","  1. Standard  (login + lockout after 5 failures)"))
print(aL("install.security_2","  2. Relaxed   (login, no lockout)"))
print(aL("install.security_3","  3. Open      (allows guest access)"))aI(0xFFFFFF)local d=aU(aL(bv,br),{"1","2","3"},"1")
if
d=="3"then b.guestAccess=true;b.autoLockout=false;b.maxAttempts=999
aM("Security: Open")elseif d=="2"then b.guestAccess=false;b.autoLockout=false;b.maxAttempts=999
aM("Security: Relaxed")else b.guestAccess=false;b.autoLockout=true;b.maxAttempts=5
aM("Security: Standard")end;print()
print(aL("install.accounts_q","Who may add, remove and change user accounts?"))aI(0xAAAAAA)
print(aL("install.accounts_1","  1. Root only"))
print(aL("install.accounts_2","  2. Root, and admins for ordinary accounts"))aI(0xFFFFFF)
b.accountAdmins=aU(aL(bv,br),{"1","2"},"1")=="2"
aM(b.accountAdmins and"Accounts: root, and admins for ordinary accounts"or
"Accounts: root only")print()
print(aL("install.trust_1","The Optional Utilities are signed by their publisher. Trusting"))
print(aL("install.trust_2","the key makes them install as trusted; `pkg trust` undoes it."))
b.trustOfficial=aV(aL("install.trust_q","Trust the Optional Utilities publisher?"))
aM(b.trustOfficial and"Optional Utilities key: trusted"or"Optional Utilities key: not trusted")print()
if a.hasModem or a.hasTunnel then aI(0x00AAFF)
print(aL("install.network","--- Network ---"))aI(0xFFFFFF)print()
b.encryptComms=aV(aL("install.encrypt","Encrypt network communications?"))
aM("Encryption: ".. (b.encryptComms and"on"or"off"))
local e=aU(aL("install.port","Listen port"),nil,"42")b.listenPort=tonumber(e)or 42
aM("Port: "..b.listenPort)print()else b.encryptComms=true;b.listenPort=42 end
if b.device==bL then aI(0x00AAFF)print("--- Tablet Options ---")
aI(0xFFFFFF)print()b.lowBatWarn=
tonumber(aU("Low battery warning %",nil,"15"))or 15
b.critBatWarn=tonumber(aU("Critical battery warning %",
nil,"5"))or 5
aM("Battery warnings: "..b.lowBatWarn.."% / "..b.critBatWarn.."%")print()end
b.verbose=aV(aL("install.verbose","Verbose boot? (shows debug messages)"))print()return b end
local function cn(a,b)local c={"return {"}local d={}for f in pairs(a)do d[#d+1]=f end
table.sort(d)
for g,f in ipairs(d)do local h=a[f]if type(h)==bd then
c[#c+1]=string.format('  [%q] = %q,',f,h)else
c[#c+1]=string.format('  [%q] = %s,',f,tostring(h))end end;c[#c+1]="}"
local e=io.open((b or"").."/etc/tos.cfg","w")
if e then e:write(table.concat(c,"\n"))e:close()return true end;return false end;local ba=bY({...})bj=ba.temporary==true;local bp,aX,a_;bi.clear()bP()
if
ba.help or ba.unknown then
if ba.unknown and not ba.help then aZ("Unknown option: "..
tostring(ba.unknown))print()end
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
print("            TOS reads as an install disk otherwise.)")return end;local bI=bR()bS(bI)local aQ=
(not ba.configure)and bQ(ba.positional[1])or nil;local aY=aQ~=nil;local bJ
if aY and aJ.exists(
aQ.."/usr/lang")then
local a=bM(aQ.."/usr/lang",aJ.list,function(b)
local c=io.open(b,"r")if not c then return nil end;local d=c:read("*a")c:close()return d end)
if#a>1 then print()for c,d in ipairs(a)do
print("  "..c..". "..d.name)end;local b=
a[tonumber(aU("Language",nil,"1"))or 1]or a[1]if b.strings then bx=b.strings
bJ=b.code end;print()end end;local aN,aO="",nil;local bb;local aR=false;local bf=ba.profile;local bg=false
if aY then
aM("Install disk found at: "..aQ)print()local a=bA(aQ)bb=a and bD(a,bf)local b;aO,b=bF(aQ,bb)
if not aO and
b=="space"and not bf and a then print()
aI(0x00AAFF)print("--- A smaller install ---")aI(0xFFFFFF)
print("The minimal system is the command line and the core of TOS, with")print("no panels, and takes about 520 KB.")
if
aV(aL("install.minimal_q","Try the minimal system instead?"))then bf=bw;bb=bD(a,bf)print()aO,b=bF(aQ,bb)end end
if not aO then print()if b~="space"then print(bh)end;return end;aN=aO.prefix;print()aI(0xFFFF00)
if aO.isBoot then
print("TOS will be installed on the current boot drive.")
print("Your /init.lua will be replaced (the current one is kept as")
print("/init.lua.pre-tos; rename it back to boot the old system).")else
print("TOS will be installed on "..bo(aO)..".")
print("Its /init.lua will be replaced (the current one, if any, is kept")
print("there as /init.lua.pre-tos). The drive this machine boots from")
print("is not changed unless you choose that at the end.")end;aI(0xFFFFFF)print()if not
aV(aL("install.continue","Continue?"))then print(bh)return end
print()
if not bT(_G._FORCE_WIPE or false,aN)then return end;if cd(aN)then
aM("Kept the previous /init.lua as "..aN..aW)end;if
aJ and not aJ.exists(aN..bl)then bp=cf(aN)end;local c;aR,c=cc(aQ,aN,bb)if c=="space"then
print()return end
if aR and bf==bw then
local d=aN.."/tos/system_manifest.lua"local e=io.open(d..".tmp","w")
local f=e and e:write(bZ(bb))if e then e:close()end
if f and aJ.size(d..".tmp")>0 then
aJ.remove(d)aJ.rename(d..".tmp",d)
aM("Minimal system: "..#bb.." files")else
aK("Could not trim the manifest, so `verify` will list the rest as missing.")end;print()end
if not aR then
aZ("Install file copy/verify did NOT fully succeed.")
aK("BIOS flash will be skipped to avoid bricking the boot.")
aK("You can retry installation; the partial files won't conflict.")
if not aV("Continue to questionnaire anyway?")then print(bh)return end;print()end;aX=aR and bp and cg(aN,bp,bb)or nil
if
aX and#aX>0 then aI(0x00AAFF)
print(aL("install.old","--- The old system ---"))aI(0xFFFFFF)aI(0xAAAAAA)
print(#aX..
aL("install.old_n"," of the previous system's files are still on this drive,"))
print(aL("install.old_why","among TOS's own (/etc, /usr, /bin, /lib). Your /home is not counted."))
print(aL("install.old_1","  1. Leave them where they are"))
print(aL("install.old_2","  2. Move them into /openos, out of TOS's way"))
print(aL("install.old_3","  3. Delete them"))aI(0xFFFFFF)local d=aU(aL(bv,br),{"1","2","3"},"2")
a_=(d==
"2"and"move")or(d=="3"and bu)or nil
aM(
a_=="move"and"The old system goes into /openos before reboot"or a_==bu and
"The old system is deleted before reboot"or"Leaving the old system's files where they are")print()elseif aR and ci(aN)then aI(0x00AAFF)
print("--- Clean install ---")aI(0xFFFFFF)aI(0xAAAAAA)
print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
print("your data (/home, /tmp, /mnt) and config are left untouched.")
print("This happens last, right before reboot — OpenOS won't be")print("bootable afterward, but TOS will be.")
aI(0xFFFFFF)
bg=aV("Remove OpenOS leftovers for a clean install?")
aM(bg and"Will clean OpenOS leftovers before reboot"or"Leaving OpenOS files in place")print()end else aI(0xFFFF00)
print("No install disk detected - running in configuration mode.")aI(0xFFFFFF)aO=cb()if not aO then print(bh)return end;aN=aO.prefix
print(
"Configuring the TOS on "..bo(aO)..".")print()if
not aV(aL("install.continue","Continue?"))then print(bh)return end;print()end;local aP=cm(bI)aP.language=bJ;aI(0x00AAFF)
print("--- Summary ---")aI(0xAAAAAA)
print("  Device:     "..aP.device)print("  Hostname:   "..aP.hostname)
print(
"  Security:   ".. (aP.autoLockout and"Standard"or
(aP.guestAccess and"Open"or"Relaxed")))
print("  Encryption: ".. (aP.encryptComms and"Yes"or"No"))
if aP.device==bL then
print("  Battery:    Warn at "..
aP.lowBatWarn.."% / "..aP.critBatWarn.."%")elseif aP.device=="server"then
print("  Headless:   "..
(aP.headless and"Yes"or"No"))
print("  Services:   "..
(aP.autoServices and"Auto-start"or"Manual"))end
print("  Verbose:    ".. (aP.verbose and"Yes"or"No"))
if aY and aR and aX and#aX>0 then
print("  Old system: "..
(
a_=="move"and"move into /openos"or a_==bu and bu or"leave in place"))elseif aY and aR then
print("  Clean inst: "..
(bg and"Yes (remove /bin, /boot, /lib)"or"No"))end;aI(0xFFFFFF)print()if not aV("Apply these settings?")then
print(bh)return end;print()aI(0x00AAFF)
print("--- Applying configuration ---")aI(0xFFFFFF)
if aJ then for b,a in ipairs(bz)do if not aJ.isDirectory(aN..a)then
aJ.makeDirectory(aN..a)end end end;local co=aP.trustOfficial;aP.trustOfficial=nil;if cn(aP,aN)then aM("Configuration saved to "..
aN.."/etc/tos.cfg")else
aK("Could not save config (defaults will be used)")end
if co then
local a=aN.."/etc/pkg_trust.cfg"
if aJ and aJ.exists(a)then
aK("A trust store is already there; to add the key, once TOS is up:")aK("  pkg trust add "..bm.." "..by)else
local b=io.open(a,"w")
if b then
b:write("return {\n  keys = {\n    [\""..
bm.."\"] = \""..by.."\",\n  },\n}\n")b:close()
aM("Trusted the Optional Utilities key as '"..bm.."'")else
aK("Could not write "..a.."; trust it later with pkg trust add")end end end;aM("Device profile: "..aP.device)print()
if aY then if aR then
cl(aQ)else
aK("Skipping BIOS flash: file copy did not fully verify.")aK("Re-run install.lua to retry before flashing.")
print()end end;local bq=false
if aY and aR and aO and not aO.isBoot then aI(0x00AAFF)
print("--- Boot drive ---")aI(0xFFFFFF)
print("TOS is on "..bo(aO)..", but this machine")
print("boots from a different drive, so it would start that system.")
if aV("Boot from the TOS drive from now on?")then
local a,b=pcall(aT.setBootAddress,aO.address)if a then bq=true
aM("Boot drive set to "..aO.address:sub(1,8))else
aK("Could not set the boot drive: "..tostring(b))end end
if not bq then
aK("The boot drive is unchanged. To switch later, run `lua` and type:")
print("  require('computer').setBootAddress('"..aO.address.."')")end;print()end
if aY and aR and bg then aI(0x00AAFF)
print("--- Cleaning OpenOS leftovers ---")aI(0xFFFFFF)local a=cj(aN)
if#a>0 then
aM("Removed: "..table.concat(a,", "))
aK("OpenOS is no longer bootable on this drive — reboot into TOS.")else aK("Nothing to remove (already clean).")end;print()end
if aY and aR and a_ and aX and#aX>0 then aI(0x00AAFF)
print(aL("install.old","--- The old system ---"))aI(0xFFFFFF)local a=ch(aN,aX,a_)
if
aN~=nil and aJ.exists(aN..aW)then if a_=="move"then aJ.rename(aN..aW,aN..bH..bk)else
aJ.remove(aN..aW)end end
aM(string.format(a_=="move"and"Moved %d file(s) into /openos"or"Deleted %d file(s)",a))if a<#aX then
aK((#aX-a).." could not be "..
(a_=="move"and"moved"or"deleted"))end;print()end
if
bj and aY and aR and aQ and aQ:find("tos%-netinstall")then
local function a(b)
if aJ.isDirectory(b)then local d,c=pcall(aJ.list,b)
if d and c then local e={}
for f in c do e[#e+1]=f end;for g,f in ipairs(e)do
a(b.."/"..tostring(f):gsub("/$",""))end end end;pcall(aJ.remove,b)end;a(aQ)
if aJ.exists(aQ)then
aK("Could not remove the download at "..
aQ.."; delete it to reclaim the space.")else aM("Removed the download at "..aQ)end;print()end;aI(0x00AAFF)print("--- Installation Complete ---")
aI(0xFFFFFF)print()aI(0x00FF00)
if aY and aR then
if
aO and not aO.isBoot and not bq then
print("TOS is installed, but this machine still boots from another drive.")else
print(aL("install.done","TOS is installed! Reboot to start."))end elseif aY then
print("Partial install — re-run from the install disk to retry.")else print("Configuration applied!")end
print(aL("install.first_boot","First boot asks you to set the root password before anything else."))if bg then aI(0xFFFF00)
print("Clean install: reboot now — OpenOS libraries were removed.")aI(0xFFFFFF)end
aI(0xFFFFFF)print()if aV(aL("install.reboot_q","Reboot now?"))then
aT.shutdown(true)end