-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the CLI repaints after a full-screen built-in ║
-- ║                                                                ║
-- ║  On the headless machine, `pkg install` from the CLI opened the ║
-- ║  package picker, and Esc closed it onto a blank screen with a  ║
-- ║  bare `root:/$` on row 6: no header, no key bar, and they did  ║
-- ║  not come back however much was typed after. The picker is a   ║
-- ║  BUILT-IN that draws straight to the GPU, so the tos_focus     ║
-- ║  repaint a full-screen program gets never happens; it calls    ║
-- ║  deps.drawAll when it hands back, and the CLI's was a no-op.   ║
-- ║  The tutorial and the tape toolbox hand back the same way.     ║
-- ║                                                                ║
-- ║  Runs the real shell/cli.lua in a coroutine, types `pkg        ║
-- ║  install` at its prompt, and lets a stand-in picker blank the  ║
-- ║  screen. Then `theme set`, which repaints and THEN reports:    ║
-- ║  the repaint clears now, and the message must still show.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cli_takeover.lua   (from TOS-Dev)

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

-- The screen, as a list of what was drawn since the last clear. A clear
-- empties it, which is exactly what a person would see.
local screen, clears = {}, 0
local theme = setmetatable({}, { __index = function() return 0xFFFFFF end })
local D = {
  getTheme = function() return theme end, getGpuTier = function() return 2 end,
  getSize = function() return 80, 25 end, getGpu = function() return nil end,
  c = function() return 0xFFFFFF end,
  set = function(_, _, s) screen[#screen + 1] = tostring(s) end,
  fill = function() end,
  clear = function() clears = clears + 1; screen = {} end,
}
local F = {
  exists = function() return true end, list = function() return {} end,
  isDirectory = function() return true end,
  join = function(...) return table.concat({ ... }, "/") end,
  normalize = function(p) return p end,
}
-- A root session, so `pkg` passes its admin gate.
local U = { getSession = function() return { tier = 3, user = "root" } end }

-- The picker: it owns the screen while it runs and blanks it on the way
-- out, as the real one does when Esc closes it.
local pickerRan = false
package.loaded["kernel.pkg"] = {
  runInstaller = function()
    pickerRan = true
    D.clear()
    return true
  end,
}
-- A theme manager that applies anything and saves nowhere. `theme` finds
-- the kernel's at _G._TOS.theme.
_G._TOS = { theme = setmetatable({
  apply = function() return true end,
  saveForUser = function() return true end,
}, { __index = function() return function() return true end end }) }

local ctx = { K = {}, E = {}, P = {}, F = F, D = D, U = U, SC = nil, NM = nil,
              cwd = "/", who = "root", W = 80, H = 25, st = "seat-token", displayIdx = 1 }

local function typeLine(co, line)
  for ch in line:gmatch(".") do coroutine.resume(co, "key_down", "kb", string.byte(ch), 0) end
  return coroutine.resume(co, "key_down", "kb", 13, 28)
end

print("=== the CLI repaints after a full-screen built-in ===")

local okL, cli = pcall(require, "shell.cli")
test("shell.cli loads", okL, cli)
if okL then
  local co = coroutine.create(function() return cli.run(ctx) end)
  local okR, err = coroutine.resume(co)
  test("the CLI starts and waits at its prompt", okR and coroutine.status(co) == "suspended", err)

  local before = clears
  local okP, errP = typeLine(co, "pkg install")
  test("`pkg install` runs and returns to the prompt", okP and coroutine.status(co) == "suspended", errP)
  test("...through the picker", pickerRan)
  local text = table.concat(screen, "\n")
  test("the CLI redraws after the picker blanks the screen", clears >= before + 2, clears - before)
  test("...with the header back", text:find("TOS CLI", 1, true) ~= nil, text:sub(1, 160))
  test("...and the key bar", text:find("[exit] Log out", 1, true) ~= nil)
  test("...and the prompt", text:find("root:/$", 1, true) ~= nil)

  typeLine(co, "theme set amber")
  text = table.concat(screen, "\n")
  test("`theme set` repaints in the new colours", text:find("TOS CLI", 1, true) ~= nil)
  test("...and its confirmation survives the repaint",
    text:find("Applied theme: amber", 1, true) ~= nil, text:sub(1, 200))
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
