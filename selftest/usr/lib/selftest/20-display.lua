









return function(t)
  
  
  
  
  if not (t.cfg and t.cfg.screen) then
    return t.skip("display colour cache", "screen checks are opt-in: add screen=true to selftest.on")
  end

  local okD, display = pcall(require, "kernel.display")
  if not okD or type(display) ~= "table" then
    return t.skip("display", "kernel.display unavailable")
  end
  local gpu = display.getGpu and display.getGpu()
  if not gpu or not gpu.getBackground then
    return t.skip("display", "no GPU bound on this machine")
  end

  local W, H = gpu.getResolution()
  local BLUE = 0x336699                       
  local ROW  = H                              

  
  
  
  
  
  local function saveRow(y)
    local cells = {}
    for x = 1, W do
      local ok, ch, fg, bg = pcall(gpu.get, x, y)
      cells[x] = ok and { ch = ch, fg = fg, bg = bg } or nil
    end
    return cells
  end
  local function restoreRow(y, cells)
    
    
    
    
    
    
    for x = 1, W do
      local c = cells[x]
      if c then pcall(display.set, x, y, c.ch or " ", c.fg, c.bg) end
    end
    
    local okS, sm = pcall(require, "kernel.screen")
    if okS and sm and sm.invalidateAll then pcall(sm.invalidateAll) end
  end

  local saved = saveRow(ROW)

  
  
  
  
  
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, BLUE)
  t.eq("hardware is at the fill colour", BLUE, gpu.getBackground())

  
  
  
  display.scrollUp(H - 1, H)
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, BLUE)
  t.eq("same colour still reaches the hardware after a scroll",
    BLUE, gpu.getBackground())

  
  local before = gpu.getBackground()
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, BLUE)
  t.eq("a repeated colour leaves the hardware where it was", before,
    gpu.getBackground())

  restoreRow(ROW, saved)
end
