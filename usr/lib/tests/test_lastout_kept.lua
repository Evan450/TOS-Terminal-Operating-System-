-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a command's status line survives the router  ║
-- ║                                                                ║
-- ║  A command reports either through o() or by setting S.lastOut  ║
-- ║  (twenty do the latter in admin.lua alone). After the command, ║
-- ║  the executor routes the o() output -- and its router started   ║
-- ║  by clearing S.lastOut. So a command that printed nothing else  ║
-- ║  lost its report: on a headless machine `useradd alice` asked   ║
-- ║  for the password twice, created the account, and said nothing. ║
-- ║                                                                ║
-- ║  Drives the REAL executor; only its collaborators are stubbed.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_lastout_kept.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

_G._TOS = _G._TOS or {}
package.path = "tos/?.lua;" .. package.path

-- The real router's shape: 0 lines clear, 1 the status row, a few inline.
package.loaded["shell.panels.helpers"] = {
  routeOutput = function(n, max)
    if n == 0 then return "clear" elseif n == 1 then return "status"
    elseif n <= max then return "inline" else return "tab" end
  end,
  expandBuf = function(_, buf)
    local out = {}
    for i, e in ipairs(buf) do out[i] = type(e) == "table" and e or { tostring(e), "FG" } end
    return out
  end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function(St) if St then St.lastFailure = nil end end,
  noteFailure = function() end,
  liveTier = function() return 3 end,
  tierName = function(n) return "tier " .. n end,
  fail = function(St, msg, o) o(msg, "ERR"); return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.pkg"] = { getCommand = function() return nil end,
                                 getCommandScreen = function() return nil end }

local executorMod = require("shell.panels.executor")
local S = {
  W = 80, H = 25, T = { error = "ERR", highlight = "HL" }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {}, U = { getSession = function() return { user = "root", tier = 3 } end }, st = "r",
}
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  C = {
    -- useradd's shape: prompts, then reports only through S.lastOut.
    quiet  = function() S.lastOut = { "User 'alice' created.", "HL" } end,
    -- prints a line AND sets a status: neither may be lost.
    loud   = function(_, o) o("first line", "FG"); S.lastOut = { "and a status", "HL" } end,
    silent = function() end,
    plain  = function(_, o) o("just this", "FG") end,
  },
})

local function shown()
  local t = {}
  if S.lastOut then t[#t + 1] = S.lastOut[1] end
  for _, l in ipairs(S.outLines or {}) do t[#t + 1] = l[1] end
  return table.concat(t, " | ")
end

print("=== a command's status line survives the router ===")
print()

exec("quiet")
test("a command that only sets S.lastOut is still heard", shown():find("User 'alice' created.", 1, true) ~= nil, shown())

exec("loud")
test("a command that prints AND sets a status keeps both",
  shown():find("first line", 1, true) and shown():find("and a status", 1, true), shown())

exec("quiet"); exec("silent")
test("the next command does not inherit a stale status", shown() == "", shown())

exec("plain")
test("o() output is routed as before", shown() == "just this", shown())

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
