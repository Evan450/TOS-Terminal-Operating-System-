local component = require("component")
local computer = require("computer")

local net = {}

local protocol = nil
local trustMgr = nil
local crypto   = nil

local SEQ_RETIRE_MAX = 8
local SEQ_MAX_PEERS  = 256

local function seqFreshnessCheck(holder, key, epoch, seq)
  if type(epoch) ~= "string" or type(seq) ~= "number" then
    return true
  end
  local rec = holder[key]
  if not rec then

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

local modem    = nil
local tunnel   = nil
local myAddr   = nil

local modems   = {}

local listenPort    = 42
local broadcastPort = nil
local encryptComms  = true
local hostname      = "tos"

local running   = false
local listeners = {}

local log    = nil
local config = nil
local event  = nil

local dispatchToListeners

function net.init(modules)
  log    = modules.log
  config = modules.config
  event  = modules.event

  protocol = require("kernel.net.protocol")
  trustMgr = require("kernel.net.trust")
  crypto   = require("kernel.crypto")

  trustMgr.init({
    fs     = modules.fs,
    crypto = crypto,
    log    = log,
    config = config,
  })

  net._trustToken = trustMgr.getBootstrapToken and trustMgr.getBootstrapToken() or nil

  if config then
    listenPort    = config.get("listenPort") or 42

    local bp = config.get("broadcastPort")
    broadcastPort = (type(bp) == "number" and bp ~= listenPort) and bp or nil
    encryptComms  = config.get("encryptComms") ~= false
    hostname      = config.get("hostname") or "tos"
  end

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

  if event then
    event.on("modem_message", function(_, localAddr, remoteAddr, port, dist, rawData)
      net.handleIncoming(remoteAddr, port, dist, rawData)

      net.meshTick()
    end, "net")
  end

  running = true

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

function net.getChatPair()
  return net._chatpair
end

function net.meshAvailable()
  return net._meshctl ~= nil
end

function net.meshSend(opts)
  if not net._meshctl then return nil, "mesh not available (no network?)" end
  return net._meshctl:send(opts or {})
end

function net.meshOn(svc, handler)
  if not net._meshctl then return false, "mesh not available" end
  net._meshctl:on(svc, handler)
  return true
end

function net.meshOff(svc)
  if net._meshctl then net._meshctl:off(svc) end
end

function net.meshHasHandler(svc)
  return net._meshctl ~= nil and net._meshctl:hasHandler(svc)
end

function net.meshPending()
  return net._meshctl and net._meshctl:pending() or 0
end

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

function net.modemCount()
  return #modems
end

local PUBLIC_PACKET_TYPES = {
  ping = true, pong = true,
  hello = true, hello_ack = true,
  challenge = true, chall_res = true,
  deny = true,

  ch_pair_init = true, ch_pair_conf = true,

  cl_pair_init = true, cl_pair_conf = true,
}

function net.send(address, packet, port)
  if not modem and not tunnel then return false, "No modem" end

  port = port or listenPort

  packet.from = myAddr

  packet.to = address

  local peerLevel = trustMgr.getLevel(address)
  local isPublic = PUBLIC_PACKET_TYPES[packet.type]
  if encryptComms and peerLevel >= trustMgr.LEVEL.TRUSTED and not isPublic then

    local secret = trustMgr._internalGetSecret(address, net._trustToken)
    if secret and packet.payload then
      local plaintext = protocol.serialize(packet.payload)
      local encrypted, method = crypto.encrypt(plaintext, secret)
      packet.payload = encrypted
      packet.enc = method

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

      if log then
        log.warn("net", string.format(
          "Refusing plaintext send to TRUSTED peer %s (%s): no shared secret; " ..
          "run 'net trust gen %s' as admin to provision one",
          address:sub(1, 8), packet.type or "?", address:sub(1, 8)))
      end
      return false, "TRUSTED peer has no shared secret; refusing plaintext send"
    end
  end

  local data = protocol.serialize(packet)
  if #data > protocol.MAX_SIZE then
    return false, "Packet too large"
  end

  local ok, err2
  if modem then
    ok, err2 = pcall(modem.send, address, port, data)
  else

    ok, err2 = pcall(tunnel.send, data)
  end
  if not ok then
    return false, "Send failed: " .. tostring(err2)
  end

  return true
end

function net.broadcast(packet, port)
  if not modem and not tunnel then return false, "No modem" end

  port = port or broadcastPort or listenPort

  packet.from = myAddr
  local data = protocol.serialize(packet)
  local anyOk = false
  for _, m in ipairs(modems) do
    local ok2 = pcall(m.proxy.broadcast, port, data)
    anyOk = anyOk or ok2
  end

  if tunnel then
    local ok2 = pcall(tunnel.send, data)
    anyOk = anyOk or ok2
  end
  if not anyOk then return false, "Broadcast failed on all NICs" end
  return true
end

function net.handleIncoming(remoteAddr, port, distance, rawData)
  if not running then return end

  local packet, err = protocol.deserialize(rawData)
  if not packet then

    return
  end

  local valid, verr = protocol.validate(packet)
  if not valid then return end

  trustMgr.seen(remoteAddr)
  packet.from = remoteAddr
  packet._distance = distance

  local peerLevel = trustMgr.getLevel(remoteAddr)

  if peerLevel == trustMgr.LEVEL.BLOCKED then
    if log then log.debug("net", "Dropped (BLOCKED): " .. remoteAddr:sub(1, 8)) end
    return
  end

  if not trustMgr.isAllowed(remoteAddr, packet.type) then

    if packet.type == protocol.TYPE.TRUST_REQ then
      local peerHostname = packet.payload and packet.payload.hostname or nil
      trustMgr.addPendingRequest(remoteAddr, peerHostname)

      dispatchToListeners(protocol.TYPE.TRUST_REQ, packet, remoteAddr)
      return
    end

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

  if packet.enc and peerLevel < trustMgr.LEVEL.TRUSTED then
    if log then
      log.warn("net", string.format(
        "Stripping enc flag on packet from non-TRUSTED peer %s (%s)",
        remoteAddr:sub(1, 8), packet.type or "?"))
    end
    packet.enc     = nil
    packet.payload = nil
    return
  end

  if packet.enc and packet.enc ~= false and peerLevel >= trustMgr.LEVEL.TRUSTED then

    local secret   = trustMgr._internalGetSecret(remoteAddr, net._trustToken)
    local dropWhy  = nil

    if packet.enc == "xor" and crypto.hasHardware and crypto.hasHardware() then
      dropWhy = "refusing XOR packet on AES-capable receiver (downgrade)"
    end

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

    if not dropWhy then
      net._recvSeq = net._recvSeq or {}
      local okSeq, seqWhy = seqFreshnessCheck(
        net._recvSeq, remoteAddr, packet.epoch, tonumber(packet.seq))
      if not okSeq then dropWhy = seqWhy end
    end

    if not dropWhy then
      net._seenNonces = net._seenNonces or {}
      local peerSeen = net._seenNonces[remoteAddr]
      if not peerSeen then

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
            packet.enc = false
          end
        end
      end
    end

    if dropWhy then
      if log then
        log.warn("net", string.format(
          "Dropped enc packet from %s (%s): %s",
          remoteAddr:sub(1, 8), packet.type or "?", dropWhy))
      end
      return
    end
  end

  if packet.type == protocol.TYPE.PING then

    local pong = protocol.pong()
    if config and peerLevel >= trustMgr.LEVEL.KNOWN then
      pong.payload = pong.payload or {}
      pong.payload.device = config.deviceType()
    end
    net.send(remoteAddr, pong)

    net._recordPeer(remoteAddr, packet.payload)
    return
  end

  if packet.type == protocol.TYPE.PONG then

    net._recordPeer(remoteAddr, packet.payload)

  end

  if packet.type == protocol.TYPE.HELLO and peerLevel >= trustMgr.LEVEL.KNOWN then

    local peer = trustMgr.getPeer(remoteAddr)
    if peer and packet.payload then
      peer.hostname = packet.payload.hostname
    end
    local ack = protocol.helloAck(hostname, _G._TOS.version)
    net.send(remoteAddr, ack)

  end

  if packet.type == protocol.TYPE.HELLO_ACK and peerLevel >= trustMgr.LEVEL.KNOWN then

    local peer = trustMgr.getPeer(remoteAddr)
    if peer and packet.payload then
      peer.hostname = packet.payload.hostname
    end
  end

  if packet.type == protocol.TYPE.CHALLENGE then
    if peerLevel < trustMgr.LEVEL.TRUSTED then return end

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

    if type(nonce) ~= "string" or #nonce < 8 or #nonce > 64 then
      if log then log.warn("net", "Bad challenge nonce from " .. remoteAddr:sub(1,8)) end
      return
    end
    local crypto = require("kernel.crypto")

    local serverNonce = crypto.salt(16)
    local ok, proof = pcall(crypto.hmac, secret, nonce .. "|" .. serverNonce)
    if not ok or not proof then return end
    local resp = protocol.challengeResponse(nonce, proof)
    resp.payload = resp.payload or {}
    resp.payload.serverNonce = serverNonce
    net.send(remoteAddr, resp)
    return
  end

  dispatchToListeners(packet.type, packet, remoteAddr)
end

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

  if listeners["*"] then
    for _, entry in ipairs(listeners["*"]) do
      local ok, err = pcall(entry.cb, packet, from)
      if not ok and log then
        log.warn("net", "Catch-all listener error: " .. tostring(err))
      end
    end
  end
end

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

function net.onceFrom(msgType, addr, callback)
  local fired = false
  return net.on(msgType, function(packet, fromAddr)
    if fired or fromAddr ~= addr then return end
    fired = true
    callback(packet, fromAddr)
  end)
end

function net.offAll(entries)
  if type(entries) ~= "table" then return end
  for _, e in ipairs(entries) do
    if type(e) == "table" and e.type and e.id then
      net.off(e.type, e.id)
    end
  end
end

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

local verifyCache = {}
local VERIFY_CACHE_TTL = 60

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

function net.verifyPeer(addr, timeout, force)
  if not protocol then return false, "protocol unavailable" end
  if not addr or addr == "" then return false, "no address" end
  if not trustMgr then return false, "trust manager unavailable" end

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

  local nonce
  if crypto.salt then
    nonce = crypto.salt(16)
  else

    local parts = {}
    for i = 1, 16 do parts[i] = string.char(math.random(0, 255)) end
    nonce = table.concat(parts)
  end

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

function net.invalidateVerification(addr)
  if addr then verifyCache[addr] = nil
  else verifyCache = {} end
end

function net.discover()
  local ping = protocol.ping()

  return net.broadcast(ping, broadcastPort)
end

function net.hello(address)
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.KNOWN then
    return false, "Peer must be KNOWN to exchange hellos"
  end
  local pkt = protocol.hello(hostname, _G._TOS.version)
  return net.send(address, pkt)
end

function net.sendMessage(address, text)
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return false, "Peer must be TRUSTED to send messages"
  end
  local pkt = protocol.message(text, encryptComms)
  return net.send(address, pkt)
end

function net.requestTrust(address)
  local pkt = protocol.trustRequest(hostname)
  return net.send(address, pkt)
end

function net.getTrust()
  return trustMgr
end

local discoveredPeers = {}

function net._recordPeer(addr, payload)
  local now = computer.uptime()
  local trust = trustMgr and trustMgr.getLevel(addr) or 0
  local hostname2 = nil
  local device2 = nil
  if type(payload) == "table" then
    hostname2 = payload.hostname
    device2   = payload.device
  end

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

function net.peers()
  local result = {}
  for _, peer in pairs(discoveredPeers) do
    result[#result + 1] = peer
  end
  table.sort(result, function(a, b) return (a.hostname or "") < (b.hostname or "") end)
  return result
end

function net.findPeer(query)

  if discoveredPeers[query] then return discoveredPeers[query] end

  for _, peer in pairs(discoveredPeers) do
    if peer.hostname and peer.hostname == query then return peer end
  end

  for addr, peer in pairs(discoveredPeers) do
    if addr:sub(1, #query) == query then return peer end
  end
  return nil
end

function net.scan(timeout)
  timeout = timeout or 3
  local results = {}
  local listenId = net.on(protocol.TYPE.PONG, function(packet, remoteAddr)
    net._recordPeer(remoteAddr, packet.payload)
    results[remoteAddr] = discoveredPeers[remoteAddr]
  end)
  net.discover()

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

function net.getProtocol()
  return protocol
end

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
