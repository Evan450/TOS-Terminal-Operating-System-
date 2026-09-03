-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: removable-disk classification        ║
-- ║  helpers.classifyDisk identifies inserted media so the ║
-- ║  shell can guide the operator to the right next step.  ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_disk_classify.lua

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

-- helpers.lua requires "computer" at load time; stub it (classifyDisk
-- itself never calls it).
package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local helpers = require("shell.panels.helpers")

-- Build a mock kernel-fs proxy from a set of present paths + a top-level
-- directory listing (dirs carry a trailing "/").
local function makeF(present, listing)
  local set = {}
  for _, p in ipairs(present) do set[p] = true end
  return {
    join = function(a, b)
      if a:sub(-1) == "/" then a = a:sub(1, -2) end
      return a .. "/" .. b
    end,
    exists = function(p) return set[p] == true end,
    list = function() return listing end,
  }
end

local MNT = "/mnt/d"

local function kindOf(present, listing)
  local F = makeF(present, listing)
  return helpers.classifyDisk(F, MNT).kind
end

print("=== Disk classification tests ===")
print()

-- A whole-OS install image (deploy output): carries the kernel AND a root
-- install.lua. Must classify as tos-install (the install.lua must NOT win).
test("TOS install disk", "tos-install", kindOf(
  { MNT .. "/tos/kernel/init.lua", MNT .. "/install.lua", MNT .. "/bios.lua" },
  { "tos/", "install.lua", "bios.lua" }))

-- Optional Utilities disk: the SET MANIFEST + one pkg dir per add-on. The
-- marker used to be a copy of the picker (install.lua); the picker moved into
-- the base image, and optutil-set.lua is the better marker anyway — it is
-- what makes the disk a SET rather than a loose pile of packages.
test("Optional Utilities disk", "optional-utilities", kindOf(
  { MNT .. "/optutil-set.lua", MNT .. "/tetris/package.lua", MNT .. "/mouse/package.lua" },
  { "optutil-set.lua", "tetris/", "mouse/" }))

-- A repo disk WITHOUT the picker still resolves as a package repo.
test("Package repo (no picker)", "package-repo", kindOf(
  { MNT .. "/tetris/package.lua" },
  { "tetris/" }))

-- Single-package disk: a bare manifest at the root.
test("Single-package disk", "package", kindOf(
  { MNT .. "/package.lua", MNT .. "/usr/modules/x/init.lua" },
  { "package.lua", "usr/" }))

-- Legacy module disk.
test("Legacy module disk", "module", kindOf(
  { MNT .. "/module.cfg" },
  { "module.cfg" }))

-- Plain data / blank disk.
test("Data disk", "data", kindOf(
  { MNT .. "/notes.txt" },
  { "notes.txt" }))

-- A set manifest with NO package dirs beside it is NOT an Optional
-- Utilities disk (it's just a script on a data disk).
test("Lone set manifest is data", "data", kindOf(
  { MNT .. "/optutil-set.lua" },
  { "optutil-set.lua" }))

-- NESTED layout: the whole dist/optional-utilities FOLDER was copied onto the
-- disk (a very easy mistake), so the packages live one level down. Must still
-- be detected instead of reading as a blank data disk. Needs a per-directory
-- fake fs (the simple makeF returns one listing for every path).
do
  local present = {
    [MNT .. "/optional-utilities/install.lua"] = true,
    [MNT .. "/optional-utilities/mouse/package.lua"] = true,
    [MNT .. "/optional-utilities/tetris/package.lua"] = true,
    [MNT .. "/optional-utilities/optutil-set.lua"] = true,
  }
  local listings = {
    [MNT] = { "optional-utilities/" },
    [MNT .. "/optional-utilities"] = { "optutil-set.lua", "mouse/", "tetris/" },
  }
  local F = {
    join = function(a, b) if a:sub(-1) == "/" then a = a:sub(1, -2) end return a .. "/" .. b end,
    exists = function(p) return present[p] == true end,
    list = function(p) p = p:gsub("/$", ""); return listings[p] or {} end,
  }
  local r = helpers.classifyDisk(F, MNT)
  test("Nested Optional Utilities detected", "optional-utilities", r.kind)
  -- The hint recommends the panels-native installer (`pkg install`, which
  -- with no argument scans mounted media), NOT "run …/install.lua": that
  -- picker is line-driven and can't read input in the panels TUI, so
  -- pointing operators at it was a dead end. (v1.4.0 unified the old
  -- `pkg from-floppy` into `pkg install`.)
  test("Nested hint recommends pkg install", "pkg install", r.hint)
end

-- A hint is offered for actionable disks, withheld for plain data.
local F = makeF({ MNT .. "/optutil-set.lua", MNT .. "/tetris/package.lua" },
                { "optutil-set.lua", "tetris/" })
test("Optional Utilities offers a hint", true,
  helpers.classifyDisk(F, MNT).hint ~= nil)
test("Data disk offers no hint", true,
  helpers.classifyDisk(makeF({}, { "x.txt" }), MNT).hint == nil)

-- scanMountedMedia: surfaces the first actionable mounted disk at startup
-- (the boot-time disk the insert auto-detect never sees).
do
  local present = { [MNT .. "/optutil-set.lua"] = true, [MNT .. "/mouse/package.lua"] = true }
  local listings = { [MNT] = { "optutil-set.lua", "mouse/" } }
  local F = {
    join = function(a, b) if a:sub(-1) == "/" then a = a:sub(1, -2) end return a .. "/" .. b end,
    exists = function(p) return present[p] == true end,
    list = function(p) p = p:gsub("/$", ""); return listings[p] or {} end,
    mounts = function() return { { mountPoint = "/" }, { mountPoint = MNT, label = "util" } } end,
  }
  local media = helpers.scanMountedMedia(F)
  test("scan finds the actionable disk", "optional-utilities", media and media.kind)
  test("scan carries the mount point", MNT, media and media.mountPoint)

  -- A box with only the boot fs and a blank data disk surfaces nothing.
  local F2 = {
    join = F.join, exists = function() return false end, list = function() return {} end,
    mounts = function() return { { mountPoint = "/" }, { mountPoint = "/mnt/data" } } end,
  }
  test("scan ignores data-only media", nil, helpers.scanMountedMedia(F2))
  -- No mounts() accessor at all -> nil, no error.
  test("scan tolerates fs without mounts()", nil, helpers.scanMountedMedia({ join = F.join }))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
