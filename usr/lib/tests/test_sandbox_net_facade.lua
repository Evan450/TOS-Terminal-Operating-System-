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

-- ══════════════════════════════════════════════════════════════════
-- #SEC — listen / off / send, against the REAL kernel.net listeners
-- ══════════════════════════════════════════════════════════════════
-- The facade passed on/off/onceFrom/send/broadcast through raw. So a
-- program holding `net` could: net.on("*") and receive every packet
-- AFTER decryption; mutate the LIVE packet before a kernel listener read
-- it; net.off() the kernel's own handlers (ids are global counters); and
-- send REMOTE_EXEC / NETFS_RES / TRUST_* sealed as this machine.
--
-- The real module's on/off/onceFrom are used here (they need no init).
-- Its dispatcher is private, so its `listeners` table is reached through
-- debug and walked exactly the way dispatchToListeners walks it.
print()
print("-- #SEC: what a program may hear, remove and send --")
do
  local realNet
  for _, p in ipairs({ "tos/kernel/net/init.lua", "TOS-Dev/tos/kernel/net/init.lua" }) do
    local chunk = loadfile(p)
    if chunk then realNet = chunk(); break end
  end
  test("the real kernel.net loads", type(realNet) == "table")
  local listeners
  for i = 1, 16 do
    local name, v = debug.getupvalue(realNet.off, i)
    if name == nil then break end
    if name == "listeners" then listeners = v end
  end
  test("...and its listener table is reachable", type(listeners) == "table")

  -- Exactly dispatchToListeners: one packet table, every listener in
  -- registration order, then the catch-all.
  local function dispatch(msgType, packet, from)
    for _, e in ipairs(listeners[msgType] or {}) do pcall(e.cb, packet, from) end
    for _, e in ipairs(listeners["*"] or {}) do pcall(e.cb, packet, from) end
  end

  -- The allowlist must name real protocol types, or it silently allows
  -- nothing (or, worse, the wrong thing) after a rename.
  local okProto, proto = pcall(dofile, "tos/kernel/net/protocol.lua")
  if okProto and type(proto) == "table" and type(proto.TYPE) == "table" then
    local all = true
    for _, name in ipairs({ "PING", "PONG", "HELLO", "HELLO_ACK", "INFO_REQ",
                            "INFO_RES", "MSG", "MSG_ACK", "DENY", "ERROR" }) do
      if proto.TYPE[name] ~= name:lower() then all = false end
    end
    test("every allowed type is a real protocol type, spelled as the facade expects", all)
  end

  -- Kernel code registers first, as it does at boot.
  local kernelMesh = realNet.on("mesh", function() end)
  local kernelNfs  = realNet.on("nfs_req", function() end)

  local sent = {}
  realNet.send      = function(addr, pkt) sent[#sent + 1] = pkt; return true end
  realNet.broadcast = function(pkt) sent[#sent + 1] = pkt; return true end
  package.loaded["kernel.net"] = realNet
  local prog = sandbox.build({ caps = { net = true } }).net

  -- 1. Sniffing.
  local sniffed = 0
  local idStar = prog.on("*", function() sniffed = sniffed + 1 end)
  test("a program cannot listen on the catch-all '*'", idStar == nil)
  test("...and nothing was registered", listeners["*"] == nil or #listeners["*"] == 0)
  test("a program cannot listen for netfs replies",
    prog.on("nfs_res", function() end) == nil)
  test("...nor for remote-exec output (onceFrom too)",
    prog.onceFrom("remote_res", "peer", function() end) == nil)
  test("...nor for pairing handshakes", prog.on("ch_pair_init", function() end) == nil)
  dispatch("nfs_res", { type = "nfs_res", payload = { data = "secret" } }, "peer")
  test("a decrypted netfs reply reaches no program", sniffed == 0)

  -- 2. Tampering: the program listens first, a kernel listener second.
  local progSaw, kernelSaw
  local idMsg = prog.on("msg", function(pkt)
    progSaw = pkt.payload and pkt.payload.text
    if pkt.payload then pkt.payload.text = "forged" end
    pkt.type = "remote_exec"
  end)
  test("a program may still listen for chat (MSG)", idMsg ~= nil)
  realNet.on("msg", function(pkt) kernelSaw = pkt.payload.text .. "|" .. pkt.type end)
  dispatch("msg", { type = "msg", payload = { text = "hello" } }, "peer")
  test("...and hears it", progSaw == "hello")
  test("...but what it changes, nobody else sees", kernelSaw == "hello|msg")

  -- 3. Removing other people's listeners.
  test("a program cannot remove the kernel's mesh listener",
    prog.off("mesh", kernelMesh) == false)
  prog.offAll({ { type = "nfs_req", id = kernelNfs }, { type = "mesh", id = kernelMesh } })
  local stillMesh, stillNfs = false, false
  for _, e in ipairs(listeners.mesh or {}) do if e.id == kernelMesh then stillMesh = true end end
  for _, e in ipairs(listeners.nfs_req or {}) do if e.id == kernelNfs then stillNfs = true end end
  test("...nor with offAll: the kernel's mesh and netfs handlers stay",
    stillMesh and stillNfs)
  test("it can remove its OWN listener", prog.off("msg", idMsg) == true)
  test("...once", prog.off("msg", idMsg) == false)

  -- 4. Sending as the machine.
  local okX, errX = prog.send("peer", { type = "remote_exec", payload = { cmd = "x" } })
  test("a program cannot send REMOTE_EXEC (rsh is admin-only)", not okX and #sent == 0)
  test("...and is told why", type(errX) == "string" and errX:find("remote_exec", 1, true) ~= nil)
  test("...nor forge a netfs reply", not prog.send("peer", { type = "nfs_res", payload = {} }))
  test("...nor broadcast a trust revocation", not prog.broadcast({ type = "trust_rev" }))
  test("nothing reached the wire", #sent == 0)

  local lying = setmetatable({}, { __index = function(_, k)
    if k == "type" then return "msg" end
  end })
  test("a packet whose metatable lies about its type is refused",
    not prog.send("peer", lying) and #sent == 0)

  test("a chat message still sends", prog.send("peer", { type = "msg", payload = { text = "hi" } }))
  test("...as a plain copy", sent[1] and getmetatable(sent[1]) == nil
    and sent[1].type == "msg" and sent[1].payload.text == "hi")
  package.loaded["kernel.net"] = net
end

print()
print("-- an rc.d service keeps the full module --")
local svc = sandbox.build({ caps = { net = true }, allowUserLibs = true })
test("a service can still arm itself", type(svc.net.setServiceArm) == "function")
svc.net.setServiceArm("rshd", true)
test("...and the call reaches the kernel", armed.rshd == true)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
