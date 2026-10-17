local h="fileshare"local g=false;local f=nil
local function i()local a=_G._TOS and _G._TOS.net;if
not a then return end
if a.setServiceArm then a.setServiceArm(h,true)else
local d,c=pcall(require,"kernel.net.transfer")if not d then return end;if c.setEnabled then c.setEnabled(true)end end;g=true;local b=a.getProtocol()
f=a.on(b.TYPE.FILE_REQ,function(c,d)if _G._TOS and _G._TOS.log then
local e=(
c.payload and c.payload.path)or"?"
_G._TOS.log(h,"File request from "..d:sub(1,8)..": "..e)end end)end
local function j()g=false;local a=_G._TOS and _G._TOS.net
if a and a.setServiceArm then
a.setServiceArm(h,false)else local c,b=pcall(require,"kernel.net.transfer")if c and b.setEnabled then
b.setEnabled(false)end end
if f then local b=_G._TOS and _G._TOS.net;if b then local c=b.getProtocol()
b.off(c.TYPE.FILE_REQ,f)end;f=nil end end;return
{start=i,stop=j,deps={},restart=true,caps={["fs.read"]=true,net=true},needs="net",user="_kernel_"}