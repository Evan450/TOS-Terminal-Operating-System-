-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `--live` (and `-f`) open a live tab          ║
-- ║                                                                ║
-- ║  `watch ps` existed; `ps -f` did not. The executor now turns   ║
-- ║  `<cmd> --live`, or `-f` on the read-only status commands in    ║
-- ║  LIVE_SHORT, into `watch <cmd>` -- before dispatch, so it meets ║
-- ║  the same gates typing `watch` would (and watch checks the      ║
-- ║  watched command's tier itself: test_watch_tier.lua). -f stays  ║
-- ║  --force for the commands that already read it that way, and a  ║
-- ║  pipeline stage or `sudo` is never rewritten.                   ║
-- ║                                                                ║
-- ║  Drives the REAL executor over the real registry.               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_live_flag.lua   (from TOS-Dev)

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

package.loaded["shell.panels.helpers"] = {
  routeOutput = function(n) return n == 0 and "clear" or "inline" end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function() end,
  noteFailure = function() end,
  liveTier = function(St) return St.userTier or 0 end,
  fail = function(_, msg, o) o(msg, "ERR"); return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.pkg"] = { getCommand = function() return nil end,
                                 getCommandScreen = function() return nil end }

local executorMod = require("shell.panels.executor")
local calls = {}
local function rec(name) return function(args) calls[#calls + 1] = { name = name, args = args } end end
local S = {
  W = 80, H = 25, T = { error = "ERR" }, cwd = "/", userTier = 2,
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {},
}
local C = {}
for _, n in ipairs({ "watch", "ps", "log", "trash", "backup", "edit", "grep", "df", "rm" }) do C[n] = rec(n) end
local exec = executorMod.build(S, { rp = function(p) return p end,
  makeProgramEnv = function() return {} end, C = C })

local function run(line)
  calls = {}
  exec(line)
  return calls
end
local function only(c, name, ...)
  local want = { ... }
  if #c ~= 1 or c[1].name ~= name then return false end
  if #c[1].args ~= #want then return false end
  for i, w in ipairs(want) do if c[1].args[i] ~= w then return false end end
  return true
end

print("=== --live and -f open a live tab ===")
print()

test("`ps -f` is `watch ps`", only(run("ps -f"), "watch", "ps"))
test("`ps --live` is `watch ps`", only(run("ps --live"), "watch", "ps"))
test("the other arguments ride along: `log 20 -f`", only(run("log 20 -f"), "watch", "log", "20"))
test("`df --live` too", only(run("df --live"), "watch", "df"))
test("--live works on any command (watch decides what it can show)",
  only(run("edit notes.txt --live"), "watch", "edit", "notes.txt"))

test("`-f` is still --force for trash", only(run("trash restore old.txt -f"), "trash", "restore", "old.txt", "-f"))
test("...and for backup", only(run("backup restore /home -f"), "backup", "restore", "/home", "-f"))
test("...and `rm -f` is not turned into a live tab", only(run("rm -f junk"), "rm", "-f", "junk"))

local piped = run("ps -f | grep x")
test("a pipeline stage is never rewritten", piped[1] and piped[1].name == "ps"
  and piped[1].args[1] == "-f" and not (piped[2] and piped[2].name == "watch"))

calls = {}
S.execOne("ps --live")
test("sudo's single-command path is never rewritten", only(calls, "ps", "--live"))

test("`watch ps -f` is left to watch", only(run("watch ps -f"), "watch", "ps", "-f"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
