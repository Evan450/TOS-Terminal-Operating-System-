-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the shell still shows output while a program  ║
-- ║  is backgrounded                                                 ║
-- ║                                                                ║
-- ║  The executor skips a command's output when that command handed ║
-- ║  the seat to a full-screen program -- the program owns the       ║
-- ║  screen. It tested "is a program recorded" instead, and the      ║
-- ║  record lives as long as the program. So after Ctrl+B put calc   ║
-- ║  in the background, every later command ran and showed nothing   ║
-- ║  (`echo`, `ps`, ...) until calc exited. Headless machine,        ║
-- ║  2026-10-10.                                                     ║
-- ║                                                                ║
-- ║  Drives the REAL executor; only its collaborators are stubbed.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bg_program_output.lua   (from TOS-Dev)

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
    hello = function(_, o) o("hello", "FG") end,
    -- What the hand-off does when a command starts a full-screen program:
    -- it records the program, and the program owns the screen.
    launch = function(_, o) S._program = { pid = 9, name = "tetris", seat = 1 }; o("stray", "FG") end,
  },
})

local function shown()
  local t = {}
  if S.lastOut then t[#t + 1] = S.lastOut[1] end
  for _, l in ipairs(S.outLines or {}) do t[#t + 1] = l[1] end
  return table.concat(t, " | ")
end

print("=== output while a program is in the background ===")
print()

exec("hello")
test("with no program, output is shown", shown() == "hello", shown())

S._program = { pid = 5, name = "calc", seat = 1 }   -- calc, backgrounded with Ctrl+B
S.lastOut, S.outLines = nil, nil
exec("hello")
test("with calc in the background, a command's output is still shown",
  shown() == "hello", shown())

S.lastOut, S.outLines = nil, nil
exec("launch")
test("a command that hands the seat to a program shows nothing over it",
  shown() == "", shown())

local src
for _, p in ipairs({ "tos/shell/panels/executor.lua", "TOS-Dev/tos/shell/panels/executor.lua" }) do
  local f = io.open(p, "rb"); if f then src = f:read("*a"); f:close(); break end
end
test("a program's exit clears the record only if it is still its own",
  src and src:find("if S._program and S._program.pid == pid then S._program = nil end", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
