local computer = require("computer")
local serialize = require("kernel.serialize")

local users = {}

local TIER = {
  GUEST  = 0,
  USER   = 1,
  ADMIN  = 2,
  ROOT   = 3,
}

local userDB = {}
local DB_PATH = "/etc/users.dat"
local SESSION_PATH = "/var/run/session"

local ELEVATE_PATH = "/etc/elevate.dat"

local sessions = {}
local currentSession = nil

local fs = nil
local crypto = nil
local log = nil
local config = nil

local MAX_FAILED_ATTEMPTS = 5
local LOCKOUT_AUTO = true
local SESSION_TIMEOUT = 3600

local MIN_PASSWORD_LEN = 6
local function validatePassword(pw)
  if type(pw) ~= "string" or #pw < MIN_PASSWORD_LEN then
    return false, "Password must be at least " .. MIN_PASSWORD_LEN .. " characters"
  end
  return true
end

local THROTTLE_AFTER = 3
local THROTTLE_BASE  = 5
local THROTTLE_CAP   = 300
local function loginCooldown(fails)
  fails = tonumber(fails) or 0
  if fails < THROTTLE_AFTER then return 0 end
  local c = THROTTLE_BASE * (2 ^ (fails - THROTTLE_AFTER))
  if c > THROTTLE_CAP then c = THROTTLE_CAP end
  return c
end

local function wallClock()
  return (os.time and os.time()) or computer.uptime()
end

local function saveDB()
  if not fs then
    if log then log.error("users", "saveDB: fs not initialized") end
    return false, "FS not initialized"
  end

  local ok, data = pcall(serialize.encode, userDB)
  if not ok then
    if log then log.error("users", "saveDB: serialize failed: " .. tostring(data)) end
    return false, "serialize failed: " .. tostring(data)
  end

  local okW, err = (fs.writeFileAtomic or fs.writeFile)(DB_PATH, data)
  if not okW then

    if log then log.error("users", "saveDB: write failed: " .. tostring(err)) end
    return false, tostring(err or "write failed")
  end
  return true
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

local function loadElevation()
  if not fs or not fs.exists(ELEVATE_PATH) then return nil end
  local data = fs.readFile(ELEVATE_PATH)
  if type(data) ~= "string" or data == "" then return nil end
  local rec = serialize.decode(data)
  if type(rec) ~= "table" or type(rec.hash) ~= "string"
     or type(rec.salt) ~= "string" then return nil end

  if rec.cap ~= TIER.ADMIN and rec.cap ~= TIER.ROOT then rec.cap = TIER.ADMIN end
  return rec
end

function users.setElevation(session, password, cap)
  local s = session or (currentSession and sessions[currentSession])
  if not s or (s.tier or 0) < TIER.ROOT then
    return false, "Only root can configure elevation"
  end
  local okPw, pwErr = validatePassword(password)
  if not okPw then return false, pwErr end
  if cap ~= TIER.ADMIN and cap ~= TIER.ROOT then
    return false, "cap must be admin or root"
  end
  local wasConfigured = loadElevation() ~= nil
  local salt = crypto.salt(16)
  local rec = { hash = crypto.hashPassword(password, salt), salt = salt, cap = cap }
  local data = serialize.encode(rec)
  local okW, err = (fs.writeFileAtomic or fs.writeFile)(ELEVATE_PATH, data)
  if not okW then return false, tostring(err or "write failed") end
  if log then log.warn("auth", "Elevation password " ..
    (wasConfigured and "updated" or "configured") .. " (cap tier " .. cap .. ") by "
    .. tostring(s.user)) end
  return true
end

function users.clearElevation(session)
  local s = session or (currentSession and sessions[currentSession])
  if not s or (s.tier or 0) < TIER.ROOT then
    return false, "Only root can disable elevation"
  end
  if fs and fs.exists(ELEVATE_PATH) then pcall(fs.remove, ELEVATE_PATH) end
  if log then log.warn("auth", "Elevation disabled by " .. tostring(s.user)) end
  return true
end

function users.elevationInfo()
  local rec = loadElevation()
  if not rec then return { configured = false } end
  return { configured = true, cap = rec.cap }
end

function users.elevate(session, password)
  local s = session or (currentSession and sessions[currentSession])
  local rec = loadElevation()

  local DUMMY_SALT = "elevate-timing-dummy"
  local probeSalt = (rec and rec.salt) or DUMMY_SALT
  local probeHash = (rec and rec.hash)
    or (crypto and crypto.hashPassword and crypto.hashPassword("x", DUMMY_SALT))
  local ok = false
  if crypto and crypto.verifyPassword and probeHash then
    ok = crypto.verifyPassword(password or "", probeSalt, probeHash)
  end
  if not s then return nil, "Not logged in" end
  if (s.tier or 0) < TIER.USER then return nil, "Guests cannot elevate" end
  if not rec then return nil, "Elevation is not configured" end
  if not ok then
    if log then log.warn("auth", "Failed elevation attempt by " .. tostring(s.user)) end
    return nil, "Incorrect elevation password"
  end

  local newTier = math.max(s.tier or 0, rec.cap)
  local elevated = {
    user         = s.user,
    tier         = newTier,
    realTier     = s.realTier or s.tier,
    home         = s.home,
    displayName  = s.displayName or s.user,
    loginTime    = s.loginTime,
    lastActivity = computer.uptime(),
    elevated     = true,
    elevatedFrom = s.tier or 0,
    elevatedCap  = rec.cap,
  }
  if log then log.warn("auth", "User '" .. tostring(s.user)
    .. "' elevated to tier " .. newTier) end
  return elevated
end

function users.registerSession(sess)
  if type(sess) ~= "table" or not sess.user then return nil end
  local token = crypto.token()
  sessions[token] = sess
  return token
end

function users.init(modules)
  fs     = modules.fs
  crypto = modules.crypto
  log    = modules.log
  config = modules.config

  if config then
    local ma = config.get and config.get("maxAttempts")
    if type(ma) == "number" and ma > 0 then MAX_FAILED_ATTEMPTS = ma end
    local al = config.get and config.get("autoLockout")
    if al ~= nil then LOCKOUT_AUTO = al ~= false end
    local st = config.get and config.get("sessionTimeout")
    if type(st) == "number" and st > 0 then SESSION_TIMEOUT = st
    elseif st == 0 then SESSION_TIMEOUT = math.huge end
  end

  if crypto then crypto.init() end

  local ok, err = loadDB()
  if not ok then
    if log then log.warn("users", "Could not load user DB: " .. tostring(err)) end
    userDB = {}
  end

  if not userDB["root"] then
    users.createFirstBoot()
  end

  if config and config.get and config.get("guestAccess") and not userDB["guest"] then
    users.createGuestAccount()
  end

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

function users.createFirstBoot()
  local salt = crypto.salt(16)
  local hash = crypto.hashPassword("root", salt)

  userDB["root"] = {
    tier           = TIER.ROOT,
    salt           = salt,
    hash           = hash,
    created        = wallClock(),
    lastLogin      = 0,
    locked         = false,
    failedAttempts = 0,
    home           = "/root",
    displayName    = "System Administrator",
    firstBoot      = true,
  }

  if fs and not fs.exists("/root") then
    fs.makeDirectory("/root")
  end

  saveDB()

  if log then
    log.warn("users", "First boot: root account created with default password")
    log.warn("users", "CHANGE THE ROOT PASSWORD IMMEDIATELY!")
  end
end

function users.createGuestAccount()
  userDB["guest"] = {
    tier           = TIER.GUEST,
    salt           = "",
    hash           = "",
    created        = wallClock(),
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

function users.guestEnabled()
  return config and config.get and config.get("guestAccess") == true
end

function users.guestLogin()
  if not users.guestEnabled() then
    return nil, "Guest access is disabled"
  end

  if not userDB["guest"] then
    users.createGuestAccount()
  end

  local user = userDB["guest"]
  if user.locked then
    return nil, "Guest account is locked"
  end

  user.lastLogin = wallClock()
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

function users.create(creator, username, password, tier)

  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then

    creator = sess.user
    if sess.tier < TIER.ADMIN then
      return false, "Insufficient privileges"
    end
  end
  if not creator then
    return false, "Creator username is required"
  end
  local creatorUser = userDB[creator]
  if not creatorUser then return false, "Creator not found" end

  local effTier = (sess and not sess.isKernel and not sess.isLogin)
    and (sess.tier or 0) or creatorUser.tier
  if effTier < TIER.ADMIN then return false, "Insufficient privileges" end

  if not username or #username < 2 or #username > 20 then
    return false, "Username must be 2-20 characters"
  end
  if username:match("[^%w_%-]") then
    return false, "Username can only contain letters, numbers, _ and -"
  end
  if userDB[username] then
    return false, "Username already exists"
  end

  local okPw, pwErr = validatePassword(password)
  if not okPw then return false, pwErr end

  tier = tier or TIER.USER

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
    created        = wallClock(),
    lastLogin      = 0,
    locked         = false,
    failedAttempts = 0,
    home           = homePath,
    displayName    = username,
  }

  if not fs.exists(homePath) then
    fs.makeDirectory(homePath)
  end

  local okS, sErr = saveDB()
  if not okS then

    userDB[username] = nil
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("User '%s' created (tier %d) by %s",
      username, tier, creator or "system"))
  end

  return true
end

function users.delete(actor, username)

  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    actor = sess.user
    if sess.tier < TIER.ADMIN then
      return false, "Insufficient privileges"
    end
  end
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

  local toRemove = {}
  for token, session in pairs(sessions) do
    if session.user == username then
      toRemove[#toRemove + 1] = token
    end
  end
  for _, token in ipairs(toRemove) do
    sessions[token] = nil
  end

  local deletedRecord = userDB[username]
  userDB[username] = nil
  local okS, sErr = saveDB()
  if not okS then

    userDB[username] = deletedRecord
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("User '%s' deleted by %s", username, actor))
  end
  return true
end

function users.changePassword(actor, username, oldPassword, newPassword)
  local user = userDB[username]
  if not user then return false, "User not found" end

  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    actor = sess.user
  end

  local actorUser = userDB[actor]
  if actor ~= username then
    if not actorUser or actorUser.tier < TIER.ADMIN then
      return false, "Insufficient privileges"
    end
  else

    local ok = crypto.verifyPassword(oldPassword, user.salt, user.hash)
    if not ok then
      return false, "Current password is incorrect"
    end
  end

  local okPw, pwErr = validatePassword(newPassword)
  if not okPw then return false, pwErr end

  local oldSalt, oldHash, oldFB = user.salt, user.hash, user.firstBoot
  local newSalt = crypto.salt(16)
  user.salt = newSalt
  user.hash = crypto.hashPassword(newPassword, newSalt)
  user.firstBoot = nil

  local okS, sErr = saveDB()
  if not okS then

    user.salt, user.hash, user.firstBoot = oldSalt, oldHash, oldFB
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("Password changed for '%s' by %s", username, actor))
  end
  return true
end

local function otherUsablePrivileged(excludeName)
  local n = 0
  for name, u in pairs(userDB) do
    if name ~= excludeName and type(u.tier) == "number"
       and u.tier >= TIER.ADMIN and not u.locked then
      n = n + 1
    end
  end
  return n
end

function users.setTier(actor, username, newTier)

  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    actor = sess.user
    if sess.tier < TIER.ADMIN then return false, "Insufficient privileges" end
  end
  local actorUser = userDB[actor]
  if not actorUser then return false, "Insufficient privileges" end

  local effTier = (sess and not sess.isKernel and not sess.isLogin)
    and (sess.tier or 0) or actorUser.tier
  if effTier < TIER.ADMIN then return false, "Insufficient privileges" end
  if username == "root" then
    return false, "Cannot change root tier"
  end
  local user = userDB[username]
  if not user then return false, "User not found" end

  if newTier >= TIER.ROOT and effTier < TIER.ROOT then
    return false, "Only root can grant root access"
  end

  if user.tier >= TIER.ADMIN and newTier < TIER.ADMIN
     and otherUsablePrivileged(username) == 0 then
    return false, "Refusing to demote the last administrator"
  end

  local oldTier = user.tier
  user.tier = newTier
  local okS, sErr = saveDB()
  if not okS then
    user.tier = oldTier
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("User '%s' tier set to %d by %s",
      username, newTier, actor))
  end
  return true
end

function users.setLocked(actor, username, locked)

  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    actor = sess.user
    if sess.tier < TIER.ADMIN then return false, "Insufficient privileges" end
  end
  local actorUser = userDB[actor]
  if not actorUser or actorUser.tier < TIER.ADMIN then
    return false, "Insufficient privileges"
  end
  local user = userDB[username]
  if not user then return false, "User not found" end

  if locked and type(user.tier) == "number" and user.tier >= TIER.ADMIN
     and not user.locked and otherUsablePrivileged(username) == 0 then
    return false, "Refusing to lock the last usable administrator"
  end
  local oldLocked, oldFA, oldLF = user.locked, user.failedAttempts, user.lastFailedAt
  user.locked = locked

  user.failedAttempts = 0
  user.lastFailedAt = nil
  local okS, sErr = saveDB()
  if not okS then
    user.locked, user.failedAttempts, user.lastFailedAt = oldLocked, oldFA, oldLF
    return false, "Persist failed: " .. tostring(sErr)
  end
  return true
end

local _DUMMY_SALT = "0123456789abcdef"
local _dummyHashCache = nil
local function ensureDummyHash()
  if _dummyHashCache then return _dummyHashCache end
  if crypto and crypto.hashPassword then
    _dummyHashCache = crypto.hashPassword("dummy-password-for-timing-only", _DUMMY_SALT)
  end
  return _dummyHashCache
end

function users.login(username, password, opts)

  opts = opts or {}
  local opts_setCurrent = opts.setCurrent
  if opts_setCurrent == nil then opts_setCurrent = true end
  local user = userDB[username]
  if not user then

    local dummy = ensureDummyHash()
    if dummy and crypto and crypto.verifyPassword then
      crypto.verifyPassword(password or "", _DUMMY_SALT, dummy)
    end
    if log then log.warn("auth", "Login attempt for unknown user: " .. tostring(username)) end
    return nil, "Invalid username or password"
  end

  local cd = loginCooldown(user.failedAttempts)
  if cd > 0 then
    local last = tonumber(user.lastFailedAt) or 0
    local elapsed = wallClock() - last

    if elapsed < cd then
      local dummy = ensureDummyHash()
      if dummy and crypto and crypto.verifyPassword then
        crypto.verifyPassword(password or "", _DUMMY_SALT, dummy)
      end
      if log then
        log.warn("auth", string.format("Login throttled for '%s' (cooldown %ds)", username, cd))
      end
      return nil, "Invalid username or password"
    end
  end

  local verified, needsRehash = crypto.verifyPassword(password, user.salt, user.hash)
  if not verified then
    user.failedAttempts = (user.failedAttempts or 0) + 1

    user.lastFailedAt = wallClock()
    if log then
      log.warn("auth", string.format("Failed login for '%s' (attempt %d)",
        username, user.failedAttempts))
    end

    if LOCKOUT_AUTO and user.failedAttempts >= MAX_FAILED_ATTEMPTS
       and username ~= "root" then
      user.locked = true
      saveDB()
      if log then log.error("auth", "Account '" .. username .. "' auto-locked!") end

      return nil, "Invalid username or password"
    end

    saveDB()
    return nil, "Invalid username or password"
  end

  if user.locked then
    if log then log.warn("auth", "Login on locked account (correct password): " .. username) end
    return nil, "Account is locked. Contact an administrator."
  end

  user.failedAttempts = 0
  user.lastFailedAt = nil
  user.lastLogin = wallClock()

  if needsRehash then
    local newSalt = crypto.salt(16)
    user.salt = newSalt
    user.hash = crypto.hashPassword(password, newSalt)
    if log then log.info("auth", "Rehashed legacy credentials for '" .. username .. "'") end
  end

  saveDB()

  local effectiveTier = user.tier
  if user.firstBoot then
    effectiveTier = TIER.GUEST
  end

  local token = crypto.token()
  sessions[token] = {
    user            = username,
    tier            = effectiveTier,
    realTier        = user.tier,
    home            = user.home,
    displayName     = user.displayName or username,
    loginTime       = computer.uptime(),
    lastActivity    = computer.uptime(),
    firstBoot       = user.firstBoot or false,
    passwordChangeOnly = user.firstBoot or false,
  }

  if opts_setCurrent ~= false then
    currentSession = token
  end

  if log then
    if user.firstBoot then
      log.info("auth", "User '" .. username .. "' authenticated (firstBoot — restricted token)")
    else
      log.info("auth", "User '" .. username .. "' logged in (tier " .. user.tier .. ")")
    end
  end

  return token
end

function users.promoteAfterFirstBoot(token)
  local s = sessions[token]
  if not s then return false, "Unknown token" end
  if not s.passwordChangeOnly then return false, "Session is not first-boot" end
  local rec = userDB[s.user]
  if not rec then return false, "User not found" end
  if rec.firstBoot then

    return false, "First-boot password still required"
  end
  s.tier = s.realTier or rec.tier
  s.passwordChangeOnly = nil
  s.firstBoot = nil
  return true
end

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

function users.currentSession()

  local okProc, procMod = pcall(require, "kernel.process")
  if okProc and procMod and procMod.currentSession then
    local s = procMod.currentSession()
    if s then

      if s.lastActivity and s.lastActivity ~= math.huge then
        s.lastActivity = computer.uptime()
      end

      local tok = procMod.currentToken and procMod.currentToken() or nil
      return s, tok
    end
  end

  if _G._TOS and _G._TOS.bootSession then
    return _G._TOS.bootSession, nil
  end

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

function users.sweepSessions()
  local now = computer.uptime()

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

local KERNEL_SESSION = {
  user         = "_kernel_",
  tier         = TIER.ROOT,
  home         = "/",
  displayName  = "Kernel",
  isKernel     = true,
  loginTime    = 0,
  lastActivity = math.huge,
}

function users.kernelSession()
  return KERNEL_SESSION
end

function users.loginSession(dIdx)
  return {
    user         = "_login_",
    tier         = TIER.GUEST,
    home         = "/",
    displayName  = "Login (seat " .. tostring(dIdx or "?") .. ")",
    isLogin      = true,
    display      = dIdx,
    loginTime    = 0,
    lastActivity = math.huge,
  }
end

function users.sessionFor(username)
  if type(username) ~= "string" then return nil end
  local u = userDB[username]
  if not u then return nil end
  return {
    user         = username,
    tier         = u.tier,
    home         = u.home,
    displayName  = u.displayName or username,
    loginTime    = computer.uptime(),
    lastActivity = math.huge,
    isService    = true,
  }
end

function users.createSession(userOrName)
  local username
  if type(userOrName) == "string" then
    username = userOrName
  elseif type(userOrName) == "table" then

    username = type(userOrName.name) == "string" and userOrName.name or nil
  end
  if not username then return nil end

  local canonical = userDB[username]
  if not canonical then return nil end
  return {
    user         = username,
    tier         = canonical.tier,
    home         = canonical.home,
    displayName  = canonical.displayName or username,
    loginTime    = computer.uptime(),
    lastActivity = math.huge,
    isService    = true,
  }
end

local WORLD_READABLE = {
  ["/etc/motd"]     = true,
  ["/etc/hostname"] = true,
  ["/etc/profile"]  = true,
  ["/etc/tos.cfg"]  = true,
}

local SHADOW_PATHS = {
  ["/etc/users.dat"] = true,
  ["/etc/shadow"]    = true,
  ["/var/shadow"]    = true,
}

local function checkAccess(session, path, mode)

  if not session then
    return false, "Not logged in"
  end

  if session.tier >= TIER.ROOT then
    return true
  end

  if type(path) ~= "string" or path == "" then
    path = "/"
  end
  if fs and fs.normalize then
    path = fs.normalize(path)
  else

    path = path:gsub("\\", "/")
    if path:find("\0", 1, true) then
      path = "/"
    else
      if path:sub(1, 1) ~= "/" then path = "/" .. path end
      local parts = {}
      for seg in path:gmatch("[^/]+") do
        if seg == ".." then parts[#parts] = nil
        elseif seg ~= "." then parts[#parts + 1] = seg end
      end
      path = "/" .. table.concat(parts, "/")
    end
  end

  if mode == "r" and WORLD_READABLE[path] then
    return true
  end

  if SHADOW_PATHS[path] then
    if mode == "r" then
      return session.tier >= TIER.ADMIN, "Shadow file (admin required)"
    end
    return session.tier >= TIER.ROOT, "Shadow file (root required)"
  end

  local function pathUnder(p, prefix)
    return p == prefix or p:sub(1, #prefix + 1) == prefix .. "/"
  end

  local mailUser = path:match("^/var/mail/([^/]+)")
  if mailUser then
    if session.user ~= mailUser and session.tier < TIER.ADMIN then
      return false, "Access denied: not your mailbox"
    end
    if mode == "w" then
      return session.tier >= TIER.ADMIN, "System path (admin required)"
    end
    return true
  end

  local systemPaths = {"/tos", "/etc", "/var", "/usr"}
  for _, sp in ipairs(systemPaths) do
    if pathUnder(path, sp) then
      if mode == "w" then
        return session.tier >= TIER.ADMIN, "System path (admin required)"
      end
      return true
    end
  end

  if pathUnder(path, "/public") then
    if mode == "w" then
      return session.tier >= TIER.USER, "Write requires user account"
    end
    return true
  end

  if pathUnder(path, "/tmp") then
    return true
  end

  local homeMatch = path:match("^/home/([^/]+)")
  if homeMatch then
    if homeMatch == session.user then
      return true
    end
    if session.tier >= TIER.ADMIN then
      return true
    end
    return false, "Access denied: not your home directory"
  end

  if pathUnder(path, "/root") then
    return session.tier >= TIER.ROOT, "Root access required"
  end

  if mode == "w" then
    return session.tier >= TIER.ADMIN, "Admin privileges required"
  end
  return session.tier >= TIER.USER, "User account required"
end

function users.canAccessAs(session, path, mode)
  return checkAccess(session, path, mode)
end

function users.canAccess(path, mode)
  return checkAccess(users.currentSession(), path, mode)
end

function users.list(forTier)
  local sess = users.currentSession()
  local sessTier = (sess and sess.tier) or TIER.GUEST
  local cap = forTier or sessTier

  if cap > sessTier then cap = sessTier end
  forTier = cap
  local result = {}
  for username, user in pairs(userDB) do
    local entry = {
      username    = username,
      tier        = user.tier,
      displayName = user.displayName or username,
      locked      = user.locked or false,
    }

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

function users.getUser(username)
  local u = userDB[username]
  if not u then return nil end
  local copy = {}
  for k, v in pairs(u) do copy[k] = v end

  copy.name = username

  copy.salt = nil
  copy.hash = nil
  return copy
end

function users.exists(username)
  return userDB[username] ~= nil
end

users.TIER = TIER

return users
