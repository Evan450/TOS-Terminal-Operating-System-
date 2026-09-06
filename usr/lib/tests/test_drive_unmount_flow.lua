-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `drive` takes the volume out and puts it back ║
-- ║                                                                ║
-- ║  format / check --repair / defrag open a SECOND driver handle   ║
-- ║  on the sectors, so they cannot run while the volume is         ║
-- ║  mounted: they rewrite the bitmap and inodes under the mount's  ║
-- ║  own cache, and the next write through it allocates from a      ║
-- ║  stale bitmap. Refusing outright was correct and useless -- it  ║
-- ║  made the operator do the unmount, the work and the remount by  ║
-- ║  hand, every time, for a volume that in the common case has     ║
-- ║  nothing whatsoever using it.                                   ║
-- ║                                                                ║
-- ║  So: unmount, work, remount. Ask FIRST only when something      ║
-- ║  would actually be disturbed -- an open file handle, or a       ║
-- ║  process whose cwd is inside the mount -- and say which. And    ║
-- ║  remount on the way out of a FAILED action too, so no drive is  ║
-- ║  ever left detached because an fsck errored.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_drive_unmount_flow.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_drive_unmount_flow.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

local DRIVE_ADDR = "drive-addr-0123456789abcdef"

-- ── A raw drive, and the blockfs driver over it ──────────────────
local sectors = {}
local rawDrive = {
  address = DRIVE_ADDR,
  getSectorSize = function() return 512 end,
  getCapacity   = function() return 512 * 512 end,
  getPlatterCount = function() return 1 end,
  readSector = function(n) return sectors[n] or string.rep("\0", 512) end,
  writeSector = function(n, d)
    if #d < 512 then d = d .. string.rep("\0", 512 - #d) elseif #d > 512 then d = d:sub(1, 512) end
    sectors[n] = d
  end,
}

package.loaded["component"] = {
  list = function(t)
    local done = false
    return function()
      if done or (t ~= "drive" and t ~= nil) then return nil end
      done = true; return DRIVE_ADDR, "drive"
    end
  end,
  proxy = function(a) return (a == DRIVE_ADDR) and rawDrive or nil end,
  type  = function() return "drive" end,
}
package.loaded["computer"] = { uptime = function() return 1 end, freeMemory = function() return 200000 end,
  pullSignal = function() end, beep = function() end }

local blockfs
for _, p in ipairs({ base .. "../../../../TOS-Extras/modules/blockfs/usr/lib/blockfs.lua",
                     "../TOS-Extras/modules/blockfs/usr/lib/blockfs.lua",
                     "TOS-Extras/modules/blockfs/usr/lib/blockfs.lua" }) do
  local chunk = loadfile(p); if chunk then blockfs = chunk(); break end
end
if not blockfs then
  print("FAIL: could not load blockfs.lua"); print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***"); os.exit(1)
end
package.loaded["blockfs"] = blockfs
blockfs.format(rawDrive, { label = "data" })

-- ── A mount table with the kernel's own openFiles reporting ──────
local mounts = {}
local unmountCalls, mountCalls = {}, {}
local F = {
  mounts = function()
    local out = {}
    for mp, proxy in pairs(mounts) do
      local openFiles = nil
      if type(proxy.openHandles) == "function" then
        local ok, n = pcall(proxy.openHandles)
        if ok and type(n) == "number" then openFiles = n end
      end
      out[#out + 1] = { mountPoint = mp, label = "data", address = proxy.address,
                        total = 0, used = 0, openFiles = openFiles }
    end
    return out
  end,
  mount = function(mp, proxy) mounts[mp] = proxy; mountCalls[#mountCalls + 1] = mp; return true end,
  unmount = function(mp)
    local p = mounts[mp]; mounts[mp] = nil
    unmountCalls[#unmountCalls + 1] = mp
    if p and p.unmount then pcall(p.unmount) end
    return true
  end,
  exists = function() return true end,
  makeDirectory = function() return true end,
}

-- ── Load the real `drive` command ────────────────────────────────
local procList = {}
local S = {
  K = { uptime = function() return 1 end },
  E = {}, P = { list = function() return procList end }, F = F,
  D = {}, U = {}, SC = {}, NM = {}, st = {},
  T = setmetatable({}, { __index = function() return 0 end }),
  tier = 3, W = 80, H = 25,
}
local askedWith, answer = nil, true
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  dialog = function() end, makeProgramEnv = function() end,
  promptInput = function() return answer and "y" or "n" end,
  confirm = function(msg, opts) askedWith = msg; return answer end,
}
local C = {}
local chunk
for _, p in ipairs({ base .. "../../../tos/shell/panels/commands/extras.lua",
                     "tos/shell/panels/commands/extras.lua" }) do
  chunk = loadfile(p); if chunk then break end
end
if not chunk then
  print("FAIL: could not load commands/extras.lua"); print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***"); os.exit(1)
end
chunk()(C, S, deps)
local drive = C.drive
if not drive then
  print("FAIL: extras registered no `drive` command"); print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***"); os.exit(1)
end

local out = {}
local function o(s) out[#out + 1] = tostring(s) end
local function reset() out, askedWith = {}, nil end
local function said(needle)
  for _, l in ipairs(out) do if l:find(needle, 1, true) then return true end end
  return false
end
local function mountedAt()
  for mp in pairs(mounts) do return mp end
  return nil
end

print("=== drive: unmount, work, remount Tests ===")
print()

-- ── Nothing using it: no question, just do it ────────────────────
print("-- an idle volume is unmounted without asking --")
mounts["/mnt/data"] = (blockfs.mount(rawDrive, { now = function() return 1 end }))
unmountCalls, mountCalls = {}, {}
reset(); drive({ "defrag", DRIVE_ADDR:sub(1, 8) }, o)
test("nothing was asked", nil, askedWith)
test("it said it was unmounting because nothing was using it", true,
  said("Nothing is using /mnt/data"))
test("the volume was unmounted", 1, #unmountCalls)
test("...and remounted at the same path", "/mnt/data", mountCalls[1])
test("...and is mounted now", "/mnt/data", mountedAt())
test("the defrag ran", true, said("Defragmented"))
test("it said so", true, said("Remounted at /mnt/data"))

-- ── An open file: ask, and say what is holding it ────────────────
print()
print("-- an open file handle makes it ask --")
local proxy = mounts["/mnt/data"]
proxy.makeDirectory("/d")
local h = proxy.open("/d/f", "w")
test("the driver reports the open handle", 1, proxy.openHandles())
unmountCalls, mountCalls = {}, {}
answer = false
reset(); drive({ "defrag", DRIVE_ADDR:sub(1, 8) }, o)
test("it asked", true, askedWith ~= nil)
test("...naming the open handle", true, (askedWith or ""):find("open file handle", 1, true) ~= nil)
test("declining cancels", true, said("Cancelled"))
test("...without unmounting", 0, #unmountCalls)
test("...and the volume is still mounted", "/mnt/data", mountedAt())
test("...and the defrag did not run", false, said("Defragmented"))

answer = true
unmountCalls, mountCalls = {}, {}
reset(); drive({ "defrag", DRIVE_ADDR:sub(1, 8) }, o)
test("accepting unmounts", 1, #unmountCalls)
test("...runs the work", true, said("Defragmented"))
test("...and remounts", "/mnt/data", mountedAt())
proxy.close(h)

-- ── A process sitting inside the mount ───────────────────────────
print()
print("-- a process inside the mount makes it ask --")
procList = { { pid = 12, name = "edit", cwd = "/mnt/data/d" } }
answer = false
reset(); drive({ "check", DRIVE_ADDR:sub(1, 8), "--repair" }, o)
test("it asked", true, askedWith ~= nil)
test("...naming the process and where it is", true,
  (askedWith or ""):find("edit (pid 12) is in /mnt/data/d", 1, true) ~= nil)
test("declining leaves it mounted", "/mnt/data", mountedAt())
-- A process merely NEAR the mount is not in it.
procList = { { pid = 13, name = "shell", cwd = "/mnt/data2/x" } }
unmountCalls = {}
answer = true
reset(); drive({ "check", DRIVE_ADDR:sub(1, 8), "--repair" }, o)
test("a sibling path is not mistaken for the mount", nil, askedWith)
test("...so it just worked", 1, #unmountCalls)
procList = {}

-- ── A read-only check does not disturb the mount at all ──────────
print()
print("-- a read-only check leaves the mount alone --")
unmountCalls = {}
reset(); drive({ "check", DRIVE_ADDR:sub(1, 8) }, o)
test("no unmount for a read-only check", 0, #unmountCalls)
test("...and the dirty flag is explained rather than reported as damage", true,
  said("the dirty flag is expected"))

-- ── format goes through the same door ────────────────────────────
print()
print("-- format --")
unmountCalls, mountCalls = {}, {}
answer = true
reset(); drive({ "format", DRIVE_ADDR:sub(1, 8), "fresh" }, o)
test("format unmounted first", 1, #unmountCalls)
test("...formatted", true, said('Formatted as TBFS "fresh"'))
test("...and remounted", "/mnt/data", mountedAt())
test("the fresh volume is empty", 0, #mounts["/mnt/data"].list("/"))

-- ── A failing action still gives the drive back ──────────────────
print()
print("-- the remount happens even when the work fails --")
local realDefrag = blockfs.defrag
blockfs.defrag = function() error("simulated driver explosion", 0) end
unmountCalls, mountCalls = {}, {}
reset()
local ok = pcall(drive, { "defrag", DRIVE_ADDR:sub(1, 8) }, o)
blockfs.defrag = realDefrag
test("the failure was not swallowed", false, ok)
test("...the volume was unmounted", 1, #unmountCalls)
test("...and it was put back anyway", "/mnt/data", mountedAt())

-- ── Not mounted at all: nothing to unmount, nothing to ask ───────
print()
print("-- an unmounted drive is just worked on --")
F.unmount("/mnt/data")
unmountCalls, mountCalls = {}, {}
reset(); drive({ "defrag", DRIVE_ADDR:sub(1, 8) }, o)
test("no unmount", 0, #unmountCalls)
test("no remount", 0, #mountCalls)
test("nothing asked", nil, askedWith)
test("the work still ran", true, said("Defragmented"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
