-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a disk's arrival is announced over old output ║
-- ║                                                                ║
-- ║  The shell draws a multi-line result (S.outLines) in preference ║
-- ║  to the one-line S.lastOut, and the disk announcements set only ║
-- ║  lastOut. So after `pkg make-disk` (three lines of output),     ║
-- ║  ejecting the disk and putting it back said nothing at all      ║
-- ║  (headless machine, 2026-10-09). helpers.announceDisk clears    ║
-- ║  the old block and classifies the disk -- a make-disk floppy is ║
-- ║  still an "Optional Utilities disk", told to run `pkg install`. ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_disk_announce.lua   (from TOS-Dev)

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

-- What `pkg make-disk /mnt/blank calc` leaves: the set manifest and one
-- package directory.
local files = {
  ["/mnt/blank/optutil-set.lua"] = true,
  ["/mnt/blank/calc/package.lua"] = true,
}
local F = {
  join = function(a, b) return (a:gsub("/$", "")) .. "/" .. b end,
  exists = function(p) return files[p] == true or p == "/mnt/blank/calc" end,
  list = function(p)
    if p == "/mnt/blank" then return { "calc/", "optutil-set.lua" } end
    if p == "/mnt/blank/calc" then return { "package.lua", "usr/" } end
    return {}
  end,
}
local T = { highlight = "HL", dim = "DIM" }

print("=== disk announcements ===")
print()

local S = { T = T, outLines = { { "Built add-on disk on /mnt/blank: 1 package(s)" }, { "  calc" },
                               { "On the target machine, insert the disk and run 'pkg install'." } } }
eq("an insert is announced", true, helpers.announceDisk(S, F, "added", "/mnt/blank", "blank"))
eq("...clearing the result that would have hidden it", nil, S.outLines)
eq("...as an Optional Utilities disk with its next step",
  'Optional Utilities disk: "blank" -> /mnt/blank   pkg install', S.lastOut and S.lastOut[1])
eq("...highlighted", "HL", S.lastOut and S.lastOut[2])

S.outLines = { { "something" }, { "else" } }
eq("a removal is announced", true, helpers.announceDisk(S, F, "removed", "/mnt/blank", "blank"))
eq("...clearing the block too", nil, S.outLines)
eq("...by name", 'Disk removed: "blank"', S.lastOut and S.lastOut[1])
eq("...dimly", "DIM", S.lastOut and S.lastOut[2])

eq("an unlabelled removal is named from its mount point", 'Disk removed: "disk_4c27"',
  (helpers.announceDisk(S, F, "removed", "/mnt/disk_4c27", nil) and S.lastOut[1]))

S.outLines = { { "kept" } }
eq("no mount point, no announcement", false, helpers.announceDisk(S, F, "added", nil, "x"))
eq("...and the output is left alone", "kept", S.outLines and S.outLines[1][1])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
