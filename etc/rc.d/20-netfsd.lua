local running = false
local listenerID = nil

local function backend()
  local ok, mod = pcall(require, "kernel.netfs")
  if ok then return mod end
  return nil
end

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  local netfs = backend()
  if not netfs then return end

  local F = _G._TOS and _G._TOS.fs
  local ok, err = netfs.loadExports(F)
  if not ok then
    if _G._TOS and _G._TOS.log then
      _G._TOS.log("netfsd", "refusing to start: " .. tostring(err))
    end

    netfs.setExports({})
    netfs.setEnabled(false)
    return
  end

  netfs.setEnabled(true)
  running = true

  local protocol = net.getProtocol()
  listenerID = net.on(protocol.TYPE.NETFS_REQ, function(packet, remoteAddr)
    if _G._TOS and _G._TOS.log then
      local p = packet.payload or {}
      _G._TOS.log("netfsd", "request from " .. tostring(remoteAddr):sub(1, 8) ..
        ": " .. tostring(p.op) .. " " .. tostring(p.share))
    end
  end)
end

local function stop()
  running = false
  local netfs = backend()
  if netfs then
    netfs.setEnabled(false)
    netfs.setExports({})
  end
  if listenerID then
    local net = _G._TOS and _G._TOS.net
    if net then
      local protocol = net.getProtocol()
      net.off(protocol.TYPE.NETFS_REQ, listenerID)
    end
    listenerID = nil
  end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { ["fs.read"] = true, ["fs.write"] = true, net = true },

  user    = "root",
}
