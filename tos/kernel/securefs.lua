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
  process = modules.process
end

-- Resolve the session that should be used for a permission check.
-- Priority: explicit session → current process principal → legacy
-- users.currentSession() → boot session (only while boot is in progress).
--
-- #SEC — Previously the boot-session fallback fired unconditionally,
-- giving any un-sessioned caller root fs access for the life of the
-- machine. We now consult `_G._TOS.bootCompleted`: once the first user
-- login completes, the fallback is disabled and un-sessioned callers
-- fail closed rather than silently running as root.
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

-- Forward declaration so checkWrite can call into the protected-target
-- guard before it's defined further down. Defence-in-depth: even an admin
-- caller is blocked from writing under /tos, /etc, /init.lua, etc.
local _isProtectedTarget

local function checkWrite(path, session)
  if not fs or not usermod then return false, "securefs not initialized" end
  path = fs.normalize(path)
  -- #SEC C18 — every write op (writeFile, appendFile, makeDirectory,
  -- open w/+/a) flows through here. Previously the protected-set check
  -- only fired from remove/rename, letting an admin overwrite
  -- /tos/kernel/init.lua and brick or backdoor the OS on next boot.
  if _isProtectedTarget then
    local hit = _isProtectedTarget(path)
    if hit then
      if log then log.warn("securefs", "WRITE denied (protected): " .. path) end
      -- This is intentional even for root: it's a defence-in-depth line, not
      -- an ACL (so a tampered admin session can't backdoor the kernel/libs).
      -- Point the operator at the supported install path instead of leaving
      -- them to conclude root "should" be able to copy files in here.
      local hint = ""
      if hit == "/usr/lib" or hit == "/usr/modules" or hit == "/usr/bin"
         or hit == "/var/pkg" then
        hint = " — install add-ons with 'pkg install', not by copying files here"
      end
      return false, "Cannot write protected system path (" .. hit .. ")" .. hint, path
    end
  end
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

  -- If listing /home, hide other users' homes from non-admin callers.
  -- #SEC H23 — previously, a nil session (early boot / un-attributed call)
  -- skipped the filter, showing every home dir. Treat nil/guest the same
  -- as a tier-0 caller: return an empty list rather than disclosing names.
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

  -- #SEC — same posture for /var/mail: hide other users' mailboxes from
  -- non-admin callers. The per-path ACL (users.checkAccess) already
  -- denies READING them; this stops the username disclosure too.
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

-- Paths that must NEVER be the target of a remove or rename, regardless
-- of any ACL decision made by users.canAccessAs. Even root going through
-- securefs is forced to go around it (e.g. by using the raw kernel.fs)
-- to e.g. reinstall. This is a defence-in-depth line, not an ACL.
local REMOVE_PROTECTED = {
  "/tos", "/etc", "/init.lua", "/bios.lua", "/install.lua",
  "/var", "/usr",
  -- #SEC C18: extended set so admins can't overwrite the package DB,
  -- shipped modules, or kernel libraries via securefs writes either.
  "/var/pkg", "/var/pkg/installed",
  "/usr/modules", "/usr/lib", "/usr/bin",
}

-- #REV — Node-protected roots: the directory NODE itself may not be
-- removed/renamed/overwritten (so nobody can swap out a user-data root),
-- but files and subdirs INSIDE it are governed by the per-user ACL
-- (users.canAccessAs), NOT this blanket guard. /home, /root and /public
-- were previously in REMOVE_PROTECTED, whose subtree match blocked EVERY
-- write beneath them — so a user could never save their own dotfiles
-- (~/.theme.cfg, ~/.profile.cfg) or write to /public at all. The kernel
-- log showed this as the recurring "WRITE denied (protected):
-- /root/.theme.cfg" that made themes un-saveable.
local NODE_PROTECTED = {
  "/home", "/root", "/public",
}

-- Paths that may exist UNDER a protected root but should remain writable
-- (e.g. /etc/users.dat — admins must be able to add accounts even though
-- /etc itself is protected). Each entry is matched as an exact path.
local WRITE_PROTECTED_EXEMPT = {
  ["/etc/users.dat"]    = true,
  ["/etc/tos.cfg"]      = true,
  ["/etc/hostname"]     = true,
  ["/etc/motd"]         = true,
  ["/etc/profile"]      = true,
  ["/etc/critical.bak"] = true,
  -- Tutorial completion marker, LEGACY. It is now per-account and lives
  -- in the user's own home (~/.tutorial_done), which needs no exemption
  -- because a user may always write their own home — and that also fixed
  -- the reason this entry had to exist: writing /etc needed ADMIN tier, so
  -- a plain USER finishing the tutorial could never record it and was
  -- offered the walkthrough again at every login. Kept because the old
  -- path is still READ, to recognise a machine whose root finished the
  -- tutorial before the split. Nothing writes it any more.
  ["/etc/.tutorial_done"] = true,
  ["/etc/peer_aliases.dat"] = true,  -- NET-1 peer alias table
  -- Self-test battery arming marker (kernel/selftest.lua). Same
  -- failure as .tutorial_done above, and found the same way -- on
  -- real hardware, as "WRITE denied (protected): /etc/selftest.on"
  -- while the shell reported the write as successful. An /etc file a
  -- documented procedure tells an admin to create MUST be listed
  -- here, or the procedure cannot be followed.
  ["/etc/selftest.on"]      = true,
  -- Cluster + kiosk + similar admin-managed cfgs land here as the
  -- corresponding packages get added. Add the file path here when a
  -- new admin-writable /etc cfg file ships.
  ["/etc/cluster-master.cfg"]  = true,
  ["/etc/cluster-manager.cfg"] = true,
  ["/etc/kiosk.cfg"]           = true,
  ["/etc/component_caps.cfg"]  = true,
  ["/etc/pkg_caps.cfg"]        = true,  -- package-capability allow/deny overrides
  -- Publisher signing keys. This one is load-bearing: the file IS the
  -- answer to "whose packages does this machine accept", so anyone who
  -- can write it can add themselves as a trusted publisher. It lives
  -- here rather than anywhere looser for exactly that reason.
  ["/etc/pkg_trust.cfg"]       = true,
  -- The machine-wide menu bar. Admin-writable: it is what every user on
  -- this computer sees, so it is an operator decision rather than a
  -- personal one (~/.menu.cfg is the personal one and needs no gate).
  ["/etc/menu.cfg"]            = true,
  -- Machine-wide keybinds. Admin: it changes how every user's
  -- keyboard behaves, which is an operator decision. ~/.keys.cfg is
  -- the personal one and needs no gate.
  ["/etc/keys.cfg"]            = true,
  ["/etc/chat-groups.cfg"]     = true,  -- multi-operator chat groups
  ["/etc/intercom.cues"]       = true,  -- announcement catalog (intercom pkg)
  ["/etc/intercom.cfg"]        = true,  -- announcement receive policy
  ["/etc/jbod.cfg"]            = true,  -- JBOD pool table (opt-in feature)
  ["/etc/widgets"]             = true,  -- dir, see C15 widget cache
  ["/var/log"]          = true,  -- log rotation needs to remove
  ["/var/run"]          = true,  -- session/pid files
  ["/var/lib"]          = true,  -- backoff (M6) + future per-app state
  ["/var/cluster"]      = true,  -- clusterd state.dat + status.dat
}

local function isProtectedTarget(path)
  -- Direct-exempt overrides: a write to one of these specific files is
  -- permitted even though its containing dir is in REMOVE_PROTECTED.
  if WRITE_PROTECTED_EXEMPT[path] then return nil end
  -- Tree-exempt prefixes. Any of these covers writes ANYWHERE under
  -- the listed directory — for things where the directory itself is
  -- admin-managed but per-file paths are arbitrary (log rotation,
  -- session/pid files, per-app cluster state, etc.).
  local TREE_EXEMPT = {
    "/var/log/", "/var/run/", "/var/lib/", "/var/cluster/", "/etc/widgets/",
  }
  for _, prefix in ipairs(TREE_EXEMPT) do
    if path:sub(1, #prefix) == prefix then return nil end
  end
  -- Node-protected roots: only the EXACT directory node is off-limits;
  -- anything inside follows the per-user ACL (so users own their homes).
  for _, p in ipairs(NODE_PROTECTED) do
    if path == p then return p end
  end
  -- Subtree-protected roots: the dir AND everything beneath it.
  for _, p in ipairs(REMOVE_PROTECTED) do
    if path == p or path:sub(1, #p + 1) == p .. "/" then
      return p
    end
  end
  return nil
end
_isProtectedTarget = isProtectedTarget

function securefs.remove(path, session)
  -- Normalize FIRST so variants like "/tos/" or "/tos/." can't slip past
  path = fs.normalize(path)
  local hit = isProtectedTarget(path)
  if hit then
    return false, "Cannot remove protected system path (" .. hit .. ")"
  end
  local ok, err = checkWrite(path, session)
  if not ok then return false, err end
  return fs.remove(path)
end

function securefs.rename(from, to, session)
  -- Normalize both sides up front so ".."/trailing-slash tricks can't
  -- steer the rename past the protected-target check.
  local nFrom = fs.normalize(from)
  local nTo   = fs.normalize(to)
  -- Refuse to rename FROM or TO anything under the protected set. This
  -- closes the "rename /home -> /home.bak then recreate" side-door that
  -- would otherwise let a caller with write access to /home.bak (which
  -- they could create first) swap the real /home out from under users.
  local hitFrom = isProtectedTarget(nFrom)
  if hitFrom then
    return false, "Cannot rename protected system path (" .. hitFrom .. ")"
  end
  local hitTo = isProtectedTarget(nTo)
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

-- Changing the mount table changes what path resolves to what proxy,
-- effectively letting the caller swap out /tos or /home for an
-- attacker-controlled filesystem. Only admins may do this.
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

-- Test hook (not part of the public API): the protected-target guard,
-- exposed so the node-vs-subtree behavior can be unit-tested off-box.
securefs._isProtectedTarget = function(p) return _isProtectedTarget(p) end

return securefs
