-- ╔══════════════════════════════════════╗
-- ║  TOS Network - File Transfer        ║
-- ║  FILE_REQ / FILE_RES / FILE_DENY    ║
-- ╚══════════════════════════════════════╝
-- Allows TRUSTED peers to request and receive files.
-- Files larger than 6KB are denied (OC modem limit is ~8KB;
-- with packet overhead, 6KB payload is the safe maximum).

local computer = require("computer")

local transfer = {}

-- Max payload size for a single file transfer packet.
-- OC modem max message is 8192 bytes; reserve 2KB for packet
-- framing, headers, and serialization overhead.
local MAX_FILE_SIZE = 6144  -- 6KB

-- Timeout for waiting on a response (seconds)
local TIMEOUT = 30

-- Module references (set during init)
local net      = nil
local fs       = nil
local trustMgr = nil
local crypto   = nil
local log      = nil
local event    = nil
local protocol = nil

-- ============================================================
-- Initialization
-- ============================================================

function transfer.init(modules)
  net      = modules.net
  fs       = modules.fs
  trustMgr = modules.trust
  crypto   = modules.crypto
  log      = modules.log
  event    = modules.event

  protocol = require("kernel.net.protocol")

  -- Register handler for incoming FILE_REQ packets
  if net then
    net.on(protocol.TYPE.FILE_REQ, function(packet, fromAddr)
      transfer.handleRequest(packet, fromAddr)
    end)
  end

  if log then
    log.info("transfer", "File transfer module initialized")
  end

  return true
end

-- ============================================================
-- Request a file from a remote peer
-- ============================================================

--- Request a file from a TRUSTED peer and save it locally.
-- @param address string: Remote peer's modem address
-- @param remotePath string: Path of the file on the remote machine
-- @param localPath string: Where to save the received file locally
-- @return boolean, string: true on success, or false + error message
function transfer.request(address, remotePath, localPath)
  if not net then return false, "Network not available" end
  if not protocol then return false, "Protocol not loaded" end

  -- Verify peer is TRUSTED
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return false, "Peer is not TRUSTED"
  end

  -- Build and send FILE_REQ
  local pkt = protocol.makePacket(protocol.TYPE.FILE_REQ, {
    path = remotePath,
  }, { to = address })

  local ok, sendErr = net.send(address, pkt)
  if not ok then
    return false, "Send failed: " .. tostring(sendErr)
  end

  if log then
    log.info("transfer", "Requested file: " .. remotePath ..
      " from " .. address:sub(1, 8) .. "...")
  end

  -- Wait for FILE_RES or FILE_DENY via net listeners
  local received = false
  local result   = false
  local errMsg   = "Timeout waiting for response"

  local resID = net.on(protocol.TYPE.FILE_RES, function(rpkt, from)
    if from == address then
      received = true
      local payload = rpkt.payload or {}
      if payload.data then
        local writeOk = fs.writeFile(localPath, payload.data)
        if writeOk then
          result = true
          if log then
            log.info("transfer", "Received file: " .. remotePath ..
              " (" .. tostring(payload.size or #payload.data) .. " bytes)")
          end
        else
          errMsg = "Failed to write local file: " .. localPath
        end
      else
        errMsg = "Response contained no data"
      end
    end
  end)

  local denyID = net.on(protocol.TYPE.FILE_DENY, function(rpkt, from)
    if from == address then
      received = true
      local payload = rpkt.payload or {}
      errMsg = payload.reason or "File request denied"
    end
  end)

  -- Poll until we get a response or timeout
  -- event.pull pumps the OC event loop, which triggers modem_message -> net dispatch
  local deadline = computer.uptime() + TIMEOUT
  while not received and computer.uptime() < deadline do
    event.pull(0.5)
  end

  -- Clean up temporary listeners
  net.off(protocol.TYPE.FILE_RES, resID)
  net.off(protocol.TYPE.FILE_DENY, denyID)

  if not received then
    return false, errMsg
  end

  return result, result and nil or errMsg
end

-- ============================================================
-- Handle incoming FILE_REQ from a remote peer
-- ============================================================

--- Process an incoming file request.
-- @param packet table: The deserialized FILE_REQ packet
-- @param fromAddr string: The sender's modem address
function transfer.handleRequest(packet, fromAddr)
  if not net or not protocol then return end

  -- Trust check: must be TRUSTED
  local level = trustMgr.getLevel(fromAddr)
  if level < trustMgr.LEVEL.TRUSTED then
    if log then
      log.warn("transfer", "FILE_REQ denied from non-trusted peer: " ..
        fromAddr:sub(1, 8) .. "...")
    end
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "Insufficient trust level",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  local payload = packet.payload or {}
  local path = payload.path

  if not path or path == "" then
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "No file path specified",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  -- Security: only allow files under /public/ (normalize resolves .. first)
  local normalized = fs.normalize(path)
  if normalized:sub(1, 8) ~= "/public/" and normalized ~= "/public" then
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "Access restricted to /public/",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  -- Check file existence
  if not fs.exists(normalized) then
    if log then
      log.info("transfer", "FILE_REQ for missing file: " .. normalized ..
        " from " .. fromAddr:sub(1, 8))
    end
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "File not found: " .. normalized,
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  -- Read the file
  local content = fs.readFile(normalized)
  if not content then
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "Cannot read file: " .. normalized,
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  -- Check size limit
  if #content > MAX_FILE_SIZE then
    if log then
      log.info("transfer", "FILE_REQ denied (too large): " .. normalized ..
        " (" .. #content .. " bytes)")
    end
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "File too large for single transfer (" ..
        #content .. " > " .. MAX_FILE_SIZE .. " bytes)",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  -- Send FILE_RES with file content
  if log then
    log.info("transfer", "Sending file: " .. normalized ..
      " (" .. #content .. " bytes) to " .. fromAddr:sub(1, 8) .. "...")
  end

  local res = protocol.makePacket(protocol.TYPE.FILE_RES, {
    path = normalized,
    data = content,
    size = #content,
  }, { to = fromAddr })

  local ok, err = net.send(fromAddr, res)
  if not ok and log then
    log.warn("transfer", "Failed to send file response: " .. tostring(err))
  end
end

return transfer
