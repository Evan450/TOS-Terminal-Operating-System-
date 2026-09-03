-- ╔══════════════════════════════════════╗
-- ║  TOS Network - File Transfer         ║
-- ║  FILE_REQ / FILE_RES / FILE_DENY     ║
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
local securefs = nil
local usersmod = nil

-- #SEC L — runtime enable switch for the FILE_REQ server. The handler is
-- registered once at boot and stays registered, so the fileshare rc
-- service's stop() needs a real way to stop serving files (otherwise
-- "service stop fileshare" only removes a logging listener while the
-- transfer module keeps answering requests). handleRequest checks this.
--
-- #SEC — default DISABLED (fail-closed), matching kernel.net.remote/rshd.
-- transfer.init() is called unconditionally during kernel boot (stage 10)
-- whenever networking comes up, which registers the FILE_REQ listener. If
-- this defaulted to true, file serving would be ARMED at boot even on a
-- machine whose operator removed (or never started) the fileshare service —
-- so deleting /etc/rc.d/20-fileshare.lua to stop sharing files would NOT
-- actually stop it. Enablement now tracks the service lifecycle: the
-- fileshare service's start() calls setEnabled(true), stop() calls
-- setEnabled(false), and no fileshare ⇒ no file serving. (Requests still
-- also require a TRUSTED, challenge-verified peer regardless of this flag.)
local enabled = false
function transfer.setEnabled(v) enabled = v and true or false end
function transfer.isEnabled() return enabled end

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
  -- #81 — optional securefs/users for path + ownership enforcement
  securefs = modules.securefs
  usersmod = modules.users

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
-- @param opts table: { session = <principal> }   -- optional; when
--   present the write goes through securefs with the caller's
--   principal so path validation and tier checks apply. Without a
--   session the function falls back to raw fs (legacy callers) but
--   refuses to write into any protected system path.
-- @return boolean, string: true on success, or false + error message
function transfer.request(address, remotePath, localPath, opts)
  if not net then return false, "Network not available" end
  if not protocol then return false, "Protocol not loaded" end
  opts = opts or {}
  local session = opts.session

  -- Verify peer is TRUSTED
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return false, "Peer is not TRUSTED"
  end

  -- #SEC — Challenge-response: see kernel.net.remote for the full
  -- threat model. We're about to write a remote-supplied byte
  -- stream to disk; if the trusted modem was relocated, the bytes
  -- come from an attacker. Verify the peer holds the shared secret
  -- before honouring the request.
  if net.verifyPeer then
    local vOk, vErr = net.verifyPeer(address)
    if not vOk then
      return false, "Peer verification failed: " .. tostring(vErr)
    end
  end

  -- #SEC C9 — strict allowlist for the local destination. The previous
  -- blocklist missed /usr/, /root/, /home/, /var/ — a trusted peer could
  -- install a binary as /usr/bin/ls and own the next shell. Now: only
  -- /tmp/, /public/, /home/<actor>/ are valid write destinations.
  local normLocal = fs.normalize and fs.normalize(localPath) or localPath
  if type(normLocal) ~= "string" or normLocal == "" or normLocal == "/" then
    return false, "Invalid local path"
  end
  -- Determine the calling user so we can scope /home writes.
  local actor = nil
  if session and session.user then
    actor = session.user
  elseif usersmod and usersmod.currentSession then
    local s = usersmod.currentSession()
    if s then actor = s.user end
  end
  -- #SEC M-4 — only use `actor` to build path prefixes if it's a clean
  -- username. A name containing "/" or ".." would otherwise widen the
  -- /home/<actor>/ allowlist via traversal (e.g. actor="x/../.." →
  -- "/home/x/../../" escapes to root). Reject anything but [%w_%-].
  if actor and not actor:match("^[%w_%-]+$") then actor = nil end
  local function startsWith(s, p) return s:sub(1, #p) == p end
  local allowed = false
  if startsWith(normLocal, "/tmp/")    then allowed = true end
  if startsWith(normLocal, "/public/") then allowed = true end
  if actor and startsWith(normLocal, "/home/" .. actor .. "/") then allowed = true end
  -- Owner of /root writes only when actor is root
  if actor == "root" and (normLocal == "/root" or startsWith(normLocal, "/root/")) then allowed = true end
  if not allowed then
    return false, "Refusing to write outside /tmp, /public, or /home/<you>: " .. normLocal
  end

  -- Register listeners BEFORE sending. net.onceFrom handles peer-address
  -- filtering and one-shot semantics so a flood of late duplicates can't
  -- re-trigger the file write.
  local received = false
  local result   = false
  local errMsg   = "Timeout waiting for response"

  local listeners = {
    { type = protocol.TYPE.FILE_RES,
      id   = net.onceFrom(protocol.TYPE.FILE_RES, address, function(rpkt)
        received = true
        local payload = rpkt.payload or {}
        -- #SEC C9 — validate the response before touching disk.
        -- 1. payload.data must be a string (a trusted peer could send a
        --    table that, when serialized into fs.writeFile, becomes a
        --    Lua string of `"table: 0x..."`).
        -- 2. payload.path, when present, must match the path we asked for
        --    (no silently substituting a different source file).
        -- 3. Size must not exceed MAX_FILE_SIZE.
        if type(payload.data) ~= "string" then
          errMsg = "Invalid response: data not a string"
        elseif payload.path and payload.path ~= remotePath then
          errMsg = "Invalid response: path mismatch (" ..
            tostring(payload.path) .. " ~= " .. tostring(remotePath) .. ")"
        elseif #payload.data > MAX_FILE_SIZE then
          errMsg = "Response too large: " .. #payload.data .. " bytes (max " .. MAX_FILE_SIZE .. ")"
        else
          -- Prefer securefs when we have a session so writes are
          -- tier-checked and path-validated like any other user write.
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

  -- Build and send FILE_REQ
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

-- ============================================================
-- Handle incoming FILE_REQ from a remote peer
-- ============================================================

--- Process an incoming file request.
-- @param packet table: The deserialized FILE_REQ packet
-- @param fromAddr string: The sender's modem address
function transfer.handleRequest(packet, fromAddr)
  if not net or not protocol then return end
  if not enabled then return end  -- #SEC L — fileshare stopped: don't serve

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

  -- #SEC — Verify the requester via challenge-response. See
  -- kernel.net.remote for the full threat model. Same 60s cache
  -- means batched FILE_REQs from the same peer don't all incur
  -- the verification round-trip.
  if net.verifyPeer then
    local vOk, vErr = net.verifyPeer(fromAddr)
    if not vOk then
      if log then
        log.warn("transfer", "Refusing FILE_REQ from " ..
          fromAddr:sub(1, 8) .. ": " .. tostring(vErr))
      end
      -- Send DENY so the requester gets a clean error rather than
      -- a silent timeout. The reason text is intentionally vague —
      -- "Insufficient trust" rather than "verification failed" —
      -- to avoid signalling that we have a secret with this peer
      -- (which would let an attacker map the secret-set graph).
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

  -- Size check BEFORE read — reading a huge file into memory only to then
  -- reject it is a straightforward memory-exhaustion vector.
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

  -- Read the file
  local content = fs.readFile(normalized)
  if not content then
    local deny = protocol.makePacket(protocol.TYPE.FILE_DENY, {
      reason = "Cannot read file: " .. normalized,
    }, { to = fromAddr })
    net.send(fromAddr, deny)
    return
  end

  -- Defence-in-depth: if fs.size wasn't available or lied, the post-read
  -- check still rejects oversized content before we send it on the wire.
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

-- #MEM — lazy self-initialization. The kernel no longer initializes this
-- module at boot; it loads on demand (first inbound FILE_REQ via net's
-- dispatch, or an outbound scp) and wires itself from the live _TOS
-- handles — the same deps boot stage 10 used to pass. The fileshare
-- service may have armed serving before this module ever loaded, so the
-- arm state recorded in net is applied here. Fail-closed: no recorded
-- arm ⇒ disabled, the same default the module ships with. Off-box tests
-- (no _TOS.net) keep using explicit init().
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
