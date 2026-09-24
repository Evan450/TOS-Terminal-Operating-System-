local computer = require("computer")

local chatpair = {}

local crypto    = nil
local protocol  = nil
local trustMod  = nil
local netMod    = nil
local log       = nil
local LOG_TAG   = "chatpair"

local PAIRING_WINDOW_SEC = 300
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
local CODE_LEN = 24
local DOMAIN = "tos-chat-pair-v1"

local _window = nil

local PAIR_ACTOR = "root"
local TIER_ROOT  = 3

function chatpair.init(opts)
  crypto   = opts and opts.crypto    or require("kernel.crypto")
  protocol = opts and opts.protocol  or require("kernel.net.protocol")
  trustMod = opts and opts.trust     or nil
  log      = opts and opts.log       or nil

  netMod   = opts and opts.net       or nil
end

local function getNet()
  if netMod then return netMod end
  local ok, m = pcall(require, "kernel.net")
  if ok then netMod = m end
  return netMod
end

--! crypto.salt returns CHARACTERS, uniform over its 62-symbol alphabet --
--! not uniform bytes. The byte-level rejection sampling below was written
--! for bytes: over the 62 ASCII codes that salt actually emits, `b % 31`
--! reaches only 27 of the 31 code characters, unevenly, so a code carried
--! about 113 bits rather than the ~119 the header states. A salt symbol's
--! POSITION is uniform over 62 = 2 * 31, so position mod 31 is exact. The
--! byte path stays for any source that does hand back raw bytes.
local SALT62 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function generateCode()
  local out, n = {}, #CODE_ALPHABET
  while #out < CODE_LEN do
    local raw = crypto.salt(64)
    for i = 1, #raw do
      if #out >= CODE_LEN then break end
      local ch = raw:sub(i, i)
      local pos = SALT62:find(ch, 1, true)
      local idx
      if pos then
        idx = ((pos - 1) % n) + 1
      else
        local b = raw:byte(i)
        if b < 248 then idx = (b % n) + 1 end
      end
      if idx then out[#out + 1] = CODE_ALPHABET:sub(idx, idx) end
    end
  end
  return table.concat(out)
end

local function deriveSecret(code)

  return crypto.hashPassword(code, DOMAIN)
end

local function macForCode(secret, addrA, addrB, ts)
  local lo, hi = tostring(addrA or ""), tostring(addrB or "")
  if lo > hi then lo, hi = hi, lo end
  return crypto.hmac(secret, lo .. "|" .. hi .. "|" .. tostring(ts or 0))
end

--! #SEC — v1 installed the CODE-DERIVED secret itself on both ends, so
--! every peer that paired during one `net pair start` window (the window
--! allows several, and `net pair status` counts them) held the SAME secret
--! with this machine. The mesh seals a message end-to-end with the secret
--! its sender shares with the recipient, and opens it with the secret for
--! the envelope's CLAIMED origin (meshctl.ingest), while every node relays
--! every envelope. So peer X, paired in the same window as Y, could read
--! Y's mail to us as it relayed it, and forge mail to us "from" Y.
--!
--! Deriving per link from the code and the two addresses would not help:
--! X typed the same code and knows both addresses. Each side therefore
--! adds a fresh nonce -- the initiator's in INIT, ours in CONFIRM -- and the
--! installed secret is HMAC(codeSecret, both addresses, both nonces). Both
--! packets are unicast and MAC'd under the code-derived secret, so the
--! nonces cannot be altered without the code, and a third machine that
--! has the code never sees them.
--!
--! Compatible both ways: v2 fields ride beside the unchanged v1 MAC. An
--! older receiver ignores them and confirms v1; an older initiator sends
--! none and is paired v1. Either way both ends install the same secret,
--! and the v1 case is logged: that peer shares the window secret with any
--! other older peer paired in the same window, until it is updated and
--! paired again. (test_chatpair.lua)
local PAIR_V2 = 2

local function nonceHex()

  return (crypto.salt(16):gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function mac2(secret, addrA, addrB, ts, initNonce, confNonce)
  local lo, hi = tostring(addrA or ""), tostring(addrB or "")
  if lo > hi then lo, hi = hi, lo end
  return crypto.hmac(secret, table.concat({ "v2", lo, hi, tostring(ts or 0),
    tostring(initNonce or ""), tostring(confNonce or "") }, "|"))
end

local function linkSecret(secret, addrA, addrB, initNonce, confNonce)
  local lo, hi = tostring(addrA or ""), tostring(addrB or "")
  if lo > hi then lo, hi = hi, lo end
  return crypto.hmac(secret, table.concat({ DOMAIN, "link", lo, hi,
    tostring(initNonce), tostring(confNonce) }, "|"))
end

local function validNonce(n)
  return type(n) == "string" and #n >= 16 and #n <= 64 and not n:find("[^%x]")
end

local function ensureTrustedOrFail(addr)
  if not trustMod then return false, "trust manager unavailable" end
  local lvl = trustMod.getLevel(addr)
  if lvl < (trustMod.LEVEL and trustMod.LEVEL.TRUSTED or 2) then
    return false, "peer must be TRUSTED before pairing (run 'net trust <addr> full' first)"
  end
  return true
end

function chatpair.startWindow()
  if not crypto then return nil, "chatpair not initialized" end
  local now = computer.uptime()
  local code = generateCode()
  _window = {
    code        = code,
    secret      = deriveSecret(code),
    opens_at    = now,
    expires_at  = now + PAIRING_WINDOW_SEC,
    paired_with = {},
  }
  if log then log.info(LOG_TAG, "pairing window opened ("..PAIRING_WINDOW_SEC.."s)") end
  return code, _window.expires_at
end

function chatpair.closeWindow()
  _window = nil
  if log then log.info(LOG_TAG, "pairing window closed") end
end

function chatpair.windowOpen()
  if not _window then return false end
  if computer.uptime() > _window.expires_at then
    _window = nil
    return false
  end
  return true
end

function chatpair.windowInfo()
  if not chatpair.windowOpen() then return nil end
  return {
    expires_in = _window.expires_at - computer.uptime(),
    paired     = #_window.paired_with,
  }
end

function chatpair.onPairInit(packet, from)
  if not chatpair.windowOpen() then
    if log then log.warn(LOG_TAG, "pair_init from "..tostring(from):sub(1,8).." but no window open") end
    return
  end
  local p = packet.payload or {}
  if type(p.mac) ~= "string" or type(p.ts) ~= "number" then
    if log then log.warn(LOG_TAG, "malformed pair_init from "..tostring(from):sub(1,8)) end
    return
  end

  for _, paddr in ipairs(_window.paired_with) do
    if paddr == from then
      if log then log.warn(LOG_TAG, "duplicate pair_init from "..tostring(from):sub(1,8)) end
      return
    end
  end

  local okTrust, terr = ensureTrustedOrFail(from)
  if not okTrust then
    if log then log.warn(LOG_TAG, "pair_init from "..tostring(from):sub(1,8).." refused: "..terr) end
    return
  end

  local net = getNet()
  local ourAddr = net and net.getAddress and net.getAddress() or nil
  if not ourAddr then
    if log then log.warn(LOG_TAG, "pair_init: no local address; dropping") end
    return
  end
  local expected = macForCode(_window.secret, ourAddr, from, p.ts)
  if not crypto.ctEquals(expected, p.mac) then
    if log then log.warn(LOG_TAG, "pair_init MAC mismatch from "..tostring(from):sub(1,8)) end
    return
  end

  local v2 = (p.v == PAIR_V2)
  if v2 and not (validNonce(p.nonce) and type(p.mac2) == "string"
      and crypto.ctEquals(mac2(_window.secret, ourAddr, from, p.ts, p.nonce, nil), p.mac2)) then
    if log then log.warn(LOG_TAG, "pair_init v2 MAC mismatch from "..tostring(from):sub(1,8)) end
    return
  end
  local confNonce = v2 and nonceHex() or nil
  local installed = v2 and linkSecret(_window.secret, ourAddr, from, p.nonce, confNonce)
    or _window.secret

  local okS, sErr = trustMod.setSecret(PAIR_ACTOR, from, installed, TIER_ROOT)
  if not okS then
    if log then log.warn(LOG_TAG, "setSecret failed for "..tostring(from):sub(1,8)..": "..tostring(sErr)) end
    return
  end
  _window.paired_with[#_window.paired_with + 1] = from
  if log then
    log.info(LOG_TAG, "paired with "..tostring(from):sub(1,12).."...")
    if not v2 then
      log.warn(LOG_TAG, tostring(from):sub(1,8).." paired with the older (v1) handshake: "
        .. "it shares this window's secret with any other v1 peer paired in it. "
        .. "Update it and pair again.")
    end
  end

  local ts = computer.uptime()
  local payload = { mac = macForCode(_window.secret, ourAddr, from, ts), ts = ts }
  if v2 then
    payload.v     = PAIR_V2
    payload.nonce = confNonce
    payload.mac2  = mac2(_window.secret, ourAddr, from, ts, p.nonce, confNonce)
  end
  local confirm = protocol.makePacket(protocol.TYPE.CHAT_PAIR_CONFIRM, payload, { to = from })
  if net and net.send then pcall(net.send, from, confirm) end
end

function chatpair.connect(peer, code, timeout)
  if not crypto or not protocol or not trustMod then
    return false, "chatpair not initialized"
  end
  if type(peer) ~= "string" or peer == "" then
    return false, "peer address required"
  end
  if type(code) ~= "string" or #code < 4 then
    return false, "pairing code required"
  end
  local okTrust, terr = ensureTrustedOrFail(peer)
  if not okTrust then return false, terr end

  local net = getNet()
  if not net or not net.send or not net.on or not net.off then
    return false, "net module unavailable"
  end

  local norm   = code:upper():gsub("[^%w]", "")
  local secret = deriveSecret(norm)
  local ts     = computer.uptime()
  local ourAddr = net.getAddress and net.getAddress() or nil
  if not ourAddr then return false, "no local address" end

  local got, confirmPayload = false, nil
  local lid = net.onceFrom(protocol.TYPE.CHAT_PAIR_CONFIRM, peer, function(pkt)
    confirmPayload = pkt.payload
    got = true
  end)

  local initNonce = nonceHex()
  local pkt = protocol.makePacket(protocol.TYPE.CHAT_PAIR_INIT, {
    mac   = macForCode(secret, ourAddr, peer, ts),
    ts    = ts,
    v     = PAIR_V2,
    nonce = initNonce,
    mac2  = mac2(secret, ourAddr, peer, ts, initNonce, nil),
  }, { to = peer })
  local sent, sErr = net.send(peer, pkt)
  if not sent then
    net.off(protocol.TYPE.CHAT_PAIR_CONFIRM, lid)
    return false, "send failed: "..tostring(sErr)
  end

  net.waitFor(function() return got end, timeout or 10)
  net.off(protocol.TYPE.CHAT_PAIR_CONFIRM, lid)
  if not got then
    return false, "no confirmation (wrong code, window expired, or peer offline)"
  end

  if type(confirmPayload) ~= "table"
     or type(confirmPayload.mac) ~= "string"
     or type(confirmPayload.ts)  ~= "number" then
    return false, "malformed confirm"
  end

  local installed
  if confirmPayload.v == PAIR_V2 then

    if not (validNonce(confirmPayload.nonce) and type(confirmPayload.mac2) == "string"
        and crypto.ctEquals(mac2(secret, ourAddr, peer, confirmPayload.ts,
          initNonce, confirmPayload.nonce), confirmPayload.mac2)) then
      return false, "confirm MAC mismatch (wrong code or attacker on wire)"
    end
    installed = linkSecret(secret, ourAddr, peer, initNonce, confirmPayload.nonce)
  else
    local expected = macForCode(secret, ourAddr, peer, confirmPayload.ts)
    if not crypto.ctEquals(expected, confirmPayload.mac) then
      return false, "confirm MAC mismatch (wrong code or attacker on wire)"
    end

    installed = secret
    if log then
      log.warn(LOG_TAG, peer:sub(1,8).." answered with the older (v1) handshake; "
        .. "the link uses the pairing window's shared secret. Update it and pair again.")
    end
  end

  local okI, iErr = trustMod.setSecret(PAIR_ACTOR, peer, installed, TIER_ROOT)
  if not okI then return false, "local setSecret failed: "..tostring(iErr) end

  if log then log.info(LOG_TAG, "paired with "..peer:sub(1,12).."...") end
  return true
end

return chatpair
