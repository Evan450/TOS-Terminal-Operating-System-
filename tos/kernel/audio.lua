local computer = require("computer")

local audio = {}

local enabled = true
local volume  = 1.0

--! OpenComputers plays no beep shorter than 50 ms (Machine.beep clamps
--! the duration to [50, 5000] ms), so that is the floor here too. Below
--! 10 ms this used to RETURN instead -- and since the "volume" is a
--! duration multiplier, `audio volume 10` silently muted notify, tick and
--! chat (0.06 s and less) while error and critical stayed audible.
local MIN_TONE = 0.05

local function tone(freq, dur)
  if not enabled then return end
  dur = dur * volume
  if dur < MIN_TONE then dur = MIN_TONE end
  pcall(computer.beep, freq, dur)
end

--! #SEC L (audio.gap) — never pullSignal here: it POPS the next event (a
--! key_down typed during the beeps) and throws it away. But the answer to
--! that was a 50 ms busy-spin that never yields either, which on this
--! cooperative scheduler froze every other seat for each gap (AUDIT 5).
--! Inside a process the gap is now proc.pause: cooperative yields, during
--! which nothing is delivered to us and anything that arrives is kept for
--! our next ordinary yield. Only with no process to yield from (boot, a
--! kernel event listener, a panic) does it still spin -- briefly, and
--! there is nothing else that could be running in that context anyway.
local GAP = 0.05
local procMod = nil
local function gap()
  if procMod == nil then
    local ok, m = pcall(require, "kernel.process")
    procMod = (ok and type(m) == "table" and type(m.pause) == "function") and m or false
  end
  if procMod and procMod.pause(GAP) then return end
  local target = computer.uptime() + GAP
  while computer.uptime() < target do

  end
end

--! Each tone PAUSES THE MACHINE for its own length: Ocelot's
--! Machine.beep(Context, Arguments) calls Context.pause(duration) after
--! emitting it (AUDIT 5, read off the bytecode). So a sound that can be
--! triggered from outside -- chat() on every incoming message, warning()
--! on every command-not-found -- was a way to stall every seat on demand:
--! a chat flood was a system-wide stall. A pattern that played less than
--! COOLDOWN seconds ago is now skipped; one chime per burst says
--! everything the next twenty would have. critical() is exempt: it marks
--! a failure, and nothing sends those in a stream.
local COOLDOWN = 1.0
local lastPlayed = {}
local function allowed(name)
  local now = computer.uptime()
  local last = lastPlayed[name]
  if last and now - last < COOLDOWN and now >= last then return false end
  lastPlayed[name] = now
  return true
end

function audio.success()
  if not allowed("success") then return end
  tone(1000, 0.1)
end

function audio.confirm()
  if not allowed("confirm") then return end
  tone(800, 0.08)
  gap()
  tone(1200, 0.1)
end

function audio.error()
  if not allowed("error") then return end
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
  if not allowed("warning") then return end
  tone(500, 0.1)
  gap()
  tone(500, 0.1)
end

function audio.notify()
  if not allowed("notify") then return end
  tone(1200, 0.06)
end

function audio.shutdown()
  if not allowed("shutdown") then return end
  tone(800, 0.12)
  gap()
  tone(400, 0.15)
end

function audio.boot()
  if not allowed("boot") then return end
  tone(1000, 0.15)
end

function audio.bootComplete()
  if not allowed("bootComplete") then return end
  tone(800, 0.08)
  gap()
  tone(1000, 0.08)
  gap()
  tone(1200, 0.1)
end

function audio.chat()
  if not allowed("chat") then return end
  tone(1000, 0.05)
  gap()
  tone(1400, 0.08)
end

function audio.tick()
  if not allowed("tick") then return end
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

function audio._resetCooldown() lastPlayed = {} end
audio.COOLDOWN = COOLDOWN

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
