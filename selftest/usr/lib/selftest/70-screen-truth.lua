














return function(t)
  
  
  
  
  if not (t.cfg and t.cfg.screen) then
    return t.skip("screen truth", "screen checks are opt-in: add screen=true to selftest.on")
  end

  local okD, display = pcall(require, "kernel.display")
  if not okD or type(display) ~= "table" then
    return t.skip("screen truth", "kernel.display unavailable")
  end
  local gpu = display.getGpu and display.getGpu()
  if not gpu or not gpu.get then
    return t.skip("screen truth", "no GPU, or gpu.get unavailable here")
  end

  local W, H = gpu.getResolution()
  local ROW = math.max(2, H - 6)          
  local A, B = 0x336699, 0x000000         

  
  
  
  
  
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

  local function bgAt(x)
    local ok, ch, fg, bg = pcall(gpu.get, x, ROW)
    if not ok then return nil end
    return bg
  end

  local function countBg(want)
    local n = 0
    for x = 1, W do if bgAt(x) == want then n = n + 1 end end
    return n
  end

  
  
  
  
  
  
  
  
  
  
  
  
  
  
  local resolvedBg = {}
  local function resolve(want)
    if resolvedBg[want] then return resolvedBg[want] end
    if display.invalidateColors then pcall(display.invalidateColors) end
    pcall(display.fill, 1, ROW, 1, 1, " ", 0xFFFFFF, want)
    resolvedBg[want] = bgAt(1) or want
    return resolvedBg[want]
  end

  
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
  t.eq("a full-width fill covers every column", W, countBg(A))

  
  
  
  display.set(1, ROW, string.rep("x", 10), 0xFFFFFF, B)
  t.eq("a 10-cell write changes exactly 10 cells", 10, countBg(B))
  t.eq("...and leaves the other W-10 as they were", W - 10, countBg(A))

  
  
  
  
  
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
  t.eq("baseline row is A", W, countBg(A))
  display.scrollUp(ROW, ROW + 1)            
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
  t.eq("the same colour still reaches the glass after a scroll", W, countBg(A))

  
  
  
  
  
  
  
  
  
  local okS, screen = pcall(require, "kernel.screen")
  local proxy, proxyIdx = nil, nil
  if okS and screen and screen.displayProxy then
    for _, idx in ipairs({ (screen.active and screen.active()) or 1, 1 }) do
      local okP, pr = pcall(screen.displayProxy, idx)
      if okP and type(pr) == "table" and pr.fill then
        proxy, proxyIdx = pr, idx
        break
      end
    end
  end
  if type(proxy) == "table" and proxy.fill and proxy.set then
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    t.eq("proxy fill reaches every column", W, countBg(A))

    
    
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    t.eq("a repeated proxy fill leaves the glass correct", W, countBg(A))

    
    
    
    
    
    
    pcall(gpu.setBackground, B)
    pcall(gpu.fill, 1, ROW, W, 1, " ")
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    local blind = countBg(A)
    t.ok("an UNDECLARED write behind the proxy is invisible to it ("
         .. blind .. "/" .. W .. ")", blind < W)

    
    
    pcall(gpu.setBackground, B)
    pcall(gpu.fill, 1, ROW, W, 1, " ")
    if screen.invalidateAll then pcall(screen.invalidateAll) end
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    t.eq("proxy repaints after a DECLARED write behind it", W, countBg(A))

    
    
    
    
    
    
    
    
    
    
    
    
    
    display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)      
    local okW = pcall(display.withContext, gpu, W, H, function()
      display.fill(1, ROW, W, 1, " ", 0xFFFFFF, B)    
    end)
    if okW then
      t.eq("the forwarded draw really landed", W, countBg(B))
      display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
      t.eq("a repaint after a forwarded draw is not skipped", W, countBg(A))
    else
      t.skip("withContext", "display.withContext not callable here")
    end

    
    
    
    
    
    
    
    
    
    
    
    
    
    local SEL_FG, SEL_BG = 0x000000, 0x00AAFF   
    local NRM_FG, NRM_BG = 0xFFFFFF, 0x000000   
    local rowText = string.rep("r", W)
    local SEL, NRM = resolve(SEL_BG), resolve(NRM_BG)

    
    
    
    if SEL == NRM then
      t.skip("selection row",
        "highlight and normal quantize to the same palette entry here")
    else
      proxy.set(1, ROW, rowText, SEL_FG, SEL_BG)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("a highlighted row paints across the full width", W, countBg(SEL))

      
      proxy.set(1, ROW, rowText, NRM_FG, NRM_BG)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("un-highlighting the row clears every cell", W, countBg(NRM))

      
      
      proxy.set(1, ROW, rowText, SEL_FG, SEL_BG)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("re-highlighting it covers every cell again", W, countBg(SEL))
    end

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    local other = nil
    if proxyIdx then
      local okO, o = pcall(screen.displayProxy, proxyIdx)
      if okO and type(o) == "table" and o.fill then other = o end
    end
    if other then
      proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
      if proxy.endFrame then pcall(proxy.endFrame) end

      other.fill(1, ROW, W, 1, " ", 0xFFFFFF, B)
      if other.endFrame then pcall(other.endFrame) end
      t.eq("a second proxy's fill reaches the glass", W, countBg(B))

      
      proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("the first proxy repaints after the second wrote", W, countBg(A))
    else
      
      
      
      
      
      
      t.ok("a second proxy can be built for seat " .. tostring(proxyIdx), false)
    end
  else
    t.skip("seat proxy", "no active seat proxy exposed on this build")
  end

  restoreRow(ROW, saved)
end
