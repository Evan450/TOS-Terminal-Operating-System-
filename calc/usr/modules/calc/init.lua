
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
local function N(b,a)a=a or print;local aI=C.list and C.list("gpu")()if not aI then
a("No GPU found.",0xFF0000)return end;local aR,_=pcall(C.proxy,aI)if not aR or not _ then
a("Cannot open the GPU.",0xFF0000)return end;local j,Q=_.getResolution()if
not j or not Q or j<40 or Q<12 then
a("calc needs at least a 40x12 screen.",0xFF6600)return end
local aS,ay=pcall(_.getDepth)
local V=(aS and type(ay)=="number")and(ay<=1 and 1 or
(ay<=4 and 2 or 3))or 1;local ar=(V==1)
local d=
ar and
{bg=0x000000,fg=0xFFFFFF,dim=0xFFFFFF,title=0xFFFFFF,selfg=0x000000,selbg=0xFFFFFF,err=0xFFFFFF,hi=0xFFFFFF,framefg=0x000000,framebg=0xFFFFFF,modefg=0x000000,modebg=0xFFFFFF,range=0xFFFFFF,s1=0xFFFFFF,s2=0xFFFFFF,s3=0xFFFFFF}or
{bg=0x000000,fg=0xFFFFFF,dim=0xAAAAAA,title=V==2 and 0xFFFF55 or 0xFFFF00,selfg=0x000000,selbg=V==2 and 0x55FFFF or 0x00FFFF,err=
V==2 and 0xFF5555 or 0xFF4040,hi=V==2 and 0x55FF55 or 0x00FF00,framefg=0x000000,framebg=
V==2 and 0xAAAAAA or 0x9A9A9A,modefg=0x000000,modebg=V==2 and 0xFFFF55 or 0xFFFF00,range=V==2 and
0x336699 or 0x2A4A6A,s1=V==2 and 0x55FFFF or 0x00C0FF,s2=
V==2 and 0xFF55FF or 0xFF60C0,s3=V==2 and 0x55FF55 or 0x80E040}
local function o(bo,bp,bq,O,P)if O then pcall(_.setForeground,O)end;if P then
pcall(_.setBackground,P)end;pcall(_.set,bo,bp,bq)end
local function ad(bo,bp,bq,br,bs,O,P)if O then pcall(_.setForeground,O)end;if P then
pcall(_.setBackground,P)end;pcall(_.fill,bo,bp,bq,br,bs or" ")end;local T,R=v.pad,v.ulen;local function ae()pcall(A.beep,880,0.05)end
local az,aa,as,ah
local function S()az=az or require("calc.ops")return az end;local c=u.new()local W=u.evaluator(c)local an=false;local e={c=1,r=1}
local p={c=1,r=1}local m={rows=0,cols=0}local i=b and b[1]or nil;local af=false;local k="READY"
local l=nil;local q,X=nil,nil;local ai=false;local Y=nil;local Z;local function h()af=true end
local function n(O)if
c.recalc=="manual"and not O then an=true;return end;W=u.evaluator(c)an=false end;local function f(O,P)q,X=O,P end;local function aJ(O)return
fs and fs.exists and fs.exists(O)or false end
local function aA()return
{printer=aJ("/usr/lib/printer.lua"),write=aJ("/usr/modules/write/init.lua")}end;local aK,aB,at,ao=4,5,Q-1,Q;local function ag(O)return u.width(c,O)end
local function ap()local P,O={},E+1
local function bp(bq)if O>j then return
false end;local br=math.min(ag(bq),j-O+1)
P[#P+1]={c=bq,x=O,w=br}O=O+ag(bq)return true end;for bq=1,m.cols do if not bp(bq)then return P end end
local bo=math.max(p.c,m.cols+1)while bo<=u.MAX_COLS and bp(bo)do bo=bo+1 end;return P end
local function aC()local P,O={},aB
for bp=1,m.rows do if O>at then return P end;P[#P+1]={r=bp,y=O}O=O+1 end;local bo=math.max(p.r,m.rows+1)while O<=at and bo<=u.MAX_ROWS do
P[#P+1]={r=bo,y=O}O=O+1;bo=bo+1 end;return P end
local function aj(O)O=O or e
if O.r>m.rows then if O.r<p.r then p.r=O.r end
local P=at-aB+1-m.rows;if P<1 then P=1 end;if O.r>p.r+P-1 then p.r=O.r-P+1 end end;if p.r<=m.rows then p.r=m.rows+1 end
if O.c>m.cols then
if O.c<p.c then p.c=O.c end
while true do local P=ap()local bp=P[#P]local bo=false;for br,bq in ipairs(P)do if
bq.c==O.c and bq.w==ag(bq.c)then bo=true end end;if
bo or not bp or p.c>=O.c then break end;p.c=p.c+1 end end;if p.c<=m.cols then p.c=m.cols+1 end end
local function aT()local P=u.raw(c,e.c,e.r)local O=u.refName(e.c,e.r)..":"
local bo=c.fmt[u._key(e.c,e.r)]if bo then O=O.." ("..bo..")"end;if c.colw[e.c]then O=O.." [W"..c.colw[e.c]..
"]"end;if P~=
""then O=O.." "..P end;return O end
local function aU()ad(1,1,j,3," ",d.fg,d.bg)
o(1,1,T(aT(),j-9),d.fg,d.bg)local O=" "..k.." "
o(j-R(O)+1,1,O,d.modefg,d.modebg)if l then
if type(l)=="table"then for bo,P in ipairs(l)do
o(P.x,2,P.text,P.fg or d.fg,P.bg or d.bg)end else o(1,2,T(l,j),d.fg,d.bg)end end;if q then
o(1,3,T(q,j),
X=="err"and d.err or(X=="hi"and d.hi or d.dim),d.bg)end end
local function aV(O)ad(1,aK,j,1," ",d.framefg,d.framebg)
for bo,P in ipairs(O)do
local bp=u.colName(P.c)
local br=math.max(0,math.floor((P.w-#bp)/2))local bq=P.c==e.c
o(P.x,aK,T(string.rep(" ",br)..bp,P.w),
bq and d.selfg or d.framefg,bq and d.selbg or d.framebg)end end
local function aW(O,P)local bo=Y;return bo and O>=bo[1]and O<=bo[3]and P>=bo[2]and P<=
bo[4]end
local function aX(P,bo,O)local bp=c.cells[u._key(P,bo)]if not bp then
return string.rep(" ",O),d.fg end;local bu=u.classify(bp)
if bu=="label"then
local bw,by=u.cellText(c,W,P,bo,ag(P))local bz=R(bw)if bz>O then bw=v.usub(bw,1,O)end;local bx=O-R(bw)
if by=="R"then local bA=math.max(0,math.min(O,
ag(P)-1))if R(bw)<=bA then bw=
v.padLeft(bw,bA)..string.rep(" ",O-bA)else bw=
string.rep(" ",bx)..bw end elseif by==
"C"then local bA=math.floor(bx/2)bw=string.rep(" ",bA)..bw..
string.rep(" ",bx-bA)else bw=bw..
string.rep(" ",bx)end;return bw,d.fg end
local bq,bv=u.cellText(c,W,P,bo,math.max(1,ag(P)-1))local br=W.get(P,bo)
local bs=u.isErr(br)and d.err or d.fg;if bv=="L"then
return T(" "..bq,O), (type(br)==z)and d.fg or bs end;local bt=
v.padLeft(bq,math.max(1,ag(P)-1)).." "
return v.usub(bt,1,O)..string.rep(" ",math.max(0,O-
R(bt))),bs end
local function aY(bp,P,O,bo)local bt=c.cells[u._key(bp,P)]if not bt then return nil end
local bv,bw,bs=u.classify(bt)if
bv~="label"or bs=="R"or bs=="C"or bs=="REP"then return nil end
if(bs or
u.PREFIX_ALIGN[c.gprefix or"'"])~="L"then return nil end;local bu=R(bw)local br=O[bo].w;if bu<=br then return nil end;local bq=bo+1
while
bq<=#O and br<bu do local bx=O[bq]if bx.c~=O[bq-1].c+1 then break end;if
c.cells[u._key(bx.c,P)]then break end;br=br+bx.w;bq=bq+1 end;return br,bq-1 end
local function aZ(O,P)
for bp,bo in ipairs(P)do local bq,br=bo.r,bo.y;ad(1,br,j,1," ",d.fg,d.bg)local bt=bq==e.r
o(1,br,T(tostring(bq),E),
bt and d.selfg or d.framefg,bt and d.selbg or d.framebg)local bs=1
while bs<=#O do local bu=O[bs]local bv,bz=aY(bu.c,bq,O,bs)
local bw,bA=aX(bu.c,bq,bv or bu.w)local bB=bu.c==e.c and bq==e.r;local bx,by=bA,d.bg;if aW(bu.c,bq)then
bx,by=d.fg,d.range end
if bB then
o(bu.x,br,v.usub(bw,1,bu.w),d.selfg,d.selbg)if bv and bv>bu.w then
o(bu.x+bu.w,br,v.usub(bw,bu.w+1,bv),bx,by)end else o(bu.x,br,bw,bx,by)end;bs=(bz or bs)+1 end end end
local function a_()local O={}if an then O[#O+1]="CALC"end
for bo,P in pairs(W.values or{})do if u.isErr(P)and P.e==
u.E_CYCLE then O[#O+1]="CIRC"break end end;if ai then O[#O+1]="END"end;return table.concat(O," ")end
local function ba()ad(1,ao,j,1,ar and" "or"░",d.dim,d.bg)
if not ar then
o(1,ao,"▓▒░",d.dim,d.bg)if j>6 then o(j-2,ao,"░▒▓",d.dim,d.bg)end end
local P=(i and i:match("[^/]+$")or"(unsaved)").. (
af and" *"or"")local O=a_()local bo=j-9-R(P)-R(O)-2
local bp=v.fitHints({"/ Menu","F1 Help","F2 Edit","F5 Goto","F9 Calc"},math.max(0,bo),
nil)local bq=" "..P..bp
o(4,ao,T(bq,j-8-R(O)),d.fg,d.bg)if O~=""then
o(j-4-R(O),ao," "..O.." ",d.modefg,d.modebg)end end;local function ab()local O,P=ap(),aC()aU()aV(O)aZ(O,P)ba()end
local function aL()return fs and
fs.writeFile and fs.readFile end;local function bb()
if fs and fs.home then local P,O=pcall(fs.home)if
P and type(O)==z and O~=""then return O end end;return"/"end
Z=bb()
local function s(O)if not O or O==""then return nil end
if O:sub(1,1)=="/"then return O end;return
(Z:sub(-1)=="/"and Z or Z.."/")..O end
local function aD(P,O)local bo={}if not(fs and fs.list)then return bo end
local bq,bp=pcall(fs.list,P)if not bq or type(bp)~="table"then return bo end
for bs,br in ipairs(bp)do if
not
br:match("/$")and(not O or br:sub(-#O)==O)then bo[#bo+1]=br end end;table.sort(bo)return bo end
local function au(O)
if not aL()then f("No filesystem access.","err")return false end;O=s(O or i)if not O then return false end
if not O:match(J)then O=O..w end;local bo,P=pcall(fs.writeFile,O,u.serialize(c))
if
bo and P~=false then i,af=O,false;f("Saved "..O,"hi")return true end;f("Save failed: "..tostring(P),"err")
return false end
local function aM(O)
if not aL()then f("No filesystem access.","err")return end;O=s(O)if not O then return end;if
not fs.exists(O)and not O:match(J)then O=O..w end;if not fs.exists(O)then
f("No such file: "..O,"err")return end;local bp,bo=pcall(fs.readFile,O)if not bp or
type(bo)~=z then f(G..O,"err")return end
c=u.deserialize(bo)W=u.evaluator(c)an=false;i,af=O,false;e.c,e.r,p.c,p.r=1,1,1,1
m.rows,m.cols=0,0;local P="Retrieved "..O;if(c.skipped or 0)>0 then
P=P.."  ("..c.skipped..
" unreadable line(s) skipped)"end;f(P,
(c.skipped or 0)>0 and"err"or"hi")end
local function ac()
while true do local O,bq,P,bo,bp=A.pullSignal()
if O=="key_down"then return"key",P,bo end;if O=="interrupted"then return"key",17,16 end
if O=="tos_focus"then ab()elseif
O=="clipboard"and type(P)==z then return"paste",P elseif O=="touch"or O=="drag"then
return"touch",P,bo,bp elseif O==M then return M,P,bo,bp end end end
local function t(P,bo,O)local bp=tostring(bo or"")local bq=0;local br=k;k="EDIT"
while true do
l=P.." "..bp.."_"if O and#O>0 then q=table.concat(O,"  ")X=nil end
ab()local bu,bs,bt=ac()
if bu=="paste"then bp=bp..bs:gsub(I," ")elseif bu=="key"then if bt==28 then k=br
l=nil;q=nil;return bp end
if y(bs,bt)then k=br;l=nil;q=nil;return nil end
if bt==14 then bp=bp:sub(1,-2)elseif
(bt==200 or bt==208)and O and#O>0 then
bq=(bt==208)and(bq%#O+1)or((bq-2)%#O+1)bp=O[bq]elseif bs and bs>=32 and bs<127 then
bp=bp..string.char(bs)end end end end
local function ak(bo,bp,O,P)
while true do local br=t(bo,tostring(bp))if br==nil then return nil end
local bq=tonumber(br)if
bq and(not O or bq>=O)and(not P or bq<=P)then return bq end;ae()
f("Enter a number".. (O and
(" from "..O.." to "..P)or"")..".","err")end end
local function al(O,P,bo)
if P==200 then O.r=math.max(1,O.r-1)elseif P==208 then
O.r=math.min(u.MAX_ROWS,O.r+1)elseif P==203 then O.c=math.max(1,O.c-1)elseif P==205 then
O.c=math.min(u.MAX_COLS,O.c+1)elseif P==201 then O.r=math.max(1,O.r-bo)elseif P==209 then
O.r=math.min(u.MAX_ROWS,O.r+bo)elseif P==199 then O.c,O.r=1,1 else return false end;return true end
local function am()return math.max(1,at-aB+1-m.rows)end
local function r(P,O)O=O or{}local bp=O.free and nil or{c=e.c,r=e.r}
local bo={c=e.c,r=e.r}if O.start then local bv,bw,bx,by=u.parseRange(O.start)if bv then bp={c=bv,r=bw}
bo={c=bx,r=by}end end
local bq=nil;local bu,br=k,{c=e.c,r=e.r}k="POINT"
local function bt()if bq then return bq end
if bp then return
u.rangeName(math.min(bp.c,bo.c),math.min(bp.r,bo.r),math.max(bp.c,bo.c),math.max(bp.r,bo.r))end;return u.refName(bo.c,bo.r)end
local function bs(bv)k=bu;Y=nil;l,q=nil,nil;e.c,e.r=br.c,br.r;aj()return bv end
while true do
if not bq then
if bp then
Y={math.min(bp.c,bo.c),math.min(bp.r,bo.r),math.max(bp.c,bo.c),math.max(bp.r,bo.r)}else Y={bo.c,bo.r,bo.c,bo.r}end;e.c,e.r=bo.c,bo.r;aj(bo)else Y=nil end
l=P.." "..bt().. (bq and"_"or"")
q=bq and"Enter accepts"or"Arrows point · . anchors · Backspace lets go · type an address or a name"X=nil;ab()local bx,bv,bw=ac()
if bx=="touch"then local by,bz=ap(),aC()for bB,bA in ipairs(by)do
if bv>=bA.x and bv<
bA.x+bA.w then for bB,bC in ipairs(bz)do
if bC.y==bw then bo.c,bo.r=bA.c,bC.r end end end end elseif
bx=="key"then
if bw==28 then local bz=bt()local by=c.names[bz:upper()]if by then return
bs({by[1],by[2],by[3],by[4]})end
local bA,bB,bC,bD=u.parseRange(bz)if bA then return bs({bA,bB,bC,bD})end;ae()
f("Invalid cell or range address: "..bz,"err")bq=nil elseif y(bv,bw)then return bs(nil)elseif bq then
if bw==14 then bq=bq:sub(1,-2)if bq==""then bq=nil end elseif bv and
bv>=32 and bv<127 then bq=bq..string.char(bv)end elseif bw==14 then
if bp then bp=nil;bo.c,bo.r=br.c,br.r else return bs(nil)end elseif bv==46 then if not bp then bp={c=bo.c,r=bo.r}end elseif al(bo,bw,am())then elseif
bv and bv>=32 and bv<127 then bq=string.char(bv)end end end end
local function U(O)if not O then return nil end;return O[1],O[2],O[3],O[4]end
local function aE(bo,P,O)local bp,bq={},1
if O then bp[1]={x=1,text=O,fg=d.title,bg=d.bg}bq=R(O)+3 end
for br,bs in ipairs(bo)do local bt=bs.label
bp[#bp+1]={x=bq,text=bt,fg=(br==P)and d.selfg or d.fg,bg=
(br==P)and d.selbg or d.bg,index=br}bq=bq+R(bt)+2 end;return bp end;local function bc(O)if O.items then local P={}for bp,bo in ipairs(O.items)do P[#P+1]=bo.label end;return
table.concat(P,"  ")end
return O.desc end
local function av(O,P)
local bo=1;local bp=k;k="MENU"
while true do l=aE(O,bo,P)q,X=O[bo].desc,nil;ab()local bs,br,bq=ac()
if
bs=="key"then if y(br,bq)or bq==14 then k=bp;l,q=nil,nil;return nil end;if bq==28 then
k=bp;l,q=nil,nil;return bo end
if bq==203 then bo=(bo-2)%#O+1 elseif
bq==205 or bq==57 then bo=bo%#O+1 elseif br and br>32 then
ah=ah or require("calc.menu")local bt=ah.byKey(O,string.char(br))
if bt then k=bp;l,q=nil,nil;return bt end end elseif bs=="touch"and bq==2 then for bu,bt in ipairs(aE(O,bo,P))do
if bt.index and br>=bt.x and br<bt.x+
R(bt.text)then k=bp;l,q=nil,nil;return bt.index end end end end end;local function aF(O,P,bo)return
av({{label="No",desc=P},{label="Yes",desc=bo}},O)==2 end
local function aw(P,O,bo)
local bp=1;local bq=k;k=bo or"HELP"
while true do ad(1,1,j,Q," ",d.fg,d.bg)
o(1,1,T(" "..P,j-9),d.title,d.bg)o(j-7,1," "..k.." ",d.modefg,d.modebg)
for bu=0,Q-3 do
local bv=O[bp+bu]
if bv then local bw,bx=bv,d.fg;if type(bv)=="table"then
bw,bx=bv[1],(bv[2]=="title"and d.title or(bv[2]==
"dim"and d.dim or d.fg))end
o(2,2+bu,T(bw,j-2),bx,d.bg)end end
o(1,Q,T(" PgUp/PgDn scroll · any other key returns",j),d.dim,d.bg)local bs,bt,br=ac()
if bs=="key"then
if br==201 then bp=math.max(1,bp- (Q-3))elseif br==209 then
bp=math.min(math.max(1,
#O- (Q-3)),bp+ (Q-3))elseif br==200 then bp=math.max(1,bp-1)elseif br==208 then bp=math.min(math.max(1,#O- (Q-3)),
bp+1)else break end end end;k=bq end
local function bd()local bo={}for bp in pairs(u.FUNCS)do bo[#bo+1]="@"..bp end
table.sort(bo)
local P={{"calc - a spreadsheet, the 1-2-3 way","title"},"",{"Moving","title"},"  arrows, PgUp/PgDn      one cell, one screen","  Home                   to A1","  End, then an arrow     to the edge of the data that way","  F5                     go to a cell or a range name","",{"Entering","title"},"  Just type. A digit or + - . ( @ # $ = starts a VALUE (a number or a","  formula); anything else starts a LABEL. Enter keeps the pointer where","  it is; an arrow enters and moves.","  While typing a formula, after an operator, ( or , the arrows POINT","  at the cell to put in; . anchors a range; F4 makes it absolute ($).","  F2 edits the cell. Backspace and ^Q (not Esc: Minecraft takes it).","  Label prefixes:  ' left   \" right   ^ centre   \\ repeat (\\- fills)","",{"Formulas","title"},"  +A1*2   @SUM(A1..A9)   @IF(B2>100,\"over\",\"ok\")   +A1&\" \"&B1","  Operators: + - * / % ^, = <> < > <= >=, #AND# #OR# #NOT#, & (text)","  $A$1 is absolute: Copy keeps it, where A1 moves with the copy.","  A range name stands for its range: @SUM(SALES).","  1-2-3 counts from 0 in @CHOOSE, @MID, @FIND and the lookups' offset.","",{"Keys","title"},"  /   the menu (first letters pick; Backspace goes back a level)","  F1 help   F2 edit   F3 names   F4 absolute   F5 go to   F9 recalc",
"  Del clears the cell   ^S saves   ^B to the background   "..D().." quits","",{"@functions","title"}}local O="  "for bq,bp in ipairs(bo)do
if#O+#bp+1 >j-4 then P[#P+1]=O;O="  "end;O=O..bp.." "end;P[#P+1]=O
return P end
local function be()local P,bo=0,0;for bt,bs in pairs(c.cells)do P=P+1
if u.classify(bs)=="formula"then bo=bo+1 end end;local O={}for bs in pairs(c.names)do
O[#O+1]=bs end;table.sort(O)local bp
for bt,bs in pairs(W.values or{})do if
u.isErr(bs)and bs.e==u.E_CYCLE then local bu,bv=u.unkey(bt)
bp=u.refName(bu,bv)break end end
local bq=(A.freeMemory and A.freeMemory())or nil
local br={{"Worksheet status","title"},"","  Cells in use:        "..
P.."  ("..bo.." formulas)","  Extent:              A1.."..u.refName(c.cols,c.rows),
"  Global format:       ".. (u.FORMATS[c.gfmt:sub(1,1)]or c.gfmt)..
" ("..c.gfmt..")",
"  Label prefix:        "..c.gprefix,"  Column width:        "..c.gwidth,"  Recalculation:       "..
(c.recalc==
"manual"and"Manual"or"Automatic"),"  Titles:              "..m.rows..
" rows, "..m.cols.." columns","  Range names:         ".. (#O>0 and
table.concat(O," ")or"(none)"),
"  Circular reference:  ".. (bp or"(none)"),"  Memory free:         "..
(bq and(
math.floor(bq/1024).." KB")or"?"),"  Printer driver:      ".. (
aA().printer and"installed"or"not installed"),
"  write:               "..
(aA().write and"installed (Print Document)"or"not installed")}aw("Status",br,"STAT")end;local bf={F=true,S=true,C=true,[","]=true,P=true}
local function aN(O)
if not bf[O]then return O end
local P=ak("Enter number of decimal places (0..15):",2,0,15)if P==nil then return nil end;return O..math.floor(P)end
local function bg()as=as or require("calc.graph")
local bo=as.collect(c,W)local O,P=as.render(bo,j,Q-1,ar)if not O then
f("Cannot draw: "..P,"err")return end;ad(1,1,j,Q," ",d.fg,d.bg)
local bp={a=d.s1,b=d.s2,c=d.s3,axis=d.dim,title=d.title}
for bq,br in ipairs(O)do local bt,bv,bu,bs=1,1,nil,{}
for bw in br:gmatch("[%z\1-\127\194-\244][\128-\191]*")do local bx=
bp[P[bq][bt]]or d.fg;if bx~=bu and#bs>0 then
o(bv,bq,table.concat(bs),bu,d.bg)bs={}bv=bt end;bu=bx;bs[#bs+1]=bw;bt=bt+1 end
if#bs>0 then o(bv,bq,table.concat(bs),bu,d.bg)end end;o(1,Q,T(" Any key returns",j),d.dim,d.bg)ac()end;local function bh()local O,P,bo,bp=u.parseRange(c.print.range or"")
return O,P,bo,bp end
local function ax(O,P,bo)aa=aa or require(K)
local bp,bq,br,bs=bh()
if not bp then return nil,"Set a print range first (Range)."end;n(true)
return
aa.pages(c,W,bp,bq,br,bs,{target=O,measure=P,maxWidth=bo,perPage=(O=="file")and 0 or 20,header=c.print.header,footer=c.print.footer,formulas=c.print.formulas})end
local function aO()local bs,O=pcall(require,B)if not bs or type(O)~="table"then return nil,
"the printer driver is not installed"end
local P,bo=pcall(require,L)
local bp,bq,br=P and bo.width or nil,P and bo.MAX_WIDTH or 164,"estimated"
if O.available and O.available()then bp,bq=O.measurer(),O.maxWidth()
local bu,bt=O.width("M")if bt=="component"then br=B end end;return O,bp,bq,br,P and bo or nil end
local function bi(O)local bq,bs,br,bo
if O~="file"then local bv;bv,bq,bs,br,bo=aO()if not bv and O==B then
f("Cannot preview: "..bq,"err")return end
if not bv then local bx,bw=pcall(require,L)if bx then
bo,bq,bs,br=bw,bw.width,bw.MAX_WIDTH,"estimated"end end end;local bp,bu=ax(O,bq,bs)if not bp then f(bu,"err")return end;local P={}local bt=
bo and bo.cost and bo.cost(bp,1)
P[1]={string.format("%d page(s) for %s%s",#bp,O,

bt and string.format(" - %d sheet(s), %d black ink%s",bt.paper,bt.black,
br and(", "..br.." widths")or"")or""),"title"}
for bv,bw in ipairs(bp)do P[#P+1]=""
P[#P+1]={string.format("-- page %d of %d --",bv,#bp),"dim"}for by,bx in ipairs(bw)do P[#P+1]=bx end end;aw("Print preview",P,"PREV")end
local function bj(O)
if O=="file"then local bo,bq=ax("file")if not bo then f(bq,"err")return end;aa=aa or
require(K)local br=
(i and i:gsub(F,"")or s("sheet"))..".prn"
local P=t("Enter print file name:",br)if not P or P==""then return end;P=s(P)
local bs,bp=pcall(fs.writeFile,P,aa.toText(bo))
if bs and bp~=false then
f("Printed "..#bo.." page(s) to "..P,"hi")else f("Not written: "..tostring(bp),"err")end elseif O==B then local P,bq,bv,bA,br=aO()
if not P then f("Cannot print: "..bq,"err")return end;if not P.available()then
f("No printer: "..tostring(P.unavailableReason()),"err")return end;local bo,bw=ax(B,bq,bv)if not bo then
f(bw,"err")return end
local bp=P.job(
(i and i:match("([^/]+)%.%w+$"))or"Worksheet")
for bB,bC in ipairs(bo)do if bB>1 then bp:pageBreak()end
for bA,bD in ipairs(bC)do
local bE,bF=bp:line(bD)if not bE then
f("Cannot print: "..tostring(bF),"err")return end end end;local bx,by=bp:check()if not bx then
f("Refused: "..tostring(by),"err")return end
local bs=br and br.cost(bo,1)or{paper=#bo,black=0}if not
aF(string.format("Print %d sheet(s), %d black ink?",bs.paper,bs.black),"Do not print","Print it")then
f("Not printed.",nil)return end
local bt,bz,bu=bp:commit()
if not bt then
f("Print failed: "..tostring(bz)..
((bu or 0)>0 and
string.format(" (%d sheet(s) DID print)",bu)or""),"err")else f("Printed "..bt.." sheet(s).","hi")end elseif O=="write"then local br,P=pcall(require,"write")if
not br or type(P)~="table"then
f("Cannot open write: "..tostring(P),"err")return end;if
not P.api or not P.api.open then
f("This write is too old (1.1.0 adds the way in).","err")return end
local bo,bp=pcall(require,L)
local bq,bs=ax("write",bo and bp.width or nil,bo and bp.MAX_WIDTH or nil)if not bq then f(bs,"err")return end;aa=aa or require(K)
local bt=(i and
i:match("([^/]+)%.%w+$"))or"Worksheet"
local bu=(i and i:gsub(F,"")or s("sheet"))..".txt"
local bv,bw=pcall(P.api.open,bu,".nf\n"..aa.toWrite(bq,bt),a)ad(1,1,j,Q," ",d.fg,d.bg)
if not bv then
f("write stopped: "..tostring(bw),"err")else f("Back from write.",nil)end end end;local g={}
local function bk(O)local bo,bp=O:match("^([%w%.]+):?(.*)$")local P=g[bo]if not P then f(
"Not done yet: "..O,"err")return end;return
P(bp)end
g["global.format"]=function(O)local P=aN(O)if not P then return end;c.gfmt=P;h()n()end;g["global.prefix"]=function(O)c.gprefix=O;h()end
g["global.width"]=function()
local O=ak("Enter global column width (1..60):",c.gwidth,1,60)if O then c.gwidth=math.floor(O)h()end end
g["global.recalc"]=function(O)c.recalc=O;h()n(O=="auto")end
g["range.format"]=function(O)local P=false
if O~="reset"then P=aN(O)if P==nil then return end end;local bo,bp,bq,br=U(r("Enter range to format:"))
if not bo then return end;S().format(c,bo,bp,bq,br,P or nil)h()end
g["range.label"]=function(O)
local P,bo,bp,bq=U(r("Enter range of labels:"))if P then S().label(c,P,bo,bp,bq,O)h()n()end end
g["range.erase"]=function()
local O,P,bo,bp=U(r("Enter range to erase:"))if O then S().erase(c,O,P,bo,bp)h()n()end end
g["range.value"]=function()
local O,bo,bp,bq=U(r("Enter range to copy FROM:"))if not O then return end
local P,br=U(r("Enter range to copy TO:",{free=true}))if not P then return end;S().values(c,O,bo,bp,bq,P,br)h()n()end
g["name.create"]=function()local O=t("Enter name:","")
if not O or O==""then return end;if not S().validName(O)then ae()
f("Not a usable name: letters, digits and _, and not like a cell or @function.","err")return end
local P,bo,bp,bq=U(r("Enter range:"))if not P then return end;c.names[O:upper()]={P,bo,bp,bq}h()n()
f(
"Named "..O:upper().." = "..u.rangeName(P,bo,bp,bq),"hi")end;local function aP()local O={}for P in pairs(c.names)do O[#O+1]=P end;table.sort(O)
return O end
g["name.delete"]=function()local O=aP()
if
#O==0 then f("There are no range names.","err")return end;local P=t("Enter name to delete:",O[1],O)if
P and c.names[P:upper()]then c.names[P:upper()]=nil;h()n()end end
g["name.reset"]=function()if
aF("Forget every range name?","Keep the names","Forget them all")then c.names={}h()n()end end
g["name.table"]=function()
local O,P=U(r("Enter range for table:",{free=true}))if not O then return end;for bo,bp in ipairs(aP())do local bq=c.names[bp]
u.set(c,O,P+bo-1,"'"..bp)
u.set(c,O+1,P+bo-1,"'"..u.rangeName(bq[1],bq[2],bq[3],bq[4]))end;h()
n()end
g["copy"]=function()
local P,bo,bp,bq=U(r("Enter range to copy FROM:"))if not P then return end
local O=r("Enter range to copy TO:",{free=true})if not O then return end
S().copy(c,P,bo,bp,bq,O[1],O[2],O[3],O[4])h()n()end
g["move"]=function()
local P,bo,bp,bq=U(r("Enter range to move FROM:"))if not P then return end
local O=r("Enter range to move TO:",{free=true})if not O then return end;local br,bs=S().move(c,P,bo,bp,bq,O[1],O[2])if
br==nil then f(bs,"err")else h()n()end end
g["ws.insert"]=function(O)
local P,bo,bp,bq=U(r(O=="col"and"Enter column insert range:"or"Enter row insert range:"))if not P then return end
if O=="col"then S().insertCols(c,P,bp-P+1)else S().insertRows(c,bo,
bq-bo+1)end;h()n()end
g["ws.delete"]=function(O)
local P,bo,bp,bq=U(r(O=="col"and"Enter range of columns to delete:"or
"Enter range of rows to delete:"))if not P then return end
if O=="col"then S().deleteCols(c,P,bp-P+1)else S().deleteRows(c,bo,
bq-bo+1)end;h()n()end
g["col.width"]=function()local O=ag(e.c)local P=k;k="EDIT"
while true do c.colw[e.c]=O;l="Enter column width (1..60): "..
O
q,X="Left/Right change it as you watch · Enter keeps it · "..
D().." cancels",nil;ab()local bq,bo,bp=ac()
if bq=="key"then if bp==28 then break end;if y(bo,bp)then c.colw[e.c]=nil;k=P;l,q=nil,
nil;return end
if bp==203 then O=math.max(1,O-1)elseif
bp==205 then O=math.min(60,O+1)elseif bo and bo>=48 and bo<=57 then
local br=ak("Enter column width (1..60):",string.char(bo),1,60)if br then O=math.floor(br)end;break end end end;k=P;l,q=nil,nil
if O==c.gwidth then c.colw[e.c]=nil else c.colw[e.c]=O end;h()end
g["col.reset"]=function()c.colw[e.c]=nil;h()end
g["ws.erase"]=function()c=u.new()W=u.evaluator(c)i=nil;af=false;an=false
e.c,e.r,p.c,p.r=1,1,1,1;m.rows,m.cols=0,0 end
g["titles"]=function(O)if O=="clear"then m.rows,m.cols=0,0;return end;if
O=="both"or O=="h"then m.rows=math.max(0,e.r-1)end;if
O=="both"or O=="v"then m.cols=math.max(0,e.c-1)end;aj()end;g["ws.status"]=function()be()end
g["file.retrieve"]=function()if
af and not
aF("Discard unsaved changes?","Keep this worksheet","Discard its unsaved changes")then return end;local P=aD(Z,w)local O=t("Name of file to retrieve:",
P[1]or"",P)
if O and O~=""then aM(O)end end
g["file.save"]=function()local bo=i or s("sheet"..w)local P=t(H,bo)if
not P or P==""then return end;local O=s(P)if not O:match(J)then O=O..w end
if O~=i and
fs.exists(O)then
local bp=av({{label="Cancel",desc="Do not save"},{label="Replace",desc="Write over the file on disk"}},
O.." exists.")if bp~=2 then return end end;au(O)end
g["file.import"]=function()local bo=aD(Z,".csv")
local O=t("Name of CSV file to import:",bo[1]or"",bo)if not O or O==""then return end;local P=s(O)
local bq,bp=pcall(fs.readFile,P)
if not bq or type(bp)~=z then f(G..P,"err")return end;local br=u.fromCSV(c,bp,e.c,e.r)h()n()
f(string.format("Imported %d cell(s) from %s at %s.",br,P,u.refName(e.c,e.r)),"hi")end
g["file.export"]=function()local bp=
(i and i:gsub(F,"")or s("sheet"))..".csv"
local O=t("Export CSV as:",bp)if not O or O==""then return end;n(true)local P=s(O)
local bq,bo=pcall(fs.writeFile,P,u.toCSV(c,W))if bq and bo~=false then f("Exported "..P,"hi")else
f("Export failed: "..tostring(bo),"err")end end
g["file.list"]=function()
local O={{"Worksheets in "..Z,"title"},""}for bo,P in ipairs(aD(Z,w))do O[#O+1]="  "..P end;if#O==2 then
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
g["print.formulas"]=function()c.print.formulas=true;h()end;g["print.preview"]=function(O)bi(O)end
g["print.go"]=function(O)bj(O)end
g["print.clear"]=function()c.print={}h()f("Print settings cleared.")end;g["graph.type"]=function(O)c.graph.type=O;h()end
g["graph.range"]=function(O)
local P=r(
"Enter "..O:upper().." range:",{start=c.graph[O]})
if P then c.graph[O]=u.rangeName(P[1],P[2],P[3],P[4])h()end end
g["graph.title"]=function(O)
local P=t(O=="title1"and"Enter first title:"or"Enter second title:",
c.graph[O]or"")if P then c.graph[O]=P~=""and P or nil;h()end end;g["graph.reset"]=function()c.graph={}h()end;g["graph.view"]=function()
n(true)bg()end
g["data.fill"]=function()
local O,bq,br,bs=U(r("Enter fill range:"))if not O then return end;local P=ak("Start:",0)if not P then return end
local bo=ak("Step:",1)if not bo then return end;local bp=ak("Stop:",8191)if not bp then return end
S().fill(c,O,bq,br,bs,P,bo,bp)h()n()end
g["sort.range"]=function()
local O=r("Enter data range:",{start=c.sort.range})
if O then c.sort.range=u.rangeName(O[1],O[2],O[3],O[4])h()end end
local function aQ(O,P)local bp=r(P,{free=true})if not bp then return end
local bo=t("Sort order (A or D):",O=="k1"and(c.sort.o1 or
"A")or(c.sort.o2 or"A"))if not bo then return end;bo=bo:upper():sub(1,1)
if
bo~="A"and bo~="D"then ae()f("A for ascending, D for descending.","err")return end;c.sort[O]=u.refName(bp[1],bp[2])
c.sort[O=="k1"and"o1"or"o2"]=bo;h()end
g["sort.key1"]=function()aQ("k1","Primary sort key:")end
g["sort.key2"]=function()aQ("k2","Secondary sort key:")end;g["sort.reset"]=function()c.sort={}h()end
g["sort.go"]=function()local O,P,bq,bo=u.parseRange(
c.sort.range or"")local bp=c.sort.k1 and
u.parseRef(c.sort.k1)if not O or not bp then ae()
f("Set the Data-Range and the Primary-Key first.","err")return end;local br=c.sort.k2 and
u.parseRef(c.sort.k2)or nil
S().sort(c,O,P,bq,bo,bp,
c.sort.o1 ~="D",br,c.sort.o2 ~="D")h()n()
f("Sorted ".. (bo-P+1).." rows.","hi")end;local aq=false
g["app.quit"]=function()
if af then
local O=av({{label="No",desc="Stay in calc"},{label="Yes",desc="Leave without saving"},{label="Save",desc="Save, then leave"}},"Worksheet changes not saved! Leave anyway?")if O==2 then aq=true elseif O==3 then
if au(i or t(H,s("sheet"..w)))then aq=true end end else aq=true end end
local function bl()ah=ah or require("calc.menu")
local O={{items=ah.root(aA()),sel=1}}local P=k;k="MENU"
while#O>0 and not aq do local bo=O[#O]local bq=bo.items;l=aE(bq,bo.sel)q,X=bc(bq[bo.sel]),
nil;ab()local bt,bs,bp=ac()local br
if bt=="key"then if y(bs,bp)then break end
if bp==14 then
table.remove(O)elseif bp==28 then br=bo.sel elseif bp==203 then bo.sel=(bo.sel-2)%#bq+1 elseif bp==205 or bp==
57 then bo.sel=bo.sel%#bq+1 elseif bp==199 then bo.sel=1 elseif bp==207 then
bo.sel=#bq elseif bs and bs>32 then br=ah.byKey(bq,string.char(bs))
if not br then ae()end end elseif bt=="touch"and bp==2 then
for bv,bu in ipairs(l)do if
bs>=bu.x and bs<bu.x+R(bu.text)then br=bu.index end end end
if br then local bu=bq[br]bo.sel=br
if bu.items then O[#O+1]={items=bu.items,sel=1}elseif bu.cmd==
"menu.up"then table.remove(O)elseif bu.cmd=="menu.quit"then break else l,q=nil,nil;k="WAIT"
bk(bu.cmd)k="MENU"if not bu.stay then break end end end end;k=P;l=nil;if not X then q=nil end end
local function aG(O,P)if O==""then u.set(c,e.c,e.r,nil)h()n()return true end
local bo=O
if
P=="LABEL"and not u.PREFIX_ALIGN[O:sub(1,1)]then bo=(c.gprefix or"'")..O end;local bp,bq=u.classify(bo)
if bp=="formula"then local br,bs=u.parse(bq)
if not br then ae()
f(
"Not a valid formula ("..tostring(bs)..
"): fix it, start it with ' to make it a label, or "..D().." to cancel.","err")return false end end;u.set(c,e.c,e.r,bo)h()n()return true end
local function aH(O,P,bo)local bq=bo or#O;local br=P;local bp=nil
local function bu()
if bp.anchor then return
u.rangeName(math.min(bp.anchor.c,bp.c),math.min(bp.anchor.r,bp.r),math.max(bp.anchor.c,bp.c),math.max(bp.anchor.r,bp.r))end;return u.refName(bp.c,bp.r)end
local function bt()if bp then local bv=bu()
O=O:sub(1,bp.at)..bv..O:sub(bp.at+1)bq=bp.at+#bv;bp=nil;Y=nil end end;local bs={c=e.c,r=e.r}
while true do k=bp and"POINT"or br;local bA=
bp and(O:sub(1,bp.at)..bu()..O:sub(
bp.at+1))or O;local bB=bp and
(bp.at+#bu())or bq;local bz=bA:sub(1,bB)
local by=bA:sub(bB+1)local bE=j-2;local bC=math.max(1,#bz-bE+10)
l={{x=1,text=T(bz:sub(bC),j),fg=d.fg,bg=d.bg}}local bx=#bz:sub(bC)+1
if bx<=j then
l[2]={x=bx,text=(
by:sub(1,1)~=""and by:sub(1,1)or" "),fg=d.selfg,bg=d.selbg}if#by>1 and bx+1 <=j then
l[3]={x=bx+1,text=by:sub(2,j-bx),fg=d.fg,bg=d.bg}end end
if bp then
Y=bp.anchor and
{math.min(bp.anchor.c,bp.c),math.min(bp.anchor.r,bp.r),math.max(bp.anchor.c,bp.c),math.max(bp.anchor.r,bp.r)}or
{bp.c,bp.r,bp.c,bp.r}e.c,e.r=bp.c,bp.r;aj()else e.c,e.r=bs.c,bs.r end;ab()local bD,bw,bv=ac()
if bD=="paste"then bt()local bF=bw:gsub(I," ")O=O:sub(1,bq)..bF..
O:sub(bq+1)bq=bq+#bF elseif bD=="key"then local bF=

bv==200 or bv==208 or bv==203 or bv==205 or bv==201 or bv==209
if
y(bw,bv)then
if bp then bp=nil;Y=nil else e.c,e.r=bs.c,bs.r;Y=nil;l=nil;return"cancel"end elseif bv==28 then bt()e.c,e.r=bs.c,bs.r;if
aG(O,br=="LABEL"and"LABEL"or"VALUE")then l=nil;f(nil)return"commit"end;br="EDIT"elseif bv==60 and
not bp then br="EDIT"elseif bv==62 then bt()O,bq=v.cycleAbs(O,bq)elseif
bv==61 and br~="LABEL"then local bG={}for bH in pairs(c.names)do bG[#bG+1]=bH end
table.sort(bG)
if#bG>0 then
local bH=av((function()local bI={}for bK,bJ in ipairs(bG)do
bI[#bI+1]={label=bJ,desc="Insert this range name"}end;return bI end)())if bH then bt()
O=O:sub(1,bq)..bG[bH]..O:sub(bq+1)bq=bq+#bG[bH]end end elseif bp then
if bv==14 then if bp.anchor then bp.anchor=nil else bp=nil;Y=nil end elseif bw==46 then if
not bp.anchor then bp.anchor={c=bp.c,r=bp.r}end elseif bF or bv==199 then
al(bp,bv,am())elseif bw and bw>=32 and bw<127 then bt()O=O:sub(1,bq)..
string.char(bw)..O:sub(bq+1)bq=bq+1 end elseif bF and br=="VALUE"and v.wantsRef(O:sub(1,bq))then
bp={at=bq,c=bs.c,r=bs.r}al(bp,bv,am())elseif bF and br~="EDIT"then e.c,e.r=bs.c,bs.r
if aG(O,
br=="LABEL"and"LABEL"or"VALUE")then l=nil;f(nil)return"move",bv end;br="EDIT"elseif br=="EDIT"and(bv==200 or bv==208)then
e.c,e.r=bs.c,bs.r;if aG(O,"VALUE")then l=nil;f(nil)return"move",bv end elseif br=="EDIT"and
bv==203 then bq=math.max(0,bq-1)elseif br=="EDIT"and bv==205 then
bq=math.min(#O,bq+1)elseif br=="EDIT"and bv==199 then bq=0 elseif br=="EDIT"and bv==207 then bq=#O elseif bv==14 then if bq>0 then O=
O:sub(1,bq-1)..O:sub(bq+1)bq=bq-1 end;if O==
""and br~="EDIT"then l=nil;return"cancel"end elseif bv==211 then if bq<#O then O=
O:sub(1,bq)..O:sub(bq+2)end elseif bw and bw>=32 and
bw<127 then
O=O:sub(1,bq)..string.char(bw)..O:sub(bq+1)bq=bq+1 end end end end
local function bm(O)local bp,bq=0,0
if O==200 then bq=-1 elseif O==208 then bq=1 elseif O==203 then bp=-1 elseif O==205 then bp=1 else return false end
local function br(bu,bv)return c.cells[u._key(bu,bv)]~=nil end;local P,bo=e.c,e.r;local bs=br(P,bo)local bt=br(P+bp,bo+bq)
if bs and bt then
while
P+bp>=1 and
bo+bq>=1 and P+bp<=u.MAX_COLS and bo+bq<=u.MAX_ROWS and br(P+bp,bo+bq)do P,bo=P+bp,bo+bq end else
repeat P,bo=P+bp,bo+bq until
P<1 or bo<1 or P>u.MAX_COLS or bo>u.MAX_ROWS or br(P,bo)
if P<1 or bo<1 or P>u.MAX_COLS or bo>u.MAX_ROWS then
P=math.max(1,math.min(u.MAX_COLS,P))bo=math.max(1,math.min(u.MAX_ROWS,bo))end end;e.c,e.r=P,bo;return true end
local function bn()
local O=t("Enter address to go to:",u.refName(e.c,e.r))if not O then return end;local P=c.names[O:upper()]
if P then e.c,e.r=P[1],P[2]return end;local bo,bp=u.parseRef(O:upper())if bo then e.c,e.r=bo,bp else ae()
f("Invalid cell address: "..O,"err")end end
if
i and i:lower():match("%.csv$")and fs and fs.exists and fs.exists(s(i))then local O=s(i)
local bo,P=pcall(fs.readFile,O)
if bo and type(P)==z then local bp=u.fromCSV(c,P,1,1)n(true)
i=O:gsub("%.[Cc][Ss][Vv]$",w)af=true
f(string.format("Imported %d cell(s) from %s; ^S saves it as %s.",bp,O,i:match("[^/]+$")),"hi")else f(G..O,"err")i=nil end elseif i then if fs and fs.exists and
(fs.exists(s(i))or fs.exists(s(i)..w))then aM(i)else i=s(i)
f("New worksheet: "..i,nil)end end;ab()
while not aq do k="READY"ab()local bo,P,O,bp=ac()
if bo=="touch"then local bq,br=ap(),aC()for bt,bs in ipairs(bq)do
if
P>=bs.x and P<bs.x+bs.w then for bt,bu in ipairs(br)do
if bu.y==O then e.c,e.r=bs.c,bu.r end end end end;f(nil)elseif
bo==M then local bq=(bp or 0)>0 and-3 or 3;e.r=math.max(1,math.min(u.MAX_ROWS,
e.r+bq))aj()elseif
bo=="paste"then
local bq=aH(P:gsub(I," "),v.entryMode(P:sub(1,1))or"LABEL")elseif bo=="key"then
if O~=207 and not
(O==200 or O==208 or O==203 or O==205)then ai=false end;if X~="err"or(P and P>=32)then f(nil)end
if y(P,O)then
g["app.quit"]()elseif P==47 or P==60 then bl()elseif P==19 then if i then au(i)else local bq=t(H,s("sheet"..w))if bq and
bq~=""then au(bq)end end elseif O==59 then
aw("Help",bd())elseif O==60 then local bq=u.raw(c,e.c,e.r)local br,bs=aH(bq,"EDIT",#bq)if br=="move"then
al(e,bs,am())end elseif O==61 then local bq={}
for br in pairs(c.names)do bq[#bq+1]=br end;table.sort(bq)
if#bq==0 then
f("There are no range names.",nil)else local br=t("Go to range name:",bq[1],bq)
if
br and c.names[br:upper()]then local bs=c.names[br:upper()]e.c,e.r=bs[1],bs[2]end end elseif O==63 then bn()elseif O==67 then n(true)elseif O==207 then ai=not ai elseif ai and bm(O)then ai=false elseif O==199 then e.c,e.r=m.cols+1,
m.rows+1 elseif O==211 then if u.raw(c,e.c,e.r)~=""then
u.set(c,e.c,e.r,nil)h()n()end elseif O==15 then local bq=ap()
e.c=math.min(u.MAX_COLS,e.c+math.max(1,#bq-
m.cols))elseif al(e,O,am())then elseif P and P>=32 and P<127 then local bq=string.char(P)
local br,bs=aH(bq,v.entryMode(bq))if br=="move"then al(e,bs,am())end end;aj()end end;ad(1,1,j,Q," ",d.fg,d.bg)end;return{commands={calc=N},text=v}