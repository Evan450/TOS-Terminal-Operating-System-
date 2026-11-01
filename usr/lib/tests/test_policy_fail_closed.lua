-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the security policy fails closed             ║
-- ║                                                                ║
-- ║  What this system allows is decided in one file now, which     ║
-- ║  makes that one file a single point of failure, so its failure ║
-- ║  has to be the safe one. If kernel/policy.lua will not load,   ║
-- ║  sandboxed code may require nothing and touch nothing, a       ║
-- ║  package may ask for nothing, a service gets nothing, and only ║
-- ║  a kernel session is an admin. Drives the real sandbox, pkg    ║
-- ║  decisions and rc tables, with the policy broken on purpose.   ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_policy_fail_closed.lua   (from TOS-Dev)

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
  beep = function() end, address = function() return "pc" end, pushSignal = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end, type = function() return "gpu" end,
  get = function(a) return a end, slot = function() return 0 end, invoke = function() end }

print("=== the real policy ===")
print()
local policy = require("kernel.policy")
test("it is one table", type(policy) == "table")
test("a sandboxed program may have the GPU", policy.BASE_COMPONENTS.gpu == true)
test("the modem is behind its capability", policy.GATED_COMPONENTS.modem == "peripheral.modem")
test("`legacy` can never be asked for", policy.PKG_RUN_CAPS.legacy == nil)
test("nor can a service have it", policy.SERVICE_CAPS.legacy == nil)
test("debug stays blocked", policy.BLOCKED_MODULES.debug == true)
test("a kernel session is an admin", policy.isAdmin({ isKernel = true }))
test("ADMIN is", policy.isAdmin({ tier = 2 }))
test("USER is not", not policy.isAdmin({ tier = 1 }))
test("no session is not", not policy.isAdmin(nil))

local realLoad = package.loaded["kernel.policyload"]
local loader = require("kernel.policyload")
test("the loader hands back the real one", loader("test") == policy)

print()
print("=== with the policy broken ===")
print()
package.loaded["kernel.policy"] = nil
package.loaded["kernel.policyload"] = nil
package.loaded["kernel.sandbox"] = nil
package.preload["kernel.policy"] = function() error("policy.lua is damaged") end
_G._TOS_POLICY_FAILURE = nil

local closed = require("kernel.policyload")("test")
test("the loader does not raise", type(closed) == "table")
test("it marks itself closed", closed.closed == true)
test("the failure is said, with the reason",
  tostring(_G._TOS_POLICY_FAILURE):find("policy.lua is damaged", 1, true) ~= nil, _G._TOS_POLICY_FAILURE)
test("and it says what that means",
  tostring(_G._TOS_POLICY_FAILURE):find("denied", 1, true) ~= nil)
test("no component type is open", next(closed.BASE_COMPONENTS) == nil
  and next(closed.GATED_COMPONENTS) == nil)
test("no module is open", next(closed.MODULE_NAMES) == nil and next(closed.MODULE_PREFIXES) == nil)
test("any module name at all is blocked", closed.BLOCKED_MODULES["anything.at.all"] == true)
test("any port at all is reserved", closed.SERVICE_PORTS[7777] ~= nil)
test("a package may ask for nothing", next(closed.PKG_RUN_CAPS) == nil)
test("a service gets nothing", next(closed.SERVICE_CAPS) == nil
  and next(closed.SERVICE_DEFAULT_CAPS) == nil)
test("no service runs at kernel tier", next(closed.KERNEL_SERVICES) == nil)
test("a kernel session still counts, so the machine can be repaired",
  closed.isAdmin({ isKernel = true }) == true)
test("ADMIN no longer does", closed.isAdmin({ tier = 2 }) == false)
test("nor ROOT", closed.isAdmin({ tier = 3 }) == false)
test("nor the login principal", closed.isAdmin({ isLogin = true }) == false)

-- The real sandbox on top of it: a program gets nothing it could use.
local okS, sandbox = pcall(require, "kernel.sandbox")
test("the sandbox still loads", okS and type(sandbox) == "table", sandbox)
if okS and type(sandbox) == "table" then
  local env = sandbox.build({ caps = { component = true, ["peripheral.modem"] = true } })
  test("a program builds, and can run", type(env) == "table")
  local okR = pcall(env.require, "compat")
  test("it can require nothing", not okR)
  local okR2 = pcall(env.require, "shell.keys")
  test("not even the keys table", not okR2)
  test("the GPU is refused too", env.component.proxy("anything") == nil)
end

do
  local h = assert(io.open("tos/kernel/diag.lua", "rb"))
  local src = h:read("a"); h:close()
  test("doctor says so, as an error",
    src:find('if _G._TOS_POLICY_FAILURE then R("security: "', 1, true) ~= nil)
end

package.preload["kernel.policy"] = nil
package.loaded["kernel.policyload"] = realLoad
_G._TOS_POLICY_FAILURE = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
