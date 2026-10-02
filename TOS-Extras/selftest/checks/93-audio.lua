-- Beeps, on a machine that really plays them (AUDIT 5: "every beep stops
-- the machine, and the gaps between them busy-spin"; fermi import da2b01e).
--
-- The premise was read off Ocelot's bytecode: Machine.beep pauses the
-- whole machine for the tone's length. Both halves of the fix follow from
-- it. A pattern that plays less than a second after itself is skipped,
-- because a sound triggered from outside (chat on every incoming message)
-- was a way to stall every seat on demand. And tones clamp to OC's 50 ms
-- floor, because tones under 10 ms used to be dropped, which made a low
-- `audio volume` mute the short sounds. Off-box, computer.beep is a stub
-- that takes no time at all, so none of this is measurable there. Here it
-- is timed with computer.uptime().
--
-- It BEEPS: under a second of tones in all. It skips if the operator
-- turned audio off, rather than override that, and it puts back the volume
-- and the cooldown state it found, so the login chime still plays.
return function(t)
  local okA, audio = pcall(require, "kernel.audio")
  if not okA or type(audio) ~= "table" or type(audio.isEnabled) ~= "function" then
    return t.skip("audio", "kernel.audio unavailable")
  end
  if not audio.isEnabled() then
    return t.skip("audio", "audio is turned off on this machine")
  end

  local up = computer.uptime
  local function timed(f, ...)
    local t0 = up(); f(...); return up() - t0
  end
  local vol = audio.getVolume()
  local reset = audio._resetCooldown or function() end

  local okRun, err = pcall(function()
    -- 1. The premise: a beep holds the machine for its duration.
    local d = timed(computer.beep, 440, 0.3)
    t.ok(string.format("computer.beep(440, 0.3) holds the machine (%.2f s)", d), d >= 0.2)

    -- 2. The cooldown: a second chime inside it plays nothing.
    audio.setVolume(1.0)
    reset()
    local first = timed(audio.chat)
    local second = timed(audio.chat)
    t.ok(string.format("a repeat chat() inside the cooldown is skipped (%.2f s, then %.2f s)",
      first, second), first >= 0.1 and second < 0.05)

    -- 3. The floor: at the lowest volume notify() is 6 ms x 0.1. It used to
    -- be dropped; it now plays at OC's 50 ms minimum.
    audio.setVolume(0.1)
    reset()
    local low = timed(audio.notify)
    t.ok(string.format("notify() at volume 0.1 still plays (%.2f s)", low), low >= 0.04)
  end)

  audio.setVolume(vol)
  reset()
  if not okRun then error(err, 0) end
end
