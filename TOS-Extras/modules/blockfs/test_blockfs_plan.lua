-- ╔══════════════════════════════════════════════════════════════╗
-- ║  test_blockfs_plan.lua — the two numbers `deploy drive` trusts  ║
-- ║                                                                ║
-- ║  `deploy drive` decides whether to ERASE a drive from two      ║
-- ║  pure functions: blockfs.plan (the layout format() will lay     ║
-- ║  down) and blockfs.blocksFor (what one file costs, including    ║
-- ║  its indirect pointer blocks). A wrong answer from either is    ║
-- ║  a drive wiped for an install that then does not fit, so each   ║
-- ║  is checked against the REAL thing — format's on-disk layout    ║
-- ║  and the allocator's actual consumption — never against a       ║
-- ║  second copy of its own arithmetic.                             ║
-- ║                                                                ║
-- ║  Run from the TOS-Extras root:                                  ║
-- ║    lua modules/blockfs/test_blockfs_plan.lua                    ║
-- ╚══════════════════════════════════════════════════════════════╝

local SS = 512

local function findUp(rel)
  for _, base in ipairs({ "modules/blockfs/usr/lib/", "../TOS-Extras/modules/blockfs/usr/lib/",
                          "TOS-Extras/modules/blockfs/usr/lib/", "usr/lib/", "" }) do
    local f = io.open(base .. rel, "r")
    if f then local s = f:read("a"); f:close(); return s end
  end
end
local src = findUp("blockfs.lua")
if not src then print("blockfs.lua not found"); os.exit(1) end
local blockfs = assert(load(src, "=blockfs.lua", "t"))()

local function fakeDrive(cap)
  local sectors = {}
  return {
    getSectorSize = function() return SS end,
    getCapacity   = function() return cap end,
    readSector    = function(i) return sectors[i] or string.rep("\0", SS) end,
    writeSector   = function(i, d) sectors[i] = d end,
  }
end

local total, failed = 0, 0
local function test(name, cond, detail)
  total = total + 1
  if cond then print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or "")) end
end
local function eq(name, want, got) test(name, want == got, "want " .. tostring(want) .. ", got " .. tostring(got)) end
local clock = function() return 1 end

print("=== blockfs.plan / blockfs.blocksFor ===")

test("plan is exported", type(blockfs.plan) == "function")
test("blocksFor is exported", type(blockfs.blocksFor) == "function")

-- ── 1. plan() is exactly the layout format() writes ─────────────────
print("\n-- plan vs format --")
for _, c in ipairs({
  { cap = 64 * 1024 },
  { cap = 1024 * 1024 },
  { cap = 2 * 1024 * 1024 },
  { cap = 1024 * 1024, inodeRatio = 512 },          -- deploy's resized table
  { cap = 2 * 1024 * 1024, bootBytes = 40000 },      -- a bootable volume
}) do
  local label = string.format("%dKB%s%s", c.cap // 1024,
    c.inodeRatio and (" ratio " .. c.inodeRatio) or "",
    c.bootBytes and (" boot " .. c.bootBytes) or "")
  local d = fakeDrive(c.cap)
  local L = blockfs.plan(d, c)
  test(label .. ": plans", L ~= nil)
  if L then
    test(label .. ": format succeeds",
      blockfs.format(d, { label = "p", now = clock, inodeRatio = c.inodeRatio,
                          bootBytes = c.bootBytes }))
    local st = blockfs.stats(d, {})
    eq(label .. ": data blocks match what format laid down", st.dataBlocks, L.dataBlocks)
    eq(label .. ": inode count matches", st.inodeCount, L.inodeCount)
    eq(label .. ": a fresh volume's free blocks are ALL its data blocks",
      st.freeBlocks, L.dataBlocks)
  end
end

-- plan() refuses exactly where format() does, so a pre-flight that passes
-- cannot be followed by a format that fails.
do
  local tiny = fakeDrive(2 * SS)
  test("a drive too small to plan says so", blockfs.plan(tiny, {}) == nil)
  test("...and format refuses it too", blockfs.format(fakeDrive(2 * SS), {}) == false)
  local d = fakeDrive(64 * 1024)
  test("a boot region that swallows the drive is refused by plan",
    blockfs.plan(d, { bootBytes = 64 * 1024 }) == nil)
  test("...and by format", blockfs.format(fakeDrive(64 * 1024), { bootBytes = 64 * 1024 }) == false)
  local more = blockfs.plan(fakeDrive(1024 * 1024), { inodeRatio = 512 })
  local less = blockfs.plan(fakeDrive(1024 * 1024), {})
  test("a smaller inodeRatio buys more inodes", more.inodeCount > less.inodeCount)
  test("...and pays for them in data blocks", more.dataBlocks < less.dataBlocks)
end

-- ── 2. blocksFor() is what the allocator really takes ───────────────
-- Sizes chosen at every mapping-tier edge: 8 direct slots (4096 B), the
-- first single-indirect block (4097), the last single-indirect slot
-- (8 + 128 blocks = 69632), the first double-indirect (69633), and one
-- that needs several double-indirect mid blocks (300000).
print("\n-- blocksFor vs the allocator --")
do
  local d = fakeDrive(4 * 1024 * 1024)
  blockfs.format(d, { label = "b", now = clock })
  local p = assert(blockfs.mount(d, { now = clock }))
  for _, n in ipairs({ 0, 1, 511, 512, 513, 4096, 4097, 69632, 69633, 100000, 300000 }) do
    local path = "/f" .. n
    local h = p.open(path, "w")        -- creates the file AND its directory entry
    local before = p.spaceUsed()       -- ...so the entry is not counted below
    if n > 0 then p.write(h, string.rep("x", n)) end
    p.close(h)
    local took = (p.spaceUsed() - before) // SS
    eq(string.format("%6d bytes: blocksFor matches the allocator", n), took, blockfs.blocksFor(n, SS))
  end
  p.unmount()
end

print(("\nResults: %d passed, %d failed"):format(total - failed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
