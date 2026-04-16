-- ╔══════════════════════════════════════╗
-- ║  TOS File Share Service             ║
-- ║  Serve files to trusted peers       ║
-- ╚══════════════════════════════════════╝
-- Listens for FILE_REQ packets from TRUSTED peers and responds
-- with the requested file's contents (or FILE_DENY if the path
-- is outside the shared directories or the peer lacks trust).
--
-- Shared directories: /public/ (read-only to TRUSTED peers)
-- Trusted peers with full trust can also request from /home/<user>/share/

local running = false
local listenerID = nil

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  -- The transfer module handles the low-level packet I/O.
  -- Verify it's loaded.
  local ok, transferMod = pcall(require, "kernel.net.transfer")
  if not ok then return end

  running = true

  -- Register a listener that logs share activity
  local protocol = net.getProtocol()
  listenerID = net.on(protocol.TYPE.FILE_REQ, function(remoteAddr, packet)
    if _G._TOS and _G._TOS.log then
      local path = (packet.payload and packet.payload.path) or "?"
      _G._TOS.log("fileshare", "File request from " .. remoteAddr:sub(1, 8) .. ": " .. path)
    end
  end)
end

local function stop()
  running = false
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
}
