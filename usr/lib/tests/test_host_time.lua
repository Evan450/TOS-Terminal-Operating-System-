-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `date` tells the real time                   ║
-- ║                                                                ║
-- ║  The manual said `date` bypassed OC's in-game clock. It did    ║
-- ║  not: on a machine it printed 1970-01-01 07:18:36, and two     ║
-- ║  calls 1.7 real seconds apart differed by 122, while `ls -l`   ║
-- ║  on the same machine said 2026. A file's modification stamp is ║
-- ║  the one real clock OC lets out, so fs.hostTime reads that.    ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_host_time.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 4e6 end,
  totalMemory = function() return 8e6 end, beep = function() end, pullSignal = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end }

local h = assert(io.open("tos/kernel/fs.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local body = src:match("(function fs%.hostTime%(%).-\nend\n)")
test("found fs.hostTime", body ~= nil)

local stamp, wrote, removed, hasTmp
local fs = {
  exists = function(p) return p == "/tmp" and hasTmp end,
  writeFile = function(p) wrote = p; return true end,
  lastModified = function() return stamp end,
  remove = function(p) removed = p end,
}
local hostTime = assert(load("local fs = ...\n" .. body .. "\nreturn fs.hostTime", "=hostTime", "t", _G))(fs)

print("=== fs.hostTime ===")
print()
hasTmp, stamp = true, 1793548800123
test("milliseconds become whole seconds", hostTime() == 1793548800, hostTime())
test("it writes on the RAM disk, so no drive pays", wrote == "/tmp/.host-time", wrote)
test("and leaves nothing behind", removed == wrote)
stamp = 0
test("a filesystem with no clock is no answer", hostTime() == nil)
stamp = 25000000
test("nor is a small number passing for a date", hostTime() == nil)
hasTmp = false
test("nor is a machine with no /tmp", hostTime() == nil)

print()
print("=== who uses it ===")
print()
local function read(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("a"):gsub("\r\n", "\n"); f:close()
  return s
end
local core = read("tos/shell/panels/commands/core.lua")
test("`date` asks it first", core:find("(real or os.time())", 1, true) ~= nil)
local backup = read("tos/kernel/backup.lua")
test("a backup stamps the real time", backup:find("fs.hostTime and fs.hostTime()", 1, true) ~= nil)
local cron = read("tos/kernel/cron.lua")
test("a cron job has io, as `run` does", cron:find('["compat.io"] = true', 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
