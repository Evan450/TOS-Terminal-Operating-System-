-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: executor shadow-invalidate contract      ║
-- ║                                                            ║
-- ║  A sandboxed package command (tetris) draws raw through    ║
-- ║  its `component` capability, past the seat's dirty-cell    ║
-- ║  shadow buffer. Without an invalidate after it exits, the  ║
-- ║  post-command repaint elides "unchanged" cells and the     ║
-- ║  operator is left staring at game leftovers (v1.4.0        ║
-- ║  emulator round: blank shell + flickering menu bar after   ║
-- ║  losing a round of Tetris). Pins: pkg-provided commands    ║
-- ║  invalidate the display after running; builtins don't.     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_executor_invalidate.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- Stubs for the executor's module dependencies.
_G._TOS = _G._TOS or {}
package.loaded["shell.panels.helpers"] = {
  routeOutput = function(n, maxInline)
    if n == 0 then return "clear"
    elseif n == 1 then return "status"
    elseif n <= (maxInline or 8) then return "inline"
    else return "tab" end
  end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  -- Alias expansion and external-program resolution both live in helpers
  -- now (the latter so `which` reports what the executor really runs).
  -- This test doesn't exercise either — identity/nil keeps it honest.
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.pkg"] = {
  getCommand = function(name)
    if name == "fakegame" then return function(_, o) o("game over") end end
    return nil
  end,
  getCommandScreen = function() return nil end,
}

package.path = "tos/?.lua;" .. package.path
local executorMod = require("shell.panels.executor")

print("=== executor shadow-invalidate Tests ===")
print()

local calls = 0
local S = {
  W = 80, H = 25, T = {}, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end,
        exists = function() return false end },
  D = { invalidate = function() calls = calls + 1 end },
}
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  C = { hello = function(_, o) o("hi") end },
})

exec("hello")
eq("builtin command does NOT invalidate", 0, calls)

exec("fakegame")
eq("pkg command invalidates the display after running", 1, calls)

exec("fakegame")
eq("each pkg run invalidates again", 2, calls)

exec("nosuchcommand")
eq("unknown command does not invalidate", 2, calls)

-- A display without the hook (plain kernel.display) must not error.
S.D = {}
local okRun = pcall(exec, "fakegame")
test("no invalidate hook on D -> still runs cleanly", okRun)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
