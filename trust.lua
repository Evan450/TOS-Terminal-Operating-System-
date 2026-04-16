-- ╔══════════════════════════════════════╗
-- ║  TOS Network - Trust Manager         ║
-- ║  Zero-trust peer management          ║
-- ╚══════════════════════════════════════╝
-- DEFAULT POLICY: Trust nothing. Respond to pings only.
-- Every machine starts as UNKNOWN. Elevated trust requires
-- explicit action from a local admin/root user.

local computer = require("computer")
local serialize = require("kernel.serialize")

local trust = {}

-- ============================================================
-- Trust levels
-- ============================================================
local LEVEL = {
  BLOCKED  = -1,  -- Packets dropped silently
  UNKNOWN  =  0,  -- Ping/pong only (default for everyone)
  KNOWN    =  1,  -- Ping + hostname exchange + public info
  TRUSTED  =  2,  -- Full encrypted messaging + file transfer
}

-- What each trust level is allowed to do
local PERMISSIONS = {
  [LEVEL.BLOCKED] = {},
  [LEVEL.UNKNOWN] = { ping = true, pong = true },
  [LEVEL.KNOWN]   = { ping = true, pong = true, hello = true, hello_ack = true,
                       info_req = true, info_res = true,
                       trust_req = true, trust_ack = true, trust_deny = true },
  [LEVEL.TRUSTED] = { ping = true, pong = true, hello = true, hello_ack = true,
                       info_req = true, info_res = true,
                       trust_req = true, trust_ack = true, trust_deny = true, trust_rev = true,
                       msg = true, msg_ack = true,
                       file_req = true, file_res = true, file_deny = true,
                       challenge = true, chall_res = true,
                       remote_exec = true, remote_res = true },
}

-- Peer database: address -> { level, hostname, lastSeen, firstSeen, sharedSecret, notes }
local peers = {}
local DB_PATH = "/etc/trust.dat"
-- Cap on UNKNOWN-level peers so a scan/flood can't fill memory.
-- KNOWN and TRUSTED peers are always kept regardless of this limit.
local MAX_UNKNOWN_PEERS = 64

-- Pending trust requests: address -> { time, hostname }
local pendingRequests = {}
local PENDING_TTL = 300  -- Seconds before a pending request expires
local MAX_PENDING = 32   -- Max pending requests (prevents memory exhaustion from spam)

-- Callbacks
local onTrustRequest = nil  -- Called when someone requests trust elevation
local onTrustChange = nil   -- Called when trust level changes

-- Module refs
local fs = nil
local crypto = nil
local log = nil
local config = nil

-- ============================================================
-- Persistence
-- ============================================================

local function saveDB()
  if not fs then return false end
  -- Strip transient data before saving
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
  return fs.writeFile(DB_PATH, serialize.encode(saveData))
end

-- Valid trust levels for clamping deserialized data
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
  -- Ensure all peers have required fields and clamp trust levels
  for addr, peer in pairs(peers) do
    if not VALID_LEVELS[peer.level] then
      peer.level = LEVEL.UNKNOWN
    end
    peer.firstSeen = peer.firstSeen or 0
    peer.lastSeen = peer.lastSeen or 0
  end
end

-- ============================================================
-- Initialization
-- ============================================================

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

-- ============================================================
-- Address resolution
-- ============================================================

--- Resolve a partial address to a full address from the peer database.
-- If an exact match exists, returns it. Otherwise finds the first peer
-- whose address starts with the partial string.
-- @param partial string: Full or partial address
-- @return string: The resolved full address (or the input if no match)
local function resolveAddress(partial)
  if not partial then return nil end
  if peers[partial] then return partial end  -- exact match
  for addr in pairs(peers) do
    if addr:sub(1, #partial) == partial then
      return addr
    end
  end
  return partial  -- not found, return as-is
end

-- ============================================================
-- Core trust operations
-- ============================================================

--- Get trust level for a remote address
-- Returns UNKNOWN for any address we haven't seen
function trust.getLevel(address)
  if not address then return LEVEL.UNKNOWN end
  address = resolveAddress(address)
  local peer = peers[address]
  if not peer then return LEVEL.UNKNOWN end
  return peer.level
end

--- Get peer info
function trust.getPeer(address)
  if not address then return nil end
  address = resolveAddress(address)
  return peers[address]
end

--- Check if a specific message type is allowed from an address
function trust.isAllowed(address, msgType)
  local level = trust.getLevel(address)
  if level == LEVEL.BLOCKED then return false end
  local perms = PERMISSIONS[level]
  if not perms then return false end
  return perms[msgType] == true
end

--- Record that we've seen a peer (updates lastSeen, creates entry if new)
function trust.seen(address)
  if not peers[address] then
    -- Before adding a new UNKNOWN peer, evict the oldest UNKNOWN entry if
    -- we're over the cap. KNOWN/TRUSTED peers are never evicted this way.
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

-- ============================================================
-- Trust elevation (requires local user action)
-- ============================================================

--- Set trust level for a peer (admin/root action)
-- @param actor string: Username performing the action
-- @param address string: Remote machine address
-- @param level number: New trust level
-- @param actorTier number: Actor's user tier
-- @return boolean, string
function trust.setLevel(actor, address, level, actorTier)
  -- Only admin+ can modify trust
  actorTier = actorTier or 0
  if actorTier < 2 then  -- ADMIN = 2
    return false, "Admin privileges required to modify trust"
  end

  -- Validate that the requested level is one of the defined values
  local validLevels = {
    [LEVEL.BLOCKED] = true, [LEVEL.UNKNOWN] = true,
    [LEVEL.KNOWN]   = true, [LEVEL.TRUSTED]  = true,
  }
  if not validLevels[level] then
    return false, "Invalid trust level: " .. tostring(level)
  end

  -- Resolve partial address to full address to avoid duplicate entries
  address = resolveAddress(address)

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

  if onTrustChange then
    pcall(onTrustChange, address, oldLevel, level)
  end

  return true
end

--- Convenience: trust a peer at KNOWN level
function trust.trustKnown(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.KNOWN, actorTier)
end

--- Convenience: trust a peer at TRUSTED level
function trust.trustFull(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.TRUSTED, actorTier)
end

--- Block a peer
function trust.block(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.BLOCKED, actorTier)
end

--- Revoke trust (reset to UNKNOWN)
function trust.revoke(actor, address, actorTier)
  return trust.setLevel(actor, address, LEVEL.UNKNOWN, actorTier)
end

--- Remove a peer entirely from the database
function trust.forget(actor, address, actorTier)
  if not address then return false, "No address" end
  actorTier = actorTier or 0
  if actorTier < 2 then
    return false, "Admin privileges required"
  end
  address = resolveAddress(address)
  if not peers[address] then return false, "Peer not found" end
  peers[address] = nil
  saveDB()
  if log then
    log.info("trust", "Peer forgotten: " .. address:sub(1, 8) .. " (by " .. actor .. ")")
  end
  return true
end

-- ============================================================
-- Shared secrets (for encrypted comms between trusted peers)
-- ============================================================

--- Set a shared secret with a peer (for message encryption)
function trust.setSecret(address, secret)
  address = resolveAddress(address)
  if not peers[address] then return false, "Unknown peer" end
  if peers[address].level < LEVEL.TRUSTED then
    return false, "Peer must be TRUSTED for shared secrets"
  end
  peers[address].sharedSecret = secret
  saveDB()
  return true
end

--- Get the shared secret for a peer
function trust.getSecret(address)
  address = resolveAddress(address)
  local peer = peers[address]
  if not peer then return nil end
  return peer.sharedSecret
end

--- Generate and set a new shared secret (both sides need to do this)
function trust.generateSecret(address)
  if not crypto then return nil, "Crypto not available" end
  local secret = crypto.salt(32)
  local ok, err = trust.setSecret(address, secret)
  if not ok then return nil, err end
  return secret
end

-- ============================================================
-- Incoming trust request handling
-- ============================================================

--- Expire old pending requests (called on add and on read)
local function expirePendingRequests()
  local now = computer.uptime()
  for addr, req in pairs(pendingRequests) do
    if now - req.time > PENDING_TTL then
      pendingRequests[addr] = nil
    end
  end
end

--- Record an incoming trust request (displayed to user)
function trust.addPendingRequest(address, hostname)
  expirePendingRequests()  -- Prune stale entries on every new request

  -- If already pending from this address, just update the timestamp
  if pendingRequests[address] then
    pendingRequests[address].time = computer.uptime()
    pendingRequests[address].hostname = hostname
    return
  end

  -- Enforce max pending cap to prevent memory exhaustion
  local count = 0
  for _ in pairs(pendingRequests) do count = count + 1 end
  if count >= MAX_PENDING then
    -- Drop the oldest pending request to make room
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
  if onTrustRequest then
    pcall(onTrustRequest, address, hostname)
  end
end

--- Get all pending trust requests
function trust.getPendingRequests()
  expirePendingRequests()
  -- Return a shallow copy to protect internal state
  local copy = {}
  for addr, req in pairs(pendingRequests) do
    copy[addr] = { time = req.time, hostname = req.hostname }
  end
  return copy
end

--- Clear a pending request
function trust.clearPendingRequest(address)
  pendingRequests[address] = nil
end

-- ============================================================
-- Peer listing
-- ============================================================

--- List all known peers
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

--- Count peers by trust level
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

-- ============================================================
-- Callbacks
-- ============================================================

function trust.onRequest(callback)
  onTrustRequest = callback
end

function trust.onChange(callback)
  onTrustChange = callback
end

-- ============================================================
-- Trust level name helper
-- ============================================================

function trust.levelName(level)
  if level == LEVEL.BLOCKED then return "BLOCKED"
  elseif level == LEVEL.UNKNOWN then return "UNKNOWN"
  elseif level == LEVEL.KNOWN then return "KNOWN"
  elseif level == LEVEL.TRUSTED then return "TRUSTED"
  else return "?" end
end

-- Export address resolver for external use
trust.resolveAddress = resolveAddress

-- Export constants
trust.LEVEL = LEVEL

return trust
