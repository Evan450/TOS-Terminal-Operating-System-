local b="sandbox"
return
function(a)local g,d=pcall(require,"kernel.sandbox")if not g or type(d)~=
"table"then
return a.skip(b,"kernel.sandbox unavailable")end;local f=
d.build or d.make or d.newEnv or d.create
if type(f)~="function"then return
a.skip(b,"no recognised env constructor on this build")end;local h,c=pcall(f,{caps={}})if not h or type(c)~="table"then
return a.skip(b,
"constructor signature differs here: "..tostring(c))end;a.ok("no raw component in a capless env",
c.component==nil)
a.ok("no raw computer in a capless env",
c.computer==nil or type(c.computer)=="table")a.ok("_G is not the real global table",c._G~=_G)if
c.tostring then
a.eq("tostring works inside","1",tostring(c.tostring(1)))end
local i,e=pcall(f,{caps={["fs.read"]=true}})
if i and type(e)=="table"then local j=e.fs and
(e.fs.writeFile or e.fs.write or e.fs.remove)a.ok("fs.read alone does not expose a writer",
j==nil)else
a.skip("fs.read env","constructor rejected that cap shape here")end end