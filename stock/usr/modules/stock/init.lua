local x=require("component")local v=require("computer")
local r=require("stock.stock")local w="/etc/stock-watch.cfg"
local function E(a,b,c)
local k=x.list and x.list("gpu")()
if not k then a("No GPU found.",0xFF0000)return nil end;local l,d=pcall(x.proxy,k)if not l or not d then
a("Cannot open the GPU.",0xFF0000)return nil end;local f,g=d.getResolution()
if not f or not
g then a("Cannot detect screen size.",0xFF0000)return nil end;if f<b or g<c then
a(string.format("Screen too small: need %dx%d, have %dx%d.",b,c,f,g),0xFF6600)return nil end
local m,i=pcall(d.getDepth)
local e=(m and type(i)=="number")and(i<=1 and 1 or
(i<=4 and 2 or 3))or 1
local j=(e==1)and
{fg=0xFFFFFF,dim=0xFFFFFF,border=0xFFFFFF,title=0xFFFFFF,hi=0xFFFFFF,warn=0xFFFFFF,bg=0x000000,sel=0xFFFFFF}or
{fg=0xFFFFFF,dim=0xAAAAAA,bg=0x000000,border=e==2 and
0x55FFFF or 0x00FFFF,title=e==2 and 0xFFFF55 or 0xFFFF00,hi=
e==2 and 0x55FF55 or 0x00FF00,warn=e==2 and 0xFF5555 or 0xFF4040,sel=e==2 and 0x336699 or 0x2A4A6A}
local n=
(e>=2)and{tl="┌",tr="┐",bl="└",br="┘",h="─",v="│"}or{tl="+",tr="+",bl="+",br="+",h="-",v="|"}local h={W=f,H=g,tier=e,T=j,BOX=n,gpu=d}function h.set(q,I,J,o,p)if o then
pcall(d.setForeground,o)end;if p then pcall(d.setBackground,p)end
pcall(d.set,q,I,J)end
function h.fill(q,I,J,K,L,o,p)if o then
pcall(d.setForeground,o)end;if p then pcall(d.setBackground,p)end;pcall(d.fill,q,I,J,K,
L or" ")end;function h.clear()h.fill(1,1,f,g," ",j.fg,j.bg)end;return h end
local function t(a,b)a=tostring(a or"")if#a>b then return
a:sub(1,math.max(1,b-1)).."…"end;return
a..string.rep(" ",b-#a)end
local function u(a,b)a=tostring(a or"")if#a>b then a=a:sub(1,b)end;return
string.rep(" ",b-#a)..a end
local function y(a)local f,b=pcall(require,"peripheral.inventory")if not f or not b then return nil,
"inventory support unavailable"end
if
not b.available()then return nil,"no inventory controller or transposer attached"end;local e=b.sides()
if#e==0 then return nil,"no inventories found on any side"end;local c,d={},{}
for h,g in ipairs(e)do if a then a(g.name)end;local i=b.stacks(g.side)if i then
d[#d+1]=g.name
for h,j in ipairs(i)do j.sideName=g.name;j.side=g.side;c[#c+1]=j end end end;return c,nil,d end
local function z()return fs and fs.readFile and fs.writeFile end
local function A()if not z()or not fs.exists or not fs.exists(w)then
return{},{}end;local b,a=pcall(fs.readFile,w)if
not b or not a then return{},{}end;return r.decodeWatches(a)end
local function B(a,b)if not z()then return false,"no filesystem access"end
local c,d=pcall(fs.writeFile,w,r.encodeWatches(a,b))
if not c then return false,tostring(d or"write failed")end;return true end;local s
do local a,b=pcall(require,"shell.keys")s=a and b or nil end;local function F(b,a)if s and s.is then return s.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function C()
if
s and s.label then local a=s.label("quit")if a~=""then return a end end;return"^Q"end
local function D(b,a)
if a==200 then return"up"elseif
a==208 then return"down"elseif a==201 then return"pgup"elseif a==209 then return"pgdn"elseif a==199 then return"home"elseif a==207 then return"end"elseif a==28 then
return"enter"elseif F(b,a)then return"esc"elseif a==14 then return"back"elseif b and b>0 then
return string.char(b):lower()end;return nil end
local function G(a)local c=E(a,50,16)if not c then return end;local b,e,i=c.T,c.W,c.H;local j,p=A()local k,J,L={},nil,{}
local d,g=1,1;local f,h="",false;local q=false;local M=0;local l=nil;local m,N=5,i-2;local n=N-m+1
local function I()local Q,R,S=y()if not Q then k,J={},R
return end;J,L=nil,S or{}
k=r.applyWatches(r.aggregate(Q),j,p)M=v.uptime()if d>#k then d=math.max(1,#k)end end
local function o()local Q=r.filter(k,f)if q then Q=r.lowStock(Q)end;return Q end
local function K()local R=o()c.clear()c.fill(1,1,e,1," ",b.bg,b.border)
c.set(2,1,"STOCK",b.bg,b.border)local S=r.totals(k)
local W=string.format("%d kinds  %s items  %d slots",S.distinct,r.fmtCount(S.items),S.slots)
c.set(math.max(8,e-#W-1),1,W,b.bg,b.border)
local Z=
(#L>0)and("sides: "..table.concat(L,", "))or"no inventories detected"c.set(2,2,t(Z,e-2),b.dim,b.bg)local Q={}if f~=""then
Q[#Q+1]="filter '"..f.."'"end;if q then Q[#Q+1]="LOW ONLY"end;local X=(#Q>0)and
table.concat(Q,"  ·  ")or""if h then
X="/"..f.."_"end
c.set(2,3,t(X,e-2),h and b.title or b.hi,b.bg)local T,U,V=9,8,7;local Y=e-2-T-U-V-12
c.set(2,4,t("ITEM",Y)..u("COUNT",T)..
u("STACKS",U)..u("MIN",V).."  WHERE",b.title,b.bg)
if J then c.set(2,m+1,J,b.warn,b.bg)
c.set(2,m+3,"Attach a transposer or inventory controller",b.dim,b.bg)
c.set(2,m+4,"with a chest next to it, then press R.",b.dim,b.bg)elseif#R==0 then
c.set(2,m+1,(f~=""or q)and"Nothing matches."or"No items found.",b.dim,b.bg)else if d<g then g=d end;if d>g+n-1 then g=d-n+1 end
for aa=0,n-1 do local ad=g+aa;local ab=R[ad]if not ab then
break end;local ae=m+aa;local af=(ad==d)
local ac=ab.low and b.warn or b.fg;if ab.absent then ac=b.warn end;local ag=af and b.sel or b.bg;if af then
c.fill(1,ae,e,1," ",ac,ag)end;local ah=
(#ab.sides>0)and table.concat(ab.sides,",")or"-"
if ab.absent then ah="(none)"end
c.set(2,ae,t(ab.label,Y)..
u(r.fmtCount(ab.total),T)..
u(r.fmtStacks(ab.total,64),U)..u(ab.min and tostring(ab.min)or"-",V)..
"  "..ah,ac,ag)end;if#R>n then
c.set(e-10,4,string.format("%d/%d",d,#R),b.dim,b.bg)end end;c.fill(1,i,e,1," ",b.bg,b.border)
local _=h and"Enter=apply  Esc=cancel"or
(
"R refresh · / filter · L low-only · W watch · U unwatch · ^B bg · "..C().." quit")c.set(2,i,t(_,e-2),b.bg,b.border)if l then
c.set(2,i-1,t(l,e-2),b.hi,b.bg)end end
local function O(Q,R)local S=tostring(R or"")
while true do
c.fill(1,i-1,e,1," ",b.fg,b.bg)c.set(2,i-1,Q.." "..S.."_",b.title,b.bg)
local T={v.pullSignal()}
if T[1]=="key_down"then local U=D(T[3],T[4])
if U=="enter"then return tonumber(S)end;if U=="esc"then return nil end;if U=="back"then S=S:sub(1,-2)elseif
U and U:match("^%d$")then S=S..U end elseif T[1]=="interrupted"then return nil end end end;I()K()local P=10
while true do local R={v.pullSignal(1)}local Q=R[1]
if Q=="key_down"then
local S=D(R[3],R[4])l=nil
if h then if S=="enter"then h=false elseif S=="esc"then h=false;f=""elseif S=="back"then f=f:sub(1,-2)elseif S and#S==1 then
f=f..S end;d,g=1,1 elseif S=="q"or S==
"esc"then break elseif S=="r"then I()l="Rescanned."elseif S=="/"then h=true elseif S=="l"then q=not q;d,g=1,1 elseif S=="up"then d=math.max(1,
d-1)elseif S=="down"then
d=math.min(math.max(1,#o()),d+1)elseif S=="pgup"then d=math.max(1,d-n)elseif S=="pgdn"then
d=math.min(math.max(1,#o()),d+n)elseif S=="home"then d=1 elseif S=="end"then d=math.max(1,#o())elseif S=="w"then local T=o()[d]
if T then
local U=O("Warn when '"..T.label..
"' drops below:",T.min or 64)
if U then j[T.key]=U;p[T.key]=T.label;local V,W=B(j,p)
l=V and("Watching "..
T.label.." (min "..U..").")or(
"Not saved (needs admin): "..tostring(W))I()end end elseif S=="u"then local T=o()[d]
if T and j[T.key]then j[T.key]=nil;p[T.key]=nil;local U,V=B(j,p)
l=

U and("Stopped watching "..T.label..".")or("Could not save: "..tostring(V))I()end end;K()elseif Q=="interrupted"then break elseif Q=="tos_focus"then K()elseif Q==nil or Q=="timer"then if
v.uptime()-M>=P then I()K()end end end;c.clear()pcall(c.gpu.setForeground,0xFFFFFF)
pcall(c.gpu.setBackground,0x000000)end
local function H(b,a)
local c=b and b[1]and tostring(b[1]):lower()or nil
if c=="help"then
a("stock — what is in your base, and what is running short.",0xFFFF55)a("",0xAAAAAA)
a("  stock            Open the live monitor (full screen)",0xFFFFFF)
a("  stock list       One-shot listing to the shell",0xFFFFFF)
a("  stock low        Only what is below its watch threshold",0xFFFFFF)
a("  stock sides      Which inventories are attached",0xFFFFFF)a("",0xAAAAAA)
a("In the monitor: R rescan · / filter · L low-only · W set a",0xAAAAAA)
a("threshold on the highlighted item · U remove it · "..C().." quit.",0xAAAAAA)
a("Thresholds are saved in "..w..".",0xAAAAAA)a("",0xAAAAAA)
a("Needs a transposer or inventory controller with at least one",0xAAAAAA)
a("inventory next to it. Items are totalled by their registry",0xAAAAAA)
a("name, so two mods' identically-named items stay separate.",0xAAAAAA)return end
if c=="sides"then local f,d=pcall(require,"peripheral.inventory")if
not f or not d or not d.available()then
a("No inventory controller or transposer attached.",0xFF5555)return end
local e=d.sides()
if#e==0 then a("No inventories on any side.",0xAAAAAA)return end
a(string.format(" %-8s %s","side","slots"),0xFFFF55)for h,g in ipairs(e)do
a(string.format(" %-8s %d",g.name,g.size),0xFFFFFF)end;return end
if c=="list"or c=="low"then local f,j,g=y()if not f then a(tostring(j),0xFF5555)
return end;local h,k=A()
local d=r.applyWatches(r.aggregate(f),h,k)
if c=="low"then d=r.lowStock(d)
if#d==0 then
a("Nothing is below its threshold.",0x55FF55)local l=0;for m in pairs(h)do l=l+1 end;if l==0 then
a("(No thresholds set — open 'stock' and press W on an item.)",0xAAAAAA)end;return end end
if#d==0 then a("No items found.",0xAAAAAA)return end
a(string.format(" %-30s %9s %8s %6s","item","count","stacks","min"),0xFFFF55)local e=0
for m,l in ipairs(d)do if e>=40 then
a(string.format(" ... and %d more (use 'stock' for the full list)",#d-e),0xAAAAAA)break end
a(string.format(" %-30s %9s %8s %6s",tostring(l.label):sub(1,30),r.fmtCount(l.total),r.fmtStacks(l.total,64),
l.min and tostring(l.min)or"-"),
l.low and 0xFF5555 or 0xFFFFFF)e=e+1 end;local i=r.totals(d)
a(string.format(" %d kinds, %s items across %s",i.distinct,r.fmtCount(i.items),(#
(g or{})>0)and table.concat(g,", ")or"?"),0xAAAAAA)return end;if c then a("Unknown subcommand: "..c,0xFF5555)
a("Try 'stock help'.",0xAAAAAA)return end;G(a)end;return{commands={stock=H}}