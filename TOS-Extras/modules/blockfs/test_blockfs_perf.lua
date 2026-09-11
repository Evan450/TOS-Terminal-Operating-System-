-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: blockfs costs what it says it costs          ║
-- ║                                                                ║
-- ║  Every sector call crosses the OC component bridge, so the     ║
-- ║  number of calls IS the speed of the filesystem. These pin the ║
-- ║  budgets the 2026-09-06 rewrite bought (measured against the   ║
-- ║  version before it, in brackets):                              ║
-- ║                                                                ║
-- ║    write 64 KB in one call     136 writes,   2 reads (384/131) ║
-- ║    write 64 KB in 8 KB calls   164 writes,   1 read  (398/145) ║
-- ║    write 4 KB                   16 writes,   2 reads  (23/12)  ║
-- ║    twenty 2-byte files         164 writes,  89 reads (165/130) ║
-- ║    remove one of twenty          7 writes,   4 reads  (25/5)   ║
-- ║    format 2 MB                  69 writes,   2 reads (134/67)  ║
-- ║                                                                ║
-- ║  Budgets are ratios and loose ceilings, not the exact figures, ║
-- ║  so an unrelated layout change does not fail them -- but a     ║
-- ║  return of any of the three per-block costs (read-before-     ║
-- ║  write, a bitmap write per bit, a pointer write per pointer)   ║
-- ║  does.                                                         ║
-- ║                                                                ║
-- ║  And the half that matters more: the shortcuts must not cost   ║
-- ║  correctness. Fresh-block zero fill, partial overwrites in the ║
-- ║  middle of existing data, a crash between the data and the     ║
-- ║  metadata flush, parents on mkdir, rename into one's own       ║
-- ║  subtree, and the boot blob still fitting its region.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/blockfs/test_blockfs_perf.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end
local function le(name, limit, actual)
  test(name .. "  (" .. tostring(actual) .. " <= " .. tostring(limit) .. ")", actual <= limit)
end

local here = (arg and arg[0]) or "modules/blockfs/test_blockfs_perf.lua"
local base = here:gsub("[^/\\]*$", "")
local chunk, blockfsPath
for _, p in ipairs({ base .. "usr/lib/blockfs.lua",
    "modules/blockfs/usr/lib/blockfs.lua",
    "TOS-Extras/modules/blockfs/usr/lib/blockfs.lua" }) do
  chunk = loadfile(p); if chunk then blockfsPath = p; break end
end
if not chunk then print("FAIL: could not load blockfs.lua"); print("*** TESTS FAILED ***"); return false end
local blockfs = chunk()

-- A counting fake drive. `failAfterWrites` makes the drive die (raise)
-- after that many more writes -- the computer block being broken mid-
-- operation -- so the on-disk picture at that instant can be inspected.
local function fakeDrive(ss, sectors)
  local store = {}
  local d = { R = 0, W = 0, failAfterWrites = nil }
  d.getSectorSize = function() return ss end
  d.getCapacity   = function() return ss * sectors end
  d.getPlatterCount = function() return 1 end
  d.readSector    = function(n) d.R = d.R + 1; return store[n] or string.rep("\0", ss) end
  d.writeSector   = function(n, s)
    if d.failAfterWrites then
      if d.failAfterWrites <= 0 then error("drive vanished", 0) end
      d.failAfterWrites = d.failAfterWrites - 1
    end
    d.W = d.W + 1
    if #s < ss then s = s .. string.rep("\0", ss - #s) elseif #s > ss then s = s:sub(1, ss) end
    store[n] = s
  end
  function d.reset() local r, w = d.R, d.W; d.R, d.W = 0, 0; return r, w end
  return d
end

local function readAll(fs, path, chunk)
  local h = fs.open(path, "r"); if not h then return nil end
  local parts = {}
  while true do local c = fs.read(h, chunk or 8192); if not c then break end; parts[#parts + 1] = c end
  fs.close(h)
  return table.concat(parts)
end
local function writeFile(fs, path, data, chunk)
  local h = fs.open(path, "w"); if not h then return false end
  local i, ok = 1, true
  while i <= #data do
    ok = fs.write(h, data:sub(i, i + (chunk or #data) - 1)) and ok
    i = i + (chunk or #data)
  end
  fs.close(h)
  return ok
end

print("=== blockfs cost + shortcut-safety Tests ===")
print()

-- ═══════════════════════════════════════════════════════════════════
print("-- what things cost --")
local d = fakeDrive(512, 4096)             -- 2 MB
blockfs.format(d, { label = "perf" })
do
  local r, w = d.reset()
  le("format: bitmap marked in one write per sector, not per block", 80, w)
  le("format: reads", 4, r)
end
local fs = blockfs.mount(d)
d.reset()

writeFile(fs, "/a4k", string.rep("x", 4096))
do
  local r, w = d.reset()
  le("4 KB write: writes (8 data + inode + super + bitmap + dir)", 20, w)
  le("4 KB write: reads (no read-before-write on fresh blocks)", 4, r)
end

writeFile(fs, "/b64k", string.rep("y", 65536))
do
  local r, w = d.reset()
  -- 128 data blocks + 1 indirect + bitmap + pointers + inode + super + dir
  le("64 KB write, one call: at most ~1.1 writes per data block", 145, w)
  le("64 KB write, one call: reads", 4, r)
end

writeFile(fs, "/c64k", string.rep("z", 65536), 8192)
do
  local r, w = d.reset()
  le("64 KB write in 8 KB calls: at most ~1.3 writes per data block", 170, w)
  le("64 KB write in 8 KB calls: reads", 4, r)
end

do
  local got = readAll(fs, "/c64k")
  local r, w = d.reset()
  eq("64 KB read back intact", 65536, #got)
  le("64 KB read: one read per block, nothing else", 134, r)
  eq("64 KB read: no writes", 0, w)
end

fs.makeDirectory("/d")
d.reset()
for i = 1, 20 do writeFile(fs, "/d/f" .. i, "hi") end
do
  local r, w = d.reset()
  le("twenty tiny files: writes per file", 20 * 9, w)
  le("twenty tiny files: reads per file", 20 * 5, r)
end
do
  fs.remove("/d/f10")
  local r, w = d.reset()
  le("removing one of twenty: the listing is rewritten in ONE pass", 9, w)
  le("removing one of twenty: reads", 6, r)
  eq("...and the directory still has nineteen", 19, #fs.list("/d"))
  test("...the right one is gone", not fs.exists("/d/f10") and fs.exists("/d/f11"))
end

-- ═══════════════════════════════════════════════════════════════════
print()
print("-- the shortcuts do not cost correctness --")

-- Fresh block, partial write: the bytes around the data must be zero,
-- exactly what a read-before-write of a zeroed block would have kept.
do
  local h = fs.open("/partial", "w")
  fs.write(h, "abc")                      -- 3 bytes into a fresh block
  fs.close(h)
  local h2 = fs.open("/partial", "a")
  fs.seek(h2, "set", 100)                 -- hole, then more
  fs.write(h2, "XYZ")
  fs.close(h2)
  local got = readAll(fs, "/partial")
  eq("sparse write: size", 103, #got)
  eq("sparse write: head", "abc", got:sub(1, 3))
  test("sparse write: hole is zero-filled", got:sub(4, 100) == string.rep("\0", 97))
  eq("sparse write: tail", "XYZ", got:sub(101))
end

-- Overwrite in the MIDDLE of an existing block: the read-modify-write
-- path still runs for a block that is not fresh and not fully covered.
do
  writeFile(fs, "/mid", string.rep("a", 1000))
  local h = fs.open("/mid", "a")
  fs.seek(h, "set", 600)
  fs.write(h, "BBB")
  fs.close(h)
  local got = readAll(fs, "/mid")
  eq("mid-file overwrite: size unchanged", 1000, #got)
  eq("mid-file overwrite: bytes before kept", string.rep("a", 600), got:sub(1, 600))
  eq("mid-file overwrite: the three bytes", "BBB", got:sub(601, 603))
  eq("mid-file overwrite: bytes after kept", string.rep("a", 397), got:sub(604))
end

-- A whole-block overwrite of an existing block: no read, same result.
do
  writeFile(fs, "/whole", string.rep("q", 1024))
  local h = fs.open("/whole", "a"); fs.seek(h, "set", 0)
  d.reset()
  fs.write(h, string.rep("Q", 512))
  local r = d.reset()
  fs.close(h)
  -- The data block is not read. The one read the budget allows is the
  -- inode sector for the size/mtime update, when the 4-slot cache has
  -- let it go.
  le("whole-block overwrite: at most the inode sector is read", 1, r)
  local got = readAll(fs, "/whole")
  eq("whole-block overwrite: first block replaced", string.rep("Q", 512), got:sub(1, 512))
  eq("whole-block overwrite: second block kept", string.rep("q", 512), got:sub(513))
end

-- Block counts are now kept incrementally; they must agree with a walk.
do
  local st = blockfs.stats(d)
  test("stats still walk cleanly after incremental counting", st ~= nil and st.files >= 5)
  local res = blockfs.check(d)
  local real = {}
  for _, p in ipairs(res.problems) do
    if p ~= "volume was not cleanly unmounted" then real[#real + 1] = p end
  end
  eq("fsck: no structural problems (mounted volume, dirty flag aside)", 0, #real)
end

-- mkdir creates parents, like OpenComputers' managed filesystem.
do
  test("mkdir -p: nested path in one call", fs.makeDirectory("/p/q/r"))
  test("mkdir -p: every level exists", fs.isDirectory("/p") and fs.isDirectory("/p/q") and fs.isDirectory("/p/q/r"))
  test("mkdir -p: idempotent", fs.makeDirectory("/p/q/r"))
  writeFile(fs, "/p/file", "f")
  test("mkdir -p: refuses to tunnel through a file", not fs.makeDirectory("/p/file/sub"))
  test("mkdir -p: root is fine", fs.makeDirectory("/"))
end

-- rename into one's own subtree would orphan the whole tree.
do
  fs.makeDirectory("/tree/inner")
  writeFile(fs, "/tree/inner/leaf", "L")
  test("rename dir into itself refused", not fs.rename("/tree", "/tree/inner/tree"))
  test("rename dir onto itself is a no-op success", fs.rename("/tree", "/tree"))
  test("tree still reachable", fs.exists("/tree/inner/leaf"))
  test("rename a dir sideways still works", fs.rename("/tree", "/tree2"))
  test("...and the leaf moved with it", fs.exists("/tree2/inner/leaf") and not fs.exists("/tree"))
  test("rename prefix-similar dir is not 'inside'", fs.makeDirectory("/ab") and fs.rename("/ab", "/abc"))
end

-- Directory blocks stay cached; file data does not evict them.
do
  d.reset()
  fs.exists("/d/f11")
  local r1 = d.reset()
  readAll(fs, "/b64k")                     -- 128 data blocks stream past
  d.reset()
  fs.exists("/d/f11")
  local r2 = d.reset()
  le("a lookup after a big read costs no more than before it", r1, r2)
end

-- ═══════════════════════════════════════════════════════════════════
print()
print("-- a crash between the data and the metadata flush --")
-- Deferred bitmap/pointer writes land AFTER the data blocks. Kill the
-- drive partway through a 64 KB write and the volume must still pass
-- fsck's structural checks after a repair: nothing double-allocated,
-- nothing referenced-but-free. Leaked blocks are the allowed outcome.
do
  local dc = fakeDrive(512, 2048)
  blockfs.format(dc, { label = "crash" })
  local fc = blockfs.mount(dc)
  writeFile(fc, "/keep", string.rep("k", 3000))
  local before = readAll(fc, "/keep")
  dc.failAfterWrites = 40                   -- dies mid-way through the data blocks
  local h = fc.open("/victim", "w")
  local ok = pcall(fc.write, h, string.rep("v", 65536))
  test("the write raised when the drive vanished", not ok)
  dc.failAfterWrites = nil                  -- "power returns"

  local res = blockfs.check(dc, { repair = true })
  test("fsck --repair runs on the torn volume", res ~= nil and res.repaired)
  local after = blockfs.check(dc)
  eq("after repair: structurally clean", true, after.ok)
  local fc2 = blockfs.mount(dc)
  eq("the earlier file is intact", before, readAll(fc2, "/keep"))
  -- The victim either does not exist or is a consistent (short) file --
  -- never a file whose blocks belong to someone else.
  local v = fc2.exists("/victim") and readAll(fc2, "/victim") or ""
  test("the torn file, if present, holds only its own bytes",
       v == string.rep("v", #v))
  writeFile(fc2, "/later", string.rep("w", 10000))
  eq("writes after recovery work", string.rep("w", 10000), readAll(fc2, "/later"))
  eq("...and the earlier file is still intact", before, readAll(fc2, "/keep"))
  fc2.unmount()
  eq("clean after unmount", true, blockfs.check(dc).ok)
end

-- ═══════════════════════════════════════════════════════════════════
print()
print("-- the driver still fits its boot region --")
do
  local fh = io.open(blockfsPath, "rb"); local src = fh:read("*a"); fh:close()
  local blob = blockfs.bootBlob(src)
  le("boot blob fits the 64 KB region test_blockfs.lua formats", 64 * 1024 - 4, #blob)
  -- The pack ships this file unstripped, so its size is RAM on a 192 KB
  -- machine. A ceiling, so growth is a decision rather than drift.
  --! DECIDED 2026-09-10: 52 KB -> 54 KB. The ENOSPC fix (an allocation
  --! journal and a two-pass write) and deploy's pre-flight (blockfs.plan,
  --! blockfs.blocksFor) added ~2.4 KB of code. The comments that came with
  --! it were cut first and the code tightened; the remainder still did not
  --! fit, and the maintainer chose to raise the ceiling over golfing
  --! readable code. The larger lever is stripping the pack's Lua at build
  --! time, which would give back far more than this cost.
  le("driver source stays under 54 KB", 54 * 1024, #src)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
