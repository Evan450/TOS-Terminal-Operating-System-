-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a mesh port that belongs to someone else      ║
-- ║  is named                                                       ║
-- ║                                                                ║
-- ║  listenPort (default 42) is the operator's to set, and nothing  ║
-- ║  said that some ports are already claimed in the OpenComputers  ║
-- ║  registry: set 4096 and TOS traffic lands on a Minitel network. ║
-- ║  The boot log now warns once, naming whose port it is, and      ║
-- ║  `net status` shows the port and the same note. Not refused: a  ║
-- ║  base can have a reason.                                        ║
-- ║                                                                ║
-- ║  Drives the REAL kernel/net/init.lua over a fake modem, and the ║
-- ║  REAL `net status` in shell/ext.lua.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_reserved_ports.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 5 end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 2e6 end,
  pullSignal = function() end, beep = function() end }

-- One real kernel.net over a fake modem; returns it, the ports opened and
-- the warnings logged.
local function boot(cfg)
  local opened, warnings = {}, {}
  package.loaded["component"] = {
    list = function(t)
      local done = t ~= "modem"
      return function() if done then return nil end; done = true; return "modem-1", "modem" end
    end,
    proxy = function() return {
      open = function(p) opened[#opened + 1] = p; return true end,
      isWireless = function() return false end,
      send = function() return true end, broadcast = function() return true end,
    } end,
    isAvailable = function() return false end,
  }
  package.loaded["kernel.net.trust"] = nil
  local files = {}
  local net = dofile("tos/kernel/net/init.lua")
  local quiet = function() end
  net.init({
    log = { info = quiet, debug = quiet, error = quiet,
            warn = function(_, msg) warnings[#warnings + 1] = msg end },
    config = { get = function(k) return cfg[k] end,
               deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = { exists = function(p) return files[p] ~= nil end,
           readFile = function(p) return files[p] end,
           writeFile = function(p, c) files[p] = c; return true end },
  })
  return net, opened, warnings
end
local function warned(list, needle)
  for _, w in ipairs(list) do if w:find(needle, 1, true) then return true end end
  return false
end

print("=== reserved mesh ports are named ===")
print()

local net, opened, warnings = boot({})
test("the default is port 42", opened[1] == 42)
test("...which is nobody else's", net.portOwner(42) == nil)
test("...so nothing is said about it", not warned(warnings, "registered to"))

net, opened, warnings = boot({ listenPort = 4096 })
test("a configured 4096 is still opened (not refused)", opened[1] == 4096)
test("...but the log names Minitel", warned(warnings, "Port 4096 is registered to MultICE / Minitel"))
test("...and points back at TOS's own port", warned(warnings, "TOS's own port is 42"))
test("net.status() carries the owner", net.status().portOwner == "MultICE / Minitel")

net, opened, warnings = boot({ listenPort = 42, broadcastPort = 9900 })
test("a legacy broadcastPort on a claimed port is named too",
  warned(warnings, "Port 9900 is registered to Zorya BIOS LAN boot"))

test("GERTi's pair are both known", net.portOwner(4378) == "GERTi" and net.portOwner(4379) == "GERTi")

-- `net status`, the real command, over the node booted on 4096.
do
  net = boot({ listenPort = 4096 })
  local X = require("shell.ext")
  local out = {}
  X.net({ "status" }, {
    K = { getNet = function() return net end },
    o = function(t) out[#out + 1] = tostring(t) end,
  })
  local text = table.concat(out, "\n")
  test("`net status` shows the port", text:find("Port: 4096", 1, true) ~= nil)
  test("...and whose it is", text:find("registered to MultICE / Minitel", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
