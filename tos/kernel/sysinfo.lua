
local B,J,C,K,w,x,y,v,D="EEPROM","Graphics","Network","Storage","border","detected","estimated","override","unknown"local t={}local z=nil
local function A()if z==nil then local a,b=pcall(require,"kernel.hal")
z=(a and b)or false end;return z or nil end;function t.stickTier(a)local b=A()return
b and b.stickTier and b.stickTier(a)or nil end
function t.ramSummary(a,b,c)
local d=A()
if not(d and d.ramSummary)then return
tostring(math.floor(a or 0)).."K"end;return d.ramSummary(c,a,b)end
local function E(a)if a>=512 then return"T2+"elseif a>=256 then return"T1.5"else return"T1"end end
local function F(a)if not a or a<=1 then return 1 end;if a<=4 then return 2 end;return 3 end
local function G(a,b)a,b=a or 0,b or 0;if a>=160 or b>=50 then return 3 end;if a>=80 or b>=25 then
return 2 end;return 1 end;local function H(a)if a<=600 then return"Floppy"end;if a<=1100 then return"T1"end
if a<=2200 then return"T2"end;return"T3"end
local u={[1]="T1 (MD5 / CRC / deflate)",[2]="T2 (AES + SHA-256)",[3]="T3 (ECC + AES + SHA-256)"}
local function L(b,a,c)if a and tonumber(a.dataTier)then local g=tonumber(a.dataTier)return g,u[g]or
("T"..g),v end
local f,e=pcall(require,"kernel.datacard")
if f and e and e.capsOf then local g=e.tierOf(e.capsOf(b,c))if g>=1 then
return g,u[g],x end;return 0,"present (unknown tier)",D end;local function d(g)return b[g]~=nil end
if
d("generateKeyPair")or d("ecdsa")or d("ecdh")then return 3,u[3],x elseif
d("sha256")or d("encrypt")then return 2,u[2],x elseif d("md5")or d("crc32")then return 1,u[1],x end;return 0,"present (unknown tier)",D end;t._memTier=E;t._gpuTier=F;t._screenTier=G;t._diskTier=H
local function I(c,b,a)if
b and tonumber(b.cpuTier)then return tonumber(b.cpuTier),v end
if
type(c)=="table"then
for f,e in pairs(c)do
if type(e)=="table"then
local d=tostring(e.class or""):lower()
if d=="processor"then
local h=((e.product or"").." ".. (e.description or"").." "..
tostring(e.clock or"")):lower()local g=h:match("tier%s*(%d)")if g then return tonumber(g),x end end end end end;if type(a)=="number"and a>0 then
if a>=768 then return 3,y elseif a>=256 then return 2,y else return 1,y end end;return nil,D end;t._detectCpuTier=I
function t.benchmarkCallBudget(a)a=a or require("computer")
local c=a.uptime()local b=0;while a.uptime()==c and b<1e7 do b=b+1 end
local d=(b>2.5e5)and
3 or(b>1.0e5)and 2 or 1;return b,d end
function t.gather(b,c,a)b=b or{}c=c or{}a=a or function()end
local e=b.component or require("component")local f=b.computer or require("computer")
local g=b.deviceInfo;if g==nil then
pcall(function()if f.getDeviceInfo then g=f.getDeviceInfo()end end)end
local d={cpu={},memory={},gpu={},screen={},disks={},modems={},dataCard={present=false},eeprom={},tunnel={present=false},other={},internet={present=false},deviceInfo=g}a("Detecting processor and memory")local p="Lua 5.3"
pcall(function()if
f.getArchitecture then p=f.getArchitecture()end end)d.cpu.arch=p
local q=(f.totalMemory and f.totalMemory())or 0
local r=(f.freeMemory and f.freeMemory())or 0;d.memory.totalKB=math.floor(q/1024)
d.memory.freeKB=math.floor(r/1024)d.memory.tier=E(d.memory.totalKB)local i=A()
d.memory.modules=i and
i.ramBanks and i.ramBanks(g)or 0
d.memory.sticks=i and i.ramSticks and i.ramSticks(g)or nil
d.memory.summary=t.ramSummary(d.memory.totalKB,d.memory.modules,d.memory.sticks)d.cpu.count=0
for h in e.list("cpu")do d.cpu.count=d.cpu.count+1 end;d.cpu.tier,d.cpu.tierSource=I(g,c,d.memory.totalKB)
a("Detecting display")local l,j,k,m=0,1,0,0
for h in e.list("gpu")do l=l+1
pcall(function()local N=e.proxy(h)local P=
(N.getDepth and N.getDepth())or 1;if P>j then j=P end
local O,Q=N.maxResolution()if O and O>k then k,m=O,Q end end)end;d.gpu={count=l,tier=F(j),depth=j,maxW=k,maxH=m}local n=0;for h in e.list("screen")do
n=n+1 end;d.screen={count=n,tier=G(k,m)}
a("Detecting storage")
local s=f.tmpAddress and f.tmpAddress()or nil
for h in e.list("filesystem")do
pcall(function()local N=e.proxy(h)
local O=math.floor((
(N.spaceTotal and N.spaceTotal())or 0)/1024)
local Q=math.floor(
((N.spaceUsed and N.spaceUsed())or 0)/1024)local P=(h==s)
d.disks[#d.disks+1]={addr=h:sub(1,8),label=
(N.getLabel and N.getLabel())or"",usedKB=Q,totalKB=O,tier=P and"RAM"or H(O),tmpfs=P or nil,readonly=
(N.isReadOnly and N.isReadOnly())or false}end)end
for h in e.list("drive",true)do
pcall(function()local N=e.proxy(h)local O=
(N.getCapacity and N.getCapacity())or 0
d.disks[#d.disks+1]={addr=h:sub(1,8),label="",usedKB=0,totalKB=math.floor(
O/1024),tier="Raw",unmanaged=true,sectorSize=
(N.getSectorSize and N.getSectorSize())or 0}end)end
for h in e.list("tape_drive",true)do
pcall(function()local N=e.proxy(h)local O=false
pcall(function()O=
N.isReady and N.isReady()or false end)local Q=0;if O then
pcall(function()Q=math.floor(
((N.getSize and N.getSize())or 0)/1024)end)end;local P
if O then pcall(function()
P=N.getLabel and N.getLabel()end)end
d.disks[#d.disks+1]={addr=h:sub(1,8),label=(P~=nil and P~="")and P or(O and
""or"(no tape)"),usedKB=0,totalKB=Q,tier="Tape",tape=true,loaded=O}end)end
table.sort(d.disks,function(h,N)return h.totalKB>N.totalKB end)a("Detecting network and peripherals")
for h in e.list("modem")do
pcall(function()
local N=e.proxy(h)
local O=(N.isWireless and N.isWireless())or false
local P=(O and N.getStrength)and N.getStrength()or nil
d.modems[#d.modems+1]={addr=h:sub(1,8),wireless=O,strength=P}end)end
for h in e.list("tunnel")do d.tunnel={present=true,addr=h:sub(1,8)}end
for h in e.list("internet")do
pcall(function()local N=e.proxy(h)
d.internet={present=true,addr=h:sub(1,8),http=(N.isHttpEnabled and
N.isHttpEnabled())or false,tcp=(N.isTcpEnabled and
N.isTcpEnabled())or false}end)break end
for h in e.list("data")do
pcall(function()local N=e.proxy(h)local O,P,Q=L(N,c,h)
d.dataCard={present=true,addr=h:sub(1,8),tier=O,name=P,tierSource=Q}end)break end
for h in e.list("eeprom")do
pcall(function()local N=e.proxy(h)
d.eeprom={addr=h:sub(1,8),label=
(N.getLabel and N.getLabel())or B,size=(N.getSize and N.getSize())or nil,bootAddr=
(
f.getBootAddress and(f.getBootAddress()or""):sub(1,8))or nil}end)break end
local M={gpu=true,screen=true,filesystem=true,modem=true,tunnel=true,data=true,eeprom=true,keyboard=true,internet=true}local o={}
for N,h in e.list()do if not M[h]then o[h]=(o[h]or 0)+1 end end
for h,N in pairs(o)do d.other[#d.other+1]={type=h,count=N}end
table.sort(d.other,function(h,N)return h.type<N.type end)return d end
function t.rows(a)local c={}
local function b(e,f,g)c[#c+1]={label=e,value=f,role=g or"value"}end
local function d(e)c[#c+1]={label="",value=e,role="section"}end;d("System")
do local g=a.cpu.tierSource;local e,f
if not a.cpu.tier then
e,f="  [Tier ? - set in boot settings]","warn"elseif g==v then e,f="  [Tier "..a.cpu.tier.."*]","value"elseif g==y then
e,f="  [~Tier "..
a.cpu.tier.." est - confirm in settings]","warn"else e,f="  [Tier "..a.cpu.tier.."]","value"end
b("Processor",(a.cpu.arch or"?")..e,f)end
b("Memory",string.format("%dK free / %dK total  [%s]",a.memory.freeKB or 0,a.memory.totalKB or 0,
a.memory.summary or a.memory.tier or"?"),(
a.memory.totalKB or 0)<192 and"warn"or"value")
if(a.gpu.count or 0)>0 then
b(J,string.format("GPU T%d, %d-bit, max %dx%d%s",a.gpu.tier or 1,
a.gpu.depth or 1,a.gpu.maxW or 0,a.gpu.maxH or 0,
(a.gpu.count or 0)>1 and("  (x"..a.gpu.count..")")or""),"value")else b(J,"no GPU card","warn")end
if a.dataCard.present then local e=a.dataCard.name or"data card"
local f,g=a.dataCard.tierSource,"ok"if f==D then e,g=e.."  [tier ? - set in boot settings]","warn"elseif f==v then
e=e.."*"end;b("Crypto",e,g)else
b("Crypto","software fallback (no data card)","warn")end
if#a.modems>0 then local e={}for g,f in ipairs(a.modems)do
e[#e+1]=
f.wireless and("wireless"..
(f.strength and(" "..
math.floor(f.strength))or""))or"wired"end;b(C,
table.concat(e,", ").." card","value")elseif
a.tunnel.present then b(C,"linked card (tunnel)","value")else b(C,"none","dim")end
if a.internet and a.internet.present then local e={}
if a.internet.http then e[#e+1]="HTTP"end;if a.internet.tcp then e[#e+1]="TCP"end;if#e>0 then
b("Internet",
table.concat(e," + ").." card","value")else
b("Internet","card present, disabled by the server","warn")end end;if a.eeprom.addr then
b(B,string.format("%s%s",a.eeprom.label or B,a.eeprom.bootAddr and("  boot:"..
a.eeprom.bootAddr)or""),"dim")end;d(K)
if#
a.disks==0 then b("","(no drives)","dim")else
for f,e in ipairs(a.disks)do local g=(e.label~=""and
e.label)or e.addr
local h=string.format("%d/%dKB",e.usedKB,e.totalKB)
b("",string.format("%-12s %-13s [%s]%s",g,h,e.tier,e.readonly and" ro"or""),"dim")end end;d("Peripherals")
b("Screens",tostring(a.screen.count or 0)..
((
a.screen.count or 0)>0 and("  [T"..
(a.screen.tier or 1).."]")or""),
(a.screen.count or 0)==0 and"warn"or"dim")
if#a.other>0 then local e={}for g,f in ipairs(a.other)do
e[#e+1]=f.type.. (
f.count>1 and("x"..f.count)or"")end
b("Attached",table.concat(e,", "),"dim")else b("Attached","(none)","dim")end;return c end
function t.diskRole(b,c,a)a=a or{}if c then return"Boot Drive"end
if b.tape then return"Tape Drive"end;if b.unmanaged then return"Raw Drive"end;if b.tmpfs or b.label=="tmpfs"then return
"Temp /tmp"end
if b.tier=="Floppy"or
(b.totalKB or 0)<=600 then a.floppy=(a.floppy or 0)+1;return
"Floppy "..string.char(
64+math.min(a.floppy,26))end;a.data=(a.data or 0)+1;return"Data Drive "..a.data end
function t.render(a,b)local g,p=b.W or 50,b.H or 16;local h=b.set
local f=b.color or function()return 0xFFFFFF end;local i=f("bg")
local function e(_,aa,ab,ac)
if not ab or aa<1 or aa>p or _>g then return end;local ad=g-_+1;if ad<1 then return end
h(_,aa,tostring(ab):sub(1,ad),f(ac or"value"),i)end;local function M(_)
e(2,_,string.rep("-",math.max(0,g-2)),w)end;local j=a.cpu or{}local k=a.memory or{}local d=a.gpu or
{}local R=k.totalKB or 0;local S=k.freeKB or 0
local function U()if not j.tier then return
"Tier ?  (set in Boot Settings)"end;local _=j.tierSource
return"Tier "..j.tier..
(
_==v and"  *"or(_==y and"  (est)"or""))end
local function V()if(d.count or 0)==0 then return"none"end;return
"GPU T".. (d.tier or 1)..

" / ".. (d.depth or 1)..
"-bit".. ((d.count or 0)>1 and
("  (x"..d.count..")")or"")end
local function W()if not(a.dataCard and a.dataCard.present)then return
"not installed"end
local _,aa=a.dataCard.tier,a.dataCard.tierSource;if _ and _>=1 then
return"Tier ".._.. (aa==v and"  *"or"")end;return"present (tier ? - set in Boot Settings)"end
local function X()
if a.modems and#a.modems>0 then local _=a.modems[1]
if _.wireless then return"Wireless"..
(_.strength and(" "..
math.floor(_.strength))or"")end;return"Wired"end
if a.tunnel and a.tunnel.present then return"Linked (tunnel)"end;return"none"end;local N,O
if(k.modules or 0)>0 then
N,O="RAM Modules",k.summary or tostring(k.modules)else N,O="Memory Tier",(k.tier or"?").."  (est)"end;local l=g>=72;local q,T=2,g-1;local Y=T-q-1
local function P(_,ab,ac,ad,aa)if _<1 or _>p then return end;h(q,_,ab..
string.rep(ac,Y)..ad,f(w),i)
if aa then h(q+2,_,"╡ "..aa..
" ╞",f("title"),i)end end;local function r(_)if _<1 or _>p then return end;h(q,_,"║",f(w),i)
h(T,_,"║",f(w),i)end
local m={{"Processor",
(j.arch or"Lua 5.3").. (
(j.count or 0)>1 and("  (x"..j.count..")")or"")},{"CPU Tier",U()},{J,V()},{"Data Card",W()},{C,X()},{B,(
a.eeprom and a.eeprom.label)or"Lua BIOS"}}
local n={{"Total Memory",R.."KB"},{"Free Memory",S.."KB"},{N,O},{"Max Text Mode",
(d.maxW or 0).."x".. (d.maxH or 0)},{"Screens",tostring(
a.screen and a.screen.count or 0)..
(
(a.screen and(
a.screen.count or 0)>0)and("  (T".. (
a.screen.tier or 1)..")")or"")},{"Boot ID",(
a.eeprom and a.eeprom.bootAddr)or"(unknown)"}}
local function s(_,aa,ab,ad,ac)
e(_,aa,ab..string.rep(" ",math.max(0,ac-#ab)).." : ","dim")e(_+ac+3,aa,ad,"value")end;local c
if l then
P(1,"╔","═","╗",b.title or"TOS System Configuration")c=2;local _=math.floor(g/2)+1
for aa=1,math.max(#m,#n)do r(c)if m[aa]then
s(4,c,m[aa][1],m[aa][2],13)end
if n[aa]then s(_,c,n[aa][1],n[aa][2],13)end;h(_-2,c,"│",f(w),i)c=c+1 end;P(c,"╠","═","╣",K)c=c+1 else
e(2,1,b.title or"TOS System Configuration","title")M(2)c=4
for ab,aa in ipairs(m)do s(2,c,aa[1],aa[2],13)c=c+1 end;for ab,aa in ipairs(n)do s(2,c,aa[1],aa[2],13)c=c+1 end
M(c)c=c+1;e(2,c,K,"title")c=c+1 end;if l then r(c)
e(4,c,string.format("%-12s %-10s %-13s %-6s %s","Role","Label","Used/Size","Tier","Boot"),"dim")c=c+1 end;local Q=a.eeprom and
a.eeprom.bootAddr;local o={}for ab,aa in ipairs(a.disks or{})do
o[#o+1]=aa end
table.sort(o,function(_,aa)
local ac,ad=(_.addr==Q),(aa.addr==Q)if ac~=ad then return ac end;return
(_.totalKB or 0)> (aa.totalKB or 0)end)local Z={}
for ab,aa in ipairs(o)do if c>=p then break end;local _=(aa.addr==Q)
local ac=t.diskRole(aa,_,Z)
local ad=(aa.label~=""and aa.label or aa.addr)
local ae=string.format("%d/%dKB",aa.usedKB or 0,aa.totalKB or 0)
local af=l and
string.format("%-12s %-10s %-13s %-6s %s",ac,ad:sub(1,10),ae,tostring(aa.tier or"?"),_ and"Yes"or"No")or string.format("%-11s %-11s %s%s",ac,ad:sub(1,11),ae,
_ and"  *"or"")if l then r(c)end;e(4,c,af,_ and"ok"or"value")c=c+1 end
if#o==0 then if l then r(c)end;e(4,c,"(no drives)","dim")c=c+1 end;if l then P(c,"╚","═","╝")else M(c)end;c=c+1
e(2,c,string.format("Memory %d/%dKB free    Display GPU T%d  %dx%d",S,R,
d.tier or 1,d.maxW or 0,d.maxH or 0),"ok")c=c+1;return c end;return t