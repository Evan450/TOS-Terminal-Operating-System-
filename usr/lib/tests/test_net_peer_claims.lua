-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what a peer says about itself                 ║
-- ║                                                                ║
-- ║  PING/PONG payloads come from UNKNOWN peers and were recorded   ║
-- ║  as-is (Sep 2026 pentest): a number as the hostname crashed the ║
-- ║  sort in net.peers() for every later caller -- `net peers`,     ║
-- ║  `net scan`, discovery -- and control characters and 8 KB names ║
-- ║  went straight to the screen. findPeer() raised on a non-string ║
-- ║  query and matched everyone on "".                              ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.net discovery table.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_peer_claims.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 5 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
local net = dofile("tos/kernel/net/init.lua")

print("=== peer claims are sanitised ===")
print()
net._recordPeer("addr-number", { hostname = 5, device = {} })
net._recordPeer("addr-escape", { hostname = "srv\27[2J\n", device = "robot" })
net._recordPeer("addr-huge",   { hostname = string.rep("x", 8192) })
net._recordPeer("addr-plain",  { hostname = "server" })
local ok, list = pcall(net.peers)
test("net.peers() survives a numeric hostname", ok and type(list) == "table" and #list == 4)
local byAddr = {}
for _, p in ipairs(ok and list or {}) do byAddr[p.addr] = p end
test("a non-string hostname is dropped", byAddr["addr-number"] and byAddr["addr-number"].hostname == nil)
test("a non-string device is dropped", byAddr["addr-number"] and byAddr["addr-number"].device == nil)
test("control characters are stripped",
  byAddr["addr-escape"] and byAddr["addr-escape"].hostname == "srv[2J")
test("an 8 KB name is cut to 32", byAddr["addr-huge"] and #byAddr["addr-huge"].hostname == 32)
test("an ordinary name is kept", byAddr["addr-plain"] and byAddr["addr-plain"].hostname == "server")
local okF, r = pcall(net.findPeer, 5)
test("findPeer(5) returns nothing rather than raising", okF and r == nil)
test("findPeer('') does not match everyone", net.findPeer("") == nil)
test("findPeer by name still works", (net.findPeer("server") or {}).addr == "addr-plain")

-- The table is bounded: 200 distinct pingers leave at most 64 entries, and
-- the newest is among them.
for i = 1, 200 do net._recordPeer(string.format("flood-%03d", i), { hostname = "f" .. i }) end
local okP, all = pcall(net.peers)
test("200 distinct pingers leave at most 64 entries (" .. tostring(okP and #all) .. ")",
  okP and #all <= 64)
test("...and the newest is kept", net.findPeer("flood-200") ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
