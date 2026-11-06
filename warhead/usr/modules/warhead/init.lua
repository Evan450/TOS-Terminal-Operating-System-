
local av,aw,ax,ay,az,am,ab,af,ai,aq="Cannot scan: ","Custom Nuke","New place","\226\150\146","blast damage","config","custom","design","shelter","string"local an=require("component")local aA=require("computer")
local X=require("warhead.model")local _=require("warhead.report")local W=X.D;local ac=X.num;local V={}local ad;do
local a,b=pcall(require,"shell.keys")ad=a and b or nil end;local function aj(b,a)if ad and ad.is then return
ad.is("quit",b,a)end
return b==17 or a==68 or a==1 end
local function ao()if ad and ad.label then
local a=ad.label("quit")if a~=""then return a end end;return"^Q"end
local Y={ENTER=28,BACK=14,DEL=211,TAB=15,UP=200,DOWN=208,LEFT=203,RIGHT=205,PGUP=201,PGDN=209,HOME=199,END=207}local function aa(a)local b=0
for c=1,#a do local d=a:byte(c)if d<0x80 or d>=0xC0 then b=b+1 end end;return b end
local function ap(c,d,e)local b,a={},0
for f=1,#c do
local g=c:byte(f)if g<0x80 or g>=0xC0 then a=a+1;b[a]=f end end;b[a+1]=#c+1;d,e=math.max(1,d),math.min(a,e)
if d>e then return""end;return c:sub(b[d],b[e+1]-1)end
local function Z(a,b)a=tostring(a or"")local c=aa(a)if c>b then return ap(a,1,b)end;return a..string.rep(" ",
b-c)end;V.ulen,V.pad=aa,Z
function V.fitKeys(b,a,c)local e=" \194\183 "local d={}for g,f in ipairs(b)do d[#d+1]=f
if aa(
table.concat(d,e)..e..a)>c then d[#d]=nil;break end end;if#d==0 then return a end;return
table.concat(d,e)..e..a end
function V.wrap(a,b,c)if aa(a)<=b then return{a}end;local h,i=0,a;local e=
not c and a:match("^(%u%l+ +)%S")or nil;if e and#e<=12 then
h=math.min(#e,math.floor(b/4))i=a:sub(#e+1)else e=nil end
local f,d={},e or""local g=true
for j in i:gmatch("%S+")do
local k=g and(d..j)or(d.." "..j)if aa(k)>b and not g then f[#f+1]=d;d=string.rep(" ",h)..j else
d=k end;g=false end;if d~=""then f[#f+1]=d end;return f end;local aB=".warhead"
function V.newSettings()return{cfg={},designs={},order={},places={}}end
function V.parseSettings(a)local b=V.newSettings()if type(a)~=aq then return b end
for c in
(a.."\n"):gmatch("(.-)\r?\n")do local d,f=c:match("^cfg (%S+) (%S+)$")if
d and W.CONFIG[d]~=nil then
if W.CONFIG_BOOL[d]then b.cfg[d]=(f=="true")else b.cfg[d]=tonumber(f)end end
local e,h=c:match("^design ([^\t]+)\t(.*)$")
if e then local l={}local k=0
for m in(h..","):gmatch("([^,]*),")do k=k+1
if k>W.CUSTOM_SLOTS then break end;if m~="-"and m~=""and
(X.byKey[m]or m==W.DROP_UPGRADE.key)then l[k]=m end end
if not b.designs[e]then b.order[#b.order+1]=e end;b.designs[e]=l end;local g,i,j=c:match("^place (%-?%d+) (%-?%d+) (.+)$")if g then
b.places[#
b.places+1]={dx=tonumber(g),dz=tonumber(i),name=j}end end;return b end
function V.serializeSettings(a)local b={"WARHEAD1"}local c={}
for d in pairs(a.cfg)do c[#c+1]=d end;table.sort(c)for e,d in ipairs(c)do b[#b+1]="cfg "..
d.." "..tostring(a.cfg[d])end
for e,d in
ipairs(a.order)do local f=a.designs[d]
if f then local g={}
for h=1,W.CUSTOM_SLOTS do local i=f[h]g[h]=
(type(i)=="table"and i.key)or i or"-"end
b[#b+1]="design "..d.."\t"..table.concat(g,",")end end;for e,d in ipairs(a.places)do
b[#b+1]=string.format("place %d %d %s",d.dx,d.dz,d.name)end;return
table.concat(b,"\n").."\n"end
local function ar()if not(fs and fs.home)then return nil end
local b,a=pcall(fs.home)
if not b or type(a)~=aq or a=="/tmp"then return nil end;return a.."/"..aB end
local function as()local a=ar()if a and fs.exists and fs.exists(a)then
local c,b=pcall(fs.readFile,a)
if c and type(b)==aq then return V.parseSettings(b)end end;return
V.newSettings()end
local function ae(a)local c=ar()if not c or not fs.writeFile then
return false,"no home directory to save in"end
local d,b,e=pcall(fs.writeFile,c,V.serializeSettings(a))if not d then return false,tostring(b)end
if b==false or b==nil then return false,tostring(
e or"the write was refused")end;return true end
function V.cleanName(a)
a=tostring(a or""):gsub("[%c]"," "):gsub("^%s+",""):gsub("%s+$","")if aa(a)>24 then a=ap(a,1,24)end;return a end
function V.catalogue()
local a={{group=aw,kind=ab,key=ab,name="Custom Nuke (designer)"}}for d,c in ipairs(W.BOMBS)do
a[#a+1]={group="Bombs",kind="bomb",key=c.key,name=c.name,ref=c}end;for c,b in ipairs(W.MISSILES)do
a[#a+1]={group="Missiles",kind="missile",key=b.key,name=b.name,ref=b}end;for c,b in ipairs(W.WARHEADS)do
a[#a+1]={group="Missile warheads",kind="missile",key=b.key,name=b.name,ref=b}end;return a end
function V.find(a)if type(a)~=aq or a==""then return nil end;local b=a:lower()
local c=V.catalogue()for e,d in ipairs(c)do if d.key==b then return d end end;for e,d in ipairs(c)do if
d.name:lower()==b then return d end end;for e,d in ipairs(c)do if
d.name:lower():find(b,1,true)then return d end end;return nil end
function V.outcome(a,b,c)
if a.kind==ab then local e,f=X.stages(c or{},b)
local d=X.customOutcome(e,b)d.name=aw;d.fall=f.fall;return d,e,f elseif a.kind=="bomb"then
return X.bombOutcome(a.ref,b)end;return X.missileOutcome(a.ref,b)end
local function ak()local b,a=pcall(require,"peripheral.inventory")if not b or
type(a)~="table"or not a.sides then
return nil,"no transposer or inventory controller attached"end
if a.available and
not a.available()then return nil,"no transposer or inventory controller attached"end;return a end;local aC={bottom=0,down=0,top=1,up=1,north=2,south=3,west=4,east=5}
local function al(a,b)
local c,e=a.stacks(b)if not c then return nil,e end;local d={}for g,f in ipairs(c)do
d[f.slot]={id=f.id,dmg=f.damage,count=f.count,label=f.label}end;return d end
function V.identify(b,a)if b==W.CUSTOM_SLOTS then return V.find(ab)end;local c,d
for f,e in
ipairs(W.BOMBS)do
if e.slots==b then local g=0;for h,i in ipairs(e.parts or{})do
if X.partMatches(i,a[h])then g=g+1 end end;for h,i in pairs(e.filled or{})do if
X.partMatches(i,a[h])then g=g+1 end end
if e.perCharge then for h=1,e.slots do if
X.partMatches(e.perCharge,a[h])then g=g+1 end end end;if not d or g>d then c,d=e,g end end end;if not c then return nil end;return V.find(c.key)end
function V.slotsFromContents(a)local b,c={},{}
for d=1,W.CUSTOM_SLOTS do local e=a[d]
if e then local f=X.lookup(e.id,e.dmg)
if f then
b[d]=f.key elseif e.id==W.DROP_UPGRADE.id then b[d]=W.DROP_UPGRADE.key else c[#c+1]={slot=d,label=e.label or
e.id}end end end;return b,c end
function V.stockFromContents(a)local b,c={},0;for e,d in pairs(a)do local f=X.lookup(d.id,d.dmg)
if f then b[f.key]=(b[f.key]or
0)+ (d.count or 1)c=c+1 end end;return b,c end
local function at(b,a)local c=b.sides()
if#c==0 then return nil,"nothing to read on any side"end;if a then local d=aC[a:lower()]or tonumber(a)for f,e in ipairs(c)do if e.side==d then
return e end end
return nil,"no inventory on side "..a end
return c end
local U={title=0xFFFF55,fg=0xFFFFFF,dim=0xAAAAAA,hi=0x55FF55,warn=0xFF5555}local function ag(a,b)
for d,c in ipairs(b)do a(c[1],U[c[2]]or 0xFFFFFF)end end;local function aD()
local b=require("warhead.best")local a={}for d,c in ipairs(b.ORDER)do a[#a+1]=c end;a[#a+1]="euph"
return a,b end
local function aE(a)local b={}
local c,d={},{}
for f,e in ipairs(a.slots)do
local g=type(e)=="table"and e.key or e;if not c[g]then d[#d+1]=g end;c[g]=(c[g]or 0)+1 end;for f,e in ipairs(d)do local g=X.byKey[e]
local h=g and g.name or W.DROP_UPGRADE.name
b[#b+1]={string.format("  %2d x %s",c[e],h),"fg"}end
b[#b+1]={string.format("  %d of %d slots. One item per slot is enough; stacks count once.",
#a.slots,W.CUSTOM_SLOTS),"dim"}return b end
local function au(a)
a("warhead — HBM Nuclear Tech nuke designer and simulator ("..W.SOURCE..")",U.title)
a("  warhead                         the full-screen simulator",U.fg)
a("  warhead list                    every warhead it knows",U.fg)
a("  warhead sim <name>              what one would do (e.g. warhead sim tsar)",U.fg)
a("  warhead best <kind> [radius N] [salt] [stock <side>]",U.fg)
a("                                  design the best custom nuke",U.dim)
a("        kinds: tnt nuke hydro bale schrab sol euph",U.dim)
a("  warhead scan [side]             read a bomb next to a transposer",U.fg)
a("  warhead shelter <name> <dist> <material> [thick]",U.fg)
a("  warhead materials               what a shelter can be built from",U.fg)
a("  warhead config [set K V | reset [K]]   your server's hbm.cfg values",U.fg)end
local function aF(c,b,a)local e=c[2]
if e=="set"then local g,h=c[3],c[4]
if not g or W.CONFIG[g]==nil then b("Unknown key: "..
tostring(g),U.warn)return end
if W.CONFIG_BOOL[g]then if h~="true"and h~="false"then
b(g.." is true or false.",U.warn)return end;a.cfg[g]=(h=="true")else
local k=tonumber(h)
if not k or k<0 then b(g.." needs a number.",U.warn)return end;a.cfg[g]=k end;local i,j=ae(a)
b(i and
("Set "..g.." = "..tostring(a.cfg[g]))or("Not saved: "..tostring(j)),
i and U.hi or U.warn)return elseif e=="reset"then if c[3]then a.cfg[c[3]]=nil else a.cfg={}end
local g,h=ae(a)
b(g and"Reset."or("Not saved: "..tostring(h)),
g and U.hi or U.warn)return end;local f=X.config(a.cfg)local d={}
for g in pairs(W.CONFIG)do d[#d+1]=g end;table.sort(d)
b("Config ("..W.SOURCE.." defaults; * = yours):",U.title)for h,g in ipairs(d)do
b(string.format("  %-22s %-8s%s",g,tostring(f[g]),a.cfg[g]~=nil and" *"or""),
a.cfg[g]~=nil and U.hi or U.fg)end end
local function aG(c,a,b)local e,g=ak()if not e then a(av..g..".",U.warn)return end
local d,h=at(e,c[2])if not d then a(av..h..".",U.warn)return end
if d.side then d={d}end;local f=0
for j,i in ipairs(d)do local l=al(e,i.side)
local k=l and V.identify(i.size,l)
if k then f=f+1
a(string.format("%s side (%d slots): %s",i.name,i.size,k.name),U.title)local m
if k.kind==ab then local n,o=V.slotsFromContents(l)local p
m,p=V.outcome(k,b,n)if m.fall then
a("  Has the Drop Upgrade: it falls, then goes off where it lands.",U.dim)end;for j,q in ipairs(o)do
a(string.format("  slot %d holds %s, which adds nothing",q.slot,q.label),U.dim)end else
m=X.bombOutcome(k.ref,b,l)end;ag(a,_.lines(m,b))a("",U.fg)end end;if f==0 then
a("No HBM bomb found next to the transposer.",U.warn)end end
local function aH(b,a,c)local k,h=aD()local i=b[2]local l=false
for n,d in ipairs(k)do if d==i then l=true end end
if not l then
a("Which kind of blast? "..table.concat(k," "),U.warn)for n,d in ipairs(h.ORDER)do
a(string.format("  %-7s %s",d,h.GOALS[d].name),U.dim)end
a("  euph    Anti Mass (beams)",U.dim)return end;local g={}local e=3
while b[e]do local d=b[e]
if d=="radius"then g.radius=tonumber(b[e+1])e=e+1 elseif d==
"salt"then g.salt=true elseif d=="stock"then local p,r=ak()if not p then
a("Cannot read stock: "..r..".",U.warn)return end;local o,t=at(p,b[e+1])
if
not o or not o.side then a("Name the chest's side: stock <side>.",U.warn)return end;local s=al(p,o.side)local q
g.stock,q=V.stockFromContents(s or{})
a(string.format("Designing from the %s chest (%d ingredient stacks).",o.name,q),U.dim)e=e+1 end;e=e+1 end;local f,j
if i=="euph"then f,j=h.designEuph(c,g)else f,j=h.design(i,c,g)end;if not f then
a("No design: "..tostring(j)..".",U.warn)return end
a("Best "..
f.goal.name:lower().." custom nuke:",U.title)ag(a,aE(f))if f.short then
a("It cannot reach radius "..g.radius.."; this is the most it can do.",U.warn)end;local m=f.outcome;m.name=nil
ag(a,_.lines(m,c))end
local function aI(b,a,c,d)local g=V.find(b[2]or"")
local h,i,j=tonumber(b[3]or""),b[4],tonumber(b[5]or"3")
if not g or not h or not i then
a("Usage: warhead shelter <name> <distance> <material> [thickness]",U.warn)
a("  e.g. warhead shelter tsar 120 concrete 4      (materials: warhead materials)",U.dim)return end;local f=_.mat(i)if not f then
a("Unknown material: "..i.." (see warhead materials).",U.warn)return end
local k=V.outcome(g,c,d.designs[d.order[1]or""])local l=X.effects(k,c)
a(string.format("%s, %s wall %d thick at %d blocks:",g.name,f.name,j,h),U.title)
ag(a,_.shelterLines(X.shelter(k,l,f,h,j),f,l))end
local function aJ(b,a)local e=as()local d=X.config(e.cfg)local c=b[1]
if c=="help"or c=="-h"or
c=="--help"then au(a)elseif c=="list"then local f
for h,g in ipairs(V.catalogue())do if g.group~=f then
a(g.group,U.title)f=g.group end
local i=string.format("  %-18s %s",g.key,g.name)
if g.kind~=ab then local j=V.outcome(g,d)
i=i..
"  -  "..
(_.ENGINE[j.engine]or j.engine)..
(j.radius and(" r"..j.radius)or(j.power and
(" power "..ac(j.power))or""))end;a(i,U.fg)end elseif c=="sim"then local f=table.concat(b," ",2)
if
f:match("^design ")or e.designs[f]then
local h=e.designs[f]and f or f:gsub("^design ","")local i=e.designs[h]if not i then
a("No saved design called "..h..".",U.warn)return end
local j=V.outcome(V.find(ab),d,i)j.name="Custom Nuke \""..h.."\""
ag(a,_.lines(j,d))return end;local g=V.find(f)if not g or g.kind==ab then
a("Which warhead? `warhead list` shows them; a saved design is `warhead sim design <name>`.",U.warn)return end
ag(a,_.lines(V.outcome(g,d),d))elseif c=="best"then aH(b,a,d)elseif c=="scan"then aG(b,a,d)elseif c==ai then aI(b,a,d,e)elseif c=="materials"then
a("Material             nuke  radiation   (resistance; see README)",U.title)for g,f in ipairs(W.MATERIALS)do
a(string.format("  %-10s %-24s %8s %8s",f.key,f.name,ac(f.nuke),ac(f.rad)),U.fg)end elseif c==am then aF(b,a,e)else return
false end;return true end
local function aK(a)local h=an.list and an.list("gpu")()if not h then
return nil,"no GPU"end;local i,c=pcall(an.proxy,h)if not i or not c then
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
local function ah()local a={aA.pullSignal()}
if a[1]=="key_down"then return a[3],a[4],a[1]end;if a[1]=="interrupted"then return 17,nil,a[1]end;return nil,nil,a[1]end
local function aL(a)local c,Q=aK(a)if not c then
a("warhead: "..Q..". The commands still work: warhead help",0xFF6600)return end;local b,d,o=c.T,c.W,c.H
local e=as()local j=X.config(e.cfg)local w;local p=V.catalogue()local m,D=1,1;local g="list"
local q,I=nil,"hi"local k={}local r=nil;local h=1;local n,x,y=50,11,3;for aZ,a_ in ipairs(W.MATERIALS)do
if a_.key=="concrete"then x=aZ end end;local function l(aZ,a_)q,I=aZ,a_ or"hi"end;local function G(aZ)return
b[aZ]or b.fg end;local f,i=3,o-2;local z="list"
local function H()
local ba=g==af or((g=="map"or
g==ai)and z==af)local aZ=ba and p[1]or p[m]local a_,bb,bc=V.outcome(aZ,j,k)if
aZ.kind==ab then
a_.name=r and("Custom Nuke \""..r.."\"")or aw end;return a_,X.effects(a_,j),bb,bc,aZ end
local function A(aZ)c.fill(1,1,d,1," ",b.bg,b.border)
c.set(2,1,Z("WARHEAD  "..aZ,d-30),b.bg,b.border)
local a_=W.SOURCE.. (next(e.cfg)and" +config"or"")c.set(d-aa(a_),1,a_,b.bg,b.border)
c.fill(1,2,d,1,c.mono and"-"or"─",b.dim,b.bg)end
local function B(aZ)c.fill(1,o-1,d,1," ",b.fg,b.bg)if q then
c.set(2,o-1,Z(q,d-2),G(I),b.bg)end;c.fill(1,o,d,1," ",b.bg,b.border)
c.set(2,o,Z(V.fitKeys(aZ,
ao().." ".. (g=="list"and"Quit"or"Back"),
d-2),d-2),b.bg,b.border)end
local function s(ba,bb,aZ,a_,bc)
for be,bd in ipairs(ba)do for be,bf in ipairs(V.wrap(bd[1],a_))do if aZ>bc then return aZ end
c.set(bb,aZ,Z(bf,a_),G(bd[2]),b.bg)aZ=aZ+1 end end;return aZ end;local u
local function L(bc,aZ,a_,ba,bb)local bd=c.mono;local bh,be=bd and"="or"═",bd and"|"or"║"
if
not bd then
c.set(aZ+1,a_+bb,string.rep(" ",ba),b.bg,0x1A1A1A)c.fill(aZ+ba,a_+1,1,bb," ",b.bg,0x1A1A1A)end;local bf=string.rep(bh,ba-2)
c.set(aZ,a_,(bd and"+"or"╔")..bf.. (
bd and"+"or"╗"),b.border,b.bg)
c.set(aZ,a_+bb-1,(bd and"+"or"╚")..
bf.. (bd and"+"or"╝"),b.border,b.bg)c.fill(aZ,a_+1,1,bb-2,be,b.border,b.bg)c.fill(aZ+ba-1,a_+1,1,
bb-2,be,b.border,b.bg)
c.fill(aZ+1,a_+1,ba-2,bb-2," ",b.fg,b.bg)local bg=Z(bc,math.min(aa(bc),ba-6))
c.set(aZ+math.floor((
ba-aa(bg)-4)/2),a_,
(bd and"[ "or"╡ ")..bg.. (bd and" ]"or" ╞"),b.title,b.bg)end
local function J(a_,ba,bb,bc,aZ)u()local bd=math.min(d-12,60)local bi=V.wrap(ba,bd-4,true)local bg=math.min(
#bi,o-8-aZ)local bh=bg+aZ+4
local be,bf=
math.floor((d-bd)/2)+1,math.floor((o-bh)/2)+1;L(a_,be,bf,bd,bh)for bj=1,bg do
c.set(be+2,bf+bj,Z(bi[bj],bd-4),G(bb),b.bg)end
c.set(be+2,bf+bh-2,Z(bc,bd-4),b.dim,b.bg)return be,bf+bg+1,bd end
local function E(aZ,a_,ba)local bb=tostring(ba or"")local bc=bb~=""
local be,bf,bd=J(aZ,a_,"fg","Enter OK · "..ao().." cancel",1)
while true do local bg=bb.."_"local bj=aa(bg)- (bd-4)if bj>0 then
bg=ap(bg,bj+1,aa(bg))end
c.set(be+2,bf,Z(bg,bd-4),b.title,b.bg)local bh,bi=ah()if bi==Y.ENTER then return bb end;if aj(bh,bi)then return nil end
if bi==
Y.BACK then bb=bb:sub(1,-2)elseif bh and bh>=32 and bh<127 then if bc then bb=""end;bb=bb..
string.char(bh)end;bc=false end end
local function M(aZ)J("Confirm",aZ,"warn","Y Yes · N No",0)
while true do local a_,ba=ah()if
aj(a_,ba)then return false end
if a_ then
local bb=string.char(a_):lower()if bb=="y"then return true end;if bb=="n"then return false end end end end
local function R(aZ,a_)q=nil;J("Warhead",aZ,a_,"Any key to go on",0)local ba,bb;repeat
ba,bb=ah()until ba or bb end
local function C(aZ,a_,ba)local bc=ba or""local bb,bd=1,1;local be,bf,bg,bi=6,4,d-12,o-7;u()L(aZ,be,bf,bg,bi)
c.set(be+2,
bf+bi-2,Z("Type to filter · Enter pick · "..ao().." cancel",bg-4),b.dim,b.bg)
while true do local bh={}for bo,bn in ipairs(a_)do
if bc==""or
bn[1]:lower():find(bc:lower(),1,true)then bh[#bh+1]=bn end end;if bb>#bh then
bb=math.max(1,#bh)end;local bk=bi-4;if bb<bd then bd=bb end;if bb>bd+bk-1 then
bd=bb-bk+1 end
local bm=(#bh==0 and 0 or bb).."/"..#bh
c.set(be+2,bf+1,Z("Filter: "..bc.."_",bg-5-aa(bm)).." "..bm,b.title,b.bg)c.fill(be+1,bf+2,bg-2,bk," ",b.fg,b.bg)if#bh==0 then
c.set(be+2,bf+2,"Nothing matches.",b.dim,b.bg)end
for bn=0,bk-1 do local bo=bh[bd+bn]if bo then
local bp=(bd+bn==bb)
c.set(be+1,bf+2+bn,Z(" "..bo[1],bg-2),bp and b.selfg or G(bo[2]),bp and
b.selbg or b.bg)end end;local bl,bj=ah()if aj(bl,bj)then return nil end;if bj==Y.ENTER then return
bh[bb]and bh[bb][3]end
if bj==Y.UP then bb=math.max(1,bb-1)elseif bj==
Y.DOWN then bb=math.min(#bh,bb+1)elseif bj==Y.PGUP then
bb=math.max(1,bb-bk)elseif bj==Y.PGDN then bb=math.min(#bh,bb+bk)elseif bj==Y.BACK then bc=bc:sub(1,-2)
bb=1 elseif bl and bl>=32 and bl<127 then bc=bc..string.char(bl)bb=1 end end end;local F=30
local function S()local aZ,a_={},nil
for bb,ba in ipairs(p)do if ba.group~=a_ then
aZ[#aZ+1]={header=ba.group}a_=ba.group end;aZ[#aZ+1]={index=bb}end;return aZ end
local function T()A("simulator")local bb=S()local aZ=1
for be,bf in ipairs(bb)do if bf.index==m then aZ=be end end;local ba=i-f+1;if aZ<D then D=aZ end;if aZ>D+ba-1 then D=aZ-ba+1 end
c.fill(1,f,d,ba," ",b.fg,b.bg)
for be=0,ba-1 do local bf=bb[D+be]local bg=f+be
if bf then
if bf.header then
c.set(1,bg,Z(" "..bf.header,F),b.title,b.bg)else local bi=p[bf.index]local bh=bf.index==m
c.set(1,bg,Z("   "..bi.name,F),bh and
b.selfg or b.fg,bh and b.selbg or b.bg)end end end;for be=f,i do
c.set(F+1,be,c.mono and"|"or"│",b.dim,b.bg)end;local bc,bd=H()local a_=_.lines(bc,j,bd)if p[m].kind==
ab then a_[#a_+1]={"","fg"}
a_[#a_+1]={"Enter opens the designer.","dim"}end;s(a_,F+3,f,d-F-3,i)
B({"\226\134\145\226\134\147 Select","Enter Design","M Map","S Shelter","K Scan","C Config"})end;local K=16
local function aN(aZ)
if aZ==W.DROP_UPGRADE.key then return"Drop Upgrade"end;local a_=X.byKey[aZ]return a_ and a_.name or""end
local function aO()
A("custom nuke designer".. (r and(" - "..r)or""))c.fill(1,f,d,i-f+1," ",b.fg,b.bg)
c.set(2,f,"Slots (one item each; a stack counts once)",b.dim,b.bg)
for bg=1,W.CUSTOM_SLOTS do local bj=(bg-1)%3;local bk=math.floor((bg-1)/3)
local bl=2+bj*K;local bm=f+1+bk;local bn=k[bg]and aN(k[bg])or"."
local bh=(bg==h)local bi=k[bg]and X.byKey[k[bg]]local bo=bi and
(bi.m and b.title or b.fg)or b.dim
c.set(bl,bm,Z(string.format("%2d %s",bg,bn),
K-1),bh and b.selfg or bo,bh and b.selbg or b.bg)end;local a_=2+3*K+1;for bg=f,i do
c.set(a_-1,bg,c.mono and"|"or"│",b.dim,b.bg)end;local bd,be,bf,bc=H()local ba=f
c.set(a_+1,ba,"Stages",b.dim,b.bg)
ba=s(_.stageLines(bf,bc,j),a_+1,ba+1,d-a_-1,i)ba=ba+1;local aZ=_.summary(bd,j,be)if bc.fall then
aZ[#aZ+1]={"Drop Upgrade: falls first, then goes off.","dim"}end
if bc.unknown>0 then aZ[#aZ+1]={bc.unknown..
" slot(s) add nothing","dim"}end;aZ[#aZ+1]={"","fg"}
aZ[#aZ+1]={"M map, S shelter, ^Q back to the full report.","dim"}s(aZ,a_+1,ba,d-a_-1,i-1)
local bb=k[h]and X.byKey[k[h]]if bb then
c.set(2,i,Z(string.format("Slot %d: %s, %s %s%s",h,bb.name,W.STAGE_NAME[bb.stage],bb.m and"x"or"+",ac(bb.v)),
a_-3),b.dim,b.bg)end
B({"Enter Pick","Del Clear","B Best","G Save","L Load","K Scan","M Map","S Shelter"})end
local function N(aZ)local a_={{"(empty slot)","dim",false}}
for bb,ba in
ipairs(W.INGREDIENTS)do
a_[#a_+1]={string.format("%-30s %-11s %s%s",ba.name,W.STAGE_NAME[ba.stage],ba.m and"x"or"+",ac(ba.v)),
ba.m and"title"or"fg",ba.key}end
a_[#a_+1]={string.format("%-30s %-11s %s",W.DROP_UPGRADE.name,"(any)","falls first"),"dim",W.DROP_UPGRADE.key}return C("ingredient for slot "..h,a_,aZ)end
local function aP()w=w or require("warhead.best")local a_={}
for bf,be in ipairs(w.ORDER)do a_[
#a_+1]={w.GOALS[be].name,"fg",be}end;a_[#a_+1]={"Anti Mass (beams)","fg","euph"}
local ba=C("best design: which kind of blast?",a_)if not ba then return end;local bb={}local bc=ak()
if bc and
M("Design from the materials in a chest on the transposer?")then local bh=bc.sides()local be={}for bk,bj in ipairs(bh)do
be[#be+1]={
bj.name.." ("..bj.size.." slots)","fg",bj.side}end
local bf=C("which chest?",be)if bf==nil then return end;local bi=al(bc,bf)or{}local bg
bb.stock,bg=V.stockFromContents(bi)if bg==0 then
l("That chest holds no custom nuke ingredients.","warn")return end end;if ba=="nuke"or ba=="hydro"then
bb.salt=M("Fill the spare slots with Salted material (longer fallout)?")end;local aZ,bd;if ba=="euph"then
aZ,bd=w.designEuph(j,bb)else aZ,bd=w.design(ba,j,bb)end
if not aZ then l(
"No design: "..tostring(bd),"warn")return end;k={}for be,bf in ipairs(aZ.slots)do k[be]=bf.key end;r=nil;h=1
l(string.format("Best %s: %d slots.",aZ.goal.name:lower(),
#aZ.slots),"hi")end
local function aQ()local aZ=E("Save design","Save design as:",r or"")aZ=aZ and
V.cleanName(aZ)if not aZ or aZ==""then return end;local a_={}for bc=1,W.CUSTOM_SLOTS do
a_[bc]=k[bc]end;if not e.designs[aZ]then
e.order[#e.order+1]=aZ end;e.designs[aZ]=a_;local ba,bb=ae(e)r=aZ
l(ba and("Saved \""..
aZ.."\".")or
("NOT saved: "..tostring(bb)),ba and"hi"or"warn")end
local function aR()if#e.order==0 then
l("No saved designs yet (G saves one).","warn")return end;local a_={}
for bb,ba in ipairs(e.order)do
local bd=V.outcome(p[1],j,e.designs[ba])local bc=X.effects(bd,j)
a_[#a_+1]={string.format("%-24s %s %s",ba,_.ENGINE[bc.kind]or
bc.kind,bc.radius and("r"..bc.radius)or""),"fg",ba}end;local aZ=C("load design",a_)if not aZ then return end;k={}for ba=1,W.CUSTOM_SLOTS do
k[ba]=e.designs[aZ][ba]end;r=aZ
l("Loaded \""..aZ.."\".")end
local function O()local ba,bb=ak()
if not ba then l(av..bb..".","warn")return end;local a_={}
for bd,bc in ipairs(ba.sides())do local be=al(ba,bc.side)local bf=be and
V.identify(bc.size,be)if bf then
a_[#a_+1]={entry=bf,contents=be,side=bc}end end;if#a_==0 then l("No HBM bomb next to the transposer.","warn")
return end;local aZ=a_[1]
if#a_>1 then local bc={}for bf,be in ipairs(a_)do
bc[#bc+1]={
be.side.name..": "..be.entry.name,"fg",bf}end;local bd=C("which bomb?",bc)if
not bd then return end;aZ=a_[bd]end
if aZ.entry.kind==ab then local bc
k,bc=V.slotsFromContents(aZ.contents)r="scanned "..aZ.side.name;g=af
l(
#bc>0 and string.format("Read it. %d slot(s) hold things that add nothing.",
#bc)or"Read the custom nuke on the "..aZ.side.name.." side.",
#bc>0 and"warn"or"hi")else local bc=X.bombOutcome(aZ.entry.ref,j,aZ.contents)
local bd=_.lines(bc,j)
A("scan - "..aZ.side.name.." side")c.fill(1,f,d,i-f+1," ",b.fg,b.bg)s(bd,3,f,d-4,i)
l("As loaded. Any key to go back.")B({})ah()q=nil end end
local function P(aZ)local a_={}
if aZ.kind=="mk5"then
a_[#a_+1]={r=aZ.radius,ch="\226\150\136",mono="#",c="r1",label="destroyed"}
a_[#a_+1]={r=aZ.lethal,ch="\226\150\147",mono="%",c="r2",label="one tick kills"}a_[#a_+1]={r=aZ.blast,ch=ay,mono="+",c="r3",label=az}if
aZ.fallout and aZ.fallout>aZ.blast then
a_[#a_+1]={r=aZ.fallout,ch="\226\150\145",mono=".",c="r4",label="fallout"}end elseif aZ.radius then
a_[#a_+1]={r=aZ.radius,ch="\226\150\136",mono="#",c="r1",label=
aZ.rinse and"rinsed"or"destroyed"}
if aZ.blast then
a_[#a_+1]={r=aZ.lethal,ch="\226\150\147",mono="%",c="r2",label="one tick kills"}a_[#a_+1]={r=aZ.blast,ch=ay,mono="+",c="r3",label=az}end elseif aZ.blast then a_[#a_+1]={r=aZ.blast,ch=ay,mono="+",c="r3",label=az}end;return a_ end
local function aS(aZ,a_)
for bb,ba in ipairs(P(aZ))do if a_<=ba.r then return ba.label,ba.c end end;return"untouched","fg"end
local function aT()local bi,bg=H()A("map - ".. (bi.name or""))c.fill(1,f,d,
i-f+1," ",b.fg,b.bg)local bd=P(bg)local bb=d-34
local bh=i-f+1;local ba=1;for bk,bj in ipairs(bd)do if bj.r>ba then ba=bj.r end end;for bk,bj in
ipairs(e.places)do
local bl=math.sqrt(bj.dx*bj.dx+bj.dz*bj.dz)if bl>ba then ba=bl end end;ba=ba*
1.05
local be,bf=math.floor(bb/2)+1,f+math.floor(bh/2)local bc=math.max(ba/ (bb/2),ba/bh)
for bj=f,i do local bm,bl,bk=1,false,{}
local function bn()if
#bk>0 then
c.set(bm,bj,table.concat(bk),bl and b[bl]or b.fg,b.bg)end end
for bo=1,bb do local bq=(bo-be)*bc;local br=(bj-bf)*bc*2
local bt=math.sqrt(bq*bq+br*br)local bs,bp=" ",nil
for bv,bu in ipairs(bd)do if bt<=bu.r then
bs=c.mono and bu.mono or bu.ch;bp=bu.c;break end end;if bp~=bl then bn()bm,bl,bk=bo,bp,{}end;bk[#bk+1]=bs end;bn()end;c.set(be,bf,"X",b.bg,b.fg)
for bk,bj in ipairs(e.places)do local bl=be+
math.floor(bj.dx/bc+0.5)local bm=bf+
math.floor(bj.dz/ (bc*2)+0.5)if bl>=1 and bl<=bb and bm>=f and
bm<=i then
c.set(bl,bm,tostring(bk%10),b.bg,b.title)end end;local a_=bb+3;local aZ=f
c.set(a_,aZ,string.format("1 column = %s blocks",ac(bc)),b.dim,b.bg)aZ=aZ+1
c.set(a_,aZ,"north is up; X is ground zero",b.dim,b.bg)aZ=aZ+2
for bk,bj in ipairs(bd)do
c.set(a_,aZ,c.mono and bj.mono or bj.ch,b[bj.c]or b.fg,b.bg)
c.set(a_+2,aZ,Z(string.format("%-15s %d",bj.label,math.floor(bj.r)),d-a_-2),b.fg,b.bg)aZ=aZ+1 end;aZ=aZ+1
if#e.places==0 then
s({{"A adds a place (your base, a farm) by its offset from ground zero.","dim"}},a_,aZ,
d-a_,i)else
for bk,bj in ipairs(e.places)do if aZ>i then break end
local bl=math.sqrt(bj.dx*bj.dx+bj.dz*bj.dz)local bm,bn=aS(bg,bl)
c.set(a_,aZ,Z(string.format("%d %s",bk%10,bj.name),d-a_),b.title,b.bg)aZ=aZ+1
c.set(a_+2,aZ,Z(string.format("%s out: %s",ac(bl),bm),d-a_-2),
b[bn]or b.fg,b.bg)aZ=aZ+1 end end;B({"A Add place","X Remove place"})end
local function aU()local aZ=E(ax,"Place name:","")
aZ=aZ and V.cleanName(aZ)if not aZ or aZ==""then return end
local a_=tonumber(
E(ax,"Blocks east of ground zero (west is negative):","0")or"")if not a_ then return end
local ba=tonumber(
E(ax,"Blocks south of ground zero (north is negative):","0")or"")if not ba then return end
e.places[#e.places+1]={name=aZ,dx=math.floor(a_),dz=math.floor(ba)}local bb,bc=ae(e)
l(bb and("Added "..aZ..".")or("Added, but NOT saved: "..
tostring(bc)),bb and
"hi"or"warn")end
local function aV()if#e.places==0 then return end;local aZ={}for ba,bb in ipairs(e.places)do
aZ[#aZ+1]={bb.name,"fg",ba}end;local a_=C("remove which place?",aZ)if not
a_ then return end;table.remove(e.places,a_)ae(e)
l("Removed.")end
local function aW()local bb,a_=H()local ba=W.MATERIALS[x]
A("shelter - ".. (bb.name or""))c.fill(1,f,d,i-f+1," ",b.fg,b.bg)local aZ=f
c.set(3,aZ,string.format("Distance  %-6d  (Up/Down 1, PgUp/PgDn 10)",n),b.fg,b.bg)aZ=aZ+1
c.set(3,aZ,string.format("Material  %-26s  (Left/Right)",ba.name),b.fg,b.bg)aZ=aZ+1
c.set(3,aZ,string.format("Thickness %-6d  (+ / -)",y),b.fg,b.bg)aZ=aZ+2;local bc=X.shelter(bb,a_,ba,n,y)
aZ=s(_.shelterLines(bc,ba,a_),3,aZ,d-6,i)
if a_.kind=="mk5"then aZ=aZ+1
c.set(3,aZ,"Blocks of "..ba.name.." that stop it, by distance:",b.dim,b.bg)aZ=aZ+1;local bd={}
for bf,be in ipairs({0.05,0.1,0.25,0.5,0.75,0.9})do local bg=math.max(1,math.floor(
a_.radius*be))
local bh,bi=X.wallStop(a_.radius,ba.nuke,bg)
bd[#bd+1]=string.format("%d: %s",bg,bi and"never"or tostring(bh))end
s({{table.concat(bd,"   "),"fg"}},3,aZ,d-6,i)aZ=aZ+2
s({{"A straight-on ray is the blast's shortest path through a wall; every slanted ray "..

"loses more. Radiation counts each block's own resistance, so obsidian shields it far ".."better than it stops the blast.","dim"}},3,aZ,
d-6,i)end
B({"\226\134\145\226\134\147 Distance","\226\134\144\226\134\146 Material","+/- Thickness"})end;local t=1;local v={}for aZ in pairs(W.CONFIG)do v[#v+1]=aZ end
table.sort(v)
local function aX()A(am)c.fill(1,f,d,i-f+1," ",b.fg,b.bg)
c.set(3,f,"Your server's hbm.cfg values (sections 03_nukes and 06_explosions).",b.dim,b.bg)local aZ=i-f-1;local a_=math.max(1,t-aZ+1)
for ba=0,aZ-1 do local bb=v[a_+ba]
if bb then local bc=(
a_+ba==t)local bd=e.cfg[bb]~=nil
local be=string.format("%-24s %-8s %s",bb,tostring(j[bb]),
bd and
("(default "..tostring(W.CONFIG[bb])..")")or"")
c.set(3,f+2+ba,Z(be,d-6),bc and b.selfg or(bd and b.hi or b.fg),
bc and b.selbg or b.bg)end end;B({"Enter Change","R Reset"})end
local function aY()local aZ=v[t]
if W.CONFIG_BOOL[aZ]then e.cfg[aZ]=not j[aZ]else
local bb=tonumber(
E("Config",aZ..":",tostring(j[aZ]))or"")if not bb or bb<0 then return end;e.cfg[aZ]=bb end;if e.cfg[aZ]==W.CONFIG[aZ]then e.cfg[aZ]=nil end
j=X.config(e.cfg)local a_,ba=ae(e)
l(a_ and"Saved."or("NOT saved: "..tostring(ba)),
a_ and"hi"or"warn")end
u=function()
if g=="list"then T()elseif g==af then aO()elseif g=="map"then aT()elseif g==ai then aW()elseif g==am then aX()end end;u()
while true do local a_,aZ,ba=ah()
if ba=="tos_focus"then u()elseif a_ or aZ then q=nil;local bb=a_ and a_>0 and
string.char(a_):lower()or""
if
aj(a_,aZ)then if g=="list"then break end
g=(g=="map"or g==ai)and z or"list"elseif g=="list"then
if aZ==Y.UP then m=math.max(1,m-1)elseif aZ==Y.DOWN then
m=math.min(#p,m+1)elseif aZ==Y.PGUP then m=math.max(1,m-10)elseif aZ==Y.PGDN then
m=math.min(#p,m+10)elseif aZ==Y.ENTER and p[m].kind==ab then g=af elseif bb=="m"then z="list"g="map"elseif bb=="s"then
z="list"g=ai elseif bb=="c"then g=am elseif bb=="k"then O()end elseif g==af then
if aZ==Y.LEFT then h=math.max(1,h-1)elseif aZ==Y.RIGHT then
h=math.min(W.CUSTOM_SLOTS,h+1)elseif aZ==Y.UP then if h>3 then h=h-3 end elseif aZ==Y.DOWN then
if h<=W.CUSTOM_SLOTS-3 then h=h+3 end elseif aZ==Y.DEL or aZ==Y.BACK then k[h]=nil elseif aZ==Y.ENTER then local bc=N()
if bc~=nil then
k[h]=bc or nil;h=math.min(W.CUSTOM_SLOTS,h+1)end elseif bb=="b"then aP()elseif bb=="g"then aQ()elseif bb=="l"then aR()elseif bb=="k"then O()elseif bb=="m"then z=af;g="map"elseif bb=="s"then z=af;g=ai elseif a_ and
a_>=32 and a_<127 then local bc=N(string.char(a_))
if bc~=nil then k[h]=bc or
nil;h=math.min(W.CUSTOM_SLOTS,h+1)end end elseif g=="map"then if bb=="a"then aU()elseif bb=="x"then aV()end elseif g==ai then
if aZ==Y.UP then n=n+1 elseif
aZ==Y.DOWN then n=math.max(1,n-1)elseif aZ==Y.PGUP then n=n+10 elseif aZ==Y.PGDN then
n=math.max(1,n-10)elseif aZ==Y.LEFT then x=(x-2)%#W.MATERIALS+1 elseif aZ==Y.RIGHT then x=x%
#W.MATERIALS+1 elseif bb=="+"or bb=="="then y=math.min(64,y+1)elseif bb==
"-"then y=math.max(1,y-1)end elseif g==am then
if aZ==Y.UP then t=math.max(1,t-1)elseif aZ==Y.DOWN then t=math.min(#v,t+1)elseif aZ==
Y.ENTER then aY()elseif bb=="r"then e.cfg[v[t]]=nil;j=X.config(e.cfg)ae(e)
l("Reset.")end end;u()if q and aa(q)>d-2 then R(q,I)u()end end end;c.fill(1,1,d,o," ",b.fg,b.bg)end;local function aM(a,b)a=a or{}b=b or print;if a[1]and aJ(a,b)then return end
if a[1]then au(b)return end;aL(b)end;return
{commands={warhead=aM},text=V}