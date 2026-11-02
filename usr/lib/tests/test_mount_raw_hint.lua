-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a raw drive in use is not an unused one      ║
-- ║                                                                ║
-- ║  `mount` and `disk` count raw drives to tell an operator that  ║
-- ║  one "holds no filesystem yet". They counted every drive, so   ║
-- ║  it said that of a TBFS volume mounted at /mnt/raw, and of     ║
-- ║  the drive the machine had booted from and was running on,     ║
-- ║  beside the advice to format it. Seen on a booted machine.     ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mount_raw_hint.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local DRIVES = {}
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1024 * 1024 end,
}
package.loaded["component"] = {
  list = function(kind, exact)
    local i = 0
    return function()
      if kind ~= "drive" or not exact then return nil end
      i = i + 1
      return DRIVES[i]
    end
  end,
  proxy = function() return nil end,
}

local function mountSays(drives, mounts)
  DRIVES = drives
  local S = {
    T = setmetatable({}, { __index = function(_, k) return k end }),
    F = { mounts = function() return mounts end },
    K = {},
  }
  local deps = {
    rp = function(p) return p end,
    rootOnly = function() return true end, adminOnly = function() return true end,
    promptInput = function() return nil end,
    confirm = function() return false end, confirmTyped = function() return false end,
  }
  local C = {}
  assert(loadfile("tos/shell/panels/commands/admin.lua"))()(C, S, deps)
  local out = {}
  C.mount({}, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

local ROOT = { mountPoint = "/", label = "disk", address = "root-disk", total = 1, used = 1 }

print("=== mount ===")
print()
test("a drive with nothing on it gets the hint",
  mountSays({ "drive-a" }, { ROOT }):find("1 unmanaged (raw) drive(s)", 1, true) ~= nil)
test("no drive, no hint", not mountSays({}, { ROOT }):find("unmanaged", 1, true))
do
  local vol = { mountPoint = "/mnt/raw", label = "mydata", address = "drive-a", total = 1, used = 1 }
  test("one mounted as TBFS gets none", not mountSays({ "drive-a" }, { ROOT, vol }):find("unmanaged", 1, true))
  local rootTbfs = { mountPoint = "/", label = "tos", address = "drive-a", total = 1, used = 1 }
  test("nor the one the machine is running on",
    not mountSays({ "drive-a" }, { rootTbfs }):find("unmanaged", 1, true))
  test("only the unused one of two is counted",
    mountSays({ "drive-a", "drive-b" }, { ROOT, vol }):find("1 unmanaged (raw) drive(s)", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
