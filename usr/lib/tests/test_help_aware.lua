-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: install-aware help (needMet/helpList)║
-- ║  - dependency tokens resolve against the live system   ║
-- ║  - help hides commands whose hardware/module is absent  ║
-- ║  - tier filtering still applies                         ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_help_aware.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_help_aware.lua"
local base = here:gsub("[^/\\]*$", "")
local M
for _, p in ipairs({ base .. "../../../tos/shell/panels/commands.lua",
    "tos/shell/panels/commands.lua", "TOS-Dev/tos/shell/panels/commands.lua" }) do
  local chunk = loadfile(p)
  if chunk then M = chunk(); break end
end
if not M then
  print("FAIL: could not load commands.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Mock the live system: a redstone block attached, network up, the `tape`
-- package installed — but NO robot, NO swap.
package.loaded["component"] = {
  list = function(t)
    local has = (t == "redstone")
    local done = false
    return function()
      if has and not done then done = true; return "rs-addr", t end
      return nil
    end
  end,
}
_G._TOS = {
  net = {},                                  -- network up
  pkg = { info = function(n) return n == "tape" and {} or nil end },
}

print("=== install-aware help Tests ===")
print()

-- ── needMet token resolution ───────────────────────────────────────
test("needMet(nil) -> true (no dependency)", true, M.needMet(nil))
test("needMet(net) when net up", true, M.needMet("net"))
test("needMet(swap) when swap down", false, M.needMet("swap"))
test("needMet(component:redstone) attached", true, M.needMet("component:redstone"))
test("needMet(component:robot) absent", false, M.needMet("component:robot"))
test("needMet(module:tape) installed", true, M.needMet("module:tape"))
test("needMet(unknown token) fails OPEN", true, M.needMet("totally-unknown"))

-- ── helpList filters by availability AND tier ──────────────────────
-- helpList collapses aliases onto the canonical row ("ls (dir)"), so
-- match on the canonical name at the start of the display name.
local function has(group, name)
  for _, e in ipairs(group or {}) do
    if e.name == name or e.name:match("^" .. name .. " %(") then return true end
  end
  return false
end

local root = M.helpList(3)
test("net command shown (net up)", true, has(root.extras, "net"))
test("chat shown (needs net, up)", true, has(root.extras, "chat"))
test("robot hidden (no robot hardware)", false, has(root.extras, "robot"))
test("redstone shown (redstone attached)", true, has(root.extras, "redstone"))
test("tape shown (module installed)", true, has(root.extras, "tape"))
test("inventory hidden (no inventory peripheral)", false, has(root.extras, "inventory"))
test("alias rows are collapsed (no standalone dir row)", false, has(root.core, "dir"))
test("canonical row names its aliases", true, (function()
  for _, e in ipairs(root.core or {}) do
    if e.name == "ls (dir)" then return true end
  end
  return false
end)())
test("core command always shown (ls)", true, has(root.core, "ls"))

-- Tier filter: a guest (tier 0) must not see admin/root commands.
local guest = M.helpList(0)
test("guest does not see 'flash' (root)", false, has(guest.admin, "flash"))
test("guest does not see 'useradd' (admin)", false, has(guest.admin, "useradd"))
test("guest sees 'help' (tier 0)", true, has(guest.core, "help"))

-- Network down: net-dependent commands vanish.
_G._TOS.net = nil
local noNet = M.helpList(3)
test("net hidden when network down", false, has(noNet.extras, "net"))
test("chat hidden when network down", false, has(noNet.extras, "chat"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
