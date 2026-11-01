-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the chat relay survives what a peer sends    ║
-- ║                                                                ║
-- ║  The one rc.d service with no test. A peer controls a MSG's    ║
-- ║  payload, and the handler indexed it as a table whenever it    ║
-- ║  was not a string, so a number threw inside the listener.      ║
-- ║                                                                ║
-- ║  Loads the real /etc/rc.d/20-chatrelay.lua on a fake net.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_chatrelay.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }

local handler
local sent, logged = {}, {}
local net = {
  getProtocol = function()
    return { TYPE = { MSG = "msg", MSG_ACK = "msg_ack" },
             makePacket = function(t, p) return { type = t, payload = p } end }
  end,
  on = function(_, cb) handler = cb; return 1 end,
  off = function() end,
  findPeer = function() return { hostname = "peer" } end,
  send = function(_, pkt) sent[#sent + 1] = pkt; return true end,
}
_G._TOS = { net = net, log = function(_, m) logged[#logged + 1] = m end }

local chunk = assert(loadfile("etc/rc.d/20-chatrelay.lua"))
local svc = chunk()
assert(svc.start, "the service has a start")
svc.start()
test("the service listens", type(handler) == "function")

local function say(payload)
  return pcall(handler, { payload = payload, seq = 1 }, "aaaa0000-0000-0000-0000-00000000000a")
end

print("=== what a peer can put in a message ===")
for _, case in ipairs({
  { "a string", "hello", "hello" },
  { "a table with text", { text = "hi there" }, "hi there" },
  { "a number", 42, "42" },
  { "true", true, "true" },
}) do
  logged = {}
  local ok, err = say(case[2])
  test(case[1] .. " does not throw", ok, err)
  test(case[1] .. " is recorded", (logged[1] or ""):find(case[3], 1, true) ~= nil, logged[1])
end
do
  local ok, err = say({ other = 1 })
  test("a table with no text does not throw", ok, err)
  local okN, errN = say(nil)
  test("no payload does not throw", okN, errN)
  local okL = say(string.rep("x", 5000))
  test("a very long one does not throw", okL)
  test("and is cut to the limit", #(logged[#logged] or "") < 600, #(logged[#logged] or ""))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
