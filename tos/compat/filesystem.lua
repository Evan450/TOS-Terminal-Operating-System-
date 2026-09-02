local function fs()
  return (_G._TOS and _G._TOS.securefs) or require("kernel.securefs")
end

local filesystem = {}

function filesystem.exists(path) return fs().exists(path) end
function filesystem.isDirectory(path) return fs().isDirectory(path) end
function filesystem.makeDirectory(path) return fs().makeDirectory(path) end
function filesystem.remove(path) return fs().remove(path) end
function filesystem.rename(from, to) return fs().rename(from, to) end
function filesystem.size(path) return fs().size(path) end
function filesystem.lastModified(path) return fs().lastModified(path) end

function filesystem.list(path)
  local raw, err = fs().list(path)
  if type(raw) == "table" then
    local i = 0
    return function()
      i = i + 1
      return raw[i]
    end
  elseif type(raw) == "function" then
    return raw
  end

  if raw == nil and err ~= nil then return nil, err end
  return function() return nil end
end

function filesystem.open(path, mode)
  mode = mode or "r"
  local handle, err = fs().open(path, mode)
  if not handle then return nil, err end

  return handle
end

function filesystem.copy(from, to)
  return fs().copy(from, to)
end

function filesystem.canonical(path)
  return fs().normalize(path)
end

function filesystem.segments(path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    parts[#parts + 1] = seg
  end
  return parts
end

function filesystem.path(path)
  local dir = path:match("^(.+/)[^/]+/?$")
  return dir or "/"
end

function filesystem.name(path)
  return path:match("([^/]+)/?$") or ""
end

function filesystem.concat(...)
  return fs().join(...)
end

local function makeSafeMountProxy(addr, mountPoint)
  local component = require("component")
  local ok, raw = pcall(component.proxy, addr)
  if not ok or not raw then return nil end

  local function denied()
    return nil, "raw filesystem access is disabled; use filesystem.open/list/etc."
  end

  local exposeAddr = false
  do
    local okU, usersmod = pcall(require, "kernel.users")
    if okU and usersmod and usersmod.currentSession and usersmod.TIER then
      local s = usersmod.currentSession()
      if s and (s.tier or 0) >= (usersmod.TIER.ADMIN or 2) then
        exposeAddr = true
      end
    end
  end

  local opaqueId = addr
  if not exposeAddr then
    local okC, cryptoMod = pcall(require, "kernel.crypto")
    if okC and cryptoMod and cryptoMod.hash then
      opaqueId = "fs:" .. cryptoMod.hash(mountPoint .. "|" .. addr):sub(1, 16)
    else
      opaqueId = "fs:" .. mountPoint
    end
  end

  local function freshRaw()
    local okR, p = pcall(component.proxy, addr)
    if okR and p then return p end
    return nil
  end
  local safe = {
    address    = opaqueId,
    mountPoint = mountPoint,
    type       = "filesystem",
    spaceTotal = function() local r = freshRaw(); return r and r.spaceTotal() or 0 end,
    spaceUsed  = function() local r = freshRaw(); return r and r.spaceUsed()  or 0 end,
    getLabel   = function() local r = freshRaw(); return r and r.getLabel()   or "" end,
    isReadOnly = function() local r = freshRaw(); return r and r.isReadOnly() or true end,
  }

  return setmetatable(safe, {
    __index = function(_, _) return denied end,

    __newindex = function(_, _, _)
      error("safe filesystem proxy is read-only", 2)
    end,
    __metatable = false,
  })
end

function filesystem.get(path)

  local f = fs()
  path = f.normalize(path)
  local bestMount, bestAddr, bestLen = nil, nil, 0
  for _, m in ipairs(f.mounts()) do
    local mp = m.mountPoint
    if #mp > bestLen then
      if mp == "/" or (path:sub(1, #mp) == mp and (#path == #mp or path:sub(#mp + 1, #mp + 1) == "/")) then
        bestMount = mp
        bestAddr = m.address
        bestLen = #mp
      end
    end
  end
  if bestAddr then
    local proxy = makeSafeMountProxy(bestAddr, bestMount)
    if proxy then return proxy, bestMount end
  end
  return nil
end

function filesystem.spaceTotal(path) return fs().spaceTotal(path or "/") end
function filesystem.spaceUsed(path) return fs().spaceUsed(path or "/") end
function filesystem.isLink() return false end

return filesystem
