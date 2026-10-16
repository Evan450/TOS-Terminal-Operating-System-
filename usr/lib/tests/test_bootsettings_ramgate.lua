-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `bootsettings` speaks the editor's words for ║
-- ║  the RAM override                                              ║
-- ║                                                                ║
-- ║  The visual Boot Settings editor's RAM row reads "auto         ║
-- ║  (measure)" / "always load" / "never load": "plenty" and       ║
-- ║  "tight" described a memory situation, not what the override  ║
-- ║  does, and were dropped. The shell command kept printing       ║
-- ║  "plenty (force on)" and offering only plenty/tight. Now it    ║
-- ║  shows and takes always/never, and the old words still work.   ║
-- ║  Drives the real command over the real bootcfg.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bootsettings_ramgate.lua   (from TOS-Dev)

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
-- The hardware rows at the end of `bootsettings show` are not this test's.
package.loaded["kernel.sysinfo"] = false

local files = {}
_G._TOS = { fs = {
  exists = function(p) return files[p] ~= nil end,
  readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
} }
local bootcfg = require("kernel.bootcfg")

local okA, register = pcall(require, "shell.panels.commands.admin")
assert(okA and type(register) == "function", tostring(register))
local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, D = {}, U = {},
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
  local ok, err = pcall(C.bootsettings, { ... }, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n"), ok, err
end
local function gate() return bootcfg.load(_G._TOS.fs).ramGate end

print("=== `bootsettings ramgate` speaks the editor's words ===")
print()

local out, ok, err = run("show")
test("`bootsettings show` runs", ok, err)
test("...and an unset gate reads auto", out:find("ramGate    : auto (measure)", 1, true) ~= nil, out)

out = run("ramgate", "always")
test("`ramgate always` saves", gate() == true and out:find("Saved", 1, true) ~= nil, out)
out = run("show")
test("...and reads back in the editor's words", out:find("always load the extras", 1, true) ~= nil, out)
test("...with no 'plenty' left", not out:find("plenty", 1, true), out)

run("ramgate", "never")
test("`ramgate never` saves", gate() == false)
out = run("show")
test("...and reads back as never", out:find("never load the extras", 1, true) ~= nil
  and not out:find("tight", 1, true), out)

run("ramgate", "auto")
test("`ramgate auto` clears it", gate() == nil)

-- The old words keep working: they are in people's scripts and habits.
run("ramgate", "plenty");  test("the old `plenty` still means always", gate() == true)
run("ramgate", "tight");   test("the old `tight` still means never", gate() == false)

out = run("ramgate", "lots")
test("a wrong value lists the new words", out:find("auto", 1, true) ~= nil
  and out:find("always", 1, true) ~= nil and out:find("never", 1, true) ~= nil
  and not out:find("plenty", 1, true), out)
test("...and changes nothing", gate() == false)

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
