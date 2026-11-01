-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Packages as archives                        ║
-- ║                                                           ║
-- ║  `pkg compact` turns a package's files under /usr into    ║
-- ║  one mtar archive, compressed if there is a data card,    ║
-- ║  and this serves them back from it. OC charges 512 bytes  ║
-- ║  for every file on top of its content, so one file is     ║
-- ║  cheaper than seventy before anything is compressed.      ║
-- ║                                                           ║
-- ║  It sits under /usr as the lower half of a copy-on-write  ║
-- ║  overlay. The disk's real /usr is the upper half, so      ║
-- ║  everything else there is untouched and still writable,   ║
-- ║  and a package that was never compacted cannot tell.      ║
-- ║  With no archive on the machine none of this loads.       ║
-- ║                                                           ║
-- ║  mtar, not a format of ours: four other systems read it.  ║
-- ║  An entry is FF FF 01, a >I2 name length, the name, a     ║
-- ║  >I8 data length and the data.                            ║
-- ╚══════════════════════════════════════════════════════════╝

local pkgfs = {}

local DIR = "/var/pkg/archive"
local fs, log
local raw                  -- the root disk's proxy: /usr is ours, so never fs
local entries, dirs = {}, {}
local archives = {}        -- name -> archive path
local overlay              -- the proxy mounted at /usr, once there is one

pkgfs.DIR = DIR

local function compressor()
  local K = _G._TOS and _G._TOS.kernel
  return K and K.getCompress and K.getCompress() or nil
end

-- ── mtar ─────────────────────────────────────────────────────

function pkgfs.entry(name, data)
  return "\255\255\1" .. string.pack(">I2", #name) .. name
    .. string.pack(">I8", #data) .. data
end

--- Read exactly n bytes from a handle, however the proxy chunks them.
local function readN(px, h, n)
  local parts, got = {}, 0
  while got < n do
    local c = px.read(h, math.min(n - got, 4096))
    if not c then break end
    parts[#parts + 1] = c
    got = got + #c
  end
  return table.concat(parts)
end

--- Walk an archive without loading it. fn(name, offset, length). A path that
--- climbs out is refused here, once, rather than at every reader: an archive
--- is only as trusted as the disk it sits on.
function pkgfs.scan(px, path, fn)
  local h, err = px.open(path, "r")
  if not h then return nil, err end
  local pos = 0
  local ok, why = true, nil
  while true do
    local head = readN(px, h, 5)
    if #head == 0 then break end
    if #head < 5 or head:sub(1, 3) ~= "\255\255\1" then
      ok, why = false, "not an mtar v1 archive at byte " .. pos
      break
    end
    local nameLen = string.unpack(">I2", head, 4)
    local name = readN(px, h, nameLen)
    local lenBytes = readN(px, h, 8)
    if #name < nameLen or #lenBytes < 8 then
      ok, why = false, "truncated at byte " .. pos
      break
    end
    local len = string.unpack(">I8", lenBytes)
    pos = pos + 5 + nameLen + 8
    for seg in name:gmatch("[^/]+") do
      if seg == ".." then ok, why = false, "unsafe path in archive: " .. name end
    end
    if not ok then break end
    fn(name, pos, len, h)
    px.seek(h, "cur", len)
    pos = pos + len
  end
  px.close(h)
  if ok then return true end
  return nil, why
end

-- ── The read-only side ───────────────────────────────────────

local function dirOf(path) return path:match("^(.*)/[^/]*$") or "" end

local function index(name, path, offset, len)
  local e = { archive = name, offset = offset, len = len }
  entries[path] = e
  local d = dirOf(path)
  while d ~= "" do
    if dirs[d] then break end
    dirs[d] = true
    d = dirOf(d)
  end
  return e
end

--- An entry's bytes, unpacked.
local function entryBytes(e)
  local h, err = raw.open(archives[e.archive], "r")
  if not h then return nil, err end
  raw.seek(h, "set", e.offset)
  local blob = readN(raw, h, e.len)
  raw.close(h)
  if #blob ~= e.len then return nil, "archive is short" end
  local cz = compressor()
  if blob:sub(1, 4) == "TCZ1" or (cz and cz.isPacked and cz.isPacked(blob)) then
    if not cz then return nil, "this package needs a data card to read" end
    return cz.unpack(blob)
  end
  return blob
end

local lower = { address = "pkgfs" }
function lower.getLabel() return "packages" end
function lower.spaceTotal() return 0 end
function lower.spaceUsed() return 0 end
function lower.isReadOnly() return true end
function lower.exists(p) return p == "/" or entries[p] ~= nil or dirs[p] == true end
function lower.isDirectory(p) return p == "/" or dirs[p] == true end
function lower.size(p)
  local e = entries[p]
  if not e then return 0 end
  if e.size then return e.size end
  local data = entryBytes(e)
  e.size = data and #data or 0
  return e.size
end
function lower.lastModified() return 0 end
function lower.list(p)
  local prefix = p == "/" and "/" or (p .. "/")
  local seen, out = {}, {}
  local function take(path, isDir)
    if path:sub(1, #prefix) == prefix then
      local rest = path:sub(#prefix + 1)
      local name = rest:match("^[^/]+")
      if name and not seen[name] then
        seen[name] = true
        local deeper = isDir or rest:find("/", 1, true) ~= nil
        out[#out + 1] = name .. (deeper and "/" or "")
      end
    end
  end
  for path in pairs(entries) do take(path, false) end
  for path in pairs(dirs) do take(path, true) end
  table.sort(out)
  return out
end

local open, nextId = {}, 1
function lower.open(p, mode)
  if mode and mode:sub(1, 1) ~= "r" then return nil, "read-only" end
  local e = entries[p]
  if not e then return nil, p end
  local data, err = entryBytes(e)
  if not data then return nil, err end
  local id = nextId
  nextId = nextId + 1
  open[id] = { data = data, pos = 1 }
  return id
end
function lower.read(id, n)
  local st = open[id]
  if not st or st.pos > #st.data then return nil end
  local c = st.data:sub(st.pos, st.pos + (n or 4096) - 1)
  st.pos = st.pos + #c
  return c
end
function lower.seek(id, whence, offset)
  local st = open[id]
  if not st then return nil end
  local base = whence == "set" and 0 or whence == "end" and #st.data or st.pos - 1
  st.pos = base + (offset or 0) + 1
  return st.pos - 1
end
function lower.close(id) open[id] = nil; return true end
function lower.write() return nil, "read-only" end
function lower.remove() return false end
function lower.rename() return false end
function lower.makeDirectory() return false end

pkgfs.lower = lower

-- ── Under /usr ───────────────────────────────────────────────

--- Put the overlay at /usr, once, the first time there is an archive.
local function ensureMounted()
  if overlay then return true end
  local cowfs = require("kernel.cowfs")
  local px = cowfs.new(lower, cowfs.sub(raw, "/usr"), { label = "/usr+packages" })
  local ok, err = fs.mount("/usr", px, { over = true })
  if not ok then return nil, err end
  overlay = px
  return true
end

local function forget(name)
  for path, e in pairs(entries) do
    if e.archive == name then entries[path] = nil end
  end
  for path in pairs(dirs) do dirs[path] = nil end
  for path in pairs(entries) do
    local d = dirOf(path)
    while d ~= "" and not dirs[d] do
      dirs[d] = true
      d = dirOf(d)
    end
  end
  archives[name] = nil
end

local function addArchive(name, path)
  archives[name] = path
  local ok, err = pkgfs.scan(raw, path, function(rel, offset, len)
    index(name, rel, offset, len)
  end)
  if not ok then forget(name) end
  return ok, err
end

function pkgfs.init(deps)
  fs, log = deps.fs, deps.log
  raw = deps.raw or fs.rootProxy()
end

--- Every archive on the disk, under /usr. Boot calls this before anything can
--- want a package's files; a damaged archive costs that package and no other.
function pkgfs.boot(deps)
  pkgfs.init(deps)
  if not raw.exists(DIR) then return 0 end
  local n = 0
  for _, f in ipairs(raw.list(DIR) or {}) do
    local name = f:match("^(.+)%.mtar$")
    if name then
      local ok, err = addArchive(name, DIR .. "/" .. f)
      if ok then
        n = n + 1
      elseif log and log.error then
        pcall(log.error, "pkgfs", name .. " did not load: " .. tostring(err))
      end
    end
  end
  if n > 0 then
    local ok, err = ensureMounted()
    if not ok and log and log.error then
      pcall(log.error, "pkgfs", "could not mount /usr: " .. tostring(err))
    end
  end
  return n
end

function pkgfs.has(name) return archives[name] ~= nil end

function pkgfs.list()
  local out = {}
  for name in pairs(archives) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- ── compact and expand ───────────────────────────────────────

--- `targets` are absolute paths under /usr. Nothing loose goes until every
--- entry has been read back through the path a reader will use and matched
--- byte for byte, so a compact that fails has lost nothing.
function pkgfs.compact(name, targets)
  local path = DIR .. "/" .. name .. ".mtar"
  if archives[name] then return nil, "already compact: " .. name end
  if not raw.exists(DIR) then raw.makeDirectory(DIR) end
  local tmp = path .. ".tmp"
  local h, err = raw.open(tmp, "w")
  if not h then return nil, err end

  local cz = compressor()
  local before, packed = 0, false
  local sources = {}
  for _, target in ipairs(targets) do
    local data, rerr = fs.readFile(target)
    if not data then
      raw.close(h)
      raw.remove(tmp)
      return nil, "cannot read " .. target .. ": " .. tostring(rerr)
    end
    before = before + #data + 512
    sources[target:sub(5)] = data
    local blob = data
    if cz and cz.pack then
      local b, method = cz.pack(data)
      if b and method == "deflate" then blob, packed = b, true end
    end
    if not raw.write(h, pkgfs.entry(target:sub(5), blob)) then
      raw.close(h)
      raw.remove(tmp)
      return nil, "disk full"
    end
  end
  raw.close(h)

  local after = raw.size(tmp) + 512
  if after >= before then
    raw.remove(tmp)
    return nil, "an archive would not be smaller"
  end

  -- Read it all back, the way a reader will, before anything is deleted.
  if raw.exists(path) then raw.remove(path) end
  if not raw.rename(tmp, path) then
    raw.remove(tmp)
    return nil, "could not put the archive in place"
  end
  local ok, serr = addArchive(name, path)
  local bad = serr
  if ok then
    for rel, data in pairs(sources) do
      local e = entries[rel]
      local back = e and entryBytes(e)
      if back ~= data then bad = "read-back differs for /usr" .. rel; break end
    end
  end
  if bad then
    forget(name)
    raw.remove(path)
    return nil, bad
  end

  local mok, merr = ensureMounted()
  if not mok then
    forget(name)
    raw.remove(path)
    return nil, merr
  end
  local cowfs = require("kernel.cowfs")
  local upper = cowfs.sub(raw, "/usr")
  for _, target in ipairs(targets) do
    cowfs.unhide(upper, target:sub(5))
    raw.remove(target)
  end
  -- An empty directory costs what a file does, and the listing comes from the
  -- archive now.
  for _, target in ipairs(targets) do
    local d = dirOf(target)
    while d ~= "/usr" and d ~= "" do
      local list = raw.list(d)
      if not list or #list > 0 then break end
      raw.remove(d)
      d = dirOf(d)
    end
  end
  return true, { before = before, after = after, packed = packed, files = #targets }
end

--- Back to loose files, verified, and only then is the archive gone.
function pkgfs.expand(name)
  if not archives[name] then return nil, "not compact: " .. name end
  local mok, merr = ensureMounted()
  if not mok then return nil, merr end
  local upper = require("kernel.cowfs").sub(raw, "/usr")

  -- Only what still shows from the archive. A file edited since is already
  -- loose and newer, and one removed since stays removed.
  local todo = {}
  for rel, e in pairs(entries) do
    if e.archive == name and overlay.exists(rel) and not upper.exists(rel) then todo[rel] = e end
  end

  --! Everything goes to a temp name, and moves only once all of it is written.
  --! A failed write to the real name would leave an empty file on upper, and
  --! upper wins: the good copy in the archive would read as nothing.
  local written = {}
  local function undo()
    for _, t in ipairs(written) do upper.remove(t) end
  end
  for rel, e in pairs(todo) do
    local data, err = entryBytes(e)
    if not data then undo(); return nil, rel .. ": " .. tostring(err) end
    local dir = ""
    for seg in dirOf(rel):gmatch("[^/]+") do
      dir = dir .. "/" .. seg
      if not upper.exists(dir) then upper.makeDirectory(dir) end
    end
    local tmp = rel .. ".tmp"
    local h, oerr = upper.open(tmp, "w")
    if not h then undo(); return nil, oerr end
    written[#written + 1] = tmp
    local okW = upper.write(h, data)
    upper.close(h)
    if not okW or upper.size(tmp) ~= #data then undo(); return nil, "disk full" end
  end
  for rel in pairs(todo) do
    if not upper.rename(rel .. ".tmp", rel) then
      undo()
      return nil, "could not put back /usr" .. rel
    end
  end
  return pkgfs.drop(name)
end

--- Forget an archive and delete it. uninstall uses this: the files are going.
function pkgfs.drop(name)
  local path = archives[name]
  if not path then return nil, "not compact: " .. name end
  forget(name)
  raw.remove(path)
  local cowfs = require("kernel.cowfs")
  cowfs.sweep(cowfs.sub(raw, "/usr"), lower)
  return true
end

return pkgfs
