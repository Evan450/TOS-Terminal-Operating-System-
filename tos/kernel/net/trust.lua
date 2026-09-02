local computer = require("computer")
local serialize = require("kernel.serialize")

local trust = {}

local LEVEL = {
  BLOCKED  = -1,
  UNKNOWN  =  0,
  KNOWN    =  1,
  TRUSTED  =  2,
}

local PERMISSIONS = {
  [LEVEL.BLOCKED] = {},
  [LEVEL.UNKNOWN] = {
    ping = true, pong = true,

    cl_pair_init = true,
    cl_pair_conf = true,
  },
  [LEVEL.KNOWN]   = { ping = true, pong = true, hello = true, hello_ack = true,
                       info_req = true, info_res = true,
                       trust_req = true, trust_ack = true, trust_deny = true },
  [LEVEL.TRUSTED] = { ping = true, pong = true, hello = true, hello_ack = true,
                       info_req = true, info_res = true,
                       trust_req = true, trust_ack = true, trust_deny = true, trust_rev = true,
                       msg = true, msg_ack = true,
                       file_req = true, file_res = true, file_deny = true,
                       challenge = true, chall_res = true,
                       remote_exec = true, remote_res = true,

                       cl_reg        = true,
                       cl_reg_ack    = true,
                       cl_hb         = true,
                       cl_asn        = true,
                       cl_asn_ack    = true,
                       cl_res        = true,
                       cl_res_chunk  = true,
                       cl_cancel     = true,
                       cl_drain      = true,
                       cl_st_req     = true,
                       cl_st_res     = true,

                       rly_fwd       = true,
                       rly_fail      = true,
                       peer_st       = true,

                       st_put        = true,
                       st_put_ack    = true,
                       st_put_chunk  = true,
                       st_ext        = true,
                       st_rel        = true,
                       st_list       = true,
                       st_list_res   = true,
                       st_err        = true,

                       ch_pair_init  = true,
                       ch_pair_conf  = true,

                       mesh          = true,
                       mesh_ack      = true },
}

local peers = {}
local DB_PATH = "/etc/trust.dat"

local MAX_UNKNOWN_PEERS = 64

local pendingRequests = {}
local PENDING_TTL = 300
local MAX_PENDING = 32

local fs = nil
local crypto = nil
local log = nil
local config = nil

local function saveDB()
  if not fs then return false end

  local saveData = {}
  for addr, peer in pairs(peers) do
    saveData[addr] = {
      level       = peer.level,
      hostname    = peer.hostname,
      firstSeen   = peer.firstSeen,
      lastSeen    = peer.lastSeen,
      sharedSecret = peer.sharedSecret,
      notes       = peer.notes,
    }
  end

  return (fs.writeFileAtomic or fs.writeFile)(DB_PATH, serialize.encode(saveData))
end

local VALID_LEVELS = {
  [LEVEL.BLOCKED] = true, [LEVEL.UNKNOWN] = true,
  [LEVEL.KNOWN]   = true, [LEVEL.TRUSTED] = true,
}

local function loadDB()
  if not fs or not fs.exists(DB_PATH) then return end
  local data, err = fs.readFile(DB_PATH)
  if not data then return end
  local db = serialize.decode(data)
  if type(db) ~= "table" then return end
  peers = db

  for addr, peer in pairs(peers) do
    if not VALID_LEVELS[peer.level] then
      peer.level = LEVEL.UNKNOWN
    end
    peer.firstSeen = peer.firstSeen or 0
    peer.lastSeen = peer.lastSeen or 0
  end
end

function trust.init(modules)
  fs     = modules.fs
  crypto = modules.crypto
  log    = modules.log
  config = modules.config

  loadDB()

  local peerCount = 0
  for _ in pairs(peers) do peerCount = peerCount + 1 end

  if log then
    log.info("trust", "Trust manager initialized (" .. peerCount .. " known peers)")
  end

  return true
end

local function resolveAddress(partial)
  if not partial then return nil end
  if peers[partial] then return partial end
  local match = nil
  for addr in pairs(peers) do
    if addr:sub(1, #partial) == partial then
      if match then
        return nil
      end
      match = addr
    end
  end
  return match
end

function trust.getLevel(address)
  if not address then return LEVEL.UNKNOWN end
  address = resolveAddress(address)
  local peer = peers[address]
  if not peer then return LEVEL.UNKNOWN end
  return peer.level
end

function trust.getPeer(address)
  if not address then return nil end
  address = resolveAddress(address)
  return peers[address]
end

function trust.isAllowed(address, msgType)
  local level = trust.getLevel(address)
  if level == LEVEL.BLOCKED then return false end
  local perms = PERMISSIONS[level]
  if not perms then return false end
  return perms[msgType] == true
end

function trust.seen(address)
  if not peers[address] then

    local unknownCount = 0
    for _, peer in pairs(peers) do
      if peer.level == LEVEL.UNKNOWN then unknownCount = unknownCount + 1 end
    end
    if unknownCount >= MAX_UNKNOWN_PEERS then
      local oldest, oldestTime = nil, math.huge
      for addr, peer in pairs(peers) do
        if peer.level == LEVEL.UNKNOWN and (peer.lastSeen or 0) < oldestTime then
          oldest = addr
          oldestTime = peer.lastSeen or 0
        end
      end
      if oldest then
        peers[oldest] = nil
        if log then log.debug("trust", "Evicted old unknown peer: " .. oldest:sub(1, 8)) end
      end
    end
    peers[address] = {
      level     = LEVEL.UNKNOWN,
      hostname  = nil,
      firstSeen = computer.uptime(),
      lastSeen  = computer.uptime(),
    }
  else
    peers[address].lastSeen = computer.uptime()
  end
end

function trust.setLevel(actor, address, level, actorTier)

  actorTier = actorTier or 0
  if actorTier < 2 then
    return false, "Admin privileges required to modify trust"
  end

  local validLevels = {
    [LEVEL.BLOCKED] = true, [LEVEL.UNKNOWN] = true,
    [LEVEL.KNOWN]   = true, [LEVEL.TRUSTED]  = true,
  }
  if not validLevels[level] then
    return false, "Invalid trust level: " .. tostring(level)
  end

  local resolved = resolveAddress(address)
  if resolved then
    address = resolved
  else

    local ok = type(address) == "string"
      and #address == 36
      and address:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
    if not ok then
      return false, "Ambiguous or invalid address: " .. tostring(address)
    end
  end

  if not peers[address] then
    peers[address] = {
      firstSeen = computer.uptime(),
      lastSeen  = computer.uptime(),
    }
  end

  local oldLevel = peers[address].level or LEVEL.UNKNOWN
  peers[address].level = level

  saveDB()

  if log then
    local levelNames = { [-1]="BLOCKED", [0]="UNKNOWN", [1]="KNOWN", [2]="TRUSTED" }
    log.info("trust", string.format("Trust for %s: %s -> %s (by %s)",
      address:sub(1, 8) .. "...",
      levelNames[oldLevel] or "?",
      levelNames[level] or "?",
      actor))
  end

  pendingRequests[address] = nil

  return true
end

function trust.trustKnown(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.KNOWN, actorTier)
end

function trust.trustFull(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.TRUSTED, actorTier)
end

function trust.block(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.BLOCKED, actorTier)
end

function trust.revoke(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.UNKNOWN, actorTier)
end

function trust.forget(actor, address, actorTier)
  if not address then return false, "No address" end
  actorTier = actorTier or 0
  if actorTier < 2 then
    return false, "Admin privileges required"
  end
  address = resolveAddress(address)
  if not peers[address] then return false, "Peer not found" end
  peers[address] = nil
  pendingRequests[address] = nil
  saveDB()
  if log then
    log.info("trust", "Peer forgotten: " .. address:sub(1, 8) .. " (by " .. actor .. ")")
  end
  return true
end

local function requireAdminActor(actor, actorTier, op)
  actorTier = tonumber(actorTier) or 0
  if actorTier < 2 then
    return false, "Admin privileges required to " .. op
  end
  if not actor or actor == "" then
    return false, "Actor required to " .. op
  end
  return true
end

function trust.setSecret(actor, address, secret, actorTier)
  local ok, err = requireAdminActor(actor, actorTier, "set peer secret")
  if not ok then return false, err end
  address = resolveAddress(address)
  if not peers[address] then return false, "Unknown peer" end
  if peers[address].level < LEVEL.TRUSTED then
    return false, "Peer must be TRUSTED for shared secrets"
  end
  peers[address].sharedSecret = secret
  saveDB()

  pcall(function()
    local netMod = require("kernel.net")
    if netMod and netMod.invalidateVerification then
      netMod.invalidateVerification(address)
    end
  end)
  if log then
    log.info("trust", "Shared secret " .. (secret and "set" or "cleared")
      .. " for " .. address:sub(1, 8) .. "... (by " .. tostring(actor) .. ")")
  end
  return true
end

function trust.getSecret(actor, address, actorTier)
  local ok, err = requireAdminActor(actor, actorTier, "read peer secret")
  if not ok then return nil, err end
  address = resolveAddress(address)
  local peer = peers[address]
  if not peer then return nil, "Unknown peer" end
  if log then
    log.info("trust", "Secret read for " .. address:sub(1, 8) .. "... (by "
      .. tostring(actor) .. ")")
  end
  return peer.sharedSecret
end

function trust.generateSecret(actor, address, actorTier)
  local ok, err = requireAdminActor(actor, actorTier, "generate peer secret")
  if not ok then return nil, err end
  if not crypto then return nil, "Crypto not available" end
  local secret = crypto.salt(32)
  local okS, sErr = trust.setSecret(actor, address, secret, actorTier)
  if not okS then return nil, sErr end
  return secret
end

local _bootstrapToken = nil
local _tokenConsumed  = false

function trust._internalGetSecret(address, token)
  if not _bootstrapToken or token ~= _bootstrapToken then
    return nil
  end
  address = resolveAddress(address)
  local peer = peers[address]
  return peer and peer.sharedSecret or nil
end

function trust.getBootstrapToken()
  if _tokenConsumed then return nil end
  if not _bootstrapToken then
    if not crypto then return nil end
    _bootstrapToken = crypto.salt(64)
  end
  _tokenConsumed = true
  return _bootstrapToken
end

local function expirePendingRequests()
  local now = computer.uptime()
  for addr, req in pairs(pendingRequests) do
    if now - req.time > PENDING_TTL then
      pendingRequests[addr] = nil
    end
  end
end

function trust.addPendingRequest(address, hostname)
  expirePendingRequests()

  if pendingRequests[address] then
    pendingRequests[address].time = computer.uptime()
    pendingRequests[address].hostname = hostname
    return
  end

  local count = 0
  for _ in pairs(pendingRequests) do count = count + 1 end
  if count >= MAX_PENDING then

    local oldestAddr, oldestTime = nil, math.huge
    for addr, req in pairs(pendingRequests) do
      if req.time < oldestTime then
        oldestAddr = addr
        oldestTime = req.time
      end
    end
    if oldestAddr then pendingRequests[oldestAddr] = nil end
  end

  pendingRequests[address] = {
    time     = computer.uptime(),
    hostname = hostname,
  }
  if log then
    log.info("trust", "Trust request from " .. address:sub(1, 8) ..
      " (" .. (hostname or "unknown") .. ")")
  end
end

function trust.getPendingRequests()
  expirePendingRequests()

  local copy = {}
  for addr, req in pairs(pendingRequests) do
    copy[addr] = { time = req.time, hostname = req.hostname }
  end
  return copy
end

function trust.clearPendingRequest(address)
  pendingRequests[address] = nil
end

function trust.listPeers()
  local result = {}
  for addr, peer in pairs(peers) do
    result[#result + 1] = {
      address    = addr,
      level      = peer.level,
      hostname   = peer.hostname,
      firstSeen  = peer.firstSeen,
      lastSeen   = peer.lastSeen,
      hasSecret  = peer.sharedSecret ~= nil,
      notes      = peer.notes,
    }
  end
  table.sort(result, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return (a.lastSeen or 0) > (b.lastSeen or 0)
  end)
  return result
end

function trust.stats()
  local counts = { blocked = 0, unknown = 0, known = 0, trusted = 0 }
  for _, peer in pairs(peers) do
    local l = peer.level
    if l == LEVEL.BLOCKED then counts.blocked = counts.blocked + 1
    elseif l == LEVEL.KNOWN then counts.known = counts.known + 1
    elseif l == LEVEL.TRUSTED then counts.trusted = counts.trusted + 1
    else counts.unknown = counts.unknown + 1 end
  end
  return counts
end

function trust.levelName(level)
  if level == LEVEL.BLOCKED then return "BLOCKED"
  elseif level == LEVEL.UNKNOWN then return "UNKNOWN"
  elseif level == LEVEL.KNOWN then return "KNOWN"
  elseif level == LEVEL.TRUSTED then return "TRUSTED"
  else return "?" end
end

trust.resolveAddress = resolveAddress

trust.LEVEL = LEVEL

return trust
