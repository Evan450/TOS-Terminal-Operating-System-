
local l="Blast     hurts to %d in line of sight; one tick kills (20 HP) inside %d"local h=require("warhead.model")local j=h.D;local i=h.num;local g={}
g.ENGINE={mk5="Nuclear blast (MK5)",fleija="Antimatter sphere (MK3)",solinium="Solinium rinse (MK3)",balefire="Balefire",large="Ordinary explosion",zomg="Anti Mass",none="Nothing"}g.CRATER_MATS={"stone","dirt","concrete"}
local function k(a)for c,b in ipairs(j.MATERIALS)do if
b.key==a then return b end end end;g.mat=k
function g.lines(b,c,a)c=h.conf(c)a=a or h.effects(b,c)local f={}local function d(n,o)f[#f+1]={n,o or
"fg"}end
if b.name then d(b.name,"title")end
if b.ready==false then d("WILL NOT DETONATE. Missing:","warn")
for o,n in ipairs(
b.missing or{})do if not n.optional then
d(string.format("  slot %d: %s",n.slot,h.partName(n.want)),"warn")end end;return f end
if b.fizzle then
d(string.format("Fizzles to Fat Man's %d: its second stage is incomplete.",b.radius),"warn")
for o,n in ipairs(b.missing or{})do if n.optional then
d(string.format("  slot %d wants %s",n.slot,h.partName(n.want)),"dim")end end end
if b.charges and b.charges<12 then
d(string.format("%d of 12 charges loaded: %d%% of the full yield.",b.charges,math.floor(
b.charges*100/12)),"dim")end;local e=a.kind;if e=="none"then
d("Nothing happens: no stage of this bomb is live.","warn")return f end
local m=g.ENGINE[e]or e;if a.radius then m=m..", radius "..a.radius elseif a.power then m=m..
", power "..i(a.power)end
d(m,"hi")
if b.formula and b.raw then local n=b.formula.." = "..i(b.raw)
if
b.cappedAt then n=n..", capped at "..b.cappedAt end;d(n,"dim")end
if e=="mk5"then local n={}
for p,o in ipairs(g.CRATER_MATS)do local q=k(o)
local r,s=h.craterDepth(a.radius,q.nuke)
n[#n+1]=(s and("all "..r)or tostring(r)).." into "..
q.name:lower():match("^[%w]+")end
d("Blocks    carved to "..
a.radius.." through air; digs "..table.concat(n,", "))
d(string.format(l,a.blast,math.floor(a.lethal)))if a.pulse then
d(string.format("Radiation 1000 RAD inside %d, 200 RAD inside %d (open air)",math.floor(a.death),math.floor(a.sick)))end
if a.fallout then local o=
"Fallout   rain out to "..a.fallout;if
(a.falloutAdd or 0)>0 then
o=o.." (+"..a.falloutAdd.." salted)"end
if c.falloutRange~=100 then o=o.." at falloutRange "..
c.falloutRange.."%"end;d(o)
d("Mobs      within "..i(a.glow).." may turn into Glowing Ones","dim")end elseif e=="fleija"then
d("Sphere    every block within "..a.radius.." is deleted (bedrock-class excepted)")
d(string.format(l,a.blast,math.floor(a.lethal)))elseif e=="solinium"then
d("Sphere    "..
a.radius..": everything alive takes 15,000-250,000 RAD a tick")elseif e=="balefire"then
d("Sphere    "..a.radius.." carved column by column and set alight")
d(string.format(l,a.blast,math.floor(a.lethal)))elseif e=="large"then
d(string.format("Blocks    broken out to %s-%s in open air; hurts to %s",i(a.reachMin),i(a.reachMax),i(a.blast)))end;for p,o in ipairs(a.notes)do d(o,"dim")end;return f end
function g.summary(b,c,a)c=h.conf(c)a=a or h.effects(b,c)local e={}local function d(f,m)
e[#e+1]={f,m or"fg"}end;if a.kind=="none"then
d("Nothing fires yet.","warn")return e end
d(
(g.ENGINE[a.kind]or a.kind).. (a.radius and(" r"..a.radius)or""),"hi")if b.formula and b.raw then
d(b.formula.." = "..
i(b.raw).. (b.cappedAt and
(" (cap "..b.cappedAt..")")or""),"dim")end;if a.beams then
d(a.beams.." beams")end
if a.radius then d("Destroyed   "..a.radius)end;if a.blast then
d("Blast       "..math.floor(a.blast)..
", kills in "..math.floor(a.lethal or 0))end
if a.fallout then
d("Fallout     "..
a.fallout.. (

(a.falloutAdd or 0)>0 and(" (+"..a.falloutAdd.." salted)")or""))elseif a.kind=="mk5"and not a.nuclear then
d("Clean: no fallout","dim")end
if a.rinse then d("Kills all life inside it","warn")end;return e end
function g.stageLines(b,a,c)c=h.conf(c)local d={}
for f,e in ipairs(j.STAGES)do local m=a.raw[e]or 0
if m>0 or
b[e]>0 then
local n=string.format("%-11s %7s",j.STAGE_NAME[e],i(b[e]))local o="fg"if a.off[e]then n=n.."  OFF"o="warn"elseif a.capped[e]then
n=n.."  cap "..a.capped[e]o="dim"end;if a.edge[e]then
n=n.."  (on the line)"o="warn"end;d[#d+1]={n,o}if a.off[e]then d[#d+1]={"  "..
a.off[e],"dim"}end end end
if#d==0 then d[1]={"(empty: put something in a slot)","dim"}end;return d end
function g.shelterLines(a,b,c)local e={}local function d(f,m)e[#e+1]={f,m or"fg"}end
if a.outside then
d(string.format("At %d blocks you are outside the destruction radius.",a.dist),"hi")elseif c.kind=="mk5"then
if a.need==nil then
d(b.name.." cannot stop it short of the radius.","warn")else
d(string.format("%d block%s of %s stop%s it at %d out.",a.need,a.need==1 and""or"s",b.name,
a.need==1 and"s"or"",a.dist),
a.breached and"warn"or"hi")end
d(a.breached and
string.format("Your %d block%s will NOT hold.",a.thick,a.thick==1 and""or"s")or
string.format("Your %d block%s hold%s.",a.thick,
a.thick==1 and""or"s",a.thick==1 and"s"or""),
a.breached and"warn"or"hi")else d("Inside the sphere: no wall survives it.","warn")end;if a.blastRange then
d("In blast range: only a wall between you and ground zero blocks the damage.","dim")end
if a.dose then
local f=
a.dose>=j.RAD_DEATH and"lethal"or
(a.dose>=j.RAD_SICK and"sickening"or"survivable")
d(string.format("Radiation behind it: %s RAD (%s)",i(a.dose),f),a.dose>=
j.RAD_SICK and"warn"or"fg")end;return e end;return g