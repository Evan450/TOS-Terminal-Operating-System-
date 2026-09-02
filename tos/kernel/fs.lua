local component = require("component")

local fs = {}

local mounts = {}

local bootFS = nil

function fs.init(bfs)
  bootFS = bfs

  mounts["/"] = bootFS
end

function fs.normalize(path)

  if path == nil or path == "" then return "/" end

  if type(path) ~= "string" then return nil end
  if path:find("\0", 1, true) then return nil end

  path = path:gsub("\\", "/")

  if path:sub(1, 1) ~= "/" then path = "/" .. path end

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

function fs.split(path)
  path = fs.normalize(path)
  if not path then return nil, nil end
  local dir, name = path:match("^(.-)([^/]+)$")
  if not dir or dir == "" then dir = "/" end
  return dir, name or ""
end

function fs.join(...)
  local parts = {...}
  return fs.normalize(table.concat(parts, "/"))
end

function fs.mount(path, proxy)
  path = fs.normalize(path)
  if not path then return false, "invalid mount path" end
  if mounts[path] then
    return false, "Already mounted at " .. path
  end
  if path ~= "/" and fs.exists(path) then
    if fs.isDirectory(path) then
      local items = fs.list(path)
      if type(items) == "table" and #items > 0 then
        return false, "Refusing to mount over non-empty directory: " .. path
      end
    else
      return false, "Mount path is a file, not a directory: " .. path
    end
  end
  mounts[path] = proxy
  return true
end

function fs.unmount(path)
  path = fs.normalize(path)
  if not path then return false, "invalid path" end
  if path == "/" then return false, "Cannot unmount root" end
  mounts[path] = nil
  return true
end

local function resolve(path)
  path = fs.normalize(path)
  if not path then return nil end

  local bestMount = "/"
  local bestLen = 1
  for mp in pairs(mounts) do
    if #mp > bestLen then

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
  if not path then return false, "invalid path" end

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
  if not from or not to then return false, "invalid path" end

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

local coopProc = nil
local function coopYield()
  if coopProc == nil then
    local okP, m = pcall(require, "kernel.process")
    coopProc = (okP and m and m.yieldCooperative) and m or false
  end
  if coopProc then coopProc.yieldCooperative() end
end

function fs.readFile(path)
  local proxy, rel = resolve(path)
  if not proxy then return nil, "No filesystem" end
  local ok0, exists = pcall(proxy.exists, rel)
  if not ok0 or not exists then return nil, "File not found: " .. path end
  local h, err = proxy.open(rel, "r")
  if not h then return nil, err end
  local chunks = {}

  local readOk, result = pcall(function()
    repeat
      local chunk = proxy.read(h, 4096)
      if chunk then chunks[#chunks + 1] = chunk end
    until not chunk
    return table.concat(chunks)
  end)
  proxy.close(h)
  chunks = nil
  if not readOk then return nil, tostring(result) end
  return result
end

function fs.writeFile(path, content)
  local proxy, rel = resolve(path)
  if not proxy then return false, "No filesystem" end

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

local ATOMIC_SUFFIX = ".tos-tmp"

function fs.writeFileAtomic(path, content)
  path = fs.normalize(path)
  if not path then return false, "invalid path" end
  local tmp = path .. ATOMIC_SUFFIX
  local ok, err = fs.writeFile(tmp, content)
  if not ok then
    pcall(fs.remove, tmp)
    return false, err or "temp write failed"
  end

  if fs.exists(path) then
    local rok = pcall(fs.remove, path)
    if not rok then pcall(fs.remove, tmp); return false, "cannot replace target" end
  end
  local mok, merr = fs.rename(tmp, path)
  if not mok then return false, "rename failed: " .. tostring(merr) end
  return true
end

function fs.recoverAtomic(paths)
  local recovered, cleaned = 0, 0
  for _, base in ipairs(paths or {}) do
    base = fs.normalize(base)
    if base then
      local tmp = base .. ATOMIC_SUFFIX
      if fs.exists(tmp) then
        if fs.exists(base) then
          pcall(fs.remove, tmp); cleaned = cleaned + 1
        else
          local pok, fok = pcall(fs.rename, tmp, base)
          if pok and fok then recovered = recovered + 1 end
        end
      end
    end
  end
  return recovered, cleaned
end

function fs.copy(src, dst)
  src = fs.normalize(src)
  dst = fs.normalize(dst)
  if not src or not dst then return false, "invalid path" end

  if fs.isDirectory(src) then
    return fs.copyRecursive(src, dst)
  end
  local content, err = fs.readFile(src)
  if not content then return false, err end
  return fs.writeFile(dst, content)
end

function fs.copyRecursive(src, dst)
  src = fs.normalize(src)
  dst = fs.normalize(dst)
  if not src or not dst then return false, "invalid path" end

  if not fs.exists(src) then
    return false, "Source not found: " .. src
  end
  if not fs.isDirectory(src) then

    return fs.copy(src, dst)
  end

  if dst:sub(1, #src) == src and (#dst == #src or dst:sub(#src + 1, #src + 1) == "/") then
    return false, "Cannot copy a directory into itself"
  end

  if not fs.exists(dst) then
    local ok, err = fs.makeDirectory(dst)
    if not ok then return false, "Cannot create directory: " .. tostring(err) end
  end

  local items = fs.list(src)
  if not items then return false, "Cannot list source directory" end

  local copied, failed = 0, 0
  for _, name in ipairs(items) do
    coopYield()

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

function fs.open(path, mode)
  local proxy, rel = resolve(path)
  if not proxy then return nil, "No filesystem" end
  local h, err = proxy.open(rel, mode or "r")
  if not h then return nil, err end

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
