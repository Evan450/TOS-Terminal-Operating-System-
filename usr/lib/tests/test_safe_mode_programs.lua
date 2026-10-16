-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: Safe Mode does not run a package's programs  ║
-- ║                                                                ║
-- ║  Safe Mode runs nothing third-party: no services, no cron, no  ║
-- ║  package commands. Its gate was pkg's dispatch -- and a        ║
-- ║  package's own /usr/bin program walked round it. On the        ║
-- ║  headless machine, after `bootsettings profile safe` and a     ║
-- ║  reboot, typing `plain` ran the package's /usr/bin/plain.lua,  ║
-- ║  with that package's caps. PATH, `run`, `bg` and the file      ║
-- ║  browser's Run now ask helpers.safeModeRefusal. A file no      ║
-- ║  package owns still runs. Real helper, real executor.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_safe_mode_programs.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { freeMemory = function() return 1e6 end, totalMemory = function() return 2097152 end,
  uptime = function() return 0 end }
package.loaded["component"] = { list = function() return function() end end }

local OWNED = { ["/usr/bin/plain.lua"] = "plain" }
local pkgLoads = 0
package.preload["kernel.pkg"] = function()
  pkgLoads = pkgLoads + 1
  return {
    ownerOfFile = function(p) return OWNED[p] end,
    capsForFile = function(p) if OWNED[p] then return {}, OWNED[p] end end,
    getCommand = function() return nil end,       -- dispatch is off in Safe Mode
  }
end

local helpers = dofile("tos/shell/panels/helpers.lua")

print("=== Safe Mode does not run a package's programs ===")
print()

_G._TOS = {}
test("a normal boot refuses nothing", helpers.safeModeRefusal("/usr/bin/plain.lua") == nil)
test("...and does not load the package manager to say so", pkgLoads == 0, pkgLoads)

_G._TOS = { pkgDispatchDisabled = true }
local why = helpers.safeModeRefusal("/usr/bin/plain.lua")
test("Safe Mode refuses a file a package owns", type(why) == "string"
  and why:find("belongs to the package 'plain'", 1, true) ~= nil, why)
test("...with its code, for `why`", why and why:find("[E-404 ERR_SAFE_MODE]", 1, true) ~= nil)
test("a file no package owns still runs", helpers.safeModeRefusal("/home/me/mine.lua") == nil)

-- ── The way the headless machine found it: a bare name, through PATH ──
local ran = {}
local PROGRAMS = { ["/usr/bin/plain.lua"] = "RAN.plain = true", ["/usr/bin/mine.lua"] = "RAN.mine = true" }
package.loaded["shell.panels.helpers"] = setmetatable({
  safeModeRefusal = helpers.safeModeRefusal,   -- the real one
  mayHavePackages = function() return true end,
  routeOutput = function(n) return n == 0 and "clear" or "inline" end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function(_, name)
    local p = "/usr/bin/" .. name .. ".lua"
    if PROGRAMS[p] then return p end
  end,
  clearFailure = function(St) if St then St.lastFailure = nil end end,
  noteFailure = function() end,
  liveTier = function() return 3 end,
  tierName = function(n) return "tier " .. n end,
  fail = function(St, msg, o) o(msg, "ERR"); St.lastFailure = { text = msg }; return false end,
  reportProgramEnd = function() end,
}, { __index = helpers })
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
local executorMod = require("shell.panels.executor")
local S = {
  W = 80, H = 25, T = { error = "ERR", fg = "FG" }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end,
        exists = function(p) return PROGRAMS[p] ~= nil end,
        readFile = function(p) return PROGRAMS[p] end },
  D = {}, userTier = 3,
}
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return setmetatable({ RAN = ran }, { __index = _G }) end,
  C = {},
})

exec("plain")
test("Safe Mode: a package's program reached by name does not run", ran.plain == nil)
test("...and the refusal says why", S.lastFailure and tostring(S.lastFailure.text):find("E-404", 1, true) ~= nil,
  S.lastFailure and S.lastFailure.text)
exec("mine")
test("Safe Mode: a program no package owns runs", ran.mine == true)

_G._TOS = {}
ran.plain = nil
exec("plain")
test("a normal boot runs the package's program", ran.plain == true)

-- ── Every other way a program file runs asks too ───────────────────
local function src(rel)
  local f = io.open(rel, "rb"); if not f then return "" end
  local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n"))
end
local admin = src("tos/shell/panels/commands/admin.lua")
local _, nAdmin = admin:gsub("local refused = helpers%.safeModeRefusal%(path%)", "")
test("`run` and `bg` ask before they load a file", nAdmin == 2, nAdmin)
test("the file browser's Run asks", src("tos/shell/panels/context.lua"):find("helpers.safeModeRefusal(S.ctxPath)", 1, true) ~= nil)

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
