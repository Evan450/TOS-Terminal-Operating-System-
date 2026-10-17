local I="output"local v={}local x
local function A()if x==nil then
local b,a=pcall(require,"shell.panels.textcol")
x=(b and type(a)=="table")and a or false end;return x or nil end;local y
local function B()if y==nil then local a,b=pcall(require,"shell.panels.home")
y=(a and b)or false end;return y or nil end;local z
local function C()if z==nil then local a,b=pcall(require,"shell.panels.apps")
z=(a and b)or false end;return z or nil end
local function D(b,a,c,d)local e=(c-d)+ (b.viewLeft or 1)-1
if e<1 then e=1 end;local f=A()if f then return f.colOf(a or"",e)end;return math.min(
# (a or"")+1,e)end;local w
local function E()
if w==nil then local b,a=pcall(require,"computer")w=
(b and a and a.uptime)and a or false end;if w then return w.uptime()end;return
os and os.clock and os.clock()or 0 end;local J=10
function v.available(a)
if type(a._mouseLib)=="table"then return a._mouseLib end;if a._mouseLib==false and
E()< (a._mouseProbeAt or 0)+J then return nil end
a._mouseProbeAt=E()a._mouseLib=false;local d=a.F;if d and d.exists and
not d.exists("/usr/lib/mouse.lua")then return nil end
local g,e=pcall(require,"shell.panels.helpers")local f,b=false,nil
if not(g and e.mayHavePackages)or
e.mayHavePackages()then f,b=pcall(require,"kernel.pkg")end;if
f and b and b.info and b.info("mouse")and b.isEnabled and not b.isEnabled("mouse")then
return nil end
local h,c=pcall(require,"mouse")
if h and type(c)=="table"and c.parse then a._mouseLib=c;return c end;return nil end;local function F(b,a)
for d,c in ipairs(b or{})do if a>=c.s and a<=c.e then return c end end;return nil end
local function K(b,c,a)
local e=F(b._menuSpans,a)if e then return e.idx end;if b._menuSpans then return nil end;local d=2;for f,g in ipairs(c)do local h=" "..
(g.label or"").." "
if a>=d and a<d+#h then return f end;d=d+#h+1 end;return nil end
local function L(a,b)local c=F(a._tabSpans,b)if not c then return nil end;if c.state=="more"then
return nil,true end;return c.idx end
local function M(a)local b=#a.tabs;if b<2 then return end;a.activeTab=(a.activeTab>1)and
(a.activeTab-1)or b end
local function G(c,a,b,d)local f,e=0,0;for k,j in ipairs(d)do
if not j.sep then
f=math.max(f,# (j.label or""))e=math.max(e,# (j.key or""))end end
local i=e>0 and 2 or 0;local g=f+i+e+4;local h=#d+2;if a+g>c.W then a=c.W-g end;if a<1 then a=1 end;if b+h>
c.H then b=c.H-h end;if b<1 then b=1 end;return a,b,g,h end
local function H(a,b,c,d,e,f)return a>=c and a<c+e and b>=d and b<d+f end
local function N(a,b,c)local f,e=c.x,c.y;local d=a.tabs[a.activeTab]
local g=d and d.type or"shell"local h=a.menuDefs or b.menuDefs
if a.menuOpen then local i=h[a.menuOpen]local k,j,l,m=G(a,i._x or 2,
a.MENU_ROW+1,i.items)if H(f,e,k,j,l,m)then local o=e-j
local n=i.items[o]
if n and not n.sep then a.menuSel=o;return 3,b.menuExecute(n)end;return 3 end
if e~=
a.MENU_ROW then a.menuOpen=nil;a.menuFocused=false;return 3 end end
if a.ctxOpen then local j,i,k,l=G(a,a.ctxX,a.ctxY,a.ctxItems)if H(f,e,j,i,k,l)then local n=e-i
local m=a.ctxItems[n]
if m and not m.sep then a.ctxSel=n;b.ctxExecute(m.action)end;return 3 end
a.ctxOpen=false;return 3 end
if e== (a.MENU_ROW or 1)then local j=K(a,h,f)
if j then if g~="shell"then
for l,m in ipairs(a.tabs)do if m.type==
"shell"then a.activeTab=l;break end end end
if a.menuOpen==j then
a.menuOpen=nil;a.menuFocused=false else a.menuOpen=j;a.menuSel=1;a.menuFocused=true;a.menuIdx=j end;return 3 end;local i,k=L(a,f)if k then M(a)return 3 end
if not i then if a.menuOpen then a.menuOpen=nil
a.menuFocused=false;return 3 end;return 0 end
if c.button==1 then local l=a.tabs[i]
if l and l.type~="shell"then
if
l.type=="edit"and l.modified then a.activeTab=i
a.lastOut={"Unsaved changes — close with F4",(a.T or{}).warning}else b.closeTab(i)end end else a.activeTab=i end;return 3 end
if g=="shell"then if e==a.CMD_ROW then local j=b.cmdColAt and b.cmdColAt(f)if j then
a.cmdCursor=j;a.cmdSel=nil;a._drag={kind="cmd"}return 1 end
return 0 end
local i=B()
if i and i.enabled(a)then if c.button~=1 and i.hitToggle(a,f,e)then
i.toggle(a,d)return 3 end;if i.isTiles(a,d)then
return i.handleClick(a,d,c,b)end end
if e>=a.LIST_TOP and e<a.LIST_TOP+a.LIST_H then local j=
a.browser.scroll+ (e-a.LIST_TOP)+1
local k=a.browser.files[j]if not k then return 0 end;local l=a.browser.sel;a.browser.sel=j;if c.button==1 then
b.openContextMenu()return 3 end
if l==j then
if k.name==".."then b.navigateUp()elseif k.dir then
b.navigateInto(k.name)elseif b.viewFile then b.viewFile()else b.openContextMenu()end;return 3 end
if b.drawFileListRow then b.drawFileListRow(l)b.drawFileListRow(j)return 0 end;return 2 end;return 0 end;if d then local i=C()
if i then i.ensureBuiltins()local j=i.get(g)if j and j.onMouse then return
j.onMouse(a,d,c,b)or 0 end end end
if
g=="edit"and d then local i=a.H-2
if e>=2 and e<2+i then local j=d.lines or{""}
local k=a.tier>=2 and(math.max(#
tostring(#j),2)+1)or 0
d.curRow=math.max(1,math.min(#j,(d.viewTop or 1)+ (e-2)))d.curCol=D(d,j[d.curRow],f,k)d.selAnchor=nil
a._drag={kind="edit",row=d.curRow,col=d.curCol}return 1 end;return 0 end
if(g=="view"or g==I)and d then local i=a.H-2
if e>=2 and e<2+i then local j=
(d.offset or 0)+ (e-1)local k=d.content or{}if j>=1 and j<=#k then
d.selAnchor,d.selCur=j,j;a._drag={kind="view"}return 1 end end;return 0 end;return 0 end
local function O(a,b,c)local f=a._drag;if not f then return 0 end;local e=a.tabs[a.activeTab]
local h,g=c.x,c.y
if f.kind=="cmd"then local d=b.cmdColAt and b.cmdColAt(h)
if not d then return 0 end;if d==a.cmdCursor then return 0 end
if not a.cmdSel then a.cmdSel=a.cmdCursor end;a.cmdCursor=d;if a.cmdSel==a.cmdCursor then a.cmdSel=nil end;return 1 elseif
f.kind=="edit"and e and e.type=="edit"then
local d=e.lines or{""}local j=a.H-2;local k=a.tier>=2 and
(math.max(#tostring(#d),2)+1)or 0
local i=math.max(1,math.min(
#d,(e.viewTop or 1)+ (g-2)))local l=D(e,d[i],h,k)if g<2 or g>=2+j then return 0 end;if not e.selAnchor then
e.selAnchor={row=
f.row or e.curRow,col=f.col or e.curCol}end;e.curRow,e.curCol=i,l;return 1 elseif

f.kind=="view"and e and(e.type=="view"or e.type==I)then local j=e.content or{}local i=a.H-2
local d=(e.offset or 0)+ (g-1)
if g<2 then e.offset=math.max(0,(e.offset or 0)-1)d=(
e.offset or 0)+1 elseif g>=2+i then e.offset=math.min(math.max(0,#j-i),
(e.offset or 0)+1)d=
(e.offset or 0)+i end;d=math.max(1,math.min(#j,d))e.selCur=d;return 1 end;return 0 end
local function P(a,b,c)local f=c.dir or 0;if f==0 then return 0 end;local d=a.tabs[a.activeTab]local e=
d and d.type or"shell"
if e=="shell"then
if a.menuOpen or a.ctxOpen then return 0 end;local h=B()
if h and h.isTiles(a,d)then return h.handleScroll(a,d,c)end;local i=f>0 and-1 or 1
local g=math.max(1,math.min(#a.browser.files,a.browser.sel+i))if g==a.browser.sel then return 0 end
local j,k=a.browser.sel,a.browser.scroll;a.browser.sel=g
if g<=a.browser.scroll then a.browser.scroll=g-1 end;if g>a.browser.scroll+a.LIST_H then
a.browser.scroll=g-a.LIST_H end
if
a.browser.scroll==k and b.drawFileListRow then b.drawFileListRow(j)b.drawFileListRow(g)return 0 end;return 2 elseif(e=="view"or e==I)and d then local h=d.content or{}
local i=a.H-2;local j=f>0 and-3 or 3;local k=math.max(0,#h-i)
local g=math.max(0,math.min(k,(d.offset or
0)+j))if g== (d.offset or 0)then return 0 end;d.offset=g;return 1 elseif
e=="edit"and d then local g=d.lines or{""}local i=a.H-2;local k=f>0 and-3 or 3
local h=A()
local j=h and h.cellOf(g[d.curRow]or"",d.curCol)or d.curCol
d.curRow=math.max(1,math.min(#g,d.curRow+k))
d.curCol=h and h.colOf(g[d.curRow]or"",j)or
math.max(1,math.min(# (
g[d.curRow]or"")+1,j))if d.curRow<d.viewTop then d.viewTop=d.curRow end
if d.curRow>
d.viewTop+i-1 then d.viewTop=d.curRow-i+1 end;return 1 elseif d then local g=C()
if g then g.ensureBuiltins()local h=g.get(e)if h and h.onScroll then return
h.onScroll(a,d,c)or 0 end end end;return 0 end
function v.handle(a,b,c,d,e,f,g,h)local j=v.available(a)if not j then return nil end
local i=j.parse(c,d,e,f,g,h)if not i then return nil end
if i.type=="click"then return N(a,b,i)elseif i.type=="scroll"then
return P(a,b,i)elseif i.type=="drag"then return O(a,b,i)elseif i.type=="drop"then a._drag=nil;return 0 end;return 0 end;return v