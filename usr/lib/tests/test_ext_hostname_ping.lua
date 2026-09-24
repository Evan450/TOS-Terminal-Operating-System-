-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `hostname`, `ping` and `audio test`           ║
-- ║                                                                ║
-- ║  Three commands in shell/ext.lua that did not do what they say: ║
-- ║   * `hostname <name>` is documented "(admin to set)" and ran    ║
-- ║     for anyone: the command is tier 0 (so `hostname` alone can  ║
-- ║     show the name) and the setter checked nothing, so a GUEST   ║
-- ║     could rewrite /etc/tos.cfg's hostname -- the name HELLO     ║
-- ║     announces. net also cached the name at boot, so even an     ║
-- ║     admin's rename did not reach peers until a restart.         ║
-- ║   * `ping <peer>` sent {type="PING"}: no protocol magic and the ║
-- ║     wrong case, dropped by every receiver's protocol.validate.  ║
-- ║   * `audio test` waited with raw computer.pullSignal, popping   ║
-- ║     whatever signal came next -- another seat's keystroke --    ║
-- ║     from inside the shell process.                              ║
-- ║                                                                ║
-- ║  Drives the REAL shell.ext and kernel.net.protocol.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ext_hostname_ping.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local rawPulls = 0
package.loaded["computer"] = {
  uptime = function() return 10 end,
  pullSignal = function() rawPulls = rawPulls + 1 end,
  beep = function() end,
}
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end }
local sleeps = 0
package.loaded["kernel.process"] = { sleep = function() sleeps = sleeps + 1 end }

local protocol = require("kernel.net.protocol")
local X = require("shell.ext")

local function joined(buf) return table.concat(buf, "\n") end

-- ── hostname ────────────────────────────────────────────────────
print("=== hostname / ping / audio test ===")
print()
print("-- hostname --")
do
  local cfg, saves, netName = { hostname = "tos" }, 0, nil
  local SC = {
    get = function(k) return cfg[k] end,
    set = function(k, v) cfg[k] = v end,
    save = function() saves = saves + 1 end,
    deviceType = function() return "computer" end,
  }
  local NM = { setHostname = function(n) netName = n; return true end }
  local function run(args, tier)
    local buf = {}
    X.hostname(args, {
      K = { getConfig = function() return SC end, getNet = function() return NM end },
      U = { getSession = function() return tier and { user = "u", tier = tier } or nil end },
      st = "tok",
      o = function(t) buf[#buf + 1] = tostring(t) end,
    })
    return buf
  end

  test("anyone can read it", joined(run({}, 0)):find("Host: tos", 1, true) ~= nil)
  run({ "pwned" }, 0)
  test("a GUEST cannot rename the machine", cfg.hostname == "tos" and saves == 0)
  run({ "pwned" }, 1)
  test("a USER cannot rename the machine", cfg.hostname == "tos" and saves == 0)
  run({ "pwned" }, nil)
  test("no session cannot rename the machine", cfg.hostname == "tos" and saves == 0)
  run({ "bad\27[2Jname" }, 2)
  test("control characters are refused", cfg.hostname == "tos" and saves == 0)
  run({ string.rep("x", 33) }, 2)
  test("a 33-character name is refused", cfg.hostname == "tos" and saves == 0)
  local out = run({ "vault-01" }, 2)
  test("an ADMIN renames it", cfg.hostname == "vault-01" and saves == 1)
  test("...and it is announced without a reboot", netName == "vault-01")
  test("...and the command says so", joined(out):find("Host: vault-01", 1, true) ~= nil)
end

-- kernel.net.setHostname holds the same line itself.
do
  package.loaded["kernel.net"] = nil
  local net = dofile("tos/kernel/net/init.lua")
  test("net.setHostname accepts a plain name", (net.setHostname("alpha")) and net.getHostname() == "alpha")
  test("net.setHostname refuses a control character", not net.setHostname("a\nb") and net.getHostname() == "alpha")
  test("net.setHostname refuses a non-string", not net.setHostname({}) and net.getHostname() == "alpha")
end

-- ── ping ────────────────────────────────────────────────────────
print()
print("-- ping --")
local PEER = "cccccccc-1111-2222-3333-444444444444"
local function fakeNet(answer)
  local NM, sent, handlers = {}, {}, {}
  NM.getProtocol = function() return protocol end
  NM.onceFrom = function(t, addr, cb)
    handlers[#handlers + 1] = { t = t, addr = addr, cb = cb }
    return #handlers
  end
  NM.off = function(_, id) handlers[id] = nil end
  NM.send = function(addr, pkt)
    sent[#sent + 1] = { addr = addr, pkt = pkt }
    if answer then
      for _, h in pairs(handlers) do
        if h.t == protocol.TYPE.PONG and h.addr == addr then h.cb(protocol.pong(), addr) end
      end
    end
    return true
  end
  NM.waitFor = function(pred) return pred() end
  NM.discover = function() NM.discovered = true end
  return NM, sent, handlers
end
do
  local NM, sent, handlers = fakeNet(true)
  local buf = {}
  X.ping({ PEER }, { K = { getNet = function() return NM end },
    o = function(t) buf[#buf + 1] = tostring(t) end })
  local pkt = sent[1] and sent[1].pkt
  test("ping sends one packet to the peer", #sent == 1 and sent[1].addr == PEER)
  test("...that passes the receiver's protocol.validate", pkt ~= nil and (protocol.validate(pkt)))
  test("...as the wire type 'ping'", pkt ~= nil and pkt.type == protocol.TYPE.PING)
  test("...reports the reply", joined(buf):find("Reply from", 1, true) ~= nil)
  test("...and removes its listener", next(handlers) == nil)
end
do
  local NM = fakeNet(false)
  local buf = {}
  X.ping({ PEER }, { K = { getNet = function() return NM end },
    o = function(t) buf[#buf + 1] = tostring(t) end })
  test("silence is reported as silence", joined(buf):find("No reply", 1, true) ~= nil)
end
do
  local NM = fakeNet(false)
  X.ping({}, { K = { getNet = function() return NM end }, o = function() end })
  test("no argument broadcasts discovery", NM.discovered == true)
end

-- ── audio test ─────────────────────────────────────────────────
print()
print("-- audio test --")
do
  _G._TOS = { audio = setmetatable({}, { __index = function() return function() end end }) }
  rawPulls, sleeps = 0, 0
  X.audio({ "test" }, { K = {}, o = function() end })
  test("the gaps yield through proc.sleep", sleeps == 9)
  test("...and never pull a raw signal", rawPulls == 0)
  _G._TOS = nil
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
