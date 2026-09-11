-- ╔══════════════════════════════════════════════════════════════╗
-- ║  test_blockfs_enospc.lua — filling a volume must not leak       ║
-- ║                                                                ║
-- ║  A write that fails for want of space already returns false     ║
-- ║  rather than raising, which is right. What it does not do is    ║
-- ║  give back the blocks it had already allocated for that write:  ║
-- ║  they keep their used-bit with no inode referencing them, so    ║
-- ║  the volume quietly loses capacity that only fsck recovers.     ║
-- ║                                                                ║
-- ║  An operator has no reason to run fsck after a disk-full error, ║
-- ║  which is what makes this worth a test rather than a note.      ║
-- ║                                                                ║
-- ║  Run from the TOS-Extras root:                                  ║
-- ║    lua modules/blockfs/test_blockfs_enospc.lua                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Contributed with the 2026-09-10 follow-up review as the reproduction for
-- its §3. The "all-or-nothing" section at the end was added with the fix.

local SS       = 512
local CAP      = 256 * 1024     -- small on purpose: fills in ~30 writes
local CHUNK    = 8192           -- 16 blocks a go, so the leak is visible
local MAX_LOOP = 200            -- guard: never spin if writes stop failing

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

local clock = function() return 1 end
local drive = fakeDrive(CAP)

test("format", blockfs.format(drive, { label = "enospc", bootBytes = 0, now = clock }))
local p = assert(blockfs.mount(drive, { now = clock }))

-- ── Fill it ─────────────────────────────────────────────────────
local n, stopped = 0, nil
while n < MAX_LOOP do
  n = n + 1
  local h = p.open("/f" .. n, "w")
  if not h then stopped = "open returned nil"; break end
  local ok, ret = pcall(p.write, h, ("q"):rep(CHUNK))
  pcall(p.close, h)
  if not ok then stopped = "write raised: " .. tostring(ret); break end
  if ret == false then stopped = "write returned false"; break end
end

test("the volume filled within the loop guard", stopped ~= nil, "ran " .. n .. " writes")
test("a full volume fails cleanly rather than raising",
     stopped ~= nil and not stopped:find("raised"), stopped)
p.unmount()

-- ── The actual assertion ────────────────────────────────────────
local r = blockfs.check(drive, {})
test("no blocks leaked when the volume filled", r and r.ok,
     r and table.concat(r.problems, "; "))

-- Recoverable, so confirm repair works even while the leak stands.
-- If the assertion above starts passing this section stays valid; it
-- just has nothing left to reclaim.
local rep = blockfs.check(drive, { repair = true })
test("check --repair runs on the filled volume", rep ~= nil)
local again = blockfs.check(drive, {})
test("clean after repair", again and again.ok,
     again and table.concat(again.problems, "; "))

-- ══════════════════════════════════════════════════════════════════
-- All-or-nothing (added with the fix)
-- ══════════════════════════════════════════════════════════════════
--! The report asked for no leaked blocks. Fixing that exposed a second,
--! quieter fault in the same loop: it mapped and wrote one block at a time,
--! so a write that ran out of space had ALREADY overwritten every existing
--! block it passed on the way. A failed write into the middle of a file
--! left the front of the target range changed and the size unchanged --
--! data modified by a call that reported failure.
--!
--! OC's own managed filesystem checks capacity before it writes a byte.
--! These pin that TBFS now does the same, and that the handle whose write
--! failed is still coherent: free some space and the SAME write succeeds.
print()
print("-- all-or-nothing --")
do
  local function readAll(fsP, path)
    local h = fsP.open(path, "r"); if not h then return nil end
    local out, c = {}, nil
    repeat c = fsP.read(h, 4096); if c then out[#out + 1] = c end until not c
    fsP.close(h)
    return table.concat(out)
  end

  -- 64 KB with enough inodes that the volume runs out of SPACE, not of
  -- inodes: at the default ratio it would have only 16.
  local d2 = fakeDrive(64 * 1024)
  test("second volume formats",
    blockfs.format(d2, { label = "aon", bootBytes = 0, inodeRatio = 1024, now = clock }))
  local q = assert(blockfs.mount(d2, { now = clock }))

  -- A file that already spans the direct slots and one indirect block.
  local KEEP = string.rep("k", 6000)
  local kh = q.open("/keep", "w"); q.write(kh, KEEP); q.close(kh)

  -- Fill the rest, and learn WHY it stopped.
  local fills, why = 0, nil
  for i = 1, 400 do
    local fh = q.open("/fill" .. i, "w")
    if not fh then why = "open"; break end
    local ok = q.write(fh, string.rep("f", 2048))
    q.close(fh)
    if not ok then why = "space"; break end
    fills = i
  end
  test("the volume filled on space, not inodes", why == "space", why)

  local usedBefore = q.spaceUsed()
  -- Overwrite the LAST 100 bytes of /keep and extend it 8 KB past the end.
  -- The first block it touches exists; the rest have to be allocated and
  -- cannot be.
  local wh = q.open("/keep", "a")
  q.seek(wh, "set", #KEEP - 100)
  local ok = q.write(wh, string.rep("N", 8000))
  test("the overwrite-and-extend write reports failure", ok == false)
  test("the bytes it would have overwritten are untouched",
    readAll(q, "/keep") == KEEP,
    "last 100 now: " .. tostring((readAll(q, "/keep") or ""):sub(-100, -91)) .. "...")
  test("...the size did not move", q.size("/keep") == #KEEP, q.size("/keep"))
  test("...and it cost no space", q.spaceUsed() == usedBefore,
    usedBefore .. " -> " .. q.spaceUsed())

  -- Free five 4-block fills (20 blocks; the write needs 16) and retry on
  -- the SAME handle. Its in-memory node went through the rollback, so this
  -- is the check that the rollback left it coherent, not merely freed.
  for i = 1, 5 do q.remove("/fill" .. i) end
  local ok2 = q.write(wh, string.rep("N", 8000))
  q.close(wh)
  test("the same write succeeds on the same handle once space is freed", ok2 == true)
  test("...and lands exactly where it was aimed",
    readAll(q, "/keep") == KEEP:sub(1, #KEEP - 100) .. string.rep("N", 8000))
  q.unmount()

  local r3 = blockfs.check(d2, {})
  test("fsck clean after fail-then-retry", r3 and r3.ok,
    r3 and table.concat(r3.problems, "; "))
end

print(("\nResults: %d passed, %d failed"):format(total - failed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
