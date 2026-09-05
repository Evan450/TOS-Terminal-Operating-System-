local securefs = {}

local fs      = nil
local usermod = nil
local log     = nil
local process = nil

function securefs.init(modules)
  fs      = modules.fs
  usermod = modules.users
  log     = modules.log
  process = modules.process
end

local function sessionOf(explicit)
  if explicit then return explicit end
  if process and process.currentSession then
    local s = process.currentSession()
    if s then return s end
  end
  if usermod and usermod.currentSession then
    local s = usermod.currentSession()
    if s then return s end
  end
  local tos = _G._TOS
  if tos and tos.bootSession and not tos.bootCompleted then
    return tos.bootSession
  end
  return nil
end

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

local _isProtectedTarget

local function checkWrite(path, session)
  if not fs or not usermod then return false, "securefs not initialized" end
  path = fs.normalize(path)
  --! Resolve the principal BEFORE the protected check, not after. The
  --! shell supplies its session through the process, not as an explicit
  --! argument, so `session` here is usually nil -- and an override armed
  --! by root would never have been seen.
  local sess = sessionOf(session)

  if _isProtectedTarget then
    local hit = _isProtectedTarget(path, sess)
    if hit then
      if log then log.warn("securefs", "WRITE denied (protected): " .. path) end

      local hint = ""
      if hit == "/usr/lib" or hit == "/usr/modules" or hit == "/usr/bin"
         or hit == "/var/pkg" then
        hint = " — install add-ons with 'pkg install', not by copying files here"
      end
      return false, "Cannot write protected system path (" .. hit .. ")" .. hint, path
    end
  end
  local allowed, reason = usermod.canAccessAs(sess, path, "w")
  if not allowed then
    if log then log.warn("securefs", "WRITE denied: " .. path .. " (" .. (reason or "?") .. ")") end
    return false, "Permission denied: " .. (reason or "access denied"), path
  end
  return true, nil, path
end

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

  if path == "/home" or path == "/home/" then
    if not sess or sess.tier < usermod.TIER.ADMIN then
      local filtered = {}
      if type(rawList) == "table" and sess and sess.user then
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

  if path == "/var/mail" or path == "/var/mail/" then
    if not sess or sess.tier < usermod.TIER.ADMIN then
      local filtered = {}
      if type(rawList) == "table" and sess and sess.user then
        for _, name in ipairs(rawList) do
          if name:gsub("/$", "") == sess.user then
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

local REMOVE_PROTECTED = {
  "/tos", "/etc", "/init.lua", "/bios.lua", "/install.lua",
  "/var", "/usr",

  "/var/pkg", "/var/pkg/installed",
  "/usr/modules", "/usr/lib", "/usr/bin",
}

local NODE_PROTECTED = {
  "/home", "/root", "/public",
}

local WRITE_PROTECTED_EXEMPT = {
  ["/etc/users.dat"]    = true,
  ["/etc/tos.cfg"]      = true,
  ["/etc/hostname"]     = true,
  ["/etc/motd"]         = true,
  ["/etc/profile"]      = true,
  ["/etc/critical.bak"] = true,

  ["/etc/.tutorial_done"] = true,
  ["/etc/peer_aliases.dat"] = true,

  ["/etc/selftest.on"]      = true,

  ["/etc/cluster-master.cfg"]  = true,
  ["/etc/cluster-manager.cfg"] = true,
  ["/etc/kiosk.cfg"]           = true,
  ["/etc/component_caps.cfg"]  = true,
  ["/etc/pkg_caps.cfg"]        = true,

  ["/etc/pkg_trust.cfg"]       = true,

  ["/etc/menu.cfg"]            = true,

  ["/etc/keys.cfg"]            = true,
  ["/etc/chat-groups.cfg"]     = true,
  ["/etc/intercom.cues"]       = true,
  ["/etc/intercom.cfg"]        = true,
  ["/etc/jbod.cfg"]            = true,
  ["/etc/widgets"]             = true,
  ["/var/log"]          = true,
  ["/var/run"]          = true,
  ["/var/lib"]          = true,
  ["/var/cluster"]      = true,
}

--! The protected set above is defence-in-depth against a TAMPERED admin
--! session, and it is worth having. What it should not be is a wall the
--! machine's owner cannot get past on their own hardware: creating a
--! file in /etc, clearing OpenOS's man pages out of /usr/man, and
--! tidying an install were all simply refused, with no supported way to
--! say "yes, I mean it".
--!
--! So it stays on by default and becomes something ROOT can stand down
--! deliberately, for their own session only:
--!
--!   * ROOT tier only. An admin cannot arm it, which is the whole point
--!     of the defence-in-depth line -- a compromised admin session is
--!     still stopped.
--!   * Per SESSION, never global, and gone on logout or reboot. It
--!     cannot be left on by accident for the next person at the seat.
--!   * Every bypass is logged with the path. Trusting the operator is
--!     not the same as keeping no record.
--!
--! This is the "warn, then let them" model rather than "refuse and let
--! them go around securefs with raw kernel.fs" -- which is what the old
--! comment actually recommended, and which produced neither safety nor
--! a log entry.
local overrideSessions = setmetatable({}, { __mode = "k" })

local function hasOverride(session)
  if not session then return false end
  return overrideSessions[session] == true
end

function securefs.setOperatorOverride(session, enabled)
  if not usermod then return false, "securefs not initialized" end
  if not session then return false, "no session" end
  local TIER = usermod.TIER
  local tier = session.tier
  if not (TIER and tier and tier >= TIER.ROOT) then
    return false, "Operator override requires root"
  end
  if enabled then
    overrideSessions[session] = true
    if log then
      log.warn("securefs", "Operator override ARMED by '" ..
        tostring(session.user) .. "' — protected system paths are writable " ..
        "for this session")
    end
  else
    overrideSessions[session] = nil
    if log then
      log.info("securefs", "Operator override disarmed for '" ..
        tostring(session.user) .. "'")
    end
  end
  return true
end

function securefs.operatorOverride(session)
  return hasOverride(session)
end

local function isProtectedTarget(path, session)
  --! An armed root session sees no protected targets at all. Logged at
  --! the point of use so the record names the path, not just the arming.
  if hasOverride(session) then
    if log then
      log.warn("securefs", "Operator override: allowing protected path " .. tostring(path))
    end
    return nil
  end

  if WRITE_PROTECTED_EXEMPT[path] then return nil end

  local TREE_EXEMPT = {
    "/var/log/", "/var/run/", "/var/lib/", "/var/cluster/", "/etc/widgets/",
  }
  for _, prefix in ipairs(TREE_EXEMPT) do
    if path:sub(1, #prefix) == prefix then return nil end
  end

  for _, p in ipairs(NODE_PROTECTED) do
    if path == p then return p end
  end

  for _, p in ipairs(REMOVE_PROTECTED) do
    if path == p or path:sub(1, #p + 1) == p .. "/" then
      return p
    end
  end
  return nil
end
_isProtectedTarget = isProtectedTarget

function securefs.remove(path, session)

  path = fs.normalize(path)
  local hit = isProtectedTarget(path, sessionOf(session))
  if hit then
    return false, "Cannot remove protected system path (" .. hit .. ")"
  end
  local ok, err = checkWrite(path, session)
  if not ok then return false, err end
  return fs.remove(path)
end

function securefs.rename(from, to, session)

  local nFrom = fs.normalize(from)
  local nTo   = fs.normalize(to)

  local hitFrom = isProtectedTarget(nFrom, sessionOf(session))
  if hitFrom then
    return false, "Cannot rename protected system path (" .. hitFrom .. ")"
  end
  local hitTo = isProtectedTarget(nTo, sessionOf(session))
  if hitTo then
    return false, "Cannot rename onto protected system path (" .. hitTo .. ")"
  end
  local ok1, err1, normFrom = checkWrite(nFrom, session)
  if not ok1 then return false, err1 end
  local ok2, err2, normTo = checkWrite(nTo, session)
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

function securefs.normalize(path) return fs.normalize(path) end
function securefs.split(path) return fs.split(path) end
function securefs.join(...) return fs.join(...) end
function securefs.spaceTotal(path) return fs.spaceTotal(path) end
function securefs.spaceUsed(path) return fs.spaceUsed(path) end
function securefs.spaceFree(path) return fs.spaceFree(path) end
function securefs.mounts() return fs.mounts() end

local function requireAdmin(session)
  if not usermod or not usermod.TIER then return nil, "users module unavailable" end
  local sess = sessionOf(session)
  if not sess then return nil, "no session" end
  if sess.tier < usermod.TIER.ADMIN then return nil, "mount requires admin" end
  return sess
end

function securefs.mount(path, proxy, session)
  if not fs then return false, "securefs not initialized" end
  local ok, err = requireAdmin(session)
  if not ok then
    if log then log.warn("securefs", "MOUNT denied: " .. tostring(path) .. " (" .. err .. ")") end
    return false, "Permission denied: " .. err
  end
  return fs.mount(path, proxy)
end

function securefs.unmount(path, session)
  if not fs then return false, "securefs not initialized" end
  local ok, err = requireAdmin(session)
  if not ok then
    if log then log.warn("securefs", "UNMOUNT denied: " .. tostring(path) .. " (" .. err .. ")") end
    return false, "Permission denied: " .. err
  end
  return fs.unmount(path)
end

function securefs.home(session)
  local sess = sessionOf(session)
  if sess then return sess.home end
  return "/tmp"
end

function securefs.resolve(path, session)
  if path == "~" or path:sub(1, 2) == "~/" then
    return securefs.home(session) .. path:sub(2)
  end
  return path
end

function securefs.forSession(session)
  local proxy = {}

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

      args[nargs + 1] = session
      return fn(table.unpack(args, 1, nargs + 1))
    end
  end

  proxy.normalize   = securefs.normalize
  proxy.split       = securefs.split
  proxy.join        = securefs.join
  proxy.spaceTotal  = securefs.spaceTotal
  proxy.spaceUsed   = securefs.spaceUsed
  proxy.spaceFree   = securefs.spaceFree
  proxy.mounts      = securefs.mounts

  proxy.copy = function(from, to) return securefs.copy(from, to, session) end
  proxy.rename = function(from, to) return securefs.rename(from, to, session) end
  return proxy
end

securefs._isProtectedTarget = function(p, s) return _isProtectedTarget(p, s) end

return securefs
