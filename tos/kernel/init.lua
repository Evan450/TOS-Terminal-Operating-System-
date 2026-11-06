
local av,aH,aI,aJ,aK,aL,aM,aN,aA,ap,ar,aB,as,al,aO,aC,ab,aP,aw,aQ,aR,aD,ax,ay,at,aS,am,aT,aU,aE,aq,aF,an,az,aV="  BAD ","  OK  "," (unreadable)","/var/crash","KB free)","Killed PID ","Result: %d OK, %s, %d damaged","^[^\n]*","_kernel_","collect","component","eeprom","filesystem","function","header","hotplug","kernel","kernel.cron","kernel.crypto","kernel.fs","kernel.log","kernel.monitor","kernel.rc","kernel.screen","kernel.serialize","kernel.srm","key_down","no EEPROM","not permitted","raised","repair","screen","string","tos_focus","tos_seat_changed"local ad=require("computer")local aj=require(ar)local ag={}local ak=false
local aW=false;local aa,ai,ah,ac,ae,af;local ao;local au={}
function ag.boot(a)a=a or{}
local q=a.earlyPrint or function()end;local v=a.earlyMinLevel or 1
local function d(z,A)if v<=1 then q(z,A)end end;local e=a.bootcfg;local g=a.bootcfgMod;local function f(A,z)
if g and e and g.wants then return g.wants(e,A,z)end;return z end;local m=40960
local function i()
local A=(
ai and ai.freeMemory and ai.freeMemory(m))or ad.freeMemory()local z=A>m;if g and e and g.ramOK then return g.ramOK(e,z)end
return z end
local j=(e and e.memprofile==true)and{}or nil
local function c(z)if not j then return end
if type(collectgarbage)==al then
pcall(collectgarbage,ap)else local A={}
for B=1,10 do local C=table.pack(ad.pullSignal(0))if C.n>0 and
C[1]~=nil then A[#A+1]=C end end;for C,B in ipairs(A)do
pcall(ad.pushSignal,table.unpack(B,1,B.n))end end
j[#j+1]={stage=z,free=ad.freeMemory(),t=ad.uptime()}end;c("1 core modules")
d("  Loading kernel modules...",0xAAAAAA)aa=require(aR)
aa.init({earlyPrint=q,earlyMinLevel=a.earlyMinLevel,bootProgress=a.bootProgress})
aa.info(ab,"TOS Kernel v".._G._TOS.version..
" (build "..tostring(_G._TOS.build or"?")..
", "..tostring(
_G._TOS.variant or"?")..") starting")_G._TOS.log=function(z,A)aa.info(z,A)end
_G._TOS.logObj=aa;c("2 hardware detection")
aa.info(ab,"Scanning hardware...")ai=require("kernel.hal")ai.scan()local h=ai.systemInfo()
aa.info(ab,string.format("CPU T%d | GPU T%d | RAM %s | %d components",h.cpuTier,h.gpuTier,
h.memTierName or("T"..h.memTier),h.components))if h.canNetwork then local z=ai.checkWireless()h.hasWireless=z
aa.info(ab,"Network: ".. (
z and"Wireless"or"Wired").." modem detected")end;if h.hasTunnel then
aa.info(ab,"Linked card (tunnel) detected")end;c("3 filesystem")
aa.info(ab,"Initializing filesystem...")ae=require(aQ)ae.init(a.bootFS)
local r=a.bootFS and a.bootFS.address;local w,n=pcall(require,"kernel.diskmount")
if
w and type(n)=="table"then ao=n;local z=_G._TOS.overlay
ao.init({fs=ae,log=aa,bootAddr=r,layerAddr=z and z.disk})
if z and z.missing then
aa.error(ab,"Overlay disk "..tostring(z.missing):sub(1,8)..
" is not here: running on the real root, and every write is permanent")end;for B,A in ipairs(ai.list(as))do
if A.address~=r then if not A.proxy then
A.proxy=aj.proxy(A.address)end;ao.mount(A.address,A.proxy)end end else
aa.warn(ab,
"Disk mounting unavailable ("..tostring(n).."): only the boot disk is mounted")end
local x={"/tmp","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/var/swap","/etc","/usr","/usr/bin","/usr/modules"}for A,z in ipairs(x)do
if not ae.exists(z)then ae.makeDirectory(z)end end
pcall(aa.attachFile,ae,"/var/log/kernel.log",{rotateBytes=16384})local o="/var/run/pwrstate"
do
local z=ae.exists(o)and ae.readFile(o)or nil;local A=0;if type(z)==an and#z>0 then
A=tonumber(z:match("\n(%d+)"))or 0;_G._TOS.unsafeShutdown=z:sub(1,1)~="C"else
_G._TOS.unsafeShutdown=false end;_G._TOS.bootCount=
A+1
if ae.recoverAtomic then
local B=ae.recoverAtomic({"/etc/users.dat","/etc/trust.dat","/etc/tos.cfg","/etc/cron.db","/etc/critical.bak"})if B>0 then
aa.warn(ab,"Recovered "..B.." interrupted critical write(s) from a prior crash")end end
pcall(ae.writeFile,o,"R\n".._G._TOS.bootCount.."\n"..
tostring((os.time and os.time())or 0))
if _G._TOS.unsafeShutdown then
aa.warn(ab,"PREVIOUS SHUTDOWN WAS UNSAFE (power loss / forced off) — state verified on boot")pcall(ad.beep,880,0.1)pcall(ad.beep,660,0.1)end end
pcall(function()local C=aj.list(aB)()if not C then return end;local A=aj.proxy(C)if not
(A and A.getData)then return end;local D=A.getData()if type(D)~=an or not
D:find("SRM:",1,true)then return end
local F,B=pcall(require,aS)if not(F and B)then
aa.warn("srm","A POST fault is parked in the EEPROM but kernel.srm "..
"would not load: "..tostring(B))return end
local z=B.readFault({eeprom=A})if not z then return end;local E=z.code..
(z.err and(" / "..z.err)or"")
aa.error("srm","LAST BOOT FAILED POST — SRM "..E..
": "..z.why)
d("  SRM "..E..": last boot failed POST",0xFF6600)d("    "..z.why,0xFFAA00)
d("    (run 'srm' for the full report)",0xAAAAAA)local G,H=B.clearFault({eeprom=A})if not G then
aa.warn("srm","could not clear the parked code: "..
tostring(H))end
if _G._TOS then _G._TOS.postFault=z end end)local s=math.floor(ae.spaceFree("/")/1024)local y=math.floor(
ae.spaceTotal("/")/1024)
aa.info(ab,string.format("Boot disk: %dKB free / %dKB total",s,y))
if s<32 then aa.warn(ab,"WARNING: Very low disk space!")end
if e and e.repair then
aa.warn(ab,"SELF-REPAIR requested — checking system state...")e.repair=false
pcall(function()if g and g.save then g.save(ae,e)end end)
local D={fs=ae,log=aa,serialize=(function()local F,G=pcall(require,at)return F and G or nil end)()}local z,B,A=nil,0,0;local E,C=pcall(require,aS)
if E and type(C)=="table"then
local G,F=pcall(C.repair,D)
if G and type(F)=="table"then z=F.findings;B=F.fixed or 0;A=
(F.counts.warn or 0)+ (F.counts.err or 0)else
aa.warn(aq,
"self-repair failed: "..tostring(F))end else
aa.warn(aq,"kernel.srm unavailable ("..tostring(C)..") — falling back to kernel.repair")local G,F=pcall(require,"kernel.repair")
if G and F then
local I,H=pcall(F.run,D)
if I and type(H)=="table"then z={}for K,J in ipairs(H.lines or{})do
z[#z+1]={text=J,sev=J:sub(1,5)==
"WARN:"and"warn"or"info"}end
B,A=H.fixed or 0,H.warned or 0 else
aa.warn(aq,"self-repair failed: "..tostring(H))end else
aa.warn(aq,"kernel.repair unavailable: "..tostring(F))end end
if z then local G={ok=0x00FF00,info=0xAAAAAA,warn=0xFFAA00,err=0xFF6600}for I,H in
ipairs(z)do aa.info(aq,H.text)
d("  "..H.text,G[H.sev]or 0xAAAAAA)end
local F=string.format("Self-repair: %d fixed, %d warning(s)",B,A)aa.warn(aq,F)
d("  "..F,A>0 and 0xFFAA00 or 0x00FF00)end end
if ae.exists("/var/pkg/archive")then
local A,z=pcall(require,"kernel.pkgfs")
if A and type(z)=="table"then
local B,C=pcall(z.boot,{fs=ae,log=aa})if not B then
aa.error(ab,"Package archives: "..tostring(C))end else
aa.error(ab,"Package archives did not load: "..tostring(z))end end;c("4 system configuration")local b=nil
do
aa.info(ab,"Loading configuration...")local A,z=pcall(require,"kernel.config")
if A then b=z;b.init(ae)
_G._TOS.config=b
aa.info(ab,"Device profile: "..b.deviceType())if b.get("verbose")then aa.setLevel("DEBUG")end else
aa.warn(ab,
"Config module not available: "..tostring(z))end end;c("4b disk swap")
if f("swap",true)then local A;do
local D,C=pcall(require,"kernel.compress")
if D and C then pcall(C.init,{log=aa})_G._TOS.compress=C;A=C end end
local B,z=pcall(require,"kernel.swap")
if B and z then
local C,D=pcall(z.init,{fs=ae,serialize=require(at),log=aa,config=b,compress=A})if C then _G._TOS.swap=z else
aa.warn(ab,"Swap init failed: "..tostring(D))end else
aa.warn(ab,"Swap module not available: "..tostring(z))end end;c("4b2 internet card transport")do
local A,z=pcall(require,"kernel.internet")
if A and z then pcall(z.init,{log=aa,config=b})_G._TOS.internet=z end end
c("4c jbod disk pooling")
if f("jbod",false)then local A,z=pcall(require,"kernel.jbod")
if A and z then
_G._TOS.jbod=z;aa.info(ab,"JBOD disk pooling enabled")
local B=z.loadConfig(ae)
if B and type(B.pools)=="table"then
for D,C in ipairs(B.pools)do
if
type(C)=="table"and
type(C.mount)==an and type(C.members)=="table"then local E={}for D,F in ipairs(C.members)do local H,G=pcall(aj.proxy,F)
if H and G then E[#E+1]=G end end
if#E==0 then
aa.warn(ab,"JBOD pool "..C.mount..
": no members present, not mounted")else local F=z.makePool(E)local G,H=ae.mount(C.mount,F)
if G then
aa.info(ab,string.format("JBOD mounted %s (%d/%d members)",C.mount,
#E,#C.members))else
aa.warn(ab,"JBOD mount "..C.mount.." failed: "..tostring(H))end end end end end else
aa.warn(ab,"JBOD enabled but module unavailable: "..tostring(z))end end;c("5 event system")
aa.info(ab,"Starting event system...")ah=require("kernel.event")
local t={screen=true,gpu=true,keyboard=true}
ah.on("component_added",function(B,z,A)ai.handleComponentAdded(z,A)
aa.info(aC,"Added: "..A.." ["..z:sub(1,8)..
"]")if t[A]then ah.push(aV,"added",A,z)end
if A==as and ao then
local D,C=pcall(aj.proxy,z)if D and C then local E,F=ao.mount(z,C)
if E then ah.push("tos_disk_added",z,E,F)end end end end,ab)
ah.on("component_removed",function(B,z,A)ai.handleComponentRemoved(z,A)
aa.info(aC,"Removed: "..A.." ["..
z:sub(1,8).."]")if t[A]then ah.push(aV,"removed",A,z)end
if A==as and ao then
local C,D=ao.unmount(z)if C then ah.push("tos_disk_removed",z,C,D)end end end,ab)
ah.on("screen_resized",function(C,z,A,B)local E,D=pcall(require,ay)if
not(E and D and D.onResized)then return end;if D.onResized(z,A,B)then local F,G=D.getResolution()
aa.info(aF,string.format("Screen resized externally -> %dx%d",
F or 0,G or 0))end end,ab)c("6 process manager")
aa.info(ab,"Starting process manager...")ac=require("kernel.process")c("7 display system")local p=b and
b.isHeadless()
if p then
aa.info(ab,"Headless mode — skipping display init")
af={init=function()end,clear=function()end,fill=function()end,set=function()end,getSize=function()return 0,0 end,getGpuTier=function()return 0 end,getGpuDepth=function()return 1 end,getTheme=function()
return setmetatable({},{__index=function()return
0xFFFFFF end})end,getGpu=function()return nil end,fit=function(z)return z or""end,c=function()return
0xFFFFFF end}else aa.info(ab,"Initializing display...")
af=require("kernel.display")local A,B,z=a.screenW,a.screenH
do local F,E=pcall(require,ay)
if
F and E and E.specFromConfig then local G=E.specFromConfig(b)E.setPolicy(G)
local H,I,J=E.gpuTarget(a.gpu,nil,G)if H and I then A,B=H,I end;z=J end end;af.init(a.gpu,A,B)local C,D=af.getSize()
aa.info(ab,string.format("Display: %dx%d, GPU Tier %d (%d-bit color)",
C or 0,D or 0,af.getGpuTier(),af.getGpuDepth()))if z then aa.warn(aF,z)end end;c("8 power monitor")
do
if f("power",i())then
local A,z=pcall(require,"kernel.power")
if A then z.init({log=aa,config=b})_G._TOS.power=z
pcall(z.applyProfile,(b and
b.get("powerProfile"))or"balanced")
if b and b.isTablet()then
ah.interval(10,function()z.check()end,"kernel:power")
z.onLow(function(B)if _G._TOS.audio then _G._TOS.audio.warning()else
ad.beep(800,0.3)end end)
z.onCritical(function(B)if _G._TOS.audio then _G._TOS.audio.critical()else
ad.beep(400,0.5)end
aa.fatal("power","Battery critical!")
if not b or b.get("critBatShutdown")~=false then
aa.warn("power","Critical battery — clean shutdown to protect data")pcall(aa.flush)ag.shutdown(false)end end)
aa.info(ab,"Tablet mode: battery monitoring active")end else
aa.warn(ab,"Power module not available: "..tostring(z))end else
aa.warn(ab,i()and"Skipping power module (boot profile)"or
("Skipping power module (low memory: "..math.floor(
ad.freeMemory()/1024)..aK))end end
local function k(z,B,A)local C,D=nil,false
_G._TOS[z]=setmetatable({},{__index=function(F,E)if C then return C[E]end
local H,G=pcall(require,B)if not H or type(G)~="table"then
if not D then D=true;aa.warn(ab,z..
": lazy load failed: "..tostring(G))end;return nil end;if
G.init and A then pcall(G.init,A())end;C=G;_G._TOS[z]=G;aa.info(ab,z..
" module ready (on demand)")return G[E]end})end;c("9 security subsystem")
do
if ad.freeMemory()>m then
local A,z=pcall(require,aw)
if A then z.init()
aa.info(ab,"Crypto: "..
(z.hasHardware()and"Hardware"or"Software"))
pcall(function()if
not(z.addEntropy and z.exportEntropy and ae)then return end;local D="/etc/entropy"
if ae.makeDirectory and not
ae.exists("/etc")then ae.makeDirectory("/etc")end;if ae.exists(D)then local E=ae.readFile(D)if type(E)==an and#E>0 then
z.addEntropy(E)end end
z.addEntropy(
tostring(ad.uptime()).."|"..
tostring(ad.freeMemory()).."|"..tostring({}))ae.writeFile(D,z.exportEntropy(64))end)local C,B=pcall(require,"kernel.users")
if C then
B.init({fs=ae,crypto=z,log=aa,config=b})_G._TOS.users=B;local E,D=pcall(require,"kernel.securefs")
if E then
D.init({fs=ae,users=B,log=aa,process=ac})_G._TOS.securefs=D;_G._TOS.bootSession=B.kernelSession()
aa.info(ab,"Security: users + securefs ready")k("trash","kernel.trash")
local H,G=pcall(require,"kernel.profile")
if H and G and G.init then
G.init({securefs=D,users=B,log=aa,serialize=require(at)})_G._TOS.profile=G;aa.info(ab,"Profile module ready")end;local I,F=pcall(require,"kernel.i18n")
if I and F and F.init then
F.init({fs=ae,log=aa,serialize=require(at),config=_G._TOS.config})_G._TOS.i18n=F;if F.language()~="en"then
aa.info(ab,"Language: "..F.language())end end
k("backup","kernel.backup",function()return{securefs=D,fs=ae,crypto=z,log=aa}end)
k("keychain","kernel.keychain",function()
return{securefs=D,users=B,log=aa,serialize=require(at)}end)if ah then
ah.interval(300,function()B.sweepSessions()end,"kernel:session_sweep")end else
aa.warn(ab,"SecureFS not available: "..tostring(D))end else
aa.warn(ab,"User system not available: "..tostring(B))_G._TOS.usersFailure=tostring(B)end else
aa.warn(ab,"Crypto not available: "..tostring(z))end else
aa.warn(ab,"Skipping security (low memory: "..
math.floor(ad.freeMemory()/1024)..aK)end end;c("9b theme manager")
if af and af.isMonochrome and
not af.isMonochrome()and f("theme",i())then
local A,z=pcall(require,"kernel.theme")
if A then
z.init({display=af,securefs=_G._TOS.securefs,log=aa})_G._TOS.theme=z
aa.info(ab,"Theme manager ready ("..#z.list().." presets)")else
aa.warn(ab,"Theme module not available: "..tostring(z))end end;c("10 network")
if
(ai.has("modem")or ai.has("tunnel"))and f("net",i())then
local A,z=pcall(require,"kernel.net")
if A then
local B=pcall(z.init,{log=aa,config=b,event=ah,fs=ae})
if B then _G._TOS.net=z
aa.info(ab,"Network ready (".. (z.getHostname())..")")local D,C=pcall(require,"kernel.net.aliases")
if D and C and C.init then
C.init({fs=ae,securefs=_G._TOS.securefs,users=_G._TOS.users,log=aa,serialize=require(at)})_G._TOS.net.aliases=C
aa.info(ab,"Peer aliases ready")end else aa.warn(ab,"Network init failed")end else
aa.warn(ab,"Network module not available: "..tostring(z))end else
if
not(ai.has("modem")or ai.has("tunnel"))then aa.info(ab,"No network hardware - skipping")elseif i()then
aa.warn(ab,"Skipping network (boot profile)")else
aa.warn(ab,"Skipping network (low memory: "..
math.floor(ad.freeMemory()/1024)..aK)end end;c("11 startup services and compatibility")
if
f("services",i())then local A,z=pcall(require,ax)
if A then
z.init({fs=ae,log=aa,proc=ac})z.runAll()_G._TOS.rc=z
aa.info(ab,"Startup services loaded")if ah then
ah.interval(30,function()z.supervise()end,"kernel:rc_supervise")end end else
aa.warn(ab,"Startup services skipped (boot profile)")end
if f("cron",i())then
if ae.exists("/etc/cron.dat")then local A,z=pcall(require,aP)if A then
z.init({fs=ae,log=aa,event=ah})_G._TOS.cron=z
aa.info(ab,"Cron scheduler initialized")end else k("cron",aP)end else _G._TOS.cronDisabled=true
aa.warn(ab,"Cron scheduler skipped (boot profile)")end
do if not f("packages",true)then _G._TOS.pkgDispatchDisabled=true
aa.warn(ab,"Package command dispatch disabled (boot profile)")end
k("pkg","kernel.pkg")end;if ah then
ah.interval(30,function()pcall(aa.flush)end,"kernel:log_flush")end
if not f("compat",true)then
_G._TOS.compatDisabled=true
aa.warn(ab,"OpenOS compat disabled (boot profile)")else
aa.info(ab,"OpenOS compat: lazy (loads on first use)")end;c("12 audio feedback system")
if f("audio",true)then
local A,z=pcall(require,"kernel.audio")
if A then z.init(b)_G._TOS.audio=z
aa.info(ab,"Audio feedback: ".. (
z.isEnabled()and"enabled"or"disabled"))else aa.info(ab,"Audio module not available")end end;function ag.gc()
if type(collectgarbage)==al then return pcall(collectgarbage,ap)end;return false end
_G._TOS.fs=ae;_G._TOS.kernel=ag;_G._TOS.proc=ac;_G._TOS.event=ah
c("13 boot complete")if type(collectgarbage)==al then
pcall(collectgarbage,"setpause",120)end
local l=
(ai and ai.freeMemory and ai.freeMemory())or ad.freeMemory()local u=ad.uptime()-_G._TOS.bootTime
if j then
_G._TOS.bootMem=j
for A,z in ipairs(j)do local B=j[A+1]
aa.info("memprofile",B and
string.format("%-36s used %4dK, %5dK free after",z.stage,math.floor((z.free-
B.free)/1024),math.floor(B.free/1024))or string.format("%-36s %5dK free",z.stage,math.floor(
z.free/1024)))end end
aa.info(ab,"Boot complete! Free memory: "..math.floor(l/1024).."KB")
aa.info(ab,string.format("Boot time: %.1fs",u))pcall(ag.checkLastCrash)if l<20480 then
aa.warn(ab,"LOW MEMORY: "..
math.floor(l/1024).."KB free!")end
do
local z=ag.manifestAnchorWarning()if z then
aa.warn(ab,"Manifest does not match its EEPROM anchor: "..z)end end
d(string.format("  Boot complete: %.1fs, %dK free",u,math.floor(l/1024)),0x00FF00)
if _G._TOS.audio then _G._TOS.audio.bootComplete()end
do
local A,z,B=pcall(function()local C=_G._TOS and _G._TOS.fs;if not(C and C.exists)then
return nil end;if C.exists("/etc/selftest.on")then
return require("kernel.selftest")end
if C.mounts then local E,D=pcall(C.mounts)
if E and type(D)==
"table"then
for G,F in ipairs(D)do local H=F.mountPoint
if H and H~="/"and
(
C.exists(H.."/selftest.on")or C.exists(H.."/selftest/selftest.on"))then return false,H end end end end;return nil end)
if A and z==false and B then
aa.warn(ab,"self-test disk at "..tostring(B)..
" ignored: this machine is not armed (create /etc/selftest.on)")
d("  Self-test disk ignored: create /etc/selftest.on to allow it",0xFFFF00)end
if A and z then
aa.info(ab,"selftest marker present - running boot battery")d("  Running self-test battery...",0xFFFF00)
pcall(z.init,{fs=_G._TOS.fs,computer=ad,log=aa})local D,C=pcall(z.run,{fs=_G._TOS.fs,computer=ad})
if D and
C then
d(string.format("  Self-test: %d passed, %d failed, %d skipped",C.pass,C.fail,C.skip),
C.fail>0 and 0xFF0000 or 0x00FF00)else
aa.error(ab,"selftest battery errored: "..tostring(C))
d("  Self-test ERRORED (see /var/selftest.log)",0xFF0000)end end end
if not p then local z=0
if b then z=tonumber(b.get("bootPause"))or
(b.get("verbose")and 1.5 or 0)end;if z>0 then ad.pullSignal(z)end end;aa.detachEarlyPrint()
c("14 login -> shell / headless loop")ag.boot=nil
if p then ag.headlessMain()else ag.loginAndStartShell()end end
local function aX(a,d,b,c)local e=a.getTheme()a.clear(e.bg)
if type(c)==an and
c:find("Module not found",1,true)then
a.set(2,2,"TOS is damaged and cannot start.",e.error,e.bg)
a.set(2,4,"The user system is missing from this",e.fg,e.bg)
a.set(2,5,"disk, so nobody can log in. More",e.fg,e.bg)a.set(2,6,"memory will not help.",e.fg,e.bg)
a.set(2,8,"Reinstall TOS from a disk or network.",e.dim,e.bg)else
a.set(2,2,"Not enough memory for TOS to start.",e.error,e.bg)
a.set(2,4,"The user system did not fit, so nobody",e.fg,e.bg)
a.set(2,5,"can log in. TOS needs at least 1 MB",e.fg,e.bg)a.set(2,6,"(one Tier 3.5 memory stick).",e.fg,e.bg)
a.set(2,8,"Add memory, then power on again.",e.dim,e.bg)end
a.set(2,10,"Press any key to power off.",e.dim,e.bg)if b then pcall(b)end;repeat until d(math.huge)==am end
local function aY(b,c,d,e,a)local f=c.getUser and c.getUser("root")if not
(f and f.firstBoot)then return nil end
local function g(h,i)
b.fill(2,h,e-3,1," ",a.fg,a.bg)b.set(2,h,i,a.dim,a.bg)local k,j=2+#i,""
while true do
b.set(k,h,string.rep("*",#j).."_ ",a.fg,a.bg)local n,o,l,m=d(0.5)
if n==am then
if m==28 then return j elseif m==14 then if#j>0 then j=j:sub(1,-2)end elseif
l and l>=32 and l<127 and#j<30 then j=j..string.char(l)end end end end
b.set(2,3,"First boot: set a password for root.",a.dim,a.bg)
while true do local h=g(5,"New password: ")local i=g(6,"Confirm:      ")b.fill(2,8,e-
3,1," ",a.fg,a.bg)
if#h<6 then
b.set(2,8,"Password must be 6+ characters.",a.error,a.bg)elseif h~=i then
b.set(2,8,"Passwords don't match. Try again.",a.error,a.bg)else local k=c.login("root","root",{setCurrent=true})
local j,l=false,"the default password was not accepted"
if k then j,l=c.changePassword("root","root","root",h)end
if j and c.promoteAfterFirstBoot then j,l=c.promoteAfterFirstBoot(k)end;if j then
b.set(2,8,"Password set. Starting TOS...",a.success,a.bg)d(1)return k end
b.set(2,8,"Could not set it: "..tostring(l),a.error,a.bg)end;d(1.5)end end
local function aZ(c,d,e,a,b,f)local g={}
for i,h in ipairs(c)do if a(d[h])then b[h]=nil elseif not a(e[h])and(b[h]or 0)<f then g[
#g+1]=h end end;return g end
function ag.loginAndStartShell()ak=true;local a=_G._TOS.users;local o=_G._TOS.securefs
local m=ad.freeMemory()local function i()
if type(collectgarbage)==al then pcall(collectgarbage,ap)end end
local function k()local q,y=af.getSize()
local p=af.getTheme()af.clear(p.bg)
af.set(2,2,"TOS - Authentication Required",p.title,p.bg)
if not a then
aX(af,ad.pullSignal,function()if _G._TOS.audio then _G._TOS.audio.critical()else
ad.beep(400,0.5)end end,_G._TOS.usersFailure)ag.shutdown()return nil end;local v=aY(af,a,ad.pullSignal,q,p)if v then return v end
af.set(2,3,"Low memory mode. Enter root password.",p.dim,p.bg)af.set(2,5,"Password: ",p.dim,p.bg)local t="/var/lockout.dat"
local function x()
local z,A=pcall(require,aQ)local ae=(z and A)or nil;if not ae or not ae.exists or
not ae.exists(t)then return 0 end
local B=ae.readFile(t)local C=tonumber(B or"")or 0;return C end
local function w(z)local A,B=pcall(require,aQ)local ae=(A and B)or nil;if not ae or
not ae.writeFile then return end
if
ae.exists and not ae.exists("/var")and ae.makeDirectory then ae.makeDirectory("/var")end;pcall(ae.writeFile,t,tostring(z))end;local r=ad.uptime()local s=x()
if s>0 and s>r and(s-r)<3600 then local z=s-r
af.set(2,4,string.format("Locked: wait %ds before retrying.",math.ceil(z)),p.error,p.bg)local A=r+z;while ad.uptime()<A do
ad.pullSignal(math.min(1,A-ad.uptime()))end
af.fill(2,4,q-3,1," ",p.fg,p.bg)end;local u=5
for z=1,u do af.fill(12,5,q-13,1," ",p.fg,p.bg)local A=""
while true do
af.set(12,5,string.rep("*",
#A).."_ ",p.fg,p.bg)local G,H,E,F=ad.pullSignal(0.5)if G==am then
if F==28 then break elseif F==14 then
if#A>0 then A=A:sub(1,-2)end elseif E and E>=32 and E<127 then A=A..string.char(E)end end end;local C=a.login("root",A,{setCurrent=true})
if C then w(0)
af.set(2,7,"Access granted.",p.success,p.bg)ad.pullSignal(0.5)return C end;local B=2^z;if aa then
aa.warn("auth",string.format("minimalAuth: bad root password (attempt %d/%d), backoff %ds",z,u,B))end;local D=u-z
if D>0 then
af.set(2,7,string.format("Wrong password. Wait %ds. (%d attempts left)",B,D),p.error,p.bg)af.fill(12,5,q-13,1," ",p.fg,p.bg)
local E=ad.uptime()+B;while ad.uptime()<E do
ad.pullSignal(math.min(1,E-ad.uptime()))end
af.fill(2,7,q-3,1," ",p.fg,p.bg)end end;w(ad.uptime()+60)
af.set(2,7,"Too many attempts. Rebooting (locked 60s)...",p.error,p.bg)if _G._TOS.audio then _G._TOS.audio.critical()else
ad.beep(400,0.5)end;ad.pullSignal(3)
ag.reboot()return nil end;local f=nil;local j=false
if m<32768 then
aa.warn(ab,"Low memory - using minimal auth")j=true else local q,p=pcall(require,"shell.login")if q then f=p else
aa.warn(ab,"Login module not available: "..
tostring(p))j=true end end;local h=nil;do local q,p=pcall(require,"shell.init")
if q then h=p else aa.error(ab,"Shell module failed: "..
tostring(p))end end
local d=require(ay)
local n={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,[ar]=true,["load"]=true,["net"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true,["peripheral.printer"]=true,["peripheral.modem"]=true,["peripheral.tractor"]=true,["peripheral.piston"]=true,["peripheral.hologram"]=true}local b={}local c={}local g={}local l
local function e(p)local r=d.displayProxy(p)if not r then return nil end
local s=a and
a.loginSession and a.loginSession(p)or nil
local q=ac.spawn("login@"..p,function()local t=nil
if j then t=k()elseif f then local v=f.new and f.new()or f
local w,u,x=pcall(v.run,{display=r,event=ah,users=a,proc=ac,log=aa})
if w then
if x=="shutdown"then
aa.info(ab,"Operator chose shutdown at the login screen (display "..p..")")
if ag and ag.shutdown then ag.shutdown()else ad.shutdown(false)end;return end;t=u else
aa.error(ab,"Login error on display "..p..": "..tostring(u))t=k()end end;if t then b[p]=t;c[p]=l(p,t)_G._TOS.shellPIDs=c end end,{display=p,priority=2,source=ab,principal=s})if q then pcall(ac.setForeground,q,p)end;g[p]=q;return q end
l=function(p,q)local r=d.displayProxy(p)if not r or not h then return nil end;local s=nil;if q and
a then s=a.getSession(q)end
if not s then if aa then
aa.error(ab,"Refusing to spawn shell on display "..
tostring(p)..": no valid session token")end;return nil end;local t=s.user or"?"
if
_G._TOS.theme and _G._TOS.theme.applyForUser then pcall(_G._TOS.theme.applyForUser,s)end
if _G._TOS.profile and _G._TOS.profile.load and
_G._TOS.profile.apply then
pcall(function()
local z=_G._TOS.profile.load(s)local A=_G._TOS.profile.apply(z,{session=s})
s.startupCommands=A end)end
local w=setmetatable({display=r,displayIdx=p,getDisplay=function()return r end,getDisplayIdx=function()return p end},{__index=ag})
aa.info(ab,"Seat "..p..": shell for "..t)local u=h.run
if t=="kiosk"then local A,z=pcall(require,"shell.kiosk")
if
A and z and z.run then u=z.run
aa.info(ab,"Seat "..p..": KIOSK mode")else local B=tostring(z)u=function()
error("kiosk shell would not load: "..B,0)end end end;i()
aa.info(ab,string.format("Seat %d: loading shell (%dKB free)",p,math.floor(ad.freeMemory()/1024)))
local v=ac.spawn("shell:"..t.."@"..p,function()local z,A=pcall(u,w,q)
if not z then local B=tostring(A)
i()
aa.error(ab,"Shell crashed on display "..p..": "..B)
pcall(function()
if r then local D,E=r.getSize()local C=r.getTheme()
r.fill(1,2,D,3," ",C.fg,C.bg)r.set(2,2,"Shell crashed:",C.error,C.bg)
r.set(2,3,r.fit(B,D-2),C.dim,C.bg)ad.pullSignal(2)end end)end;ah.push("tos_shell_exited",p)end,{priority=1,source=ab,tsr=false,principal=s,token=q,cwd=
s and s.home or"/",caps=n,display=p})local x,y=ac.setForeground(v,p)if not x then
aa.error(ab,"Seat "..
p..": foreground handoff FAILED ("..tostring(y)..
") — input will not reach the shell")end;return v end
if h then _G._TOS.bootSession=nil;_G._TOS.bootCompleted=true;local t=d.count()
for z,y in
ipairs(d.indices())do local B=e(y)local A=d.get(y)
aa.info(ab,string.format("Seat %d: gpu=%s screen=%s keyboards=%d login pid=%s",y,tostring(
A and A.gpu and A.gpu.address or"?"):sub(1,8),tostring(
A and A.screen or"?"):sub(1,8),(
A and A.keyboards and#A.keyboards)or 0,tostring(
B or"FAILED")))end;_G._TOS.shellPIDs=c;if t>1 then
aa.info(ab,"Multi-seat: "..t.." displays active")end;local s={}local u=0;local p={}local q=0;local v,r=0,{}local w=ac.STATE and
ac.STATE.DEAD or"dead"
local function x(y)
local z=y and ac.get(y)return z~=nil and z.state~=w end
while ak do local y=table.pack(ah.pull(0.1))if y[1]=="tos_shutdown"then
ak=false;break end
if y[1]=="tos_logout"then local A=y[2]
if not A then local C,B=nil,0;for D in pairs(c)do
B=B+1;C=D end
if B==1 then A=C
aa.warn(ab,"tos_logout without a seat index — assuming seat "..C)else
aa.warn(ab,"tos_logout without a seat index ignored ("..B.." seats live)")end end
if A then
if c[A]then ac.kill(c[A],{kernel=true})c[A]=nil end;if a and b[A]then a.logout(b[A])b[A]=nil end;aa.info(ab,"Seat "..A..
": logged out")e(A)q=0 end;y=table.pack(nil)end
if y[1]=="tos_shell_exited"then local A=y[2]
if A and not c[A]then elseif A then c[A]=nil;if a and b[A]then
a.logout(b[A])b[A]=nil end
aa.info(ab,"Seat "..
A..": shell exited, respawning login")e(A)end;q=0;y=table.pack(nil)end
if y[1]==am then local A=ad.uptime()
if A-u>1 then u=A
local B=package.loaded and package.loaded[aw]if B and B.addEntropy then
pcall(B.addEntropy,tostring(A)..
"|"..tostring(ad.freeMemory()))end end end
if y[1]==am and y[3]==3 then local A=1;if d.displayForKeyboard then
A=d.displayForKeyboard(y[2])or 1 end;local B=ac.getForeground(A)
local C=ad.uptime()
if B then
if s[A]and(C-s[A])<1.5 then ac.kill(B,{kernel=true})
s[A]=nil
aa.warn(ab,aL..B.." via double Ctrl+C on display "..A)else ac.signal(B,"tos_interrupt")s[A]=C end end;y=table.pack(nil)end
if y[1]==am and y[3]==20 then local A=1;if d.displayForKeyboard then
A=d.displayForKeyboard(y[2])or 1 end;local B=au[A]
local C=B and ac.get and ac.get(B)
if C and C.state~=ac.STATE.DEAD and c[A]==B then
ac.setForeground(B,A,{kernel=true});(ac.signalKernel or ac.signal)(B,"tos_monitor")y=table.pack(
nil)else local D=p[A]
local E=D and ac.get and ac.get(D)
if E and E.state~=ac.STATE.DEAD then y=table.pack(nil)else local H=nil;if a and
b[A]then H=a.getSession(b[A])end;local I=b[A]local F=c[A]
local G
G=ac.spawn("monitor@"..A,function()
local J=ag.taskSwitcher(A,H,{pull=function()return coroutine.yield()end,fgPID=F,selfPid=G})p[A]=nil
if not(J and ac.get and ac.get(J))then if
F and ac.get and ac.get(F)then

ac.setForeground(F,A,{kernel=true});(ac.signalKernel or ac.signal)(F,az)end end end,{priority=2,source=ab,principal=H,token=I,display=A})p[A]=G;ac.setForeground(G,A,{kernel=true})
y=table.pack(nil)end end end
if y[1]==am and y[3]==2 then local A=1;if d.displayForKeyboard then
A=d.displayForKeyboard(y[2])or 1 end;local C=ac.getForeground(A)local B=c[A]
if
C and B and C~=B then local D=ac.get and ac.get(B)
if D and
D.state~=ac.STATE.DEAD then ac.setForeground(B,A,{kernel=true});(
ac.signalKernel or ac.signal)(B,az)
aa.info(ab,
"Backgrounded PID "..tostring(C).." on display "..A.." (Ctrl+B)")end end;y=table.pack(nil)end
if y[1]==aV then local A,B=d.rebuild()
for D,C in ipairs(B)do if c[C]then
ac.kill(c[C],{kernel=true})c[C]=nil end;if p[C]then
ac.kill(p[C],{kernel=true})p[C]=nil end;if au[C]then au[C]=nil end;if g[C]then
ac.kill(g[C],{kernel=true})g[C]=nil end;r[C]=nil;if b[C]then
if a then a.logout(b[C])end;b[C]=nil end
aa.warn(aC,"Display "..C.." removed")end;for D,C in ipairs(A)do e(C)
aa.info(aC,"Display "..C.." added, spawning login")end;y=table.pack(nil)end;local z=ad.uptime()
if z-v>=1 and ac.count()>0 then v=z
for B,A in
ipairs(aZ(d.indices(),c,g,x,r,5))do if b[A]then if a then a.logout(b[A])end;b[A]=nil end;c[A]=
nil;r[A]=(r[A]or 0)+1
aa.warn(ab,"Seat "..A..
": its shell is gone without exiting"..
" (killed?), starting its login again ["..r[A].."/5]")e(A)end end;ac.tick(y.n>0 and y or nil)
if ac.count()==0 then
aa.warn(ab,"All processes terminated")for C,B in pairs(b)do if a then a.logout(B)end end;for B in pairs(b)do
b[B]=nil end;for B in pairs(c)do c[B]=nil end;i()local A=
(d.count and d.count())or 0
if ak and A>0 then q=q+1
if q<=3 and
ad.freeMemory()>=64*1024 then
aa.warn(ab,string.format("Unexpected shell exit — recovering login on %d seat(s) [try %d/3, %dKB free]",A,q,math.floor(
ad.freeMemory()/1024)))for C,B in ipairs(d.indices())do e(B)end else
aa.error(ab,string.format("Shell unrecoverable (%dKB free after GC) — dropping to emergency shell",math.floor(
ad.freeMemory()/1024)))
pcall(ag.crashDump,string.format("shell unrecoverable (%dKB free after GC)",math.floor(ad.freeMemory()/1024)))ag.emergencyShell()break end else break end end end else ag.emergencyShell()ak=false end;ag.shutdown()end
function ag.crashWriteRaw(b,c,d,a)local f,h,i
pcall(function()f=ad.getBootAddress()end)
pcall(function()h=ad.tmpAddress()end)pcall(function()i=ad.address()end)
local g,j={},{}local function k(m)
if type(m)==an and m~=h and not j[m]then j[m]=true;g[#g+1]=m end end;k(f)pcall(function()
for m in aj.list(as)do k(m)end end)local function e(n,o,...)return
pcall(aj.invoke,n,o,...)end
local function l(m,n,o)local r,p=e(m,"open",n,"w")if
not r or not p then return false end;local s,q,t=e(m,"write",p,o)
e(m,"close",p)
return s and q~=false and not(q==nil and t~=nil)end
for n,m in ipairs(g)do local o,p=e(m,"isReadOnly")
if o and p==false then local q=(m==f)
e(m,"makeDirectory",aJ)if l(m,"/var/crash/"..b,q and c or d)then
l(m,"/var/crash/NEW",q and a or(a..
"\nmachine "..tostring(i)))return m,q end end end;return nil end
function ag.crashDump(a,b)local ae=_G._TOS and _G._TOS.fs;local f=math.floor(
(ad.uptime and ad.uptime())or 0)
local m=math.floor(
((
ad.freeMemory and ad.freeMemory())or 0)/1024)
local n=math.floor(
((ad.totalMemory and ad.totalMemory())or 0)/1024)
local c={"=== TOS CRASH REPORT ===","reason : "..tostring(a or"unknown"),"uptime : "..f.."s",
"memory : "..m.."KB free / "..n.."KB"}if b then c[#c+1]="detail :"for q in tostring(b):gmatch("[^\n]+")do
c[#c+1]="  "..q end end;local o=
table.concat(c,"\n").."\n"c[#c+1]=""
c[#c+1]="--- recent log ---"local g,d=pcall(require,aR)
if g and d and d.recent then
local r,q=pcall(d.recent,40)
if r and type(q)=="table"then for t,s in ipairs(q)do
c[#c+1]=string.format("[%8.1f][%s] %s",
tonumber(s.time)or 0,tostring(s.source or"?"),tostring(s.msg or""))end end end;local h="crash-"..f..".txt"local e="/var/crash/"..h;local i=
table.concat(c,"\n").."\n"local j=tostring(a or"unknown")..
" @ uptime "..f.."s"local k=false;if
ae and ae.writeFile then local q,r=pcall(ae.writeFile,e,i)
k=q and r and true or false end
if k then
pcall(ae.writeFile,"/var/crash/NEW",j)if g and d and d.warn then
pcall(d.warn,ab,"Crash report saved: "..e)end;return e end;local l,p=ag.crashWriteRaw(h,i,o,j)if not l then return false end
if p then return e end;return e.." on disk "..l:sub(1,8)end
function ag.checkLastCrash()local ae=_G._TOS and _G._TOS.fs;if
not(ae and ae.exists)then return end;local a={aJ}
if ae.mounts then local f,e=pcall(ae.mounts)
if f and type(e)==
"table"then
for h,g in ipairs(e)do
local i,j=pcall(aj.type,type(g)=="table"and g.address)if
i and j==as and type(g.mountPoint)==an and g.mountPoint~="/"then
a[#a+1]=(g.mountPoint:gsub("/+$",""))..aJ end end end end;local c;pcall(function()c=ad.address()end)
local d,b=pcall(require,aR)
for e,f in ipairs(a)do local g=f.."/NEW"
if ae.exists(g)then local h=""
if ae.readFile then
local k,j=pcall(ae.readFile,g)if k and type(j)==an then h=j end end;local i=h:match("\nmachine (%S+)")
if
e==1 or(i~=nil and i==c)then
local j=(h:match(aN)or""):gsub("%s+$","")if j==""then j="a previous run"end;if d and b and b.warn then
b.warn(ab,"Last run crashed: "..j..

" — see "..f.. (e==1 and" (`crash`)"or""))end;if ae.remove then
pcall(ae.remove,g)end end end end end
function ag.monitorSnapshot(b,a)if not ac then return{rows={}}end;local e=require(aD)
local j=a and a.user or nil;local g=(a and a.tier)or 0;local c=ac.list()if b then local l={}
for n,m in ipairs(c)do if not
m.display or m.display==b then l[#l+1]=m end end;c=l end
if a and g<2 then local l={}for n,m in
ipairs(c)do
if not m.user or m.user==j or m.user==aA then l[#l+1]=m end end;c=l end;local h={}if g>=2 then local m,l=pcall(require,ax)
if m and l and l.list then
local o,n=pcall(l.list)if o and type(n)=="table"then h=n end end end
local i=(
ad.freeMemory and ad.freeMemory())or 0
local d=(ad.totalMemory and ad.totalMemory())or 0
local k=(ad.uptime and ad.uptime())or 0
local f={{text=string.format("Uptime %s   RAM %dK/%dK [%s]   Processes %d",e.fmtUptime(k),math.floor((d-i)/1024),math.floor(
d/1024),e.memBar(d-i,d,12),#c),tone="vitals"},{text="",tone="dim"}}for m,l in ipairs(e.textRows(c,h))do f[#f+1]=l end
return{rows=f}end
function ag.setMonitorHost(a)if not ac then return false end
local b=ac.current and ac.current()
if not(b and b.display and b.pid)then return false end;local c=_G._TOS and _G._TOS.shellPIDs;if not
(c and c[b.display]==b.pid)then return false end;au[b.display]=
(a~=false)and b.pid or nil;return true end
function ag.isForeground()if not ac then return true end
local a=ac.current and ac.current()if not a then return true end
return ac.getForeground(a.display)==a.pid end
function ag.monitorList(a,b)if not ac then return{rows={},vitals=nil}end
local e=require(aD)local j=b and b.user or nil;local f=(b and b.tier)or 0;local k=a and
ac.getForeground(a)or nil;local d=ac.list()
if a then local m={}for o,n in
ipairs(d)do
if not n.display or n.display==a then m[#m+1]=n end end;d=m end;if b and f<2 then local m={}
for o,n in ipairs(d)do if
not n.user or n.user==j or n.user==aA then m[#m+1]=n end end;d=m end;local h={}
if f>=2 then
local n,m=pcall(require,ax)if n and m and m.list then local p,o=pcall(m.list)
if p and type(o)=="table"then h=o end end end;local c={}
for n,m in ipairs(d)do
c[#c+1]={kind="proc",pid=m.pid,label=e.describe(m),owner=m.user or ab,state=m.tsr and"TSR"or
(m.state or""),tsr=m.tsr or false,cpu=m.cpuTime or 0,isFg=(m.pid==k),canAct=e.canAct(f,j,a,m)}end
if#h>0 then c[#c+1]={kind=aO,text="Services"}for n,m in ipairs(h)do
c[#c+1]={kind="svc",name=m.name,running=m.running or
false,enabled=m.enabled~=false,canAct=f>=2,status=e.svcStatus(m)}end end
local i=(ad.freeMemory and ad.freeMemory())or 0
local g=(ad.totalMemory and ad.totalMemory())or 0
local l=string.format("up %s  ·  mem [%s] %dK/%dK free %dK  ·  %d proc",e.fmtUptime(
(ad.uptime and ad.uptime())or 0),e.memBar(g-i,g,12),math.floor((g-i)/1024),math.floor(
g/1024),math.floor(i/1024),#d)return{rows=c,vitals=l}end
function ag.monitorAct(a,b)if not ac then return false,"scheduler unavailable"end;local d=
ac.current and ac.current()if not d then
return false,"no calling process"end;local e=d.display;local f=d.principal
local g=f and f.user or nil;local h=(f and f.tier)or 0;local j=require(aD)
if a=="svc"then if h<2 then return false,
"admin only"end;local o,l=pcall(require,ax)if not
(o and l and l.list)then return false,"rc unavailable"end
local m=nil;local p,n=pcall(l.list)if p and type(n)=="table"then for u,t in ipairs(n)do
if t.name==b then m=t;break end end end;if not
m then return false,"no such service"end
local q,r=j.svcToggle(l,m,g)if not q then return false,r end;return true end;local c=ac.get(tonumber(b)or-1)
if not c or
c.state==ac.STATE.DEAD then return false,"no such process"end
if e and c.display and c.display~=e then return false,"not on this seat"end
local i=c.principal and c.principal.user or nil
if f and h<2 and i~=nil and i~=g and i~=aA then return false,aU end;local k={pid=c.pid,user=i,display=c.display}
if a=="switch"then if c.pid==d.pid then return false,
"already in front"end
ac.setForeground(c.pid,e,{kernel=true});(ac.signalKernel or ac.signal)(c.pid,az)
aa.info(ab,
"Switched to PID "..
c.pid.." ("..tostring(c.name)..") from monitor tab")return true elseif a=="kill"then
if c.pid==d.pid then return false,"Refused: PID "..
c.pid.." is the shell this Monitor runs in"end;if not j.canAct(h,g,e,k)then return false,aU end
ac.kill(c.pid,{kernel=true})
aa.warn(ab,aL..c.pid.." ("..
tostring(c.name)..") from monitor by "..tostring(g or ab))return true elseif a=="tsr"then
if c.pid==d.pid then return false,"Refused: PID "..
c.pid.." is the shell this Monitor runs in"end;if not j.canAct(h,g,e,k)then return false,aU end;if c.tsr then c.tsr=false
c.state=ac.STATE.READY else ac.goTSR(c.pid)end;return true end;return false,"unknown action"end
function ag.taskSwitcher(a,c,b)b=b or{}local C=b.pull~=nil;local D=b.pull or
function()return ad.pullSignal(0.5)end;local E=b.selfPid
local F=require(ay)local e=a and F.displayProxy(a)or af;if
not e or not ac then return end;local N=_G._TOS.users
local s=c and c.user or nil;local t=c and c.tier or 0;local j=require(aD)
local y,p=pcall(require,ax)local G,I=e.getSize()local d=e.getTheme()
local function J()local H=ac.list()if a then local O={}
for Q,P in ipairs(H)do if

P.pid~=E and(not P.display or P.display==a)then O[#O+1]=P end end;H=O end
if c and t<2 then
local O={}for Q,P in ipairs(H)do if not P.user or P.user==s or P.user==aA then
O[#O+1]=P end end;H=O end;return H end
local function K()
if t<2 or not(y and p and p.list)then return{}end;local O,H=pcall(p.list)return
(O and type(H)=="table")and H or{}end;local function z(H)return j.canAct(t,s,a,H)end;local i,m=1,1;local h,q=G,I;local w=math.max(20,h-2-
30)
local A=math.max(12,math.min(28,h-2-4-34))local L=m+4;local n=math.max(1,q-6)
local u=b.fgPID or ac.getForeground(a)local x=nil;local v=nil;local g={}local f=1;local k=0
local function o()if#g==0 then k=0;return end;if f<=k then k=f-1 end;if f>
k+n then k=f-n end;local H=math.max(0,#g-n)if k>H then k=H end
if k<0 then k=0 end end
local function r()g=j.buildRows(J(),K())if#g==0 then return false end
if f>#g then f=#g end;if f<1 or(g[f]and g[f].kind==aO)then
f=j.firstSelectable(g)end;o()return true end;if not r()then return end;for O,H in ipairs(g)do if H.kind=="proc"and H.p.pid==u then f=O;o()
break end end;local function M()
e.dbox(i,m,h,q,"System Monitor",{border=d.border,bg=d.panel_bg,title=d.title})end
local function l()
local H=ad.totalMemory()or 0;local Q=ad.freeMemory()or 0;local R=H-Q;local O=0;for W,V in ipairs(g)do if V.kind=="proc"then
O=O+1 end end
local T=string.format(" up %s  ·  mem [%s] %dK/%dK free %dK  ·  %d proc",j.fmtUptime(ad.uptime()),j.memBar(R,H,12),math.floor(
R/1024),math.floor(H/1024),math.floor(Q/1024),O)e.set(i+1,m+1,e.fit(T,h-2),d.fg,d.panel_bg)e.fill(i+
1,m+2,h-2,1," ",d.fg,d.panel_bg)
local U=string.format(" %-4s %-"..w..
"s %-8s %-7s %5s","PID","Process","Owner","State","CPU")e.set(i+1,m+3,e.fit(U,h-2),d.dim,d.panel_bg)
for V=1,n do
local X=k+V;local W=L+V-1
if X<=#g then local Y=g[X]local Z=(X==f)
if Y.kind==aO then local _=h-2
local bb=4+#Y.text+1;local ba;if bb<=_ then
ba=" ── "..Y.text.." "..string.rep("─",_-bb)else
ba=" ── "..Y.text:sub(1,math.max(0,_-5)).." "end
e.set(i+1,W,ba,d.title,d.panel_bg)elseif Y.kind=="proc"then local _=Y.p;local bb=(_.pid==u)and"*"or" "
local bc=_.tsr and
"TSR"or(_.state or""):sub(1,7)local bd=(_.user or ab):sub(1,8)
local ba=string.format("%s%-4d %-"..w..
"s %-8s %-7s %4.1fs",bb,_.pid,j.describe(_):sub(1,w),bd,bc,_.cpuTime or 0)
if Z then e.set(i+1,W,e.fit(ba,h-2),d.sel_fg,d.sel_bg)else
local be=d.fg;if _.tsr then be=d.dim elseif _.pid==u then be=d.highlight end
e.set(i+1,W,e.fit(ba,h-2),be,d.panel_bg)end else local _=Y.s
local ba=string.format("   %-"..A.."s %s",(_.name or"?"):sub(1,A),j.svcStatus(_))if Z then e.set(i+1,W,e.fit(ba,h-2),d.sel_fg,d.sel_bg)else
e.set(
i+1,W,e.fit(ba,h-2),_.running and d.highlight or d.dim,d.panel_bg)end end else e.fill(i+1,W,h-2,1," ",d.fg,d.panel_bg)end end;local S=g[f]local P
if S and S.kind=="svc"then
P=" [Enter/S] start-stop   up/down move   [^Q] close"else P=" [Enter] switch  [K]ill  [T]SR   up/down move   [^Q] close"end
if v then e.fill(i+1,m+q-2,h-2,1," ",d.fg,d.panel_bg)
e.set(i+1,
m+q-2,e.fit(" "..v,h-2),d.error or d.fg,d.panel_bg)else
e.set(i+1,m+q-2,e.fit(P,h-2),d.dim,d.panel_bg)end end;M()l()
while true do local P,Q,H,O=D()
if P==am then v=nil
if H==17 or H==113 then break elseif O==200 then
f=j.nextSelectable(g,f,-1)o()l()elseif O==208 then f=j.nextSelectable(g,f,1)o()l()elseif O==201 then for Q=1,n do
f=j.nextSelectable(g,f,-1)end;o()l()elseif O==209 then
for Q=1,n do f=j.nextSelectable(g,f,1)end;o()l()else local R=g[f]
if R and R.kind=="proc"then local S=R.p
if O==28 then
ac.setForeground(S.pid,a,{kernel=true});(ac.signalKernel or ac.signal)(S.pid,az)
aa.info(ab,
"Switched to PID "..S.pid.." ("..tostring(S.name)..")")x=S.pid;break elseif H==107 or H==75 then
if S.pid~=u and z(S)then
ac.kill(S.pid,{kernel=true})
aa.warn(ab,aL..S.pid.." ("..
tostring(S.name)..") from monitor by "..tostring(s or ab))if not r()then break end;l()end elseif H==116 or H==84 then if z(S)then local T=ac.get(S.pid)
if T then if T.tsr then T.tsr=false
T.state=ac.STATE.READY else ac.goTSR(S.pid)end;r()l()end end end elseif R and R.kind=="svc"then if O==28 or H==115 or H==83 then
if t>=2 and y and p then
local S,T=j.svcToggle(p,R.s,s)v=(not S)and T or nil;r()l()end end end end elseif P==nil then r()l()end end;if C then return x end;local B=ac.getForeground(a)if B then
(ac.signalKernel or ac.signal)(B,az)end;return x end
function ag.emergencyShell()if not af then return end;local g=_G._TOS.users;local h,q=af.getSize()
local c=af.getTheme()af.clear(c.bg)
af.set(2,2,"TOS EMERGENCY - Auth Required",c.error,c.bg)
if not g then
af.set(2,3,"User system unavailable - cannot authenticate.",c.error,c.bg)af.set(2,4,"Rebooting...",c.dim,c.bg)
ad.pullSignal(3)ag.reboot()return end;af.set(2,3,"Password: ",c.dim,c.bg)local i=false
for r=1,3 do
af.fill(12,3,h-13,1," ",c.fg,c.bg)local s=""
while true do
af.set(12,3,string.rep("*",#s).."_ ",c.fg,c.bg)local w,x,u,v=ad.pullSignal(0.5)if w==am then
if v==28 then break elseif v==14 then
if#s>0 then s=s:sub(1,-2)end elseif u and u>=32 and u<127 then s=s..string.char(u)end end end;local t=g.login("root",s,{setCurrent=true})
if t then i=true;break end
if r<3 then
af.set(2,5,"Wrong. ".. (3-r).." left.",c.error,c.bg)ad.pullSignal(1.5)af.fill(2,5,h-3,1," ",c.fg,c.bg)end end;if not i then af.set(2,5,"Locked. Rebooting...",c.error,c.bg)
ad.pullSignal(3)ag.reboot()return end
local e,j=af.getSize()local a=af.getTheme()local f={}local k=0;local l=3;local m=j-l-1
local function o()af.clear(a.bg)
af.set(2,1,"TOS EMERGENCY SHELL",a.error,a.bg)
af.set(2,2,"Main shell could not load.",a.warning,a.bg)af.set(2,3,"'help' for list.",a.dim,a.bg)
local r=#f-m-k+1;if r<1 then r=1 end
for s=1,m do local t=r+s-1;local u=l+s
if t>=1 and t<=#f then local v=f[t]
af.fill(1,u,e,1," ",a.fg,a.bg)
af.set(1,u,v[1]:sub(1,e),v[2]or a.dim,a.bg)else af.fill(1,u,e,1," ",a.fg,a.bg)end end end
local function b(r,s)f[#f+1]={tostring(r),s or a.dim}k=0;o()end
local function p()local s=j;af.fill(1,s,e,1," ",a.fg,a.bg)
af.set(1,s,"> ",a.prompt,a.bg)local r=""
while true do af.fill(3,s,e-3,1," ",a.fg,a.bg)
af.set(3,s,r,a.fg,a.bg)af.set(3+#r,s,"_",a.prompt,a.bg)
local v,w,t,u=ad.pullSignal(0.5)if v==am then
if u==28 then return r elseif u==14 then if#r>0 then r=r:sub(1,-2)end elseif
t and t>=32 and t<127 then r=r..string.char(t)end end end end;local d=_G._TOS and _G._TOS.securefs;local n=
g.kernelSession and g.kernelSession()or nil
while true do local t=p()local r={}for u in
t:gmatch("%S+")do r[#r+1]=u end
local s=r[1]and r[1]:lower()or""
if s=="help"then b("Emergency commands:",a.title)
b("  ls [path]   - List files")b("  cat <file>  - Show file")
b("  mem         - Memory info")b("  df          - Disks and free space")
b("  log [N]     - Last N kernel log lines")b("  verify      - Check system files")
b("  srm [status|scan|repair [--restore]]")b("              - System Repair & Maintenance")
b("  reboot      - Reboot system")b("  shutdown    - Shut down")elseif s=="df"then local u;pcall(function()
u=ad.getBootAddress()end)local v=false
for w in
aj.list(as)do v=true
local function x(B)local C,D=pcall(aj.invoke,w,B)if C then return D end end;local y,z=x("spaceTotal"),x("spaceUsed")local A=x("getLabel")
b(string.format("  %s %-12s %8s used of %8s%s%s",w:sub(1,8),tostring(
A or""):gsub("%c","?"):sub(1,12),
z and(math.floor(z/1024).."K")or"?",
y and(math.floor(y/1024).."K")or"?",
x("isReadOnly")and"  read-only"or"",w==u and"  (boot)"or""))end
if not v then b("No filesystems found.",a.error)end elseif s=="log"then
local v=math.max(1,math.min(tonumber(r[2])or 20,200))
local w,u=pcall(function()return aa.recent(v)end)
if w and type(u)=="table"and#u>0 then for y,x in ipairs(u)do
b(string.format("[%7.1f][%s] %s",
tonumber(x.time)or 0,tostring(x.source or"?"),tostring(x.msg or"")))end else
local y,x=pcall(ae.readFile,"/var/log/kernel.log")
if y and type(x)==an and x~=""then local z={}
for A in x:gmatch("[^\n]+")do
z[#z+1]=A;if#z>v then table.remove(z,1)end end;for B,A in ipairs(z)do b(A)end else
b("No log available (the ring and /var/log/kernel.log are both unreadable).",a.error)end end elseif s=="srm"then local u=(r[2]or"status"):lower()
local w,v=pcall(require,aS)
if not w or type(v)~="table"then
b("srm will not load: "..tostring(v),a.error)elseif u~="status"and u~="scan"and u~=aq then
b("Usage: srm [status | scan | repair [--restore]]",a.dim)else
local y,x=pcall(v[u],nil,{restore=r[3]=="--restore"})
if not y or type(x)~="table"then b("srm "..
u.." failed: "..tostring(x),a.error)else
for A,z in ipairs(
x.findings or{})do
b("  "..tostring(z.text),

(z.sev=="err"and a.error)or(z.sev=="warn"and a.warning)or(
z.sev=="ok"and a.success)or a.dim)end end end elseif s=="ls"then local v=r[2]or"/"local u;if d and d.list then u=d.list(v,n)else
local w,x=pcall(ae.list,v)if w then u=x end end
if u then if type(u)=="table"then for x,w in
ipairs(u)do b("  "..w)end elseif type(u)==al then
for w in u do b("  "..w)end end else
b("Cannot list: "..v,a.error)end elseif s=="cat"then
if r[2]then local u;if d and d.readFile then u=d.readFile(r[2],n)else
u=ae.readFile(r[2])end
if u then
for v in u:gmatch("[^\n]*")do b(v)end else b("Cannot read: "..r[2],a.error)end end elseif s=="mem"then
b(string.format("Free: %dKB / Total: %dKB",math.floor(ad.freeMemory()/1024),math.floor(
ad.totalMemory()/1024)))elseif s=="verify"then ag.verifySystem(b)elseif s=="reboot"then ag.reboot()return elseif
s=="shutdown"then ag.shutdown()return elseif s~=""then b("Unknown: "..s,a.warning)end end end
function ag.verifySystem(a)a=a or function()end
local l=af and af.c("success")or 0xFFFFFF;local g=af and af.c("warning")or 0xFFFFFF;local d=af and
af.c("error")or 0xFFFFFF
local j=af and af.c("dim")or 0xFFFFFF;local m
do local p,o=pcall(require,"system_manifest")
if
p and type(o)=="table"then m=o else
m={{path="/init.lua",critical=true},{path="/tos/kernel/init.lua",critical=true},{path="/tos/shell/init.lua",critical=true}}
a("  WARN: system_manifest.lua not found, using minimal verify list",g)end end;local c,e,b=0,0,0;local h=0;local i=nil
do local o,p=pcall(require,aw)if o then i=p end end;local k=0
local function n(o)local p=ae.open(o,"r")
if not p then return nil,nil,"unreadable"end;local r,s={},0
local u,v=pcall(function()while true do local y=p:read(4096)if y==nil then break end
if#y>0 then s=s+1;r[s]=y end end end)pcall(p.close,p)if not u then return nil,v,aE end;local q=0
local w,t,x=pcall(load,function()q=q+1
local y=r[q]r[q]=nil;return y end,"="..o,"t")if not w then return nil,t,aE end;return t,x,nil end
for p,o in ipairs(m)do
if ae.exists(o.path)then
do
if o.hash and i and i.hash then
if type(o.hash)~=an or
#o.hash~=64 or o.hash:find("[^%x]")then
a(av..
o.path.." (malformed hash in manifest)",g)b=b+1
if type(collectgarbage)==al then pcall(collectgarbage,ap)end;goto continue_verify end;local q=ae.readFile(o.path)if not q then a(av..o.path..aI,d)
b=b+1
if type(collectgarbage)==al then pcall(collectgarbage,ap)end;goto continue_verify end
local r=i.hash(q)q=nil
if not i.ctEquals(r,o.hash)then
a("  HASH "..o.path..
" (manifest="..o.hash:sub(1,12).." actual="..
r:sub(1,12)..")",d)k=k+1;b=b+1;if type(collectgarbage)==al then
pcall(collectgarbage,ap)end;goto continue_verify end;a(aH..o.path,l)c=c+1;if type(collectgarbage)==al then
pcall(collectgarbage,ap)end;goto continue_verify end
if not o.path:match("%.lua$")then local r=false
local q=ae.open(o.path,"r")if q then
r=pcall(function()repeat local s=q:read(4096)until s==nil end)pcall(q.close,q)end
if r then
a(aH..o.path,l)c=c+1 else a(av..o.path..aI,d)b=b+1 end else local s,q,r=n(o.path)
if s then a(aH..o.path,l)c=c+1 elseif r=="unreadable"then a(av..
o.path..aI,d)b=b+1 else local t
if r==aE then t="OOM"else t="error"if q then if q:find("memory")then
t="low RAM"else t="syntax"end end end;a(av..o.path.." ("..t..")",g)
if
r~=aE and q then a("      "..tostring(q),j)end;b=b+1 end end end
if type(collectgarbage)==al then pcall(collectgarbage,ap)end else local q=o.critical and"MISS"or"GONE"
local r=o.critical and d or g
a("  "..q..
" "..o.path..
(o.critical and" (critical, not installed)"or" (not installed)"),r)e=e+1;if o.critical then h=h+1 end end::continue_verify::
if ac and ac.yieldCooperative then pcall(ac.yieldCooperative)end end;a("",j)local f=tostring(e)
if h>0 then
f=string.format("%d missing (%d CRITICAL)",e,h)else f=string.format("%d missing",e)end
if k>0 then
a(string.format("Result: %d OK, %s, %d damaged (incl. %d HASH MISMATCH)",c,f,b,k),d)elseif h>0 or b>0 then a(string.format(aM,c,f,b),d)elseif e>0 then
a(string.format(aM,c,f,b),g)
a("Missing files are absent, not corrupt — reinstall to restore them.",j)else a(string.format(aM,c,f,b),j)end;return e==0 and b==0 end
local function a_()local a="/tos/system_manifest.lua"
if not ae.exists(a)then return nil,"manifest missing"end;return ae.readFile(a)end
function ag.computeManifestHash()local b,c=a_()if not b then return nil,c end
local d,a=pcall(require,aw)
if not d or not a or not a.hash then return nil,"crypto unavailable"end;return a.hash(b)end
function ag.anchorManifestHash()local a,e=ag.computeManifestHash()
if not a then return false,e end;local aj=require(ar)local c=aj.list(aB)()
if not c then return false,aT end;local b=aj.proxy(c)
if not b.setData then return false,"EEPROM has no setData"end;local f=b.getData()or""local g=f:match(aN)or""
local d=g.."\nTOS1:"..a;if#d>256 then return false,"EEPROM data field too small"end
b.setData(d)return true,a end
function ag.clearManifestAnchor()local aj=require(ar)local b=aj.list(aB,true)()if not b then return false,
aT end;local a=aj.proxy(b)
if not
(a.getData and a.setData)then return false,"EEPROM has no data field"end;local c=a.getData()or""
a.setData(c:match(aN)or"")return true end
function ag.verifyManifestHash()local aj=require(ar)local d=aj.list(aB)()
if not d then return false,aT end;local e=aj.proxy(d)
if not e.getData then return false,"EEPROM has no getData"end;local f=e.getData()or""
local a=f:match("\nTOS1:(%x+)")or f:match("^TOS1:(%x+)")
if not a then return false,"no anchored hash (run `verify anchor` as admin)"end;a=a:sub(1,64)if#a~=64 or a:find("[^%x]")then
return false,"anchored value malformed"end
local b,g=ag.computeManifestHash()if not b then return false,g end;local h,c=pcall(require,aw)
if not h or not c or not
c.ctEquals then return false,"crypto unavailable"end;if c.ctEquals(b,a)then return true end;return false,
"manifest hash mismatch (live="..b:sub(1,12).." anchored="..
a:sub(1,12)..")"end
function ag.manifestAnchorWarning()local b,c,a=pcall(ag.verifyManifestHash)if not b or c then
return nil end;a=tostring(a)if a:find("mismatch",1,true)or
a:find("malformed",1,true)then return a end;return nil end;function ag.getLog()return aa end;function ag.getHAL()return ai end
function ag.getEvent()return ah end;function ag.getProc()return ac end
function ag.getFS()return _G._TOS.securefs or ae end;function ag.getDisplay()return af end;function ag.getDisplayIdx()return nil end;function ag.getUsers()return
_G._TOS.users end
function ag.getSecureFS()return _G._TOS.securefs end;function ag.getConfig()return _G._TOS.config end;function ag.getPower()
return _G._TOS.power end;function ag.getSwap()return _G._TOS.swap end;function ag.getJBOD()return
_G._TOS.jbod end
function ag.getNet()return _G._TOS.net end
function ag.getCompress()if _G._TOS.compress then return _G._TOS.compress end
local b,a=pcall(require,"kernel.compress")
if b and a then pcall(a.init,{})_G._TOS.compress=a;return a end;return nil end
function ag.uptime()return ad.uptime()-_G._TOS.bootTime end;local aG=false
function ag.shutdown(a)if a then aG=true end;a=aG;ak=false;aW=true
if aa then aa.info(ab,a and"Rebooting..."or
"Shutting down...")end
local b=package and package.loaded and package.loaded[aP]
if type(b)=="table"and b.shutdown then pcall(b.shutdown)end
if _G._TOS.rc then pcall(_G._TOS.rc.stopAll)end;if ac then
for d,c in ipairs(ac.list())do pcall(ac.kill,c.pid,{kernel=true})end end;if _G._TOS.net then
pcall(_G._TOS.net.shutdown)end;pcall(aa.flush)
pcall(aa.detachFile)
if af then
pcall(function()local c=af.getTheme()af.clear(c.bg)
af.set(2,2,a and"Rebooting TOS..."or
"TOS shut down.",c.success,c.bg)af.set(2,3,"Goodbye!",c.dim,c.bg)end)end
if _G._TOS.audio then pcall(_G._TOS.audio.shutdown)end
pcall(function()local c=_G._TOS.fs;if c and c.writeFile then
c.writeFile("/var/run/pwrstate","C\n"..
tostring(_G._TOS.bootCount or 0)..
"\n"..tostring((os.time and os.time())or 0))end end)ad.pullSignal(0.5)ad.shutdown(a or false)end;function ag.reboot()ag.shutdown(true)end;function ag.version()return _G._TOS.version,
_G._TOS.codename end
function ag.headlessMain()ak=true;_G._TOS.bootSession=
nil;_G._TOS.bootCompleted=true
aa.info(ab,"Entering headless service loop")
if not _G._TOS.net then
aa.warn(ab,"WARNING: headless server has no network!")
aa.warn(ab,"Install a modem or linked card so the server can be reached.")end
while ak do local a=table.pack(ah.pull(0.5))if a[1]=="tos_shutdown"then
ak=false;break end
if a[1]=="component_added"then local b=a[3]
if
b==aF or b=="gpu"or b=="keyboard"then
aa.info(ab,"Display hardware detected — checking for interactive switch")local c=require(ar)local d=c.list("gpu")()~=nil;local e=
c.list(aF)()~=nil
local f=c.list("keyboard")()~=nil
if d and e and f then
aa.info(ab,"Full display hardware present — switching to interactive mode")ak=false;af=require("kernel.display")
local g=c.proxy(c.list("gpu")())
if g then local j,k=g.maxResolution()local l,i=pcall(require,ay)
if
l and i and i.gpuTarget then
local h=i.getPolicy()or i.specFromConfig(_G._TOS and _G._TOS.config)i.setPolicy(h)local m,n=i.gpuTarget(g,nil,h)
if m and n then j,k=m,n end end;af.init(g,j,k)end;ag.loginAndStartShell()return end end end;ac.tick(a.n>0 and a or nil)end;ag.shutdown()end;return ag