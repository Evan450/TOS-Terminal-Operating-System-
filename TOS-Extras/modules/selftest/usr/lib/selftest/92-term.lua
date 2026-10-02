-- compat.term on real OpenComputers (AUDIT 5, H-04 / H-06 / H-07).
--
-- H-04: term.read used to pull straight off the machine's signal queue.
-- It now YIELDS whenever it can, so the scheduler hands it this seat's
-- input, and pulls raw only when it cannot. coroutine.isyieldable() picks
-- the branch, and real OpenComputers answers that differently from a
-- desktop Lua: the whole kernel already runs inside machine.lua's
-- coroutine, and OC's coroutine library wraps yield so that a program's
-- own yields come back to the program's resume while the machine's
-- (pullSignal, synchronized component calls) bubble past it to the host.
-- Off-box there is no such wrapper. So this:
--   1. records what isyieldable() answers in kernel context here, which
--      says whether the "no scheduler: bounded raw pull" branch is ever
--      reached at boot on a real machine;
--   2. runs term.read inside a coroutine, as a process runs it, and feeds
--      it keystrokes through resume -- the scheduler's job -- while its
--      redraws hit the real GPU in between. It has to hand control back to
--      our resume on every wait, and return the line it was fed.
-- It never pushes a signal: a key_down sent now would reach the login
-- screen as a phantom keystroke.
--
-- H-06 / H-07 with no caller seat (kernel context): the cursor is the
-- shared one and term.screen() is the machine's screen. The PER-SEAT half
-- needs two seats and a running shell, which is past the point where the
-- battery runs, so it stays an operator check (TODO.txt, OCELOT CHECK FOR
-- THE FERMI IMPORT).
return function(t)
  local okT, term = pcall(require, "compat.term")
  if not okT or type(term) ~= "table" then
    return t.skip("compat.term", "does not load here: " .. tostring(term))
  end

  -- 1. The yieldability question, answered by the machine.
  local y = coroutine.isyieldable and coroutine.isyieldable()
  t.ok("coroutine.isyieldable() in kernel context is a boolean", type(y) == "boolean")
  -- The answer itself goes in as a note: only failure and skip names reach
  -- the report, and the first round lost it by carrying it in a pass name.
  if t.note then
    t.note("isyieldable() in kernel context: " .. tostring(y) .. " -- term.read at boot "
      .. (y and "yields to the host; its bounded raw-pull branch is unreachable here"
            or "takes the bounded raw pull"))
  end

  -- H-07 with no seat: the machine's screen, and a GPU proxy that answers.
  local scr = term.screen()
  t.ok("term.screen() is a real screen address",
    scr ~= nil and component.type(scr) == "screen")
  -- CALL it, never type() it: a real component method is a callable
  -- table (machine.lua's componentCallback). The first round of this
  -- check asserted type(...) == "function" and failed for exactly that
  -- reason -- which is how term.gpu()'s own identical mistake was found.
  local okG, tg = pcall(term.gpu)
  local okW, w = pcall(function() return tg.getResolution() end)
  t.ok("term.gpu() answers with a usable proxy" .. (okW and "" or (" (" .. tostring(w) .. ")")),
    okG and type(tg) == "table" and okW and type(w) == "number")

  -- The premise, on this machine: a raw GPU method is a callable table.
  local gaddr = component.list("gpu")()
  local raw = gaddr and component.proxy(gaddr)
  local mt = raw and type(raw.set) == "table" and getmetatable(raw.set)
  t.ok("a raw GPU method here is a callable table, not a function",
    type(mt) == "table" and mt.__call ~= nil)
  -- ...so a display-cap proxy must hand back its OWN wrapper for a mutating
  -- method (the one that marks the glass dirty), not the raw callable.
  local okC, rw = pcall(term._gpuForCaps, { gpu = true })
  t.ok("a display-cap term.gpu() wraps setBackground (marks the glass dirty)",
    okC and type(rw) == "table" and type(rw.setBackground) == "function")

  -- H-06 with no seat: the shared cursor round-trips.
  local cx, cy = term.getCursor()
  term.setCursor(7, 3)
  local nx, ny = term.getCursor()
  t.ok("setCursor/getCursor round-trip with no caller seat", nx == 7 and ny == 3)
  term.setCursor(cx, cy)

  -- 2. term.read in a coroutine. It paints the line it is reading, so it
  -- is opt-in like every check that draws on the boot console.
  if not (t.cfg and t.cfg.screen) then
    return t.skip("term.read in a coroutine",
      "it draws: add screen=true to selftest.on")
  end
  -- Without isyieldable, term.read takes the raw-pull branch even inside
  -- our coroutine and waits for a REAL Enter key, which would hold the
  -- boot at this check until someone typed one.
  if type(coroutine.isyieldable) ~= "function" then
    return t.skip("term.read in a coroutine",
      "this Lua has no coroutine.isyieldable, so term.read would wait for a real key")
  end
  local okD, display = pcall(require, "kernel.display")
  local gpu = okD and type(display) == "table" and display.getGpu and display.getGpu()
  if not gpu or not gpu.get then
    return t.skip("term.read in a coroutine", "no GPU, or gpu.get unavailable")
  end

  local W, H = gpu.getResolution()
  local ROW = math.max(2, H - 6)
  -- Save the row and put it back through display.set, for the reason
  -- 70-screen-truth gives: a raw restore desyncs kernel.display's colour
  -- cache, which is the very bug that check hunts.
  local saved = {}
  for x = 1, W do
    local ok, ch, fg, bg = pcall(gpu.get, x, ROW)
    saved[x] = ok and { ch = ch, fg = fg, bg = bg } or nil
  end

  term.setCursor(1, ROW)
  local co = coroutine.create(function() return term.read(nil, false) end)
  local ok1, e1 = coroutine.resume(co)
  t.ok("term.read hands control back to its resumer while it waits (H-04)"
    .. (ok1 and "" or (" (raised: " .. tostring(e1) .. ")")),
    ok1 and coroutine.status(co) == "suspended")

  -- "h", "i", Enter, in the shape proc.tick resumes a process with.
  local kb = component.list("keyboard")() or "selftest"
  local feed = { { "key_down", kb, 104, 35 }, { "key_down", kb, 105, 23 },
                 { "key_down", kb, 13, 28 } }
  local line, err
  for _, ev in ipairs(feed) do
    if coroutine.status(co) ~= "suspended" then break end
    local okR, r = coroutine.resume(co, table.unpack(ev))
    if not okR then err = r; break end
    if coroutine.status(co) == "dead" then line = r end
  end
  t.eq("term.read returns the line it was fed" .. (err and (" (raised: " .. tostring(err) .. ")") or ""),
    "hi", line)

  local _, c1 = pcall(gpu.get, 1, ROW)
  local _, c2 = pcall(gpu.get, 2, ROW)
  t.ok("...and the glass shows what was typed (got " .. tostring(c1) .. tostring(c2) .. ")",
    c1 == "h" and c2 == "i")

  term.setCursor(cx, cy)
  for x = 1, W do
    local c = saved[x]
    if c then pcall(display.set, x, ROW, c.ch or " ", c.fg, c.bg) end
  end
  local okS, sm = pcall(require, "kernel.screen")
  if okS and sm and sm.invalidateAll then pcall(sm.invalidateAll) end
end
