-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the Lua REPL remembers                       ║
-- ║                                                                ║
-- ║  On a booted machine `x = 5` and then `x * 2` answered         ║
-- ║  "attempt to perform arithmetic on a nil value (global 'x')".  ║
-- ║  Every line got a new sandbox, so nothing defined at the       ║
-- ║  prompt survived to the next one, and each line paid for a     ║
-- ║  whole env build. It also ignored the quit key, the one way    ║
-- ║  out of everything else. Drives the real command.              ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_lua_repl.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 4e6 end,
  totalMemory = function() return 8e6 end, pullSignal = function() return nil end,
  beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end }

local register = require("shell.panels.commands.admin")
local shown, keys, builds = {}, {}, 0
local D = {
  fill = function() end,
  set = function(_, _, text) shown[#shown + 1] = tostring(text) end,
  getGpu = function() return { copy = function() end } end,
}
local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, U = {}, D = D,
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6, bg = 0,
        bar_fg = 1, bar_bg = 0 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end, openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end, canRead = function() return true end,
  canWrite = function() return true end, canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  promptInput = function() return "" end, confirm = function() return true end,
  confirmTyped = function() return true end,
  makeProgramEnv = function(opts)
    builds = builds + 1
    return setmetatable({ print = opts.stdout }, { __index = { tostring = tostring } })
  end,
  pullSignal = function()
    local k = table.remove(keys, 1)
    if not k then error("the REPL did not exit", 0) end
    return "key_down", "kb", k[1], k[2]
  end,
}
local C = {}
assert(pcall(register, C, S, deps))

local function typeLine(text)
  for c in text:gmatch(".") do keys[#keys + 1] = { c:byte(), 0 } end
  keys[#keys + 1] = { 13, 28 }
end
local function session(...)
  shown, keys, builds = {}, {}, 0
  for _, line in ipairs({ ... }) do typeLine(line) end
end
local function saw(text)
  for _, s in ipairs(shown) do if s == text then return true end end
  return false
end

print("=== the REPL ===")
print()

session("x = 5", "x * 2", "exit")
local ok, err = pcall(C.lua, {}, function() end)
test("a session runs and leaves", ok, err)
test("a variable set on one line is there on the next", saw("10"))
test("one sandbox for the session, not one per line", builds == 1, builds)

session("function f(n) return n + 1 end", "f(41)", "exit")
pcall(C.lua, {}, function() end)
test("so is a function", saw("42"))

session("function g()", "return 7", "end", "g()", "exit")
pcall(C.lua, {}, function() end)
test("a block over several lines still works", saw("7"))

session("1 + 2")
keys[#keys + 1] = { 17, 16 }                     -- ^Q
ok, err = pcall(C.lua, {}, function() end)
test("the quit key leaves", ok, err)
test("after answering what came first", saw("3"))

session("function h()")
keys[#keys + 1] = { 17, 16 }
ok, err = pcall(C.lua, {}, function() end)
test("and it leaves from inside a block, where `exit` would be code", ok, err)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
