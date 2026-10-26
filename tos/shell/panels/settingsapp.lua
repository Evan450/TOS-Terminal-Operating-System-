local v,A,y,E,B,F="button","choice","header","kernel.profile","kernel.theme","string"
local u=require("shell.panels.ui")local z=require("shell.panels.tabs")local t={}
function t.buildPages(a)a=a or{}local b={}
local g={{kind=y,label="Appearance"},{kind=A,id="theme",label="Theme preset",values=
a.themeNames or{},value=a.themeCurrent},{kind="info",text="Left/Right previews the theme live."},{kind=v,id="theme_save",label="Save as my theme"},{kind=v,id="theme_reset",label="Forget my saved theme"}}b[#b+1]={id="appearance",label="Appearance",rows=g}
local e={{kind=y,label="Status Bar"},{kind="info",text="Widgets on the bottom bar. Changes save immediately."}}for k,j in ipairs(a.widgetsAvailable or{})do
e[#e+1]={kind="toggle",id="widget:"..j,label=j,value=
(a.widgetsEnabled or{})[j]or false}end
b[#b+1]={id="statusbar",label="Status Bar",rows=e}local h={desktop="tiles",shell="files"}
local i=h[a.landing]or a.landing or"tiles"
local d={{kind=y,label="Home"},{kind=A,id="landing",label="After login, show",values={"tiles","files"},value=i}}
if a.canProfile==false then
d[#d+1]={kind="info",text="No home directory — this session can't save a profile."}else
d[#d+1]={kind="info",text="Saved to your profile immediately."}end;b[#b+1]={id="desktop",label="Home",rows=d}
local f={{kind=y,label="Language"},{kind=A,id="uilang",label="UI language",values=
a.langCodes or{"en"},value=a.language or"en"},{kind="info",text="Applies now; saved to your profile. Catalogs live in /usr/lang."}}if a.langName and a.langName~=""then
table.insert(f,3,{kind="info",text="Current: "..a.langName})end
b[#b+1]={id="language",label="Language",rows=f}local c={{kind=y,label="System"}}
if
(a.userTier or 0)>=2 then
c[#c+1]={kind=v,id="run:bootsettings",label="Boot Settings"}c[#c+1]={kind=v,id="run:users",label="User Accounts"}end
c[#c+1]={kind=v,id="run:doctor",label="Health Check (doctor)"}c[#c+1]={kind=v,id="run:about",label="About TOS"}
b[#b+1]={id="system",label="System",rows=c}return b end
local function w(a)
if a.U and a.st and a.U.getSession then
local c,b=pcall(a.U.getSession,a.st)if c and b then return b end end;if a.U and a.U.currentSession then local b,c=pcall(a.U.currentSession)
if b then return c end end;return nil end;function t.defaultLanding(a)
return(a=="root")and"shell"or"desktop"end
local function G(a)
local b={userTier=a.userTier or 0}local j,g=pcall(require,B)
if j and g then local p,q=pcall(g.list)
b.themeNames=p and q or{}local r,o=pcall(g.current)b.themeCurrent=
(r and type(o)=="table"and o.preset)or nil end
local k={"memory","disk","clock","user","uptime","battery"}local h,c={},{}for p,o in ipairs(k)do h[o]=true;c[#c+1]=o end
local l,e=pcall(require,"shell.panels.widgets")
if l and e then local r,o=pcall(e.makeWidgetDefs,a)if r and type(o)=="table"then
pcall(e.loadCustomWidgets,a,o)
for M in pairs(o)do if not h[M]then h[M]=true;c[#c+1]=M end end end;local p={}
local s,q=pcall(e.getWidgetList,a)
if s and type(q)=="table"then for N,M in ipairs(q)do p[M]=true end end;b.widgetsEnabled=p end;b.widgetsAvailable=c;local m,f=pcall(require,"kernel.i18n")
if m and f then
local o={}local p,c=pcall(f.available)if p and type(c)=="table"then for O,N in ipairs(c)do
o[#o+1]=N.code end end
if#o==0 then o={"en"}end;b.langCodes=o;local q,r=pcall(f.language)b.language=q and r or"en"
local s,M=pcall(f.languageName)b.langName=s and M or nil end;local d=w(a)
b.canProfile=not not
(d and d.home and d.home~=""and d.home~="/")local n,i=pcall(require,E)if n and i and i.load then local p,o=pcall(i.load,d)
if p and
type(o)=="table"and o.landing then b.landing=o.landing end end;b.landing=b.landing or
t.defaultLanding(a.who)return b end
function t.refresh(b,a)a.pages=t.buildPages(G(b))
a.page=math.max(1,math.min(a.page or 1,#a.pages))local c=a.pages[a.page].rows
a.sel=u.firstSelectable(c)or 1 end
function t.open(a)local c=z.find(a,"settings")local b;if c then b=a.tabs[c]a.activeTab=c else
b=z.create(a,"settings","Settings",{page=1,sel=1})end;t.refresh(a,b)return b end;local function H(a)
for b,c in ipairs(a.tabs)do if c.type=="shell"then return b end end;return 1 end
local function I(a,b,c)local e=w(a)
local g,d=pcall(require,E)if not(g and d and d.load and d.save)then
b.msg={"Profile module unavailable",a.T.error}return end;local f=d.load(e)
f.landing=c;local h,i=d.save(f,e)
b.msg=
h and{"Landing saved: "..c,a.T.highlight}or{"Save failed: "..tostring(i),a.T.error}end
local function J(a,b,c)local g,d=pcall(require,"kernel.i18n")
if not
(g and d and d.setLanguage)then b.msg={"i18n unavailable",a.T.error}return end;local h,i=d.setLanguage(c)if not h then
b.msg={"Cannot set '"..
tostring(c).."': "..tostring(i),a.T.error}return end;local f=w(a)
local j,e=pcall(require,E)
if j and e and e.load and e.save then local k=e.load(f)
k.lang=
(d.language()~="en")and d.language()or nil;local l,m=e.save(k,f)
b.msg=l and
{"Language: "..d.language().." (saved)",a.T.highlight}or
{"Language set (profile save failed: "..tostring(m)..")",a.T.warning}else
b.msg={"Language: "..d.language().." (this session)",a.T.highlight}end end
local function K(a,b)local d=b.pages[b.page]local c={}for f,e in ipairs(d.rows)do local g=type(e.id)==F and
e.id:match("^widget:(.+)$")
if g and e.value then c[#c+1]=g end end
if
a.SC and a.SC.set then a.SC.set("statusbar_widgets",c)
if a.SC.save then a.SC.save()end;b.msg={"Status bar updated",a.T.highlight}else
b.msg={"Config unavailable",a.T.error}end end
local function L(a,b,c)local g,d=pcall(require,B)if not(g and d and d.apply)then
b.msg={"Theme module unavailable",a.T.error}return end;local h,e,f=pcall(d.apply,c)if not
h then e,f=false,e end
if e then a.T=a.D.getTheme()
b.msg={"Previewing: "..c..
"  (use Save to keep it)",a.T.highlight}else
b.msg={"Theme failed: "..tostring(f),a.T.error}end end
local function x(b,c,a,e,d)if not a then return 0 end;if a.kind=="toggle"then a.value=not a.value
if
type(a.id)==F and a.id:match("^widget:")then K(b,c)end;return 3 end
if a.kind==A then
local f=u.cycle(a.values,a.value,e)if f==a.value then return 0 end;a.value=f
if a.id=="theme"then L(b,c,f)elseif
a.id=="landing"then I(b,c,f)elseif a.id=="uilang"then J(b,c,f)end;return 3 end
if a.kind==v then
local f=type(a.id)==F and a.id:match("^run:(.+)$")
if f then b.activeTab=H(b)if d and d.exec then d.exec(f)end;return 3 end
if a.id=="theme_save"then local h,g=pcall(require,B)
if h and g and g.saveForUser then
local k,i,j=pcall(g.saveForUser,w(b))if not k then i,j=false,i end
c.msg=i and
{"Theme saved for ".. (b.who or"?"),b.T.highlight}or
{"Save failed: "..tostring(j),b.T.error}end;return 3 end
if a.id=="theme_reset"then local h,g=pcall(require,B)
if h and g and g.clearForUser then
local k,i,j=pcall(g.clearForUser,w(b))if not k then i,j=false,i end
c.msg=
i and{"Saved theme forgotten",b.T.highlight}or{"Reset failed: "..tostring(j),b.T.error}end;return 3 end end;return 0 end
local function C(a)local c,b={},2;for d,e in ipairs(a)do local f=" "..e.label.." "
c[d]={s=b,e=b+#f-1,cell=f}b=b+#f+1 end;return c end
function t.draw(b,a)local d,c,e,f=b.D,b.T,b.W,b.H;if not a.pages then t.refresh(b,a)end
local h=a.pages;local j=h[a.page]d.fill(1,2,e,f-1," ",c.fg,c.bg)
u.drawRail(d,c,2,e,{{label="§ Settings"}},{labelFg=
c.title or c.fg})
for l,k in ipairs(C(h))do if k.s<=e then
if l==a.page then
d.set(k.s,3,k.cell,c.sel_fg or c.bg,c.sel_bg or c.highlight)else d.set(k.s,3,k.cell,c.dim or c.fg,c.bg)end end end;local i=5;local g=f-i-1;a.scroll=a.scroll or 0;if a.sel-a.scroll>g then
a.scroll=a.sel-g end;if a.sel-a.scroll<1 then
a.scroll=math.max(0,a.sel-1)end
for k=1,g do local l=a.scroll+k;local m=j.rows[l]
if not m then break end;u.drawSettingRow(d,c,i+k-1,2,e-2,m,l==a.sel)end;if a.msg then d.fill(1,f-1,e,1," ",c.fg,c.bg)
d.set(2,f-1,tostring(a.msg[1]):sub(1,
e-2),a.msg[2]or c.dim,c.bg)end
u.drawRampBar(d,c,f,e,
"Arrows Move · Left/Right Change · Enter Apply · Tab Page · "..
require("shell.keys").quitHint(b.who).." Close",nil,c.statusbar_fg or c.bar_fg,
c.statusbar_bg or c.bar_bg)end
local function D(c,a,b)a.page=a.page+b;if a.page>#a.pages then a.page=1 end;if a.page<1 then a.page=
#a.pages end;a.scroll=0;a.msg=nil;a.sel=
u.firstSelectable(a.pages[a.page].rows)or 1 end
function t.handleKey(c,a,e,b,d)if not a.pages then t.refresh(c,a)end
local f=a.pages[a.page].rows;local g=f[a.sel]
if
require("shell.keys").isQuit(e,b,true,c.who)then z.close(c)return 3 elseif b==15 or b==209 then D(c,a,1)return 3 elseif b==201 then D(c,a,-1)return 3 elseif
b==200 then a.sel=u.nextSelectable(f,a.sel,-1)return 3 elseif b==208 then
a.sel=u.nextSelectable(f,a.sel,1)return 3 elseif b==203 then return x(c,a,g,-1,d)elseif b==205 then return x(c,a,g,1,d)elseif b==28 then
return x(c,a,g,1,d)end;return 0 end
function t.handleClick(c,a,b,d)if not a.pages then t.refresh(c,a)end
if b.y==3 then
for j,k in
ipairs(C(a.pages))do if b.x>=k.s and b.x<=k.e then
if j~=a.page then a.page=j;a.scroll=0;a.msg=nil;a.sel=
u.firstSelectable(a.pages[j].rows)or 1 end;return 3 end end;return 0 end;local f=5;local g=(a.scroll or 0)+ (b.y-f+1)
local h=a.pages[a.page].rows;local e=h[g]
if b.y>=f and e and u.rowSelectable(e)then a.sel=g;if b.button==1 then
return 3 end;return x(c,a,e,1,d)end;return 0 end
function t.handleScroll(b,a,c)if not a.pages then t.refresh(b,a)end
local e=a.pages[a.page].rows;local f=(c.dir or 0)>0 and-1 or 1
local d=u.nextSelectable(e,a.sel,f)if d==a.sel then return 0 end;a.sel=d;return 3 end;return t