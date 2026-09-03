-- ╔══════════════════════════════════════╗
-- ║  TOS File Share Service              ║
-- ║  Serve files to trusted peers        ║
-- ╚══════════════════════════════════════╝
-- Listens for FILE_REQ packets from TRUSTED peers and responds
-- with the requested file's contents (or FILE_DENY if the path
-- is outside the shared directory or the peer lacks trust).
--
-- Shared directory: /public/ ONLY (read-only to TRUSTED peers).
-- transfer.handleRequest denies anything that doesn't normalize under
-- /public/. (There is intentionally no /home/<user>/share/ exposure.)

local running = false
local listenerID = nil

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  -- #SEC L — arm the FILE_REQ server.
  -- #MEM — via net.setServiceArm instead of require()ing the transfer
  -- module: requiring it here forced it into RAM on every boot just to
  -- flip a flag. net records the arm state and applies it when the module
  -- loads (first FILE_REQ packet / first outbound scp). Fail-closed: an
  -- unloaded backend refuses requests exactly like a disabled one.
  if net.setServiceArm then
    net.setServiceArm("fileshare", true)
  else
    -- Older kernel without the arm API: keep the original direct path.
    local ok, transferMod = pcall(require, "kernel.net.transfer")
    if not ok then return end
    if transferMod.setEnabled then transferMod.setEnabled(true) end
  end

  running = true

  -- Register a listener that logs share activity
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
  -- #SEC L — stop serving files for real, not just drop the log listener.
  -- #MEM — through the arm API when available (also disables the backend
  -- immediately if it is loaded); direct module fallback otherwise.
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
