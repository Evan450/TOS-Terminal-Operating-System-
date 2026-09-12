-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the `net` capability is a facade              ║
-- ║                                                                ║
-- ║  sandbox.build handed a program holding `net` the whole         ║
-- ║  kernel.net module (Sep 2026 pentest): getTrust() -- the trust  ║
-- ║  manager, setLevel/setSecret included -- handleIncoming (inject ║
-- ║  a packet "from" anyone), setServiceArm (arm rshd), shutdown(), ║
-- ║  and the live peer-discovery records, whose .addr a program     ║
-- ║  could rewrite to redirect everyone else's ssh/share.           ║
-- ║                                                                ║
-- ║  Drives the REAL sandbox.build against a kernel.net stand-in    ║
-- ║  that behaves like the real one where it matters (live records, ║
-- ║  shared protocol table).                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_net_facade.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 500000 end,
  pushSignal = function() end, address = function() return "addr" end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local serverRec = { addr = "real-server-addr", hostname = "server", trust = 3 }
local discovered = { ["real-server-addr"] = serverRec }
local protocol = { TYPE = { PING = "ping" } }
local trustMgr = { setLevel = function() return true end, getSecret = function() return "S" end }
local armed = {}
local net = {
  _trustToken    = "tok",
  send           = function() return true end,
  on             = function() return 1 end,
  onceFrom       = function() return 1 end,
  getTrust       = function() return trustMgr end,
  handleIncoming = function() return true end,
  setServiceArm  = function(n, on) armed[n] = on end,
  shutdown       = function() return true end,
  peers          = function() local out = {}; for _, p in pairs(discovered) do out[#out + 1] = p end; return out end,
  findPeer       = function(q) if discovered[q] then return discovered[q] end
                     for _, p in pairs(discovered) do if p.hostname == q then return p end end end,
  getProtocol    = function() return protocol end,
  status         = function() return { available = true, peers = { total = 1 } } end,
}
package.loaded["kernel.net"] = net

local sandbox = require("kernel.sandbox")
local env = sandbox.build({ caps = { net = true } })
local n = env.net

print("=== the net capability is a facade ===")
print()
test("the facade exists", type(n) == "table")
test("it can send", type(n.send) == "function")
test("it can listen", type(n.on) == "function" and type(n.onceFrom) == "function")
test("no trust manager (getTrust)", n.getTrust == nil)
test("no packet injection (handleIncoming)", n.handleIncoming == nil)
test("no service arming (setServiceArm)", n.setServiceArm == nil)
test("no shutdown", n.shutdown == nil)
test("no internals (_trustToken)", n._trustToken == nil)

local p = n.findPeer("server")
test("findPeer still answers", p and p.addr == "real-server-addr")
if p then p.addr = "attacker-addr" end
test("...but rewriting what it returned does not redirect anyone", serverRec.addr == "real-server-addr")
local list = n.peers()
if list[1] then list[1].hostname = "spoofed" end
test("peers() returns copies too", serverRec.hostname == "server")
local proto = n.getProtocol()
proto.TYPE = {}
test("getProtocol() is a view; the shared protocol table is untouched", protocol.TYPE.PING == "ping")
test("status() carries no live tables", n.status().peers == nil)

print("-- an rc.d service keeps the full module --")
local svc = sandbox.build({ caps = { net = true }, allowUserLibs = true })
test("a service can still arm itself", type(svc.net.setServiceArm) == "function")
svc.net.setServiceArm("rshd", true)
test("...and the call reaches the kernel", armed.rshd == true)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
