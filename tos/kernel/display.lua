local R,S="number","highlight"local C={}local D=nil;local E,G=50,16
local B={bg=0x000000,fg=0xE6E6E6,border=0x2FB8C6,title=0xFFD75A,highlight=0x42D77D,selected_bg=0x0E5E70,selected_fg=0xFFFFFF,menubar_bg=0x262B33,menubar_fg=0xE6E6E6,menubar_hot=0xFFD75A,statusbar_bg=0x103C4E,statusbar_fg=0xBFE3EE,error=0xFF5C57,warning=0xFFA042,dim=0x909090,panel_bg=0x000000,input_bg=0x14181E,input_fg=0xFFFFFF,syn_keyword=0x61AFEF,syn_string=0x98C379,syn_comment=0x7A828E,syn_number=0xD19A66,syn_func=0xE5C07B,file_lua=0x56B6C2,dir_color=0x42D77D}
local T={tl="┌",tr="┐",bl="└",br="┘",h="─",v="│",lt="├",rt="┤",tt="┬",bt="┴",cross="┼",DTL="╔",DTR="╗",DBL="╚",DBR="╝",DH="═",DV="║"}
local U={tl="+",tr="+",bl="+",br="+",h="-",v="|",lt="+",rt="+",tt="+",bt="+",cross="+",DTL="+",DTR="+",DBL="+",DBR="+",DH="=",DV="|"}local F=T;local L=1;local J=1;local H,I=nil,nil;local K;local M=false
local function V(a)
local b={getResolution=function()return E,G end,maxResolution=function()return E,G end,getViewport=function()return
E,G end,getDepth=function()return L end,getBackground=function()return I or 0x000000 end,getForeground=function()return H or
0xFFFFFF end,get=function()
return" ",H or 0xFFFFFF,I or 0x000000 end}local c={_tosRawGpu=a}
return
setmetatable(c,{__index=function(e,d)local f=a[d]
if type(f)~="function"then return f end
local g=function(...)
if not M then local j,i,k,l,m,n=pcall(f,...)if j then return i,k,l,m,n end;M=true
pcall(function()
require("computer").pushSignal("tos_display_lost",tostring(i))end)end;local h=b[d]if h then return h()end;return true end;rawset(e,d,g)return g end})end;function C.isLost()return M end
function C.init(a,b,c)M=false
if a and not a._tosRawGpu then a=V(a)end;D=a
if D then
if
type(b)==R and type(c)==R and b>0 and c>0 then pcall(D.setResolution,b,c)else
local h,f,g=pcall(D.maxResolution)if h and f and g then pcall(D.setResolution,f,g)end end;E,G=D.getResolution()local e,d=pcall(D.getDepth)if e and d then L=d;if d<=1 then J=1 elseif d<=4 then
J=2 else J=3 end end
D.setBackground(0x000000)D.setForeground(0xFFFFFF)I,H=0x000000,0xFFFFFF;if not _G._BIOS_CY then
D.fill(1,1,E,G," ")end
if J==1 then F=U;B.bg=0x000000;B.fg=0xFFFFFF;B.border=0xFFFFFF
B.title=0xFFFFFF;B.highlight=0xFFFFFF;B.dim=0xFFFFFF;B.error=0xFFFFFF;B.warning=0xFFFFFF
B.panel_bg=0x000000;B.input_bg=0x000000;B.selected_bg=0xFFFFFF;B.selected_fg=0x000000
B.menubar_bg=0xFFFFFF;B.menubar_fg=0x000000;B.menubar_hot=0x000000;B.statusbar_bg=0xFFFFFF
B.statusbar_fg=0x000000;B.syn_keyword=0xFFFFFF;B.syn_string=0xFFFFFF;B.syn_comment=0xFFFFFF
B.syn_number=0xFFFFFF;B.syn_func=0xFFFFFF;B.file_lua=0xFFFFFF;B.dir_color=0xFFFFFF;K()elseif J==2 then
B.fg=0xFFFFFF;B.dim=0xCCCCCC;B.border=0x6699FF;B.title=0xFFFF33;B.highlight=0x33CC33
B.warning=0xFFCC33;B.error=0xFF3333;B.selected_bg=0x336699;B.selected_fg=0xFFFFFF
B.menubar_bg=0x333333;B.menubar_fg=0xFFFFFF;B.menubar_hot=0xFFCC33;B.statusbar_bg=0x336699
B.statusbar_fg=0xFFFFFF;B.input_bg=0x333333;B.syn_keyword=0x6699FF;B.syn_string=0x33CC33
B.syn_comment=0xCCCCCC;B.syn_number=0xFFCC33;B.syn_func=0xFFFF33;B.file_lua=0x6699FF
B.dir_color=0x33CC33;K()else B.syn_keyword=0x61AFEF;B.syn_string=0x98C379;B.syn_comment=0x7A828E
B.syn_number=0xD19A66;B.syn_func=0xE5C07B;B.file_lua=0x56B6C2;B.dir_color=0x42D77D;K()end end;if b then E=b end;if c then G=c end end;function C.getGpuTier()return J end;function C.getGpuDepth()return L end
function C.isMonochrome()return L<=1 end;function C.getSize()return E,G end;function C.refreshSize()if D then local c,a,b=pcall(D.getResolution)if
c and a and b then E,G=a,b end end
return E,G end
function C.getTheme()return B end
local W={bar_fg="menubar_fg",bar_bg="menubar_bg",bar_accent="menubar_hot",statusbar_fg="statusbar_fg",statusbar_bg="statusbar_bg",prompt=S,title="title",dim="dim",border="border",dir="dir_color",file="fg",file_exec=S,file_cfg="warning",file_log="dim",file_lua="file_lua",success=S,warning="warning",error="error"}function C.c(a)local c=B[a]if c~=nil then return c end;local b=W[a]
if b and B[b]~=nil then return B[b]end;return B.fg end
local function N(b,a,c)if b~=a then
return b end;local d
if a==0xFFFFFF then d=0x000000 elseif a==0x000000 then d=0xFFFFFF else d=0xFFFFFF-a end;local f,e=pcall(require,"kernel.log")if f and e and e.warn then
e.warn("display",string.format("%s fg/bg collision (both 0x%06X); forcing fg to 0x%06X",
c or"?",a,d))end;return d end
K=function()B.panel_active=B.border;B.panel_inactive=B.dim;B.sel_bg=B.selected_bg
B.sel_fg=N(B.selected_fg,B.selected_bg,"selection")B.dir=B.highlight;B.file=B.fg;B.file_exec=B.highlight;B.file_cfg=B.warning
B.file_log=B.dim;B.bar_fg=N(B.menubar_fg,B.menubar_bg,"menubar")
B.bar_bg=B.menubar_bg;B.bar_accent=B.menubar_hot
B.statusbar_fg=N(B.statusbar_fg,B.statusbar_bg,"statusbar")end;K()
local X={bg=true,fg=true,border=true,title=true,highlight=true,dim=true,error=true,warning=true,panel_bg=true,input_bg=true,input_fg=true,selected_bg=true,selected_fg=true,menubar_bg=true,menubar_fg=true,menubar_hot=true,statusbar_bg=true,statusbar_fg=true,syn_keyword=true,syn_string=true,syn_comment=true,syn_number=true,syn_func=true,file_lua=true,dir_color=true}
local function Y(a)return type(a)==R and a==math.floor(a)and a>=0 and a<=
0xFFFFFF end
local Z={0xFFFFFF,0xFFCC33,0xCC66CC,0x6699FF,0xFFFF33,0x33CC33,0xFF6699,0x333333,0xCCCCCC,0x336699,0x9933CC,0x333399,0x663300,0x336600,0xFF3333,0x000000}local _={0xFFFFFF,0xCCCCCC,0x333333,0x000000}
local function O(a)
local c=(a>>16)&0xFF;local d=(a>>8)&0xFF;local e=a&0xFF
local h=math.max(c,d,e)-math.min(c,d,e)local i=(h<=32)and _ or Z;local g,f
for j,b in ipairs(i)do
local k=c- ((b>>16)&0xFF)local l=d- ((b>>8)&0xFF)local m=e- (b&0xFF)local n=k*k*3+
l*l*4+m*m*2;if not f or n<f then f,g=n,b end end;return g end;C._snapToT2=O
function C.setTheme(a)
if type(a)~="table"then return false,"overrides must be a table"end;local c=(L==4)local b=0;for e,d in pairs(a)do
if X[e]and Y(d)then B[e]=c and O(d)or d;b=b+1 end end;K()return true,b end
local function P(a)if a~=H then D.setForeground(a)H=a end end
local function Q(a)if a~=I then D.setBackground(a)I=a end end;function C.invalidateColors()H,I=nil,nil end
function C.set(c,d,e,a,b)if not D then return end
if a then P(a)end;if b then Q(b)end;D.set(c,d,e)end;function C.fill(c,d,e,f,g,a,b)if not D then return end;if a then P(a)end;if b then Q(b)end
D.fill(c,d,e,f,g or" ")end;function C.clear(a)
C.fill(1,1,E,G," ",nil,a or B.bg)end;function C.getGpu()return D end
function C.scrollUp(a,b)
if not D then return end;a=a or 1;b=b or G;local c=b-a;if c<1 then return end;D.copy(1,a+1,E,c,0,-1)
D.setBackground(0x000000)D.setForeground(0xFFFFFF)I,H=0x000000,0xFFFFFF
D.fill(1,b,E,1," ")end
function C.box(a,b,c,d,f,e)e=e or{}local h=e.border or B.border;local g=e.bg or B.panel_bg;local i=
e.title or B.title;C.fill(a,b,c,d," ",B.fg,g)
C.set(a,b,F.tl,h,g)C.set(a+1,b,string.rep(F.h,c-2),h,g)
C.set(a+c-1,b,F.tr,h,g)C.set(a,b+d-1,F.bl,h,g)
C.set(a+1,b+d-1,string.rep(F.h,c-2),h,g)C.set(a+c-1,b+d-1,F.br,h,g)for j=b+1,b+d-2 do
C.set(a,j,F.v,h,g)C.set(a+c-1,j,F.v,h,g)end;if f then
local j=" "..f.." "local k=a+math.floor((c-#j)/2)
C.set(k,b,j,i,g)end end
function C.dbox(a,b,c,d,f,e)e=e or{}local h=e.border or B.border
local g=e.bg or B.panel_bg;local i=e.title or B.title;C.fill(a,b,c,d," ",B.fg,g)
C.set(a,b,F.DTL,h,g)C.set(a+1,b,string.rep(F.DH,c-2),h,g)
C.set(a+c-1,b,F.DTR,h,g)C.set(a,b+d-1,F.DBL,h,g)
C.set(a+1,b+d-1,string.rep(F.DH,c-2),h,g)C.set(a+c-1,b+d-1,F.DBR,h,g)for j=b+1,b+d-2 do
C.set(a,j,F.DV,h,g)C.set(a+c-1,j,F.DV,h,g)end;if f then
local j=" "..f.." "local k=a+math.floor((c-#j)/2)
C.set(k,b,j,i,g)end end
function C.hdivider(b,c,d,a)local e=(a and a.border)or B.border;local f=(a and a.bg)or
B.panel_bg;C.set(b,c,F.lt,e,f)
C.set(b+1,c,string.rep(F.h,d-2),e,f)C.set(b+d-1,c,F.rt,e,f)end
function C.menuBar(a)C.fill(1,1,E,1," ",B.menubar_fg,B.menubar_bg)local b=2
for d,c in
ipairs(a)do local e=c.label or""local f=c.hotkey
if f then local g=e:find(f,1,true)
if g then
C.set(b,1,e:sub(1,g-1),B.menubar_fg,B.menubar_bg)C.set(b+g-1,1,f,B.menubar_hot,B.menubar_bg)C.set(b+g,1,e:sub(
g+1),B.menubar_fg,B.menubar_bg)else
C.set(b,1,e,B.menubar_fg,B.menubar_bg)end else C.set(b,1,e,B.menubar_fg,B.menubar_bg)end;b=b+#e+2 end end
function C.statusBar(c,b,a)a=a or G
C.fill(1,a,E,1," ",B.statusbar_fg,B.statusbar_bg)
if c then C.set(2,a,c,B.statusbar_fg,B.statusbar_bg)end
if b then C.set(E-#b+1,a,b,B.statusbar_fg,B.statusbar_bg)end end
function C.fkeyBar(b,a)a=a or G;C.fill(1,a,E,1," ",B.fg,B.menubar_bg)local c=1;local d=math.floor(
E/math.max(#b,1))
for f,e in ipairs(b)do local g="["..
(e.key or"").."]"local h=e.label or""
C.set(c,a,g,B.dim,B.menubar_bg)C.set(c+#g,a,h,B.menubar_fg,B.menubar_bg)c=c+d end end
function C.fit(a,b,c)a=tostring(a or"")
if#a>b then return a:sub(1,b-1).."…"elseif
c=="right"then return string.rep(" ",b-#a)..a elseif c=="center"then local d=b-#a;local e=math.floor(
d/2)return
string.rep(" ",e)..a..string.rep(" ",d-e)else return a..string.rep(" ",b-#a)end end
function C.writeWrapped(e,f,a,g,b,c,d)c=c or B.fg;d=d or B.panel_bg;local h=0;local i=1
while i<=#b+1 and h<g do local k=
b:find("\n",i,true)or(#b+1)local j=b:sub(i,k-1)i=k+1;if#j==0 then C.set(e,f+
h,C.fit("",a),c,d)h=h+1 else
while#j>0 and h<g do
local l=j:sub(1,a)C.set(e,f+h,C.fit(l,a),c,d)j=j:sub(a+1)h=h+1 end end end;return h end
function C.dialog(c,a,b)b=b or{"OK"}local d={}local h=1
while h<=#a+1 do
local o=a:find("\n",h,true)or(#a+1)d[#d+1]=a:sub(h,o-1)h=o+1 end;if#d==0 then d[1]=""end;local e=#c+4
for p,o in ipairs(d)do if#o>e then e=#o end end;local f=0;for p,o in ipairs(b)do f=f+#o+4 end;if f>e then e=f end
local i=math.min(e+4,E-4)local j=#d+5;local k=math.floor((E-i)/2)+1;local l=
math.floor((G-j)/2)+1;C.dbox(k,l,i,j,c)
for o,p in ipairs(d)do C.set(k+2,l+1+o-1,C.fit(p,
i-4),B.fg,B.panel_bg)end;local g=k+math.floor((i-f)/2)local m=l+j-2;local n={}
for o,p in
ipairs(b)do local q="[ "..p.." ]"n[o]={x=g,label=p}
if o==1 then
C.set(g,m,q,B.selected_fg,B.selected_bg)else C.set(g,m,q,B.fg,B.panel_bg)end;g=g+#q+2 end;return n,m end
function C.menuBarEx(b,c,d,a)a=a or 1
C.fill(1,a,E,1," ",B.menubar_fg,B.menubar_bg)local e=2
for g,f in ipairs(b)do local h=" ".. (f.label or"").." "if d and
g==c then C.set(e,a,h,B.sel_fg,B.sel_bg)else
C.set(e,a,h,B.menubar_fg,B.menubar_bg)end;f._x=e;f._w=#h;e=e+#h+1 end end
function C.dropdown(a,b,c,d)local h=0;local e=0;for m,l in ipairs(c)do
if not l.sep then
h=math.max(h,# (l.label or""))e=math.max(e,# (l.key or""))end end
local j=e>0 and 2 or 0;local k=h+j+e;local f=k+4;local i=#c+2;if a+f>E then a=E-f end;if a<1 then a=1 end;if b+i>G then
b=G-i end;if b<1 then b=1 end
C.box(a,b,f,i,nil,{border=B.border,bg=B.panel_bg})local g=b+1
for m,l in ipairs(c)do
if l.sep then C.hdivider(a,g,f)else
local n=" "..C.fit(l.label or"",h)if e>0 then
n=n.."  "..C.fit(l.key or"",e,"right")end;n=n.." "if m==d then
C.set(a+1,g,n,B.sel_fg,B.sel_bg)else local o=l.disabled and B.dim or B.fg
C.set(a+1,g,n,o,B.panel_bg)end end;g=g+1 end;return f,i end;C.contextMenu=C.dropdown
local function aa(c,d)if c==d then return true end;if type(c)~="table"or type(d)~=
"table"then return true end;local e,a=pcall(function()
return c.address end)
local f,b=pcall(function()return d.address end)
if not e or not f or a==nil or b==nil then return true end;return a==b end
function C.withContext(a,b,c,d)local f,g,h=D,E,G;local i,j=H,I;D,E,G=a,b,c;H,I=nil,nil
local e=table.pack(pcall(d))D,E,G=f,g,h;if aa(a,f)then H,I=nil,nil else H,I=i,j end;if e[1]then return
table.unpack(e,2,e.n)else error(e[2],2)end end;C.BOX=F;C.THEME=B;return C