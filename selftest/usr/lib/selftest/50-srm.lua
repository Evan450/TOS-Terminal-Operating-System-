
return
function(a)local h,b=pcall(require,"kernel.srm")
if
not h or type(b)~="table"then return a.skip("srm","kernel.srm unavailable")end;local c=_G._TOS and _G._TOS.fs;if not c then
return a.skip("srm","no filesystem")end;local e="/tmp/srm-selftest-"..
tostring(math.floor(computer.uptime()*100))local d=e..
"/subject.lua"local g="-- v1\nreturn 1\n"
local f={DIR=b.DIR,INDEX=b.INDEX,STORE=b.STORE,LAST=b.LAST}
local function i()b.DIR,b.INDEX,b.STORE,b.LAST=f.DIR,f.INDEX,f.STORE,f.LAST end
local j,k=pcall(function()c.makeDirectory(e)c.writeFile(d,g)b.DIR=e.."/srm"b.INDEX=
b.DIR.."/index.dat"b.STORE=b.DIR.."/store"
b.LAST=b.DIR.."/last.dat"local m,n=b.baseline(nil,{paths={d},content=true})
a.ok(
"baseline succeeds ("..tostring(n)..")",m and true or false)a.ok("index was written",c.exists(b.INDEX))if
b.storeUsage then local p=b.storeUsage(nil)
a.ok("store usage is a number",type(p)=="number"or
type(p)=="table")end
local l=b.scan(nil)
a.ok("scan returns a report",type(l)=="table")
a.eq("no drift before the edit",0,# (l.drift or{}))c.writeFile(d,"-- v2 TAMPERED\nreturn 2\n")
local o=b.scan(nil)
a.ok("scan detects the edit",# (o.drift or{})>0)
if b.restore then b.restore(nil,{paths={d}})
a.eq("restore returns the original content",g,c.readFile(d))local p=b.scan(nil)
a.eq("and the scan is clean again",0,# (p.drift or{}))else a.skip("srm.restore","not present in this build")end end)i()
pcall(function()
for m,l in ipairs({d})do if c.exists(l)then c.remove(l)end end;if c.exists(e)then c.remove(e)end end)
a.ok("srm paths restored to the real ones",b.INDEX==f.INDEX)if not j then
a.ok("srm check body: "..tostring(k),false)end end