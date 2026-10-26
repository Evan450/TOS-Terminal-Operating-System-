-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: trusting a peer starts the key exchange      ║
-- ║                                                                ║
-- ║  Automatic Diffie-Hellman (e2f2445) rides on HELLO/HELLO_ACK,  ║
-- ║  the only packets that carry a DH public key. Nothing ever     ║
-- ║  sent a HELLO: net.hello had no caller since the first commit, ║
-- ║  so two real machines that trusted each other never agreed a   ║
-- ║  secret, and every sealed send was refused. test_trust_dh.lua  ║
-- ║  could not see it: it hands each side the other's key.         ║
-- ║                                                                ║
-- ║  Here: two REAL kernel.net instances over fake modems, the     ║
-- ║  bytes one sends handed to the other, and nothing called but   ║
-- ║  what an operator types: trust, then send.                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_trust_hello.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local clock = 100
package.loaded["computer"] = { uptime = function() return clock end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 2e6 end }

-- HELLO carries the version; the kernel sets _TOS before net starts.
_G._TOS = _G._TOS or { version = "test" }

local A = "aaaa0000-0000-0000-0000-00000000000a"
local B = "bbbb0000-0000-0000-0000-00000000000b"
local quiet = function() end

-- One real kernel.net over a fake modem whose sends land in `outbox`.
local function makeNode(myAddr)
  local outbox, warns = {}, {}
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
  package.loaded["kernel.net.trust"] = nil
  package.loaded["kernel.net.meshctl"] = nil
  package.loaded["kernel.net.mesh"] = nil
  local files = {}
  local net = dofile("tos/kernel/net/init.lua")
  net.init({
    log = { info = quiet, debug = quiet, error = quiet,
            warn = function(_, m) warns[#warns + 1] = tostring(m) end },
    config = { get = function() return nil end, deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = setmetatable({
      exists = function(p) return files[p] ~= nil end,
      readFile = function(p) return files[p] end,
      writeFile = function(p, c) files[p] = c; return true end,
      writeFileAtomic = function(p, c) files[p] = c; return true end,
    }, { __index = function() return function() return true end end }),
  })
  return { net = net, out = outbox, warns = warns, trust = net.getTrust(), addr = myAddr }
end

-- Hand everything `from` has sent to `to`, as its modem would, and empty
-- the outbox in place (the fake modem closes over that table).
local function deliver(from, to)
  local snap = {}
  for i, m in ipairs(from.out) do snap[i] = m end
  for i = #from.out, 1, -1 do from.out[i] = nil end
  for _, m in ipairs(snap) do
    if m.to == to.addr or m.to == "*" then to.net.handleIncoming(from.addr, 42, 1, m.data) end
  end
  return #snap
end

local function secret(node, peer)
  return node.trust.getSecret("root", peer, 3)
end
local PROTOCOL = require("kernel.net.protocol")
local function typesIn(node)
  local t = {}
  for _, m in ipairs(node.out) do
    local pkt = PROTOCOL.deserialize(m.data)
    t[#t + 1] = type(pkt) == "table" and tostring(pkt.type) or "?"
  end
  return table.concat(t, ",")
end

print("=== Trusting a peer says hello, and two trusts agree a secret ===")
print()

local a, b = makeNode(A), makeNode(B)
test("both machines have a DH identity", a.trust.getMyDhPublicKey() and b.trust.getMyDhPublicKey())

assert(a.trust.setLevel("root", B, a.trust.LEVEL.TRUSTED, 3))
test("A trusting B sends B a hello", typesIn(a):find("hello", 1, true) ~= nil, typesIn(a))
deliver(a, b)
test("B, which does not know A yet, does not answer", #b.out == 0, typesIn(b))
test("...and caches nothing from an UNKNOWN peer", not (b.trust.getPeer(A) or {}).dhPub)

assert(b.trust.setLevel("root", A, b.trust.LEVEL.TRUSTED, 3))
test("B trusting A sends A a hello", typesIn(b):find("hello", 1, true) ~= nil, typesIn(b))
deliver(b, a)
test("A now has a secret for B", secret(a, B) ~= nil)
test("A answers with a hello_ack", typesIn(a):find("hello_ack", 1, true) ~= nil, typesIn(a))
deliver(a, b)
test("B now has a secret for A", secret(b, A) ~= nil)
test("the two secrets are the same", secret(a, B) ~= nil and secret(a, B) == secret(b, A))

local heard
b.net.on("msg", function(...)
  for _, v in ipairs({ ... }) do
    if type(v) == "table" then
      local p = v.payload or v
      if type(p) == "table" and p.text then heard = p.text end
    end
  end
end)
local ok, err = a.net.sendMessage(B, "sealed hello")
test("A's sealed send is accepted (" .. tostring(err) .. ")", ok == true)
test("...and goes out encrypted", tostring((a.out[1] or {}).data):find("sealed hello", 1, true) == nil)
deliver(a, b)
test("B reads it", heard == "sealed hello", heard)

print()
print("=== A peer trusted with no key yet is asked for one ===")
print()

-- C is trusted by A before A's hello could reach it (it was off), so A
-- never got C's key. A send to C must ask again, not just refuse.
local C = "cccc0000-0000-0000-0000-00000000000c"
local c = makeNode(C)
a.trust.setLevel("root", C, a.trust.LEVEL.TRUSTED, 3)
for i = #a.out, 1, -1 do a.out[i] = nil end          -- that hello was lost
c.trust.setLevel("root", A, c.trust.LEVEL.TRUSTED, 3)
for i = #c.out, 1, -1 do c.out[i] = nil end          -- and so was C's
ok = a.net.sendMessage(C, "x")
test("a send with no secret is refused", ok == false)
test("...and asks the peer for its key", typesIn(a):find("hello", 1, true) ~= nil, typesIn(a))
deliver(a, c)
deliver(c, a)
test("the answer completes the exchange", secret(a, C) ~= nil and secret(a, C) == secret(c, A))
ok = a.net.sendMessage(C, "y")
test("the retry is sealed and accepted", ok == true)

-- Asking is rate-limited per peer.
local D = "dddd0000-0000-0000-0000-00000000000d"
a.trust.setLevel("root", D, a.trust.LEVEL.TRUSTED, 3)
for i = #a.out, 1, -1 do a.out[i] = nil end
a.net.sendMessage(D, "1"); a.net.sendMessage(D, "2")
local hellos = select(2, typesIn(a):gsub("hello", ""))
test("two refused sends in a row ask once", hellos == 1, typesIn(a))
clock = clock + 31
a.net.sendMessage(D, "3")
hellos = select(2, typesIn(a):gsub("hello", ""))
test("...and again after 30 s", hellos == 2, typesIn(a))

print()
print("=== The reinstalled peer, end to end ===")
print()

-- B is reinstalled: same address, empty /etc, a new key. Its operator
-- trusts A again, which says hello.
local b2 = makeNode(B)
test("the reinstalled B has a different key", b2.trust.getMyDhPublicKey() ~= b.trust.getMyDhPublicKey())
local before = secret(a, B)
b2.trust.setLevel("root", A, b2.trust.LEVEL.TRUSTED, 3)
deliver(b2, a)
test("A keeps the old secret", secret(a, B) == before)
test("A flags B's new key", (a.trust.getPeer(B) or {}).dhKeyChanged == true)
deliver(a, b2)
test("the new B has a secret, and it differs from A's", secret(b2, A) ~= nil and secret(b2, A) ~= before)
test("A logged what to do", table.concat(a.warns, "\n"):find("net trust rekey", 1, true) ~= nil)
test("A's operator accepts the key", a.trust.rekey("root", B, 3) == true)
test("the two sides agree again", secret(a, B) == secret(b2, A))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
