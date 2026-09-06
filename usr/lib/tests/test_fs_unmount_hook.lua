-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: fs.unmount tells the proxy                  ║
-- ║                                                                ║
-- ║  A TBFS volume marks itself dirty at mount and clean when its  ║
-- ║  proxy's unmount() runs. kernel.fs.unmount dropped the table   ║
-- ║  entry and never called it, so `umount` left every TBFS disk  ║
-- ║  flagged "not cleanly unmounted" forever and fsck reported it  ║
-- ║  as a finding every time. Managed OC filesystems have no such  ║
-- ║  method, and must keep working exactly as before.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fs_unmount_hook.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_fs_unmount_hook.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- Minimal boot filesystem so kernel.fs can initialise.
local function fakeManaged()
  return {
    address = "managed-1", getLabel = function() return "m" end,
    spaceTotal = function() return 1 end, spaceUsed = function() return 0 end,
    exists = function() return false end, isDirectory = function() return true end,
    list = function() return {} end, makeDirectory = function() return true end,
  }
end
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, invoke = function() return nil end,
}
package.loaded["computer"] = { uptime = function() return 0 end, getBootAddress = function() return "managed-1" end }

local fs = require("kernel.fs")
if fs.init then pcall(fs.init, fakeManaged()) end

print("=== fs.unmount -> proxy.unmount Tests ===")
print()

do
  local told = 0
  local tbfsLike = fakeManaged()
  tbfsLike.address = "drive-1"
  tbfsLike.unmount = function() told = told + 1 end
  test("mount accepts the proxy", fs.mount("/mnt/t", tbfsLike) ~= false)
  test("unmount succeeds", fs.unmount("/mnt/t") == true)
  test("...and the proxy was told exactly once", told == 1)
  test("the mount is gone", (function()
    for _, m in ipairs(fs.mounts()) do if m.mountPoint == "/mnt/t" then return false end end
    return true
  end)())
end

do
  local plain = fakeManaged(); plain.address = "managed-2"   -- no unmount method
  fs.mount("/mnt/p", plain)
  local ok, res = pcall(fs.unmount, "/mnt/p")
  test("a proxy without unmount() is unmounted without error", ok and res == true)
end

do
  local angry = fakeManaged(); angry.address = "drive-2"
  angry.unmount = function() error("drive vanished") end
  fs.mount("/mnt/a", angry)
  local ok, res = pcall(fs.unmount, "/mnt/a")
  test("a proxy whose unmount() throws still unmounts cleanly", ok and res == true)
end

test("root cannot be unmounted", fs.unmount("/") == false)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
