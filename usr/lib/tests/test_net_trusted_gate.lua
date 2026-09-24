-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what reaches a listener from a TRUSTED peer   ║
-- ║                                                                ║
-- ║  Two holes at the same gate in net.handleIncoming:              ║
-- ║                                                                ║
-- ║  1. nfs_req / nfs_res were in NO trust level's permission set,  ║
-- ║     so every netfs request was refused as "insufficient trust"  ║
-- ║     from a TRUSTED peer -- the #CLUSTER-1 bug again. netfs's own ║
-- ║     tests drive a fake net, which is why nobody saw it.         ║
-- ║  2. The MAC, sequence and nonce checks ran only for a packet    ║
-- ║     that SAID it was encrypted. A TRUSTED peer's packet with    ║
-- ║     no `enc` skipped all three and was dispatched as genuine -- ║
-- ║     which is exactly what a moved trusted modem, holding the    ║
-- ║     address but not the secret, would send.                     ║
-- ║                                                                ║
-- ║  Drives two REAL kernel.net instances, each with its own trust  ║
-- ║  manager, passing the bytes one's modem sends to the other.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_trusted_gate.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 5 end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 2e6 end }

local A_ADDR = "aaaa0000-0000-0000-0000-00000000000a"
local B_ADDR = "bbbb0000-0000-0000-0000-00000000000b"
local SECRET = "0123456789abcdefghijklmnopqrstuv"

-- One real kernel.net over a fake modem whose sends land in `outbox`.
local function makeNode(myAddr, cfg)
  local outbox = {}
  package.loaded["component"] = {
    list = function(t)
      local done = t ~= "modem"
      return function() if done then return nil end; done = true; return myAddr, "modem" end
    end,
    proxy = function() return {
      open = function() end, isWireless = function() return false end,
      send = function(to, _, data) outbox[#outbox + 1] = { to = to, data = data }; return true end,
      broadcast = function(_, data) outbox[#outbox + 1] = { to = "*", data = data }; return true end,
    } end,
  }
  package.loaded["kernel.net.trust"] = nil   -- each node its own trust DB
  local files = {}
  local net = dofile("tos/kernel/net/init.lua")
  local quiet = function() end
  net.init({
    log = { info = quiet, warn = quiet, debug = quiet, error = quiet },
    config = { get = function(k) return cfg and cfg[k] end,
               deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = { exists = function(p) return files[p] ~= nil end,
           readFile = function(p) return files[p] end,
           writeFile = function(p, c) files[p] = c; return true end },
  })
  return net, outbox
end

local function pair(trust, peer, withSecret)
  assert(trust.setLevel("root", peer, trust.LEVEL.TRUSTED, 3))
  if withSecret then assert(trust.setSecret("root", peer, SECRET, 3)) end
end

local netA, outA = makeNode(A_ADDR)
local netB = makeNode(B_ADDR)
local P = netA.getProtocol()
pair(netA.getTrust(), B_ADDR, true)
pair(netB.getTrust(), A_ADDR, true)

local function heard(net, ptype)
  local got = {}
  net.on(ptype, function(pkt) got[#got + 1] = pkt end)
  return got
end
-- What A's modem actually put on the wire, delivered to B.
local function relayAtoB()
  for _, m in ipairs(outA) do netB.handleIncoming(A_ADDR, 42, 1, m.data) end
  for i = #outA, 1, -1 do outA[i] = nil end
end
-- A packet written by hand, as a moved modem would: no enc, no mac.
local function forge(net, from, ptype, payload)
  local pkt = P.makePacket(ptype, payload)
  pkt.from = from
  net.handleIncoming(from, 42, 1, P.serialize(pkt))
end

print("=== the TRUSTED gate ===")
print()
print("-- every wire type can reach someone --")
do
  local trust = netB.getTrust()
  local NOBODY_LISTENS = { deny = true, error = true }
  local dead = {}
  for name, wire in pairs(P.TYPE) do
    if not NOBODY_LISTENS[wire] and not trust.isAllowed(A_ADDR, wire)
       and not trust.isAllowed("unseen-peer", wire) then
      dead[#dead + 1] = name
    end
  end
  table.sort(dead)
  test("no protocol type is refused at every trust level (" .. table.concat(dead, ", ") .. ")",
    #dead == 0)
  test("nfs_req is allowed from a TRUSTED peer", trust.isAllowed(A_ADDR, P.TYPE.NETFS_REQ))
  test("nfs_res is allowed from a TRUSTED peer", trust.isAllowed(A_ADDR, P.TYPE.NETFS_RES))
end

print()
print("-- sealed traffic between two paired machines --")
do
  local got = heard(netB, P.TYPE.NETFS_REQ)
  netA.send(B_ADDR, P.makePacket(P.TYPE.NETFS_REQ, { op = "space", share = "pub" }, { to = B_ADDR }))
  test("A seals a netfs request to B", outA[1] ~= nil and outA[1].data:find("mac", 1, true) ~= nil)
  relayAtoB()
  test("B's netfs listener receives it", #got == 1)
  test("...decrypted", got[1] and type(got[1].payload) == "table" and got[1].payload.op == "space")

  local msgs = heard(netB, P.TYPE.MSG)
  netA.send(B_ADDR, P.makePacket(P.TYPE.MSG, { text = "hello" }, { to = B_ADDR }))
  relayAtoB()
  test("a sealed chat message is delivered", #msgs == 1 and msgs[1].payload.text == "hello")

  print()
  print("-- the same packets, unsealed --")
  forge(netB, A_ADDR, P.TYPE.MSG, { text = "spoofed" })
  test("an unsealed MSG from a peer we share a secret with is dropped", #msgs == 1)
  forge(netB, A_ADDR, P.TYPE.NETFS_REQ, { op = "remove", share = "pub", path = "/" })
  test("an unsealed netfs request is dropped", #got == 1)
  local assigns = heard(netB, P.TYPE.CLUSTER_ASSIGN)
  forge(netB, A_ADDR, P.TYPE.CLUSTER_ASSIGN, { assignment_id = 1, tasks_inline = {} })
  test("an unsealed CLUSTER_ASSIGN is dropped", #assigns == 0)
  local revokes = heard(netB, P.TYPE.TRUST_REVOKE)
  forge(netB, A_ADDR, P.TYPE.TRUST_REVOKE, {})
  test("an unsealed TRUST_REVOKE is dropped", #revokes == 0)

  print()
  print("-- what stays unsealed by design --")
  local hellos = heard(netB, P.TYPE.HELLO)
  _G._TOS = { version = "test" }
  forge(netB, A_ADDR, P.TYPE.HELLO, { hostname = "a" })
  _G._TOS = nil
  test("a public type (HELLO) still arrives in the clear", #hellos == 1)
  local meshes = heard(netB, P.TYPE.MESH)
  forge(netB, A_ADDR, P.TYPE.MESH, { v = 1 })
  test("a mesh envelope (broadcast, sealed inside) still arrives", #meshes == 1)
end

print()
print("-- where there is nothing to check against --")
do
  local C_ADDR = "cccc0000-0000-0000-0000-00000000000c"
  pair(netB.getTrust(), C_ADDR, false)      -- TRUSTED, no shared secret
  local msgs = heard(netB, P.TYPE.MSG)
  forge(netB, C_ADDR, P.TYPE.MSG, { text = "no secret" })
  test("a TRUSTED peer with no shared secret is unchanged (delivered)", #msgs == 1)

  local netD = makeNode("dddd0000-0000-0000-0000-00000000000d", { encryptComms = false })
  pair(netD.getTrust(), A_ADDR, true)
  local dmsgs = heard(netD, P.TYPE.MSG)
  forge(netD, A_ADDR, P.TYPE.MSG, { text = "operator chose plaintext" })
  test("with encryptComms off, plaintext is accepted as before", #dmsgs == 1)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
