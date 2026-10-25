local K=".center"local C=require("component")
local L=require("computer")local y=require("write.doc")local D=require("printerfmt")
local M,x=pcall(require,"printer")if not M then x=nil end
local function N(a,b,c)local k=C.list and C.list("gpu")()if
not k then a("No GPU found.",0xFF0000)return nil end
local l,d=pcall(C.proxy,k)
if not l or not d then a("Cannot open the GPU.",0xFF0000)return nil end;local f,g=d.getResolution()if not f or not g then
a("Cannot detect screen size.",0xFF0000)return nil end;if f<b or g<c then
a(string.format("Screen too small: need %dx%d, have %dx%d.",b,c,f,g),0xFF6600)return nil end
local m,i=pcall(d.getDepth)
local e=(m and type(i)=="number")and(i<=1 and 1 or
(i<=4 and 2 or 3))or 1
local j=(e==1)and
{fg=0xFFFFFF,dim=0xFFFFFF,border=0xFFFFFF,title=0xFFFFFF,hi=0xFFFFFF,warn=0xFFFFFF,bg=0x000000,sel=0xFFFFFF}or
{fg=0xFFFFFF,dim=0xAAAAAA,bg=0x000000,border=e==2 and
0x55FFFF or 0x00FFFF,title=e==2 and 0xFFFF55 or 0xFFFF00,hi=
e==2 and 0x55FF55 or 0x00FF00,warn=e==2 and 0xFF5555 or 0xFF4040,sel=e==2 and 0x336699 or 0x2A4A6A}local h={W=f,H=g,tier=e,T=j,gpu=d}function h.set(p,q,r,n,o)
if n then pcall(d.setForeground,n)end;if o then pcall(d.setBackground,o)end
pcall(d.set,p,q,r)end
function h.fill(p,q,r,s,t,n,o)if n then
pcall(d.setForeground,n)end;if o then pcall(d.setBackground,o)end;pcall(d.fill,p,q,r,s,
t or" ")end;function h.clear()h.fill(1,1,f,g," ",j.fg,j.bg)end;return h end
local function z(a,b)a=tostring(a or"")if#a>b then return
a:sub(1,math.max(1,b-1)).."…"end;return
a..string.rep(" ",b-#a)end
local w={F1=59,F2=60,F3=61,F4=62,F5=63,F6=64,F7=65,F10=68,ESC=1,ENTER=28,BACK=14,DEL=211,TAB=15,UP=200,DOWN=208,LEFT=203,RIGHT=205,PGUP=201,PGDN=209,HOME=199,END=207}local G=17;local A
do local a,b=pcall(require,"shell.keys")A=a and b or nil end
local function E(b,a)if A and A.is then return A.is("quit",b,a)end;return a==w.F10 or b==G or
a==w.ESC end;local function F()
if A and A.label then local a=A.label("quit")if a~=""then return a end end;return"F10"end
local function B(a)
local b={L.pullSignal(a)}if b[1]=="key_down"then return b[3],b[4]end;if b[1]=="interrupted"then
return G,nil end;return nil,nil end
local function H()return fs and fs.readFile and fs.writeFile end;local I=64*1024
local function O(a)if not H()then return nil,"no filesystem access"end;if not
fs.exists(a)then return nil,nil end;local c,b=pcall(fs.readFile,a)
if
not c or not b then return nil,tostring(b or"cannot read")end;if#b>I then
return nil,string.format("%d bytes; the limit is %d",#b,I)end;return b end
local function P(a,b)if not H()then return false,"no filesystem access"end
local c,d=pcall(fs.writeFile,a,b)
if not c then return false,tostring(d or"write failed")end;return true end
local function J(a,c,b)local h=N(c,46,12)if not h then return end;local e,i,n=h.T,h.W,h.H;local u,U
if b then u=tostring(b)else
u,U=O(a)if U then c("Cannot open "..a..": "..U,0xFF5555)
return end end;local ac=(u==nil)local f=y.toBuffer(u or"")local d,g=1,1;local o=1;local v=b~=nil;local j=ac and(
"New document: "..a)or nil
if
b then j="Not saved yet: F2 saves it as "..a end;local t=false;local r=1;local s,k,X;local V=true;local Y,Z,_=D.width,D.MAX_WIDTH,"estimated"
if x and
x.available()then Y=x.measurer()Z=x.maxWidth()local ao,an=x.width("M")if an==
"component"then _="printer"end end
local function S()if not V then return end;s=y.parse(y.serialize(f))
k=y.layout(s,{measure=Y,maxWidth=Z})X=y.stats(s,k)V=false end;local function l()v=true;V=true end;local m,T=3,n-2;local p=T-m+1
local function ad()S()
h.fill(1,1,i,1," ",e.bg,e.border)local aq=a:match("[^/]+$")or a
h.set(2,1,"WRITE  "..
aq.. (v and" *"or""),e.bg,e.border)local ar=s.title or"(untitled)"local an="Title: "..ar;if#an+12 <i then
h.set(math.max(12,
i-#an-1),1,an,e.bg,e.border)end;local as=y.pageFor(k,d)or 1
local au,ap=y.locate(k,d)local ao=y.cost(k,1)
local at=string.format("page %d/%d  line %s/%d  %d words  %d sheet(s), %d black, %d colour  [%s widths]",as,#k,ap and
tostring(ap)or"-",D.MAX_LINES,X.words,ao.paper,ao.black,ao.color,_)h.set(1,2,z(at,i),e.dim,e.bg)end
local function ae()h.fill(1,m,i,p," ",e.fg,e.bg)local an={}for ap=2,#k do local aq=k[ap][1]if
aq and aq.src then an[aq.src]=ap end end
for ap=0,
p-1 do local aq=o+ap;local ar=f[aq]if ar==nil then break end;local as=m+ap
if an[aq]then
h.set(1,as,z(string.rep("─",math.max(0,
i-12))..string.format(" page %d ",an[aq]),i),e.border,e.bg)else
local at=ar:sub(1,1)=="."and ar:sub(1,2)~=".."local au=at and e.title or e.fg
h.set(1,as,string.format("%4d ",aq),e.dim,e.bg)h.set(6,as,z(ar,i-5),au,e.bg)end end;local ao=m+ (d-o)if ao>=m and ao<=T then local ap=f[d]:sub(g,g)
if ap==""then ap=" "end;local aq=6+ (g-1)
if aq<=i then h.set(aq,ao,ap,e.bg,e.hi)end end end
local function af()h.fill(1,m,i,p," ",e.fg,e.bg)local an=k[r]or{}
h.set(2,m,string.format("── sheet %d of %d ──",r,
#k),e.title,e.bg)
for ap,ao in ipairs(an)do local ar=m+ap;if ar>T then break end;local aq=ao.text;local as=i-4;if ao.align=="center"then
aq=string.rep(" ",math.max(0,math.floor((
as-#aq)/2)))..aq end;h.set(3,ar,z(aq,as),ao.color and e.warn or
e.fg,e.bg)end;if#an==0 then
h.set(3,m+1,"(this sheet is empty)",e.dim,e.bg)end end
local function ag()
if j then h.set(1,n-1,z(j,i),e.hi,e.bg)else local ao=s.warnings[1]
if ao then
h.set(1,n-1,z(string.format("line %d: %s",ao.line,ao.text),i),e.warn,e.bg)else h.fill(1,n-1,i,1," ",e.fg,e.bg)end end
local an=t and
("F5 edit · PgUp/PgDn sheet · F3 print · "..F().." quit")or
(
"F1 help · F2 save · F3 print · F4 title · F5 pages · F6 break · F7 centre · "..F().." quit")if#an>i-2 then
an="F1 help · F2 save · F3 print · F5 pages · "..F().." quit"end
h.fill(1,n,i,1," ",e.bg,e.border)h.set(2,n,z(an,i-2),e.bg,e.border)end
local function W()S()h.clear()ad()if t then af()else ae()end;ag()end
local function ah(an,ao)local ap=tostring(ao or"")
while true do
h.fill(1,n-1,i,1," ",e.fg,e.bg)
h.set(1,n-1,z(an.." "..ap.."_",i),e.title,e.bg)local aq,ar=B()if ar==w.ENTER then return ap end;if E(aq,ar)then return nil end;if
ar==w.BACK then ap=ap:sub(1,-2)elseif aq and aq>=32 and aq<127 then
ap=ap..string.char(aq)end end end
local function aa(an)h.fill(1,n-1,i,1," ",e.fg,e.bg)
h.set(1,n-1,z(an.."  (Y/N)",i),e.warn,e.bg)
while true do local ao,ap=B()if E(ao,ap)then return false end
if ao then
local aq=string.char(ao):lower()if aq=="y"then return true end;if aq=="n"then return false end end end end
local function ai()h.fill(1,m,i,p," ",e.fg,e.bg)
local an={"WRITE — a word processor for TOS","","The rail at the top is the point: it shows which printed","sheet the cursor is on, how full that sheet is, and what","the document will cost in paper and ink.","","Formatting rides on DOT COMMANDS in column one, so the","file stays plain text you can cat, grep and mail:","","  .title My Report     the printed page's item name","  .center / .left      alignment, from here on","  .color 0xFF0000      colour, from here on (.color off)","  .page                start a new sheet","  .nf / .fi            lines as typed (a table) / filled","  ..text               a literal line starting with a dot","","Colour costs one unit of COLOUR ink per line — the rail","counts it separately so it cannot surprise you.","","Press any key."}for ao,ap in ipairs(an)do local aq=m+ao-1;if aq>T then break end
h.set(2,aq,z(ap,i-2),ao==1 and e.title or e.fg,e.bg)end;B()end
local function ab()local an,ao=P(a,y.serialize(f))if not an then
j="NOT SAVED: "..tostring(ao)return false end;v=false;j="Saved "..a;return true end
local function aj()S()
if not x then j="The printer driver is not available (pkg enable printer)."return end;if not x.available()then
j="No printer: "..tostring(x.unavailableReason())return end;local ao=y.cost(k,1)
if not
aa(string.format("Print %d sheet(s), %d black, %d colour?",ao.paper,ao.black,ao.color))then j="Not printed."return end
local an=x.job(s.title or(a:match("[^/]+$")or"Document"))
for au,av in ipairs(k)do if au>1 then an:pageBreak()end;for ax,aw in ipairs(av)do
local ay,az=an:line(aw.text,aw.color,aw.align)
if not ay then j="Cannot print: "..tostring(az)return end end end;local ar,as=an:check()
if not ar then j="Refused: "..tostring(as)return end;local ap,at,aq=an:commit()
if not ap then
j="Print failed: "..tostring(at)if(aq or 0)>0 then
j=j..string.format(" (%d sheet(s) DID print)",aq)end;return end;j=string.format("Printed %d sheet(s).",ap)end
local function ak()local an=ah("Title:",s.title or"")if an==nil then return end
for ap,ao in
ipairs(f)do if ao:match("^%.title%s")or ao==".title"then
f[ap]=".title "..an;l()j="Title set."return end end;table.insert(f,1,".title "..an)d=d+1;l()j="Title set."end;local function al(an)table.insert(f,d,an)d=d+1;g=1;l()end
local function am()
local an=f[d-1]if an==K then f[d-1]=".left"l()j="Left."return end;if an==".left"then
f[d-1]=K;l()j="Centred."return end;table.insert(f,d,K)
d=d+1;l()j="Centred."end
local function q()if d<1 then d=1 end;if d>#f then d=#f end;local an=#f[d]if g<1 then g=1 end
if g>an+1 then g=an+1 end;if d<o then o=d end;if d>o+p-1 then o=d-p+1 end;if o<1 then o=1 end end;W()
while true do local ao,an=B()if an~=nil or ao~=nil then j=nil end
if E(ao,an)then if v then
if aa("Save "..a..
" before leaving?")then if not ab()then W()end end end;break elseif an==w.F1 then ai()elseif
an==w.F2 or ao==19 then ab()elseif an==w.F3 then aj()elseif an==w.F4 then ak()elseif an==w.F5 then S()t=not t;r=math.min(math.max(1,y.pageFor(k,d)or 1),math.max(1,
#k))elseif t then if
an==w.PGDN or an==w.DOWN or an==w.RIGHT then
r=math.min(#k,r+1)elseif an==w.PGUP or an==w.UP or an==w.LEFT then
r=math.max(1,r-1)end elseif an==w.F6 then
al(".page")elseif an==w.F7 then am()elseif an==w.UP then d=d-1;q()elseif an==w.DOWN then d=d+1;q()elseif an==w.LEFT then if g>1 then g=g-1 elseif d>1 then d=d-1;g=#
f[d]+1 end;q()elseif an==w.RIGHT then if g<=#f[d]then g=g+1 elseif d<#f then
d=d+1;g=1 end;q()elseif an==w.HOME then g=1 elseif an==w.END then g=#f[d]+1 elseif
an==w.PGUP then d=d-p;q()elseif an==w.PGDN then d=d+p;q()elseif an==w.ENTER then local ap=f[d]f[d]=ap:sub(1,g-1)table.insert(f,
d+1,ap:sub(g))d=d+1;g=1;l()q()elseif an==w.BACK then
if g>1 then
local ap=f[d]f[d]=ap:sub(1,g-2)..ap:sub(g)g=g-1;l()elseif d>1 then
local ap=#f[d-1]f[d-1]=f[d-1]..f[d]table.remove(f,d)d=d-1;g=ap+1;l()end;q()elseif an==w.DEL then local ap=f[d]
if g<=#ap then
f[d]=ap:sub(1,g-1)..ap:sub(g+1)l()elseif d<#f then f[d]=ap..f[d+1]table.remove(f,d+1)l()end elseif an==w.TAB then local ap=f[d]
f[d]=ap:sub(1,g-1).."    "..ap:sub(g)g=g+4;l()elseif ao and ao>=32 and ao<127 then local ap=f[d]f[d]=ap:sub(1,g-1)..
string.char(ao)..ap:sub(g)g=g+1
l()end;W()end;h.clear()end
local function Q(b,a)b=b or{}local c=b[1]
if not c or c=="help"then
a("write — a word processor for TOS",0xFFFF55)
a("  write <path>     Open (or create) a document",0xFFFFFF)a("",0xFFFFFF)
a("Unlike `edit`, it knows where the printed page breaks and",0xAAAAAA)
a("what the document will cost in paper and ink. Formatting",0xAAAAAA)
a("uses dot commands (.title .center .color .page), so the",0xAAAAAA)a("file stays plain text.",0xAAAAAA)if
x and not x.available()then a("",0xFFFFFF)
a("No printer attached: composing and pagination still work.",0xAAAAAA)end;return end;if c:sub(1,1)~="/"then
a("Give a full path (e.g. /home/report.txt).",0xFF5555)return end;J(c,a)end
local R={VERSION="1.1.0",open=function(b,c,a)a=a or print;if type(b)~="string"or b:sub(1,1)~="/"then
a("write: a document needs a full path to be saved at.",0xFF5555)return false end
J(b,a,c or"")return true end}return{commands={write=Q},api=R}