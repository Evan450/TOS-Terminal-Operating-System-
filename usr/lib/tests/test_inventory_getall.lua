-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the fast inventory path names the real slot  ║
-- ║                                                                ║
-- ║  tos/peripheral/inventory.lua reads a transposer / inventory   ║
-- ║  controller two ways: one getAllStacks call (fast), or one     ║
-- ║  getStackInSlot per slot (the fallback). The fast path said    ║
-- ║  "getAll() is 0-based" and labelled entry i as slot i + 1.     ║
-- ║                                                                ║
-- ║  It is not 0-based. OpenComputers 1.8.10 (the Irradiated       ║
-- ║  Circuits pack's version), li.cil.oc.api.prefab.               ║
-- ║  ItemStackArrayValue.getAll, disassembled (javap, 2026-10-26): ║
-- ║     for i in 0 until array.length:                              ║
-- ║       map.put(Integer.valueOf(i + 1), stack or emptyMap)        ║
-- ║  -- a TreeMap keyed from 1, with an EMPTY TABLE for an empty    ║
-- ║  slot. Totals were right; every .slot was one high and the last ║
-- ║  named a slot that does not exist, so the two paths disagreed.  ║
-- ║  Latent (stock aggregates, never reads .slot) until something   ║
-- ║  moves an item by the slot inv.stacks() gave it.                ║
-- ║                                                                ║
-- ║  The REAL inventory.lua, against a fake transposer whose        ║
-- ║  getAllStacks() reproduces that bytecode. Found by the 2026-09  ║
-- ║  audit (claude/tos-audit), whose pin this replaces.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_inventory_getall.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

print("=== inv.stacks(): fast path vs per-slot path ===")
print()

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- A chest on one side: iron in slot 1, gold in slot 3, slots 2 and 4 empty.
local IRON = { name = "minecraft:iron_ingot", label = "Iron Ingot", size = 10, damage = 0, maxSize = 64 }
local GOLD = { name = "minecraft:gold_ingot", label = "Gold Ingot", size = 5,  damage = 0, maxSize = 64 }
local SLOTS = { IRON, nil, GOLD, nil }
local SIZE = 4
local ZERO_BASED = false   -- an OC build that keys getAll() from 0, if one exists

local transposer = {
  getInventorySize = function() return SIZE end,
  -- OC's getStackInSlot is 1-based and returns nil for an empty slot.
  getStackInSlot = function(_, slot) return SLOTS[slot] end,
  -- OC 1.8.10: an ItemStackArrayValue whose getAll() is a TreeMap keyed
  -- i + 1 for i = 0..n-1, with an empty map for an empty slot.
  getAllStacks = function()
    return {
      getAll = function()
        local t = {}
        for i = 0, SIZE - 1 do
          t[ZERO_BASED and i or (i + 1)] = SLOTS[i + 1] or {}
        end
        return t
      end,
    }
  end,
}

package.loaded["kernel.hal"] = {
  proxy = function(ctype) if ctype == "transposer" then return transposer end end,
}
package.loaded["kernel.process"] = { current = function() return nil end }
package.loaded["kernel.event"] = { on = function() end }

local okI, inv = pcall(require, "peripheral.inventory")
test("peripheral/inventory.lua loads", okI and type(inv) == "table" and inv.stacks ~= nil)
if not (okI and type(inv) == "table") then
  print(); print(string.format("Results: %d passed, %d failed", passed, failed + 1))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local function slotsById(list)
  local m = {}
  for _, s in ipairs(list or {}) do m[s.id] = s.slot end
  return m
end
local function totalsById(list)
  local m = {}
  for _, s in ipairs(list or {}) do m[s.id] = (m[s.id] or 0) + s.count end
  return m
end

local SIDE = 1
local fast = inv.stacks(SIDE)
local keep = transposer.getAllStacks
transposer.getAllStacks = nil               -- the proxy is cached; this forces the fallback
local slow = inv.stacks(SIDE)
transposer.getAllStacks = keep

local ft, st = totalsById(fast), totalsById(slow)
test("both paths find the same items in the same amounts",
  ft[IRON.name] == 10 and st[IRON.name] == 10 and ft[GOLD.name] == 5 and st[GOLD.name] == 5
    and #(fast or {}) == 2 and #(slow or {}) == 2)

local fs, ss = slotsById(fast), slotsById(slow)
test("the per-slot path reports the real slots (iron 1, gold 3)",
  ss[IRON.name] == 1 and ss[GOLD.name] == 3)
test("the getAllStacks path reports the same slots (iron 1, gold 3)",
  fs[IRON.name] == 1 and fs[GOLD.name] == 3)

-- A full chest: the last stack is in the last slot, not one past it.
SLOTS = { IRON, GOLD, IRON, GOLD }
local full = inv.stacks(SIDE)
local maxSlot = 0
for _, s in ipairs(full or {}) do maxSlot = math.max(maxSlot, s.slot) end
test("a full chest's last stack is in slot " .. SIZE .. " (got " .. maxSlot .. ")", maxSlot == SIZE)
test("...and all four are found", #(full or {}) == 4)

-- Should an OC build key getAll() from 0, it is read as such.
SLOTS = { IRON, nil, GOLD, nil }
ZERO_BASED = true
local z = slotsById(inv.stacks(SIDE))
test("a 0-keyed getAll() still gives iron 1, gold 3", z[IRON.name] == 1 and z[GOLD.name] == 3)

local h = io.open("tos/peripheral/inventory.lua", "rb")
local src = h and h:read("*a"); if h then h:close() end
test("inventory.lua no longer says getAll() is 0-based",
  src ~= nil and src:find("getAll() is 0-based", 1, true) == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
