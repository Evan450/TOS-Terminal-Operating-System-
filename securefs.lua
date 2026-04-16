-- ╔══════════════════════════════════════╗
-- ║  TOS Security - Secure FS Wrapper    ║
-- ║  Permission-enforcing filesystem     ║
-- ╚══════════════════════════════════════╝
-- Wraps kernel.fs with access checks from kernel.users.
-- All user-facing code should use this instead of raw fs.
--
-- Session resolution: every public method accepts an OPTIONAL trailing
-- `session` argument. When omitted, the session is resolved from the
-- current process's `principal` field (phase 4), falling back to the
-- legacy `users.currentSession()` path for callers that haven't been
-- migrated and for early-boot code.

local securefs = {}

-- Module references (set during init)
local fs      = nil
local usermod = nil
local log     = nil
local process = nil  -- optional; late-bound so early-boot works

function securefs.init(modules)
  fs      = modules.fs
  usermod = modules.users
  log     = modules.log
  process = modules.process  -- may be nil until phase 4 wires it
end

--- Late-bind the process module (called from kernel.init after proc loads).
function securefs.setProcess(procMod)
  process = procMod
end

-- Resolve the session that should be used for a permission check.
-- Priority: explicit session → current process principal → boot session
-- → legacy users.currentSession().
local function sessionOf(explicit)
  if explicit then return explicit end
  if process and process.currentSession then
    local s = process.currentSession()
    if s then return s end
  end
  if _G._TOS and _G._TOS.bootSession then
    return _G._TOS.bootSession
  end
  if usermod and usermod.currentSession then
    return usermod.currentSession()
  end
  return nil
end

-- ============================================================
-- Permission-checked wrappers
-- ============================================================

local function checkRead(path, session)
  if not fs or not usermod then return false, "securefs not initialized" end
  path = fs.normalize(path)
  local sess = sessionOf(session)
  local allowed, reason = usermod.canAccessAs(sess, path, "r")
  if not allowed then
    if log then log.warn("securefs", "READ denied: " .. path .. " (" .. (reason or "?") .. ")") end
    return false, "Permission denied: " .. (reason or "access denied"), path
  end
  return true, nil, path
end

local function checkWrite(path, session)
  if not fs or not usermod then return false, "securefs not initialized" end
  path = fs.normalize(path)
  local sess = sessionOf(session)
  local allowed, reason = usermod.canAccessAs(sess, path, "w")
  if not allowed then
    if log then log.warn("securefs", "WRITE denied: " .. path .. " (" .. (reason or "?") .. ")") end
    return false, "Permission denied: " .. (reason or "access denied"), path
  end
  return true, nil, path
end

-- ── Read operations ──────────────────────────────────────

function securefs.exists(path, session)
  local ok, _, norm = checkRead(path, session)
  if not ok then return false end
  return fs.exists(norm)
end

function securefs.isDirectory(path, session)
  local ok, _, norm = checkRead(path, session)
  if not ok then return false end
  return fs.isDirectory(norm)
end

function securefs.list(path, session)
  local ok, err, norm = checkRead(path, session)
  if not ok then return {}, err end
  path = norm

  local rawList = fs.list(norm)
  local sess = sessionOf(session)

  -- If listing /home and not admin, only show own directory
  if path == "/home" or path == "/home/" then
    if sess and sess.tier < usermod.TIER.ADMIN then
      local filtered = {}
      if type(rawList) == "table" then
        for _, name in ipairs(rawList) do
          local cleanName = name:gsub("/$", "")
          if cleanName == sess.user then
            filtered[#filtered + 1] = name
          end
        end
      end
      return filtered
    end
  end

  return rawList
end

function securefs.readFile(path, session)
  local ok, err, norm = checkRead(path, session)
  if not ok then return nil, err end
  return fs.readFile(norm)
end

function securefs.size(path, session)
  local ok, _, norm = checkRead(path, session)
  if not ok then return 0 end
  return fs.size(norm)
end

function securefs.lastModified(path, session)
  local ok, _, norm = checkRead(path, session)
  if not ok then return 0 end
  return fs.lastModified(norm)
end

-- ── Write operations ─────────────────────────────────────

function securefs.writeFile(path, content, session)
  local ok, err, norm = checkWrite(path, session)
  if not ok then return false, err end
  return fs.writeFile(norm, content)
end

function securefs.appendFile(path, content, session)
  local ok, err, norm = checkWrite(path, session)
  if not ok then return false, err end
  return fs.appendFile(norm, content)
end

function securefs.makeDirectory(path, session)
  local ok, err, norm = checkWrite(path, session)
  if not ok then return false, err end
  return fs.makeDirectory(norm)
end

function securefs.remove(path, session)
  -- Normalize FIRST so variants like "/tos/" or "/tos/." can't slip past
  path = fs.normalize(path)
  -- Extra protection: never allow removing critical system paths
  local protected = {"/tos", "/etc", "/init.lua", "/home", "/public", "/root", "/var"}
  for _, p in ipairs(protected) do
    if path == p or path:sub(1, #p + 1) == p .. "/" then
      return false, "Cannot remove protected system path"
    end
  end
  local ok, err = checkWrite(path, session)
  if not ok then return false, err end
  return fs.remove(path)
end

function securefs.rename(from, to, session)
  local ok1, err1, normFrom = checkWrite(from, session)
  if not ok1 then return false, err1 end
  local ok2, err2, normTo = checkWrite(to, session)
  if not ok2 then return false, err2 end
  return fs.rename(normFrom, normTo)
end

function securefs.copy(src, dst, session)
  local ok1, err1, normSrc = checkRead(src, session)
  if not ok1 then return false, err1 end
  local ok2, err2, normDst = checkWrite(dst, session)
  if not ok2 then return false, err2 end
  return fs.copy(normSrc, normDst)
end

-- ── File handles (checked on open) ───────────────────────

function securefs.open(path, mode, session)
  mode = mode or "r"
  local norm
  if mode:find("w") or mode:find("a") or mode:find("+") then
    local ok, err, n = checkWrite(path, session)
    if not ok then return nil, err end
    norm = n
  else
    local ok, err, n = checkRead(path, session)
    if not ok then return nil, err end
    norm = n
  end
  return fs.open(norm, mode)
end

-- ── Pass-through (no permission needed) ──────────────────

function securefs.normalize(path) return fs.normalize(path) end
function securefs.split(path) return fs.split(path) end
function securefs.join(...) return fs.join(...) end
function securefs.spaceTotal(path) return fs.spaceTotal(path) end
function securefs.spaceUsed(path) return fs.spaceUsed(path) end
function securefs.spaceFree(path) return fs.spaceFree(path) end
function securefs.mounts() return fs.mounts() end

function securefs.mount(path, proxy)
  if not fs then return false, "securefs not initialized" end
  return fs.mount(path, proxy)
end

function securefs.unmount(path)
  if not fs then return false, "securefs not initialized" end
  return fs.unmount(path)
end

-- ── User convenience ─────────────────────────────────────

--- Get the current user's home directory
function securefs.home(session)
  local sess = sessionOf(session)
  if sess then return sess.home end
  return "/tmp"  -- Fallback for no session
end

--- Resolve ~ to home directory
function securefs.resolve(path, session)
  if path == "~" or path:sub(1, 2) == "~/" then
    return securefs.home(session) .. path:sub(2)
  end
  return path
end

-- ============================================================
-- Session-bound proxy — returned by securefs.forSession(sess)
-- Lets callers pre-bind a session and call normal methods.
-- Used by the sandbox builder in phase 2 so user programs see
-- a simple `fs` object that already carries their principal.
-- ============================================================

function securefs.forSession(session)
  local proxy = {}
  -- Public methods that accept a trailing session arg
  local bound = {
    "exists", "isDirectory", "list", "readFile", "writeFile", "appendFile",
    "makeDirectory", "remove", "rename", "copy", "open", "size", "lastModified",
    "home", "resolve",
  }
  for _, name in ipairs(bound) do
    local fn = securefs[name]
    proxy[name] = function(...)
      local nargs = select("#", ...)
      local args = {...}
      -- Append session at the end
      args[nargs + 1] = session
      return fn(table.unpack(args, 1, nargs + 1))
    end
  end
  -- Pass-throughs (no session)
  proxy.normalize   = securefs.normalize
  proxy.split       = securefs.split
  proxy.join        = securefs.join
  proxy.spaceTotal  = securefs.spaceTotal
  proxy.spaceUsed   = securefs.spaceUsed
  proxy.spaceFree   = securefs.spaceFree
  proxy.mounts      = securefs.mounts
  -- Special case: copy takes two paths then session
  proxy.copy = function(from, to) return securefs.copy(from, to, session) end
  proxy.rename = function(from, to) return securefs.rename(from, to, session) end
  return proxy
end

return securefs
