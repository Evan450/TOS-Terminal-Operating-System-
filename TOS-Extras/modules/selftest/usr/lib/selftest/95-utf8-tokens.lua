-- The syntax highlighter's tokens, painted on the real glass (fermi import
-- 350fd87; AUDIT 5, "THE EDITOR COUNTS BYTES WHERE THE SCREEN COUNTS
-- CHARACTERS", the code-position half).
--
-- shell/syntax.lua used to emit one token per BYTE for anything >= 0x80.
-- kernel.screen draws by CHARACTER, so a lone lead byte painted as a
-- garbage cell and the continuation byte, no character on its own, was
-- dropped: `local café = 1` lost its é. This paints the tokens one at a
-- time through a real kernel.screen display proxy, as the editor paints
-- them, advancing by the characters the screen draws. Then it reads the row
-- back with gpu.get. With the old tokenizer the é and ï cells are wrong.
--
-- Then the other half, the editor's column model: draw.lua's editTab used
-- to advance by BYTES, so from the first non-ASCII character its text, its
-- cursor and its scroll were off by a cell per extra byte. It measures in
-- cells since 2026-10-01 (textcol.lua). Here the real editTab paints the
-- line on the glass, gpu.get reads it back, and the cursor has to be in
-- the cell right after the last character; with the byte model it lands
-- two cells further on (é and ï are two bytes each).
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
    -- What the screen draws for a string: one cell per match of the same
    -- pattern kernel.screen splits on.
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
  if not okRun then error(err, 0) end

  local okDr, draw = pcall(require, "shell.panels.draw")
  if not (okDr and type(draw) == "table" and type(draw.editTab) == "function") then
    return t.skip("editor column model", "shell.panels.draw unavailable: " .. tostring(draw))
  end
  -- Distinct colours, so the cursor cell can be told from its neighbours
  -- whatever the GPU's palette rounds them to.
  local T = setmetatable({ fg = 0xFFFFFF, bg = 0x000000, sel_fg = 0x000000, sel_bg = 0xFFFFFF },
    { __index = function() return 0x808080 end })
  local tab = { type = "edit", lines = { line }, curRow = 1, curCol = #line + 1,
                viewTop = 1, viewLeft = 1, label = "selftest" }
  local okE, eerr = pcall(function()
    display.fill(1, 1, W, H, " ", 0xFFFFFF, 0x000000)
    draw.editTab({ D = proxy, T = T, W = W, H = H, tier = 1, padW = string.rep(" ", W) }, tab)
    local found
    for y = 1, H do
      local row = {}
      for x = 1, W do
        local ok, ch = pcall(gpu.get, x, y)
        row[x] = (ok and type(ch) == "string") and ch or " "
      end
      local text = table.concat(row)
      local i = text:find(line, 1, true)
      if i then found = { y = y, x = utf8.len(text:sub(1, i - 1)) + 1 }; break end
    end
    t.ok("the editor draws the line whole, one character per cell", found ~= nil)
    if found then
      local cx = found.x + utf8.len(line)
      local _, _, _, bgCur = pcall(gpu.get, cx, found.y)
      local _, _, _, bgPrev = pcall(gpu.get, cx - 1, found.y)
      t.ok(string.format("the cursor is the cell after the line's last character (cell %d)", cx),
        bgCur ~= nil and bgCur ~= bgPrev)
    end
  end)
  display.fill(1, 1, W, H, " ", 0xFFFFFF, 0x000000)
  if screen.invalidateAll then pcall(screen.invalidateAll) end
  if not okE then error(eerr, 0) end
end
