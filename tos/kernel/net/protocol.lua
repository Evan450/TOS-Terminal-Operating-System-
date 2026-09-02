local computer = require("computer")
local serialize = require("kernel.serialize")

local protocol = {}

protocol.VERSION = 1
protocol.MAGIC   = "TOS"
protocol.MAX_SIZE = 8192

protocol.TYPE = {

  PING          = "ping",
  PONG          = "pong",

  HELLO         = "hello",
  HELLO_ACK     = "hello_ack",
  INFO_REQ      = "info_req",
  INFO_RES      = "info_res",

  MSG           = "msg",
  MSG_ACK       = "msg_ack",
  FILE_REQ      = "file_req",
  FILE_RES      = "file_res",
  FILE_DENY     = "file_deny",

  TRUST_REQ     = "trust_req",
  TRUST_ACK     = "trust_ack",
  TRUST_DENY    = "trust_deny",
  TRUST_REVOKE  = "trust_rev",

  CHALLENGE     = "challenge",
  CHALLENGE_RES = "chall_res",

  REMOTE_EXEC   = "remote_exec",
  REMOTE_RES    = "remote_res",

  CLUSTER_REGISTER      = "cl_reg",
  CLUSTER_REGISTER_ACK  = "cl_reg_ack",
  CLUSTER_HEARTBEAT     = "cl_hb",
  CLUSTER_ASSIGN        = "cl_asn",
  CLUSTER_ASSIGN_ACK    = "cl_asn_ack",
  CLUSTER_RESULT        = "cl_res",
  CLUSTER_RESULT_CHUNK  = "cl_res_chunk",
  CLUSTER_CANCEL        = "cl_cancel",
  CLUSTER_DRAIN         = "cl_drain",
  CLUSTER_STATUS_REQ    = "cl_st_req",
  CLUSTER_STATUS_RES    = "cl_st_res",

  CLUSTER_PAIR_INIT     = "cl_pair_init",
  CLUSTER_PAIR_CONFIRM  = "cl_pair_conf",

  CHAT_PAIR_INIT        = "ch_pair_init",
  CHAT_PAIR_CONFIRM     = "ch_pair_conf",

  MESH                  = "mesh",
  MESH_ACK              = "mesh_ack",

  RELAY_FORWARD         = "rly_fwd",
  RELAY_FAIL            = "rly_fail",
  PEER_STATUS           = "peer_st",

  STORE_PUT             = "st_put",
  STORE_PUT_ACK         = "st_put_ack",
  STORE_PUT_CHUNK       = "st_put_chunk",
  STORE_LEASE_EXTEND    = "st_ext",
  STORE_RELEASE         = "st_rel",
  STORE_LIST            = "st_list",
  STORE_LIST_RES        = "st_list_res",
  STORE_ERROR           = "st_err",

  NETFS_REQ             = "nfs_req",
  NETFS_RES             = "nfs_res",

  DENY          = "deny",
  ERROR         = "error",
}

local KNOWN_TYPES = {}
for _, v in pairs(protocol.TYPE) do KNOWN_TYPES[v] = true end

function protocol.makePacket(msgType, payload, opts)
  opts = opts or {}
  return {
    magic   = protocol.MAGIC,
    ver     = protocol.VERSION,
    type    = msgType,
    from    = nil,
    to      = opts.to or nil,
    seq     = opts.seq or math.random(0, 0xFFFF),
    time    = math.floor(computer.uptime() * 100),
    enc     = opts.encrypted or false,
    payload = payload or {},
  }
end

function protocol.serialize(packet)
  return serialize.compact(packet)
end

function protocol.deserialize(str)
  if not str or #str < 10 then return nil, "Too short" end
  if #str > protocol.MAX_SIZE then return nil, "Too large" end

  local result, err = serialize.decode(str, { maxBytes = protocol.MAX_SIZE })
  if not result then return nil, err end
  if type(result) ~= "table" then return nil, "Not a table" end

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

  if not KNOWN_TYPES[packet.type] then
    return false, "Unknown message type: " .. tostring(packet.type)
  end

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

function protocol.ping()
  return protocol.makePacket(protocol.TYPE.PING, {})
end

function protocol.pong()

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
