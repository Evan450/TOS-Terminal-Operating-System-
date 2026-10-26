-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `deploy <mount>` refuses a disk TOS won't fit║
-- ║                                                                ║
-- ║  `deploy <mount>` offered "e.g. deploy /mnt/floppy", and its    ║
-- ║  refusal named /mnt/floppy too. A floppy is 512 KB and the     ║
-- ║  release is ~1.35 MB on a managed disk. The free-space line    ║
-- ║  was "best-effort" -- printed, never compared -- so the copy   ║
-- ║  ran until the disk filled and printed a FAIL per file that    ║
-- ║  did not make it (AUDIT 1). `deploy drive` has had a real fit  ║
-- ║  check since 2026-09; the mount path now prices the copy the   ║
-- ║  way install.lua's spaceNeeded does (each file's bytes, less   ║
-- ║  what a file already there takes, plus 512 B of fileCost per   ║
-- ║  new file and directory) and refuses before writing anything.  ║
-- ║  Drives the REAL C.deploy.                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_deploy_mount_fits.lua   (from TOS-Dev)

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

local KB = 1024
local FILES, DIRS, FREE, copies
local function reset(free)
  FILES = {
    ["/init.lua"]           = string.rep("i", 10 * KB),
    ["/tos/kernel/a.lua"]   = string.rep("a", 300 * KB),
    ["/tos/kernel/b.lua"]   = string.rep("b", 300 * KB),
    ["/bios.lua"]           = string.rep("x", 3 * KB),
    ["/install.lua"]        = string.rep("y", 20 * KB),
  }
  DIRS = { ["/mnt/disk"] = true }
  FREE, copies = free, 0
end
package.loaded["system_manifest"] = {
  { path = "/init.lua" }, { path = "/tos/kernel/a.lua" }, { path = "/tos/kernel/b.lua" },
}
local F = {
  normalize     = function(p) return (tostring(p):gsub("/+", "/")) end,
  exists        = function(p) return FILES[p] ~= nil or DIRS[p] == true end,
  isDirectory   = function(p) return DIRS[p] == true end,
  makeDirectory = function(p) DIRS[p] = true; return true end,
  size          = function(p) return FILES[p] and #FILES[p] or 0 end,
  spaceTotal    = function() return 4096 * KB end,
  spaceFree     = function() return FREE end,
  copy          = function(a, b)
    if not FILES[a] then return false, "no such file" end
    copies = copies + 1; FILES[b] = FILES[a]; return true
  end,
}

local register = assert(require("shell.panels.commands.extras"))
local S = {
  K = { uptime = function() return 0 end, getConfig = function() return nil end },
  E = { push = function() end }, P = {}, F = F, D = {}, U = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end, refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end, promptInput = function() return "y" end,
  dialog = function() return 1 end, confirm = function() return true end,
  confirmTyped = function() return true end,
}
local C = {}
register(C, S, deps)

local function deploy(args)
  local out = {}
  local ok, err = pcall(C.deploy, args, function(t) out[#out + 1] = tostring(t) end)
  return ok, table.concat(out, "\n"), err
end

-- 633 KB of files + 5 files x 512 + dirs (/tos, /tos/kernel, and the five
-- deploy makes up front) x 512: about 640 KB.
print("=== deploy <mount> checks the fit before it copies ===")
print()

reset(512 * KB)                                        -- a floppy
local ok, text, err = deploy({ "/mnt/disk" })
test("deploy returns cleanly", ok, err)
test("a disk TOS does not fit is refused", text:find("will not fit", 1, true) ~= nil, text)
test("...naming both sizes", text:find("needs", 1, true) ~= nil and text:find("free", 1, true) ~= nil, text)
test("...with the error code", text:find("E-306", 1, true) ~= nil, text)
test("...and nothing is copied", copies == 0, copies)
test("...and no directory is made on it", DIRS["/mnt/disk/tos"] == nil)

reset(2048 * KB)
ok, text = deploy({ "/mnt/disk" })
test("a disk with room is deployed", text:find("Install disk created", 1, true) ~= nil, text)
test("...all five files", copies == 5, copies)
test("...after saying how much it needs", text:find("Needs ", 1, true) ~= nil, text)

-- Re-deploying over an existing install only needs the difference.
FREE = 64 * KB
copies = 0
ok, text = deploy({ "/mnt/disk" })
test("re-deploying over the same files fits in what is free", text:find("Install disk created", 1, true) ~= nil, text)

reset(2048 * KB)
ok, text = deploy({})
test("the usage no longer suggests a floppy", text:find("floppy", 1, true) == nil, text)
ok, text = deploy({ "/etc" })
test("the system-path refusal no longer suggests a floppy", text:find("floppy", 1, true) == nil, text)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
