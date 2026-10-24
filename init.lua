
local aF,ap,aM,aG,aH,aN,ax="screen","key_down","filesystem","/tos/kernel/init.lua","/init.lua","splash","string"local ab=...local ah=component;local ac=computer
if not load("return 1<<1")then local a
for c in
ah.list("gpu")do local e,d=pcall(ah.proxy,c)if e and d then a=d;break end end;local b;for c in ah.list(aF)do b=c;break end
if a and b then pcall(a.bind,b)
pcall(a.setBackground,0x000000)pcall(a.setForeground,0xFFFFFF)
pcall(a.fill,1,1,80,25," ")
pcall(a.set,2,2,"TOS requires the Lua 5.3 or 5.4 CPU architecture.")
pcall(a.set,2,3,"This CPU is running an older one (Lua 5.2).")
pcall(a.set,2,5,"Fix: sneak-click (crouch + right-click) the CPU in its")
pcall(a.set,2,6,"computer-case slot to cycle architectures, then reboot.")pcall(a.set,2,8,"Press any key to power off.")end;pcall(ac.beep,800,0.3)
while true do
local c=ac.pullSignal(math.huge)if c==ap then ac.shutdown()end end end
if not ab and _G._TOS_UNMANAGED_ROOT then ab=_G._TOS_UNMANAGED_ROOT end;if not ab then local a=ac.getBootAddress
if a then local b=a()if b and b~=""then local d,c=pcall(ah.proxy,b)if
d and c then ab=c end end end end;local function aO(a,b)
local c,d=pcall(a.exists,b)return c and d end
local function ay(a)
if type(a)~="table"or
type(a.isReadOnly)~="function"then return false end;local b,c=pcall(a.isReadOnly)return b and c==true end
local function aI(a)
for c,b in ipairs({true,false})do for d in ah.list(aM)do local f,e=pcall(ah.proxy,d)
if
f and e and e.exists and aO(e,a)then if not(b and ay(e))then return e end end end end end;if not ab then ab=aI(aG)end;if not ab then ab=aI(aH)end;if not ab then
error("FATAL: Cannot find boot filesystem!")end;_G._TOS_ROOT_READONLY=ay(ab)
if _G._TOS_ROOT_READONLY then
local a=ah.list("gpu")()local b=ah.list(aF)()
if a and b then local d,c=pcall(ah.proxy,a)
if d and c then
pcall(c.bind,b)pcall(c.setBackground,0x000000)
pcall(c.setForeground,0xFF5555)local e,f=pcall(c.getResolution)
pcall(c.fill,1,1,(e and f)or 80,6," ")
pcall(c.set,2,2,"WARNING: the boot filesystem is READ-ONLY.")pcall(c.setForeground,0xAAAAAA)
pcall(c.set,2,3,"Disk "..

tostring(ab.address or"?"):sub(1,8).."...  Nothing TOS writes will survive, and First Boot Setup")
pcall(c.set,2,4,"cannot set a root password at all.")
pcall(c.set,2,5,"Install to a writable drive (run install.lua), or unprotect this one.")pcall(ac.pullSignal,5)end end end
do local a=ab.spaceTotal()local c=524288;local b=_G._TOS_ROOT_READONLY;if _G._BIOS_ONETIME then
a=nil end
if a and(a<=c or b)then local d=nil;local e=0
for f in ah.list(aM)do
if f~=ab.address then
local h,g=pcall(ah.proxy,f)if h and g and not ay(g)then local i=g.spaceTotal()
if i and i>a and i>e then d=g;e=i end end end end
if d then local f;for h in ah.list("gpu")do f=ah.proxy(h)break end;local g;for h in
ah.list(aF)do g=h;break end
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
(ab.address or"?"):sub(1,12).."...",0xAAAAAA)
h(5,"  target:  ".. (d.address or"?"):sub(1,12).."...",0xAAAAAA)
h(7,"1. Install TOS to the hard drive (recommended)",0x00FF00)
h(8,b and"2. Continue read-only (nothing is saved)"or"2. Continue booting from floppy (limited space)",0xAAAAAA)h(10,"Press 1 or 2:",0xFFFFFF)
while true do
local m,o,n=ac.pullSignal(60)
if m==ap then
if n==49 then
if ab.exists("/install.lua")then f.fill(1,1,i,j," ")
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
I..": "..tostring(N)break end end;D.close(J)E.close(K)if q then return end;r=r+1 end end end;local u=s(ab,"/")+8192;local v=(d.spaceTotal()or 0)-
(d.spaceUsed()or 0)
if v<u then
h(p,"Target too full: need "..

math.floor(u/1024).."KB, only "..math.floor(v/1024).."KB free",0xFF0000)p=p+1
h(p,"Nothing was written. Free up the disk and retry.",0xFFAA00)while true do local D=ac.pullSignal(1e9)
if D==ap then ac.shutdown(true)end end end
local B={"/tos/","/tos/kernel/","/tos/kernel/net/","/tos/shell/","/tos/compat/","/tos/peripheral/","/etc/","/etc/rc.d/","/home/","/root/","/public/","/usr/","/usr/bin/","/usr/lib/","/usr/modules/","/var/","/var/log/","/var/run/","/tmp/"}for o,D in ipairs(B)do d.makeDirectory(D)end;t(ab,d,"/")
if q then h(p,
"Copy FAILED: "..q,0xFF0000)p=p+1
h(p,"BIOS not updated. Remove disk to try again.",0xFFAA00)while true do local D=ac.pullSignal(1e9)
if D==ap then ac.shutdown(true)end end end;h(p,"Copied "..r.." files",0x00FF00)p=p+1
local w=d.exists(aH)local x=d.exists(aG)local y=w and d.size(aH)or 0;local z=
x and d.size(aG)or 0
if
not(w and x and y>0 and z>0)then
h(p,"Verification FAILED — BIOS not updated",0xFF0000)p=p+1
h(p,"  init.lua="..tostring(y).." kernel="..tostring(z),0xFF6600)while true do local D=ac.pullSignal(1e9)
if D==ap then ac.shutdown(true)end end end
h(p,"Files copied. Update EEPROM to boot from hard drive?",0xFFAA00)p=p+1
h(p,"  [Y] update EEPROM   [N] leave EEPROM alone",0xAAAAAA)p=p+1
h(p,"  Target: "..
(d.address or"?"):sub(1,12).."...",0xAAAAAA)p=p+1;local A=false;local C=ac.uptime()
while ac.uptime()-C<30 do
local E,o,D=ac.pullSignal(30)if E==ap then if D==121 or D==89 then A=true end;break end end
if A then h(p,"Setting boot drive...",0x00AAFF)
ac.setBootAddress(d.address)p=p+1 else
h(p,"EEPROM unchanged — remove floppy and reboot to use HD",0xFFAA00)p=p+1 end;h(p,"",0xFFFFFF)p=p+1
h(p,"TOS installed to hard drive!",0x00FF00)p=p+1;h(p,"Rebooting in 3 seconds...",0xAAAAAA)
ac.pullSignal(3)ac.shutdown(true)else
h(10,"install.lua not found on floppy!",0xFF0000)h(11,"Booting from floppy instead...",0xAAAAAA)
ac.pullSignal(2)end;break elseif n==50 then break end elseif not m then break end end end end end end
_G._TOS={version="1.5.0",codename="Aletheia",build="d6963fb",variant="minified",bootFS=ab,bootAddr=ab and ab.address or nil,bootTime=ac.uptime(),startMem=ac.freeMemory(),totalMem=ac.totalMemory()}local am={}local az={}local aJ={}
local aP={"/tos/?.lua","/tos/?/init.lua","/usr/lib/?.lua","/usr/modules/?.lua","/usr/modules/?/init.lua"}_G.package={loaded=nil}
local function aK(a)if not ab.exists(a)then return nil end
local b=ab.open(a,"r")if not b then return nil end;local c={}while true do local d=ab.read(b,4096)if not d then break end;c[#
c+1]=d end;ab.close(b)return
table.concat(c)end
local function aQ(a)if not ab.exists(a)then return false end;local c=ab.open(a,"r")if
not c then return false end;local d,e={},0
local g,h=pcall(function()
while true do local k=ab.read(c,4096)
if k==nil then break end;if#k>0 then e=e+1;d[e]=k end end end)ab.close(c)if not g then return true,nil,h,"read"end;local b=0
local i,f,j=pcall(load,function()b=b+1
local k=d[b]d[b]=nil;return k end,"="..a,"t")if not i then return true,nil,f,"compile"end;return true,f,j,"compile"end
local function aR(a,b,c,d)local e=tostring(c)if d=="read"then return
"Read error in '"..a.."' ("..b.."): "..e end;if
e:find("not enough memory",1,true)then
return"Out of memory loading '"..a.."' ("..b.."): "..e end;return"Syntax error in '"..a.."' ("..
b.."): "..e end
local aS={sides=true,colors=true,keyboard=true,text=true,serialization=true,buffer=true,term=true,filesystem=true,event=true,shell=true,io=true,internet=true,robot=true,process=true,note=true}
local function aT(a)
if aS[a]and not am[a]then local d=_G._TOS
if
not(d and d.compatDisabled)then local f,e=pcall(_G.require,"compat")if f and e and e.init then
pcall(e.init,{procSleep=
d and d.proc and d.proc.sleep})end;if am[a]then return am[a]end end end;local c=a:gsub("%.","/")local b={}
for e,d in ipairs(aP)do local f=d:gsub("%?",c)
local h,g,i,j=aQ(f)
if h then if not g then error(aR(a,f,i,j),2)end;local l,k=pcall(g,a)if not l then
error(
"Runtime error in '"..a.."': "..tostring(k),2)end;if k==nil then k=true end;am[a]=k;aJ[a]=f
return k end;b[#b+1]=f end
error("Module not found: "..
a.."\nSearched:\n  "..table.concat(b,"\n  "),2)end
local function aU(a)if am[a]then return am[a]end;if az[a]then
error("Circular dependency: "..a,2)end;az[a]=true;local c,b=pcall(aT,a)az[a]=nil;if not c then
error(b,0)end;return b end;_G.require=aU;am["component"]=ah;am["computer"]=ac;if unicode then
am["unicode"]=unicode end;_G.package.loaded=am
_G.package.loadedFrom=aJ;local aq,ak,an
do local b,a=pcall(require,"kernel.bootcfg")
if b and a then aq=a
local c,d=pcall(a.load,{exists=function(e)return
ab.exists(e)end,readFile=function(e)return aK(e)end})ak=c and d or nil end
an=(aq and ak)and aq.verbosity(ak)or"text"_G._TOS.bootcfg=ak;_G._TOS.bootcfgMod=aq end;local aA
if aq and aq.echoMinLevel then aA=aq.echoMinLevel(an)else aA=
({silent=4,splash=2,text=1,verbose=0})[an]or 1 end;local aB;for a in ah.list("gpu")do aB=a;break end;local aC
for a in ah.list(aF)do aC=a;break end;local ae;if aB and aC then ae=ah.proxy(aB)
if not _G._BIOS_CY then ae.bind(aC)end;_G._TOS.gpu=ae end;local af,ai=50,16;if ae then
af,ai=ae.getResolution()end;local au=_G._BIOS_DEPTH or 1;if ae then
local b,a=pcall(ae.getDepth)if b and a then au=a end end;local av=au<=1;local function ad(a)if av then
return 0xFFFFFF end;return a end;local al=1;local aV=
(_G._TOS and _G._TOS.bootTime)or ac.uptime()
local function ag(a,b)
if not ae then return end;a=tostring(a)
if an=="verbose"then
local c=math.floor((ac.uptime()-aV)*1000)a=string.format("[%6dms] %s",c,a)end;if b then ae.setForeground(ad(b))end;if al>ai then
ae.copy(1,2,af,ai-1,0,-1)al=ai end;ae.fill(1,al,af,1," ")
ae.set(1,al,a)al=al+1 end
local function ar()if not ae then return end;ae.setBackground(0x000000)
ae.setForeground(ad(0x00FF00))ae.fill(1,1,af,ai," ")al=1 end
local function ao(a)if an~=aN then return"  "..a end;return
string.rep(" ",math.max(0,math.floor((af-#a)/2)))..a end
if _G._BIOS_CY then al=_G._BIOS_CY;if ae then ae.setBackground(0x000000)
ae.setForeground(ad(0x00FF00))end else ar()end;local aD=math.floor(_G._TOS.totalMem/1024)local aW=math.floor(
ac.freeMemory()/1024)
local function aw()
if an~="silent"then
local b,a=pcall(require,"kernel.logo")
if b and a and a.banner then local c={ascii=av,compact=af<34}if an==aN then c.width=af else
c.indent=2 end;for e,d in ipairs(a.banner(c))do
ag(d[1],ad(
(a.COLORS and a.COLORS[d[2]])or 0x00AAFF))end else
local c=string.rep(av and"="or"═",math.min(38,af))ag(c,ad(0x00AAFF))ag("  TOS",ad(0x00AAFF))
ag(c,ad(0x00AAFF))end
ag(ao("TOS v"..
_G._TOS.version.." [".._G._TOS.codename.."]"),ad(0x00AAFF))
ag(ao("Memory: "..aW.."K free / "..aD.."K total"),ad(0xAAAAAA))end;if _G._BIOS_ONETIME then
ag(ao("ONE-TIME BOOT: EEPROM unchanged, boot config preserved"),ad(0xFFAA00))end
if
ak and ak.profile=="safe"then
ag(ao("SAFE MODE: services, cron, packages, net, themes are OFF"),ad(0xFFAA00))
ag(ao("(Boot Settings -> Profile to leave Safe Mode)"),ad(0xAAAAAA))end
if aD<128 then
ag(ao("WARNING: Low memory - features limited!"),ad(0xFF0000))elseif aD<256 then
ag(ao("NOTE: Limited memory - some features may be skipped"),ad(0xFFFF00))end end;aw()
if
((ak and ak.showConfig)or an=="verbose")and ae then
pcall(function()local b=require("kernel.sysinfo")
local function c(j)
local k={bg=0x000000,border=ad(0x00AAFF),title=ad(0x00FFFF),dim=ad(0xAAAAAA),value=ad(0xFFFFFF),ok=ad(0x00FF00),warn=ad(0xFFAA00),section=ad(0x00FFFF)}return k[j]or ad(0xFFFFFF)end;local function a(k,l,m,n,j)if j then ae.setBackground(j)end
ae.setForeground(n or 0xFFFFFF)ae.set(k,l,m)end
local h=b.gather(
nil,{cpuTier=ak.cpuTier,dataTier=ak.dataTier},function(j)
ag("  Standby - "..j.."...",ad(0xAAAAAA))end)ar()local d="TOS System Configuration"
if af>=60 then
local k,j=pcall(require,"kernel.logo")if k and j and j.VENDOR then
d=j.VENDOR.."  -  System Configuration"end end;local i=b.render(h,{W=af,H=ai,color=c,set=a,title=d})
a(2,math.min(ai,(
i or ai)+1),"Press DEL for Boot Settings, S for Safe Mode (once)...",ad(0xFFAA00))local e=false;local f=false;local g=ac.uptime()+3
while ac.uptime()<g do local k,m,j,l=ac.pullSignal(g-
ac.uptime())if k==ap then if l==211 then e=true elseif j==115 or j==83 then
f=true end;break end end;ar()aw()
if f and ak then ak.profile="safe"
ag("  SAFE MODE (one-time): services, cron, packages, net, themes OFF",ad(0xFFAA00))
ag("  Boot config untouched - the next boot is normal.",ad(0xAAAAAA))end
if e then local k,j=pcall(require,"kernel.bootsettings")
if k and j then
local m={W=af,H=ai,color=c,set=a,sysinfo=b,clear=ar,readKey=function()while true do
local o,r,p,q=ac.pullSignal()if o==ap then return o,p,q end end end}local l,n=j.run(ak,m)
if l=="save"or l=="reboot"then
local o={exists=function(q)return ab.exists(q)end,readFile=aK,writeFile=function(q,r)
if
not ab.exists("/etc")then pcall(ab.makeDirectory,"/etc")end;local p=ab.open(q,"w")if not p then return false end;ab.write(p,r)
ab.close(p)return true end}
pcall(function()
require("kernel.bootcfg").save(o,n)end)ar()
if l=="reboot"then
a(2,2,"Saved. Rebooting to apply...",ad(0x00FF00))ac.pullSignal(1)ac.shutdown(true)else
a(2,2,"Saved. Changes apply on next boot. Continuing...",ad(0x00FF00))ac.pullSignal(1)ar()aw()end end end end end)end
local function aX(a)if not ab.exists(a)then return nil end;local b=ab.open(a,"r")if not b then
return nil end;local c={}
repeat local d=ab.read(b,4096)if d then c[#c+1]=d end until not d;ab.close(b)return table.concat(c)end
local function aE(a,b)local c=aX(a)if not c then return nil end;local d=load(c,"="..b,"t")
if not d then return nil end;local f,e=pcall(d)
if not f or type(e)~="table"then return nil end;return e end;local aj={}local at="(none)"
do
local a=aE("/var/pkg/installed/tos-core/package.lua","tos-core/package")
if a and type(a.critical)=="table"then for c,b in ipairs(a.critical)do if
type(b)==ax then aj[#aj+1]=b end end;if
#aj>0 then at="tos-core/package.lua"end end end
if#aj==0 then local a=aE("/etc/critical.bak","critical.bak")
if a then for c,b in ipairs(a)do if
type(b)==ax then aj[#aj+1]=b end end;if#aj>
0 then at="critical.bak"end end end
if#aj==0 then
local a=aE("/tos/system_manifest.lua","system_manifest")if a then for c,b in ipairs(a)do
if b.critical and type(b.path)==ax then aj[#aj+1]=b.path end end
if#aj>0 then at="system_manifest.lua"end end end
if#aj==0 then
aj={aG,"/tos/kernel/log.lua","/tos/kernel/hal.lua","/tos/kernel/event.lua","/tos/kernel/process.lua","/tos/kernel/fs.lua","/tos/kernel/serialize.lua","/tos/kernel/display.lua","/tos/shell/init.lua"}at="hardcoded fallback"end;local as={}
for b,a in ipairs(aj)do if not ab.exists(a)then as[#as+1]=a end end
local function aY(b,c,a,e,d)local function g()
while true do local i,k,j=e()if i==ap then return tonumber(j)or 0 end end end;if type(d)~="function"then
a("Press any key to reboot...")g()return nil end
local function h()local i={}local function j(k,l)
local n,m=pcall(l.getLabel)
i[#i+1]={addr=k,label=(n and type(m)==ax)and m or""}end
for k in b.list(aM)do if not c[k]then
local m,l=pcall(b.proxy,k)
if m and l then local n,o=pcall(l.exists,aH)if n and o then j(k,l)end end end end
for k in b.list("drive",true)do
if not c[k]then local m,l=pcall(b.proxy,k)
if
m and l and l.readSector then local o,n=pcall(l.readSector,1)if o and type(n)==ax and
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
if#as>0 then
ag("MISSING "..#as.." FILES:",ad(0xFF0000))
for c,b in ipairs(as)do ag("  "..b,ad(0xFF6600))end;ac.beep(400,0.5)local a={}
if ab.address then a[ab.address]=true end
if _G._TBFS_BOOT_DRIVE then a[_G._TBFS_BOOT_DRIVE]=true end
pcall(function()a[ac.tmpAddress()]=true end)
pcall(aY,ah,a,function(b)ag(b,ad(0xAAAAAA))end,function()return
ac.pullSignal(math.huge)end,ac.setBootAddress)ac.shutdown(true)end
if an~="silent"then
ag(ao("Verifying: ".. (#aj-#as).."/"..
#aj.." system files OK ["..at.."]"),ad(0x00FF00))ag(ao("Loading kernel..."),ad(0x00FF00))end;local aL=nil
if an==aN and ae then local h,a=pcall(require,"kernel.bootsteps")
local i=al;local b,e,f,c,j;local l=3
local function m()
if h and a and a.splashGeometry then
b,e,f,c=a.splashGeometry(af,ai,i)else e=math.max(10,math.min(40,af-6))
f=math.max(1,math.floor((af-
(e+2))/2)+1)b=math.max(1,math.min(ai-1,i+1))end;c=c or math.max(0,math.min(l,ai-b))j=af-
f+1;ae.setBackground(0x000000)
pcall(ae.fill,1,b,af,c+1," ")end;local g=0;local k=16;local q=av and"#"or"█"local d={}local n=nil;if
h and a and a.STAGE_COUNT then k=a.STAGE_COUNT end;local function r(t)
if h and a then return a.stageFor(t)end;return nil end
local function s()
local v,t,u=pcall(ae.getResolution)if not v or not t or not u then return false end;if
t==af and u==ai then return false end;af,ai=t,u;ar()al=1;aw()i=al;m()
al=math.min(ai,b+c+1)return true end
local function o()s()ae.setBackground(0x000000)local t=math.floor(e*math.min(1,g/k)+
0.5)
ae.setForeground(ad(0x00AAFF))
ae.set(f,b,"["..
string.rep(q,t)..string.rep(" ",e-t).."]")local u=math.max(0,#d-c)for v=1,c do local w=d[u+v]ae.setForeground((w and w[2])or
ad(0xAAAAAA))
ae.set(f,b+v,((
(w and w[1])or"")..string.rep(" ",j)):sub(1,j))end end
local function p(t,u)d[#d+1]={t,u}while#d>l do table.remove(d,1)end end;m()o()al=math.min(ai,b+c+1)
aL=function(t,u)t=tostring(t or"")
if
u and u>=2 then local v=(u==2)and"! "or"!! "p(v..t,(u==2)and ad(0xFFAA00)or
ad(0xFF4040))else local v=r(t)if v and
v~=n then n=v;g=g+1;p(v,ad(0xAAAAAA))end end;if t:find("Boot complete",1,true)then g=k end;o()end end
local function aZ(a,b,c)local e={}
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
local function a_(a,b,e,c,d)local g,f,h=0x0000AA,0xFFFFFF,0xAAAAAA;if d<=1 then g,f,h=0xFFFFFF,0x000000,0x000000 elseif d<=4 then
g,f,h=0x333399,0xFFFFFF,0xCCCCCC end
pcall(a.setBackground,g)pcall(a.setForeground,f)pcall(a.fill,1,1,e,c," ")
for j=1,math.min(
#b,c)do
pcall(a.setForeground,(b[j][2]=="dim")and h or f)pcall(a.set,1,j,b[j][1])end end
local ba,bb=xpcall(function()local a=require("kernel")
a.boot({gpu=ae,gpuDepth=au,screenW=af,screenH=ai,earlyPrint=ag,bootFS=ab,bootcfg=ak,bootcfgMod=aq,earlyMinLevel=aA,bootProgress=aL})end,function(a)
return
tostring(a).."\n"..debug.traceback("",2)end)
if not ba then local b=tostring(bb)or"Unknown error"
local j={ERR_KERNEL_PANIC={"E-201","0x00020001"},ERR_OUT_OF_MEMORY={"E-202","0x00020002"}}
local a=b:find("not enough memory",1,true)and"ERR_OUT_OF_MEMORY"or
"ERR_KERNEL_PANIC"local d,k=j[a][1],j[a][2]local l,c=pcall(require,"kernel.errors")
local e=
l and type(c)=="table"and c.find(a)if e then d,k=c.code(e),c.hex(e)end
local f="KERNEL PANIC ["..d.." "..a.."]"local g
pcall(function()local m=_G._TOS and _G._TOS.kernel;if m and m.crashDump then
local o,n=pcall(m.crashDump,f,b)if o and n then g=n;return end end
if ab and
ab.open then pcall(ab.makeDirectory,"/var/crash")
local n=ab.open("/var/crash/crash-panic.txt","w")
if n then
ab.write(n,"=== TOS "..f.." ===\n"..
b.."\nFree RAM: "..math.floor(ac.freeMemory()/1024)..
"KB\n")ab.close(n)g="/var/crash/crash-panic.txt"end;local o=ab.open("/var/crash/NEW","w")if o then ab.write(o,f)
ab.close(o)end end end)local h,i=af,ai
if ae then pcall(ae.setActiveBuffer,0)
local o,m,n=pcall(ae.getResolution)if o and m and n then h,i=m,n end;local p=_G._TOS or{}
a_(ae,aZ({code=d,sym=a,hex=k,detail=b,report=g,status=string.format("uptime %ds | %d KB free | TOS %s",math.floor(ac.uptime()),math.floor(
ac.freeMemory()/1024),tostring(p.version or"?"))},h,i),h,i,au)end;ac.beep(400,0.15)ac.pullSignal(0.05)
ac.beep(400,0.15)ac.pullSignal(0.05)ac.beep(400,0.15)while true do
local m=ac.pullSignal(math.huge)if m==ap then break end end
ac.shutdown(true)end