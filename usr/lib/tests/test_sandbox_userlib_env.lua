-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a user library runs with its caller's caps    ║
-- ║                                                                ║
-- ║  A sandboxed require() of an installed library (/usr/lib,       ║
-- ║  /usr/modules) went to the kernel loader, which compiles with   ║
-- ║  no environment -- the real _G. So any package could ship       ║
-- ║  /usr/lib/x.lua next to a command that says require("x") and    ║
-- ║  have x run as the kernel, whatever its manifest declared       ║
-- ║  (Sep 2026 pentest). A library now loads inside the sandbox     ║
-- ║  that asked for it; rc.d services keep the kernel loader.       ║
-- ║                                                                ║
-- ║  package.preload stands in for the kernel loader, compiling in  ║
-- ║  _G exactly as /init.lua's tosRequire does, so the pre-fix      ║
-- ║  sandbox demonstrably hands the kernel back.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_userlib_env.lua   (from TOS-Dev)

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
package.loaded["component"] = {
  list = function() return function() end end, proxy = function() end,
}
-- What a kernel-context chunk can see and a sandbox must not.
_G._TOS = { marker = "KERNEL" }

local LIBS = {
  ["/usr/lib/evil.lua"] = [[
    return { tos = _TOS, dbg = debug, exec = os and os.execute, rawReq = package }
  ]],
  ["/usr/lib/good.lua"] = [[
    local computer = require("computer")
    return { up = function() return computer.uptime() end, computer = computer }
  ]],
  ["/usr/lib/loopy.lua"] = [[ return require("loopy") ]],
}
package.loaded["kernel.fs"] = {
  exists   = function(p) return LIBS[p] ~= nil end,
  readFile = function(p) return LIBS[p] end,
}
-- The kernel loader, as /init.lua's tosRequire behaves: compile in _G.
for path, src in pairs(LIBS) do
  local name = path:match("^/usr/lib/(.-)%.lua$")
  package.preload[name] = function() return assert(load(src, "=" .. path, "t", _G))() end
end
-- An rc.d service's own library, already in the kernel's cache.
package.loaded["svclib"] = { shared = true }
LIBS["/usr/lib/svclib.lua"] = "return {}"

local sandbox = require("kernel.sandbox")
local function build(extra)
  local opts = { caps = { component = true } }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return sandbox.build(opts)
end

print("=== user libraries load inside the sandbox ===")
print()
local env = build()
local ok, evil = pcall(env.require, "evil")
test("the library loads (" .. tostring(not ok and evil or "ok") .. ")", ok and type(evil) == "table")
if ok and type(evil) == "table" then
  test("it cannot see _TOS", evil.tos == nil)
  test("it cannot see the debug library", evil.dbg == nil)
  test("it has no os.execute", evil.exec == nil)
  test("it has no package table", evil.rawReq == nil)
end
local okG, good = pcall(env.require, "good")
test("an honest library still works", okG and type(good) == "table" and good.up() == 0)
test("...and its computer is the sandbox's own, not the kernel's",
  okG and good.computer == env.computer and good.computer ~= package.loaded["computer"])
test("requiring it again returns the same instance", okG and env.require("good") == good)
local env2 = build()
test("another sandbox gets its own instance", okG and env2.require("good") ~= good)
local okL, errL = pcall(env.require, "loopy")
test("a circular require is refused, not recursed", okL == false and tostring(errL):find("circular", 1, true) ~= nil)

print("-- an rc.d service keeps the kernel loader --")
local svc = sandbox.build({ caps = { ["fs.read"] = true }, allowUserLibs = true })
test("allowUserLibs: require('svclib') is the kernel's table",
  svc.require("svclib") == package.loaded["svclib"])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
