-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: one trusted neighbour cannot fill a relay     ║
-- ║                                                                ║
-- ║  A relay keeps a copy of each unicast envelope it passes on,    ║
-- ║  re-flooding it for RELAY_HOLD (120 s), and nothing bounded     ║
-- ║  how many. 40 unique 7 KB envelopes a second for two minutes    ║
-- ║  left a relay holding 3840 of them -- 28 MB -- and it re-flooded ║
-- ║  them 13440 times. The dedup cache kept 512 ids of any length:  ║
-- ║  7 KB ids made it 3.5 MB (Sep 2026 pentest). Mesh traffic comes ║
-- ║  only from TRUSTED neighbours, but every relay forwards to its  ║
-- ║  own, so one bad node anywhere could take down every relay.     ║
-- ║  Drives the REAL kernel.net.mesh and kernel.net.meshctl.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mesh_bounds.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e9 end }
local meshctl = require("kernel.net.meshctl")
local mesh = require("kernel.net.mesh")
local T = 0
pcall(meshctl.init, { log = nil, clock = function() return T end })
local function kb() collectgarbage(); collectgarbage(); return collectgarbage("count") end
local HOLD_MAX = mesh.RELAY_HOLD_MAX or -1

print("=== one trusted neighbour cannot fill a relay ===")
print()
-- 1. The measured flood.
local sent = 0
local node = meshctl.new({ myAddr = "relay", clock = function() return T end,
  broadcast = function() sent = sent + 1 end })
local base = kb()
local n = 0
for sec = 0, 119 do
  T = sec
  for _ = 1, 40 do
    n = n + 1
    node:onPacket({ id = "e" .. n, kind = "msg", from = "attacker", to = "someone-else",
      ttl = 8, path = {}, svc = "mail", sealed = string.rep("z", 7000) .. n })
  end
  node:tick(T)
end
local held, kept = mesh.pending(node.outbox), kb() - base
test(string.format("two minutes of 7 KB envelopes at 40/s: the relay holds %d and keeps %.0f KB", held, kept),
  held <= HOLD_MAX and kept < 128)
test(string.format("...and floods %d times for %d received, not a multiple of it", sent, n), sent <= n)

-- 2. Small messages are still held for store-and-forward -- the newest few.
T = 0
local node2 = meshctl.new({ myAddr = "relay2", clock = function() return T end, broadcast = function() end })
for i = 1, 30 do
  node2:onPacket({ id = "s" .. i, kind = "msg", from = "a", to = "c", ttl = 4, path = {},
    svc = "mail", sealed = string.rep("y", 1000) })
end
test("small relayed messages are still held, at most " .. tostring(mesh.RELAY_HOLD_MAX),
  mesh.pending(node2.outbox) == HOLD_MAX)
test("...and the ones kept are the newest", node2.outbox.items["s30"] ~= nil and node2.outbox.items["s1"] == nil)

-- 3. The dedup cache holds ids, not whatever a sender calls an id.
local node3 = meshctl.new({ myAddr = "relay3", clock = function() return 0 end, broadcast = function() end })
local b3 = kb()
for i = 1, 512 do
  node3:onPacket({ id = string.rep("i", 7000) .. i, kind = "ack", from = "a", to = "*", ttl = 0, path = {} })
end
local k3 = kb() - b3
test(string.format("512 envelopes with 7 KB ids leave %.0f KB behind", k3), k3 < 32)

-- 4. Hop budgets and paths are what the protocol says they are.
local r = mesh.route({ id = "t1", kind = "msg", from = "a", to = "c", ttl = 1e9, path = {} },
  "me", nil, mesh.newSeen())
test("a huge ttl is clamped before it is relayed", r.forward and r.out.ttl <= (mesh.MAX_TTL or 0) - 1)
local okS = pcall(mesh.route, { id = "t2", kind = "msg", from = "a", to = "c", ttl = "8", path = {} },
  "me", nil, mesh.newSeen())
test("a ttl sent as a string does not raise", okS)
local r3 = mesh.route({ id = "t3", kind = "msg", from = "a", to = "c", ttl = 4, path = "junk" },
  "me", nil, mesh.newSeen())
test("a path that is not a list is refused", not r3.forward and not r3.deliver)

-- 5. A plaintext payload is a table of any size: relayed, never held.
local node4 = meshctl.new({ myAddr = "relay4", clock = function() return 0 end, broadcast = function() end })
local act = node4:onPacket({ id = "p1", kind = "msg", from = "a", to = "c", ttl = 4, path = {},
  svc = "mail", payload = { body = "hi" } })
test("a plaintext envelope is relayed but not held",
  act.forward and mesh.pending(node4.outbox) == 0)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
