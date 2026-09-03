-- ╔══════════════════════════════════════╗
-- ║  TOS Network - Protocol Layer        ║
-- ║  Packet format & message types       ║
-- ╚══════════════════════════════════════╝
-- All network communication uses this packet format.
-- Packets are serialized Lua tables sent as strings.
--
-- ── ON INTEROPERABILITY, decided 2026-08-11 ─────────────────────────
-- This protocol is BESPOKE, and that is a position held on purpose
-- rather than one backed into. Writing it down because until now it was
-- only ever implied, and an unexamined default is indistinguishable
-- from an oversight.
--
-- The ecosystem's de-facto interop layer is MINITEL: Cynosure 2 ships
-- it in the KERNEL beside TCP and HTTP (NET_MTEL), and PsychOS's
-- partition table (MTPT) is named for it. Adopting it would let TOS
-- machines talk to non-TOS machines, which is a genuine thing to want.
--
-- We are not going to, because the properties this layer exists for are
-- not properties you can get out of someone else's protocol: replay-
-- resistant MACs, and trust TIERS that gate message types (see
-- protocol.TYPE above — PING is UNKNOWN+, MSG is TRUSTED). A transport
-- that does not model trust cannot be given trust semantics by the
-- layer above it; you would be checking a permission after the packet
-- had already been accepted.
--
-- The consequence, stated plainly so nobody discovers it by surprise:
-- TOS machines can only talk to TOS machines. If that ever needs to
-- change, a Minitel bridge is an EXTRAS PACKAGE that speaks both and
-- terminates trust at the boundary — never a kernel change, and never
-- a second entry point into this file.

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

  -- Cluster control plane (TRUSTED; Master ↔ Manager)
  CLUSTER_REGISTER      = "cl_reg",       -- Manager introduces itself
  CLUSTER_REGISTER_ACK  = "cl_reg_ack",   -- Master accepts/rejects registration
  CLUSTER_HEARTBEAT     = "cl_hb",        -- Periodic Manager status snapshot
  CLUSTER_ASSIGN        = "cl_asn",       -- Master hands out work
  CLUSTER_ASSIGN_ACK    = "cl_asn_ack",   -- Manager accepts/rejects assignment
  CLUSTER_RESULT        = "cl_res",       -- Assignment result (single packet)
  CLUSTER_RESULT_CHUNK  = "cl_res_chunk", -- Assignment result (one chunk of N)
  CLUSTER_CANCEL        = "cl_cancel",    -- Master cancels in-flight work
  CLUSTER_DRAIN         = "cl_drain",     -- Master asks Manager to stop taking new work
  CLUSTER_STATUS_REQ    = "cl_st_req",    -- Out-of-band status query
  CLUSTER_STATUS_RES    = "cl_st_res",    -- Out-of-band status reply

  -- Pairing handshake (operator-driven, pre-trust). The flow is
  -- documented in /TOS-Extras/cluster/master-skeleton/cluster.lua's
  -- pair subcommand. Both sides remain at UNKNOWN level for trust
  -- gating; pairing packets are allowed at UNKNOWN explicitly so the
  -- exchange can complete before either side raises the other to
  -- TRUSTED. Once pairing finishes, both sides set the peer to
  -- TRUSTED with the derived shared secret.
  CLUSTER_PAIR_INIT     = "cl_pair_init",    -- Manager → Master: "here's my code proof"
  CLUSTER_PAIR_CONFIRM  = "cl_pair_conf",    -- Master → Manager: "accepted; same secret"

  -- Chat / peer pairing (operator-driven shared-secret bootstrap).
  -- Replaces the manual "net trust gen <addr>" → copy hex → "net trust
  -- setSecret <addr> <hex>" flow on the other side, which is tedious
  -- and error-prone. Pre-condition: BOTH sides have already manually
  -- elevated each other to TRUSTED (the friction the operator
  -- explicitly wants preserved — see net/chatpair.lua header). Pairing
  -- only handles secret distribution, not trust elevation.
  CHAT_PAIR_INIT        = "ch_pair_init",    -- B → A: "here's my code proof"
  CHAT_PAIR_CONFIRM     = "ch_pair_conf",    -- A → B: "accepted; same secret"

  -- Mesh transport (store-and-forward; flooded, payload sealed end-to-end,
  -- service-multiplexed by the envelope's `svc` field — stage 5: the mesh
  -- is part of the integrated network; mail/chat/etc. are tenants).
  -- These ride net.broadcast and are routed by net/mesh.lua, NOT by the
  -- unicast trust/MAC pipeline — the payload is opaque to relays, so the
  -- net layer hands MESH straight to the transport controller after a
  -- light gate. See net/meshctl.lua + net/mesh.lua.
  MESH                  = "mesh",         -- A mesh envelope (one hop)
  MESH_ACK              = "mesh_ack",     -- Delivery acknowledgement (flooded back)

  -- Relay routing (Manager ↔ relay-peer Manager, strictly limited)
  RELAY_FORWARD         = "rly_fwd",      -- Wrapped Master-bound packet
  RELAY_FAIL            = "rly_fail",     -- TTL/loop/unreachable
  PEER_STATUS           = "peer_st",      -- Relay-peer liveness

  -- Public storage ops (TOS-protocol path; Manager ↔ Storage Node)
  STORE_PUT             = "st_put",
  STORE_PUT_ACK         = "st_put_ack",
  STORE_PUT_CHUNK       = "st_put_chunk",
  STORE_LEASE_EXTEND    = "st_ext",
  STORE_RELEASE         = "st_rel",
  STORE_LIST            = "st_list",
  STORE_LIST_RES        = "st_list_res",
  STORE_ERROR           = "st_err",

  -- Remote filesystem shares (TRUSTED; kernel.netfs)
  -- ONE request type with an `op` field rather than a type per
  -- operation. Nine types would mean nine places to remember the arm
  -- check, the trust check, the verifyPeer call and the vague-denial
  -- rule — and a tenth operation added later would be one more chance
  -- to forget one. netfs.handleRequest is the single gate; the ops
  -- dispatch behind it. This also mirrors the PUB read protocol (§3.2
  -- of the cluster spec), which multiplexes on `op` for the same reason.
  NETFS_REQ             = "nfs_req",
  NETFS_RES             = "nfs_res",

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

  -- #SEC M14 — cap parser table-entries for network packets specifically.
  -- The global serialize cap is 10000; a packet bounded by MAX_SIZE bytes
  -- can never legitimately carry that many entries. Override with a much
  -- tighter ceiling so a hostile peer can't cause MAX_SIZE-sized parse
  -- traffic to allocate large internal arrays.
  local result, err = serialize.decode(str, { maxBytes = protocol.MAX_SIZE })
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
  -- Type-check before comparing: a malformed packet whose `ver` field
  -- arrives as a string (intentionally or by accident) would otherwise
  -- raise "attempt to compare string with number" inside the dispatch
  -- path and crash the receiver. Reject unparseable values up front.
  if packet.ver ~= nil then
    if type(packet.ver) ~= "number" then
      return false, "Invalid protocol version field"
    end
    if packet.ver > protocol.VERSION then
      return false, "Unsupported protocol version"
    end
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
