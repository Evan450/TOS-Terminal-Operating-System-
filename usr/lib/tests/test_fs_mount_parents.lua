-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a mount point's parents are directories     ║
-- ║                                                                ║
-- ║  TOS mounts a disk at /mnt/<label> without creating /mnt on    ║
-- ║  the boot disk, so /mnt was invisible: `ls /mnt` said "no such ║
-- ║  file" with two floppies mounted under it (headless machine,   ║
-- ║  2026-10-09). kernel.fs now answers exists/isDirectory/list    ║
-- ║  for every proper ancestor of a mount point, merged with what  ║
-- ║  the disk below really holds.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fs_mount_parents.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_fs_mount_parents.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- A disk as a set of paths: directories end in "/".
local function fakeDisk(address, paths)
  local set = {}
  for _, p in ipairs(paths) do set[p] = true end
  local function isDir(p) return p == "/" or set[p .. "/"] == true end
  return {
    address = address, getLabel = function() return address end,
    spaceTotal = function() return 1 end, spaceUsed = function() return 0 end,
    exists = function(p) return isDir(p) or set[p] == true end,
    isDirectory = function(p) return isDir(p) end,
    list = function(p)
      if not isDir(p) then return nil, "no such file" end
      local prefix = p == "/" and "/" or p .. "/"
      local out, seen = {}, {}
      for q in pairs(set) do
        if q:sub(1, #prefix) == prefix and #q > #prefix then
          local rest = q:sub(#prefix + 1)
          local name = rest:match("^[^/]+/?")
          if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
        end
      end
      table.sort(out)
      return out
    end,
    makeDirectory = function() return true end,
  }
end
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, invoke = function() return nil end,
}
package.loaded["computer"] = { uptime = function() return 0 end, getBootAddress = function() return "boot" end }

local fs = require("kernel.fs")
-- A boot disk with NO /mnt, and a /home holding a real directory.
fs.init(fakeDisk("boot", { "/etc/", "/home/", "/home/alice/", "/init.lua" }))

local function has(list, name)
  for _, n in ipairs(list or {}) do if n == name then return true end end
  return false
end

print("=== mount points' parents ===")
print()

test("before any mount, /mnt does not exist", not fs.exists("/mnt"))
test("...and lists nothing", #fs.list("/mnt") == 0)

fs.mount("/mnt/disk1", fakeDisk("d1", { "/calc/", "/calc/package.lua" }))
fs.mount("/mnt/disk2", fakeDisk("d2", { "/snake/" }))

test("with disks mounted under it, /mnt exists", fs.exists("/mnt") == true)
test("...and is a directory", fs.isDirectory("/mnt") == true)
local mnt = fs.list("/mnt")
test("ls /mnt lists both mounts", has(mnt, "disk1/") and has(mnt, "disk2/") and #mnt == 2)
test("...sorted", mnt[1] == "disk1/" and mnt[2] == "disk2/")
test("/ lists mnt/ beside what the disk holds",
  has(fs.list("/"), "mnt/") and has(fs.list("/"), "etc/") and has(fs.list("/"), "init.lua"))
test("a mount still lists its own contents", has(fs.list("/mnt/disk1"), "calc/"))
test("a name that only shares a prefix is not a parent", not fs.exists("/mn"))
test("a file on the disk below is still a file", fs.exists("/init.lua") and not fs.isDirectory("/init.lua"))

-- A real directory that also has a mount under it: merged, never doubled.
fs.mount("/home/alice", fakeDisk("ha", { "/notes.txt" }))
fs.mount("/home/bob", fakeDisk("hb", {}))
local home = fs.list("/home")
test("a real directory keeps its entries and gains the mount", has(home, "alice/") and has(home, "bob/"))
test("...without listing a name twice", #home == 2)

-- Deeper mounts make every ancestor a directory, one level at a time.
fs.mount("/media/usb/a", fakeDisk("ua", {}))
test("/media exists for a mount two levels down", fs.isDirectory("/media"))
test("...and lists only the next segment", has(fs.list("/media"), "usb/") and #fs.list("/media") == 1)
test("/media/usb lists a/", has(fs.list("/media/usb"), "a/"))

-- Unmounting takes the virtual directory away again.
fs.unmount("/mnt/disk1")
fs.unmount("/mnt/disk2")
test("after the last unmount /mnt is gone", not fs.exists("/mnt") and #fs.list("/mnt") == 0)
test("...and / no longer lists it", not has(fs.list("/"), "mnt/"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
