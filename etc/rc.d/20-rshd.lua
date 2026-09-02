local running = false

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  if net.setServiceArm then
    net.setServiceArm("rshd", true)
  else

    local ok, remoteMod = pcall(require, "kernel.net.remote")
    if not ok then return end
    if remoteMod.setEnabled then remoteMod.setEnabled(true) end
  end

  running = true
  if _G._TOS and _G._TOS.log then
    _G._TOS.log("rc", "rshd: Remote shell daemon active")
  end
end

local function stop()

  local net0 = _G._TOS and _G._TOS.net
  if net0 and net0.setServiceArm then
    net0.setServiceArm("rshd", false)
  else
    local ok, remoteMod = pcall(require, "kernel.net.remote")
    if ok and remoteMod.setEnabled then remoteMod.setEnabled(false) end
  end
  running = false
  if _G._TOS and _G._TOS.log then
    _G._TOS.log("rc", "rshd: Remote shell daemon stopped (exec requests now refused)")
  end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { net = true },
  user    = "_kernel_",
}
