-- ╔══════════════════════════════════════╗
-- ║  TOS Network - Protocol Layer        ║
-- ║  Packet format & message types       ║
-- ╚══════════════════════════════════════╝
-- All network communication uses this packet format.
-- Packets are serialized Lua tables sent as strings.

local computer = require("computer")
local serialize = require("kernel.serialize")

local protocol = {}

-- ============================================================
-- Protocol constants
-- ============================================================

protocol.VERSION = 1           -- Protocol version
protocol.MAGIC   = "TOS"      -- Packet identifier (filters non-TOS traffic)
protocol.MAX_SIZE = 8192       -- Max packet size (bytes)

-- Message types (what the packet is for)
protocol.TYPE = {
  -- Discovery (UNKNOWN+ trust level)
  PING          = "ping",        -- "Are you there?"
  PONG          = "pong",        -- "Yes, I'm here" (minimal info)

  -- Information exchange (KNOWN+ trust level)
  HELLO         = "hello",       -- Handshake with hostname/version
  HELLO_ACK     = "hello_ack",   -- Handshake response
  INFO_REQ      = "info_req",    -- Request system info
  INFO_RES      = "info_res",    -- System info response

  -- Secure messaging (TRUSTED level)
  MSG           = "msg",         -- Encrypted text message
  MSG_ACK       = "msg_ack",     -- Message received acknowledgment
  FILE_REQ      = "file_req",    -- Request a file
  FILE_RES      = "file_res",    -- File data response
  FILE_DENY     = "file_deny",   -- File request denied

  -- Trust negotiation (any level, handled by trust system)
  TRUST_REQ     = "trust_req",   -- "I want to trust you"
  TRUST_ACK     = "trust_ack",   -- "Trust accepted"
  TRUST_DENY    = "trust_deny",  -- "Trust denied"
  TRUST_REVOKE  = "trust_rev",   -- "I'm revoking trust"

  -- Challenge-response (anti-spoofing for trusted connections)
  CHALLENGE     = "challenge",   -- "Prove you are who you say"
  CHALLENGE_RES = "chall_res",   -- "Here's my proof"

  -- Remote execution (TRUSTED level)
  REMOTE_EXEC   = "remote_exec", -- Execute command on remote peer
  REMOTE_RES    = "remote_res",  -- Command execution result

  -- Administrative
  DENY          = "deny",        -- Generic denial (wrong trust level)
  ERROR         = "error",       -- Error response
}

-- Reverse lookup set for O(1) type validation
local KNOWN_TYPES = {}
for _, v in pairs(protocol.TYPE) do KNOWN_TYPES[v] = true end

-- ============================================================
-- Packet construction
-- ============================================================

--- Build a packet table
-- @param msgType string: One of protocol.TYPE values
-- @param payload table: Message-specific data
-- @param opts table: { to=address, encrypted=bool, seq=number }
-- @return table: Complete packet
function protocol.makePacket(msgType, payload, opts)
  opts = opts or {}
  return {
    magic   = protocol.MAGIC,
    ver     = protocol.VERSION,
    type    = msgType,
    from    = nil,  -- Set by net layer (our address)
    to      = opts.to or nil,  -- nil = broadcast
    seq     = opts.seq or math.random(0, 0xFFFF),
    time    = math.floor(computer.uptime() * 100),
    enc     = opts.encrypted or false,  -- Is payload encrypted?
    payload = payload or {},
  }
end

-- ============================================================
-- Serialization (packet <-> string)
-- ============================================================

--- Serialize a packet to a string for transmission
function protocol.serialize(packet)
  return serialize.compact(packet)
end

--- Deserialize a string back to a packet table
function protocol.deserialize(str)
  if not str or #str < 10 then return nil, "Too short" end
  if #str > protocol.MAX_SIZE then return nil, "Too large" end

  local result, err = serialize.decode(str)
  if not result then return nil, err end
  if type(result) ~= "table" then return nil, "Not a table" end

  -- Reject pathologically deep tables (would bypass the serialize depth=8 limit)
  local function checkDepth(v, d)
    if d >= 8 then return false end
    if type(v) == "table" then
      for _, val in pairs(v) do
        if not checkDepth(val, d + 1) then return false end
      end
    end
    return true
  end
  if not checkDepth(result, 0) then return nil, "Table nesting too deep" end

  return result
end

-- ============================================================
-- Packet validation
-- ============================================================

--- Check if a deserialized table is a valid TOS packet
function protocol.validate(packet)
  if type(packet) ~= "table" then
    return false, "Not a table"
  end
  if packet.magic ~= protocol.MAGIC then
    return false, "Not a TOS packet"
  end
  if not packet.type then
    return false, "No message type"
  end
  -- Reject unrecognised message types so unknown traffic can't slip through
  if not KNOWN_TYPES[packet.type] then
    return false, "Unknown message type: " .. tostring(packet.type)
  end
  if packet.ver and packet.ver > protocol.VERSION then
    return false, "Unsupported protocol version"
  end
  return true
end

-- ============================================================
-- Convenience constructors for common packets
-- ============================================================

function protocol.ping()
  return protocol.makePacket(protocol.TYPE.PING, {})
end

function protocol.pong()
  -- Minimal response: just "I exist and run TOS"
  -- NO hostname, NO version details, NO user info
  return protocol.makePacket(protocol.TYPE.PONG, {
    tos = true,
  })
end

function protocol.hello(hostname, version)
  return protocol.makePacket(protocol.TYPE.HELLO, {
    hostname = hostname,
    version  = version,
  })
end

function protocol.helloAck(hostname, version)
  return protocol.makePacket(protocol.TYPE.HELLO_ACK, {
    hostname = hostname,
    version  = version,
  })
end

function protocol.deny(reason)
  return protocol.makePacket(protocol.TYPE.DENY, {
    reason = reason or "Access denied",
  })
end

function protocol.error(message)
  return protocol.makePacket(protocol.TYPE.ERROR, {
    message = message or "Unknown error",
  })
end

function protocol.message(text, encrypted)
  return protocol.makePacket(protocol.TYPE.MSG, {
    text = text,
  }, { encrypted = encrypted })
end

function protocol.challenge(nonce)
  return protocol.makePacket(protocol.TYPE.CHALLENGE, {
    nonce = nonce,
  })
end

function protocol.challengeResponse(nonce, proof)
  return protocol.makePacket(protocol.TYPE.CHALLENGE_RES, {
    nonce = nonce,
    proof = proof,
  })
end

function protocol.trustRequest(hostname)
  return protocol.makePacket(protocol.TYPE.TRUST_REQ, {
    hostname = hostname,
  })
end

return protocol
