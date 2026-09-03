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
  -- Propagate denial/error instead of masking it as an empty
  -- directory, so callers can distinguish "no entries" from
  -- "access denied / bad path".
  if raw == nil and err ~= nil then return nil, err end
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
--
-- #SEC — Previously returned the raw component filesystem proxy from
-- component.proxy(addr), which let any caller (including sandboxed
-- OpenOS programs) call proxy.open / proxy.list / proxy.remove
-- directly, completely bypassing securefs ACLs and session checks.
--
-- The returned object now exposes only non-sensitive disk metadata.
-- Path-operation methods (open/list/remove/rename/...) intentionally
-- do NOT exist — callers must use filesystem.open / filesystem.list
-- etc., which route through securefs. setLabel is also dropped since
-- it is a write that would not flow through the ACL layer.
local function makeSafeMountProxy(addr, mountPoint)
  local component = require("component")
  local ok, raw = pcall(component.proxy, addr)
  if not ok or not raw then return nil end

  local function denied()
    return nil, "raw filesystem access is disabled; use filesystem.open/list/etc."
  end

  -- #SEC H15 — `address` is a privileged field. Non-privileged
  -- callers used to get the raw FS address here, then re-resolve it
  -- via `component.proxy(addr)` outside the sandbox boundary and
  -- bypass securefs entirely. Determine whether the current caller
  -- has admin-or-better tier; only then expose `address`. For lower
  -- tiers, hand back a synthetic stable identifier so OpenOS code
  -- that uses `address` as a cache key still works without leaking
  -- the real component UUID.
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

  -- Stable opaque identifier for non-privileged callers — hash of the
  -- (mountPoint || addr) so the value is reproducible across calls
  -- but never reveals the underlying component address.
  local opaqueId = addr
  if not exposeAddr then
    local okC, cryptoMod = pcall(require, "kernel.crypto")
    if okC and cryptoMod and cryptoMod.hash then
      opaqueId = "fs:" .. cryptoMod.hash(mountPoint .. "|" .. addr):sub(1, 16)
    else
      opaqueId = "fs:" .. mountPoint
    end
  end

  -- Safe metadata methods — these are the ONLY accessors the proxy
  -- intentionally exposes. Anything else (open/list/remove/rename/...
  -- AND any future method OC's filesystem component grows) falls
  -- through __index to denied().
  -- #SEC H15 — also re-resolve raw on every call rather than capturing
  -- it in the closure. If the underlying component goes away or is
  -- re-bound, we don't keep handing back a stale proxy.
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

  -- #SEC — Allowlist + __index trap.
  --
  -- The previous implementation enumerated each known dangerous
  -- method by name (open, list, remove, rename, ...) and bound it
  -- to denied(). That worked today because OC's filesystem
  -- component method set is finite and known. But: if a future OC
  -- version adds a new method (chmod, listAttributes, hard-link,
  -- whatever), the explicit denial list silently misses it — the
  -- proxy returns nil for the unknown name and the caller crashes
  -- OR, worse, if any code path ever proxies through to `raw`, the
  -- new method leaks unmediated to the sandbox.
  --
  -- The metatable trap below makes that impossible: any attribute
  -- not present in `safe` returns the denied() function. So the
  -- proxy's surface is exactly the four metadata accessors,
  -- regardless of what the underlying OC component exposes now or
  -- in the future.
  return setmetatable(safe, {
    __index = function(_, _) return denied end,
    -- Refuse mutations too — a sandboxed program could otherwise do
    -- `proxy.open = function() ... end` to install its own bypass.
    __newindex = function(_, _, _)
      error("safe filesystem proxy is read-only", 2)
    end,
    __metatable = false,  -- block setmetatable() escape attempts
  })
end

function filesystem.get(path)
  -- Returns a securefs-wrapped mount proxy and the mount point
  -- (longest prefix match). The proxy exposes only safe metadata —
  -- see makeSafeMountProxy above for the rationale.
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

--- Check available space
function filesystem.spaceTotal(path) return fs().spaceTotal(path or "/") end
function filesystem.spaceUsed(path) return fs().spaceUsed(path or "/") end
function filesystem.isLink() return false end -- OC doesn't have real symlinks

return filesystem
