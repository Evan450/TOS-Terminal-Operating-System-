-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Audio Feedback         ║
-- ║  Beep codes and notification sounds  ║
-- ╚══════════════════════════════════════╝
-- Provides audible feedback through the computer speaker.
-- Useful for headless machines or general UI feedback.
--
-- Beep code reference:
--   1 short high beep     = Boot success / positive action
--   2 ascending beeps     = Login success / task complete
--   1 long low beep       = Error / login failure
--   3 short low beeps     = Critical error / kernel panic
--   2 short beeps         = Warning / command not found
--   1 quick high beep     = Notification / chat message
--   2 descending beeps    = Shutdown / logout

local computer = require("computer")

local audio = {}

-- ============================================================
-- Configuration
-- ============================================================

local enabled = true     -- Master audio toggle
local volume  = 1.0      -- Volume multiplier for durations (0.5 = quieter/shorter)

-- ============================================================
-- Low-level beep
-- ============================================================

--- Play a single tone. Does nothing if audio is disabled.
-- @param freq number: Frequency in Hz (200-2000 typical)
-- @param dur number: Duration in seconds
local function tone(freq, dur)
  if not enabled then return end
  dur = dur * volume
  if dur < 0.01 then return end
  pcall(computer.beep, freq, dur)
end

--- Brief pause between beeps (yields to scheduler).
-- #SEC L (audio.gap) — pullSignal *consumes* the next event if one is
-- queued (e.g. a `key_down` the user pressed during a beep sequence),
-- discarding their input. Use an uptime-based busy wait that never
-- pops the event queue. The wait is short (50 ms) so the busy-spin
-- cost is negligible on OC's scheduler.
local function gap()
  local target = computer.uptime() + 0.05
  while computer.uptime() < target do
    -- spin; intentionally do NOT call pullSignal so we don't eat events
  end
end

-- ============================================================
-- Beep patterns
-- ============================================================

--- Single short high beep: success, positive feedback.
function audio.success()
  tone(1000, 0.1)
end

--- Two ascending beeps: login success, task complete.
function audio.confirm()
  tone(800, 0.08)
  gap()
  tone(1200, 0.1)
end

--- Single long low beep: error, login failure.
function audio.error()
  tone(300, 0.3)
end

--- Three short low beeps: critical error, kernel panic.
function audio.critical()
  tone(400, 0.15)
  gap()
  tone(400, 0.15)
  gap()
  tone(400, 0.15)
end

--- Two short beeps: warning, command not found.
function audio.warning()
  tone(500, 0.1)
  gap()
  tone(500, 0.1)
end

--- Single quick high beep: notification, incoming message.
function audio.notify()
  tone(1200, 0.06)
end

--- Two descending beeps: shutdown, logout.
function audio.shutdown()
  tone(800, 0.12)
  gap()
  tone(400, 0.15)
end

--- Single short medium beep: boot POST success.
function audio.boot()
  tone(1000, 0.15)
end

--- Three ascending beeps: boot complete melody.
function audio.bootComplete()
  tone(800, 0.08)
  gap()
  tone(1000, 0.08)
  gap()
  tone(1200, 0.1)
end

--- Quick two-tone chime: chat / incoming message.
function audio.chat()
  tone(1000, 0.05)
  gap()
  tone(1400, 0.08)
end

--- Single low tick: keypress feedback (very short, use sparingly).
function audio.tick()
  tone(600, 0.02)
end

-- ============================================================
-- Configuration
-- ============================================================

--- Enable or disable audio feedback.
function audio.setEnabled(state)
  enabled = state ~= false
end

--- Check if audio is enabled.
function audio.isEnabled()
  return enabled
end

--- Set volume/duration multiplier (0.5 = shorter beeps, 1.0 = normal, 1.5 = longer).
function audio.setVolume(v)
  volume = math.max(0.1, math.min(2.0, tonumber(v) or 1.0))
end

function audio.getVolume()
  return volume
end

--- Initialize from system config.
function audio.init(config)
  if config then
    local audioEnabled = config.get("audio")
    if audioEnabled ~= nil then
      enabled = audioEnabled ~= false
    end
    local audioVolume = config.get("audioVolume")
    if audioVolume then
      audio.setVolume(audioVolume)
    end
  end
end

return audio
