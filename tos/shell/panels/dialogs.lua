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

--! Same frame, same title tab, same shadow, same button styling as every
--! other dialog -- it calls drawDialog like dialogLoop does, and adds
--! nothing to the visual grammar. The only difference is what it takes
--! to answer yes.
--!
--! WHY THIS EXISTS RATHER THAN A y/N BOX. Typing a word is what defeats
--! muscle memory, and the operations using it (flashing an EEPROM,
--! forcing a non-BIOS image onto one) fail by leaving a machine that no
--! longer boots. Safe-choice-first helps a reflex press; it does nothing
--! for a confident wrong press, and these are the cases where the
--! operator being confident is the problem.
--!
--! No first-letter hotkeys here, unlike dialogLoop: every printable key
--! belongs to the text field, or the word could never be typed.
function M.confirmTyped(S, message, word, opts)
  opts = opts or {}
  local style  = opts.style or opts.severity or "danger"
  local title  = opts.title or STYLE_TITLE[style] or "Confirm"
  local labels = { opts.no or "Cancel", opts.yes or "Confirm" }
  local body   = M.wrapText(opts.message or message or "",
                            math.max(16, (S.W or 50) - 8))
  local buf, focus = "", 1
  local maxLen = math.max(#word + 8, 16)

  while true do
    --! Constant line COUNT in every state. Adding or removing a line as
    --! the text matched would resize the box mid-typing, and a dialog
    --! that jumps under the cursor is how a misclick happens.
    local lines = {}
    for _, l in ipairs(body) do lines[#lines + 1] = l end
    lines[#lines + 1] = ""
    lines[#lines + 1] = 'Type  ' .. word .. '  to confirm:'
    lines[#lines + 1] = "  " .. buf .. "_"
    local matched = (buf == word)
    lines[#lines + 1] = matched and "  the word matches - choose Confirm"
                                 or "  (Confirm stays inert until it matches)"

    local rects = drawDialog(S, style, title, lines, labels, focus, opts.shadow)
    local sig, _, b, c = pullSignal()

    if sig == "key_down" then
      if c == 1 or b == 17 then
        if opts.redraw then opts.redraw() end
        return false
      elseif c == 28 then
        if focus == 1 then
          if opts.redraw then opts.redraw() end
          return false
        elseif matched then
          if opts.redraw then opts.redraw() end
          return true
        end

      elseif c == 203 then focus = (focus > 1) and (focus - 1) or #labels
      elseif c == 205 or c == 15 then
        focus = (focus < #labels) and (focus + 1) or 1
      elseif c == 14 then
        if #buf > 0 then buf = buf:sub(1, -2) end
      elseif b and b >= 32 and b < 127 and #buf < maxLen then
        buf = buf .. string.char(b)
      end

    elseif sig == "touch" and type(b) == "number" and type(c) == "number" then
      for i, rt in ipairs(rects) do
        if c == rt.y and b >= rt.x1 and b <= rt.x2 then
          if i == 1 then
            if opts.redraw then opts.redraw() end
            return false
          elseif matched then
            if opts.redraw then opts.redraw() end
            return true
          else
            --! A click on an inert Confirm moves focus there rather than
            --! doing nothing at all, so the button is visibly the thing
            --! waiting on them.
            focus = 2
          end
        end
      end

    elseif sig == "clipboard" and type(b) == "string" then
      buf = (buf .. b:gsub("\n", "")):sub(1, maxLen)
    end
  end
end

--! Exists because a run of yes/no questions with no visible end is the
--! thing operators start clicking through. Telling them there are three
--! left costs two lines and buys an answer they actually meant.
function M.progressLines(index, total, width)
  if type(index) ~= "number" or type(total) ~= "number" or total < 1 then
    return {}
  end
  width = math.max(10, math.min(width or 30, 40))
  --! Counts the question you are ON, not the ones behind you. Measuring
  --! answered-so-far was defensible and read as broken: the last prompt
  --! sat at 3-of-4 filled and the bar never completed, no matter what
  --! you installed. "4 of 4" with a bar that is not full invites the
  --! reasonable conclusion that something is stuck.
  --!
  --! So the first prompt shows one step of progress rather than an empty
  --! trough, and the last one is full while it is still on screen -- the
  --! run finishes visibly, before the box goes away.
  local seen = math.max(0, math.min(index, total))
  local filled = math.floor((seen / total) * width + 0.5)
  return {
    "",
    string.format("%d of %d   [%s%s]", index, total,
      string.rep("#", filled), string.rep("-", width - filled)),
  }
end

function M.dialog(S, opts)
  opts = opts or {}
  local style  = opts.style or opts.severity or "general"
  local title  = opts.title or STYLE_TITLE[style] or "Message"
  local labels = opts.buttons or { "OK" }
  local lines  = M.wrapText(opts.message or opts.body or "", math.max(16, (S.W or 50) - 8))
  --! Appended to the body rather than drawn separately, so it lands
  --! inside the same frame with no change to drawDialog.
  if opts.progress then
    for _, l in ipairs(M.progressLines(opts.progress.index, opts.progress.total,
                                       (S.W or 50) - 16)) do
      lines[#lines + 1] = l
    end
  end
  local focus  = opts.default or 1
  local escIdx = opts.escIndex or #labels
  local pick = dialogLoop(S, style, title, lines, labels, focus, escIdx, opts.shadow)
  --! `redraw == false` means "another box follows immediately -- leave
  --! the screen alone". Repainting the whole shell between questions is
  --! what made a sequence flicker: box, full redraw, box again, one row
  --! lower or in a different place. Only the LAST one in a run repaints.
  if opts.redraw and opts.redraw ~= false then opts.redraw() end
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

--! NO COMES FIRST. Keyboard focus already started on the safe choice, but
--! the button ORDER was { Yes, No } -- so the leftmost button, the one a
--! click-through or a stray mouse press lands on, was the destructive
--! one. Someone dismissing a dialog without reading it should get the
--! outcome that changes nothing.
--!
--! The return value is unchanged (true means yes), so callers did not
--! need touching -- which is also the trap: the index-to-meaning mapping
--! flipped inside here and nowhere else. test_dialog_confirm.lua pins
--! both the order and the mapping.
function M.confirm(S, message, opts)
  opts = opts or {}
  local pick = M.dialog(S, {
    style    = opts.style or opts.severity or "danger",
    title    = opts.title,
    message  = opts.message or message,
    buttons  = { opts.no or "No", opts.yes or "Yes" },
    default  = (opts.default == "yes") and 2 or 1,
    escIndex = 1,
    progress = opts.progress,
    shadow   = opts.shadow, redraw = opts.redraw,
  })
  return pick == 2
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
