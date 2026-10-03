









































local computer = require("computer")
local crypto   = require("kernel.crypto")
local protocol = require("kernel.net.protocol")
local net      = require("kernel.net")



local log
do
  local okK, mod = pcall(require, "kernel.log")
  if not (okK and mod and mod.info) then okK, mod = pcall(require, "log") end
  if okK and mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.pair"

local pair = {}





local PAIRING_WINDOW_SEC = 300  
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  
local CODE_LEN = 24


local _window = nil


local _trustMod = nil
local _trustActor = "root"  
                            
                            
                            
                            
                            

function pair.init(opts)
  _trustMod = opts and opts.trust or nil
end





--! crypto.salt returns CHARACTERS, uniform over a 62-symbol alphabet, not
--! uniform bytes. `b % 31` over those 62 ASCII codes reaches only 27 of the
--! 31 code characters, unevenly (~113 bits per code, not ~119). A salt
--! symbol's POSITION is uniform over 62 = 2 * 31, so position mod 31 is
--! exact; the byte path stays for a source that returns raw bytes. Same
--! fix as kernel/net/chatpair.lua.
local SALT62 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function generateCode()
  local out = {}
  local n = #CODE_ALPHABET
  while #out < CODE_LEN do
    local raw = crypto.salt(64)  
    for i = 1, #raw do
      if #out >= CODE_LEN then break end
      local pos = SALT62:find(raw:sub(i, i), 1, true)
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
  
  
  
  return crypto.hashPassword(code, "tos-cluster-pair-v1")
end

local function macForCode(secret, peerAddr, ts)
  
  
  return crypto.hmac(secret, tostring(peerAddr or "") .. "|" .. tostring(ts or 0))
end







function pair.startWindow()
  local now = computer.uptime()
  local code = generateCode()
  _window = {
    code       = code,
    secret     = deriveSecret(code),
    opens_at   = now,
    expires_at = now + PAIRING_WINDOW_SEC,
    paired_with = {},  
  }
  log.info(LOG_TAG, "pairing window opened (" .. PAIRING_WINDOW_SEC .. "s)")
  return code, _window.expires_at
end


function pair.closeWindow()
  _window = nil
  log.info(LOG_TAG, "pairing window closed")
end


function pair.windowOpen()
  if not _window then return false end
  if computer.uptime() > _window.expires_at then
    _window = nil
    return false
  end
  return true
end

function pair.windowInfo()
  if not pair.windowOpen() then return nil end
  return {
    expires_in = _window.expires_at - computer.uptime(),
    paired     = #_window.paired_with,
  }
end








function pair.onPairInit(packet, from)
  if not pair.windowOpen() then
    log.warn(LOG_TAG, "pair_init from " .. tostring(from):sub(1, 8) ..
      " but no window open")
    return
  end
  local p = packet.payload or {}
  if type(p.mac) ~= "string" or type(p.ts) ~= "number" then
    log.warn(LOG_TAG, "malformed pair_init from " .. tostring(from):sub(1, 8))
    return
  end
  --! p.ts is the MANAGER's uptime and is NOT compared with ours. The two
  --! machines' clocks are independent: this check refused every Manager
  --! booted more than PAIRING_WINDOW_SEC before or after the Master --
  --! silently, as "timestamp out of window". It is the same defect chat
  --! pairing already removed (#SEC M-21, net/chatpair.lua), still live on
  --! this side because test_cluster_pairing.lua runs both ends off one
  --! clock. Replay stays bounded without it: the window must be open, one
  --! init per address per window (below), and the MAC is over THIS
  --! window's code-derived secret AND ts, so an init from another window,
  --! or with its ts edited, fails the MAC.
  
  for _, paddr in ipairs(_window.paired_with) do
    if paddr == from then
      log.warn(LOG_TAG, "duplicate pair_init from " .. tostring(from):sub(1, 8))
      return
    end
  end
  
  local expected = macForCode(_window.secret, from, p.ts)
  if not crypto.ctEquals(expected, p.mac) then
    log.warn(LOG_TAG, "pair_init MAC mismatch from " .. tostring(from):sub(1, 8))
    return
  end

  
  if _trustMod then
    
    
    
    
    local TIER_ROOT = 3
    pcall(_trustMod.setLevel, _trustActor, from, _trustMod.LEVEL.TRUSTED, TIER_ROOT)
    pcall(_trustMod.setSecret, _trustActor, from, _window.secret, TIER_ROOT)
  end
  _window.paired_with[#_window.paired_with + 1] = from
  log.info(LOG_TAG, "paired with " .. tostring(from):sub(1, 12) .. "...")

  
  
  
  local ts = computer.uptime()
  local confirm = protocol.makePacket(protocol.TYPE.CLUSTER_PAIR_CONFIRM, {
    mac = macForCode(_window.secret, from, ts),
    ts  = ts,
  }, { to = from })
  pcall(net.send, from, confirm)
end

return pair
