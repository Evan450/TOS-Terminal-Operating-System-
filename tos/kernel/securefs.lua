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

--! #SEC (pentest, Sep 2026) — a path fs.normalize rejects (a NUL byte, a
--! non-string) is refused here, by name. It used to reach the ACL as nil,
--! which read it as "/" and said yes, and a write raised in the
--! protected-path check instead of refusing.
local INVALID_PATH = "Permission denied: invalid path  [E-401 ERR_PERM_DENIED]"

local function checkRead(path, session)
  if not fs or not usermod then return false, "securefs not initialized" end
  path = fs.normalize(path)
  if not path then return false, INVALID_PATH end
  local sess = sessionOf(session)
  local allowed, reason = usermod.canAccessAs(sess, path, "r")
  if not allowed then
    if log then log.warn("securefs", "READ denied: " .. path .. " (" .. (reason or "?") .. ")") end
    return false, "Permission denied: " .. (reason or "access denied") .. "  [E-401 ERR_PERM_DENIED]", path
  end
  return true, nil, path
end

-- Forward declaration so checkWrite can call into the protected-target
-- guard before it's defined further down. Defence-in-depth: even an admin
-- caller is blocked from writing under /tos, /etc, /init.lua, etc.
local _isProtectedTarget
--! Forward-declared for the same reason as the guard above:
--! checkWrite needs it and it is defined further down, next to
--! the protected-path tables it describes.
local protectedMsg

local function checkWrite(path, session)
  if not fs or not usermod then return false, "securefs not initialized" end
  path = fs.normalize(path)
  if not path then return false, INVALID_PATH end
  --! Resolve the principal BEFORE the protected check, not after. The
  --! shell supplies its session through the process, not as an explicit
  --! argument, so `session` here is usually nil -- and an override armed
  --! by root would never have been seen.
  local sess = sessionOf(session)
  -- #SEC C18 — every write op (writeFile, appendFile, makeDirectory,
  -- open w/+/a) flows through here. Previously the protected-set check
  -- only fired from remove/rename, letting an admin overwrite
  -- /tos/kernel/init.lua and brick or backdoor the OS on next boot.
  if _isProtectedTarget then
    local hit = _isProtectedTarget(path, sess)
    if hit then
      if log then log.warn("securefs",
        "WRITE denied (protected system path " .. hit .. "): " .. path ..
        " -- root can lift this for one session with `protect off`") end
      -- This is intentional even for root: it's a defence-in-depth line, not
      -- an ACL (so a tampered admin session can't backdoor the kernel/libs).
      -- Point the operator at the supported install path instead of leaving
      -- them to conclude root "should" be able to copy files in here.
      local hint = ""
      if hit == "/usr/lib" or hit == "/usr/modules" or hit == "/usr/bin"
         or hit == "/var/pkg" then
        hint = " — install add-ons with 'pkg install', not by copying files here"
      end
      return false, protectedMsg("writing to", hit, sess) .. hint, path
    end
  end
  local allowed, reason = usermod.canAccessAs(sess, path, "w")
  if not allowed then
    if log then log.warn("securefs", "WRITE denied: " .. path .. " (" .. (reason or "?") .. ")") end
    return false, "Permission denied: " .. (reason or "access denied") .. "  [E-401 ERR_PERM_DENIED]", path
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
  --! #SEC (pentest, Sep 2026) — matched on the folded key: "/HOME" lists
  --! /home on a case-insensitive disk, and skipped both filters below.
  local key = usermod.pathKey and usermod.pathKey(path) or path

  -- If listing /home, hide other users' homes from non-admin callers.
  -- #SEC H23 — previously, a nil session (early boot / un-attributed call)
  -- skipped the filter, showing every home dir. Treat nil/guest the same
  -- as a tier-0 caller: return an empty list rather than disclosing names.
  if key == "/home" then
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
  if key == "/var/mail" then
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

-- ============================================================
-- Operator override
-- ============================================================
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

--- Arm or disarm the protected-path override for one session.
-- Returns ok, err. ROOT tier only.
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

--- Is the override armed for this session? (For UI to show the state.)
function securefs.operatorOverride(session)
  return hasOverride(session)
end

--! One place builds the refusal text, so every path -- write, remove,
--! rename -- says the same three things: WHAT was refused, WHY, and what
--! to do about it.
--!
--! The old messages said only "Cannot write protected system path
--! (/etc)". True, and useless: the operator learned neither that the
--! rule is deliberate rather than a bug, nor that there is a supported
--! way past it. The full explanation existed only in the kernel log,
--! which is not somewhere anyone looks unless they already know to.
--!
--! The remedy line is TAILORED. Telling a plain user to run a root-only
--! command is noise that sends them looking for a permission they cannot
--! have, so they are told what it would take instead.
function protectedMsg(verb, hit, session)
  local base = "Refused: " .. verb .. " " .. hit ..
    " is a protected system path. This guard sits above the permission " ..
    "model and stops even an admin overwriting the kernel or its libraries."
  local TIER = usermod and usermod.TIER
  local isRoot = TIER and session and session.tier and session.tier >= TIER.ROOT
  if isRoot then
    return base .. "  You own this machine: `protect off` stands the guard " ..
      "down for THIS SESSION ONLY (it ends at logout, and every path it " ..
      "allows is logged).  [E-402 ERR_PATH_PROTECTED]"
  end
  return base .. "  Only root can lift it, with `protect off`, and only " ..
    "for their own session.  [E-402 ERR_PATH_PROTECTED]"
end

-- Tree-exempt prefixes. Any of these covers writes ANYWHERE under
-- the listed directory — for things where the directory itself is
-- admin-managed but per-file paths are arbitrary (log rotation,
-- session/pid files, per-app cluster state, etc.).
local TREE_EXEMPT = {
  "/var/log/", "/var/run/", "/var/lib/", "/var/cluster/", "/etc/widgets/",
}

local function protectedHit(path)
  -- Direct-exempt overrides: a write to one of these specific files is
  -- permitted even though its containing dir is in REMOVE_PROTECTED.
  if WRITE_PROTECTED_EXEMPT[path] then return nil end
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

--! #SEC (pentest, Sep 2026) — checked as written AND as users.pathKey
--! folds it, because the disk may be case-insensitive (see pathKey in
--! kernel/users.lua): "/TOS/kernel/init.lua" was not "/tos", so an admin
--! could rewrite the kernel through it. Not a string: refused -- a NUL
--! byte makes fs.normalize return nil, and this used to raise on it.
local function isProtectedTarget(path, session)
  if type(path) ~= "string" then return "(invalid path)" end
  --! An armed root session sees no protected targets at all. Logged at
  --! the point of use so the record names the path, not just the arming.
  if hasOverride(session) then
    if log then
      log.warn("securefs", "Operator override: allowing protected path " .. tostring(path))
    end
    return nil
  end
  local hit = protectedHit(path)
  if hit then return hit end
  local key = usermod and usermod.pathKey and usermod.pathKey(path)
  if key and key ~= path then return protectedHit(key) end
  return nil
end
_isProtectedTarget = isProtectedTarget

function securefs.remove(path, session)
  -- Normalize FIRST so variants like "/tos/" or "/tos/." can't slip past
  path = fs.normalize(path)
  if not path then return false, INVALID_PATH end
  local hit = isProtectedTarget(path, sessionOf(session))
  if hit then
    return false, protectedMsg("removing", hit, sessionOf(session))
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
  if not nFrom or not nTo then return false, INVALID_PATH end
  -- Refuse to rename FROM or TO anything under the protected set. This
  -- closes the "rename /home -> /home.bak then recreate" side-door that
  -- would otherwise let a caller with write access to /home.bak (which
  -- they could create first) swap the real /home out from under users.
  local hitFrom = isProtectedTarget(nFrom, sessionOf(session))
  if hitFrom then
    return false, protectedMsg("renaming", hitFrom, sessionOf(session))
  end
  local hitTo = isProtectedTarget(nTo, sessionOf(session))
  if hitTo then
    return false, protectedMsg("renaming onto", hitTo, sessionOf(session))
  end
  local ok1, err1, normFrom = checkWrite(nFrom, session)
  if not ok1 then return false, err1 end
  local ok2, err2, normTo = checkWrite(nTo, session)
  if not ok2 then return false, err2 end
  return fs.rename(normFrom, normTo)
end

-- Cooperative slice between whole files (as kernel.fs does), so a big
-- tree copy slows the other seats instead of freezing them. Resolved
-- lazily: securefs loads before kernel.process is guaranteed to exist.
local coopProc = nil
local function coopYield()
  if coopProc == nil then
    local okP, m = pcall(require, "kernel.process")
    coopProc = (okP and type(m) == "table" and m.yieldCooperative) and m or false
  end
  if coopProc then coopProc.yieldCooperative() end
end

local function isUnder(p, root)
  return p == root or root == "/" or p:sub(1, #root + 1) == root .. "/"
end

--! #SEC (pentest, Sep 2026) — a DIRECTORY copy is checked per entry, as
--! the caller. It used to check the top path only and hand the tree to
--! kernel.fs.copyRecursive, which walks the raw filesystem. "/home" and
--! "/etc" are readable as directory NODES by any user, so `cp /home ~/x`
--! copied every other user's home and `cp /etc ~/x` copied
--! /etc/users.dat. Each entry now goes back through securefs.copy: the
--! same read check, the same filtered listing (/home and /var/mail show a
--! user only their own), the same write check on the destination.
--! (test_securefs_session_bind.lua)
local function copyTree(src, dst, session)
  if isUnder(dst, src) then
    return false, "Cannot copy a directory into itself"
  end
  if not fs.exists(dst) then
    local ok, err = fs.makeDirectory(dst)   -- dst already passed checkWrite
    if not ok then return false, "Cannot create directory: " .. tostring(err) end
  end
  local copied, failed = 0, 0
  for _, name in ipairs(securefs.list(src, session)) do
    coopYield()
    local clean = name:match("^(.-)/?$") or name
    if clean ~= "" then
      if securefs.copy(fs.join(src, clean), fs.join(dst, clean), session) then
        copied = copied + 1
      else
        failed = failed + 1
      end
    end
  end
  if failed > 0 then
    return false, string.format("Copied %d items, %d failed", copied, failed)
  end
  return true
end

function securefs.copy(src, dst, session)
  local ok1, err1, normSrc = checkRead(src, session)
  if not ok1 then return false, err1 end
  local ok2, err2, normDst = checkWrite(dst, session)
  if not ok2 then return false, err2 end
  if fs.isDirectory(normSrc) then
    return copyTree(normSrc, normDst, session)
  end
  -- A file: copied here rather than through fs.copy, which would recurse
  -- unchecked if the path had become a directory meanwhile. copyFile
  -- streams it a block at a time (#MEM); a stand-in fs without it falls
  -- back to the whole-file read.
  if fs.copyFile then return fs.copyFile(normSrc, normDst) end
  local content, err = fs.readFile(normSrc)
  if not content then return false, err end
  return fs.writeFile(normDst, content)
end

-- ── File handles (checked on open) ───────────────────────

--! #SEC (pentest, Sep 2026) — the mode is matched against the closed set
--! OpenComputers' managed filesystem accepts, not searched for "w"/"a"/"+".
--! Anything without those letters used to count as a READ, and a backend
--! decides for itself what an odd mode means: TBFS (blockfs) opens every
--! mode except exactly "r" writable, so open(p, "x") passed the read check
--! and came back with a handle that writes. On a machine booted from a raw
--! drive, that was any user rewriting /tos/kernel.
local READ_MODES  = { r = true, rb = true }
local WRITE_MODES = { w = true, wb = true, a = true, ab = true }

function securefs.open(path, mode, session)
  mode = mode or "r"
  if not (READ_MODES[mode] or WRITE_MODES[mode]) then
    return nil, "Unsupported open mode: " .. tostring(mode)
  end
  local ok, err, norm
  if WRITE_MODES[mode] then
    ok, err, norm = checkWrite(path, session)
  else
    ok, err, norm = checkRead(path, session)
  end
  if not ok then return nil, err end
  local h, herr = fs.open(norm, mode)
  if not h then return nil, herr end
  --! #SEC (pentest, Sep 2026) — return the four methods and nothing else.
  --! kernel.fs's handle also carries `proxy` -- the raw filesystem
  --! component -- and this table goes straight to sandboxed code, so one
  --! fs.open("/etc/motd") handed a program the whole disk with no ACL at
  --! all: h.proxy.remove("/init.lua"). (test_securefs_session_bind.lua)
  return {
    read  = function(_, n) return h:read(n) end,
    write = function(_, data) return h:write(data) end,
    seek  = function(_, whence, offset) return h:seek(whence, offset) end,
    close = function() return h:close() end,
  }
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

--! #SEC (pentest, Sep 2026) — a mount point is held to the protected-path
--! guard, as a write is. A mount replaces what a path resolves to, and
--! fs.mount takes an empty or absent directory anywhere, so an admin -- or
--! a drive's label, before `drive mount` sanitised it -- could put a disk of
--! their choosing at an empty /var/pkg/secrets or /etc/rc.d, where the guard
--! stops even an admin writing. /mnt, homes and /tmp are unaffected, and
--! root lifts it with `protect off` like any other. (test_mount_points.lua)
function securefs.mount(path, proxy, session)
  if not fs then return false, "securefs not initialized" end
  local ok, err = requireAdmin(session)
  if not ok then
    if log then log.warn("securefs", "MOUNT denied: " .. tostring(path) .. " (" .. err .. ")") end
    return false, "Permission denied: " .. err .. "  [E-401 ERR_PERM_DENIED]"
  end
  local norm = fs.normalize(path)
  if not norm then return false, INVALID_PATH end
  local hit = isProtectedTarget(norm, ok)
  if hit then
    if log then log.warn("securefs", "MOUNT denied (protected system path " .. hit .. "): " .. norm) end
    return false, protectedMsg("mounting over", hit, ok)
  end
  return fs.mount(norm, proxy)
end

function securefs.unmount(path, session)
  if not fs then return false, "securefs not initialized" end
  local ok, err = requireAdmin(session)
  if not ok then
    if log then log.warn("securefs", "UNMOUNT denied: " .. tostring(path) .. " (" .. err .. ")") end
    return false, "Permission denied: " .. err .. "  [E-401 ERR_PERM_DENIED]"
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
  --! #SEC (pentest, Sep 2026) — FIXED ARITY. Every method takes exactly
  --! the arguments its securefs counterpart declares, and the bound session
  --! always lands in the session slot. The old proxy appended the session
  --! AFTER whatever the caller passed, so one extra argument moved into the
  --! session slot: fs.readFile(p, { tier = 3 }) ran with the CALLER's table
  --! as its principal (the bound session landed one past it, unread), and
  --! users.checkAccess trusts any table's .tier. Any sandboxed program with
  --! fs.read could read /etc/users.dat; with fs.write, rewrite it. This
  --! proxy is handed straight to untrusted code, so it must never forward
  --! caller-supplied arguments past the ones it names.
  --! (test_securefs_session_bind.lua)
  local ONE_ARG = {
    "exists", "isDirectory", "list", "readFile", "makeDirectory", "remove",
    "size", "lastModified", "resolve",
  }
  for _, name in ipairs(ONE_ARG) do
    local fn = securefs[name]
    proxy[name] = function(a) return fn(a, session) end
  end
  local TWO_ARGS = { "writeFile", "appendFile", "open", "rename", "copy" }
  for _, name in ipairs(TWO_ARGS) do
    local fn = securefs[name]
    proxy[name] = function(a, b) return fn(a, b, session) end
  end
  proxy.home = function() return securefs.home(session) end
  -- Pass-throughs (no session)
  proxy.normalize   = securefs.normalize
  proxy.split       = securefs.split
  proxy.join        = securefs.join
  proxy.spaceTotal  = securefs.spaceTotal
  proxy.spaceUsed   = securefs.spaceUsed
  proxy.spaceFree   = securefs.spaceFree
  proxy.mounts      = securefs.mounts
  return proxy
end

-- Test hook (not part of the public API): the protected-target guard,
-- exposed so the node-vs-subtree behavior can be unit-tested off-box.
securefs._isProtectedTarget = function(p, s) return _isProtectedTarget(p, s) end
-- Same, for the refusal TEXT. `why` recognises this message by substring
-- to explain it, and a substring match against a message defined in
-- another file is a seam that rots silently. test_why_failure.lua builds
-- the real message from here and asserts the explainer still knows it.
securefs._protectedMsg = function(v, h, s) return protectedMsg(v, h, s) end

return securefs
