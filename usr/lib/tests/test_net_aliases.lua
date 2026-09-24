-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: who may rewrite the peer alias table          ║
-- ║                                                                ║
-- ║  aliases.lua's header says ADMIN sets and removes, and its gate ║
-- ║  lets the caller through when there is no users module -- the   ║
-- ║  early-boot case. kernel/init.lua handed it `users = usersmod`, ║
-- ║  a local of an EARLIER block, so the name read a nil global and ║
-- ║  the gate saw "early boot" for the machine's whole uptime: any  ║
-- ║  account with `net` (tier 1) could repoint "server" at its own  ║
-- ║  modem for everyone. test_global_leaks.lua could not see it     ║
-- ║  (the name sat past the 256th constant; that lint is fixed too).║
-- ║                                                                ║
-- ║  Also pinned: a refused save leaves memory as it was, where it  ║
-- ║  used to keep the change until the reboot dropped it.           ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.net.aliases.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_aliases.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path

local ADDR1 = "aaaaaaaa-1111-2222-3333-444444444444"
local ADDR2 = "bbbbbbbb-1111-2222-3333-444444444444"

-- In-memory disk; `refuse` makes the next writes fail the way a full or
-- read-only disk does.
local files, refuse = {}, false
local fs = {
  exists    = function(p) return files[p] ~= nil end,
  readFile  = function(p) return files[p] end,
  writeFile = function(p, c)
    if refuse then return false, "not enough space" end
    files[p] = c; return true
  end,
}

local CURRENT = nil
local users = {
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 },
  currentSession = function() return CURRENT end,
}
local alice = { user = "alice", tier = 1 }
local adam  = { user = "adam",  tier = 2 }

local function fresh(initUsers)
  package.loaded["kernel.net.aliases"] = nil
  local A = require("kernel.net.aliases")
  A.init({ fs = fs, users = initUsers, serialize = require("kernel.serialize") })
  return A
end

print("=== peer aliases: tier gate and rollback ===")
print()

print("-- users injected --")
do
  files, refuse = {}, false
  local A = fresh(users)
  CURRENT = alice
  test("a USER cannot set an alias", not A.set("server", ADDR1))
  test("...and nothing was stored", A.addressOf("server") == nil)
  CURRENT = adam
  test("an ADMIN can set an alias", (A.set("server", ADDR1)))
  CURRENT = alice
  test("a USER cannot repoint it", not A.set("server", ADDR2))
  test("...so it still resolves to the admin's address", A.resolve("server") == ADDR1)
  test("a USER cannot remove it", not A.remove("server"))
  test("anyone can still read it", A.addressOf("server") == ADDR1)
end

print()
print("-- users NOT injected (the kernel/init.lua wiring bug) --")
do
  files, refuse = {}, false
  _G._TOS = { users = users }
  local A = fresh(nil)
  CURRENT = alice
  test("the live _TOS.users still gates a USER", not A.set("server", ADDR2))
  CURRENT = adam
  test("...and still admits an ADMIN", (A.set("server", ADDR2)))
  _G._TOS = nil
  CURRENT = alice
  local A2 = fresh(nil)
  test("with no user system at all, the early-boot rule still applies",
    (A2.set("boot", ADDR1)))
end

print()
print("-- a refused save changes nothing --")
do
  files, refuse = {}, false
  local A = fresh(users)
  CURRENT = adam
  A.set("server", ADDR1)
  refuse = true
  local ok, err = A.set("server", ADDR2)
  test("set reports the failed write", not ok and tostring(err):find("persist", 1, true) ~= nil)
  test("...and the alias still points where the disk says", A.resolve("server") == ADDR1)
  test("...and the old address still has its alias", A.aliasOf(ADDR1) == "server")
  test("...and the new address gained none", A.aliasOf(ADDR2) == nil)
  local okR = A.remove("server")
  test("remove reports the failed write", not okR)
  test("...and the alias is still there", A.addressOf("server") == ADDR1)
  refuse = false
  test("once the disk takes writes again, remove works", (A.remove("server")))
  test("...and it is gone", A.addressOf("server") == nil)
end

print()
print("-- kernel/init.lua wires the real modules --")
do
  local f = io.open("tos/kernel/init.lua", "r")
  local src = f and f:read("*a") or ""
  if f then f:close() end
  local block = src:match("aliasesMod%.init%((%b{})%)") or ""
  test("found the aliases.init call", block ~= "")
  test("users comes from _TOS", block:find("users%s*=%s*_G%._TOS%.users") ~= nil)
  test("securefs comes from _TOS", block:find("securefs%s*=%s*_G%._TOS%.securefs") ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
