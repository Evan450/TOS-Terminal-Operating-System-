

























return function(t)
  local okT, term = pcall(require, "compat.term")
  if not okT or type(term) ~= "table" then
    return t.skip("compat.term", "does not load here: " .. tostring(term))
  end

  
  local y = coroutine.isyieldable and coroutine.isyieldable()
  t.ok("coroutine.isyieldable() in kernel context is a boolean", type(y) == "boolean")
  
  
  if t.note then
    t.note("isyieldable() in kernel context: " .. tostring(y) .. " -- term.read at boot "
      .. (y and "yields to the host; its bounded raw-pull branch is unreachable here"
            or "takes the bounded raw pull"))
  end

  
  local scr = term.screen()
  t.ok("term.screen() is a real screen address",
    scr ~= nil and component.type(scr) == "screen")
  
  
  
  
  local okG, tg = pcall(term.gpu)
  local okW, w = pcall(function() return tg.getResolution() end)
  t.ok("term.gpu() answers with a usable proxy" .. (okW and "" or (" (" .. tostring(w) .. ")")),
    okG and type(tg) == "table" and okW and type(w) == "number")

  
  local gaddr = component.list("gpu")()
  local raw = gaddr and component.proxy(gaddr)
  local mt = raw and type(raw.set) == "table" and getmetatable(raw.set)
  t.ok("a raw GPU method here is a callable table, not a function",
    type(mt) == "table" and mt.__call ~= nil)
  
  
  local okC, rw = pcall(term._gpuForCaps, { gpu = true })
  t.ok("a display-cap term.gpu() wraps setBackground (marks the glass dirty)",
    okC and type(rw) == "table" and type(rw.setBackground) == "function")

  
  local cx, cy = term.getCursor()
  term.setCursor(7, 3)
  local nx, ny = term.getCursor()
  t.ok("setCursor/getCursor round-trip with no caller seat", nx == 7 and ny == 3)
  term.setCursor(cx, cy)

  
  
  if not (t.cfg and t.cfg.screen) then
    return t.skip("term.read in a coroutine",
      "it draws: add screen=true to selftest.on")
  end
  
  
  
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
