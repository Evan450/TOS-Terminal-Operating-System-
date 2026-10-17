local y=" \194\183 "local p=require("shell.panels.ui")local n={}local r=nil
local function t()if
r==nil then local a,b=pcall(require,"shell.panels.desktop")
r=(a and b)or false end;return r or nil end;function n._forgetDesktop()r=nil end;local u=nil;local function v()if u==nil then
local a,b=pcall(require,"kernel.ustr")u=(a and b)or false end
return u or nil end;local function w(a,b)local c=v()if c and c.fit then return
c.fit(a,b)end
return tostring(a or""):sub(1,b)end
local function s(a)local b=v()if b and b.width then return
b.width(a)end;return#tostring(a or"")end
function n.markToggle(a,d,b,c)a._viewToggleSpans=a._viewToggleSpans or{}a._viewToggleSpans[d]=(
b and c)and{s=b,e=c}or nil end
function n.hitToggle(a,b,c)
local d=a._viewToggleSpans and a._viewToggleSpans[c]return d~=nil and b>=d.s and b<=d.e end
local function o(b,a,...)local d,c=pcall(require,"kernel.i18n")if d and c and c.t then
return c.t(b,a,...)end;if select("#",...)>0 then
return string.format(a,...)end;return a end;function n.enabled(a)return a and not a.uiSplit end
local function q(a)local b=a.tabs and
a.tabs[a.activeTab]if b and
(b.type==nil or b.type=="shell")then return b end;for d,c in ipairs(a.tabs or{})do if
c.type=="shell"then return c end end
return nil end;n.tab=q
function n.view(b,a)if not n.enabled(b)then return"files"end;a=a or q(b)return
(a and
a.view=="tiles")and"tiles"or"files"end;function n.isTiles(a,b)return n.view(a,b)=="tiles"end
function n.setView(b,c,a)if not
n.enabled(b)then return false end;a=a or q(b)
if not a then return false end;local d=(c=="tiles")and"tiles"or"files"if
a.view==d then return false end
if d=="tiles"and not t()then
b.lastOut={"Tiles unavailable: not enough memory to load the app list",(
b.T or{}).error}return false end;a.view=d;if d=="tiles"then n.refresh(b,a)end;return true end;function n.toggle(b,a)a=a or q(b)return
n.setView(b,n.isTiles(b,a)and"files"or"tiles",a)end
function n.viewKeyLabel(a)
local c,b=pcall(require,"shell.keys")
if c and b and b.label then
local d=b.label("view",a and a.who or nil)if d and d~=""then return
(d:match("^[^/]+")or d):gsub("%s+$","")end end;return"F2"end
function n.cycleKeyLabel(a)return n.enabled(a)and"Tab"or"F2"end
function n.isViewKey(a,c,b)local e,d=pcall(require,"shell.keys")
if e and d and d.is then return d.is("view",c,b,
a and a.who or nil)end;return b==
(a and a.KEYS and a.KEYS.homeView or 60)end
function n.refresh(b,a)a=a or q(b)if not a then return end;local c=t()
if not c then a.apps=a.apps or{}return end;c.refresh(b,a,{home=n.enabled(b)})end
function n.apps(b,a)a=a or q(b)if not a then return{}end
if not a.apps then n.refresh(b,a)end;return a.apps or{}end;function n.listMode(a)return
(a.tier or 1)<2 or a.W<46 or a.TILE_H<4 end
function n.grid(a)
local b={x=2,y=a.TILE_TOP,w=a.W-2,h=math.max(3,a.TILE_H)}local c=(a.W>=120)and 18 or 14
local d=(a.H>=40)and 5 or 4;return p.tileGrid(b,{tileW=c,tileH=d})end
function n.perPage(a)
if n.listMode(a)then return math.max(1,a.TILE_H)end;return n.grid(a).perPage end
function n.pageOf(b,a)local f=n.apps(b,a)local c=n.perPage(b)
local g=(a and a.sel)or 1;local d=math.max(1,math.ceil(#f/c))local e=math.min(d,
math.floor((g-1)/c)+1)return e,d, (e-1)*c,c end
function n.drawHeader(a,b)local g,c,e=a.D,a.T,a.W;local h=
(a.SC and a.SC.get and a.SC.get("hostname"))or"tos"local f="--:--"
local i,d=pcall(os.date,"*t")
if i and d then f=string.format("%02d:%02d",d.hour,d.min)end
p.drawRail(g,c,a.RAIL_ROW,e,{{label="\226\140\130 ".. (a.who or"?").."@"..h},{text=
a.cwd or"/"},{text=f,at=e-8}},{labelFg=c.title or
c.fg})end
function n.drawBand(a,b)local j,e,k=a.D,a.T,a.W;local h=n.apps(a,b)local i,c,l,m=n.pageOf(a,b)local A=math.max(0,math.min(m,
#h-l))local d={}a._homeBand=nil;if c>1 then
d[#d+1]={label=
"\226\128\185 page "..i.."/"..c.." \226\128\186"}end
local f=o("home.band","%d tiles \194\183 %d shown",#h,A)if c>1 then
f=f..y..
((i<c)and o("home.band.next","PgDn next page")or
o("home.band.back","PgUp back"))end;d[#d+1]={text=f}
local g=p.drawRail(j,e,a.BAND_ROW,k,d,{labelFg=
e.title or e.fg})if c>1 and g[1]then
a._homeBand={row=a.BAND_ROW,prev=g[1].s,next=g[1].e,pages=c}end end
function n.drawTiles(a,b)local d,c,e=a.D,a.T,a.W;local f=n.apps(a,b)local l,l,h,k=n.pageOf(a,b)
local i=b.sel or 1
d.fill(1,a.TILE_TOP,e,math.max(0,a.TILE_H)," ",c.fg,c.bg)
if n.listMode(a)then
for g=1,k do local E=h+g;local D=f[E]if not D then break end
local m=a.TILE_TOP+g-1;local A=(E==i)
local B=A and(c.sel_fg or c.bg)or c.fg
local C=A and(c.sel_bg or c.highlight)or c.bg;d.fill(1,m,e,1," ",B,C)
local F=(g<=9)and("["..g.."] ")or"    "
d.set(2,m,F,A and B or(c.dim or c.fg),C)
d.set(6,m,D.glyph or"\194\183",A and B or(c.title or c.fg),C)
d.set(8,m,w(tostring(D.label),e-9),B,C)end;return end;local j=n.grid(a)
for g=1,j.perPage do local A=h+g;local m=f[A]if not m then break end
local B=p.tileRect(j,g)if B then
p.drawTile(d,c,B,{glyph=m.glyph,label=m.label,selected=(A==i),dim=m.pkg})end end end
function n.summaryText(a,b)local d=n.apps(a,b)local h,h,e,f=n.pageOf(a,b)
local g=math.max(0,math.min(f,#d-e))local c=o("home.sum","%d tiles \194\183 %d shown",#d,g)if
a.browser and a.browser.freeStr then c=c..
y..a.browser.freeStr.." free"end
return c end
function n.hintText(a,b)local k=n.apps(a,b)local d=k[b.sel or 1]
local l=n.viewKeyLabel(a)local m,h=n.pageOf(a,b)local f
if d and d.hint and d.hint~=""then f=
(d.label or"").." \226\128\148 "..d.hint else
f=o("home.keys","Enter Open \194\183 Arrows Move \194\183 Alt+1-9 Quick")end
local i=l.." "..o("home.key.files","Files")local e={i}if h>1 then
e[#e+1]=((m<h)and"PgDn"or"PgUp").." "..
o("home.key.page","Page")end
e[#e+1]="F10 "..o("home.key.quit","Quit")local c=" "..f;local g,j=nil,nil
for B,A in ipairs(e)do local C=c..y..A
if s(C)>a.W-2 then break end;if A==i then g=s(c)+4;j=g+s(A)-1 end;c=C end
if b.dropped and b.dropped>0 then local A=c..
o("home.more","   (+%d more via the prompt)",b.dropped)if
s(A)<=a.W-2 then c=A end end;return w(c,a.W-1),g,j end
function n.activate(a,c,d,b)local f=t()if not f then return 0 end;local e=f.resolveApp(c.apps,d)
if e.type==
"tab"then n.setView(a,"files",c)return 3 elseif e.type=="settings"then
local h,g=pcall(require,"shell.panels.settingsapp")if h and g then g.open(a)else
a.lastOut={"Settings unavailable: "..tostring(g),a.T.error}end;return 3 elseif e.type=="logout"then
a.E.push("tos_logout",a.displayIdx)return 3,"exit"elseif e.type=="cmd"then if b and b.exec then b.exec(e.cmd)end
return 3 end;return 0 end;local z=1
local function x(b,a)
if type(a)~="number"or a<2 or a>10 then return nil end;if b~=nil and b~=0 then return nil end;return a-z end;n._altDigit=x
function n.handleKey(b,a,e,c,d)local g=n.apps(b,a)local f=a.sel or 1
local k,k,k,i=n.pageOf(b,a)
local h=n.listMode(b)and 1 or n.grid(b).cols;if
c==28 and(b.cmdline==""or b.cmdline==nil)then return n.activate(b,a,f,d)end
local j=x(e,c)if j then local k,k,m=n.pageOf(b,a)local l=m+j
if g[l]then a.sel=l;return n.activate(b,a,l,d)end;return 0 end
if c==203 then if f>1 then
a.sel=f-1;return 3 end;return 0 elseif c==205 then if f<#g then a.sel=f+1;return 3 end;return 0 elseif
c==200 then if f-h>=1 then a.sel=f-h;return 3 end;return 0 elseif c==208 then
if f+h<=#g then a.sel=f+h;return 3 end;return 0 elseif c==201 then a.sel=math.max(1,f-i)return 3 elseif c==209 then
a.sel=math.min(math.max(1,#g),f+i)return 3 elseif
c==199 and(b.cmdline==""or b.cmdline==nil)then a.sel=1;return 3 elseif
c==207 and(b.cmdline==""or b.cmdline==nil)then a.sel=math.max(1,#g)return 3 end;return nil end
function n.handleClick(a,c,b,d)local h=n.apps(a,c)local j,j,i,g=n.pageOf(a,c)local f=a._homeBand
if f and
b.y==f.row then
if b.x==f.prev then
c.sel=math.max(1,(c.sel or 1)-g)return 3 elseif b.x==f.next then
c.sel=math.min(math.max(1,#h),(c.sel or 1)+g)return 3 end;return 0 end
if b.y<a.TILE_TOP or b.y>=a.TILE_TOP+a.TILE_H then return 0 end;local e
if n.listMode(a)then local k=b.y-a.TILE_TOP+1
if k>=1 and k<=g then e=i+k end else local k=p.tileHit(n.grid(a),b.x,b.y)if k then e=i+k end end;if not e or not h[e]then return 0 end;c.sel=e
if b.button==1 then return 3 end;return n.activate(a,c,e,d)end
function n.handleScroll(b,a,c)local e=n.apps(b,a)
local f=(c.dir or 0)>0 and-1 or 1
local d=math.max(1,math.min(math.max(1,#e),(a.sel or 1)+f))if d==a.sel then return 0 end;a.sel=d;return 3 end;return n