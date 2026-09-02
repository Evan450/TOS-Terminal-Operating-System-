local computer = require("computer")

local power = {}

local isTablet = false
local lastLevel = 100
local lastCheck = 0
local CHECK_INTERVAL = 5
local warned = { low = false, critical = false }

local LOW_THRESHOLD = 15
local CRIT_THRESHOLD = 5

local onLowBattery = nil
local onCriticalBattery = nil

local log = nil
local config = nil

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

function power.level()
  if not isTablet then return 100 end

  local now = computer.uptime()
  if now - lastCheck >= CHECK_INTERVAL then

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

function power.energy()
  return computer.energy(), computer.maxEnergy()
end

function power.isActive()
  return isTablet
end

function power.check()
  if not isTablet then return end

  local level = power.level()

  if level <= CRIT_THRESHOLD and not warned.critical then
    warned.critical = true
    if log then log.error("power", "CRITICAL: Battery at " .. level .. "%!") end
    if onCriticalBattery then onCriticalBattery(level) end

  elseif level <= LOW_THRESHOLD and not warned.low then
    warned.low = true
    if log then log.warn("power", "Low battery: " .. level .. "%") end
    if onLowBattery then onLowBattery(level) end
  end

  if level > CRIT_THRESHOLD + 5 then
    warned.critical = false
  end
  if level > LOW_THRESHOLD + 5 then
    warned.low = false
  end
end

function power.onLow(callback)
  onLowBattery = callback
end

function power.onCritical(callback)
  onCriticalBattery = callback
end

function power.statusString()
  if not isTablet then return nil end

  local level = power.level()
  local icon

  if level > 75 then     icon = "█"
  elseif level > 50 then icon = "▓"
  elseif level > 25 then icon = "▒"
  else                   icon = "░"
  end

  return string.format("%s%d%%", icon, level)
end

return power
