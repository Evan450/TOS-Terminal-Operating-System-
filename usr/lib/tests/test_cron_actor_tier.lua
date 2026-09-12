-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: cron.add cannot schedule as a higher tier     ║
-- ║                                                                ║
-- ║  cron.add's opts.user picks the identity a job runs as, and     ║
-- ║  sessionForJob mints that user's own session at tick time. The  ║
-- ║  only gate was ADMIN, so a tier-2 admin could set user="root"   ║
-- ║  and the job ran as root -- the same ADMIN-to-root escalation    ║
-- ║  the service-install gate closes (Sep 2026 pentest). You may     ║
-- ║  now schedule as an account only if you at least match its tier. ║
-- ║  Drives the REAL kernel.cron.                                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cron_actor_tier.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  loadFile = function() return nil end, saveFile = function() return true end,
}

local TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 }
local ACCOUNTS = { root = TIER.ROOT, adam = TIER.ADMIN, alice = TIER.USER, bob = TIER.USER }
local current
package.loaded["kernel.users"] = {
  currentSession = function() return current end,
  getUser = function(n) return ACCOUNTS[n] and { name = n, tier = ACCOUNTS[n] } or nil end,
  canAccessAs = function() return true end,
  TIER = TIER,
}

local cron = require("kernel.cron")
cron.init({ fs = { exists = function() return false end, readFile = function() return nil end,
  writeFile = function() return true end, writeFileAtomic = function() return true end },
  log = nil, event = nil })

local function asUser(name) current = { user = name, tier = ACCOUNTS[name] } end

print("=== cron.add cannot schedule above your own tier ===")
print()

asUser("adam")   -- ADMIN
local id, err = cron.add("evil", 60, "print(1)", { user = "root" })
test("an ADMIN cannot schedule a job as root", id == nil and tostring(err):find("outrank", 1, true) ~= nil)

id = cron.add("as-self", 60, "print(1)")
test("...but can schedule as itself", type(id) == "number")

id = cron.add("as-user", 60, "print(1)", { user = "alice" })
test("...and as a plain USER (which it outranks)", type(id) == "number")

asUser("root")   -- ROOT
id = cron.add("root-job", 60, "print(1)", { user = "root" })
test("ROOT can schedule a job as root", type(id) == "number")
id = cron.add("root-for-adam", 60, "print(1)", { user = "adam" })
test("...and as an admin", type(id) == "number")

asUser("alice")  -- USER
id, err = cron.add("nope", 60, "print(1)", { user = "adam" })
test("a USER cannot schedule as anyone but itself (the ADMIN bar still holds)",
  id == nil and tostring(err):find("cannot schedule", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
