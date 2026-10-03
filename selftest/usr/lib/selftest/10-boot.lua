


return function(t)
  local TOS = _G._TOS
  t.ok("_TOS global exists", type(TOS) == "table")
  if type(TOS) ~= "table" then return end

  t.ok("filesystem is up", type(TOS.fs) == "table")
  t.ok("log is up",        type(TOS.log) == "function" or type(TOS.log) == "table")

  
  
  
  local free = computer.freeMemory()
  t.ok("free memory > 32K after boot (" .. math.floor(free / 1024) .. "K)",
    free > 32 * 1024)

  
  
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

  
  
  t.ok("uptime is positive", computer.uptime() > 0)
end
