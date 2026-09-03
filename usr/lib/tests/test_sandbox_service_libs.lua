-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: rc.d service shims may require THEIR OWN   ║
-- ║  package's library; ordinary sandboxed code still may not    ║
-- ║                                                              ║
-- ║  Full-priv add-on libs (`mail`, `rbmk-cmd`, …) are on the     ║
-- ║  sandbox blocklist so a sandboxed COMMAND (a game, a user    ║
-- ║  program) can't pull one in and reach kernel.net through it.  ║
-- ║  But rc.d SERVICE shims are sandboxed too, and a service      ║
-- ║  package's shim legitimately does `require("mail")` — which   ║
-- ║  is how cluster-manager/clusterd have always started. The     ║
-- ║  blocklist broke that: the mail service failed at every boot  ║
-- ║  with "module 'mail' is not available to sandboxed code",     ║
-- ║  so mail could never RECEIVE (emulator round 6).             ║
-- ║                                                              ║
-- ║  Fix: rc.lua builds service envs with allowUserLibs, which    ║
-- ║  lifts the block ONLY for names that really resolve under     ║
-- ║  /usr/lib or /usr/modules. This pins BOTH directions, plus    ║
-- ║  that the dangerous non-lib names stay blocked for services.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_service_libs.lua  (from TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

-- ── Stubs: a fake /usr/lib with one installed add-on library ──────
local FAKE_LIB_FILES = {
  ["/usr/lib/mail.lua"]           = true,
  ["/usr/modules/snake/logic.lua"] = true,
}
package.loaded["kernel.fs"] = {
  exists = function(p) return FAKE_LIB_FILES[p] == true end,
  isDirectory = function() return false end,
  readFile = function() return nil end,
}
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 1e6 end,
  address = function() return "test" end,
  pushSignal = function() end, pullSignal = function() return nil end,
}
-- The modules the bypass is allowed to reach: pre-cache them so the real
-- require() resolves without touching disk.
package.loaded["mail"] = { _isTheRealMailLib = true }
package.loaded["snake.logic"] = { _isSnakeLogic = true }

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local sandbox = require("kernel.sandbox")

print("=== rc.d service libs vs sandboxed commands ===")
print()

local function requireIn(env, name)
  if type(env) ~= "table" or type(env.require) ~= "function" then
    return false, "no require in env"
  end
  return pcall(env.require, name)
end

-- ── An ORDINARY sandboxed command env (a game, a user program) ────
local cmdEnv = sandbox.build({ caps = { ["fs.read"] = true } })
test("command env built", type(cmdEnv) == "table")
do
  local ok, err = requireIn(cmdEnv, "mail")
  test("a sandboxed COMMAND may NOT require the mail add-on lib", ok == false)
  test("...and the refusal says why",
    type(err) == "string" and err:find("not available to sandboxed code", 1, true) ~= nil)
end

-- ── An rc.d SERVICE env (allowUserLibs) ───────────────────────────
local svcEnv = sandbox.build({ caps = { ["fs.read"] = true }, allowUserLibs = true })
test("service env built", type(svcEnv) == "table")
do
  local ok, mod = requireIn(svcEnv, "mail")
  test("an rc.d SERVICE may require its package's lib (the mail bug)", ok == true)
  test("...and gets the real module", ok and type(mod) == "table"
    and mod._isTheRealMailLib == true)

  -- A dotted user-lib name under /usr/modules resolves too.
  local ok2, mod2 = requireIn(svcEnv, "snake.logic")
  test("dotted /usr/modules names resolve for a service", ok2 == true
    and type(mod2) == "table" and mod2._isSnakeLogic == true)
end

-- ── The bypass must NOT widen anything else ───────────────────────
-- These are blocked names that do NOT live under a user-lib root, so
-- even a service env must still be refused. This is the whole reason
-- the bypass is keyed on "resolves under /usr/lib or /usr/modules"
-- rather than on a plain allow-flag.
do
  local stillBlocked = { "debug", "os", "io", "package", "component",
                         "computer", "filesystem", "shell.panels.commands",
                         "shell.init", "init" }
  local leaked = {}
  for _, name in ipairs(stillBlocked) do
    local ok = requireIn(svcEnv, name)
    if ok then leaked[#leaked + 1] = name end
  end
  test("a service env STILL cannot reach debug/os/io/component/shell.*"
    .. (#leaked > 0 and ("  [leaked: " .. table.concat(leaked, ", ") .. "]") or ""),
    #leaked == 0)
end

-- Kernel modules stay unreachable from BOTH env kinds.
do
  local okC = requireIn(cmdEnv, "kernel.net")
  local okS = requireIn(svcEnv, "kernel.net")
  test("kernel.* is unreachable from a command env", okC == false)
  test("kernel.* is unreachable from a service env too", okS == false)
end

-- A blocked name that does NOT exist on disk is still refused even in a
-- service env (the bypass requires a REAL resolved file, so a package
-- can't unlock a name by merely claiming it).
do
  local ok = requireIn(svcEnv, "mailui")   -- on the blocklist, not in FAKE_LIB_FILES
  test("an unresolvable blocked name stays refused for a service", ok == false)
end

-- ── rc.lua actually asks for it ───────────────────────────────────
do
  local function readAll(p)
    local h = io.open(p, "rb"); if not h then return nil end
    local s = h:read("*a"); h:close(); return s
  end
  local src
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    src = readAll(pre .. "tos/kernel/rc.lua"); if src then break end
  end
  test("kernel/rc.lua readable", src ~= nil)
  if src then
    test("rc.lua builds service envs with allowUserLibs",
      src:find("allowUserLibs", 1, true) ~= nil)
    -- The kernel-tier path must NOT get it (those use buildKernelEnv,
    -- whose require is the separately-gated allowlist).
    test("the _kernel_ tier still uses buildKernelEnv",
      src:find("buildKernelEnv()", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
