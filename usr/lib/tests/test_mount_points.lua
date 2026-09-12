-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a mount lands where TOS says, not where the   ║
-- ║  disk says                                                      ║
-- ║                                                                ║
-- ║  `drive mount <addr>` joined the TBFS volume's own label onto   ║
-- ║  /mnt/, and a label is whatever the disk's author wrote:        ║
-- ║  "../../var/pkg/secrets" mounted the disk over that directory   ║
-- ║  (the hot-plug mount always sanitised labels; this did not).    ║
-- ║  And securefs.mount checked only for ADMIN: fs.mount takes any  ║
-- ║  empty or absent directory, so a disk could sit where the       ║
-- ║  protected-path guard stops even an admin writing (Sep 2026     ║
-- ║  pentest). Drives the REAL C.drive and securefs.mount.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mount_points.lua   (from TOS-Dev)

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
local DRIVE = { address = "dddd1111" }
package.loaded["component"] = {
  list = function(kind)
    local done = false
    return function()
      if kind == "drive" and not done then done = true; return DRIVE.address end
    end
  end,
  proxy = function(a) if a == DRIVE.address then return DRIVE end end,
  isAvailable = function() return false end,
}
package.loaded["kernel.process"] = { currentSession = function() return nil end,
                                     yieldCooperative = function() end }

local function norm(p)
  local parts = {}
  for seg in tostring(p):gsub("\\", "/"):gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return "/" .. table.concat(parts, "/")
end

print("=== a mount lands where TOS says ===")
print()
print("-- drive mount names the mount point from a sanitised label --")
local LABEL = "../../var/pkg/secrets"
package.loaded["blockfs"] = {
  mount = function() return { getLabel = function() return LABEL end } end,
  stats = function() return nil end,
}
local mounted = {}
local F = {
  exists = function() return false end, makeDirectory = function() return true end,
  mounts = function() return {} end, normalize = norm,
  mount = function(p) mounted[#mounted + 1] = norm(p); return true end,
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
test("extras.lua registers C.drive", okR and type(C.drive) == "function", rerr)
local out = {}
pcall(C.drive, { "mount", "dddd" }, function(t) out[#out + 1] = tostring(t) end)
local at = mounted[1]
test("a volume labelled " .. LABEL .. " is mounted under /mnt/, as a name",
  at ~= nil and at:sub(1, 5) == "/mnt/" and at:find("/", 6, true) == nil, at or table.concat(out, " | "))

print()
print("-- securefs.mount holds a mount point to the protected-path guard --")
local fs = require("kernel.fs")
local users = require("kernel.users")
local sfs = require("kernel.securefs")
local fsMounts = {}
sfs.init({ fs = { normalize = fs.normalize,
                  mount = function(p) fsMounts[#fsMounts + 1] = p; return true end },
           users = users })
local T = users.TIER
local alice = { user = "alice", tier = T.USER }
local adam  = { user = "adam",  tier = T.ADMIN }
local root  = { user = "root",  tier = T.ROOT }

for _, p in ipairs({ "/var/pkg/secrets", "/etc/rc.d", "/tos/kernel/extra", "/usr/lib/kernel",
                     "/MNT/../ETC/rc.d" }) do
  local ok, err = sfs.mount(p, {}, adam)
  test("an admin cannot mount a disk at " .. p, ok == false and tostring(err):find("protected", 1, true) ~= nil,
    tostring(err))
end
test("...and none of those reached fs.mount", #fsMounts == 0, #fsMounts .. " mounts")
test("an admin still mounts under /mnt/", sfs.mount("/mnt/usb", {}, adam) == true and fsMounts[1] == "/mnt/usb")
test("...and in a home", sfs.mount("/home/adam/share", {}, adam) == true)
test("a USER still cannot mount at all", sfs.mount("/mnt/other", {}, alice) == false)
sfs.setOperatorOverride(root, true)
test("root with `protect off` can, and it is on them", sfs.mount("/var/pkg/secrets", {}, root) == true)
sfs.setOperatorOverride(root, false)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
