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

--! WHAT OPENCOMPUTERS ACTUALLY CHARGES FOR, because a "power saving"
--! toggle that saves nothing is worse than no toggle at all. Verified
--! against the OpenComputers config shipped with the emulator
--! (OpenComputers.conf, `power.cost`), not from memory:
--!
--!   * computer, per tick while RUNNING .............. computer
--!     ...multiplied by `sleepFactor` (0.1 by default) for the ticks it
--!     spends blocked in pullSignal or os.sleep. Time asleep is an order
--!     of magnitude cheaper than time awake, so FEWER IDLE WAKE-UPS is a
--!     real saving, not a micro-optimisation.
--!   * screen, per tick .............................. screen
--!     "For each lit pixel (each character that is not blank) this cost
--!     increases linearly." A screen showing a full TUI costs; a screen
--!     showing spaces costs ~nothing. That is what makes blanking worth
--!     doing, and why we blank with SPACES on black rather than drawing
--!     a screensaver.
--!   * GPU writes .................................... gpuSet / gpuFill
--!     Billed per changed cell, and `set` is the most expensive of them.
--!     The dirty-cell display buffer (`optimize buffer`) skips writes for
--!     cells that did not change, so it is a power feature as much as a
--!     speed one.
--!   * disk I/O ...................................... hddRead/hddWrite
--!     Per kilobyte, and writes cost more than reads. Swap trades RAM for
--!     disk writes, so it is the one optimisation that COSTS energy.
--!
--! The numbers themselves are pack-configurable, so nothing here hardcodes
--! them — the profiles change behaviour, and `optimize power` reports the
--! machine's measured energy rather than an estimate from constants that
--! may not be this server's.

power.PROFILES = {

  off      = { idleSec = 1, blankSec = 0,   buffer = "auto" },

  balanced = { idleSec = 1, blankSec = 600, buffer = "auto" },

  save     = { idleSec = 5, blankSec = 120, buffer = "on" },
}

local PROFILE_ORDER = { "off", "balanced", "save" }
power.PROFILE_ORDER = PROFILE_ORDER

function power.normalizeProfile(name)
  name = tostring(name or ""):lower()
  if name == "none" or name == "performance" or name == "full" then name = "off" end
  if name == "default" or name == "normal" then name = "balanced" end
  if name == "saver" or name == "low" or name == "conserve" then name = "save" end
  return power.PROFILES[name] and name or nil
end

local activeProfile = nil

function power.applyProfile(name)
  local key = power.normalizeProfile(name)
  if not key then return nil, "unknown power profile: " .. tostring(name) end
  local p = power.PROFILES[key]
  activeProfile = key
  local TOS = _G._TOS
  if TOS then
    TOS.powerIdleSec   = p.idleSec
    TOS.screenBlankSec = p.blankSec
  end
  if log then log.info("power", "Profile '" .. key .. "': idle "
    .. p.idleSec .. "s, blank " .. (p.blankSec > 0 and (p.blankSec .. "s") or "never")) end
  return key
end

function power.profile() return activeProfile or "off" end

function power.idleSeconds()
  local v = tonumber(_G._TOS and _G._TOS.powerIdleSec)
  return (v and v > 0) and v or 1
end

function power.blankSeconds()
  local v = tonumber(_G._TOS and _G._TOS.screenBlankSec)
  return (v and v > 0) and v or 0
end

function power.shouldBlank(now, lastInputAt, blanked, blankSec)
  if blanked then return false end
  blankSec = blankSec or power.blankSeconds()
  if blankSec <= 0 then return false end
  now = tonumber(now) or 0

  return (now - (tonumber(lastInputAt) or 0)) >= blankSec
end

function power.setKnob(what, seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds < 0 then return nil, "expected a number of seconds" end
  local TOS = _G._TOS
  if what == "idle" then
    if seconds < 1 then return nil, "idle cadence must be at least 1 second" end
    if TOS then TOS.powerIdleSec = seconds end
    return seconds
  elseif what == "blank" then

    if seconds > 0 and seconds < 10 then return nil, "blank timeout must be 0 (off) or at least 10 seconds" end
    if TOS then TOS.screenBlankSec = seconds end
    return seconds
  end
  return nil, "unknown knob: " .. tostring(what)
end

return power
