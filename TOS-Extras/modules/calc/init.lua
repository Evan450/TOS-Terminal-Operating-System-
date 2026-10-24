-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: calc — a spreadsheet, the 1-2-3 way             ║
-- ║                                                              ║
-- ║  A keyboard program of the kind that ran the world's books   ║
-- ║  before windows: the three-line control panel at the top     ║
-- ║  (the cell and what is in it; the line you type on, or the   ║
-- ║  menu; the menu's next level or what the command does), the  ║
-- ║  MODE in the corner, and every command one / and a few       ║
-- ║  letters away. Type to enter; point at cells with the arrows ║
-- ║  while you type a formula; F2 edits, F5 goes to, F9 recalcs. ║
-- ║                                                              ║
-- ║  The MODEL and the formula engine live in calc/sheet.lua and ║
-- ║  calc/ops.lua (pure, unit-tested); the page layout and the   ║
-- ║  graph in calc/print.lua and calc/graph.lua, loaded only     ║
-- ║  when used. This file is the screen and the keys.            ║
-- ║                                                              ║
-- ║  Runs inside the pkg sandbox — draws through the sandboxed   ║
-- ║  `component` GPU proxy, pulls raw signals, and reads/writes  ║
-- ║  through the session-bound `fs`, so a sheet is saved with    ║
-- ║  the CALLING user's permissions (no way to write somewhere   ║
-- ║  they couldn't write themselves).                            ║
-- ║                                                              ║
-- ║  Esc belongs to Minecraft (it closes the screen), so where   ║
-- ║  1-2-3 used Esc, calc uses Backspace to go back a step and   ║
-- ║  ^Q to cancel outright.                                      ║
-- ║                                                              ║
-- ║  Usage:  calc [file]                                         ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local S         = require("calc.sheet")

-- Standard TOS shortcuts, shared with the shell (tos/shell/keys.lua): ^Q
-- closes this the same way it closes everything else TOS ships, and an
-- operator rebinding `quit` with `keys set` reaches here too. Falls back
-- to the coded defaults when the module is unavailable.
local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function stdQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return ch == 17 or code == 68 or code == 1
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "^Q"
end

local M = {}

local ROWHDR  = 5         -- row-number gutter width
local DEFAULT_EXT = ".calc"

-- #FIX (emulator round 7) — pad/padLeft measured BYTES. Chrome text
-- here is not ASCII: the key bar separates its hints with "·" (2 bytes
-- in UTF-8), so a 68-COLUMN key bar measured 73 and got sliced on an
-- 80-column screen — the operator saw "^Q Qui". Count characters
-- instead: in UTF-8 a character is any byte that is not a 10xxxxxx
-- continuation byte, and every glyph this program draws is one column
-- wide, so characters and columns agree.
function M.ulen(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
  end
  return n
end
function M.usub(s, a, b)
  local starts, n = {}, 0
  for i = 1, #s do
    local by = s:byte(i)
    if by < 0x80 or by >= 0xC0 then n = n + 1; starts[n] = i end
  end
  starts[n + 1] = #s + 1
  a, b = math.max(1, a), math.min(n, b)
  if a > b then return "" end
  return s:sub(starts[a], starts[b + 1] - 1)
end
function M.pad(s, n)
  s = tostring(s or "")
  local w = M.ulen(s)
  if w > n then return M.usub(s, 1, n) end
  return s .. string.rep(" ", n - w)
end
function M.padLeft(s, n)
  s = tostring(s or "")
  local w = M.ulen(s)
  if w > n then return M.usub(s, 1, n) end
  return string.rep(" ", n - w) .. s
end

--- Join key hints so the bar always ends on a WHOLE hint. When they
--- don't all fit, drop from the RIGHT rather than slicing a word in
--- half — a bar reading "^Q Qui" looks like a rendering fault, while a
--- bar that simply stops after "Del Clear" reads as a short screen.
--- The hints keep their natural reading order; `must` (the way OUT of
--- the program) is re-appended if the drop would have eaten it, since
--- an operator who can't see how to quit is genuinely stuck.
function M.fitHints(hints, cols, must)
  local function join(list)
    return (#list == 0) and "" or (" " .. table.concat(list, " · ") .. " ")
  end
  local kept = {}
  for _, h in ipairs(hints) do
    kept[#kept + 1] = h
    if M.ulen(join(kept)) > cols then kept[#kept] = nil; break end
  end
  if must then
    local have = false
    for _, h in ipairs(kept) do if h == must then have = true end end
    while not have do
      kept[#kept + 1] = must
      if M.ulen(join(kept)) <= cols then have = true
      else
        kept[#kept] = nil                 -- didn't fit: free a slot and retry
        if #kept == 0 then return join({ must }) end
        kept[#kept] = nil
      end
    end
  end
  return join(kept)
end

-- ── Which entry a first keystroke starts ──────────────────────────────
-- 1-2-3's rule: a digit or one of + - . ( @ # $ starts a VALUE; = does
-- too (calc's own spelling); anything else starts a LABEL.
function M.entryMode(ch)
  if type(ch) ~= "string" or ch == "" then return nil end
  if ch:match("[%d%+%-%.%(@#%$=]") then return "VALUE" end
  return "LABEL"
end

--- Whether a VALUE entry ending in `buf` is waiting for a reference, so
--- an arrow key should POINT rather than finish the entry: after an
--- operator, an opening parenthesis or a comma, as in 1-2-3.
function M.wantsRef(buf)
  if buf == "" then return false end
  local last = buf:sub(-1)
  return last:match("[%+%-%*/%^%(,=<>&#%.]") ~= nil
end

--- F4: cycle the reference that ends at position `pos` of `buf` through
--- A1 -> $A$1 -> A$1 -> $A1 -> A1. Returns the new buffer and position.
function M.cycleAbs(buf, pos)
  local before = buf:sub(1, pos)
  local s, word = before:match("()(%$?%a+%$?%d+)$")
  if not s then return buf, pos end
  local d1, col, d2, row = word:match("^(%$?)(%a+)(%$?)(%d+)$")
  local nextWord
  if d1 == "" and d2 == "" then nextWord = "$" .. col .. "$" .. row
  elseif d1 == "$" and d2 == "$" then nextWord = col .. "$" .. row
  elseif d1 == "" and d2 == "$" then nextWord = "$" .. col .. row
  else nextWord = col .. row end
  local out = buf:sub(1, s - 1) .. nextWord .. buf:sub(pos + 1)
  return out, s - 1 + #nextWord
end

-- ══════════════════════════════════════════════════════════════════════
local function run(args, o)
  o = o or print

  local gpuAddr = component.list and component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return end
  local okG, gpu = pcall(component.proxy, gpuAddr)
  if not okG or not gpu then o("Cannot open the GPU.", 0xFF0000); return end
  local W, H = gpu.getResolution()
  if not W or not H or W < 40 or H < 12 then
    o("calc needs at least a 40x12 screen.", 0xFF6600); return
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number")
    and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local mono = (tier == 1)

  local T = mono and {
    bg = 0x000000, fg = 0xFFFFFF, dim = 0xFFFFFF, title = 0xFFFFFF,
    selfg = 0x000000, selbg = 0xFFFFFF, err = 0xFFFFFF, hi = 0xFFFFFF,
    framefg = 0x000000, framebg = 0xFFFFFF, modefg = 0x000000, modebg = 0xFFFFFF,
    range = 0xFFFFFF, s1 = 0xFFFFFF, s2 = 0xFFFFFF, s3 = 0xFFFFFF,
  } or {
    bg = 0x000000, fg = 0xFFFFFF, dim = 0xAAAAAA,
    title = tier == 2 and 0xFFFF55 or 0xFFFF00,
    selfg = 0x000000, selbg = tier == 2 and 0x55FFFF or 0x00FFFF,
    err = tier == 2 and 0xFF5555 or 0xFF4040,
    hi = tier == 2 and 0x55FF55 or 0x00FF00,
    framefg = 0x000000, framebg = tier == 2 and 0xAAAAAA or 0x9A9A9A,
    modefg = 0x000000, modebg = tier == 2 and 0xFFFF55 or 0xFFFF00,
    range = tier == 2 and 0x336699 or 0x2A4A6A,
    s1 = tier == 2 and 0x55FFFF or 0x00C0FF, s2 = tier == 2 and 0xFF55FF or 0xFF60C0,
    s3 = tier == 2 and 0x55FF55 or 0x80E040,
  }

  local function set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  local function fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  local pad, ulen = M.pad, M.ulen
  local function beep() pcall(computer.beep, 880, 0.05) end

  -- Lazily loaded parts: a T2 machine only pays for what is used.
  local O, P, G, MENU
  local function ops() O = O or require("calc.ops"); return O end

  -- ── State ──────────────────────────────────────────────────────
  local sh = S.new()
  local ctx = S.evaluator(sh)
  local calcDue = false
  local cur = { c = 1, r = 1 }
  local off = { c = 1, r = 1 }            -- top-left of the scrolling area
  local titles = { rows = 0, cols = 0 }
  local path = args and args[1] or nil
  local dirty = false
  local mode = "READY"
  local line2 = nil                        -- what the second control line shows
  local line3, line3Tone = nil, nil        -- the third: a message, or the menu's next level
  local endKey = false
  local highlight = nil                    -- a range being pointed at: { c1, r1, c2, r2 }
  local dir

  local function changed() dirty = true end
  local function recalc(force)
    if sh.recalc == "manual" and not force then calcDue = true; return end
    ctx = S.evaluator(sh)
    calcDue = false
  end
  local function say(msg, tone) line3, line3Tone = msg, tone end

  -- Optional companions. Seen by their files, never loaded to look: the
  -- printer driver or write is only pulled in when it is used.
  local function exists(p) return fs and fs.exists and fs.exists(p) or false end
  local function env()
    return { printer = exists("/usr/lib/printer.lua"),
             write = exists("/usr/modules/write/init.lua") }
  end

  -- ── Geometry ───────────────────────────────────────────────────
  local HDR_Y, GRID_TOP, GRID_BOT, STATUS_Y = 4, 5, H - 1, H
  local function colW(c) return S.width(sh, c) end

  --- The columns on screen: the frozen ones, then from off.c until the
  --- screen is full. Each { c, x, w } (w cut at the right edge).
  local function layoutCols()
    local cols, x = {}, ROWHDR + 1
    local function add(c)
      if x > W then return false end
      local w = math.min(colW(c), W - x + 1)
      cols[#cols + 1] = { c = c, x = x, w = w }
      x = x + colW(c)
      return true
    end
    for c = 1, titles.cols do if not add(c) then return cols end end
    local c = math.max(off.c, titles.cols + 1)
    while c <= S.MAX_COLS and add(c) do c = c + 1 end
    return cols
  end
  local function layoutRows()
    local rows, y = {}, GRID_TOP
    for r = 1, titles.rows do
      if y > GRID_BOT then return rows end
      rows[#rows + 1] = { r = r, y = y }; y = y + 1
    end
    local r = math.max(off.r, titles.rows + 1)
    while y <= GRID_BOT and r <= S.MAX_ROWS do
      rows[#rows + 1] = { r = r, y = y }; y = y + 1; r = r + 1
    end
    return rows
  end

  local function ensureVisible(p)
    p = p or cur
    if p.r > titles.rows then
      if p.r < off.r then off.r = p.r end
      local visible = GRID_BOT - GRID_TOP + 1 - titles.rows
      if visible < 1 then visible = 1 end
      if p.r > off.r + visible - 1 then off.r = p.r - visible + 1 end
    end
    if off.r <= titles.rows then off.r = titles.rows + 1 end
    if p.c > titles.cols then
      if p.c < off.c then off.c = p.c end
      while true do
        local cols = layoutCols()
        local last = cols[#cols]
        local seen = false
        for _, col in ipairs(cols) do if col.c == p.c and col.w == colW(col.c) then seen = true end end
        if seen or not last or off.c >= p.c then break end
        off.c = off.c + 1
      end
    end
    if off.c <= titles.cols then off.c = titles.cols + 1 end
  end

  -- ── Drawing ────────────────────────────────────────────────────
  local function controlLine1()
    local raw = S.raw(sh, cur.c, cur.r)
    local s = S.refName(cur.c, cur.r) .. ":"
    local f = sh.fmt[S._key(cur.c, cur.r)]
    if f then s = s .. " (" .. f .. ")" end
    if sh.colw[cur.c] then s = s .. " [W" .. sh.colw[cur.c] .. "]" end
    if raw ~= "" then s = s .. " " .. raw end
    return s
  end

  local function drawControl()
    fill(1, 1, W, 3, " ", T.fg, T.bg)
    set(1, 1, pad(controlLine1(), W - 9), T.fg, T.bg)
    local m = " " .. mode .. " "
    set(W - ulen(m) + 1, 1, m, T.modefg, T.modebg)
    if line2 then
      if type(line2) == "table" then
        for _, seg in ipairs(line2) do set(seg.x, 2, seg.text, seg.fg or T.fg, seg.bg or T.bg) end
      else
        set(1, 2, pad(line2, W), T.fg, T.bg)
      end
    end
    if line3 then set(1, 3, pad(line3, W), line3Tone == "err" and T.err or (line3Tone == "hi" and T.hi or T.dim), T.bg) end
  end

  local function drawHeader(cols)
    fill(1, HDR_Y, W, 1, " ", T.framefg, T.framebg)
    for _, col in ipairs(cols) do
      local name = S.colName(col.c)
      local lead = math.max(0, math.floor((col.w - #name) / 2))
      local isCur = col.c == cur.c
      set(col.x, HDR_Y, pad(string.rep(" ", lead) .. name, col.w),
        isCur and T.selfg or T.framefg, isCur and T.selbg or T.framebg)
    end
  end

  local function inHighlight(c, r)
    local h = highlight
    return h and c >= h[1] and c <= h[3] and r >= h[2] and r <= h[4]
  end

  -- One cell's text across `w` columns; a left-aligned label too long
  -- for its column spills into the empty cells to its right, as 1-2-3's
  -- did, which the caller handles by passing the spill width.
  local function cellRender(c, r, w)
    local raw = sh.cells[S._key(c, r)]
    if not raw then return string.rep(" ", w), T.fg end
    local kind = S.classify(raw)
    if kind == "label" then
      local text, align = S.cellText(sh, ctx, c, r, colW(c))
      local tw = ulen(text)
      if tw > w then text = M.usub(text, 1, w) end
      local padn = w - ulen(text)
      if align == "R" then
        -- Flush with the numbers below it, which keep their last column
        -- blank: a right-aligned heading over a column of figures is the
        -- whole point of the " prefix.
        local inner = math.max(0, math.min(w, colW(c) - 1))
        if ulen(text) <= inner then text = M.padLeft(text, inner) .. string.rep(" ", w - inner)
        else text = string.rep(" ", padn) .. text end
      elseif align == "C" then
        local l = math.floor(padn / 2)
        text = string.rep(" ", l) .. text .. string.rep(" ", padn - l)
      else text = text .. string.rep(" ", padn) end
      return text, T.fg
    end
    -- A value: right-aligned with one blank column after it, so two
    -- numbers side by side never run together.
    local text, align = S.cellText(sh, ctx, c, r, math.max(1, colW(c) - 1))
    local v = ctx.get(c, r)
    local tone = S.isErr(v) and T.err or T.fg
    if align == "L" then return pad(" " .. text, w), (type(v) == "string") and T.fg or tone end
    local cell = M.padLeft(text, math.max(1, colW(c) - 1)) .. " "
    return M.usub(cell, 1, w) .. string.rep(" ", math.max(0, w - ulen(cell))), tone
  end

  local function spillWidth(c, r, cols, idx)
    local raw = sh.cells[S._key(c, r)]
    if not raw then return nil end
    local kind, body, align = S.classify(raw)
    if kind ~= "label" or align == "R" or align == "C" or align == "REP" then return nil end
    if (align or S.PREFIX_ALIGN[sh.gprefix or "'"]) ~= "L" then return nil end
    local need = ulen(body)
    local w = cols[idx].w
    if need <= w then return nil end
    local j = idx + 1
    while j <= #cols and w < need do
      local nc = cols[j]
      if nc.c ~= cols[j - 1].c + 1 then break end
      if sh.cells[S._key(nc.c, r)] then break end
      w = w + nc.w
      j = j + 1
    end
    return w, j - 1
  end

  local function drawGrid(cols, rows)
    for _, row in ipairs(rows) do
      local r, y = row.r, row.y
      fill(1, y, W, 1, " ", T.fg, T.bg)
      local isCurRow = r == cur.r
      set(1, y, pad(tostring(r), ROWHDR), isCurRow and T.selfg or T.framefg,
        isCurRow and T.selbg or T.framebg)
      local i = 1
      while i <= #cols do
        local col = cols[i]
        local w, lastIdx = spillWidth(col.c, r, cols, i)
        local text, tone = cellRender(col.c, r, w or col.w)
        local isCur = col.c == cur.c and r == cur.r
        local fg, bg = tone, T.bg
        if inHighlight(col.c, r) then fg, bg = T.fg, T.range end
        if isCur then
          -- The cell pointer covers its own column only, even when the
          -- label spills on past it.
          set(col.x, y, M.usub(text, 1, col.w), T.selfg, T.selbg)
          if w and w > col.w then set(col.x + col.w, y, M.usub(text, col.w + 1, w), fg, bg) end
        else
          set(col.x, y, text, fg, bg)
        end
        i = (lastIdx or i) + 1
      end
    end
  end

  local function indicators()
    local ind = {}
    if calcDue then ind[#ind + 1] = "CALC" end
    for _, v in pairs(ctx.values or {}) do
      if S.isErr(v) and v.e == S.E_CYCLE then ind[#ind + 1] = "CIRC"; break end
    end
    if endKey then ind[#ind + 1] = "END" end
    return table.concat(ind, " ")
  end

  local function drawStatus()
    fill(1, STATUS_Y, W, 1, mono and " " or "░", T.dim, T.bg)
    if not mono then
      set(1, STATUS_Y, "▓▒░", T.dim, T.bg)
      if W > 6 then set(W - 2, STATUS_Y, "░▒▓", T.dim, T.bg) end
    end
    local name = (path and path:match("[^/]+$") or "(unsaved)") .. (dirty and " *" or "")
    local ind = indicators()
    local room = W - 9 - ulen(name) - ulen(ind) - 2
    local keys = M.fitHints({ "/ Menu", "F1 Help", "F2 Edit", "F5 Goto", "F9 Calc" },
      math.max(0, room), nil)
    local text = " " .. name .. keys
    set(4, STATUS_Y, pad(text, W - 8 - ulen(ind)), T.fg, T.bg)
    if ind ~= "" then set(W - 4 - ulen(ind), STATUS_Y, " " .. ind .. " ", T.modefg, T.modebg) end
  end

  local function redraw()
    local cols, rows = layoutCols(), layoutRows()
    drawControl(); drawHeader(cols); drawGrid(cols, rows); drawStatus()
  end

  -- ── Files ──────────────────────────────────────────────────────
  local function haveFs() return fs and fs.writeFile and fs.readFile end
  local function homeDir()
    if fs and fs.home then
      local okH, h = pcall(fs.home)
      if okH and type(h) == "string" and h ~= "" then return h end
    end
    return "/"
  end
  dir = homeDir()
  local function absPath(p)
    if not p or p == "" then return nil end
    if p:sub(1, 1) == "/" then return p end
    return (dir:sub(-1) == "/" and dir or dir .. "/") .. p
  end
  local function filesIn(d, ext)
    local out = {}
    if not (fs and fs.list) then return out end
    local okL, list = pcall(fs.list, d)
    if not okL or type(list) ~= "table" then return out end
    for _, n in ipairs(list) do
      if not n:match("/$") and (not ext or n:sub(-#ext) == ext) then out[#out + 1] = n end
    end
    table.sort(out)
    return out
  end

  local function doSave(target)
    if not haveFs() then say("No filesystem access.", "err"); return false end
    target = absPath(target or path)
    if not target then return false end
    if not target:match("[^/]+%.[^/]*$") then target = target .. DEFAULT_EXT end
    local okW, e = pcall(fs.writeFile, target, S.serialize(sh))
    if okW and e ~= false then
      path, dirty = target, false
      say("Saved " .. target, "hi")
      return true
    end
    say("Save failed: " .. tostring(e), "err")
    return false
  end

  local function doOpen(target)
    if not haveFs() then say("No filesystem access.", "err"); return end
    target = absPath(target)
    if not target then return end
    if not fs.exists(target) and not target:match("[^/]+%.[^/]*$") then target = target .. DEFAULT_EXT end
    if not fs.exists(target) then say("No such file: " .. target, "err"); return end
    local okR, data = pcall(fs.readFile, target)
    if not okR or type(data) ~= "string" then say("Cannot read " .. target, "err"); return end
    sh = S.deserialize(data)
    ctx = S.evaluator(sh)
    calcDue = false
    path, dirty = target, false
    cur.c, cur.r, off.c, off.r = 1, 1, 1, 1
    titles.rows, titles.cols = 0, 0
    local note = "Retrieved " .. target
    if (sh.skipped or 0) > 0 then note = note .. "  (" .. sh.skipped .. " unreadable line(s) skipped)" end
    say(note, (sh.skipped or 0) > 0 and "err" or "hi")
  end

  -- ── Waiting for a key ──────────────────────────────────────────
  local function pull()
    while true do
      local ev, _, a, b, c = computer.pullSignal()
      if ev == "key_down" then return "key", a, b end
      if ev == "interrupted" then return "key", 17, 16 end
      if ev == "tos_focus" then redraw()
      elseif ev == "clipboard" and type(a) == "string" then return "paste", a
      elseif ev == "touch" or ev == "drag" then return "touch", a, b, c
      elseif ev == "scroll" then return "scroll", a, b, c end
    end
  end

  -- ── Prompts on the second line ─────────────────────────────────
  --- Text, with an optional list Up/Down cycles through (file names,
  --- range names). Returns the text, or nil when cancelled.
  local function promptText(label, initial, choices)
    local buf = tostring(initial or "")
    local ci = 0
    local saveMode = mode
    mode = "EDIT"
    while true do
      line2 = label .. " " .. buf .. "_"
      if choices and #choices > 0 then
        line3 = table.concat(choices, "  ")
        line3Tone = nil
      end
      redraw()
      local kind, ch, code = pull()
      if kind == "paste" then buf = buf .. ch:gsub("[\r\n\t]", " ")
      elseif kind == "key" then
        if code == 28 then mode = saveMode; line2 = nil; line3 = nil; return buf end
        if stdQuit(ch, code) then mode = saveMode; line2 = nil; line3 = nil; return nil end
        if code == 14 then buf = buf:sub(1, -2)
        elseif (code == 200 or code == 208) and choices and #choices > 0 then
          ci = (code == 208) and (ci % #choices + 1) or ((ci - 2) % #choices + 1)
          buf = choices[ci]
        elseif ch and ch >= 32 and ch < 127 then buf = buf .. string.char(ch) end
      end
    end
  end

  local function promptNumber(label, default, lo, hi)
    while true do
      local t = promptText(label, tostring(default))
      if t == nil then return nil end
      local n = tonumber(t)
      if n and (not lo or n >= lo) and (not hi or n <= hi) then return n end
      beep()
      say("Enter a number" .. (lo and (" from " .. lo .. " to " .. hi) or "") .. ".", "err")
    end
  end

  local function moveBy(p, code, rows)
    if code == 200 then p.r = math.max(1, p.r - 1)
    elseif code == 208 then p.r = math.min(S.MAX_ROWS, p.r + 1)
    elseif code == 203 then p.c = math.max(1, p.c - 1)
    elseif code == 205 then p.c = math.min(S.MAX_COLS, p.c + 1)
    elseif code == 201 then p.r = math.max(1, p.r - rows)
    elseif code == 209 then p.r = math.min(S.MAX_ROWS, p.r + rows)
    elseif code == 199 then p.c, p.r = 1, 1
    else return false end
    return true
  end
  local function screenRows() return math.max(1, GRID_BOT - GRID_TOP + 1 - titles.rows) end

  --- A range, 1-2-3's way: it starts ANCHORED at the cell pointer, so
  --- the arrows stretch it; Backspace lets go of the anchor (the arrows
  --- then move the pointer) and . drops it again; typing an address or a
  --- range name replaces it. Returns c1, r1, c2, r2, or nil.
  local function promptRange(label, opts)
    opts = opts or {}
    local anchor = opts.free and nil or { c = cur.c, r = cur.r }
    local p = { c = cur.c, r = cur.r }
    if opts.start then
      local c1, r1, c2, r2 = S.parseRange(opts.start)
      if c1 then anchor = { c = c1, r = r1 }; p = { c = c2, r = r2 } end
    end
    local typed = nil
    local saveMode, saveCur = mode, { c = cur.c, r = cur.r }
    mode = "POINT"
    local function current()
      if typed then return typed end
      if anchor then return S.rangeName(math.min(anchor.c, p.c), math.min(anchor.r, p.r),
        math.max(anchor.c, p.c), math.max(anchor.r, p.r)) end
      return S.refName(p.c, p.r)
    end
    local function finish(result)
      mode = saveMode
      highlight = nil
      line2, line3 = nil, nil
      cur.c, cur.r = saveCur.c, saveCur.r
      ensureVisible()
      return result
    end
    while true do
      if not typed then
        if anchor then
          highlight = { math.min(anchor.c, p.c), math.min(anchor.r, p.r),
                        math.max(anchor.c, p.c), math.max(anchor.r, p.r) }
        else highlight = { p.c, p.r, p.c, p.r } end
        cur.c, cur.r = p.c, p.r
        ensureVisible(p)
      else highlight = nil end
      line2 = label .. " " .. current() .. (typed and "_" or "")
      line3 = typed and "Enter accepts" or "Arrows point · . anchors · Backspace lets go · type an address or a name"
      line3Tone = nil
      redraw()
      local kind, ch, code = pull()
      if kind == "touch" then
        -- A click points at the cell under it.
        local cols, rows = layoutCols(), layoutRows()
        for _, col in ipairs(cols) do
          if ch >= col.x and ch < col.x + col.w then
            for _, row in ipairs(rows) do if row.y == code then p.c, p.r = col.c, row.r end end
          end
        end
      elseif kind == "key" then
        if code == 28 then
          local spec = current()
          local name = sh.names[spec:upper()]
          if name then return finish({ name[1], name[2], name[3], name[4] }) end
          local c1, r1, c2, r2 = S.parseRange(spec)
          if c1 then return finish({ c1, r1, c2, r2 }) end
          beep()
          say("Invalid cell or range address: " .. spec, "err")
          typed = nil
        elseif stdQuit(ch, code) then return finish(nil)
        elseif typed then
          if code == 14 then
            typed = typed:sub(1, -2)
            if typed == "" then typed = nil end
          elseif ch and ch >= 32 and ch < 127 then typed = typed .. string.char(ch) end
        elseif code == 14 then
          if anchor then anchor = nil; p.c, p.r = saveCur.c, saveCur.r
          else return finish(nil) end
        elseif ch == 46 then                           -- "." anchors
          if not anchor then anchor = { c = p.c, r = p.r } end
        elseif moveBy(p, code, screenRows()) then
        elseif ch and ch >= 32 and ch < 127 then typed = string.char(ch) end
      end
    end
  end

  local function unpackRange(t) if not t then return nil end return t[1], t[2], t[3], t[4] end

  -- ── Menus ──────────────────────────────────────────────────────
  local function menuSegments(items, sel, question)
    local segs, x = {}, 1
    if question then
      segs[1] = { x = 1, text = question, fg = T.title, bg = T.bg }
      x = ulen(question) + 3
    end
    for i, it in ipairs(items) do
      local label = it.label
      segs[#segs + 1] = { x = x, text = label, fg = (i == sel) and T.selfg or T.fg,
                          bg = (i == sel) and T.selbg or T.bg, index = i }
      x = x + ulen(label) + 2
    end
    return segs
  end
  local function menuLine3(it)
    if it.items then
      local names = {}
      for _, sub in ipairs(it.items) do names[#names + 1] = sub.label end
      return table.concat(names, "  ")
    end
    return it.desc
  end

  --- Choose from a short list shown as a menu line (1-2-3 asked No/Yes
  --- this way), after `question` when there is one. Returns the index,
  --- or nil.
  local function choose(items, question)
    local sel = 1
    local saveMode = mode
    mode = "MENU"
    while true do
      line2 = menuSegments(items, sel, question)
      line3, line3Tone = items[sel].desc, nil
      redraw()
      local kind, ch, code = pull()
      if kind == "key" then
        if stdQuit(ch, code) or code == 14 then mode = saveMode; line2, line3 = nil, nil; return nil end
        if code == 28 then mode = saveMode; line2, line3 = nil, nil; return sel end
        if code == 203 then sel = (sel - 2) % #items + 1
        elseif code == 205 or code == 57 then sel = sel % #items + 1
        elseif ch and ch > 32 then
          MENU = MENU or require("calc.menu")
          local i = MENU.byKey(items, string.char(ch))
          if i then mode = saveMode; line2, line3 = nil, nil; return i end
        end
      elseif kind == "touch" and code == 2 then
        for _, seg in ipairs(menuSegments(items, sel, question)) do
          if seg.index and ch >= seg.x and ch < seg.x + ulen(seg.text) then mode = saveMode; line2, line3 = nil, nil; return seg.index end
        end
      end
    end
  end
  local function confirm(question, noDesc, yesDesc)
    return choose({ { label = "No", desc = noDesc }, { label = "Yes", desc = yesDesc } }, question) == 2
  end

  -- ── Full-screen views ──────────────────────────────────────────
  local function showLines(title, lines, keepMode)
    local top = 1
    local saveMode = mode
    mode = keepMode or "HELP"
    while true do
      fill(1, 1, W, H, " ", T.fg, T.bg)
      set(1, 1, pad(" " .. title, W - 9), T.title, T.bg)
      set(W - 7, 1, " " .. mode .. " ", T.modefg, T.modebg)
      for i = 0, H - 3 do
        local l = lines[top + i]
        if l then
          local text, tone = l, T.fg
          if type(l) == "table" then text, tone = l[1], (l[2] == "title" and T.title or (l[2] == "dim" and T.dim or T.fg)) end
          set(2, 2 + i, pad(text, W - 2), tone, T.bg)
        end
      end
      set(1, H, pad(" PgUp/PgDn scroll · any other key returns", W), T.dim, T.bg)
      local kind, _, code = pull()
      if kind == "key" then
        if code == 201 then top = math.max(1, top - (H - 3))
        elseif code == 209 then top = math.min(math.max(1, #lines - (H - 3)), top + (H - 3))
        elseif code == 200 then top = math.max(1, top - 1)
        elseif code == 208 then top = math.min(math.max(1, #lines - (H - 3)), top + 1)
        else break end
      end
    end
    mode = saveMode
  end

  local function helpLines()
    local fnames = {}
    for k in pairs(S.FUNCS) do fnames[#fnames + 1] = "@" .. k end
    table.sort(fnames)
    local out = {
      { "calc - a spreadsheet, the 1-2-3 way", "title" }, "",
      { "Moving", "title" },
      "  arrows, PgUp/PgDn      one cell, one screen",
      "  Home                   to A1",
      "  End, then an arrow     to the edge of the data that way",
      "  F5                     go to a cell or a range name",
      "",
      { "Entering", "title" },
      "  Just type. A digit or + - . ( @ # $ = starts a VALUE (a number or a",
      "  formula); anything else starts a LABEL. Enter keeps the pointer where",
      "  it is; an arrow enters and moves.",
      "  While typing a formula, after an operator, ( or , the arrows POINT",
      "  at the cell to put in; . anchors a range; F4 makes it absolute ($).",
      "  F2 edits the cell. Backspace and ^Q (not Esc: Minecraft takes it).",
      "  Label prefixes:  ' left   \" right   ^ centre   \\ repeat (\\- fills)",
      "",
      { "Formulas", "title" },
      "  +A1*2   @SUM(A1..A9)   @IF(B2>100,\"over\",\"ok\")   +A1&\" \"&B1",
      "  Operators: + - * / % ^, = <> < > <= >=, #AND# #OR# #NOT#, & (text)",
      "  $A$1 is absolute: Copy keeps it, where A1 moves with the copy.",
      "  A range name stands for its range: @SUM(SALES).",
      "  1-2-3 counts from 0 in @CHOOSE, @MID, @FIND and the lookups' offset.",
      "",
      { "Keys", "title" },
      "  /   the menu (first letters pick; Backspace goes back a level)",
      "  F1 help   F2 edit   F3 names   F4 absolute   F5 go to   F9 recalc",
      "  Del clears the cell   ^S saves   ^B to the background   " .. quitLabel() .. " quits",
      "",
      { "@functions", "title" },
    }
    local row = "  "
    for _, f in ipairs(fnames) do
      if #row + #f + 1 > W - 4 then out[#out + 1] = row; row = "  " end
      row = row .. f .. " "
    end
    out[#out + 1] = row
    return out
  end

  local function statusScreen()
    local cells, formulas = 0, 0
    for _, raw in pairs(sh.cells) do
      cells = cells + 1
      if S.classify(raw) == "formula" then formulas = formulas + 1 end
    end
    local names = {}
    for n in pairs(sh.names) do names[#names + 1] = n end
    table.sort(names)
    local circ
    for k, v in pairs(ctx.values or {}) do
      if S.isErr(v) and v.e == S.E_CYCLE then
        local c, r = S.unkey(k); circ = S.refName(c, r); break
      end
    end
    local free = (computer.freeMemory and computer.freeMemory()) or nil
    local lines = {
      { "Worksheet status", "title" }, "",
      "  Cells in use:        " .. cells .. "  (" .. formulas .. " formulas)",
      "  Extent:              A1.." .. S.refName(sh.cols, sh.rows),
      "  Global format:       " .. (S.FORMATS[sh.gfmt:sub(1, 1)] or sh.gfmt) .. " (" .. sh.gfmt .. ")",
      "  Label prefix:        " .. sh.gprefix,
      "  Column width:        " .. sh.gwidth,
      "  Recalculation:       " .. (sh.recalc == "manual" and "Manual" or "Automatic"),
      "  Titles:              " .. titles.rows .. " rows, " .. titles.cols .. " columns",
      "  Range names:         " .. (#names > 0 and table.concat(names, " ") or "(none)"),
      "  Circular reference:  " .. (circ or "(none)"),
      "  Memory free:         " .. (free and (math.floor(free / 1024) .. " KB") or "?"),
      "  Printer driver:      " .. (env().printer and "installed" or "not installed"),
      "  write:               " .. (env().write and "installed (Print Document)" or "not installed"),
    }
    showLines("Status", lines, "STAT")
  end

  -- ── Commands ───────────────────────────────────────────────────
  local DECIMALS = { F = true, S = true, C = true, [","] = true, P = true }
  local function formatCode(kind)
    if not DECIMALS[kind] then return kind end
    local n = promptNumber("Enter number of decimal places (0..15):", 2, 0, 15)
    if n == nil then return nil end
    return kind .. math.floor(n)
  end

  local function graphView()
    G = G or require("calc.graph")
    local d = G.collect(sh, ctx)
    local rows, marks = G.render(d, W, H - 1, mono)
    if not rows then say("Cannot draw: " .. marks, "err"); return end
    fill(1, 1, W, H, " ", T.fg, T.bg)
    local COL = { a = T.s1, b = T.s2, c = T.s3, axis = T.dim, title = T.title }
    for y, line in ipairs(rows) do
      -- Runs of one colour per gpu.set.
      local x, runStart, runTone, buf = 1, 1, nil, {}
      for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local tone = COL[marks[y][x]] or T.fg
        if tone ~= runTone and #buf > 0 then
          set(runStart, y, table.concat(buf), runTone, T.bg); buf = {}; runStart = x
        end
        runTone = tone
        buf[#buf + 1] = ch
        x = x + 1
      end
      if #buf > 0 then set(runStart, y, table.concat(buf), runTone, T.bg) end
    end
    set(1, H, pad(" Any key returns", W), T.dim, T.bg)
    pull()
  end

  -- Printing ---------------------------------------------------------
  local function printRange()
    local c1, r1, c2, r2 = S.parseRange(sh.print.range or "")
    return c1, r1, c2, r2
  end

  local function layoutFor(target, measure, maxWidth)
    P = P or require("calc.print")
    local c1, r1, c2, r2 = printRange()
    if not c1 then return nil, "Set a print range first (Range)." end
    recalc(true)
    return P.pages(sh, ctx, c1, r1, c2, r2, {
      target = target, measure = measure, maxWidth = maxWidth,
      perPage = (target == "file") and 0 or 20,
      header = sh.print.header, footer = sh.print.footer, formulas = sh.print.formulas,
    })
  end

  local function printerParts()
    local okP, PR = pcall(require, "printer")
    if not okP or type(PR) ~= "table" then return nil, "the printer driver is not installed" end
    local okF, fmt = pcall(require, "printerfmt")
    local measure, maxW, src = okF and fmt.width or nil, okF and fmt.MAX_WIDTH or 164, "estimated"
    if PR.available and PR.available() then
      measure, maxW = PR.measurer(), PR.maxWidth()
      local _, s = PR.width("M")
      if s == "component" then src = "printer" end
    end
    return PR, measure, maxW, src, okF and fmt or nil
  end

  local function previewPages(target)
    local measure, maxW, src, fmt
    if target ~= "file" then
      local PR
      PR, measure, maxW, src, fmt = printerParts()
      if not PR and target == "printer" then say("Cannot preview: " .. measure, "err"); return end
      if not PR then
        local okF, f = pcall(require, "printerfmt")
        if okF then fmt, measure, maxW, src = f, f.width, f.MAX_WIDTH, "estimated" end
      end
    end
    local pages, why = layoutFor(target, measure, maxW)
    if not pages then say(why, "err"); return end
    local lines = {}
    local cost = fmt and fmt.cost and fmt.cost(pages, 1)
    lines[1] = { string.format("%d page(s) for %s%s", #pages, target,
      cost and string.format(" - %d sheet(s), %d black ink%s", cost.paper, cost.black,
        src and (", " .. src .. " widths") or "") or ""), "title" }
    for i, page in ipairs(pages) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = { string.format("-- page %d of %d --", i, #pages), "dim" }
      for _, l in ipairs(page) do lines[#lines + 1] = l end
    end
    showLines("Print preview", lines, "PREV")
  end

  local function printGo(target)
    if target == "file" then
      local pages, why = layoutFor("file")
      if not pages then say(why, "err"); return end
      P = P or require("calc.print")
      local suggest = (path and path:gsub("%.%w+$", "") or absPath("sheet")) .. ".prn"
      local t = promptText("Enter print file name:", suggest)
      if not t or t == "" then return end
      t = absPath(t)
      local okW, e = pcall(fs.writeFile, t, P.toText(pages))
      if okW and e ~= false then say("Printed " .. #pages .. " page(s) to " .. t, "hi")
      else say("Not written: " .. tostring(e), "err") end
    elseif target == "printer" then
      local PR, measure, maxW, _, fmt = printerParts()
      if not PR then say("Cannot print: " .. measure, "err"); return end
      if not PR.available() then say("No printer: " .. tostring(PR.unavailableReason()), "err"); return end
      local pages, why = layoutFor("printer", measure, maxW)
      if not pages then say(why, "err"); return end
      local job = PR.job((path and path:match("([^/]+)%.%w+$")) or "Worksheet")
      for i, page in ipairs(pages) do
        if i > 1 then job:pageBreak() end
        for _, l in ipairs(page) do
          local okL, lErr = job:line(l)
          if not okL then say("Cannot print: " .. tostring(lErr), "err"); return end
        end
      end
      local okC, cw = job:check()
      if not okC then say("Refused: " .. tostring(cw), "err"); return end
      local cost = fmt and fmt.cost(pages, 1) or { paper = #pages, black = 0 }
      if not confirm(string.format("Print %d sheet(s), %d black ink?", cost.paper, cost.black),
          "Do not print", "Print it") then
        say("Not printed.", nil); return
      end
      local printed, pErr, partial = job:commit()
      if not printed then
        say("Print failed: " .. tostring(pErr) .. ((partial or 0) > 0 and
          string.format(" (%d sheet(s) DID print)", partial) or ""), "err")
      else
        say("Printed " .. printed .. " sheet(s).", "hi")
      end
    elseif target == "write" then
      local okW, WR = pcall(require, "write")
      if not okW or type(WR) ~= "table" then say("Cannot open write: " .. tostring(WR), "err"); return end
      if not WR.api or not WR.api.open then say("This write is too old (1.1.0 adds the way in).", "err"); return end
      local okF, fmt = pcall(require, "printerfmt")
      local pages, why = layoutFor("write", okF and fmt.width or nil, okF and fmt.MAX_WIDTH or nil)
      if not pages then say(why, "err"); return end
      P = P or require("calc.print")
      local title = (path and path:match("([^/]+)%.%w+$")) or "Worksheet"
      local docPath = (path and path:gsub("%.%w+$", "") or absPath("sheet")) .. ".txt"
      -- write runs here, in calc's process, and hands the seat back when
      -- the operator quits it. Nothing is saved unless they press F2.
      local okR, rErr = pcall(WR.api.open, docPath, ".nf\n" .. P.toWrite(pages, title), o)
      fill(1, 1, W, H, " ", T.fg, T.bg)
      if not okR then say("write stopped: " .. tostring(rErr), "err")
      else say("Back from write.", nil) end
    end
  end

  -- The command table ------------------------------------------------
  local CMD = {}
  local function handle(cmd)
    local name, argv = cmd:match("^([%w%.]+):?(.*)$")
    local f = CMD[name]
    if not f then say("Not done yet: " .. cmd, "err"); return end
    return f(argv)
  end

  CMD["global.format"] = function(k)
    local code = formatCode(k); if not code then return end
    sh.gfmt = code; changed(); recalc()
  end
  CMD["global.prefix"] = function(p) sh.gprefix = p; changed() end
  CMD["global.width"] = function()
    local n = promptNumber("Enter global column width (1..60):", sh.gwidth, 1, 60)
    if n then sh.gwidth = math.floor(n); changed() end
  end
  CMD["global.recalc"] = function(m) sh.recalc = m; changed(); recalc(m == "auto") end
  CMD["range.format"] = function(k)
    local code = false                    -- Reset: back to the global format
    if k ~= "reset" then
      code = formatCode(k)
      if code == nil then return end
    end
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range to format:"))
    if not c1 then return end
    ops().format(sh, c1, r1, c2, r2, code or nil); changed()
  end
  CMD["range.label"] = function(p)
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range of labels:"))
    if c1 then ops().label(sh, c1, r1, c2, r2, p); changed(); recalc() end
  end
  CMD["range.erase"] = function()
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range to erase:"))
    if c1 then ops().erase(sh, c1, r1, c2, r2); changed(); recalc() end
  end
  CMD["range.value"] = function()
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range to copy FROM:"))
    if not c1 then return end
    local tc, tr = unpackRange(promptRange("Enter range to copy TO:", { free = true }))
    if not tc then return end
    ops().values(sh, c1, r1, c2, r2, tc, tr); changed(); recalc()
  end
  CMD["name.create"] = function()
    local n = promptText("Enter name:", "")
    if not n or n == "" then return end
    if not ops().validName(n) then
      beep(); say("Not a usable name: letters, digits and _, and not like a cell or @function.", "err"); return
    end
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range:"))
    if not c1 then return end
    sh.names[n:upper()] = { c1, r1, c2, r2 }; changed(); recalc()
    say("Named " .. n:upper() .. " = " .. S.rangeName(c1, r1, c2, r2), "hi")
  end
  local function nameList()
    local names = {}
    for n in pairs(sh.names) do names[#names + 1] = n end
    table.sort(names)
    return names
  end
  CMD["name.delete"] = function()
    local names = nameList()
    if #names == 0 then say("There are no range names.", "err"); return end
    local n = promptText("Enter name to delete:", names[1], names)
    if n and sh.names[n:upper()] then sh.names[n:upper()] = nil; changed(); recalc() end
  end
  CMD["name.reset"] = function()
    if confirm("Forget every range name?", "Keep the names", "Forget them all") then sh.names = {}; changed(); recalc() end
  end
  CMD["name.table"] = function()
    local c1, r1 = unpackRange(promptRange("Enter range for table:", { free = true }))
    if not c1 then return end
    for i, n in ipairs(nameList()) do
      local rg = sh.names[n]
      S.set(sh, c1, r1 + i - 1, "'" .. n)
      S.set(sh, c1 + 1, r1 + i - 1, "'" .. S.rangeName(rg[1], rg[2], rg[3], rg[4]))
    end
    changed(); recalc()
  end
  CMD["copy"] = function()
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range to copy FROM:"))
    if not c1 then return end
    local t = promptRange("Enter range to copy TO:", { free = true })
    if not t then return end
    ops().copy(sh, c1, r1, c2, r2, t[1], t[2], t[3], t[4]); changed(); recalc()
  end
  CMD["move"] = function()
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter range to move FROM:"))
    if not c1 then return end
    local t = promptRange("Enter range to move TO:", { free = true })
    if not t then return end
    local n, why = ops().move(sh, c1, r1, c2, r2, t[1], t[2])
    if n == nil then say(why, "err") else changed(); recalc() end
  end
  CMD["ws.insert"] = function(what)
    local c1, r1, c2, r2 = unpackRange(promptRange(what == "col" and "Enter column insert range:" or "Enter row insert range:"))
    if not c1 then return end
    if what == "col" then ops().insertCols(sh, c1, c2 - c1 + 1) else ops().insertRows(sh, r1, r2 - r1 + 1) end
    changed(); recalc()
  end
  CMD["ws.delete"] = function(what)
    local c1, r1, c2, r2 = unpackRange(promptRange(what == "col" and "Enter range of columns to delete:" or "Enter range of rows to delete:"))
    if not c1 then return end
    if what == "col" then ops().deleteCols(sh, c1, c2 - c1 + 1) else ops().deleteRows(sh, r1, r2 - r1 + 1) end
    changed(); recalc()
  end
  CMD["col.width"] = function()
    -- The arrows widen and narrow the column as you watch, as in 1-2-3.
    local w = colW(cur.c)
    local saveMode = mode
    mode = "EDIT"
    while true do
      sh.colw[cur.c] = w
      line2 = "Enter column width (1..60): " .. w
      line3, line3Tone = "Left/Right change it as you watch · Enter keeps it · " .. quitLabel() .. " cancels", nil
      redraw()
      local kind, ch, code = pull()
      if kind == "key" then
        if code == 28 then break end
        if stdQuit(ch, code) then sh.colw[cur.c] = nil; mode = saveMode; line2, line3 = nil, nil; return end
        if code == 203 then w = math.max(1, w - 1)
        elseif code == 205 then w = math.min(60, w + 1)
        elseif ch and ch >= 48 and ch <= 57 then
          local n = promptNumber("Enter column width (1..60):", string.char(ch), 1, 60)
          if n then w = math.floor(n) end
          break
        end
      end
    end
    mode = saveMode
    line2, line3 = nil, nil
    if w == sh.gwidth then sh.colw[cur.c] = nil else sh.colw[cur.c] = w end
    changed()
  end
  CMD["col.reset"] = function() sh.colw[cur.c] = nil; changed() end
  CMD["ws.erase"] = function()
    sh = S.new(); ctx = S.evaluator(sh); path = nil; dirty = false; calcDue = false
    cur.c, cur.r, off.c, off.r = 1, 1, 1, 1; titles.rows, titles.cols = 0, 0
  end
  CMD["titles"] = function(how)
    if how == "clear" then titles.rows, titles.cols = 0, 0; return end
    if how == "both" or how == "h" then titles.rows = math.max(0, cur.r - 1) end
    if how == "both" or how == "v" then titles.cols = math.max(0, cur.c - 1) end
    ensureVisible()
  end
  CMD["ws.status"] = function() statusScreen() end
  CMD["file.retrieve"] = function()
    if dirty and not confirm("Discard unsaved changes?", "Keep this worksheet", "Discard its unsaved changes") then return end
    local list = filesIn(dir, DEFAULT_EXT)
    local t = promptText("Name of file to retrieve:", list[1] or "", list)
    if t and t ~= "" then doOpen(t) end
  end
  CMD["file.save"] = function()
    local suggest = path or absPath("sheet" .. DEFAULT_EXT)
    local t = promptText("Enter name of file to save:", suggest)
    if not t or t == "" then return end
    local target = absPath(t)
    if not target:match("[^/]+%.[^/]*$") then target = target .. DEFAULT_EXT end
    if target ~= path and fs.exists(target) then
      local i = choose({ { label = "Cancel", desc = "Do not save" },
                         { label = "Replace", desc = "Write over the file on disk" } }, target .. " exists.")
      if i ~= 2 then return end
    end
    doSave(target)
  end
  CMD["file.import"] = function()
    local list = filesIn(dir, ".csv")
    local t = promptText("Name of CSV file to import:", list[1] or "", list)
    if not t or t == "" then return end
    local p = absPath(t)
    local okR, data = pcall(fs.readFile, p)
    if not okR or type(data) ~= "string" then say("Cannot read " .. p, "err"); return end
    local n = S.fromCSV(sh, data, cur.c, cur.r)
    changed(); recalc()
    say(string.format("Imported %d cell(s) from %s at %s.", n, p, S.refName(cur.c, cur.r)), "hi")
  end
  CMD["file.export"] = function()
    local suggest = (path and path:gsub("%.%w+$", "") or absPath("sheet")) .. ".csv"
    local t = promptText("Export CSV as:", suggest)
    if not t or t == "" then return end
    recalc(true)
    local p = absPath(t)
    local okW, e = pcall(fs.writeFile, p, S.toCSV(sh, ctx))
    if okW and e ~= false then say("Exported " .. p, "hi") else say("Export failed: " .. tostring(e), "err") end
  end
  CMD["file.list"] = function()
    local lines = { { "Worksheets in " .. dir, "title" }, "" }
    for _, n in ipairs(filesIn(dir, DEFAULT_EXT)) do lines[#lines + 1] = "  " .. n end
    if #lines == 2 then lines[3] = "  (none)" end
    showLines("File list", lines, "FILES")
  end
  CMD["file.dir"] = function()
    local t = promptText("Enter current directory:", dir)
    if t and t ~= "" then
      if fs.isDirectory and not fs.isDirectory(t) then say("Not a directory: " .. t, "err"); return end
      dir = t
    end
  end
  CMD["print.range"] = function()
    local t = promptRange("Enter print range:", { start = sh.print.range })
    if t then sh.print.range = S.rangeName(t[1], t[2], t[3], t[4]); changed() end
  end
  CMD["print.header"] = function()
    local t = promptText("Enter header line:", sh.print.header or "")
    if t then sh.print.header = t ~= "" and t or nil; changed() end
  end
  CMD["print.footer"] = function()
    local t = promptText("Enter footer line:", sh.print.footer or "")
    if t then sh.print.footer = t ~= "" and t or nil; changed() end
  end
  CMD["print.displayed"] = function() sh.print.formulas = nil; changed() end
  CMD["print.formulas"] = function() sh.print.formulas = true; changed() end
  CMD["print.preview"] = function(target) previewPages(target) end
  CMD["print.go"] = function(target) printGo(target) end
  CMD["print.clear"] = function() sh.print = {}; changed(); say("Print settings cleared.") end
  CMD["graph.type"] = function(t) sh.graph.type = t; changed() end
  CMD["graph.range"] = function(k)
    local t = promptRange("Enter " .. k:upper() .. " range:", { start = sh.graph[k] })
    if t then sh.graph[k] = S.rangeName(t[1], t[2], t[3], t[4]); changed() end
  end
  CMD["graph.title"] = function(k)
    local t = promptText(k == "title1" and "Enter first title:" or "Enter second title:", sh.graph[k] or "")
    if t then sh.graph[k] = t ~= "" and t or nil; changed() end
  end
  CMD["graph.reset"] = function() sh.graph = {}; changed() end
  CMD["graph.view"] = function() recalc(true); graphView() end
  CMD["data.fill"] = function()
    local c1, r1, c2, r2 = unpackRange(promptRange("Enter fill range:"))
    if not c1 then return end
    local start = promptNumber("Start:", 0); if not start then return end
    local step = promptNumber("Step:", 1); if not step then return end
    local stop = promptNumber("Stop:", 8191); if not stop then return end
    ops().fill(sh, c1, r1, c2, r2, start, step, stop); changed(); recalc()
  end
  CMD["sort.range"] = function()
    local t = promptRange("Enter data range:", { start = sh.sort.range })
    if t then sh.sort.range = S.rangeName(t[1], t[2], t[3], t[4]); changed() end
  end
  local function sortKey(which, label)
    local t = promptRange(label, { free = true })
    if not t then return end
    local o2 = promptText("Sort order (A or D):", which == "k1" and (sh.sort.o1 or "A") or (sh.sort.o2 or "A"))
    if not o2 then return end
    o2 = o2:upper():sub(1, 1)
    if o2 ~= "A" and o2 ~= "D" then beep(); say("A for ascending, D for descending.", "err"); return end
    sh.sort[which] = S.refName(t[1], t[2])
    sh.sort[which == "k1" and "o1" or "o2"] = o2
    changed()
  end
  CMD["sort.key1"] = function() sortKey("k1", "Primary sort key:") end
  CMD["sort.key2"] = function() sortKey("k2", "Secondary sort key:") end
  CMD["sort.reset"] = function() sh.sort = {}; changed() end
  CMD["sort.go"] = function()
    local c1, r1, c2, r2 = S.parseRange(sh.sort.range or "")
    local k1 = sh.sort.k1 and S.parseRef(sh.sort.k1)
    if not c1 or not k1 then beep(); say("Set the Data-Range and the Primary-Key first.", "err"); return end
    local k2 = sh.sort.k2 and S.parseRef(sh.sort.k2) or nil
    ops().sort(sh, c1, r1, c2, r2, k1, sh.sort.o1 ~= "D", k2, sh.sort.o2 ~= "D")
    changed(); recalc()
    say("Sorted " .. (r2 - r1 + 1) .. " rows.", "hi")
  end

  local quitting = false
  CMD["app.quit"] = function()
    if dirty then
      local i = choose({ { label = "No", desc = "Stay in calc" },
                         { label = "Yes", desc = "Leave without saving" },
                         { label = "Save", desc = "Save, then leave" } }, "Worksheet changes not saved! Leave anyway?")
      if i == 2 then quitting = true
      elseif i == 3 then if doSave(path or promptText("Enter name of file to save:", absPath("sheet" .. DEFAULT_EXT))) then quitting = true end end
    else
      quitting = true
    end
  end

  --- The / menu. Returns when a command that does not keep its menu
  --- open has run, or the operator backs all the way out.
  local function menuLoop()
    MENU = MENU or require("calc.menu")
    local stack = { { items = MENU.root(env()), sel = 1 } }
    local saveMode = mode
    mode = "MENU"
    while #stack > 0 and not quitting do
      local top = stack[#stack]
      local items = top.items
      line2 = menuSegments(items, top.sel)
      line3, line3Tone = menuLine3(items[top.sel]), nil
      redraw()
      local kind, ch, code = pull()
      local pick
      if kind == "key" then
        if stdQuit(ch, code) then break end
        if code == 14 then table.remove(stack)
        elseif code == 28 then pick = top.sel
        elseif code == 203 then top.sel = (top.sel - 2) % #items + 1
        elseif code == 205 or code == 57 then top.sel = top.sel % #items + 1
        elseif code == 199 then top.sel = 1
        elseif code == 207 then top.sel = #items
        elseif ch and ch > 32 then
          pick = MENU.byKey(items, string.char(ch))
          if not pick then beep() end
        end
      elseif kind == "touch" and code == 2 then
        for _, seg in ipairs(line2) do
          if ch >= seg.x and ch < seg.x + ulen(seg.text) then pick = seg.index end
        end
      end
      if pick then
        local it = items[pick]
        top.sel = pick
        if it.items then
          stack[#stack + 1] = { items = it.items, sel = 1 }
        elseif it.cmd == "menu.up" then
          table.remove(stack)
        elseif it.cmd == "menu.quit" then
          break
        else
          line2, line3 = nil, nil
          mode = "WAIT"
          handle(it.cmd)
          mode = "MENU"
          -- A sticky menu (Print, Graph, Sort) stays at the level that
          -- holds the command, the way 1-2-3's did; anything else is done.
          if not it.stay then break end
        end
      end
    end
    mode = saveMode
    line2 = nil
    if not line3Tone then line3 = nil end
  end

  -- ── Entering and editing a cell ────────────────────────────────
  --- Commit `buf` into the current cell. Returns true, or false (the
  --- caller stays in EDIT with the error shown) when a VALUE does not
  --- parse — 1-2-3 beeped and dropped you into EDIT the same way.
  local function commit(buf, entryKind)
    if buf == "" then S.set(sh, cur.c, cur.r, nil); changed(); recalc(); return true end
    local raw = buf
    if entryKind == "LABEL" and not S.PREFIX_ALIGN[buf:sub(1, 1)] then raw = (sh.gprefix or "'") .. buf end
    local kind, body = S.classify(raw)
    if kind == "formula" then
      local ast, perr = S.parse(body)
      if not ast then
        beep()
        say("Not a valid formula (" .. tostring(perr) .. "): fix it, start it with ' to make it a label, or "
          .. quitLabel() .. " to cancel.", "err")
        return false
      end
    end
    S.set(sh, cur.c, cur.r, raw)
    changed(); recalc()
    return true
  end

  --- LABEL / VALUE / EDIT / POINT. `buf` starts the entry, `pos` the
  --- cursor in it (EDIT moves it; the others type at the end). Returns
  --- when the entry is committed or cancelled, with the key that ended
  --- it so an arrow can move on.
  local function entryLoop(buf, kindOf, startPos)
    local pos = startPos or #buf
    local kind = kindOf
    local point = nil                         -- { at = index, c, r, anchor }
    local function pointText()
      if point.anchor then
        return S.rangeName(math.min(point.anchor.c, point.c), math.min(point.anchor.r, point.r),
          math.max(point.anchor.c, point.c), math.max(point.anchor.r, point.r))
      end
      return S.refName(point.c, point.r)
    end
    local function settlePoint()
      if point then
        local t = pointText()
        buf = buf:sub(1, point.at) .. t .. buf:sub(point.at + 1)
        pos = point.at + #t
        point = nil
        highlight = nil
      end
    end
    local home = { c = cur.c, r = cur.r }
    while true do
      mode = point and "POINT" or kind
      local shown = point and (buf:sub(1, point.at) .. pointText() .. buf:sub(point.at + 1)) or buf
      local cpos = point and (point.at + #pointText()) or pos
      local head = shown:sub(1, cpos)
      local tail = shown:sub(cpos + 1)
      local avail = W - 2
      local start = math.max(1, #head - avail + 10)
      line2 = { { x = 1, text = pad(head:sub(start), W), fg = T.fg, bg = T.bg } }
      local cx = #head:sub(start) + 1
      if cx <= W then
        line2[2] = { x = cx, text = (tail:sub(1, 1) ~= "" and tail:sub(1, 1) or " "), fg = T.selfg, bg = T.selbg }
        if #tail > 1 and cx + 1 <= W then line2[3] = { x = cx + 1, text = tail:sub(2, W - cx), fg = T.fg, bg = T.bg } end
      end
      if point then
        highlight = point.anchor and { math.min(point.anchor.c, point.c), math.min(point.anchor.r, point.r),
          math.max(point.anchor.c, point.c), math.max(point.anchor.r, point.r) } or { point.c, point.r, point.c, point.r }
        cur.c, cur.r = point.c, point.r
        ensureVisible()
      else
        cur.c, cur.r = home.c, home.r
      end
      redraw()
      local ek, ch, code = pull()
      if ek == "paste" then
        settlePoint()
        local t = ch:gsub("[\r\n\t]", " ")
        buf = buf:sub(1, pos) .. t .. buf:sub(pos + 1); pos = pos + #t
      elseif ek == "key" then
        local isArrow = code == 200 or code == 208 or code == 203 or code == 205 or code == 201 or code == 209
        if stdQuit(ch, code) then
          if point then point = nil; highlight = nil
          else cur.c, cur.r = home.c, home.r; highlight = nil; line2 = nil; return "cancel" end
        elseif code == 28 then
          settlePoint()
          cur.c, cur.r = home.c, home.r
          if commit(buf, kind == "LABEL" and "LABEL" or "VALUE") then line2 = nil; say(nil); return "commit" end
          kind = "EDIT"
        elseif code == 60 and not point then                 -- F2: into EDIT
          kind = "EDIT"
        elseif code == 62 then                                -- F4: absolute
          settlePoint()
          buf, pos = M.cycleAbs(buf, pos)
        elseif code == 61 and kind ~= "LABEL" then             -- F3: a name
          local names = {}
          for n in pairs(sh.names) do names[#names + 1] = n end
          table.sort(names)
          if #names > 0 then
            local i = choose((function()
              local items = {}
              for _, n in ipairs(names) do items[#items + 1] = { label = n, desc = "Insert this range name" } end
              return items
            end)())
            if i then settlePoint(); buf = buf:sub(1, pos) .. names[i] .. buf:sub(pos + 1); pos = pos + #names[i] end
          end
        elseif point then
          if code == 14 then
            if point.anchor then point.anchor = nil else point = nil; highlight = nil end
          elseif ch == 46 then
            if not point.anchor then point.anchor = { c = point.c, r = point.r } end
          elseif isArrow or code == 199 then
            moveBy(point, code, screenRows())
          elseif ch and ch >= 32 and ch < 127 then
            -- An operator (or anything typed) fixes the reference and
            -- carries on typing after it.
            settlePoint()
            buf = buf:sub(1, pos) .. string.char(ch) .. buf:sub(pos + 1); pos = pos + 1
          end
        elseif isArrow and kind == "VALUE" and M.wantsRef(buf:sub(1, pos)) then
          point = { at = pos, c = home.c, r = home.r }
          moveBy(point, code, screenRows())
        elseif isArrow and kind ~= "EDIT" then
          cur.c, cur.r = home.c, home.r
          if commit(buf, kind == "LABEL" and "LABEL" or "VALUE") then line2 = nil; say(nil); return "move", code end
          kind = "EDIT"
        elseif kind == "EDIT" and (code == 200 or code == 208) then
          cur.c, cur.r = home.c, home.r
          if commit(buf, "VALUE") then line2 = nil; say(nil); return "move", code end
        elseif kind == "EDIT" and code == 203 then pos = math.max(0, pos - 1)
        elseif kind == "EDIT" and code == 205 then pos = math.min(#buf, pos + 1)
        elseif kind == "EDIT" and code == 199 then pos = 0
        elseif kind == "EDIT" and code == 207 then pos = #buf
        elseif code == 14 then
          if pos > 0 then buf = buf:sub(1, pos - 1) .. buf:sub(pos + 1); pos = pos - 1 end
          if buf == "" and kind ~= "EDIT" then line2 = nil; return "cancel" end
        elseif code == 211 then
          if pos < #buf then buf = buf:sub(1, pos) .. buf:sub(pos + 2) end
        elseif ch and ch >= 32 and ch < 127 then
          buf = buf:sub(1, pos) .. string.char(ch) .. buf:sub(pos + 1); pos = pos + 1
        end
      end
    end
  end

  -- ── End: jump to the edge of the data ──────────────────────────
  local function endJump(code)
    local dc, dr = 0, 0
    if code == 200 then dr = -1 elseif code == 208 then dr = 1
    elseif code == 203 then dc = -1 elseif code == 205 then dc = 1 else return false end
    local function filled(c, r) return sh.cells[S._key(c, r)] ~= nil end
    local c, r = cur.c, cur.r
    local start = filled(c, r)
    local nextFilled = filled(c + dc, r + dr)
    if start and nextFilled then
      while c + dc >= 1 and r + dr >= 1 and c + dc <= S.MAX_COLS and r + dr <= S.MAX_ROWS
        and filled(c + dc, r + dr) do c, r = c + dc, r + dr end
    else
      repeat c, r = c + dc, r + dr
      until c < 1 or r < 1 or c > S.MAX_COLS or r > S.MAX_ROWS or filled(c, r)
      if c < 1 or r < 1 or c > S.MAX_COLS or r > S.MAX_ROWS then
        c = math.max(1, math.min(S.MAX_COLS, c)); r = math.max(1, math.min(S.MAX_ROWS, r))
      end
    end
    cur.c, cur.r = c, r
    return true
  end

  local function gotoCell()
    local t = promptText("Enter address to go to:", S.refName(cur.c, cur.r))
    if not t then return end
    local rg = sh.names[t:upper()]
    if rg then cur.c, cur.r = rg[1], rg[2]; return end
    local c, r = S.parseRef(t:upper())
    if c then cur.c, cur.r = c, r else beep(); say("Invalid cell address: " .. t, "err") end
  end

  -- ── Open a file passed on the command line ─────────────────────
  -- A .csv (what `open` hands over for one) is IMPORTED into a new
  -- worksheet named after it, so saving writes budget.calc and never
  -- turns the CSV itself into a worksheet file.
  if path and path:lower():match("%.csv$") and fs and fs.exists and fs.exists(absPath(path)) then
    local src = absPath(path)
    local okR, data = pcall(fs.readFile, src)
    if okR and type(data) == "string" then
      local n = S.fromCSV(sh, data, 1, 1)
      recalc(true)
      path = src:gsub("%.[Cc][Ss][Vv]$", DEFAULT_EXT)
      dirty = true
      say(string.format("Imported %d cell(s) from %s; ^S saves it as %s.", n, src, path:match("[^/]+$")), "hi")
    else
      say("Cannot read " .. src, "err")
      path = nil
    end
  elseif path then
    if fs and fs.exists and (fs.exists(absPath(path)) or fs.exists(absPath(path) .. DEFAULT_EXT)) then
      doOpen(path)
    else
      path = absPath(path)
      say("New worksheet: " .. path, nil)
    end
  end

  -- ── Main loop (READY) ──────────────────────────────────────────
  redraw()
  while not quitting do
    mode = "READY"
    redraw()
    local kind, ch, code, arg5 = pull()
    if kind == "touch" then
      local cols, rows = layoutCols(), layoutRows()
      for _, col in ipairs(cols) do
        if ch >= col.x and ch < col.x + col.w then
          for _, row in ipairs(rows) do if row.y == code then cur.c, cur.r = col.c, row.r end end
        end
      end
      say(nil)
    elseif kind == "scroll" then
      local step = (arg5 or 0) > 0 and -3 or 3
      cur.r = math.max(1, math.min(S.MAX_ROWS, cur.r + step))
      ensureVisible()
    elseif kind == "paste" then
      local _ = entryLoop(ch:gsub("[\r\n\t]", " "), M.entryMode(ch:sub(1, 1)) or "LABEL")
    elseif kind == "key" then
      if code ~= 207 and not (code == 200 or code == 208 or code == 203 or code == 205) then endKey = false end
      if line3Tone ~= "err" or (ch and ch >= 32) then say(nil) end
      if stdQuit(ch, code) then
        CMD["app.quit"]()
      elseif ch == 47 or ch == 60 then                           -- "/" (or "<")
        menuLoop()
      elseif ch == 19 then                                       -- ^S
        if path then doSave(path) else
          local t = promptText("Enter name of file to save:", absPath("sheet" .. DEFAULT_EXT))
          if t and t ~= "" then doSave(t) end
        end
      elseif code == 59 then showLines("Help", helpLines())       -- F1
      elseif code == 60 then                                     -- F2
        local raw = S.raw(sh, cur.c, cur.r)
        local res, mv = entryLoop(raw, "EDIT", #raw)
        if res == "move" then moveBy(cur, mv, screenRows()) end
      elseif code == 61 then                                     -- F3: names
        local names = {}
        for n in pairs(sh.names) do names[#names + 1] = n end
        table.sort(names)
        if #names == 0 then say("There are no range names.", nil)
        else
          local t = promptText("Go to range name:", names[1], names)
          if t and sh.names[t:upper()] then local rg = sh.names[t:upper()]; cur.c, cur.r = rg[1], rg[2] end
        end
      elseif code == 63 then gotoCell()                          -- F5
      elseif code == 67 then recalc(true)                        -- F9
      elseif code == 207 then endKey = not endKey                -- End
      elseif endKey and endJump(code) then endKey = false
      elseif code == 199 then cur.c, cur.r = titles.cols + 1, titles.rows + 1  -- Home
      elseif code == 211 then                                    -- Del
        if S.raw(sh, cur.c, cur.r) ~= "" then S.set(sh, cur.c, cur.r, nil); changed(); recalc() end
      elseif code == 15 then                                     -- Tab: a screen right
        local cols = layoutCols()
        cur.c = math.min(S.MAX_COLS, cur.c + math.max(1, #cols - titles.cols))
      elseif moveBy(cur, code, screenRows()) then
      elseif ch and ch >= 32 and ch < 127 then
        local first = string.char(ch)
        local res, mv = entryLoop(first, M.entryMode(first))
        if res == "move" then moveBy(cur, mv, screenRows()) end
      end
      ensureVisible()
    end
  end
  fill(1, 1, W, H, " ", T.fg, T.bg)
end

return { commands = { calc = run }, text = M }
