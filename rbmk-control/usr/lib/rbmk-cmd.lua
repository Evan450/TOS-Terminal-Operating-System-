local v="string"local m=require("rbmk.core")local n={}
local function s(...)for a=1,select("#",...)do
local c,b=pcall(require,(select(a,...)))if c and b then return b end end end;local l=s("component")local p=s("kernel.fs","filesystem")
local o="/etc/rbmk.cfg"
local function t()local a={}
if p and p.exists and p.exists(o)and p.readFile then
local b=p.readFile(o)local c=b and load(b,"="..o,"t",{})
if c then local e,d=pcall(c)if e and type(d)==
"table"then a=d end end end;return a end;n.loadCfg=t
local function u(a)
if type(a.profile)=="table"then return a.profile end;return
m.PROFILES[a.profileName or"hbm-ntm"]or m.PROFILES["hbm-ntm"]end;n.activeProfile=u
local function q(a)local b={}if not(l and l.list)then return b end
local c={}for e,d in ipairs((a and a.componentTypes)or{})do
c[d:lower()]=true end
for e,d in l.list()do
local f=tostring(d):lower()local g=c[f]if not g then
g=
f:find("rbmk",1,true)or f:find("reactor",1,true)or f:find("nuclear",1,true)or
f:find("ntm",1,true)end;if g then
b[#b+1]={address=e,type=d}end end;return b end;n.candidates=q
local function r(a)local b={}
if l and l.methods then local d,c=pcall(l.methods,a)
if d and
type(c)=="table"then for e,f in pairs(c)do
if type(e)==v then b[#b+1]=e elseif type(f)==v then b[#b+1]=f end end end end
if#b==0 and l and l.proxy then local d,c=pcall(l.proxy,a)
if
d and type(c)=="table"then for e,f in pairs(c)do
if type(f)=="function"and type(e)==v then b[#b+1]=e end end end end;table.sort(b)return b end;n.methodsOf=r
function n.read(b,a)
if a and a.driver=="ntm-console"then
local d=b and b[a.columns]if not d then return m.normalize({}),{}end
local e,f=m.scanCore(function(g,h)return d(g,h)end)return m.normalize(e),f end;local c={}
if a.bulk then local e,d=pcall(b[a.bulk])if e and type(d)=="table"then for f,g in
pairs(d)do c[f]=g end end end
for d,e in pairs(a.bound or{})do if d~="scram"and b[e]then local g,f=pcall(b[e])if
g and f~=nil then c[d]=f end end end;return m.normalize(c)end
function n.readColumns(b,a,c)
if not(b and a and a.columns)then return{}end;local d=b[a.columns]if not d then return{}end;local f,e=pcall(d)if not f or
type(e)~="table"then return{}end
return m.normalizeColumns(e,c)end
function n.scram(b,a,c)local e,d=false,{}
if a and a.bound and a.bound.scram and b then
local g=b[a.bound.scram]
if g then local h,i=pcall(g,true)
if h and i==nil then e=true
d[#d+1]="console."..a.bound.scram elseif h then d[#d+1]="console."..
a.bound.scram.." refused ("..tostring(i)..")"end end end;local f=c and tonumber(c.az5RedstoneSide)
if
f and l and l.list then local g=l.list("redstone")()
if g then local i,h=pcall(l.proxy,g)
if i and h and
h.setOutput then local j=pcall(h.setOutput,f,15)if j then e=true
d[#d+1]="redstone side "..f end end end end;return e,table.concat(d," + ")end
function n.run(c,a,b)a=a or print;c=c or{}b=b or{}
local g=(c[1]or"status"):lower()local d=t()local i=u(d)
if g=="skala"or g=="panel"then if not b.display then
a("The panel needs a screen; run `rbmk skala` from the shell.",0xFF6600)return end
local G,D=pcall(require,"rbmk-skala")if not G or type(D)~="table"or not D.run then
a(
"The panel renderer is missing: "..tostring(D),0xFF0000)return end
local E,F="auto",false
for H=2,#c do local I=tostring(c[H]):lower()if
I=="--wall"or I=="wall"then F=true elseif I=="--net"or I=="net"then E="net"elseif I=="--local"or I=="local"then
E="local"end end
D.run({display=b.display,event=b.event,cfg=d,mode=E,wallMode=F,o=a})return end
if g=="wall"then local F,E=pcall(require,"rbmk.wall")
local G,H=pcall(require,"rbmk.skala")if not(F and G)then
a("The panel libraries are missing.",0xFF0000)return end;local D=1;if b.screen and b.screen.list then D=#
b.screen.list()end
local I=E.plan(D,d.wall,function(J)
return H.param(J)~=nil end)
a("Display wall on this machine ("..D..
" screen".. (D==1 and""or"s").."):",0x00AAFF)
for K,J in ipairs(I)do local L=E.page(J.page)
a(string.format("  seat %d  %-9s %s%s%s",J.seat,L and L.label or J.page,(
J.page=="map"or J.page=="trend")and
("["..J.param.."] ")or"",
J.pinned and"pinned "or"",J.rejected and"(config rejected -- using the default)"or""),
J.rejected and 0xFFAA00 or 0xFFFFFF)end;a("")
a("Run `rbmk skala --wall` to drive them all; plain `rbmk skala`",0xAAAAAA)
a("uses only the seat you are sitting at, so other operators keep",0xAAAAAA)
a("their screens. Set `wall = { [2] = { page = \"trend\" } }` in",0xAAAAAA)
a(o.." to change the assignment.",0xAAAAAA)a("")
a("Satellites are NOT listed: displays never register with the",0xAAAAAA)
a("controller. Each one picks its own page from its own config,",0xAAAAAA)
a("so the machine that owns SCRAM has no inbound network path.",0xAAAAAA)return end
if g=="survey"then a("RBMK component survey",0x00AAFF)a("")
local D=q(i)
if#D==0 then a("No candidate components found.",0xFF6600)
a("Looked for the profile's types plus anything matching",0xAAAAAA)
a("rbmk / reactor / nuclear / ntm. Is the console adapter linked?",0xAAAAAA)return end
for F,E in ipairs(D)do
a(string.format("%s  %s",tostring(E.address):sub(1,8),tostring(E.type)),0xFFFFFF)local I=r(E.address)
if#I==0 then
a("    (no methods visible)",0xAAAAAA)else local L="    "for F,M in ipairs(I)do
if#L+#M+2 >76 then a(L,0xAAAAAA)L="    "end;L=L..M.."  "end;if#L>4 then
a(L,0xAAAAAA)end end;local G=m.bind(i,I)local H={}
for L,M in pairs(G.bound)do H[#H+1]=L.."="..M end;table.sort(H)
a("    bound:   "..
(#H>0 and table.concat(H,"  ")or"(nothing)"),#H>0 and 0x00FF00 or 0xFF6600)if#G.missing>0 then
a("    missing: "..table.concat(G.missing,"  "),0xFFAA00)end;if G.bulk then
a("    bulk:    "..G.bulk,0x00FF00)end
if G.columns then
a("    columns: "..
G.columns.."  (SKALA core map available)",0x00FF00)else
a("    columns: (none) -- the panel will show reactor-wide",0xAAAAAA)
a("             readings only, no per-channel core map",0xAAAAAA)end
if G.driver and G.columns then local M,L=pcall(l.proxy,E.address)
if M and L then local T=G.pos and
L[G.pos]local U,O=false,nil;if T then U,O=pcall(T)end
if U and
type(O)=="table"then
a(string.format("    core:    linked, centre %s, %s, %s",tostring(O.rbmkCenterX),tostring(O.rbmkCenterY),tostring(O.rbmkCenterZ)),0x00FF00)else
a("    core:    NOT LINKED -- the console reports no reactor",0xFF6600)end;local N,P=n.read(L,G)local Q,R={},{}
for F,V in ipairs(P or{})do local W=V.kind or"?"if not Q[W]then
R[#R+1]=W end;Q[W]=(Q[W]or 0)+1 end;table.sort(R)local S={}
for F,V in ipairs(R)do S[#S+1]=Q[V].." "..V end
a(string.format("    scan:    %d channel%s%s",# (P or{}),# (P or{})==1 and""or"s",

#S>0 and(" ("..table.concat(S,", ")..")")or""),
# (P or{})>0 and 0xFFFFFF or 0xFF6600)
if N.temp then
a(string.format("    hottest: hull %.0f C%s",N.temp,N.melt and
string.format(", fuel at %.0f%% of melting point",N.melt)or""),0xAAAAAA)end;if N.unread and N.unread>0 then
a("    unread:  "..N.unread.." channel(s) raised an error",0xFFAA00)end end end
local J,K=m.bindingUsable(G,d.az5RedstoneSide~=nil)
a("    usable:  "..
(J and"YES"or("NO — "..tostring(K))),J and 0x00FF00 or 0xFF0000)a("")end
a("Default profile is hbm-ntm (the mod's real rbmk_console API). A console",0xAAAAAA)
a("with per-reading getters instead: profileName = \"hbm-generic\", or add",0xAAAAAA)
a("profile = { temp = { \"theRealName\" }, ... } to "..o.." and re-run.",0xAAAAAA)return end
if g=="limits"then local E=m.mergeLimits(d.limits)
a("Active safety limits:",0x00AAFF)local D={}for F in pairs(E)do D[#D+1]=F end;table.sort(D)for G,F in ipairs(D)do
a(string.format("  %-12s %s",F,tostring(E[F])),0xFFFFFF)end
a("Edit "..o.." (admin) to change them.",0xAAAAAA)return end;local j=q(i)if#j==0 then
a("No RBMK console found — run `rbmk survey`.",0xFF6600)return end;local h=j[1]
if d.address then for E,D in ipairs(j)do
if tostring(D.address):sub(1,
#d.address)==d.address then h=D end end end;local z=r(h.address)local x=m.bind(i,z)
local A,k=pcall(l.proxy,h.address)if not A or not k then
a("Cannot open the console proxy.",0xFF0000)return end
if g=="scram"then local D,E=n.scram(k,x,d)if
D then a("SCRAM fired ("..E..")",0xFF0000)else
a("SCRAM FAILED — no console method and no redstone AZ-5 line.",0xFF0000)end;return end;local e=n.read(k,x)local B=m.mergeLimits(d.limits)
local w,C=m.evaluate(e,B,0)
a("RBMK "..tostring(h.type)..
"  "..tostring(h.address):sub(1,8),0x00AAFF)
local function f(D,E,F)if E==nil then
a(string.format("  %-10s (not reported)",D),0xAAAAAA)else
a(string.format("  %-10s %s%s",D,tostring(E),F or""),0xFFFFFF)end end;f("core",e.temp," C")
f("melt",e.melt and string.format("%.0f",e.melt)," % of fuel melting point")f("flux",e.flux)f("rods",e.rodDepth)
f("steam",e.steam)f("water",e.water," %")f("fuel",e.fuel)
local y=
(w=="scram")and 0xFF0000 or(w=="warn")and 0xFFAA00 or 0x00FF00;a("  state      "..w:upper(),y)for E,D in ipairs(C)do
a("    - "..D,y)end end;return n