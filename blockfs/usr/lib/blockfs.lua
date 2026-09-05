-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TBFS - TOS Block File System (driver for UNMANAGED drives)    ║
-- ║                                                                ║
-- ║  OpenComputers drives come in two flavours. A *managed* disk   ║
-- ║  is a `filesystem` component: it hands you open/read/write/     ║
-- ║  list already. An *unmanaged* disk is a raw `drive` component:  ║
-- ║  readSector/writeSector/getSectorSize/getCapacity and nothing  ║
-- ║  else - no files, no directories. To use one for storage you   ║
-- ║  must lay a filesystem down on the bare sectors yourself.      ║
-- ║                                                                 ║
-- ║  This library IS that filesystem. Given a raw drive proxy it   ║
-- ║  formats, checks, defragments, and - the payoff - returns a     ║
-- ║  proxy that speaks the EXACT managed-filesystem interface TOS   ║
-- ║  already mounts (exists/isDirectory/list/makeDirectory/remove/  ║
-- ║  rename/size/lastModified/open/read/write/close/seek/           ║
-- ║  spaceTotal/spaceUsed/getLabel/setLabel/isReadOnly). So once    ║
-- ║  mounted, securefs, the panels browser, cp, everything works    ║
-- ║  on it unmodified.                                              ║
-- ║                                                                 ║
-- ║  It is PURE: the only thing it touches is the drive proxy you   ║
-- ║  pass in (readSector/writeSector/getSectorSize/getCapacity),    ║
-- ║  so it unit-tests off-box against a table-backed fake drive.    ║
-- ║                                                                 ║
-- ║  ── On-disk layout (TBFS v1) ──                                 ║
-- ║    block 0            superblock                                ║
-- ║    bitmap region      1 bit per block (free/used)              ║
-- ║    inode region       fixed inode table                        ║
-- ║    data region        file + directory blocks                  ║
-- ║  A block is one sector. Files map logical→physical blocks via   ║
-- ║  8 direct + 1 single-indirect + 1 double-indirect pointer, so   ║
-- ║  a single file scales into the megabytes. Directories are just  ║
-- ║  files whose data is a list of {name, inode} entries.          ║
-- ╚══════════════════════════════════════════════════════════════╝

local blockfs = {}
blockfs._VERSION = "1.0.0"

local MAGIC        = "TBFS"
local FMT_VERSION  = 1
local INODE_SIZE   = 64          -- bytes per inode record
local N_DIRECT     = 8           -- direct block pointers in an inode
local T_FREE, T_FILE, T_DIR = 0, 1, 2
local NAME_MAX     = 48          -- longest directory-entry name
local ROOT_INODE   = 1           -- inode 0 is reserved (== "nil pointer")

-- ============================================================
-- Low-level drive I/O (whole-block reads/writes)
-- ============================================================
-- The drive proxy is the OC unmanaged `drive` component (readSector/
-- writeSector are 1-indexed in OC). We wrap it so the rest of the code
-- speaks in 0-indexed block numbers and never worries about padding.

local function driveGeom(drive)
  local ss = drive.getSectorSize and drive.getSectorSize() or 512
  local cap = drive.getCapacity and drive.getCapacity() or (ss * 1024)
  ss = math.max(64, math.floor(ss))
  local blocks = math.floor(cap / ss)
  return ss, blocks
end

-- Read block b (0-indexed) as an ss-byte string.
-- ============================================================
-- Block cache
-- ============================================================
--! MEASURED, not guessed. Writing one 8 KB file cost 219 sector reads
--! for 16 blocks of data, and TWO sectors were 89% of them: the file's
--! inode block, re-read 144 times, and the allocation bitmap, re-read 50
--! times. Both are read-modify-write per operation -- bitGet/bitSet
--! re-read the same bitmap sector for every single bit tested, and one
--! bitmap sector covers ss*8 blocks, so a scan can re-read one sector
--! thousands of times.
--!
--! WRITE-THROUGH, never write-back. The cached copy is updated at the
--! moment the drive is, so a machine that stops mid-operation -- which
--! here means someone broke the computer block -- never loses data a
--! caller was told had been written. Write-back would be faster again
--! and is the wrong trade on hardware that can vanish mid-write.
--!
--! Four slots: 4 * 512 B = 2 KB, roughly 1% of a Tier 1 machine's RAM.
--! The hot set is genuinely tiny -- one inode block, one bitmap block,
--! one directory block -- so more slots would buy almost nothing.
--!
--! Safe only because of two facts about this file: every write goes
--! through writeBlock (the single writeSector call), and the only read
--! that bypasses readBlock is the superblock at mount time, before an fs
--! handle exists. If either stops being true, this becomes a corruption
--! bug rather than a speedup.
local CACHE_SLOTS = 4

local function cachePut(fs, b, data)
  local c = fs.cache
  if not c then return end
  local e = c.map[b]
  c.tick = c.tick + 1
  if e then e.data, e.used = data, c.tick; return end
  if c.n >= CACHE_SLOTS then
    local oldest, oldestUsed
    for blk, ent in pairs(c.map) do
      if not oldestUsed or ent.used < oldestUsed then oldest, oldestUsed = blk, ent.used end
    end
    if oldest then c.map[oldest] = nil; c.n = c.n - 1 end
  end
  c.map[b] = { data = data, used = c.tick }
  c.n = c.n + 1
end

local function readBlock(fs, b)
  if b < 0 or b >= fs.totalBlocks then
    error("readBlock out of range: " .. tostring(b), 2)
  end
  local c = fs.cache
  if c then
    local e = c.map[b]
    if e then c.tick = c.tick + 1; e.used = c.tick; return e.data end
  end
  local s = fs.drive.readSector(b + 1)          -- OC sectors are 1-indexed
  if type(s) ~= "string" then s = "" end
  if #s < fs.ss then s = s .. string.rep("\0", fs.ss - #s) end
  s = s:sub(1, fs.ss)
  cachePut(fs, b, s)
  return s
end

-- Write an ss-byte block (data is padded/truncated to the sector).
local function writeBlock(fs, b, data)
  if b < 0 or b >= fs.totalBlocks then
    error("writeBlock out of range: " .. tostring(b), 2)
  end
  if #data < fs.ss then data = data .. string.rep("\0", fs.ss - #data)
  elseif #data > fs.ss then data = data:sub(1, fs.ss) end
  fs.drive.writeSector(b + 1, data)
  --! Through, not back: the drive already has it before the cache does.
  cachePut(fs, b, data)
end

-- ============================================================
-- Superblock
-- ============================================================

-- Superblock layout. bootStart/bootBlocks describe an optional CONTIGUOUS
-- boot region (super | bitmap | inodes | BOOT | data) holding a stage-2
-- boot blob — this is what lets an unmanaged drive be BOOTABLE: the
-- tiny EEPROM reads this contiguous run and runs it (no in-EEPROM TBFS
-- parser needed). bootBlocks == 0 means a normal, non-bootable volume.
local function packSuper(sb)
  local label = (sb.label or ""):sub(1, 32)
  return string.pack("<c4 I1 I2 I4 I4 I4 I4 I4 I4 I4 I4 I4 I4 I1 s2",
    MAGIC, FMT_VERSION, sb.ss, sb.totalBlocks,
    sb.bitmapStart, sb.bitmapBlocks,
    sb.inodeStart, sb.inodeCount, sb.inodeBlocks,
    sb.bootStart or 0, sb.bootBlocks or 0,
    sb.dataStart, sb.freeBlocks, sb.clean and 1 or 0, label)
end

local function unpackSuper(raw)
  local ok, magic, ver, ss, tb, bmS, bmB, inS, inC, inB, btS, btB, dS, fb, clean, label =
    pcall(string.unpack, "<c4 I1 I2 I4 I4 I4 I4 I4 I4 I4 I4 I4 I4 I1 s2", raw)
  if not ok or magic ~= MAGIC then return nil, "not a TBFS volume" end
  if ver ~= FMT_VERSION then return nil, "unsupported TBFS version " .. tostring(ver) end
  return {
    ss = ss, totalBlocks = tb, bitmapStart = bmS, bitmapBlocks = bmB,
    inodeStart = inS, inodeCount = inC, inodeBlocks = inB,
    bootStart = btS, bootBlocks = btB,
    dataStart = dS, freeBlocks = fb, clean = (clean == 1), label = label,
  }
end

local function writeSuper(fs)
  writeBlock(fs, 0, packSuper({
    ss = fs.ss, totalBlocks = fs.totalBlocks,
    bitmapStart = fs.bitmapStart, bitmapBlocks = fs.bitmapBlocks,
    inodeStart = fs.inodeStart, inodeCount = fs.inodeCount,
    inodeBlocks = fs.inodeBlocks, bootStart = fs.bootStart, bootBlocks = fs.bootBlocks,
    dataStart = fs.dataStart, freeBlocks = fs.freeBlocks, clean = fs.clean, label = fs.label,
  }))
end

-- ============================================================
-- Block bitmap (1 bit per block; bit set == used)
-- ============================================================

local function bitmapByte(fs, blk)
  local bitIndex = blk
  local byteIndex = bitIndex >> 3
  local blkOfBitmap = fs.bitmapStart + (byteIndex // fs.ss)
  local offInBlk = byteIndex % fs.ss
  return blkOfBitmap, offInBlk, (bitIndex & 7)
end

local function bitGet(fs, blk)
  local bb, off, bit = bitmapByte(fs, blk)
  local sector = readBlock(fs, bb)
  local byte = sector:byte(off + 1) or 0
  return (byte >> bit) & 1
end

local function bitSet(fs, blk, val)
  local bb, off, bit = bitmapByte(fs, blk)
  local sector = readBlock(fs, bb)
  local byte = sector:byte(off + 1) or 0
  if val == 1 then byte = byte | (1 << bit) else byte = byte & (~(1 << bit) & 0xFF) end
  writeBlock(fs, bb, sector:sub(1, off) .. string.char(byte) .. sector:sub(off + 2))
end

-- Layout-aware allocation: prefer `near`+1 (keep a file's blocks
-- contiguous → the simulated head doesn't seek), else the nearest free
-- block scanning outward from the last-served cursor. Marks it used,
-- decrements the free count, and returns the block number (or nil).
local function allocBlock(fs, near)
  if fs.freeBlocks <= 0 then return nil end
  local first, last = fs.dataStart, fs.totalBlocks - 1
  local function tryTake(b)
    if b >= first and b <= last and bitGet(fs, b) == 0 then
      bitSet(fs, b, 1); fs.freeBlocks = fs.freeBlocks - 1; fs.allocHint = b
      return b
    end
    return nil
  end
  if near and tryTake(near + 1) then return near + 1 end
  local start = fs.allocHint or first
  for b = start, last do local t = tryTake(b); if t then return t end end
  for b = first, start - 1 do local t = tryTake(b); if t then return t end end
  return nil
end

local function freeBlock(fs, b)
  if b == 0 then return end
  if bitGet(fs, b) == 1 then
    bitSet(fs, b, 0); fs.freeBlocks = fs.freeBlocks + 1
  end
end

-- ============================================================
-- Inodes
-- ============================================================
-- Record: type(1) flags(1) size(4) mtime(4) blocks(4) direct[8]*4
--         indirect(4) doubleIndirect(4)  = 1+1+4+4+4+32+4+4 = 54, pad 64.

local function inodeLoc(fs, ino)
  local perBlock = fs.ss // INODE_SIZE
  local idx = ino                      -- inode 0 reserved; array is dense
  local blk = fs.inodeStart + (idx // perBlock)
  local off = (idx % perBlock) * INODE_SIZE
  return blk, off
end

local function readInode(fs, ino)
  local blk, off = inodeLoc(fs, ino)
  local sector = readBlock(fs, blk)
  local rec = sector:sub(off + 1, off + INODE_SIZE)
  local t, flags, size, mtime, blocks = string.unpack("<I1 I1 I4 I4 I4", rec)
  local direct = {}
  local p = 15                          -- byte offset after the 14-byte header
  for i = 1, N_DIRECT do
    direct[i] = string.unpack("<I4", rec, p); p = p + 4
  end
  local indirect = string.unpack("<I4", rec, p); p = p + 4
  local double = string.unpack("<I4", rec, p)
  return { num = ino, type = t, flags = flags, size = size, mtime = mtime,
           blocks = blocks, direct = direct, indirect = indirect, double = double }
end

local function writeInode(fs, node)
  local parts = { string.pack("<I1 I1 I4 I4 I4",
    node.type, node.flags or 0, node.size or 0, node.mtime or 0, node.blocks or 0) }
  for i = 1, N_DIRECT do parts[#parts + 1] = string.pack("<I4", node.direct[i] or 0) end
  parts[#parts + 1] = string.pack("<I4", node.indirect or 0)
  parts[#parts + 1] = string.pack("<I4", node.double or 0)
  local rec = table.concat(parts)
  rec = rec .. string.rep("\0", INODE_SIZE - #rec)
  local blk, off = inodeLoc(fs, node.num)
  local sector = readBlock(fs, blk)
  writeBlock(fs, blk, sector:sub(1, off) .. rec:sub(1, INODE_SIZE) .. sector:sub(off + INODE_SIZE + 1))
end

local function allocInode(fs, itype)
  for ino = ROOT_INODE, fs.inodeCount - 1 do
    local n = readInode(fs, ino)
    if n.type == T_FREE then
      local fresh = { num = ino, type = itype, flags = 0, size = 0,
        mtime = fs.now(), blocks = 0, direct = {}, indirect = 0, double = 0 }
      for i = 1, N_DIRECT do fresh.direct[i] = 0 end
      writeInode(fs, fresh)
      return fresh
    end
  end
  return nil
end

-- ============================================================
-- Logical → physical block mapping (direct / indirect / double)
-- ============================================================
local function ppb(fs) return fs.ss // 4 end     -- pointers per block

local function readPtr(fs, blk, slot)
  local sector = readBlock(fs, blk)
  return (string.unpack("<I4", sector, slot * 4 + 1))
end
local function writePtr(fs, blk, slot, val)
  local sector = readBlock(fs, blk)
  local at = slot * 4
  writeBlock(fs, blk, sector:sub(1, at) .. string.pack("<I4", val) .. sector:sub(at + 5))
end

-- Physical block backing logical file-block `li`; when `alloc`, grows
-- the file (allocating indirect blocks as needed) and keeps blocks near
-- each other for a defrag-friendly, seek-cheap layout. Returns block#|nil.
local function mapBlock(fs, node, li, alloc)
  local P = ppb(fs)
  local function near() return fs.allocHint end
  if li < N_DIRECT then
    if node.direct[li + 1] == 0 and alloc then
      local b = allocBlock(fs, li > 0 and node.direct[li] ~= 0 and node.direct[li] or near())
      if not b then return nil end
      node.direct[li + 1] = b; node._dirty = true
    end
    local d = node.direct[li + 1]
    return d ~= 0 and d or nil
  end
  li = li - N_DIRECT
  if li < P then                                   -- single indirect
    if node.indirect == 0 then
      if not alloc then return nil end
      local ib = allocBlock(fs, near()); if not ib then return nil end
      writeBlock(fs, ib, string.rep("\0", fs.ss)); node.indirect = ib; node._dirty = true
    end
    local phys = readPtr(fs, node.indirect, li)
    if phys == 0 and alloc then
      phys = allocBlock(fs, node.indirect); if not phys then return nil end
      writePtr(fs, node.indirect, li, phys)
    end
    return phys ~= 0 and phys or nil
  end
  li = li - P
  if li < P * P then                               -- double indirect
    if node.double == 0 then
      if not alloc then return nil end
      local db = allocBlock(fs, near()); if not db then return nil end
      writeBlock(fs, db, string.rep("\0", fs.ss)); node.double = db; node._dirty = true
    end
    local l1, l2 = li // P, li % P
    local mid = readPtr(fs, node.double, l1)
    if mid == 0 then
      if not alloc then return nil end
      mid = allocBlock(fs, node.double); if not mid then return nil end
      writeBlock(fs, mid, string.rep("\0", fs.ss)); writePtr(fs, node.double, l1, mid)
    end
    local phys = readPtr(fs, mid, l2)
    if phys == 0 and alloc then
      phys = allocBlock(fs, mid); if not phys then return nil end
      writePtr(fs, mid, l2, phys)
    end
    return phys ~= 0 and phys or nil
  end
  return nil   -- beyond double-indirect reach (multi-MB file)
end

-- Visit every physical block a file owns (data + indirect metadata),
-- calling fn(block, kind) where kind is "data"|"meta". Used by free,
-- fsck, and defrag.
local function walkBlocks(fs, node, fn)
  local P = ppb(fs)
  local nblk = node.blocks
  local li = 0
  for i = 1, N_DIRECT do
    if node.direct[i] ~= 0 then fn(node.direct[i], "data") end
  end
  if node.indirect ~= 0 then
    fn(node.indirect, "meta")
    for s = 0, P - 1 do
      local p = readPtr(fs, node.indirect, s)
      if p ~= 0 then fn(p, "data") end
    end
  end
  if node.double ~= 0 then
    fn(node.double, "meta")
    for l1 = 0, P - 1 do
      local mid = readPtr(fs, node.double, l1)
      if mid ~= 0 then
        fn(mid, "meta")
        for l2 = 0, P - 1 do
          local p = readPtr(fs, mid, l2)
          if p ~= 0 then fn(p, "data") end
        end
      end
    end
  end
  return nblk, li
end

local function freeInodeBlocks(fs, node)
  walkBlocks(fs, node, function(b) freeBlock(fs, b) end)
  node.blocks = 0; node.size = 0
  for i = 1, N_DIRECT do node.direct[i] = 0 end
  node.indirect = 0; node.double = 0
end

-- ============================================================
-- File data read / write (byte ranges over the block map)
-- ============================================================

local function readData(fs, node, offset, count)
  if offset >= node.size then return "" end
  count = math.min(count, node.size - offset)
  local out = {}
  local pos = offset
  while count > 0 do
    local li = pos // fs.ss
    local within = pos % fs.ss
    local phys = mapBlock(fs, node, li, false)
    local chunk
    if phys then
      chunk = readBlock(fs, phys):sub(within + 1, within + math.min(count, fs.ss - within))
    else
      chunk = string.rep("\0", math.min(count, fs.ss - within))   -- sparse hole
    end
    out[#out + 1] = chunk
    local n = #chunk
    if n == 0 then break end
    pos = pos + n; count = count - n
  end
  return table.concat(out)
end

local function writeData(fs, node, offset, data)
  local pos = offset
  local i = 1
  local n = #data
  while i <= n do
    local li = pos // fs.ss
    local within = pos % fs.ss
    local phys = mapBlock(fs, node, li, true)
    if not phys then return false, "out of space" end
    local room = fs.ss - within
    local chunk = data:sub(i, i + room - 1)
    local sector = readBlock(fs, phys)
    writeBlock(fs, phys, sector:sub(1, within) .. chunk .. sector:sub(within + #chunk + 1))
    -- Recount owned blocks lazily via the high-water mark below.
    pos = pos + #chunk; i = i + #chunk
  end
  if pos > node.size then node.size = pos end
  -- Recompute block count (cheap: derive from size for the fast path).
  local nb = 0
  walkBlocks(fs, node, function() nb = nb + 1 end)
  node.blocks = nb
  node.mtime = fs.now()
  return true
end

-- ============================================================
-- Directories (a directory file is a list of entries)
-- ============================================================
-- Entry: nameLen(1) name(nameLen) inode(4). Packed back-to-back in the
-- directory's data. A zero-length name marks a tombstone (deleted slot).

local function dirEntries(fs, dnode)
  local raw = readData(fs, dnode, 0, dnode.size)
  local list, p = {}, 1
  while p + 5 <= #raw + 1 do
    local nl = raw:byte(p); if not nl then break end
    local name = raw:sub(p + 1, p + nl)
    local ino = string.unpack("<I4", raw, p + 1 + nl)
    if nl > 0 then list[#list + 1] = { name = name, inode = ino, off = p - 1 } end
    p = p + 1 + nl + 4
  end
  return list
end

local function dirLookup(fs, dnode, name)
  for _, e in ipairs(dirEntries(fs, dnode)) do
    if e.name == name then return e.inode, e.off end
  end
  return nil
end

local function dirAdd(fs, dnode, name, ino)
  -- Reload the directory inode fresh: two resolve() results for the same
  -- directory are SEPARATE in-memory copies, so a caller (e.g. rename,
  -- where source and dest share a parent) could otherwise hold a stale
  -- copy whose write-back clobbers an entry another copy just added.
  dnode = readInode(fs, dnode.num)
  if #name > NAME_MAX then return false, "name too long" end
  if dirLookup(fs, dnode, name) then return false, "exists" end
  local rec = string.char(#name) .. name .. string.pack("<I4", ino)
  local ok, err = writeData(fs, dnode, dnode.size, rec)
  if not ok then return false, err end
  writeInode(fs, dnode)
  return true
end

-- Remove an entry by rewriting the directory without it (keeps the
-- format simple and the on-disk data compact — no tombstone accrual).
local function dirRemove(fs, dnode, name)
  dnode = readInode(fs, dnode.num)     -- fresh copy (see dirAdd)
  local kept = {}
  for _, e in ipairs(dirEntries(fs, dnode)) do
    if e.name ~= name then kept[#kept + 1] = e end
  end
  freeInodeBlocks(fs, dnode)
  dnode.size = 0
  for _, e in ipairs(kept) do
    local rec = string.char(#e.name) .. e.name .. string.pack("<I4", e.inode)
    writeData(fs, dnode, dnode.size, rec)
  end
  writeInode(fs, dnode)
  return true
end

-- ============================================================
-- Path resolution
-- ============================================================

local function splitPath(path)
  local parts = {}
  for seg in tostring(path or ""):gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil
    elseif seg ~= "." and seg ~= "" then parts[#parts + 1] = seg end
  end
  return parts
end

-- Resolve to (inode-number, node) or nil. Also returns the parent dir
-- node and the final path segment, so callers can create/remove.
local function resolve(fs, path)
  local parts = splitPath(path)
  local cur = readInode(fs, ROOT_INODE)
  local parent, leaf = cur, nil
  for i, seg in ipairs(parts) do
    if cur.type ~= T_DIR then return nil, nil, nil, "not a directory" end
    parent = cur; leaf = seg
    local ino = dirLookup(fs, cur, seg)
    if not ino then
      if i == #parts then return nil, parent, leaf end      -- missing leaf
      return nil, nil, nil, "no such path"
    end
    cur = readInode(fs, ino)
  end
  return cur, parent, leaf
end

-- ============================================================
-- Format
-- ============================================================

--- Lay a fresh TBFS onto a raw drive. opts = { label, inodeRatio,
--- bootBytes }. inodeRatio = data-bytes per inode (default 4 KB).
--- bootBytes > 0 reserves a contiguous BOOT region of that many bytes
--- (rounded up to a sector) between the inode table and the data region,
--- making the volume bootable (see blockfs.writeBoot). Default 0.
function blockfs.format(drive, opts)
  opts = opts or {}
  local ss, totalBlocks = driveGeom(drive)
  if totalBlocks < 8 then return false, "drive too small for TBFS" end

  local bitmapBlocks = math.max(1, math.ceil(totalBlocks / (ss * 8)))
  local cap = ss * totalBlocks
  local inodeCount = math.max(16, math.floor(cap / (opts.inodeRatio or 4096)))
  local perBlock = ss // INODE_SIZE
  local inodeBlocks = math.max(1, math.ceil(inodeCount / perBlock))
  inodeCount = inodeBlocks * perBlock

  local bootBlocks = 0
  if opts.bootBytes and opts.bootBytes > 0 then
    bootBlocks = math.ceil(opts.bootBytes / ss)
  end

  local bitmapStart = 1
  local inodeStart  = bitmapStart + bitmapBlocks
  local bootStart   = inodeStart + inodeBlocks
  local dataStart   = bootStart + bootBlocks
  if dataStart >= totalBlocks then return false, "drive too small for metadata + boot region" end

  local fs = {
    drive = drive, ss = ss, totalBlocks = totalBlocks,
    bitmapStart = bitmapStart, bitmapBlocks = bitmapBlocks,
    inodeStart = inodeStart, inodeCount = inodeCount, inodeBlocks = inodeBlocks,
    bootStart = bootStart, bootBlocks = bootBlocks,
    dataStart = dataStart, freeBlocks = 0, clean = true,
    label = (opts.label or "tbfs"):sub(1, 32),
    now = opts.now or function() return 0 end, allocHint = dataStart,
  }

  -- Zero metadata (superblock + bitmap + inode table).
  for b = 0, dataStart - 1 do writeBlock(fs, b, string.rep("\0", ss)) end
  -- Mark metadata blocks used in the bitmap; data blocks free.
  fs.freeBlocks = totalBlocks - dataStart
  for b = 0, dataStart - 1 do bitSet(fs, b, 1) end
  -- Root directory inode (empty).
  local root = { num = ROOT_INODE, type = T_DIR, flags = 0, size = 0,
    mtime = fs.now(), blocks = 0, direct = {}, indirect = 0, double = 0 }
  for i = 1, N_DIRECT do root.direct[i] = 0 end
  writeInode(fs, root)
  writeSuper(fs)
  return true
end

-- ============================================================
-- Open a formatted volume → the in-memory fs handle
-- ============================================================

local function openVolume(drive, opts)
  opts = opts or {}
  local raw = drive.readSector(1)
  if type(raw) ~= "string" then return nil, "cannot read drive" end
  local sb, err = unpackSuper(raw)
  if not sb then return nil, err end
  local fs = {
    --! Created here so it lives and dies with the handle: unmounting
    --! or reformatting drops it, and there is no global to go stale.
    cache = { map = {}, n = 0, tick = 0 },
    drive = drive, ss = sb.ss, totalBlocks = sb.totalBlocks,
    bitmapStart = sb.bitmapStart, bitmapBlocks = sb.bitmapBlocks,
    inodeStart = sb.inodeStart, inodeCount = sb.inodeCount,
    inodeBlocks = sb.inodeBlocks, bootStart = sb.bootStart, bootBlocks = sb.bootBlocks,
    dataStart = sb.dataStart, freeBlocks = sb.freeBlocks, clean = sb.clean, label = sb.label,
    now = opts.now or function() return 0 end, allocHint = sb.dataStart,
  }
  return fs
end

-- ============================================================
-- The managed-filesystem proxy (what TOS mounts)
-- ============================================================

--- Build the OC-`filesystem`-shaped proxy over a formatted drive.
--- Returns (proxy, fs) or (nil, err).
function blockfs.mount(drive, opts)
  local fs, err = openVolume(drive, opts)
  if not fs then return nil, err end
  fs.clean = false; writeSuper(fs)          -- mark dirty until a clean unmount
  local handles, nextH = {}, 1

  local function nodeAt(path)
    local node = select(1, resolve(fs, path))
    return node
  end

  local P = {}

  -- Component-proxy shape: expose the underlying drive's address (and the
  -- filesystem type tag) so consumers can treat the root like any managed
  -- FS proxy. init.lua's _TOS.bootAddr reads .address — without it the
  -- shell's auto-mount gate (#SEC H26, fail-closed) would silently refuse
  -- every inserted disk on a TBFS-booted box.
  P.address = drive.address
  P.type = "filesystem"

  function P.getLabel() return fs.label end
  function P.setLabel(name)
    fs.label = tostring(name or ""):sub(1, 32); writeSuper(fs); return fs.label
  end
  function P.isReadOnly() return false end
  function P.spaceTotal() return (fs.totalBlocks - fs.dataStart) * fs.ss end
  function P.spaceUsed()
    return ((fs.totalBlocks - fs.dataStart) - fs.freeBlocks) * fs.ss
  end

  function P.exists(path) return nodeAt(path) ~= nil end

  function P.isDirectory(path)
    local n = nodeAt(path); return n ~= nil and n.type == T_DIR
  end

  function P.size(path)
    local n = nodeAt(path); return (n and n.type == T_FILE) and n.size or 0
  end

  function P.lastModified(path)
    local n = nodeAt(path); return n and n.mtime or 0
  end

  function P.list(path)
    local n = nodeAt(path)
    if not n or n.type ~= T_DIR then return {} end
    local out = {}
    for _, e in ipairs(dirEntries(fs, n)) do
      local child = readInode(fs, e.inode)
      out[#out + 1] = e.name .. (child.type == T_DIR and "/" or "")
    end
    return out
  end

  function P.makeDirectory(path)
    local node, parent, leaf = resolve(fs, path)
    if node then return node.type == T_DIR end          -- already exists
    if not parent or not leaf then return false end
    local dir = allocInode(fs, T_DIR)
    if not dir then return false end
    local ok = dirAdd(fs, parent, leaf, dir.num)
    if not ok then dir.type = T_FREE; writeInode(fs, dir); return false end
    writeSuper(fs)
    return true
  end

  function P.remove(path)
    local node, parent, leaf = resolve(fs, path)
    if not node or not parent or not leaf then return false end
    if node.type == T_DIR then
      -- recursive remove of children first
      for _, e in ipairs(dirEntries(fs, node)) do
        P.remove((path:gsub("/+$", "")) .. "/" .. e.name)
      end
    end
    freeInodeBlocks(fs, node)
    node.type = T_FREE; writeInode(fs, node)
    dirRemove(fs, parent, leaf)
    writeSuper(fs)
    return true
  end

  function P.rename(from, to)
    local node, fparent, fleaf = resolve(fs, from)
    if not node then return false end
    local existing, tparent, tleaf = resolve(fs, to)
    if not tparent or not tleaf then return false end
    if existing then P.remove(to) end
    local ok = dirAdd(fs, tparent, tleaf, node.num)
    if not ok then return false end
    dirRemove(fs, fparent, fleaf)
    writeSuper(fs)
    return true
  end

  function P.open(path, mode)
    mode = (mode or "r"):gsub("b", "")
    local node, parent, leaf = resolve(fs, path)
    if mode == "r" then
      if not node or node.type ~= T_FILE then return nil, "no such file" end
    else                                                 -- w / a: create if absent
      if not node then
        if not parent or not leaf then return nil, "bad path" end
        node = allocInode(fs, T_FILE); if not node then return nil, "no inodes" end
        if not dirAdd(fs, parent, leaf, node.num) then
          node.type = T_FREE; writeInode(fs, node); return nil, "cannot link"
        end
      elseif node.type ~= T_FILE then return nil, "is a directory" end
      if mode == "w" then freeInodeBlocks(fs, node); writeInode(fs, node) end
    end
    local h = nextH; nextH = nextH + 1
    handles[h] = { node = node, mode = mode, pos = (mode == "a") and node.size or 0 }
    return h
  end

  function P.read(h, count)
    local st = handles[h]; if not st then return nil, "bad handle" end
    if st.pos >= st.node.size then return nil end        -- EOF (OC returns nil)
    local data = readData(fs, st.node, st.pos, math.min(count, st.node.size - st.pos))
    st.pos = st.pos + #data
    return data
  end

  function P.write(h, data)
    local st = handles[h]; if not st then return false, "bad handle" end
    if st.mode == "r" then return false, "read-only handle" end
    local ok, err = writeData(fs, st.node, st.pos, data)
    if not ok then return false, err end
    st.pos = st.pos + #data
    writeInode(fs, st.node); writeSuper(fs)
    return true
  end

  function P.seek(h, whence, offset)
    local st = handles[h]; if not st then return nil, "bad handle" end
    offset = offset or 0
    if whence == "set" then st.pos = offset
    elseif whence == "cur" then st.pos = st.pos + offset
    elseif whence == "end" then st.pos = st.node.size + offset end
    if st.pos < 0 then st.pos = 0 end
    return st.pos
  end

  -- A nil handle is what a caller hands us when it forgot to check
  -- open()'s return. Indexing `handles` with it raises "table index is
  -- nil" from inside the driver, which points the reader at this file
  -- instead of at their own missing check.
  function P.close(h)
    if h == nil or handles[h] == nil then return false, "bad file descriptor" end
    handles[h] = nil
    return true
  end

  -- Flush the clean bit so a later mount knows the volume was shut down
  -- properly (fsck can then trust the free counts). Call on unmount.
  function P.sync() fs.clean = true; writeSuper(fs); fs.clean = false; writeSuper(fs) end
  function P.unmount() fs.clean = true; writeSuper(fs) end

  return P, fs
end

-- ============================================================
-- Statistics + fragmentation
-- ============================================================

--- Volume stats without mounting: capacity, usage, inode use, and the
--- FRAGMENTATION ratio — the share of a file's data-block steps that
--- jump to a non-adjacent block (0 = perfectly contiguous). Pure read.
function blockfs.stats(drive, opts)
  local fs, err = openVolume(drive, opts)
  if not fs then return nil, err end
  local files, dirs = 0, 0
  local totalSteps, jumps = 0, 0
  for ino = ROOT_INODE, fs.inodeCount - 1 do
    local n = readInode(fs, ino)
    if n.type == T_FILE or n.type == T_DIR then
      if n.type == T_FILE then files = files + 1 else dirs = dirs + 1 end
      local prev = nil
      walkBlocks(fs, n, function(b, kind)
        if kind == "data" then
          if prev ~= nil then
            totalSteps = totalSteps + 1
            if b ~= prev + 1 then jumps = jumps + 1 end
          end
          prev = b
        end
      end)
    end
  end
  local frag = (totalSteps > 0) and (jumps / totalSteps) or 0
  return {
    label = fs.label, sectorSize = fs.ss, totalBlocks = fs.totalBlocks,
    freeBlocks = fs.freeBlocks, usedBlocks = (fs.totalBlocks - fs.dataStart) - fs.freeBlocks,
    dataBlocks = fs.totalBlocks - fs.dataStart, inodeCount = fs.inodeCount,
    files = files, dirs = dirs, clean = fs.clean,
    fragmentation = frag, fragJumps = jumps, fragSteps = totalSteps,
  }
end

-- ============================================================
-- fsck — consistency check (+ optional repair of the free counts)
-- ============================================================

--- Check the volume. opts.repair = true rebuilds the block bitmap and
--- free count from what the inodes actually reference (the safe repair:
--- reachable blocks become the truth), and clears the dirty flag.
--- Returns { ok, problems = {...}, repaired = bool }.
function blockfs.check(drive, opts)
  opts = opts or {}
  local fs, err = openVolume(drive, opts)
  if not fs then return nil, err end
  -- opts.yield (a function) is called between inodes during the scan so
  -- a big fsck doesn't freeze other seats — but ONLY on a read-only
  -- check: a --repair rewrites the bitmap from the scan results, and a
  -- yield window there would let concurrent writes make the scan stale
  -- before it's applied. Repairs stay atomic. (defrag has NO yield hook
  -- for the same reason, deliberately — a torn snapshot is data loss.)
  local yield = (not opts.repair) and type(opts.yield) == "function"
    and opts.yield or nil
  local problems = {}
  local used = {}                       -- block → times referenced
  local function mark(b)
    if b < fs.dataStart or b >= fs.totalBlocks then
      problems[#problems + 1] = "pointer out of range: " .. b; return
    end
    used[b] = (used[b] or 0) + 1
    if used[b] > 1 then problems[#problems + 1] = "block " .. b .. " double-allocated" end
  end
  for ino = ROOT_INODE, fs.inodeCount - 1 do
    if yield then yield() end
    local n = readInode(fs, ino)
    if n.type == T_FILE or n.type == T_DIR then
      walkBlocks(fs, n, function(b) mark(b) end)
    end
  end
  -- Compare against the bitmap.
  local bitmapUsed, leaked = 0, 0
  for b = fs.dataStart, fs.totalBlocks - 1 do
    local bit = bitGet(fs, b)
    if bit == 1 then bitmapUsed = bitmapUsed + 1 end
    if bit == 1 and not used[b] then leaked = leaked + 1 end
    if bit == 0 and used[b] then
      problems[#problems + 1] = "block " .. b .. " referenced but marked free"
    end
  end
  if leaked > 0 then problems[#problems + 1] = leaked .. " leaked block(s) (used-bit set, unreferenced)" end
  if not fs.clean then problems[#problems + 1] = "volume was not cleanly unmounted" end

  local repaired = false
  if opts.repair then
    -- Rebuild the bitmap from reachability: metadata + referenced blocks used.
    for b = 0, fs.dataStart - 1 do bitSet(fs, b, 1) end
    local free = 0
    for b = fs.dataStart, fs.totalBlocks - 1 do
      if used[b] then bitSet(fs, b, 1) else bitSet(fs, b, 0); free = free + 1 end
    end
    fs.freeBlocks = free; fs.clean = true; writeSuper(fs)
    repaired = true
  end
  return { ok = (#problems == 0), problems = problems, repaired = repaired,
           leaked = leaked, referenced = fs.totalBlocks - fs.dataStart - fs.freeBlocks }
end

-- ============================================================
-- Defragmentation
-- ============================================================

--- Rewrite every file's data blocks into contiguous runs, packed toward
--- the front of the data region, so the simulated head stops seeking.
--- opts.now for timestamps. Returns { moved = <blocks>, before, after }
--- (fragmentation ratios). Manual; the `drive` command also calls this
--- automatically when stats().fragmentation crosses a threshold.
---
--- Safety: relocating one file could overwrite sectors another file
--- still references, so we read EVERY file/dir's bytes into memory
--- FIRST (phase 1), then reset the allocation and lay them all back
--- down contiguously (phase 3). OC volumes are small, so holding the
--- content briefly is fine; a huge volume would want a scratch-region
--- pass instead.
function blockfs.defrag(drive, opts)
  opts = opts or {}
  local before = blockfs.stats(drive, opts)
  if not before then return nil, "not a TBFS volume" end
  local fs = openVolume(drive, opts)

  -- Phase 1 — snapshot all content via the CURRENT (fragmented) mapping.
  local content = {}
  for ino = ROOT_INODE, fs.inodeCount - 1 do
    local n = readInode(fs, ino)
    if n.type == T_FILE or n.type == T_DIR then
      content[ino] = readData(fs, n, 0, n.size)
    end
  end

  -- Phase 2 — free the whole data region; allocation now starts clean at
  -- dataStart, so each rewrite packs contiguously from the front.
  for b = fs.dataStart, fs.totalBlocks - 1 do bitSet(fs, b, 0) end
  fs.freeBlocks = fs.totalBlocks - fs.dataStart
  fs.allocHint = fs.dataStart

  -- Phase 3 — rewrite each inode's data in inode order. writeData pulls
  -- from allocHint upward and keeps a file's blocks adjacent, so files
  -- land in tight back-to-back runs.
  local moved = 0
  for ino = ROOT_INODE, fs.inodeCount - 1 do
    if content[ino] ~= nil then
      local n = readInode(fs, ino)
      for i = 1, N_DIRECT do n.direct[i] = 0 end
      n.indirect = 0; n.double = 0; n.blocks = 0; n.size = 0
      local ok, err = writeData(fs, n, 0, content[ino])
      if not ok then return nil, "defrag rewrite failed: " .. tostring(err) end
      writeInode(fs, n)
      moved = moved + n.blocks
    end
  end

  fs.clean = true; writeSuper(fs)
  local after = blockfs.stats(drive, opts)
  return { moved = moved, before = before.fragmentation,
           after = after and after.fragmentation or 0 }
end

-- ============================================================
-- Boot support (make an unmanaged drive BOOTABLE)
-- ============================================================
-- A drive formatted with a boot region (format opts.bootBytes > 0) holds
-- a stage-2 boot blob in a fixed CONTIGUOUS run of sectors. The whole
-- point: a ~15-line EEPROM can read that run and run() it without any
-- TBFS parser of its own. The blob (assembled by blockfs.bootBlob) is a
-- self-contained chunk that embeds this very driver, mounts the drive as
-- root, and hands off to /init.lua.

--- The default stage-2 bootstrap. Runs in the OC boot environment (the
--- globals `component` and `computer` exist). `blockfs` is already in
--- scope because bootBlob prepends the driver. Mounts the boot drive as
--- root and executes /init.lua from it.
blockfs.BOOTSTRAP = [==[
-- TBFS stage-2 bootstrap (loaded from the boot region by the EEPROM).
local component = component or require("component")
local computer  = computer  or require("computer")
-- The TOS BIOS hands us the exact drive it read this blob from — trust it
-- first: getBootAddress may still point at a managed FS (fresh deploy) and
-- a blind first-drive scan could mount the wrong volume on a multi-drive box.
local addr = _G._TBFS_BOOT_DRIVE
_G._TBFS_BOOT_DRIVE = nil
if not addr then addr = computer.getBootAddress and computer.getBootAddress() end
local drive
if addr and component.type and component.type(addr) == "drive" then
  drive = component.proxy(addr)
else
  for a in component.list("drive") do drive = component.proxy(a); break end
end
if not drive then error("TBFS boot: no drive component") end
local root, mErr = blockfs.mount(drive)
if not root then error("TBFS boot: mount failed: " .. tostring(mErr)) end
-- init.lua prefers this global over proxying a managed boot filesystem,
-- so the unmanaged root reaches the kernel unchanged.
_G._TOS_UNMANAGED_ROOT = root
local h = root.open("/init.lua", "r")
if not h then error("TBFS boot: /init.lua not found on root") end
local parts = {}
while true do local c = root.read(h, 8192); if not c then break end; parts[#parts + 1] = c end
root.close(h)
local fn, lErr = load(table.concat(parts), "=/init.lua", "t")
if not fn then error("TBFS boot: init load error: " .. tostring(lErr)) end
return fn()
]==]

--- Assemble a runnable stage-2 boot blob: the driver source embedded as
--- an inline module, then the bootstrap. `blockfsSrc` is the text of this
--- file (the caller reads /usr/lib/blockfs.lua — the library stays pure
--- and never reads its own file). `bootstrapSrc` defaults to BOOTSTRAP.
--- Returns the blob string (valid Lua).
function blockfs.bootBlob(blockfsSrc, bootstrapSrc)
  bootstrapSrc = bootstrapSrc or blockfs.BOOTSTRAP
  -- blockfsSrc ends with `return blockfs`, so the IIFE yields the module.
  return "local blockfs = (function()\n" .. blockfsSrc .. "\nend)()\n" .. bootstrapSrc
end

--- Write a boot blob into the volume's reserved boot region. The region
--- stores a 4-byte little-endian length, then the blob bytes. Fails if
--- the volume has no boot region or the blob doesn't fit. Returns
--- (true) or (false, reason).
function blockfs.writeBoot(drive, blob)
  local fs, err = openVolume(drive)
  if not fs then return false, err end
  if (fs.bootBlocks or 0) == 0 then return false, "volume has no boot region (format with bootBytes)" end
  local capacity = fs.bootBlocks * fs.ss - 4
  if #blob > capacity then
    return false, string.format("boot blob too large (%d > %d bytes)", #blob, capacity)
  end
  local payload = string.pack("<I4", #blob) .. blob
  -- Write sector by sector across the contiguous boot region.
  local off = 1
  for b = fs.bootStart, fs.bootStart + fs.bootBlocks - 1 do
    writeBlock(fs, b, payload:sub(off, off + fs.ss - 1))
    off = off + fs.ss
    if off > #payload then break end
  end
  return true
end

--- Read the boot blob back (nil if no boot region / empty). Pure read;
--- this is essentially what the EEPROM does (read the contiguous run,
--- take the length-prefixed blob).
function blockfs.readBoot(drive)
  local fs, err = openVolume(drive)
  if not fs then return nil, err end
  if (fs.bootBlocks or 0) == 0 then return nil, "no boot region" end
  local parts = {}
  for b = fs.bootStart, fs.bootStart + fs.bootBlocks - 1 do
    parts[#parts + 1] = readBlock(fs, b)
  end
  local raw = table.concat(parts)
  local len = string.unpack("<I4", raw)
  if len == 0 or len > #raw - 4 then return nil, "no boot blob written" end
  return raw:sub(5, 4 + len)
end

--- Is this a bootable TBFS volume (has a boot region with a blob)?
function blockfs.isBootable(drive)
  local blob = blockfs.readBoot(drive)
  return blob ~= nil and #blob > 0
end

return blockfs
