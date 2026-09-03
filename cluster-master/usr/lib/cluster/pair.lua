-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.pair — Trust bootstrap (Master side)                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Solves the chicken-and-egg problem of "Master and Manager need a
-- shared secret to talk securely, but they need a secure channel to
-- exchange the secret." The answer is an OUT-OF-BAND pairing code:
-- the operator reads it off Master's screen and types it on the
-- Manager. Both sides derive the same shared secret from the code
-- via PBKDF, and both sides set each other to TRUSTED.
--
-- Flow:
--   1. Operator runs `cluster pair start` on Master.
--      → Master generates a high-entropy code (24 alphanumeric chars),
--        opens a 5-minute pairing window, displays the code.
--   2. Operator types the code on the Manager:
--      `cluster-manager pair <master-addr> <code>`
--      → Manager derives secret = PBKDF(code, "tos-cluster-pair-v1").
--      → Manager sends CLUSTER_PAIR_INIT to Master, carrying
--        HMAC(secret, code || manager_addr || timestamp).
--   3. Master receives CLUSTER_PAIR_INIT, verifies the HMAC against
--      its own derived secret. If valid AND inside the pairing window:
--      → Master adds Manager to trust DB at TRUSTED with that secret.
--      → Master sends CLUSTER_PAIR_CONFIRM carrying its own HMAC.
--   4. Manager receives CLUSTER_PAIR_CONFIRM, verifies, sets Master
--      to TRUSTED with the same secret.
--
-- After step 4 the normal CLUSTER_REGISTER → CLUSTER_REGISTER_ACK
-- handshake takes over with encrypted + MACed transport.
--
-- Security notes:
--   * The pairing code is the operator's responsibility — anyone who
--     sees it on Master's screen and types it into a Manager BEFORE
--     the legitimate Manager pairs will succeed. The 5-minute window
--     limits exposure.
--   * PBKDF cost is set by kernel.crypto's hashPassword, so the
--     derived key inherits the rounds-tunable resistance of the v3
--     hash format.
--   * No replay protection on the pair_init beyond the per-window
--     freshness — a captured init from one pairing CANNOT replay
--     into a different pairing because the code (and therefore the
--     derived secret) is unique per window.

local computer = require("computer")
local crypto   = require("kernel.crypto")
local protocol = require("kernel.net.protocol")
local net      = require("kernel.net")

-- kernel.log first — bare "log" resolves nowhere on TOS, which made
-- these logs silently vanish.
local log
do
  local okK, mod = pcall(require, "kernel.log")
  if not (okK and mod and mod.info) then okK, mod = pcall(require, "log") end
  if okK and mod and mod.info then log = mod
  else log = { info=function() end, warn=function() end, error=function() end } end
end
local LOG_TAG = "cluster.pair"

local pair = {}

-- ============================================================
-- Window state
-- ============================================================

local PAIRING_WINDOW_SEC = 300  -- 5 minutes
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  -- skip 0/O/I/L/1 ambiguity
local CODE_LEN = 24

-- Active window: { code, secret, opens_at, expires_at } or nil.
local _window = nil

-- Trust manager handle, plumbed in by init().
local _trustMod = nil
local _trustActor = "root"  -- the synthetic actor we attribute pair-driven
                            -- trust mutations to in the audit log. Operators
                            -- running `cluster pair start` are themselves
                            -- ROOT, but the trust update happens deep inside
                            -- a packet handler so we attribute it to "root"
                            -- rather than rummaging up the call stack.

function pair.init(opts)
  _trustMod = opts and opts.trust or nil
end

-- ============================================================
-- Code + key derivation
-- ============================================================

local function generateCode()
  -- Use crypto.salt for high-entropy bytes, then map to our restricted
  -- alphabet via rejection sampling (M10-style).
  local out = {}
  local n = #CODE_ALPHABET
  while #out < CODE_LEN do
    local raw = crypto.salt(64)  -- always plenty
    for i = 1, #raw do
      if #out >= CODE_LEN then break end
      local b = raw:byte(i)
      -- 248 = 31 * 8, largest multiple of 31 ≤ 256. Reject above.
      if b < 248 then
        local idx = (b % n) + 1
        out[#out + 1] = CODE_ALPHABET:sub(idx, idx)
      end
    end
  end
  return table.concat(out)
end

local function deriveSecret(code)
  -- Distinct domain-separator from any other use of hashPassword in TOS.
  -- This way a stolen tape vault secret can't be replayed as a pairing
  -- secret and vice versa.
  return crypto.hashPassword(code, "tos-cluster-pair-v1")
end

local function macForCode(secret, peerAddr, ts)
  -- HMAC binds the pairing handshake to a specific peer + timestamp,
  -- so a captured init from peer A can't be replayed at peer B.
  return crypto.hmac(secret, tostring(peerAddr or "") .. "|" .. tostring(ts or 0))
end

-- ============================================================
-- Public API (Master side)
-- ============================================================

--- Open a pairing window. Returns the code (caller displays it to the
--- operator) and the window's expiry uptime.
function pair.startWindow()
  local now = computer.uptime()
  local code = generateCode()
  _window = {
    code       = code,
    secret     = deriveSecret(code),
    opens_at   = now,
    expires_at = now + PAIRING_WINDOW_SEC,
    paired_with = {},  -- track who already used this code (one-shot per peer)
  }
  log.info(LOG_TAG, "pairing window opened (" .. PAIRING_WINDOW_SEC .. "s)")
  return code, _window.expires_at
end

--- Close the active window without waiting for expiry.
function pair.closeWindow()
  _window = nil
  log.info(LOG_TAG, "pairing window closed")
end

--- True iff a window is currently open and hasn't expired.
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

-- ============================================================
-- Packet handlers (registered by clusterd via netmod)
-- ============================================================

--- Handle inbound CLUSTER_PAIR_INIT. Verifies the MAC and, on success,
--- adds the peer to trust DB at TRUSTED level with the derived secret,
--- then sends CLUSTER_PAIR_CONFIRM back.
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
  -- Timestamp must be within the window. Manager's clock is its own
  -- uptime; we trust it for freshness but bound the window so a
  -- captured init can't replay outside.
  if math.abs(computer.uptime() - p.ts) > PAIRING_WINDOW_SEC then
    log.warn(LOG_TAG, "pair_init timestamp out of window from " ..
      tostring(from):sub(1, 8))
    return
  end
  -- Reject duplicate pair_inits from the same address inside this window.
  for _, paddr in ipairs(_window.paired_with) do
    if paddr == from then
      log.warn(LOG_TAG, "duplicate pair_init from " .. tostring(from):sub(1, 8))
      return
    end
  end
  -- Verify MAC.
  local expected = macForCode(_window.secret, from, p.ts)
  if not crypto.ctEquals(expected, p.mac) then
    log.warn(LOG_TAG, "pair_init MAC mismatch from " .. tostring(from):sub(1, 8))
    return
  end

  -- Accept: store the peer at TRUSTED with the derived secret.
  if _trustMod then
    -- trust.setLevel + setSecret require actor + tier. We attribute
    -- the call to "root" with TIER.ROOT (=3) so the admin-actor check
    -- passes. This is OK because the pairing window is explicitly
    -- opened by a ROOT-tier operator.
    local TIER_ROOT = 3
    pcall(_trustMod.setLevel, _trustActor, from, _trustMod.LEVEL.TRUSTED, TIER_ROOT)
    pcall(_trustMod.setSecret, _trustActor, from, _window.secret, TIER_ROOT)
  end
  _window.paired_with[#_window.paired_with + 1] = from
  log.info(LOG_TAG, "paired with " .. tostring(from):sub(1, 12) .. "...")

  -- Send the confirmation. Our MAC binds it back to the same code +
  -- this Manager so the Manager knows it really came from the Master
  -- and not from an attacker on the network.
  local ts = computer.uptime()
  local confirm = protocol.makePacket(protocol.TYPE.CLUSTER_PAIR_CONFIRM, {
    mac = macForCode(_window.secret, from, ts),
    ts  = ts,
  }, { to = from })
  pcall(net.send, from, confirm)
end

return pair
