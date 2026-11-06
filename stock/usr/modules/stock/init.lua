local v=require("component")local u=require("computer")
local q=require("stock.stock")
local function B(a,b,c)local k=v.list and v.list("gpu")()if not k then
a("No GPU found.",0xFF0000)return nil end;local l,d=pcall(v.proxy,k)if not l or not d then
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
(e>=2)and{tl="┌",tr="┐",bl="└",br="┘",h="─",v="│"}or{tl="+",tr="+",bl="+",br="+",h="-",v="|"}local h={W=f,H=g,tier=e,T=j,BOX=n,gpu=d}function h.set(G,H,I,o,p)if o then
pcall(d.setForeground,o)end;if p then pcall(d.setBackground,p)end
pcall(d.set,G,H,I)end
function h.fill(G,H,I,J,K,o,p)if o then
pcall(d.setForeground,o)end;if p then pcall(d.setBackground,p)end;pcall(d.fill,G,H,I,J,
K or" ")end;function h.clear()h.fill(1,1,f,g," ",j.fg,j.bg)end;return h end
local function s(a,b)a=tostring(a or"")if#a>b then return
a:sub(1,math.max(1,b-1)).."…"end;return
a..string.rep(" ",b-#a)end
local function t(a,b)a=tostring(a or"")if#a>b then a=a:sub(1,b)end;return
string.rep(" ",b-#a)..a end
local function w(a)local f,b=pcall(require,"peripheral.inventory")if not f or not b then return nil,
"inventory support unavailable"end
if
not b.available()then return nil,"no inventory controller or transposer attached"end;local e=b.sides()
if#e==0 then return nil,"no inventories found on any side"end;local c,d={},{}
for h,g in ipairs(e)do if a then a(g.name)end;local i=b.stacks(g.side)if i then
d[#d+1]=g.name
for h,j in ipairs(i)do j.sideName=g.name;j.side=g.side;c[#c+1]=j end end end;return c,nil,d end
local function C()return fs and fs.readFile and fs.writeFile end
local function x()return q.readWatches(C()and fs or nil)end;local function y(a,b)return q.saveWatches(fs,a,b)end;local r;do
local a,b=pcall(require,"shell.keys")r=a and b or nil end
local function D(b,a)if r and r.is then
return r.is("quit",b,a)end;return b==17 or a==68 or a==1 end;local function z()
if r and r.label then local a=r.label("quit")if a~=""then return a end end;return"^Q"end
local function A(b,a)
if a==200 then return"up"elseif
a==208 then return"down"elseif a==201 then return"pgup"elseif a==209 then return"pgdn"elseif a==199 then return"home"elseif a==207 then return"end"elseif a==28 then
return"enter"elseif D(b,a)then return"esc"elseif a==14 then return"back"elseif b and b>0 then
return string.char(b):lower()end;return nil end
local function E(a)local c=B(a,50,16)if not c then return end;local b,e,k=c.T,c.W,c.H;local f,h=x()local l,I,K={},nil,{}
local d,i=1,1;local g,j="",false;local G=false;local L=0;local m=nil;local n,M=5,k-2;local o=M-n+1
local function H()local P,Q,R=w()if not P then l,I={},Q
return end;I,K=nil,R or{}
l=q.applyWatches(q.aggregate(P),f,h)L=u.uptime()if d>#l then d=math.max(1,#l)end end
local function p()local P=q.filter(l,g)if G then P=q.lowStock(P)end;return P end
local function J()local Q=p()c.clear()c.fill(1,1,e,1," ",b.bg,b.border)
c.set(2,1,"STOCK",b.bg,b.border)local R=q.totals(l)
local V=string.format("%d kinds  %s items  %d slots",R.distinct,q.fmtCount(R.items),R.slots)
c.set(math.max(8,e-#V-1),1,V,b.bg,b.border)
local Y=
(#K>0)and("sides: "..table.concat(K,", "))or"no inventories detected"c.set(2,2,s(Y,e-2),b.dim,b.bg)local P={}if g~=""then
P[#P+1]="filter '"..g.."'"end;if G then P[#P+1]="LOW ONLY"end;local W=(#P>0)and
table.concat(P,"  ·  ")or""if j then
W="/"..g.."_"end
c.set(2,3,s(W,e-2),j and b.title or b.hi,b.bg)local S,T,U=9,8,7;local X=e-2-S-T-U-12
c.set(2,4,s("ITEM",X)..t("COUNT",S)..
t("STACKS",T)..t("MIN",U).."  WHERE",b.title,b.bg)
if I then c.set(2,n+1,I,b.warn,b.bg)
c.set(2,n+3,"Attach a transposer or inventory controller",b.dim,b.bg)
c.set(2,n+4,"with a chest next to it, then press R.",b.dim,b.bg)elseif#Q==0 then
c.set(2,n+1,(g~=""or G)and"Nothing matches."or"No items found.",b.dim,b.bg)else if d<i then i=d end;if d>i+o-1 then i=d-o+1 end
for _=0,o-1 do local ac=i+_;local aa=Q[ac]if not aa then
break end;local ad=n+_;local ae=(ac==d)
local ab=aa.low and b.warn or b.fg;if aa.absent then ab=b.warn end;local af=ae and b.sel or b.bg;if ae then
c.fill(1,ad,e,1," ",ab,af)end;local ag=
(#aa.sides>0)and table.concat(aa.sides,",")or"-"
if aa.absent then ag="(none)"end
c.set(2,ad,s(aa.label,X)..
t(q.fmtCount(aa.total),S)..
t(q.fmtStacks(aa.total,64),T)..t(aa.min and tostring(aa.min)or"-",U)..
"  "..ag,ab,af)end;if#Q>o then
c.set(e-10,4,string.format("%d/%d",d,#Q),b.dim,b.bg)end end;c.fill(1,k,e,1," ",b.bg,b.border)
local Z=j and"Enter=apply  Esc=cancel"or
(
"R refresh · / filter · L low-only · W watch · U unwatch · ^B bg · "..z().." quit")c.set(2,k,s(Z,e-2),b.bg,b.border)if m then
c.set(2,k-1,s(m,e-2),b.hi,b.bg)end end
local function N(P,Q)local R,S=tostring(Q or""),true
while true do
c.fill(1,k-1,e,1," ",b.fg,b.bg)c.set(2,k-1,P.." "..R.."_",b.title,b.bg)
local T={u.pullSignal()}
if T[1]=="key_down"then local U=A(T[3],T[4])
if U=="enter"then return tonumber(R)end;if U=="esc"then return nil end;R,S=q.numberKey(R,S,U)elseif
T[1]=="interrupted"then return nil end end end;H()J()local O=10
while true do local Q={u.pullSignal(1)}local P=Q[1]
if P=="key_down"then
local R=A(Q[3],Q[4])m=nil
if j then if R=="enter"then j=false elseif R=="esc"then j=false;g=""elseif R=="back"then g=g:sub(1,-2)elseif R and#R==1 then
g=g..R end;d,i=1,1 elseif R=="q"or R==
"esc"then break elseif R=="r"then H()m="Rescanned."elseif R=="/"then j=true elseif R=="l"then G=not G;d,i=1,1 elseif R=="up"then d=math.max(1,
d-1)elseif R=="down"then
d=math.min(math.max(1,#p()),d+1)elseif R=="pgup"then d=math.max(1,d-o)elseif R=="pgdn"then
d=math.min(math.max(1,#p()),d+o)elseif R=="home"then d=1 elseif R=="end"then d=math.max(1,#p())elseif R=="w"then local S=p()[d]
if S then
local T=N("Warn when '"..S.label..
"' drops below:",S.min or 64)
if T then local V,W=f[S.key],h[S.key]f[S.key]=T;h[S.key]=S.label;local U,X=y(f,h)
m=U and
(
"Watching "..S.label.." (min "..T..").")or
("Not saved (needs admin): "..tostring(X))if not U then f[S.key],h[S.key]=V,W end;H()end end elseif R=="u"then local S=p()[d]
if S and f[S.key]then local U,V=f[S.key],h[S.key]
f[S.key]=nil;h[S.key]=nil;local T,W=y(f,h)
m=T and
("Stopped watching "..S.label..".")or("Could not save: "..tostring(W))if not T then f[S.key],h[S.key]=U,V end;H()end end;J()elseif P=="interrupted"then break elseif P=="tos_focus"then J()elseif P==nil or P=="timer"then if
u.uptime()-L>=O then H()J()end end end;c.clear()pcall(c.gpu.setForeground,0xFFFFFF)
pcall(c.gpu.setBackground,0x000000)end
local function F(b,a)
local c=b and b[1]and tostring(b[1]):lower()or nil
if c=="help"then
a("stock — what is in your base, and what is running short.",0xFFFF55)a("",0xAAAAAA)
a("  stock            Open the live monitor (full screen)",0xFFFFFF)
a("  stock list       One-shot listing to the shell",0xFFFFFF)
a("  stock low        Only what is below its watch threshold",0xFFFFFF)
a("  stock sides      Which inventories are attached",0xFFFFFF)a("",0xAAAAAA)
a("In the monitor: R rescan · / filter · L low-only · W set a",0xAAAAAA)
a("threshold on the highlighted item · U remove it · "..z().." quit.",0xAAAAAA)
a("Thresholds are saved in "..q.WATCH_FILE..".",0xAAAAAA)a("",0xAAAAAA)
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
if c=="list"or c=="low"then local f,j,g=w()if not f then a(tostring(j),0xFF5555)
return end;local h,k=x()
local d=q.applyWatches(q.aggregate(f),h,k)
if c=="low"then d=q.lowStock(d)
if#d==0 then
a("Nothing is below its threshold.",0x55FF55)local l=0;for m in pairs(h)do l=l+1 end;if l==0 then
a("(No thresholds set — open 'stock' and press W on an item.)",0xAAAAAA)end;return end end
if#d==0 then a("No items found.",0xAAAAAA)return end
a(string.format(" %-30s %9s %8s %6s","item","count","stacks","min"),0xFFFF55)local e=0
for m,l in ipairs(d)do if e>=40 then
a(string.format(" ... and %d more (use 'stock' for the full list)",#d-e),0xAAAAAA)break end
a(string.format(" %-30s %9s %8s %6s",tostring(l.label):sub(1,30),q.fmtCount(l.total),q.fmtStacks(l.total,64),
l.min and tostring(l.min)or"-"),
l.low and 0xFF5555 or 0xFFFFFF)e=e+1 end;local i=q.totals(d)
a(string.format(" %d kinds, %s items across %s",i.distinct,q.fmtCount(i.items),(#
(g or{})>0)and table.concat(g,", ")or"?"),0xAAAAAA)return end;if c then a("Unknown subcommand: "..c,0xFF5555)
a("Try 'stock help'.",0xAAAAAA)return end;E(a)end;return{commands={stock=F}}