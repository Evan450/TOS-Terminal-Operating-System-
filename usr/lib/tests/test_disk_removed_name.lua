-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a removed disk is named, not "Unnamed"       ║
-- ║                                                                ║
-- ║  Once a disk is gone its component cannot answer getLabel(),   ║
-- ║  so fs.mounts() reports "Unnamed" for it -- and the shell said ║
-- ║  `Disk removed: "Unnamed"` for a floppy it had announced as     ║
-- ║  "disk1" a moment before (headless machine, 2026-10-09). The   ║
-- ║  mount point was named from the label when it mounted, so the  ║
-- ║  shell names the disk from that.                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_disk_removed_name.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local helpers = require("shell.panels.helpers")

print("=== the name a removed disk is given ===")
print()
eq("a readable label is used", "Backups", helpers.diskName({ label = "Backups", mountPoint = "/mnt/Backups" }))
eq("an unreadable label falls back to the mount point",
  "disk1", helpers.diskName({ label = "Unnamed", mountPoint = "/mnt/disk1" }))
eq("...an unlabelled disk's mount names it by address",
  "disk_fdb1", helpers.diskName({ label = "Unnamed", mountPoint = "/mnt/disk_fdb1" }))
eq("no label field at all", "disk2", helpers.diskName({ mountPoint = "/mnt/disk2" }))
eq("a trailing slash is ignored", "disk3", helpers.diskName({ label = "", mountPoint = "/mnt/disk3/" }))
eq("nothing to go on", "disk", helpers.diskName({}))
eq("not even a table", "disk", helpers.diskName(nil))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
