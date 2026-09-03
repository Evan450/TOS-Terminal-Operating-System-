-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: launcher menu model (validation + nav)   ║
-- ║  normalizeMenu hardens an untrusted menu (cfg/tape); a     ║
-- ║  malformed item is dropped, never run. resolveSelection    ║
-- ║  maps an index to an action.                               ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_launcher_menu.lua

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

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local L = require("shell.launcher")

print("=== launcher menu model Tests ===")
print()

-- A mix of valid and malformed items: only the valid ones survive.
local m = L.normalizeMenu({
  title = "Home",
  items = {
    { label = "Status",  run = "doctor" },                 -- ok
    { label = "Tools",   menu = { items = { { label = "df", run = "df" } } } }, -- ok submenu
    { label = "About",   info = "TOS launcher" },          -- ok info
    { label = "Bad nl",  run = "doctor\nrm -rf /" },       -- newline → dropped
    { run = "noLabel" },                                   -- no label → dropped
    { label = string.rep("x", 200), run = "ok" },          -- label too long → dropped
    { label = "Empty submenu", menu = { items = {} } },    -- empty submenu → dropped
    { label = "Mystery" },                                 -- no action → dropped
  },
})
test("title kept", "Home", m.title)
test("valid items kept (3)", 3, #m.items)
test("first is a run item", "doctor", m.items[1].run)
test("second is a submenu", "table", type(m.items[2].menu))
test("submenu child is run", "df", m.items[2].menu.items[1].run)
test("third is info", "TOS launcher", m.items[3].info)

-- Newline-injecting run must NOT survive anywhere.
local foundNewline = false
for _, it in ipairs(m.items) do if it.run and it.run:find("\n") then foundNewline = true end end
test("no newline survives in any run", false, foundNewline)

-- Depth cap: deeply nested menus stop nesting (no crash, bounded).
local deep = { items = {} }
local cur = deep
for _ = 1, 10 do
  local inner = { items = { { label = "leaf", run = "df" } } }
  cur.items[#cur.items + 1] = { label = "down", menu = inner }
  cur = inner
end
local okDeep = pcall(L.normalizeMenu, deep)
test("deep nesting doesn't crash", true, okDeep)

-- resolveSelection action descriptors.
test("resolve run",     "run",     L.resolveSelection(m, 1).type)
test("resolve submenu", "submenu", L.resolveSelection(m, 2).type)
test("resolve info",    "info",    L.resolveSelection(m, 3).type)
test("resolve OOB",     "none",    L.resolveSelection(m, 99).type)
test("resolve nil idx", "none",    L.resolveSelection(m, nil).type)

-- Non-table input normalizes to an empty menu (no crash).
test("garbage -> empty menu", 0, #L.normalizeMenu("not a table").items)

-- Cluster profile is well-formed: non-empty, all items run a command.
local cp = L.clusterProfile()
test("cluster profile non-empty", true, #cp.items > 0)
local allRun = true
for _, it in ipairs(cp.items) do if not it.run then allRun = false end end
test("cluster profile items all run", true, allRun)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
