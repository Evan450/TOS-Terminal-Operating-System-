-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: sysinfo.render (AMIBIOS POST screen)     ║
-- ║                                                            ║
-- ║  Renders into a text buffer and asserts the AMI-style      ║
-- ║  layout: two-column key/value grid, pseudo drive names,    ║
-- ║  and the retro footer. Guards the boot config screen.      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sysinfo_render.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, invoke = function() end }
package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;" .. package.path
local si = require("kernel.sysinfo")

local W, H = 80, 25
local buf = {}
for y = 1, H do buf[y] = {} for x = 1, W do buf[y][x] = " " end end
-- One cell per CHARACTER (not byte), like a real OC Unicode GPU — the
-- boxed layout's ║/│/═ frame chars are 3 bytes but ONE column.
local function set(x, y, t)
  if type(t) ~= "string" or y < 1 or y > H then return end
  local i = 0
  for _, code in utf8.codes(t) do
    i = i + 1
    local c = x + i - 1
    if c >= 1 and c <= W then buf[y][c] = utf8.char(code) end
  end
end
local function rowStr(y) return table.concat(buf[y]) end
local function screenHas(s)
  for y = 1, H do if rowStr(y):find(s, 1, true) then return true end end
  return false
end

local inv = {
  cpu = { arch = "Lua 5.3", tier = 3, tierSource = "detected", count = 1 },
  memory = { totalKB = 2048, freeKB = 1926, tier = "T2+", modules = 2 },
  gpu = { count = 1, tier = 2, depth = 4, maxW = 80, maxH = 25 },
  screen = { count = 1, tier = 2 },
  disks = {
    { addr = "b174c1d3", label = "OpenOS", usedKB = 957, totalKB = 4096, tier = "T3" },
    { addr = "e1344d2b", label = "",       usedKB = 0,   totalKB = 2048, tier = "T2" },
    { addr = "8ce0575a", label = "tmpfs",  usedKB = 0,   totalKB = 64,   tier = "Floppy" },
  },
  modems = { { addr = "0e1d6a0a", wireless = true, strength = 400 } },
  dataCard = { present = true, tier = 2, name = "data card", tierSource = "override" },
  tunnel = { present = false }, other = {},
  eeprom = { addr = "b174c1d3", label = "Lua BIOS", bootAddr = "b174c1d3" },
}

print("=== sysinfo.render (AMIBIOS) Tests ===")
print()

local after = si.render(inv, { W = W, H = H, set = set, title = "Acme - System Configuration" })
test("returns a positive next-row", type(after) == "number" and after > 1)
test("title line drawn", screenHas("Acme - System Configuration"))
-- Honest grid: real component names, no invented PC-BIOS facts.
test("Processor label", screenHas("Processor"))
test("no fake Numeric Processor", not screenHas("Numeric"))
test("no fake Base Memory split", not screenHas("Base Memory"))
test("real Total Memory", screenHas("Total Memory"))
test("real Free Memory", screenHas("Free Memory"))
test("honest RAM module count", screenHas("RAM Modules"))
test("module count value 2", screenHas("RAM Modules") and screenHas(" 2"))
test("Data Card named as such", screenHas("Data Card"))
test("data card tier", screenHas("Tier 2"))
test("graphics value", screenHas("GPU T2 / 4-bit"))
test("boot id from addr", screenHas("b174c1d3"))
test("storage header", screenHas("Storage"))
test("boot disk role = Boot Drive", screenHas("Boot Drive"))
test("no pseudo IDE names", not screenHas("Primary Master"))
test("data disk role = Data Drive", screenHas("Data Drive"))
-- v1.4.0: honest roles — tmpfs is named by its mount point, never
-- "RAM Disk" (which also mislabeled real floppies).
test("tmpfs role = Temp /tmp", screenHas("Temp /tmp"))
test("nothing is called RAM Disk", not screenHas("RAM Disk"))
test("footer honest memory", screenHas("Memory 1926/2048KB free"))

-- An empty/degraded box must not crash and still draws a frame + title.
local after2 = si.render({}, { W = 80, H = 25, set = function() end })
test("degraded inv renders without crashing", type(after2) == "number")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
