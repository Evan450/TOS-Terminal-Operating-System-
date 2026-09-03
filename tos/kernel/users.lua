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
-- Privilege elevation (sudo-style): a SEPARATE elevation password lets a
-- non-root user temporarily perform higher-tier ACTIONS without holding
-- the root account or its login password. Stored apart from the user DB
-- as { hash, salt, cap } where cap = TIER.ADMIN or TIER.ROOT (root sets
-- the ceiling when configuring). Absent file = elevation DISABLED (opt-in;
-- no default, so no new default-password hole).
local ELEVATE_PATH = "/etc/elevate.dat"

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

-- #SEC L — single source of truth for password policy. users.create and
-- users.changePassword both call validatePassword(), so the minimum-length
-- rule can't drift between the create path and the change path (and every
-- shell UI that wraps them — passwd, useradd, firstBootSetup — inherits
-- the same rule via the kernel, which is authoritative).
local MIN_PASSWORD_LEN = 6
local function validatePassword(pw)
  if type(pw) ~= "string" or #pw < MIN_PASSWORD_LEN then
    return false, "Password must be at least " .. MIN_PASSWORD_LEN .. " characters"
  end
  return true
end

-- #SEC H-5 — login backoff. The literal "root" account is exempt from
-- the permanent auto-lock (it is the rescue account), which previously
-- meant an attacker could brute-force root online with unlimited,
-- undelayed attempts. We now impose an exponentially-growing cooldown
-- between attempts once failures accumulate; this applies to EVERY
-- account, including ones that can never be hard-locked. Cooldown uses
-- the persisted wall clock (cf. H-9) so a reboot cannot reset it.
local THROTTLE_AFTER = 3    -- free attempts before backoff engages
local THROTTLE_BASE  = 5    -- seconds (first throttled attempt)
local THROTTLE_CAP   = 300  -- seconds (ceiling)
local function loginCooldown(fails)
  fails = tonumber(fails) or 0
  if fails < THROTTLE_AFTER then return 0 end
  local c = THROTTLE_BASE * (2 ^ (fails - THROTTLE_AFTER))
  if c > THROTTLE_CAP then c = THROTTLE_CAP end
  return c
end

-- #SEC H9 — wall-clock timestamp for PERSISTED audit fields (account
-- `created`, `lastLogin`). computer.uptime() counts seconds since the
-- last boot and resets to ~0 on every reboot, so storing it makes these
-- records meaningless after a power-cycle (a "created at 167" stamp, an
-- account that always looks freshly created/logged-in). os.time() gives
-- a monotonic-across-reboots world clock. NOTE: live session liveness
-- (loginTime / lastActivity, compared against computer.uptime() for the
-- idle-timeout) must KEEP using uptime — mixing the two clocks there
-- would break timeout math, so those call sites are intentionally left.
local function wallClock()
  return (os.time and os.time()) or computer.uptime()
end

-- ============================================================
-- Database I/O
-- ============================================================

local function saveDB()
  if not fs then
    if log then log.error("users", "saveDB: fs not initialized") end
    return false, "FS not initialized"
  end
  -- Protect the serializer itself — a broken user DB (e.g. corrupted
  -- in-memory table) would otherwise crash the caller mid-mutation and
  -- leave the system in an inconsistent state.
  local ok, data = pcall(serialize.encode, userDB)
  if not ok then
    if log then log.error("users", "saveDB: serialize failed: " .. tostring(data)) end
    return false, "serialize failed: " .. tostring(data)
  end
  -- Atomic write when available: a power cut mid-save must not truncate
  -- /etc/users.dat (a corrupt user DB locks everyone out).
  local okW, err = (fs.writeFileAtomic or fs.writeFile)(DB_PATH, data)
  if not okW then
    -- Loud error: the DB mutation happened in-memory but won't survive
    -- a reboot. Operators MUST see this so they can intervene (free
    -- disk space, fix mount, etc.) before the next power-cycle wipes
    -- their changes. Swallowing this was the risk flagged in review.
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

-- ============================================================
-- Privilege elevation (sudo / doas equivalent)
-- ============================================================
-- Threat model: the elevation password is effectively "temporary keys to
-- higher-tier actions". It is stored hashed+salted like any password,
-- verified in constant time, and every attempt (pass or fail) is logged.
-- It NEVER grants access to the root account itself — only an elevated
-- session bound to the CALLING user's identity, capped at the configured
-- ceiling. Guests can never elevate.

local function loadElevation()
  if not fs or not fs.exists(ELEVATE_PATH) then return nil end
  local data = fs.readFile(ELEVATE_PATH)
  if type(data) ~= "string" or data == "" then return nil end
  local rec = serialize.decode(data)
  if type(rec) ~= "table" or type(rec.hash) ~= "string"
     or type(rec.salt) ~= "string" then return nil end
  -- Clamp the stored ceiling to a known tier; default to ADMIN (the safer
  -- of the two) if it was tampered to something out of range.
  if rec.cap ~= TIER.ADMIN and rec.cap ~= TIER.ROOT then rec.cap = TIER.ADMIN end
  return rec
end

--- Configure (or replace) the elevation password. ROOT only. `cap` is the
--- ceiling elevation grants: TIER.ADMIN or TIER.ROOT.
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

--- Disable elevation entirely (remove the password). ROOT only.
function users.clearElevation(session)
  local s = session or (currentSession and sessions[currentSession])
  if not s or (s.tier or 0) < TIER.ROOT then
    return false, "Only root can disable elevation"
  end
  if fs and fs.exists(ELEVATE_PATH) then pcall(fs.remove, ELEVATE_PATH) end
  if log then log.warn("auth", "Elevation disabled by " .. tostring(s.user)) end
  return true
end

--- Public status (no secret): is elevation configured, and its ceiling.
function users.elevationInfo()
  local rec = loadElevation()
  if not rec then return { configured = false } end
  return { configured = true, cap = rec.cap }
end

--- Elevate `session` using the elevation password. Returns a NEW elevated
--- session table (same user + home, tier raised to min(cap, ROOT)),
--- flagged `elevated`, or (nil, reason). The caller decides whether to use
--- it transiently (one command) or register it as a token (`sudo -s`).
--- Guests are refused outright; a dummy verify still runs so a wrong
--- password and a disabled/guest case are timing-indistinguishable.
function users.elevate(session, password)
  local s = session or (currentSession and sessions[currentSession])
  local rec = loadElevation()
  -- Constant-time-ish: always run a verify (against a self-contained dummy
  -- when elevation isn't configured) so "wrong password", "not configured",
  -- and "guest" are timing-indistinguishable. Self-contained because the
  -- login module's dummy-hash cache is declared later in this file.
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
  -- Never exceed the configured ceiling; never below the user's own tier.
  local newTier = math.max(s.tier or 0, rec.cap)
  local elevated = {
    user         = s.user,
    tier         = newTier,
    realTier     = s.realTier or s.tier,
    home         = s.home,
    displayName  = s.displayName or s.user,
    loginTime    = s.loginTime,
    lastActivity = computer.uptime(),
    elevated     = true,          -- audit: this is an elevated session
    elevatedFrom = s.tier or 0,   -- the tier it was raised from
    elevatedCap  = rec.cap,
  }
  if log then log.warn("auth", "User '" .. tostring(s.user)
    .. "' elevated to tier " .. newTier) end
  return elevated
end

--- Register an elevated session as a real token (for `sudo -s`). Returns
--- the token, or nil. Kept separate so per-command elevation stays
--- token-free (nothing to leak / forget to revoke).
function users.registerSession(sess)
  if type(sess) ~= "table" or not sess.user then return nil end
  local token = crypto.token()
  sessions[token] = sess
  return token
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
    created        = wallClock(),
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
  -- #SEC C8: prefer the live session over a caller-supplied actor name.
  -- A caller could previously pass any admin's name and impersonate them.
  -- We still accept `creator` for compatibility with kernel boot code, but
  -- it MUST match (or be subordinate to) the session's user. Boot code
  -- runs under the synthetic _kernel_ root session and so always passes.
  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    -- A real session: ignore `creator` and use the session's principal.
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
  -- #SEC (sudo) — authorize on the caller's EFFECTIVE tier: a real
  -- session's tier (which sudo elevation may have legitimately raised —
  -- password-verified + capped), falling back to the stored account tier
  -- only for kernel/boot callers with no bound session. The old stored-tier
  -- re-check refused a valid elevated admin; the session already binds the
  -- actor (line above), so re-deriving privilege from the account is both
  -- redundant for identity and wrong for elevation.
  local effTier = (sess and not sess.isKernel and not sess.isLogin)
    and (sess.tier or 0) or creatorUser.tier
  if effTier < TIER.ADMIN then return false, "Insufficient privileges" end

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

  -- Validate password (#SEC L — centralized policy)
  local okPw, pwErr = validatePassword(password)
  if not okPw then return false, pwErr end

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
    created        = wallClock(),
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

  local okS, sErr = saveDB()
  if not okS then
    -- Roll back the in-memory change so our view matches disk.
    userDB[username] = nil
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("User '%s' created (tier %d) by %s",
      username, tier, creator or "system"))
  end

  return true
end

--- Delete a user account
function users.delete(actor, username)
  -- #SEC C8: session takes precedence over caller-supplied `actor`.
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
  local deletedRecord = userDB[username]
  userDB[username] = nil
  local okS, sErr = saveDB()
  if not okS then
    -- Restore the user record so memory and disk stay consistent.
    -- Sessions were already invalidated above; they stay revoked — that's
    -- fine, the user just has to log in again.
    userDB[username] = deletedRecord
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("User '%s' deleted by %s", username, actor))
  end
  return true
end

--- Change a user's password
function users.changePassword(actor, username, oldPassword, newPassword)
  local user = userDB[username]
  if not user then return false, "User not found" end

  -- #SEC C8: bind to the live session. The previous implementation
  -- accepted any `actor` string and skipped the old-password check
  -- when actor ~= username — a sandboxed caller could pass actor =
  -- "admin1" and change root's password with no credentials.
  --
  -- Carve-out for synthetic principals (isKernel / isLogin): these
  -- are pseudo-sessions used by kernel boot code and the login UI's
  -- first-boot password flow. In those contexts the caller-supplied
  -- `actor` is the right thing to use — and for self-change the old
  -- password still has to verify below, so this isn't a privilege
  -- escalation path. (First-boot calls changePassword("root",
  -- "root", "root", new) — actor == username, old password verified
  -- against the stored hash.)
  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    actor = sess.user
  end

  -- Users can change their own password, admins can change anyone's
  local actorUser = userDB[actor]
  if actor ~= username then
    if not actorUser or actorUser.tier < TIER.ADMIN then
      return false, "Insufficient privileges"
    end
  else
    -- Verify old password for self-change
    local ok = crypto.verifyPassword(oldPassword, user.salt, user.hash)
    if not ok then
      return false, "Current password is incorrect"
    end
  end

  local okPw, pwErr = validatePassword(newPassword)  -- #SEC L — centralized policy
  if not okPw then return false, pwErr end

  local oldSalt, oldHash, oldFB = user.salt, user.hash, user.firstBoot
  local newSalt = crypto.salt(16)
  user.salt = newSalt
  user.hash = crypto.hashPassword(newPassword, newSalt)
  user.firstBoot = nil  -- Clear first-boot flag

  local okS, sErr = saveDB()
  if not okS then
    -- Revert. A password change that didn't persist would silently
    -- revert on reboot; worse, the user would think their new password
    -- works while the old one still does. Better to fail loudly.
    user.salt, user.hash, user.firstBoot = oldSalt, oldHash, oldFB
    return false, "Persist failed: " .. tostring(sErr)
  end

  if log then
    log.info("users", string.format("Password changed for '%s' by %s", username, actor))
  end
  return true
end

-- #SEC M-20 — count OTHER accounts that can still administer the system
-- (tier >= ADMIN and not locked), excluding `excludeName`. Used to refuse
-- the last-admin foot-gun: demoting or locking the final usable privileged
-- account would lock out all administration with no recovery short of the
-- emergency shell.
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

--- Set a user's access tier
function users.setTier(actor, username, newTier)
  -- #SEC C8: see users.create. Session is canonical.
  local sess = users.currentSession()
  if sess and not sess.isKernel and not sess.isLogin then
    actor = sess.user
    if sess.tier < TIER.ADMIN then return false, "Insufficient privileges" end
  end
  local actorUser = userDB[actor]
  if not actorUser then return false, "Insufficient privileges" end
  -- #SEC (sudo) — effective tier: elevated session tier when a real session
  -- is bound, else the stored account tier (kernel/boot). See users.create.
  local effTier = (sess and not sess.isKernel and not sess.isLogin)
    and (sess.tier or 0) or actorUser.tier
  if effTier < TIER.ADMIN then return false, "Insufficient privileges" end
  if username == "root" then
    return false, "Cannot change root tier"
  end
  local user = userDB[username]
  if not user then return false, "User not found" end

  -- Only ROOT-effective callers may grant ROOT (an ADMIN — stored or
  -- elevated-capped-at-admin — cannot).
  if newTier >= TIER.ROOT and effTier < TIER.ROOT then
    return false, "Only root can grant root access"
  end

  -- #SEC M-20 — refuse to demote the last usable administrator.
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

--- Lock/unlock a user account
function users.setLocked(actor, username, locked)
  -- #SEC C8: session is canonical.
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
  -- #SEC M-20 — refuse to lock the last usable administrator (this
  -- includes locking root when it is the only unlocked privileged
  -- account), which would otherwise lock out all administration.
  if locked and type(user.tier) == "number" and user.tier >= TIER.ADMIN
     and not user.locked and otherUsablePrivileged(username) == 0 then
    return false, "Refusing to lock the last usable administrator"
  end
  local oldLocked, oldFA, oldLF = user.locked, user.failedAttempts, user.lastFailedAt
  user.locked = locked
  -- Reset the auto-lockout counter on any manual lock state change so the
  -- next cycle starts fresh regardless of which direction the admin took.
  user.failedAttempts = 0
  user.lastFailedAt = nil  -- #SEC H-5 — also clear the backoff timer
  local okS, sErr = saveDB()
  if not okS then
    user.locked, user.failedAttempts, user.lastFailedAt = oldLocked, oldFA, oldLF
    return false, "Persist failed: " .. tostring(sErr)
  end
  return true
end

-- ============================================================
-- Authentication & Sessions
-- ============================================================

--- Authenticate a user and create a session
-- @return session_token or nil, error_message
-- #SEC M8 — timing-oracle defense: when an unknown username comes in,
-- run a dummy verifyPassword against a stable fixed hash so the call
-- takes ~the same wall-clock time as a known-user mismatch. Otherwise
-- an attacker sees "user not found" return in microseconds vs.
-- "wrong password" returning in (rounds × hash) milliseconds and can
-- enumerate the user DB by timing alone.
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
  -- #SEC M32 — opts.setCurrent (default true) — when false, do NOT
  -- mutate the module-global `currentSession`. Multi-seat callers
  -- (kernel/init's per-seat spawnLoginProcess) pass false so a
  -- second seat's login doesn't trample the first seat's fallback.
  opts = opts or {}
  local opts_setCurrent = opts.setCurrent
  if opts_setCurrent == nil then opts_setCurrent = true end
  local user = userDB[username]
  if not user then
    -- Don't reveal whether the username exists. #SEC M8 — burn the
    -- same CPU we would have burned on a real verify so the timing
    -- channel doesn't leak the answer.
    local dummy = ensureDummyHash()
    if dummy and crypto and crypto.verifyPassword then
      crypto.verifyPassword(password or "", _DUMMY_SALT, dummy)
    end
    if log then log.warn("auth", "Login attempt for unknown user: " .. tostring(username)) end
    return nil, "Invalid username or password"
  end

  -- #SEC H10 — do NOT short-circuit on user.locked here. The previous
  -- code returned the distinctive "Account is locked" message before any
  -- password check, so an unauthenticated attacker could enumerate valid
  -- usernames (and their lock state) purely from the error text. We now
  -- always run the password verify first; the locked-account message is
  -- only disclosed below to a caller who supplied the CORRECT password.
  -- A wrong password against a locked account falls through to the same
  -- generic "Invalid username or password" everyone else gets.

  -- #SEC H-5 — exponential backoff BEFORE we verify. Once failures
  -- accumulate, an attempt that arrives inside the cooldown window is
  -- refused without even checking the password, so brute force is capped
  -- at roughly one guess per (growing) cooldown — even for root, which
  -- never hard-locks. We burn an equivalent dummy verify first so this
  -- path's timing matches the unknown-user path (#SEC M8) and doesn't
  -- become an "account exists and is under cooldown" oracle. The
  -- cooldown rejection does NOT increment failedAttempts, so spamming
  -- during the window can't inflate a legitimate user's penalty.
  local cd = loginCooldown(user.failedAttempts)
  if cd > 0 then
    local last = tonumber(user.lastFailedAt) or 0
    local elapsed = wallClock() - last
    -- elapsed < 0 means the clock moved unexpectedly (e.g. uptime-fallback
    -- after reboot); fail closed and keep throttling rather than handing
    -- out a free attempt.
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
    -- #SEC H-5 — stamp the wall-clock time of this failure so the
    -- cooldown above can measure elapsed time across reboots.
    user.lastFailedAt = wallClock()
    if log then
      log.warn("auth", string.format("Failed login for '%s' (attempt %d)",
        username, user.failedAttempts))
    end

    -- Auto-lock after too many failures. The literal "root" account is
    -- exempt: locking it out would require emergency-shell recovery to
    -- restore access, defeating the rescue-account purpose. The
    -- rate-limiting (attempt counter logged above) still applies.
    -- #SEC M7 — exempt by USERNAME, not by TIER. If a future admin
    -- account is ever promoted to ROOT tier (or root is recreated under
    -- a different username), the exemption should still attach to the
    -- single canonical recovery account, not to whoever happens to hold
    -- ROOT tier at the moment.
    if LOCKOUT_AUTO and user.failedAttempts >= MAX_FAILED_ATTEMPTS
       and username ~= "root" then
      user.locked = true
      saveDB()
      if log then log.error("auth", "Account '" .. username .. "' auto-locked!") end
      -- #SEC H10 — lock the account, but return the SAME generic message
      -- as every other failure. A distinct "account locked" reply here is
      -- only reachable for a real, existing username (unknown users return
      -- early), so it would leak which usernames are valid. The legitimate
      -- owner learns of the lock when they later supply the correct
      -- password (handled above), or via an administrator.
      return nil, "Invalid username or password"
    end

    saveDB()
    return nil, "Invalid username or password"
  end

  -- #SEC H10 — password is correct. Only now is it safe to disclose
  -- that the account is locked: the caller has proven they hold the
  -- credentials, so this leaks nothing to an enumeration attacker.
  if user.locked then
    if log then log.warn("auth", "Login on locked account (correct password): " .. username) end
    return nil, "Account is locked. Contact an administrator."
  end

  -- Success!
  user.failedAttempts = 0
  user.lastFailedAt = nil  -- #SEC H-5 — clear the backoff timer
  user.lastLogin = wallClock()

  -- Opportunistic rehash: if the stored hash was in a legacy format,
  -- upgrade to the current stretched algorithm now that we have the
  -- plaintext password (#31). The new salt ensures the upgraded hash
  -- can't collide with any other account.
  if needsRehash then
    local newSalt = crypto.salt(16)
    user.salt = newSalt
    user.hash = crypto.hashPassword(password, newSalt)
    if log then log.info("auth", "Rehashed legacy credentials for '" .. username .. "'") end
  end

  saveDB()

  -- #SEC C11 — first-boot enforcement at the kernel layer, not the UI.
  -- The login UI checked `firstBoot` and ran the password-change dialog,
  -- but `users.login()` itself returned a full-tier token. Every other
  -- caller (autoLogin, emergency shell, minimalAuth, kernel REPL, any
  -- compat shim) could authenticate as root with the default "root"
  -- password and bypass the dialog entirely. Mint a restricted token
  -- here: it can be used to call users.changePassword for the same
  -- account, but the session's tier is forced to GUEST and `firstBoot`
  -- is set so other consumers (shell, securefs) can refuse privileged
  -- ops until the password is changed.
  local effectiveTier = user.tier
  if user.firstBoot then
    effectiveTier = TIER.GUEST
  end

  -- Create session
  local token = crypto.token()
  sessions[token] = {
    user            = username,
    tier            = effectiveTier,
    realTier        = user.tier,  -- so the password-change dialog can re-elevate after
    home            = user.home,
    displayName     = user.displayName or username,
    loginTime       = computer.uptime(),
    lastActivity    = computer.uptime(),
    firstBoot       = user.firstBoot or false,
    passwordChangeOnly = user.firstBoot or false,
  }

  -- #SEC M32 — DO NOT set the module-global currentSession on login
  -- when a per-seat shell is going to be spawned with its own principal.
  -- The previous behaviour mutated `currentSession` on every login, so
  -- two seats logging in close together each saw the OTHER seat's token
  -- as "the current session" via the legacy fallback path. The login
  -- caller now passes the token directly to spawnShellForSeat, which
  -- attaches it to that process. The legacy currentSession is kept as
  -- a back-compat fallback for un-sessioned callers (kernel boot
  -- pre-login), but we only set it from minimalAuth / emergency shell
  -- where there's exactly one current seat by definition.
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

--- Promote a firstBoot-restricted session to its real tier.
-- Called by the login flow after a successful password change. Refuses
-- if the user record still has firstBoot set (i.e. changePassword
-- didn't clear it) so a malicious caller can't bypass the dialog.
function users.promoteAfterFirstBoot(token)
  local s = sessions[token]
  if not s then return false, "Unknown token" end
  if not s.passwordChangeOnly then return false, "Session is not first-boot" end
  local rec = userDB[s.user]
  if not rec then return false, "User not found" end
  if rec.firstBoot then
    -- changePassword didn't clear the firstBoot flag — the password
    -- change either didn't happen or didn't persist. Stay restricted.
    return false, "First-boot password still required"
  end
  s.tier = s.realTier or rec.tier
  s.passwordChangeOnly = nil
  s.firstBoot = nil
  return true
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

--- Return a synthetic guest-tier session representing a not-yet-authenticated
-- seat at the login screen (#135). Each call returns a fresh table so that
-- independent seats can't mutate each other's principal. The login process
-- runs under this session instead of inheriting the ambient/boot/root session
-- — this way, if the login UI is ever compromised, the attacker sees only a
-- guest-tier token rather than root.
-- @param dIdx number: display index this login principal belongs to
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

--- Return a synthetic (non-token) session for the named user.
-- Used by rc.d services and cron jobs that declare `user = "..."` to
-- run under that user's principal without needing the password. The
-- returned session is NOT stored in the sessions table (no token
-- issued) and carries math.huge as lastActivity so it doesn't expire
-- — kernel-bound services would otherwise get kicked by the idle
-- reaper. Returns nil if the user doesn't exist.
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

--- Create a synthetic session for a user by username or from a user
-- record produced by users.getUser(). Separate from users.login() in
-- that it doesn't require a password — caller is assumed to already be
-- authorised (kernel boot, rc.d dispatcher, cron scheduler). Returns
-- nil on a bad/unknown input so miscalls fail closed rather than
-- minting a root token by default.
function users.createSession(userOrName)
  local username
  if type(userOrName) == "string" then
    username = userOrName
  elseif type(userOrName) == "table" then
    -- #SEC H7 — identify the record by its canonical username only.
    -- We deliberately do NOT match on salt+hash: that treated mere
    -- possession of the stored password hash (e.g. read out of
    -- /etc/users.dat) as proof of identity, letting a caller mint a
    -- session without ever knowing the password. getUser() now stamps
    -- the DB key onto the record as `.name`, so callers that pass a
    -- getUser() result still work; everything else falls closed.
    username = type(userOrName.name) == "string" and userOrName.name or nil
  end
  if not username then return nil end
  -- Always resolve via the canonical DB entry so a tampered input
  -- record can't elevate its tier beyond what the real user holds.
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

-- #SEC H7 — shadow paths. A read here yields salt + password hash for
-- every user; USER tier must NOT be able to dump it for offline cracking.
-- canAccessAs's generic "/etc is system path" branch returned `true` for
-- any read by any logged-in user; this set forces ADMIN+ specifically.
local SHADOW_PATHS = {
  ["/etc/users.dat"] = true,
  ["/etc/shadow"]    = true,
  ["/var/shadow"]    = true,
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

  -- #SEC H11 — canonicalize the path BEFORE any prefix/ACL matching.
  -- The old code only guaranteed a leading slash and left ".."/"." in
  -- place. securefs normalizes before it calls us, but the public
  -- users.canAccess / users.canAccessAs entry points do NOT — so a
  -- direct caller could pass "/home/<me>/../../etc/users.dat": the
  -- home-prefix branch below would match "<me>" and grant access while
  -- the real target was the shadow file. Resolve the path to its true
  -- target here and fail closed on anything that isn't a usable string.
  if type(path) ~= "string" or path == "" then
    path = "/"
  end
  if fs and fs.normalize then
    path = fs.normalize(path)
  else
    -- Self-contained fallback for early boot before fs is wired in.
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

  -- World-readable carve-outs (read only)
  if mode == "r" and WORLD_READABLE[path] then
    return true
  end

  -- #SEC H7: shadow files require ADMIN tier for read, ROOT for write.
  -- Checked BEFORE the generic /etc system-path branch (which would
  -- otherwise return true for any read by any logged-in user).
  if SHADOW_PATHS[path] then
    if mode == "r" then
      return session.tier >= TIER.ADMIN, "Shadow file (admin required)"
    end
    return session.tier >= TIER.ROOT, "Shadow file (root required)"
  end

  -- Helper: check if path is exactly prefix or starts with prefix/
  local function pathUnder(p, prefix)
    return p == prefix or p:sub(1, #prefix + 1) == prefix .. "/"
  end

  -- #SEC — /var/mail/<username> is PRIVATE to its owner (+ADMIN).
  -- Checked BEFORE the generic /var system-path branch, which returns
  -- "read OK" to ANY logged-in session (even guest) — that exposed
  -- delivered mail at rest: E2E sealing only protects mail IN FLIGHT;
  -- once opened into the inbox it's plaintext. Delivery is unaffected
  -- (the kernel mail controller writes through the raw kernel fs, not
  -- securefs); writes keep the system-path posture (ADMIN+).
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

  -- System paths (read-only for non-admin; admin+ may write).
  -- Kept in rough sync with securefs REMOVE_PROTECTED so users can't
  -- shadow or rewrite OS binaries via paths the ACL doesn't cover.
  local systemPaths = {"/tos", "/etc", "/var", "/usr"}
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

-- ============================================================
-- User listing / info (for admin panels)
-- ============================================================

--- List all users (admin only returns full info).
-- #SEC H19: the disclosure tier is read from the caller's session, NOT
-- from forTier. A USER previously passed `forTier = TIER.ADMIN` and got
-- back created/lastLogin/failedAttempts/home for every account. forTier
-- is retained only as a ceiling so admin code that wants the public view
-- can still ask for it (e.g. shell `users` command from the user shell).
function users.list(forTier)
  local sess = users.currentSession()
  local sessTier = (sess and sess.tier) or TIER.GUEST
  local cap = forTier or sessTier
  -- Never let `forTier` exceed the caller's actual tier — disclosure is
  -- bounded above by what the session is entitled to see.
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
  -- #SEC H7 — stamp the canonical username onto the returned record so
  -- createSession() can identify it by name rather than by matching on
  -- salt+hash (which made mere possession of the stored hash act as a
  -- credential). The name is the DB key, not attacker-supplied.
  copy.name = username
  -- #SEC — don't hand back the credential material. No caller of getUser
  -- needs the password salt/hash (createSession resolves the canonical
  -- record itself; the shell/diag callers only read tier/firstBoot/name),
  -- and returning them widens the surface for an accidental log/echo of a
  -- record to leak crackable hashes. Strip them from the projection.
  copy.salt = nil
  copy.hash = nil
  return copy
end

--- Check if user exists
function users.exists(username)
  return userDB[username] ~= nil
end

-- Export constants
users.TIER = TIER

return users
