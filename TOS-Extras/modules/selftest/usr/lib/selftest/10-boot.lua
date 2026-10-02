-- Boot invariants. The class of failure the off-box suite structurally
-- cannot see: hundreds of pure-Lua tests, not one of which catches
-- "the kernel did not actually come up on this machine".
return function(t)
  local TOS = _G._TOS
  t.ok("_TOS global exists", type(TOS) == "table")
  if type(TOS) ~= "table" then return end

  t.ok("filesystem is up", type(TOS.fs) == "table")
  t.ok("log is up",        type(TOS.log) == "function" or type(TOS.log) == "table")

  -- Free memory at the moment the battery runs. Not an assertion about a
  -- specific number -- it is recorded so a regression shows as a trend
  -- across rounds rather than as a boot that mysteriously stops fitting.
  local free = computer.freeMemory()
  t.ok("free memory > 32K after boot (" .. math.floor(free / 1024) .. "K)",
    free > 32 * 1024)

  -- The seat actually bound a display. A headless boot is legal, so this
  -- skips rather than fails when there is no GPU.
  local okC, component = pcall(require, "component")
  if okC and component then
    local hasGpu = false
    for _ in component.list("gpu") do hasGpu = true break end
    if hasGpu then
      local okS, screen = pcall(require, "kernel.screen")
      t.ok("screen module loaded", okS and type(screen) == "table")
    else
      t.skip("seat binding", "no GPU on this machine")
    end
  end

  -- Uptime must be sane. A clock that reads zero here means computer.uptime
  -- is not what every timeout in the tree believes it is.
  t.ok("uptime is positive", computer.uptime() > 0)
end
