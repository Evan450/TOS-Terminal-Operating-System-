local computer = require("computer")

local transfer = {}

local MAX_FILE_SIZE = 6144

local TIMEOUT = 30

local net      = nil
local fs       = nil
local trustMgr = nil
local crypto   = nil
local log      = nil
local event    = nil
local protocol = nil
local securefs = nil
local usersmod = nil

local enabled = false
function transfer.setEnabled(v) enabled = v and true or false end
function transfer.isEnabled() return enabled end

function transfer.init(modules)
  net      = modules.net
  fs       = modules.fs
  trustMgr = modules.trust
  crypto   = modules.crypto
  log      = modules.log
  event    = modules.event

  securefs = modules.securefs
  usersmod = modules.users

  protocol = require("kernel.net.protocol")

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

function transfer.request(address, remotePath, localPath, opts)
  if not net then return false, "Network not available" end
  if not protocol then return false, "Protocol not loaded" end
  opts = opts or {}
  local session = opts.session

  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return false, "Peer is not TRUSTED"
  end

  if net.verifyPeer then
    local vOk, vErr = net.verifyPeer(address)
    if not vOk then
      return false, "Peer verification failed: " .. tostring(vErr)
    end
  end

  local normLocal = fs.normalize and fs.normalize(localPath) or localPath
  if type(normLocal) ~= "string" or normLocal == "" or normLocal == "/" then
    return false, "Invalid local path"
  end

  local actor = nil
  if session and session.user then
    actor = session.user
  elseif usersmod and usersmod.currentSession then
    local s = usersmod.currentSession()
    if s then actor = s.user end
  end

  if actor and not actor:match("^[%w_%-]+$") then actor = nil end
  local function startsWith(s, p) return s:sub(1, #p) == p end
  local allowed = false
  if startsWith(normLocal, "/tmp/")    then allowed = true end
  if startsWith(normLocal, "/public/") then allowed = true end
  if actor and startsWith(normLocal, "/home/" .. actor .. "/") then allowed = true end

  if actor == "root" and (normLocal == "/root" or startsWith(normLocal, "/root/")) then allowed = true end
  if not allowed then
    return false, "Refusing to write outside /tmp, /public, or /home/<you>: " .. normLocal
  end

  local received = false
  local result   = false
  local errMsg   = "Timeout waiting for response"

  local listeners = {
    { type = protocol.TYPE.FILE_RES,
      id   = net.onceFrom(protocol.TYPE.FILE_RES, address, function(rpkt)
        received = true
        local payload = rpkt.payload or {}

        if type(payload.data) ~= "string" then
          errMsg = "Invalid response: data not a string"
        elseif payload.path and payload.path ~= remotePath then
          errMsg = "Invalid response: path mismatch (" ..
            tostring(payload.path) .. " ~= " .. tostring(remotePath) .. ")"
        elseif #payload.data > MAX_FILE_SIZE then
          errMsg = "Response too large: " .. #payload.data .. " bytes (max " .. MAX_FILE_SIZE .. ")"
        else

          local writeOk, writeErr
          if securefs and session and securefs.writeFile then
            writeOk, writeErr = securefs.writeFile(localPath, payload.data,
              { session = session })
          else
            writeOk, writeErr = fs.writeFile(localPath, payload.data)
          end
          if writeOk then
            result = true
            if log then
              log.info("transfer", "Received file: " .. remotePath ..
                " (" .. tostring(payload.size or #payload.data) .. " bytes)")
            end
          else
            errMsg = "Failed to write local file: " .. tostring(writeErr or localPath)
          end
        end
      end) },
    { type = protocol.TYPE.FILE_DENY,
      id   = net.onceFrom(protocol.TYPE.FILE_DENY, address, function(rpkt)
        received = true
        local payload = rpkt.payload or {}
        errMsg = payload.reason or "File request denied"
      end) },
  }

  local pkt = protocol.makePacket(protocol.TYPE.FILE_REQ, {
    path = remotePath,
  }, { to = address })

  local ok, sendErr = net.send(address, pkt)
  if not ok then
    net.offAll(listeners)
    return false, "Send failed: " .. tostring(sendErr)
  end

  if log then
    log.info("transfer", "Requested file: " .. remotePath ..
      " from " .. address:sub(1, 8) .. "...")
  end

  net.waitFor(function() return received end, TIMEOUT)
  net.offAll(listeners)

  if not received then
    return false, errMsg
  end

  return result, result and nil or errMsg
end

function transfer.handleRequest(packet, fromAddr)
  if not net or not protocol then return end
  if not enabled then return end

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

  if net.verifyPeer then
    local vOk, vErr = net.verifyPeer(fromAddr)
    if not vOk then
      if log then
        log.warn("transfer", "Refusing FILE_REQ from " ..
          fromAddr:sub(1, 8) .. ": " .. tostring(vErr))
      end

      local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
        reason = "Insufficient trust level",
      }, { to = fromAddr })
      net.send(fromAddr, deny)
      return
    end
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

  local normalized = fs.normalize(path)
  if normalized:sub(1, 8) ~= "/public/" and normalized ~= "/public" then
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "Access restricted to /public/",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

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

  local sz = fs.size and fs.size(normalized) or nil
  if type(sz) == "number" and sz > MAX_FILE_SIZE then
    if log then
      log.info("transfer", "FILE_REQ denied (too large): " .. normalized ..
        " (" .. sz .. " bytes)")
    end
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "File too large for single transfer (" ..
        sz .. " > " .. MAX_FILE_SIZE .. " bytes)",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  local content = fs.readFile(normalized)
  if not content then
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "Cannot read file: " .. normalized,
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  if #content > MAX_FILE_SIZE then
    if log then
      log.info("transfer", "FILE_REQ denied post-read (too large): " ..
        normalized .. " (" .. #content .. " bytes)")
    end
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "File too large for single transfer (" ..
        #content .. " > " .. MAX_FILE_SIZE .. " bytes)",
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

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

do
  local T = rawget(_G, "_TOS")
  if T and T.net and not net then
    local okC, cryptoMod = pcall(require, "kernel.crypto")
    local okI = pcall(transfer.init, {
      net      = T.net,
      fs       = T.fs,
      trust    = T.net.getTrust and T.net.getTrust() or nil,
      crypto   = okC and cryptoMod or nil,
      log      = T.logObj,
      event    = T.event,
      securefs = T.securefs,
      users    = T.users,
    })
    if okI and T.net.getServiceArm and T.net.getServiceArm("fileshare") then
      transfer.setEnabled(true)
    end
  end
end

return transfer
