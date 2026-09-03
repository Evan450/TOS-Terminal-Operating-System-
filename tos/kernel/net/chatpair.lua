-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Chat / peer pairing                            ║
-- ║                                                              ║
-- ║  Out-of-band shared-secret bootstrap for two TRUSTED peers.  ║
-- ║                                                              ║
-- ║  Problem this solves:                                        ║
-- ║    Today, distributing a shared secret between two peers is  ║
-- ║    an eight-step manual ritual:                              ║
-- ║      1. operator on A: `net trust gen <B-addr>`              ║
-- ║      2. A prints 64 hex chars on screen                      ║
-- ║      3. operator transcribes them (no typos!)                ║
-- ║      4. operator on B: `net trust setSecret <A-addr> <hex>`  ║
-- ║    Until step 4 finishes, B can't decrypt anything from A,   ║
-- ║    and sends from B are refused by net.send() because B has  ║
-- ║    no secret for the TRUSTED peer.                           ║
-- ║                                                              ║
-- ║  This module replaces steps 2–4 with:                        ║
-- ║      1. operator on A: `net pair start` (shows 24-char code) ║
-- ║      2. operator on B: `net pair <A> <code>`                 ║
-- ║      3. both sides now share a PBKDF-derived secret          ║
-- ║                                                              ║
-- ║  Security model (the bit that matters):                      ║
-- ║    Pairing distributes a SECRET. It does NOT establish       ║
-- ║    TRUST. Both peers MUST already be at TRUSTED level on     ║
-- ║    both sides before pairing — that elevation is the manual  ║
-- ║    friction the operator explicitly keeps, so an automation  ║
-- ║    flaw here cannot trick the operator into trusting the     ║
-- ║    wrong peer. The worst case if a rogue actor on the OC     ║
-- ║    network learns the code is that the rogue's TRUSTED       ║
-- ║    address pairs in front of the legitimate one — but it     ║
-- ║    has to be TRUSTED first, which is the operator's call.    ║
-- ║                                                              ║
-- ║    The 5-minute window + 24-char code from a 31-character    ║
-- ║    alphabet (≈ 119 bits of entropy) bounds online brute      ║
-- ║    force comfortably. PBKDF cost on the code derivation      ║
-- ║    inherits crypto.hashPassword's tunable rounds.            ║
-- ║                                                              ║
-- ║    Distinct domain separator ("tos-chat-pair-v1") so a       ║
-- ║    stolen cluster-pair code can't be replayed here and       ║
-- ║    vice versa.                                               ║
-- ╚══════════════════════════════════════════════════════════════╝

local computer = require("computer")

local chatpair = {}

local crypto    = nil
local protocol  = nil
local trustMod  = nil
local netMod    = nil  -- set lazily because we live INSIDE kernel.net
local log       = nil
local LOG_TAG   = "chatpair"

-- ============================================================
-- Tunables
-- ============================================================

local PAIRING_WINDOW_SEC = 300   -- 5 minutes
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  -- skip 0/O/I/L/1
local CODE_LEN = 24
local DOMAIN = "tos-chat-pair-v1"

-- Active window (receiver side): { code, secret, expires_at, paired_with }
-- nil when no window is open.
local _window = nil

-- We attribute pairing-driven trust.setSecret calls to "root" with
-- TIER.ROOT (= 3). The pairing window was opened by a ROOT-tier shell
-- session, but the packet handler runs deep inside the dispatch path
-- and we don't carry the originating actor through.
local PAIR_ACTOR = "root"
local TIER_ROOT  = 3

-- ============================================================
-- Init
-- ============================================================

function chatpair.init(opts)
  crypto   = opts and opts.crypto    or require("kernel.crypto")
  protocol = opts and opts.protocol  or require("kernel.net.protocol")
  trustMod = opts and opts.trust     or nil
  log      = opts and opts.log       or nil
  -- Optional injection point for tests; live kernel passes nothing
  -- here and we lazily require kernel.net on first use to avoid the
  -- init-time circular require with kernel.net.init.
  netMod   = opts and opts.net       or nil
end

-- Lazily attach the net module. kernel.net.init requires THIS file
-- during its own init(), so requiring kernel.net at module-load time
-- would be a cycle. We grab it on first use instead.
local function getNet()
  if netMod then return netMod end
  local ok, m = pcall(require, "kernel.net")
  if ok then netMod = m end
  return netMod
end

-- ============================================================
-- Code + secret derivation
-- ============================================================

local function generateCode()
  -- Rejection sampling against the 31-character alphabet (M10 pattern).
  local out, n = {}, #CODE_ALPHABET
  while #out < CODE_LEN do
    local raw = crypto.salt(64)
    for i = 1, #raw do
      if #out >= CODE_LEN then break end
      local b = raw:byte(i)
      if b < 248 then  -- 248 = 31 * 8, largest multiple of 31 ≤ 256
        local idx = (b % n) + 1
        out[#out + 1] = CODE_ALPHABET:sub(idx, idx)
      end
    end
  end
  return table.concat(out)
end

local function deriveSecret(code)
  -- hashPassword does the PBKDF; the salt argument is the domain
  -- separator so a code stolen from the cluster-pair UX cannot be
  -- replayed here (different DOMAIN → different secret).
  return crypto.hashPassword(code, DOMAIN)
end

-- Canonical MAC input: sorted address pair + timestamp, so BOTH sides
-- of the handshake produce the same value without having to know who
-- is "sender" or "receiver." Without this canonicalization the sender
-- would have to MAC over its own address and the receiver would
-- verify over the inbound `from` — which works one direction but
-- breaks for the confirm reply (where the roles are swapped). Using a
-- sorted pair sidesteps the asymmetry entirely.
local function macForCode(secret, addrA, addrB, ts)
  local lo, hi = tostring(addrA or ""), tostring(addrB or "")
  if lo > hi then lo, hi = hi, lo end
  return crypto.hmac(secret, lo .. "|" .. hi .. "|" .. tostring(ts or 0))
end

-- ============================================================
-- Pre-condition check
-- ============================================================

-- Both pairing peers must already be at TRUSTED level on both sides.
-- This is the "manual friction" the operator keeps: pairing only
-- helps distribute a secret between peers they've already chosen to
-- trust; it cannot itself escalate trust.
local function ensureTrustedOrFail(addr)
  if not trustMod then return false, "trust manager unavailable" end
  local lvl = trustMod.getLevel(addr)
  if lvl < (trustMod.LEVEL and trustMod.LEVEL.TRUSTED or 2) then
    return false, "peer must be TRUSTED before pairing (run 'net trust <addr> full' first)"
  end
  return true
end

-- ============================================================
-- Receiver side ("net pair start")
-- ============================================================

--- Open a 5-minute pairing window. Returns (code, expires_at_uptime).
--- Caller displays the code to the operator; the operator types it on
--- the other peer.
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

-- ============================================================
-- Packet handlers (registered by net.init)
-- ============================================================

--- Receiver-side handler: inbound CHAT_PAIR_INIT.
--- Verifies the MAC against our window secret, installs the secret
--- locally, and sends CHAT_PAIR_CONFIRM back so the sender can do the
--- same on its side.
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
  -- #SEC M-21 — we do NOT compare p.ts (the SENDER's uptime) against our
  -- own uptime: the two machines have independent, unsynchronised clocks,
  -- so the difference is meaningless and would reject legitimate inits at
  -- random. Replay is already bounded three ways: (1) our pairing window
  -- must be open (checked above), (2) per-address dedup (checked below),
  -- and (3) the MAC is computed over THIS window's secret, so an init
  -- captured from an earlier window fails MAC verification regardless of
  -- its timestamp. `p.ts` remains part of the authenticated payload but
  -- is not range-checked here.
  -- One pair attempt per address per window.
  for _, paddr in ipairs(_window.paired_with) do
    if paddr == from then
      if log then log.warn(LOG_TAG, "duplicate pair_init from "..tostring(from):sub(1,8)) end
      return
    end
  end
  -- Pre-condition: the sender must already be TRUSTED on our side.
  -- If not, we silently refuse — telling the sender they're not trusted
  -- would leak our trust DB to anyone who guesses the code.
  local okTrust, terr = ensureTrustedOrFail(from)
  if not okTrust then
    if log then log.warn(LOG_TAG, "pair_init from "..tostring(from):sub(1,8).." refused: "..terr) end
    return
  end
  -- MAC check. Compute over our own addr + the inbound sender's addr
  -- in canonical (sorted) order so both sides agree without caring
  -- which is the "sender".
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

  -- Install the derived secret. Pre-condition checked above means
  -- trust.setSecret won't refuse on "Peer must be TRUSTED".
  local okS, sErr = trustMod.setSecret(PAIR_ACTOR, from, _window.secret, TIER_ROOT)
  if not okS then
    if log then log.warn(LOG_TAG, "setSecret failed for "..tostring(from):sub(1,8)..": "..tostring(sErr)) end
    return
  end
  _window.paired_with[#_window.paired_with + 1] = from
  if log then log.info(LOG_TAG, "paired with "..tostring(from):sub(1,12).."...") end

  -- Confirm back. Same canonical MAC so the sender can verify with
  -- (its own addr, our addr) → same value.
  local ts = computer.uptime()
  local confirm = protocol.makePacket(protocol.TYPE.CHAT_PAIR_CONFIRM, {
    mac = macForCode(_window.secret, ourAddr, from, ts),
    ts  = ts,
  }, { to = from })
  if net and net.send then pcall(net.send, from, confirm) end
end

-- ============================================================
-- Sender side ("net pair <peer> <code>")
-- ============================================================

--- Pair with `peer` using the out-of-band code shown by the receiver.
--- Sends CHAT_PAIR_INIT, awaits CHAT_PAIR_CONFIRM, on success installs
--- the derived secret locally too.
---
--- Returns (true) on success or (false, reason) on failure.
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

  -- Normalise the code: alphabet is case-insensitive, but the receiver
  -- generated uppercase, so derive against uppercase here too.
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

  -- Verify the confirm MAC. The receiver bound it to (us, their_ts)
  -- under the same code-derived secret, so a forged confirm from a
  -- bystander without the code can't authenticate.
  if type(confirmPayload) ~= "table"
     or type(confirmPayload.mac) ~= "string"
     or type(confirmPayload.ts)  ~= "number" then
    return false, "malformed confirm"
  end
  -- #SEC M-21 (round-1 "pairing never completes" root cause) — do NOT
  -- range-check confirmPayload.ts against our own clock. It is the
  -- RECEIVER's uptime: the two machines' clocks are independent and
  -- unsynchronised, so any pair of boxes booted more than the window
  -- apart could NEVER pair (|our_uptime - their_uptime| > 300 → refused
  -- every time, silently). This was the leftover sender-side twin of the
  -- receiver check M-21 already removed. Replay stays bounded the same
  -- three ways: the one-shot onceFrom listener only exists during THIS
  -- connect() call, the confirm must come from `peer`, and the MAC is
  -- computed over the code-derived secret + this ts — a confirm captured
  -- from an earlier exchange fails ctEquals below.
  -- Canonical MAC: (our addr, peer addr) sorted, plus confirm ts.
  -- Same value whether computed here or on the receiver.
  local expected = macForCode(secret, ourAddr, peer, confirmPayload.ts)
  if not crypto.ctEquals(expected, confirmPayload.mac) then
    return false, "confirm MAC mismatch (wrong code or attacker on wire)"
  end

  -- Install the secret locally so subsequent sends to `peer` encrypt
  -- and MAC correctly.
  local okI, iErr = trustMod.setSecret(PAIR_ACTOR, peer, secret, TIER_ROOT)
  if not okI then return false, "local setSecret failed: "..tostring(iErr) end

  if log then log.info(LOG_TAG, "paired with "..peer:sub(1,12).."...") end
  return true
end

return chatpair
