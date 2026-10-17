local j="/etc/widgets"local k=require("computer")
local l=require("shell.panels.helpers")local g={}local h=nil
function g.getSyntax(a)if h==nil then
if a.tier>=2 then
local b,c=pcall(require,"shell.syntax")h=b and c or false else h=false end end;return h end
function g.makeWidgetDefs(a)local b=a.F;local c=a.K
local d={memory=function()return
math.floor(k.freeMemory()/1024).."K"end,disk=function()local e=b.mounts and b.mounts()or
{}for m,f in ipairs(e)do
if f.mountPoint=="/"then local n=(f.total or 0)- (
f.used or 0)return l.fmtSz(n)end end;return"?"end,clock=function()
local f,e=pcall(os.date,"*t")
if f and e then return string.format("%02d:%02d",e.hour,e.min)end;return"--:--"end,user=function()
return a.who end,uptime=function()local e=c.uptime()local f=math.floor(e/3600)local m=math.floor((e%
3600)/60)
return string.format("%dh%dm",f,m)end,battery=function()local e=_G._TOS and
_G._TOS.power;if e and e.isActive()then
return e.level().."%"end;return nil end,view=function()
local f,e=pcall(require,"shell.panels.home")
if not(f and e and e.enabled(a))then return nil end;return e.isTiles(a)and"TILES"or"FILES"end}return d end
function g.getWidgetList(a)
local b=a.SC and a.SC.get("statusbar_widgets")if type(b)=="table"then return b end
local c=_G._TOS and _G._TOS.power
if c and c.isActive()then return{"battery","memory","disk","view"}end;return{"memory","disk","view"}end;local i=setmetatable({},{__mode="k"})
function g.loadCustomWidgets(a,b)if i[a]then return end
i[a]=true;local f=a.F;if not f.isDirectory(j)then return end;local c=a.U;local n=a.st
local function o(r)if not c or not
c.canAccessAs then return true end
local s=(n and c.getSession and
c.getSession(n))or
(c.currentSession and c.currentSession())local t=c.canAccessAs(s,r,"r")return t end;if not o(j)then return end;local p,d=pcall(f.list,j)
if not p or not d then return end;local e={}
if type(d)=="table"then e=d elseif type(d)=="function"then for r in d do e[#e+1]=r end end;local q=32;local m=0
for s,r in ipairs(e)do if m>=q then break end
if r:match("%.lua$")then
local t=r:gsub("%.lua$","")
if not b[t]then local u="/etc/widgets/"..r
if o(u)then local v=f.readFile(u)if
v and#v<=8192 then local w,s=load(v,"=widget:"..t,"t",{})
if w then local y,x=pcall(w)if y and type(x)==
"function"then b[t]=x;m=m+1 end end end end end end end end;return g