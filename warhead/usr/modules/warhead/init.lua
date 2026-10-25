
local au,av,aw,ax,al,_,ae,ag,an="Cannot scan: ","Custom Nuke","\226\150\146","blast damage","config","custom","design","shelter","string"local am=require("component")local ay=require("computer")
local W=require("warhead.model")local Z=require("warhead.report")local V=W.D;local aa=W.num;local U={}local ab;do
local a,b=pcall(require,"shell.keys")ab=a and b or nil end;local function ai(b,a)if ab and ab.is then return
ab.is("quit",b,a)end
return b==17 or a==68 or a==1 end
local function ao()if ab and ab.label then
local a=ab.label("quit")if a~=""then return a end end;return"^Q"end
local X={ENTER=28,BACK=14,DEL=211,TAB=15,UP=200,DOWN=208,LEFT=203,RIGHT=205,PGUP=201,PGDN=209,HOME=199,END=207}local function ac(a)local b=0
for c=1,#a do local d=a:byte(c)if d<0x80 or d>=0xC0 then b=b+1 end end;return b end
local function ap(c,d,e)local b,a={},0
for f=1,#c do
local g=c:byte(f)if g<0x80 or g>=0xC0 then a=a+1;b[a]=f end end;b[a+1]=#c+1;d,e=math.max(1,d),math.min(a,e)
if d>e then return""end;return c:sub(b[d],b[e+1]-1)end
local function Y(a,b)a=tostring(a or"")local c=ac(a)if c>b then return ap(a,1,b)end;return a..string.rep(" ",
b-c)end;U.ulen,U.pad=ac,Y
function U.fitKeys(b,a,c)local e=" \194\183 "local d={}for g,f in ipairs(b)do d[#d+1]=f
if ac(
table.concat(d,e)..e..a)>c then d[#d]=nil;break end end;if#d==0 then return a end;return
table.concat(d,e)..e..a end
function U.wrap(a,b)if ac(a)<=b then return{a}end;local g,h=0,a
local d=a:match("^(%u%l+ +)%S")if d and#d<=12 then g=math.min(#d,math.floor(b/4))
h=a:sub(#d+1)else d=nil end;local e,c={},d or""local f=true
for i in
h:gmatch("%S+")do local j=f and(c..i)or(c.." "..i)
if ac(j)>b and not f then e[
#e+1]=c;c=string.rep(" ",g)..i else c=j end;f=false end;if c~=""then e[#e+1]=c end;return e end;local az=".warhead"
function U.newSettings()return{cfg={},designs={},order={},places={}}end
function U.parseSettings(a)local b=U.newSettings()if type(a)~=an then return b end
for c in
(a.."\n"):gmatch("(.-)\r?\n")do local d,f=c:match("^cfg (%S+) (%S+)$")if
d and V.CONFIG[d]~=nil then
if V.CONFIG_BOOL[d]then b.cfg[d]=(f=="true")else b.cfg[d]=tonumber(f)end end
local e,h=c:match("^design ([^\t]+)\t(.*)$")
if e then local l={}local k=0
for m in(h..","):gmatch("([^,]*),")do k=k+1
if k>V.CUSTOM_SLOTS then break end;if m~="-"and m~=""and
(W.byKey[m]or m==V.DROP_UPGRADE.key)then l[k]=m end end
if not b.designs[e]then b.order[#b.order+1]=e end;b.designs[e]=l end;local g,i,j=c:match("^place (%-?%d+) (%-?%d+) (.+)$")if g then
b.places[#
b.places+1]={dx=tonumber(g),dz=tonumber(i),name=j}end end;return b end
function U.serializeSettings(a)local b={"WARHEAD1"}local c={}
for d in pairs(a.cfg)do c[#c+1]=d end;table.sort(c)for e,d in ipairs(c)do b[#b+1]="cfg "..
d.." "..tostring(a.cfg[d])end
for e,d in
ipairs(a.order)do local f=a.designs[d]
if f then local g={}
for h=1,V.CUSTOM_SLOTS do local i=f[h]g[h]=
(type(i)=="table"and i.key)or i or"-"end
b[#b+1]="design "..d.."\t"..table.concat(g,",")end end;for e,d in ipairs(a.places)do
b[#b+1]=string.format("place %d %d %s",d.dx,d.dz,d.name)end;return
table.concat(b,"\n").."\n"end
local function aq()if not(fs and fs.home)then return nil end
local b,a=pcall(fs.home)
if not b or type(a)~=an or a=="/tmp"then return nil end;return a.."/"..az end
local function ar()local a=aq()if a and fs.exists and fs.exists(a)then
local c,b=pcall(fs.readFile,a)
if c and type(b)==an then return U.parseSettings(b)end end;return
U.newSettings()end
local function ad(a)local b=aq()if not b or not fs.writeFile then
return false,"no home directory to save in"end
local d,c=pcall(fs.writeFile,b,U.serializeSettings(a))if not d or c==false then return false,tostring(c)end
return true end
function U.cleanName(a)
a=tostring(a or""):gsub("[%c]"," "):gsub("^%s+",""):gsub("%s+$","")if ac(a)>24 then a=ap(a,1,24)end;return a end
function U.catalogue()
local a={{group=av,kind=_,key=_,name="Custom Nuke (designer)"}}for d,c in ipairs(V.BOMBS)do
a[#a+1]={group="Bombs",kind="bomb",key=c.key,name=c.name,ref=c}end;for c,b in ipairs(V.MISSILES)do
a[#a+1]={group="Missiles",kind="missile",key=b.key,name=b.name,ref=b}end;for c,b in ipairs(V.WARHEADS)do
a[#a+1]={group="Missile warheads",kind="missile",key=b.key,name=b.name,ref=b}end;return a end
function U.find(a)if type(a)~=an or a==""then return nil end;local b=a:lower()
local c=U.catalogue()for e,d in ipairs(c)do if d.key==b then return d end end;for e,d in ipairs(c)do if
d.name:lower()==b then return d end end;for e,d in ipairs(c)do if
d.name:lower():find(b,1,true)then return d end end;return nil end
function U.outcome(a,b,c)
if a.kind==_ then local e,f=W.stages(c or{},b)
local d=W.customOutcome(e,b)d.name=av;d.fall=f.fall;return d,e,f elseif a.kind=="bomb"then
return W.bombOutcome(a.ref,b)end;return W.missileOutcome(a.ref,b)end
local function aj()local b,a=pcall(require,"peripheral.inventory")if not b or
type(a)~="table"or not a.sides then
return nil,"no transposer or inventory controller attached"end
if a.available and
not a.available()then return nil,"no transposer or inventory controller attached"end;return a end;local aA={bottom=0,down=0,top=1,up=1,north=2,south=3,west=4,east=5}
local function ak(a,b)
local c,e=a.stacks(b)if not c then return nil,e end;local d={}for g,f in ipairs(c)do
d[f.slot]={id=f.id,dmg=f.damage,count=f.count,label=f.label}end;return d end
function U.identify(b,a)if b==V.CUSTOM_SLOTS then return U.find(_)end;local c,d
for f,e in
ipairs(V.BOMBS)do
if e.slots==b then local g=0;for h,i in ipairs(e.parts or{})do
if W.partMatches(i,a[h])then g=g+1 end end;for h,i in pairs(e.filled or{})do if
W.partMatches(i,a[h])then g=g+1 end end
if e.perCharge then for h=1,e.slots do if
W.partMatches(e.perCharge,a[h])then g=g+1 end end end;if not d or g>d then c,d=e,g end end end;if not c then return nil end;return U.find(c.key)end
function U.slotsFromContents(a)local b,c={},{}
for d=1,V.CUSTOM_SLOTS do local e=a[d]
if e then local f=W.lookup(e.id,e.dmg)
if f then
b[d]=f.key elseif e.id==V.DROP_UPGRADE.id then b[d]=V.DROP_UPGRADE.key else c[#c+1]={slot=d,label=e.label or
e.id}end end end;return b,c end
function U.stockFromContents(a)local b,c={},0;for e,d in pairs(a)do local f=W.lookup(d.id,d.dmg)
if f then b[f.key]=(b[f.key]or
0)+ (d.count or 1)c=c+1 end end;return b,c end
local function as(b,a)local c=b.sides()
if#c==0 then return nil,"nothing to read on any side"end;if a then local d=aA[a:lower()]or tonumber(a)for f,e in ipairs(c)do if e.side==d then
return e end end
return nil,"no inventory on side "..a end
return c end
local T={title=0xFFFF55,fg=0xFFFFFF,dim=0xAAAAAA,hi=0x55FF55,warn=0xFF5555}local function af(a,b)
for d,c in ipairs(b)do a(c[1],T[c[2]]or 0xFFFFFF)end end;local function aB()
local b=require("warhead.best")local a={}for d,c in ipairs(b.ORDER)do a[#a+1]=c end;a[#a+1]="euph"
return a,b end
local function aC(a)local b={}
local c,d={},{}
for f,e in ipairs(a.slots)do
local g=type(e)=="table"and e.key or e;if not c[g]then d[#d+1]=g end;c[g]=(c[g]or 0)+1 end;for f,e in ipairs(d)do local g=W.byKey[e]
local h=g and g.name or V.DROP_UPGRADE.name
b[#b+1]={string.format("  %2d x %s",c[e],h),"fg"}end
b[#b+1]={string.format("  %d of %d slots. One item per slot is enough; stacks count once.",
#a.slots,V.CUSTOM_SLOTS),"dim"}return b end
local function at(a)
a("warhead — HBM Nuclear Tech nuke designer and simulator ("..V.SOURCE..")",T.title)
a("  warhead                         the full-screen simulator",T.fg)
a("  warhead list                    every warhead it knows",T.fg)
a("  warhead sim <name>              what one would do (e.g. warhead sim tsar)",T.fg)
a("  warhead best <kind> [radius N] [salt] [stock <side>]",T.fg)
a("                                  design the best custom nuke",T.dim)
a("        kinds: tnt nuke hydro bale schrab sol euph",T.dim)
a("  warhead scan [side]             read a bomb next to a transposer",T.fg)
a("  warhead shelter <name> <dist> <material> [thick]",T.fg)
a("  warhead materials               what a shelter can be built from",T.fg)
a("  warhead config [set K V | reset [K]]   your server's hbm.cfg values",T.fg)end
local function aD(c,b,a)local e=c[2]
if e=="set"then local g,h=c[3],c[4]
if not g or V.CONFIG[g]==nil then b("Unknown key: "..
tostring(g),T.warn)return end
if V.CONFIG_BOOL[g]then if h~="true"and h~="false"then
b(g.." is true or false.",T.warn)return end;a.cfg[g]=(h=="true")else
local k=tonumber(h)
if not k or k<0 then b(g.." needs a number.",T.warn)return end;a.cfg[g]=k end;local i,j=ad(a)
b(i and
("Set "..g.." = "..tostring(a.cfg[g]))or("Not saved: "..tostring(j)),
i and T.hi or T.warn)return elseif e=="reset"then if c[3]then a.cfg[c[3]]=nil else a.cfg={}end
local g,h=ad(a)
b(g and"Reset."or("Not saved: "..tostring(h)),
g and T.hi or T.warn)return end;local f=W.config(a.cfg)local d={}
for g in pairs(V.CONFIG)do d[#d+1]=g end;table.sort(d)
b("Config ("..V.SOURCE.." defaults; * = yours):",T.title)for h,g in ipairs(d)do
b(string.format("  %-22s %-8s%s",g,tostring(f[g]),a.cfg[g]~=nil and" *"or""),
a.cfg[g]~=nil and T.hi or T.fg)end end
local function aE(c,a,b)local e,g=aj()if not e then a(au..g..".",T.warn)return end
local d,h=as(e,c[2])if not d then a(au..h..".",T.warn)return end
if d.side then d={d}end;local f=0
for j,i in ipairs(d)do local l=ak(e,i.side)
local k=l and U.identify(i.size,l)
if k then f=f+1
a(string.format("%s side (%d slots): %s",i.name,i.size,k.name),T.title)local m
if k.kind==_ then local n,o=U.slotsFromContents(l)local p
m,p=U.outcome(k,b,n)if m.fall then
a("  Has the Drop Upgrade: it falls, then goes off where it lands.",T.dim)end;for j,q in ipairs(o)do
a(string.format("  slot %d holds %s, which adds nothing",q.slot,q.label),T.dim)end else
m=W.bombOutcome(k.ref,b,l)end;af(a,Z.lines(m,b))a("",T.fg)end end;if f==0 then
a("No HBM bomb found next to the transposer.",T.warn)end end
local function aF(b,a,c)local k,h=aB()local i=b[2]local l=false
for n,d in ipairs(k)do if d==i then l=true end end
if not l then
a("Which kind of blast? "..table.concat(k," "),T.warn)for n,d in ipairs(h.ORDER)do
a(string.format("  %-7s %s",d,h.GOALS[d].name),T.dim)end
a("  euph    Anti Mass (beams)",T.dim)return end;local g={}local e=3
while b[e]do local d=b[e]
if d=="radius"then g.radius=tonumber(b[e+1])e=e+1 elseif d==
"salt"then g.salt=true elseif d=="stock"then local p,r=aj()if not p then
a("Cannot read stock: "..r..".",T.warn)return end;local o,t=as(p,b[e+1])
if
not o or not o.side then a("Name the chest's side: stock <side>.",T.warn)return end;local s=ak(p,o.side)local q
g.stock,q=U.stockFromContents(s or{})
a(string.format("Designing from the %s chest (%d ingredient stacks).",o.name,q),T.dim)e=e+1 end;e=e+1 end;local f,j
if i=="euph"then f,j=h.designEuph(c,g)else f,j=h.design(i,c,g)end;if not f then
a("No design: "..tostring(j)..".",T.warn)return end
a("Best "..
f.goal.name:lower().." custom nuke:",T.title)af(a,aC(f))if f.short then
a("It cannot reach radius "..g.radius.."; this is the most it can do.",T.warn)end;local m=f.outcome;m.name=nil
af(a,Z.lines(m,c))end
local function aG(b,a,c,d)local g=U.find(b[2]or"")
local h,i,j=tonumber(b[3]or""),b[4],tonumber(b[5]or"3")
if not g or not h or not i then
a("Usage: warhead shelter <name> <distance> <material> [thickness]",T.warn)
a("  e.g. warhead shelter tsar 120 concrete 4      (materials: warhead materials)",T.dim)return end;local f=Z.mat(i)if not f then
a("Unknown material: "..i.." (see warhead materials).",T.warn)return end
local k=U.outcome(g,c,d.designs[d.order[1]or""])local l=W.effects(k,c)
a(string.format("%s, %s wall %d thick at %d blocks:",g.name,f.name,j,h),T.title)
af(a,Z.shelterLines(W.shelter(k,l,f,h,j),f,l))end
local function aH(b,a)local e=ar()local d=W.config(e.cfg)local c=b[1]
if c=="help"or c=="-h"or
c=="--help"then at(a)elseif c=="list"then local f
for h,g in ipairs(U.catalogue())do if g.group~=f then
a(g.group,T.title)f=g.group end
local i=string.format("  %-18s %s",g.key,g.name)
if g.kind~=_ then local j=U.outcome(g,d)
i=i..
"  -  "..
(Z.ENGINE[j.engine]or j.engine)..
(j.radius and(" r"..j.radius)or(j.power and
(" power "..aa(j.power))or""))end;a(i,T.fg)end elseif c=="sim"then local f=table.concat(b," ",2)
if
f:match("^design ")or e.designs[f]then
local h=e.designs[f]and f or f:gsub("^design ","")local i=e.designs[h]if not i then
a("No saved design called "..h..".",T.warn)return end
local j=U.outcome(U.find(_),d,i)j.name="Custom Nuke \""..h.."\""
af(a,Z.lines(j,d))return end;local g=U.find(f)if not g or g.kind==_ then
a("Which warhead? `warhead list` shows them; a saved design is `warhead sim design <name>`.",T.warn)return end
af(a,Z.lines(U.outcome(g,d),d))elseif c=="best"then aF(b,a,d)elseif c=="scan"then aE(b,a,d)elseif c==ag then aG(b,a,d,e)elseif c=="materials"then
a("Material             nuke  radiation   (resistance; see README)",T.title)for g,f in ipairs(V.MATERIALS)do
a(string.format("  %-10s %-24s %8s %8s",f.key,f.name,aa(f.nuke),aa(f.rad)),T.fg)end elseif c==al then aD(b,a,e)else return
false end;return true end
local function aI(a)local h=am.list and am.list("gpu")()if not h then
return nil,"no GPU"end;local i,c=pcall(am.proxy,h)if not i or not c then
return nil,"cannot open the GPU"end;local d,e=c.getResolution()
if not d or d<80 or
e<24 then return nil,
string.format("the full screen needs 80x24 (this one is %sx%s)",tostring(d),tostring(e))end;local j,f=pcall(c.getDepth)local b=
(j and type(f)=="number")and(
f<=1 and 1 or(f<=4 and 2 or 3))or 1
local k=

(b==1)and
{fg=0xFFFFFF,dim=0xFFFFFF,bg=0x000000,border=0xFFFFFF,title=0xFFFFFF,hi=0xFFFFFF,warn=0xFFFFFF,selfg=0x000000,selbg=0xFFFFFF,r1=0xFFFFFF,r2=0xFFFFFF,r3=0xFFFFFF,r4=0xFFFFFF}or
{fg=0xFFFFFF,dim=0xAAAAAA,bg=0x000000,border=b==2 and 0x55FFFF or 0x00FFFF,title=b==2 and 0xFFFF55 or 0xFFFF00,hi=
b==2 and 0x55FF55 or 0x00FF00,warn=b==2 and 0xFF5555 or 0xFF4040,selfg=0x000000,selbg=
b==2 and 0x55FFFF or 0x00FFFF,r1=b==2 and 0xFF5555 or 0xFF3030,r2=
b==2 and 0xFFAA00 or 0xFF8000,r3=b==2 and 0xFFFF55 or 0xFFE040,r4=b==2 and 0x55FF55 or 0x80C040}local g={W=d,H=e,tier=b,T=k,gpu=c,mono=b==1}function g.set(n,o,p,l,m)if l then
pcall(c.setForeground,l)end;if m then pcall(c.setBackground,m)end
pcall(c.set,n,o,p)end
function g.fill(n,o,p,q,r,l,m)if l then
pcall(c.setForeground,l)end;if m then pcall(c.setBackground,m)end;pcall(c.fill,n,o,p,q,
r or" ")end;return g end
local function ah()local a={ay.pullSignal()}
if a[1]=="key_down"then return a[3],a[4],a[1]end;if a[1]=="interrupted"then return 17,nil,a[1]end;return nil,nil,a[1]end
local function aJ(a)local c,O=aI(a)if not c then
a("warhead: "..O..". The commands still work: warhead help",0xFF6600)return end;local b,d,n=c.T,c.W,c.H
local e=ar()local j=W.config(e.cfg)local u;local p=U.catalogue()local m,B=1,1;local g="list"
local C,J=nil,"hi"local k={}local q=nil;local h=1;local o,v,w=50,11,3;for aV,aW in ipairs(V.MATERIALS)do
if aW.key=="concrete"then v=aV end end;local function l(aV,aW)C,J=aV,aW or"hi"end;local function G(aV)return
b[aV]or b.fg end;local f,i=3,n-2;local x="list"
local function F()
local aX=g==ae or((g=="map"or
g==ag)and x==ae)local aV=aX and p[1]or p[m]local aW,aY,aZ=U.outcome(aV,j,k)if
aV.kind==_ then
aW.name=q and("Custom Nuke \""..q.."\"")or av end;return aW,W.effects(aW,j),aY,aZ,aV end
local function y(aV)c.fill(1,1,d,1," ",b.bg,b.border)
c.set(2,1,Y("WARHEAD  "..aV,d-30),b.bg,b.border)
local aW=V.SOURCE.. (next(e.cfg)and" +config"or"")c.set(d-ac(aW),1,aW,b.bg,b.border)
c.fill(1,2,d,1,c.mono and"-"or"─",b.dim,b.bg)end
local function z(aV)c.fill(1,n-1,d,1," ",b.fg,b.bg)if C then
c.set(2,n-1,Y(C,d-2),G(J),b.bg)end;c.fill(1,n,d,1," ",b.bg,b.border)
c.set(2,n,Y(U.fitKeys(aV,
ao().." ".. (g=="list"and"Quit"or"Back"),
d-2),d-2),b.bg,b.border)end
local function r(aX,aY,aV,aW,aZ)
for ba,a_ in ipairs(aX)do for ba,bb in ipairs(U.wrap(a_[1],aW))do if aV>aZ then return aV end
c.set(aY,aV,Y(bb,aW),G(a_[2]),b.bg)aV=aV+1 end end;return aV end
local function D(aV,aW)local aX=tostring(aW or"")
while true do
c.fill(1,n-1,d,1," ",b.fg,b.bg)
c.set(2,n-1,Y(aV.." "..aX.."_",d-2),b.title,b.bg)local aY,aZ=ah()if aZ==X.ENTER then return aX end;if ai(aY,aZ)then return nil end;if aZ==
X.BACK then aX=aX:sub(1,-2)elseif aY and aY>=32 and aY<127 then
aX=aX..string.char(aY)end end end
local function K(aV)c.fill(1,n-1,d,1," ",b.fg,b.bg)
c.set(2,n-1,Y(aV.."  (Y/N)",d-2),b.warn,b.bg)
while true do local aW,aX=ah()if ai(aW,aX)then return false end
if aW then
local aY=string.char(aW):lower()if aY=="y"then return true end;if aY=="n"then return false end end end end
local function A(aV,aW,aX)local aZ=aX or""local aY,a_=1,1;local ba,bb,bc,bd=6,4,d-12,n-7
while true do local be={}for bj,bi in ipairs(aW)do
if aZ==""or
bi[1]:lower():find(aZ:lower(),1,true)then be[#be+1]=bi end end;if aY>#be then
aY=math.max(1,#be)end;local bg=bd-3;if aY<a_ then a_=aY end;if aY>a_+bg-1 then
a_=aY-bg+1 end;c.fill(ba,bb,bc,bd," ",b.fg,b.bg)
c.set(ba,bb,Y("[ "..aV..
" ]  filter: "..aZ.."_",bc),b.title,b.bg)
for bi=0,bg-1 do local bj=be[a_+bi]if bj then local bk=(a_+bi==aY)
c.set(ba+1,bb+2+bi,Y(bj[1],bc-2),
bk and b.selfg or G(bj[2]),bk and b.selbg or b.bg)end end
c.set(ba,bb+bd-1,Y("type to filter · Enter pick · "..ao().." cancel",bc),b.dim,b.bg)local bh,bf=ah()if ai(bh,bf)then return nil end;if bf==X.ENTER then return
be[aY]and be[aY][3]end
if bf==X.UP then aY=math.max(1,aY-1)elseif bf==
X.DOWN then aY=math.min(#be,aY+1)elseif bf==X.PGUP then
aY=math.max(1,aY-bg)elseif bf==X.PGDN then aY=math.min(#be,aY+bg)elseif bf==X.BACK then aZ=aZ:sub(1,-2)
aY=1 elseif bh and bh>=32 and bh<127 then aZ=aZ..string.char(bh)aY=1 end end end;local E=30
local function P()local aV,aW={},nil
for aY,aX in ipairs(p)do if aX.group~=aW then
aV[#aV+1]={header=aX.group}aW=aX.group end;aV[#aV+1]={index=aY}end;return aV end
local function Q()y("simulator")local aY=P()local aV=1
for ba,bb in ipairs(aY)do if bb.index==m then aV=ba end end;local aX=i-f+1;if aV<B then B=aV end;if aV>B+aX-1 then B=aV-aX+1 end
c.fill(1,f,d,aX," ",b.fg,b.bg)
for ba=0,aX-1 do local bb=aY[B+ba]local bc=f+ba
if bb then
if bb.header then
c.set(1,bc,Y(" "..bb.header,E),b.title,b.bg)else local be=p[bb.index]local bd=bb.index==m
c.set(1,bc,Y("   "..be.name,E),bd and
b.selfg or b.fg,bd and b.selbg or b.bg)end end end;for ba=f,i do
c.set(E+1,ba,c.mono and"|"or"│",b.dim,b.bg)end;local aZ,a_=F()local aW=Z.lines(aZ,j,a_)if p[m].kind==
_ then aW[#aW+1]={"","fg"}
aW[#aW+1]={"Enter opens the designer.","dim"}end;r(aW,E+3,f,d-E-3,i)
z({"\226\134\145\226\134\147 Select","Enter Design","M Map","S Shelter","K Scan","C Config"})end;local H=16
local function R(aV)
if aV==V.DROP_UPGRADE.key then return"Drop Upgrade"end;local aW=W.byKey[aV]return aW and aW.name or""end
local function S()
y("custom nuke designer".. (q and(" - "..q)or""))c.fill(1,f,d,i-f+1," ",b.fg,b.bg)
c.set(2,f,"Slots (one item each; a stack counts once)",b.dim,b.bg)
for bc=1,V.CUSTOM_SLOTS do local bf=(bc-1)%3;local bg=math.floor((bc-1)/3)
local bh=2+bf*H;local bi=f+1+bg;local bj=k[bc]and R(k[bc])or"."
local bd=(bc==h)local be=k[bc]and W.byKey[k[bc]]local bk=be and
(be.m and b.title or b.fg)or b.dim
c.set(bh,bi,Y(string.format("%2d %s",bc,bj),
H-1),bd and b.selfg or bk,bd and b.selbg or b.bg)end;local aW=2+3*H+1;for bc=f,i do
c.set(aW-1,bc,c.mono and"|"or"│",b.dim,b.bg)end;local a_,ba,bb,aZ=F()local aX=f
c.set(aW+1,aX,"Stages",b.dim,b.bg)
aX=r(Z.stageLines(bb,aZ,j),aW+1,aX+1,d-aW-1,i)aX=aX+1;local aV=Z.summary(a_,j,ba)if aZ.fall then
aV[#aV+1]={"Drop Upgrade: falls first, then goes off.","dim"}end
if aZ.unknown>0 then aV[#aV+1]={aZ.unknown..
" slot(s) add nothing","dim"}end;aV[#aV+1]={"","fg"}
aV[#aV+1]={"M map, S shelter, ^Q back to the full report.","dim"}r(aV,aW+1,aX,d-aW-1,i-1)
local aY=k[h]and W.byKey[k[h]]if aY then
c.set(2,i,Y(string.format("Slot %d: %s, %s %s%s",h,aY.name,V.STAGE_NAME[aY.stage],aY.m and"x"or"+",aa(aY.v)),
aW-3),b.dim,b.bg)end
z({"Enter Pick","Del Clear","B Best","G Save","L Load","K Scan","M Map","S Shelter"})end
local function L(aV)local aW={{"(empty slot)","dim",false}}
for aY,aX in
ipairs(V.INGREDIENTS)do
aW[#aW+1]={string.format("%-30s %-11s %s%s",aX.name,V.STAGE_NAME[aX.stage],aX.m and"x"or"+",aa(aX.v)),
aX.m and"title"or"fg",aX.key}end
aW[#aW+1]={string.format("%-30s %-11s %s",V.DROP_UPGRADE.name,"(any)","falls first"),"dim",V.DROP_UPGRADE.key}return A("ingredient for slot "..h,aW,aV)end
local function aL()u=u or require("warhead.best")local aW={}
for bb,ba in ipairs(u.ORDER)do aW[
#aW+1]={u.GOALS[ba].name,"fg",ba}end;aW[#aW+1]={"Anti Mass (beams)","fg","euph"}
local aX=A("best design: which kind of blast?",aW)if not aX then return end;local aY={}local aZ=aj()
if aZ and
K("Design from the materials in a chest on the transposer?")then local bd=aZ.sides()local ba={}for bg,bf in ipairs(bd)do
ba[#ba+1]={
bf.name.." ("..bf.size.." slots)","fg",bf.side}end
local bb=A("which chest?",ba)if bb==nil then return end;local be=ak(aZ,bb)or{}local bc
aY.stock,bc=U.stockFromContents(be)if bc==0 then
l("That chest holds no custom nuke ingredients.","warn")return end end;if aX=="nuke"or aX=="hydro"then
aY.salt=K("Fill the spare slots with Salted material (longer fallout)?")end;local aV,a_;if aX=="euph"then
aV,a_=u.designEuph(j,aY)else aV,a_=u.design(aX,j,aY)end
if not aV then l(
"No design: "..tostring(a_),"warn")return end;k={}for ba,bb in ipairs(aV.slots)do k[ba]=bb.key end;q=nil;h=1
l(string.format("Best %s: %d slots.",aV.goal.name:lower(),
#aV.slots),"hi")end
local function aM()local aV=D("Save design as:",q or"")
aV=aV and U.cleanName(aV)if not aV or aV==""then return end;local aW={}
for aZ=1,V.CUSTOM_SLOTS do aW[aZ]=k[aZ]end
if not e.designs[aV]then e.order[#e.order+1]=aV end;e.designs[aV]=aW;local aX,aY=ad(e)q=aV
l(
aX and("Saved \""..aV.."\".")or("NOT saved: "..tostring(aY)),
aX and"hi"or"warn")end
local function aN()if#e.order==0 then
l("No saved designs yet (G saves one).","warn")return end;local aW={}
for aY,aX in ipairs(e.order)do
local a_=U.outcome(p[1],j,e.designs[aX])local aZ=W.effects(a_,j)
aW[#aW+1]={string.format("%-24s %s %s",aX,Z.ENGINE[aZ.kind]or
aZ.kind,aZ.radius and("r"..aZ.radius)or""),"fg",aX}end;local aV=A("load design",aW)if not aV then return end;k={}for aX=1,V.CUSTOM_SLOTS do
k[aX]=e.designs[aV][aX]end;q=aV
l("Loaded \""..aV.."\".")end
local function M()local aX,aY=aj()
if not aX then l(au..aY..".","warn")return end;local aW={}
for a_,aZ in ipairs(aX.sides())do local ba=ak(aX,aZ.side)local bb=ba and
U.identify(aZ.size,ba)if bb then
aW[#aW+1]={entry=bb,contents=ba,side=aZ}end end;if#aW==0 then l("No HBM bomb next to the transposer.","warn")
return end;local aV=aW[1]
if#aW>1 then local aZ={}for bb,ba in ipairs(aW)do
aZ[#aZ+1]={
ba.side.name..": "..ba.entry.name,"fg",bb}end;local a_=A("which bomb?",aZ)if
not a_ then return end;aV=aW[a_]end
if aV.entry.kind==_ then local aZ
k,aZ=U.slotsFromContents(aV.contents)q="scanned "..aV.side.name;g=ae
l(
#aZ>0 and string.format("Read it. %d slot(s) hold things that add nothing.",
#aZ)or"Read the custom nuke on the "..aV.side.name.." side.",
#aZ>0 and"warn"or"hi")else local aZ=W.bombOutcome(aV.entry.ref,j,aV.contents)
local a_=Z.lines(aZ,j)
y("scan - "..aV.side.name.." side")c.fill(1,f,d,i-f+1," ",b.fg,b.bg)r(a_,3,f,d-4,i)
l("As loaded. Any key to go back.")z({})ah()C=nil end end
local function N(aV)local aW={}
if aV.kind=="mk5"then
aW[#aW+1]={r=aV.radius,ch="\226\150\136",mono="#",c="r1",label="destroyed"}
aW[#aW+1]={r=aV.lethal,ch="\226\150\147",mono="%",c="r2",label="one tick kills"}aW[#aW+1]={r=aV.blast,ch=aw,mono="+",c="r3",label=ax}if
aV.fallout and aV.fallout>aV.blast then
aW[#aW+1]={r=aV.fallout,ch="\226\150\145",mono=".",c="r4",label="fallout"}end elseif aV.radius then
aW[#aW+1]={r=aV.radius,ch="\226\150\136",mono="#",c="r1",label=
aV.rinse and"rinsed"or"destroyed"}
if aV.blast then
aW[#aW+1]={r=aV.lethal,ch="\226\150\147",mono="%",c="r2",label="one tick kills"}aW[#aW+1]={r=aV.blast,ch=aw,mono="+",c="r3",label=ax}end elseif aV.blast then aW[#aW+1]={r=aV.blast,ch=aw,mono="+",c="r3",label=ax}end;return aW end
local function aO(aV,aW)
for aY,aX in ipairs(N(aV))do if aW<=aX.r then return aX.label,aX.c end end;return"untouched","fg"end
local function aP()local be,bc=F()y("map - ".. (be.name or""))c.fill(1,f,d,
i-f+1," ",b.fg,b.bg)local a_=N(bc)local aY=d-34
local bd=i-f+1;local aX=1;for bg,bf in ipairs(a_)do if bf.r>aX then aX=bf.r end end;for bg,bf in
ipairs(e.places)do
local bh=math.sqrt(bf.dx*bf.dx+bf.dz*bf.dz)if bh>aX then aX=bh end end;aX=aX*
1.05
local ba,bb=math.floor(aY/2)+1,f+math.floor(bd/2)local aZ=math.max(aX/ (aY/2),aX/bd)
for bf=f,i do local bi,bh,bg=1,false,{}
local function bj()if
#bg>0 then
c.set(bi,bf,table.concat(bg),bh and b[bh]or b.fg,b.bg)end end
for bk=1,aY do local bm=(bk-ba)*aZ;local bn=(bf-bb)*aZ*2
local bp=math.sqrt(bm*bm+bn*bn)local bo,bl=" ",nil
for br,bq in ipairs(a_)do if bp<=bq.r then
bo=c.mono and bq.mono or bq.ch;bl=bq.c;break end end;if bl~=bh then bj()bi,bh,bg=bk,bl,{}end;bg[#bg+1]=bo end;bj()end;c.set(ba,bb,"X",b.bg,b.fg)
for bg,bf in ipairs(e.places)do local bh=ba+
math.floor(bf.dx/aZ+0.5)local bi=bb+
math.floor(bf.dz/ (aZ*2)+0.5)if bh>=1 and bh<=aY and bi>=f and
bi<=i then
c.set(bh,bi,tostring(bg%10),b.bg,b.title)end end;local aW=aY+3;local aV=f
c.set(aW,aV,string.format("1 column = %s blocks",aa(aZ)),b.dim,b.bg)aV=aV+1
c.set(aW,aV,"north is up; X is ground zero",b.dim,b.bg)aV=aV+2
for bg,bf in ipairs(a_)do
c.set(aW,aV,c.mono and bf.mono or bf.ch,b[bf.c]or b.fg,b.bg)
c.set(aW+2,aV,Y(string.format("%-15s %d",bf.label,math.floor(bf.r)),d-aW-2),b.fg,b.bg)aV=aV+1 end;aV=aV+1
if#e.places==0 then
r({{"A adds a place (your base, a farm) by its offset from ground zero.","dim"}},aW,aV,
d-aW,i)else
for bg,bf in ipairs(e.places)do if aV>i then break end
local bh=math.sqrt(bf.dx*bf.dx+bf.dz*bf.dz)local bi,bj=aO(bc,bh)
c.set(aW,aV,Y(string.format("%d %s",bg%10,bf.name),d-aW),b.title,b.bg)aV=aV+1
c.set(aW+2,aV,Y(string.format("%s out: %s",aa(bh),bi),d-aW-2),
b[bj]or b.fg,b.bg)aV=aV+1 end end;z({"A Add place","X Remove place"})end
local function aQ()local aV=D("Place name:","")aV=aV and U.cleanName(aV)if
not aV or aV==""then return end
local aW=tonumber(
D("Blocks east of ground zero (west is negative):","0")or"")if not aW then return end
local aX=tonumber(
D("Blocks south of ground zero (north is negative):","0")or"")if not aX then return end
e.places[#e.places+1]={name=aV,dx=math.floor(aW),dz=math.floor(aX)}local aY,aZ=ad(e)
l(aY and("Added "..aV..".")or("Added, but NOT saved: "..
tostring(aZ)),aY and
"hi"or"warn")end
local function aR()if#e.places==0 then return end;local aV={}for aX,aY in ipairs(e.places)do
aV[#aV+1]={aY.name,"fg",aX}end;local aW=A("remove which place?",aV)if not
aW then return end;table.remove(e.places,aW)ad(e)
l("Removed.")end
local function aS()local aY,aW=F()local aX=V.MATERIALS[v]
y("shelter - ".. (aY.name or""))c.fill(1,f,d,i-f+1," ",b.fg,b.bg)local aV=f
c.set(3,aV,string.format("Distance  %-6d  (Up/Down 1, PgUp/PgDn 10)",o),b.fg,b.bg)aV=aV+1
c.set(3,aV,string.format("Material  %-26s  (Left/Right)",aX.name),b.fg,b.bg)aV=aV+1
c.set(3,aV,string.format("Thickness %-6d  (+ / -)",w),b.fg,b.bg)aV=aV+2;local aZ=W.shelter(aY,aW,aX,o,w)
aV=r(Z.shelterLines(aZ,aX,aW),3,aV,d-6,i)
if aW.kind=="mk5"then aV=aV+1
c.set(3,aV,"Blocks of "..aX.name.." that stop it, by distance:",b.dim,b.bg)aV=aV+1;local a_={}
for bb,ba in ipairs({0.05,0.1,0.25,0.5,0.75,0.9})do local bc=math.max(1,math.floor(
aW.radius*ba))
local bd,be=W.wallStop(aW.radius,aX.nuke,bc)
a_[#a_+1]=string.format("%d: %s",bc,be and"never"or tostring(bd))end
r({{table.concat(a_,"   "),"fg"}},3,aV,d-6,i)aV=aV+2
r({{"A straight-on ray is the blast's shortest path through a wall; every slanted ray "..

"loses more. Radiation counts each block's own resistance, so obsidian shields it far ".."better than it stops the blast.","dim"}},3,aV,
d-6,i)end
z({"\226\134\145\226\134\147 Distance","\226\134\144\226\134\146 Material","+/- Thickness"})end;local s=1;local t={}for aV in pairs(V.CONFIG)do t[#t+1]=aV end
table.sort(t)
local function aT()y(al)c.fill(1,f,d,i-f+1," ",b.fg,b.bg)
c.set(3,f,"Your server's hbm.cfg values (sections 03_nukes and 06_explosions).",b.dim,b.bg)local aV=i-f-1;local aW=math.max(1,s-aV+1)
for aX=0,aV-1 do local aY=t[aW+aX]
if aY then local aZ=(
aW+aX==s)local a_=e.cfg[aY]~=nil
local ba=string.format("%-24s %-8s %s",aY,tostring(j[aY]),
a_ and
("(default "..tostring(V.CONFIG[aY])..")")or"")
c.set(3,f+2+aX,Y(ba,d-6),aZ and b.selfg or(a_ and b.hi or b.fg),
aZ and b.selbg or b.bg)end end;z({"Enter Change","R Reset"})end
local function aU()local aV=t[s]
if V.CONFIG_BOOL[aV]then e.cfg[aV]=not j[aV]else local aY=tonumber(
D(aV..":",tostring(j[aV]))or"")if
not aY or aY<0 then return end;e.cfg[aV]=aY end;if e.cfg[aV]==V.CONFIG[aV]then e.cfg[aV]=nil end
j=W.config(e.cfg)local aW,aX=ad(e)
l(aW and"Saved."or("NOT saved: "..tostring(aX)),
aW and"hi"or"warn")end;local function I()
if g=="list"then Q()elseif g==ae then S()elseif g=="map"then aP()elseif g==ag then aS()elseif g==al then aT()end end;I()
while true do
local aW,aV,aX=ah()
if aX=="tos_focus"then I()elseif aW or aV then C=nil;local aY=aW and aW>0 and
string.char(aW):lower()or""
if
ai(aW,aV)then if g=="list"then break end
g=(g=="map"or g==ag)and x or"list"elseif g=="list"then
if aV==X.UP then m=math.max(1,m-1)elseif aV==X.DOWN then
m=math.min(#p,m+1)elseif aV==X.PGUP then m=math.max(1,m-10)elseif aV==X.PGDN then
m=math.min(#p,m+10)elseif aV==X.ENTER and p[m].kind==_ then g=ae elseif aY=="m"then x="list"g="map"elseif aY=="s"then
x="list"g=ag elseif aY=="c"then g=al elseif aY=="k"then M()end elseif g==ae then
if aV==X.LEFT then h=math.max(1,h-1)elseif aV==X.RIGHT then
h=math.min(V.CUSTOM_SLOTS,h+1)elseif aV==X.UP then if h>3 then h=h-3 end elseif aV==X.DOWN then
if h<=V.CUSTOM_SLOTS-3 then h=h+3 end elseif aV==X.DEL or aV==X.BACK then k[h]=nil elseif aV==X.ENTER then local aZ=L()
if aZ~=nil then
k[h]=aZ or nil;h=math.min(V.CUSTOM_SLOTS,h+1)end elseif aY=="b"then aL()elseif aY=="g"then aM()elseif aY=="l"then aN()elseif aY=="k"then M()elseif aY=="m"then x=ae;g="map"elseif aY=="s"then x=ae;g=ag elseif aW and
aW>=32 and aW<127 then local aZ=L(string.char(aW))
if aZ~=nil then k[h]=aZ or
nil;h=math.min(V.CUSTOM_SLOTS,h+1)end end elseif g=="map"then if aY=="a"then aQ()elseif aY=="x"then aR()end elseif g==ag then
if aV==X.UP then o=o+1 elseif
aV==X.DOWN then o=math.max(1,o-1)elseif aV==X.PGUP then o=o+10 elseif aV==X.PGDN then
o=math.max(1,o-10)elseif aV==X.LEFT then v=(v-2)%#V.MATERIALS+1 elseif aV==X.RIGHT then v=v%
#V.MATERIALS+1 elseif aY=="+"or aY=="="then w=math.min(64,w+1)elseif aY==
"-"then w=math.max(1,w-1)end elseif g==al then
if aV==X.UP then s=math.max(1,s-1)elseif aV==X.DOWN then s=math.min(#t,s+1)elseif aV==
X.ENTER then aU()elseif aY=="r"then e.cfg[t[s]]=nil;j=W.config(e.cfg)ad(e)
l("Reset.")end end;I()end end;c.fill(1,1,d,n," ",b.fg,b.bg)end;local function aK(a,b)a=a or{}b=b or print;if a[1]and aH(a,b)then return end
if a[1]then at(b)return end;aJ(b)end;return
{commands={warhead=aK},text=U}