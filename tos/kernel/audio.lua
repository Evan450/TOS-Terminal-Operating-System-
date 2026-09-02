local computer = require("computer")

local audio = {}

local enabled = true
local volume  = 1.0

local function tone(freq, dur)
  if not enabled then return end
  dur = dur * volume
  if dur < 0.01 then return end
  pcall(computer.beep, freq, dur)
end

local function gap()
  local target = computer.uptime() + 0.05
  while computer.uptime() < target do

  end
end

function audio.success()
  tone(1000, 0.1)
end

function audio.confirm()
  tone(800, 0.08)
  gap()
  tone(1200, 0.1)
end

function audio.error()
  tone(300, 0.3)
end

function audio.critical()
  tone(400, 0.15)
  gap()
  tone(400, 0.15)
  gap()
  tone(400, 0.15)
end

function audio.warning()
  tone(500, 0.1)
  gap()
  tone(500, 0.1)
end

function audio.notify()
  tone(1200, 0.06)
end

function audio.shutdown()
  tone(800, 0.12)
  gap()
  tone(400, 0.15)
end

function audio.boot()
  tone(1000, 0.15)
end

function audio.bootComplete()
  tone(800, 0.08)
  gap()
  tone(1000, 0.08)
  gap()
  tone(1200, 0.1)
end

function audio.chat()
  tone(1000, 0.05)
  gap()
  tone(1400, 0.08)
end

function audio.tick()
  tone(600, 0.02)
end

function audio.setEnabled(state)
  enabled = state ~= false
end

function audio.isEnabled()
  return enabled
end

function audio.setVolume(v)
  volume = math.max(0.1, math.min(2.0, tonumber(v) or 1.0))
end

function audio.getVolume()
  return volume
end

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
