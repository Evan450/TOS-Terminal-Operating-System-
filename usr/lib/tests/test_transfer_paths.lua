-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.net.transfer's two path boundaries    ║
-- ║                                                                ║
-- ║  1. transfer.request(addr, remote, local, { session = s })     ║
-- ║     wrote the reply through securefs.writeFile(p, data,         ║
-- ║     { session = s }) -- but securefs's third argument IS the    ║
-- ║     session. The ACL got a table with no tier and raised,       ║
-- ║     inside a pcall'd net listener, so a caller using the        ║
-- ║     documented opts.session got "Timeout waiting for response"  ║
-- ║     for a reply that had arrived, and nothing was written.      ║
-- ║     And a SUCCESS returned (true, "Timeout waiting for          ║
-- ║     response"): `result, result and nil or errMsg` is always    ║
-- ║     errMsg, the classic `x and nil or y` trap.                  ║
-- ║  2. handleRequest took a path from the wire and called          ║
-- ║     fs.normalize(path):sub(...). A path normalize refuses (not  ║
-- ║     a string, a NUL byte) is nil: the handler raised instead of ║
-- ║     answering FILE_DENY, and the peer waited out its timeout.   ║
-- ║                                                                ║
-- ║  The REAL transfer, securefs and users modules; the net layer   ║
-- ║  is a stand-in whose listener dispatch is pcall'd, as the       ║
-- ║  kernel's dispatchToListeners is.                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_transfer_paths.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_transfer_paths.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = "tos/?.lua;" .. base .. "../../../tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end,
                                     yieldCooperative = function() end }

print("=== kernel.net.transfer path boundaries ===")
print()

-- ── Real ACL stack over a recording filesystem ────────────────────
local kfs = require("kernel.fs")
local users = require("kernel.users")
users.init({ fs = { normalize = kfs.normalize, exists = function() return false end,
  readFile = function() return nil end, writeFile = function() return true end,
  makeDirectory = function() return true end },
  crypto = { init = function() end, hasHardware = function() return false end,
    salt = function(n) return string.rep("s", n or 16) end,
    hashPassword = function(pw, s) return "h:" .. pw .. s end } })
local written = {}
local fsRec = setmetatable({
  writeFile = function(p, c) written[p] = c; return true end,
  exists    = function(p) return p == "/public/hello.txt" end,
  size      = function() return 5 end,
  readFile  = function(p) if p == "/public/hello.txt" then return "hello" end end,
}, { __index = kfs })
local securefs = require("kernel.securefs")
securefs.init({ fs = fsRec, users = users, log = nil })

-- ── A net stand-in: listeners by type, dispatched under pcall ─────
local listeners, nextId, sent, reply = {}, 0, {}, nil
local listenerErrors = {}
local net = {}
function net.onceFrom(t, addr, cb)
  nextId = nextId + 1
  listeners[#listeners + 1] = { t = t, addr = addr, cb = cb, id = nextId }
  return nextId
end
function net.on() nextId = nextId + 1; return nextId end   -- the FILE_REQ server hook
function net.offAll() listeners = {} end
function net.waitFor(pred) return pred() end
function net.verifyPeer() return true end
function net.send(addr, pkt)
  sent[#sent + 1] = pkt
  if reply then   -- the peer answers at once
    for _, l in ipairs(listeners) do
      if l.t == reply.type and l.addr == addr then
        local ok, err = pcall(l.cb, reply, addr)
        if not ok then listenerErrors[#listenerErrors + 1] = tostring(err) end
      end
    end
  end
  return true
end

local protocol = require("kernel.net.protocol")
local transfer = require("kernel.net.transfer")
transfer.init({ net = net, fs = fsRec, securefs = securefs, users = users,
  trust = { getLevel = function() return 3 end, LEVEL = { TRUSTED = 3 } } })

-- ── 1. The documented opts.session path ───────────────────────────
print("-- request(..., { session = s }) --")
local T = users.TIER
local alice = { user = "alice", tier = T.USER, home = "/home/alice" }
reply = protocol.makePacket(protocol.TYPE.FILE_RES,
  { path = "/public/hello.txt", data = "hello", size = 5 })
local ok, err = transfer.request("peer", "/public/hello.txt", "/home/alice/hello.txt",
  { session = alice })
test("the reply is written", ok == true)
test("...and success carries no error (was 'Timeout waiting for response'; got "
  .. tostring(err) .. ")", err == nil)
test("...to alice's own home, through securefs", written["/home/alice/hello.txt"] == "hello")
test("...with no listener error on the way", #listenerErrors == 0)

-- securefs is really consulted, as alice: another user's home is refused.
written = {}
local okB = transfer.request("peer", "/public/hello.txt", "/home/bob/hello.txt",
  { session = alice })
test("alice cannot land a file in bob's home", okB ~= true and written["/home/bob/hello.txt"] == nil)

-- ── 2. A path from the wire that does not normalise ───────────────
print()
print("-- handleRequest with a hostile path --")
transfer.setEnabled(true)
reply = nil
for _, bad in ipairs({ 42, { "x" }, "/public/a\0b", true }) do
  sent = {}
  local okH, e = pcall(transfer.handleRequest,
    protocol.makePacket(protocol.TYPE.FILE_REQ, { path = bad }), "peer")
  test("path " .. type(bad) .. (type(bad) == "string" and " with NUL" or "")
    .. " does not raise" .. (okH and "" or (" (" .. tostring(e) .. ")")), okH)
  test("...and the peer gets FILE_DENY", sent[1] and sent[1].type == protocol.TYPE.FILE_DENY)
end
sent = {}
transfer.handleRequest(protocol.makePacket(protocol.TYPE.FILE_REQ,
  { path = "/public/../etc/users.dat" }), "peer")
test("a path that climbs out of /public is still denied",
  sent[1] and sent[1].type == protocol.TYPE.FILE_DENY)
sent = {}
transfer.handleRequest(protocol.makePacket(protocol.TYPE.FILE_REQ,
  { path = "/public/hello.txt" }), "peer")
test("a real /public file is still served",
  sent[1] and sent[1].type == protocol.TYPE.FILE_RES and sent[1].payload.data == "hello")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
