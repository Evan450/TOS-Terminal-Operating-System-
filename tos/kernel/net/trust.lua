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

-- What each trust level is allowed to do.
-- Keys are the WIRE TYPE STRINGS from kernel.net.protocol (the values
-- in the TYPE table), not the friendly enum names. net.handleIncoming
-- calls trust.isAllowed(addr, packet.type) where packet.type IS the
-- wire string, so the keys must match.
local PERMISSIONS = {
  [LEVEL.BLOCKED] = {},
  [LEVEL.UNKNOWN] = {
    ping = true, pong = true,
    -- #CLUSTER-6 — pairing packets are exchanged BEFORE trust is
    -- established (chicken-and-egg). They're authenticated by a
    -- pre-shared pairing code (out-of-band: operator-typed) rather
    -- than by trust level, so we allow them at UNKNOWN.
    cl_pair_init = true,
    cl_pair_conf = true,
  },
  --! The pairing pair is allowed at EVERY level below BLOCKED, not only at
  --! UNKNOWN. A Manager trusts its Master BEFORE the round trip (cluster-
  --! manager's pair: "apply locally FIRST"), so the Master's confirm arrives
  --! from a TRUSTED peer -- and was refused right here. Every pairing through
  --! the wizard reported "no confirm received" while the Master had in fact
  --! paired and the Manager went on to register (2-machine headless run,
  --! 2026-10-10). Nothing is widened: these packets are authenticated by the
  --! pairing code's MAC, not by level, and UNKNOWN peers could already send
  --! them. (test_net_trusted_gate.lua)
  [LEVEL.KNOWN]   = { ping = true, pong = true, hello = true, hello_ack = true,
                       info_req = true, info_res = true,
                       trust_req = true, trust_ack = true, trust_deny = true,
                       cl_pair_init = true, cl_pair_conf = true },
  [LEVEL.TRUSTED] = { ping = true, pong = true, hello = true, hello_ack = true,
                       info_req = true, info_res = true,
                       trust_req = true, trust_ack = true, trust_deny = true, trust_rev = true,
                       cl_pair_init = true, cl_pair_conf = true,
                       msg = true, msg_ack = true,
                       file_req = true, file_res = true, file_deny = true,
                       challenge = true, chall_res = true,
                       remote_exec = true, remote_res = true,
                       -- #CLUSTER-1 — cluster control plane (Master ↔ Manager).
                       -- The keys here MUST match the wire type strings in
                       -- protocol.lua's TYPE table — not the enum names.
                       -- Without this block every Manager↔Master packet was
                       -- silently dropped at the trust gate even at TRUSTED
                       -- level, which is why the existing master-skeleton's
                       -- onRegister/onHeartbeat handlers never saw traffic.
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
                       -- Relay path (Manager ↔ relay-peer Manager) — TRUSTED
                       -- is correct here: we only relay for peers we already
                       -- trust to fully encrypt + sign their traffic.
                       rly_fwd       = true,
                       rly_fail      = true,
                       peer_st       = true,
                       -- Public storage ops (Manager ↔ Storage Node) — only
                       -- the Storage Node itself uses these; gated at
                       -- TRUSTED because the put/get path can ship arbitrary
                       -- bytes through the storage tier's ACL.
                       st_put        = true,
                       st_put_ack    = true,
                       st_put_chunk  = true,
                       st_ext        = true,
                       st_rel        = true,
                       st_list       = true,
                       st_list_res   = true,
                       st_err        = true,
                       -- #NET-2 — chat-pair handshake. Pre-condition is
                       -- both sides at TRUSTED (operator already manually
                       -- elevated). Pairing only distributes the shared
                       -- secret; it does NOT change trust level. The
                       -- packets are MAC-authenticated by the out-of-band
                       -- pairing code, not by the (yet-to-exist) secret.
                       ch_pair_init  = true,
                       ch_pair_conf  = true,
                       -- Mesh transport (mail/chat/any service rides it).
                       -- Each hop is between mutually-TRUSTED neighbours
                       -- (same posture as the rly_fwd relay path above): a
                       -- node only relays/accepts flooded envelopes from
                       -- peers it already trusts to sign their traffic.
                       -- The PAYLOAD is additionally sealed end-to-end for
                       -- the final recipient (net/meshctl.lua), so relays
                       -- forward a blob they cannot read.
                       mesh          = true,
                       mesh_ack      = true,
                       --! Remote filesystem shares (kernel.netfs). Missing
                       --! from this table since netfs shipped -- the #CLUSTER-1
                       --! bug again: every NETFS_REQ was refused HERE, at
                       --! TRUSTED, before netfs.handleRequest (which does its
                       --! own arm/trust/verifyPeer/ACL checks) ever saw it, so
                       --! `netfs mount` timed out against every real host.
                       --! test_netfs.lua drove a fake net and could not see it;
                       --! test_net_trusted_gate.lua now pins every wire type.
                       nfs_req       = true,
                       nfs_res       = true },
}

-- Peer database: address -> { level, hostname, lastSeen, firstSeen, sharedSecret, dhPub, notes }
local peers = {}
local DB_PATH = "/etc/trust.dat"

-- Our own long-term Diffie-Hellman identity (kernel.x25519, RFC 7748):
-- { priv, pub }, both 32 bytes. Generated once, lazily, and persisted
-- alongside the peer DB -- see ensureMyDh/saveDB/loadDB below. nil until
-- first needed, and nil forever on a box with no usable randomness
-- source (ensureMyDh degrades to "no automatic secrets", never a crash).
local myDh = nil

-- Forward declaration: trust.setLevel (defined well before the DH
-- section below) calls this the moment a peer becomes TRUSTED, so the
-- real definition is bound to this local rather than left to resolve
-- as an undefined global.
local tryAutoSecret
-- How to say hello to a peer, registered once by kernel.net (which
-- requires this module, so this module cannot require it back).
local helloSender = nil
-- Cap on UNKNOWN-level peers so a scan/flood can't fill memory.
-- KNOWN and TRUSTED peers are always kept regardless of this limit.
local MAX_UNKNOWN_PEERS = 64

-- Pending trust requests: address -> { time, hostname }
local pendingRequests = {}
local PENDING_TTL = 300  -- Seconds before a pending request expires
local MAX_PENDING = 32   -- Max pending requests (prevents memory exhaustion from spam)

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
      dhPub       = peer.dhPub,
      secretDhPub = peer.secretDhPub,
      dhKeyChanged = peer.dhKeyChanged,
      notes       = peer.notes,
    }
  end
  -- Wrapped since the DH identity was added (loadDB tells this apart
  -- from the old bare-peer-map format: a real peer address is a UUID
  -- and can never collide with the "peers"/"dh" keys).
  local blob = { peers = saveData, dh = myDh }
  -- Atomic write when available so a power cut can't truncate the trust
  -- DB into an unparseable file (which would silently drop every peer's
  -- trust level + shared secret back to UNKNOWN on the next boot).
  return (fs.writeFileAtomic or fs.writeFile)(DB_PATH, serialize.encode(blob))
end

--! A peer's hostname is its own claim about itself. net.lua cleans it on
--! the way in (cleanClaim: a printable string of at most 32, or nil); this
--! holds the same line for any other caller and for names an older build
--! already saved into trust.dat raw.
local function cleanHostname(v)
  if type(v) ~= "string" then return nil end
  v = v:gsub("%c", ""):sub(1, 32)
  if v == "" then return nil end
  return v
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
  -- Old format: the file IS the peer map directly. Current format
  -- (since the DH identity was added): { peers = <peer map>, dh = our
  -- own identity or nil }. A real peer address is a UUID, so it can
  -- never collide with either wrapper key -- the check is unambiguous.
  if db.peers ~= nil or db.dh ~= nil then
    peers = db.peers or {}
    myDh = db.dh
    if not (type(myDh) == "table" and type(myDh.priv) == "string" and #myDh.priv == 32
        and type(myDh.pub) == "string" and #myDh.pub == 32) then
      myDh = nil   -- corrupt/foreign data: regenerate on next use rather than use it
    end
  else
    peers = db
  end
  -- Ensure all peers have required fields and clamp trust levels
  for addr, peer in pairs(peers) do
    if not VALID_LEVELS[peer.level] then
      peer.level = LEVEL.UNKNOWN
    end
    peer.hostname = cleanHostname(peer.hostname)
    peer.firstSeen = peer.firstSeen or 0
    peer.lastSeen = peer.lastSeen or 0
    if type(peer.dhPub) ~= "string" or #peer.dhPub ~= 32 then
      peer.dhPub = nil
    end
    if type(peer.secretDhPub) ~= "string" or #peer.secretDhPub ~= 32 then
      peer.secretDhPub = nil
    end
    peer.dhKeyChanged = peer.dhKeyChanged == true or nil
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
-- If an exact match exists, returns it. Otherwise requires an UNAMBIGUOUS
-- prefix match — returns nil if multiple peers share the prefix, and nil
-- (not the input) if no peer matches. Previously this returned the first
-- `pairs()` hit and fell back to the raw input on no-match; both
-- behaviours let a malicious UNKNOWN peer (auto-learned via trust.seen)
-- hijack admin commands that resolved by prefix.
-- @param partial string: Full or partial address
-- @return string|nil: The resolved full address, or nil if ambiguous/unknown
local function resolveAddress(partial)
  if not partial then return nil end
  if peers[partial] then return partial end  -- exact match
  local match = nil
  for addr in pairs(peers) do
    if addr:sub(1, #partial) == partial then
      if match then
        return nil  -- ambiguous: two peers share this prefix
      end
      match = addr
    end
  end
  return match  -- nil if no match; caller must handle
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

  -- Resolve partial address to full address to avoid duplicate entries.
  -- resolveAddress returns nil on ambiguous/no-match; in setLevel we
  -- still want to accept a full-length UUID-style address for a peer
  -- we've never seen before (admin adding a peer up front).
  local resolved = resolveAddress(address)
  if resolved then
    address = resolved
  else
    -- #SEC M13 — accept only canonical UUID form for new-peer adds.
    -- Previously `#address < 32` accepted "1234567890123456789012345678901"
    -- and similar non-UUID strings; the peer record then sat in the DB
    -- forever and offered an attacker-controlled key for impersonation
    -- (any later component_id reusing that string would inherit the
    -- pre-seeded trust). UUID format: 8-4-4-4-12 hex digits.
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

  -- Newly TRUSTED, and we already have their DH public key cached from
  -- an earlier hello (or they said hello before this elevation and
  -- we're only now catching up): try to establish a secret with no
  -- further operator action. See the "Automatic Diffie-Hellman" section
  -- below for the full picture; this is the other of its two triggers.
  if level == LEVEL.TRUSTED and oldLevel ~= LEVEL.TRUSTED then
    tryAutoSecret(address)
  end

  saveDB()

  if log then
    local levelNames = { [-1]="BLOCKED", [0]="UNKNOWN", [1]="KNOWN", [2]="TRUSTED" }
    log.info("trust", string.format("Trust for %s: %s -> %s (by %s)",
      address:sub(1, 8) .. "...",
      levelNames[oldLevel] or "?",
      levelNames[level] or "?",
      actor))
  end

  -- An explicit admin decision resolves any pending trust request
  -- from this peer (approve, refuse, or block all count as "handled").
  pendingRequests[address] = nil

  --! Say hello to a peer the moment it is raised to KNOWN or TRUSTED.
  --! HELLO / HELLO_ACK carry the DH public key, and until 2026-10-26
  --! nothing ever sent a HELLO: net.hello had no caller, so the
  --! automatic Diffie-Hellman below could not run between two real
  --! machines (its tests hand each side the other's key). The peer only
  --! answers once it has raised us to KNOWN too; then whichever side
  --! trusts second completes the exchange. (test_trust_hello.lua)
  if level >= LEVEL.KNOWN and level > oldLevel and helloSender then
    pcall(helloSender, address)
  end

  return true
end

--- Register how to say hello to a peer (kernel.net, once, at boot). A
--- second registration is refused, so later code cannot redirect it.
function trust.setHelloSender(fn)
  if helloSender or type(fn) ~= "function" then return false end
  helloSender = fn
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
  pendingRequests[address] = nil
  saveDB()
  if log then
    log.info("trust", "Peer forgotten: " .. address:sub(1, 8) .. " (by " .. actor .. ")")
  end
  return true
end

-- ============================================================
-- Shared secrets (for encrypted comms between trusted peers)
-- ============================================================
--
-- #39/#43/#44 — shared secrets gate inter-host confidentiality. Any
-- sandboxed program that can reach the trust module could previously
-- read or replace them without any privilege check, effectively
-- hijacking (or disclosing) secure channels. All three entry points
-- now require an explicit admin-tier actor. Legacy callers that pass
-- no actorTier fail closed.

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

--- Set a shared secret with a peer (for message encryption).
-- @param actor string: Username performing the action (for audit log)
-- @param address string: Remote machine address
-- @param secret string: Raw secret bytes (or nil to clear)
-- @param actorTier number: Actor's user tier (ADMIN+ required)
--- @tier admin
function trust.setSecret(actor, address, secret, actorTier)
  local ok, err = requireAdminActor(actor, actorTier, "set peer secret")
  if not ok then return false, err end
  address = resolveAddress(address)
  if not peers[address] then return false, "Unknown peer" end
  if peers[address].level < LEVEL.TRUSTED then
    return false, "Peer must be TRUSTED for shared secrets"
  end
  peers[address].sharedSecret = secret
  -- A secret set here is the operator's, not derived from any DH key.
  peers[address].secretDhPub = nil
  peers[address].dhKeyChanged = nil
  saveDB()
  -- #SEC M11 — invalidate the net layer's verifyCache for this peer
  -- so a cached "verified" hit can't continue to authenticate against
  -- the old secret after rotation. The net module exposes the
  -- invalidator at a known path; require lazily so trust.lua doesn't
  -- hard-depend on net being loaded.
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

--- Get the shared secret for a peer.
-- @param actor string: Username requesting the secret (for audit log)
-- @param address string: Remote machine address
-- @param actorTier number: Actor's user tier (ADMIN+ required)
--- @tier admin
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

--- Generate and set a new shared secret (both sides need to do this).
--- Manual fallback for when automatic Diffie-Hellman (below) can't run
--- on one or both ends -- still requires the operator to transcribe the
--- result to the other side, or to use `net pair` (chatpair.lua) instead.
--- @tier admin
function trust.generateSecret(actor, address, actorTier)
  local ok, err = requireAdminActor(actor, actorTier, "generate peer secret")
  if not ok then return nil, err end
  if not crypto then return nil, "Crypto not available" end
  local secret = crypto.salt(32)
  local okS, sErr = trust.setSecret(actor, address, secret, actorTier)
  if not okS then return nil, sErr end
  return secret
end

-- ============================================================
-- Automatic Diffie-Hellman (kernel.x25519, RFC 7748)
-- ============================================================
-- The user-visible goal: two TOS peers that talk to each other get a
-- shared secret with NO operator action beyond the trust decision they
-- already have to make (elevating a peer to TRUSTED). No code to type,
-- no "net trust gen" + manual transcription, no chatpair ritual -- those
-- all remain available as explicit fallbacks, but stop being the normal
-- path.
--
-- How it fits the existing model, unchanged:
--   * Trust elevation stays 100% manual. This module only ever derives
--     and installs a secret for a peer that is ALREADY TRUSTED -- it
--     cannot elevate anyone, and an automation flaw here has nothing to
--     trick an operator into trusting.
--   * A DH public key is public data: HELLO/HELLO_ACK already exchange
--     hostnames at KNOWN+ level (net/init.lua), so a dhPub field rides
--     along for free, cached via noteDhPublicKey regardless of trust
--     level (storing someone's public key needs no trust in them).
--   * The actual secret is only ever derived and installed once the
--     peer reaches TRUSTED and has no secret yet (tryAutoSecret, called
--     from trust.setLevel and from noteDhPublicKey) -- "first contact"
--     from the secret's point of view is whichever of those two events
--     happens second.
--   * It NEVER overwrites an existing secret: an operator's pairing or
--     manually-generated secret is authoritative. Rotation stays an
--     explicit action (trust.generateSecret / net pair), same as today.
--   * Any failure -- no randomness source, no cached dhPub yet (an
--     older peer that predates this, or one we simply haven't said
--     hello to), a malformed peer key -- just leaves the peer exactly
--     where it already was: TRUSTED with no secret, which net.send's
--     existing refusal (#47, "no shared secret... run net trust gen")
--     IS the graceful fallback the user asked for. Nothing here raises;
--     every entry point is defensive about its own inputs.

-- kernel.x25519 is lazily required: trust.lua must still load fine on a
-- stripped-down image or during the off-box signer, same posture as
-- crypto/log/config already have here.
local x25519mod = nil
local function getX25519()
  if x25519mod then return x25519mod end
  local ok, mod = pcall(require, "kernel.x25519")
  if ok then x25519mod = mod end
  return x25519mod
end

--- Our own DH keypair, generating one on first call if none exists yet.
--- Returns nil if there is no randomness source to generate one from
--- (crypto unavailable) or kernel.x25519 failed to load -- callers treat
--- that exactly like "DH isn't available right now", not an error.
local function ensureMyDh()
  if myDh then return myDh end
  local xm = getX25519()
  if not (xm and crypto and crypto.salt) then return nil end
  local okP, priv = pcall(xm.generatePrivateKey, crypto.salt)
  if not (okP and priv) then return nil end
  local okK, pub = pcall(xm.publicKey, priv)
  if not (okK and pub) then return nil end
  myDh = { priv = priv, pub = pub }
  saveDB()
  return myDh
end

--- Our DH public key. Safe to hand to anyone -- it is public by
--- definition -- and this is the only part of our DH identity any
--- caller outside this file ever sees; the private half never leaves
--- ensureMyDh. nil if DH isn't available on this box (see ensureMyDh).
function trust.getMyDhPublicKey()
  local dh = ensureMyDh()
  return dh and dh.pub or nil
end

--- If `address` is TRUSTED, has no shared secret yet, and we have a
--- cached DH public key for them, derive one via X25519 and install it.
--- Idempotent and silent on every "not yet, not now" case; logs once on
--- success or on an actual derivation failure (as opposed to simply not
--- being ready yet, which is the common case right after a hello).
function tryAutoSecret(address)
  local peer = peers[address]
  if not peer or peer.sharedSecret or not peer.dhPub then return end
  if (peer.level or 0) < LEVEL.TRUSTED then return end
  local dh = ensureMyDh()
  local xm = getX25519()
  if not (dh and xm) then return end
  local okC, secret, derr = pcall(xm.sharedSecret, dh.priv, peer.dhPub)
  if okC and secret then
    peer.sharedSecret = secret
    peer.secretDhPub = peer.dhPub
    peer.dhKeyChanged = nil
    saveDB()
    if log then
      log.info("trust", "Diffie-Hellman secret established automatically with "
        .. address:sub(1, 8) .. "...")
    end
  elseif log then
    log.warn("trust", "DH with " .. address:sub(1, 8)
      .. "... did not produce a secret (falling back to manual pairing): "
      .. tostring(okC and derr or secret))
  end
end

--- Record a peer's advertised DH public key (from a HELLO/HELLO_ACK)
--- and opportunistically derive+install a shared secret if they are
--- already TRUSTED and don't have one. Safe to call for a peer at any
--- trust level -- caching their public key needs no trust in them, only
--- actually USING it for a secret does, and tryAutoSecret enforces that.
function trust.noteDhPublicKey(address, dhPub)
  if type(dhPub) ~= "string" or #dhPub ~= 32 then return end
  address = resolveAddress(address)
  local peer = address and peers[address]
  if not peer then return end
  local old = peer.dhPub
  peer.dhPub = dhPub
  --! A TRUSTED peer whose DH key changes was almost always reinstalled:
  --! same network card, so the same address, but a new X25519 identity.
  --! It derives a fresh secret with us; we keep the one we have, and
  --! every sealed packet between the two fails with nothing saying why.
  --! The key is NOT accepted automatically -- anyone who can send a HELLO
  --! as this address could otherwise swap in their own key and read the
  --! sealed traffic. It is flagged and logged, and `net trust rekey`
  --! (trust.rekey, admin) is the operator's way to accept it.
  --! (test_trust_rekey.lua)
  if peer.sharedSecret and old and old ~= dhPub then
    if peer.secretDhPub == dhPub then
      peer.dhKeyChanged = nil          -- back to the key the secret came from
    elseif not peer.dhKeyChanged then
      peer.dhKeyChanged = true
      if log then
        log.warn("trust", "Peer " .. address:sub(1, 8) .. "... has a new identity key"
          .. " (reinstalled?). The secret we share "
          .. (peer.secretDhPub and "came from its old key and no longer matches"
              or "was set by hand and may be gone on its side")
          .. ": 'net trust rekey " .. address:sub(1, 8) .. "' to accept the new key.")
      end
    end
    saveDB()
    return
  end
  tryAutoSecret(address)
end

--- Accept a peer's new DH key: replace the secret we share with one
--- derived from the key it last sent. For a peer flagged by
--- noteDhPublicKey (reinstalled), and harmless otherwise -- the result is
--- what tryAutoSecret would have made on first contact. Refuses a peer
--- that is not TRUSTED or has sent no key, and a box with no DH.
--- @tier admin
function trust.rekey(actor, address, actorTier)
  local ok, err = requireAdminActor(actor, actorTier, "re-derive peer secret")
  if not ok then return false, err end
  address = resolveAddress(address)
  local peer = address and peers[address]
  if not peer then return false, "Unknown peer" end
  if (peer.level or 0) < LEVEL.TRUSTED then
    return false, "Peer must be TRUSTED for shared secrets"
  end
  if not peer.dhPub then return false, "No key from this peer yet (it has not said hello)" end
  local dh, xm = ensureMyDh(), getX25519()
  if not (dh and xm) then return false, "Diffie-Hellman is not available on this machine" end
  local okC, secret, derr = pcall(xm.sharedSecret, dh.priv, peer.dhPub)
  if not (okC and secret) then
    return false, "Key exchange failed: " .. tostring(okC and derr or secret)
  end
  local okS, sErr = trust.setSecret(actor, address, secret, actorTier)
  if not okS then return false, sErr end
  peer.secretDhPub = peer.dhPub
  saveDB()
  return true
end

-- #SEC H22 — closure-isolated secret access. Previously this function
-- returned the raw 32-byte shared secret for any peer to any caller that
-- could `require("kernel.net.trust")`. The naming convention "_" prefix
-- was advisory, not enforced; in particular, kernel.sandbox's
-- isUserLibName check wouldn't apply because the module is loaded via
-- the trusted require, not user libraries.
--
-- New model: a one-shot bootstrap token, minted at trust.init() and
-- handed to kernel.net at boot. Callers must present the token to read
-- a secret. Anyone who later requires the module sees an empty stub.
local _bootstrapToken = nil
local _tokenConsumed  = false

function trust._internalGetSecret(address, token)
  if not _bootstrapToken or token ~= _bootstrapToken then
    return nil  -- silent: don't even tell the caller why
  end
  address = resolveAddress(address)
  local peer = peers[address]
  return peer and peer.sharedSecret or nil
end

-- Called once at boot by kernel.net.init; returns the secret-access token.
-- After the first call the token is "consumed" — subsequent calls return
-- nil so a late require(kernel.net.trust) can't re-mint or re-read it.
function trust.getBootstrapToken()
  if _tokenConsumed then return nil end
  if not _bootstrapToken then
    if not crypto then return nil end
    _bootstrapToken = crypto.salt(64)
  end
  _tokenConsumed = true
  return _bootstrapToken
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
  hostname = cleanHostname(hostname)
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
      keyChanged = peer.dhKeyChanged == true,
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
