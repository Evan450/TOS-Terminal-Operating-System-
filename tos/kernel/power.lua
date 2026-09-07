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

-- ============================================================
-- Conservation profiles  (`optimize power`)
-- ============================================================
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

--- The knobs a profile sets. Pure data so it can be tested off-box and
--- read by the shell without loading the kernel.
--   idleSec   how often an idle shell repaints its status bar (seconds)
--   blankSec  idle seconds before the screen is blanked (0 = never)
--   buffer    display dirty-cell buffer mode to apply ("on"/"auto")
power.PROFILES = {
  -- No conservation: the behaviour TOS had before this existed.
  off      = { idleSec = 1, blankSec = 0,   buffer = "auto" },
  -- The default. Clock still ticks once a second; the screen blanks after
  -- ten unattended minutes, which no operator sitting at the machine will
  -- ever see.
  balanced = { idleSec = 1, blankSec = 600, buffer = "auto" },
  -- Battery, solar, or a base whose generator is the bottleneck.
  save     = { idleSec = 5, blankSec = 120, buffer = "on" },
}

local PROFILE_ORDER = { "off", "balanced", "save" }
power.PROFILE_ORDER = PROFILE_ORDER

--- Pure: normalise an operator-typed profile name, or nil if unknown.
function power.normalizeProfile(name)
  name = tostring(name or ""):lower()
  if name == "none" or name == "performance" or name == "full" then name = "off" end
  if name == "default" or name == "normal" then name = "balanced" end
  if name == "saver" or name == "low" or name == "conserve" then name = "save" end
  return power.PROFILES[name] and name or nil
end

-- Live values, published on _G._TOS so the shell event loop can read them
-- on every tick without a require or a config hit. The loop runs ~10x a
-- second on every seat; a table lookup is the only affordable shape.
--
-- nil until a profile is APPLIED, not "balanced": on a boot that skipped
-- this module the globals are unpublished and the machine really does
-- behave as `off`. Reporting a profile it is not running is exactly the
-- kind of claim this feature exists to avoid making.
local activeProfile = nil

--- Apply a profile. Sets the live knobs and returns the profile name, or
--- nil + reason for an unknown name. Does NOT persist — the caller owns
--- /etc/tos.cfg (the kernel applies at boot, `optimize power` saves).
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

--- The active profile name — "off" when none has been applied, because
--- that is what the machine is then doing.
function power.profile() return activeProfile or "off" end

--- Seconds between idle status-bar repaints. Read by the shell loop.
function power.idleSeconds()
  local v = tonumber(_G._TOS and _G._TOS.powerIdleSec)
  return (v and v > 0) and v or 1
end

--- Seconds of no input before the screen blanks; 0 = never.
function power.blankSeconds()
  local v = tonumber(_G._TOS and _G._TOS.screenBlankSec)
  return (v and v > 0) and v or 0
end

--- Pure: should a seat blank now? Split out from the event loop so the
--- decision is testable without running a shell — the loop calls exactly
--- this, so the test and the running system cannot disagree.
--- `blanked` is the seat's current state; returns true only on the edge.
function power.shouldBlank(now, lastInputAt, blanked, blankSec)
  if blanked then return false end
  blankSec = blankSec or power.blankSeconds()
  if blankSec <= 0 then return false end
  now = tonumber(now) or 0
  -- No input yet this session counts from the seat's start (0), which is
  -- right: a machine nobody has ever touched is the definition of idle.
  return (now - (tonumber(lastInputAt) or 0)) >= blankSec
end

--- Override a single knob without switching profile. Returns the value
--- set, or nil + reason. `what` is "idle" or "blank".
function power.setKnob(what, seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds < 0 then return nil, "expected a number of seconds" end
  local TOS = _G._TOS
  if what == "idle" then
    if seconds < 1 then return nil, "idle cadence must be at least 1 second" end
    if TOS then TOS.powerIdleSec = seconds end
    return seconds
  elseif what == "blank" then
    -- 0 disables. Anything under 10s would blank while the operator reads.
    if seconds > 0 and seconds < 10 then return nil, "blank timeout must be 0 (off) or at least 10 seconds" end
    if TOS then TOS.screenBlankSec = seconds end
    return seconds
  end
  return nil, "unknown knob: " .. tostring(what)
end

return power
