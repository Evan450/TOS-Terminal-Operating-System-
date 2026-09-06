-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: cluster pairing, Manager against Master      ║
-- ║                                                                ║
-- ║  `cluster pair` could never succeed. The Master verifies the   ║
-- ║  Manager's CLUSTER_PAIR_INIT with a MAC over the MANAGER's     ║
-- ║  address (what it sees on the wire) and signs its confirm the  ║
-- ║  same way; the Manager computed both MACs over the MASTER's    ║
-- ║  address. Every pairing died at "pair_init MAC mismatch", and  ║
-- ║  the Manager's own comment said which address it should have   ║
-- ║  used while the code used the other.                           ║
-- ║                                                                ║
-- ║  Neither side's unit tests could see it: each was tested       ║
-- ║  against a hand-built packet from the same author. This runs   ║
-- ║  the REAL Manager pair() against the REAL Master pair module   ║
-- ║  with the real kernel.crypto, and routes the packets between   ║
-- ║  them.                                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_pairing.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_cluster_pairing.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

local MANAGER = "manager-addr-0123456789abcdef"
local MASTER  = "master-addr-fedcba9876543210"

-- ── One clock, one wire ──────────────────────────────────────────
local clock = 500
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, invoke = function() return nil end,
}
package.loaded["computer"] = {
  uptime = function() return clock end,
  freeMemory = function() return 200000 end, totalMemory = function() return 262144 end,
  address = function() return MANAGER end,
}
package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["kernel.fs"]  = { exists = function() return false end }
package.loaded["log"] = { info = function() end, warn = function(_, m) end, error = function() end }
package.loaded["kernel.log"] = package.loaded["log"]
package.loaded["event"] = {
  on = function() end, interval = function() return 1 end, timer = function() return 1 end,
  cancelTimer = function() return true end,
  pull = function() clock = clock + 0.25 end,
}
package.loaded["kernel.event"] = package.loaded["event"]
package.loaded["kernel.net.protocol"] = {
  TYPE = setmetatable({}, { __index = function(_, k) return "T_" .. k end }),
  makePacket = function(t, p, o) return { type = t, payload = p, to = o and o.to } end,
}

-- The wire: listeners per side, and send() delivers to the OTHER side
-- synchronously, tagged with the sender's address. `wire.drop` lets a
-- test lose a packet; `wire.tamper` lets it rewrite one.
local wire = { listeners = {}, log = {}, drop = nil, tamper = nil }
local function makeNet(selfAddr, peerAddr)
  return {
    getAddress = function() return selfAddr end,
    on = function(t, cb)
      wire.listeners[peerAddr] = wire.listeners[peerAddr]     -- (peer registers its own)
      wire.listeners[selfAddr] = wire.listeners[selfAddr] or {}
      local id = #wire.log + 1000 + #(wire.listeners[selfAddr])
      table.insert(wire.listeners[selfAddr], { type = t, cb = cb, id = id })
      return id
    end,
    off = function(t, id)
      for i, l in ipairs(wire.listeners[selfAddr] or {}) do
        if l.id == id then table.remove(wire.listeners[selfAddr], i); return true end
      end
    end,
    send = function(to, pkt)
      wire.log[#wire.log + 1] = { from = selfAddr, to = to, type = pkt.type }
      if wire.drop and wire.drop(pkt) then return true end
      if wire.tamper then pkt = wire.tamper(pkt) or pkt end
      for _, l in ipairs(wire.listeners[to] or {}) do
        if l.type == pkt.type then l.cb(pkt, selfAddr) end
      end
      return true
    end,
  }
end

-- A trust DB both sides write to (recorded per actor call).
local trustCalls = {}
local trustStub = {
  LEVEL = { TRUSTED = 3 },
  setLevel  = function(actor, addr, level, tier) trustCalls[#trustCalls + 1] = { "level", addr, level }; return true end,
  setSecret = function(actor, addr, secret, tier) trustCalls[#trustCalls + 1] = { "secret", addr, secret }; return true end,
}
package.loaded["kernel.net.trust"] = trustStub

-- ── Load the MASTER pair module with the Master's net ────────────
package.loaded["kernel.net"] = makeNet(MASTER, MANAGER)
local masterPair
for _, p in ipairs({ "../TOS-Extras/cluster/master-skeleton/lib/cluster/pair.lua",
                     "TOS-Extras/cluster/master-skeleton/lib/cluster/pair.lua" }) do
  local chunk = loadfile(p); if chunk then masterPair = chunk(); break end
end
-- ── Load the MANAGER with the Manager's net ──────────────────────
package.loaded["kernel.net"] = makeNet(MANAGER, MASTER)
local mgr
for _, p in ipairs({ "../TOS-Extras/cluster/manager-skeleton/usr/lib/cluster-manager.lua",
                     "TOS-Extras/cluster/manager-skeleton/usr/lib/cluster-manager.lua" }) do
  local chunk = loadfile(p); if chunk then mgr = chunk(); break end
end
if not (masterPair and mgr) then
  print("FAIL: could not load the Master pair module and/or the Manager")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); os.exit(1)
end
masterPair.init({ trust = trustStub })
-- The Master's packet listener is registered by clusterd via netmod;
-- here the wire binds it directly.
wire.listeners[MASTER] = wire.listeners[MASTER] or {}
table.insert(wire.listeners[MASTER], { type = "T_CLUSTER_PAIR_INIT", id = 1,
  cb = function(pkt, from) masterPair.onPairInit(pkt, from) end })

print("=== cluster pairing, Manager <-> Master Tests ===")
print()

-- ── The happy path ───────────────────────────────────────────────
print("-- a real pairing --")
local code, expires = masterPair.startWindow()
test("the Master opened a window with a 24-char code", 24, #code)
test("...that expires in the future", true, expires > clock)

trustCalls = {}
local ok, msg = mgr.pair(MASTER, code)
test("the Manager reports paired", true, ok)
test("...with the message 'paired'", "paired", msg)
local sawInit, sawConfirm = false, false
for _, e in ipairs(wire.log) do
  if e.type == "T_CLUSTER_PAIR_INIT" and e.from == MANAGER then sawInit = true end
  if e.type == "T_CLUSTER_PAIR_CONFIRM" and e.from == MASTER then sawConfirm = true end
end
test("the init crossed the wire", true, sawInit)
test("the Master answered with a confirm (its MAC check passed)", true, sawConfirm)
local mgrTrusted, masterTrusted = false, false
for _, c in ipairs(trustCalls) do
  if c[1] == "level" and c[2] == MASTER then mgrTrusted = true end
  if c[1] == "level" and c[2] == MANAGER then masterTrusted = true end
end
test("the Manager trusts the Master", true, mgrTrusted)
test("the Master trusts the Manager", true, masterTrusted)
test("the Master records who paired", 1, masterPair.windowInfo().paired)

-- ── Wrong code ───────────────────────────────────────────────────
print()
print("-- wrong code --")
masterPair.closeWindow()
local code2 = masterPair.startWindow()
wire.log = {}
local ok2, msg2 = mgr.pair(MASTER, code2:sub(1, 12) .. "WRONGWRONGWR")
test("a wrong code does not pair", false, ok2)
local confirmed = false
for _, e in ipairs(wire.log) do if e.type == "T_CLUSTER_PAIR_CONFIRM" then confirmed = true end end
test("...and the Master never confirmed", false, confirmed)
test("the Manager says the confirm did not arrive", true, msg2:find("no confirm", 1, true) ~= nil)

-- ── A confirm from an impostor ───────────────────────────────────
print()
print("-- a forged confirm --")
masterPair.closeWindow()
local code3 = masterPair.startWindow()
wire.tamper = function(pkt)
  if pkt.type == "T_CLUSTER_PAIR_CONFIRM" then
    return { type = pkt.type, payload = { mac = string.rep("0", 64), ts = pkt.payload.ts }, to = pkt.to }
  end
end
local ok3, msg3 = mgr.pair(MASTER, code3)
wire.tamper = nil
test("a confirm with a bad MAC is not accepted", false, ok3)
test("...and says why", true, msg3:find("MAC mismatch", 1, true) ~= nil)

-- ── No window on the Master ──────────────────────────────────────
print()
print("-- no window open --")
masterPair.closeWindow()
wire.log = {}
local ok4 = mgr.pair(MASTER, code3)
test("with no window open the Master ignores the init", false, ok4)

-- ── A stale init (timestamp outside the window) ──────────────────
print()
print("-- replayed init --")
local code5 = masterPair.startWindow()
wire.tamper = function(pkt)
  if pkt.type == "T_CLUSTER_PAIR_INIT" then
    return { type = pkt.type, payload = { mac = pkt.payload.mac, ts = pkt.payload.ts - 1000 }, to = pkt.to }
  end
end
local ok5 = mgr.pair(MASTER, code5)
wire.tamper = nil
test("an init whose timestamp is outside the window is refused", false, ok5)

-- ── Refusals before any packet ───────────────────────────────────
print()
print("-- argument checks --")
test("a short master address is refused", false, (mgr.pair("short", code5)))
test("a short code is refused", false, (mgr.pair(MASTER, "abc")))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
