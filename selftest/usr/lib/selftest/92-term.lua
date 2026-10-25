local c,d="key_down","term.read in a coroutine"
return
function(a)
local C,b=pcall(require,"compat.term")
if not C or type(b)~="table"then return
a.skip("compat.term","does not load here: "..tostring(b))end
local i=coroutine.isyieldable and coroutine.isyieldable()
a.ok("coroutine.isyieldable() in kernel context is a boolean",type(i)=="boolean")
if a.note then
a.note("isyieldable() in kernel context: "..
tostring(i).." -- term.read at boot "..
(i and
"yields to the host; its bounded raw-pull branch is unreachable here"or"takes the bounded raw pull"))end;local n=b.screen()
a.ok("term.screen() is a real screen address",n~=nil and
component.type(n)=="screen")local D,o=pcall(b.gpu)
local p,q=pcall(function()return o.getResolution()end)
a.ok("term.gpu() answers with a usable proxy"..
(p and""or(" ("..tostring(q)..")")),
D and type(o)=="table"and p and type(q)=="number")local r=component.list("gpu")()
local j=r and component.proxy(r)
local s=j and type(j.set)=="table"and getmetatable(j.set)
a.ok("a raw GPU method here is a callable table, not a function",type(s)=="table"and s.__call~=nil)local E,t=pcall(b._gpuForCaps,{gpu=true})
a.ok("a display-cap term.gpu() wraps setBackground (marks the glass dirty)",
E and type(t)=="table"and type(t.setBackground)=="function")local u,v=b.getCursor()b.setCursor(7,3)local F,G=b.getCursor()
a.ok("setCursor/getCursor round-trip with no caller seat",
F==7 and G==3)b.setCursor(u,v)
if not(a.cfg and a.cfg.screen)then return
a.skip(d,"it draws: add screen=true to selftest.on")end
if type(coroutine.isyieldable)~="function"then return
a.skip(d,"this Lua has no coroutine.isyieldable, so term.read would wait for a real key")end;local I,h=pcall(require,"kernel.display")
local e=
I and type(h)=="table"and h.getGpu and h.getGpu()if not e or not e.get then
return a.skip(d,"no GPU, or gpu.get unavailable")end;local w,J=e.getResolution()local f=math.max(2,
J-6)local x={}for H=1,w do local O,P,Q,R=pcall(e.get,H,f)x[H]=
O and{ch=P,fg=Q,bg=R}or nil end
b.setCursor(1,f)
local g=coroutine.create(function()return b.read(nil,false)end)local y,K=coroutine.resume(g)
a.ok("term.read hands control back to its resumer while it waits (H-04)"..
(
y and""or(" (raised: "..tostring(K)..")")),y and
coroutine.status(g)=="suspended")
local k=component.list("keyboard")()or"selftest"local L={{c,k,104,35},{c,k,105,23},{c,k,13,28}}local z,l
for O,H in
ipairs(L)do if coroutine.status(g)~="suspended"then break end
local Q,P=coroutine.resume(g,table.unpack(H))if not Q then l=P;break end
if coroutine.status(g)=="dead"then z=P end end
a.eq("term.read returns the line it was fed".. (l and
(" (raised: "..tostring(l)..")")or""),"hi",z)local N,A=pcall(e.get,1,f)local N,B=pcall(e.get,2,f)
a.ok(
"...and the glass shows what was typed (got "..tostring(A)..tostring(B)..")",
A=="h"and B=="i")b.setCursor(u,v)for H=1,w do local O=x[H]if O then
pcall(h.set,H,f,O.ch or" ",O.fg,O.bg)end end
local M,m=pcall(require,"kernel.screen")
if M and m and m.invalidateAll then pcall(m.invalidateAll)end end