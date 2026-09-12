-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `deploy <mount>` copies, it does not read the ║
-- ║  OS into memory a file at a time                                ║
-- ║                                                                ║
-- ║  Building an install disk read every OS file whole and wrote it ║
-- ║  back. The largest are 67-120 KB, and with the panels shell    ║
-- ║  running a 192 KB machine has less than that free (Sep 2026    ║
-- ║  pentest, RAM pass). It copies through F.copy now, which       ║
-- ║  streams 4 KB blocks. Drives the REAL C.deploy.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_deploy_mount_streams.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
                               freeMemory = function() return 1e6 end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

-- The running system, and the floppy it is deployed onto.
local BIG = string.rep("0123456789abcdef", 6000)          -- 96 KB, like core.lua
local FILES = {
  ["/init.lua"]            = "-- init\n",
  ["/tos/kernel/big.lua"]  = BIG,
  ["/bios.lua"]            = "-- bios\n",
  ["/install.lua"]         = "-- installer\n",
}
package.loaded["system_manifest"] = {
  { path = "/init.lua" }, { path = "/tos/kernel/big.lua" }, { path = "/tos/kernel/gone.lua" },
}
local DIRS = { ["/mnt/floppy"] = true }
local wholeReads, copies = 0, {}
local F = {
  normalize     = function(p) return (tostring(p):gsub("/+", "/")) end,
  exists        = function(p) return FILES[p] ~= nil or DIRS[p] == true end,
  isDirectory   = function(p) return DIRS[p] == true end,
  makeDirectory = function(p) DIRS[p] = true; return true end,
  spaceTotal    = function() return 2 * 1024 * 1024 end,
  spaceFree     = function() return 2 * 1024 * 1024 end,
  readFile      = function(p) if FILES[p] then wholeReads = wholeReads + 1 end; return FILES[p] end,
  writeFile     = function(p, c) FILES[p] = c; return true end,
  copy          = function(a, b)
    if not FILES[a] then return false, "no such file" end
    copies[#copies + 1] = a; FILES[b] = FILES[a]; return true
  end,
}

local okE, register = pcall(require, "shell.panels.commands.extras")
test("extras.lua loads", okE and type(register) == "function", register)
if not okE then print("*** TESTS FAILED ***"); os.exit(1) end
local S = {
  K = { uptime = function() return 0 end, getConfig = function() return nil end },
  E = { push = function() end }, P = {}, F = F, D = {}, U = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "y" end,
  dialog = function() return 1 end, confirm = function() return true end,
  confirmTyped = function() return true end,
}
local C = {}
local okR, rerr = pcall(register, C, S, deps)
test("extras.lua registers its commands", okR and type(C.deploy) == "function", rerr)
if not (okR and C.deploy) then print("*** TESTS FAILED ***"); os.exit(1) end

print()
print("=== deploy <mount> copies ===")
local out = {}
local ok, err = pcall(C.deploy, { "/mnt/floppy" }, function(t) out[#out + 1] = tostring(t) end)
local text = table.concat(out, "\n")
test("deploy returns cleanly and says the disk was made",
  ok and text:find("Install disk created", 1, true) ~= nil, text ~= "" and text or err)
test("the OS files, bios.lua and install.lua all arrive, intact",
  FILES["/mnt/floppy/tos/kernel/big.lua"] == BIG and FILES["/mnt/floppy/init.lua"] == "-- init\n"
  and FILES["/mnt/floppy/bios.lua"] == "-- bios\n" and FILES["/mnt/floppy/install.lua"] == "-- installer\n")
test("...every one through F.copy", #copies == 4, #copies .. " copies")
test("...and none of them was read whole into memory", wholeReads == 0, wholeReads .. " whole reads")
test("a manifest file the system lacks is skipped, not reported as a failure",
  text:find("FAIL", 1, true) == nil and FILES["/mnt/floppy/tos/kernel/gone.lua"] == nil)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
