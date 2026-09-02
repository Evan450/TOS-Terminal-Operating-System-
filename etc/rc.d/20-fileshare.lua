local running = false
local listenerID = nil

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  if net.setServiceArm then
    net.setServiceArm("fileshare", true)
  else

    local ok, transferMod = pcall(require, "kernel.net.transfer")
    if not ok then return end
    if transferMod.setEnabled then transferMod.setEnabled(true) end
  end

  running = true

  local protocol = net.getProtocol()
  listenerID = net.on(protocol.TYPE.FILE_REQ, function(packet, remoteAddr)
    if _G._TOS and _G._TOS.log then
      local path = (packet.payload and packet.payload.path) or "?"
      _G._TOS.log("fileshare", "File request from " .. remoteAddr:sub(1, 8) .. ": " .. path)
    end
  end)
end

local function stop()
  running = false

  local net0 = _G._TOS and _G._TOS.net
  if net0 and net0.setServiceArm then
    net0.setServiceArm("fileshare", false)
  else
    local ok, transferMod = pcall(require, "kernel.net.transfer")
    if ok and transferMod.setEnabled then transferMod.setEnabled(false) end
  end
  if listenerID then
    local net = _G._TOS and _G._TOS.net
    if net then
      local protocol = net.getProtocol()
      net.off(protocol.TYPE.FILE_REQ, listenerID)
    end
    listenerID = nil
  end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { ["fs.read"] = true, net = true },
  user    = "_kernel_",
}
