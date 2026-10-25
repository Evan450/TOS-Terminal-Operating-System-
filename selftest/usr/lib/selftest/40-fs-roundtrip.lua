local b="/moved.txt"
return
function(a)local c=_G._TOS and _G._TOS.fs;if not c then return
a.skip("fs","no filesystem module")end
local d="/tmp/selftest-"..tostring(math.floor(
computer.uptime()*100))local e=d.."/probe.txt"local f="the quick brown fox\nsecond line\n"
a.ok("makeDirectory",
(c.makeDirectory(d))and true or false)
a.ok("directory exists after creation",c.exists(d))a.ok("isDirectory agrees",c.isDirectory(d))
a.ok("writeFile",
(c.writeFile(e,f))and true or false)a.ok("file exists",c.exists(e))
a.eq("read round-trips exactly",f,c.readFile(e))
a.eq("size matches the bytes written",#f,c.size(e))
a.ok("isDirectory is false for a file",not c.isDirectory(e))local g=false
for i,h in ipairs(c.list(d)or{})do if tostring(h):gsub("/$","")==
"probe.txt"then g=true end end;a.ok("list() finds the file we just wrote",g)
if
c.writeFileAtomic then local h=d.."/atomic.txt"
a.ok("writeFileAtomic",(c.writeFileAtomic(h,"x"))and
true or false)a.eq("atomic content","x",c.readFile(h))
a.ok("no .tos-tmp left behind",
not c.exists(h..".tos-tmp"))c.remove(h)else
a.skip("writeFileAtomic","not present in this build")end
a.ok("rename",(c.rename(e,d..b))and true or false)
a.ok("old path gone after rename",not c.exists(e))a.ok("new path present",c.exists(d..b))
c.remove(d..b)c.remove(d)
a.ok("cleaned up",not c.exists(d))end