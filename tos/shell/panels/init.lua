local d=require("computer")local f=require("component")local e={}
function e.run(a)
local p=require("shell.panels.state")local b=p.new(a)local c=require("shell.panels.helpers")
local m=require("shell.panels.widgets")local j=require("shell.panels.dialogs")
local g=require("shell.panels.draw")local k=require("shell.panels.editor")
local q=require("shell.panels.executor")local r=require("shell.panels.commands")
local s=require("shell.panels.events")
local l=require("shell.progenv").builder(b)b.menuDefs=g.buildMenuDefs(b)
pcall(function()local u=nil
local x,v=pcall(require,"kernel.profile")
if x and v and v.load then local A=
(b.U and b.st and b.U.getSession and b.U.getSession(b.st))or nil
local B,z=pcall(v.load,A)if B and type(z)=="table"then u=z.landing end end;if not u then
u=(b.who=="root")and"shell"or"desktop"end
local w=(u=="desktop"or u=="tiles")if not b.uiSplit then
if w and d.freeMemory()>=300*1024 then
local z=require("shell.panels.home")z.setView(b,"tiles")end;return end;if not w and
d.freeMemory()<300*1024 then return end
local y=require("shell.panels.desktop")y.open(b,{background=not w})end)local h=m.makeWidgetDefs(b)
pcall(m.loadCustomWidgets,b,h)
local n=r.build(b,{rp=function(u)return c.resolvePath(b,u)end,openViewTab=function(u,v)
return k.openViewTab(b,u,v)end,openLiveTab=function(u,v,w)return k.openLiveTab(b,u,v,w)end,openEditTab=function(u)return
k.openEditTab(b,u)end,refreshBrowser=function()return c.refreshBrowser(b)end,canRead=function(u,v)return
c.canRead(b,u,v)end,canWrite=function(u,v)return c.canWrite(b,u,v)end,canAccess=function(u,v,w)return
c.canAccess(b,u,v,w)end,rootOnly=function(u)return c.rootOnly(b,u)end,adminOnly=function(u)return
c.adminOnly(b,u)end,makeProgramEnv=l,promptInput=function(u,v,w)return j.promptInput(b,u,v,w)end,dialog=function(u)u=
u or{}
u.redraw=u.redraw or function()g.all(b,h)end;return j.dialog(b,u)end,alert=function(v,u)
u=u or{}u.redraw=u.redraw or function()g.all(b,h)end;return
j.alert(b,v,u)end,confirm=function(v,u)u=u or{}if
u.redraw==nil then u.redraw=function()g.all(b,h)end end;return
j.confirm(b,v,u)end,confirmTyped=function(v,w,u)u=u or{}u.redraw=
u.redraw or function()g.all(b,h)end;return
j.confirmTyped(b,v,w,u)end,drawAll=function()
return g.all(b,h)end,drawOutRow=function(u,v)return g.outRow(b,u,v)end,loadFiles=function(u)
return c.loadFiles(b,u)end,createTab=function(u,v,w)return
require("shell.panels.tabs").create(b,u,v,w)end,tabs=b.tabs,pullSignal=function()if
coroutine.isyieldable and coroutine.isyieldable()then
return coroutine.yield()end;return d.pullSignal(0.05)end})
local t=q.build(b,{rp=function(u)return c.resolvePath(b,u)end,makeProgramEnv=l,C=n})local i=_G._TOS and _G._TOS.kernel;if i and i.setMonitorHost then
pcall(i.setMonitorHost,true)end
local o=s.run(b,{C=n,exec=t,makeProgramEnv=l,widgetDefs=h})if b.sudoDrop then pcall(b.sudoDrop)end;if o~="cli"then
local v,u=pcall(require,"kernel.clipboard")
if v and u and u.clear then pcall(u.clear,b.displayIdx)end end;if
i and i.setMonitorHost then pcall(i.setMonitorHost,false)end
return o end;return e