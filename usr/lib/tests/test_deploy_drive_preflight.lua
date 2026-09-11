-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `deploy drive` checks BEFORE it erases        ║
-- ║                                                                 ║
-- ║  deploy drive used to format the raw drive first and find out    ║
-- ║  afterwards whether TOS fit, printing one "FAIL <path>" per      ║
-- ║  file that didn't -- on a drive it had already wiped. An outside ║
-- ║  review (2026-09-10) flagged the inode half: one inode per 4 KB  ║
-- ║  gives a 1 MB drive 256, shared by 152 files and their directory ║
-- ║  chain. The byte half is the one that bites first today, since   ║
-- ║  the OS is ~1.6 MB, and nothing checked it at all.               ║
-- ║                                                                  ║
-- ║  Drives the REAL C.deploy (TOS-Dev) against the REAL blockfs     ║
-- ║  (TOS-Extras) on a fake raw drive that counts sector writes, so   ║
-- ║  "nothing was erased" is measured rather than read off a message. ║
-- ╚═══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_deploy_drive_preflight.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local blockfsSrc
for _, p in ipairs({ "../TOS-Extras/modules/blockfs/usr/lib/blockfs.lua",
                     "TOS-Extras/modules/blockfs/usr/lib/blockfs.lua",
                     "../../../../TOS-Extras/modules/blockfs/usr/lib/blockfs.lua" }) do
  blockfsSrc = readAll(p); if blockfsSrc then break end
end
if not blockfsSrc then
  print("FAIL: blockfs.lua not found (TOS-Extras ships inside the dev branch)")
  print("*** TESTS FAILED ***"); os.exit(1)
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

-- ── Stubs, installed BEFORE anything loads ──────────────────────────
package.loaded["computer"] = { uptime = function() return 0 end,
                               freeMemory = function() return 1e6 end,
                               beep = function() end }
local DRIVES = {}
package.loaded["component"] = {
  list = function(kind)
    local keys = {}
    if kind == "drive" then for a in pairs(DRIVES) do keys[#keys + 1] = a end end
    table.sort(keys)
    local i = 0
    return function() i = i + 1; return keys[i] end
  end,
  proxy = function(a) return DRIVES[a] end,
  isAvailable = function() return false end,
}

-- The real driver, registered under the name deploy require()s.
local blockfs = assert(load(blockfsSrc, "=blockfs.lua", "t"))()
package.loaded["blockfs"] = blockfs

-- A raw drive that counts what is written to it.
local function fakeDrive(cap)
  local sectors, writes = {}, 0
  return {
    getSectorSize = function() return 512 end,
    getCapacity   = function() return cap end,
    readSector    = function(i) return sectors[i] or string.rep("\0", 512) end,
    writeSector   = function(i, s) writes = writes + 1; sectors[i] = s end,
  }, function() return writes end
end

-- The running system's files, as deploy reads them.
local FILES = {}
local F = {
  exists   = function(p) return FILES[p] ~= nil end,
  readFile = function(p) return FILES[p] end,
  size     = function(p) return FILES[p] and #FILES[p] or 0 end,
}
local function manifestOf(n, size, dirs)
  FILES = { ["/usr/lib/blockfs.lua"] = blockfsSrc }
  local m = {}
  for i = 1, n do
    local p = dirs[(i - 1) % #dirs + 1] .. "/f" .. i .. ".lua"
    FILES[p] = string.rep("x", size)
    m[#m + 1] = { path = p }
  end
  package.loaded["system_manifest"] = m
  return m
end

-- ── The real command table ─────────────────────────────────────────
local okE, register = pcall(require, "shell.panels.commands.extras")
test("extras.lua loads", okE and type(register) == "function", register)
if not okE then print("*** TESTS FAILED ***"); os.exit(1) end

local asked = 0
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
  dialog = function() return 1 end,
  confirm = function() asked = asked + 1; return true end,
  confirmTyped = function() return true end,
}
local C = {}
local okR, rerr = pcall(register, C, S, deps)
test("extras.lua registers its commands", okR, rerr)
test("C.deploy exists", type(C.deploy) == "function")
if not (okR and C.deploy) then print("*** TESTS FAILED ***"); os.exit(1) end

local function deploy(prefix)
  local out = {}
  local ok, err = pcall(C.deploy, { "drive", prefix }, function(t) out[#out + 1] = tostring(t) end)
  return ok, err, table.concat(out, "\n")
end

print()
print("=== deploy drive pre-flight ===")

-- ── A. Too small in BYTES: refused, never asked, never touched ─────
print("\n-- A: the OS does not fit --")
do
  manifestOf(40, 8192, { "/tos/a", "/tos/b" })          -- ~320 KB of files
  local d, writes = fakeDrive(256 * 1024)              -- ~190 KB after the boot region
  DRIVES = { ["aaaa1111"] = d }
  asked = 0
  local ok, err, text = deploy("aaaa")
  test("A: deploy returns cleanly", ok, err)
  test("A: it says TOS will not fit", text:find("will not fit", 1, true) ~= nil, text)
  test("A: ...and that nothing was erased", text:find("Nothing was erased", 1, true) ~= nil)
  test("A: it never asked to erase the drive", asked == 0, "asked " .. asked)
  test("A: and never wrote a single sector", writes() == 0, writes() .. " writes")
end

-- ── B. Enough bytes, too few default inodes: fixed, not refused ────
print("\n-- B: the default inode table is too small --")
do
  -- 300 files + 4 dirs + root = 305 inodes; 1 MB at 1 per 4 KB gives 256.
  local m = manifestOf(300, 100, { "/usr/x", "/usr/y", "/usr/z" })
  local d = fakeDrive(1024 * 1024)
  DRIVES = { ["bbbb2222"] = d }
  asked = 0
  local ok, err, text = deploy("bbbb")
  test("B: deploy returns cleanly", ok, err)
  test("B: it sized the inode table for the install instead of failing",
    text:find("Sizing the inode table", 1, true) ~= nil, text)
  test("B: it asked once before erasing", asked == 1, "asked " .. asked)
  test("B: no file failed to copy", text:find("FAIL", 1, true) == nil, text)
  test("B: it reports a written install", text:find("TBFS install written", 1, true) ~= nil, text)
  local p = blockfs.mount(d, {})
  local missing = 0
  for _, e in ipairs(m) do if not (p and p.exists(e.path)) then missing = missing + 1 end end
  test("B: all 300 files are really on the drive", missing == 0, missing .. " missing")
  if p then p.unmount() end
  local r = blockfs.check(d, {})
  test("B: and the volume is structurally clean", r and r.ok, r and table.concat(r.problems, "; "))
end

-- ── C. Fits comfortably: says so, with the numbers ─────────────────
print("\n-- C: it fits --")
do
  manifestOf(20, 4096, { "/tos/kernel" })
  local d = fakeDrive(2 * 1024 * 1024)
  DRIVES = { ["cccc3333"] = d }
  asked = 0
  local ok, err, text = deploy("cccc")
  test("C: deploy returns cleanly", ok, err)
  test("C: it reports that it fits", text:find("Fits:", 1, true) ~= nil, text)
  test("C: no inode resize when none is needed",
    text:find("Sizing the inode table", 1, true) == nil)
  test("C: it asked once", asked == 1, "asked " .. asked)
  test("C: the install was written", text:find("TBFS install written", 1, true) ~= nil, text)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
