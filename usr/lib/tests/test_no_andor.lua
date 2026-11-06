-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: && and || are refused, not half-run          ║
-- ║                                                                ║
-- ║  TOS's shell has neither. `whoami && echo X` ran whoami, which ║
-- ║  ignored the rest of the line, and said nothing; `a || b` was  ║
-- ║  split at its bars into a pipe, so b ran whatever a did, the   ║
-- ║  opposite of ||. Both now say so and run nothing. Quoted, they ║
-- ║  are just text. Drives the real executor.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_no_andor.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

_G._TOS = _G._TOS or {}
package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["shell.panels.helpers"] = {
  mayHavePackages = function() return false end,
  routeOutput = function(n) return n == 0 and "clear" or "inline" end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function() end,
  noteFailure = function() end,
  liveTier = function() return 3 end,
  tierName = function() return "ROOT" end,
  fail = function(_, msg, o) o(msg, "ERR"); return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.process"] = { current = function() return nil end, inProcess = function() return false end }

local ran = {}
local C = {
  whoami = function(_, o) ran[#ran + 1] = "whoami"; o("root") end,
  echo = function(args, o) ran[#ran + 1] = "echo"; o(table.concat(args, " ")) end,
}
local S = {
  W = 80, H = 25, T = { fg = 1, error = 3 }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {}, U = {},
}
local shown
local exec = require("shell.panels.executor").build(S, {
  rp = function(p) return p end, makeProgramEnv = function() return {} end, C = C,
  showOutput = function(wrapped) shown = wrapped end,
})
local function run(line)
  ran, shown = {}, nil
  exec(line)
  local said = type(S.lastOut) == "table" and S.lastOut[1] or tostring(S.lastOut or "")
  return said, table.concat(ran, ",")
end

print("=== chaining is refused ===")
local said, r = run("whoami && echo X")
test("&& says the shell has none", said:find("has no &&", 1, true) ~= nil, said)
test("...and runs nothing, not half the line", r == "", r)
said, r = run("whoami || echo X")
test("|| says so too", said:find("has no ||", 1, true) ~= nil, said)
test("...rather than piping one into the other", r == "", r)
said, r = run("whoami&&echo X")
test("without spaces as well", said:find("has no &&", 1, true) ~= nil and r == "", said)

print("=== quoted, they are only text ===")
said, r = run('echo "a && b"')
test("a quoted && is echoed", r == "echo" and said == "", said)
said, r = run("echo 'x || y'")
test("a quoted || is echoed", r == "echo" and said == "", said)

print("=== a single bar is still a pipe ===")
said, r = run("whoami | echo piped")
test("whoami | echo runs both", r == "whoami,echo", r)

_G._TOS = nil
print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
