-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.net.chatpair                         ║
-- ║                                                                ║
-- ║  Drives the FULL two-machine pair handshake (startWindow on   ║
-- ║  B, connect on A, INIT/CONFIRM routed between them) against   ║
-- ║  stubbed crypto/trust/net — with the two machines' clocks     ║
-- ║  DELIBERATELY skewed far past the pairing window. The round-1 ║
-- ║  "pairing never completes" bug was a leftover sender-side     ║
-- ║  |our_uptime - their_ts| range check (the twin of the #SEC    ║
-- ║  M-21 receiver check already removed): any two boxes booted   ║
-- ║  more than 5 minutes apart could never pair.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_chatpair.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond, extra)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (extra and ("  (" .. tostring(extra) .. ")") or ""))
  end
end

-- ── Shared clock stub: per-machine uptimes, switched by `current` ──
-- A has been up ~3 hours; B rebooted a minute ago. |A-B| >> the 300s
-- pairing window — exactly the emulator round-1 situation.
local now = { A = 10000, B = 42 }
local current = "A"
package.loaded["computer"] = {
  uptime = function() now[current] = now[current] + 0.01; return now[current] end,
}

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- ── Crypto stub: deterministic, shape-compatible ───────────────────
local crypto = {
  salt = function(n)
    -- bytes < 248 so generateCode's rejection sampling accepts them.
    local t = {}
    for i = 1, n do t[i] = string.char((i * 37) % 200) end
    return table.concat(t)
  end,
  hashPassword = function(code, domain) return "PBKDF[" .. code .. "/" .. domain .. "]" end,
  hmac = function(secret, msg) return "MAC(" .. secret .. "|" .. msg .. ")" end,
  ctEquals = function(a, b) return a == b end,
}

-- ── Protocol stub ──────────────────────────────────────────────────
local protocol = {
  TYPE = { CHAT_PAIR_INIT = "chat_pair_init", CHAT_PAIR_CONFIRM = "chat_pair_confirm" },
  makePacket = function(t, payload, opts)
    return { type = t, payload = payload, to = opts and opts.to }
  end,
}

-- ── Per-machine trust stub (both sides TRUSTED, records secrets) ───
local function makeTrust(peerAddr, level)
  local t = {
    LEVEL = { UNKNOWN = 0, KNOWN = 1, TRUSTED = 2, BLOCKED = -1 },
    secrets = {},
  }
  t.getLevel = function(addr) return (addr == peerAddr) and level or 0 end
  t.setSecret = function(_actor, addr, secret, _tier)
    t.secrets[addr] = secret; return true
  end
  return t
end

-- ── Load TWO instances of the module (separate _window state) ──────
local function loadChatpair()
  local chunk = assert(loadfile("tos/kernel/net/chatpair.lua"))
  return chunk()
end

local ADDR = { A = "aaaa-1111-aaaa-1111", B = "bbbb-2222-bbbb-2222" }

local CA, CB = loadChatpair(), loadChatpair()
local trustA = makeTrust(ADDR.B, 2)
local trustB = makeTrust(ADDR.A, 2)

-- ── Net stubs: send() routes to the other machine synchronously ────
-- (flipping `current` so each side computes with its OWN clock).
-- Dot-call style, matching the real net.onceFrom(msgType, addr, cb).
local function makeNet(selfAddr, deliver)
  local n = { _once = {} }
  n.getAddress = function() return selfAddr end
  n.onceFrom = function(msgType, addr, cb)
    local id = #n._once + 1
    n._once[id] = { type = msgType, addr = addr, cb = cb }
    return id
  end
  n.on  = function() return 0 end   -- connect() probes for it
  n.off = function(_msgType, id) n._once[id] = nil end
  n.send = function(to, pkt) return deliver(to, pkt, selfAddr) end
  n.waitFor = function(pred, _timeout)
    -- Synchronous delivery means the confirm (if any) already arrived.
    return pred()
  end
  n._dispatch = function(pkt, from)
    for id, l in pairs(n._once) do
      if l.type == pkt.type and l.addr == from then
        n._once[id] = nil
        l.cb(pkt, from)
      end
    end
  end
  return n
end

local deliver
netA = makeNet(ADDR.A, function(to, pkt, from) return deliver(to, pkt, from) end)
netB = makeNet(ADDR.B, function(to, pkt, from) return deliver(to, pkt, from) end)

deliver = function(to, pkt, from)
  local prev = current
  if to == ADDR.B then
    current = "B"
    if pkt.type == protocol.TYPE.CHAT_PAIR_INIT then CB.onPairInit(pkt, from)
    else netB._dispatch(pkt, from) end
  elseif to == ADDR.A then
    current = "A"
    if pkt.type == protocol.TYPE.CHAT_PAIR_INIT then CA.onPairInit(pkt, from)
    else netA._dispatch(pkt, from) end
  end
  current = prev
  return true
end

CA.init({ crypto = crypto, protocol = protocol, trust = trustA, net = netA })
CB.init({ crypto = crypto, protocol = protocol, trust = trustB, net = netB })

print("=== kernel.net.chatpair Tests ===")
print()

-- ── 1. Happy path with clocks skewed FAR past the window ───────────
current = "B"
local code, expires = CB.startWindow()
test("receiver window opens", type(code) == "string" and #code == 24)
test("window reports open", CB.windowOpen())

current = "A"
local ok, err = CA.connect(ADDR.B, code, 1)
test("pair completes with clocks skewed >> window  (THE regression)",
  ok == true, err)
test("receiver installed the secret", trustB.secrets[ADDR.A] ~= nil)
test("sender installed the secret", trustA.secrets[ADDR.B] ~= nil)
test("both sides derived the SAME secret",
  trustA.secrets[ADDR.B] == trustB.secrets[ADDR.A]
  and trustA.secrets[ADDR.B] ~= nil)

-- ── 2. Wrong code: receiver stays silent, sender times out ─────────
current = "B"
CB.closeWindow()
local code2 = CB.startWindow()
current = "A"
local ok2, err2 = CA.connect(ADDR.B, "WRONGCODEWRONGCODEWRONGX", 1)
test("wrong code -> no pair", ok2 == false)
test("wrong code -> explains", type(err2) == "string" and err2:find("confirmation") ~= nil, err2)

-- ── 3. No window open: init dropped, sender times out ──────────────
current = "B"
CB.closeWindow()
current = "A"
local ok3 = CA.connect(ADDR.B, code2, 1)
test("no window -> no pair", ok3 == false)

-- ── 4. Untrusted peer refused on the SENDER side up front ──────────
local CU = loadChatpair()
local trustNone = makeTrust(ADDR.B, 0)
CU.init({ crypto = crypto, protocol = protocol, trust = trustNone, net = netA })
local ok4, err4 = CU.connect(ADDR.B, code2, 1)
test("untrusted peer refused", ok4 == false
  and type(err4) == "string" and err4:find("TRUSTED") ~= nil, err4)

-- ── 5. Window expiry honours the RECEIVER's own clock ──────────────
current = "B"
CB.closeWindow()
CB.startWindow()
now.B = now.B + 301          -- receiver's clock passes its own window
test("expired window reports closed", CB.windowOpen() == false)

-- ── 6. Several peers in ONE window get DIFFERENT secrets ───────────
-- v1 installed the code-derived secret itself, so every peer paired in
-- one window shared it with B -- and the mesh opens a sealed envelope
-- with the secret for its CLAIMED origin, while every node relays every
-- envelope: peer C could read A's mail to B and forge mail "from" A.
-- Each side now adds a nonce, sent only in its own unicast packet.
print()
print("-- several peers, one window --")
local saltN = 0
crypto.salt = function(n)
  saltN = saltN + 1
  local t = {}
  for i = 1, n do t[i] = string.char((i * 37 + saltN * 11) % 200) end
  return table.concat(t)
end
ADDR.C = "cccc-3333-cccc-3333"
local trustBmany = {
  LEVEL = { UNKNOWN = 0, KNOWN = 1, TRUSTED = 2, BLOCKED = -1 }, secrets = {},
  getLevel = function() return 2 end,
}
trustBmany.setSecret = function(_a, addr, s) trustBmany.secrets[addr] = s; return true end
local trustC = makeTrust(ADDR.B, 2)
local netC = makeNet(ADDR.C, function(to, pkt, from) return deliver(to, pkt, from) end)
local CC = loadChatpair()
CC.init({ crypto = crypto, protocol = protocol, trust = trustC, net = netC })
CB.init({ crypto = crypto, protocol = protocol, trust = trustBmany, net = netB })
local prevDeliver = deliver
deliver = function(to, pkt, from)
  if to == ADDR.C then
    local prev = current; current = "A"
    netC._dispatch(pkt, from); current = prev
    return true
  end
  return prevDeliver(to, pkt, from)
end
trustA.secrets = {}
current = "B"; CB.closeWindow(); now.B = 42
local code6 = CB.startWindow()
current = "A"
test("A pairs in the window", (CA.connect(ADDR.B, code6, 1)))
test("C pairs in the SAME window", (CC.connect(ADDR.B, code6, 1)))
local windowSecret = crypto.hashPassword(code6, "tos-chat-pair-v1")
test("A and B agree on their link", trustA.secrets[ADDR.B] ~= nil
  and trustA.secrets[ADDR.B] == trustBmany.secrets[ADDR.A])
test("C and B agree on theirs", trustC.secrets[ADDR.B] ~= nil
  and trustC.secrets[ADDR.B] == trustBmany.secrets[ADDR.C])
test("A's link and C's link are DIFFERENT secrets",
  trustBmany.secrets[ADDR.A] ~= trustBmany.secrets[ADDR.C])
test("neither is the code-derived window secret C also holds",
  trustBmany.secrets[ADDR.A] ~= windowSecret and trustBmany.secrets[ADDR.C] ~= windowSecret)

-- ── 7. An OLDER initiator (v1 fields only) still pairs ─────────────
print()
print("-- older peers --")
trustBmany.secrets = {}
current = "B"; CB.closeWindow()
local code7 = CB.startWindow()   -- A already paired in the last one
windowSecret = crypto.hashPassword(code7, "tos-chat-pair-v1")
local confirmSeen
netA._once[#netA._once + 1] = { type = protocol.TYPE.CHAT_PAIR_CONFIRM, addr = ADDR.B,
  cb = function(pkt) confirmSeen = pkt.payload end }
current = "A"
local tsOld = now.A
deliver(ADDR.B, protocol.makePacket(protocol.TYPE.CHAT_PAIR_INIT, {
  mac = crypto.hmac(windowSecret, (ADDR.A < ADDR.B and (ADDR.A .. "|" .. ADDR.B) or (ADDR.B .. "|" .. ADDR.A))
    .. "|" .. tostring(tsOld)),
  ts = tsOld,
}), ADDR.A)
test("an older initiator is paired", trustBmany.secrets[ADDR.A] == windowSecret)
test("...and answered in the older form (no v2 fields)",
  type(confirmSeen) == "table" and confirmSeen.v == nil and confirmSeen.mac2 == nil)

-- ── 8. An OLDER receiver (ignores v2 fields) still pairs ───────────
-- Simulated by stripping the v2 fields before B sees the init: B then
-- answers v1, exactly as a receiver that predates them would.
trustA.secrets = {}
current = "B"; CB.closeWindow()
local code8 = CB.startWindow()
deliver = function(to, pkt, from)
  if to == ADDR.B and pkt.type == protocol.TYPE.CHAT_PAIR_INIT then
    pkt.payload.v, pkt.payload.nonce, pkt.payload.mac2 = nil, nil, nil
  end
  return prevDeliver(to, pkt, from)
end
current = "A"
test("pairing with an older receiver still completes", (CA.connect(ADDR.B, code8, 1)))
test("...on the window secret both ends can derive",
  trustA.secrets[ADDR.B] == crypto.hashPassword(code8, "tos-chat-pair-v1")
  and trustA.secrets[ADDR.B] == trustBmany.secrets[ADDR.A])

-- ── 9. A tampered v2 nonce is refused, not quietly downgraded ──────
trustA.secrets = {}
current = "B"; CB.closeWindow()
local code9 = CB.startWindow()
deliver = function(to, pkt, from)
  if to == ADDR.A and pkt.type == protocol.TYPE.CHAT_PAIR_CONFIRM and pkt.payload.v then
    pkt.payload.nonce = string.rep("0", 32)
  end
  return prevDeliver(to, pkt, from)
end
current = "A"
local ok9, err9 = CA.connect(ADDR.B, code9, 1)
test("a confirm whose nonce was altered is refused", ok9 == false
  and tostring(err9):find("MAC mismatch", 1, true) ~= nil, err9)
test("...and nothing was installed", trustA.secrets[ADDR.B] == nil)
deliver = prevDeliver

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
