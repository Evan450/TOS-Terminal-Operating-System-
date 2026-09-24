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

-- ── The other hostnames a peer sends ─────────────────────────────
-- The fix above covered PING/PONG only. TRUST_REQ (from ANY peer) and
-- HELLO / HELLO_ACK (from KNOWN ones) carried the same claim straight into
-- the pending-request list and /etc/trust.dat: a table raised inside the
-- trust manager after the record was already stored, and 8 KB of escape
-- codes reached `net requests` / `net peers`. Driven through the REAL
-- net.handleIncoming, with the real trust manager, over a fake modem.
print()
print("-- TRUST_REQ and HELLO hostnames --")
do
  local files = {}
  local fsStub = {
    exists = function(p) return files[p] ~= nil end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c) files[p] = c; return true end,
  }
  local MODEM = "0000aaaa-0000-0000-0000-000000000000"
  package.loaded["computer"] = { uptime = function() return 5 end,
    freeMemory = function() return 1e6 end, totalMemory = function() return 2e6 end }
  package.loaded["component"] = {
    list = function(t)
      local done = t ~= "modem"
      return function() if done then return nil end; done = true; return MODEM, "modem" end
    end,
    proxy = function() return { open = function() end, isWireless = function() return false end,
      send = function() return true end, broadcast = function() return true end } end,
  }
  for _, m in ipairs({ "kernel.net", "kernel.net.trust", "kernel.net.protocol", "kernel.crypto" }) do
    package.loaded[m] = nil
  end
  local quiet = function() end
  local live = dofile("tos/kernel/net/init.lua")
  live.init({
    log = { info = quiet, warn = quiet, debug = quiet, error = quiet },
    config = { get = function() return nil end, deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = fsStub,
  })
  local protocol = live.getProtocol()
  local trustMgr = live.getTrust()
  local function deliver(from, ptype, payload)
    local raw = protocol.serialize(protocol.makePacket(ptype, payload))
    return pcall(live.handleIncoming, from, 42, 1, raw)
  end

  local STRANGER = "5555aaaa-0000-0000-0000-000000000001"
  local okT = deliver(STRANGER, protocol.TYPE.TRUST_REQ, { hostname = {} })
  test("a TRUST_REQ with a table hostname does not raise", okT)
  deliver("5555aaaa-0000-0000-0000-000000000002", protocol.TYPE.TRUST_REQ,
    { hostname = "evil\27[2J" .. string.rep("x", 5000) })
  local reqs = trustMgr.getPendingRequests()
  test("...the request is still recorded", reqs[STRANGER] ~= nil)
  test("...with no hostname rather than a table", reqs[STRANGER] and reqs[STRANGER].hostname == nil)
  local r2 = reqs["5555aaaa-0000-0000-0000-000000000002"]
  test("an escape-laden 5 KB name arrives printable and cut to 32",
    r2 and type(r2.hostname) == "string" and #r2.hostname == 32 and not r2.hostname:find("%c"))
  test("trust.addPendingRequest cleans on its own too", (function()
    trustMgr.addPendingRequest("5555aaaa-0000-0000-0000-000000000003", 42)
    local r = trustMgr.getPendingRequests()["5555aaaa-0000-0000-0000-000000000003"]
    return r ~= nil and r.hostname == nil
  end)())

  local FRIEND = "6666aaaa-0000-0000-0000-000000000001"
  assert(trustMgr.setLevel("root", FRIEND, trustMgr.LEVEL.KNOWN, 3))
  deliver(FRIEND, protocol.TYPE.HELLO, { hostname = "srv\n\27[31m" })
  test("a HELLO hostname is stored printable", trustMgr.getPeer(FRIEND).hostname == "srv[31m")
  deliver(FRIEND, protocol.TYPE.HELLO_ACK, { hostname = { "not", "a", "name" } })
  test("a HELLO_ACK table hostname is stored as nothing", trustMgr.getPeer(FRIEND).hostname == nil)
  deliver(FRIEND, protocol.TYPE.HELLO_ACK, { hostname = "vault" })
  test("an ordinary HELLO_ACK name is kept", trustMgr.getPeer(FRIEND).hostname == "vault")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
