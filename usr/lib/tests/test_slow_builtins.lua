-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a slow builtin says it is running            ║
-- ║                                                                ║
-- ║  The panels shell says "Running <name>…" before a PROGRAM      ║
-- ║  blocks, and nothing for a builtin, on the reasoning that      ║
-- ║  builtins are instant. pkg is a builtin, and `pkg install --all ║
-- ║  --dry-run` sat 12.7 s on a T3 headless machine (2026-10-09)   ║
-- ║  with the prompt frozen -- keys typed meanwhile landed in its  ║
-- ║  output afterwards. The registry now marks the builtins that   ║
-- ║  can take seconds `slow`, and the Enter path announces them.   ║
-- ║  The announcement itself is seen on the headless machine; this ║
-- ║  pins the declarations and the check that reads them.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_slow_builtins.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local okR, reg = pcall(require, "shell.panels.commands")
test("the command registry loads", okR and type(reg) == "table" and type(reg.entry) == "function")

print("=== slow builtins announce themselves ===")
print()
if okR then
  for _, name in ipairs({ "pkg", "srm", "verify", "doctor", "backup", "find", "du", "drive", "deploy" }) do
    local e = reg.entry(name)
    test(name .. " is marked slow", type(e) == "table" and e.slow == true)
  end
  for _, name in ipairs({ "ls", "cd", "echo", "help", "cat" }) do
    local e = reg.entry(name)
    test(name .. " is not (it answers at once, and a notice would only flash)",
      type(e) == "table" and not e.slow)
  end
end

local h = io.open("tos/shell/panels/events.lua", "rb")
local src = h and h:read("*a") or ""
if h then h:close() end
test("the Enter path asks the registry for `slow`",
  src:find("e.slow == true", 1, true) ~= nil
  and src:find("willRunProgram(first) or slowBuiltin(first)", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
