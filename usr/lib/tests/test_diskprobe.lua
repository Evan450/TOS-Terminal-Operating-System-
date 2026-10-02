-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: name what is on a drive before erasing it     ║
-- ║                                                                ║
-- ║  `drive format` and `deploy` erased a raw drive behind a danger ║
-- ║  box that could say nothing about what was there: TBFS's only   ║
-- ║  answer about a foreign volume was "not a TBFS volume". The     ║
-- ║  probe (shell/panels/diskprobe.lua) recognises the formats      ║
-- ║  other OpenComputers systems write, read-only, and the boxes    ║
-- ║  and `drive info` now say what they found.                      ║
-- ║                                                                ║
-- ║  Each fixture is built from its format's own spec with          ║
-- ║  string.pack, not copied from anyone's disk.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_diskprobe.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_diskprobe.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

local okP, dp = pcall(require, "shell.panels.diskprobe")
test("the probe loads", okP and type(dp) == "table" and type(dp.probe) == "function", dp)
if not okP then print("*** TESTS FAILED ***"); os.exit(1) end

-- ── Fake raw drives ────────────────────────────────────────────────
local SS, COUNT = 512, 256
local writes = 0
local function drive(sectors, opts)
  opts = opts or {}
  local px = {
    getSectorSize = function() return SS end,
    getCapacity = function() return SS * COUNT end,
    readSector = function(n)
      if opts.raises then error("drive removed") end
      local s = sectors[n] or ""
      return s .. string.rep("\0", SS - #s)
    end,
    writeSector = function() writes = writes + 1; error("the probe must not write") end,
  }
  return px
end
local function pad(s) return s .. string.rep("\0", SS - #s) end

-- OSDI 1.1: 32-byte little-endian entries; the first is the header.
local OSDI = "<I4I4c8I3c13"
local function osdi(entries)
  local t = { OSDI:pack(1, 0, "OSDI\170\170\85\85", 0, "") }
  for _, e in ipairs(entries) do t[#t + 1] = OSDI:pack(e[1], e[2], e[3], e[4] or 0, e[5] or "") end
  return pad(table.concat(t))
end
-- MTPT: 32-byte big-endian entries in the LAST sector; the first is typed "mtpt".
local MTPT = ">c20c4I4I4"
local function mtpt(entries)
  local t = { MTPT:pack("table", "mtpt", 0, 0) }
  for _, e in ipairs(entries) do t[#t + 1] = MTPT:pack(e[1], e[2], e[3], e[4]) end
  return pad(table.concat(t))
end

print("=== name what is on a drive before erasing it ===")
print()

local function probe(sectors, opts) return dp.probe(drive(sectors, opts)) end

local r = probe({ [1] = "TBFS\1" })
test("TBFS is recognised", r.kind == "tbfs", r.text)

r = probe({ [1] = osdi({ { 2, 8, "BOOTCODE", 0x200, "" }, { 10, 128, "foxfs   ", 0, "Tsuki" } }) })
test("OSDI is recognised", r.kind == "osdi", r.text)
test("...with its partitions named (the type when a partition has no name)",
  r.text == "an OSDI partition table: 2 partitions (BOOTCODE, Tsuki)", r.text)

r = probe({ [1] = osdi({ { 2, 8, "a", 0, "one" }, { 10, 8, "b", 0, "two" }, { 18, 8, "c", 0, "three" },
                         { 26, 8, "d", 0, "four" }, { 34, 8, "e", 0, "five" } }) })
test("a long table shows three names and a count", r.text == "an OSDI partition table: 5 partitions (one, two, three, +2)", r.text)

r = probe({ [1] = osdi({ { 2, 8, "x", 0, "\27[2J\7evil" } }) })
test("a partition name cannot draw on the screen", r.text:find("\27", 1, true) == nil
  and r.text:find("\7", 1, true) == nil and r.text:find("?[2J?evil", 1, true) ~= nil, r.text)

r = probe({ [1] = osdi({}) })
test("an OSDI table with nothing in it says so", r.text == "an OSDI partition table, with no partitions", r.text)

r = probe({ [2] = "\27[OCGPTm" .. ("<I8"):pack(0) })
test("OCGPT is recognised (sector 2)", r.kind == "ocgpt", r.text)

r = probe({ [COUNT] = mtpt({ { "root", "rtfs", 1, 100 }, { "swap", "swap", 101, 50 } }) })
test("MTPT is recognised (the LAST sector)", r.kind == "mtpt", r.text)
test("...with its partitions named", r.text == "an MTPT partition table: 2 partitions (root, swap)", r.text)

r = probe({ [1] = "\27SFS" .. string.rep("\1", 12) .. "storage" })
test("SimpleFS is recognised, with its label", r.kind == "simplefs"
  and r.text == 'a SimpleFS filesystem labelled "storage"', r.text)

r = probe({ [1] = string.rep("\0", 510) .. "\85\170" })
test("an MBR/FAT boot record is recognised", r.kind == "mbr", r.text)

r = probe({})
test("an empty drive reads as blank", r.kind == "blank", r.text)

r = probe({ [1] = "just some bytes somebody wrote" })
test("anything else is 'not recognised', never 'blank'", r.kind == "unknown", r.text)

r = probe({ [1] = "TBFS\1" }, { raises = true })
test("a drive that errors is 'unreadable', and the probe does not throw", r.kind == "unreadable", r.text)

r = dp.probe({ getLabel = function() return "a managed disk" end })
test("something that is not a raw drive is said so", r.kind == "unreadable", r.text)

test("the probe never wrote a sector", writes == 0, writes)

-- ── The real `drive` command says it before it erases ──────────────
print()
print("--- drive format, drive info ---")
do
  local DRIVE_ADDR = "osdi0123-drive-addr-4567"
  local sectors = { [1] = osdi({ { 2, 8, "BOOTCODE", 0x200, "" }, { 10, 128, "foxfs   ", 0, "Tsuki" } }) }
  local raw = drive(sectors)
  raw.address = DRIVE_ADDR
  raw.getPlatterCount = function() return 1 end
  package.loaded["component"] = {
    list = function(t)
      local done = false
      return function()
        if done or (t ~= "drive" and t ~= nil) then return nil end
        done = true; return DRIVE_ADDR, "drive"
      end
    end,
    proxy = function(a) return (a == DRIVE_ADDR) and raw or nil end,
    type = function() return "drive" end,
  }
  package.loaded["computer"] = { uptime = function() return 1 end, freeMemory = function() return 200000 end,
    pullSignal = function() end, beep = function() end }
  local blockfs
  for _, p in ipairs({ base .. "../../../../TOS-Extras/modules/blockfs/usr/lib/blockfs.lua",
                       "../TOS-Extras/modules/blockfs/usr/lib/blockfs.lua",
                       "TOS-Extras/modules/blockfs/usr/lib/blockfs.lua" }) do
    local chunk = loadfile(p); if chunk then blockfs = chunk(); break end
  end
  test("blockfs loads (the drive command needs it to format)", blockfs ~= nil)
  package.loaded["blockfs"] = blockfs

  local F = { mounts = function() return {} end, exists = function() return true end,
              makeDirectory = function() return true end }
  local S = { K = { uptime = function() return 1 end }, E = {}, P = { list = function() return {} end },
              F = F, D = {}, U = {}, SC = {}, NM = {}, st = {},
              T = setmetatable({}, { __index = function() return 0 end }), tier = 3, W = 80, H = 25 }
  local askedWith
  local deps = {
    rp = function(p) return p end, openViewTab = function() end, openEditTab = function() end,
    refreshBrowser = function() end, canRead = function() return true end,
    canWrite = function() return true end, canAccess = function() return true end,
    rootOnly = function() return true end, adminOnly = function() return true end,
    dialog = function() end, makeProgramEnv = function() end,
    promptInput = function() return "n" end,
    confirm = function(msg) askedWith = msg; return false end,      -- the operator says no
  }
  local C, chunk = {}, nil
  for _, p in ipairs({ base .. "../../../tos/shell/panels/commands/extras.lua",
                       "tos/shell/panels/commands/extras.lua" }) do
    chunk = loadfile(p); if chunk then break end
  end
  test("commands/extras.lua loads", chunk ~= nil)
  if chunk and blockfs then
    chunk()(C, S, deps)
    local out = {}
    local o = function(t) out[#out + 1] = tostring(t) end
    C.drive({ "format", "osdi0123" }, o)
    test("the format box names what is on the drive",
      askedWith ~= nil and askedWith:find("It holds an OSDI partition table: 2 partitions (BOOTCODE, Tsuki).", 1, true) ~= nil,
      askedWith)
    local holdsAt = askedWith and askedWith:find("It holds", 1, true)
    local goneAt = askedWith and askedWith:find("destroyed", 1, true)
    test("...before the line saying it will be destroyed", holdsAt ~= nil and goneAt ~= nil and holdsAt < goneAt)
    test("...and answering no leaves the table where it was", sectors[1]:sub(9, 16) == "OSDI\170\170\85\85")

    out = {}
    C.drive({ "info", "osdi0123" }, o)
    local said = table.concat(out, "\n")
    test("drive info says what a foreign drive holds",
      said:find("Not a TBFS volume. It holds an OSDI partition table", 1, true) ~= nil, said)
  end
  test("nothing was written along the way", writes == 0, writes)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
