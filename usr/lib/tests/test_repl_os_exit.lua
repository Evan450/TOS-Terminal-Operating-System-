-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: os.exit() leaves the Lua REPL                ║
-- ║                                                                ║
-- ║  In a program os.exit() ends the program: the sandbox raises   ║
-- ║  an exit sentinel and the runner reads it as an exit. The      ║
-- ║  REPL evaluates each line under its own pcall, which caught    ║
-- ║  the sentinel and printed it: on the headless machine          ║
-- ║  `os.exit()` answered "exit nil" and the REPL carried on.      ║
-- ║  Found by the local worker; `exit` itself always worked.       ║
-- ║                                                                ║
-- ║  Evaluates lines the way the REPL does, in a real sandbox, and ║
-- ║  checks the REPL acts on the answer.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_repl_os_exit.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 500000 end,
  pushSignal = function() end, address = function() return "addr" end,
}
package.loaded["kernel.screen"] = {}
package.loaded["kernel.fs"] = { exists = function() return false end }
package.loaded["component"] = {
  list = function() return function() return nil end end,
  type = function() return nil end, proxy = function() return nil end,
  slot = function() return -1 end,
}
package.loaded["kernel.process"] = { sleep = function() end, current = function() return nil end }
package.loaded["unicode"] = { len = function(s) return #s end, char = string.char }
-- os comes with the compat.io cap, as the REPL's program env has it.
package.loaded["compat.io"] = { who = "io" }
package.loaded["compat.filesystem"] = { who = "filesystem" }

local sandbox = require("kernel.sandbox")
local env = sandbox.build({ caps = { ["compat.io"] = true } })

-- One REPL line, evaluated as admin.lua's REPL does: expression form
-- first, then statement form, under pcall.
local function line(src)
  local fn = load("return " .. src, "=repl", "t", env)
  if not fn then fn = assert(load(src, "=repl", "t", env)) end
  return pcall(fn)
end

print("=== what the REPL sees ===")
local ok1, res1 = line("os.exit()")
test("os.exit() fails the line's pcall", ok1 == false)
test("...with the sentinel, not an error message", sandbox.exitStatus(res1) == true, tostring(res1))
local ok2, res2 = line("os.exit(3)")
test("os.exit(3) is an exit too, with its code", not ok2 and sandbox.exitStatus(res2) == 3)
local ok3, res3 = line("error('boom')")
test("a real error is not taken for an exit", not ok3 and sandbox.exitStatus(res3) == nil, tostring(res3))
local ok4, res4 = line("1 + 1")
test("and a value is a value", ok4 and res4 == 2)

print("=== what the REPL does with it ===")
local f = assert(io.open("tos/shell/panels/commands/admin.lua", "rb"))
local src = f:read("a"); f:close()
local evalAt = src:find("local ok3, res = pcall(fn3)", 1, true)
local checkAt = evalAt and src:find("sbMod.exitStatus(res) ~= nil", evalAt, true)
local breakAt = checkAt and src:find("if exited then break end", checkAt, true)
local printAt = evalAt and src:find("reout(tostring(res), T.error)", evalAt, true)
test("the REPL asks the sandbox whether the line exited", checkAt ~= nil)
test("...and leaves its loop when it did", breakAt ~= nil)
test("...before the error would be printed", breakAt ~= nil and printAt ~= nil and breakAt < printAt)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
