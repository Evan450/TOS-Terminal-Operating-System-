-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg/modules Admin Gate (CR-5)      ║
-- ║  install/uninstall/enable/disable require ADMIN+.     ║
-- ║  Kernel/login pseudo-sessions pass; guests/users are  ║
-- ║  denied; no-session fails closed.                     ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_admin_gate.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end, loadFile = function() return nil end,
}

-- Minimal in-memory-ish fs stub: nothing exists, writes succeed.
local fsStub = {
  exists = function() return false end,
  makeDirectory = function() return true end,
  list = function() return {} end,
  isDirectory = function() return false end,
  join = function(a, b) return (a:gsub("/$", "")) .. "/" .. b end,
  normalize = function(p) return p end,
  readFile = function() return nil end,
  writeFile = function() return true end,
  split = function(p) return p:gsub("/[^/]*$", "") end,
}

-- Users mock: getSession is irrelevant here (we pass sessions explicitly).
local usersMock = {
  currentSession = function() return nil end,  -- force "no session" fallback
}

local ADMIN = { user = "admin", tier = 2 }
local USER  = { user = "bob",   tier = 1 }
local GUEST = { user = "guest", tier = 0 }
local KERNEL = { user = "_kernel_", isKernel = true, tier = 0 }

local here = (arg and arg[0]) or "usr/lib/tests/test_admin_gate.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local pkg = loadMod("pkg.lua")
if not pkg then
  print("FAIL: could not load pkg.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
pkg.init({ fs = fsStub, log = nil, users = usersMock })

local function isPrivErr(_, err)
  return type(err) == "string" and err:find("privileges", 1, true) ~= nil
end

print("=== pkg Admin Gate Tests ===")
print()

-- ── pkg.install gate ───────────────────────────────────────────────
test("pkg.install denies GUEST", true, isPrivErr(pkg.install("/x", { session = GUEST })))
test("pkg.install denies USER",  true, isPrivErr(pkg.install("/x", { session = USER })))
test("pkg.install denies no-session", true, isPrivErr(pkg.install("/x", {})))
-- ADMIN passes the gate: the error (if any) must NOT be a privileges error.
test("pkg.install allows ADMIN past gate", false, isPrivErr(pkg.install("/x", { session = ADMIN })))
test("pkg.install allows KERNEL past gate", false, isPrivErr(pkg.install("/x", { session = KERNEL })))

-- ── pkg.uninstall / setEnabled / installByName / installFromFloppy ─
test("pkg.uninstall denies USER", true, isPrivErr(pkg.uninstall("foo", { session = USER })))
test("pkg.setEnabled denies USER", true, isPrivErr(pkg.setEnabled("foo", true, { session = USER })))
test("pkg.installByName denies GUEST", true, isPrivErr(pkg.installByName("foo", { session = GUEST })))
test("pkg.installFromFloppy denies USER", true, isPrivErr(pkg.installFromFloppy({ session = USER })))

-- (The legacy modules admin gate was removed with kernel.modules in v1.3.1;
--  pkg is now the sole install/enable path and is gated above.)

-- ── inert when users module not wired (boot/test safety) ───────────
local pkg2 = loadMod("pkg.lua")
pkg2.init({ fs = fsStub, log = nil })  -- no users
test("gate inert without users module", false, isPrivErr(pkg2.install("/x", {})))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
