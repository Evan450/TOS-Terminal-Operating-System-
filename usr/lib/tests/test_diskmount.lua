-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the kernel mounts every disk, hot-plugged    ║
-- ║  ones included                                                 ║
-- ║                                                                ║
-- ║  A disk inserted after boot was mounted by the panels shell's  ║
-- ║  event loop and nothing else, so while the package picker held ║
-- ║  the seat the floppy its own "Insert disk 1" modal asked for   ║
-- ║  was never mounted (headless machine, 2026-10-09), and the CLI ║
-- ║  shell never mounted one at all. kernel.diskmount now does it, ║
-- ║  from the kernel's own component_added listener, by the one    ║
-- ║  rule boot uses.                                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_diskmount.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")",
    expected == actual)
end

local here = (arg and arg[0]) or "usr/lib/tests/test_diskmount.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- Component methods are CALLABLE TABLES on OpenComputers, not functions
-- (test_component_callable.lua). The first version of this module tested
-- type(getLabel) == "function", passed a stub of plain functions, and on
-- the headless machine mounted every labelled floppy as /mnt/disk_<stub>.
local function method(f) return setmetatable({}, { __call = function(_, ...) return f(...) end }) end

local function fakeDisk(address, label, paths)
  local set = {}
  for _, p in ipairs(paths or {}) do set[p] = true end
  local function isDir(p) return p == "/" or set[p .. "/"] == true end
  return {
    address = address,
    getLabel = method(function() return label end),
    spaceTotal = function() return 1 end, spaceUsed = function() return 0 end,
    exists = function(p) return isDir(p) or set[p] == true end,
    isDirectory = function(p) return isDir(p) end,
    list = function(p)
      if not isDir(p) then return nil end
      local prefix = p == "/" and "/" or p .. "/"
      local out, seen = {}, {}
      for q in pairs(set) do
        if q:sub(1, #prefix) == prefix and #q > #prefix then
          local name = q:sub(#prefix + 1):match("^[^/]+/?")
          if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
        end
      end
      return out
    end,
    makeDirectory = function() return true end,
  }
end
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, invoke = function() return nil end,
}
package.loaded["computer"] = { uptime = function() return 0 end }

local fs = require("kernel.fs")
-- The boot disk carries an EMPTY /mnt/old (the shell's old hot-plug mount
-- created and abandoned these) and a /mnt/full with something in it.
fs.init(fakeDisk("boot-0000", "TOS", { "/mnt/", "/mnt/old/", "/mnt/full/", "/mnt/full/x.txt" }))
local dm = require("kernel.diskmount")

local function mountedAt(path)
  for _, m in ipairs(fs.mounts()) do if m.mountPoint == path then return m.address end end
end

print("=== kernel.diskmount ===")
print()

print("-- the boot-disk gate (#SEC H26) --")
dm.init({ fs = fs, bootAddr = nil })
local mp, why = dm.mount("aaaa1111", fakeDisk("aaaa1111", "x"))
test("with no known boot address nothing is mounted", mp == nil and why ~= nil)
dm.init({ fs = fs, bootAddr = "boot-0000" })
test("the boot disk is never mounted under /mnt", dm.mount("boot-0000", fakeDisk("boot-0000", "TOS")) == nil)

print("-- names --")
local d1 = fakeDisk("fdb122ed", "disk1")
local mp1, l1 = dm.mount("fdb122ed", d1)
eq("a labelled disk mounts at /mnt/<label>", "/mnt/disk1", mp1)
eq("...and reports its label", "disk1", l1)
test("...in the kernel's mount table", mountedAt("/mnt/disk1") == "fdb122ed")
eq("mounting it again answers where it already is", "/mnt/disk1", (dm.mount("fdb122ed", d1)))
local n = 0
for _, m in ipairs(fs.mounts()) do if m.address == "fdb122ed" then n = n + 1 end end
eq("...without a second mount", 1, n)

eq("a second disk with the same label gets its address stub", "/mnt/disk1_d106",
  (dm.mount("d10624da", fakeDisk("d10624da", "disk1"))))
eq("an unlabelled disk is named by its address", "/mnt/disk_9abc",
  (dm.mount("9abc0000", fakeDisk("9abc0000", nil))))
eq("a label that tries to climb out is flattened", "/mnt/___etc",
  (dm.mount("e7c00000", fakeDisk("e7c00000", "../etc"))))
eq("an empty directory left on the boot disk is reused", "/mnt/old",
  (dm.mount("01d00000", fakeDisk("01d00000", "old"))))
eq("a directory with something in it is not mounted over", "/mnt/full_f011",
  (dm.mount("f0110000", fakeDisk("f0110000", "full"))))
eq("mountPointOf knows each one", "/mnt/disk1", (dm.mountPointOf("fdb122ed")))

print("-- the label rule --")
eq("nil label", "disk_abcd", dm.sanitizeLabel(nil, "abcdef"))
eq("a dot is flattened like any other byte", "_", dm.sanitizeLabel(".", "abcdef"))
eq("spaces collapse and trim", "My Disk", dm.sanitizeLabel("  My   Disk ", "abcdef"))
eq("32 characters at most", 32, #dm.sanitizeLabel(string.rep("a", 40), "abcdef"))

print("-- removal --")
local rmp, rl = dm.unmount("fdb122ed")
eq("unmount says where the disk was", "/mnt/disk1", rmp)
eq("...and its label", "disk1", rl)
test("...and it is out of the mount table", mountedAt("/mnt/disk1") == nil)
test("a second unmount has nothing to say", dm.unmount("fdb122ed") == nil)
eq("re-inserted, it gets its name back", "/mnt/disk1", (dm.mount("fdb122ed", d1)))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
