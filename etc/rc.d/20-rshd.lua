local d=false
local function e()local a=_G._TOS and _G._TOS.net;if not a then return end
if
a.setServiceArm then a.setServiceArm("rshd",true)else
local c,b=pcall(require,"kernel.net.remote")if not c then return end;if b.setEnabled then b.setEnabled(true)end end;d=true;if _G._TOS and _G._TOS.log then
_G._TOS.log("rc","rshd: Remote shell daemon active")end end
local function f()local a=_G._TOS and _G._TOS.net
if a and a.setServiceArm then
a.setServiceArm("rshd",false)else local c,b=pcall(require,"kernel.net.remote")if c and b.setEnabled then
b.setEnabled(false)end end;d=false;if _G._TOS and _G._TOS.log then
_G._TOS.log("rc","rshd: Remote shell daemon stopped (exec requests now refused)")end end
return{start=e,stop=f,deps={},restart=true,caps={net=true},needs="net",user="_kernel_"}