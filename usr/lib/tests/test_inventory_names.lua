-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `inventory` shows item names whole           ║
-- ║                                                                ║
-- ║  The Item column was a fixed 24 that cut every longer name     ║
-- ║  without a mark: "minecraft:diamond_pickaxe" (25) listed as    ║
-- ║  "minecraft:diamond_pickax". The last of the cut-name lists    ║
-- ║  that ls, pkg trust/repo and disk list were fixed for.         ║
-- ║  Runs the real extras.lua over a stub inventory.               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_inventory_names.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
local HUGE = "mod:" .. string.rep("x", 90)
package.loaded["peripheral.inventory"] = {
  available = function() return true end,
  list = function()
    return { { slot = 1, name = "minecraft:diamond_pickaxe", count = 1 },
             { slot = 2, name = "minecraft:stone", count = 64 },
             { slot = 3, name = HUGE, count = 2 },
             { slot = 4, name = "minecraft:air", count = 0 } }
  end,
}

local S = {
  T = setmetatable({}, { __index = function(_, k) return k end }),
  F = {}, K = {}, E = {}, P = {}, D = {}, W = 80, H = 25, st = "tok",
  U = { getSession = function() return { user = "root", tier = 3 } end },
}
local deps = setmetatable({ rp = function(p) return p end }, {
  __index = function() return function() return true end end })
local C = {}
assert(loadfile("tos/shell/panels/commands/extras.lua"))()(C, S, deps)
local out = {}
C.inventory({}, function(line) out[#out + 1] = tostring(line) end)
local text = table.concat(out, "\n")

print("=== inventory ===")
test("a 25-character item name is listed whole", text:find("minecraft:diamond_pickaxe ", 1, true) ~= nil, text)
test("a name too long for the screen ends in ~", text:find("x~", 1, true) ~= nil, text)
local widest, countAt = 0, {}
for _, line in ipairs(out) do
  widest = math.max(widest, #line)
  local at = line:find("%d+$")
  if line:find("^ %d") and at then countAt[#countAt + 1] = at end
end
test("no line is wider than the screen", widest <= 80, widest)
test("the counts line up", #countAt == 3 and countAt[1] == countAt[2] and countAt[2] == countAt[3],
  table.concat(countAt, ","))
test("an empty slot is still left out", not text:find("minecraft:air", 1, true))

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
