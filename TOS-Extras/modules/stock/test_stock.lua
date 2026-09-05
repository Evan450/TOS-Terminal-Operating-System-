-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: stock/stock.lua                            ║
-- ║                                                              ║
-- ║  Pure aggregation, no hardware. The headline property is      ║
-- ║  IDENTITY: a stock count keyed on the DISPLAY LABEL silently  ║
-- ║  merges different items (two mods' "Copper Ingot") and splits ║
-- ║  identical ones (an anvil-renamed stack), which is the one    ║
-- ║  thing an inventory monitor must never do. Also: a watched     ║
-- ║  item that has hit ZERO must still appear — that is exactly   ║
-- ║  when the monitor should be shouting, and it is the case a    ║
-- ║  "iterate what we found" implementation drops.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/stock/test_stock.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "modules/?.lua;modules/?/init.lua;" .. package.path
local S = require("stock.stock")

print("=== stock aggregation Tests ===")
print()

local function reading(id, dmg, count, sideName, slot, label)
  return {
    key = id .. "#" .. tostring(dmg or 0), id = id,
    label = label or id, count = count,
    sideName = sideName or "north", slot = slot or 1,
  }
end

-- ── Aggregation ─────────────────────────────────────────────────────
print("-- aggregation --")
do
  local rows = S.aggregate({
    reading("minecraft:cobblestone", 0, 64, "north", 1),
    reading("minecraft:cobblestone", 0, 32, "north", 2),
    reading("minecraft:cobblestone", 0, 64, "east",  1),
    reading("minecraft:iron_ingot",  0, 12, "north", 3),
  })
  eq("two distinct items", 2, #rows)
  eq("cobblestone totalled across slots and sides", 160, rows[1].total)
  eq("...counted as three stacks", 3, rows[1].stacks)
  eq("...from two sides", 2, #rows[1].sides)
  eq("sorted by total descending", "minecraft:iron_ingot", rows[2].id)
end

do
  -- THE identity property, both directions.
  local rows = S.aggregate({
    -- Same label, different registry name: two different items.
    { key = "modA:copper#0", id = "modA:copper", label = "Copper Ingot",
      count = 10, sideName = "north" },
    { key = "modB:copper#0", id = "modB:copper", label = "Copper Ingot",
      count = 5, sideName = "north" },
  })
  eq("same label + different id stays TWO rows", 2, #rows)

  local rows2 = S.aggregate({
    -- Same registry name, different labels (one was renamed on an anvil):
    -- still one item.
    { key = "minecraft:diamond#0", id = "minecraft:diamond",
      label = "Diamond", count = 3, sideName = "north" },
    { key = "minecraft:diamond#0", id = "minecraft:diamond",
      label = "Bob's Lucky Diamond", count = 2, sideName = "north" },
  })
  eq("same id + different labels merges to ONE row", 1, #rows2)
  eq("...with the counts summed", 5, rows2[1].total)
  eq("...and a stable label (first seen wins)", "Diamond", rows2[1].label)

  -- Damage distinguishes variants that share a registry name.
  local rows3 = S.aggregate({
    reading("minecraft:wool", 0, 10, "north"),
    reading("minecraft:wool", 14, 3, "north"),
  })
  eq("damage variants stay distinct", 2, #rows3)
end

do
  eq("empty input aggregates to nothing", 0, #S.aggregate({}))
  eq("nil input is handled", 0, #S.aggregate(nil))
  -- Zero and negative counts are not stock.
  eq("zero-count readings are ignored", 0,
    #S.aggregate({ reading("x:y", 0, 0, "north") }))
  eq("malformed readings are skipped", 0,
    #S.aggregate({ "not a table", {}, { count = 5 } }))
end

-- ── Watches ─────────────────────────────────────────────────────────
print("\n-- low-stock watches --")
do
  local rows = S.aggregate({
    reading("minecraft:iron_ingot", 0, 12, "north"),
    reading("minecraft:coal", 0, 500, "north"),
  })
  local watched = S.applyWatches(rows, {
    ["minecraft:iron_ingot#0"] = 64,
    ["minecraft:coal#0"] = 100,
  })
  local byKey = {}
  for _, r in ipairs(watched) do byKey[r.key] = r end
  test("under-threshold item flagged low", byKey["minecraft:iron_ingot#0"].low == true)
  test("over-threshold item not flagged", byKey["minecraft:coal#0"].low ~= true)
  eq("threshold recorded on the row", 64, byKey["minecraft:iron_ingot#0"].min)
end

do
  -- The case a naive implementation drops: you are watching an item and
  -- the bin is now EMPTY, so it is in no reading at all.
  local rows = S.aggregate({ reading("minecraft:coal", 0, 500, "north") })
  local watched = S.applyWatches(rows,
    { ["minecraft:redstone#0"] = 64 },
    { ["minecraft:redstone#0"] = "Redstone" })
  local found
  for _, r in ipairs(watched) do
    if r.key == "minecraft:redstone#0" then found = r end
  end
  test("a watched item at ZERO still appears", found ~= nil)
  eq("...with total 0", 0, found and found.total)
  test("...flagged low", found and found.low == true)
  test("...marked absent", found and found.absent == true)
  eq("...using the remembered label", "Redstone", found and found.label)
  eq("...and sorted to the top", "minecraft:redstone#0", watched[1].key)
end

do
  local rows = S.applyWatches(S.aggregate({
    reading("a:a", 0, 10, "north"),
    reading("b:b", 0, 10, "north"),
    reading("c:c", 0, 90, "north"),
  }), { ["a:a#0"] = 100, ["b:b#0"] = 20, ["c:c#0"] = 100 })
  local low = S.lowStock(rows)
  eq("three watched, three low", 3, #low)
  -- Worst deficit first: a is short 90, c is short 10, b is short 10.
  eq("worst deficit first", "a:a", low[1].id)
  eq("ties broken by label", "b:b", low[2].id)
end

-- ── Filtering ───────────────────────────────────────────────────────
print("\n-- filtering --")
do
  local rows = S.aggregate({
    reading("minecraft:iron_ingot", 0, 10, "north", 1, "Iron Ingot"),
    reading("minecraft:coal", 0, 10, "north", 2, "Coal"),
  })
  eq("filter by label", 1, #S.filter(rows, "iron"))
  eq("filter is case-insensitive", 1, #S.filter(rows, "IRON"))
  -- An operator may type the registry name instead of the display name.
  eq("filter by registry id too", 1, #S.filter(rows, "minecraft:coal"))
  eq("no match returns empty", 0, #S.filter(rows, "zzz"))
  eq("empty query returns everything", 2, #S.filter(rows, ""))
  eq("nil query returns everything", 2, #S.filter(rows, nil))
end

-- ── Formatting ──────────────────────────────────────────────────────
print("\n-- formatting --")
do
  eq("small counts print plainly", "999", S.fmtCount(999))
  eq("9999 still plain", "9999", S.fmtCount(9999))
  eq("10k abbreviates", "10.0k", S.fmtCount(10000))
  eq("millions abbreviate", "1.5M", S.fmtCount(1500000))
  eq("nil counts as zero", "0", S.fmtCount(nil))

  eq("under a stack shows the raw count", "30", S.fmtStacks(30, 64))
  eq("exact stacks show no remainder", "2s", S.fmtStacks(128, 64))
  eq("stacks plus remainder", "2s+2", S.fmtStacks(130, 64))
  eq("honours a non-64 max stack", "3s+1", S.fmtStacks(49, 16))
  eq("a zero max stack falls back to 64", "1s+1", S.fmtStacks(65, 0))
end

do
  local t = S.totals(S.applyWatches(
    S.aggregate({
      reading("a:a", 0, 100, "north"),
      reading("b:b", 0, 50, "east"),
    }),
    { ["missing:x#0"] = 10 }))
  eq("totals sum real items", 150, t.items)
  eq("...counting distinct kinds", 2, t.distinct)
  eq("...and occupied slots", 2, t.slots)
  -- The synthesized absent row must not inflate the totals.
  test("an absent watched item adds nothing to the totals", t.distinct == 2)
end

-- ── Watch persistence ───────────────────────────────────────────────
print("\n-- watch persistence --")
do
  local text = S.encodeWatches(
    { ["minecraft:coal#0"] = 100, ["minecraft:iron_ingot#0"] = 64 },
    { ["minecraft:coal#0"] = "Coal" })
  local w, l = S.decodeWatches(text)
  eq("round-trips the threshold", 100, w["minecraft:coal#0"])
  eq("round-trips the second entry", 64, w["minecraft:iron_ingot#0"])
  eq("round-trips the label", "Coal", l["minecraft:coal#0"])

  -- The file is hand-editable, so it must survive being hand-mangled.
  local w2 = S.decodeWatches("garbage\n\nminecraft:x#0\t50\tX\nbad\tNaN\ty\n")
  eq("junk lines are skipped", 50, w2["minecraft:x#0"])
  eq("...and contribute nothing else", nil, w2["bad"])
  eq("decoding nil yields an empty table", 0, (function()
    local n = 0; for _ in pairs(S.decodeWatches(nil)) do n = n + 1 end; return n
  end)())

  -- A key carrying a tab or newline would forge extra records on the way
  -- back in; it must not be written at all.
  local bad = S.encodeWatches({ ["evil\tkey"] = 5, ["also\nevil"] = 5 })
  eq("keys with separators are refused", "", bad)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***"); os.exit(1) end
