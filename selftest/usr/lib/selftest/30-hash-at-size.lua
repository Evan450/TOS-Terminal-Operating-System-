
return
function(a)local d,c=pcall(require,"kernel.sha256")
if
not d or type(c)~="table"then return a.skip("sha256","kernel.sha256 unavailable")end
a.eq("FIPS vector still correct on this machine","ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",c.hex("abc"))local e={1024,16384,65536,131072,262144}local b=0
for g,f in ipairs(e)do if
computer.freeMemory()< (f*3)then
a.skip("hash "..f.." bytes","not enough free memory to try safely")break end
local h=pcall(function()
local i=string.rep("a",f)local j=c.hex(i)if#j~=64 then
error("digest was not 64 hex chars",0)end end)if h then b=f else
a.ok("hashing "..f.." bytes raised (largest ok: "..b..")",false)break end;if
type(collectgarbage)=="function"then pcall(collectgarbage)end end
a.ok("can hash at least 64K (backup.lua hashes file bodies) -- got "..b,b>=65536)end