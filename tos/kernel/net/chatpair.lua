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

local function generateCode()

  local out, n = {}, #CODE_ALPHABET
  while #out < CODE_LEN do
    local raw = crypto.salt(64)
    for i = 1, #raw do
      if #out >= CODE_LEN then break end
      local b = raw:byte(i)
      if b < 248 then
        local idx = (b % n) + 1
        out[#out + 1] = CODE_ALPHABET:sub(idx, idx)
      end
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

  local okS, sErr = trustMod.setSecret(PAIR_ACTOR, from, _window.secret, TIER_ROOT)
  if not okS then
    if log then log.warn(LOG_TAG, "setSecret failed for "..tostring(from):sub(1,8)..": "..tostring(sErr)) end
    return
  end
  _window.paired_with[#_window.paired_with + 1] = from
  if log then log.info(LOG_TAG, "paired with "..tostring(from):sub(1,12).."...") end

  local ts = computer.uptime()
  local confirm = protocol.makePacket(protocol.TYPE.CHAT_PAIR_CONFIRM, {
    mac = macForCode(_window.secret, ourAddr, from, ts),
    ts  = ts,
  }, { to = from })
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

  local pkt = protocol.makePacket(protocol.TYPE.CHAT_PAIR_INIT, {
    mac = macForCode(secret, ourAddr, peer, ts),
    ts  = ts,
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

  local expected = macForCode(secret, ourAddr, peer, confirmPayload.ts)
  if not crypto.ctEquals(expected, confirmPayload.mac) then
    return false, "confirm MAC mismatch (wrong code or attacker on wire)"
  end

  local okI, iErr = trustMod.setSecret(PAIR_ACTOR, peer, secret, TIER_ROOT)
  if not okI then return false, "local setSecret failed: "..tostring(iErr) end

  if log then log.info(LOG_TAG, "paired with "..peer:sub(1,12).."...") end
  return true
end

return chatpair
