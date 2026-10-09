-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: setmetatable in a sandbox, on a REAL machine  ║
-- ║                                                                ║
-- ║  OpenComputers' machine.lua wraps getmetatable so that          ║
-- ║  getmetatable("") answers nil. sandbox.lua read the string      ║
-- ║  metatable that way and compared every metamethod field with    ║
-- ║  it, so on hardware an ABSENT field matched (nil == nil) and    ║
-- ║  setmetatable refused nearly every metatable: "metatable        ║
-- ║  referencing protected library denied". Found 2026-10-09 when  ║
-- ║  the data loot disk's data.lua hit it on the headless machine; ║
-- ║  the printer add-on's setmetatable(self, Printer) had the same  ║
-- ║  fate, unseen because no printer was ever attached.             ║
-- ║                                                                ║
-- ║  Off-box Lua has a real string metatable, so every other        ║
-- ║  sandbox test passes either way. This one loads kernel.sandbox  ║
-- ║  under OC's getmetatable, which is the environment that broke. ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_setmetatable_oc.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 500000 end,
  pushSignal = function() end, address = function() return "addr" end,
}
package.loaded["kernel.screen"] = {}
package.loaded["kernel.fs"] = { exists = function() return false end }

-- OpenComputers' getmetatable, as machine.lua defines it for the whole
-- machine (the __gc unwrapping is irrelevant here).
local realGetmetatable = getmetatable
_G.getmetatable = function(t)
  if type(t) == "string" then return nil end
  return realGetmetatable(t)
end
test("the harness reproduces OC: getmetatable('') is nil", getmetatable("") == nil)

local sandbox = require("kernel.sandbox")
local function run(src, extra)
  local env = sandbox.build({ caps = {} })
  for k, v in pairs(extra or {}) do env[k] = v end
  local fn = assert(load(src, "=probe", "t", env))
  local ok, err = pcall(fn)
  return env, ok, err
end

print("=== setmetatable under OpenComputers' getmetatable ===")
print()

do
  local env, ok, err = run([[
    -- data.lua, verbatim in shape
    local data = {}
    setmetatable(data, { __index = function(_, key) return "card." .. key end })
    viaIndex = data.sha256
    -- a class, the printer add-on's shape
    local Printer = {}
    Printer.__index = Printer
    function Printer.name(self) return self.n end
    local p = setmetatable({ n = "lp0" }, Printer)
    name = p:name()
    -- __tostring alone, cluster state's shape
    local clear = setmetatable({}, { __tostring = function() return "<clear>" end })
    shown = tostring(clear)
    -- and reading it back
    same = getmetatable(p) == Printer
    strMt = getmetatable("abc")
  ]])
  test("the probe ran (" .. tostring(err) .. ")", ok)
  test("an __index-only metatable is accepted", env.viaIndex == "card.sha256")
  test("a class metatable is accepted", env.name == "lp0")
  test("a __tostring-only metatable is accepted", env.shown == "<clear>")
  test("getmetatable reads a table's metatable back", env.same == true)
  test("...and still hides the string metatable", env.strMt == nil)
end

print("-- the guard still refuses the real string library --")
do
  local env = run([[
    okIdx = pcall(setmetatable, {}, { __index = realS })
    okNew = pcall(setmetatable, {}, { __newindex = realS })
    okMt  = pcall(setmetatable, {}, realS)
    okCopy = pcall(setmetatable, {}, { __index = string })
  ]], { realS = string })
  test("__index = the real string library is refused", env.okIdx == false)
  test("__newindex = the real string library is refused", env.okNew == false)
  test("the real string library as a metatable is refused", env.okMt == false)
  test("the sandbox's own string copy is fine", env.okCopy == true)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
