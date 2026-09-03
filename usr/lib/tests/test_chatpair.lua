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

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
