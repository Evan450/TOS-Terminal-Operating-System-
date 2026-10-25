local b="function"
return
function(a)local h,c=pcall(require,"kernel.process")
if not h or type(c)~=
"table"or type(c.inProcess)~=b then return
a.skip("inprocess callers","kernel.process unavailable")end
a.note("kernel context: isyieldable="..

tostring(coroutine.isyieldable and coroutine.isyieldable()).." inProcess="..tostring(c.inProcess()))local i,e=pcall(require,"kernel.pipe")
if i and type(e)=="table"and
type(e.create)==b then local m=e.create()
local n=computer.uptime()local o,p=pcall(m.read,m)
a.ok(string.format("an empty pipe read in kernel context returns nil (%.2f s)",
computer.uptime()-n),o and p==nil and
computer.uptime()-n<1)else a.skip("pipe read","kernel.pipe unavailable")end;local j,d=pcall(require,"kernel.event")
if
j and type(d)=="table"and type(d.on)==b then local m="selftest_inprocess_probe"
local o=false;local q=d.on(m,function()o=true end,"selftest")
computer.pushSignal(m)local r=computer.uptime()local p,s=pcall(c.sleep,0.3)local n=
computer.uptime()-r;d.off(m,q)
a.ok(string.format("proc.sleep(0.3) in kernel context takes about 0.3 s (%.2f s%s)",n,
p and""or(", raised: "..tostring(s))),
p and n>=0.25 and n<2)
a.ok("...and the signal pushed during it reached its listener",o)else a.skip("proc.sleep","kernel.event unavailable")end;local g=computer.uptime()local k=pcall(c.yield)
a.ok(string.format("proc.yield in kernel context returns at once (%.2f s)",
computer.uptime()-g),k and
computer.uptime()-g<1)local l,f=pcall(require,"kernel.sandbox")
if
l and type(f)=="table"and type(f.build)==b then
local o,m=pcall(f.build,{caps={component=true}})
local n=o and type(m)=="table"and m.computer and m.computer.pullSignal
if type(n)==b then local q=computer.uptime()local r=pcall(n,0.2)local p=
computer.uptime()-q
a.ok(string.format("a sandbox pullSignal(0.2) in kernel context returns on time (%.2f s)",p),
r and p<2)else
a.skip("sandbox pullSignal","sandbox env has no computer.pullSignal")end else
a.skip("sandbox pullSignal","kernel.sandbox unavailable")end end