-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Filesystem Layer       ║
-- ╚══════════════════════════════════════╝

local component = require("component")

local fs = {}

-- Mount table: mountPoint -> filesystem proxy
local mounts = {}
-- Boot filesystem (set during init)
local bootFS = nil

function fs.init(bfs)
  bootFS = bfs
  -- Mount boot drive as root
  mounts["/"] = bootFS
end

-- ============================================================
-- Path utilities
-- ============================================================

--- Normalize a path (resolve . and .., remove double slashes)
function fs.normalize(path)
  if not path or path == "" then return "/" end
  -- Ensure leading slash
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  -- Split and resolve
  local parts = {}
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then
      parts[#parts] = nil
    elseif segment ~= "." then
      parts[#parts + 1] = segment
    end
  end
  local result = "/" .. table.concat(parts, "/")
  return result
end

--- Split path into directory and filename
function fs.split(path)
  path = fs.normalize(path)
  local dir, name = path:match("^(.-)([^/]+)$")
  if not dir or dir == "" then dir = "/" end
  return dir, name or ""
end

--- Join path segments
function fs.join(...)
  local parts = {...}
  return fs.normalize(table.concat(parts, "/"))
end

-- ============================================================
-- Mount management
-- ============================================================

--- Mount a filesystem at a path
function fs.mount(path, proxy)
  path = fs.normalize(path)
  mounts[path] = proxy
  return true
end

--- Unmount
function fs.unmount(path)
  path = fs.normalize(path)
  if path == "/" then return false, "Cannot unmount root" end
  mounts[path] = nil
  return true
end

--- Resolve a path to (filesystem_proxy, relative_path)
local function resolve(path)
  path = fs.normalize(path)
  -- Find longest matching mount point
  local bestMount = "/"
  local bestLen = 1
  for mp in pairs(mounts) do
    if #mp > bestLen then
      -- Match root "/" or prefix with boundary (e.g., /mnt/data must not match /mnt/data2)
      if mp == "/" or (path:sub(1, #mp) == mp and (#path == #mp or path:sub(#mp + 1, #mp + 1) == "/")) then
        bestMount = mp
        bestLen = #mp
      end
    end
  end
  local relPath = path:sub(bestLen + 1)
  if relPath == "" then relPath = "/" end
  if relPath:sub(1, 1) ~= "/" then relPath = "/" .. relPath end
  return mounts[bestMount], relPath
end

-- ============================================================
-- File operations
-- ============================================================

function fs.exists(path)
  local proxy, rel = resolve(path)
  if not proxy then return false end
  local ok, result = pcall(proxy.exists, rel)
  if not ok then return false end
  return result
end

function fs.isDirectory(path)
  local proxy, rel = resolve(path)
  if not proxy then return false end
  local ok, result = pcall(proxy.isDirectory, rel)
  if not ok then return false end
  return result
end

function fs.list(path)
  local proxy, rel = resolve(path)
  if not proxy then return {} end
  local ok, result = pcall(proxy.list, rel)
  if not ok then return {} end
  return result or {}
end

function fs.makeDirectory(path)
  local proxy, rel = resolve(path)
  if not proxy then return false, "No filesystem" end
  local ok, result = pcall(proxy.makeDirectory, rel)
  if not ok then return false, tostring(result) end
  return result
end

function fs.remove(path)
  path = fs.normalize(path)
  -- Prevent deleting mount points directly
  if mounts[path] then
    return false, "Cannot delete a mount point (use umount)"
  end
  local proxy, rel = resolve(path)
  if not proxy then return false, "No filesystem" end
  local ok, result = pcall(proxy.remove, rel)
  if not ok then return false, tostring(result) end
  return result
end

function fs.rename(from, to)
  from = fs.normalize(from)
  to = fs.normalize(to)
  -- Prevent renaming mount points
  if mounts[from] then
    return false, "Cannot rename a mount point"
  end
  local proxyFrom, relFrom = resolve(from)
  local proxyTo, relTo = resolve(to)
  if not proxyFrom then return false, "Source not found" end
  if proxyFrom ~= proxyTo then
    return false, "Cannot rename across filesystems"
  end
  local ok, result = pcall(proxyFrom.rename, relFrom, relTo)
  if not ok then return false, tostring(result) end
  return result
end

function fs.size(path)
  local proxy, rel = resolve(path)
  if not proxy then return 0 end
  local ok, result = pcall(proxy.size, rel)
  return ok and result or 0
end

function fs.lastModified(path)
  local proxy, rel = resolve(path)
  if not proxy then return 0 end
  local ok, result = pcall(proxy.lastModified, rel)
  return ok and result or 0
end

-- ============================================================
-- File I/O
-- ============================================================

--- Read entire file as string
function fs.readFile(path)
  local proxy, rel = resolve(path)
  if not proxy then return nil, "No filesystem" end
  local ok0, exists = pcall(proxy.exists, rel)
  if not ok0 or not exists then return nil, "File not found: " .. path end
  local h, err = proxy.open(rel, "r")
  if not h then return nil, err end
  local chunks = {}
  local readOk, readErr = pcall(function()
    repeat
      local chunk = proxy.read(h, 4096)
      if chunk then chunks[#chunks + 1] = chunk end
    until not chunk
  end)
  proxy.close(h)
  if not readOk then return nil, tostring(readErr) end
  return table.concat(chunks)
end

--- Write string to file (overwrite)
function fs.writeFile(path, content)
  local proxy, rel = resolve(path)
  if not proxy then return false, "No filesystem" end
  -- Ensure parent directory exists
  local dir = rel:match("^(.+)/[^/]+$")
  if dir and dir ~= "" then
    local ok0, isDir = pcall(proxy.isDirectory, dir)
    if not ok0 or not isDir then pcall(proxy.makeDirectory, dir) end
  end
  local h, err = proxy.open(rel, "w")
  if not h then return false, err end
  local ok = pcall(proxy.write, h, content)
  proxy.close(h)
  if not ok then return false, "Write failed" end
  return true
end

--- Append to file
function fs.appendFile(path, content)
  local proxy, rel = resolve(path)
  if not proxy then return false, "No filesystem" end
  local h, err = proxy.open(rel, "a")
  if not h then return false, err end
  local ok = pcall(proxy.write, h, content)
  proxy.close(h)
  if not ok then return false, "Write failed" end
  return true
end

--- Copy a file from src to dst (handles cross-filesystem copies)
function fs.copy(src, dst)
  src = fs.normalize(src)
  dst = fs.normalize(dst)
  -- If source is a directory, use recursive copy
  if fs.isDirectory(src) then
    return fs.copyRecursive(src, dst)
  end
  local content, err = fs.readFile(src)
  if not content then return false, err end
  return fs.writeFile(dst, content)
end

--- Recursively copy a directory tree from src to dst.
-- Creates the destination directory and copies all files and subdirectories.
-- @param src string: Source directory path
-- @param dst string: Destination directory path
-- @return boolean, string: success or false + error
function fs.copyRecursive(src, dst)
  src = fs.normalize(src)
  dst = fs.normalize(dst)

  if not fs.exists(src) then
    return false, "Source not found: " .. src
  end
  if not fs.isDirectory(src) then
    -- Single file, just copy it
    return fs.copy(src, dst)
  end

  -- Prevent copying a directory into itself
  if dst:sub(1, #src) == src and (#dst == #src or dst:sub(#src + 1, #src + 1) == "/") then
    return false, "Cannot copy a directory into itself"
  end

  -- Create destination directory
  if not fs.exists(dst) then
    local ok, err = fs.makeDirectory(dst)
    if not ok then return false, "Cannot create directory: " .. tostring(err) end
  end

  -- Iterate contents
  local items = fs.list(src)
  if not items then return false, "Cannot list source directory" end

  local copied, failed = 0, 0
  for _, name in ipairs(items) do
    -- Strip trailing slash from directory names (OC fs.list may include it)
    local cleanName = name:match("^(.-)/?$") or name
    if cleanName ~= "" then
      local srcPath = fs.join(src, cleanName)
      local dstPath = fs.join(dst, cleanName)

      if fs.isDirectory(srcPath) then
        local ok, err = fs.copyRecursive(srcPath, dstPath)
        if ok then copied = copied + 1 else failed = failed + 1 end
      else
        local content = fs.readFile(srcPath)
        if content then
          local ok = fs.writeFile(dstPath, content)
          if ok then copied = copied + 1 else failed = failed + 1 end
        else
          failed = failed + 1
        end
      end
    end
  end

  if failed > 0 then
    return false, string.format("Copied %d items, %d failed", copied, failed)
  end
  return true
end

--- Open a file handle (low-level)
function fs.open(path, mode)
  local proxy, rel = resolve(path)
  if not proxy then return nil, "No filesystem" end
  local h, err = proxy.open(rel, mode or "r")
  if not h then return nil, err end
  -- Return a wrapper with read/write/close
  return {
    handle = h,
    proxy  = proxy,
    read = function(self, n)
      return proxy.read(h, n or 4096)
    end,
    write = function(self, data)
      return proxy.write(h, data)
    end,
    close = function(self)
      return proxy.close(h)
    end,
    seek = function(self, whence, offset)
      return proxy.seek(h, whence, offset)
    end,
  }
end

-- Disk space info
function fs.spaceTotal(path)
  local proxy = resolve(path or "/")
  if not proxy then return 0 end
  local ok, result = pcall(proxy.spaceTotal)
  return ok and result or 0
end

function fs.spaceUsed(path)
  local proxy = resolve(path or "/")
  if not proxy then return 0 end
  local ok, result = pcall(proxy.spaceUsed)
  return ok and result or 0
end

function fs.spaceFree(path)
  return fs.spaceTotal(path) - fs.spaceUsed(path)
end

-- List mount points
function fs.mounts()
  local result = {}
  for mp, proxy in pairs(mounts) do
    local label = "Unnamed"
    pcall(function() label = proxy.getLabel() or "Unnamed" end)
    local total, used = 0, 0
    pcall(function() total = proxy.spaceTotal() end)
    pcall(function() used = proxy.spaceUsed() end)
    result[#result + 1] = {
      mountPoint = mp,
      label      = label,
      address    = proxy.address,
      total      = total,
      used       = used,
    }
  end
  return result
end

return fs
