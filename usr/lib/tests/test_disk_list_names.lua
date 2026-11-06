-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `disk list` shows mount points whole         ║
-- ║                                                                ║
-- ║  A floppy mounts at "/mnt/" plus its label, and a label may    ║
-- ║  run to 32 characters (diskmount.sanitizeLabel). `disk list`   ║
-- ║  cut the mount point at 16, so a disk labelled "Optional       ║
-- ║  Utilities" listed as "/mnt/Optional Ut" -- not a directory    ║
-- ║  anyone could `cd` into. Found with ls doing the same to /etc  ║
-- ║  on the headless machine ("component_caps.cfg.examp").         ║
-- ║                                                                ║
-- ║  Runs the real extras.lua, both the kernel mount list and the  ║
-- ║  /mnt scan it falls back to.                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_disk_list_names.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1024 * 1024 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local LONG = "/mnt/Optional Utilities"   -- 23
local function machine(withMounts)
  local F = {
    exists = function(p) return p == "/mnt" end,
    list = function(p) if p == "/mnt" then return { "Optional Utilities/", "a/" } end return {} end,
    join = function(a, b) return (a:sub(-1) == "/" and a or a .. "/") .. b end,
    isDirectory = function() return true end,
  }
  if withMounts then
    F.mounts = function()
      return { { mountPoint = "/", label = "TOS" },
               { mountPoint = LONG, label = "Optional Utilities" },
               { mountPoint = "/mnt/a", label = "a" } }
    end
  end
  local S = {
    T = setmetatable({}, { __index = function(_, k) return k end }),
    F = F, K = {}, E = {}, P = {}, D = {}, st = "tok", W = 80, H = 25,
    U = { getSession = function() return { user = "root", tier = 3 } end },
  }
  local deps = setmetatable({ rp = function(p) return p end }, {
    __index = function() return function() return true end end })
  local C = {}
  assert(loadfile("tos/shell/panels/commands/extras.lua"))()(C, S, deps)
  local out = {}
  C.disk({ "list" }, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

local function aligned(text)
  -- every row's Status text starts in the column its heading starts in:
  -- a space just before it, something other than a space at it
  local col, rows, bad = nil, 0, {}
  for line in text:gmatch("[^\n]+") do
    if line:find("^ Mount ") then col = line:find("Status", 1, true)
    elseif col and line:find("^ /mnt/") then
      rows = rows + 1
      if line:sub(col - 1, col - 1) ~= " " or line:sub(col, col):find("%s") then
        bad[#bad + 1] = line
      end
    end
  end
  return col ~= nil and rows == 2 and #bad == 0, table.concat(bad, " | ")
end

print("=== from the kernel's mount list ===")
local listed = machine(true)
test("a 23-character mount point is listed whole", listed:find(LONG, 1, true) ~= nil, listed)
test("...and so is its label", listed:find("Optional Utilities ", 1, true) ~= nil
  and select(2, listed:gsub("Optional Utilities", "")) == 2, listed)
test("...and the Status column lines up", aligned(listed))

print("=== from the /mnt scan ===")
local scanned = machine(false)
test("a 23-character mount point is listed whole", scanned:find(LONG, 1, true) ~= nil, scanned)
test("...and the Status column lines up", aligned(scanned))

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
