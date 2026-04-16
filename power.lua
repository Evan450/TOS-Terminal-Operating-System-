-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Power Monitor          ║
-- ║  Battery tracking & power saving     ║
-- ╚══════════════════════════════════════╝
-- Active only in tablet mode. On computers, provides
-- stub functions that report "AC power" so the rest
-- of the OS doesn't need to care about the difference.

local computer = require("computer")

local power = {}

-- State
local isTablet = false
local lastLevel = 100
local lastCheck = 0
local CHECK_INTERVAL = 5  -- Seconds between battery polls
local warned = { low = false, critical = false }

-- Thresholds (set from config during init)
local LOW_THRESHOLD = 15
local CRIT_THRESHOLD = 5

-- Callbacks
local onLowBattery = nil
local onCriticalBattery = nil

-- Module refs
local log = nil
local config = nil

-- ============================================================
-- Init
-- ============================================================

function power.init(modules)
  log    = modules.log
  config = modules.config

  isTablet = config and config.isTablet() or false

  if config then
    LOW_THRESHOLD  = config.get("lowBatWarn") or 15
    CRIT_THRESHOLD = config.get("critBatWarn") or 5
  end

  if isTablet then
    if log then log.info("power", "Tablet mode: battery monitoring active") end
  else
    if log then log.debug("power", "Computer mode: power monitor idle") end
  end

  return true
end

-- ============================================================
-- Battery status
-- ============================================================

--- Get current battery level (0-100)
-- On computers, always returns 100
function power.level()
  if not isTablet then return 100 end

  local now = computer.uptime()
  if now - lastCheck >= CHECK_INTERVAL then
    -- computer.energy() returns current stored energy
    -- computer.maxEnergy() returns max capacity
    local current = computer.energy()
    local max = computer.maxEnergy()
    if max > 0 then
      lastLevel = math.floor((current / max) * 100)
    else
      lastLevel = 100
    end
    lastCheck = now
  end

  return lastLevel
end

--- Get raw energy values
function power.energy()
  return computer.energy(), computer.maxEnergy()
end

--- Check if on external power (computers always true)
function power.isCharging()
  if not isTablet then return true end
  -- OC tablets don't expose charging state directly,
  -- but we can infer from energy increasing
  -- For now, assume not charging when on tablet
  return false
end

--- Is battery monitoring active?
function power.isActive()
  return isTablet
end

-- ============================================================
-- Periodic check (called from kernel tick or timer)
-- ============================================================

function power.check()
  if not isTablet then return end

  local level = power.level()

  -- Critical battery warning
  if level <= CRIT_THRESHOLD and not warned.critical then
    warned.critical = true
    if log then log.error("power", "CRITICAL: Battery at " .. level .. "%!") end
    if onCriticalBattery then onCriticalBattery(level) end
  -- Low battery warning
  elseif level <= LOW_THRESHOLD and not warned.low then
    warned.low = true
    if log then log.warn("power", "Low battery: " .. level .. "%") end
    if onLowBattery then onLowBattery(level) end
  end

  -- Reset warnings independently if battery recovered (charging)
  if level > CRIT_THRESHOLD + 5 then
    warned.critical = false
  end
  if level > LOW_THRESHOLD + 5 then
    warned.low = false
  end
end

-- ============================================================
-- Callbacks
-- ============================================================

function power.onLow(callback)
  onLowBattery = callback
end

function power.onCritical(callback)
  onCriticalBattery = callback
end

-- ============================================================
-- Status string (for status bar)
-- ============================================================

function power.statusString()
  if not isTablet then return nil end  -- Don't show on computers

  local level = power.level()
  local icon

  if level > 75 then     icon = "█"  -- Full-ish
  elseif level > 50 then icon = "▓"
  elseif level > 25 then icon = "▒"
  else                   icon = "░"  -- Low
  end

  return string.format("%s%d%%", icon, level)
end

--- Get color for battery level (for status bar coloring)
function power.statusColor()
  local level = power.level()
  if level <= CRIT_THRESHOLD then return 0xFF0000     -- Red
  elseif level <= LOW_THRESHOLD then return 0xFFFF00   -- Yellow
  else return 0x00FF00 end                             -- Green
end

return power
