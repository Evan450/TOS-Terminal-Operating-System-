local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return require("computer").pullSignal(0.05)
end

function M.scrollTail(text, width)
  width = math.max(0, math.floor(width or 0))
  if #text <= width then return text end
  return text:sub(#text - width + 1)
end

function M.fitPrompt(msg, width)
  msg = tostring(msg or "")
  local budget = math.max(12, math.floor(width or 80) - 10)
  if #msg <= budget then return msg end
  local tail = math.min(16, budget - 8)
  local head = budget - tail - 3
  return msg:sub(1, head) .. "..." .. msg:sub(#msg - tail + 1)
end

function M.promptInput(S, msg, maxLen, isPassword)
  local D, T, W = S.D, S.T, S.W
  local OUT_ROW = S.OUT_ROW
  msg = M.fitPrompt(msg, W)
  local buf = ""
  while true do
    D.fill(1, OUT_ROW, W, 1, " ", T.fg, T.bg)
    local disp = isPassword and string.rep("*", #buf) or buf

    local shown = M.scrollTail(disp, W - #msg - 1)
    D.set(1, OUT_ROW, (msg .. shown .. "_"):sub(1, W), T.title, T.bg)
    local sig, _, ch2, co2 = pullSignal()
    if sig == "key_down" then
      if co2 == 28 then return buf
      elseif ch2 == 17 then return nil
      elseif co2 == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
      elseif ch2 and ch2 >= 32 and ch2 < 127 and #buf < (maxLen or 64) then
        buf = buf .. string.char(ch2)
      end
    elseif sig == "clipboard" and type(ch2) == "string" and not isPassword then
      buf = (buf .. ch2:gsub("\n", "")):sub(1, maxLen or 64)
    end
  end
end

function M.wrapText(text, width)
  width = math.max(1, math.floor(width or 40))
  local lines = {}
  for rawLine in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    if rawLine == "" then
      lines[#lines + 1] = ""
    else
      local cur = ""
      for word in rawLine:gmatch("%S+") do
        while #word > width do
          if cur ~= "" then lines[#lines + 1] = cur; cur = "" end
          lines[#lines + 1] = word:sub(1, width)
          word = word:sub(width + 1)
        end
        if cur == "" then cur = word
        elseif #cur + 1 + #word <= width then cur = cur .. " " .. word
        else lines[#lines + 1] = cur; cur = word end
      end
      if cur ~= "" then lines[#lines + 1] = cur end
    end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

function M.layoutButtons(labels)
  local parts, spans, col = {}, {}, 1
  for i, lbl in ipairs(labels) do
    if i > 1 then parts[#parts + 1] = "   "; col = col + 3 end
    local cell = "[ " .. lbl .. " ]"
    parts[#parts + 1] = cell
    spans[i] = { s = col, e = col + #cell - 1 }
    col = col + #cell
  end
  return table.concat(parts), spans, (col - 1)
end

function M.boxRect(W, H, contentW, contentH)
  local w = math.min(W, math.max(1, contentW) + 4)
  local h = math.min(H, math.max(1, contentH) + 2)
  local x = math.max(1, math.floor((W - w) / 2) + 1)
  local y = math.max(1, math.floor((H - h) / 2) + 1)
  return { x = x, y = y, w = w, h = h }
end

local STYLES = {
  info    = { frame = "title",   title = "title"   },
  install = { frame = "title",   title = "title"   },
  warn    = { frame = "warning", title = "warning" },
  danger  = { frame = "error",   title = "error"   },
  error   = { frame = "error",   title = "error"   },
  general = { frame = "border",  title = "fg"      },
  plain   = { frame = "border",  title = "fg"      },
}

local STYLE_TITLE = {
  info = "Information", install = "Install", warn = "Warning",
  danger = "Warning",  error = "Error",     general = "Message",
  plain = "Message",
}

local function drawDialog(S, style, title, lines, labels, focus, shadow)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local meta = STYLES[style] or STYLES.general
  local frameColor = T[meta.frame] or T.border or T.fg
  local titleColor = T[meta.title] or T.fg
  title = title or ""

  local titleTab = (title ~= "") and ("╡ " .. title .. " ╞") or nil
  local titleCols = titleTab and (#title + 4) or 0

  local btnRow, spans, btnW = M.layoutButtons(labels)
  local contentW = math.max(titleCols - 2, btnW)
  for _, l in ipairs(lines) do contentW = math.max(contentW, #l) end
  local contentH = #lines + 2

  local r = M.boxRect(W, H, contentW, contentH)
  local interior = r.w - 2
  local bg = T.panel_bg or T.bg

  if shadow ~= false then
    local sh = 0x1A1A1A
    D.set(r.x + 1, r.y + r.h, string.rep(" ", r.w), sh, sh)
    for row = 1, r.h do
      D.set(r.x + r.w, r.y + row, " ", sh, sh)
    end
  end

  D.set(r.x, r.y, "╔" .. string.rep("═", interior) .. "╗", frameColor, bg)
  for row = 1, r.h - 2 do
    D.set(r.x, r.y + row, "║" .. string.rep(" ", interior) .. "║", frameColor, bg)
  end
  D.set(r.x, r.y + r.h - 1, "╚" .. string.rep("═", interior) .. "╝", frameColor, bg)

  if titleTab then
    local off = math.max(0, math.floor((interior - titleCols) / 2))
    D.set(r.x + 1 + off, r.y, titleTab, titleColor, bg)
  end

  for i, l in ipairs(lines) do
    D.set(r.x + 2, r.y + i, l:sub(1, interior - 2), T.fg, bg)
  end

  local rowY = r.y + #lines + 2
  local off = math.max(0, math.floor((interior - btnW) / 2))
  local baseX = r.x + 1 + off
  local rects = {}
  for i, lbl in ipairs(labels) do
    local s = spans[i]
    local cell = btnRow:sub(s.s, s.e)
    local focused = (i == focus)
    local fg = focused and (T.selected_fg or bg) or T.fg
    local cbg = focused and (T.selected_bg or T.highlight) or bg
    D.set(baseX + s.s - 1, rowY, cell, fg, cbg)
    rects[i] = { x1 = baseX + s.s - 1, x2 = baseX + s.e - 1, y = rowY, label = lbl }
  end
  return rects
end

local function dialogLoop(S, style, title, lines, labels, focus, escIndex, shadow)

  local hot = {}
  for i, l in ipairs(labels) do
    local c = l:sub(1, 1):lower()
    if c ~= "" and not hot[c] then hot[c] = i end
  end
  while true do
    local rects = drawDialog(S, style, title, lines, labels, focus, shadow)
    local sig, _, b, c = pullSignal()
    if sig == "key_down" then
      if c == 28 then return focus

      elseif c == 1 or b == 17 then return escIndex
      elseif c == 203 then focus = (focus > 1) and (focus - 1) or #labels
      elseif c == 205 or c == 15 then
        focus = (focus < #labels) and (focus + 1) or 1
      elseif b and b >= 32 and b < 127 then
        local i = hot[string.char(b):lower()]
        if i then return i end
      end
    elseif sig == "touch" and type(b) == "number" and type(c) == "number" then
      for i, rt in ipairs(rects) do
        if c == rt.y and b >= rt.x1 and b <= rt.x2 then return i end
      end
    end
  end
end

function M.dialog(S, opts)
  opts = opts or {}
  local style  = opts.style or opts.severity or "general"
  local title  = opts.title or STYLE_TITLE[style] or "Message"
  local labels = opts.buttons or { "OK" }
  local lines  = M.wrapText(opts.message or opts.body or "", math.max(16, (S.W or 50) - 8))
  local focus  = opts.default or 1
  local escIdx = opts.escIndex or #labels
  local pick = dialogLoop(S, style, title, lines, labels, focus, escIdx, opts.shadow)
  if opts.redraw then opts.redraw() end
  return pick
end

function M.alert(S, message, opts)
  opts = opts or {}
  M.dialog(S, {
    style   = opts.style or opts.severity or "info",
    title   = opts.title,
    message = opts.message or message,
    buttons = { opts.ok or "OK" },
    default = 1, escIndex = 1,
    shadow  = opts.shadow, redraw = opts.redraw,
  })
  return true
end

function M.confirm(S, message, opts)
  opts = opts or {}
  local pick = M.dialog(S, {
    style    = opts.style or opts.severity or "danger",
    title    = opts.title,
    message  = opts.message or message,
    buttons  = { opts.yes or "Yes", opts.no or "No" },
    default  = (opts.default == "yes") and 1 or 2,
    escIndex = 2,
    shadow   = opts.shadow, redraw = opts.redraw,
  })
  return pick == 1
end

function M.promptSearch(S, currentTerm)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local buf = currentTerm or ""
  while true do
    D.fill(1, H, W, 1, " ", T.fg, T.bg)
    local shown = M.scrollTail(buf, W - 7)
    D.set(1, H, ("Find: " .. shown .. "_"):sub(1, W), T.title, T.bg)
    local sig, _, ch2, co2 = pullSignal()
    if sig == "key_down" then
      if co2 == 28 then return #buf > 0 and buf or nil
      elseif ch2 == 17 then return currentTerm
      elseif co2 == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
      elseif ch2 and ch2 >= 32 and ch2 < 127 then buf = buf .. string.char(ch2)
      end
    end
  end
end

return M
