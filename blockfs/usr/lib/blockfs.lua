

































local blockfs = {}
blockfs._VERSION = "1.2.0"

local MAGIC        = "TBFS"
local FMT_VERSION  = 1
local INODE_SIZE   = 64          
local N_DIRECT     = 8           
local T_FREE, T_FILE, T_DIR = 0, 1, 2
local NAME_MAX     = 48          
local ROOT_INODE   = 1           








local function driveGeom(drive)
  local ss = drive.getSectorSize and drive.getSectorSize() or 512
  local cap = drive.getCapacity and drive.getCapacity() or (ss * 1024)
  ss = math.max(64, math.floor(ss))
  local blocks = math.floor(cap / ss)
  return ss, blocks
end





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

--! MEASURED AGAIN with the cache in (2026-09-06): reads were fixed, WRITES
--! were not. A 64 KB file cost 384 sector writes for 128 blocks -- the
--! data, plus the bitmap sector rewritten per BIT and the pointer block
--! rewritten per POINTER -- and each block was read before being written
--! to keep bytes a fresh block does not have. Three changes, and
--! write-through survives all of them (test_blockfs_perf.lua):
--!  1. Bitmap/pointer writes are COALESCED PER OPERATION: inside a batch
--!     they update the cache, pinned, and are written once when the
--!     outermost batch closes -- before the caller hears "written". Data
--!     blocks are never deferred. A crash mid-batch leaves data the
--!     bitmap still calls free and no inode referencing it: exactly the
--!     old crash window, and one fsck repairs it. Drive order is
--!     unchanged: data, bitmap+pointers, inode, superblock.
--!  2. A block fully overwritten or just allocated is NOT read first.
--!  3. File data stays OUT of the 4-slot cache (it streamed 128 blocks
--!     through and evicted the inode/bitmap every time); directory data
--!     is metadata and stays cached.
local function cachePut(fs, b, data, pin)
  local c = fs.cache
  if not c then return end
  local e = c.map[b]
  c.tick = c.tick + 1
  if e then
    e.data, e.used = data, c.tick
    if pin then e.dirty = true end
    return
  end
  if c.n >= CACHE_SLOTS then
    
    
    local oldest, oldestUsed
    for blk, ent in pairs(c.map) do
      if not ent.dirty and (not oldestUsed or ent.used < oldestUsed) then
        oldest, oldestUsed = blk, ent.used
      end
    end
    if oldest then c.map[oldest] = nil; c.n = c.n - 1 end
  end
  c.map[b] = { data = data, used = c.tick, dirty = pin or nil }
  c.n = c.n + 1
end




local function readBlock(fs, b, cacheable)
  if b < 0 or b >= fs.totalBlocks then
    error("readBlock out of range: " .. tostring(b), 2)
  end
  local c = fs.cache
  if c then
    local e = c.map[b]
    if e then c.tick = c.tick + 1; e.used = c.tick; return e.data end
  end
  local s = fs.drive.readSector(b + 1)          
  if type(s) ~= "string" then s = "" end
  if #s < fs.ss then s = s .. string.rep("\0", fs.ss - #s) end
  s = s:sub(1, fs.ss)
  if cacheable ~= false then cachePut(fs, b, s) end
  return s
end



local function flushDeferred(fs)
  local c = fs.cache
  if not c or not c.dirtyCount or c.dirtyCount == 0 then return end
  local blks = {}
  for blk, ent in pairs(c.map) do
    if ent.dirty then blks[#blks + 1] = blk end
  end
  table.sort(blks)
  for _, blk in ipairs(blks) do
    local ent = c.map[blk]
    fs.drive.writeSector(blk + 1, ent.data)
    ent.dirty = nil
  end
  c.dirtyCount = 0
end




local function beginBatch(fs) fs.batchDepth = (fs.batchDepth or 0) + 1 end
local function endBatch(fs)
  fs.batchDepth = fs.batchDepth - 1
  if fs.batchDepth <= 0 then fs.batchDepth = 0; flushDeferred(fs) end
end




local function writeBlock(fs, b, data, defer)
  if b < 0 or b >= fs.totalBlocks then
    error("writeBlock out of range: " .. tostring(b), 2)
  end
  if #data < fs.ss then data = data .. string.rep("\0", fs.ss - #data)
  elseif #data > fs.ss then data = data:sub(1, fs.ss) end
  local c = fs.cache
  if defer and c and (fs.batchDepth or 0) > 0 then
    local wasDirty = c.map[b] and c.map[b].dirty
    cachePut(fs, b, data, true)
    if not wasDirty then c.dirtyCount = (c.dirtyCount or 0) + 1 end
    return
  end
  fs.drive.writeSector(b + 1, data)
  --! Through, not back: the drive already has it before the cache does.
  
  
  
  if c and (b < fs.dataStart or (c.map[b] ~= nil)) then
    local e = c.map[b]
    if e and e.dirty then e.dirty = nil; c.dirtyCount = c.dirtyCount - 1 end
    cachePut(fs, b, data)
  end
end










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
  fs.superDirty = false
end




local function writeSuperIfDirty(fs)
  if fs.superDirty then writeSuper(fs) end
end





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
  writeBlock(fs, bb, sector:sub(1, off) .. string.char(byte) .. sector:sub(off + 2), true)
end





local function allocBlock(fs, near)
  if fs.freeBlocks <= 0 then return nil end
  local first, last = fs.dataStart, fs.totalBlocks - 1
  local function tryTake(b)
    if b >= first and b <= last and bitGet(fs, b) == 0 then
      bitSet(fs, b, 1); fs.freeBlocks = fs.freeBlocks - 1; fs.allocHint = b
      fs.superDirty = true                     
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
    fs.superDirty = true
  end
end







local function inodeLoc(fs, ino)
  local perBlock = fs.ss // INODE_SIZE
  local idx = ino                      
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
  local p = 15                          
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




local function ppb(fs) return fs.ss // 4 end     

local function readPtr(fs, blk, slot)
  local sector = readBlock(fs, blk)
  return (string.unpack("<I4", sector, slot * 4 + 1))
end
local function writePtr(fs, blk, slot, val)
  local sector = readBlock(fs, blk)
  local at = slot * 4
  writeBlock(fs, blk, sector:sub(1, at) .. string.pack("<I4", val) .. sector:sub(at + 5), true)
end

--! Journal for writeData's mapping pass: a failed write undoes every
--! allocation + link newest-first (no leaked blocks; test_blockfs_enospc).
local function jot(fs, op, a, b)
  local j = fs.journal
  if j then j[#j + 1] = { op, a, b } end
end







local function mapBlock(fs, node, li, alloc)
  local P = ppb(fs)
  local function near() return fs.allocHint end
  local function take(nearBlk)
    local b = allocBlock(fs, nearBlk)
    if b then
      node.blocks = (node.blocks or 0) + 1; node._dirty = true
      jot(fs, "blk", b)
    end
    return b
  end
  if li < N_DIRECT then
    if node.direct[li + 1] == 0 and alloc then
      local b = take(li > 0 and node.direct[li] ~= 0 and node.direct[li] or near())
      if not b then return nil end
      node.direct[li + 1] = b; jot(fs, "direct", li + 1)
      return b, true
    end
    local d = node.direct[li + 1]
    return d ~= 0 and d or nil
  end
  li = li - N_DIRECT
  if li < P then                                   
    if node.indirect == 0 then
      if not alloc then return nil end
      local ib = take(near()); if not ib then return nil end
      writeBlock(fs, ib, string.rep("\0", fs.ss), true)
      node.indirect = ib; jot(fs, "ind")
    end
    local phys = readPtr(fs, node.indirect, li)
    if phys == 0 and alloc then
      phys = take(node.indirect); if not phys then return nil end
      writePtr(fs, node.indirect, li, phys); jot(fs, "ptr", node.indirect, li)
      return phys, true
    end
    return phys ~= 0 and phys or nil
  end
  li = li - P
  if li < P * P then                               
    if node.double == 0 then
      if not alloc then return nil end
      local db = take(near()); if not db then return nil end
      writeBlock(fs, db, string.rep("\0", fs.ss), true)
      node.double = db; jot(fs, "dbl")
    end
    local l1, l2 = li // P, li % P
    local mid = readPtr(fs, node.double, l1)
    if mid == 0 then
      if not alloc then return nil end
      mid = take(node.double); if not mid then return nil end
      writeBlock(fs, mid, string.rep("\0", fs.ss), true)
      writePtr(fs, node.double, l1, mid); jot(fs, "ptr", node.double, l1)
    end
    local phys = readPtr(fs, mid, l2)
    if phys == 0 and alloc then
      phys = take(mid); if not phys then return nil end
      writePtr(fs, mid, l2, phys); jot(fs, "ptr", mid, l2)
      return phys, true
    end
    return phys ~= 0 and phys or nil
  end
  return nil   
end


local function rollback(fs, node, j)
  for k = #j, 1, -1 do
    local op, a, b = j[k][1], j[k][2], j[k][3]
    if op == "blk" then freeBlock(fs, a); node.blocks = node.blocks - 1
    elseif op == "direct" then node.direct[a] = 0
    elseif op == "ind" then node.indirect = 0
    elseif op == "dbl" then node.double = 0
    else writePtr(fs, a, b, 0) end   
  end
end




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
  beginBatch(fs)                 
  walkBlocks(fs, node, function(b) freeBlock(fs, b) end)
  endBatch(fs)
  node.blocks = 0; node.size = 0
  for i = 1, N_DIRECT do node.direct[i] = 0 end
  node.indirect = 0; node.double = 0
end





local function readData(fs, node, offset, count)
  if offset >= node.size then return "" end
  count = math.min(count, node.size - offset)
  local out = {}
  local pos = offset
  
  
  local cacheable = (node.type == T_DIR)
  while count > 0 do
    local li = pos // fs.ss
    local within = pos % fs.ss
    local phys = mapBlock(fs, node, li, false)
    local chunk
    if phys then
      chunk = readBlock(fs, phys, cacheable):sub(within + 1, within + math.min(count, fs.ss - within))
    else
      chunk = string.rep("\0", math.min(count, fs.ss - within))   
    end
    out[#out + 1] = chunk
    local n = #chunk
    if n == 0 then break end
    pos = pos + n; count = count - n
  end
  return table.concat(out)
end

--! Map (allocating) every block, THEN write: all-or-nothing like OC's
--! managed fs. Same I/O; metadata still lands after data.
local function writeData(fs, node, offset, data)
  local n = #data
  local ss = fs.ss
  beginBatch(fs)                 

  
  local firstLi = offset // ss
  local phys, fresh = {}, {}
  if n > 0 then
    local lastLi = (offset + n - 1) // ss
    local journal = {}
    fs.journal = journal
    for li = firstLi, lastLi do
      local p, f = mapBlock(fs, node, li, true)
      if not p then
        fs.journal = nil
        rollback(fs, node, journal)
        endBatch(fs)
        return false, "out of space"
      end
      phys[li - firstLi + 1], fresh[li - firstLi + 1] = p, f
    end
    fs.journal = nil
  end

  
  local pos, i = offset, 1
  while i <= n do
    local li = pos // ss
    local within = pos % ss
    local k = li - firstLi + 1
    local blk = phys[k]
    local room = ss - within
    local chunk = data:sub(i, i + room - 1)
    local sector
    if #chunk == ss then
      sector = chunk                                   
    elseif fresh[k] then
      
      
      sector = string.rep("\0", within) .. chunk .. string.rep("\0", ss - within - #chunk)
    else
      local old = readBlock(fs, blk, node.type == T_DIR)
      sector = old:sub(1, within) .. chunk .. old:sub(within + #chunk + 1)
    end
    writeBlock(fs, blk, sector)
    pos = pos + #chunk; i = i + #chunk
  end
  endBatch(fs)
  if pos > node.size then node.size = pos end
  
  node.mtime = fs.now()
  return true
end







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
  
  
  
  
  dnode = readInode(fs, dnode.num)
  if #name > NAME_MAX then return false, "name too long" end
  if dirLookup(fs, dnode, name) then return false, "exists" end
  local rec = string.char(#name) .. name .. string.pack("<I4", ino)
  local ok, err = writeData(fs, dnode, dnode.size, rec)
  if not ok then return false, err end
  writeInode(fs, dnode)
  return true
end



local function dirRemove(fs, dnode, name)
  dnode = readInode(fs, dnode.num)     
  local kept = {}
  for _, e in ipairs(dirEntries(fs, dnode)) do
    if e.name ~= name then
      kept[#kept + 1] = string.char(#e.name) .. e.name .. string.pack("<I4", e.inode)
    end
  end
  freeInodeBlocks(fs, dnode)
  dnode.size = 0
  
  
  
  if #kept > 0 then
    local ok, err = writeData(fs, dnode, 0, table.concat(kept))
    if not ok then return false, err end
  end
  writeInode(fs, dnode)
  return true
end





local function splitPath(path)
  local parts = {}
  for seg in tostring(path or ""):gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil
    elseif seg ~= "." and seg ~= "" then parts[#parts + 1] = seg end
  end
  return parts
end



local function resolve(fs, path)
  local parts = splitPath(path)
  local cur = readInode(fs, ROOT_INODE)
  local parent, leaf = cur, nil
  for i, seg in ipairs(parts) do
    if cur.type ~= T_DIR then return nil, nil, nil, "not a directory" end
    parent = cur; leaf = seg
    local ino = dirLookup(fs, cur, seg)
    if not ino then
      if i == #parts then return nil, parent, leaf end      
      return nil, nil, nil, "no such path"
    end
    cur = readInode(fs, ino)
  end
  return cur, parent, leaf
end







function blockfs.plan(drive, opts)
  opts = opts or {}
  local ss, totalBlocks = driveGeom(drive)
  if totalBlocks < 8 then return nil, "drive too small for TBFS" end

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
  if dataStart >= totalBlocks then return nil, "drive too small for metadata + boot region" end
  return {
    ss = ss, totalBlocks = totalBlocks,
    bitmapStart = bitmapStart, bitmapBlocks = bitmapBlocks,
    inodeStart = inodeStart, inodeCount = inodeCount, inodeBlocks = inodeBlocks,
    bootStart = bootStart, bootBlocks = bootBlocks,
    dataStart = dataStart, dataBlocks = totalBlocks - dataStart,
  }
end


function blockfs.blocksFor(bytes, ss)
  ss = ss or 512
  local data = math.ceil((tonumber(bytes) or 0) / ss)
  if data <= N_DIRECT then return data end
  local P = ss // 4
  local meta, rest = 1, data - N_DIRECT - P   
  if rest > 0 then meta = meta + 1 + math.ceil(rest / P) end   
  return data + meta
end






function blockfs.format(drive, opts)
  opts = opts or {}
  local fs, lerr = blockfs.plan(drive, opts)   
  if not fs then return false, lerr end
  local ss, totalBlocks, dataStart = fs.ss, fs.totalBlocks, fs.dataStart
  fs.drive, fs.freeBlocks, fs.clean = drive, 0, true
  fs.label = (opts.label or "tbfs"):sub(1, 32)
  fs.now = opts.now or function() return 0 end
  fs.allocHint = dataStart
  
  
  fs.cache = { map = {}, n = 0, tick = 0 }

  
  for b = 0, dataStart - 1 do writeBlock(fs, b, string.rep("\0", ss)) end
  
  
  fs.freeBlocks = totalBlocks - dataStart
  beginBatch(fs)
  for b = 0, dataStart - 1 do bitSet(fs, b, 1) end
  endBatch(fs)
  
  local root = { num = ROOT_INODE, type = T_DIR, flags = 0, size = 0,
    mtime = fs.now(), blocks = 0, direct = {}, indirect = 0, double = 0 }
  for i = 1, N_DIRECT do root.direct[i] = 0 end
  writeInode(fs, root)
  writeSuper(fs)
  return true
end





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







function blockfs.mount(drive, opts)
  local fs, err = openVolume(drive, opts)
  if not fs then return nil, err end
  fs.clean = false; writeSuper(fs)          
  local handles, nextH = {}, 1

  local function nodeAt(path)
    local node = select(1, resolve(fs, path))
    return node
  end

  local P = {}

  
  
  
  
  
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

  --! Creates parents as needed. NOT because the managed filesystem does --
  --! it does not: OC's disk-backed component calls Java's File.mkdir()
  --! and its in-memory one fails when the parent is absent, so a managed
  --! disk is single-level and so is OpenOS above it. The guarantee TOS
  --! relies on lives in kernel.fs.makeDirectory, which walks the chain for
  --! every backend.
  --!
  --! This stays recursive anyway, and it is not redundant: kernel.fs hands
  --! down one level at a time, but anything holding this proxy DIRECTLY --
  --! the TBFS boot blob mounting the root before the kernel exists, and
  --! `deploy drive`, which creates the whole manifest's directory chain --
  --! calls it with a full path. Being a superset of the managed contract
  --! is safe; relying on that from portable code is not, which is why the
  --! guarantee is stated one layer up rather than here.
  function P.makeDirectory(path)
    local parts = splitPath(path)
    if #parts == 0 then return true end                 
    local acc = ""
    for _, seg in ipairs(parts) do
      acc = acc .. "/" .. seg
      local node, parent, leaf = resolve(fs, acc)
      if node then
        if node.type ~= T_DIR then return false end     
      else
        if not parent or not leaf then return false end
        local dir = allocInode(fs, T_DIR)
        if not dir then return false end
        local ok = dirAdd(fs, parent, leaf, dir.num)
        if not ok then dir.type = T_FREE; writeInode(fs, dir); return false end
      end
    end
    writeSuperIfDirty(fs)
    return true
  end

  function P.remove(path)
    local node, parent, leaf = resolve(fs, path)
    if not node or not parent or not leaf then return false end
    if node.type == T_DIR then
      
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
    if not node or not fleaf then return false end      
    
    
    
    if node.type == T_DIR then
      local f, t = splitPath(from), splitPath(to)
      local inside = #t >= #f
      for i = 1, #f do if t[i] ~= f[i] then inside = false; break end end
      if inside and #t == #f then return true end       
      if inside then return false end
    end
    local existing, tparent, tleaf = resolve(fs, to)
    if not tparent or not tleaf then return false end
    if existing and existing.num == node.num then return true end   
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
    else                                                 
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
    if st.pos >= st.node.size then return nil end        
    local data = readData(fs, st.node, st.pos, math.min(count, st.node.size - st.pos))
    st.pos = st.pos + #data
    return data
  end

  function P.write(h, data)
    local st = handles[h]; if not st then return false, "bad handle" end
    if st.mode == "r" then return false, "read-only handle" end
    local ok, err = writeData(fs, st.node, st.pos, data)
    if not ok then writeSuperIfDirty(fs); return false, err end   
    st.pos = st.pos + #data
    writeInode(fs, st.node); writeSuperIfDirty(fs)
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

  
  
  
  
  function P.close(h)
    if h == nil or handles[h] == nil then return false, "bad file descriptor" end
    handles[h] = nil
    return true
  end

  
  
  
  
  
  function P.openHandles()
    local n = 0
    for _ in pairs(handles) do n = n + 1 end
    return n
  end

  
  
  function P.sync() fs.clean = true; writeSuper(fs); fs.clean = false; writeSuper(fs) end
  function P.unmount() fs.clean = true; writeSuper(fs) end

  return P, fs
end








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









function blockfs.check(drive, opts)
  opts = opts or {}
  local fs, err = openVolume(drive, opts)
  if not fs then return nil, err end
  
  
  
  
  
  
  local yield = (not opts.repair) and type(opts.yield) == "function"
    and opts.yield or nil
  local problems = {}
  local used = {}                       
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
    
    
    
    
    beginBatch(fs)
    for b = 0, fs.dataStart - 1 do bitSet(fs, b, 1) end
    local free = 0
    for b = fs.dataStart, fs.totalBlocks - 1 do
      if used[b] then bitSet(fs, b, 1) else bitSet(fs, b, 0); free = free + 1 end
    end
    endBatch(fs)
    fs.freeBlocks = free; fs.clean = true; writeSuper(fs)
    repaired = true
  end
  return { ok = (#problems == 0), problems = problems, repaired = repaired,
           leaked = leaked, referenced = fs.totalBlocks - fs.dataStart - fs.freeBlocks }
end

















function blockfs.defrag(drive, opts)
  opts = opts or {}
  local before = blockfs.stats(drive, opts)
  if not before then return nil, "not a TBFS volume" end
  local fs = openVolume(drive, opts)

  
  local content = {}
  for ino = ROOT_INODE, fs.inodeCount - 1 do
    local n = readInode(fs, ino)
    if n.type == T_FILE or n.type == T_DIR then
      content[ino] = readData(fs, n, 0, n.size)
    end
  end

  
  
  beginBatch(fs)
  for b = fs.dataStart, fs.totalBlocks - 1 do bitSet(fs, b, 0) end
  endBatch(fs)
  fs.freeBlocks = fs.totalBlocks - fs.dataStart
  fs.allocHint = fs.dataStart

  
  
  
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






function blockfs.bootBlob(blockfsSrc, bootstrapSrc)
  bootstrapSrc = bootstrapSrc or blockfs.BOOTSTRAP
  
  return "local blockfs = (function()\n" .. blockfsSrc .. "\nend)()\n" .. bootstrapSrc
end





function blockfs.writeBoot(drive, blob)
  local fs, err = openVolume(drive)
  if not fs then return false, err end
  if (fs.bootBlocks or 0) == 0 then return false, "volume has no boot region (format with bootBytes)" end
  local capacity = fs.bootBlocks * fs.ss - 4
  if #blob > capacity then
    return false, string.format("boot blob too large (%d > %d bytes)", #blob, capacity)
  end
  local payload = string.pack("<I4", #blob) .. blob
  
  local off = 1
  for b = fs.bootStart, fs.bootStart + fs.bootBlocks - 1 do
    writeBlock(fs, b, payload:sub(off, off + fs.ss - 1))
    off = off + fs.ss
    if off > #payload then break end
  end
  return true
end




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


function blockfs.isBootable(drive)
  local blob = blockfs.readBoot(drive)
  return blob ~= nil and #blob > 0
end

return blockfs
