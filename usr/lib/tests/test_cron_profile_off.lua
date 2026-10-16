-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `cron` tells the truth when the boot profile ║
-- ║  has turned it off                                             ║
-- ║                                                                ║
-- ║  On the headless machine: a job added, `bootsettings profile   ║
-- ║  safe`, a reboot, and `cron list` said "No scheduled jobs" --  ║
-- ║  while /etc/cron.dat still held it. The scheduler is not       ║
-- ║  loaded in that profile (on purpose: no stored job runs), so   ║
-- ║  its list was empty, and an add or rm reached a scheduler with ║
-- ║  no disk. Now `cron` says cron is off, lists the saved jobs    ║
-- ║  from the file, and changes nothing. Drives the real command.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cron_profile_off.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
                                totalMemory = function() return 2097152 end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
local serialize = require("kernel.serialize")

local files = {}
local F = {
  readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
  exists = function(p) return files[p] ~= nil end,
}
_G._TOS = { fs = {} }

local okA, register = pcall(require, "shell.panels.commands.admin")
assert(okA and type(register) == "function", tostring(register))
local S = {
  K = {}, E = { push = function() end }, P = {}, F = F, D = {}, U = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end, refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "" end,
  confirm = function() return true end, confirmTyped = function() return true end,
}
local C = {}
assert(pcall(register, C, S, deps))

local function run(...)
  local out = {}
  local ok, err = pcall(C.cron, { ... }, function(t, c) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n"), ok, err
end

print("=== `cron` when the boot profile has it off ===")
print()

files["/etc/cron.dat"] = serialize.encode({ nextID = 3, jobs = {
  [1] = { name = "tick", interval = 600, script = "print(1)", enabled = true },
  [2] = { name = "backup-home", interval = 3600, script = "print(2)", enabled = true },
} })
local saved = files["/etc/cron.dat"]
_G._TOS.cronDisabled = true

local out, ok, err = run("list")
test("`cron list` runs", ok, err)
test("...says cron is off", out:find("Cron is off in this boot profile", 1, true) ~= nil, out)
test("...and lists the saved jobs from the file, not \"No scheduled jobs\"",
  out:find("2 saved job(s)", 1, true) ~= nil and out:find("tick", 1, true) ~= nil
  and out:find("backup-home", 1, true) ~= nil and not out:find("No scheduled jobs", 1, true), out)
test("...without loading the scheduler", package.loaded["kernel.cron"] == nil)

out = run("add", "x", "60", "print(3)")
test("`cron add` is refused, with its code", out:find("[E-404 ERR_SAFE_MODE]", 1, true) ~= nil, out)
out = run("rm", "1")
test("`cron rm` is refused too", out:find("[E-404 ERR_SAFE_MODE]", 1, true) ~= nil, out)
test("...and /etc/cron.dat is untouched", files["/etc/cron.dat"] == saved)

files["/etc/cron.dat"] = nil
out = run()
test("with nothing saved it still says cron is off, and lists nothing",
  out:find("Cron is off", 1, true) ~= nil and not out:find("saved job", 1, true), out)

_G._TOS.cronDisabled = nil
package.loaded["kernel.cron"] = { list = function() return {} end }
out = run("list")
test("a normal boot is unchanged", out == "No scheduled jobs", out)

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
