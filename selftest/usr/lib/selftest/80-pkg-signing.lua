local c,d="pkg signing","string"
return
function(a)
local l,b=pcall(require,"kernel.pkgsign")if not l or type(b)~="table"then
return a.skip(c,"kernel.pkgsign unavailable")end
local m,h=pcall(require,"kernel.pkg")local e=_G._TOS and _G._TOS.fs;if not e then
return a.skip(c,"no filesystem")end;local n,i=pcall(require,"kernel.ed25519")if
not n or not i or not i.sign or not i.publickey then return
a.skip(c,"kernel.ed25519 unavailable")end
local o,p=pcall(require,"kernel.serialize")
if not o then return a.skip(c,"kernel.serialize unavailable")end;local q,r=pcall(require,"kernel.log")
b.init({fs=e,serialize=p,log=q and r or nil})local k=b.requiresSignature()local j="tos-selftest-probe"
local g="/tmp/pkgsign-selftest-"..tostring(math.floor(
computer.uptime()*100))local f=g.."/package.lua"
local s,t=pcall(function()e.makeDirectory(g)
e.writeFile(f,"return { name = 'selftest-probe', version = '1.0.0' }\n")local v=string.rep("\7",32)local w=i.publickey(v)
a.ok("ed25519 derives a public key on this machine",
type(w)==d and#w==32)local x,z=b.signManifest(f,v,{signer="selftest"})
a.ok(
"signManifest succeeds ("..tostring(z)..")",type(x)==d)
a.ok("a .sig file lands beside the manifest",e.exists(b.sigPathFor(f)))local A=b.verifyManifest(f)
a.eq("a real signature from an untrusted key verifies as unknown","unknown",A.state)local B,C=b.addKey(j,x)
a.ok("trust add succeeds ("..tostring(C)..")",
B and true or false)b.reloadTrust()local y=b.verifyManifest(f)
a.eq("once trusted, the same bytes verify as trusted","trusted",y.state)a.eq("...under the label we just added",j,y.label)
local D=b.removeKey(j)
a.ok("trust remove succeeds",D and true or false)b.reloadTrust()local E=b.verifyManifest(f)
a.eq("removing the key drops it back to unknown","unknown",E.state)local F=e.readFile(f)
e.writeFile(f,(F:gsub("selftest%-probe","tampered!!!!!")))local u=b.verifyManifest(f)
a.eq("a hand-edited manifest is INVALID, not unsigned and not silently accepted","invalid",u.state)
a.ok("...and the reason says so",type(u.reason)==d and#u.reason>0)
if m and h and h._signGate then local G=g.."/unsigned.lua"
e.writeFile(G,"return { name = 'unsigned-probe', version = '1.0.0' }\n")b.setRequireSignature(true)local I,H=h._signGate(G,{})
a.eq("require=on: an unsigned manifest is refused","unsigned",I.state)
a.ok("...and the refusal names the require-signature setting",type(H)==d and
H:find("require signatures",1,true)~=nil)local J,K=h._signGate(G,{allowUnsigned=true})
a.eq("--allow-unsigned still reads as unsigned...","unsigned",J.state)a.eq("...but is NOT refused",nil,K)
b.setRequireSignature(false)local M,L=h._signGate(G,{})
a.eq("require=off: the same unsigned manifest passes through",nil,L)else
a.skip("require-signature gate","kernel.pkg._signGate unavailable")end end)
pcall(function()b.removeKey(j)b.setRequireSignature(k)
b.reloadTrust()end)
pcall(function()
for v,u in
ipairs({f,b.sigPathFor(f),g.."/unsigned.lua"})do if u and e.exists(u)then e.remove(u)end end;if e.exists(g)then e.remove(g)end end)
a.eq("require-signature setting restored to what we found",k,b.requiresSignature())if not s then
a.ok("pkg signing check body: "..tostring(t),false)end end