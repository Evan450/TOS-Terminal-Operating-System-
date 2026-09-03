-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Helpers                          ║
-- ║  Path, file, text, and permission utility functions  ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local M = {}

-- ── Path / file helpers ─────────────────────────────

function M.resolvePath(S, p)
  if not p or p == "" then return S.cwd end
  if p:sub(1, 1) == "/" then return p end
  if p == "~" or p:sub(1, 2) == "~/" then
    local home = "/home/" .. S.who
    return home .. p:sub(2)
  end
  return S.F.join(S.cwd, p)
end

function M.loadFiles(S, b)
  b.files = {}
  if b.path ~= "/" then
    b.files[1] = { name = "..", dir = true, sz = 0 }
  end
  local ok, list = pcall(S.F.list, b.path)
  if not ok or not list then return end
  local raw = {}
  if type(list) == "table" then
    for _, n in ipairs(list) do raw[#raw + 1] = n end
  elseif type(list) == "function" then
    for n in list do raw[#raw + 1] = n end
  end
  table.sort(raw, function(a, b2)
    local ad, bd = a:sub(-1) == "/", b2:sub(-1) == "/"
    if ad ~= bd then return ad end
    return a < b2
  end)
  for _, n in ipairs(raw) do
    local isDir = n:sub(-1) == "/"
    local name  = isDir and n:sub(1, -2) or n
    local sz    = 0
    if not isDir then
      pcall(function() sz = S.F.size(S.F.join(b.path, name)) end)
    end
    b.files[#b.files + 1] = { name = name, dir = isDir, sz = sz }
  end
  if b.sel > #b.files then b.sel = math.max(1, #b.files) end
  -- Free space on THIS path's mount, cached here so the summary rail
  -- (draw.sumRail) repaints without touching the filesystem per frame.
  b.freeStr = nil
  pcall(function()
    local best, bestLen = nil, -1
    for _, m in ipairs(S.F.mounts() or {}) do
      local mp = m.mountPoint or ""
      if mp ~= "" and b.path:sub(1, #mp) == mp and #mp > bestLen then
        best, bestLen = m, #mp
      end
    end
    if best and best.total then
      b.freeStr = M.fmtSz(math.max(0, (best.total or 0) - (best.used or 0)))
    end
  end)
end

function M.refreshBrowser(S)
  M.loadFiles(S, S.browser)
end

function M.fileColor(S, f)
  local T = S.T
  if f.dir then return T.dir or T.dir_color or T.highlight end
  if f.name:match("%.lua$") then return T.file_lua or T.file_exec or T.highlight end
  if f.name:match("%.cfg$") or f.name:match("%.conf$") then return T.file_cfg or T.warning end
  if f.name:match("%.log$") then return T.file_log or T.dim end
  return T.fg
end

function M.fmtSz(sz)
  if sz >= 1048576 then return string.format("%.1fM", sz / 1048576) end
  if sz >= 1024    then return string.format("%dK", math.floor(sz / 1024)) end
  return sz .. "B"
end

function M.selPath(S)
  if S.browser.sel < 1 or S.browser.sel > #S.browser.files then return nil, nil end
  local f = S.browser.files[S.browser.sel]
  if f.name == ".." then return nil, nil end
  return S.F.join(S.browser.path, f.name), f
end

-- ── Removable-disk classification ──────────────────
-- Identify what an inserted/mounted disk IS so the shell can guide the
-- operator to the right next step (the "auto-detect & guide on insert"
-- feature). Pure F (kernel filesystem) reads, no side effects. Shared by
-- the component_added handler (one-line hint) and the `disk` command
-- (full detail) so the two never describe the same disk differently.
-- Returns { kind, desc, hint } where:
--   kind: "tos-install" | "optional-utilities" | "package-repo"
--       | "package" | "module" | "data"
--   desc: short human label
--   hint: the single most useful next action, or nil
-- Detection order is significant: a TOS install disk also carries a
-- root install.lua, so the whole-OS check must precede the picker check.
function M.classifyDisk(F, mnt)
  if not F or not mnt or mnt == "" then return { kind = "data", desc = "disk" } end
  local function exists(p)
    local ok, r = pcall(F.exists, p)
    return ok and r or false
  end
  local function has(rel) return exists(F.join(mnt, rel)) end
  local function listNames(dir)
    local names = {}
    local ok, list = pcall(F.list, dir)
    if ok and list then
      if type(list) == "table" then for _, n in ipairs(list) do names[#names + 1] = n end
      elseif type(list) == "function" then for n in list do names[#names + 1] = n end end
    end
    return names
  end
  -- Does `dir` directly contain at least one <name>/package.lua? Defence-in-
  -- depth: a list entry is one path component, but skip separators/dot-
  -- segments so the existence probe can't be steered outside the mount.
  local function hasPackageDir(dir)
    for _, n in ipairs(listNames(dir)) do
      local clean = n:gsub("/$", "")
      if clean ~= "" and clean ~= "." and clean ~= ".."
         and not clean:find("[/\\]")
         and exists(F.join(F.join(dir, clean), "package.lua")) then
        return true
      end
    end
    return false
  end

  -- Whole-OS install image (deploy output): the TOS kernel + installer.
  if has("tos/kernel/init.lua") then
    return { kind = "tos-install", desc = "TOS install disk",
      hint = "(install image — run its install.lua on the target machine)" }
  end

  -- Repo layout: one subdirectory per package, each holding a package.lua —
  -- AT the disk root...
  if hasPackageDir(mnt) then
    -- An Optional Utilities disk is now identified by its SET MANIFEST, not
    -- by carrying a copy of the installer. That is both more accurate (the
    -- manifest is what makes it a set rather than a loose pile of packages)
    -- and necessary — the picker moved into the base image, so the disks
    -- stopped shipping install.lua at all.
    if has("optutil-set.lua") then
      return { kind = "optional-utilities", desc = "Optional Utilities disk",
        hint = "pkg install" }
    end
    return { kind = "package-repo", desc = "package repo disk", hint = "pkg install" }
  end
  -- ...or ONE LEVEL DOWN. This covers a disk where the whole
  -- dist/optional-utilities FOLDER was copied on (so the packages sit under
  -- /mnt/<disk>/optional-utilities/) instead of its contents — a very easy
  -- mistake that otherwise reads as a blank "data" disk.
  for _, n in ipairs(listNames(mnt)) do
    local clean = n:gsub("/$", "")
    if clean ~= "" and clean ~= "." and clean ~= ".." and not clean:find("[/\\]") then
      local sub = F.join(mnt, clean)
      if hasPackageDir(sub) then
        if exists(F.join(sub, "optutil-set.lua")) then
          -- Nested layout, same rule as above.
          return { kind = "optional-utilities", desc = "Optional Utilities disk",
            hint = "pkg install" }
        end
        return { kind = "package-repo", desc = "package repo disk", hint = "pkg install" }
      end
    end
  end

  -- Single-package disk: a bare manifest at the root.
  if has("package.lua") then
    return { kind = "package", desc = "single-package disk",
      hint = "disk install " .. mnt }
  end
  -- Legacy module disk (pre-pkg module.cfg format).
  if has("module.cfg") then
    return { kind = "module", desc = "module disk (legacy)",
      hint = "disk install " .. mnt }
  end
  return { kind = "data", desc = "data / blank disk" }
end

-- Scan mounted removable media for the first ACTIONABLE disk (anything
-- classifyDisk recognizes as non-"data" — an install image, package repo,
-- Optional Utilities disk, single package, or legacy module). The hot-plug
-- auto-detect only fires on INSERT, so a disk already in the drive at boot
-- would otherwise never be announced; the shell calls this once at startup
-- to surface it. Returns the classification table (with .mountPoint/.label
-- added) or nil when there's nothing worth surfacing.
function M.scanMountedMedia(F)
  if not F or not F.mounts then return nil end
  local ok, mnts = pcall(F.mounts)
  if not ok or type(mnts) ~= "table" then return nil end
  for _, m in ipairs(mnts) do
    if m.mountPoint and m.mountPoint ~= "/" then
      local info = M.classifyDisk(F, m.mountPoint)
      if info and info.kind ~= "data" then
        info.mountPoint = m.mountPoint
        info.label = m.label
        return info
      end
    end
  end
  return nil
end

-- Decide the LIGHTEST surface for a command's `n` wrapped output lines, so a
-- few lines of result don't open a whole tab the operator has to close:
--   "none"   nothing to show
--   "status" one line on the status row (OUT_ROW)
--   "inline" a transient multi-line region just above the prompt
--   "tab"    a real scrollable view tab (only for genuinely long output)
function M.routeOutput(n, maxInline)
  n = tonumber(n) or 0
  if n <= 0 then return "none" end
  if n == 1 then return "status" end
  if n <= (maxInline or 8) then return "inline" end
  return "tab"
end

-- Tab-completion core. Given a `prefix` and `candidates`, return the longest
-- string all matching candidates share (≥ prefix), plus the list of matches.
-- One match → the full candidate; several → the common prefix (extends the
-- input as far as is unambiguous); none → the prefix unchanged. Pure.
function M.completeToken(prefix, candidates)
  prefix = prefix or ""
  local matches = {}
  for _, c in ipairs(candidates or {}) do
    if c:sub(1, #prefix) == prefix then matches[#matches + 1] = c end
  end
  if #matches == 0 then return prefix, matches end
  if #matches == 1 then return matches[1], matches end
  local cp = matches[1]
  for i = 2, #matches do
    local m, n = matches[i], 0
    while n < #cp and n < #m and cp:sub(n + 1, n + 1) == m:sub(n + 1, n + 1) do n = n + 1 end
    cp = cp:sub(1, n)
  end
  return cp, matches
end

-- Complete the LAST token of a shell `cmdline`. The first word completes
-- against `cmds` (command names); a later word is a path, completed against
-- `listDir(dirPart)` -> array of { name=, dir=bool } (the caller resolves the
-- directory). Returns the new cmdline + the match list (for showing on
-- ambiguity). A lone command match gets a trailing space; a lone directory
-- match gets a trailing "/". Pure given `listDir`.
function M.completeCmdline(cmdline, cmds, listDir)
  local before, token = (cmdline or ""):match("^(.-)(%S*)$")
  if not before:find("%S") then            -- still on the first word: a command
    local comp, matches = M.completeToken(token, cmds or {})
    if #matches == 1 then comp = comp .. " " end
    return before .. comp, matches
  end
  local dirPart, base = token:match("^(.*/)([^/]*)$")
  dirPart, base = dirPart or "", base or token
  local entries = (listDir and listDir(dirPart)) or {}
  local names = {}
  for _, e in ipairs(entries) do names[#names + 1] = (type(e) == "table" and e.name or e) end
  local comp, matches = M.completeToken(base, names)
  if #matches == 1 then
    for _, e in ipairs(entries) do
      local nm = type(e) == "table" and e.name or e
      if nm == comp then comp = comp .. ((type(e) == "table" and e.dir) and "/" or " "); break end
    end
  end
  return before .. dirPart .. comp, matches
end

-- Horizontal scroll for the command line: given the string length, the 1-based
-- cursor index (1 .. len+1, where len+1 means "after the last char") and the
-- number of columns `avail` available for text, return the count of leading
-- chars to hide so the cursor cell stays visible. Pure; unit-tested. Keeps the
-- cursor at the right edge once you type past the visible width, and slides back
-- left when you move the cursor toward the start.
function M.cmdScroll(len, cursor, avail)
  if avail < 1 then avail = 1 end
  local cur0 = (cursor or (len + 1)) - 1      -- 0-based column of the cursor
  if cur0 < 0 then cur0 = 0 elseif cur0 > len then cur0 = len end
  local hs = 0
  if cur0 > avail - 1 then hs = cur0 - (avail - 1) end
  if hs < 0 then hs = 0 end
  return hs
end

-- ── Text helpers ──────────────────────────────────

function M.wrapLine(text, width)
  if #text <= width then return { text } end
  local lines = {}
  while #text > width do
    local cut = width
    local foundSpace = false
    for i = width, math.max(1, width - 20), -1 do
      if text:sub(i, i) == " " then cut = i - 1; foundSpace = true; break end
    end
    lines[#lines + 1] = text:sub(1, cut)
    text = text:sub(cut + (foundSpace and 2 or 1))
  end
  if #text > 0 then lines[#lines + 1] = text end
  return lines
end

function M.expandBuf(S, rawBuf)
  local out = {}
  -- #REV — wrap to the VIEWER's content width, not the full screen width.
  -- A view tab draws a line-number gutter on T2+ (viewW = W - gutterW) and
  -- then truncates each line to viewW. expandBuf used to wrap to the full
  -- S.W, so the rightmost gutter-width characters were clipped at draw
  -- time — the "'or' becomes 'o', 'r' off-screen" bug. Reserve a fixed 6
  -- columns on T2+ (enough for the gutter of any output up to 99,999
  -- lines) so a wrapped line always fits inside viewW without re-clipping.
  local reserve = (S.tier and S.tier >= 2) and 6 or 0
  local wrapW = math.max(8, S.W - reserve)
  for _, e in ipairs(rawBuf) do
    local txt = type(e) == "table" and e[1] or tostring(e)
    local col = type(e) == "table" and e[2] or S.T.fg
    for _, l in ipairs(M.wrapLine(txt, wrapW)) do
      out[#out + 1] = { l, col }
    end
  end
  return out
end

-- Pre-built printf format strings for the line-number gutter, keyed by
-- gutter width. Building "%Nd " from scratch on every visible line on
-- every redraw burns string concatenations; the gutter width changes
-- rarely (only when a file crosses a power of 10), so the cache holds
-- ~3 entries in practice.
local lineNumFmtCache = {}

function M.formatLineNum(n, gutterW)
  local fmt = lineNumFmtCache[gutterW]
  if not fmt then
    fmt = "%" .. (gutterW - 1) .. "d "
    lineNumFmtCache[gutterW] = fmt
  end
  return string.format(fmt, n)
end

-- Safe pad: avoids string.format width limit of 99
function M.padR(s, w)
  s = tostring(s)
  if #s >= w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

function M.padL(s, w)
  s = tostring(s)
  if #s >= w then return s:sub(1, w) end
  return string.rep(" ", w - #s) .. s
end

-- ── Permission helpers ────────────────────────────
-- TIER constants: GUEST=0, USER=1, ADMIN=2, ROOT=3

-- #SEC M-7 — resolve the LIVE tier from the seat's session rather than the
-- cached S.userTier snapshot taken at panel construction. Without this, an
-- admin demoted (or whose session expired) mid-session keeps elevated
-- command access until they re-login. Fail closed: if a seat token exists
-- but no live session resolves (expired/revoked), drop to GUEST(0). Only
-- fall back to the cached value for token-less contexts (e.g. kernel REPL).
function M.liveTier(S)
  if S and S.U and S.st then
    -- Resolve ONLY the seat token's session — do NOT fall back to the
    -- module-global currentSession() here. If this seat's token has
    -- expired/been revoked, the seat is no longer authenticated and must
    -- drop to GUEST, regardless of what some other seat's global session
    -- says.
    if S.U.getSession then
      local s = S.U.getSession(S.st)
      if s and type(s.tier) == "number" then return s.tier end
    end
    return 0
  end
  return (S and S.userTier) or 0
end

function M.rootOnly(S, o)
  if M.liveTier(S) < 3 then
    -- Record the denial so `why` (no args) can explain it after the fact.
    S.lastDenial = { cmd = S.curCmd, need = 3, have = M.liveTier(S) }
    local msg = "Permission denied: root only"
    if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
    return false
  end
  return true
end

function M.adminOnly(S, o)
  if M.liveTier(S) < 2 then
    S.lastDenial = { cmd = S.curCmd, need = 2, have = M.liveTier(S) }
    local msg = "Permission denied: admin access required"
    if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
    return false
  end
  return true
end

-- Pure: the human name of a tier number (0..3). Used by `why`.
function M.tierName(n)
  n = tonumber(n) or 0
  return ({ [0] = "GUEST", [1] = "USER", [2] = "ADMIN", [3] = "ROOT" })[n]
    or ("tier " .. n)
end

-- Pure: explain whether a command `cmd` (needing tier `need`) is runnable at the
-- caller's tier `have`. `known` = is it a real command. Returns an array of
-- { text=, tone= } where tone ∈ title/ok/err/fix/dim — the caller maps tone to a
-- theme colour. Unit-tested off-box (test_why.lua); the `why` command renders it.
function M.whyExplain(cmd, need, have, known)
  local out = {}
  local function add(t, tone) out[#out + 1] = { text = t, tone = tone } end
  cmd = cmd or "?"
  if not known then
    add("Unknown command: " .. cmd, "err")
    add("It isn't a built-in. If it came from a package, check `pkg list`;", "dim")
    add("otherwise check the spelling — Tab completes command names.", "dim")
    return out
  end
  need = tonumber(need) or 0
  have = tonumber(have) or 0
  add(cmd .. " — needs " .. M.tierName(need) .. "; you are " .. M.tierName(have) .. ".", "title")
  if have >= need then
    add("You have the access to run this.", "ok")
    add("If it still failed, the cause is something else (a missing", "dim")
    add("resource, file, or capability) — check `doctor` and `log`.", "dim")
  elseif need >= 3 then
    add("This is ROOT-only.", "err")
    add("Fix: log in on the root account to run it (`logout`, then", "fix")
    add("sign in as root).", "fix")
  else
    add("This needs administrator access.", "err")
    add("Fix: have an admin run it, or sign in on an admin account", "fix")
    add("(`logout`, then log in as an admin). An admin can also grant", "fix")
    add("your account admin rights.", "fix")
  end
  return out
end

--! The ONE way to log a seat out.
--!
--! There were five: the `logout` command, the System menu, the F10 power
--! menu, the ^Q prompt and the Desktop. Only the command dropped an active
--! `sudo -s` elevation first -- and its own comment calls that an invariant
--! ("never carry elevation across logout"). The other four pushed the signal
--! straight out, so the elevated SESSION the sudo path registered was never
--! logged out: the kernel's handler retires sessionTokens[seat], which is the
--! ORIGINAL login token, a different object entirely.
--!
--! What that costs TODAY is small, and worth stating precisely rather than
--! dressing up: the elevated token is discarded with the shell state, so
--! nobody can present it; there is no session cap to exhaust; and nothing
--! enumerates sessions to an operator. It lingers as a phantom entry until
--! sweepSessions retires it, within SESSION_TIMEOUT.
--!
--! It is fixed anyway, and centrally, for two reasons. sudoDrop does not only
--! retire the token -- it also restores the shell process's principal, and
--! that only stays harmless while every logout path also KILLS the process.
--! The kernel's handler does today; a future "switch user" or a CLI handoff
--! that reuses the process would not, and then the elevation rides across.
--! And five copies of a security rule is four chances to update it in the
--! wrong number of places. (test_logout_elevation.lua)
function M.logout(S)
  if S and S._sudo and S.sudoDrop then pcall(S.sudoDrop) end
  if S and S.E and S.E.push then S.E.push("tos_logout", S.displayIdx) end
end

-- #REV (#9) — power-off policy. Reboot/shutdown halt the WHOLE machine,
-- killing every seat's session, so a non-admin may only do it when they are
-- the SOLE active operator. ADMIN+ may always power off. Returns (ok,
-- reason). Logout is per-seat and not gated by this.
function M.canPowerOff(S)
  if M.liveTier(S) >= 2 then return true end  -- admin/root always may
  -- Count seats with a live shell (active operators).
  local n = 0
  local pids = _G._TOS and _G._TOS.shellPIDs
  if type(pids) == "table" then
    for _, pid in pairs(pids) do if pid then n = n + 1 end end
  end
  if n <= 1 then return true end  -- sole operator — fine
  return false, n .. " operators are logged in. Ask an admin to power off, "
    .. "or wait for the others to log out."
end

-- #SEC CR-9 — resolve the principal BOUND TO THIS SEAT. The panel state
-- carries the seat's login token (S.st); resolve it to the live session
-- TABLE. We must NOT rely on users.currentSession() for ACL decisions:
-- logins use setCurrent=false, so the module-global is nil (single-seat)
-- or another seat's session (multi-seat) — either way the wrong principal.
-- Falls back to currentSession() only when no seat token is present
-- (e.g. the kernel REPL). Always returns a session table or nil — never a
-- raw token (passing a token where a session is expected silently fails
-- every tier check).
function M.sessionOf(S)
  if S and S.U then
    if S.st and S.U.getSession then
      local s = S.U.getSession(S.st)
      if s then return s end
    end
    if S.U.currentSession then
      local s = S.U.currentSession()
      if s then return s end
    end
  end
  return nil
end

function M.canAccess(S, path, mode, o)
  if S.U then
    -- #SEC C8/CR-9 — check against the seat-bound session, not the global.
    local session = M.sessionOf(S)
    local ok, reason
    if session and S.U.canAccessAs then
      ok, reason = S.U.canAccessAs(session, path, mode)
    elseif S.U.canAccess then
      ok, reason = S.U.canAccess(path, mode)  -- legacy back-compat only
    else
      -- #SEC M-8 — fail CLOSED: the users module is present but exposes no
      -- usable access-check API (or no session resolved). Denying is safer
      -- than granting on a half-initialised auth subsystem.
      ok, reason = false, "access check unavailable"
    end
    if not ok then
      local msg = "Permission denied: " .. (reason or path)
      if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
      return false
    end
    return true
  end
  if mode == "w" then
    for _, sp in ipairs({ "/tos", "/etc", "/var" }) do
      if path == sp or path:sub(1, #sp + 1) == sp .. "/" then
        if S.who ~= "root" then
          local msg = "Permission denied: system path"
          if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
          return false
        end
      end
    end
  end
  return true
end

function M.canWrite(S, path, o) return M.canAccess(S, path, "w", o) end
function M.canRead(S, path, o)  return M.canAccess(S, path, "r", o) end

-- ============================================================
-- External program resolution (shared by the executor and `which`)
-- ============================================================
--! #SEC H9 — an unqualified command name resolves only against a fixed set
--! of system bin directories. PATH is honoured only where its entries are
--! also on the safe list: anything under /mnt, /tmp, /public, /home or
--! /root is REJECTED, so an attacker setting PATH=/mnt/floppy:/bin and
--! running `ls` cannot silently shadow the system binary.
--
-- This lived inline in executor.lua until `which` needed the same answer.
-- Two copies of a security rule is one copy too many — the whole point of
-- `which` is to report what the executor WILL run, and it can only do that
-- honestly by asking the same code.
M.SYSTEM_BIN_DIRS  = { "/bin", "/usr/bin", "/tos/shell" }
M.UNSAFE_PREFIXES  = { "/mnt/", "/tmp/", "/public/", "/home/", "/root/" }

--! #SEC — BUG FOUND WHEN THIS MOVED OUT OF executor.lua (2026-08-04).
--! The prefix list is written with trailing slashes, and the old check
--! compared the PATH entry against them raw. A PATH entry of exactly
--! "/tmp" (or "/mnt", "/home", "/root", "/public") therefore matched
--! NOTHING and was treated as safe — `PATH=/tmp` plus a planted
--! /tmp/<name>.lua would run for any name that isn't a built-in and
--! isn't in a system bin dir. Subdirectories ("/tmp/x") were caught
--! correctly all along, which is why it survived: the shape people
--! actually write in a PATH is the bare root.
--! Normalizing to a trailing slash before comparing closes it.
function M.dirIsSafe(dir)
  local d = tostring(dir or "")
  if d == "" then return false end
  if d:sub(-1) ~= "/" then d = d .. "/" end
  for _, p in ipairs(M.UNSAFE_PREFIXES) do
    if d:sub(1, #p) == p then return false end
  end
  return true
end

-- ============================================================
-- Command aliases (per-user, stored in ~/.profile.cfg)
-- ============================================================
-- Loaded LAZILY on first dispatch and cached on S, rather than at login:
-- the boot path is the most-tested code in the shell and an alias table is
-- not worth a new step in it. `alias`/`unalias` call M.invalidateAliases so
-- an edit takes effect on the next command, not the next login.
--
--! An alias carries NO privilege. It is expanded before dispatch, so the
--! expansion meets exactly the same tier gates as if it had been typed —
--! aliasing a name to an admin command does not make it runnable. The
--! table is read from the caller's OWN profile through securefs, so one
--! user cannot plant an alias in another user's shell.
function M.aliases(S)
  if S._aliases then return S._aliases end
  local out = {}
  local pmod = _G._TOS and _G._TOS.profile
  if pmod and pmod.load then
    local ok, p = pcall(pmod.load, M.sessionOf(S))
    if ok and type(p) == "table" and type(p.aliases) == "table" then
      for k, v in pairs(p.aliases) do
        if type(k) == "string" and type(v) == "string" then out[k:lower()] = v end
      end
    end
  end
  S._aliases = out
  return out
end

function M.invalidateAliases(S) S._aliases = nil end

--- Expand a leading alias in an already-tokenized command.
--- Returns the (possibly rewritten) parts array.
--
-- Expansion is repeated so `alias ll='ls -l'` + `alias l=ll` works, but a
-- name is only ever expanded ONCE per chain: `alias ls='ls -a'` must run
-- the real `ls`, not recurse until the stack gives out. That self-reference
-- is the single most common alias people write, so it has to be the case
-- that works rather than the case that hangs the seat.
local ALIAS_MAX_DEPTH = 8
function M.expandAlias(S, parts)
  if type(parts) ~= "table" or #parts == 0 then return parts end
  local table_ = M.aliases(S)
  if next(table_) == nil then return parts end
  local seen = {}
  for _ = 1, ALIAS_MAX_DEPTH do
    local head = tostring(parts[1] or ""):lower()
    local expansion = table_[head]
    if not expansion or seen[head] then break end
    seen[head] = true
    local repl = M.tokenizeSimple(expansion)
    if #repl == 0 then break end
    local rest = {}
    for i = 2, #parts do rest[#rest + 1] = parts[i] end
    for _, a in ipairs(rest) do repl[#repl + 1] = a end
    parts = repl
  end
  return parts
end

--- Whitespace tokenizer for alias expansions (quotes are already resolved
--- by the executor's tokenizer when the alias was DEFINED, so the stored
--- string is plain). Deliberately not the executor's full quote-aware
--- tokenizer: re-parsing quotes here would let a stored alias smuggle
--- quoting through a second round of interpretation.
function M.tokenizeSimple(s)
  local t = {}
  for word in tostring(s):gmatch("%S+") do t[#t + 1] = word end
  return t
end

--- Resolve `name` to an executable file path, or nil.
--- Returns (path, source) where source is "system" (a trusted bin dir) or
--- "path" (an allowed PATH entry) — `which` reports the difference because
--- "it came from your PATH" is the interesting half of the answer.
function M.resolveProgram(F, name)
  if type(name) ~= "string" or name == "" then return nil end
  local function probe(dir)
    local full = F.join(dir, name .. ".lua")
    if F.exists(full) then return full end
    full = F.join(dir, name)
    if F.exists(full) then return full end
    return nil
  end
  for _, dir in ipairs(M.SYSTEM_BIN_DIRS) do
    local hit = probe(dir)
    if hit then return hit, "system" end
  end
  local ok, envMod = pcall(require, "kernel.env")
  if ok then
    local pathStr = envMod.read(nil, "PATH") or "/usr/bin:/bin"
    for dir in pathStr:gmatch("[^:]+") do
      if M.dirIsSafe(dir) then
        local hit = probe(dir)
        if hit then return hit, "path" end
      end
    end
  end
  return nil
end

return M
