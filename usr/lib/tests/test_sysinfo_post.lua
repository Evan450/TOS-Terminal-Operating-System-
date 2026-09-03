-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: sysinfo POST screen (roles + borders)    ║
-- ║                                                            ║
-- ║  Pins the honest storage roles (the operator's "my box     ║
-- ║  has two disks and a floppy, not RAM Disks" report):       ║
-- ║  tmpfs is named by its mount point, floppies get AMIBIOS   ║
-- ║  letters, data drives numbers. Also smoke-renders the      ║
-- ║  boxed (AMIBIOS-style) wide layout on a fake cell buffer.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sysinfo_post.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- sysinfo requires component/computer at load; stub them.
package.loaded["component"] = {
  list = function() return function() end end,
  proxy = function() return nil end,
}
package.loaded["computer"] = {
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1820 * 1024 end,
  uptime = function() return 0 end,
  tmpAddress = function() return "tmp-addr" end,
}
package.path = "tos/?.lua;" .. package.path
local sysinfo = require("kernel.sysinfo")

print("=== sysinfo POST Tests ===")
print()

-- ── diskRole: the operator's exact machine ─────────────────────────
-- Boot HDD, one data HDD, the Optional Utilities floppy (512KB), and
-- OC's built-in tmpfs. NOTHING may be called "RAM Disk" anymore.
local state = {}
eq("boot drive", "Boot Drive",
  sysinfo.diskRole({ label = "OpenOS", totalKB = 4096, tier = "T3" }, true, state))
eq("data drive numbered", "Data Drive 1",
  sysinfo.diskRole({ label = "", totalKB = 2048, tier = "T2" }, false, state))
eq("512KB floppy is Floppy A (not RAM Disk)", "Floppy A",
  sysinfo.diskRole({ label = "bff0a073", totalKB = 512, tier = "Floppy" }, false, state))
eq("tmpfs named by its mount point", "Temp /tmp",
  sysinfo.diskRole({ label = "tmpfs", totalKB = 64, tier = "RAM", tmpfs = true }, false, state))
eq("second floppy is Floppy B", "Floppy B",
  sysinfo.diskRole({ label = "", totalKB = 512, tier = "Floppy" }, false, state))
eq("second data drive numbered 2", "Data Drive 2",
  sysinfo.diskRole({ label = "", totalKB = 4096, tier = "T3" }, false, state))
-- tmpfs flag wins even when a label is missing.
eq("tmpfs flag alone is enough", "Temp /tmp",
  sysinfo.diskRole({ label = "", totalKB = 64, tmpfs = true }, false, {}))

-- ── render: boxed wide layout on a fake 80x25 buffer ───────────────
local Wd, Hd = 80, 25
local buf = {}
for y = 1, Hd do buf[y] = {} for x = 1, Wd do buf[y][x] = " " end end
local ctx = {
  W = Wd, H = Hd,
  set = function(x, y, t)
    if type(t) ~= "string" or y < 1 or y > Hd then return end
    local cc = 0
    for _, code in utf8.codes(t) do
      cc = cc + 1
      local c = x + cc - 1
      if c >= 1 and c <= Wd then buf[y][c] = utf8.char(code) end
    end
  end,
  color = function() return 0xFFFFFF end,
  title = "Strata Systems LLC - System Configuration",
}
local inv = {
  cpu = { arch = "Lua 5.3", tier = 3, tierSource = "override" },
  memory = { totalKB = 2048, freeKB = 1820, tier = "T2+", modules = 0 },
  gpu = { count = 1, tier = 2, depth = 4, maxW = 80, maxH = 25 },
  screen = { count = 1, tier = 2 },
  eeprom = { label = "Lua BIOS", bootAddr = "b174c1d3" },
  modems = { { wireless = true, strength = 400 } },
  other = {},
  disks = {
    { addr = "b174c1d3", label = "OpenOS", usedKB = 1285, totalKB = 4096, tier = "T3" },
    { addr = "e1344d2b", label = "", usedKB = 0, totalKB = 2048, tier = "T2" },
    { addr = "bff0a073", label = "bff0a073", usedKB = 370, totalKB = 512, tier = "Floppy" },
    { addr = "tmp-addr", label = "tmpfs", usedKB = 0, totalKB = 64, tier = "RAM", tmpfs = true },
  },
}
local ok, yAfter = pcall(sysinfo.render, inv, ctx)
test("render: wide layout draws without error", ok)
local function row(y) return table.concat(buf[y]) end
local function anywhere(s)
  for y = 1, Hd do if row(y):find(s, 1, true) then return true end end
  return false
end
test("render: double-line top border", row(1):find("╔", 1, true) ~= nil
  and row(1):find("╗", 1, true) ~= nil)
test("render: title rides the top border as a tab", row(1):find("╡ Strata", 1, true) ~= nil)
test("render: Storage section divider tab", anywhere("╡ Storage ╞"))
test("render: side walls present", anywhere("║"))
test("render: bottom border", anywhere("╚"))
test("render: column divider through the grid", row(3):find("│", 1, true) ~= nil)
test("render: floppy row honest", anywhere("Floppy A"))
test("render: tmpfs row honest", anywhere("Temp /tmp"))
test("render: no 'RAM Disk' anywhere", not anywhere("RAM Disk"))
test("render: boot drive first + marked", anywhere("Boot Drive"))
test("render: returns a sane next-y", type(yAfter) == "number" and yAfter <= Hd + 1)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
