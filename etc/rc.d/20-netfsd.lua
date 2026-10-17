
local function c()if not(net and net.setServiceArm)then
error("netfsd: no kernel.net arm API in this environment",0)end
net.setServiceArm("netfsd",true)end;local function d()
if net and net.setServiceArm then net.setServiceArm("netfsd",false)end end;return
{start=c,stop=d,deps={},restart=true,caps={net=true},needs="net",user="root"}