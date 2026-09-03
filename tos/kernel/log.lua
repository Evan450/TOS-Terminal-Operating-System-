-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Logger Module          ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")

local log = {}
local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4 }
local LEVEL_NAMES = { [0]="DBG", [1]="INF", [2]="WRN", [3]="ERR", [4]="FTL" }
local LEVEL_COLORS = {
  [0] = 0x666666,  -- DEBUG: gray
  [1] = 0xAAAAAA,  -- INFO: light gray
  [2] = 0xFFFF00,  -- WARN: yellow
  [3] = 0xFF6600,  -- ERROR: orange
  [4] = 0xFF0000,  -- FATAL: red
}

-- Ring buffer to save memory (keeps last N entries)
local MAX_ENTRIES = 64
local entries = {}
local entryCount = 0
local minLevel = LOG_LEVELS.INFO  -- Default: don't store DEBUG

-- #SEC M16 — track entries overwritten by the ring buffer. A flood of
-- log activity used to silently lose the early entries; that masked
-- attacker reconnaissance under a wave of subsequent noise. We emit a
-- single "[N entries lost since last read]" marker the next time
-- log.recent() is called, then reset the counter.
local lostSinceRead = 0

-- Boot context (set during kernel init)
local _earlyPrint = nil
local _verbose = false
-- Minimum level that ECHOES to the boot screen. This is the verbosity
-- "muter" (boot-reorg #3): silent boots raise it so per-stage INFO chatter
-- is suppressed (warnings/errors still show); verbose boots lower it to
-- DEBUG. Defaults to INFO = today's behavior. Storage (the ring buffer)
-- is unaffected — only what's drawn during boot changes.
local _earlyMinLevel = LOG_LEVELS.INFO
-- Splash-mode boot progress hook. When set (only on a "splash" boot — see
-- root init.lua), each per-stage INFO message that the muter would otherwise
-- swallow instead nudges a loading bar, so a quiet boot still shows motion.
local _bootProgress = nil

function log.init(opts)
  opts = opts or {}
  _earlyPrint = opts.earlyPrint
  _bootProgress = opts.bootProgress
  _verbose = opts.verbose or false
  if type(opts.earlyMinLevel) == "number" then _earlyMinLevel = opts.earlyMinLevel end
  -- Storage floor must track the verbosity. The echo gate (writeEntry) runs
  -- AFTER the storage gate, so a "verbose" boot that wants DEBUG echoed must
  -- also STORE debug — otherwise debug entries are dropped before they can
  -- echo and verbose silently degrades to text-with-timestamps. A DEBUG echo
  -- threshold (earlyMinLevel 0) OR an explicit verbose flag lowers it; any
  -- other mode keeps the normal INFO floor.
  if _verbose or _earlyMinLevel <= LOG_LEVELS.DEBUG then
    minLevel = LOG_LEVELS.DEBUG
  else
    minLevel = LOG_LEVELS.INFO
  end
  -- On very low memory, reduce buffer
  if computer.totalMemory() < 131072 then  -- <128KB
    MAX_ENTRIES = 16
  elseif computer.totalMemory() < 262144 then  -- <256KB
    MAX_ENTRIES = 32
  end
end

function log.setLevel(level)
  if type(level) == "string" then
    level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
  end
  minLevel = level
end

-- ============================================================
-- CORE 2 — Role/permission-aware logging
-- ============================================================
-- Per-source minimum level (overrides the global minLevel for that
-- source label). Lets operators raise verbosity on "auth" while
-- keeping "net" quiet, or vice versa. Setter requires ADMIN+ tier.
local sourceMinLevel = {}

--- Set the minimum level for a single source label. Pass nil to clear.
function log.setSourceLevel(source, level)
  local okU, usersmod = pcall(require, "kernel.users")
  if okU and usersmod and usersmod.currentSession then
    local sess = usersmod.currentSession()
    if sess and not sess.isKernel
       and (sess.tier or 0) < (usersmod.TIER and usersmod.TIER.ADMIN or 2) then
      return false, "admin required to change source-level filtering"
    end
  end
  if level == nil then
    sourceMinLevel[source] = nil
    return true
  end
  if type(level) == "string" then
    level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
  end
  sourceMinLevel[source] = level
  return true
end

-- Source-label visibility rules. By default ALL sources are visible
-- to ADMIN+, "auth"/"users"/"repl"/"crypto"/"trust" are restricted to
-- ADMIN+ even for explicit reads, and other categories are visible to
-- USER+ (they can see the same info they'd see in their own shell).
-- GUEST sees no log at all.
local ADMIN_ONLY_SOURCES = {
  auth = true, users = true, repl = true, crypto = true,
  trust = true, securefs = true,
}
local function canViewSource(sess, source)
  if not sess then return false end
  local tier = sess.tier or 0
  local TIER_ROOT  = 3
  local TIER_ADMIN = 2
  local TIER_USER  = 1
  if tier >= TIER_ROOT then return true end
  if tier >= TIER_ADMIN then return true end
  if tier < TIER_USER then return false end
  -- USER tier
  if ADMIN_ONLY_SOURCES[source] then return false end
  return true
end

-- #SEC M15 — sanitize newlines + control characters in log messages.
-- Without this an attacker who can influence a log line (peer hostname,
-- chat message, filename) can fabricate a fake log entry by embedding
-- "\n[INFO][auth] root logged in", which is indistinguishable from a
-- real entry when grepping /var/log. Source labels get the same scrub.
local function sanitizeForLog(s)
  s = tostring(s)
  -- Replace CR/LF and other control chars (0x00-0x1F, 0x7F) with a
  -- visible escape. Tab is allowed (0x09) since legitimate log lines
  -- sometimes embed tab-indented context.
  return (s:gsub("[%c]", function(ch)
    local b = string.byte(ch)
    if b == 9 then return ch end
    return string.format("\\x%02x", b)
  end))
end

local function writeEntry(level, source, msg)
  -- #SEC CORE2 — per-source level override takes precedence over the
  -- global minLevel. An operator can crank "net" up to DEBUG without
  -- drowning in unrelated chatter, or hush a chatty source without
  -- losing the rest.
  local effectiveMin = sourceMinLevel[source] or minLevel
  if level < effectiveMin then return end

  local entry = {
    time   = computer.uptime(),
    level  = level,
    source = sanitizeForLog(source or "kernel"),
    msg    = sanitizeForLog(msg),
  }

  entryCount = entryCount + 1
  local idx = ((entryCount - 1) % MAX_ENTRIES) + 1
  -- #SEC M16 — count the entry we're overwriting (if any) as lost.
  if entries[idx] then lostSinceRead = lostSinceRead + 1 end
  entries[idx] = entry

  -- During boot, echo to screen (gated by the verbosity muter, #3).
  --
  -- ...unless the splash loading bar is up. Those are two INCOMPATIBLE screen
  -- owners: _earlyPrint is a free-scrolling cursor printer that clears whole
  -- lines and, once it runs past the last row, gpu.copy-scrolls the WHOLE
  -- screen — while the bar and its narration paint at FIXED rows. Sending a
  -- message to both drew it twice and, after enough lines, dragged the
  -- wordmark and bar out from under themselves: the operator saw a second
  -- ghost bar with repair/Safe-Mode text overlapping the narration column.
  -- A splash boot logs plenty of WARNs (Safe Mode alone emits one per
  -- disabled subsystem, self-repair a couple more), so this was reliably
  -- reproducible rather than an edge case.
  --
  -- Nothing is hidden by this: _bootProgress renders WARN/ERROR verbatim and
  -- coloured (see the level >= 2 branch in init.lua's bar), so warnings still
  -- reach the operator — in the one place that owns the screen.
  if _earlyPrint and not _bootProgress and level >= _earlyMinLevel then
    local prefix = string.format("[%s] ", LEVEL_NAMES[level] or "???")
    _earlyPrint(prefix .. entry.msg, LEVEL_COLORS[level])
  end
  -- Splash mode: drive the loading bar from the boot-stage chatter (the same
  -- INFO messages the muter hides above). The numeric level (INFO=1, WARN=2,
  -- ERROR=3, FATAL=4) lets the bar show warnings/errors verbatim instead of
  -- simplifying them away. Guarded so a bad callback can't break logging.
  if _bootProgress and level >= LOG_LEVELS.INFO then
    pcall(_bootProgress, entry.msg, level)
  end
end

function log.debug(source, msg) writeEntry(LOG_LEVELS.DEBUG, source, msg) end
function log.info(source, msg)  writeEntry(LOG_LEVELS.INFO, source, msg) end
function log.warn(source, msg)  writeEntry(LOG_LEVELS.WARN, source, msg) end
function log.error(source, msg) writeEntry(LOG_LEVELS.ERROR, source, msg) end
function log.fatal(source, msg) writeEntry(LOG_LEVELS.FATAL, source, msg) end

-- Get recent log entries.
-- #CORE2 — accepts an optional session for per-source ACL filtering.
-- Default behaviour (no session passed) is unchanged: returns everything,
-- which the kernel-internal `log` command path already uses since it's
-- already wrapped in tier checks at the shell layer. New callers that
-- want per-user filtering pass the session.
function log.recent(count, session)
  count = math.min(count or 20, MAX_ENTRIES, entryCount)
  local result = {}
  -- #SEC M16 — prepend a synthetic "[N entries lost]" marker if the
  -- ring buffer overwrote anything since the last read. This is the
  -- ONLY place we surface the count, so consumers (log command,
  -- panels log viewer) automatically see it. Reset after reporting.
  if lostSinceRead > 0 then
    result[#result + 1] = {
      time   = computer.uptime(),
      level  = LOG_LEVELS.WARN,
      source = "log",
      msg    = "[" .. lostSinceRead .. " entries lost since last read]",
    }
    lostSinceRead = 0
  end
  local start = entryCount - count + 1
  if start < 1 then start = 1 end
  for i = start, entryCount do
    local idx = ((i - 1) % MAX_ENTRIES) + 1
    if entries[idx] then
      -- #CORE2 — apply per-source ACL when a session was passed.
      if session and not canViewSource(session, entries[idx].source) then
        -- skip
      else
        result[#result + 1] = entries[idx]
      end
    end
  end
  return result
end

--- Returns the list of sources currently filtered (for `log filter` UI).
function log.getSourceLevels()
  local copy = {}
  for k, v in pairs(sourceMinLevel) do copy[k] = v end
  return copy
end

-- Format a log entry as string
function log.format(entry)
  return string.format("[%7.1f][%s][%s] %s",
    entry.time, LEVEL_NAMES[entry.level] or "???",
    entry.source, entry.msg)
end

-- Stop echoing to early boot display
function log.detachEarlyPrint()
  _earlyPrint = nil
  -- Also stop the splash boot-progress hook. It draws the loading bar +
  -- narration at FIXED screen rows; once the shell/login owns the screen, any
  -- later INFO log (login status, "Starting networking", shutdown messages)
  -- would otherwise REDRAW that splash chrome on top of the live UI — which is
  -- exactly the "splash reappears at login/shutdown" bug. Both hooks are torn
  -- down at the same boot→shell handoff.
  _bootProgress = nil
end

-- ============================================================
-- Persistent log file (/var/log/kernel.log)
-- ============================================================
-- Three responsibilities:
--   1. log.attachFile registers the kernel fs + path + rotation policy.
--   2. log.flush appends entries that arrived since the previous flush
--      (no double-writing, no missing entries up to MAX_ENTRIES).
--   3. log.fatal flushes synchronously so a crash captures its own
--      cause before the box reboots.
--
-- Rotation: when the active file would exceed `rotateBytes`, it's
-- renamed to <path>.1 (overwriting any existing .1) and a fresh file
-- is started. Two generations is plenty for OC's tight disks; any
-- more retention belongs in an off-machine sink.

local _logFs        = nil   -- kernel.fs reference, set by attachFile
local _logPath      = nil   -- e.g. "/var/log/kernel.log"
local _rotateBytes  = 16384 -- default: rotate at 16 KB
local _flushedCount = 0     -- entryCount at most-recent successful flush

--- Attach a destination file + fs proxy for periodic flushing.
-- @param fs        kernel.fs (or anything with appendFile/exists/size/rename/writeFile)
-- @param path      absolute path on the OC filesystem
-- @param opts      optional: { rotateBytes = N }
function log.attachFile(fs, path, opts)
  _logFs       = fs
  _logPath     = path
  if opts and tonumber(opts.rotateBytes) then
    _rotateBytes = tonumber(opts.rotateBytes)
  end
  -- Reset the flush cursor — anything currently in the buffer will be
  -- flushed on the next call, capturing whatever the boot path logged
  -- before the file was attached.
  _flushedCount = 0
end

--- Detach (stop persisting). Used during kernel.shutdown so the final
--- close happens cleanly and a half-rotated file isn't left behind.
function log.detachFile()
  _logFs        = nil
  _logPath      = nil
  _flushedCount = 0
end

-- Internal: rotate <path> -> <path>.1 (overwriting any existing .1) if
-- the active file is over budget. Best-effort; failures are silent
-- because we're in the logger and can't usefully log about them.
local function maybeRotate()
  if not _logFs or not _logPath then return end
  if not _logFs.exists or not _logFs.size or not _logFs.rename then return end
  if not _logFs.exists(_logPath) then return end
  local sz = _logFs.size(_logPath) or 0
  if sz < _rotateBytes then return end
  local rotated = _logPath .. ".1"
  -- Remove existing .1 first; some OC fs proxies refuse rename-over.
  if _logFs.exists(rotated) and _logFs.remove then
    pcall(_logFs.remove, rotated)
  end
  pcall(_logFs.rename, _logPath, rotated)
end

--- Append entries that arrived since the last flush. Safe to call
--- repeatedly — only new entries are written.
function log.flush()
  if not _logFs or not _logPath then return false, "no log file attached" end
  if entryCount <= _flushedCount then return true, "nothing to flush" end

  maybeRotate()

  -- Determine the range of new entries. The ring buffer keeps only the
  -- last MAX_ENTRIES, so if more than that arrived between flushes we
  -- can only flush what's still in memory — clamp to entryCount-MAX+1.
  local first = _flushedCount + 1
  local oldest = entryCount - MAX_ENTRIES + 1
  if first < oldest then first = oldest end

  -- Build the text up-front and write in one append call. fs.appendFile
  -- opens, writes, closes; doing it once per flush is cheaper than
  -- per-entry, especially under heavy logging.
  local parts = {}
  for i = first, entryCount do
    local idx = ((i - 1) % MAX_ENTRIES) + 1
    if entries[idx] then
      parts[#parts + 1] = log.format(entries[idx])
    end
  end
  if #parts == 0 then
    _flushedCount = entryCount
    return true, "no entries in window"
  end
  parts[#parts + 1] = ""  -- trailing newline
  local payload = table.concat(parts, "\n")

  if _logFs.appendFile then
    local ok, err = _logFs.appendFile(_logPath, payload)
    if not ok then return false, err end
  elseif _logFs.open then
    -- #SEC L — append through a low-level handle instead of the
    -- read+concat+write fallback below, which re-reads and rewrites the
    -- ENTIRE file on every flush (O(file) per flush — wasteful even
    -- bounded by rotation, and an OOM risk if rotation ever fails). Works
    -- whether the fs exposes write/close as functions (kernel.fs) or the
    -- handle exposes them as methods (raw OC proxy).
    local h, oerr = _logFs.open(_logPath, "a")
    if not h then return false, oerr or "open(append) failed" end
    local okW
    if _logFs.write then okW = _logFs.write(h, payload)
    elseif h.write then okW = h:write(payload) end
    if _logFs.close then _logFs.close(h)
    elseif h.close then h:close() end
    if okW == false then return false, "append write failed" end
  elseif _logFs.writeFile then
    -- Last-resort: read+concat+write. Slowest; only if neither appendFile
    -- nor open is available on the proxy in question.
    local existing = _logFs.readFile and _logFs.readFile(_logPath) or ""
    local ok, err = _logFs.writeFile(_logPath, (existing or "") .. payload)
    if not ok then return false, err end
  else
    return false, "fs supports neither appendFile, open, nor writeFile"
  end

  _flushedCount = entryCount
  return true
end

-- ============================================================
-- Auto-flush on FATAL
-- ============================================================
-- Override log.fatal to flush synchronously after recording the entry,
-- so a kernel panic captures its own cause to disk before the box
-- reboots. Wraps the original writeEntry path.

local _origFatal = log.fatal
function log.fatal(source, msg)
  _origFatal(source, msg)
  -- Best-effort; if the fs is wedged we can't help further.
  if _logFs and _logPath then pcall(log.flush) end
end

log.LEVELS = LOG_LEVELS
return log
