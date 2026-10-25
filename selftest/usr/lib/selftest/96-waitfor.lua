local b="function"
return
function(a)local i,d=pcall(require,"kernel.net")
if not i or
type(d)~="table"or type(d.waitFor)~=b then return
a.skip("net.waitFor","kernel.net unavailable")end;local j,c=pcall(require,"kernel.event")
if

not j or type(c)~="table"or type(c.on)~=b or type(c.off)~=b then return a.skip("net.waitFor","kernel.event unavailable")end;local e="selftest_waitfor_probe"local f=false
local k=c.on(e,function()f=true end,"selftest")computer.pushSignal(e)local l=computer.uptime()local h,g=pcall(d.waitFor,function()return
f end,2)local m=
computer.uptime()-l;c.off(e,k)
a.ok(string.format(
"net.waitFor in kernel context lets a listener see what it waits for".." (returned %s after %.1f s%s)",tostring(g),m,
h and""or(", raised: "..tostring(g))),
h and g==true and f)end