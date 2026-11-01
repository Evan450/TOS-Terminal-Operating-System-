
local F,G,H,I,J,K,B,L,M,z="%.%w+$","Cannot read ","Enter name of file to save:","[\r\n\t]","[^/]+%.[^/]*$","calc.print","printer","printerfmt","scroll","string"local C=require("component")local A=require("computer")
local u=require("calc.sheet")local x
do local a,b=pcall(require,"shell.keys")x=a and b or nil end;local function y(b,a)if x and x.is then return x.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function D()
if
x and x.label then local a=x.label("quit")if a~=""then return a end end;return"^Q"end;local v={}local E=5
local w=".calc"function v.ulen(a)local b=0
for c=1,#a do local d=a:byte(c)if d<0x80 or d>=0xC0 then b=b+1 end end;return b end
function v.usub(c,d,e)local b,a={},0
for f=1,#c do
local g=c:byte(f)if g<0x80 or g>=0xC0 then a=a+1;b[a]=f end end;b[a+1]=#c+1;d,e=math.max(1,d),math.min(a,e)
if d>e then return""end;return c:sub(b[d],b[e+1]-1)end
function v.pad(a,b)a=tostring(a or"")local c=v.ulen(a)
if c>b then return v.usub(a,1,b)end;return a..string.rep(" ",b-c)end
function v.padLeft(a,b)a=tostring(a or"")local c=v.ulen(a)
if c>b then return v.usub(a,1,b)end;return string.rep(" ",b-c)..a end
function v.fitHints(c,b,a)
local function e(f)return(#f==0)and""or
(" "..table.concat(f," · ").." ")end;local d={}for g,f in ipairs(c)do d[#d+1]=f
if v.ulen(e(d))>b then d[#d]=nil;break end end
if a then local f=false;for h,g in ipairs(d)do
if g==a then f=true end end;while not f do d[#d+1]=a
if v.ulen(e(d))<=b then f=true else
d[#d]=nil;if#d==0 then return e({a})end;d[#d]=nil end end end;return e(d)end
function v.entryMode(a)if type(a)~=z or a==""then return nil end;if
a:match("[%d%+%-%.%(@#%$=]")then return"VALUE"end;return"LABEL"end
function v.wantsRef(a)if a==""then return false end;local b=a:sub(-1)return
b:match("[%+%-%*/%^%(,=<>&#%.]")~=nil end
function v.cycleAbs(a,b)local i=a:sub(1,b)local f,j=i:match("()(%$?%a+%$?%d+)$")if not f then
return a,b end;local g,d,h,e=j:match("^(%$?)(%a+)(%$?)(%d+)$")local c
if
g==""and h==""then c="$"..d.."$"..e elseif g=="$"and h=="$"then c=d.."$"..e elseif
g==""and h=="$"then c="$"..d..e else c=d..e end;local k=a:sub(1,f-1)..c..a:sub(b+1)
return k,f-1+#c end
local function N(b,a)a=a or print;local aJ=C.list and C.list("gpu")()if not aJ then
a("No GPU found.",0xFF0000)return end;local aS,_=pcall(C.proxy,aJ)if not aS or not _ then
a("Cannot open the GPU.",0xFF0000)return end;local j,Q=_.getResolution()if
not j or not Q or j<40 or Q<12 then
a("calc needs at least a 40x12 screen.",0xFF6600)return end
local aT,ay=pcall(_.getDepth)
local V=(aT and type(ay)=="number")and(ay<=1 and 1 or
(ay<=4 and 2 or 3))or 1;local ar=(V==1)
local d=
ar and
{bg=0x000000,fg=0xFFFFFF,dim=0xFFFFFF,title=0xFFFFFF,selfg=0x000000,selbg=0xFFFFFF,err=0xFFFFFF,hi=0xFFFFFF,framefg=0x000000,framebg=0xFFFFFF,modefg=0x000000,modebg=0xFFFFFF,range=0xFFFFFF,s1=0xFFFFFF,s2=0xFFFFFF,s3=0xFFFFFF}or
{bg=0x000000,fg=0xFFFFFF,dim=0xAAAAAA,title=V==2 and 0xFFFF55 or 0xFFFF00,selfg=0x000000,selbg=V==2 and 0x55FFFF or 0x00FFFF,err=
V==2 and 0xFF5555 or 0xFF4040,hi=V==2 and 0x55FF55 or 0x00FF00,framefg=0x000000,framebg=
V==2 and 0xAAAAAA or 0x9A9A9A,modefg=0x000000,modebg=V==2 and 0xFFFF55 or 0xFFFF00,range=V==2 and
0x336699 or 0x2A4A6A,s1=V==2 and 0x55FFFF or 0x00C0FF,s2=
V==2 and 0xFF55FF or 0xFF60C0,s3=V==2 and 0x55FF55 or 0x80E040}
local function o(bp,bq,br,O,P)if O then pcall(_.setForeground,O)end;if P then
pcall(_.setBackground,P)end;pcall(_.set,bp,bq,br)end
local function ad(bp,bq,br,bs,bt,O,P)if O then pcall(_.setForeground,O)end;if P then
pcall(_.setBackground,P)end;pcall(_.fill,bp,bq,br,bs,bt or" ")end;local T,R=v.pad,v.ulen;local function ae()pcall(A.beep,880,0.05)end
local az,aa,as,ah
local function S()az=az or require("calc.ops")return az end;local c=u.new()local W=u.evaluator(c)local an=false;local e={c=1,r=1}
local p={c=1,r=1}local m={rows=0,cols=0}local i=b and b[1]or nil;local af=false;local k="READY"
local l=nil;local q,X=nil,nil;local ai=false;local Y=nil;local Z;local function h()af=true end
local function n(O)if
c.recalc=="manual"and not O then an=true;return end;W=u.evaluator(c)an=false end;local function f(O,P)q,X=O,P end;local function aK(O)return
fs and fs.exists and fs.exists(O)or false end
local function aA()return
{printer=aK("/usr/lib/printer.lua"),write=aK("/usr/modules/write/init.lua")}end;local aL,aB,at,ao=4,5,Q-1,Q;local function ag(O)return u.width(c,O)end
local function ap()local P,O={},E+1
local function bq(br)if O>j then return
false end;local bs=math.min(ag(br),j-O+1)
P[#P+1]={c=br,x=O,w=bs}O=O+ag(br)return true end;for br=1,m.cols do if not bq(br)then return P end end
local bp=math.max(p.c,m.cols+1)while bp<=u.MAX_COLS and bq(bp)do bp=bp+1 end;return P end
local function aC()local P,O={},aB
for bq=1,m.rows do if O>at then return P end;P[#P+1]={r=bq,y=O}O=O+1 end;local bp=math.max(p.r,m.rows+1)while O<=at and bp<=u.MAX_ROWS do
P[#P+1]={r=bp,y=O}O=O+1;bp=bp+1 end;return P end
local function aj(O)O=O or e
if O.r>m.rows then if O.r<p.r then p.r=O.r end
local P=at-aB+1-m.rows;if P<1 then P=1 end;if O.r>p.r+P-1 then p.r=O.r-P+1 end end;if p.r<=m.rows then p.r=m.rows+1 end
if O.c>m.cols then
if O.c<p.c then p.c=O.c end
while true do local P=ap()local bq=P[#P]local bp=false;for bs,br in ipairs(P)do if
br.c==O.c and br.w==ag(br.c)then bp=true end end;if
bp or not bq or p.c>=O.c then break end;p.c=p.c+1 end end;if p.c<=m.cols then p.c=m.cols+1 end end
local function aU()local P=u.raw(c,e.c,e.r)local O=u.refName(e.c,e.r)..":"
local bp=c.fmt[u._key(e.c,e.r)]if bp then O=O.." ("..bp..")"end;if c.colw[e.c]then O=O.." [W"..c.colw[e.c]..
"]"end;if P~=
""then O=O.." "..P end;return O end
local function aV()ad(1,1,j,3," ",d.fg,d.bg)
o(1,1,T(aU(),j-9),d.fg,d.bg)local O=" "..k.." "
o(j-R(O)+1,1,O,d.modefg,d.modebg)if l then
if type(l)=="table"then for bp,P in ipairs(l)do
o(P.x,2,P.text,P.fg or d.fg,P.bg or d.bg)end else o(1,2,T(l,j),d.fg,d.bg)end end;if q then
o(1,3,T(q,j),
X=="err"and d.err or(X=="hi"and d.hi or d.dim),d.bg)end end
local function aW(O)ad(1,aL,j,1," ",d.framefg,d.framebg)
for bp,P in ipairs(O)do
local bq=u.colName(P.c)
local bs=math.max(0,math.floor((P.w-#bq)/2))local br=P.c==e.c
o(P.x,aL,T(string.rep(" ",bs)..bq,P.w),
br and d.selfg or d.framefg,br and d.selbg or d.framebg)end end
local function aX(O,P)local bp=Y;return bp and O>=bp[1]and O<=bp[3]and P>=bp[2]and P<=
bp[4]end
local function aY(P,bp,O)local bq=c.cells[u._key(P,bp)]if not bq then
return string.rep(" ",O),d.fg end;local bv=u.classify(bq)
if bv=="label"then
local bx,bz=u.cellText(c,W,P,bp,ag(P))local bA=R(bx)if bA>O then bx=v.usub(bx,1,O)end;local by=O-R(bx)
if bz=="R"then local bB=math.max(0,math.min(O,
ag(P)-1))if R(bx)<=bB then bx=
v.padLeft(bx,bB)..string.rep(" ",O-bB)else bx=
string.rep(" ",by)..bx end elseif bz==
"C"then local bB=math.floor(by/2)bx=string.rep(" ",bB)..bx..
string.rep(" ",by-bB)else bx=bx..
string.rep(" ",by)end;return bx,d.fg end
local br,bw=u.cellText(c,W,P,bp,math.max(1,ag(P)-1))local bs=W.get(P,bp)
local bt=u.isErr(bs)and d.err or d.fg;if bw=="L"then
return T(" "..br,O), (type(bs)==z)and d.fg or bt end;local bu=
v.padLeft(br,math.max(1,ag(P)-1)).." "
return v.usub(bu,1,O)..string.rep(" ",math.max(0,O-
R(bu))),bt end
local function aZ(bq,P,O,bp)local bu=c.cells[u._key(bq,P)]if not bu then return nil end
local bw,bx,bt=u.classify(bu)if
bw~="label"or bt=="R"or bt=="C"or bt=="REP"then return nil end
if(bt or
u.PREFIX_ALIGN[c.gprefix or"'"])~="L"then return nil end;local bv=R(bx)local bs=O[bp].w;if bv<=bs then return nil end;local br=bp+1
while
br<=#O and bs<bv do local by=O[br]if by.c~=O[br-1].c+1 then break end;if
c.cells[u._key(by.c,P)]then break end;bs=bs+by.w;br=br+1 end;return bs,br-1 end
local function a_(O,P)
for bq,bp in ipairs(P)do local br,bs=bp.r,bp.y;ad(1,bs,j,1," ",d.fg,d.bg)local bu=br==e.r
o(1,bs,T(tostring(br),E),
bu and d.selfg or d.framefg,bu and d.selbg or d.framebg)local bt=1
while bt<=#O do local bv=O[bt]local bw,bA=aZ(bv.c,br,O,bt)
local bx,bB=aY(bv.c,br,bw or bv.w)local bC=bv.c==e.c and br==e.r;local by,bz=bB,d.bg;if aX(bv.c,br)then
by,bz=d.fg,d.range end
if bC then
o(bv.x,bs,v.usub(bx,1,bv.w),d.selfg,d.selbg)if bw and bw>bv.w then
o(bv.x+bv.w,bs,v.usub(bx,bv.w+1,bw),by,bz)end else o(bv.x,bs,bx,by,bz)end;bt=(bA or bt)+1 end end end
local function ba()local O={}if an then O[#O+1]="CALC"end
for bp,P in pairs(W.values or{})do if u.isErr(P)and P.e==
u.E_CYCLE then O[#O+1]="CIRC"break end end;if ai then O[#O+1]="END"end;return table.concat(O," ")end
local function bb()ad(1,ao,j,1,ar and" "or"░",d.dim,d.bg)
if not ar then
o(1,ao,"▓▒░",d.dim,d.bg)if j>6 then o(j-2,ao,"░▒▓",d.dim,d.bg)end end
local P=(i and i:match("[^/]+$")or"(unsaved)").. (
af and" *"or"")local O=ba()local bp=j-9-R(P)-R(O)-2
local bq=v.fitHints({"/ Menu","F1 Help","F2 Edit","F5 Goto","F9 Calc"},math.max(0,bp),
nil)local br=" "..P..bq
o(4,ao,T(br,j-8-R(O)),d.fg,d.bg)if O~=""then
o(j-4-R(O),ao," "..O.." ",d.modefg,d.modebg)end end;local function ab()local O,P=ap(),aC()aV()aW(O)a_(O,P)bb()end
local function aM()return fs and
fs.writeFile and fs.readFile end
local function aD(O,P)local bq,bp,br=pcall(fs.writeFile,O,P)
if not bq then return false,tostring(bp)end;if bp==false or bp==nil then return false,
tostring(br or"the write was refused")end
return true end;local function bc()
if fs and fs.home then local P,O=pcall(fs.home)if
P and type(O)==z and O~=""then return O end end;return"/"end
Z=bc()
local function s(O)if not O or O==""then return nil end
if O:sub(1,1)=="/"then return O end;return
(Z:sub(-1)=="/"and Z or Z.."/")..O end
local function aE(P,O)local bp={}if not(fs and fs.list)then return bp end
local br,bq=pcall(fs.list,P)if not br or type(bq)~="table"then return bp end
for bt,bs in ipairs(bq)do if
not
bs:match("/$")and(not O or bs:sub(-#O)==O)then bp[#bp+1]=bs end end;table.sort(bp)return bp end
local function au(O)
if not aM()then f("No filesystem access.","err")return false end;O=s(O or i)if not O then return false end
if not O:match(J)then O=O..w end;local P,bp=aD(O,u.serialize(c))if P then i,af=O,false
f("Saved "..O,"hi")return true end
f("Save failed: "..tostring(bp),"err")return false end
local function aN(O)
if not aM()then f("No filesystem access.","err")return end;O=s(O)if not O then return end;if
not fs.exists(O)and not O:match(J)then O=O..w end;if not fs.exists(O)then
f("No such file: "..O,"err")return end;local bq,bp=pcall(fs.readFile,O)if not bq or
type(bp)~=z then f(G..O,"err")return end
c=u.deserialize(bp)W=u.evaluator(c)an=false;i,af=O,false;e.c,e.r,p.c,p.r=1,1,1,1
m.rows,m.cols=0,0;local P="Retrieved "..O;if(c.skipped or 0)>0 then
P=P.."  ("..c.skipped..
" unreadable line(s) skipped)"end;f(P,
(c.skipped or 0)>0 and"err"or"hi")end
local function ac()
while true do local O,br,P,bp,bq=A.pullSignal()
if O=="key_down"then return"key",P,bp end;if O=="interrupted"then return"key",17,16 end
if O=="tos_focus"then ab()elseif
O=="clipboard"and type(P)==z then return"paste",P elseif O=="touch"or O=="drag"then
return"touch",P,bp,bq elseif O==M then return M,P,bp,bq end end end
local function t(P,bp,O)local bq=tostring(bp or"")local br=0;local bs=k;k="EDIT"
while true do
l=P.." "..bq.."_"if O and#O>0 then q=table.concat(O,"  ")X=nil end
ab()local bv,bt,bu=ac()
if bv=="paste"then bq=bq..bt:gsub(I," ")elseif bv=="key"then if bu==28 then k=bs
l=nil;q=nil;return bq end
if y(bt,bu)then k=bs;l=nil;q=nil;return nil end
if bu==14 then bq=bq:sub(1,-2)elseif
(bu==200 or bu==208)and O and#O>0 then
br=(bu==208)and(br%#O+1)or((br-2)%#O+1)bq=O[br]elseif bt and bt>=32 and bt<127 then
bq=bq..string.char(bt)end end end end
local function ak(bp,bq,O,P)
while true do local bs=t(bp,tostring(bq))if bs==nil then return nil end
local br=tonumber(bs)if
br and(not O or br>=O)and(not P or br<=P)then return br end;ae()
f("Enter a number".. (O and
(" from "..O.." to "..P)or"")..".","err")end end
local function al(O,P,bp)
if P==200 then O.r=math.max(1,O.r-1)elseif P==208 then
O.r=math.min(u.MAX_ROWS,O.r+1)elseif P==203 then O.c=math.max(1,O.c-1)elseif P==205 then
O.c=math.min(u.MAX_COLS,O.c+1)elseif P==201 then O.r=math.max(1,O.r-bp)elseif P==209 then
O.r=math.min(u.MAX_ROWS,O.r+bp)elseif P==199 then O.c,O.r=1,1 else return false end;return true end
local function am()return math.max(1,at-aB+1-m.rows)end
local function r(P,O)O=O or{}local bq=O.free and nil or{c=e.c,r=e.r}
local bp={c=e.c,r=e.r}if O.start then local bw,bx,by,bz=u.parseRange(O.start)if bw then bq={c=bw,r=bx}
bp={c=by,r=bz}end end
local br=nil;local bv,bs=k,{c=e.c,r=e.r}k="POINT"
local function bu()if br then return br end
if bq then return
u.rangeName(math.min(bq.c,bp.c),math.min(bq.r,bp.r),math.max(bq.c,bp.c),math.max(bq.r,bp.r))end;return u.refName(bp.c,bp.r)end
local function bt(bw)k=bv;Y=nil;l,q=nil,nil;e.c,e.r=bs.c,bs.r;aj()return bw end
while true do
if not br then
if bq then
Y={math.min(bq.c,bp.c),math.min(bq.r,bp.r),math.max(bq.c,bp.c),math.max(bq.r,bp.r)}else Y={bp.c,bp.r,bp.c,bp.r}end;e.c,e.r=bp.c,bp.r;aj(bp)else Y=nil end
l=P.." "..bu().. (br and"_"or"")
q=br and"Enter accepts"or"Arrows point · . anchors · Backspace lets go · type an address or a name"X=nil;ab()local by,bw,bx=ac()
if by=="touch"then local bz,bA=ap(),aC()for bC,bB in ipairs(bz)do
if bw>=bB.x and bw<
bB.x+bB.w then for bC,bD in ipairs(bA)do
if bD.y==bx then bp.c,bp.r=bB.c,bD.r end end end end elseif
by=="key"then
if bx==28 then local bA=bu()local bz=c.names[bA:upper()]if bz then return
bt({bz[1],bz[2],bz[3],bz[4]})end
local bB,bC,bD,bE=u.parseRange(bA)if bB then return bt({bB,bC,bD,bE})end;ae()
f("Invalid cell or range address: "..bA,"err")br=nil elseif y(bw,bx)then return bt(nil)elseif br then
if bx==14 then br=br:sub(1,-2)if br==""then br=nil end elseif bw and
bw>=32 and bw<127 then br=br..string.char(bw)end elseif bx==14 then
if bq then bq=nil;bp.c,bp.r=bs.c,bs.r else return bt(nil)end elseif bw==46 then if not bq then bq={c=bp.c,r=bp.r}end elseif al(bp,bx,am())then elseif
bw and bw>=32 and bw<127 then br=string.char(bw)end end end end
local function U(O)if not O then return nil end;return O[1],O[2],O[3],O[4]end
local function aF(bp,P,O)local bq,br={},1
if O then bq[1]={x=1,text=O,fg=d.title,bg=d.bg}br=R(O)+3 end
for bs,bt in ipairs(bp)do local bu=bt.label
bq[#bq+1]={x=br,text=bu,fg=(bs==P)and d.selfg or d.fg,bg=
(bs==P)and d.selbg or d.bg,index=bs}br=br+R(bu)+2 end;return bq end;local function bd(O)if O.items then local P={}for bq,bp in ipairs(O.items)do P[#P+1]=bp.label end;return
table.concat(P,"  ")end
return O.desc end
local function av(O,P)
local bp=1;local bq=k;k="MENU"
while true do l=aF(O,bp,P)q,X=O[bp].desc,nil;ab()local bt,bs,br=ac()
if
bt=="key"then if y(bs,br)or br==14 then k=bq;l,q=nil,nil;return nil end;if br==28 then
k=bq;l,q=nil,nil;return bp end
if br==203 then bp=(bp-2)%#O+1 elseif
br==205 or br==57 then bp=bp%#O+1 elseif bs and bs>32 then
ah=ah or require("calc.menu")local bu=ah.byKey(O,string.char(bs))
if bu then k=bq;l,q=nil,nil;return bu end end elseif bt=="touch"and br==2 then for bv,bu in ipairs(aF(O,bp,P))do
if bu.index and bs>=bu.x and bs<bu.x+
R(bu.text)then k=bq;l,q=nil,nil;return bu.index end end end end end;local function aG(O,P,bp)return
av({{label="No",desc=P},{label="Yes",desc=bp}},O)==2 end
local function aw(P,O,bp)
local bq=1;local br=k;k=bp or"HELP"
while true do ad(1,1,j,Q," ",d.fg,d.bg)
o(1,1,T(" "..P,j-9),d.title,d.bg)o(j-7,1," "..k.." ",d.modefg,d.modebg)
for bv=0,Q-3 do
local bw=O[bq+bv]
if bw then local bx,by=bw,d.fg;if type(bw)=="table"then
bx,by=bw[1],(bw[2]=="title"and d.title or(bw[2]==
"dim"and d.dim or d.fg))end
o(2,2+bv,T(bx,j-2),by,d.bg)end end
o(1,Q,T(" PgUp/PgDn scroll · any other key returns",j),d.dim,d.bg)local bt,bu,bs=ac()
if bt=="key"then
if bs==201 then bq=math.max(1,bq- (Q-3))elseif bs==209 then
bq=math.min(math.max(1,
#O- (Q-3)),bq+ (Q-3))elseif bs==200 then bq=math.max(1,bq-1)elseif bs==208 then bq=math.min(math.max(1,#O- (Q-3)),
bq+1)else break end end end;k=br end
local function be()local bp={}for bq in pairs(u.FUNCS)do bp[#bp+1]="@"..bq end
table.sort(bp)
local P={{"calc - a spreadsheet, the 1-2-3 way","title"},"",{"Moving","title"},"  arrows, PgUp/PgDn      one cell, one screen","  Home                   to A1","  End, then an arrow     to the edge of the data that way","  F5                     go to a cell or a range name","",{"Entering","title"},"  Just type. A digit or + - . ( @ # $ = starts a VALUE (a number or a","  formula); anything else starts a LABEL. Enter keeps the pointer where","  it is; an arrow enters and moves.","  While typing a formula, after an operator, ( or , the arrows POINT","  at the cell to put in; . anchors a range; F4 makes it absolute ($).","  F2 edits the cell. Backspace and ^Q (not Esc: Minecraft takes it).","  Label prefixes:  ' left   \" right   ^ centre   \\ repeat (\\- fills)","",{"Formulas","title"},"  +A1*2   @SUM(A1..A9)   @IF(B2>100,\"over\",\"ok\")   +A1&\" \"&B1","  Operators: + - * / % ^, = <> < > <= >=, #AND# #OR# #NOT#, & (text)","  $A$1 is absolute: Copy keeps it, where A1 moves with the copy.","  A range name stands for its range: @SUM(SALES).","  1-2-3 counts from 0 in @CHOOSE, @MID, @FIND and the lookups' offset.","",{"Keys","title"},"  /   the menu (first letters pick; Backspace goes back a level)","  F1 help   F2 edit   F3 names   F4 absolute   F5 go to   F9 recalc",
"  Del clears the cell   ^S saves   ^B to the background   "..D().." quits","",{"@functions","title"}}local O="  "for br,bq in ipairs(bp)do
if#O+#bq+1 >j-4 then P[#P+1]=O;O="  "end;O=O..bq.." "end;P[#P+1]=O
return P end
local function bf()local P,bp=0,0;for bu,bt in pairs(c.cells)do P=P+1
if u.classify(bt)=="formula"then bp=bp+1 end end;local O={}for bt in pairs(c.names)do
O[#O+1]=bt end;table.sort(O)local bq
for bu,bt in pairs(W.values or{})do if
u.isErr(bt)and bt.e==u.E_CYCLE then local bv,bw=u.unkey(bu)
bq=u.refName(bv,bw)break end end
local br=(A.freeMemory and A.freeMemory())or nil
local bs={{"Worksheet status","title"},"","  Cells in use:        "..
P.."  ("..bp.." formulas)","  Extent:              A1.."..u.refName(c.cols,c.rows),
"  Global format:       ".. (u.FORMATS[c.gfmt:sub(1,1)]or c.gfmt)..
" ("..c.gfmt..")",
"  Label prefix:        "..c.gprefix,"  Column width:        "..c.gwidth,"  Recalculation:       "..
(c.recalc==
"manual"and"Manual"or"Automatic"),"  Titles:              "..m.rows..
" rows, "..m.cols.." columns","  Range names:         ".. (#O>0 and
table.concat(O," ")or"(none)"),
"  Circular reference:  ".. (bq or"(none)"),"  Memory free:         "..
(br and(
math.floor(br/1024).." KB")or"?"),"  Printer driver:      ".. (
aA().printer and"installed"or"not installed"),
"  write:               "..
(aA().write and"installed (Print Document)"or"not installed")}aw("Status",bs,"STAT")end;local bg={F=true,S=true,C=true,[","]=true,P=true}
local function aO(O)
if not bg[O]then return O end
local P=ak("Enter number of decimal places (0..15):",2,0,15)if P==nil then return nil end;return O..math.floor(P)end
local function bh()as=as or require("calc.graph")
local bp=as.collect(c,W)local O,P=as.render(bp,j,Q-1,ar)if not O then
f("Cannot draw: "..P,"err")return end;ad(1,1,j,Q," ",d.fg,d.bg)
local bq={a=d.s1,b=d.s2,c=d.s3,axis=d.dim,title=d.title}
for br,bs in ipairs(O)do local bu,bw,bv,bt=1,1,nil,{}
for bx in bs:gmatch("[%z\1-\127\194-\244][\128-\191]*")do local by=
bq[P[br][bu]]or d.fg;if by~=bv and#bt>0 then
o(bw,br,table.concat(bt),bv,d.bg)bt={}bw=bu end;bv=by;bt[#bt+1]=bx;bu=bu+1 end
if#bt>0 then o(bw,br,table.concat(bt),bv,d.bg)end end;o(1,Q,T(" Any key returns",j),d.dim,d.bg)ac()end;local function bi()local O,P,bp,bq=u.parseRange(c.print.range or"")
return O,P,bp,bq end
local function ax(O,P,bp)aa=aa or require(K)
local bq,br,bs,bt=bi()
if not bq then return nil,"Set a print range first (Range)."end;n(true)
return
aa.pages(c,W,bq,br,bs,bt,{target=O,measure=P,maxWidth=bp,perPage=(O=="file")and 0 or 20,header=c.print.header,footer=c.print.footer,formulas=c.print.formulas})end
local function aP()local bt,O=pcall(require,B)if not bt or type(O)~="table"then return nil,
"the printer driver is not installed"end
local P,bp=pcall(require,L)
local bq,br,bs=P and bp.width or nil,P and bp.MAX_WIDTH or 164,"estimated"
if O.available and O.available()then bq,br=O.measurer(),O.maxWidth()
local bv,bu=O.width("M")if bu=="component"then bs=B end end;return O,bq,br,bs,P and bp or nil end
local function bj(O)local br,bt,bs,bp
if O~="file"then local bw;bw,br,bt,bs,bp=aP()if not bw and O==B then
f("Cannot preview: "..br,"err")return end
if not bw then local by,bx=pcall(require,L)if by then
bp,br,bt,bs=bx,bx.width,bx.MAX_WIDTH,"estimated"end end end;local bq,bv=ax(O,br,bt)if not bq then f(bv,"err")return end;local P={}local bu=
bp and bp.cost and bp.cost(bq,1)
P[1]={string.format("%d page(s) for %s%s",#bq,O,

bu and string.format(" - %d sheet(s), %d black ink%s",bu.paper,bu.black,
bs and(", "..bs.." widths")or"")or""),"title"}
for bw,bx in ipairs(bq)do P[#P+1]=""
P[#P+1]={string.format("-- page %d of %d --",bw,#bq),"dim"}for bz,by in ipairs(bx)do P[#P+1]=by end end;aw("Print preview",P,"PREV")end
local function bk(O)
if O=="file"then local bp,bq=ax("file")if not bp then f(bq,"err")return end;aa=aa or
require(K)local br=
(i and i:gsub(F,"")or s("sheet"))..".prn"
local P=t("Enter print file name:",br)if not P or P==""then return end;P=s(P)
local bs,bt=aD(P,aa.toText(bp))
if bs then
f("Printed "..#bp.." page(s) to "..P,"hi")else f("Not written: "..tostring(bt),"err")end elseif O==B then local P,br,bw,bB,bs=aP()
if not P then f("Cannot print: "..br,"err")return end;if not P.available()then
f("No printer: "..tostring(P.unavailableReason()),"err")return end;local bp,bx=ax(B,br,bw)if not bp then
f(bx,"err")return end
local bq=P.job(
(i and i:match("([^/]+)%.%w+$"))or"Worksheet")
for bC,bD in ipairs(bp)do if bC>1 then bq:pageBreak()end
for bB,bE in ipairs(bD)do
local bF,bG=bq:line(bE)if not bF then
f("Cannot print: "..tostring(bG),"err")return end end end;local by,bz=bq:check()if not by then
f("Refused: "..tostring(bz),"err")return end
local bt=bs and bs.cost(bp,1)or{paper=#bp,black=0}if not
aG(string.format("Print %d sheet(s), %d black ink?",bt.paper,bt.black),"Do not print","Print it")then
f("Not printed.",nil)return end
local bu,bA,bv=bq:commit()
if not bu then
f("Print failed: "..tostring(bA)..
((bv or 0)>0 and
string.format(" (%d sheet(s) DID print)",bv)or""),"err")else f("Printed "..bu.." sheet(s).","hi")end elseif O=="write"then local bs,P=pcall(require,"write")if
not bs or type(P)~="table"then
f("Cannot open write: "..tostring(P),"err")return end;if
not P.api or not P.api.open then
f("This write is too old (1.1.0 adds the way in).","err")return end
local bp,bq=pcall(require,L)
local br,bt=ax("write",bp and bq.width or nil,bp and bq.MAX_WIDTH or nil)if not br then f(bt,"err")return end;aa=aa or require(K)
local bu=(i and
i:match("([^/]+)%.%w+$"))or"Worksheet"
local bv=(i and i:gsub(F,"")or s("sheet"))..".txt"
local bw,bx=pcall(P.api.open,bv,".nf\n"..aa.toWrite(br,bu),a)ad(1,1,j,Q," ",d.fg,d.bg)
if not bw then
f("write stopped: "..tostring(bx),"err")else f("Back from write.",nil)end end end;local g={}
local function bl(O)local bp,bq=O:match("^([%w%.]+):?(.*)$")local P=g[bp]if not P then f(
"Not done yet: "..O,"err")return end;return
P(bq)end
g["global.format"]=function(O)local P=aO(O)if not P then return end;c.gfmt=P;h()n()end;g["global.prefix"]=function(O)c.gprefix=O;h()end
g["global.width"]=function()
local O=ak("Enter global column width (1..60):",c.gwidth,1,60)if O then c.gwidth=math.floor(O)h()end end
g["global.recalc"]=function(O)c.recalc=O;h()n(O=="auto")end
g["range.format"]=function(O)local P=false
if O~="reset"then P=aO(O)if P==nil then return end end;local bp,bq,br,bs=U(r("Enter range to format:"))
if not bp then return end;S().format(c,bp,bq,br,bs,P or nil)h()end
g["range.label"]=function(O)
local P,bp,bq,br=U(r("Enter range of labels:"))if P then S().label(c,P,bp,bq,br,O)h()n()end end
g["range.erase"]=function()
local O,P,bp,bq=U(r("Enter range to erase:"))if O then S().erase(c,O,P,bp,bq)h()n()end end
g["range.value"]=function()
local O,bp,bq,br=U(r("Enter range to copy FROM:"))if not O then return end
local P,bs=U(r("Enter range to copy TO:",{free=true}))if not P then return end;S().values(c,O,bp,bq,br,P,bs)h()n()end
g["name.create"]=function()local O=t("Enter name:","")
if not O or O==""then return end;if not S().validName(O)then ae()
f("Not a usable name: letters, digits and _, and not like a cell or @function.","err")return end
local P,bp,bq,br=U(r("Enter range:"))if not P then return end;c.names[O:upper()]={P,bp,bq,br}h()n()
f(
"Named "..O:upper().." = "..u.rangeName(P,bp,bq,br),"hi")end;local function aQ()local O={}for P in pairs(c.names)do O[#O+1]=P end;table.sort(O)
return O end
g["name.delete"]=function()local O=aQ()
if
#O==0 then f("There are no range names.","err")return end;local P=t("Enter name to delete:",O[1],O)if
P and c.names[P:upper()]then c.names[P:upper()]=nil;h()n()end end
g["name.reset"]=function()if
aG("Forget every range name?","Keep the names","Forget them all")then c.names={}h()n()end end
g["name.table"]=function()
local O,P=U(r("Enter range for table:",{free=true}))if not O then return end;for bp,bq in ipairs(aQ())do local br=c.names[bq]
u.set(c,O,P+bp-1,"'"..bq)
u.set(c,O+1,P+bp-1,"'"..u.rangeName(br[1],br[2],br[3],br[4]))end;h()
n()end
g["copy"]=function()
local P,bp,bq,br=U(r("Enter range to copy FROM:"))if not P then return end
local O=r("Enter range to copy TO:",{free=true})if not O then return end
S().copy(c,P,bp,bq,br,O[1],O[2],O[3],O[4])h()n()end
g["move"]=function()
local P,bp,bq,br=U(r("Enter range to move FROM:"))if not P then return end
local O=r("Enter range to move TO:",{free=true})if not O then return end;local bs,bt=S().move(c,P,bp,bq,br,O[1],O[2])if
bs==nil then f(bt,"err")else h()n()end end
g["ws.insert"]=function(O)
local P,bp,bq,br=U(r(O=="col"and"Enter column insert range:"or"Enter row insert range:"))if not P then return end
if O=="col"then S().insertCols(c,P,bq-P+1)else S().insertRows(c,bp,
br-bp+1)end;h()n()end
g["ws.delete"]=function(O)
local P,bp,bq,br=U(r(O=="col"and"Enter range of columns to delete:"or
"Enter range of rows to delete:"))if not P then return end
if O=="col"then S().deleteCols(c,P,bq-P+1)else S().deleteRows(c,bp,
br-bp+1)end;h()n()end
g["col.width"]=function()local O=ag(e.c)local P=k;k="EDIT"
while true do c.colw[e.c]=O;l="Enter column width (1..60): "..
O
q,X="Left/Right change it as you watch · Enter keeps it · "..
D().." cancels",nil;ab()local br,bp,bq=ac()
if br=="key"then if bq==28 then break end;if y(bp,bq)then c.colw[e.c]=nil;k=P;l,q=nil,
nil;return end
if bq==203 then O=math.max(1,O-1)elseif
bq==205 then O=math.min(60,O+1)elseif bp and bp>=48 and bp<=57 then
local bs=ak("Enter column width (1..60):",string.char(bp),1,60)if bs then O=math.floor(bs)end;break end end end;k=P;l,q=nil,nil
if O==c.gwidth then c.colw[e.c]=nil else c.colw[e.c]=O end;h()end
g["col.reset"]=function()c.colw[e.c]=nil;h()end
g["ws.erase"]=function()c=u.new()W=u.evaluator(c)i=nil;af=false;an=false
e.c,e.r,p.c,p.r=1,1,1,1;m.rows,m.cols=0,0 end
g["titles"]=function(O)if O=="clear"then m.rows,m.cols=0,0;return end;if
O=="both"or O=="h"then m.rows=math.max(0,e.r-1)end;if
O=="both"or O=="v"then m.cols=math.max(0,e.c-1)end;aj()end;g["ws.status"]=function()bf()end
g["file.retrieve"]=function()if
af and not
aG("Discard unsaved changes?","Keep this worksheet","Discard its unsaved changes")then return end;local P=aE(Z,w)local O=t("Name of file to retrieve:",
P[1]or"",P)
if O and O~=""then aN(O)end end
g["file.save"]=function()local bp=i or s("sheet"..w)local P=t(H,bp)if
not P or P==""then return end;local O=s(P)if not O:match(J)then O=O..w end
if O~=i and
fs.exists(O)then
local bq=av({{label="Cancel",desc="Do not save"},{label="Replace",desc="Write over the file on disk"}},
O.." exists.")if bq~=2 then return end end;au(O)end
g["file.import"]=function()local bp=aE(Z,".csv")
local O=t("Name of CSV file to import:",bp[1]or"",bp)if not O or O==""then return end;local P=s(O)
local br,bq=pcall(fs.readFile,P)
if not br or type(bq)~=z then f(G..P,"err")return end;local bs=u.fromCSV(c,bq,e.c,e.r)h()n()
f(string.format("Imported %d cell(s) from %s at %s.",bs,P,u.refName(e.c,e.r)),"hi")end
g["file.export"]=function()local bp=
(i and i:gsub(F,"")or s("sheet"))..".csv"
local O=t("Export CSV as:",bp)if not O or O==""then return end;n(true)local P=s(O)
local bq,br=aD(P,u.toCSV(c,W))if bq then f("Exported "..P,"hi")else
f("Export failed: "..tostring(br),"err")end end
g["file.list"]=function()
local O={{"Worksheets in "..Z,"title"},""}for bp,P in ipairs(aE(Z,w))do O[#O+1]="  "..P end;if#O==2 then
O[3]="  (none)"end;aw("File list",O,"FILES")end
g["file.dir"]=function()local O=t("Enter current directory:",Z)
if O and O~=""then if
fs.isDirectory and not fs.isDirectory(O)then
f("Not a directory: "..O,"err")return end;Z=O end end
g["print.range"]=function()
local O=r("Enter print range:",{start=c.print.range})
if O then c.print.range=u.rangeName(O[1],O[2],O[3],O[4])h()end end
g["print.header"]=function()
local O=t("Enter header line:",c.print.header or"")if O then c.print.header=O~=""and O or nil;h()end end
g["print.footer"]=function()
local O=t("Enter footer line:",c.print.footer or"")if O then c.print.footer=O~=""and O or nil;h()end end
g["print.displayed"]=function()c.print.formulas=nil;h()end
g["print.formulas"]=function()c.print.formulas=true;h()end;g["print.preview"]=function(O)bj(O)end
g["print.go"]=function(O)bk(O)end
g["print.clear"]=function()c.print={}h()f("Print settings cleared.")end;g["graph.type"]=function(O)c.graph.type=O;h()end
g["graph.range"]=function(O)
local P=r(
"Enter "..O:upper().." range:",{start=c.graph[O]})
if P then c.graph[O]=u.rangeName(P[1],P[2],P[3],P[4])h()end end
g["graph.title"]=function(O)
local P=t(O=="title1"and"Enter first title:"or"Enter second title:",
c.graph[O]or"")if P then c.graph[O]=P~=""and P or nil;h()end end;g["graph.reset"]=function()c.graph={}h()end;g["graph.view"]=function()
n(true)bh()end
g["data.fill"]=function()
local O,br,bs,bt=U(r("Enter fill range:"))if not O then return end;local P=ak("Start:",0)if not P then return end
local bp=ak("Step:",1)if not bp then return end;local bq=ak("Stop:",8191)if not bq then return end
S().fill(c,O,br,bs,bt,P,bp,bq)h()n()end
g["sort.range"]=function()
local O=r("Enter data range:",{start=c.sort.range})
if O then c.sort.range=u.rangeName(O[1],O[2],O[3],O[4])h()end end
local function aR(O,P)local bq=r(P,{free=true})if not bq then return end
local bp=t("Sort order (A or D):",O=="k1"and(c.sort.o1 or
"A")or(c.sort.o2 or"A"))if not bp then return end;bp=bp:upper():sub(1,1)
if
bp~="A"and bp~="D"then ae()f("A for ascending, D for descending.","err")return end;c.sort[O]=u.refName(bq[1],bq[2])
c.sort[O=="k1"and"o1"or"o2"]=bp;h()end
g["sort.key1"]=function()aR("k1","Primary sort key:")end
g["sort.key2"]=function()aR("k2","Secondary sort key:")end;g["sort.reset"]=function()c.sort={}h()end
g["sort.go"]=function()local O,P,br,bp=u.parseRange(
c.sort.range or"")local bq=c.sort.k1 and
u.parseRef(c.sort.k1)if not O or not bq then ae()
f("Set the Data-Range and the Primary-Key first.","err")return end;local bs=c.sort.k2 and
u.parseRef(c.sort.k2)or nil
S().sort(c,O,P,br,bp,bq,
c.sort.o1 ~="D",bs,c.sort.o2 ~="D")h()n()
f("Sorted ".. (bp-P+1).." rows.","hi")end;local aq=false
g["app.quit"]=function()
if af then
local O=av({{label="No",desc="Stay in calc"},{label="Yes",desc="Leave without saving"},{label="Save",desc="Save, then leave"}},"Worksheet changes not saved! Leave anyway?")if O==2 then aq=true elseif O==3 then
if au(i or t(H,s("sheet"..w)))then aq=true end end else aq=true end end
local function bm()ah=ah or require("calc.menu")
local O={{items=ah.root(aA()),sel=1}}local P=k;k="MENU"
while#O>0 and not aq do local bp=O[#O]local br=bp.items;l=aF(br,bp.sel)q,X=bd(br[bp.sel]),
nil;ab()local bu,bt,bq=ac()local bs
if bu=="key"then if y(bt,bq)then break end
if bq==14 then
table.remove(O)elseif bq==28 then bs=bp.sel elseif bq==203 then bp.sel=(bp.sel-2)%#br+1 elseif bq==205 or bq==
57 then bp.sel=bp.sel%#br+1 elseif bq==199 then bp.sel=1 elseif bq==207 then
bp.sel=#br elseif bt and bt>32 then bs=ah.byKey(br,string.char(bt))
if not bs then ae()end end elseif bu=="touch"and bq==2 then
for bw,bv in ipairs(l)do if
bt>=bv.x and bt<bv.x+R(bv.text)then bs=bv.index end end end
if bs then local bv=br[bs]bp.sel=bs
if bv.items then O[#O+1]={items=bv.items,sel=1}elseif bv.cmd==
"menu.up"then table.remove(O)elseif bv.cmd=="menu.quit"then break else l,q=nil,nil;k="WAIT"
bl(bv.cmd)k="MENU"if not bv.stay then break end end end end;k=P;l=nil;if not X then q=nil end end
local function aH(O,P)if O==""then u.set(c,e.c,e.r,nil)h()n()return true end
local bp=O
if
P=="LABEL"and not u.PREFIX_ALIGN[O:sub(1,1)]then bp=(c.gprefix or"'")..O end;local bq,br=u.classify(bp)
if bq=="formula"then local bs,bt=u.parse(br)
if not bs then ae()
f(
"Not a valid formula ("..tostring(bt)..
"): fix it, start it with ' to make it a label, or "..D().." to cancel.","err")return false end end;u.set(c,e.c,e.r,bp)h()n()return true end
local function aI(O,P,bp)local br=bp or#O;local bs=P;local bq=nil
local function bv()
if bq.anchor then return
u.rangeName(math.min(bq.anchor.c,bq.c),math.min(bq.anchor.r,bq.r),math.max(bq.anchor.c,bq.c),math.max(bq.anchor.r,bq.r))end;return u.refName(bq.c,bq.r)end
local function bu()if bq then local bw=bv()
O=O:sub(1,bq.at)..bw..O:sub(bq.at+1)br=bq.at+#bw;bq=nil;Y=nil end end;local bt={c=e.c,r=e.r}
while true do k=bq and"POINT"or bs;local bB=
bq and(O:sub(1,bq.at)..bv()..O:sub(
bq.at+1))or O;local bC=bq and
(bq.at+#bv())or br;local bA=bB:sub(1,bC)
local bz=bB:sub(bC+1)local bF=j-2;local bD=math.max(1,#bA-bF+10)
l={{x=1,text=T(bA:sub(bD),j),fg=d.fg,bg=d.bg}}local by=#bA:sub(bD)+1
if by<=j then
l[2]={x=by,text=(
bz:sub(1,1)~=""and bz:sub(1,1)or" "),fg=d.selfg,bg=d.selbg}if#bz>1 and by+1 <=j then
l[3]={x=by+1,text=bz:sub(2,j-by),fg=d.fg,bg=d.bg}end end
if bq then
Y=bq.anchor and
{math.min(bq.anchor.c,bq.c),math.min(bq.anchor.r,bq.r),math.max(bq.anchor.c,bq.c),math.max(bq.anchor.r,bq.r)}or
{bq.c,bq.r,bq.c,bq.r}e.c,e.r=bq.c,bq.r;aj()else e.c,e.r=bt.c,bt.r end;ab()local bE,bx,bw=ac()
if bE=="paste"then bu()local bG=bx:gsub(I," ")O=O:sub(1,br)..bG..
O:sub(br+1)br=br+#bG elseif bE=="key"then local bG=

bw==200 or bw==208 or bw==203 or bw==205 or bw==201 or bw==209
if
y(bx,bw)then
if bq then bq=nil;Y=nil else e.c,e.r=bt.c,bt.r;Y=nil;l=nil;return"cancel"end elseif bw==28 then bu()e.c,e.r=bt.c,bt.r;if
aH(O,bs=="LABEL"and"LABEL"or"VALUE")then l=nil;f(nil)return"commit"end;bs="EDIT"elseif bw==60 and
not bq then bs="EDIT"elseif bw==62 then bu()O,br=v.cycleAbs(O,br)elseif
bw==61 and bs~="LABEL"then local bH={}for bI in pairs(c.names)do bH[#bH+1]=bI end
table.sort(bH)
if#bH>0 then
local bI=av((function()local bJ={}for bL,bK in ipairs(bH)do
bJ[#bJ+1]={label=bK,desc="Insert this range name"}end;return bJ end)())if bI then bu()
O=O:sub(1,br)..bH[bI]..O:sub(br+1)br=br+#bH[bI]end end elseif bq then
if bw==14 then if bq.anchor then bq.anchor=nil else bq=nil;Y=nil end elseif bx==46 then if
not bq.anchor then bq.anchor={c=bq.c,r=bq.r}end elseif bG or bw==199 then
al(bq,bw,am())elseif bx and bx>=32 and bx<127 then bu()O=O:sub(1,br)..
string.char(bx)..O:sub(br+1)br=br+1 end elseif bG and bs=="VALUE"and v.wantsRef(O:sub(1,br))then
bq={at=br,c=bt.c,r=bt.r}al(bq,bw,am())elseif bG and bs~="EDIT"then e.c,e.r=bt.c,bt.r
if aH(O,
bs=="LABEL"and"LABEL"or"VALUE")then l=nil;f(nil)return"move",bw end;bs="EDIT"elseif bs=="EDIT"and(bw==200 or bw==208)then
e.c,e.r=bt.c,bt.r;if aH(O,"VALUE")then l=nil;f(nil)return"move",bw end elseif bs=="EDIT"and
bw==203 then br=math.max(0,br-1)elseif bs=="EDIT"and bw==205 then
br=math.min(#O,br+1)elseif bs=="EDIT"and bw==199 then br=0 elseif bs=="EDIT"and bw==207 then br=#O elseif bw==14 then if br>0 then O=
O:sub(1,br-1)..O:sub(br+1)br=br-1 end;if O==
""and bs~="EDIT"then l=nil;return"cancel"end elseif bw==211 then if br<#O then O=
O:sub(1,br)..O:sub(br+2)end elseif bx and bx>=32 and
bx<127 then
O=O:sub(1,br)..string.char(bx)..O:sub(br+1)br=br+1 end end end end
local function bn(O)local bq,br=0,0
if O==200 then br=-1 elseif O==208 then br=1 elseif O==203 then bq=-1 elseif O==205 then bq=1 else return false end
local function bs(bv,bw)return c.cells[u._key(bv,bw)]~=nil end;local P,bp=e.c,e.r;local bt=bs(P,bp)local bu=bs(P+bq,bp+br)
if bt and bu then
while
P+bq>=1 and
bp+br>=1 and P+bq<=u.MAX_COLS and bp+br<=u.MAX_ROWS and bs(P+bq,bp+br)do P,bp=P+bq,bp+br end else
repeat P,bp=P+bq,bp+br until
P<1 or bp<1 or P>u.MAX_COLS or bp>u.MAX_ROWS or bs(P,bp)
if P<1 or bp<1 or P>u.MAX_COLS or bp>u.MAX_ROWS then
P=math.max(1,math.min(u.MAX_COLS,P))bp=math.max(1,math.min(u.MAX_ROWS,bp))end end;e.c,e.r=P,bp;return true end
local function bo()
local O=t("Enter address to go to:",u.refName(e.c,e.r))if not O then return end;local P=c.names[O:upper()]
if P then e.c,e.r=P[1],P[2]return end;local bp,bq=u.parseRef(O:upper())if bp then e.c,e.r=bp,bq else ae()
f("Invalid cell address: "..O,"err")end end
if
i and i:lower():match("%.csv$")and fs and fs.exists and fs.exists(s(i))then local O=s(i)
local bp,P=pcall(fs.readFile,O)
if bp and type(P)==z then local bq=u.fromCSV(c,P,1,1)n(true)
i=O:gsub("%.[Cc][Ss][Vv]$",w)af=true
f(string.format("Imported %d cell(s) from %s; ^S saves it as %s.",bq,O,i:match("[^/]+$")),"hi")else f(G..O,"err")i=nil end elseif i then if fs and fs.exists and
(fs.exists(s(i))or fs.exists(s(i)..w))then aN(i)else i=s(i)
f("New worksheet: "..i,nil)end end;ab()
while not aq do k="READY"ab()local bp,P,O,bq=ac()
if bp=="touch"then local br,bs=ap(),aC()for bu,bt in ipairs(br)do
if
P>=bt.x and P<bt.x+bt.w then for bu,bv in ipairs(bs)do
if bv.y==O then e.c,e.r=bt.c,bv.r end end end end;f(nil)elseif
bp==M then local br=(bq or 0)>0 and-3 or 3;e.r=math.max(1,math.min(u.MAX_ROWS,
e.r+br))aj()elseif
bp=="paste"then
local br=aI(P:gsub(I," "),v.entryMode(P:sub(1,1))or"LABEL")elseif bp=="key"then
if O~=207 and not
(O==200 or O==208 or O==203 or O==205)then ai=false end;if X~="err"or(P and P>=32)then f(nil)end
if y(P,O)then
g["app.quit"]()elseif P==47 or P==60 then bm()elseif P==19 then if i then au(i)else local br=t(H,s("sheet"..w))if br and
br~=""then au(br)end end elseif O==59 then
aw("Help",be())elseif O==60 then local br=u.raw(c,e.c,e.r)local bs,bt=aI(br,"EDIT",#br)if bs=="move"then
al(e,bt,am())end elseif O==61 then local br={}
for bs in pairs(c.names)do br[#br+1]=bs end;table.sort(br)
if#br==0 then
f("There are no range names.",nil)else local bs=t("Go to range name:",br[1],br)
if
bs and c.names[bs:upper()]then local bt=c.names[bs:upper()]e.c,e.r=bt[1],bt[2]end end elseif O==63 then bo()elseif O==67 then n(true)elseif O==207 then ai=not ai elseif ai and bn(O)then ai=false elseif O==199 then e.c,e.r=m.cols+1,
m.rows+1 elseif O==211 then if u.raw(c,e.c,e.r)~=""then
u.set(c,e.c,e.r,nil)h()n()end elseif O==15 then local br=ap()
e.c=math.min(u.MAX_COLS,e.c+math.max(1,#br-
m.cols))elseif al(e,O,am())then elseif P and P>=32 and P<127 then local br=string.char(P)
local bs,bt=aI(br,v.entryMode(br))if bs=="move"then al(e,bt,am())end end;aj()end end;ad(1,1,j,Q," ",d.fg,d.bg)end;return{commands={calc=N},text=v}