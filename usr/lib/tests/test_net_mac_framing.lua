-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the packet MAC frames its fields             ║
-- ║                                                                ║
-- ║  AUDIT 5. The tag covered a \0-joined concat of variable,      ║
-- ║  attacker-influenced fields, so a captured packet could be     ║
-- ║  reshaped across a boundary and keep its tag: moving a byte    ║
-- ║  from the nonce into the payload left the joined string the    ║
-- ║  same, which quietly defeats the nonce ring. The H-3 sequence  ║
-- ║  check stopped a replay, but the ring is documented as the     ║
-- ║  second layer and this removed it.                             ║
-- ║                                                                ║
-- ║  Here: two REAL kernel.net instances over fake modems, a real  ║
-- ║  sealed packet captured off the wire, and the reshapes tried.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_mac_framing.lua   (from TOS-Dev)

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
_G._TOS = _G._TOS or { version = "test" }

local A = "aaaa0000-0000-0000-0000-00000000000a"
local B = "bbbb0000-0000-0000-0000-00000000000b"
local quiet = function() end

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

local function drain(from, to)
  local snap = {}
  for i, m in ipairs(from.out) do snap[i] = m end
  for i = #from.out, 1, -1 do from.out[i] = nil end
  if to then
    for _, m in ipairs(snap) do
      if m.to == to.addr or m.to == "*" then to.net.handleIncoming(from.addr, 42, 1, m.data) end
    end
  end
  return snap
end

local PROTOCOL = require("kernel.net.protocol")
local function trustBoth(a, b)
  assert(a.trust.setLevel("root", b.addr, a.trust.LEVEL.TRUSTED, 3))
  drain(a, b)
  assert(b.trust.setLevel("root", a.addr, b.trust.LEVEL.TRUSTED, 3))
  drain(b, a); drain(a, b); drain(b, a)
end

local a, b = makeNode(A), makeNode(B)
trustBoth(a, b)
test("the two machines agreed a secret", b.trust.getSecret("root", A, 3) ~= nil)

local heard = {}
b.net.on("msg", function(pkt) heard[#heard + 1] = pkt end)

local function capture(text)
  assert(a.net.send(B, PROTOCOL.makePacket("msg", { text = text or "hi" }, { to = B })))
  local snap = drain(a)
  return PROTOCOL.deserialize(snap[#snap].data)
end
local function inject(pkt)
  b.warns[#b.warns + 1] = nil
  local before = #heard
  for i = #b.warns, 1, -1 do b.warns[i] = nil end
  b.net.handleIncoming(A, 42, 1, PROTOCOL.serialize(pkt))
  return #heard > before, table.concat(b.warns, " | ")
end
local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end

print("=== a sealed packet is framed ===")
local pkt = capture()
test("it says which framing it used", pkt.macv == 2, pkt.macv)
test("the untouched packet is accepted", (inject(copy(pkt))))

print("=== a captured packet cannot be reshaped ===")
do
  -- The audit's case. Ciphertext holds \0 bytes, so a nonce can swallow the
  -- start of the payload up to one, and the old \0-join reads the same.
  local p, cut
  for i = 1, 2000 do
    -- The text varies: the software cipher gives one message one ciphertext.
    p = capture(string.rep(string.char(33 + i % 90), 40))
    cut = p.payload:find("\0", 1, true)
    if cut and cut <= 40 then break end
    cut = nil
  end
  test("a real packet with a \\0 early in its ciphertext turned up", cut ~= nil)
  local q = copy(p)
  q.nonce = p.nonce .. "\0" .. p.payload:sub(1, cut - 1)
  q.payload = p.payload:sub(cut + 1)
  local ok, why = inject(q)
  test("the nonce swallowing part of the payload is refused", not ok, why)
  test("for the tag, before anything is decrypted", why:find("MAC mismatch", 1, true) ~= nil, why)
  local r = copy(p)
  r.nonce = r.nonce .. "x"
  test("a nonce with a byte added is refused", not (inject(r)))
  local s = copy(p)
  s.to = s.to .. "\0" .. tostring(s.enc)
  s.enc = ""
  test("a field split across the type/to boundary is refused", not (inject(s)))
  test("and the real one still lands", (inject(copy(p))))
end

print("=== a framed tag cannot pass as the old kind ===")
do
  local p = capture()
  local q = copy(p)
  q.macv = nil
  local ok, why = inject(q)
  test("stripping the marker does not downgrade it", not ok, why)
  test("for the tag", why:find("MAC mismatch", 1, true) ~= nil, why)
end

print("=== a peer still on the old build keeps working ===")
do
  -- What an older TOS sends: the \0-joined tag, no macv.
  local crypto = require("kernel.crypto")
  local secret = b.trust.getSecret("root", A, 3)
  local p = capture()
  p.macv = nil
  p.seq = tonumber(p.seq) + 100
  p.nonce = crypto.salt(16)
  p.mac = crypto.hmac(secret, table.concat({
    p.type or "", p.to or "", p.enc or "", p.epoch, tostring(p.seq), p.nonce, p.payload,
  }, "\0"))
  local ok, why = inject(p)
  test("an old-format tag from a real peer is accepted", ok, why)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
