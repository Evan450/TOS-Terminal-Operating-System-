-- TOS OpenOS Compatibility - filesystem API
-- Wraps TOS securefs to provide the OpenOS filesystem interface.
-- OpenOS programs use require("filesystem") for file operations.

-- Deferred filesystem accessor. Resolves to securefs (permission-checked)
-- when the kernel has finished booting, falling back to raw kernel.fs
-- only before securefs has loaded. This keeps the OpenOS-compat API
-- identical in shape while enforcing ACLs under the hood.
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
  local raw = fs().list(path)
  if type(raw) == "table" then
    local i = 0
    return function()
      i = i + 1
      return raw[i]
    end
  elseif type(raw) == "function" then
    return raw
  end
  return function() return nil end
end

function filesystem.open(path, mode)
  mode = mode or "r"
  local handle, err = fs().open(path, mode)
  if not handle then return nil, err end
  -- OpenOS file handles have read/write/close/seek as methods
  return handle
end

function filesystem.copy(from, to)
  return fs().copy(from, to)
end

--- Canonical path (resolve .. and .)
function filesystem.canonical(path)
  return fs().normalize(path)
end

--- Get path segments
function filesystem.segments(path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    parts[#parts + 1] = seg
  end
  return parts
end

--- Get parent directory
function filesystem.path(path)
  local dir = path:match("^(.+/)[^/]+/?$")
  return dir or "/"
end

--- Get filename from path
function filesystem.name(path)
  return path:match("([^/]+)/?$") or ""
end

--- Concatenate path segments
function filesystem.concat(...)
  return fs().join(...)
end

--- Get mount point for a path
function filesystem.get(path)
  -- Returns the filesystem proxy and mount point (longest prefix match)
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
    local component = require("component")
    local ok, proxy = pcall(component.proxy, bestAddr)
    if ok then return proxy, bestMount end
  end
  return nil
end

--- Check available space
function filesystem.spaceTotal(path) return fs().spaceTotal(path or "/") end
function filesystem.spaceUsed(path) return fs().spaceUsed(path or "/") end
function filesystem.isLink() return false end -- OC doesn't have real symlinks

return filesystem
