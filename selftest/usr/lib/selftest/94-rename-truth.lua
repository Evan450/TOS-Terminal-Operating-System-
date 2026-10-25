
return
function(a)local c=_G._TOS and _G._TOS.fs;if not c then return
a.skip("rename truth","no filesystem module")end
local d="/var/selftest-rename-"..tostring(math.floor(
computer.uptime()*100))if not c.makeDirectory(d)then return
a.skip("rename truth","could not make "..d)end;local e,f=d.."/a.txt",
d.."/b.txt"
local g,h=pcall(function()c.writeFile(e,"from a")
c.writeFile(f,"from b")local n,o=pcall(c.rename,e,f)
local i=(n and o)and true or false;local k,l=not c.exists(e),c.readFile(f)local j;if i then
j=k and l=="from a"else j=(not k)and l=="from b"end
a.ok(
"rename onto an existing file answered "..
tostring(i)..
(i and", and did overwrite"or", and left both files alone")..": the answer matches the disk",j)local b=d.."/atomic.txt"c.writeFile(b,"old")
local m,p=c.writeFileAtomic(b,"new")
a.ok("writeFileAtomic replaces an existing file on this disk".. (m and""or
(" ("..tostring(p)..")")),
m and c.readFile(b)=="new")
a.ok("...and leaves no .tos-tmp behind",not c.exists(b..".tos-tmp"))end)
for i,b in
ipairs({e,f,d.."/atomic.txt",d.."/atomic.txt.tos-tmp"})do if c.exists(b)then c.remove(b)end end;c.remove(d)
a.ok("cleaned up",not c.exists(d))if not g then error(h,0)end end