


















local component = require("component")
local computer   = require("computer")




local fs         = fs  

local mod = {}


local MAGIC     = "TOS\x01"
local EOA       = "TOS\x00"  
local VERSION   = 1
local FLAG_DIR  = 1
local BLOCK     = 8192        





--! kernel.vault writes V2 today and still reads V1 (#SEC CR-7). Accept both.
local VAULT_MAGIC_V1 = "TVAULT1\0"
local VAULT_MAGIC_V2 = "TVAULT2\0"
local VAULT_HEADER   = 114    
local VAULT_CTLEN_AT = 47     




local function findDrive(addr)
  if addr then
    for a in component.list("tape_drive") do
      if a:sub(1, #addr) == addr then
        return component.proxy(a)
      end
    end
    return nil, "No tape drive matching: " .. addr
  end
  local a = component.list("tape_drive")()
  if a then return component.proxy(a) end
  return nil, "No tape drive found"
end

--! #BUG (mod-source verification round, 2026-09-20) — THE TAPE DRIVE HAS NO
--! GETTER FOR SPEED OR VOLUME. Computronics' TileTapeDrive.java declares
--! exactly these @Callbacks, and this is the whole Lua surface:
--!   getLabel getPosition getSize getState isEnd isReady play read seek
--!   setLabel setSpeed setVolume stop write
--! setSpeed and setVolume are there; getSpeed and getVolume do not exist,
--! at any tier, in any version of that file. `tape state`, `tape speed` and
--! `tape volume` all called them inside a pcall, so the pcall failed on
--! EVERY machine: state printed no Speed or Volume line at all, and the two
--! bare commands answered "Current speed: ?" forever. The pcall is why it
--! looked like a hardware quirk instead of a typo.
--!   So TOS remembers what TOS SET, per drive address, and labels it as
--! such. That is deliberately narrower than a getter: a value set by
--! another computer on the same drive, or set before this reboot, is
--! reported as unknown rather than guessed at. Reporting a number nobody
--! asked the drive for would be the same class of mistake as the pcall
--! that hid this one.
local lastSet = {}   

local function noteSet(drive, key, value)
  local a = drive and drive.address
  if not a then return end
  lastSet[a] = lastSet[a] or {}
  lastSet[a][key] = value
end

local function recalled(drive, key)
  local a = drive and drive.address
  local rec = a and lastSet[a]
  return rec and rec[key] or nil
end


local function enc16(n)
  return string.char(math.floor(n / 256) % 256, n % 256)
end

local function dec16(s)
  return s:byte(1) * 256 + s:byte(2)
end

local function enc32(n)
  local b1 = math.floor(n / 16777216) % 256
  local b2 = math.floor(n / 65536) % 256
  local b3 = math.floor(n / 256) % 256
  local b4 = n % 256
  return string.char(b1, b2, b3, b4)
end

local function dec32(s)
  return s:byte(1) * 16777216 + s:byte(2) * 65536 + s:byte(3) * 256 + s:byte(4)
end


local function checksum(data)
  local sum = 0
  for i = 1, #data do
    sum = (sum + data:byte(i)) % 4294967296
  end
  return sum
end


local function tapeRead(drive, n)
  local parts = {}
  local remaining = n
  while remaining > 0 do
    local chunk = drive.read(math.min(remaining, BLOCK))
    if not chunk or #chunk == 0 then return nil end
    parts[#parts + 1] = chunk
    remaining = remaining - #chunk
  end
  return table.concat(parts)
end


local function tapeWrite(drive, data)
  local written = 0
  while written < #data do
    local chunk = data:sub(written + 1, written + BLOCK)
    drive.write(chunk)
    written = written + #chunk
  end
end


local function rewind(drive)
  drive.seek(-drive.getSize())
end


local function seekTo(drive, pos)
  rewind(drive)
  if pos > 0 then
    drive.seek(pos)
  end
end


local function fmtSize(n)
  if n >= 1048576 then
    return string.format("%.1fMB", n / 1048576)
  elseif n >= 1024 then
    return string.format("%.1fKB", n / 1024)
  end
  return n .. "B"
end




local function tapeMinutes(sizeBytes)
  return sizeBytes / 262144
end


local function fmtCapacity(size)
  local mins = tapeMinutes(size)
  if mins >= 1 then
    return string.format("%s (%d-minute tape)", fmtSize(size), math.floor(mins + 0.5))
  end
  return fmtSize(size)
end


local HEADER_FIXED = 16

local EOA_SIZE = 4


local function entryTapeSize(pathLen, dataLen)
  return HEADER_FIXED + pathLen + dataLen
end

--! An archive path is RELATIVE, and it has to be relative to the byte.
--!
--! This was `path:sub(#basePath + 1)`, which leaves the separator: with
--! basePath "/home/docs", "/home/docs/a.txt" became "/a.txt" and the base
--! directory itself became "" -> "/". Restore's #SEC C16 guard refuses an
--! absolute path by rewinding and RETURNING, so the first entry aborted
--! the whole restore and a directory archive restored nothing at all.
--!
--! Single files escaped it because fs.split returns "/home/" WITH the
--! trailing slash, so the same arithmetic came out clean -- which is
--! exactly why a manual test of `tape store <file>` looked fine.
--!
--! The base directory itself is "." (fs.join(dest, ".") normalizes back
--! to dest, so restore recreates the destination and nothing else).
--! (test_tape_archive.lua)
local function relativeTo(basePath, full)
  if #basePath > 1 and full:sub(1, #basePath) == basePath then
    full = full:sub(#basePath + 1)
  end
  full = full:gsub("^/+", "")
  if full == "" then full = "." end
  return full
end



local function scanArchive(drive)
  rewind(drive)
  local info = { used = 0, files = 0, dirs = 0, dataBytes = 0 }

  while true do
    local magic = tapeRead(drive, 4)
    if not magic or #magic < 4 then break end
    if magic == EOA then
      info.used = info.used + EOA_SIZE
      break
    end
    if magic ~= MAGIC then break end

    local verFlag = tapeRead(drive, 2)
    if not verFlag then break end
    local flags = verFlag:byte(2)

    local pathLenRaw = tapeRead(drive, 2)
    if not pathLenRaw then break end
    local pathLen = dec16(pathLenRaw)

    local relPath = tapeRead(drive, pathLen)
    if not relPath then break end

    local dataLenRaw = tapeRead(drive, 4)
    if not dataLenRaw then break end
    local dataLen = dec32(dataLenRaw)

    
    tapeRead(drive, 4)

    local isDir = (flags % 2) == 1
    local overhead = HEADER_FIXED + pathLen

    if isDir then
      info.dirs = info.dirs + 1
      info.used = info.used + overhead
    else
      info.files = info.files + 1
      info.dataBytes = info.dataBytes + dataLen
      info.used = info.used + overhead + dataLen
    end

    
    if dataLen > 0 then
      drive.seek(dataLen)
    end

    
    if (info.files + info.dirs) % 10 == 0 then
      computer.pullSignal(0)
    end
  end

  rewind(drive)
  return info
end




local function cmdDetect(args, o)
  local count = 0
  for addr in component.list("tape_drive") do
    count = count + 1
    local drive = component.proxy(addr)
    local ready = drive.isReady()
    local label = ready and (drive.getLabel() or "(unlabeled)") or "(no tape)"
    local state = drive.getState()
    o(string.format(" %d. %s", count, addr:sub(1, 8)), 0xFFFF00)
    if ready then
      local size = drive.getSize()
      o(string.format("    Label: %s  Capacity: %s  State: %s",
        label, fmtCapacity(size), state), 0xFFFFFF)
    else
      o(string.format("    %s  State: %s", label, state), 0xFFFFFF)
    end
  end
  if count == 0 then
    o("No tape drives found.", 0xFF6600)
    o("Install a Computronics Tape Drive to use this module.", 0xAAAAAA)
  end
end


local function cmdInfo(args, o)
  local drive, err = findDrive(args[2])
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted in drive " .. drive.address:sub(1, 8), 0xFF6600); return
  end
  local size = drive.getSize()
  local mins = tapeMinutes(size)
  o(" Tape Drive Info", 0xFFFF00)
  o("  Address:  " .. drive.address:sub(1, 8), 0xFFFFFF)
  o("  Label:    " .. (drive.getLabel() or "(none)"), 0xFFFFFF)
  o("  Capacity: " .. fmtCapacity(size), 0xFFFFFF)
  o("  Bytes:    " .. size, 0xAAAAAA)
  o("  State:    " .. drive.getState(), 0xFFFFFF)
  
  rewind(drive)
  local header = tapeRead(drive, 4)
  rewind(drive)
  if header == MAGIC then
    o("  Format:   TOS archive", 0x00FF00)
    
    local info = scanArchive(drive)
    local free = size - info.used
    local pctUsed = info.used * 100 / size
    o("", 0xFFFFFF)
    o("  Archive:", 0xFFFF00)
    o(string.format("    Files:    %d files, %d directories", info.files, info.dirs), 0xFFFFFF)
    o(string.format("    Data:     %s (file content)", fmtSize(info.dataBytes)), 0xFFFFFF)
    o(string.format("    Overhead: %s (headers + index)", fmtSize(info.used - info.dataBytes)), 0xAAAAAA)
    o(string.format("    Used:     %s (%.1f%%)", fmtSize(info.used), pctUsed), 0xFFFFFF)
    o(string.format("    Free:     %s (%.1f%%)", fmtSize(free), 100 - pctUsed),
      free < size * 0.1 and 0xFF6600 or 0x00FF00)
  elseif header == EOA then
    o("  Format:   TOS archive (empty)", 0xAAAAAA)
    local free = size - EOA_SIZE
    o(string.format("  Free:     %s (entire tape)", fmtSize(free)), 0x00FF00)
  elseif header then
    o("  Format:   Unknown / raw data", 0xAAAAAA)
    o("  Use 'tape dump 0 64' to inspect contents.", 0xAAAAAA)
  else
    o("  Format:   Blank", 0xAAAAAA)
    o(string.format("  Free:     %s (entire tape)", fmtSize(size)), 0x00FF00)
  end
end


local function cmdLabel(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end
  if args[2] then
    local name = table.concat(args, " ", 2)
    drive.setLabel(name)
    o("Label set: " .. name, 0x00FF00)
  else
    local lbl = drive.getLabel()
    if lbl and lbl ~= "" then
      o("Current label: " .. lbl, 0xFFFFFF)
    else
      o("Tape has no label. Use: tape label <name>", 0xAAAAAA)
    end
  end
end


local function cmdStore(args, o)
  local path = args[2]
  if not path then
    o("Usage: tape store <path> [--overwrite]", 0xAAAAAA)
    o("  Archives a file or directory to the tape.", 0xAAAAAA)
    o("  Appends after existing archive data by default.", 0xAAAAAA)
    o("  Use --overwrite to replace the entire archive.", 0xAAAAAA)
    return
  end

  
  local overwrite = false
  local pathArg = nil
  for i = 2, #args do
    if args[i] == "--overwrite" then
      overwrite = true
    else
      pathArg = args[i]
    end
  end
  if pathArg then path = pathArg end
  if not path or path == "" then
    o("Usage: tape store <path> [--overwrite]", 0xAAAAAA); return
  end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  drive.stop()

  
  path = fs.normalize(path)
  if not fs.exists(path) then
    o("Path not found: " .. path, 0xFF0000); return
  end

  local entries = {}  
  local basePath = path

  local function scan(dir)
    entries[#entries + 1] = { path = dir, isDir = true }
    local list = fs.list(dir)
    if not list then return end
    for _, name in ipairs(list) do
      local full = fs.join(dir, name)
      if fs.isDirectory(full) then
        scan(full)
      else
        entries[#entries + 1] = { path = full, isDir = false }
      end
    end
  end

  if fs.isDirectory(path) then
    scan(path)
  else
    entries[#entries + 1] = { path = path, isDir = false }
    basePath = fs.split(path) or "/"
  end

  
  
  
  local tapeSize = drive.getSize()
  local appendPos = 0
  local existingUsed = 0  

  if not overwrite then
    rewind(drive)
    local headerCheck = tapeRead(drive, 4)
    rewind(drive)
    if headerCheck == MAGIC then
      local info = scanArchive(drive)
      if info.used > EOA_SIZE then
        existingUsed = info.used - EOA_SIZE  
        appendPos = existingUsed
        o(string.format("Existing archive: %d files, %d dirs (%s)",
          info.files, info.dirs, fmtSize(info.used)), 0x00AAFF)
        o("Appending after existing entries...", 0xAAAAAA)
      end
    elseif headerCheck == EOA then
      
      existingUsed = 0
      appendPos = 0
    end
  end

  
  
  local estimatedBytes = EOA_SIZE  
  local estimateFiles = 0
  local estimateData = 0
  for _, entry in ipairs(entries) do
    local relPath = relativeTo(basePath, entry.path)
    if entry.isDir then
      estimatedBytes = estimatedBytes + entryTapeSize(#relPath, 0)
    else
      local sz = fs.size(entry.path) or 0
      estimatedBytes = estimatedBytes + entryTapeSize(#relPath, sz)
      estimateData = estimateData + sz
      estimateFiles = estimateFiles + 1
    end
  end

  local availableSpace = tapeSize - existingUsed

  o(string.format("Archiving %d entries from %s", #entries, path), 0x00AAFF)
  o(string.format("  New data size:  %s (%s data + %s overhead)",
    fmtSize(estimatedBytes),
    fmtSize(estimateData),
    fmtSize(estimatedBytes - estimateData - EOA_SIZE)), 0xAAAAAA)
  if existingUsed > 0 then
    o(string.format("  Existing data:  %s", fmtSize(existingUsed)), 0xAAAAAA)
  end
  o(string.format("  Tape capacity:  %s", fmtCapacity(tapeSize)), 0xAAAAAA)

  if estimatedBytes > availableSpace then
    local over = estimatedBytes - availableSpace
    o(string.format("  WARNING: Data exceeds available space by %s!", fmtSize(over)), 0xFF6600)
    o("  Some files will not fit. Writing what we can...", 0xFF6600)
  else
    local afterFree = availableSpace - estimatedBytes
    local totalUsed = existingUsed + estimatedBytes
    o(string.format("  After write:    %s free (%.1f%% used)",
      fmtSize(afterFree), totalUsed * 100 / tapeSize), 0x00FF00)
  end
  o("", 0xFFFFFF)

  
  
  seekTo(drive, appendPos)
  local totalBytes = 0
  local fileCount = 0

  for _, entry in ipairs(entries) do
    
    local relPath = relativeTo(basePath, entry.path)

    local flags = entry.isDir and FLAG_DIR or 0
    local data = ""
    if not entry.isDir then
      data = fs.readFile(entry.path) or ""
      fileCount = fileCount + 1
    end

    
    local pathBytes = relPath
    local header = MAGIC
      .. string.char(VERSION)
      .. string.char(flags)
      .. enc16(#pathBytes)
      .. pathBytes
      .. enc32(#data)
      .. enc32(checksum(data))

    
    local needed = #header + #data
    if existingUsed + totalBytes + needed + EOA_SIZE > tapeSize then
      o("WARNING: Tape full after " .. fileCount .. " files.", 0xFF6600)
      break
    end

    tapeWrite(drive, header)
    if #data > 0 then
      tapeWrite(drive, data)
    end
    totalBytes = totalBytes + needed

    
    if fileCount % 5 == 0 then
      computer.pullSignal(0)
    end
  end

  
  tapeWrite(drive, EOA)
  totalBytes = totalBytes + EOA_SIZE

  rewind(drive)
  local totalOnTape = existingUsed + totalBytes
  local freeAfter = tapeSize - totalOnTape
  o(string.format("Done: %d files, %s written", fileCount, fmtSize(totalBytes)), 0x00FF00)
  o(string.format("Tape: %s free (%.1f%% used)",
    fmtSize(freeAfter), totalOnTape * 100 / tapeSize),
    freeAfter < tapeSize * 0.1 and 0xFF6600 or 0x00FF00)
end


local function cmdRestore(args, o)
  local destBase = args[2] or "/home"
  destBase = fs.normalize(destBase)

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  drive.stop()
  rewind(drive)

  o("Restoring from tape to " .. destBase .. " ...", 0x00AAFF)

  local fileCount = 0
  local dirCount = 0
  local totalBytes = 0

  while true do
    
    local magic = tapeRead(drive, 4)
    if not magic or #magic < 4 then
      o("Unexpected end of tape", 0xFF6600)
      break
    end

    
    if magic == EOA then
      break
    end

    if magic ~= MAGIC then
      o("Not a TOS archive (bad magic at byte " .. totalBytes .. ")", 0xFF0000)
      rewind(drive)
      return
    end

    
    local verFlag = tapeRead(drive, 2)
    if not verFlag then o("Truncated header", 0xFF0000); break end
    local ver   = verFlag:byte(1)
    local flags = verFlag:byte(2)

    if ver > VERSION then
      o("Archive version " .. ver .. " not supported (max " .. VERSION .. ")", 0xFF0000)
      rewind(drive)
      return
    end

    local pathLenRaw = tapeRead(drive, 2)
    if not pathLenRaw then o("Truncated header", 0xFF0000); break end
    local pathLen = dec16(pathLenRaw)

    local relPath = tapeRead(drive, pathLen)
    if not relPath then o("Truncated path", 0xFF0000); break end

    local dataLenRaw = tapeRead(drive, 4)
    if not dataLenRaw then o("Truncated header", 0xFF0000); break end
    local dataLen = dec32(dataLenRaw)

    local cksumRaw = tapeRead(drive, 4)
    if not cksumRaw then o("Truncated header", 0xFF0000); break end
    local expectedSum = dec32(cksumRaw)

    totalBytes = totalBytes + 4 + 2 + 2 + pathLen + 4 + 4

    local isDir = (flags % 2) == 1
    
    
    
    
    
    if type(relPath) ~= "string" or relPath == "" then
      o("Skipping entry with empty path", 0xFF6600)
      break
    end
    if relPath:find("\0", 1, true) then
      o("REFUSING tainted path from tape: " .. relPath, 0xFF0000)
      rewind(drive); return
    end
    --! A leading slash is STRIPPED, not refused. What contains a hostile
    --! path is the join under destBase plus the baseGuard check below --
    --! "/etc/users.dat" becomes "etc/users.dat" and lands inside the
    --! destination, which is the correct outcome. Refusing it outright
    --! also refused every tape written before the store side was fixed,
    --! and refusing meant aborting the whole restore.
    relPath = relPath:gsub("^/+", "")
    if relPath == "" then relPath = "." end
    
    do
      local bad = false
      for seg in relPath:gmatch("[^/\\]+") do
        if seg == ".." then bad = true; break end
      end
      if bad then
        o("REFUSING traversal path from tape: " .. relPath, 0xFF0000)
        rewind(drive); return
      end
    end
    local fullPath = fs.join(destBase, relPath)
    
    
    
    local baseGuard = destBase
    if baseGuard:sub(-1) ~= "/" then baseGuard = baseGuard .. "/" end
    if fullPath ~= destBase and fullPath:sub(1, #baseGuard) ~= baseGuard then
      o("REFUSING path that escapes destBase: " .. fullPath, 0xFF0000)
      rewind(drive); return
    end

    if isDir then
      if not fs.exists(fullPath) then
        fs.makeDirectory(fullPath)
      end
      dirCount = dirCount + 1
    else
      
      local data = ""
      if dataLen > 0 then
        data = tapeRead(drive, dataLen)
        if not data then
          o("Truncated data for: " .. relPath, 0xFF0000)
          break
        end
      end
      totalBytes = totalBytes + dataLen

      
      local actualSum = checksum(data)
      if actualSum ~= expectedSum then
        o("CHECKSUM MISMATCH: " .. relPath, 0xFF6600)
        o("  Expected: " .. expectedSum .. " Got: " .. actualSum, 0xFF6600)
        
      end

      
      local parentDir = fs.split(fullPath)
      if parentDir and parentDir ~= "/" and not fs.exists(parentDir) then
        fs.makeDirectory(parentDir)
      end

      fs.writeFile(fullPath, data)
      fileCount = fileCount + 1
    end

    
    if (fileCount + dirCount) % 5 == 0 then
      computer.pullSignal(0)
    end
  end

  rewind(drive)
  local tapeSize = drive.getSize()
  o(string.format("Restored: %d files, %d dirs (%s read from %s tape)",
    fileCount, dirCount, fmtSize(totalBytes), fmtCapacity(tapeSize)), 0x00FF00)
end


local function cmdList(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  local tapeSize = drive.getSize()
  drive.stop()
  rewind(drive)

  local magic = tapeRead(drive, 4)
  if magic == EOA then
    o("Tape archive is empty.", 0xAAAAAA)
    o(string.format("Tape: %s available (%s)", fmtSize(tapeSize - EOA_SIZE), fmtCapacity(tapeSize)), 0x00FF00)
    rewind(drive)
    return
  end
  if magic ~= MAGIC then
    o("Tape does not contain a TOS archive.", 0xFF6600)
    o("Use 'tape dump 0 64' to inspect raw data.", 0xAAAAAA)
    rewind(drive)
    return
  end

  
  rewind(drive)

  o(string.format(" %-6s  %-8s  %s", "Type", "Size", "Path"), 0xFFFF00)
  o(string.rep("-", 40), 0xAAAAAA)

  local fileCount = 0
  local dirCount = 0
  local totalData = 0
  local totalUsed = 0  

  while true do
    local hdrMagic = tapeRead(drive, 4)
    if not hdrMagic or hdrMagic == EOA then
      totalUsed = totalUsed + EOA_SIZE
      break
    end
    if hdrMagic ~= MAGIC then break end

    local verFlag = tapeRead(drive, 2)
    if not verFlag then break end
    local flags = verFlag:byte(2)

    local pathLenRaw = tapeRead(drive, 2)
    if not pathLenRaw then break end
    local pathLen = dec16(pathLenRaw)

    local relPath = tapeRead(drive, pathLen)
    if not relPath then break end

    local dataLenRaw = tapeRead(drive, 4)
    if not dataLenRaw then break end
    local dataLen = dec32(dataLenRaw)

    
    tapeRead(drive, 4)

    local isDir = (flags % 2) == 1
    local entryOverhead = HEADER_FIXED + pathLen

    if isDir then
      o(string.format(" %-6s  %-8s  %s", "DIR", "", relPath), 0x55FF55)
      dirCount = dirCount + 1
      totalUsed = totalUsed + entryOverhead
    else
      o(string.format(" %-6s  %-8s  %s", "FILE", fmtSize(dataLen), relPath), 0xFFFFFF)
      fileCount = fileCount + 1
      totalData = totalData + dataLen
      totalUsed = totalUsed + entryOverhead + dataLen
    end

    
    if dataLen > 0 then
      drive.seek(dataLen)
    end

    if (fileCount + dirCount) % 10 == 0 then
      computer.pullSignal(0)
    end
  end

  rewind(drive)

  local free = tapeSize - totalUsed
  local pctUsed = totalUsed * 100 / tapeSize
  local overhead = totalUsed - totalData - EOA_SIZE

  o("", 0xFFFFFF)
  o(string.format(" %d files, %d dirs | %s data + %s overhead",
    fileCount, dirCount, fmtSize(totalData), fmtSize(overhead)), 0xAAAAAA)
  o(string.format(" Tape: %s used (%.1f%%) | %s free",
    fmtSize(totalUsed), pctUsed, fmtSize(free)),
    free < tapeSize * 0.1 and 0xFF6600 or 0x00FF00)
end


local function cmdErase(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  
  
  local full = args[2] == "full"

  drive.stop()
  rewind(drive)

  if full then
    o("Full erase: wiping " .. fmtSize(drive.getSize()) .. " ...", 0x00AAFF)
    local zeros = string.rep("\0", BLOCK)
    local size = drive.getSize()
    local written = 0
    while written < size do
      local chunk = math.min(BLOCK, size - written)
      if chunk < BLOCK then
        drive.write(string.rep("\0", chunk))
      else
        drive.write(zeros)
      end
      written = written + chunk
      if written % (BLOCK * 16) == 0 then
        computer.pullSignal(0)
      end
    end
    rewind(drive)
    o("Tape erased (" .. fmtSize(size) .. " zeroed)", 0x00FF00)
  else
    
    tapeWrite(drive, EOA)
    rewind(drive)
    o("Tape quick-erased (archive header cleared)", 0x00FF00)
    o("Use 'tape erase full' to zero all bytes", 0xAAAAAA)
  end
end


local function cmdDump(args, o)
  local offset = tonumber(args[2]) or 0
  local length = tonumber(args[3]) or 128

  if length > 1024 then
    length = 1024
    o("(clamped to 1024 bytes)", 0xAAAAAA)
  end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  drive.stop()
  seekTo(drive, offset)

  local data = tapeRead(drive, length)
  if not data then
    o("Could not read tape at offset " .. offset, 0xFF0000)
    rewind(drive)
    return
  end

  o(string.format(" Tape dump: offset %d, %d bytes", offset, #data), 0xFFFF00)
  o("", 0xFFFFFF)

  
  for row = 0, #data - 1, 16 do
    local hex = {}
    local ascii = {}
    for col = 0, 15 do
      local idx = row + col + 1
      if idx <= #data then
        local b = data:byte(idx)
        hex[#hex + 1] = string.format("%02X", b)
        ascii[#ascii + 1] = (b >= 32 and b < 127) and string.char(b) or "."
      else
        hex[#hex + 1] = "  "
        ascii[#ascii + 1] = " "
      end
    end
    local addr = offset + row
    o(string.format(" %06X  %s  %s",
      addr,
      table.concat(hex, " "),
      table.concat(ascii)),
      0xFFFFFF)
  end

  rewind(drive)
end


local function cmdSeek(args, o)
  local pos = tonumber(args[2])
  if not pos then
    o("Usage: tape seek <position>", 0xAAAAAA)
    o("  Moves the tape head to the given byte position.", 0xAAAAAA)
    return
  end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  seekTo(drive, pos)
  o("Tape head at byte " .. pos, 0x00FF00)
end


local function cmdRawRead(args, o)
  
  local offset = tonumber(args[3])
  local length = tonumber(args[4])
  local file   = args[5]

  if not offset or not length or not file then
    o("Usage: tape raw read <offset> <length> <file>", 0xAAAAAA)
    o("  Read raw bytes from tape and save to a file.", 0xAAAAAA)
    return
  end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  drive.stop()
  seekTo(drive, offset)

  o("Reading " .. fmtSize(length) .. " from tape at " .. offset .. " ...", 0x00AAFF)

  
  local fh, ferr = fs.open(file, "w")
  if not fh then
    o("Cannot open file: " .. tostring(ferr), 0xFF0000)
    rewind(drive)
    return
  end

  local remaining = length
  local total = 0
  while remaining > 0 do
    local chunk = drive.read(math.min(remaining, BLOCK))
    if not chunk or #chunk == 0 then
      o("Tape ended after " .. fmtSize(total), 0xFF6600)
      break
    end
    fh:write(chunk)
    total = total + #chunk
    remaining = remaining - #chunk
    if total % (BLOCK * 8) == 0 then computer.pullSignal(0) end
  end
  fh:close()
  rewind(drive)

  o("Saved " .. fmtSize(total) .. " to " .. file, 0x00FF00)
end


local function cmdRawWrite(args, o)
  
  local offset = tonumber(args[3])
  local file   = args[4]

  if not offset or not file then
    o("Usage: tape raw write <offset> <file>", 0xAAAAAA)
    o("  Write raw file contents to tape at the given offset.", 0xAAAAAA)
    return
  end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then
    o("No tape inserted.", 0xFF6600); return
  end

  if not fs.exists(file) then
    o("File not found: " .. file, 0xFF0000); return
  end

  local data = fs.readFile(file)
  if not data then
    o("Cannot read file: " .. file, 0xFF0000); return
  end

  drive.stop()
  seekTo(drive, offset)

  o("Writing " .. fmtSize(#data) .. " to tape at " .. offset .. " ...", 0x00AAFF)
  tapeWrite(drive, data)
  rewind(drive)

  o("Wrote " .. fmtSize(#data) .. " from " .. file, 0x00FF00)
end







local function cmdPlay(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then o("No tape inserted.", 0xFF6600); return end
  local ok, perr = pcall(drive.play)
  if not ok then o("Play failed: " .. tostring(perr), 0xFF0000); return end
  o("Playing.", 0x00FF00)
end

local function cmdStop(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  pcall(drive.stop)
  o("Stopped.", 0x00FF00)
end

local function cmdState(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then o("State: NO_TAPE", 0xFF6600); return end
  local state = "?"
  local okS, s = pcall(drive.getState)
  if okS and s then state = s end
  local okP, pos = pcall(drive.getPosition)
  local okSz, sz = pcall(drive.getSize)
  o("State:    " .. state, 0xFFFFFF)
  if okP and okSz and pos and sz and sz > 0 then
    o(string.format("Position: %s / %s (%d%%)",
      fmtSize(pos), fmtSize(sz),
      math.floor(pos * 100 / sz)), 0xFFFFFF)
  end
  local sp = recalled(drive, "speed")
  if sp then o(string.format("Speed:    %.2fx (set here)", sp), 0xFFFFFF)
  else o("Speed:    not reported by the drive", 0xAAAAAA) end
  local v = recalled(drive, "volume")
  if v then o(string.format("Volume:   %.2f (set here)", v), 0xFFFFFF)
  else o("Volume:   not reported by the drive", 0xAAAAAA) end
end

local function cmdSpeed(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not args[2] then
    local sp = recalled(drive, "speed")
    if sp then o(string.format("Speed set here: %.2fx", sp), 0xFFFFFF)
    else o("The drive does not report its speed (setter only).", 0xAAAAAA) end
    return
  end
  local n = tonumber(args[2])
  if not n or n < 0.25 or n > 2.0 then
    o("Speed must be 0.25..2.0 (got " .. tostring(args[2]) .. ")", 0xFF0000); return
  end
  local ok, err2 = pcall(drive.setSpeed, n)
  if not ok then o("setSpeed failed: " .. tostring(err2), 0xFF0000); return end
  noteSet(drive, "speed", n)
  o(string.format("Speed set to %.2fx", n), 0x00FF00)
end

local function cmdVolume(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not args[2] then
    local v = recalled(drive, "volume")
    if v then o(string.format("Volume set here: %.2f", v), 0xFFFFFF)
    else o("The drive does not report its volume (setter only).", 0xAAAAAA) end
    return
  end
  local n = tonumber(args[2])
  if not n or n < 0 or n > 1 then
    o("Volume must be 0..1 (got " .. tostring(args[2]) .. ")", 0xFF0000); return
  end
  local ok, err2 = pcall(drive.setVolume, n)
  if not ok then o("setVolume failed: " .. tostring(err2), 0xFF0000); return end
  noteSet(drive, "volume", n)
  o(string.format("Volume set to %.2f", n), 0x00FF00)
end

local function cmdRewind(args, o)
  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then o("No tape inserted.", 0xFF6600); return end
  pcall(drive.stop)
  
  local size = drive.getSize() or 0
  if size > 0 then pcall(drive.seek, -size) end
  o("Rewound.", 0x00FF00)
end





local function cmdLoad(args, o)
  local file = args[2]
  if not file then o("Usage: tape load <file.dfpwm>", 0xAAAAAA); return end
  if not fs or not fs.exists or not fs.exists(file) then
    o("Cannot read: " .. tostring(file), 0xFF0000); return
  end
  local data = fs.readFile(file)
  if not data then o("Empty or unreadable: " .. file, 0xFF0000); return end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then o("No tape inserted.", 0xFF6600); return end
  local size = drive.getSize() or 0
  if #data > size then
    o(string.format("File too large for tape (%s > %s)",
      fmtSize(#data), fmtSize(size)), 0xFF0000); return
  end

  
  
  pcall(drive.stop)
  pcall(drive.seek, -size)
  local written = 0
  while written < #data do
    local chunk = data:sub(written + 1, written + BLOCK)
    local ok, werr = pcall(drive.write, chunk)
    if not ok then
      o("write failed at " .. written .. ": " .. tostring(werr), 0xFF0000); return
    end
    written = written + #chunk
    
    if (written / BLOCK) % 8 == 0 then computer.pullSignal(0) end
  end
  pcall(drive.seek, -size)  
  o(string.format("Loaded %s onto tape. Run `tape play` to listen.",
    fmtSize(written)), 0x00FF00)
end









local function loadVault()
  
  
  
  if type(vault) == "table" and vault.encrypt and vault.decrypt then
    return vault
  end
  
  
  local ok, v = pcall(require, "kernel.vault")
  if ok and v then return v end
  return nil
end

--! Largest single Lua string we will build out of tape data. Derived from
--! ACTUAL free RAM rather than a fixed constant: unlike launcher.lua's
--! 64 KiB menu cap, this module legitimately handles multi-MB archives, so
--! the honest ceiling is what the machine can hold. encrypt/decrypt keep the
--! input, the cipher output and the assembled blob alive at once, hence /3.
local function memBudget()
  local free = computer.freeMemory and computer.freeMemory() or 0
  if free <= 0 then return math.huge end  
  return math.floor(free / 3)
end




local function readExact(drive, n)
  local parts, got, blocks = {}, 0, 0
  while got < n do
    local ok, c = pcall(drive.read, math.min(BLOCK, n - got))
    if not ok or type(c) ~= "string" or #c == 0 then break end
    parts[#parts + 1] = c
    got = got + #c
    blocks = blocks + 1
    if (blocks % 8) == 0 then computer.pullSignal(0) end
  end
  if got < n then return nil end
  return table.concat(parts)
end




--! Replaces readWholeTape(), which pulled getSize() bytes into one string on
--! the claim that "tapes typically hold a few hundred KB at most". That is
--! false for a stock 4 MB Computronics tape, and it is the same pattern that
--! caused the "Tape Menu OOMs" bug that launcher.readTapeMenuFromDrive was
--! written to fix (see modules/tape-authenticator/package.lua). scanArchive()
--! already walks the entries structurally, so ask it how long the archive
--! actually is instead of reading the cartridge and discarding the padding.


function mod.readArchiveFromDrive(drive)
  if not (drive and drive.read and drive.seek and drive.getSize) then
    return nil, "no tape drive"
  end
  local size = drive.getSize() or 0
  if size <= 0 then return nil, "No tape data." end
  if drive.stop then pcall(drive.stop) end

  local info = scanArchive(drive)          
  local used = info.used or 0
  if used <= 0 or used > size then
    return nil, "No TOS data archive found on this tape."
  end
  local budget = memBudget()
  if used > budget then
    return nil, string.format(
      "Archive is %s but only ~%s of RAM is safely usable. Free memory first.",
      fmtSize(used), fmtSize(budget))
  end

  rewind(drive)
  local data = readExact(drive, used)
  if not data then return nil, "Short read while loading the archive." end
  return data, nil
end




function mod.readVaultBlobFromDrive(drive)
  if not (drive and drive.read and drive.seek and drive.getSize) then
    return nil, "no tape drive"
  end
  local size = drive.getSize() or 0
  if size <= 0 then return nil, "No tape data." end
  if drive.stop then pcall(drive.stop) end

  rewind(drive)
  local head = size >= VAULT_HEADER and readExact(drive, VAULT_HEADER) or nil
  if not head then
    return nil, "Tape is not encrypted (no TOS vault header)."
  end
  local magic = head:sub(1, 8)
  if magic ~= VAULT_MAGIC_V1 and magic ~= VAULT_MAGIC_V2 then
    return nil, "Tape is not encrypted (no TOS vault header)."
  end

  --! ctLen is LITTLE-endian in the vault format; this module's own dec32 is
  --! big-endian, so decode it explicitly rather than reusing dec32.
  local b1, b2, b3, b4 = head:byte(VAULT_CTLEN_AT, VAULT_CTLEN_AT + 3)
  local ctLen = b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)
  local total = VAULT_HEADER + ctLen
  if ctLen <= 0 or total > size then
    return nil, "Vault blob is truncated or its length field is corrupt."
  end
  local budget = memBudget()
  if total > budget then
    return nil, string.format(
      "Encrypted blob is %s but only ~%s of RAM is safely usable.",
      fmtSize(total), fmtSize(budget))
  end

  local ct = readExact(drive, ctLen)
  if not ct then return nil, "Short read while loading the encrypted blob." end
  return head .. ct, nil
end

local function writeWholeTape(drive, data)
  drive.stop()
  drive.seek(-(drive.getSize() or 0))
  local written = 0
  while written < #data do
    local chunk = data:sub(written + 1, written + BLOCK)
    local ok, werr = pcall(drive.write, chunk)
    if not ok then return false, "write failed at " .. written .. ": " .. tostring(werr) end
    written = written + #chunk
    if (written / BLOCK) % 8 == 0 then computer.pullSignal(0) end
  end
  
  
  local tail = (drive.getSize() or 0) - written
  if tail > 0 then
    local pad = string.rep("\0", math.min(tail, BLOCK))
    while tail > 0 do
      local n = math.min(#pad, tail)
      pcall(drive.write, pad:sub(1, n))
      tail = tail - n
      if (tail / BLOCK) % 8 == 0 then computer.pullSignal(0) end
    end
  end
  drive.stop()
  drive.seek(-(drive.getSize() or 0))
  return true
end






local function tapeFormatGuess(data)
  if not data or #data < 8 then return "empty" end
  if data:sub(1, 4) == MAGIC then return "tos-archive" end
  --! Match BOTH vault wire versions. kernel.vault writes V2 for every new
  --! blob (vault.lua: `local MAGIC = MAGIC_V2`) while still reading V1, so
  --! matching only V1 here made `tape decrypt` reject every tape that
  --! `tape encrypt` had just written — encrypt/decrypt never round-tripped.
  --! The file-based `tape vault` path never had this bug because it asks
  --! v.isEncrypted(), which accepts both.
  local m = data:sub(1, 8)
  if m == VAULT_MAGIC_V1 or m == VAULT_MAGIC_V2 then return "tos-vault" end
  return "unknown"
end

local function cmdEncrypt(args, o)
  local passphrase = args[2]
  if not passphrase or #passphrase < 1 then
    o("Usage: tape encrypt <passphrase>", 0xAAAAAA)
    o("  Encrypts the tape's data archive in place. Refuses if the", 0xAAAAAA)
    o("  tape doesn't start with a TOS archive header (we don't want", 0xAAAAAA)
    o("  to encrypt an audio tape by accident).", 0xAAAAAA)
    return
  end
  local v = loadVault()
  if not v then o("vault module unavailable", 0xFF0000); return end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then o("No tape inserted.", 0xFF6600); return end

  
  
  rewind(drive)
  local head = readExact(drive, math.min(8, drive.getSize() or 0)) or ""
  local kind = tapeFormatGuess(head)
  if kind == "tos-vault" then
    o("Tape is already encrypted. Use 'tape decrypt' first.", 0xFF6600); return
  end
  if kind ~= "tos-archive" then
    o("Tape does not start with a TOS data archive header.", 0xFF6600)
    o("Refusing to encrypt — audio tapes would become unplayable.", 0xFF6600)
    o("Use 'tape store' first, then encrypt.", 0xAAAAAA)
    return
  end

  
  
  local data, rerr = mod.readArchiveFromDrive(drive)
  if not data then o(tostring(rerr), 0xFF0000); return end

  local blob, info = v.encrypt(data, passphrase)
  if not blob then o("encrypt failed: " .. tostring(info), 0xFF0000); return end

  local ok2, werr = writeWholeTape(drive, blob)
  if not ok2 then o(tostring(werr), 0xFF0000); return end
  o(string.format("Encrypted %s -> %s on tape (algo=%s).",
    fmtSize(#data), fmtSize(#blob), info.algo), 0x00FF00)
end

local function cmdDecrypt(args, o)
  local passphrase = args[2]
  if not passphrase or #passphrase < 1 then
    o("Usage: tape decrypt <passphrase>", 0xAAAAAA); return
  end
  local v = loadVault()
  if not v then o("vault module unavailable", 0xFF0000); return end

  local drive, err = findDrive(nil)
  if not drive then o(err, 0xFF0000); return end
  if not drive.isReady() then o("No tape inserted.", 0xFF6600); return end

  
  
  
  local data, rerr = mod.readVaultBlobFromDrive(drive)
  if not data then o(tostring(rerr), 0xFF6600); return end

  local plaintext, dinfo = v.decrypt(data, passphrase)
  if not plaintext then
    o("Decrypt failed: " .. tostring(dinfo), 0xFF0000)
    return
  end

  local ok2, werr = writeWholeTape(drive, plaintext)
  if not ok2 then o(tostring(werr), 0xFF0000); return end
  o(string.format("Decrypted %s -> %s on tape.",
    fmtSize(#data), fmtSize(#plaintext)), 0x00FF00)
end






local function cmdVault(args, o)
  local sub = args[2]
  if sub ~= "encrypt" and sub ~= "decrypt" then
    o("Usage: tape vault encrypt <src> <dst> <passphrase>", 0xAAAAAA)
    o("       tape vault decrypt <src> <dst> <passphrase>", 0xAAAAAA)
    o("  Encrypt or decrypt a file (works on /mnt/<floppy>/ paths too).", 0xAAAAAA)
    return
  end
  local src, dst, passphrase = args[3], args[4], args[5]
  if not src or not dst or not passphrase then
    o("Need src, dst, and passphrase.", 0xFF0000); return
  end
  local v = loadVault()
  if not v then o("vault module unavailable", 0xFF0000); return end
  if not fs.exists(src) then o("No such file: " .. src, 0xFF0000); return end

  local data = fs.readFile(src)
  if not data then o("Cannot read: " .. src, 0xFF0000); return end

  if sub == "encrypt" then
    local blob, info = v.encrypt(data, passphrase)
    if not blob then o("encrypt failed: " .. tostring(info), 0xFF0000); return end
    local ok2, werr = fs.writeFile(dst, blob)
    if not ok2 then o("write failed: " .. tostring(werr), 0xFF0000); return end
    o(string.format("Encrypted %s -> %s (algo=%s).",
      fmtSize(#data), fmtSize(#blob), info.algo), 0x00FF00)
  else
    if not v.isEncrypted(data) then
      o("Source is not a TOS vault blob.", 0xFF6600); return
    end
    local plaintext, dinfo = v.decrypt(data, passphrase)
    if not plaintext then o("Decrypt failed: " .. tostring(dinfo), 0xFF0000); return end
    local ok2, werr = fs.writeFile(dst, plaintext)
    if not ok2 then o("write failed: " .. tostring(werr), 0xFF0000); return end
    o(string.format("Decrypted %s -> %s.",
      fmtSize(#data), fmtSize(#plaintext)), 0x00FF00)
  end
end



local function tapeCmd(args, o)
  local sub = args[1]

  if not sub or sub == "help" then
    o("=== Tape Module ===", 0xFFFF00)
    o("", 0xFFFFFF)
    o(" Discovery & Info", 0x00FF00)
    o("  tape detect           List tape drives and status", 0xFFFFFF)
    o("  tape info             Tape details (label, size, format)", 0xFFFFFF)
    o("  tape state            Current head position, speed, volume", 0xFFFFFF)
    o("  tape label [name]     Get or set tape label", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" Archive Operations", 0x00FF00)
    o("  tape store <path>     Archive file/directory to tape", 0xFFFFFF)
    o("  tape restore [path]   Restore archive to path (default /home)", 0xFFFFFF)
    o("  tape list             List entries in tape archive", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" Audio Playback (EXP-1)", 0x00FF00)
    o("  tape play             Start playback from current position", 0xFFFFFF)
    o("  tape stop             Stop playback", 0xFFFFFF)
    o("  tape rewind           Stop and seek to start of tape", 0xFFFFFF)
    o("  tape speed [0.25-2.0] Get or set playback speed", 0xFFFFFF)
    o("  tape volume [0-1]     Get or set playback volume", 0xFFFFFF)
    o("  tape load <file>      Rewind, write file (DFPWM) to tape", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" Low-Level Tools", 0x00FF00)
    o("  tape dump [off] [len] Hex dump (default: 0, 128)", 0xFFFFFF)
    o("  tape seek <pos>       Move tape head to byte position", 0xFFFFFF)
    o("  tape erase [full]     Quick-erase or full zero-wipe", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" Raw I/O", 0x00FF00)
    o("  tape raw read <off> <len> <file>", 0xFFFFFF)
    o("     Read raw bytes from tape into a file", 0xAAAAAA)
    o("  tape raw write <off> <file>", 0xFFFFFF)
    o("     Write raw file bytes to tape at offset", 0xAAAAAA)
    o("", 0xFFFFFF)
    o(" Encryption (FEAT-10)", 0x00FF00)
    o("  tape encrypt <passphrase>      Encrypt the tape's data archive", 0xFFFFFF)
    o("  tape decrypt <passphrase>      Decrypt the tape's data archive", 0xFFFFFF)
    o("  tape vault encrypt <src> <dst> <passphrase>", 0xFFFFFF)
    o("     Encrypt any file (works on floppy paths too)", 0xAAAAAA)
    o("  tape vault decrypt <src> <dst> <passphrase>", 0xFFFFFF)
    o("     Decrypt any vault file", 0xAAAAAA)
    return
  end

  if     sub == "detect"  then cmdDetect(args, o)
  elseif sub == "info"    then cmdInfo(args, o)
  elseif sub == "state"   then cmdState(args, o)
  elseif sub == "label"   then cmdLabel(args, o)
  elseif sub == "store"   then cmdStore(args, o)
  elseif sub == "restore" then cmdRestore(args, o)
  elseif sub == "list"    then cmdList(args, o)
  elseif sub == "erase"   then cmdErase(args, o)
  elseif sub == "dump"    then cmdDump(args, o)
  elseif sub == "seek"    then cmdSeek(args, o)
  elseif sub == "play"    then cmdPlay(args, o)
  elseif sub == "stop"    then cmdStop(args, o)
  elseif sub == "rewind"  then cmdRewind(args, o)
  elseif sub == "speed"   then cmdSpeed(args, o)
  elseif sub == "volume"  then cmdVolume(args, o)
  elseif sub == "load"    then cmdLoad(args, o)
  elseif sub == "encrypt" then cmdEncrypt(args, o)
  elseif sub == "decrypt" then cmdDecrypt(args, o)
  elseif sub == "vault"   then cmdVault(args, o)
  elseif sub == "raw"     then
    local rawSub = args[2]
    if rawSub == "read"  then cmdRawRead(args, o)
    elseif rawSub == "write" then cmdRawWrite(args, o)
    else
      o("Usage: tape raw read|write ...", 0xAAAAAA)
      o("  tape raw read <offset> <length> <file>", 0xAAAAAA)
      o("  tape raw write <offset> <file>", 0xAAAAAA)
    end
  else
    o("Unknown subcommand: " .. tostring(sub), 0xFF6600)
    o("Type 'tape help' for usage.", 0xAAAAAA)
  end
end




mod.commands = {
  tape = tapeCmd,
}

return mod
