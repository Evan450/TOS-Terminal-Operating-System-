-- Does the glass hold what we think we drew?
--
-- Three bugs reported from real hardware resisted static reading: a
-- status bar that alternates between its colour and black, output that
-- half-overwrites the F-key legend, and a selection bar leaving a wide
-- fragment on the row you moved away from. All three are "what is drawn"
-- disagreeing with "what is displayed", and no off-box test can see that
-- because off-box there is no glass.
--
-- gpu.get(x, y) returns the character AND its colours as the hardware
-- actually holds them, so this reads the screen back instead of trusting
-- the draw call. That is the whole point of running in here.
--
-- It scribbles on the screen and clears up after. The battery runs
-- before the shell paints, so there is nothing to preserve.
return function(t)
  -- Painting the boot console is opt-in: add `screen=true` to
  -- selftest.on. The console is a scrolling log and the battery logs
  -- while it runs, so no amount of save/restore keeps this invisible --
  -- enabling it is choosing a messy console for the round.
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
  local ROW = math.max(2, H - 6)          -- well clear of anything else
  local A, B = 0x336699, 0x000000         -- both real T2 palette entries

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

  -- What does the hardware actually STORE for a requested colour?
  --
  -- This GPU is Tier 2: 4-bit, 16 colours. A requested RGB is quantized
  -- to the nearest palette entry, so gpu.get never returns what you
  -- asked for unless you happened to ask for an entry. Comparing against
  -- the REQUEST then reports a perfectly good paint as a failure -- which
  -- is exactly what two of round 8's three failures were. A and B above
  -- are palette-exact by construction and need no help; the shell's own
  -- theme colours are not, and section 6 uses those on purpose because
  -- they are the colours the reported bug is about.
  --
  -- The probe costs one cell of the scratch row, overwritten immediately
  -- after, and goes through display.fill -- whose correctness assertion 1
  -- has already established before anything here runs.
  local resolvedBg = {}
  local function resolve(want)
    if resolvedBg[want] then return resolvedBg[want] end
    if display.invalidateColors then pcall(display.invalidateColors) end
    pcall(display.fill, 1, ROW, 1, 1, " ", 0xFFFFFF, want)
    resolvedBg[want] = bgAt(1) or want
    return resolvedBg[want]
  end

  -- 1. A full-width fill really does reach every cell.
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
  t.eq("a full-width fill covers every column", W, countBg(A))

  -- 2. A SHORT write leaves the rest of the row alone. This is not a bug
  --    in itself -- it is the mechanism behind every fragment reported,
  --    demonstrated on real hardware rather than argued about.
  display.set(1, ROW, string.rep("x", 10), 0xFFFFFF, B)
  t.eq("a 10-cell write changes exactly 10 cells", 10, countBg(B))
  t.eq("...and leaves the other W-10 as they were", W - 10, countBg(A))

  -- 3. THE COLOUR CACHE, on the real GPU. _setBg skips the call when the
  --    colour matches the last one set, so a raw call that moves the
  --    hardware without updating the cache makes the next matching draw
  --    a no-op. scrollUp used to do exactly that; this is the regression
  --    test for that fix, executed against hardware.
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
  t.eq("baseline row is A", W, countBg(A))
  display.scrollUp(ROW, ROW + 1)            -- sets the hardware to black, raw
  display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
  t.eq("the same colour still reaches the glass after a scroll", W, countBg(A))

  -- 4. And through the SEAT PROXY, which keeps its own second cache and
  --    its own dirty-cell shadow. The shell draws through this, not
  --    through kernel.display, so a proxy that elides a cell it believes
  --    is already correct is the likelier source of a stale bar.
  -- The battery runs BEFORE seat init (kernel.log: battery at 11.7,
  -- "Seat init" at 14.4), so screen.active() has no seat to name yet and
  -- asking for it got this skipped on the first successful round.
  -- displayProxy calls ensureInit itself, so index 1 is enough -- and
  -- seat init is about to run a fraction of a second later regardless.
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

    -- Paint the same colour twice: the shadow SHOULD elide the second,
    -- and the glass must still be right afterwards.
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    t.eq("a repeated proxy fill leaves the glass correct", W, countBg(A))

    -- Now move the hardware behind the proxy's back. UNDECLARED, the
    -- proxy cannot know: its shadow says the row is already A, so it
    -- elides. That is not a defect to fix in the proxy -- checking would
    -- cost a gpu.get per cell, every cell, forever. It is the reason
    -- every raw writer in TOS has to declare, and it is recorded here so
    -- the limit is written down rather than rediscovered.
    pcall(gpu.setBackground, B)
    pcall(gpu.fill, 1, ROW, W, 1, " ")
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    local blind = countBg(A)
    t.ok("an UNDECLARED write behind the proxy is invisible to it ("
         .. blind .. "/" .. W .. ")", blind < W)

    -- ...and declaring it repairs the row. THIS is the contract every
    -- raw writer now honours, so this one must hold.
    pcall(gpu.setBackground, B)
    pcall(gpu.fill, 1, ROW, W, 1, " ")
    if screen.invalidateAll then pcall(screen.invalidateAll) end
    proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
    if proxy.endFrame then pcall(proxy.endFrame) end
    t.eq("proxy repaints after a DECLARED write behind it", W, countBg(A))

    -- 5. THE REPORTED BUG, end to end.
    --
    -- The shell draws its status bar through proxy.statusBar, which is
    -- FORWARDED: screen.displayProxy runs it inside display.withContext
    -- on the seat's GPU. When the machine has one GPU that is this GPU,
    -- so the forwarded draw moves the very glass kernel.display's colour
    -- cache describes -- and withContext used to RESTORE that cache on
    -- the way out, on the theory that the context was other hardware.
    -- It then skipped the next fill in that colour as redundant, and the
    -- bar kept whatever the forwarded draw left. scrollUp leaves BLACK.
    --
    -- Off-box this is provable against a fake GPU, and is. On real
    -- hardware it is provable against the glass, which is better.
    display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)      -- cache: A
    local okW = pcall(display.withContext, gpu, W, H, function()
      display.fill(1, ROW, W, 1, " ", 0xFFFFFF, B)    -- glass -> B
    end)
    if okW then
      t.eq("the forwarded draw really landed", W, countBg(B))
      display.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
      t.eq("a repaint after a forwarded draw is not skipped", W, countBg(A))
    else
      t.skip("withContext", "display.withContext not callable here")
    end

    -- 6. THE SELECTION ROW, measured rather than argued about.
    --
    -- Reported: arrow-keying down the file list leaves earlier rows
    -- still wearing the highlight -- not a one-cell fragment, whole
    -- rows. The fast path repaints exactly two rows, the one you left
    -- and the one you arrived at, so a repaint of the row you LEFT that
    -- never reaches the glass looks precisely like that.
    --
    -- The shell draws the list through this proxy, so the question is
    -- narrow and answerable: does re-painting a row with the SAME text
    -- and DIFFERENT colours actually land? The shadow compares char, fg
    -- and bg, so it should -- but "should" is what four rounds of this
    -- bug have already survived.
    local SEL_FG, SEL_BG = 0x000000, 0x00AAFF   -- the shell's highlight
    local NRM_FG, NRM_BG = 0xFFFFFF, 0x000000   -- the shell's normal row
    local rowText = string.rep("r", W)
    local SEL, NRM = resolve(SEL_BG), resolve(NRM_BG)

    -- If the palette collapsed both onto one entry the selection would be
    -- invisible and every count below would be meaningless. Say so rather
    -- than reporting a confident pass built on nothing.
    if SEL == NRM then
      t.skip("selection row",
        "highlight and normal quantize to the same palette entry here")
    else
      proxy.set(1, ROW, rowText, SEL_FG, SEL_BG)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("a highlighted row paints across the full width", W, countBg(SEL))

      -- Same text, normal colours: this is "you moved off this row".
      proxy.set(1, ROW, rowText, NRM_FG, NRM_BG)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("un-highlighting the row clears every cell", W, countBg(NRM))

      -- And the inverse, since the arriving row is the other half of the
      -- same move and takes the opposite path through the diff.
      proxy.set(1, ROW, rowText, SEL_FG, SEL_BG)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("re-highlighting it covers every cell again", W, countBg(SEL))
    end

    -- 7. TWO PROXIES, ONE SCREEN.
    --
    -- displayProxy builds a FRESH proxy on every call, and the kernel
    -- calls it for the login process, for the shell, and again for each
    -- task-switcher popup. Every one keeps a private shadow of the same
    -- glass while believing it is alone on it.
    --
    -- None of the foreign-write machinery covers this: a proxy drawing
    -- normally is not a raw write, so nothing declared it, and the other
    -- proxy went on eliding repaints of cells it believed were correct.
    -- Provable off-box against a fake GPU, and is -- but the whole point
    -- of this file is that the glass gets the last word.
    -- Use the index that ALREADY produced a working proxy above. Asking
    -- screen.active() a second time skipped this check on its first
    -- round: the battery runs before seat init, so the seat it names is
    -- not necessarily one displayProxy will build for -- which is why
    -- the lookup above has a fallback. Re-deriving it here without that
    -- fallback threw the answer away and reported a skip as if the
    -- machine could not do it.
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

      -- The first proxy's shadow still says this row is A. It is not.
      proxy.fill(1, ROW, W, 1, " ", 0xFFFFFF, A)
      if proxy.endFrame then pcall(proxy.endFrame) end
      t.eq("the first proxy repaints after the second wrote", W, countBg(A))
    else
      -- Not a skip. We built a proxy for this seat seconds ago, and the
      -- kernel itself builds several per display (login, shell, task
      -- switcher), so a second one failing is a finding about the kernel
      -- -- or about this check -- and either way it is not the machine
      -- declining to answer. A skip here reads as "not applicable", and
      -- it is the one thing this must not say.
      t.ok("a second proxy can be built for seat " .. tostring(proxyIdx), false)
    end
  else
    t.skip("seat proxy", "no active seat proxy exposed on this build")
  end

  restoreRow(ROW, saved)
end
