-- ╔══════════════════════════════════════╗
-- ║  TOS Network - Main Network Layer    ║
-- ║  Zero-trust modem/tunnel comms       ║
-- ╚══════════════════════════════════════╝
-- SECURITY POLICY: Every incoming packet is checked against
-- the trust manager BEFORE any processing occurs. Untrusted
-- machines can only ping. Everything else is denied silently.

local component = require("component")
local computer = require("computer")

local net = {}

-- Sub-modules
local protocol = nil
local trustMgr = nil
local crypto   = nil

-- #SEC H-3 — replay freshness via a per-peer monotonic sequence number,
-- bound into the packet MAC. The old defence was a 512-entry nonce ring
-- per peer: a captured packet replays successfully once its nonce ages
-- out of that window. We additionally require the per-sender sequence to
-- strictly increase. A per-boot random `epoch` accompanies the counter so
-- a sender that reboots (and restarts its counter at 1) is not mistaken
-- for a replay: a never-before-seen epoch is accepted and becomes the new
-- baseline, while packets carrying the CURRENT or a RETIRED epoch must
-- still advance the counter. An attacker cannot forge a fresh epoch
-- because epoch+seq are inside the secret-bound MAC.
local SEQ_RETIRE_MAX = 8     -- retired epochs remembered per peer
local SEQ_MAX_PEERS  = 256   -- cap distinct peers tracked (anti-DoS)

-- Pure freshness decision. `holder` is a peer→record map; mutates the
-- record to advance the high-water mark / rotate epochs. Returns
-- (true) to accept or (false, reason) to drop. Legacy packets with no
-- epoch/seq return true (the nonce window remains the backstop).
-- Exposed as net._seqCheck for tests.
local function seqFreshnessCheck(holder, key, epoch, seq)
  if type(epoch) ~= "string" or type(seq) ~= "number" then
    return true  -- no sequence info; defer to the nonce window
  end
  local rec = holder[key]
  if not rec then
    -- Anti-DoS: bound the number of peers we track. Evict the oldest.
    holder.__order = holder.__order or {}
    if #holder.__order >= SEQ_MAX_PEERS then
      local victim = table.remove(holder.__order, 1)
      if victim ~= nil then holder[victim] = nil end
    end
    holder.__order[#holder.__order + 1] = key
    holder[key] = { epoch = epoch, maxSeq = seq, retired = {}, retiredOrder = {} }
    return true
  end
  if rec.epoch == epoch then
    if seq <= rec.maxSeq then return false, "stale or replayed sequence" end
    rec.maxSeq = seq
    return true
  end
  if rec.retired[epoch] then
    return false, "replayed packet from a retired epoch"
  end
  -- A never-before-seen epoch: genuine sender reboot. Retire the current
  -- epoch (bounded) and adopt the new one.
  rec.retired[rec.epoch] = true
  rec.retiredOrder[#rec.retiredOrder + 1] = rec.epoch
  if #rec.retiredOrder > SEQ_RETIRE_MAX then
    local old = table.remove(rec.retiredOrder, 1)
    rec.retired[old] = nil
  end
  rec.epoch = epoch
  rec.maxSeq = seq
  return true
end
net._seqCheck = seqFreshnessCheck

-- Hardware
local modem    = nil   -- Primary modem (back-compat)
local tunnel   = nil
local myAddr   = nil
-- Multi-NIC: all available modems. modem == modems[1].proxy for compat.
local modems   = {}    -- { { addr, proxy, wireless }, ... }

-- Config
--
-- listenPort handles ALL traffic — discovery broadcasts, unicasts,
-- responses. We used to use 42 for unicast and 43 for broadcast,
-- but that doesn't fit a Tier-1 wireless modem (which can hold one
-- port open at a time). The OC modem API doesn't restrict broadcast
-- vs unicast by port; a modem hears anything on any port it's
-- opened, so a single port is enough.
--
-- The legacy `broadcastPort` config key is still read for
-- compatibility — if a saved tos.cfg sets it, we open that port too.
-- New installs leave it nil and only use listenPort.
local listenPort    = 42
local broadcastPort = nil    -- legacy / opt-in second port
local encryptComms  = true
local hostname      = "tos"

-- State
local running   = false
local listeners = {}  -- msgType -> { callback, ... }

-- Module refs
local log    = nil
local config = nil
local event  = nil

-- Forward declarations (prevent global namespace pollution)
local dispatchToListeners

-- ============================================================
-- Initialization
-- ============================================================

function net.init(modules)
  log    = modules.log
  config = modules.config
  event  = modules.event

  -- Load sub-modules
  protocol = require("kernel.net.protocol")
  trustMgr = require("kernel.net.trust")
  crypto   = require("kernel.crypto")

  trustMgr.init({
    fs     = modules.fs,
    crypto = crypto,
    log    = log,
    config = config,
  })

  -- #SEC H22 — claim the one-shot bootstrap token now so secret access
  -- below works. After this call, trust.getBootstrapToken() returns nil
  -- so any code that later requires the module can't fetch it.
  net._trustToken = trustMgr.getBootstrapToken and trustMgr.getBootstrapToken() or nil

  -- Load config
  if config then
    listenPort    = config.get("listenPort") or 42
    -- broadcastPort is legacy/opt-in. nil means "single-port mode";
    -- only set if the operator explicitly configured it.
    local bp = config.get("broadcastPort")
    broadcastPort = (type(bp) == "number" and bp ~= listenPort) and bp or nil
    encryptComms  = config.get("encryptComms") ~= false
    hostname      = config.get("hostname") or "tos"
  end

  -- Detect hardware: enumerate ALL modems (multi-NIC for server racks)
  --
  -- Tier-1 wireless modems can hold ONE open port at a time; opening
  -- a second port silently closes the first. We default to one port
  -- (listenPort) and only open broadcastPort if the operator
  -- explicitly configured it (legacy tos.cfg). For T1 wireless the
  -- single-port path is the only one that works.
  modems = {}
  for addr in component.list("modem") do
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then
      pcall(proxy.open, listenPort)
      if broadcastPort then pcall(proxy.open, broadcastPort) end
      local wireless = false
      pcall(function() wireless = proxy.isWireless() end)
      modems[#modems + 1] = { addr = addr, proxy = proxy, wireless = wireless }
      if log then
        log.info("net", string.format("Modem %d: %s [%s]",
          #modems, wireless and "wireless" or "wired", addr:sub(1, 8) .. "..."))
      end
    end
  end
  -- Primary modem = first one found (back-compat)
  if #modems > 0 then
    modem  = modems[1].proxy
    myAddr = modems[1].addr
    if log and #modems > 1 then
      log.info("net", #modems .. " NICs active (multi-modem)")
    end
    if log then
      local portInfo = broadcastPort
        and ("ports " .. listenPort .. ", " .. broadcastPort)
        or  ("port " .. listenPort .. " (single-port mode)")
      log.info("net", "Listening on " .. portInfo)
    end
  end

  -- Detect tunnel (linked card)
  for addr in component.list("tunnel") do
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then
      tunnel = proxy
      if log then log.info("net", "Linked card detected") end
    end
    break
  end

  if not modem and not tunnel then
    if log then log.warn("net", "No network hardware detected") end
    return false
  end

  -- Register modem_message event handler
  if event then
    event.on("modem_message", function(_, localAddr, remoteAddr, port, dist, rawData)
      net.handleIncoming(remoteAddr, port, dist, rawData)
      -- Opportunistic retry pump: re-flood any un-ACKed mesh message whose
      -- retry window has come. Driven off live traffic (throttled to ~5s)
      -- so we don't need a dedicated kernel timer; mesh consumers (the
      -- mail package UI) also tick on open to cover quiet stretches.
      net.meshTick()
    end, "net")
  end

  running = true

  -- #NET-2 — chat-pair handler. Initialised after trust is up because
  -- the handler does setSecret on inbound init. We register the inbound
  -- packet listener here so the dispatch path delivers it; the sender
  -- side is invoked directly by the shell command.
  local okCP, chatpairMod = pcall(require, "kernel.net.chatpair")
  if okCP and chatpairMod and chatpairMod.init then
    chatpairMod.init({
      crypto   = crypto,
      protocol = protocol,
      trust    = trustMgr,
      log      = log,
    })
    net._chatpair = chatpairMod
    net.on(protocol.TYPE.CHAT_PAIR_INIT, function(pkt, from)
      chatpairMod.onPairInit(pkt, from)
    end)
    if log then log.info("net", "Chat-pair handler registered") end
  elseif log then
    log.warn("net", "chatpair module unavailable: "..tostring(chatpairMod))
  end

  -- Mesh transport controller (stage 5: the mesh is part of the
  -- INTEGRATED network). One flood mesh, service-multiplexed by the
  -- envelope's `svc` field: mail (an Extras package), chat, or any other
  -- service registers a delivery handler via net.meshOn and sends via
  -- net.meshSend. Envelopes ride net.broadcast with the payload sealed
  -- end-to-end using the per-peer trust secret, so relays pass an opaque
  -- blob; the trust gate (TRUSTED-only, like the relay path) is the
  -- transport-level protection.
  local okMesh, meshctlMod = pcall(require, "kernel.net.meshctl")
  if okMesh and meshctlMod then
    meshctlMod.init({ crypto = crypto, serialize = require("kernel.serialize"),
      log = log, clock = function() return computer.uptime() end })

    net._meshctl = meshctlMod.new({
      myAddr = myAddr,
      clock  = function() return computer.uptime() end,
      broadcast = function(env)
        local t = (env.kind == "ack") and protocol.TYPE.MESH_ACK or protocol.TYPE.MESH
        net.broadcast(protocol.makePacket(t, env))
      end,
      secretFor = function(addr)
        return trustMgr._internalGetSecret
          and trustMgr._internalGetSecret(addr, net._trustToken) or nil
      end,
      log = log,
    })

    local function onMeshPkt(pkt)
      if type(pkt.payload) == "table" then net._meshctl:onPacket(pkt.payload) end
    end
    net.on(protocol.TYPE.MESH, onMeshPkt)
    net.on(protocol.TYPE.MESH_ACK, onMeshPkt)
    if log then log.info("net", "Mesh transport controller registered") end
  elseif log then
    log.warn("net", "mesh transport unavailable: " .. tostring(meshctlMod))
  end

  if log then
    log.info("net", "Network initialized (zero-trust mode)")
    log.info("net", "Encryption: " .. (encryptComms and "enabled" or "disabled"))
  end

  return true
end

--- Expose the chat-pair module so shell commands can call connect/startWindow.
function net.getChatPair()
  return net._chatpair
end

-- ============================================================
-- Mesh transport (public API — services register + send here)
-- ============================================================
-- Stage 5: mail moved to an Extras package that consumes this API; the
-- old net.sendMail/inbox/inboxBox/mailPending/mailTick surface is gone
-- (the mail package owns mailbox semantics now).

--- True when the mesh transport came up (network hardware present).
function net.meshAvailable()
  return net._meshctl ~= nil
end

--- Send a mesh message. `opts` = { svc="mail"|..., to=address|"*",
--- user=, fromUser=, payload=<table>, ttl=, allowPlaintext= }.
--- Returns (id, sealed) or (nil, reason). #SEC — a unicast send with no
--- shared secret is REFUSED unless allowPlaintext is set (relayed
--- plaintext was the review's "silent fallback" finding).
function net.meshSend(opts)
  if not net._meshctl then return nil, "mesh not available (no network?)" end
  return net._meshctl:send(opts or {})
end

--- Register the local delivery handler for a mesh service kind.
--- handler(message, env) -> truthy when accepted (only then is the
--- delivery ACKed back to the sender).
function net.meshOn(svc, handler)
  if not net._meshctl then return false, "mesh not available" end
  net._meshctl:on(svc, handler)
  return true
end

--- Unregister a mesh service handler.
function net.meshOff(svc)
  if net._meshctl then net._meshctl:off(svc) end
end

--- Is a local handler registered for this service kind?
function net.meshHasHandler(svc)
  return net._meshctl ~= nil and net._meshctl:hasHandler(svc)
end

--- Count of our sent mesh messages still awaiting acknowledgement.
function net.meshPending()
  return net._meshctl and net._meshctl:pending() or 0
end

--- Re-flood un-ACKed messages whose retry window has come (throttled to
--- ~5s). Safe to call often; a no-op when the mesh isn't available.
function net.meshTick()
  if not net._meshctl then return end
  local now = computer.uptime()
  if now - (net._lastMeshTick or 0) >= 5 then
    net._lastMeshTick = now
    net._meshctl:tick(now)
  end
end

function net.isAvailable()
  return modem ~= nil or tunnel ~= nil
end

function net.getAddress()
  return myAddr
end

function net.getHostname()
  return hostname
end

--- Return count of available modems.
function net.modemCount()
  return #modems
end

-- ============================================================
-- Sending
-- ============================================================

--- Send a packet to a specific address
-- @param address string: Destination modem address
-- @param packet table: Protocol packet (from protocol.make*)
-- @param port number: (optional) port override
-- @return boolean
-- Packet types that should NEVER be encrypted, regardless of trust
-- level or encryptComms setting:
--   • Discovery (PING/PONG): need to reach UNKNOWN peers; no payload
--     worth protecting — just "I exist" + maybe device type.
--   • Hostname exchange (HELLO/HELLO_ACK): semi-public.
--   • Challenge handshake (CHALLENGE/CHALLENGE_RES): the proof is an
--     HMAC of a public nonce; the secret never crosses the wire by
--     definition. Encrypting it would require a secret to verify the
--     secret — chicken-and-egg.
--   • Errors (DENY): refusal reasons, no sensitive payload.
--
-- Sensitive packet types (REMOTE_EXEC/REMOTE_RES/FILE_*/MSG/TRUST_*)
-- still go through the encrypt-or-refuse logic when the peer is
-- TRUSTED with encryptComms on.
local PUBLIC_PACKET_TYPES = {
  ping = true, pong = true,
  hello = true, hello_ack = true,
  challenge = true, chall_res = true,
  deny = true,
  -- #NET-2 — chat-pair packets are authenticated by an out-of-band
  -- pairing code (PBKDF-derived MAC); they MUST NOT be encrypted with
  -- the shared secret because the whole point of the handshake is to
  -- bootstrap that very secret. Without this entry, the send-path
  -- would refuse to ship them ("TRUSTED peer has no shared secret").
  ch_pair_init = true, ch_pair_conf = true,
  -- The cluster-pair handshake has the same property; it currently
  -- works only because both sides are still UNKNOWN at pair time and
  -- never hit the encrypt branch. Listing them here makes the policy
  -- explicit and protects a future cluster-pair-after-trust flow.
  cl_pair_init = true, cl_pair_conf = true,
}

function net.send(address, packet, port)
  if not modem and not tunnel then return false, "No modem" end

  port = port or listenPort

  -- Stamp our address
  packet.from = myAddr

  -- #SEC H-1 — stamp the destination so the per-packet MAC actually binds
  -- `to`. The MAC concat below mixes in `packet.to`, but unicast packets
  -- built via protocol.ping()/message()/etc. never set it, leaving the
  -- binding a constant empty string and the "can't be redirected to another
  -- recipient" guarantee vacuous. Setting it here (unicast destination ==
  -- `address`) makes that guarantee real. Wire-compatible: the value travels
  -- with the packet, so the receiver MACs the same `to` regardless of which
  -- side is patched.
  packet.to = address

  -- Encrypt payload if talking to a trusted peer, encryption is on,
  -- AND the packet type carries something worth encrypting.
  --
  -- The bug this guards against: a PING from us to a TRUSTED peer
  -- (or a PONG response to an incoming PING) used to fail the
  -- encryption check whenever we hadn't yet provisioned a shared
  -- secret with that peer. Operators couldn't even discover or
  -- handshake until they ran `net trust gen` first — a usability
  -- and bootstrapping problem, not a security improvement (PING
  -- carries no secret payload).
  local peerLevel = trustMgr.getLevel(address)
  local isPublic = PUBLIC_PACKET_TYPES[packet.type]
  if encryptComms and peerLevel >= trustMgr.LEVEL.TRUSTED and not isPublic then
    -- Internal accessor: send-path runs in the kernel with no user
    -- actor, so we skip the admin gate that protects the public API
    -- (#39/#43/#44). The secret is still only materialised inside the
    -- kernel crypto pipeline.
    local secret = trustMgr._internalGetSecret(address, net._trustToken)
    if secret and packet.payload then
      local plaintext = protocol.serialize(packet.payload)
      local encrypted, method = crypto.encrypt(plaintext, secret)
      packet.payload = encrypted
      packet.enc = method  -- "aes" or "xor"
      -- #SEC C10/H-1 — append a per-packet nonce and HMAC over
      -- (type || to || algo || nonce || ciphertext). Binding the packet
      -- TYPE and destination (`to`) means a captured packet cannot be
      -- replayed as a different type or redirected to another recipient
      -- without invalidating the tag. The receiver checks the HMAC
      -- before deserializing, refuses duplicate nonces (replay), and
      -- refuses XOR downgrade when AES would be available. `from` is not
      -- bound: OC authenticates the sending modem address (the receiver
      -- overrides packet.from with it), and binding the "tunnel" fallback
      -- (linked cards) would break those links.
      -- #SEC H-3 — per-boot epoch + per-peer monotonic sequence, both
      -- bound into the MAC so a replay can't strip or rewrite them.
      net._bootEpoch = net._bootEpoch or crypto.salt(12)
      net._sendSeq = net._sendSeq or {}
      net._sendSeq[address] = (net._sendSeq[address] or 0) + 1
      packet.epoch = net._bootEpoch
      packet.seq   = net._sendSeq[address]
      packet.nonce = crypto.salt(16)
      packet.mac   = crypto.hmac(secret, table.concat({
        packet.type or "", packet.to or "", method or "",
        packet.epoch, tostring(packet.seq), packet.nonce, encrypted
      }, "\0"))
    elseif packet.payload and not secret then
      -- #47 — Sensitive packet, TRUSTED peer, no secret. Plaintext
      -- would silently downgrade the security the operator asked
      -- for. Refuse and surface the actionable command.
      if log then
        log.warn("net", string.format(
          "Refusing plaintext send to TRUSTED peer %s (%s): no shared secret; " ..
          "run 'net trust gen %s' as admin to provision one",
          address:sub(1, 8), packet.type or "?", address:sub(1, 8)))
      end
      return false, "TRUSTED peer has no shared secret; refusing plaintext send"
    end
  end

  -- Serialize and send
  local data = protocol.serialize(packet)
  if #data > protocol.MAX_SIZE then
    return false, "Packet too large"
  end

  local ok, err2
  if modem then
    ok, err2 = pcall(modem.send, address, port, data)
  else
    -- Tunnel-only box (linked card): point-to-point fallback. The link
    -- partner ignores packets not addressed to it, so a wrong `address`
    -- fails safe.
    ok, err2 = pcall(tunnel.send, data)
  end
  if not ok then
    return false, "Send failed: " .. tostring(err2)
  end

  return true
end

--- Broadcast a packet to all machines on a port.
-- Multi-NIC: broadcasts on ALL modems so the packet reaches every
-- physical network the server is connected to.
function net.broadcast(packet, port)
  if not modem and not tunnel then return false, "No modem" end
  -- Fall back to listenPort when no separate broadcastPort is
  -- configured (single-port mode, the new default for T1 wireless).
  port = port or broadcastPort or listenPort

  packet.from = myAddr
  local data = protocol.serialize(packet)
  local anyOk = false
  for _, m in ipairs(modems) do
    local ok2 = pcall(m.proxy.broadcast, port, data)
    anyOk = anyOk or ok2
  end
  -- A linked card is a fixed point-to-point pair; "broadcast" to the
  -- link partner is exactly discovery's intent, so include it.
  if tunnel then
    local ok2 = pcall(tunnel.send, data)
    anyOk = anyOk or ok2
  end
  if not anyOk then return false, "Broadcast failed on all NICs" end
  return true
end

-- ============================================================
-- Receiving & trust enforcement
-- ============================================================

--- Handle an incoming modem_message
-- This is the SECURITY GATE. Every packet goes through trust checks.
function net.handleIncoming(remoteAddr, port, distance, rawData)
  if not running then return end

  -- Parse packet
  local packet, err = protocol.deserialize(rawData)
  if not packet then
    -- Not a valid packet - silently drop
    return
  end

  -- Validate it's a TOS packet
  local valid, verr = protocol.validate(packet)
  if not valid then return end  -- Not TOS traffic, ignore

  -- Record that we've seen this peer
  trustMgr.seen(remoteAddr)
  packet.from = remoteAddr  -- Ensure 'from' matches actual sender
  packet._distance = distance  -- Attach distance info

  -- ══════════════════════════════════════════════
  -- TRUST ENFORCEMENT - The core security gate
  -- ══════════════════════════════════════════════

  local peerLevel = trustMgr.getLevel(remoteAddr)

  -- BLOCKED: drop everything silently
  if peerLevel == trustMgr.LEVEL.BLOCKED then
    if log then log.debug("net", "Dropped (BLOCKED): " .. remoteAddr:sub(1, 8)) end
    return
  end

  -- Check if this message type is allowed at this trust level
  if not trustMgr.isAllowed(remoteAddr, packet.type) then
    -- Trust requests are special: always let them through so we can
    -- show them to the user (but don't act on them)
    if packet.type == protocol.TYPE.TRUST_REQ then
      local peerHostname = packet.payload and packet.payload.hostname or nil
      trustMgr.addPendingRequest(remoteAddr, peerHostname)
      -- Notify listeners about the request
      dispatchToListeners(protocol.TYPE.TRUST_REQ, packet, remoteAddr)
      return
    end

    -- Only send DENY to peers we already acknowledge (KNOWN+).
    -- Sending DENY to UNKNOWN peers would reveal that TOS is running
    -- and that the packet was received, which aids reconnaissance.
    if peerLevel >= trustMgr.LEVEL.KNOWN then
      if packet.type ~= protocol.TYPE.DENY and packet.type ~= protocol.TYPE.ERROR then
        local denyPkt = protocol.deny("Insufficient trust level")
        net.send(remoteAddr, denyPkt)
      end
    end

    if log then
      log.debug("net", string.format("Denied %s from %s (level: %s)",
        packet.type, remoteAddr:sub(1, 8),
        trustMgr.levelName(peerLevel)))
    end
    return
  end

  -- ══════════════════════════════════════════════
  -- DECRYPT if payload is encrypted
  -- ══════════════════════════════════════════════

  -- #SEC M12 — refuse to honor the `enc` field on a packet from a
  -- non-TRUSTED peer. Without this gate, listeners would see the raw
  -- ciphertext as their `payload` field (because the decrypt branch
  -- below is skipped when peerLevel < TRUSTED), and any handler that
  -- happens to log or echo payload would leak ciphertext + nonce
  -- structure to whoever reads the log. Strip the marker so it can't
  -- mislead a downstream consumer either.
  if packet.enc and peerLevel < trustMgr.LEVEL.TRUSTED then
    if log then
      log.warn("net", string.format(
        "Stripping enc flag on packet from non-TRUSTED peer %s (%s)",
        remoteAddr:sub(1, 8), packet.type or "?"))
    end
    packet.enc     = nil
    packet.payload = nil  -- can't deliver garbage either
    return
  end

  if packet.enc and packet.enc ~= false and peerLevel >= trustMgr.LEVEL.TRUSTED then
    -- Internal accessor (see send-path above): receive-path is kernel-only.
    local secret   = trustMgr._internalGetSecret(remoteAddr, net._trustToken)
    local dropWhy  = nil

    -- #SEC C10 — ban XOR downgrade when AES is available. A TRUSTED peer
    -- (or an attacker spoofing one) could otherwise force the receiver
    -- onto the no-MAC software cipher. crypto.hasHardware() tells us
    -- whether we even have AES at all.
    if packet.enc == "xor" and crypto.hasHardware and crypto.hasHardware() then
      dropWhy = "refusing XOR packet on AES-capable receiver (downgrade)"
    end

    -- #SEC C10/H-1 — verify the HMAC before doing any decryption work.
    -- (type || to || algo || nonce || ciphertext) must match the
    -- secret-bound tag. packet.from is the OC-authenticated sender
    -- (overridden above) so it is not part of the tag. A missing/empty
    -- `mac` from a TRUSTED peer means an attacker is talking to us
    -- without one — drop. (Old peers without C10 will fail this check;
    -- the operator must upgrade them in lockstep.)
    if not dropWhy then
      local nonce = packet.nonce
      local mac   = packet.mac
      if type(nonce) ~= "string" or #nonce < 8 or #nonce > 64 then
        dropWhy = "missing or malformed nonce"
      elseif type(mac) ~= "string" or #mac ~= 64 then
        dropWhy = "missing or malformed MAC"
      elseif not secret then
        dropWhy = "no shared secret"
      else
        -- #SEC H-3 — epoch + seq are bound into the MAC, so they can't be
        -- stripped or rewritten by a replayer without invalidating the tag.
        local expected = crypto.hmac(secret, table.concat({
          packet.type or "", packet.to or "", packet.enc or "",
          tostring(packet.epoch or ""), tostring(packet.seq or ""),
          nonce, (packet.payload or "")
        }, "\0"))
        if not crypto.ctEquals(expected, mac) then
          dropWhy = "MAC mismatch"
        end
      end
    end

    -- #SEC H-3 — sequence freshness. A captured packet whose nonce has
    -- aged out of the ring below would otherwise replay; requiring the
    -- per-sender sequence to strictly increase (within its epoch) closes
    -- that. epoch+seq are MAC-bound, so they're trustworthy here.
    if not dropWhy then
      net._recvSeq = net._recvSeq or {}
      local okSeq, seqWhy = seqFreshnessCheck(
        net._recvSeq, remoteAddr, packet.epoch, tonumber(packet.seq))
      if not okSeq then dropWhy = seqWhy end
    end

    -- #SEC C10 — per-peer nonce replay window. A captured packet replayed
    -- after the original has already been processed must not fire the
    -- handler again. We use a per-peer ring buffer of the last N nonces.
    -- This remains as a second layer behind the H-3 sequence check.
    if not dropWhy then
      net._seenNonces = net._seenNonces or {}
      local peerSeen = net._seenNonces[remoteAddr]
      if not peerSeen then
        -- #SEC L — bound the number of distinct peers tracked. The per-peer
        -- ring is already capped, but without this an attacker spoofing
        -- many source addresses could grow this map without limit. Evict
        -- the oldest peer once the cap is hit (same policy as _recvSeq).
        net._seenNonces.__order = net._seenNonces.__order or {}
        local ord = net._seenNonces.__order
        if #ord >= SEQ_MAX_PEERS then
          local victim = table.remove(ord, 1)
          if victim ~= nil then net._seenNonces[victim] = nil end
        end
        ord[#ord + 1] = remoteAddr
        peerSeen = { order = {}, set = {} }
        net._seenNonces[remoteAddr] = peerSeen
      end
      if peerSeen.set[packet.nonce] then
        dropWhy = "replayed nonce"
      else
        peerSeen.set[packet.nonce] = true
        peerSeen.order[#peerSeen.order + 1] = packet.nonce
        local NONCE_WINDOW = 512
        if #peerSeen.order > NONCE_WINDOW then
          local stale = table.remove(peerSeen.order, 1)
          peerSeen.set[stale] = nil
        end
      end
    end

    if not dropWhy then
      if type(packet.payload) ~= "string" then
        dropWhy = "enc flag set but payload is not ciphertext"
      else
        local decrypted = crypto.decrypt(packet.payload, secret, packet.enc)
        if not decrypted then
          dropWhy = "decryption failed (tampered or wrong key)"
        else
          local parsed = protocol.deserialize(decrypted)
          if not parsed then
            dropWhy = "decrypted payload failed to deserialize"
          else
            packet.payload = parsed
            packet.enc = false  -- Mark as decrypted
          end
        end
      end
    end
    -- #46 — If we could not authenticate/decrypt a packet that claimed to
    -- be encrypted from a TRUSTED peer, drop it. Silently continuing with
    -- garbage ciphertext as the payload would let a MITM (or a peer whose
    -- secret has drifted) feed unauthenticated data to handlers.
    if dropWhy then
      if log then
        log.warn("net", string.format(
          "Dropped enc packet from %s (%s): %s",
          remoteAddr:sub(1, 8), packet.type or "?", dropWhy))
      end
      return
    end
  end

  -- ══════════════════════════════════════════════
  -- BUILT-IN HANDLERS (automatic responses)
  -- ══════════════════════════════════════════════

  if packet.type == protocol.TYPE.PING then
    -- Always respond to pings (UNKNOWN+ level).
    --
    -- #SEC — Pong stays minimal. Hostname is intentionally NOT included
    -- here; protocol.pong()'s comment is the contract. A KNOWN+ peer
    -- learns our hostname via the HELLO handshake below, which IS gated
    -- on trust level. Adding hostname to the pong leaks it to any random
    -- modem on the network that sends a single PING.
    --
    -- Device type is borderline (a port scan would reveal it indirectly
    -- on most networks) but cheap to gate on KNOWN+ as well, so we do.
    local pong = protocol.pong()
    if config and peerLevel >= trustMgr.LEVEL.KNOWN then
      pong.payload = pong.payload or {}
      pong.payload.device = config.deviceType()
    end
    net.send(remoteAddr, pong)
    -- Record the pinger as a discovered peer
    net._recordPeer(remoteAddr, packet.payload)
    return
  end

  if packet.type == protocol.TYPE.PONG then
    -- Record the responder
    net._recordPeer(remoteAddr, packet.payload)
    -- Fall through to dispatch so scan() listener gets it
  end

  if packet.type == protocol.TYPE.HELLO and peerLevel >= trustMgr.LEVEL.KNOWN then
    -- Respond with our hostname (only to KNOWN+ peers)
    local peer = trustMgr.getPeer(remoteAddr)
    if peer and packet.payload then
      peer.hostname = packet.payload.hostname
    end
    local ack = protocol.helloAck(hostname, _G._TOS.version)
    net.send(remoteAddr, ack)
    -- Fall through to listeners too
  end

  if packet.type == protocol.TYPE.HELLO_ACK and peerLevel >= trustMgr.LEVEL.KNOWN then
    -- Store their hostname
    local peer = trustMgr.getPeer(remoteAddr)
    if peer and packet.payload then
      peer.hostname = packet.payload.hostname
    end
  end

  -- ══════════════════════════════════════════════
  -- CHALLENGE-RESPONSE
  -- ══════════════════════════════════════════════
  -- Threat model: a TRUSTED peer's modem moved to an attacker's
  -- machine. Modem addresses can't be spoofed at the OC level, so
  -- the address-based trust check catches packets originating from
  -- elsewhere — but a physically-relocated modem keeps its address
  -- AND would be trusted indefinitely. Challenge-response binds
  -- trust to possession of the shared secret instead of just the
  -- modem address: the proof is HMAC(secret, nonce), the secret
  -- never crosses the wire, and a fresh nonce per challenge stops
  -- replay.
  --
  -- Server side (this branch): when we receive a CHALLENGE from a
  -- TRUSTED peer with whom we share a secret, compute the HMAC
  -- proof and send it back. We DON'T respond to CHALLENGE from
  -- non-TRUSTED peers — answering would let an attacker probe
  -- whether we have a secret with a given address (and feed an
  -- HMAC oracle of arbitrary nonces, which is useful for some
  -- secret-recovery attacks against weak HMAC implementations).
  if packet.type == protocol.TYPE.CHALLENGE then
    if peerLevel < trustMgr.LEVEL.TRUSTED then return end
    -- #SEC H16 — per-peer rate limit on the HMAC oracle. The CHALLENGE
    -- handler signs an attacker-chosen nonce for any TRUSTED peer; an
    -- attacker who is on the secret-set (or who has rotated through
    -- onto it) can hammer this endpoint for an arbitrarily large set
    -- of HMAC inputs. Cap at 1 per second per peer.
    net._challengeRate = net._challengeRate or {}
    local now = computer.uptime()
    local last = net._challengeRate[remoteAddr] or 0
    if now - last < 1.0 then
      if log then log.warn("net", "CHALLENGE throttled from " .. remoteAddr:sub(1,8)) end
      return
    end
    net._challengeRate[remoteAddr] = now

    local secret = trustMgr._internalGetSecret and
                   trustMgr._internalGetSecret(remoteAddr, net._trustToken) or nil
    if not secret or secret == "" then return end
    local nonce = packet.payload and packet.payload.nonce
    -- Nonce length bounds: too short enables rainbow tables, too
    -- long is a memory-amplification vector. 8..64 bytes covers
    -- every legitimate caller (verifyPeer below uses 16).
    if type(nonce) ~= "string" or #nonce < 8 or #nonce > 64 then
      if log then log.warn("net", "Bad challenge nonce from " .. remoteAddr:sub(1,8)) end
      return
    end
    local crypto = require("kernel.crypto")
    -- #SEC H16 — mix in a server-chosen nonce so the peer can't pick
    -- every byte of the HMAC input. The proof signs (clientNonce ||
    -- serverNonce); both are returned so the peer can verify the same
    -- combination they signed. This bounds the oracle: an attacker can
    -- learn HMAC(secret, x || y) only when y is our server nonce.
    local serverNonce = crypto.salt(16)
    local ok, proof = pcall(crypto.hmac, secret, nonce .. "|" .. serverNonce)
    if not ok or not proof then return end
    local resp = protocol.challengeResponse(nonce, proof)
    resp.payload = resp.payload or {}
    resp.payload.serverNonce = serverNonce
    net.send(remoteAddr, resp)
    return
  end

  -- ══════════════════════════════════════════════
  -- DISPATCH to registered listeners
  -- ══════════════════════════════════════════════

  dispatchToListeners(packet.type, packet, remoteAddr)
end

-- ============================================================
-- Message dispatch
-- ============================================================

-- #MEM — transfer/remote no longer load at boot; each loads on its FIRST
-- inbound packet (its self-init registers the real listener, then normal
-- dispatch below delivers this same packet to it). Keyed by wire type via
-- the protocol constants; built on first use because `protocol` is only
-- set once net.init has run. One load attempt per type per boot.
local lazyInbound = nil
local function loadLazyInbound(msgType)
  if lazyInbound == nil then
    if not protocol then return end
    lazyInbound = {
      [protocol.TYPE.FILE_REQ]    = "kernel.net.transfer",
      [protocol.TYPE.REMOTE_EXEC] = "kernel.net.remote",
    }
  end
  local modname = lazyInbound[msgType]
  if not modname then return end
  lazyInbound[msgType] = nil
  local okM, err = pcall(require, modname)
  if not okM and log then
    log.warn("net", "Lazy handler load failed (" .. modname .. "): " .. tostring(err))
  end
end

dispatchToListeners = function(msgType, packet, from)
  if not listeners[msgType] then
    loadLazyInbound(msgType)
  end
  if listeners[msgType] then
    for _, entry in ipairs(listeners[msgType]) do
      local ok, err = pcall(entry.cb, packet, from)
      if not ok and log then
        log.warn("net", "Listener error for " .. tostring(msgType) .. ": " .. tostring(err))
      end
    end
  end
  -- Also dispatch to catch-all listeners
  if listeners["*"] then
    for _, entry in ipairs(listeners["*"]) do
      local ok, err = pcall(entry.cb, packet, from)
      if not ok and log then
        log.warn("net", "Catch-all listener error: " .. tostring(err))
      end
    end
  end
end

-- #MEM — service arm-state for the lazily-loaded daemon backends.
-- fileshare/rshd used to require() transfer/remote at start() just to flip
-- their enable gates, which forced both modules into RAM on every boot.
-- The services now record the desired state HERE; if the backend is
-- already loaded it is toggled immediately, otherwise its self-init reads
-- the flag when the first packet (or outbound call) loads it. Fail-closed:
-- an unset flag reads as disabled, the same default the modules ship with.
local armFlags = {}
local ARM_BACKENDS = {
  fileshare = "kernel.net.transfer",
  rshd      = "kernel.net.remote",
}
function net.setServiceArm(name, on)
  armFlags[name] = on and true or false
  local modname = ARM_BACKENDS[name]
  if modname and package and package.loaded and package.loaded[modname] then
    local m = package.loaded[modname]
    if m and m.setEnabled then m.setEnabled(on and true or false) end
  end
end
function net.getServiceArm(name)
  return armFlags[name] == true
end

--- Register a listener for a specific message type
-- @return number: Listener ID for removal via net.off()
local listenerNextID = 1
function net.on(msgType, callback)
  if not listeners[msgType] then
    listeners[msgType] = {}
  end
  local id = listenerNextID
  listenerNextID = listenerNextID + 1
  listeners[msgType][#listeners[msgType] + 1] = { cb = callback, id = id }
  return id
end

--- Remove a listener by message type + ID
function net.off(msgType, id)
  if not listeners[msgType] then return false end
  for i, entry in ipairs(listeners[msgType]) do
    if entry.id == id then
      table.remove(listeners[msgType], i)
      return true
    end
  end
  return false
end

-- ============================================================
-- Request / reply helpers
-- ============================================================
-- Common pattern across usr/bin/{ssh,share}, kernel.net.remote, and
-- kernel.net.transfer: register one or more peer-filtered listeners,
-- send a request packet, wait for a reply, then tear the listeners
-- down. Each call site previously hand-rolled the loop and got a
-- subtle detail wrong at least once (callback arg order, registration
-- timing race, or partial cleanup on early send-failure). These three
-- helpers consolidate the moving parts so future call sites don't
-- repeat those mistakes.

--- Register a one-shot listener that fires ONLY for `msgType` packets
--- received from `addr`. Subsequent packets (duplicates, late arrivals,
--- spoofs from other peers) are silently ignored — but the listener
--- itself stays registered until removed via net.off / net.offAll.
---
--- The internal `fired` flag does the de-duplication; we don't
--- self-deregister inside the callback because dispatchToListeners
--- iterates with ipairs() and a mid-iteration table.remove would
--- skip or repeat sibling listeners.
---
--- @return number  listener id (pass to net.off or net.offAll)
function net.onceFrom(msgType, addr, callback)
  local fired = false
  return net.on(msgType, function(packet, fromAddr)
    if fired or fromAddr ~= addr then return end
    fired = true
    callback(packet, fromAddr)
  end)
end

--- Bulk-remove a set of listeners. Pass an array of
--- { type = msgType, id = listenerID } entries — the same shape the
--- request-reply call sites collect as they install listeners.
---
--- Safer than three or four sequential net.off() calls because partial
--- cleanup on an early send-failure leaves dangling listeners that
--- fire on later, unrelated traffic.
function net.offAll(entries)
  if type(entries) ~= "table" then return end
  for _, e in ipairs(entries) do
    if type(e) == "table" and e.type and e.id then
      net.off(e.type, e.id)
    end
  end
end

--- Pump the event loop until `predicate()` returns truthy or `timeout`
--- seconds elapse. Returns true on success, false on timeout.
---
--- Why three branches: from a process coroutine (ssh, share, rsh CLI)
--- we want to yield so the kernel scheduler can route signals back to
--- us; from the kernel main loop or a non-coroutine context we use
--- event.pull which dispatches timers + listeners on each tick;
--- without an event module (early boot, emergency shell) we fall back
--- to the raw OC primitive.
function net.waitFor(predicate, timeout)
  local deadline = computer.uptime() + (timeout or 10)
  while not predicate() do
    if computer.uptime() >= deadline then return false end
    if coroutine.isyieldable and coroutine.isyieldable() then
      coroutine.yield()
    elseif event and event.pull then
      event.pull(0.5)
    else
      computer.pullSignal(0.5)
    end
  end
  return true
end

-- ============================================================
-- Challenge-response peer verification
-- ============================================================
-- See the CHALLENGE incoming-handler for the threat model. This
-- is the client side: send a fresh nonce, expect HMAC(secret, nonce)
-- back, compare with our locally-computed expected value.
--
-- A short positive cache (`verifyCache`) keeps verification cheap
-- when callers do back-to-back sensitive sends — without it, every
-- REMOTE_EXEC would pay a round-trip. 60 seconds is short enough
-- that a stolen-modem window after legitimate use is small, and
-- long enough that batches of operations don't all challenge.

local verifyCache = {}  -- addr → expiry timestamp (computer.uptime)
local VERIFY_CACHE_TTL = 60

-- Constant-time string compare. Prefers the crypto module's
-- constant-time primitive; the inline fallback is itself
-- constant-time over max(#a,#b) so a missing crypto module never
-- silently reintroduces an early-exit timing leak in proof checks.
local function safeEquals(a, b, crypto)
  if crypto and crypto.ctEquals then return crypto.ctEquals(a, b) end
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local la, lb = #a, #b
  local n = la > lb and la or lb
  local diff = la ~ lb
  for i = 1, n do
    local ba = i <= la and a:byte(i) or 0
    local bb = i <= lb and b:byte(i) or 0
    diff = diff | (ba ~ bb)
  end
  return diff == 0
end

--- Verify a peer's identity via challenge-response.
---
--- Sends CHALLENGE, awaits CHALLENGE_RES, validates the HMAC
--- proof. Returns true if the peer demonstrably holds the shared
--- secret; false + reason otherwise.
---
--- Pre-conditions:
---   • Peer must be at TRUSTED level (lower trust = no shared
---     secret to verify against).
---   • A shared secret must be set with the peer.
---
--- Use `force = true` to bypass the positive cache.
function net.verifyPeer(addr, timeout, force)
  if not protocol then return false, "protocol unavailable" end
  if not addr or addr == "" then return false, "no address" end
  if not trustMgr then return false, "trust manager unavailable" end

  -- Cache hit fast-path
  if not force then
    local exp = verifyCache[addr]
    if exp and computer.uptime() < exp then return true end
  end

  if trustMgr.getLevel(addr) < trustMgr.LEVEL.TRUSTED then
    return false, "peer not trusted"
  end
  local secret = trustMgr._internalGetSecret and
                 trustMgr._internalGetSecret(addr, net._trustToken) or nil
  if not secret or secret == "" then
    return false, "no shared secret with peer"
  end

  local crypto = require("kernel.crypto")
  -- Fresh nonce per challenge — replay protection. salt() pulls
  -- from the entropy-mixed kernel RNG. Fall back to a less-good
  -- source only if crypto.salt is unavailable; in that case the
  -- challenge is best-effort.
  local nonce
  if crypto.salt then
    nonce = crypto.salt(16)
  else
    -- Best-effort: 16 bytes from math.random. Marked as such so
    -- a future audit can find this branch; in practice crypto.salt
    -- is always present.
    local parts = {}
    for i = 1, 16 do parts[i] = string.char(math.random(0, 255)) end
    nonce = table.concat(parts)
  end

  -- #SEC H16/CR-2 — also capture the server-chosen nonce that the
  -- responder mixes into the HMAC input. The proof signs
  -- (clientNonce || "|" || serverNonce); we verify the same
  -- composite. A server nonce is MANDATORY: accepting an empty one
  -- would let an attacker who can produce HMAC(secret, clientNonce)
  -- for a chosen client nonce pass verification, collapsing the
  -- oracle bound. Every TOS responder sends one (see CHALLENGE
  -- handler above); there is no pre-H16 compatibility path.
  local got, gotProof, gotServerNonce = false, nil, nil
  local lid = net.onceFrom(protocol.TYPE.CHALLENGE_RES, addr, function(pkt)
    if pkt.payload and pkt.payload.nonce == nonce then
      gotProof = pkt.payload.proof
      gotServerNonce = pkt.payload.serverNonce
      got = true
    end
  end)

  local sent, sErr = net.send(addr, protocol.challenge(nonce))
  if not sent then
    net.off(protocol.TYPE.CHALLENGE_RES, lid)
    return false, "send failed: " .. tostring(sErr)
  end

  net.waitFor(function() return got end, timeout or 5)
  net.off(protocol.TYPE.CHALLENGE_RES, lid)

  if not got then return false, "challenge timeout" end

  -- Server nonce is mandatory and length-bounded (8..64, matching the
  -- CHALLENGE handler's own bounds); reject empty/absent outright.
  if type(gotServerNonce) ~= "string"
     or #gotServerNonce < 8 or #gotServerNonce > 64 then
    return false, "bad server nonce"
  end

  local expected
  do
    local toSign = nonce .. "|" .. gotServerNonce
    local ok, p = pcall(crypto.hmac, secret, toSign)
    if not ok or not p then return false, "hmac failed" end
    expected = p
  end

  if not safeEquals(gotProof, expected, crypto) then
    if log then
      log.warn("net", "Challenge proof mismatch from " .. addr:sub(1,8))
    end
    return false, "bad proof"
  end

  verifyCache[addr] = computer.uptime() + VERIFY_CACHE_TTL
  return true
end

--- Invalidate the challenge-response cache for one peer (or all
--- peers if `addr` is nil). Use after a peer's secret rotates,
--- after a suspected key compromise, or to force re-verification
--- before a particularly sensitive operation.
function net.invalidateVerification(addr)
  if addr then verifyCache[addr] = nil
  else verifyCache = {} end
end

-- ============================================================
-- Discovery (find other TOS machines)
-- ============================================================

--- Broadcast a ping to discover other TOS machines
function net.discover()
  local ping = protocol.ping()
  -- Single-port mode: net.broadcast falls back to listenPort when
  -- broadcastPort is nil. Pass nil through explicitly so the
  -- single-port case isn't accidentally bypassed.
  return net.broadcast(ping, broadcastPort)
end

--- Send hello to a known peer (exchange hostnames)
function net.hello(address)
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.KNOWN then
    return false, "Peer must be KNOWN to exchange hellos"
  end
  local pkt = protocol.hello(hostname, _G._TOS.version)
  return net.send(address, pkt)
end

-- ============================================================
-- Secure messaging (TRUSTED peers only)
-- ============================================================

--- Send an encrypted message to a trusted peer
function net.sendMessage(address, text)
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return false, "Peer must be TRUSTED to send messages"
  end
  local pkt = protocol.message(text, encryptComms)
  return net.send(address, pkt)
end

--- Request trust from a remote machine
function net.requestTrust(address)
  local pkt = protocol.trustRequest(hostname)
  return net.send(address, pkt)
end

-- ============================================================
-- High-level API (used by shell commands)
-- ============================================================

--- Get the trust manager instance
function net.getTrust()
  return trustMgr
end

-- ============================================================
-- Peer Discovery (Phase 8)
-- ============================================================

-- Persistent discovered-peer table, populated by pong responses
-- and the optional discoveryd service. Entries:
--   { addr, lastSeen, device, hostname, trust }
local discoveredPeers = {}

--- Internal: record a peer from a pong response.
function net._recordPeer(addr, payload)
  local now = computer.uptime()
  local trust = trustMgr and trustMgr.getLevel(addr) or 0
  local hostname2 = nil
  local device2 = nil
  if type(payload) == "table" then
    hostname2 = payload.hostname
    device2   = payload.device
  end
  -- Merge with trust manager data if available
  if trustMgr then
    local peer = trustMgr.getPeer(addr)
    if peer then
      hostname2 = hostname2 or peer.hostname
    end
  end
  discoveredPeers[addr] = {
    addr      = addr,
    lastSeen  = now,
    hostname  = hostname2,
    device    = device2,
    trust     = trust,
  }
end

--- Return the current discovered-peer table as a sorted list.
function net.peers()
  local result = {}
  for _, peer in pairs(discoveredPeers) do
    result[#result + 1] = peer
  end
  table.sort(result, function(a, b) return (a.hostname or "") < (b.hostname or "") end)
  return result
end

--- Look up a specific peer by address or hostname.
function net.findPeer(query)
  -- Exact address match
  if discoveredPeers[query] then return discoveredPeers[query] end
  -- Hostname search
  for _, peer in pairs(discoveredPeers) do
    if peer.hostname and peer.hostname == query then return peer end
  end
  -- Partial address prefix
  for addr, peer in pairs(discoveredPeers) do
    if addr:sub(1, #query) == query then return peer end
  end
  return nil
end

--- Active scan: broadcast a ping, collect pong responses for `timeout`
--- seconds, return the peers found in this scan.
function net.scan(timeout)
  timeout = timeout or 3
  local results = {}
  local listenId = net.on(protocol.TYPE.PONG, function(packet, remoteAddr)
    net._recordPeer(remoteAddr, packet.payload)
    results[remoteAddr] = discoveredPeers[remoteAddr]
  end)
  net.discover()
  -- Wait for responses (cooperative — yields)
  local deadline = computer.uptime() + timeout
  while computer.uptime() < deadline do
    if coroutine.isyieldable and coroutine.isyieldable() then
      coroutine.yield()
    else
      computer.pullSignal(0.5)
    end
  end
  net.off(protocol.TYPE.PONG, listenId)
  local list = {}
  for _, p in pairs(results) do list[#list + 1] = p end
  return list
end

--- Get the protocol module
function net.getProtocol()
  return protocol
end

--- Get network status summary
function net.status()
  local stats = trustMgr.stats()
  return {
    available    = net.isAvailable(),
    address      = myAddr and (myAddr:sub(1, 8) .. "...") or "none",
    fullAddress  = myAddr,
    hostname     = hostname,
    listenPort   = listenPort,
    encrypted    = encryptComms,
    hasModem     = modem ~= nil,
    hasTunnel    = tunnel ~= nil,
    peers        = stats,
  }
end

function net.shutdown()
  running = false
  if modem then
    pcall(function()
      modem.close(listenPort)
      if broadcastPort then modem.close(broadcastPort) end
    end)
  end
  if log then log.info("net", "Network shut down") end
end

return net
