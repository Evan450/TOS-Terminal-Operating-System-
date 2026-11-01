-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: who may power off, and who may look          ║
-- ║                                                                ║
-- ║  Three permission rules settled 2026-11-01:                    ║
-- ║   * canPowerOff is the one rule for reboot and shutdown: alone ║
-- ║     you may, with others logged in you need admin. Dispatch    ║
-- ║     used to refuse the typed commands at tier 2 first, so a    ║
-- ║     lone user on a box too short of RAM to load `core` was     ║
-- ║     told to reboot and then refused. The menus never had that  ║
-- ║     problem, because they call canPowerOff directly;           ║
-- ║   * `pkg list/search/info` and `service list` are open to a    ║
-- ║     user, and every verb that changes something stays admin,   ║
-- ║     including a verb nobody has written yet;                   ║
-- ║   * an admin can write /usr/lang, because a catalog never runs ║
-- ║     (the ACL behind that is checked on the runner).            ║
-- ║  Drives the real commands, with an admin gate that says no.    ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_power_off_policy.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;"
  .. "../../../tos/?.lua;../../../tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
                                totalMemory = function() return 2097152 end,
                                pullSignal = function() return nil end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end, proxy = function() end }

local installed = { { name = "calc", version = "2.0", kind = "app" } }
local called = {}
package.loaded["kernel.pkg"] = {
  list = function() called.list = true; return installed end,
  listAllAvailable = function() called.search = true; return installed end,
  info = function(n) called.info = true; return n == "calc" and installed[1] or nil end,
  install = function() called.install = true; return true end,
  uninstall = function() called.uninstall = true; return true end,
  setEnabled = function() called.enable = true; return true end,
  repos = function() return {} end,
  isEnabled = function() return true end,
}
package.loaded["kernel.rc"] = {
  list = function() called.svclist = true; return { { name = "20-rshd", running = false } } end,
  start = function() called.start = true; return true end,
  stop = function() called.stop = true; return true end,
}

local helpers = require("shell.panels.helpers")

print("=== who may power off ===")
print()
do
  local function seat(tier) return { userTier = tier } end
  _G._TOS = { shellPIDs = { [1] = 7 } }          -- one operator, alone
  test("a lone user may", helpers.canPowerOff(seat(1)) == true)
  test("a lone guest may: the rescue has to work for them too",
    helpers.canPowerOff(seat(0)) == true)
  _G._TOS.shellPIDs = { [1] = 7, [2] = 9 }       -- someone else is on it
  test("with others on, a user may not", not helpers.canPowerOff(seat(1)))
  test("nor a guest", not helpers.canPowerOff(seat(0)))
  test("an admin still may", helpers.canPowerOff(seat(2)) == true)
  test("and root", helpers.canPowerOff(seat(3)) == true)
  local ok, why = helpers.canPowerOff(seat(1))
  test("and the refusal says why", not ok and tostring(why):find("2 operators", 1, true) ~= nil, why)
  _G._TOS = nil
end

local okR, register = pcall(require, "shell.panels.commands.admin")
assert(okR and type(register) == "function", tostring(register))
local refused = 0
local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, D = {}, U = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 1, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end, openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end, canRead = function() return true end,
  canWrite = function() return true end, canAccess = function() return true end,
  rootOnly = function() return false end,
  adminOnly = function(o) refused = refused + 1; o("Admin tier required.", S.T.error); return false end,
  makeProgramEnv = function() return {} end, promptInput = function() return "" end,
  confirm = function() return true end, confirmTyped = function() return true end,
}
local C = {}
assert(pcall(register, C, S, deps))

local function run(fn, ...)
  refused, called = 0, {}
  local out = {}
  local ok, err = pcall(fn, { ... }, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n"), ok, err
end

print()
print("=== a user may look ===")
print()
do
  local out, ok, err = run(C.pkg)
  test("`pkg` lists", ok and refused == 0 and called.list, err or out)
  out, ok, err = run(C.pkg, "list")
  test("`pkg list` lists", ok and refused == 0 and out:find("calc", 1, true) ~= nil, err or out)
  out, ok, err = run(C.pkg, "search", "calc")
  test("`pkg search` searches", ok and refused == 0 and called.search, err or out)
  out, ok, err = run(C.pkg, "info", "calc")
  test("`pkg info` answers", ok and refused == 0 and called.info, err or out)
  out, ok, err = run(C.service)
  test("`service` lists", ok and refused == 0 and called.svclist, err or out)
  out, ok, err = run(C.service, "list")
  test("`service list` lists", ok and refused == 0 and called.svclist, err or out)
end

print()
print("=== and may not touch ===")
print()
for _, verb in ipairs({ "install", "uninstall", "enable", "disable", "upgrade", "fetch",
    "repo", "trust", "sign", "make-disk", "remote", "outdated", "a-verb-from-next-year" }) do
  run(C.pkg, verb, "calc")
  test("`pkg " .. verb .. "` is admin", refused == 1 and not called.install
    and not called.uninstall and not called.enable, refused)
end
run(C.service, "start", "20-rshd")
test("`service start` is admin", refused == 1 and not called.start, refused)
run(C.service, "stop", "20-rshd")
test("`service stop` is admin", refused == 1 and not called.stop, refused)

print()
print("=== the registry agrees ===")
print()
do
  local reg = require("shell.panels.commands")
  test("pkg is open to users, not guests", reg.entry("pkg").tier == 1)
  test("service is too", reg.entry("service").tier == 1)
  test("install stays admin", reg.entry("install").tier == 2)
  test("uninstall stays admin", reg.entry("uninstall").tier == 2)
  test("dispatch leaves reboot to canPowerOff", reg.entry("reboot").tier == 0)
  test("and shutdown", reg.entry("shutdown").tier == 0)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
