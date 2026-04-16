-- ╔══════════════════════════════════════╗
-- ║  TOS Security - User & Auth System   ║
-- ║  Multi-user, access tiers, sessions  ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")
local serialize = require("kernel.serialize")

local users = {}

-- ============================================================
-- Access tiers (higher number = more privilege)
-- ============================================================
local TIER = {
  GUEST  = 0,   -- Can only access /public, no write
  USER   = 1,   -- Own home dir + /public read/write + /tmp
  ADMIN  = 2,   -- All of USER + can manage users + system config
  ROOT   = 3,   -- Full system access (single root account)
}

-- ============================================================
-- User database structure (stored in /etc/users.dat)
-- Format: Lua table serialized to string
-- {
--   ["username"] = {
--     tier = TIER.USER,
--     salt = "random_salt",
--     hash = "hashed_password",
--     created = uptime,
--     lastLogin = uptime,
--     locked = false,
--     failedAttempts = 0,
--     home = "/home/username",
--   }
-- }
-- ============================================================

local userDB = {}
local DB_PATH = "/etc/users.dat"
local SESSION_PATH = "/var/run/session"

-- Active sessions: { token -> { user, tier, loginTime, lastActivity } }
local sessions = {}
local currentSession = nil

-- Module references (set during init)
local fs = nil
local crypto = nil
local log = nil
local config = nil

-- Security settings (defaults, overridable from config in init())
local MAX_FAILED_ATTEMPTS = 5
local LOCKOUT_AUTO = true  -- Auto-lock after max failures
local SESSION_TIMEOUT = 3600  -- Idle timeout: 1 hour (seconds)

-- ============================================================
-- Database I/O
-- ============================================================

local function saveDB()
  if not fs then return false, "FS not initialized" end
  local data = serialize.encode(userDB)
  -- If crypto is available, we could encrypt the DB here
  -- For now, basic obfuscation (not plaintext passwords anyway)
  return fs.writeFile(DB_PATH, data)
end

local function loadDB()
  if not fs then return false, "FS not initialized" end
  if not fs.exists(DB_PATH) then
    userDB = {}
    return true
  end
  local data, err = fs.readFile(DB_PATH)
  if not data then return false, err end
  local db, derr = serialize.decode(data)
  if not db then return false, derr end
  userDB = db
  return true
end

-- ============================================================
-- Initialization
-- ============================================================

function users.init(modules)
  fs     = modules.fs
  crypto = modules.crypto
  log    = modules.log
  config = modules.config

  -- Read security settings from config (fall back to sensible defaults)
  if config then
    local ma = config.get and config.get("maxAttempts")
    if type(ma) == "number" and ma > 0 then MAX_FAILED_ATTEMPTS = ma end
    local al = config.get and config.get("autoLockout")
    if al ~= nil then LOCKOUT_AUTO = al ~= false end
    local st = config.get and config.get("sessionTimeout")
    if type(st) == "number" and st > 0 then SESSION_TIMEOUT = st
    elseif st == 0 then SESSION_TIMEOUT = math.huge end  -- 0 = never expire
  end

  if crypto then crypto.init() end

  -- Load existing user database
  local ok, err = loadDB()
  if not ok then
    if log then log.warn("users", "Could not load user DB: " .. tostring(err)) end
    userDB = {}
  end

  -- Create root account if it doesn't exist (first boot)
  if not userDB["root"] then
    users.createFirstBoot()
  end

  -- Create guest account if guestAccess is enabled and no guest user exists
  if config and config.get and config.get("guestAccess") and not userDB["guest"] then
    users.createGuestAccount()
  end

  -- Ensure /public exists
  if not fs.exists("/public") then
    fs.makeDirectory("/public")
  end
  if not fs.exists("/home") then
    fs.makeDirectory("/home")
  end

  if log then
    local count = 0
    for _ in pairs(userDB) do count = count + 1 end
    log.info("users", "User system initialized (" .. count .. " accounts)")
    log.info("users", "Crypto: " .. (crypto.hasHardware() and "Hardware (data card)" or "Software"))
  end

  return true
end

--- First-boot setup: create root with default password
function users.createFirstBoot()
  local salt = crypto.salt(16)
  local hash = crypto.hashPassword("root", salt)  -- Default password

  userDB["root"] = {
    tier           = TIER.ROOT,
    salt           = salt,
    hash           = hash,
    created        = computer.uptime(),
    lastLogin      = 0,
    locked         = false,
    failedAttempts = 0,
    home           = "/root",
    displayName    = "System Administrator",
    firstBoot      = true,  -- Flag to force password change
  }

  -- Create root home
  if fs and not fs.exists("/root") then
    fs.makeDirectory("/root")
  end

  saveDB()

  if log then
    log.warn("users", "First boot: root account created with default password")
    log.warn("users", "CHANGE THE ROOT PASSWORD IMMEDIATELY!")
  end
end

-- ============================================================
-- Guest account support
-- ============================================================

--- Create the built-in guest account (no password, GUEST tier)
function users.createGuestAccount()
  userDB["guest"] = {
    tier           = TIER.GUEST,
    salt           = "",
    hash           = "",
    created        = computer.uptime(),
    lastLogin      = 0,
    locked         = false,
    failedAttempts = 0,
    home           = "/public",
    displayName    = "Guest",
    isGuest        = true,
  }
  saveDB()
  if log then log.info("users", "Guest account created") end
end

--- Check if guest access is currently enabled
function users.guestEnabled()
  return config and config.get and config.get("guestAccess") == true
end

--- Log in as guest (no password required, must be enabled in config)
-- @return session_token or nil, error_message
function users.guestLogin()
  if not users.guestEnabled() then
    return nil, "Guest access is disabled"
  end

  -- Create guest account on demand if it doesn't exist yet
  if not userDB["guest"] then
    users.createGuestAccount()
  end

  local user = userDB["guest"]
  if user.locked then
    return nil, "Guest account is locked"
  end

  user.lastLogin = computer.uptime()
  saveDB()

  local token = crypto.token()
  sessions[token] = {
    user         = "guest",
    tier         = TIER.GUEST,
    home         = user.home,
    displayName  = "Guest",
    loginTime    = computer.uptime(),
    lastActivity = computer.uptime(),
    firstBoot    = false,
    isGuest      = true,
  }

  currentSession = token

  if log then log.info("auth", "Guest login") end
  return token
end

-- ============================================================
-- User management
-- ============================================================

--- Create a new user account
-- @param creator string: Username of who's creating (must be admin/root)
-- @param username string: New username
-- @param password string: Initial password
-- @param tier number: Access tier (TIER.USER by default)
-- @return boolean, string: Success, error message
function users.create(creator, username, password, tier)
  -- Validate creator permissions (creator is always required for the public API;
  -- first-boot root creation goes through createFirstBoot() which bypasses this)
  if not creator then
    return false, "Creator username is required"
  end
  local creatorUser = userDB[creator]
  if not creatorUser then return false, "Creator not found" end
  if creatorUser.tier < TIER.ADMIN then return false, "Insufficient privileges" end

  -- Validate username
  if not username or #username < 2 or #username > 20 then
    return false, "Username must be 2-20 characters"
  end
  if username:match("[^%w_%-]") then
    return false, "Username can only contain letters, numbers, _ and -"
  end
  if userDB[username] then
    return false, "Username already exists"
  end

  -- Validate password
  if not password or #password < 6 then
    return false, "Password must be at least 6 characters"
  end

  tier = tier or TIER.USER

  -- Can't create root-level users
  if tier >= TIER.ROOT and (not creator or creator ~= "root") then
    return false, "Only root can create root-level accounts"
  end

  local salt = crypto.salt(16)
  local hash = crypto.hashPassword(password, salt)

  local homePath = "/home/" .. username
  userDB[username] = {
    tier           = tier,
    salt           = salt,
    hash           = hash,
    created        = computer.uptime(),
    lastLogin      = 0,
    locked         = false,
    failedAttempts = 0,
    home           = homePath,
    displayName    = username,
  }

  -- Create home directory
  if not fs.exists(homePath) then
    fs.makeDirectory(homePath)
  end

  saveDB()

  if log then
    log.info("users", string.format("User '%s' created (tier %d) by %s",
      username, tier, creator or "system"))
  end

  return true
end

--- Delete a user account
function users.delete(actor, username)
  local actorUser = userDB[actor]
  if not actorUser or actorUser.tier < TIER.ADMIN then
    return false, "Insufficient privileges"
  end
  if username == "root" then
    return false, "Cannot delete root account"
  end
  if not userDB[username] then
    return false, "User not found"
  end

  -- Invalidate sessions BEFORE saving the DB: even if saveDB fails,
  -- the deleted user can no longer use their active session tokens.
  -- Collect tokens first to avoid modifying table during pairs() iteration.
  local toRemove = {}
  for token, session in pairs(sessions) do
    if session.user == username then
      toRemove[#toRemove + 1] = token
    end
  end
  for _, token in ipairs(toRemove) do
    sessions[token] = nil
  end

  -- Don't delete home directory (safety) - admin can do that manually
  userDB[username] = nil
  saveDB()

  if log then
    log.info("users", string.format("User '%s' deleted by %s", username, actor))
  end
  return true
end

--- Change a user's password
function users.changePassword(actor, username, oldPassword, newPassword)
  local user = userDB[username]
  if not user then return false, "User not found" end

  -- Users can change their own password, admins can change anyone's
  local actorUser = userDB[actor]
  if actor ~= username then
    if not actorUser or actorUser.tier < TIER.ADMIN then
      return false, "Insufficient privileges"
    end
  else
    -- Verify old password for self-change
    if not crypto.verifyPassword(oldPassword, user.salt, user.hash) then
      return false, "Current password is incorrect"
    end
  end

  if not newPassword or #newPassword < 6 then
    return false, "New password must be at least 6 characters"
  end

  local newSalt = crypto.salt(16)
  user.salt = newSalt
  user.hash = crypto.hashPassword(newPassword, newSalt)
  user.firstBoot = nil  -- Clear first-boot flag

  saveDB()

  if log then
    log.info("users", string.format("Password changed for '%s' by %s", username, actor))
  end
  return true
end

--- Set a user's access tier
function users.setTier(actor, username, newTier)
  local actorUser = userDB[actor]
  if not actorUser or actorUser.tier < TIER.ADMIN then
    return false, "Insufficient privileges"
  end
  if username == "root" then
    return false, "Cannot change root tier"
  end
  local user = userDB[username]
  if not user then return false, "User not found" end

  -- Admins can't promote to ROOT
  if newTier >= TIER.ROOT and actorUser.tier < TIER.ROOT then
    return false, "Only root can grant root access"
  end

  user.tier = newTier
  saveDB()

  if log then
    log.info("users", string.format("User '%s' tier set to %d by %s",
      username, newTier, actor))
  end
  return true
end

--- Lock/unlock a user account
function users.setLocked(actor, username, locked)
  local actorUser = userDB[actor]
  if not actorUser or actorUser.tier < TIER.ADMIN then
    return false, "Insufficient privileges"
  end
  local user = userDB[username]
  if not user then return false, "User not found" end
  user.locked = locked
  if not locked then user.failedAttempts = 0 end
  saveDB()
  return true
end

-- ============================================================
-- Authentication & Sessions
-- ============================================================

--- Authenticate a user and create a session
-- @return session_token or nil, error_message
function users.login(username, password)
  local user = userDB[username]
  if not user then
    -- Don't reveal whether the username exists
    if log then log.warn("auth", "Login attempt for unknown user: " .. username) end
    return nil, "Invalid username or password"
  end

  if user.locked then
    if log then log.warn("auth", "Login attempt on locked account: " .. username) end
    return nil, "Account is locked. Contact an administrator."
  end

  if not crypto.verifyPassword(password, user.salt, user.hash) then
    user.failedAttempts = (user.failedAttempts or 0) + 1
    if log then
      log.warn("auth", string.format("Failed login for '%s' (attempt %d)",
        username, user.failedAttempts))
    end

    -- Auto-lock after too many failures
    if LOCKOUT_AUTO and user.failedAttempts >= MAX_FAILED_ATTEMPTS then
      user.locked = true
      saveDB()
      if log then log.error("auth", "Account '" .. username .. "' auto-locked!") end
      return nil, "Too many failed attempts. Account locked."
    end

    saveDB()
    return nil, "Invalid username or password"
  end

  -- Success!
  user.failedAttempts = 0
  user.lastLogin = computer.uptime()
  saveDB()

  -- Create session
  local token = crypto.token()
  sessions[token] = {
    user         = username,
    tier         = user.tier,
    home         = user.home,
    displayName  = user.displayName or username,
    loginTime    = computer.uptime(),
    lastActivity = computer.uptime(),
    firstBoot    = user.firstBoot or false,
  }

  currentSession = token

  if log then
    log.info("auth", "User '" .. username .. "' logged in (tier " .. user.tier .. ")")
  end

  return token
end

--- Logout / destroy session
function users.logout(token)
  token = token or currentSession
  if token and sessions[token] then
    local username = sessions[token].user
    sessions[token] = nil
    if token == currentSession then
      currentSession = nil
    end
    if log then log.info("auth", "User '" .. username .. "' logged out") end
    return true
  end
  return false
end

--- Get current session info (expires if idle too long)
-- Resolution order (phase 4):
--   1. The currently-running process's principal — if process.current()
--      has one, that IS the canonical answer. Each process carries its
--      own session so multiple concurrent principals on one machine
--      don't clobber each other.
--   2. _G._TOS.bootSession — set by kernel boot before any user exists.
--   3. The legacy module-global currentSession — kept for back-compat
--      paths that haven't been migrated yet.
function users.currentSession()
  -- 1. Process-bound principal (phase 4)
  local okProc, procMod = pcall(require, "kernel.process")
  if okProc and procMod and procMod.currentSession then
    local s = procMod.currentSession()
    if s then
      -- Touch lastActivity so real sessions don't expire while owned
      -- by a running process. Kernel sessions have math.huge and are
      -- unaffected.
      if s.lastActivity and s.lastActivity ~= math.huge then
        s.lastActivity = computer.uptime()
      end
      -- Retrieve the token from the process binding, not from the session
      -- object itself (sessions don't carry their own token internally).
      local tok = procMod.currentToken and procMod.currentToken() or nil
      return s, tok
    end
  end

  -- 2. Boot session fallback
  if _G._TOS and _G._TOS.bootSession then
    return _G._TOS.bootSession, nil
  end

  -- 3. Legacy global (pre-phase-4 code paths)
  if currentSession and sessions[currentSession] then
    local s = sessions[currentSession]
    local now = computer.uptime()
    if (now - (s.lastActivity or 0)) > SESSION_TIMEOUT then
      if log then log.info("auth", "Session expired for '" .. s.user .. "' (idle timeout)") end
      sessions[currentSession] = nil
      currentSession = nil
      return nil
    end
    s.lastActivity = now
    return s, currentSession
  end
  return nil
end

--- Get session by token (checks expiry)
function users.getSession(token)
  local s = sessions[token]
  if s then
    local now = computer.uptime()
    if (now - (s.lastActivity or 0)) > SESSION_TIMEOUT then
      if log then log.info("auth", "Session expired for '" .. s.user .. "' (idle timeout)") end
      sessions[token] = nil
      if token == currentSession then currentSession = nil end
      return nil
    end
  end
  return s
end

--- Sweep all expired sessions (call periodically from cron or kernel tick)
function users.sweepSessions()
  local now = computer.uptime()
  -- Collect expired tokens first to avoid modifying table during pairs()
  local expired = {}
  for token, s in pairs(sessions) do
    if (now - (s.lastActivity or 0)) > SESSION_TIMEOUT then
      expired[#expired + 1] = { token = token, user = s.user }
    end
  end
  for _, e in ipairs(expired) do
    if log then log.info("auth", "Sweeping expired session for '" .. e.user .. "'") end
    sessions[e.token] = nil
    if e.token == currentSession then currentSession = nil end
  end
end

-- ============================================================
-- Kernel / system sessions
-- ============================================================

-- Synthetic session for kernel boot code. Used by securefs before any
-- user has logged in (e.g. the kernel needs to write /etc/users.dat,
-- create /home, etc.). Never stored in the `sessions` table — callers
-- pass it explicitly via securefs.*(path, opts, session).
local KERNEL_SESSION = {
  user         = "_kernel_",
  tier         = TIER.ROOT,
  home         = "/",
  displayName  = "Kernel",
  isKernel     = true,
  loginTime    = 0,
  lastActivity = math.huge,  -- never expires
}

--- Return a synthetic root-tier session for kernel boot / privileged code.
-- Safe to call at any time; the returned object is a singleton.
function users.kernelSession()
  return KERNEL_SESSION
end

--- Look up a session by token without refreshing lastActivity.
-- Used by process binding so attaching a token to a process doesn't
-- keep it alive past its idle timeout on its own.
function users.sessionForToken(token)
  return sessions[token]
end

-- ============================================================
-- Permission checks
-- ============================================================

-- Files that are always world-readable regardless of the accessor's tier.
-- Needed so tier-0 (guest) programs can still read basic system identity
-- after securefs denies most of /etc by default.
local WORLD_READABLE = {
  ["/etc/motd"]     = true,
  ["/etc/hostname"] = true,
  ["/etc/profile"]  = true,
  ["/etc/tos.cfg"]  = true,
}

-- Internal: access check that takes an explicit session. This is the
-- canonical implementation; users.canAccess() is a thin back-compat
-- wrapper that resolves the current session itself.
local function checkAccess(session, path, mode)
  -- No session = no access (except during boot)
  if not session then
    return false, "Not logged in"
  end

  -- Root can do anything
  if session.tier >= TIER.ROOT then
    return true
  end

  -- Normalize path
  path = path or "/"
  if path:sub(1, 1) ~= "/" then path = "/" .. path end

  -- World-readable carve-outs (read only)
  if mode == "r" and WORLD_READABLE[path] then
    return true
  end

  -- Helper: check if path is exactly prefix or starts with prefix/
  local function pathUnder(p, prefix)
    return p == prefix or p:sub(1, #prefix + 1) == prefix .. "/"
  end

  -- System paths (read-only for non-root)
  local systemPaths = {"/tos", "/etc", "/var"}
  for _, sp in ipairs(systemPaths) do
    if pathUnder(path, sp) then
      if mode == "w" then
        return session.tier >= TIER.ADMIN, "System path (admin required)"
      end
      return true  -- Read is OK
    end
  end

  -- /public - everyone can read, USER+ can write
  if pathUnder(path, "/public") then
    if mode == "w" then
      return session.tier >= TIER.USER, "Write requires user account"
    end
    return true
  end

  -- /tmp - everyone can read/write
  if pathUnder(path, "/tmp") then
    return true
  end

  -- /home/<username> - only the owner (or admin+)
  local homeMatch = path:match("^/home/([^/]+)")
  if homeMatch then
    if homeMatch == session.user then
      return true  -- Own home directory
    end
    if session.tier >= TIER.ADMIN then
      return true  -- Admin can access all homes
    end
    return false, "Access denied: not your home directory"
  end

  -- /root - only root
  if pathUnder(path, "/root") then
    return session.tier >= TIER.ROOT, "Root access required"
  end

  -- Default: admin+ for write, user+ for read
  if mode == "w" then
    return session.tier >= TIER.ADMIN, "Admin privileges required"
  end
  return session.tier >= TIER.USER, "User account required"
end

--- Check if an explicit session can access a path.
-- This is the canonical session-aware API; securefs threads a session
-- through every call via this function.
function users.canAccessAs(session, path, mode)
  return checkAccess(session, path, mode)
end

--- Check if current user can access a path (back-compat wrapper)
function users.canAccess(path, mode)
  return checkAccess(users.currentSession(), path, mode)
end

--- Check if a user has a minimum access tier
function users.requireTier(minTier)
  local session = users.currentSession()
  if not session then return false, "Not logged in" end
  if session.tier < minTier then
    return false, "Insufficient privileges (need tier " .. minTier .. ")"
  end
  return true
end

-- ============================================================
-- User listing / info (for admin panels)
-- ============================================================

--- List all users (admin only returns full info)
function users.list(forTier)
  forTier = forTier or TIER.USER
  local result = {}
  for username, user in pairs(userDB) do
    local entry = {
      username    = username,
      tier        = user.tier,
      displayName = user.displayName or username,
      locked      = user.locked or false,
    }
    -- Only show sensitive info to admins
    if forTier >= TIER.ADMIN then
      entry.created        = user.created
      entry.lastLogin      = user.lastLogin
      entry.failedAttempts = user.failedAttempts
      entry.home           = user.home
    end
    result[#result + 1] = entry
  end
  table.sort(result, function(a, b)
    if a.tier ~= b.tier then return a.tier > b.tier end
    return a.username < b.username
  end)
  return result
end

--- Get user info (returns a shallow copy to protect internal state)
function users.getUser(username)
  local u = userDB[username]
  if not u then return nil end
  local copy = {}
  for k, v in pairs(u) do copy[k] = v end
  return copy
end

--- Check if user exists
function users.exists(username)
  return userDB[username] ~= nil
end

--- Get tier name
function users.tierName(tier)
  if tier >= TIER.ROOT then return "root"
  elseif tier >= TIER.ADMIN then return "admin"
  elseif tier >= TIER.USER then return "user"
  else return "guest" end
end

-- Export constants
users.TIER = TIER

return users
