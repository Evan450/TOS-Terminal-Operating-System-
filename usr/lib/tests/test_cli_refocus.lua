-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the CLI repaints when a program hands back   ║
-- ║                                                                ║
-- ║  On the headless machine, `calc` started from the CLI and then ║
-- ║  quit with ^Q left a BLANK screen: no prompt, no header. The   ║
-- ║  CLI was alive -- `ls /` typed blind printed fine -- but it    ║
-- ║  never repainted. A full-screen program runs in its own        ║
-- ║  process and, when it ends, sends the shell `tos_focus`; the   ║
-- ║  panels shell repaints on it, the CLI ignored it. The CLI's    ║
-- ║  only repaint ran right after the hand-off, while the program  ║
-- ║  was still STARTING.                                           ║
-- ║                                                                ║
-- ║  Runs the real shell/cli.lua in a coroutine, the way a seat    ║
-- ║  runs it, waits at its prompt, and then sends `tos_focus`.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cli_refocus.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, pullSignal = function() return nil end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 4e6 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local drawn, clears = {}, 0
local theme = setmetatable({}, { __index = function() return 0xFFFFFF end })
local D = {
  getTheme = function() return theme end, getGpuTier = function() return 2 end,
  getSize = function() return 80, 25 end, getGpu = function() return nil end,
  c = function() return 0xFFFFFF end,
  set = function(_, _, s) drawn[#drawn + 1] = tostring(s) end,
  fill = function() end,
  clear = function() clears = clears + 1 end,
}
local F = {
  exists = function() return true end, list = function() return {} end,
  isDirectory = function() return true end,
  join = function(...) return table.concat({ ... }, "/") end,
  normalize = function(p) return p end,
}
local ctx = { K = {}, E = {}, P = {}, F = F, D = D, U = nil, SC = nil, NM = nil,
              cwd = "/", who = "root", W = 80, H = 25, st = nil, displayIdx = 1 }

print("=== the CLI repaints when a program hands the seat back ===")

local okL, cli = pcall(require, "shell.cli")
test("shell.cli loads", okL, cli)
if okL then
  local co = coroutine.create(function() return cli.run(ctx) end)
  local okR, err = coroutine.resume(co)
  test("the CLI starts and waits at its prompt", okR and coroutine.status(co) == "suspended", err)

  -- A full-screen program ran, drew over everything, and handed back.
  drawn, clears = {}, 0
  local okF, errF = coroutine.resume(co, "tos_focus")
  test("tos_focus is taken in stride", okF and coroutine.status(co) == "suspended", errF)
  local text = table.concat(drawn, "\n")
  test("the screen is cleared and redrawn", clears >= 1, clears)
  test("...with the header back", text:find("TOS CLI", 1, true) ~= nil)
  test("...and the prompt back", text:find("root:/$", 1, true) ~= nil, text:sub(1, 120))

  -- Still a working prompt afterwards.
  drawn = {}
  coroutine.resume(co, "key_down", "kb", string.byte("x"), 45)
  test("typing still reaches the prompt", table.concat(drawn, "\n"):find("root:/$ x", 1, true) ~= nil)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
