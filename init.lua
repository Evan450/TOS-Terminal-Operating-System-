
local aI,aJ,aR,ar,aS,aK,aT,aA="/init.lua","/tos/kernel/init.lua","filesystem","key_down","reboot","screen","splash","string"local ae=...local ak=component;local af=computer
if not load("return 1<<1")then local a
for c in
ak.list("gpu")do local e,d=pcall(ak.proxy,c)if e and d then a=d;break end end;local b;for c in ak.list(aK)do b=c;break end
if a and b then pcall(a.bind,b)
pcall(a.setBackground,0x000000)pcall(a.setForeground,0xFFFFFF)
pcall(a.fill,1,1,80,25," ")
pcall(a.set,2,2,"TOS requires the Lua 5.3 or 5.4 CPU architecture.")
pcall(a.set,2,3,"This CPU is running an older one (Lua 5.2).")
pcall(a.set,2,5,"Fix: sneak-click (crouch + right-click) the CPU in its")
pcall(a.set,2,6,"computer-case slot to cycle architectures, then reboot.")pcall(a.set,2,8,"Press any key to power off.")end;pcall(af.beep,800,0.3)
while true do
local c=af.pullSignal(math.huge)if c==ar then af.shutdown()end end end
if not ae and _G._TOS_UNMANAGED_ROOT then ae=_G._TOS_UNMANAGED_ROOT end;if not ae then local a=af.getBootAddress
if a then local b=a()if b and b~=""then local d,c=pcall(ak.proxy,b)if
d and c then ae=c end end end end;local function aU(a,b)
local c,d=pcall(a.exists,b)return c and d end
local function aB(a)
if type(a)~="table"or
type(a.isReadOnly)~="function"then return false end;local b,c=pcall(a.isReadOnly)return b and c==true end
local function aL(a)
for c,b in ipairs({true,false})do for d in ak.list(aR)do local f,e=pcall(ak.proxy,d)
if
f and e and e.exists and aU(e,a)then if not(b and aB(e))then return e end end end end end;if not ae then ae=aL(aJ)end;if not ae then ae=aL(aI)end;if not ae then
error("FATAL: Cannot find boot filesystem!")end;_G._TOS_ROOT_READONLY=aB(ae)
if _G._TOS_ROOT_READONLY then
local a=ak.list("gpu")()local b=ak.list(aK)()
if a and b then local d,c=pcall(ak.proxy,a)
if d and c then
pcall(c.bind,b)pcall(c.setBackground,0x000000)
pcall(c.setForeground,0xFF5555)local e,f=pcall(c.getResolution)
pcall(c.fill,1,1,(e and f)or 80,6," ")
pcall(c.set,2,2,"WARNING: the boot filesystem is READ-ONLY.")pcall(c.setForeground,0xAAAAAA)
pcall(c.set,2,3,"Disk "..

tostring(ae.address or"?"):sub(1,8).."...  Nothing TOS writes will survive, and First Boot Setup")
pcall(c.set,2,4,"cannot set a root password at all.")
pcall(c.set,2,5,"Install to a writable drive (run install.lua), or unprotect this one.")pcall(af.pullSignal,5)end end end
do local a=ae.spaceTotal()local c=524288;local b=_G._TOS_ROOT_READONLY;if _G._BIOS_ONETIME then
a=nil end
if a and(a<=c or b)then local d=nil;local e=0
for f in ak.list(aR)do
if f~=ae.address then
local h,g=pcall(ak.proxy,f)if h and g and not aB(g)then local i=g.spaceTotal()
if i and i>a and i>e then d=g;e=i end end end end
if d then local f;for h in ak.list("gpu")do f=ak.proxy(h)break end;local g;for h in
ak.list(aK)do g=h;break end
if f and g then pcall(f.bind,g)
f.setBackground(0x000000)f.setForeground(0xFFFFFF)local i,j=f.getResolution()
f.fill(1,1,i,j," ")local function h(m,n,o)f.setForeground(o or 0xFFFFFF)
f.set(2,m,tostring(n))end;local k=math.floor(a/1024)local l=math.floor(
e/1024)
h(2,
(b and"TOS is running from a read-only disk ("or
"TOS is running from a floppy disk (")..k.."KB)",0xFFFF00)
h(3,"A larger drive was detected ("..l.."KB)",0xFFFF00)
h(4,"  source:  "..
(ae.address or"?"):sub(1,12).."...",0xAAAAAA)
h(5,"  target:  ".. (d.address or"?"):sub(1,12).."...",0xAAAAAA)
h(7,"1. Install TOS to the hard drive (recommended)",0x00FF00)
h(8,b and"2. Continue read-only (nothing is saved)"or"2. Continue booting from floppy (limited space)",0xAAAAAA)h(10,"Press 1 or 2:",0xFFFFFF)
while true do
local m,o,n=af.pullSignal(60)
if m==ar then
if n==49 then
if ae.exists("/install.lua")then f.fill(1,1,i,j," ")
h(2,"Starting installer...",0x00AAFF)f.fill(1,1,i,j," ")
h(2,"Copying TOS to hard drive...",0x00AAFF)local p=4;local r=0;local q=nil
local function s(D,E)local F=0;local G=D.list(E)if not G then return F end;for o,H in ipairs(G)do
local I=E..H
if D.isDirectory(I)then F=F+s(D,I)else F=F+ (D.size(I)or 0)end end;return F end
local function t(D,E,F)if q then return end;local G=D.list(F)if not G then return end
for o,H in ipairs(G)do if q then return end
local I=F..H
if D.isDirectory(I)then E.makeDirectory(I)t(D,E,I)else local J=D.open(I,"r")if
not J then q="open-src "..I;return end;local K=E.open(I,"w")if not K then
D.close(J)q="open-dst "..I;return end
while true do
local L=D.read(J,4096)if not L then break end;local M,N=E.write(K,L)if not M then q="write "..
I..": "..tostring(N)break end end;D.close(J)E.close(K)if q then return end;r=r+1 end end end;local u=s(ae,"/")+8192;local v=(d.spaceTotal()or 0)-
(d.spaceUsed()or 0)
if v<u then
h(p,"Target too full: need "..

math.floor(u/1024).."KB, only "..math.floor(v/1024).."KB free",0xFF0000)p=p+1
h(p,"Nothing was written. Free up the disk and retry.",0xFFAA00)while true do local D=af.pullSignal(1e9)
if D==ar then af.shutdown(true)end end end
local B={"/tos/","/tos/kernel/","/tos/kernel/net/","/tos/shell/","/tos/compat/","/tos/peripheral/","/etc/","/etc/rc.d/","/home/","/root/","/public/","/usr/","/usr/bin/","/usr/lib/","/usr/modules/","/var/","/var/log/","/var/run/","/tmp/"}for o,D in ipairs(B)do d.makeDirectory(D)end;t(ae,d,"/")
if q then h(p,
"Copy FAILED: "..q,0xFF0000)p=p+1
h(p,"BIOS not updated. Remove disk to try again.",0xFFAA00)while true do local D=af.pullSignal(1e9)
if D==ar then af.shutdown(true)end end end;h(p,"Copied "..r.." files",0x00FF00)p=p+1
local w=d.exists(aI)local x=d.exists(aJ)local y=w and d.size(aI)or 0;local z=
x and d.size(aJ)or 0
if
not(w and x and y>0 and z>0)then
h(p,"Verification FAILED — BIOS not updated",0xFF0000)p=p+1
h(p,"  init.lua="..tostring(y).." kernel="..tostring(z),0xFF6600)while true do local D=af.pullSignal(1e9)
if D==ar then af.shutdown(true)end end end
h(p,"Files copied. Update EEPROM to boot from hard drive?",0xFFAA00)p=p+1
h(p,"  [Y] update EEPROM   [N] leave EEPROM alone",0xAAAAAA)p=p+1
h(p,"  Target: "..
(d.address or"?"):sub(1,12).."...",0xAAAAAA)p=p+1;local A=false;local C=af.uptime()
while af.uptime()-C<30 do
local E,o,D=af.pullSignal(30)if E==ar then if D==121 or D==89 then A=true end;break end end
if A then h(p,"Setting boot drive...",0x00AAFF)
af.setBootAddress(d.address)p=p+1 else
h(p,"EEPROM unchanged — remove floppy and reboot to use HD",0xFFAA00)p=p+1 end;h(p,"",0xFFFFFF)p=p+1
h(p,"TOS installed to hard drive!",0x00FF00)p=p+1;h(p,"Rebooting in 3 seconds...",0xAAAAAA)
af.pullSignal(3)af.shutdown(true)else
h(10,"install.lua not found on floppy!",0xFF0000)h(11,"Booting from floppy instead...",0xAAAAAA)
af.pullSignal(2)end;break elseif n==50 then break end elseif not m then break end end end end end end
_G._TOS={version="1.5.0",codename="Aletheia",build="b2ac70b",variant="minified",bootFS=ae,bootAddr=ae and ae.address or nil,bootTime=af.uptime(),startMem=af.freeMemory(),totalMem=af.totalMemory()}local ap={}local aC={}local aM={}
local aV={"/tos/?.lua","/tos/?/init.lua","/usr/lib/?.lua","/usr/modules/?.lua","/usr/modules/?/init.lua"}_G.package={loaded=nil}
local function aN(a)if not ae.exists(a)then return nil end
local b=ae.open(a,"r")if not b then return nil end;local c={}while true do local d=ae.read(b,4096)if not d then break end;c[#
c+1]=d end;ae.close(b)return
table.concat(c)end
local function aW(a)if not ae.exists(a)then return false end;local c=ae.open(a,"r")if
not c then return false end;local d,e={},0
local g,h=pcall(function()
while true do local k=ae.read(c,4096)
if k==nil then break end;if#k>0 then e=e+1;d[e]=k end end end)ae.close(c)if not g then return true,nil,h,"read"end;local b=0
local i,f,j=pcall(load,function()b=b+1
local k=d[b]d[b]=nil;return k end,"="..a,"t")if not i then return true,nil,f,"compile"end;return true,f,j,"compile"end
local function aX(a,b,c,d)local e=tostring(c)if d=="read"then return
"Read error in '"..a.."' ("..b.."): "..e end;if
e:find("not enough memory",1,true)then
return"Out of memory loading '"..a.."' ("..b.."): "..e end;return"Syntax error in '"..a.."' ("..
b.."): "..e end
local aY={sides=true,colors=true,keyboard=true,text=true,serialization=true,buffer=true,term=true,filesystem=true,event=true,shell=true,io=true,internet=true,robot=true,process=true,note=true}
local function aZ(a)
if aY[a]and not ap[a]then local d=_G._TOS
if
not(d and d.compatDisabled)then local f,e=pcall(_G.require,"compat")if f and e and e.init then
pcall(e.init,{procSleep=
d and d.proc and d.proc.sleep})end;if ap[a]then return ap[a]end end end;local c=a:gsub("%.","/")local b={}
for e,d in ipairs(aV)do local f=d:gsub("%?",c)
local h,g,i,j=aW(f)
if h then if not g then error(aX(a,f,i,j),2)end;local l,k=pcall(g,a)if not l then
error(
"Runtime error in '"..a.."': "..tostring(k),2)end;if k==nil then k=true end;ap[a]=k;aM[a]=f
return k end;b[#b+1]=f end
error("Module not found: "..
a.."\nSearched:\n  "..table.concat(b,"\n  "),2)end
local function a_(a)if ap[a]then return ap[a]end;if aC[a]then
error("Circular dependency: "..a,2)end;aC[a]=true;local c,b=pcall(aZ,a)aC[a]=nil;if not c then
error(b,0)end;return b end;_G.require=a_;ap["component"]=ak;ap["computer"]=af;if unicode then
ap["unicode"]=unicode end;_G.package.loaded=ap
_G.package.loadedFrom=aM;local au,an,aq
do local b,a=pcall(require,"kernel.bootcfg")
if b and a then au=a
local c,d=pcall(a.load,{exists=function(e)return
ae.exists(e)end,readFile=function(e)return aN(e)end})an=c and d or nil end
aq=(au and an)and au.verbosity(an)or"text"_G._TOS.bootcfg=an;_G._TOS.bootcfgMod=au end;local aD
if au and au.echoMinLevel then aD=au.echoMinLevel(aq)else aD=
({silent=4,splash=2,text=1,verbose=0})[aq]or 1 end;local aE;for a in ak.list("gpu")do aE=a;break end;local aF
for a in ak.list(aK)do aF=a;break end;local ag;if aE and aF then ag=ak.proxy(aE)
if not _G._BIOS_CY then ag.bind(aF)end;_G._TOS.gpu=ag end;local ai,al=50,16;if ag then
ai,al=ag.getResolution()end;local ax=_G._BIOS_DEPTH or 1;if ag then
local b,a=pcall(ag.getDepth)if b and a then ax=a end end;local ay=ax<=1;local function ah(a)if ay then
return 0xFFFFFF end;return a end;local ao=1;local ba=
(_G._TOS and _G._TOS.bootTime)or af.uptime()
local function aj(a,b)
if not ag then return end;a=tostring(a)
if aq=="verbose"then
local c=math.floor((af.uptime()-ba)*1000)a=string.format("[%6dms] %s",c,a)end;if b then ag.setForeground(ah(b))end;if ao>al then
ag.copy(1,2,ai,al-1,0,-1)ao=al end;ag.fill(1,ao,ai,1," ")
ag.set(1,ao,a)ao=ao+1 end
local function as()if not ag then return end;ag.setBackground(0x000000)
ag.setForeground(ah(0x00FF00))ag.fill(1,1,ai,al," ")ao=1 end
local function at(a)if aq~=aT then return"  "..a end;return
string.rep(" ",math.max(0,math.floor((ai-#a)/2)))..a end
if _G._BIOS_CY then ao=_G._BIOS_CY;if ag then ag.setBackground(0x000000)
ag.setForeground(ah(0x00FF00))end else as()end;local aG=math.floor(_G._TOS.totalMem/1024)local bb=math.floor(
af.freeMemory()/1024)
local function az()
if aq~="silent"then
local b,a=pcall(require,"kernel.logo")
if b and a and a.banner then local c={ascii=ay,compact=ai<34}if aq==aT then c.width=ai else
c.indent=2 end;for e,d in ipairs(a.banner(c))do
aj(d[1],ah(
(a.COLORS and a.COLORS[d[2]])or 0x00AAFF))end else
local c=string.rep(ay and"="or"═",math.min(38,ai))aj(c,ah(0x00AAFF))aj("  TOS",ah(0x00AAFF))
aj(c,ah(0x00AAFF))end
aj(at("TOS v"..
_G._TOS.version.." [".._G._TOS.codename.."]"),ah(0x00AAFF))
aj(at("Memory: "..bb.."K free / "..aG.."K total"),ah(0xAAAAAA))end;if _G._BIOS_ONETIME then
aj(at("ONE-TIME BOOT: EEPROM unchanged, boot config preserved"),ah(0xFFAA00))end
if
an and an.profile=="safe"then
aj(at("SAFE MODE: services, cron, packages, net, themes are OFF"),ah(0xFFAA00))
aj(at("(Boot Settings -> Profile to leave Safe Mode)"),ah(0xAAAAAA))end
if aG<128 then
aj(at("WARNING: Low memory - features limited!"),ah(0xFF0000))elseif aG<256 then
aj(at("NOTE: Limited memory - some features may be skipped"),ah(0xFFFF00))end end;az()
local function bc(b,c,a,e,d)local function g()
while true do local i,k,j=e()if i==ar then return tonumber(j)or 0 end end end;if type(d)~="function"then
a("Press any key to reboot...")g()return nil end
local function h()local i={}local function j(k,l)
local n,m=pcall(l.getLabel)
i[#i+1]={addr=k,label=(n and type(m)==aA)and m or""}end
for k in b.list(aR)do if not c[k]then
local m,l=pcall(b.proxy,k)
if m and l then local n,o=pcall(l.exists,aI)if n and o then j(k,l)end end end end
for k in b.list("drive",true)do
if not c[k]then local m,l=pcall(b.proxy,k)
if
m and l and l.readSector then local o,n=pcall(l.readSector,1)if o and type(n)==aA and
n:sub(1,4)=="TBFS"then j(k,l)end end end end;return i end
a("Any key reboots. B: boot another disk instead.")local f=g()
while f==66 or f==98 do local i=h()
if#i==0 then
a("No other bootable disk. Insert one (the TOS")a("installer floppy will do), then press B.")else for k=1,math.min(#i,9)
do
a(" "..k..") "..
i[k].addr:sub(1,8).." "..i[k].label:sub(1,30))end
a("Its number boots it from now on. B rescans.")end;a("Any other key reboots.")f=g()local j=f-48
if
j>=1 and j<=9 and i[j]then d(i[j].addr)
a("Boot disk set to "..
i[j].addr:sub(1,8)..". Rebooting.")return i[j].addr end end;return nil end
local function aO()local a={}if ae.address then a[ae.address]=true end;if _G._TBFS_BOOT_DRIVE then
a[_G._TBFS_BOOT_DRIVE]=true end
pcall(function()a[af.tmpAddress()]=true end)
pcall(bc,ak,a,function(b)aj(b,ah(0xAAAAAA))end,function()return
af.pullSignal(math.huge)end,af.setBootAddress)af.shutdown(true)end
local function aP(a,b)if not ag then return nil end
local e,d=pcall(require,"kernel.recovery")if not e or type(d)~="table"then return nil end
local f={title=0x00FFFF,value=0xFFFFFF,dim=0xAAAAAA,ok=0x00FF00,warn=0xFFAA00}
local g,c=pcall(d.run,{W=ai,H=al,px=ae,component=ak,failed=a,why=b,otherDisk=aO,clear=as,color=function(h)return ah(f[h]or 0xFFFFFF)end,set=function(h,i,j,k)ag.setForeground(
k or 0xFFFFFF)ag.set(h,i,j)end,tick=function()
af.pullSignal(0)end,readKey=function()while true do local h,k,i,j=af.pullSignal(math.huge)
if h==ar then return h,i,j end end end})if not g then as()
aj("Recovery stopped: "..tostring(c),ah(0xFF6600))return nil end;if c==aS then
af.shutdown(true)end;if c=="off"then af.shutdown(false)end;return c end
if
((an and an.showConfig)or aq=="verbose")and ag then
pcall(function()local b=require("kernel.sysinfo")
local function e(k)
local l={bg=0x000000,border=ah(0x00AAFF),title=ah(0x00FFFF),dim=ah(0xAAAAAA),value=ah(0xFFFFFF),ok=ah(0x00FF00),warn=ah(0xFFAA00),section=ah(0x00FFFF)}return l[k]or ah(0xFFFFFF)end;local function a(l,m,n,o,k)if k then ag.setBackground(k)end
ag.setForeground(o or 0xFFFFFF)ag.set(l,m,n)end
local i=b.gather(
nil,{cpuTier=an.cpuTier,dataTier=an.dataTier},function(k)
aj("  Standby - "..k.."...",ah(0xAAAAAA))end)as()local f="TOS System Configuration"
if ai>=60 then
local l,k=pcall(require,"kernel.logo")if l and k and k.VENDOR then
f=k.VENDOR.."  -  System Configuration"end end;local j=b.render(i,{W=ai,H=al,color=e,set=a,title=f})
a(2,math.min(al,(
j or al)+1),"DEL Boot Settings, S Safe Mode (once), R Recovery...",ah(0xFFAA00))local c=false;local d=false;local g=false;local h=af.uptime()+3
while af.uptime()<h do local l,n,k,m=af.pullSignal(
h-af.uptime())if l==ar then
if m==211 then c=true elseif k==115 or
k==83 then d=true elseif k==114 or k==82 then g=true end;break end end;if g then local k=aP(false)
if k=="safe"then d=true elseif k=="settings"then c=true end end;as()az()
if d and an then
an.profile="safe"
aj("  SAFE MODE (one-time): services, cron, packages, net, themes OFF",ah(0xFFAA00))
aj("  Boot config untouched - the next boot is normal.",ah(0xAAAAAA))end
if c then local l,k=pcall(require,"kernel.bootsettings")
if l and k then
local n={W=ai,H=al,color=e,set=a,sysinfo=b,clear=as,readKey=function()while true do
local p,s,q,r=af.pullSignal()if p==ar then return p,q,r end end end}local m,o=k.run(an,n)
if m=="save"or m==aS then
local p={exists=function(q)return ae.exists(q)end,readFile=aN,writeFile=function(q,r)
if
not ae.exists("/etc")then pcall(ae.makeDirectory,"/etc")end;local s=ae.open(q,"w")if not s then return false end;ae.write(s,r)
ae.close(s)return true end}
pcall(function()
require("kernel.bootcfg").save(p,o)end)as()
if m==aS then
a(2,2,"Saved. Rebooting to apply...",ah(0x00FF00))af.pullSignal(1)af.shutdown(true)else
a(2,2,"Saved. Changes apply on next boot. Continuing...",ah(0x00FF00))af.pullSignal(1)as()az()end end end end end)end
local function bd(a)if not ae.exists(a)then return nil end;local b=ae.open(a,"r")if not b then
return nil end;local c={}
repeat local d=ae.read(b,4096)if d then c[#c+1]=d end until not d;ae.close(b)return table.concat(c)end
local function aH(a,b)local c=bd(a)if not c then return nil end;local d=load(c,"="..b,"t")
if not d then return nil end;local f,e=pcall(d)
if not f or type(e)~="table"then return nil end;return e end;local am={}local aw="(none)"
do
local a=aH("/var/pkg/installed/tos-core/package.lua","tos-core/package")
if a and type(a.critical)=="table"then for c,b in ipairs(a.critical)do if
type(b)==aA then am[#am+1]=b end end;if
#am>0 then aw="tos-core/package.lua"end end end
if#am==0 then local a=aH("/etc/critical.bak","critical.bak")
if a then for c,b in ipairs(a)do if
type(b)==aA then am[#am+1]=b end end;if#am>
0 then aw="critical.bak"end end end
if#am==0 then
local a=aH("/tos/system_manifest.lua","system_manifest")if a then for c,b in ipairs(a)do
if b.critical and type(b.path)==aA then am[#am+1]=b.path end end
if#am>0 then aw="system_manifest.lua"end end end
if#am==0 then
am={aJ,"/tos/kernel/log.lua","/tos/kernel/hal.lua","/tos/kernel/event.lua","/tos/kernel/process.lua","/tos/kernel/fs.lua","/tos/kernel/serialize.lua","/tos/kernel/display.lua","/tos/shell/init.lua"}aw="hardcoded fallback"end;local av={}
for b,a in ipairs(am)do if not ae.exists(a)then av[#av+1]=a end end
if#av>0 then
aj("MISSING "..#av.." FILES:",ah(0xFF0000))
for b,a in ipairs(av)do aj("  "..a,ah(0xFF6600))end;af.beep(400,0.5)
aP(true,#av.." system file(s) are missing.")aO()end
if aq~="silent"then
aj(at("Verifying: ".. (#am-#av).."/"..
#am.." system files OK ["..aw.."]"),ah(0x00FF00))aj(at("Loading kernel..."),ah(0x00FF00))end;local aQ=nil
if aq==aT and ag then local h,a=pcall(require,"kernel.bootsteps")
local i=ao;local b,e,f,c,j;local l=3
local function m()
if h and a and a.splashGeometry then
b,e,f,c=a.splashGeometry(ai,al,i)else e=math.max(10,math.min(40,ai-6))
f=math.max(1,math.floor((ai-
(e+2))/2)+1)b=math.max(1,math.min(al-1,i+1))end;c=c or math.max(0,math.min(l,al-b))j=ai-
f+1;ag.setBackground(0x000000)
pcall(ag.fill,1,b,ai,c+1," ")end;local g=0;local k=16;local q=ay and"#"or"█"local d={}local n=nil;if
h and a and a.STAGE_COUNT then k=a.STAGE_COUNT end;local function r(t)
if h and a then return a.stageFor(t)end;return nil end
local function s()
local v,t,u=pcall(ag.getResolution)if not v or not t or not u then return false end;if
t==ai and u==al then return false end;ai,al=t,u;as()ao=1;az()i=ao;m()
ao=math.min(al,b+c+1)return true end
local function o()s()ag.setBackground(0x000000)local t=math.floor(e*math.min(1,g/k)+
0.5)
ag.setForeground(ah(0x00AAFF))
ag.set(f,b,"["..
string.rep(q,t)..string.rep(" ",e-t).."]")local u=math.max(0,#d-c)for v=1,c do local w=d[u+v]ag.setForeground((w and w[2])or
ah(0xAAAAAA))
ag.set(f,b+v,((
(w and w[1])or"")..string.rep(" ",j)):sub(1,j))end end
local function p(t,u)d[#d+1]={t,u}while#d>l do table.remove(d,1)end end;m()o()ao=math.min(al,b+c+1)
aQ=function(t,u)t=tostring(t or"")
if
u and u>=2 then local v=(u==2)and"! "or"!! "p(v..t,(u==2)and ah(0xFFAA00)or
ah(0xFF4040))else local v=r(t)if v and
v~=n then n=v;g=g+1;p(v,ah(0xAAAAAA))end end;if t:find("Boot complete",1,true)then g=k end;o()end end
local function be(a,b,c)local e={}
local function d(g,h,i,j)local k=string.rep(" ",j or 2)
local l=math.max(8,b-#k-1)g=tostring(g or"")if g==""then e[#e+1]={"",h,i}return end
for m in(g..
"\n"):gmatch("([^\n]*)\n")do repeat
e[#e+1]={k..m:sub(1,l),h,i}m=m:sub(l+1)until m==""end end;d("","body",1)
d("TOS has stopped to protect your data.","title",6)d("","body",1)
d("*** STOP: "..a.code.."  "..a.sym,"code",9)d(a.hex,"dim",2,6)d("","body",1)local f=true
for g in
(
tostring(a.detail or"").."\n"):gmatch("([^\n]*)\n")do g=g:gsub("\t","  ")if g:find("%S")then
d(g,"body",f and 8 or 4)f=false end end;d("","body",1)
d("1. Reboot."..
(a.report and
(" The crash report is "..a.report)or""),"body",5)
d("2. After boot: crash reads it, why "..a.code.." explains the code,","body",5)
d("   srm repairs. If it repeats, boot another disk and run srm scan.","body",5)d("","body",1)d(a.status,"dim",3)d("","body",1)
d("Press any key to reboot.","title",7)
while#e>c do local g,h=math.huge,nil
for j=#e,1,-1 do if e[j][3]<g then g,h=e[j][3],j end end;table.remove(e,h)end;return e end
local function bf(a,b,e,c,d)local g,f,h=0x0000AA,0xFFFFFF,0xAAAAAA;if d<=1 then g,f,h=0xFFFFFF,0x000000,0x000000 elseif d<=4 then
g,f,h=0x333399,0xFFFFFF,0xCCCCCC end
pcall(a.setBackground,g)pcall(a.setForeground,f)pcall(a.fill,1,1,e,c," ")
for j=1,math.min(
#b,c)do
pcall(a.setForeground,(b[j][2]=="dim")and h or f)pcall(a.set,1,j,b[j][1])end end
local bg,bh=xpcall(function()local a=require("kernel")
a.boot({gpu=ag,gpuDepth=ax,screenW=ai,screenH=al,earlyPrint=aj,bootFS=ae,bootcfg=an,bootcfgMod=au,earlyMinLevel=aD,bootProgress=aQ})end,function(a)
return
tostring(a).."\n"..debug.traceback("",2)end)
if not bg then local b=tostring(bh)or"Unknown error"
local j={ERR_KERNEL_PANIC={"E-201","0x00020001"},ERR_OUT_OF_MEMORY={"E-202","0x00020002"}}
local a=b:find("not enough memory",1,true)and"ERR_OUT_OF_MEMORY"or
"ERR_KERNEL_PANIC"local d,k=j[a][1],j[a][2]local l,c=pcall(require,"kernel.errors")
local e=
l and type(c)=="table"and c.find(a)if e then d,k=c.code(e),c.hex(e)end
local f="KERNEL PANIC ["..d.." "..a.."]"local g
pcall(function()local m=_G._TOS and _G._TOS.kernel;if m and m.crashDump then
local o,n=pcall(m.crashDump,f,b)if o and n then g=n;return end end
if ae and
ae.open then pcall(ae.makeDirectory,"/var/crash")
local n=ae.open("/var/crash/crash-panic.txt","w")
if n then
ae.write(n,"=== TOS "..f.." ===\n"..
b.."\nFree RAM: "..math.floor(af.freeMemory()/1024)..
"KB\n")ae.close(n)g="/var/crash/crash-panic.txt"end;local o=ae.open("/var/crash/NEW","w")if o then ae.write(o,f)
ae.close(o)end end end)local h,i=ai,al
if ag then pcall(ag.setActiveBuffer,0)
local o,m,n=pcall(ag.getResolution)if o and m and n then h,i=m,n end;local p=_G._TOS or{}
bf(ag,be({code=d,sym=a,hex=k,detail=b,report=g,status=string.format("uptime %ds | %d KB free | TOS %s",math.floor(af.uptime()),math.floor(
af.freeMemory()/1024),tostring(p.version or"?"))},h,i),h,i,ax)end;af.beep(400,0.15)af.pullSignal(0.05)
af.beep(400,0.15)af.pullSignal(0.05)af.beep(400,0.15)while true do
local m=af.pullSignal(math.huge)if m==ar then break end end
af.shutdown(true)end