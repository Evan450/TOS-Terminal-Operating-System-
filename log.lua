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

-- Boot context (set during kernel init)
local _earlyPrint = nil
local _verbose = false

function log.init(opts)
  opts = opts or {}
  _earlyPrint = opts.earlyPrint
  _verbose = opts.verbose or false
  if _verbose then minLevel = LOG_LEVELS.DEBUG end
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

local function writeEntry(level, source, msg)
  if level < minLevel then return end

  local entry = {
    time   = computer.uptime(),
    level  = level,
    source = source or "kernel",
    msg    = tostring(msg),
  }

  entryCount = entryCount + 1
  local idx = ((entryCount - 1) % MAX_ENTRIES) + 1
  entries[idx] = entry

  -- During boot, echo to screen
  if _earlyPrint and level >= LOG_LEVELS.INFO then
    local prefix = string.format("[%s] ", LEVEL_NAMES[level] or "???")
    _earlyPrint(prefix .. entry.msg, LEVEL_COLORS[level])
  end
end

function log.debug(source, msg) writeEntry(LOG_LEVELS.DEBUG, source, msg) end
function log.info(source, msg)  writeEntry(LOG_LEVELS.INFO, source, msg) end
function log.warn(source, msg)  writeEntry(LOG_LEVELS.WARN, source, msg) end
function log.error(source, msg) writeEntry(LOG_LEVELS.ERROR, source, msg) end
function log.fatal(source, msg) writeEntry(LOG_LEVELS.FATAL, source, msg) end

-- Get recent log entries
function log.recent(count)
  count = math.min(count or 20, MAX_ENTRIES, entryCount)
  local result = {}
  local start = entryCount - count + 1
  if start < 1 then start = 1 end
  for i = start, entryCount do
    local idx = ((i - 1) % MAX_ENTRIES) + 1
    if entries[idx] then
      result[#result + 1] = entries[idx]
    end
  end
  return result
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
end

-- Dump recent logs to var/log
function log.dumpToFile(fs, path, count)
  if not fs or not path then return false, "no fs/path" end
  local ok, err = pcall(function()
    local f = fs.open(path, "a")
    if not f then error("open failed") end
    for _, e in ipairs(log.recent(count or 64)) do
      f:write(log.format(e) .. "\n")
    end
    f:close()
  end)
  if not ok then return false, err end
  return true
end

log.LEVELS = LOG_LEVELS
return log
