-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package command is heard while it runs     ║
-- ║                                                                ║
-- ║  A package command wrote to the executor's buffer, so all of   ║
-- ║  it appeared when the command ended. rc's "Shared secret for   ║
-- ║  ..." never showed while it waited for the secret, and its key ║
-- ║  legend and every pong stayed hidden until the pilot quit, the ║
-- ║  one moment none of it was any use. PATH programs had been     ║
-- ║  fixed; this one route was left. Drives the real executor.     ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_package_output_live.lua   (from TOS-Dev)

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

package.loaded["shell.panels.helpers"] = {
  mayHavePackages = function() return true end,
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
package.loaded["compat.term"] = { setCursor = function() end }

local me = { name = "shell" }
package.loaded["kernel.process"] = {
  current = function() return me end,
  inProcess = function() return false end,
}

local during = {}
local readHook
package.loaded["kernel.pkg"] = {
  getCommand = function(name)
    if name == "pilot" then
      return function(_, o)
        o("Keys: W forward", 7)
        during.liveAtFirstLine = #during.live
        readHook = me.beforeRead
        if me.beforeRead then me.beforeRead("") end
        o("  pong")
        during.liveAtLastLine = #during.live
      end
    end
    if name == "broken" then return function() error("boom") end end
  end,
  getCommandScreen = function() return nil end,
}

local S = {
  W = 80, H = 25, T = { fg = 1, error = 3 }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {}, U = {},
}
local rows = 0
local executorMod = require("shell.panels.executor")
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  C = {},
  liveLine = function(text, color) during.live[#during.live + 1] = { text, color } end,
  inputRow = function() rows = rows + 1; return 20 end,
})

print("=== a package command is heard while it runs ===")
print()

during = { live = {} }
exec("pilot")
test("its first line arrived before it finished", during.liveAtFirstLine == 1, during.liveAtFirstLine)
test("and so did the last", during.liveAtLastLine == 2, during.liveAtLastLine)
test("its colour came with it", during.live[1] and during.live[1][2] == 7)
test("the read hook was there during the call", type(readHook) == "function")
test("and asked for one row, not one per line: the CLI's inputRow takes a row",
  rows == 1, rows)
test("it is gone afterwards, so the next program does not inherit it", me.beforeRead == nil)

during = { live = {} }
exec("broken")
test("a command that throws leaves no hook behind", me.beforeRead == nil)

during = { live = {} }
readHook, rows = nil, 0
local shown = exec("pilot | cat")
test("in a pipe the buffer is still the output", #during.live == 0, #during.live)
test("and there is no read hook", readHook == nil)
local _ = shown

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
