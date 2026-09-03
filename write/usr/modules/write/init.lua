-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: write — a word processor for TOS                ║
-- ║                                                              ║
-- ║  TOS already has `edit`, a text editor. This is not that.    ║
-- ║  The difference is the PAGE: `write` knows how wide a        ║
-- ║  printed line is in pixels, how many lines fit on a sheet,   ║
-- ║  and therefore where your document breaks — live, in the     ║
-- ║  rail, while you type. That is the one thing an editor       ║
-- ║  cannot tell you and the only reason to have a second        ║
-- ║  program that edits text.                                    ║
-- ║                                                              ║
-- ║  It DEPENDS on the printer driver package rather than        ║
-- ║  recommending it, because the page model lives in the        ║
-- ║  driver's printerfmt.lua and without it there is no page —   ║
-- ║  just `edit` with extra steps. The printer HARDWARE is a     ║
-- ║  different matter and is soft: compose, paginate and save    ║
-- ║  all work with no printer in the world, and F3 says so       ║
-- ║  rather than pretending.                                     ║
-- ║                                                              ║
-- ║  The model (write/doc.lua) is pure and unit-tested off-box   ║
-- ║  by modules/write/test_write.lua. This file is drawing,      ║
-- ║  keys and files.                                             ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local D_        = require("write.doc")
local fmt       = require("printerfmt")

-- The driver is optional AT RUNTIME even though the package is a hard
-- dependency: `pkg disable printer` leaves the files in place but the
-- machine may still have no printer, and this program must open anyway.
local okP, P = pcall(require, "printer")
if not okP then P = nil end

-- ── Screen ────────────────────────────────────────────────────────────
-- Same kit stock/calc use, duplicated rather than shared so installing
-- `write` pulls in nothing but the driver.
local function screen(o, minW, minH)
  local gpuAddr = component.list and component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return nil end
  local okG, gpu = pcall(component.proxy, gpuAddr)
  if not okG or not gpu then o("Cannot open the GPU.", 0xFF0000); return nil end
  local W, H = gpu.getResolution()
  if not W or not H then o("Cannot detect screen size.", 0xFF0000); return nil end
  if W < minW or H < minH then
    o(string.format("Screen too small: need %dx%d, have %dx%d.", minW, minH, W, H), 0xFF6600)
    return nil
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number")
    and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, border = 0xFFFFFF, title = 0xFFFFFF,
    hi = 0xFFFFFF, warn = 0xFFFFFF, bg = 0x000000, sel = 0xFFFFFF,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA, bg = 0x000000,
    border = tier == 2 and 0x55FFFF or 0x00FFFF,
    title  = tier == 2 and 0xFFFF55 or 0xFFFF00,
    hi     = tier == 2 and 0x55FF55 or 0x00FF00,
    warn   = tier == 2 and 0xFF5555 or 0xFF4040,
    sel    = tier == 2 and 0x336699 or 0x2A4A6A,
  }
  local Dv = { W = W, H = H, tier = tier, T = T, gpu = gpu }
  function Dv.set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  function Dv.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  function Dv.clear() Dv.fill(1, 1, W, H, " ", T.fg, T.bg) end
  return Dv
end

local function pad(s, w)
  s = tostring(s or "")
  if #s > w then return s:sub(1, math.max(1, w - 1)) .. "…" end
  return s .. string.rep(" ", w - #s)
end

-- ── Keys ──────────────────────────────────────────────────────────────
-- F-keys rather than Ctrl chords, and not only for period flavour: the
-- panels shell already owns ^B (background) and ^T (task switch), so a
-- word processor reaching for them would be fighting the seat for its
-- own keyboard. ^S is kept for save because everyone's hands do it.
--
-- #FIX (real Minecraft, 2026-08-11) — QUIT IS F10 OR ^Q, NOT Esc.
-- Esc belongs to the game: it closes the screen GUI, so the keypress
-- never reaches the computer and the player just walks away from a
-- terminal that is still running this editor. Shipping Esc as the only
-- way out made `write` genuinely unexitable in real Minecraft.
-- ^Q rather than plain Q because this is an editor — Q types a Q. See
-- the convention block in tos/shell/panels/keymap.lua.
local K = {
  F1 = 59, F2 = 60, F3 = 61, F4 = 62, F5 = 63, F6 = 64, F7 = 65, F10 = 68,
  ESC = 1, ENTER = 28, BACK = 14, DEL = 211, TAB = 15,
  UP = 200, DOWN = 208, LEFT = 203, RIGHT = 205,
  PGUP = 201, PGDN = 209, HOME = 199, END = 207,
}
local CTRL_Q = 17   -- character code, not a scancode

-- Shared with the shell (tos/shell/keys.lua), so ^Q closes this the same
-- way it closes everything else TOS ships, and an operator who rebinds
-- `quit` with `keys set` has it reach here too. Falls back to the coded
-- defaults when the module is unavailable (an older base image, or the
-- off-box tests).
local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end

--- True when this keypress means "get me out of here". Esc is still
--- honoured on the chance a future OC build delivers it, but it is never
--- the only way.
local function isQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return code == K.F10 or ch == CTRL_Q or code == K.ESC
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "F10"
end

local function pullKey(timeout)
  local e = { computer.pullSignal(timeout) }
  if e[1] == "key_down" then return e[3], e[4] end
  -- A kernel interrupt reads as a quit request. Reported as ^Q rather
  -- than Esc so every downstream check sees the key that actually works.
  if e[1] == "interrupted" then return CTRL_Q, nil end
  return nil, nil
end

-- ── Files ─────────────────────────────────────────────────────────────
-- Everything goes through the sandbox's session-bound `fs`, so a
-- document is always read and written with the calling user's
-- permissions. A save that the filesystem refuses is reported, never
-- swallowed — the worst outcome for a word processor is an operator who
-- believes their work is on disk.
local function haveFs() return fs and fs.readFile and fs.writeFile end

local MAX_DOC_BYTES = 64 * 1024

local function loadFile(path)
  if not haveFs() then return nil, "no filesystem access" end
  if not fs.exists(path) then return nil, nil end     -- a new document
  local ok, data = pcall(fs.readFile, path)
  if not ok or not data then return nil, tostring(data or "cannot read") end
  if #data > MAX_DOC_BYTES then
    return nil, string.format("%d bytes; the limit is %d", #data, MAX_DOC_BYTES)
  end
  return data
end

local function saveFile(path, text)
  if not haveFs() then return false, "no filesystem access" end
  local ok, err = pcall(fs.writeFile, path, text)
  if not ok then return false, tostring(err or "write failed") end
  return true
end

-- ══════════════════════════════════════════════════════════════════════
-- The word processor
-- ══════════════════════════════════════════════════════════════════════
local function run(path, o)
  local Dv = screen(o, 46, 12)
  if not Dv then return end
  local T, W, H = Dv.T, Dv.W, Dv.H

  local raw, lErr = loadFile(path)
  if lErr then o("Cannot open " .. path .. ": " .. lErr, 0xFF5555); return end
  local isNew = (raw == nil)

  local buf     = D_.toBuffer(raw or "")
  local cy, cx  = 1, 1        -- cursor line, column (1 = before first char)
  local top     = 1           -- first visible buffer line
  local dirty   = false
  local status  = isNew and ("New document: " .. path) or nil
  local pageView = false
  local pvPage  = 1

  -- Layout is recomputed lazily, not on every keystroke: wrapping a
  -- whole document is the expensive thing this program does, and doing
  -- it per character on a T1 turns typing into a slideshow. `stale`
  -- marks it; draw() resolves it once per frame.
  local parsed, pages, stats
  local stale = true

  -- Measure with the attached printer where there is one, so the page
  -- breaks the rail shows are the breaks the paper will have. With no
  -- printer we fall back to the transcribed width table and SAY so —
  -- an estimated break and a real one are not equally trustworthy.
  local measure, maxWidth, metricSrc = fmt.width, fmt.MAX_WIDTH, "estimated"
  if P and P.available() then
    measure  = P.measurer()
    maxWidth = P.maxWidth()
    local _, src = P.width("M")
    if src == "component" then metricSrc = "printer" end
  end

  local function relayout()
    if not stale then return end
    parsed = D_.parse(D_.serialize(buf))
    pages  = D_.layout(parsed, { measure = measure, maxWidth = maxWidth })
    stats  = D_.stats(parsed, pages)
    stale  = false
  end

  local function touch() dirty = true; stale = true end

  -- ── Drawing ────────────────────────────────────────────────────────
  local bodyTop, bodyBottom = 3, H - 2
  local bodyRows = bodyBottom - bodyTop + 1

  local function drawHeader()
    relayout()
    Dv.fill(1, 1, W, 1, " ", T.bg, T.border)
    local name = path:match("[^/]+$") or path
    Dv.set(2, 1, "WRITE  " .. name .. (dirty and " *" or ""), T.bg, T.border)
    local title = parsed.title or "(untitled)"
    local right = "Title: " .. title
    if #right + 12 < W then
      Dv.set(math.max(12, W - #right - 1), 1, right, T.bg, T.border)
    end

    -- The rail. This is the program's reason to exist, so it says the
    -- things a plain editor cannot: which sheet the cursor is on, how
    -- full that sheet is, and what the whole document will cost.
    local page = D_.pageFor(pages, cy) or 1
    local _, lineOnPage = D_.locate(pages, cy)
    local cost = D_.cost(pages, 1)
    local rail = string.format(
      "page %d/%d  line %s/%d  %d words  %d sheet(s), %d black, %d colour  [%s widths]",
      page, #pages,
      lineOnPage and tostring(lineOnPage) or "-", fmt.MAX_LINES,
      stats.words, cost.paper, cost.black, cost.color, metricSrc)
    Dv.set(1, 2, pad(rail, W), T.dim, T.bg)
  end

  local function drawSource()
    Dv.fill(1, bodyTop, W, bodyRows, " ", T.fg, T.bg)
    -- Where each sheet begins, drawn as a rule across the text. This is
    -- the page break made visible in the place you are actually typing,
    -- rather than in a separate preview you have to go and look at.
    local breakAt = {}
    for p = 2, #pages do
      local first = pages[p][1]
      if first and first.src then breakAt[first.src] = p end
    end
    for i = 0, bodyRows - 1 do
      local n = top + i
      local line = buf[n]
      if line == nil then break end
      local y = bodyTop + i
      if breakAt[n] then
        -- A rule ABOVE the line that starts the new sheet.
        Dv.set(1, y, pad(string.rep("─", math.max(0, W - 12))
          .. string.format(" page %d ", breakAt[n]), W), T.border, T.bg)
      else
        local isDirective = line:sub(1, 1) == "." and line:sub(1, 2) ~= ".."
        local fg = isDirective and T.title or T.fg
        -- The gutter carries the source line number; a document that
        -- warns about line 14 is useless if you cannot find line 14.
        Dv.set(1, y, string.format("%4d ", n), T.dim, T.bg)
        Dv.set(6, y, pad(line, W - 5), fg, T.bg)
      end
    end
    -- Cursor: rendered as an inverted cell rather than a hardware
    -- cursor, which OC does not have.
    local cyRow = bodyTop + (cy - top)
    if cyRow >= bodyTop and cyRow <= bodyBottom then
      local ch = buf[cy]:sub(cx, cx)
      if ch == "" then ch = " " end
      local col = 6 + (cx - 1)
      if col <= W then Dv.set(col, cyRow, ch, T.bg, T.hi) end
    end
  end

  local function drawPageView()
    Dv.fill(1, bodyTop, W, bodyRows, " ", T.fg, T.bg)
    local page = pages[pvPage] or {}
    Dv.set(2, bodyTop, string.format("── sheet %d of %d ──", pvPage, #pages), T.title, T.bg)
    for i, entry in ipairs(page) do
      local y = bodyTop + i
      if y > bodyBottom then break end
      local text = entry.text
      -- Centring is shown centred. The printed page is 164 PIXELS wide
      -- and the screen is 80 CELLS, so this is an impression of the
      -- layout and not a facsimile — which is exactly why the rail
      -- reports numbers and this view does not claim to be WYSIWYG.
      local inner = W - 4
      if entry.align == "center" then
        text = string.rep(" ", math.max(0, math.floor((inner - #text) / 2))) .. text
      end
      Dv.set(3, y, pad(text, inner), entry.color and T.warn or T.fg, T.bg)
    end
    if #page == 0 then
      Dv.set(3, bodyTop + 1, "(this sheet is empty)", T.dim, T.bg)
    end
  end

  local function drawFooter()
    if status then
      Dv.set(1, H - 1, pad(status, W), T.hi, T.bg)
    else
      local warn = parsed.warnings[1]
      if warn then
        Dv.set(1, H - 1, pad(string.format("line %d: %s", warn.line, warn.text), W),
          T.warn, T.bg)
      else
        Dv.fill(1, H - 1, W, 1, " ", T.fg, T.bg)
      end
    end
    local help = pageView
      and ("F5 edit · PgUp/PgDn sheet · F3 print · " .. quitLabel() .. " quit")
      or  ("F1 help · F2 save · F3 print · F4 title · F5 pages · F6 break · F7 centre · "
           .. quitLabel() .. " quit")
    if #help > W - 2 then
      help = "F1 help · F2 save · F3 print · F5 pages · " .. quitLabel() .. " quit"
    end
    Dv.fill(1, H, W, 1, " ", T.bg, T.border)
    Dv.set(2, H, pad(help, W - 2), T.bg, T.border)
  end

  local function draw()
    relayout()
    Dv.clear()
    drawHeader()
    if pageView then drawPageView() else drawSource() end
    drawFooter()
  end

  -- ── Modal helpers ──────────────────────────────────────────────────
  local function prompt(label, default)
    local s = tostring(default or "")
    while true do
      Dv.fill(1, H - 1, W, 1, " ", T.fg, T.bg)
      Dv.set(1, H - 1, pad(label .. " " .. s .. "_", W), T.title, T.bg)
      local ch, code = pullKey()
      if code == K.ENTER then return s end
      -- ^Q cancels, not Esc: Esc never arrives (see the key block above).
      if isQuit(ch, code) then return nil end
      if code == K.BACK then s = s:sub(1, -2)
      elseif ch and ch >= 32 and ch < 127 then s = s .. string.char(ch) end
    end
  end

  local function confirm(question)
    Dv.fill(1, H - 1, W, 1, " ", T.fg, T.bg)
    Dv.set(1, H - 1, pad(question .. "  (Y/N)", W), T.warn, T.bg)
    while true do
      local ch, code = pullKey()
      if isQuit(ch, code) then return false end
      if ch then
        local c = string.char(ch):lower()
        if c == "y" then return true end
        if c == "n" then return false end
      end
    end
  end

  local function showHelp()
    Dv.fill(1, bodyTop, W, bodyRows, " ", T.fg, T.bg)
    local lines = {
      "WRITE — a word processor for TOS",
      "",
      "The rail at the top is the point: it shows which printed",
      "sheet the cursor is on, how full that sheet is, and what",
      "the document will cost in paper and ink.",
      "",
      "Formatting rides on DOT COMMANDS in column one, so the",
      "file stays plain text you can cat, grep and mail:",
      "",
      "  .title My Report     the printed page's item name",
      "  .center / .left      alignment, from here on",
      "  .color 0xFF0000      colour, from here on (.color off)",
      "  .page                start a new sheet",
      "  ..text               a literal line starting with a dot",
      "",
      "Colour costs one unit of COLOUR ink per line — the rail",
      "counts it separately so it cannot surprise you.",
      "",
      "Press any key.",
    }
    for i, l in ipairs(lines) do
      local y = bodyTop + i - 1
      if y > bodyBottom then break end
      Dv.set(2, y, pad(l, W - 2), i == 1 and T.title or T.fg, T.bg)
    end
    pullKey()
  end

  -- ── Actions ────────────────────────────────────────────────────────
  local function doSave()
    local ok, err = saveFile(path, D_.serialize(buf))
    if not ok then
      status = "NOT SAVED: " .. tostring(err)
      return false
    end
    dirty = false
    status = "Saved " .. path
    return true
  end

  local function doPrint()
    relayout()
    if not P then
      status = "The printer driver is not available (pkg enable printer)."
      return
    end
    if not P.available() then
      status = "No printer: " .. tostring(P.unavailableReason())
      return
    end
    local cost = D_.cost(pages, 1)
    if not confirm(string.format("Print %d sheet(s), %d black, %d colour?",
        cost.paper, cost.black, cost.color)) then
      status = "Not printed."
      return
    end
    -- Built page by page from the LAID-OUT document rather than handed
    -- to the driver as raw text: the pagination on screen and the
    -- pagination on paper are then the same computation, not two that
    -- have to be kept agreeing.
    local job = P.job(parsed.title or (path:match("[^/]+$") or "Document"))
    for i, page in ipairs(pages) do
      if i > 1 then job:pageBreak() end
      for _, entry in ipairs(page) do
        local okL, lErr2 = job:line(entry.text, entry.color, entry.align)
        if not okL then status = "Cannot print: " .. tostring(lErr2); return end
      end
    end
    local okC, why = job:check()
    if not okC then
      status = "Refused: " .. tostring(why)
      return
    end
    local printed, pErr, partial = job:commit()
    if not printed then
      status = "Print failed: " .. tostring(pErr)
      if (partial or 0) > 0 then
        status = status .. string.format(" (%d sheet(s) DID print)", partial)
      end
      return
    end
    status = string.format("Printed %d sheet(s).", printed)
  end

  local function setTitle()
    local t = prompt("Title:", parsed.title or "")
    if t == nil then return end
    -- Written as a .title line at the top of the buffer, because the
    -- source file is the document: a title kept only in memory would
    -- vanish on save and reappear as a mystery on reload.
    for i, line in ipairs(buf) do
      if line:match("^%.title%s") or line == ".title" then
        buf[i] = ".title " .. t
        touch(); status = "Title set."
        return
      end
    end
    table.insert(buf, 1, ".title " .. t)
    cy = cy + 1
    touch(); status = "Title set."
  end

  local function insertLine(text)
    table.insert(buf, cy, text)
    cy = cy + 1; cx = 1
    touch()
  end

  local function toggleCentre()
    -- Insert the directive above the current line, or flip an existing
    -- one — pressing F7 twice should undo itself rather than stack.
    local prev = buf[cy - 1]
    if prev == ".center" then buf[cy - 1] = ".left"; touch(); status = "Left."; return end
    if prev == ".left" then buf[cy - 1] = ".center"; touch(); status = "Centred."; return end
    table.insert(buf, cy, ".center")
    cy = cy + 1
    touch(); status = "Centred."
  end

  -- ── Cursor ─────────────────────────────────────────────────────────
  local function clampCursor()
    if cy < 1 then cy = 1 end
    if cy > #buf then cy = #buf end
    local len = #buf[cy]
    if cx < 1 then cx = 1 end
    if cx > len + 1 then cx = len + 1 end
    if cy < top then top = cy end
    if cy > top + bodyRows - 1 then top = cy - bodyRows + 1 end
    if top < 1 then top = 1 end
  end

  -- ── Main loop ──────────────────────────────────────────────────────
  draw()
  while true do
    local ch, code = pullKey()
    if code ~= nil or ch ~= nil then status = nil end

    if isQuit(ch, code) then
      if dirty then
        if confirm("Save " .. path .. " before leaving?") then
          if not doSave() then draw() end
        end
      end
      break

    elseif code == K.F1 then
      showHelp()

    elseif code == K.F2 or ch == 19 then     -- F2 / ^S
      doSave()

    elseif code == K.F3 then
      doPrint()

    elseif code == K.F4 then
      setTitle()

    elseif code == K.F5 then
      relayout()
      pageView = not pageView
      pvPage = math.min(math.max(1, D_.pageFor(pages, cy) or 1), math.max(1, #pages))

    elseif pageView then
      -- Page view is read-only: it is a proof, not a second editor.
      if code == K.PGDN or code == K.DOWN or code == K.RIGHT then
        pvPage = math.min(#pages, pvPage + 1)
      elseif code == K.PGUP or code == K.UP or code == K.LEFT then
        pvPage = math.max(1, pvPage - 1)
      end

    elseif code == K.F6 then
      insertLine(".page")

    elseif code == K.F7 then
      toggleCentre()

    elseif code == K.UP then
      cy = cy - 1; clampCursor()
    elseif code == K.DOWN then
      cy = cy + 1; clampCursor()
    elseif code == K.LEFT then
      if cx > 1 then cx = cx - 1
      elseif cy > 1 then cy = cy - 1; cx = #buf[cy] + 1 end
      clampCursor()
    elseif code == K.RIGHT then
      if cx <= #buf[cy] then cx = cx + 1
      elseif cy < #buf then cy = cy + 1; cx = 1 end
      clampCursor()
    elseif code == K.HOME then
      cx = 1
    elseif code == K.END then
      cx = #buf[cy] + 1
    elseif code == K.PGUP then
      cy = cy - bodyRows; clampCursor()
    elseif code == K.PGDN then
      cy = cy + bodyRows; clampCursor()

    elseif code == K.ENTER then
      local line = buf[cy]
      buf[cy] = line:sub(1, cx - 1)
      table.insert(buf, cy + 1, line:sub(cx))
      cy = cy + 1; cx = 1
      touch(); clampCursor()

    elseif code == K.BACK then
      if cx > 1 then
        local line = buf[cy]
        buf[cy] = line:sub(1, cx - 2) .. line:sub(cx)
        cx = cx - 1
        touch()
      elseif cy > 1 then
        local prevLen = #buf[cy - 1]
        buf[cy - 1] = buf[cy - 1] .. buf[cy]
        table.remove(buf, cy)
        cy = cy - 1; cx = prevLen + 1
        touch()
      end
      clampCursor()

    elseif code == K.DEL then
      local line = buf[cy]
      if cx <= #line then
        buf[cy] = line:sub(1, cx - 1) .. line:sub(cx + 1)
        touch()
      elseif cy < #buf then
        buf[cy] = line .. buf[cy + 1]
        table.remove(buf, cy + 1)
        touch()
      end

    elseif code == K.TAB then
      local line = buf[cy]
      buf[cy] = line:sub(1, cx - 1) .. "    " .. line:sub(cx)
      cx = cx + 4
      touch()

    elseif ch and ch >= 32 and ch < 127 then
      local line = buf[cy]
      buf[cy] = line:sub(1, cx - 1) .. string.char(ch) .. line:sub(cx)
      cx = cx + 1
      touch()
    end

    draw()
  end

  Dv.clear()
end

-- ══════════════════════════════════════════════════════════════════════
-- Command entry
-- ══════════════════════════════════════════════════════════════════════
local function writeCmd(args, o)
  args = args or {}
  local path = args[1]
  if not path or path == "help" then
    o("write — a word processor for TOS", 0xFFFF55)
    o("  write <path>     Open (or create) a document", 0xFFFFFF)
    o("", 0xFFFFFF)
    o("Unlike `edit`, it knows where the printed page breaks and", 0xAAAAAA)
    o("what the document will cost in paper and ink. Formatting", 0xAAAAAA)
    o("uses dot commands (.title .center .color .page), so the", 0xAAAAAA)
    o("file stays plain text.", 0xAAAAAA)
    if P and not P.available() then
      o("", 0xFFFFFF)
      o("No printer attached: composing and pagination still work.", 0xAAAAAA)
    end
    return
  end
  if path:sub(1, 1) ~= "/" then
    o("Give a full path (e.g. /home/report.txt).", 0xFF5555)
    return
  end
  run(path, o)
end

return { commands = { write = writeCmd } }
