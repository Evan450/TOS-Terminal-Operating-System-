













return function(t)
  if not (t.cfg and t.cfg.screen) then
    return t.skip("utf8 tokens", "it draws: add screen=true to selftest.on")
  end
  local okS, syntax = pcall(require, "shell.syntax")
  if not okS or type(syntax) ~= "table" or type(syntax.tokenize) ~= "function" then
    return t.skip("utf8 tokens", "shell.syntax unavailable: " .. tostring(syntax))
  end
  local okD, display = pcall(require, "kernel.display")
  local gpu = okD and type(display) == "table" and display.getGpu and display.getGpu()
  if not gpu or not gpu.get then
    return t.skip("utf8 tokens", "no GPU, or gpu.get unavailable")
  end
  local okM, screen = pcall(require, "kernel.screen")
  local proxy = okM and type(screen) == "table" and screen.displayProxy
    and screen.displayProxy(1)
  if not proxy or type(proxy.set) ~= "function" then
    return t.skip("utf8 tokens", "no kernel.screen display proxy before seat init")
  end

  local line = "local café = naïve -- ok"
  local tokens = syntax.tokenize(line)
  local whole = true
  for _, tok in ipairs(tokens) do
    if utf8.len(tok.text) == nil then whole = false end
  end
  t.ok("every token is whole UTF-8", whole)

  local W, H = gpu.getResolution()
  local ROW = math.max(2, H - 6)
  local saved = {}
  for x = 1, W do
    local ok, ch, fg, bg = pcall(gpu.get, x, ROW)
    saved[x] = ok and { ch = ch, fg = fg, bg = bg } or nil
  end

  local okRun, err = pcall(function()
    display.fill(1, ROW, W, 1, " ", 0xFFFFFF, 0x000000)
    
    
    local UTF8 = "[\0-\127\194-\255][\128-\191]*"
    local x = 1
    for _, tok in ipairs(tokens) do
      proxy.set(x, ROW, tok.text, 0xFFFFFF, 0x000000)
      local _, n = tok.text:gsub(UTF8, "")
      x = x + n
    end
    local col, bad = 0, nil
    for _, cp in utf8.codes(line) do
      col = col + 1
      local ok, ch = pcall(gpu.get, col, ROW)
      if not (ok and ch == utf8.char(cp)) and not bad then
        bad = string.format("column %d: want %q, got %q", col, utf8.char(cp), tostring(ch))
      end
    end
    t.ok("tokens painted one at a time read back as the line ("
      .. (bad or ("all " .. col .. " cells")) .. ")", bad == nil)
  end)

  for x = 1, W do
    local c = saved[x]
    if c then pcall(display.set, x, ROW, c.ch or " ", c.fg, c.bg) end
  end
  if screen.invalidateAll then pcall(screen.invalidateAll) end
  t.skip("editor column model",
    "draw.lua still advances by bytes (TODO: THE EDITOR COUNTS BYTES WHERE THE SCREEN COUNTS CHARACTERS)")
  if not okRun then error(err, 0) end
end
