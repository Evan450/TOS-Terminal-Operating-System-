-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the Master refuses unauthenticated relays     ║
-- ║                                                                ║
-- ║  A RELAY_FORWARD's inner packet was serialize.encode(pkt): no   ║
-- ║  encryption, no MAC -- and the Master took its origin from the  ║
-- ║  inner packet's own `from`. Any trusted Manager could wrap a    ║
-- ║  RESULT, HEARTBEAT or REGISTER "from" another Manager and have  ║
-- ║  the Master accept it as theirs, and rewrite that Manager's     ║
-- ║  return path so its next assignment went to the relay instead.  ║
-- ║  No Manager sends RELAY_FORWARD (cluster.relayHandle has no     ║
-- ║  caller), so refusing it costs nothing that worked.             ║
-- ║                                                                ║
-- ║  Drives the REAL master-skeleton cluster/net.lua.               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_relay_refused.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 100 end }
local quiet = function() end
package.loaded["kernel.log"] = { info = quiet, warn = quiet, error = quiet }

local listeners = {}
package.loaded["kernel.net"] = {
  on = function(t, cb) listeners[t] = cb; return #listeners + 1 end,
  off = function() end,
  send = function() return true end,
}
local protocol = require("kernel.net.protocol")
package.loaded["kernel.net.protocol"] = protocol
local serialize = require("kernel.serialize")

local netmod
for _, p in ipairs({ "TOS-Extras/cluster/master-skeleton/lib/cluster/net.lua",
                     "../TOS-Extras/cluster/master-skeleton/lib/cluster/net.lua" }) do
  local chunk = loadfile(p); if chunk then netmod = chunk(); break end
end
if not netmod then
  print("FAIL: could not load the Master's cluster/net.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); os.exit(1)
end

local calls = {}
local function rec(name) return function(pkt, from) calls[#calls + 1] = { name, from, pkt } end end
netmod.register({
  onRegister = rec("register"), onHeartbeat = rec("heartbeat"),
  onResult = rec("result"), onResultChunk = rec("chunk"),
  onAssignAck = rec("ack"), onStatusRes = rec("status"),
  onRelayFail = rec("relayfail"), onPairInit = rec("pairinit"),
})

local T = netmod.TYPE
local EVIL, VICTIM = "evil0000-manager", "victim00-manager"
local function relay(inner, path)
  listeners[T.RELAY_FORWARD]({
    type = T.RELAY_FORWARD,
    payload = { dest = "master", path = path or { EVIL }, ttl = 3,
                inner = serialize.encode(inner), inner_type = inner.type },
  }, EVIL)
end

print("=== the Master and RELAY_FORWARD ===")
print()
test("the Master listens for RELAY_FORWARD", type(listeners[T.RELAY_FORWARD]) == "function")

relay({ type = T.CLUSTER_RESULT, from = VICTIM,
        payload = { assignment_id = 7, status = "ok", outputs = { "forged" } } })
test("a RESULT claiming to be another Manager's is not accepted", #calls == 0)

relay({ type = T.CLUSTER_HEARTBEAT, from = VICTIM, payload = { state = "active" } }, { EVIL })
test("a HEARTBEAT in another Manager's name is not accepted", #calls == 0)
test("...and the victim's return path was not rewritten",
  not netmod.hasRelayReturnPath(VICTIM))

relay({ type = T.CLUSTER_REGISTER, from = EVIL, payload = {} })
test("even a relay speaking for itself is refused (nothing sends one)", #calls == 0)

-- The direct path is unaffected.
listeners[T.CLUSTER_HEARTBEAT]({ type = T.CLUSTER_HEARTBEAT, payload = { state = "active" } }, VICTIM)
test("a direct HEARTBEAT still reaches its handler", #calls == 1 and calls[1][1] == "heartbeat"
  and calls[1][2] == VICTIM)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
