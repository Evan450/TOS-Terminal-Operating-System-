local backup = {}

local MAGIC = "TOSBAK1\0"
local MAX_ENTRY_PATH    = 256
local MAX_ENTRY_BYTES   = 1024 * 1024
local MAX_TOTAL_ENTRIES = 4096
local DEFAULT_EXCLUDES  = {

  [".trash"]      = true,
  ["tmp"]         = true,
}

local securefs = nil
local fs       = nil
local crypto   = nil
local log      = nil

function backup.init(modules)
  securefs = modules.securefs
  fs       = modules.fs
  crypto   = modules.crypto
  log      = modules.log
end

local function packU8(n)  return string.char(n & 0xFF) end
local function packU16(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF)
end
local function packU32(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
end

local function unpackU8(s, off)
  return s:byte(off), off + 1
end
local function unpackU16(s, off)
  return s:byte(off) | (s:byte(off + 1) << 8), off + 2
end
local function unpackU32(s, off)
  return s:byte(off)
    | (s:byte(off + 1) << 8)
    | (s:byte(off + 2) << 16)
    | (s:byte(off + 3) << 24), off + 4
end

local function walkTree(srcRoot, session, excludes)
  local entries = {}
  excludes = excludes or DEFAULT_EXCLUDES
  local count = 0

  local function visit(rel)
    if count >= MAX_TOTAL_ENTRIES then return end
    local full = (rel == "") and srcRoot or (srcRoot .. rel)
    if not securefs.exists(full, session) then return end
    if securefs.isDirectory(full, session) then

      if rel ~= "" then
        count = count + 1
        entries[count] = { rel = rel, isDir = true }
      end
      local list = securefs.list(full, session)
      if type(list) == "table" then
        for _, name in ipairs(list) do
          local clean = name:gsub("/$", "")
          if not excludes[clean] then
            visit(rel .. "/" .. clean)
          end
        end
      end
    else
      count = count + 1
      local sz = securefs.size(full, session) or 0
      if sz > MAX_ENTRY_BYTES then

        if log then
          log.warn("backup", "Skipping oversized file: " .. full ..
            " (" .. sz .. " > " .. MAX_ENTRY_BYTES .. ")")
        end
        count = count - 1
        return
      end
      entries[count] = { rel = rel, isDir = false, size = sz }
    end
  end

  visit("")
  return entries
end

local function encodeSnapshot(srcRoot, entries, session)
  local parts = {}
  local function emit(s) parts[#parts + 1] = s end

  local bodyParts = {}
  local function emitBody(s) bodyParts[#bodyParts + 1] = s end

  for _, e in ipairs(entries) do
    local flags = e.isDir and 1 or 0
    emitBody(packU8(flags))
    emitBody(packU16(#e.rel))
    emitBody(e.rel)
    if e.isDir then
      emitBody(packU32(0))
      emitBody(string.rep("0", 64))
    else
      local data = securefs.readFile(srcRoot .. e.rel, session) or ""
      emitBody(packU32(#data))
      emitBody(data)
      emitBody(crypto and crypto.hash(data) or string.rep("0", 64))
    end
  end

  local body = table.concat(bodyParts)

  local rootBytes = srcRoot
  local now = (os.time and os.time()) or 0
  emit(MAGIC)
  emit(packU32(now))
  emit(packU32(#entries))
  emit(packU16(#rootBytes))
  emit(rootBytes)

  local metaHash = crypto and crypto.hash(body) or string.rep("0", 64)
  emit(metaHash)
  emit(body)

  return table.concat(parts), {
    entries = #entries,
    bytes   = 0,
    root    = srcRoot,
    created = now,
    hash    = metaHash,
  }
end

function backup.snapshot(srcRoot, destPath, opts)
  if not securefs or not fs then return false, "backup not initialized" end
  opts = opts or {}
  local session = opts.session
    or (_G._TOS and _G._TOS.users and _G._TOS.users.currentSession())
    or nil
  if not session then return false, "no session" end

  srcRoot = securefs.normalize(srcRoot)
  if srcRoot == "/" then

    return false, "backup of / is not supported (use the tape package for full images)"
  end
  if not securefs.exists(srcRoot, session) then
    return false, "source not found: " .. srcRoot
  end
  if not securefs.isDirectory(srcRoot, session) then
    return false, "source is not a directory: " .. srcRoot
  end

  destPath = securefs.normalize(destPath)
  if securefs.isDirectory(destPath, session) then
    return false, "destination is a directory; pass a file path"
  end

  if destPath:sub(1, #srcRoot + 1) == srcRoot .. "/" then
    return false, "destination must be outside source"
  end

  local entries = walkTree(srcRoot, session, opts.exclude)
  if #entries == 0 then
    return false, "no files to back up under " .. srcRoot
  end
  if #entries >= MAX_TOTAL_ENTRIES then
    return false, "tree exceeds " .. MAX_TOTAL_ENTRIES .. " entries"
  end

  local blob, summary = encodeSnapshot(srcRoot, entries, session)
  summary.bytes = #blob

  local ok, err = securefs.writeFile(destPath, blob, session)
  if not ok then return false, "write failed: " .. tostring(err) end

  if log then
    log.info("backup", string.format("Snapshot %s -> %s (%d entries, %d bytes)",
      srcRoot, destPath, summary.entries, summary.bytes))
  end
  return true, summary
end

function backup.inspect(srcPath, opts)
  if not securefs then return nil, "backup not initialized" end
  opts = opts or {}
  local session = opts.session
    or (_G._TOS and _G._TOS.users and _G._TOS.users.currentSession())
    or nil
  if not session then return nil, "no session" end
  local raw = securefs.readFile(srcPath, session)
  if not raw then return nil, "cannot read: " .. srcPath end
  if #raw < #MAGIC + 4 + 4 + 2 + 64 then return nil, "truncated header" end
  if raw:sub(1, #MAGIC) ~= MAGIC then return nil, "bad magic (not a TOS backup)" end
  local off = #MAGIC + 1
  local created;     created,    off = unpackU32(raw, off)
  local fileCount;   fileCount,  off = unpackU32(raw, off)
  local rootLen;     rootLen,    off = unpackU16(raw, off)
  if rootLen > MAX_ENTRY_PATH then return nil, "header: root path too long" end
  local root = raw:sub(off, off + rootLen - 1); off = off + rootLen
  local metaHash = raw:sub(off, off + 63);      off = off + 64
  return {
    magic    = MAGIC,
    created  = created,
    entries  = fileCount,
    root     = root,
    metaHash = metaHash,
    bodyOff  = off,
    size     = #raw,
  }
end

function backup.restore(srcPath, opts)
  if not securefs then return false, "backup not initialized" end
  opts = opts or {}
  local session = opts.session
    or (_G._TOS and _G._TOS.users and _G._TOS.users.currentSession())
    or nil
  if not session then return false, "no session" end

  local info, err = backup.inspect(srcPath, { session = session })
  if not info then return false, err end

  local destRoot = securefs.normalize(opts.destRoot or info.root)
  if destRoot == "/" then return false, "refusing to restore to /" end

  if securefs.exists(destRoot, session) and not opts.force then
    if securefs.isDirectory(destRoot, session) then
      local list = securefs.list(destRoot, session)
      if type(list) == "table" and #list > 0 then
        return false, "destRoot non-empty; pass force=true to overwrite: " .. destRoot
      end
    end
  end

  if not securefs.exists(destRoot, session) then
    securefs.makeDirectory(destRoot, session)
  end

  local raw = securefs.readFile(srcPath, session)
  if not raw then return false, "cannot read: " .. srcPath end

  local body = raw:sub(info.bodyOff)
  if crypto then
    local liveHash = crypto.hash(body)
    if not crypto.ctEquals(liveHash, info.metaHash) then
      return false, "backup integrity check failed (metaHash mismatch)"
    end
  end

  local off = 1
  local restored = 0
  for i = 1, info.entries do
    if off > #body then return false, "truncated body at entry " .. i end
    local flags;     flags,   off = unpackU8(body, off)
    local pathLen;   pathLen, off = unpackU16(body, off)
    if pathLen > MAX_ENTRY_PATH then return false, "entry " .. i .. ": path too long" end
    local relPath = body:sub(off, off + pathLen - 1); off = off + pathLen

    if relPath:sub(1, 1) ~= "/" then
      return false, "entry " .. i .. ": unsafe path " .. relPath
    end
    local dataLen;   dataLen, off = unpackU32(body, off)
    if dataLen > MAX_ENTRY_BYTES then return false, "entry " .. i .. ": data too large" end
    local data = body:sub(off, off + dataLen - 1); off = off + dataLen
    local hash = body:sub(off, off + 63);          off = off + 64

    local fullDest = securefs.normalize(destRoot .. relPath)
    if fullDest ~= destRoot
       and fullDest:sub(1, #destRoot + 1) ~= destRoot .. "/" then
      return false, "entry " .. i .. ": path escapes destRoot: " .. relPath
    end
    local isDir = (flags & 1) == 1
    if isDir then
      if not securefs.exists(fullDest, session) then
        securefs.makeDirectory(fullDest, session)
      end
    else

      if crypto and #data > 0 then
        local liveHash = crypto.hash(data)
        if not crypto.ctEquals(liveHash, hash) then
          if log then
            log.warn("backup", "Skipping entry with bad hash: " .. relPath)
          end
        else

          local parent = fullDest:match("^(.+)/[^/]+$")
          if parent and parent ~= "" and not securefs.exists(parent, session) then

            local accum = ""
            for seg in parent:gmatch("[^/]+") do
              accum = accum .. "/" .. seg
              if not securefs.exists(accum, session) then
                securefs.makeDirectory(accum, session)
              end
            end
          end
          local wOk, wErr = securefs.writeFile(fullDest, data, session)
          if wOk then restored = restored + 1
          elseif log then
            log.warn("backup", "Restore write failed: " .. fullDest .. ": " ..
              tostring(wErr))
          end
        end
      end
    end
  end

  if log then
    log.info("backup", string.format("Restored %d files from %s -> %s",
      restored, srcPath, destRoot))
  end
  return true, { entries = info.entries, restored = restored, destRoot = destRoot }
end

return backup
