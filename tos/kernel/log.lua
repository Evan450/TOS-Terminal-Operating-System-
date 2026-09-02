local computer = require("computer")

local log = {}
local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4 }
local LEVEL_NAMES = { [0]="DBG", [1]="INF", [2]="WRN", [3]="ERR", [4]="FTL" }
local LEVEL_COLORS = {
  [0] = 0x666666,
  [1] = 0xAAAAAA,
  [2] = 0xFFFF00,
  [3] = 0xFF6600,
  [4] = 0xFF0000,
}

local MAX_ENTRIES = 64
local entries = {}
local entryCount = 0
local minLevel = LOG_LEVELS.INFO

local lostSinceRead = 0

local _earlyPrint = nil
local _verbose = false

local _earlyMinLevel = LOG_LEVELS.INFO

local _bootProgress = nil

function log.init(opts)
  opts = opts or {}
  _earlyPrint = opts.earlyPrint
  _bootProgress = opts.bootProgress
  _verbose = opts.verbose or false
  if type(opts.earlyMinLevel) == "number" then _earlyMinLevel = opts.earlyMinLevel end

  if _verbose or _earlyMinLevel <= LOG_LEVELS.DEBUG then
    minLevel = LOG_LEVELS.DEBUG
  else
    minLevel = LOG_LEVELS.INFO
  end

  if computer.totalMemory() < 131072 then
    MAX_ENTRIES = 16
  elseif computer.totalMemory() < 262144 then
    MAX_ENTRIES = 32
  end
end

function log.setLevel(level)
  if type(level) == "string" then
    level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
  end
  minLevel = level
end

local sourceMinLevel = {}

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

  if ADMIN_ONLY_SOURCES[source] then return false end
  return true
end

local function sanitizeForLog(s)
  s = tostring(s)

  return (s:gsub("[%c]", function(ch)
    local b = string.byte(ch)
    if b == 9 then return ch end
    return string.format("\\x%02x", b)
  end))
end

local function writeEntry(level, source, msg)

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

  if entries[idx] then lostSinceRead = lostSinceRead + 1 end
  entries[idx] = entry

  if _earlyPrint and not _bootProgress and level >= _earlyMinLevel then
    local prefix = string.format("[%s] ", LEVEL_NAMES[level] or "???")
    _earlyPrint(prefix .. entry.msg, LEVEL_COLORS[level])
  end

  if _bootProgress and level >= LOG_LEVELS.INFO then
    pcall(_bootProgress, entry.msg, level)
  end
end

function log.debug(source, msg) writeEntry(LOG_LEVELS.DEBUG, source, msg) end
function log.info(source, msg)  writeEntry(LOG_LEVELS.INFO, source, msg) end
function log.warn(source, msg)  writeEntry(LOG_LEVELS.WARN, source, msg) end
function log.error(source, msg) writeEntry(LOG_LEVELS.ERROR, source, msg) end
function log.fatal(source, msg) writeEntry(LOG_LEVELS.FATAL, source, msg) end

function log.recent(count, session)
  count = math.min(count or 20, MAX_ENTRIES, entryCount)
  local result = {}

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

      if session and not canViewSource(session, entries[idx].source) then

      else
        result[#result + 1] = entries[idx]
      end
    end
  end
  return result
end

function log.getSourceLevels()
  local copy = {}
  for k, v in pairs(sourceMinLevel) do copy[k] = v end
  return copy
end

function log.format(entry)
  return string.format("[%7.1f][%s][%s] %s",
    entry.time, LEVEL_NAMES[entry.level] or "???",
    entry.source, entry.msg)
end

function log.detachEarlyPrint()
  _earlyPrint = nil

  _bootProgress = nil
end

local _logFs        = nil
local _logPath      = nil
local _rotateBytes  = 16384
local _flushedCount = 0

function log.attachFile(fs, path, opts)
  _logFs       = fs
  _logPath     = path
  if opts and tonumber(opts.rotateBytes) then
    _rotateBytes = tonumber(opts.rotateBytes)
  end

  _flushedCount = 0
end

function log.detachFile()
  _logFs        = nil
  _logPath      = nil
  _flushedCount = 0
end

local function maybeRotate()
  if not _logFs or not _logPath then return end
  if not _logFs.exists or not _logFs.size or not _logFs.rename then return end
  if not _logFs.exists(_logPath) then return end
  local sz = _logFs.size(_logPath) or 0
  if sz < _rotateBytes then return end
  local rotated = _logPath .. ".1"

  if _logFs.exists(rotated) and _logFs.remove then
    pcall(_logFs.remove, rotated)
  end
  pcall(_logFs.rename, _logPath, rotated)
end

function log.flush()
  if not _logFs or not _logPath then return false, "no log file attached" end
  if entryCount <= _flushedCount then return true, "nothing to flush" end

  maybeRotate()

  local first = _flushedCount + 1
  local oldest = entryCount - MAX_ENTRIES + 1
  if first < oldest then first = oldest end

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
  parts[#parts + 1] = ""
  local payload = table.concat(parts, "\n")

  if _logFs.appendFile then
    local ok, err = _logFs.appendFile(_logPath, payload)
    if not ok then return false, err end
  elseif _logFs.open then

    local h, oerr = _logFs.open(_logPath, "a")
    if not h then return false, oerr or "open(append) failed" end
    local okW
    if _logFs.write then okW = _logFs.write(h, payload)
    elseif h.write then okW = h:write(payload) end
    if _logFs.close then _logFs.close(h)
    elseif h.close then h:close() end
    if okW == false then return false, "append write failed" end
  elseif _logFs.writeFile then

    local existing = _logFs.readFile and _logFs.readFile(_logPath) or ""
    local ok, err = _logFs.writeFile(_logPath, (existing or "") .. payload)
    if not ok then return false, err end
  else
    return false, "fs supports neither appendFile, open, nor writeFile"
  end

  _flushedCount = entryCount
  return true
end

local _origFatal = log.fatal
function log.fatal(source, msg)
  _origFatal(source, msg)

  if _logFs and _logPath then pcall(log.flush) end
end

log.LEVELS = LOG_LEVELS
return log
