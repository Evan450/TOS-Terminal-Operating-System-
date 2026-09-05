-- The GPU colour cache, on a real GPU.
--
-- display._setBg skips the gpu call when the requested colour matches the
-- last one set. That is only correct while the cache tells the truth, and
-- scrollUp used to set the hardware to black with a RAW call without
-- updating it -- so the next fill in the cached colour was skipped and
-- painted black. It shipped as "the status bar background is black".
--
-- The off-box test for this drives a FAKE gpu. This one drives the real
-- one, which is the point: it audits the fake.
return function(t)
  -- Painting the boot console is opt-in: add `screen=true` to
  -- selftest.on. The console is a scrolling log and the battery logs
  -- while it runs, so no amount of save/restore keeps this invisible --
  -- enabling it is choosing a messy console for the round.
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
  local BLUE = 0x336699                       -- a real T2 palette entry
  local ROW  = H                              -- the bottom line only

  -- SAVE THE ROW, then put it back. These checks run on the boot console
  -- an operator is watching, and "clear it to black afterwards" is not
  -- tidying up -- it destroys whatever the boot log had written there.
  -- gpu.get returns the character AND its colours, which is exactly
  -- enough to restore a row byte for byte.
  local function saveRow(y)
    local cells = {}
    for x = 1, W do
      local ok, ch, fg, bg = pcall(gpu.get, x, y)
      cells[x] = ok and { ch = ch, fg = fg, bg = bg } or nil
    end
    return cells
  end
  local function restoreRow(y, cells)
    -- display.set, NOT raw gpu calls. Writing raw moves the hardware
    -- without updating kernel.display's OWN _lastFg/_lastBg, so the next
    -- display.fill sees a matching cached colour and skips the call --
    -- which is precisely the bug this file exists to detect, committed
    -- by the code cleaning up after it. Round two went 7/1 -> 4/4 on
    -- exactly that.
    for x = 1, W do
      local c = cells[x]
      if c then pcall(display.set, x, y, c.ch or " ", c.fg, c.bg) end
    end
    -- Still tell the live proxies: display.set is raw from THEIR side.
    local okS, sm = pcall(require, "kernel.screen")
    if okS and sm and sm.invalidateAll then pcall(sm.invalidateAll) end
  end

  local saved = saveRow(ROW)

  -- THIS DRAWS ON THE BOOT CONSOLE the operator is watching, so it works
  -- on ONE row and puts it back. The first successful round left a blue
  -- band across the screen and scrolled the boot log up by a line, which
  -- looked like a display fault and was really this check tidying up
  -- after nobody.
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, BLUE)
  t.eq("hardware is at the fill colour", BLUE, gpu.getBackground())

  -- Scroll only the bottom two rows, not the whole screen: the mechanism
  -- under test is the colour cache, and scrolling the console to prove
  -- it costs the operator the top of their boot log.
  display.scrollUp(H - 1, H)
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, BLUE)
  t.eq("same colour still reaches the hardware after a scroll",
    BLUE, gpu.getBackground())

  -- And the optimisation itself must survive: a repeat really should skip.
  local before = gpu.getBackground()
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, BLUE)
  t.eq("a repeated colour leaves the hardware where it was", before,
    gpu.getBackground())

  restoreRow(ROW, saved)
end
