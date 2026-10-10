-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: an announcement reaches the other machine     ║
-- ║                                                                ║
-- ║  intercom (TOS-Extras) sends over the kernel's mesh and        ║
-- ║  registers a mesh handler to receive. The transport hands a    ║
-- ║  handler the message ENVELOPE ({ id, from, ts, sealed, ...,    ║
-- ║  payload }); intercom's handler read msg.text, which an        ║
-- ║  envelope never has, and refused every announcement. On two    ║
-- ║  headless machines the receiver's handler ran and returned at  ║
-- ║  once: no box, no chat line, nothing in `intercom log`         ║
-- ║  (2026-10-10). test_intercom.lua only ever called M.deliver.   ║
-- ║                                                                ║
-- ║  Here: two REAL kernel.net instances, a REAL intercom.lua on   ║
-- ║  each, the bytes one modem sends handed to the other.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_intercom_mesh_seam.lua   (from TOS-Dev)

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

local INTERCOM
for _, p in ipairs({ "../TOS-Extras/modules/intercom/usr/lib/intercom.lua",
    "TOS-Extras/modules/intercom/usr/lib/intercom.lua" }) do
  local f = io.open(p, "rb")
  if f then INTERCOM = f:read("*a"); f:close(); break end
end
if not INTERCOM then
  print("  FAIL: could not read TOS-Extras/modules/intercom/usr/lib/intercom.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
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

local netA, outA = makeNode(A_ADDR)
local netB = makeNode(B_ADDR)
for _, pr in ipairs({ { netA, B_ADDR }, { netB, A_ADDR } }) do
  local t = pr[1].getTrust()
  assert(t.setLevel("root", pr[2], t.LEVEL.TRUSTED, 3))
  assert(t.setSecret("root", pr[2], SECRET, 3))
end

-- A machine's own files, and what reaches its operator.
local function machine(net)
  local files, posts, logs = {}, {}, {}
  local fs = setmetatable({
    exists = function(p) return files[p] ~= nil end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c) files[p] = c; return true end,
    writeFileAtomic = function(p, c) files[p] = c; return true end,
    isDirectory = function() return false end,
  }, { __index = function() return function() return true end end })
  package.loaded["kernel.net"] = net
  package.loaded["kernel.fs"] = fs
  package.loaded["kernel.serialize"] = dofile("tos/kernel/serialize.lua")
  package.loaded["kernel.notify"] = {
    post = function(spec) posts[#posts + 1] = spec; return #posts end,
  }
  package.loaded["kernel.log"] = {
    info = function(t, m) logs[#logs + 1] = tostring(t) .. ": " .. tostring(m) end,
    warn = function(t, m) logs[#logs + 1] = tostring(t) .. ": " .. tostring(m) end,
    error = quiet,
  }
  package.loaded["kernel.event"] = { timer = function() return 1 end }
  local M = assert(load(INTERCOM, "=intercom.lua"))()
  return { M = M, files = files, posts = posts, logs = logs }
end

local sender = machine(netA)
local receiver = machine(netB)

print("=== an announcement, across the real mesh ===")
print()

test("the receiver starts listening", receiver.M.start() == true)
local rep = sender.M.announce({ text = "Warning: Reactor offline.", severity = "alert" })
test("the sender says it was sent", rep and rep.sent == true, rep and rep.err)
test("...as a broadcast on its modem", #outA >= 1)
for _, m in ipairs(outA) do netB.handleIncoming(A_ADDR, 42, 1, m.data) end

local heard = false
for _, l in ipairs(receiver.logs) do
  if l:find("Heard", 1, true) and l:find("Reactor offline", 1, true) then heard = true end
end
test("the receiver hears it", heard, table.concat(receiver.logs, " | "))
local spooled = false
for p, c in pairs(receiver.files) do
  if p:find("intercom", 1, true) and tostring(c):find("Reactor offline", 1, true) then spooled = true end
end
test("...keeps it for `intercom log`", spooled)
test("...and, at alert, raises the box",
  #receiver.posts == 1 and tostring(receiver.posts[1].message or receiver.posts[1].text or "")
    :find("Reactor offline", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
