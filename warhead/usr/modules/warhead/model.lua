local u,v="balefire","string"local p=require("warhead.data")local m={}m.D=p;local n=function(a)
return a end;do
local a=pcall(function()return string.pack("f",1.5)end)
if a then n=function(b)
return(string.unpack("f",string.pack("f",b)))end end end
m.f32=n;m.EXACT=(n(0.1)~=0.1)local s=math.floor;local function o(a)if a>=0 then return s(a)end;return-
s(-a)end;m.toInt=o
function m.config(a)local b={}for c,d in
pairs(p.CONFIG)do b[c]=d end
if type(a)=="table"then for c,d in pairs(a)do
if p.CONFIG[c]~=nil and
type(d)==type(p.CONFIG[c])then b[c]=d end end end;return b end;function m.conf(a)
if type(a)=="table"and a.falloutRange~=nil then return a end;return m.config()end
m.byKey={}m.byItem={}for b,a in ipairs(p.INGREDIENTS)do m.byKey[a.key]=a
m.byItem[a.id.. (a.dmg and
("#"..a.dmg)or"")]=a end
function m.lookup(a,b)
if type(a)~=v then return nil end
local c=b and m.byItem[a.."#"..tostring(o(b))]return c or m.byItem[a]end;local function t(a)if type(a)=="table"then return a end
if type(a)==v then return m.byKey[a]end;return nil end
m.asIngredient=t
function m.stages(b,a)a=m.conf(a)local e,g={},{}
for i,h in ipairs(p.STAGES)do e[h]=n(0)g[h]=n(1)end;local d={raw={},off={},capped={},edge={},used=0,unknown=0,fall=false}
for h=1,p.CUSTOM_SLOTS
do local i=b and b[h]
if i~=nil and i~=false then d.used=d.used+1
if
i==p.DROP_UPGRADE.key or
(type(i)=="table"and i.key==p.DROP_UPGRADE.key)then d.fall=true else local j=t(i)if not j then
d.unknown=d.unknown+1 elseif j.m then if j.stage~="EUPH"then
g[j.stage]=n(g[j.stage]*n(j.v))end else
e[j.stage]=n(e[j.stage]+n(j.v))end end end end;local c={}for i,h in ipairs(p.STAGES)do
c[h]=(h=="EUPH")and e[h]or n(e[h]*g[h])d.raw[h]=c[h]end
local function f(i,h,j)if
c[i]>0 and c[h]<j then
d.off[i]=string.format("%s is %s, under the %s it needs",p.STAGE_NAME[h],m.num(c[h]),m.num(j))c[i]=0 end;if
not
m.EXACT and c[h]>0 and math.abs(c[h]-j)<1e-3 then d.edge[h]=true end end;f("NUKE","TNT",16)f("HYDRO","NUKE",100)
f("BALE","NUKE",50)f("SCHRAB","NUKE",50)f("SOL","NUKE",25)if c.EUPH>0 and(c.SCHRAB<1 or
c.SOL<1)then
d.off.EUPH="Anti Mass needs both Schrabidium and Solinium of at least 1"c.EUPH=0 end;for i,h in
ipairs(p.STAGES)do local j=a[p.STAGE_CAP[h]]
if c[h]>j then c[h]=j;d.capped[h]=j end end;return c,d end
function m.customOutcome(b,a)a=m.conf(a)local d,e,f,g=b.TNT,b.NUKE,b.HYDRO,b.BALE
local h,i,j=b.SCHRAB,b.SOL,b.EUPH;local k=math.min(b.DIRTY,a.maxCustomDirtyRadius)local c
if j>0 then
local l=math.min(j,a.maxCustomEuphLvl)c={engine="zomg",via="EUPH",beams=o(100*l),level=l}elseif i>0 then local l=i+h/2+
g/4+f/8+e/16+d/32
c={engine="solinium",via="SOL",raw=l,radius=o(math.min(l,a.maxCustomSolRadius)),formula="Sol + Schrab/2 + Bale/4 + Hydro/8 + Nuke/16 + TNT/32"}elseif h>0 then local l=h+g/2+f/4+e/8+d/16
c={engine="fleija",via="SCHRAB",raw=l,radius=o(math.min(l,a.maxCustomSchrabRadius)),formula="Schrab + Bale/2 + Hydro/4 + Nuke/8 + TNT/16"}elseif g>0 then local l=g+f/2+e/4+d/8
c={engine=u,via="BALE",raw=l,radius=o(math.min(l,a.maxCustomBaleRadius)),formula="Bale + Hydro/2 + Nuke/4 + TNT/8"}elseif f>0 then local l=f+e/2+d/4
c={engine="mk5",via="HYDRO",raw=l,radius=o(math.min(l,a.maxCustomHydroRadius)),falloutAdd=o(
k*0.25),formula="Hydro + Nuke/2 + TNT/4"}elseif e>0 then local l=e+d/2
c={engine="mk5",via="NUKE",raw=l,radius=o(math.min(l,a.maxCustomNukeRadius)),falloutAdd=o(k),formula="Nuke + TNT/2"}elseif d>=75 then
c={engine="mk5",via="TNT",fallout=false,raw=d,radius=o(math.min(d,a.maxCustomTNTRadius)),formula="TNT (75 and over)"}elseif d>0 then
c={engine="large",via="TNT",power=d,formula="TNT (under 75)"}else c={engine="none"}end;if c.raw and c.radius and c.raw>c.radius+1 then
c.cappedAt=c.radius end;return c end
local function w(a)
if type(a)~="table"or type(a.id)~=v then return nil end;local b=tonumber(a.dmg or a.damage)or 0;return a.id,a.id..
"#"..o(b)end
local function q(a,b)local c,d=w(b)if not c then return false end
if type(a)=="table"then for f,e in ipairs(a)do
if q(e,b)then return true end end;return false end;if a:find("#")then return a==d end;return a==c end;m.partMatches=q
function m.partName(a)
if type(a)=="table"then local b={}for d,c in ipairs(a)do
b[#b+1]=m.partName(c)end;return table.concat(b," or ")end;return p.PART_NAME[a]or a end
function m.bombOutcome(a,c,b)c=m.conf(c)
local d={engine=a.engine,fallout=(a.fallout~=false),falloutAdd=0,name=a.name,ready=true,missing={}}
local function e(f,g)if b and not q(g,b[f])then
d.missing[#d.missing+1]={slot=f,want=g}return false end;return true end
if a.perCharge then local f=12;if b then f=0
for g=1,a.slots do if q(a.perCharge,b[g])then f=f+1 end end end;d.charges=f;if f==0 then d.ready=false
d.missing[1]={slot=1,want=a.perCharge}d.radius=0 else
d.radius=o(n(c[a.radius]*f)/12)end;return d end
for f,g in ipairs(a.parts or{})do if not e(f,g)then d.ready=false end end
if a.fixed then d.radius=a.fixed elseif a.filled then local f=true;for g,h in pairs(a.filled)do if b and not q(h,b[g])then
f=false end end
if d.ready and not f then
d.radius=c[a.fizzle]d.fizzle=true
for g,h in pairs(a.filled)do if not q(h,b[g])then
d.missing[#d.missing+1]={slot=g,want=h,optional=true}end end else d.radius=c[a.radius]end else d.radius=c[a.radius]end;if not d.ready then d.radius=0 end;return d end
function m.missileOutcome(a,b)b=m.conf(b)local c
if a.strength then c=o(a.strength)else c=b[a.radius]if a.div then c=o(c/
a.div)end;if a.mult then c=c*a.mult end end
local d={engine=a.engine,fallout=(a.fallout~=false),falloutAdd=a.falloutAdd or 0,name=a.name,ready=true,missing={}}if a.engine=="large"then d.power=c else d.radius=c end;return d end
local function x(a,b)local c=n(n(n(a)/n(255))*n(100))
local e=n(n(b)/n(255))return n((c+1)^ (3*e)-1)end
function m.lossFactor(a,b)a=n(a)if a>=2000000 then return a end;if a<=0 then return 0 end;if a>100 then return(a+1)^
(3*b)-1 end
local c=o(n(n(a*n(255))/n(100)))if c==0 then return(a+1)^ (3*b)-1 end
return x(c,o(b*255))end
function m.ray(a,b)local c=n(n(2*a)*n(0.3))local d,e,f=0,0,0;local g=1/a
while c>0 do local k=e+0.5
local h=k-d;local i=a-d;if i<=1e-9 then break end;local l=h>i-1e-12;if l then h=i end;local j=b(e)if j and
h>1e-9 then
if n(j)>=2000000 then c=0 else
local y=math.max(d,0.009999999776482582)*g;c=c-m.lossFactor(j,y)*h end;f=f+1 end;d=k;if
c<=0 or l then break end;e=e+1 end;return f,c>0 end
function m.craterDepth(a,b)return
m.ray(a,function(c)if c==0 then return nil end;return b end)end
function m.wallStop(a,b,c)return
m.ray(a,function(d)if d>=c then return b end;return nil end)end;local r=0;for a=2,9 do r=r+1/ (5*a+1)end;m.PULSE=2500000*r;function m.dose(a,b)if
a<=0 then return math.huge end;return
m.PULSE/math.max(1,b or 0)/ (a*a)end;function m.doseRadius(a)return math.sqrt(
m.PULSE/a)end
function m.effects(a,b)
b=m.conf(b)local c={kind=a.engine,notes={}}
local function d(e)c.notes[#c.notes+1]=e end
if a.engine=="none"or
(a.radius==0 and a.engine~="large"and a.engine~="zomg")then c.kind="none"
d("Nothing happens: no stage of this bomb is live.")return c end
if a.engine=="mk5"then local e=a.radius;if e==0 then e=25 end;local f=2*e;c.radius,c.strength=e,f;c.rays=o(
7.853981633974483*f*f)
c.energy=n(n(f)*n(0.3))c.blast=2*e
c.lethal=c.blast* (1-p.PLAYER_HP/250)
local g=a.fallout~=false and not b.disableNuclear;c.nuclear=g
if g then
if f>=75 then c.pulse=true
c.sick=math.min(m.doseRadius(p.RAD_SICK),c.blast)
c.death=math.min(m.doseRadius(p.RAD_DEATH),c.blast)else
d("Too small for the radiation pulse (it needs a radius of 38 or more).")end;c.glow=e*1.5
c.fallout=o(
o(e*2.5+ (a.falloutAdd or 0))*b.falloutRange/100)c.falloutAdd=a.falloutAdd or 0 else
d(
b.disableNuclear and"This server's config disables the nuclear part of nukes."or"A clean blast: no radiation pulse, no fallout.")end elseif a.engine=="fleija"then c.radius=a.radius;c.blast=2*a.radius;c.lethal=c.blast* (1-
p.PLAYER_HP/250)c.sphere=true
d("Antimatter: every block in the sphere is deleted except bedrock-class ones.")
d("A Field Disturber or a DFC core within 300 blocks jams it: nothing happens.")elseif a.engine=="solinium"then c.radius=a.radius;c.sphere=true;c.rinse=true
d("Everything living inside the sphere takes 15,000-250,000 RAD every tick.")
d("Plants, leaves and wood go; wasteland, trinitite and taint revert to land.")elseif a.engine==u then c.radius=a.radius;c.blast=2*a.radius;c.lethal=c.blast*
(1-p.PLAYER_HP/250)
d("Balefire: carves the sphere and sets it alight with balefire.")elseif a.engine=="large"then c.power=a.power;c.reachMin,c.reachMax=0.7*a.power/0.225*0.3,
1.3*a.power/0.225*0.3;c.blast=2*
a.power
d("An ordinary explosion (vanilla rules), with HBM's debris on top.")elseif a.engine=="zomg"then c.beams=a.beams
d(string.format("Anti Mass: %d rainbow beams fire off in random directions.",a.beams))end;return c end
function m.shelter(e,a,d,b,c)local f={dist=b,thick=c}
if a.kind=="mk5"then
local g,h=m.wallStop(a.radius,d.nuke,b)f.need=h and nil or g;f.breached=h or g>c;if b>=a.radius then f.need=0
f.breached=false;f.outside=true end;f.blastRange=b<=a.blast
if
a.pulse and b<=a.blast then f.dose=m.dose(b,d.rad*c)end elseif a.sphere or a.kind==u then f.need=nil;f.breached=b<=a.radius
f.outside=not f.breached;f.blastRange=a.blast and b<=a.blast or false
if a.rinse and
b<=a.radius then f.dose=15000+
(250000-15000)* (1-b/a.radius)end end;return f end
function m.num(a)if type(a)~="number"then return tostring(a)end;if
a==math.huge then return"inf"end;local b=string.format("%.2f",a)
b=b:gsub("0+$",""):gsub("%.$","")if b=="-0"then b="0"end;return b end;return m