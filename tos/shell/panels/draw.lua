local W=require("computer")
local B=require("shell.panels.helpers")local N=require("shell.panels.widgets")
local C=require("shell.panels.ui")local E=require("shell.panels.selection")
local A=require("shell.panels.textcol")local z={}local I=nil
local function O()if I==nil then local a,b=pcall(require,"kernel.ustr")I=(a and b)or
false end;return I or nil end;local function X(a,b)local c=O()if c and c.fit then return c.fit(a,b)end;return
tostring(a or""):sub(1,b)end;local function J(a)
local b=O()if b and b.width then return b.width(a)end
return#tostring(a or"")end;local K=nil;local function F()if K==nil then
local a,b=pcall(require,"shell.panels.home")K=(a and b)or false end;return
K or nil end;local L=nil
local function P()if L==
nil then local a,b=pcall(require,"shell.panels.apps")
L=(a and b)or false end;return L or nil end
local function M(c,a,b)a=tostring(a or"")if A.isAscii(a)then
return(a..c.padW):sub(1,b)end;local d=A.slice(a,1,b)return d..
c.padW:sub(1,math.max(0,b-A.cells(d)))end
local Q={{label="File",items={{label="New File",action="newfile"},{label="New Directory",action="mkdir",key="F7"},{label="Rename",action="rename"},{label="Delete",action="delete",key="F8"},{sep=true},{label="Refresh",action="refresh"}}},{label="View",items={{label="View File",action="viewfile",key="F3"},{label="Edit File",action="editfile"}}},{label="Tools",items={{label="Lua REPL",action="lua"},{label="Verify System",action="verify"},{label="Flash EEPROM",action="flash"},{sep=true},{label="Packages",action="run:pkg"},{label="Repair (SRM)",action="run:srm"},{label="Diagnostics",action="run:doctor"}}},{label="System",items={{label="Desktop",action="run:desktop"},{label="Processes",action="ps"},{label="Memory",action="mem"},{label="Hardware",action="hw"},{label="Disk Usage",action="df"},{label="System Log",action="log"},{sep=true},{label="CLI Mode",action="run:cli"},{sep=true},{label="Log Out",action="logout"},{label="Reboot",action="reboot"},{label="Shut Down",action="shutdown"}}},{label="Settings",items={{label="Settings App",action="run:settings"},{label="Theme",action="run:theme list"},{label="Status Bar",action="statusbar_cfg"},{label="Menu Bar",action="run:menu"},{label="Boot Settings",action="run:bootsettings"}}},{label="Help",items={{label="Quick Help",action="help",key="F1"},{label="Keyboard Shortcuts",action="keyhelp"},{label="Manual Pages",action="man"},{sep=true},{label="Tutorial",action="tutorial"},{label="About TOS",action="about"}}}}z.menuDefs=Q
local function R()local a={}
for c,b in ipairs(Q)do local d={label=b.label,items={}}
for c,e in ipairs(b.items)do
local f={}for g,h in pairs(e)do f[g]=h end;d.items[#d.items+1]=f end;a[#a+1]=d end;return a end
local function D(a,b)for d,c in ipairs(a)do if c.label==b then return c,d end end end
local function G(a,b)for d,c in ipairs(a)do
for f,e in ipairs(c.items)do if e.label==b then return e,f,c end end end end
local function S(b,a)if type(a)~="table"then return end
local function c(k,l)return(type(k)=="string"and#k>0 and#k<=
(l or 24))and k or
nil end
if a.remove~=nil then local k=c(a.remove,32)if not k then return end
if a.menu==true then
local m,l=D(b,k)if l then table.remove(b,l)end else local n,m,l=G(b,k)if l then
table.remove(l.items,m)end end;return end
if a.rename~=nil then local k,l=c(a.rename,32),c(a.to,24)
if not(k and l)then return end;local n=D(b,k)if n then n.label=l;return end;local o=G(b,k)if o then o.label=l end;return end
if a.move~=nil then local l,m=c(a.move,32),c(a.menu,24)
if not(l and m)then return end;local n,p,o=G(b,l)local k=D(b,m)if n and o and k then table.remove(o.items,p)k.items[
#k.items+1]=n end;return end
if a.menu~=nil and a.cmd==nil and a.label==nil and
a.add==nil then local k=c(a.menu,24)
if not k or D(b,k)then return end;local l={label=k,items={}}local n,m=D(b,c(a.after,24)or"")if m then table.insert(b,
m+1,l)else
table.insert(b,math.max(1,#b),l)end;return end;local e=c(a.add,24)or c(a.label,24)
local f=
(
type(a.cmd)=="string"and#a.cmd>0 and#a.cmd<=200)and a.cmd or nil;if not(e and f)then return end;local d=D(b,a.menu or"")
if not d then
d=D(b,"Custom")if not d then d={label="Custom",items={}}
table.insert(b,math.max(1,#b),d)end end;local g={label=e,action="run:"..f}
local j,h,i=G(b,c(a.after,32)or"")if h and i==d then table.insert(d.items,h+1,g)else
d.items[#d.items+1]=g end end
local function T(c,a,b)if not
(a and a.F and a.F.exists and a.F.exists(b))then return end
local e=a.F.readFile(b)local g,d=pcall(require,"kernel.serialize")if not
(e and g and d and d.decode)then return end
local h,f=pcall(d.decode,e,{maxBytes=8192})if not h or type(f)~="table"then return end
for j,i in ipairs(f)do S(c,i)end end
function z.buildMenuDefs(a)local b=R()T(b,a,"/etc/menu.cfg")
if a and a.who then
local c=
(a.who=="root")and"/root"or("/home/"..a.who)T(b,a,c.."/.menu.cfg")end;if#b==0 then return R()end;return b end;z._applyEdit=S
function z.topBar(a)local d,b,g=a.D,a.T,a.W
local e=b.menubar_fg or b.bar_fg or b.fg;local c=b.menubar_bg or b.bar_bg or b.bg
d.fill(1,1,g,1," ",e,c)
local j=(b.dim and b.dim~=c)and b.dim or e;local k=a.menuDefs or z.menuDefs;local f=C.menuSpans(k)
local o=a.menuOpen or(
a.menuFocused and a.menuIdx or nil)
for q,p in ipairs(f)do if k[q]then k[q]._x=p.s end
if q==o then
d.set(p.s,1,p.text,b.sel_fg or c,b.sel_bg or b.highlight)else d.set(p.s,1,p.text,j,c)end end;a._menuSpans=f;local m=#f>0 and f[#f].e or 1;local h=math.floor(
W.freeMemory()/1024).."K"d.set(g-
#h,1,h,j,c)do local p=P()if p and p.refreshTabs then
pcall(p.refreshTabs,a)end end;local i=C.fitChips(a.tabs,a.activeTab,
g-#h-2,m+2)
for q,p in ipairs(i)do
if
p.state=="active"then
d.set(p.s,1,p.text,b.sel_fg or c,b.sel_bg or b.highlight)elseif p.state=="busy"then d.set(p.s,1,p.text,b.title or e,c)elseif p.state==
"more"then
d.set(p.s,1,p.text,b.highlight or b.title or e,c)else d.set(p.s,1,p.text,e,c)end end;a._tabSpans=i;local l=m+2;local n=
((i[1]and i[1].s)or(g-#h-1))-2;if n>=l then
d.set(l,1,string.rep("░",n-l+1),j,c)end end;z.tabBar=z.topBar;function z.menuBar(a)end
function z.rail(a)local f,d=a.T,a.W;local e=7
local g=a.tier>=3 and d>=80;local l=g and 6 or 0
local j=g and(d-e-l-4)or(d-e-3)local k=j+e-3
local b={{label=a.browser.path},{text="Name"}}local c=F()local h=nil;if c and c.enabled(a)then
local m=c.viewKeyLabel(a).." \226\150\184 tiles"local n=k- (J(m)+5)
if n>14 then h={label=m,at=n}b[#b+1]=h end end
b[#b+1]={text="Size",at=k}if g then b[#b+1]={text="Type",at=j+e+2}end
local i=C.drawRail(a.D,f,a.RAIL_ROW,d,b,{labelFg=
f.title or f.fg})if c then c.markToggle(a,a.RAIL_ROW,nil,nil)
for m,n in ipairs(b)do if n==h and i[m]then
c.markToggle(a,a.RAIL_ROW,i[m].s,i[m].e)end end end end
function z.sumRail(a,b)local c=b
if not c then local d=a.browser.files or{}local e=#d;if d[1]and
d[1].name==".."then e=e-1 end;c=e.." items"
if a.browser.freeStr then c=c.." · "..
a.browser.freeStr.." free"end end;C.drawRail(a.D,a.T,a.SUM_ROW,a.W,{{label=c}})end
local function U(a)local b=a.W;local c=7;local d=a.tier>=3 and b>=80;local e=d and 6 or 0;local f=d and(b-c-e-
4)or(b-c-3)return c,e,f,d end
local function V(a,b,c,f,d,e,g)local l,i,m=a.D,a.T,a.W;if b<1 or b>#a.browser.files then
l.fill(1,c,m,1," ",i.bg,i.bg)return end;local h=a.browser.files[b]
local n=
h.dir and("["..h.name.."]")or h.name
local p=h.dir and" <DIR> "or B.padL(B.fmtSz(h.sz),f)n=n:sub(1,e-2)local q="   "..B.padR(n,e-2)local o
if g then
local r=
h.dir and"dir"or(h.name:match("%.(%w+)$")or"")
o=q.." "..p.." "..B.padR(r:sub(1,d),d)else o=q.." "..p end;local j,k;if b==a.browser.sel then j,k=i.sel_fg,i.sel_bg else
j,k=B.fileColor(a,h),i.bg end;l.set(1,c,M(a,o,m),j,k)
if m>=
4 then l.set(2,c,C.fileGlyph(h.name,h.dir),j,k)end end
function z.fileList(a)local b,c,d,e=U(a)for f=1,a.LIST_H do local g=a.browser.scroll+f
local h=a.LIST_TOP+f-1;V(a,g,h,b,c,d,e)end end
function z.fileListRow(a,b)local c=b-a.browser.scroll
if c<1 or c>a.LIST_H then return end;local d,e,f,g=U(a)V(a,b,a.LIST_TOP+c-1,d,e,f,g)end
function z.outRow(a,b,c)local g,d,e=a.D,a.T,a.W;if a._viewToggleSpans then
a._viewToggleSpans[a.OUT_ROW]=nil end
local f=X(b and tostring(b)or"",e)
g.set(1,a.OUT_ROW,f..a.padW:sub(1,math.max(0,e-J(f))),c or
d.dim,d.bg)end
local H={"F1 Help","F3 View","F5 Copy","F6 Move","F7 New","F8 Del","F9 Menu","F10 Quit","Tab Complete"}
function z.idleHint(a)local h,f,g=a.D,a.T,a.W;local c=H;local b=F()local d=nil
if b and b.enabled(a)then d=
b.viewKeyLabel(a).." Tiles"c={H[1],d}
for k=2,#H do c[#c+1]=H[k]end;b.markToggle(a,a.OUT_ROW,nil,nil)end;local i,e="  ",""
for l,k in ipairs(c)do
local m=(e=="")and(" "..k)or(e..i..k)if#m>g then break end;if d and k==d then
b.markToggle(a,a.OUT_ROW,#m-#k+1,#m)end;e=m end;local j=(e..a.padW):sub(1,g)
h.set(1,a.OUT_ROW,j,f.dim,f.bg)end
function z.cmdGeom(a)local g=a.W
local j=a.SC and a.SC.get("hostname")or"tos"local f=a._sudo~=nil;local h=f and"[sudo] "or""
local i=f and"# "or"$ "
local c=h..a.who.."@"..j..":"..a.cwd..i;if#c>math.floor(g/2)then c=h..a.who..i end
local k=#c+1;local d=g-#c;if d<1 then d=1 end;local e=a.cmdline;local b=a.cmdCursor or(#e+1)if
b<1 then b=1 elseif b>#e+1 then b=#e+1 end;local l=B.cmdScroll(#e,b,d)return c,k,
d,l,b,f end
function z.cmdIndexAt(b,a)local g,c,d,e=z.cmdGeom(b)if not a or a<c then return nil end;if
a>c+d-1 then a=c+d-1 end;local f=(a-c)+1+e;return
math.max(1,math.min(#b.cmdline+1,f))end
function z.cmdRow(a)local c,b,i=a.D,a.T,a.W;local m,d,j,f,e,n=z.cmdGeom(a)local g=a.cmdline
local k=g:sub(f+1,f+j)local o=a.padW:sub(1,math.max(0,j-#k))
c.set(1,a.CMD_ROW,m,b.highlight,b.bg)
if n then c.set(1,a.CMD_ROW,"[sudo]",b.warning,b.bg)end;c.set(d,a.CMD_ROW,k..o,b.fg,b.bg)
local l,p=E.range(a.cmdSel,e)
if l then local q=b.sel_fg or b.bg;local r=b.sel_bg or b.highlight
for s=l,p-1 do local t=
d+ (s-1)-f;if t>=d and t<=i then
c.set(t,a.CMD_ROW,g:sub(s,s),q,r)end end end;local h=d+ ((e-1)-f)
if h>=d and h<=i then
local q=(e<=#g)and g:sub(e,e)or"_"if q==" "then q="_"end;c.set(h,a.CMD_ROW,q,b.bg,b.highlight)end end
function z.statusBar(a,b)local e,c,f=a.D,a.T,a.W;local g=N.getWidgetList(a)local d={}for i,h in ipairs(g)do
local j=b[h]
if j then local l,k=pcall(j)if l and k then d[#d+1]=h:sub(1,1):upper()..
h:sub(2)..":"..k end end end
C.drawRampBar(e,c,a.STAT_ROW,f,table.concat(d," │ "),
nil,c.statusbar_fg,c.statusbar_bg)end
function z.viewTab(b,a)local d,c,h,j=b.D,b.T,b.W,b.H;local g=a.content or{}local e=b.tier>=2 and(
#tostring(#g)+1)or 0
local f=h-e;local i=j-2;d.fill(1,2,h,i," ",c.fg,c.bg)
for p=1,i do local q=a.offset+p
if q<=#g then
local s=g[q]
local r=type(s)=="table"and s[1]or tostring(s)local t=type(s)=="table"and s[2]or c.fg
if e>0 then d.set(1,
1+p,B.formatLineNum(q,e),c.dim,c.bg)end
if a.searchTerm and#a.searchTerm>0 then
local u=r:find(a.searchTerm,1,true)
if u then d.set(e+1,1+p,A.slice(r,1,f),t,c.bg)
local v=A.cellOf(r,u)local w=r:sub(u,u+#a.searchTerm-1)if v<=f then
d.set(e+v,1+p,A.slice(w,1,
f-v+1),c.sel_fg,c.sel_bg)end else
d.set(e+1,1+p,A.slice(r,1,f),t,c.bg)end else d.set(e+1,1+p,A.slice(r,1,f),t,c.bg)end
if
a.selAnchor and E.lineRange(a.selAnchor,a.selCur or a.selAnchor)then
local u,v=E.lineRange(a.selAnchor,a.selCur or a.selAnchor)if q>=u and q<=v then
d.set(e+1,1+p,M(b,r,f),c.sel_fg or c.bg,c.sel_bg or c.highlight)end end end end;local l=math.min(i,math.max(0,#g-a.offset))
local m=
a.searchTerm and(" [/"..a.searchTerm.."]")or""local k=F()local n=k and k.cycleKeyLabel(b)or"F2"
local o=string.format("%d-%d / %d%s  [^Q]Close [^F]Find [%s]Tab",
a.offset+1,a.offset+l,#g,m,n)C.drawRampBar(d,c,j,h,o,nil,c.bar_fg,c.bar_bg)end
function z.editTab(b,a)local f,c,l,o=b.D,b.T,b.W,b.H;local h=a.lines or{""}local k=o-2;local e=
b.tier>=2 and(math.max(#tostring(
#h),2)+1)or 0;local j=l-e;local p=a.path and
a.path:match("%.lua$")local m=p and N.getSyntax(b)local g=A.cellOf(
h[a.curRow]or"",a.curCol)
local d=a.viewLeft or 1;if g<d then d=g end;if g>d+j-1 then d=g-j+1 end;if d<1 then d=1 end;a.viewLeft=d;local i=
d+j-1;f.fill(1,2,l,k," ",c.fg,c.bg)
for t=1,k do
local u=a.viewTop+t-1
if u<=#h then local w=h[u]local v=1+t
if e>0 then
local x=u==a.curRow and c.title or c.dim;f.set(1,v,B.formatLineNum(u,e),x,c.bg)end
if m then local y=m.tokenize(w)local x=1
for Z,Y in ipairs(y)do local aa=Y.text
local ab=x+A.cells(aa)-1;local _=math.max(x,d)local ac=math.min(ab,i)
if ac>=_ then
local ad=A.slice(aa,_-x+1,ac-x+1)if#ad>0 then
f.set(e+ (_-d)+1,v,ad,m.tokenColor(Y.type,c),c.bg)end end;x=ab+1;if x>i then break end end else f.set(e+1,v,A.slice(w,d,i),c.fg,c.bg)end;if d>1 then f.set(e+1,v,"<",c.dim,c.bg)end;if
A.cells(w)>i then f.set(e+j,v,">",c.dim,c.bg)end end end
if a.selAnchor then local t=c.sel_fg or c.bg;local u=c.sel_bg or c.highlight
local v={row=a.curRow,col=a.curCol}
for w=1,k do local y=a.viewTop+w-1;local x=h[y]
if x then local Y,_;if A.isAscii(x)then Y=nil else
Y,_=A.units(x)end;local aa=Y and#Y or#x
for ab=d,math.min(aa,i)do
local ac=Y and Y[ab]or ab;if E.contains(a.selAnchor,v,y,ac)then
f.set(e+ (ab-d)+1,1+w,Y and _[ab]or x:sub(ab,ab),t,u)end end;local Z=aa+1
if
Z>=d and Z<=i and E.contains(a.selAnchor,v,y,#x+1)then f.set(e+ (Z-d)+1,1+w," ",t,u)end end end end;local n=a.curRow-a.viewTop+2
if n>=2 and n<2+k then
local t=e+ (g-d)+1
if t>=e+1 and t<=e+j then
local u=A.slice(h[a.curRow]or"",g,g)if u==""then u=" "end;f.set(t,n,u,c.sel_fg,c.sel_bg)end end;local q=a.modified and" [+]"or""local r=a.searchTerm and
(" [/"..a.searchTerm.."]")or""
local s=string.format("%s%s  Ln %d, Col %d%s  [^S]Save [^F]Find [^Q]Close",a.label,q,a.curRow,g,r)C.drawRampBar(f,c,o,l,s,nil,c.bar_fg,c.bar_bg)end
function z.shell(a,b)local c=F()local d=a.tabs[a.activeTab]
local e=c and c.isTiles(a,d)
if e then c.drawHeader(a,d)c.drawBand(a,d)c.drawTiles(a,d)
z.sumRail(a,c.summaryText(a,d))else a._homeBand=nil;z.rail(a)z.fileList(a)z.sumRail(a)end;if c then c.markToggle(a,a.OUT_ROW,nil,nil)end
if
a.outLines and#a.outLines>0 then z.outLines(a)elseif a.lastOut then
z.outMessage(a,a.lastOut[1],a.lastOut[2])elseif e then local f,g,h=c.hintText(a,d)z.outRow(a,f,a.T.dim)
c.markToggle(a,a.OUT_ROW,g,h)else z.idleHint(a)end;z.cmdRow(a)z.statusBar(a,b)end
function z.outMessage(a,c,b)local f=a.W;local d=tostring(c or"")
if J(d)<=f then return z.outRow(a,d,b)end;local g=B.wrapLine(d,f)local e={}
for i,h in ipairs(g)do e[#e+1]={h,b}end;z.outLines(a,e)end
function z.outLines(a,b)local h,d,i=a.D,a.T,a.W;local c=b or a.outLines
if not c or#c==0 then return end;local e=a.LIST_TOP;local f=F()
if f and f.isTiles(a)then e=a.TILE_TOP end;local g=math.min(#c,a.OUT_ROW-e+1)
local e=a.OUT_ROW-g+1;for j=1,g do local k=c[j]or{"",d.fg}
h.set(1,e+j-1,M(a,k[1],i),k[2]or d.fg,d.bg)end end
function z.all(a,b)
local c=a.D and a.D.beginFrame and a.D.beginFrame()if not c then return z._allBody(a,b)end
local d,e=pcall(z._allBody,a,b)a.D.endFrame()if not d then error(e,0)end end
function z._allBody(a,b)z.topBar(a)local c=a.tabs[a.activeTab]
if
not c or c.type=="shell"then z.shell(a,b)elseif c.type=="view"or c.type=="output"then
z.viewTab(a,c)elseif c.type=="edit"then z.editTab(a,c)else local d=P()
if d then d.ensureBuiltins()
local e=d.get(c.type)if e and e.draw then e.draw(a,c)end end end end
function z.menuDropdown(a)if not a.menuOpen then return end
local b=(a.menuDefs or z.menuDefs)[a.menuOpen]if not b then return end;local c=b._x or 2
a.D.dropdown(c,a.MENU_ROW+1,b.items,a.menuSel)end;function z.contextMenu(a)if not a.ctxOpen then return end
a.D.dropdown(a.ctxX,a.ctxY,a.ctxItems,a.ctxSel)end;return z