
local at,aF,aG,aH,aI,aJ,aK,ay,an,ap,az,aq,ak,aL,aA,_,aM,au,aN,aO,aB,av,aw,ar,aP,aj,aQ,aR,aC,ao,aD,al,ax,aS="  BAD "," (unreadable)","/var/crash","KB free)","Killed PID ","Result: %d OK, %s, %d damaged","^[^\n]*","_kernel_","collect","component","eeprom","filesystem","function","header","hotplug","kernel","kernel.cron","kernel.crypto","kernel.fs","kernel.log","kernel.monitor","kernel.rc","kernel.screen","kernel.serialize","kernel.srm","key_down","no EEPROM","not permitted","raised","repair","screen","string","tos_focus","tos_seat_changed"local ab=require("computer")local ah=require(ap)local ae={}local ai=false
local aT=false;local Z,ag,af,aa,ad,ac;local am;local as={}
function ae.boot(a)a=a or{}
local q=a.earlyPrint or function()end;local v=a.earlyMinLevel or 1
local function d(z,A)if v<=1 then q(z,A)end end;local e=a.bootcfg;local g=a.bootcfgMod;local function f(A,z)
if g and e and g.wants then return g.wants(e,A,z)end;return z end;local m=40960
local function i()
local A=(
ag and ag.freeMemory and ag.freeMemory(m))or ab.freeMemory()local z=A>m;if g and e and g.ramOK then return g.ramOK(e,z)end
return z end
local j=(e and e.memprofile==true)and{}or nil
local function c(z)if not j then return end
if type(collectgarbage)==ak then
pcall(collectgarbage,an)else local A={}
for B=1,10 do local C=table.pack(ab.pullSignal(0))if C.n>0 and
C[1]~=nil then A[#A+1]=C end end;for C,B in ipairs(A)do
pcall(ab.pushSignal,table.unpack(B,1,B.n))end end
j[#j+1]={stage=z,free=ab.freeMemory(),t=ab.uptime()}end;c("1 core modules")
d("  Loading kernel modules...",0xAAAAAA)Z=require(aO)
Z.init({earlyPrint=q,earlyMinLevel=a.earlyMinLevel,bootProgress=a.bootProgress})
Z.info(_,"TOS Kernel v".._G._TOS.version..
" (build "..tostring(_G._TOS.build or"?")..
", "..tostring(
_G._TOS.variant or"?")..") starting")_G._TOS.log=function(z,A)Z.info(z,A)end
_G._TOS.logObj=Z;c("2 hardware detection")
Z.info(_,"Scanning hardware...")ag=require("kernel.hal")ag.scan()local h=ag.systemInfo()
Z.info(_,string.format("CPU T%d | GPU T%d | RAM %s | %d components",h.cpuTier,h.gpuTier,
h.memTierName or("T"..h.memTier),h.components))if h.canNetwork then local z=ag.checkWireless()h.hasWireless=z
Z.info(_,"Network: ".. (z and"Wireless"or
"Wired").." modem detected")end;if h.hasTunnel then
Z.info(_,"Linked card (tunnel) detected")end;c("3 filesystem")
Z.info(_,"Initializing filesystem...")ad=require(aN)ad.init(a.bootFS)
local r=a.bootFS and a.bootFS.address;local w,n=pcall(require,"kernel.diskmount")
if
w and type(n)=="table"then am=n;am.init({fs=ad,log=Z,bootAddr=r})for A,z in
ipairs(ag.list(aq))do
if z.address~=r then
if not z.proxy then z.proxy=ah.proxy(z.address)end;am.mount(z.address,z.proxy)end end else
Z.warn(_,
"Disk mounting unavailable ("..tostring(n).."): only the boot disk is mounted")end
local x={"/tmp","/var","/var/log","/var/run","/var/pkg","/var/pkg/installed","/var/swap","/etc","/usr","/usr/bin","/usr/modules"}for A,z in ipairs(x)do
if not ad.exists(z)then ad.makeDirectory(z)end end
pcall(Z.attachFile,ad,"/var/log/kernel.log",{rotateBytes=16384})local o="/var/run/pwrstate"
do
local z=ad.exists(o)and ad.readFile(o)or nil;local A=0;if type(z)==al and#z>0 then
A=tonumber(z:match("\n(%d+)"))or 0;_G._TOS.unsafeShutdown=z:sub(1,1)~="C"else
_G._TOS.unsafeShutdown=false end;_G._TOS.bootCount=
A+1
if ad.recoverAtomic then
local B=ad.recoverAtomic({"/etc/users.dat","/etc/trust.dat","/etc/tos.cfg","/etc/cron.db","/etc/critical.bak"})if B>0 then
Z.warn(_,"Recovered "..B.." interrupted critical write(s) from a prior crash")end end
pcall(ad.writeFile,o,"R\n".._G._TOS.bootCount.."\n"..
tostring((os.time and os.time())or 0))
if _G._TOS.unsafeShutdown then
Z.warn(_,"PREVIOUS SHUTDOWN WAS UNSAFE (power loss / forced off) — state verified on boot")pcall(ab.beep,880,0.1)pcall(ab.beep,660,0.1)end end
pcall(function()local C=ah.list(az)()if not C then return end;local A=ah.proxy(C)if not
(A and A.getData)then return end;local D=A.getData()if type(D)~=al or not
D:find("SRM:",1,true)then return end
local F,B=pcall(require,aP)if not(F and B)then
Z.warn("srm","A POST fault is parked in the EEPROM but kernel.srm "..
"would not load: "..tostring(B))return end
local z=B.readFault({eeprom=A})if not z then return end;local E=z.code..
(z.err and(" / "..z.err)or"")
Z.error("srm","LAST BOOT FAILED POST — SRM "..E..
": "..z.why)
d("  SRM "..E..": last boot failed POST",0xFF6600)d("    "..z.why,0xFFAA00)
d("    (run 'srm' for the full report)",0xAAAAAA)local G,H=B.clearFault({eeprom=A})if not G then
Z.warn("srm","could not clear the parked code: "..
tostring(H))end
if _G._TOS then _G._TOS.postFault=z end end)local s=math.floor(ad.spaceFree("/")/1024)local y=math.floor(
ad.spaceTotal("/")/1024)
Z.info(_,string.format("Boot disk: %dKB free / %dKB total",s,y))
if s<32 then Z.warn(_,"WARNING: Very low disk space!")end
if e and e.repair then
Z.warn(_,"SELF-REPAIR requested — checking system state...")e.repair=false
pcall(function()if g and g.save then g.save(ad,e)end end)
local D={fs=ad,log=Z,serialize=(function()local F,G=pcall(require,ar)return F and G or nil end)()}local z,B,A=nil,0,0;local E,C=pcall(require,aP)
if E and type(C)=="table"then
local G,F=pcall(C.repair,D)
if G and type(F)=="table"then z=F.findings;B=F.fixed or 0;A=
(F.counts.warn or 0)+ (F.counts.err or 0)else Z.warn(ao,
"self-repair failed: "..tostring(F))end else
Z.warn(ao,"kernel.srm unavailable ("..tostring(C)..") — falling back to kernel.repair")local G,F=pcall(require,"kernel.repair")
if G and F then
local I,H=pcall(F.run,D)
if I and type(H)=="table"then z={}for K,J in ipairs(H.lines or{})do
z[#z+1]={text=J,sev=J:sub(1,5)==
"WARN:"and"warn"or"info"}end
B,A=H.fixed or 0,H.warned or 0 else
Z.warn(ao,"self-repair failed: "..tostring(H))end else
Z.warn(ao,"kernel.repair unavailable: "..tostring(F))end end
if z then local G={ok=0x00FF00,info=0xAAAAAA,warn=0xFFAA00,err=0xFF6600}for I,H in
ipairs(z)do Z.info(ao,H.text)
d("  "..H.text,G[H.sev]or 0xAAAAAA)end
local F=string.format("Self-repair: %d fixed, %d warning(s)",B,A)Z.warn(ao,F)
d("  "..F,A>0 and 0xFFAA00 or 0x00FF00)end end;c("4 system configuration")local b=nil
do
Z.info(_,"Loading configuration...")local A,z=pcall(require,"kernel.config")
if A then b=z;b.init(ad)
_G._TOS.config=b
Z.info(_,"Device profile: "..b.deviceType())if b.get("verbose")then Z.setLevel("DEBUG")end else
Z.warn(_,
"Config module not available: "..tostring(z))end end;c("4b disk swap")
if f("swap",true)then local A;do
local D,C=pcall(require,"kernel.compress")
if D and C then pcall(C.init,{log=Z})_G._TOS.compress=C;A=C end end
local B,z=pcall(require,"kernel.swap")
if B and z then
local C,D=pcall(z.init,{fs=ad,serialize=require(ar),log=Z,config=b,compress=A})if C then _G._TOS.swap=z else
Z.warn(_,"Swap init failed: "..tostring(D))end else
Z.warn(_,"Swap module not available: "..tostring(z))end end;c("4b2 internet card transport")do
local A,z=pcall(require,"kernel.internet")
if A and z then pcall(z.init,{log=Z,config=b})_G._TOS.internet=z end end
c("4c jbod disk pooling")
if f("jbod",false)then local A,z=pcall(require,"kernel.jbod")
if A and z then
_G._TOS.jbod=z;Z.info(_,"JBOD disk pooling enabled")
local B=z.loadConfig(ad)
if B and type(B.pools)=="table"then
for D,C in ipairs(B.pools)do
if
type(C)=="table"and
type(C.mount)==al and type(C.members)=="table"then local E={}for D,F in ipairs(C.members)do local H,G=pcall(ah.proxy,F)
if H and G then E[#E+1]=G end end
if#E==0 then
Z.warn(_,"JBOD pool "..C.mount..
": no members present, not mounted")else local F=z.makePool(E)local G,H=ad.mount(C.mount,F)
if G then
Z.info(_,string.format("JBOD mounted %s (%d/%d members)",C.mount,
#E,#C.members))else
Z.warn(_,"JBOD mount "..C.mount.." failed: "..tostring(H))end end end end end else
Z.warn(_,"JBOD enabled but module unavailable: "..tostring(z))end end;c("5 event system")
Z.info(_,"Starting event system...")af=require("kernel.event")
local t={screen=true,gpu=true,keyboard=true}
af.on("component_added",function(B,z,A)ag.handleComponentAdded(z,A)
Z.info(aA,"Added: "..A.." ["..z:sub(1,8)..
"]")if t[A]then af.push(aS,"added",A,z)end
if A==aq and am then
local D,C=pcall(ah.proxy,z)if D and C then local E,F=am.mount(z,C)
if E then af.push("tos_disk_added",z,E,F)end end end end,_)
af.on("component_removed",function(B,z,A)ag.handleComponentRemoved(z,A)
Z.info(aA,"Removed: "..A.." ["..
z:sub(1,8).."]")if t[A]then af.push(aS,"removed",A,z)end
if A==aq and am then
local C,D=am.unmount(z)if C then af.push("tos_disk_removed",z,C,D)end end end,_)
af.on("screen_resized",function(C,z,A,B)local E,D=pcall(require,aw)if
not(E and D and D.onResized)then return end;if D.onResized(z,A,B)then local F,G=D.getResolution()
Z.info(aD,string.format("Screen resized externally -> %dx%d",
F or 0,G or 0))end end,_)c("6 process manager")
Z.info(_,"Starting process manager...")aa=require("kernel.process")c("7 display system")local p=b and
b.isHeadless()
if p then
Z.info(_,"Headless mode — skipping display init")
ac={init=function()end,clear=function()end,fill=function()end,set=function()end,getSize=function()return 0,0 end,getGpuTier=function()return 0 end,getGpuDepth=function()return 1 end,getTheme=function()
return setmetatable({},{__index=function()return
0xFFFFFF end})end,getGpu=function()return nil end,fit=function(z)return z or""end,c=function()return
0xFFFFFF end}else Z.info(_,"Initializing display...")
ac=require("kernel.display")local A,B,z=a.screenW,a.screenH
do local F,E=pcall(require,aw)
if
F and E and E.specFromConfig then local G=E.specFromConfig(b)E.setPolicy(G)
local H,I,J=E.gpuTarget(a.gpu,nil,G)if H and I then A,B=H,I end;z=J end end;ac.init(a.gpu,A,B)local C,D=ac.getSize()
Z.info(_,string.format("Display: %dx%d, GPU Tier %d (%d-bit color)",
C or 0,D or 0,ac.getGpuTier(),ac.getGpuDepth()))if z then Z.warn(aD,z)end end;c("8 power monitor")
do
if f("power",i())then
local A,z=pcall(require,"kernel.power")
if A then z.init({log=Z,config=b})_G._TOS.power=z
pcall(z.applyProfile,(b and
b.get("powerProfile"))or"balanced")
if b and b.isTablet()then
af.interval(10,function()z.check()end,"kernel:power")
z.onLow(function(B)if _G._TOS.audio then _G._TOS.audio.warning()else
ab.beep(800,0.3)end end)
z.onCritical(function(B)if _G._TOS.audio then _G._TOS.audio.critical()else
ab.beep(400,0.5)end
Z.fatal("power","Battery critical!")
if not b or b.get("critBatShutdown")~=false then
Z.warn("power","Critical battery — clean shutdown to protect data")pcall(Z.flush)ae.shutdown(false)end end)Z.info(_,"Tablet mode: battery monitoring active")end else
Z.warn(_,"Power module not available: "..tostring(z))end else
Z.warn(_,i()and"Skipping power module (boot profile)"or
("Skipping power module (low memory: "..math.floor(
ab.freeMemory()/1024)..aH))end end
local function k(z,B,A)local C,D=nil,false
_G._TOS[z]=setmetatable({},{__index=function(F,E)if C then return C[E]end
local H,G=pcall(require,B)if not H or type(G)~="table"then
if not D then D=true;Z.warn(_,z..
": lazy load failed: "..tostring(G))end;return nil end;if
G.init and A then pcall(G.init,A())end;C=G;_G._TOS[z]=G;Z.info(_,z..
" module ready (on demand)")return G[E]end})end;c("9 security subsystem")
do
if ab.freeMemory()>m then
local A,z=pcall(require,au)
if A then z.init()
Z.info(_,"Crypto: "..
(z.hasHardware()and"Hardware"or"Software"))
pcall(function()if
not(z.addEntropy and z.exportEntropy and ad)then return end;local D="/etc/entropy"
if ad.makeDirectory and not
ad.exists("/etc")then ad.makeDirectory("/etc")end;if ad.exists(D)then local E=ad.readFile(D)if type(E)==al and#E>0 then
z.addEntropy(E)end end
z.addEntropy(
tostring(ab.uptime()).."|"..
tostring(ab.freeMemory()).."|"..tostring({}))ad.writeFile(D,z.exportEntropy(64))end)local C,B=pcall(require,"kernel.users")
if C then
B.init({fs=ad,crypto=z,log=Z,config=b})_G._TOS.users=B;local E,D=pcall(require,"kernel.securefs")
if E then
D.init({fs=ad,users=B,log=Z,process=aa})_G._TOS.securefs=D;_G._TOS.bootSession=B.kernelSession()
Z.info(_,"Security: users + securefs ready")k("trash","kernel.trash")
local H,G=pcall(require,"kernel.profile")
if H and G and G.init then
G.init({securefs=D,users=B,log=Z,serialize=require(ar)})_G._TOS.profile=G;Z.info(_,"Profile module ready")end;local I,F=pcall(require,"kernel.i18n")
if I and F and F.init then
F.init({fs=ad,log=Z,serialize=require(ar),config=_G._TOS.config})_G._TOS.i18n=F;if F.language()~="en"then
Z.info(_,"Language: "..F.language())end end
k("backup","kernel.backup",function()return{securefs=D,fs=ad,crypto=z,log=Z}end)
k("keychain","kernel.keychain",function()
return{securefs=D,users=B,log=Z,serialize=require(ar)}end)if af then
af.interval(300,function()B.sweepSessions()end,"kernel:session_sweep")end else
Z.warn(_,"SecureFS not available: "..tostring(D))end else
Z.warn(_,"User system not available: "..tostring(B))end else
Z.warn(_,"Crypto not available: "..tostring(z))end else
Z.warn(_,"Skipping security (low memory: "..
math.floor(ab.freeMemory()/1024)..aH)end end;c("9b theme manager")
if ac and ac.isMonochrome and
not ac.isMonochrome()and f("theme",i())then
local A,z=pcall(require,"kernel.theme")
if A then
z.init({display=ac,securefs=_G._TOS.securefs,log=Z})_G._TOS.theme=z
Z.info(_,"Theme manager ready ("..#z.list().." presets)")else
Z.warn(_,"Theme module not available: "..tostring(z))end end;c("10 network")
if
(ag.has("modem")or ag.has("tunnel"))and f("net",i())then
local A,z=pcall(require,"kernel.net")
if A then local B=pcall(z.init,{log=Z,config=b,event=af,fs=ad})
if B then
_G._TOS.net=z
Z.info(_,"Network ready (".. (z.getHostname())..")")local D,C=pcall(require,"kernel.net.aliases")
if D and C and C.init then
C.init({fs=ad,securefs=_G._TOS.securefs,users=_G._TOS.users,log=Z,serialize=require(ar)})_G._TOS.net.aliases=C;Z.info(_,"Peer aliases ready")end else Z.warn(_,"Network init failed")end else
Z.warn(_,"Network module not available: "..tostring(z))end else
if
not(ag.has("modem")or ag.has("tunnel"))then Z.info(_,"No network hardware - skipping")elseif i()then
Z.warn(_,"Skipping network (boot profile)")else
Z.warn(_,"Skipping network (low memory: "..
math.floor(ab.freeMemory()/1024)..aH)end end;c("11 startup services and compatibility")
if
f("services",i())then local A,z=pcall(require,av)
if A then z.init({fs=ad,log=Z,proc=aa})
z.runAll()_G._TOS.rc=z;Z.info(_,"Startup services loaded")if af then
af.interval(30,function()
z.supervise()end,"kernel:rc_supervise")end end else
Z.warn(_,"Startup services skipped (boot profile)")end
if f("cron",i())then
if ad.exists("/etc/cron.dat")then local A,z=pcall(require,aM)
if A then
z.init({fs=ad,log=Z,event=af})_G._TOS.cron=z;Z.info(_,"Cron scheduler initialized")end else k("cron",aM)end else _G._TOS.cronDisabled=true
Z.warn(_,"Cron scheduler skipped (boot profile)")end
do if not f("packages",true)then _G._TOS.pkgDispatchDisabled=true
Z.warn(_,"Package command dispatch disabled (boot profile)")end
k("pkg","kernel.pkg")end;if af then
af.interval(30,function()pcall(Z.flush)end,"kernel:log_flush")end
if not f("compat",true)then
_G._TOS.compatDisabled=true;Z.warn(_,"OpenOS compat disabled (boot profile)")else
Z.info(_,"OpenOS compat: lazy (loads on first use)")end;c("12 audio feedback system")
if f("audio",true)then
local A,z=pcall(require,"kernel.audio")
if A then z.init(b)_G._TOS.audio=z
Z.info(_,"Audio feedback: ".. (z.isEnabled()and"enabled"or
"disabled"))else Z.info(_,"Audio module not available")end end;function ae.gc()
if type(collectgarbage)==ak then return pcall(collectgarbage,an)end;return false end
_G._TOS.fs=ad;_G._TOS.kernel=ae;_G._TOS.proc=aa;_G._TOS.event=af
c("13 boot complete")if type(collectgarbage)==ak then
pcall(collectgarbage,"setpause",120)end
local l=
(ag and ag.freeMemory and ag.freeMemory())or ab.freeMemory()local u=ab.uptime()-_G._TOS.bootTime
if j then
_G._TOS.bootMem=j
for A,z in ipairs(j)do local B=j[A+1]
Z.info("memprofile",B and
string.format("%-36s used %4dK, %5dK free after",z.stage,math.floor((z.free-
B.free)/1024),math.floor(B.free/1024))or string.format("%-36s %5dK free",z.stage,math.floor(
z.free/1024)))end end
Z.info(_,"Boot complete! Free memory: "..math.floor(l/1024).."KB")
Z.info(_,string.format("Boot time: %.1fs",u))pcall(ae.checkLastCrash)if l<20480 then
Z.warn(_,"LOW MEMORY: "..math.floor(l/1024)..
"KB free!")end
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
Z.warn(_,"self-test disk at "..tostring(B)..
" ignored: this machine is not armed (create /etc/selftest.on)")
d("  Self-test disk ignored: create /etc/selftest.on to allow it",0xFFFF00)end
if A and z then
Z.info(_,"selftest marker present - running boot battery")d("  Running self-test battery...",0xFFFF00)
pcall(z.init,{fs=_G._TOS.fs,computer=ab,log=Z})local D,C=pcall(z.run,{fs=_G._TOS.fs,computer=ab})
if D and
C then
d(string.format("  Self-test: %d passed, %d failed, %d skipped",C.pass,C.fail,C.skip),
C.fail>0 and 0xFF0000 or 0x00FF00)else
Z.error(_,"selftest battery errored: "..tostring(C))
d("  Self-test ERRORED (see /var/selftest.log)",0xFF0000)end end end
if not p then local z=0
if b then z=tonumber(b.get("bootPause"))or
(b.get("verbose")and 1.5 or 0)end;if z>0 then ab.pullSignal(z)end end;Z.detachEarlyPrint()
c("14 login -> shell / headless loop")ae.boot=nil
if p then ae.headlessMain()else ae.loginAndStartShell()end end
local function aU(a,c,b)local d=a.getTheme()a.clear(d.bg)
a.set(2,2,"Not enough memory for TOS to start.",d.error,d.bg)
a.set(2,4,"The user system did not fit, so nobody",d.fg,d.bg)
a.set(2,5,"can log in. TOS needs at least 1 MB",d.fg,d.bg)a.set(2,6,"(one Tier 3.5 memory stick).",d.fg,d.bg)
a.set(2,8,"Add memory, then power on again.",d.dim,d.bg)
a.set(2,10,"Press any key to power off.",d.dim,d.bg)if b then pcall(b)end;repeat until c(math.huge)==aj end
local function aV(b,c,d,e,a)local f=c.getUser and c.getUser("root")if not
(f and f.firstBoot)then return nil end
local function g(h,i)
b.fill(2,h,e-3,1," ",a.fg,a.bg)b.set(2,h,i,a.dim,a.bg)local k,j=2+#i,""
while true do
b.set(k,h,string.rep("*",#j).."_ ",a.fg,a.bg)local n,o,l,m=d(0.5)
if n==aj then
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
function ae.loginAndStartShell()ai=true;local a=_G._TOS.users;local n=_G._TOS.securefs
local l=ab.freeMemory()local function h()
if type(collectgarbage)==ak then pcall(collectgarbage,an)end end
local function j()local p,x=ac.getSize()
local o=ac.getTheme()ac.clear(o.bg)
ac.set(2,2,"TOS - Authentication Required",o.title,o.bg)
if not a then
aU(ac,ab.pullSignal,function()if _G._TOS.audio then _G._TOS.audio.critical()else
ab.beep(400,0.5)end end)ae.shutdown()return nil end;local u=aV(ac,a,ab.pullSignal,p,o)if u then return u end
ac.set(2,3,"Low memory mode. Enter root password.",o.dim,o.bg)ac.set(2,5,"Password: ",o.dim,o.bg)local s="/var/lockout.dat"
local function w()
local y,z=pcall(require,aN)local ad=(y and z)or nil;if not ad or not ad.exists or
not ad.exists(s)then return 0 end
local A=ad.readFile(s)local B=tonumber(A or"")or 0;return B end
local function v(y)local z,A=pcall(require,aN)local ad=(z and A)or nil;if not ad or
not ad.writeFile then return end
if
ad.exists and not ad.exists("/var")and ad.makeDirectory then ad.makeDirectory("/var")end;pcall(ad.writeFile,s,tostring(y))end;local q=ab.uptime()local r=w()
if r>0 and r>q and(r-q)<3600 then local y=r-q
ac.set(2,4,string.format("Locked: wait %ds before retrying.",math.ceil(y)),o.error,o.bg)local z=q+y;while ab.uptime()<z do
ab.pullSignal(math.min(1,z-ab.uptime()))end
ac.fill(2,4,p-3,1," ",o.fg,o.bg)end;local t=5
for y=1,t do ac.fill(12,5,p-13,1," ",o.fg,o.bg)local z=""
while true do
ac.set(12,5,string.rep("*",
#z).."_ ",o.fg,o.bg)local F,G,D,E=ab.pullSignal(0.5)if F==aj then
if E==28 then break elseif E==14 then
if#z>0 then z=z:sub(1,-2)end elseif D and D>=32 and D<127 then z=z..string.char(D)end end end;local B=a.login("root",z,{setCurrent=true})
if B then v(0)
ac.set(2,7,"Access granted.",o.success,o.bg)ab.pullSignal(0.5)return B end;local A=2^y;if Z then
Z.warn("auth",string.format("minimalAuth: bad root password (attempt %d/%d), backoff %ds",y,t,A))end;local C=t-y
if C>0 then
ac.set(2,7,string.format("Wrong password. Wait %ds. (%d attempts left)",A,C),o.error,o.bg)ac.fill(12,5,p-13,1," ",o.fg,o.bg)
local D=ab.uptime()+A;while ab.uptime()<D do
ab.pullSignal(math.min(1,D-ab.uptime()))end
ac.fill(2,7,p-3,1," ",o.fg,o.bg)end end;v(ab.uptime()+60)
ac.set(2,7,"Too many attempts. Rebooting (locked 60s)...",o.error,o.bg)if _G._TOS.audio then _G._TOS.audio.critical()else
ab.beep(400,0.5)end;ab.pullSignal(3)
ae.reboot()return nil end;local e=nil;local i=false
if l<32768 then
Z.warn(_,"Low memory - using minimal auth")i=true else local p,o=pcall(require,"shell.login")if p then e=o else
Z.warn(_,"Login module not available: "..
tostring(o))i=true end end;local g=nil;do local p,o=pcall(require,"shell.init")
if p then g=o else Z.error(_,"Shell module failed: "..
tostring(o))end end
local d=require(aw)
local m={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,[ap]=true,["load"]=true,["net"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true,["peripheral.printer"]=true,["peripheral.modem"]=true,["peripheral.tractor"]=true,["peripheral.piston"]=true,["peripheral.hologram"]=true}local c={}local b={}local k
local function f(o)local q=d.displayProxy(o)if not q then return nil end
local r=a and
a.loginSession and a.loginSession(o)or nil
local p=aa.spawn("login@"..o,function()local s=nil
if i then s=j()elseif e then local u=e.new and e.new()or e
local v,t,w=pcall(u.run,{display=q,event=af,users=a,proc=aa,log=Z})
if v then
if w=="shutdown"then
Z.info(_,"Operator chose shutdown at the login screen (display "..o..")")
if ae and ae.shutdown then ae.shutdown()else ab.shutdown(false)end;return end;s=t else
Z.error(_,"Login error on display "..o..": "..tostring(t))s=j()end end;if s then c[o]=s;b[o]=k(o,s)_G._TOS.shellPIDs=b end end,{display=o,priority=2,source=_,principal=r})if p then pcall(aa.setForeground,p,o)end;return p end
k=function(o,p)local q=d.displayProxy(o)if not q or not g then return nil end;local r=nil;if p and
a then r=a.getSession(p)end
if not r then if Z then
Z.error(_,"Refusing to spawn shell on display "..
tostring(o)..": no valid session token")end;return nil end;local s=r.user or"?"
if
_G._TOS.theme and _G._TOS.theme.applyForUser then pcall(_G._TOS.theme.applyForUser,r)end
if _G._TOS.profile and _G._TOS.profile.load and
_G._TOS.profile.apply then
pcall(function()
local y=_G._TOS.profile.load(r)local z=_G._TOS.profile.apply(y,{session=r})
r.startupCommands=z end)end
local v=setmetatable({display=q,displayIdx=o,getDisplay=function()return q end,getDisplayIdx=function()return o end},{__index=ae})
Z.info(_,"Seat "..o..": shell for "..s)local t=g.run
if s=="kiosk"then local z,y=pcall(require,"shell.kiosk")if
z and y and y.run then t=y.run
Z.info(_,"Seat "..o..": KIOSK mode")end end;h()
Z.info(_,string.format("Seat %d: loading shell (%dKB free)",o,math.floor(ab.freeMemory()/1024)))
local u=aa.spawn("shell:"..s.."@"..o,function()local y,z=pcall(t,v,p)
if not y then local A=tostring(z)
h()
Z.error(_,"Shell crashed on display "..o..": "..A)
pcall(function()
if q then local C,D=q.getSize()local B=q.getTheme()
q.fill(1,2,C,3," ",B.fg,B.bg)q.set(2,2,"Shell crashed:",B.error,B.bg)
q.set(2,3,q.fit(A,C-2),B.dim,B.bg)ab.pullSignal(2)end end)end;af.push("tos_shell_exited",o)end,{priority=1,source=_,tsr=false,principal=r,token=p,cwd=
r and r.home or"/",caps=m,display=o})local w,x=aa.setForeground(u,o)if not w then
Z.error(_,"Seat "..
o..": foreground handoff FAILED ("..tostring(x)..
") — input will not reach the shell")end;return u end
if g then _G._TOS.bootSession=nil;_G._TOS.bootCompleted=true;local r=d.count()
for u,t in
ipairs(d.indices())do local w=f(t)local v=d.get(t)
Z.info(_,string.format("Seat %d: gpu=%s screen=%s keyboards=%d login pid=%s",t,tostring(
v and v.gpu and v.gpu.address or"?"):sub(1,8),tostring(
v and v.screen or"?"):sub(1,8),(
v and v.keyboards and#v.keyboards)or 0,tostring(
w or"FAILED")))end;_G._TOS.shellPIDs=b;if r>1 then
Z.info(_,"Multi-seat: "..r.." displays active")end;local q={}local s=0;local o={}local p=0
while ai do
local t=table.pack(af.pull(0.1))if t[1]=="tos_shutdown"then ai=false;break end
if t[1]=="tos_logout"then
local u=t[2]
if not u then local w,v=nil,0;for x in pairs(b)do v=v+1;w=x end
if v==1 then u=w
Z.warn(_,
"tos_logout without a seat index — assuming seat "..w)else
Z.warn(_,"tos_logout without a seat index ignored ("..v.." seats live)")end end
if u then
if b[u]then aa.kill(b[u],{kernel=true})b[u]=nil end;if a and c[u]then a.logout(c[u])c[u]=nil end;Z.info(_,"Seat "..u..
": logged out")f(u)p=0 end;t=table.pack(nil)end
if t[1]=="tos_shell_exited"then local u=t[2]
if u and not b[u]then elseif u then b[u]=nil;if a and c[u]then
a.logout(c[u])c[u]=nil end
Z.info(_,"Seat "..u..": shell exited, respawning login")f(u)end;p=0;t=table.pack(nil)end
if t[1]==aj then local u=ab.uptime()
if u-s>1 then s=u
local v=package.loaded and package.loaded[au]if v and v.addEntropy then
pcall(v.addEntropy,tostring(u)..
"|"..tostring(ab.freeMemory()))end end end
if t[1]==aj and t[3]==3 then local u=1;if d.displayForKeyboard then
u=d.displayForKeyboard(t[2])or 1 end;local v=aa.getForeground(u)
local w=ab.uptime()
if v then
if q[u]and(w-q[u])<1.5 then aa.kill(v,{kernel=true})
q[u]=nil
Z.warn(_,aI..v.." via double Ctrl+C on display "..u)else aa.signal(v,"tos_interrupt")q[u]=w end end;t=table.pack(nil)end
if t[1]==aj and t[3]==20 then local u=1;if d.displayForKeyboard then
u=d.displayForKeyboard(t[2])or 1 end;local v=as[u]
local w=v and aa.get and aa.get(v)
if w and w.state~=aa.STATE.DEAD and b[u]==v then
aa.setForeground(v,u,{kernel=true});(aa.signalKernel or aa.signal)(v,"tos_monitor")t=table.pack(
nil)else local x=o[u]
local y=x and aa.get and aa.get(x)
if y and y.state~=aa.STATE.DEAD then t=table.pack(nil)else local B=nil;if a and
c[u]then B=a.getSession(c[u])end;local C=c[u]local z=b[u]
local A
A=aa.spawn("monitor@"..u,function()
local D=ae.taskSwitcher(u,B,{pull=function()return coroutine.yield()end,fgPID=z,selfPid=A})o[u]=nil
if not(D and aa.get and aa.get(D))then if
z and aa.get and aa.get(z)then

aa.setForeground(z,u,{kernel=true});(aa.signalKernel or aa.signal)(z,ax)end end end,{priority=2,source=_,principal=B,token=C,display=u})o[u]=A;aa.setForeground(A,u,{kernel=true})
t=table.pack(nil)end end end
if t[1]==aj and t[3]==2 then local u=1;if d.displayForKeyboard then
u=d.displayForKeyboard(t[2])or 1 end;local w=aa.getForeground(u)local v=b[u]
if
w and v and w~=v then local x=aa.get and aa.get(v)
if x and
x.state~=aa.STATE.DEAD then aa.setForeground(v,u,{kernel=true});(
aa.signalKernel or aa.signal)(v,ax)
Z.info(_,
"Backgrounded PID "..tostring(w).." on display "..u.." (Ctrl+B)")end end;t=table.pack(nil)end
if t[1]==aS then local u,v=d.rebuild()
for x,w in ipairs(v)do if b[w]then
aa.kill(b[w],{kernel=true})b[w]=nil end;if o[w]then
aa.kill(o[w],{kernel=true})o[w]=nil end;if as[w]then as[w]=nil end;if c[w]then if a then
a.logout(c[w])end;c[w]=nil end
Z.warn(aA,"Display "..w.." removed")end;for x,w in ipairs(u)do f(w)
Z.info(aA,"Display "..w.." added, spawning login")end;t=table.pack(nil)end;aa.tick(t.n>0 and t or nil)
if aa.count()==0 then
Z.warn(_,"All processes terminated")for w,v in pairs(c)do if a then a.logout(v)end end;for v in pairs(c)do
c[v]=nil end;for v in pairs(b)do b[v]=nil end;h()local u=
(d.count and d.count())or 0
if ai and u>0 then p=p+1
if p<=3 and
ab.freeMemory()>=64*1024 then
Z.warn(_,string.format("Unexpected shell exit — recovering login on %d seat(s) [try %d/3, %dKB free]",u,p,math.floor(
ab.freeMemory()/1024)))for w,v in ipairs(d.indices())do f(v)end else
Z.error(_,string.format("Shell unrecoverable (%dKB free after GC) — dropping to emergency shell",math.floor(
ab.freeMemory()/1024)))
pcall(ae.crashDump,string.format("shell unrecoverable (%dKB free after GC)",math.floor(ab.freeMemory()/1024)))ae.emergencyShell()break end else break end end end else ae.emergencyShell()ai=false end;ae.shutdown()end
function ae.crashWriteRaw(b,c,d,a)local f,h,i
pcall(function()f=ab.getBootAddress()end)
pcall(function()h=ab.tmpAddress()end)pcall(function()i=ab.address()end)
local g,j={},{}local function k(m)
if type(m)==al and m~=h and not j[m]then j[m]=true;g[#g+1]=m end end;k(f)pcall(function()
for m in ah.list(aq)do k(m)end end)local function e(n,o,...)return
pcall(ah.invoke,n,o,...)end
local function l(m,n,o)local r,p=e(m,"open",n,"w")if
not r or not p then return false end;local s,q,t=e(m,"write",p,o)
e(m,"close",p)
return s and q~=false and not(q==nil and t~=nil)end
for n,m in ipairs(g)do local o,p=e(m,"isReadOnly")
if o and p==false then local q=(m==f)
e(m,"makeDirectory",aG)if l(m,"/var/crash/"..b,q and c or d)then
l(m,"/var/crash/NEW",q and a or(a..
"\nmachine "..tostring(i)))return m,q end end end;return nil end
function ae.crashDump(a,b)local ad=_G._TOS and _G._TOS.fs;local f=math.floor(
(ab.uptime and ab.uptime())or 0)
local m=math.floor(
((
ab.freeMemory and ab.freeMemory())or 0)/1024)
local n=math.floor(
((ab.totalMemory and ab.totalMemory())or 0)/1024)
local c={"=== TOS CRASH REPORT ===","reason : "..tostring(a or"unknown"),"uptime : "..f.."s",
"memory : "..m.."KB free / "..n.."KB"}if b then c[#c+1]="detail :"for q in tostring(b):gmatch("[^\n]+")do
c[#c+1]="  "..q end end;local o=
table.concat(c,"\n").."\n"c[#c+1]=""
c[#c+1]="--- recent log ---"local g,d=pcall(require,aO)
if g and d and d.recent then
local r,q=pcall(d.recent,40)
if r and type(q)=="table"then for t,s in ipairs(q)do
c[#c+1]=string.format("[%8.1f][%s] %s",
tonumber(s.time)or 0,tostring(s.source or"?"),tostring(s.msg or""))end end end;local h="crash-"..f..".txt"local e="/var/crash/"..h;local i=
table.concat(c,"\n").."\n"local j=tostring(a or"unknown")..
" @ uptime "..f.."s"local k=false;if
ad and ad.writeFile then local q,r=pcall(ad.writeFile,e,i)
k=q and r and true or false end
if k then
pcall(ad.writeFile,"/var/crash/NEW",j)if g and d and d.warn then
pcall(d.warn,_,"Crash report saved: "..e)end;return e end;local l,p=ae.crashWriteRaw(h,i,o,j)if not l then return false end
if p then return e end;return e.." on disk "..l:sub(1,8)end
function ae.checkLastCrash()local ad=_G._TOS and _G._TOS.fs;if
not(ad and ad.exists)then return end;local a={aG}
if ad.mounts then local f,e=pcall(ad.mounts)
if f and type(e)==
"table"then
for h,g in ipairs(e)do
local i,j=pcall(ah.type,type(g)=="table"and g.address)if
i and j==aq and type(g.mountPoint)==al and g.mountPoint~="/"then
a[#a+1]=(g.mountPoint:gsub("/+$",""))..aG end end end end;local c;pcall(function()c=ab.address()end)
local d,b=pcall(require,aO)
for e,f in ipairs(a)do local g=f.."/NEW"
if ad.exists(g)then local h=""
if ad.readFile then
local k,j=pcall(ad.readFile,g)if k and type(j)==al then h=j end end;local i=h:match("\nmachine (%S+)")
if
e==1 or(i~=nil and i==c)then
local j=(h:match(aK)or""):gsub("%s+$","")if j==""then j="a previous run"end;if d and b and b.warn then
b.warn(_,"Last run crashed: "..j..

" — see "..f.. (e==1 and" (`crash`)"or""))end;if ad.remove then
pcall(ad.remove,g)end end end end end
function ae.monitorSnapshot(b,a)if not aa then return{rows={}}end;local e=require(aB)
local j=a and a.user or nil;local g=(a and a.tier)or 0;local c=aa.list()if b then local l={}
for n,m in ipairs(c)do if not
m.display or m.display==b then l[#l+1]=m end end;c=l end
if a and g<2 then local l={}for n,m in
ipairs(c)do
if not m.user or m.user==j or m.user==ay then l[#l+1]=m end end;c=l end;local h={}if g>=2 then local m,l=pcall(require,av)
if m and l and l.list then
local o,n=pcall(l.list)if o and type(n)=="table"then h=n end end end
local i=(
ab.freeMemory and ab.freeMemory())or 0
local d=(ab.totalMemory and ab.totalMemory())or 0
local k=(ab.uptime and ab.uptime())or 0
local f={{text=string.format("Uptime %s   RAM %dK/%dK [%s]   Processes %d",e.fmtUptime(k),math.floor((d-i)/1024),math.floor(
d/1024),e.memBar(d-i,d,12),#c),tone="vitals"},{text="",tone="dim"}}for m,l in ipairs(e.textRows(c,h))do f[#f+1]=l end
return{rows=f}end
function ae.setMonitorHost(a)if not aa then return false end
local b=aa.current and aa.current()
if not(b and b.display and b.pid)then return false end;local c=_G._TOS and _G._TOS.shellPIDs;if not
(c and c[b.display]==b.pid)then return false end;as[b.display]=
(a~=false)and b.pid or nil;return true end
function ae.isForeground()if not aa then return true end
local a=aa.current and aa.current()if not a then return true end
return aa.getForeground(a.display)==a.pid end
function ae.monitorList(a,b)if not aa then return{rows={},vitals=nil}end
local e=require(aB)local j=b and b.user or nil;local f=(b and b.tier)or 0;local k=a and
aa.getForeground(a)or nil;local d=aa.list()
if a then local m={}for o,n in
ipairs(d)do
if not n.display or n.display==a then m[#m+1]=n end end;d=m end;if b and f<2 then local m={}
for o,n in ipairs(d)do if
not n.user or n.user==j or n.user==ay then m[#m+1]=n end end;d=m end;local h={}
if f>=2 then
local n,m=pcall(require,av)if n and m and m.list then local p,o=pcall(m.list)
if p and type(o)=="table"then h=o end end end;local c={}
for n,m in ipairs(d)do
c[#c+1]={kind="proc",pid=m.pid,label=e.describe(m),owner=m.user or _,state=m.tsr and"TSR"or
(m.state or""),tsr=m.tsr or false,cpu=m.cpuTime or 0,isFg=(m.pid==k),canAct=e.canAct(f,j,a,m)}end
if#h>0 then c[#c+1]={kind=aL,text="Services"}for n,m in ipairs(h)do
c[#c+1]={kind="svc",name=m.name,running=m.running or
false,enabled=m.enabled~=false,canAct=f>=2,status=e.svcStatus(m)}end end
local i=(ab.freeMemory and ab.freeMemory())or 0
local g=(ab.totalMemory and ab.totalMemory())or 0
local l=string.format("up %s  ·  mem [%s] %dK/%dK free %dK  ·  %d proc",e.fmtUptime(
(ab.uptime and ab.uptime())or 0),e.memBar(g-i,g,12),math.floor((g-i)/1024),math.floor(
g/1024),math.floor(i/1024),#d)return{rows=c,vitals=l}end
function ae.monitorAct(a,b)if not aa then return false,"scheduler unavailable"end;local d=
aa.current and aa.current()if not d then
return false,"no calling process"end;local e=d.display;local f=d.principal
local g=f and f.user or nil;local h=(f and f.tier)or 0;local j=require(aB)
if a=="svc"then if h<2 then return false,
"admin only"end;local o,l=pcall(require,av)if not
(o and l and l.list)then return false,"rc unavailable"end
local m=nil;local p,n=pcall(l.list)if p and type(n)=="table"then for u,t in ipairs(n)do
if t.name==b then m=t;break end end end;if not
m then return false,"no such service"end
local q,r=j.svcToggle(l,m,g)if not q then return false,r end;return true end;local c=aa.get(tonumber(b)or-1)
if not c or
c.state==aa.STATE.DEAD then return false,"no such process"end
if e and c.display and c.display~=e then return false,"not on this seat"end
local i=c.principal and c.principal.user or nil
if f and h<2 and i~=nil and i~=g and i~=ay then return false,aR end;local k={pid=c.pid,user=i,display=c.display}
if a=="switch"then if c.pid==d.pid then return false,
"already in front"end
aa.setForeground(c.pid,e,{kernel=true});(aa.signalKernel or aa.signal)(c.pid,ax)
Z.info(_,
"Switched to PID "..
c.pid.." ("..tostring(c.name)..") from monitor tab")return true elseif a=="kill"then
if c.pid==d.pid then return false,"Refused: PID "..
c.pid.." is the shell this Monitor runs in"end;if not j.canAct(h,g,e,k)then return false,aR end
aa.kill(c.pid,{kernel=true})
Z.warn(_,aI..c.pid.." ("..
tostring(c.name)..") from monitor by "..tostring(g or _))return true elseif a=="tsr"then
if c.pid==d.pid then return false,"Refused: PID "..
c.pid.." is the shell this Monitor runs in"end;if not j.canAct(h,g,e,k)then return false,aR end;if c.tsr then c.tsr=false
c.state=aa.STATE.READY else aa.goTSR(c.pid)end;return true end;return false,"unknown action"end
function ae.taskSwitcher(a,c,b)b=b or{}local C=b.pull~=nil;local D=b.pull or
function()return ab.pullSignal(0.5)end;local E=b.selfPid
local F=require(aw)local e=a and F.displayProxy(a)or ac;if
not e or not aa then return end;local N=_G._TOS.users
local s=c and c.user or nil;local t=c and c.tier or 0;local j=require(aB)
local y,p=pcall(require,av)local G,I=e.getSize()local d=e.getTheme()
local function J()local H=aa.list()if a then local O={}
for Q,P in ipairs(H)do if

P.pid~=E and(not P.display or P.display==a)then O[#O+1]=P end end;H=O end
if c and t<2 then
local O={}for Q,P in ipairs(H)do if not P.user or P.user==s or P.user==ay then
O[#O+1]=P end end;H=O end;return H end
local function K()
if t<2 or not(y and p and p.list)then return{}end;local O,H=pcall(p.list)return
(O and type(H)=="table")and H or{}end;local function z(H)return j.canAct(t,s,a,H)end;local i,m=1,1;local h,q=G,I;local w=math.max(20,h-2-
30)
local A=math.max(12,math.min(28,h-2-4-34))local L=m+4;local n=math.max(1,q-6)
local u=b.fgPID or aa.getForeground(a)local x=nil;local v=nil;local g={}local f=1;local k=0
local function o()if#g==0 then k=0;return end;if f<=k then k=f-1 end;if f>
k+n then k=f-n end;local H=math.max(0,#g-n)if k>H then k=H end
if k<0 then k=0 end end
local function r()g=j.buildRows(J(),K())if#g==0 then return false end
if f>#g then f=#g end;if f<1 or(g[f]and g[f].kind==aL)then
f=j.firstSelectable(g)end;o()return true end;if not r()then return end;for O,H in ipairs(g)do if H.kind=="proc"and H.p.pid==u then f=O;o()
break end end;local function M()
e.dbox(i,m,h,q,"System Monitor",{border=d.border,bg=d.panel_bg,title=d.title})end
local function l()
local H=ab.totalMemory()or 0;local Q=ab.freeMemory()or 0;local R=H-Q;local O=0;for W,V in ipairs(g)do if V.kind=="proc"then
O=O+1 end end
local T=string.format(" up %s  ·  mem [%s] %dK/%dK free %dK  ·  %d proc",j.fmtUptime(ab.uptime()),j.memBar(R,H,12),math.floor(
R/1024),math.floor(H/1024),math.floor(Q/1024),O)e.set(i+1,m+1,e.fit(T,h-2),d.fg,d.panel_bg)e.fill(i+
1,m+2,h-2,1," ",d.fg,d.panel_bg)
local U=string.format(" %-4s %-"..w..
"s %-8s %-7s %5s","PID","Process","Owner","State","CPU")e.set(i+1,m+3,e.fit(U,h-2),d.dim,d.panel_bg)
for V=1,n do
local X=k+V;local W=L+V-1
if X<=#g then local Y=g[X]local aX=(X==f)
if Y.kind==aL then local aY=h-2
local a_=4+#Y.text+1;local aZ
if a_<=aY then aZ=" ── "..
Y.text.." "..string.rep("─",aY-a_)else aZ=" ── "..
Y.text:sub(1,math.max(0,aY-5)).." "end;e.set(i+1,W,aZ,d.title,d.panel_bg)elseif Y.kind=="proc"then local aY=Y.p;local a_=(
aY.pid==u)and"*"or" "local ba=aY.tsr and"TSR"or
(aY.state or""):sub(1,7)
local bb=(aY.user or _):sub(1,8)
local aZ=string.format("%s%-4d %-"..w.."s %-8s %-7s %4.1fs",a_,aY.pid,j.describe(aY):sub(1,w),bb,ba,
aY.cpuTime or 0)
if aX then e.set(i+1,W,e.fit(aZ,h-2),d.sel_fg,d.sel_bg)else
local bc=d.fg;if aY.tsr then bc=d.dim elseif aY.pid==u then bc=d.highlight end;e.set(i+1,W,e.fit(aZ,
h-2),bc,d.panel_bg)end else local aY=Y.s
local aZ=string.format("   %-"..A.."s %s",(aY.name or"?"):sub(1,A),j.svcStatus(aY))if aX then e.set(i+1,W,e.fit(aZ,h-2),d.sel_fg,d.sel_bg)else
e.set(
i+1,W,e.fit(aZ,h-2),aY.running and d.highlight or d.dim,d.panel_bg)end end else e.fill(i+1,W,h-2,1," ",d.fg,d.panel_bg)end end;local S=g[f]local P
if S and S.kind=="svc"then
P=" [Enter/S] start-stop   up/down move   [^Q] close"else P=" [Enter] switch  [K]ill  [T]SR   up/down move   [^Q] close"end
if v then e.fill(i+1,m+q-2,h-2,1," ",d.fg,d.panel_bg)
e.set(i+1,
m+q-2,e.fit(" "..v,h-2),d.error or d.fg,d.panel_bg)else
e.set(i+1,m+q-2,e.fit(P,h-2),d.dim,d.panel_bg)end end;M()l()
while true do local P,Q,H,O=D()
if P==aj then v=nil
if H==17 or H==113 then break elseif O==200 then
f=j.nextSelectable(g,f,-1)o()l()elseif O==208 then f=j.nextSelectable(g,f,1)o()l()elseif O==201 then for Q=1,n do
f=j.nextSelectable(g,f,-1)end;o()l()elseif O==209 then
for Q=1,n do f=j.nextSelectable(g,f,1)end;o()l()else local R=g[f]
if R and R.kind=="proc"then local S=R.p
if O==28 then
aa.setForeground(S.pid,a,{kernel=true});(aa.signalKernel or aa.signal)(S.pid,ax)
Z.info(_,
"Switched to PID "..S.pid.." ("..tostring(S.name)..")")x=S.pid;break elseif H==107 or H==75 then
if S.pid~=u and z(S)then
aa.kill(S.pid,{kernel=true})
Z.warn(_,aI..S.pid.." ("..
tostring(S.name)..") from monitor by "..tostring(s or _))if not r()then break end;l()end elseif H==116 or H==84 then if z(S)then local T=aa.get(S.pid)
if T then if T.tsr then T.tsr=false
T.state=aa.STATE.READY else aa.goTSR(S.pid)end;r()l()end end end elseif R and R.kind=="svc"then if O==28 or H==115 or H==83 then
if t>=2 and y and p then
local S,T=j.svcToggle(p,R.s,s)v=(not S)and T or nil;r()l()end end end end elseif P==nil then r()l()end end;if C then return x end;local B=aa.getForeground(a)if B then
(aa.signalKernel or aa.signal)(B,ax)end;return x end
function ae.emergencyShell()if not ac then return end;local g=_G._TOS.users;local h,q=ac.getSize()
local c=ac.getTheme()ac.clear(c.bg)
ac.set(2,2,"TOS EMERGENCY - Auth Required",c.error,c.bg)
if not g then
ac.set(2,3,"User system unavailable - cannot authenticate.",c.error,c.bg)ac.set(2,4,"Rebooting...",c.dim,c.bg)
ab.pullSignal(3)ae.reboot()return end;ac.set(2,3,"Password: ",c.dim,c.bg)local i=false
for r=1,3 do
ac.fill(12,3,h-13,1," ",c.fg,c.bg)local s=""
while true do
ac.set(12,3,string.rep("*",#s).."_ ",c.fg,c.bg)local w,x,u,v=ab.pullSignal(0.5)if w==aj then
if v==28 then break elseif v==14 then
if#s>0 then s=s:sub(1,-2)end elseif u and u>=32 and u<127 then s=s..string.char(u)end end end;local t=g.login("root",s,{setCurrent=true})
if t then i=true;break end
if r<3 then
ac.set(2,5,"Wrong. ".. (3-r).." left.",c.error,c.bg)ab.pullSignal(1.5)ac.fill(2,5,h-3,1," ",c.fg,c.bg)end end;if not i then ac.set(2,5,"Locked. Rebooting...",c.error,c.bg)
ab.pullSignal(3)ae.reboot()return end
local e,j=ac.getSize()local a=ac.getTheme()local f={}local k=0;local l=3;local m=j-l-1
local function o()ac.clear(a.bg)
ac.set(2,1,"TOS EMERGENCY SHELL",a.error,a.bg)
ac.set(2,2,"Main shell could not load.",a.warning,a.bg)ac.set(2,3,"'help' for list.",a.dim,a.bg)
local r=#f-m-k+1;if r<1 then r=1 end
for s=1,m do local t=r+s-1;local u=l+s
if t>=1 and t<=#f then local v=f[t]
ac.fill(1,u,e,1," ",a.fg,a.bg)
ac.set(1,u,v[1]:sub(1,e),v[2]or a.dim,a.bg)else ac.fill(1,u,e,1," ",a.fg,a.bg)end end end
local function b(r,s)f[#f+1]={tostring(r),s or a.dim}k=0;o()end
local function p()local s=j;ac.fill(1,s,e,1," ",a.fg,a.bg)
ac.set(1,s,"> ",a.prompt,a.bg)local r=""
while true do ac.fill(3,s,e-3,1," ",a.fg,a.bg)
ac.set(3,s,r,a.fg,a.bg)ac.set(3+#r,s,"_",a.prompt,a.bg)
local v,w,t,u=ab.pullSignal(0.5)if v==aj then
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
u=ab.getBootAddress()end)local v=false
for w in
ah.list(aq)do v=true
local function x(B)local C,D=pcall(ah.invoke,w,B)if C then return D end end;local y,z=x("spaceTotal"),x("spaceUsed")local A=x("getLabel")
b(string.format("  %s %-12s %8s used of %8s%s%s",w:sub(1,8),tostring(
A or""):gsub("%c","?"):sub(1,12),
z and(math.floor(z/1024).."K")or"?",
y and(math.floor(y/1024).."K")or"?",
x("isReadOnly")and"  read-only"or"",w==u and"  (boot)"or""))end
if not v then b("No filesystems found.",a.error)end elseif s=="log"then
local v=math.max(1,math.min(tonumber(r[2])or 20,200))
local w,u=pcall(function()return Z.recent(v)end)
if w and type(u)=="table"and#u>0 then for y,x in ipairs(u)do
b(string.format("[%7.1f][%s] %s",
tonumber(x.time)or 0,tostring(x.source or"?"),tostring(x.msg or"")))end else
local y,x=pcall(ad.readFile,"/var/log/kernel.log")
if y and type(x)==al and x~=""then local z={}
for A in x:gmatch("[^\n]+")do
z[#z+1]=A;if#z>v then table.remove(z,1)end end;for B,A in ipairs(z)do b(A)end else
b("No log available (the ring and /var/log/kernel.log are both unreadable).",a.error)end end elseif s=="srm"then local u=(r[2]or"status"):lower()
local w,v=pcall(require,aP)
if not w or type(v)~="table"then
b("srm will not load: "..tostring(v),a.error)elseif u~="status"and u~="scan"and u~=ao then
b("Usage: srm [status | scan | repair [--restore]]",a.dim)else
local y,x=pcall(v[u],nil,{restore=r[3]=="--restore"})
if not y or type(x)~="table"then b("srm "..
u.." failed: "..tostring(x),a.error)else
for A,z in ipairs(
x.findings or{})do
b("  "..tostring(z.text),

(z.sev=="err"and a.error)or(z.sev=="warn"and a.warning)or(
z.sev=="ok"and a.success)or a.dim)end end end elseif s=="ls"then local v=r[2]or"/"local u;if d and d.list then u=d.list(v,n)else
local w,x=pcall(ad.list,v)if w then u=x end end
if u then if type(u)=="table"then for x,w in
ipairs(u)do b("  "..w)end elseif type(u)==ak then
for w in u do b("  "..w)end end else
b("Cannot list: "..v,a.error)end elseif s=="cat"then
if r[2]then local u;if d and d.readFile then u=d.readFile(r[2],n)else
u=ad.readFile(r[2])end
if u then
for v in u:gmatch("[^\n]*")do b(v)end else b("Cannot read: "..r[2],a.error)end end elseif s=="mem"then
b(string.format("Free: %dKB / Total: %dKB",math.floor(ab.freeMemory()/1024),math.floor(
ab.totalMemory()/1024)))elseif s=="verify"then ae.verifySystem(b)elseif s=="reboot"then ae.reboot()return elseif
s=="shutdown"then ae.shutdown()return elseif s~=""then b("Unknown: "..s,a.warning)end end end
function ae.verifySystem(a)a=a or function()end
local m=ac and ac.c("success")or 0xFFFFFF;local g=ac and ac.c("warning")or 0xFFFFFF;local d=ac and
ac.c("error")or 0xFFFFFF
local j=ac and ac.c("dim")or 0xFFFFFF;local l
do local p,o=pcall(require,"system_manifest")
if
p and type(o)=="table"then l=o else
l={{path="/init.lua",critical=true},{path="/tos/kernel/init.lua",critical=true},{path="/tos/shell/init.lua",critical=true}}
a("  WARN: system_manifest.lua not found, using minimal verify list",g)end end;local c,e,b=0,0,0;local h=0;local i=nil
do local o,p=pcall(require,au)if o then i=p end end;local k=0
local function n(o)local p=ad.open(o,"r")
if not p then return nil,nil,"unreadable"end;local r,s={},0
local u,v=pcall(function()while true do local y=p:read(4096)if y==nil then break end
if#y>0 then s=s+1;r[s]=y end end end)pcall(p.close,p)if not u then return nil,v,aC end;local q=0
local w,t,x=pcall(load,function()q=q+1
local y=r[q]r[q]=nil;return y end,"="..o,"t")if not w then return nil,t,aC end;return t,x,nil end
for p,o in ipairs(l)do
if ad.exists(o.path)then
do
if o.hash and i and i.hash then
if type(o.hash)~=al or
#o.hash~=64 or o.hash:find("[^%x]")then
a(at..
o.path.." (malformed hash in manifest)",g)b=b+1
if type(collectgarbage)==ak then pcall(collectgarbage,an)end;goto continue_verify end;local q=ad.readFile(o.path)if not q then a(at..o.path..aF,d)
b=b+1
if type(collectgarbage)==ak then pcall(collectgarbage,an)end;goto continue_verify end
local r=i.hash(q)q=nil
if not i.ctEquals(r,o.hash)then
a("  HASH "..o.path..
" (manifest="..o.hash:sub(1,12).." actual="..
r:sub(1,12)..")",d)k=k+1;b=b+1;if type(collectgarbage)==ak then
pcall(collectgarbage,an)end;goto continue_verify end end
if not o.path:match("%.lua$")then local r=false
local q=ad.open(o.path,"r")if q then
r=pcall(function()repeat local s=q:read(4096)until s==nil end)pcall(q.close,q)end;if r then a("  OK  "..
o.path,m)c=c+1 else a(at..o.path..aF,d)b=b+
1 end else local s,q,r=n(o.path)
if s then
a("  OK  "..o.path,m)c=c+1 elseif r=="unreadable"then a(at..o.path..aF,d)b=b+1 else local t;if r==aC then
t="OOM"else t="error"
if q then if q:find("memory")then t="low RAM"else t="syntax"end end end;a(at..
o.path.." ("..t..")",g)if r~=aC and q then
a("      "..tostring(q),j)end;b=b+1 end end end
if type(collectgarbage)==ak then pcall(collectgarbage,an)end else local q=o.critical and"MISS"or"GONE"
local r=o.critical and d or g
a("  "..q..
" "..o.path..
(o.critical and" (critical, not installed)"or" (not installed)"),r)e=e+1;if o.critical then h=h+1 end end::continue_verify::
if aa and aa.yieldCooperative then pcall(aa.yieldCooperative)end end;a("",j)local f=tostring(e)
if h>0 then
f=string.format("%d missing (%d CRITICAL)",e,h)else f=string.format("%d missing",e)end
if k>0 then
a(string.format("Result: %d OK, %s, %d damaged (incl. %d HASH MISMATCH)",c,f,b,k),d)elseif h>0 or b>0 then a(string.format(aJ,c,f,b),d)elseif e>0 then
a(string.format(aJ,c,f,b),g)
a("Missing files are absent, not corrupt — reinstall to restore them.",j)else a(string.format(aJ,c,f,b),j)end;return e==0 and b==0 end
local function aW()local a="/tos/system_manifest.lua"
if not ad.exists(a)then return nil,"manifest missing"end;return ad.readFile(a)end
function ae.computeManifestHash()local b,c=aW()if not b then return nil,c end
local d,a=pcall(require,au)
if not d or not a or not a.hash then return nil,"crypto unavailable"end;return a.hash(b)end
function ae.anchorManifestHash()local a,e=ae.computeManifestHash()
if not a then return false,e end;local ah=require(ap)local c=ah.list(az)()
if not c then return false,aQ end;local b=ah.proxy(c)
if not b.setData then return false,"EEPROM has no setData"end;local f=b.getData()or""local g=f:match(aK)or""
local d=g.."\nTOS1:"..a;if#d>256 then return false,"EEPROM data field too small"end
b.setData(d)return true,a end
function ae.clearManifestAnchor()local ah=require(ap)local b=ah.list(az,true)()if not b then return false,
aQ end;local a=ah.proxy(b)
if not
(a.getData and a.setData)then return false,"EEPROM has no data field"end;local c=a.getData()or""
a.setData(c:match(aK)or"")return true end
function ae.verifyManifestHash()local ah=require(ap)local d=ah.list(az)()
if not d then return false,aQ end;local e=ah.proxy(d)
if not e.getData then return false,"EEPROM has no getData"end;local f=e.getData()or""
local a=f:match("\nTOS1:(%x+)")or f:match("^TOS1:(%x+)")
if not a then return false,"no anchored hash (run `verify anchor` as admin)"end;a=a:sub(1,64)if#a~=64 or a:find("[^%x]")then
return false,"anchored value malformed"end
local b,g=ae.computeManifestHash()if not b then return false,g end;local h,c=pcall(require,au)
if not h or not c or not
c.ctEquals then return false,"crypto unavailable"end;if c.ctEquals(b,a)then return true end;return false,
"manifest hash mismatch (live="..b:sub(1,12).." anchored="..
a:sub(1,12)..")"end;function ae.getLog()return Z end;function ae.getHAL()return ag end
function ae.getEvent()return af end;function ae.getProc()return aa end
function ae.getFS()return _G._TOS.securefs or ad end;function ae.getDisplay()return ac end;function ae.getDisplayIdx()return nil end;function ae.getUsers()return
_G._TOS.users end
function ae.getSecureFS()return _G._TOS.securefs end;function ae.getConfig()return _G._TOS.config end;function ae.getPower()
return _G._TOS.power end;function ae.getSwap()return _G._TOS.swap end;function ae.getJBOD()return
_G._TOS.jbod end
function ae.getNet()return _G._TOS.net end
function ae.getCompress()if _G._TOS.compress then return _G._TOS.compress end
local b,a=pcall(require,"kernel.compress")
if b and a then pcall(a.init,{})_G._TOS.compress=a;return a end;return nil end
function ae.uptime()return ab.uptime()-_G._TOS.bootTime end;local aE=false
function ae.shutdown(a)if a then aE=true end;a=aE;ai=false;aT=true
if Z then Z.info(_,a and"Rebooting..."or
"Shutting down...")end
local b=package and package.loaded and package.loaded[aM]
if type(b)=="table"and b.shutdown then pcall(b.shutdown)end
if _G._TOS.rc then pcall(_G._TOS.rc.stopAll)end;if aa then
for d,c in ipairs(aa.list())do pcall(aa.kill,c.pid,{kernel=true})end end;if _G._TOS.net then
pcall(_G._TOS.net.shutdown)end;pcall(Z.flush)pcall(Z.detachFile)
if ac then
pcall(function()
local c=ac.getTheme()ac.clear(c.bg)
ac.set(2,2,a and"Rebooting TOS..."or"TOS shut down.",c.success,c.bg)ac.set(2,3,"Goodbye!",c.dim,c.bg)end)end
if _G._TOS.audio then pcall(_G._TOS.audio.shutdown)end
pcall(function()local c=_G._TOS.fs;if c and c.writeFile then
c.writeFile("/var/run/pwrstate","C\n"..
tostring(_G._TOS.bootCount or 0)..
"\n"..tostring((os.time and os.time())or 0))end end)ab.pullSignal(0.5)ab.shutdown(a or false)end;function ae.reboot()ae.shutdown(true)end;function ae.version()return _G._TOS.version,
_G._TOS.codename end
function ae.headlessMain()ai=true
local a=_G._TOS.users;if a then _G._TOS.bootSession=a.kernelSession()end
Z.info(_,"Entering headless service loop")
if not _G._TOS.net then
Z.warn(_,"WARNING: headless server has no network!")
Z.warn(_,"Install a modem or linked card so the server can be reached.")end
while ai do local b=table.pack(af.pull(0.5))if b[1]=="tos_shutdown"then
ai=false;break end
if b[1]=="component_added"then local c=b[3]
if
c==aD or c=="gpu"or c=="keyboard"then
Z.info(_,"Display hardware detected — checking for interactive switch")local d=require(ap)local e=d.list("gpu")()~=nil;local f=
d.list(aD)()~=nil
local g=d.list("keyboard")()~=nil
if e and f and g then
Z.info(_,"Full display hardware present — switching to interactive mode")ai=false;ac=require("kernel.display")
local h=d.proxy(d.list("gpu")())
if h then local j,k=h.maxResolution()local l,i=pcall(require,aw)
if
l and i and i.gpuTarget then
local m=i.getPolicy()or i.specFromConfig(_G._TOS and _G._TOS.config)i.setPolicy(m)local n,o=i.gpuTarget(h,nil,m)
if n and o then j,k=n,o end end;ac.init(h,j,k)end;ae.loginAndStartShell()return end end end;aa.tick(b.n>0 and b or nil)end;ae.shutdown()end;return ae