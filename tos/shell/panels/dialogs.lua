-- ╔═════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Dialogs                         ║
-- ║                                                     ║
-- ║  Two registers of attention a developer can pick    ║
-- ║  between, whatever the message:                      ║
-- ║   • NON-INTRUSIVE - promptInput / promptSearch.     ║
-- ║       A single line on the status row. The screen   ║
-- ║       behind it stays put; the operator can ignore  ║
-- ║       it. Good for ordinary input (filenames, find).║
-- ║   • DIALOG BOX    - dialog / alert / confirm.       ║
-- ║       A titled, framed box painted over the middle  ║
-- ║       of the screen (the MS-DOS INSTALL/ERROR/      ║
-- ║       GENERAL look) that blocks until the operator  ║
-- ║       answers. It is a GENERAL primitive, not a     ║
-- ║       danger siren: use it for anything that wants  ║
-- ║       a focused yes/no/ack — installs, results,     ║
-- ║       "are you sure". The `style` only chooses the  ║
-- ║       colour; reserve the red (danger/error) styles ║
-- ║       for the genuinely destructive so the colour   ║
-- ║       still means something.                        ║
-- ╚═════════════════════════════════════════════════════╝

local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return require("computer").pullSignal(0.05)
end

-- Keep the END of a growing input visible: return the trailing `width`
-- columns of `text`. A field that just `:sub(1, W)`'d clipped the cursor
-- (and whatever you were typing — e.g. a long ".example" extension) off
-- the right edge once the line filled; this scrolls it left to follow the
-- cursor instead. Pure + testable.
function M.scrollTail(text, width)
  width = math.max(0, math.floor(width or 0))
  if #text <= width then return text end
  return text:sub(#text - width + 1)
end

-- Fit a prompt MESSAGE to the row, middle-ellipsized. The TAIL is what
-- carries the affordance ("? [y/N]: "), so an over-long message must
-- lose its middle, never its end — `pkg from-floppy` built an 88-column
-- question whose "[y/N]: " AND the echo of the typed answer both fell
-- off the right edge of an 80-column screen. Also reserves ~10 columns
-- so the typed input stays visible. Pure + testable.
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
    -- Reserve room for the prompt + the trailing cursor, then scroll the
    -- input so the cursor end stays on screen as it grows.
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

-- ============================================================
-- Intrusive modal box (pure geometry, then the interactive shells)
-- ============================================================

-- Word-wrap `text` to `width` columns. Honours explicit newlines and
-- hard-breaks any single word longer than the column. Pure + testable.
function M.wrapText(text, width)
  width = math.max(1, math.floor(width or 40))
  local lines = {}
  for rawLine in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    if rawLine == "" then
      lines[#lines + 1] = ""
    else
      local cur = ""
      for word in rawLine:gmatch("%S+") do
        while #word > width do            -- a single over-long token
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

-- Lay a row of buttons out as a single string + per-button spans
-- (1-based column ranges within the row). Used for both drawing and
-- click hit-testing, so the two can never drift. Pure + testable.
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

-- Centre a content box (contentW x contentH interior, excluding the
-- frame) on a W x H screen. Returns the outer rect {x,y,w,h}, clamped
-- to the screen. Pure + testable.
function M.boxRect(W, H, contentW, contentH)
  local w = math.min(W, math.max(1, contentW) + 4)   -- frame + 1 pad each side
  local h = math.min(H, math.max(1, contentH) + 2)   -- frame top + bottom
  local x = math.max(1, math.floor((W - w) / 2) + 1)
  local y = math.max(1, math.floor((H - h) / 2) + 1)
  return { x = x, y = y, w = w, h = h }
end

-- A dialog STYLE is pure presentation: which theme colour the frame and
-- title wear. It is NOT a claim that the dialog is dangerous — a dialog
-- box is a general way to talk to the operator (à la the MS-DOS
-- INSTALL/ERROR/GENERAL boxes), usable for anything from "package
-- installed" to "are you sure". Pick the style whose colour fits.
--   info/install -> accent (title colour)   general/plain -> neutral
--   warn -> warning (amber)                  danger/error  -> error (red)
local STYLES = {
  info    = { frame = "title",   title = "title"   },
  install = { frame = "title",   title = "title"   },
  warn    = { frame = "warning", title = "warning" },
  danger  = { frame = "error",   title = "error"   },
  error   = { frame = "error",   title = "error"   },
  general = { frame = "border",  title = "fg"      },
  plain   = { frame = "border",  title = "fg"      },
}
-- Default title shown when a caller gives a style but no explicit title.
local STYLE_TITLE = {
  info = "Information", install = "Install", warn = "Warning",
  danger = "Warning",  error = "Error",     general = "Message",
  plain = "Message",
}

-- Draw the dialog frame + contents and return the on-screen button rects
-- (absolute columns) for click hit-testing. Single-line DOS frame with a
-- centred "┤ Title ├" tab on the top border, an optional drop shadow, and
-- a focus-highlighted button row. `focus` is the 1-based index of the
-- highlighted button (or nil for none).
local function drawDialog(S, style, title, lines, labels, focus, shadow)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local meta = STYLES[style] or STYLES.general
  local frameColor = T[meta.frame] or T.border or T.fg
  local titleColor = T[meta.title] or T.fg
  title = title or ""
  -- Visual grammar rule 1: dialogs are MODAL, so they wear the
  -- double-line frame (+ the existing ▓-tinted shadow). Passive
  -- containers (tiles, panes) keep single-line — see ui.drawTile.
  local titleTab = (title ~= "") and ("╡ " .. title .. " ╞") or nil
  local titleCols = titleTab and (#title + 4) or 0   -- title is ASCII: bytes == cols

  local btnRow, spans, btnW = M.layoutButtons(labels)
  local contentW = math.max(titleCols - 2, btnW)
  for _, l in ipairs(lines) do contentW = math.max(contentW, #l) end
  local contentH = #lines + 2                 -- blank + button row

  local r = M.boxRect(W, H, contentW, contentH)
  local interior = r.w - 2                     -- columns between the side frames
  local bg = T.panel_bg or T.bg

  -- Drop shadow first (offset one row down / one col right), so the box
  -- paints on top. A near-black tint; on a black theme it just blends in
  -- harmlessly, on a lighter theme it reads as depth like the DOS look.
  if shadow ~= false then
    local sh = 0x1A1A1A
    D.set(r.x + 1, r.y + r.h, string.rep(" ", r.w), sh, sh)         -- bottom edge
    for row = 1, r.h do
      D.set(r.x + r.w, r.y + row, " ", sh, sh)                      -- right edge
    end
  end

  -- Frame. Each box char is one column but 3 bytes — draw whole runs and
  -- never byte-slice them (a column-count :sub would cut one in half and
  -- corrupt the line on a real Unicode GPU).
  D.set(r.x, r.y, "╔" .. string.rep("═", interior) .. "╗", frameColor, bg)
  for row = 1, r.h - 2 do
    D.set(r.x, r.y + row, "║" .. string.rep(" ", interior) .. "║", frameColor, bg)
  end
  D.set(r.x, r.y + r.h - 1, "╚" .. string.rep("═", interior) .. "╝", frameColor, bg)

  -- Centre the "╡ Title ╞" tab on the top border (interior >= titleCols by
  -- construction). Drawn whole, in the title colour, over the ═ run.
  if titleTab then
    local off = math.max(0, math.floor((interior - titleCols) / 2))
    D.set(r.x + 1 + off, r.y, titleTab, titleColor, bg)
  end

  -- Message lines (left-aligned, one pad column in).
  for i, l in ipairs(lines) do
    D.set(r.x + 2, r.y + i, l:sub(1, interior - 2), T.fg, bg)
  end

  -- Button row, centred in the interior.
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

-- Block until one of the buttons is chosen. Keyboard: Left/Right or Tab
-- move focus, Enter accepts, Esc picks `escIndex`, and any label's first
-- letter is a hotkey. Touch: a click inside a button rect picks it.
-- Returns the 1-based index of the chosen button.
local function dialogLoop(S, style, title, lines, labels, focus, escIndex, shadow)
  -- Build a first-letter hotkey map (lowercased).
  local hot = {}
  for i, l in ipairs(labels) do
    local c = l:sub(1, 1):lower()
    if c ~= "" and not hot[c] then hot[c] = i end
  end
  while true do
    local rects = drawDialog(S, style, title, lines, labels, focus, shadow)
    local sig, _, b, c = pullSignal()
    if sig == "key_down" then
      if c == 28 then return focus                       -- Enter
      -- ^Q cancels. Esc is still accepted, but it never arrives in real
      -- Minecraft (it closes the screen GUI), so a dialog that offered
      -- only Esc was a dialog with no way out but answering it.
      elseif c == 1 or b == 17 then return escIndex      -- ^Q / Esc
      elseif c == 203 then focus = (focus > 1) and (focus - 1) or #labels   -- Left
      elseif c == 205 or c == 15 then                    -- Right / Tab
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

--- GENERAL dialog box — the reusable primitive. Shows a titled, framed,
--- centred box with a wrapped message and one or more buttons, and blocks
--- until the operator picks one. Returns the chosen button's 1-based index.
--- `opts` = {
---   title    = string,                       -- centred on the top border
---   message  = string,                       -- body (word-wrapped)
---   buttons  = { "OK" } | {"Yes","No"} | ..., -- labels, left to right
---   style    = "info"|"install"|"warn"|"danger"|"error"|"general",
---   default  = index of the initially-focused button (default 1),
---   escIndex = index returned on Esc (default last button),
---   shadow   = false to suppress the drop shadow,
---   redraw   = function() called to repaint under the box afterwards,
--- }
--- Use this for ANY interruptive prompt — install confirmations, results,
--- "are you sure" — not only dangerous ones. For a quiet, non-intrusive
--- prompt that stays on the status row instead, use M.promptInput.
-- Block until the operator either cancels or types `word` exactly and
-- chooses Confirm. Returns true only for the latter.
--
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
      if c == 1 or b == 17 then                      -- ^Q / Esc
        if opts.redraw then opts.redraw() end
        return false
      elseif c == 28 then                            -- Enter
        if focus == 1 then
          if opts.redraw then opts.redraw() end
          return false
        elseif matched then
          if opts.redraw then opts.redraw() end
          return true
        end
        -- Focused on Confirm without the word: do nothing. Not an error
        -- state, just not an answer yet.
      elseif c == 203 then focus = (focus > 1) and (focus - 1) or #labels
      elseif c == 205 or c == 15 then
        focus = (focus < #labels) and (focus + 1) or 1
      elseif c == 14 then                            -- Backspace
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

-- Render "3 of 7" plus a bar, as two extra body lines. ASCII only: the
-- Release minifier and the 4-bit GPUs both cope badly with box-drawing
-- characters mid-string, and this has to survive both.
--
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

-- Convenience: a one-button acknowledgement box. Returns true once
-- dismissed. Defaults to the "info" style (override with opts.style or
-- opts.severity). opts: { title, style/severity, ok=label, shadow, redraw }.
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

-- Convenience: a yes/no box. Returns true for yes, false for no/cancel
-- (Esc and the No button both mean false). Defaults to the "danger" style
-- and focuses the safe (No) choice. opts: { title, style/severity,
-- yes=label, no=label, default="yes"|"no", shadow, redraw }.
--
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
    local shown = M.scrollTail(buf, W - 7)   -- "Find: " + cursor
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
