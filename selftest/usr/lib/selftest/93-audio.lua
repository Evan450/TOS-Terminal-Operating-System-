















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
    
    local d = timed(computer.beep, 440, 0.3)
    t.ok(string.format("computer.beep(440, 0.3) holds the machine (%.2f s)", d), d >= 0.2)

    
    audio.setVolume(1.0)
    reset()
    local first = timed(audio.chat)
    local second = timed(audio.chat)
    t.ok(string.format("a repeat chat() inside the cooldown is skipped (%.2f s, then %.2f s)",
      first, second), first >= 0.1 and second < 0.05)

    
    
    audio.setVolume(0.1)
    reset()
    local low = timed(audio.notify)
    t.ok(string.format("notify() at volume 0.1 still plays (%.2f s)", low), low >= 0.04)
  end)

  audio.setVolume(vol)
  reset()
  if not okRun then error(err, 0) end
end
