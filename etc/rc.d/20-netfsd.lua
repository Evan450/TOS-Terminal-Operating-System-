local function start()

if not (net and net.setServiceArm) then
error("netfsd: no kernel.net arm API in this environment", 0)
end
net.setServiceArm("netfsd", true)
end

local function stop()
if net and net.setServiceArm then net.setServiceArm("netfsd", false) end
end

return {
start   = start,
stop    = stop,
deps    = {},
restart = true,
caps    = { net = true },
needs   = "net",

user    = "root",
}
