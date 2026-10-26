-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a mail reaches the other machine's inbox     ║
-- ║                                                                ║
-- ║  mail (TOS-Extras) sends over the kernel's mesh and registers  ║
-- ║  a "mail" handler to receive. test_mail.lua drives mail.lua    ║
-- ║  against a STUB kernel.net, so it checks what mail asks of the ║
-- ║  transport, never what the transport hands back -- the seam    ║
-- ║  where intercom refused every announcement for want of this    ║
-- ║  test (it read msg.text from an envelope that has none; found  ║
-- ║  on two machines 2026-10-10, test_intercom_mesh_seam.lua).     ║
-- ║                                                                ║
-- ║  Here: two REAL kernel.net instances, a REAL mail.lua on each, ║
-- ║  the bytes one modem sends handed to the other, and the ACK    ║
-- ║  handed back.                                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mail_mesh_seam.lua   (from TOS-Dev)

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

local MAIL
for _, p in ipairs({ "../TOS-Extras/modules/mail/usr/lib/mail.lua",
    "TOS-Extras/modules/mail/usr/lib/mail.lua" }) do
  local f = io.open(p, "rb")
  if f then MAIL = f:read("*a"); f:close(); break end
end
if not MAIL then
  print("  SKIP: TOS-Extras is not beside TOS-Dev")
  print("Results: 0 passed, 0 failed"); print("All tests passed."); return
end

local A_ADDR = "aaaa0000-0000-0000-0000-00000000000a"
local B_ADDR = "bbbb0000-0000-0000-0000-00000000000b"
local SECRET = "0123456789abcdefghijklmnopqrstuv"
local quiet = function() end

-- One real kernel.net over a fake modem whose sends land in `outbox`.
local function makeNode(myAddr)
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
  package.loaded["kernel.net.trust"] = nil
  package.loaded["kernel.net.meshctl"] = nil
  package.loaded["kernel.net.mesh"] = nil
  local files = {}
  local net = dofile("tos/kernel/net/init.lua")
  net.init({
    log = { info = quiet, warn = quiet, debug = quiet, error = quiet },
    config = { get = function() return nil end, deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = setmetatable({
      exists = function(p) return files[p] ~= nil end,
      readFile = function(p) return files[p] end,
      writeFile = function(p, c) files[p] = c; return true end,
    }, { __index = function() return function() return true end end }),
  })
  return net, outbox
end

local function carry(outbox, toNet, fromAddr)
  local snap = {}
  for i, m in ipairs(outbox) do snap[i] = m end
  for i = #outbox, 1, -1 do outbox[i] = nil end
  for _, m in ipairs(snap) do toNet.handleIncoming(fromAddr, 42, 1, m.data) end
  return #snap
end

local netA, outA = makeNode(A_ADDR)
local netB, outB = makeNode(B_ADDR)
for _, pr in ipairs({ { netA, B_ADDR }, { netB, A_ADDR } }) do
  local t = pr[1].getTrust()
  assert(t.setLevel("root", pr[2], t.LEVEL.TRUSTED, 3))
  assert(t.setSecret("root", pr[2], SECRET, 3))
end
for i = #outA, 1, -1 do outA[i] = nil end   -- the hellos trust raised
for i = #outB, 1, -1 do outB[i] = nil end

-- A machine's own files, with the real mail.lua on its net.
local function machine(net)
  local files, logs = {}, {}
  local fs = setmetatable({
    exists = function(p) return files[p] ~= nil end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c) files[p] = c; return true end,
    writeFileAtomic = function(p, c) files[p] = c; return true end,
    makeDirectory = function(p) files[p] = files[p] or ""; return true end,
    isDirectory = function() return false end,
  }, { __index = function() return function() return true end end })
  package.loaded["kernel.net"] = net
  package.loaded["kernel.fs"] = fs
  package.loaded["kernel.serialize"] = dofile("tos/kernel/serialize.lua")
  -- Read the inbox as the kernel: an inbox is owner-or-admin, and mail.lua
  -- fails closed to nobody when there is no session.
  package.loaded["kernel.users"] = { currentSession = function() return { isKernel = true, tier = 3 } end }
  package.loaded["kernel.log"] = {
    info = function(t, m) logs[#logs + 1] = tostring(t) .. ": " .. tostring(m) end,
    warn = function(t, m) logs[#logs + 1] = tostring(t) .. ": " .. tostring(m) end,
    error = quiet,
  }
  local M = assert(load(MAIL, "=mail.lua"))()
  return { M = M, files = files, logs = logs }
end

local sender = machine(netA)
local receiver = machine(netB)

print("=== a mail, across the real mesh ===")
print()

test("the receiver's mail service starts", receiver.M.start() == true)
local id, sealed = sender.M.send({ to = B_ADDR, user = "bob", fromUser = "alice",
  subject = "Reactor", body = "Coolant is low on loop 2." })
test("the sender's send is accepted (" .. tostring(sealed) .. ")", id ~= nil)
test("...sealed, since the two share a secret", sealed == true)
test("...and goes out on its modem", #outA >= 1)
test("the sender counts it pending until acknowledged", sender.M.pending() == 1, sender.M.pending())

carry(outA, netB, A_ADDR)
local inbox = receiver.M.inbox("bob") or {}
test("bob's inbox on the receiver holds one mail", #inbox == 1, #inbox)
local m = inbox[1] or {}
test("...with the subject and body that were sent",
  m.subject == "Reactor" and m.body == "Coolant is low on loop 2.", tostring(m.subject))
test("...from alice on the sender", m.fromUser == "alice" and m.from == A_ADDR, tostring(m.from))
test("...marked sealed and readable", m.sealed == true and m.readable ~= false)
test("nothing was delivered to anyone else",
  #(receiver.M.inbox("_node") or {}) == 0 and #(receiver.M.inbox("alice") or {}) == 0)

test("the receiver acknowledges it", #outB >= 1)
carry(outB, netA, B_ADDR)
test("...and the sender stops counting it pending", sender.M.pending() == 0, sender.M.pending())

-- The same mail arriving twice (a relay's copy) is kept once.
id = sender.M.send({ to = B_ADDR, user = "bob", fromUser = "alice", subject = "Twice", body = "x" })
local copy = {}
for i, mm in ipairs(outA) do copy[i] = mm end
carry(outA, netB, A_ADDR)
for _, mm in ipairs(copy) do netB.handleIncoming(A_ADDR, 42, 1, mm.data) end
local twice = 0
for _, mm in ipairs(receiver.M.inbox("bob") or {}) do if mm.subject == "Twice" then twice = twice + 1 end end
test("a duplicate delivery is kept once", twice == 1, twice)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
