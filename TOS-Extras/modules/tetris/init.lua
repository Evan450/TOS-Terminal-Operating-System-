-- ╔══════════════════════════════════════╗
-- ║  TOS Module: tetris                  ║
-- ║  Classic Tetris with high scores     ║
-- ╚══════════════════════════════════════╝
-- Full-screen Tetris that runs entirely inside the pkg sandbox: it
-- draws through the sandboxed `component` GPU proxy and pulls raw
-- signals via computer.pullSignal (the same pattern as the mouse
-- package's mousetest). kernel.* modules are NOT reachable from
-- package code — the pre-pivot build required kernel.display /
-- kernel.event and therefore could not launch at all under pkg.
-- Per-user high scores are stored in ~/.tetris_hs so every player
-- keeps an independent leaderboard.
--
-- Controls (in-game):
--   ← → / A D     Move left / right
--   ↑ / W / X     Rotate clockwise      Z  Rotate counter-clockwise
--   ↓ / S         Soft drop   (+1 pt/row)
--   Space          Hard drop  (+2 pts/row)
--   P              Pause / unpause
--   Q / Esc        Quit to shell
--
-- Requires a T2+ GPU with at least an 80×24 screen.

local component = require("component")
local computer  = require("computer")

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

local mod = {}

-- ── Board geometry ────────────────────────────────────────────────────────────
local BW       = 10          -- board width  (cells, 0-indexed columns 0..9)
local BH       = 20          -- board height (cells, 0-indexed rows 0..19)
local CW       = 2           -- cell width in terminal characters
local PANEL_W  = 18          -- side panel outer width (chars, includes border)
local PF_BOX_W = BW * CW + 2 -- playfield box outer width  = 22
local PF_BOX_H = BH + 2      -- playfield box outer height = 22
local MIN_W    = PF_BOX_W + 1 + PANEL_W  -- 41 chars minimum screen width
local MIN_H    = PF_BOX_H + 2            -- 24 rows minimum screen height

-- ── Piece definitions ─────────────────────────────────────────────────────────
-- 7 pieces × 4 rotations × 4 cells.
-- Each cell is a {col, row} offset from the top-left of the 4×4 bounding box.
-- Rotations follow the Tetris Guideline (SRS) sequence.
local PIECES = {
  -- 1: I  ████
  {{{0,1},{1,1},{2,1},{3,1}}, {{2,0},{2,1},{2,2},{2,3}},
   {{0,2},{1,2},{2,2},{3,2}}, {{1,0},{1,1},{1,2},{1,3}}},
  -- 2: O  ██
  --       ██
  {{{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}},
   {{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}}},
  -- 3: T  .█.
  --       ███
  {{{1,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{2,1},{1,2}},
   {{0,1},{1,1},{2,1},{1,2}}, {{1,0},{0,1},{1,1},{1,2}}},
  -- 4: S  .██
  --       ██.
  {{{1,0},{2,0},{0,1},{1,1}}, {{1,0},{1,1},{2,1},{2,2}},
   {{1,1},{2,1},{0,2},{1,2}}, {{0,0},{0,1},{1,1},{1,2}}},
  -- 5: Z  ██.
  --       .██
  {{{0,0},{1,0},{1,1},{2,1}}, {{2,0},{1,1},{2,1},{1,2}},
   {{0,1},{1,1},{1,2},{2,2}}, {{1,0},{0,1},{1,1},{0,2}}},
  -- 6: J  █..
  --       ███
  {{{0,0},{0,1},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{1,2}},
   {{0,1},{1,1},{2,1},{2,2}}, {{1,0},{1,1},{0,2},{1,2}}},
  -- 7: L  ..█
  --       ███
  {{{2,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{1,2},{2,2}},
   {{0,1},{1,1},{2,1},{0,2}}, {{0,0},{1,0},{1,1},{1,2}}},
}

-- Piece colors indexed [gpuTier][pieceType].
-- T3 = full RGB, T2 = OC 16-colour dye palette, T1 = monochrome (all white).
local PCOLORS = {
  [3] = {0x00FFFF, 0xFFFF00, 0xFF00FF, 0x00FF00, 0xFF0000, 0x5555FF, 0xFF8800},
  [2] = {0x55FFFF, 0xFFFF55, 0xFF55FF, 0x55FF55, 0xFF5555, 0x5555FF, 0xFFAA00},
  [1] = {0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF},
}

-- Key codes (OC / LWJGL scan codes)
local K = {
  LEFT=203, RIGHT=205, UP=200, DOWN=208,
  SPACE=57, ESC=1, ENTER=28,
  Q=16, W=17, A=30, S=31, D=32, P=25, R=19, Z=44, X=45,
}

-- Wall kick offsets tried during rotation (shared constant to avoid
-- re-allocating 7 tables every rotation call).
local WALL_KICKS = {{0,0},{-1,0},{1,0},{-2,0},{2,0},{0,-1}}

-- Points awarded for clearing N lines (multiplied by current level)
local LINE_PTS = {100, 300, 500, 800}

-- Gravity speed in seconds/row for each level (clamps at 0.05)
local function gravity(lv)
  return math.max(0.05, 0.75 - (lv - 1) * 0.07)
end

-- ── Line clearing (pure; unit-tested via mod._test) ───────────────────────────

-- 1-based indices (top row = 1) of every completely-filled row in board `bd`.
local function fullRows(bd, bw, bh)
  local rows = {}
  for r = 1, bh do
    local full = true
    for c = 1, bw do
      if bd[r][c] == 0 then full = false; break end
    end
    if full then rows[#rows + 1] = r end
  end
  return rows
end

-- Remove the given rows from `bd` (mutating it) and refill the SAME count of
-- blank rows at the top, so completed lines collapse and the stack drops down.
--
-- #BUGFIX — the old code interleaved `table.remove(bd, r)` with
-- `table.insert(bd, 1, blank)` in one loop. Each top-insert shifted every
-- not-yet-removed index down by one, so when 2+ lines completed at once it
-- removed the WRONG rows and left some full lines sitting on the board — the
-- "lines clear one at a time instead of all at once" the operator saw. Fix:
-- remove ALL targeted rows first (highest index first, so the lower indices we
-- still need stay valid), THEN add the blanks.
local function removeRows(bd, bw, rows)
  if #rows == 0 then return end
  local order = {}
  for i, r in ipairs(rows) do order[i] = r end
  table.sort(order, function(a, b) return a > b end)
  for _, r in ipairs(order) do table.remove(bd, r) end
  for _ = 1, #rows do
    local blank = {}
    for c = 1, bw do blank[c] = 0 end
    table.insert(bd, 1, blank)
  end
end

mod._test = { fullRows = fullRows, removeRows = removeRows }

-- ── High-score persistence ────────────────────────────────────────────────────

local SCORE_FILE = ".tetris_hs"
local MAX_SCORES = 5

-- Returns the absolute path to the score file for the current user,
-- or nil when no session-bound filesystem (or no session) is around.
-- `fs` is the sandbox-provided securefs proxy (granted by the
-- fs.read/fs.write caps in package.lua); fs.home() resolves the
-- INVOKING user's home per call, so each player gets their own file.
local function scorePath()
  if type(fs) ~= "table" or not fs.home then return nil end
  local ok, home = pcall(fs.home)
  if not ok or type(home) ~= "string" then return nil end
  -- securefs.home() falls back to /tmp when there is no live session;
  -- treat that as "not logged in" rather than sharing one scoreboard.
  if home == "/tmp" then return nil end
  return home .. "/" .. SCORE_FILE
end

-- #SEC L (tetris kernel.fs) — high-score file lives under the user's
-- home directory and is per-user, so it MUST go through securefs to
-- get the per-user ACL. The sandbox's `fs` global IS the session-bound
-- securefs proxy (there is no raw-fs fallback any more), so every
-- read/write below carries the invoking user's principal.

local function getSerializer()
  -- compat.serialization is on the sandbox's allowed-module list and
  -- wraps the same encoder/decoder kernel.serialize uses, so score
  -- files written before this pivot ("return {...}" form) still load.
  local ok, ser = pcall(require, "compat.serialization")
  if ok and type(ser) == "table" then return ser end
  return nil
end

local function loadScores(path)
  if not path or type(fs) ~= "table" then return {} end
  if not fs.exists(path) then return {} end
  local data = fs.readFile(path)
  if not data then return {} end
  local SZ = getSerializer()
  if not SZ then return {} end
  local t = SZ.unserialize(data)
  return type(t) == "table" and t or {}
end

local function saveScores(path, tbl)
  if not path or type(fs) ~= "table" then return end
  local SZ = getSerializer()
  if SZ then fs.writeFile(path, SZ.serialize(tbl)) end
end

-- Insert a new score entry, keep the top MAX_SCORES, persist and return list.
local function recordScore(path, score, lines, level)
  local tbl = loadScores(path)
  tbl[#tbl + 1] = {
    score = score, lines = lines, level = level,
    t = math.floor(computer.uptime()),
  }
  table.sort(tbl, function(a, b) return a.score > b.score end)
  while #tbl > MAX_SCORES do tbl[#tbl] = nil end
  saveScores(path, tbl)
  return tbl
end

-- ── Game ─────────────────────────────────────────────────────────────────────

local function play(o)
  -- Acquire the seat's GPU through the sandboxed component API --------------
  -- (granted by the `component` capability). kernel.display/kernel.event
  -- are not reachable from the pkg sandbox, so the game draws with a raw
  -- GPU proxy and pulls raw signals — the mousetest pattern.
  local gpuAddr = component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return end
  local gpu = component.proxy(gpuAddr)

  local W, H = gpu.getResolution()
  if not W or not H then o("Cannot detect screen size.", 0xFF0000); return end

  -- GPU tier from color depth (1-bit = T1, 4-bit = T2, 8-bit = T3).
  local okDepth, depth = pcall(gpu.getDepth)
  if not okDepth or type(depth) ~= "number" then depth = 1 end
  local tier = depth <= 1 and 1 or (depth <= 4 and 2 or 3)

  if W < MIN_W or H < MIN_H then
    o(string.format("Screen too small: need %dx%d, have %dx%d.",
                    MIN_W, MIN_H, W, H), 0xFF6600)
    o("A Tier 2+ screen (80×24 minimum) is required.", 0xAAAAAA)
    return
  end

  -- Theme (mirrors the kernel.display defaults; T1 collapses to mono).
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, border = 0xFFFFFF,
    title = 0xFFFFFF, highlight = 0xFFFFFF,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA,
    border    = tier == 2 and 0x55FFFF or 0x00FFFF,
    title     = tier == 2 and 0xFFFF55 or 0xFFFF00,
    highlight = tier == 2 and 0x55FF55 or 0x00FF00,
  }

  -- ── Minimal TUI kit: the slice of kernel.display tetris used ─────────────
  -- (set/fill/clear/fit/box/dbox). ASCII borders on T1, where the OC
  -- font may not render the box-drawing glyphs.
  local BOX = tier >= 2
    and { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│",
          DTL = "╔", DTR = "╗", DBL = "╚", DBR = "╝", DH = "═", DV = "║" }
    or  { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|",
          DTL = "+", DTR = "+", DBL = "+", DBR = "+", DH = "=", DV = "|" }

  local D = {}
  function D.set(x, y, text, fg, bg)
    if fg then gpu.setForeground(fg) end
    if bg then gpu.setBackground(bg) end
    gpu.set(x, y, text)
  end
  function D.fill(x, y, w, h, char, fg, bg)
    if fg then gpu.setForeground(fg) end
    if bg then gpu.setBackground(bg) end
    gpu.fill(x, y, w, h, char or " ")
  end
  function D.clear() D.fill(1, 1, W, H, " ", T.fg, 0x000000) end
  function D.fit(text, width)
    text = tostring(text or "")
    if #text > width then return text:sub(1, width - 1) .. "…" end
    return text .. string.rep(" ", width - #text)
  end
  local function drawBoxKind(x, y, w, h, title, style, double)
    style = style or {}
    local bfg = style.border or T.border
    local bbg = style.bg or 0x000000
    local tl  = double and BOX.DTL or BOX.tl
    local tr  = double and BOX.DTR or BOX.tr
    local bl  = double and BOX.DBL or BOX.bl
    local br  = double and BOX.DBR or BOX.br
    local hch = double and BOX.DH  or BOX.h
    local vch = double and BOX.DV  or BOX.v
    D.fill(x, y, w, h, " ", T.fg, bbg)
    D.set(x, y,         tl .. string.rep(hch, w - 2) .. tr, bfg, bbg)
    D.set(x, y + h - 1, bl .. string.rep(hch, w - 2) .. br, bfg, bbg)
    for row = y + 1, y + h - 2 do
      D.set(x,         row, vch, bfg, bbg)
      D.set(x + w - 1, row, vch, bfg, bbg)
    end
    if title then
      local tstr = " " .. title .. " "
      D.set(x + math.floor((w - #tstr) / 2), y, tstr, style.title or T.title, bbg)
    end
  end
  function D.box(x, y, w, h, title, style)  drawBoxKind(x, y, w, h, title, style, false) end
  function D.dbox(x, y, w, h, title, style) drawBoxKind(x, y, w, h, title, style, true)  end

  -- Raw signal pull. Behaves like the old kernel.event.pull for our
  -- purposes: returns the signal tuple, or nil on timeout, and yields
  -- to the machine while waiting.
  local E = { pull = function(timeout) return computer.pullSignal(timeout) end }

  -- Color palette (gracefully degraded per GPU tier) -------------------------
  local pCol = PCOLORS[tier] or PCOLORS[1]

  local C = {
    ghost  = tier >= 3 and 0x1A1A3A or (tier == 2 and 0x222255 or 0x555555),
    empty  = 0x000000,
    border = tier >= 2 and T.border   or 0xFFFFFF,
    title  = tier >= 2 and T.title    or 0xFFFFFF,
    text   = T.fg,
    dim    = T.dim,
    hi     = tier >= 2 and T.highlight or 0xFFFFFF,
    score  = tier == 3 and 0xFFFF00 or (tier == 2 and 0xFFFF55 or 0xFFFFFF),
    danger = tier >= 2 and 0xFF5555   or 0xFFFFFF,
  }

  -- Layout -------------------------------------------------------------------
  local totalW  = PF_BOX_W + 1 + PANEL_W
  local bx      = math.max(1, math.floor((W - totalW) / 2) + 1)
  local by      = math.max(1, math.floor((H - PF_BOX_H) / 2) + 1)
  local pfx     = bx + 1            -- playfield interior: leftmost char X
  local pfy     = by + 1            -- playfield interior: topmost char Y
  local panBX   = bx + PF_BOX_W + 1 -- panel box X
  local pnx     = panBX + 1         -- panel interior X
  local pny     = by + 1            -- panel interior Y
  local pniw    = PANEL_W - 2       -- panel inner width = 16

  local path    = scorePath()       -- user's score file (may be nil)

  -- ── Low-level cell drawing ──────────────────────────────────────────────────

  -- Returns screen coordinates for board cell (col, row), both 0-indexed.
  local function cxy(col, row) return pfx + col * CW, pfy + row end

  -- Draw a filled or empty board cell.
  local function drawCell(col, row, color)
    local sx, sy = cxy(col, row)
    if tier == 1 then
      gpu.setForeground(color ~= 0 and 0xFFFFFF or 0x000000)
      gpu.setBackground(0x000000)
      gpu.set(sx, sy, color ~= 0 and "[]" or "  ")
    else
      gpu.setBackground(color)
      gpu.fill(sx, sy, CW, 1, " ")
    end
  end

  -- Draw a ghost (drop preview) cell.
  local function drawGhost(col, row)
    local sx, sy = cxy(col, row)
    if tier == 1 then
      gpu.setForeground(C.dim); gpu.setBackground(C.empty)
      gpu.set(sx, sy, "::")
    else
      gpu.setBackground(C.ghost); gpu.fill(sx, sy, CW, 1, " ")
    end
  end

  -- ── Board-level drawing ─────────────────────────────────────────────────────

  -- Redraw all 200 board cells from data (used after line clears / full render).
  local function drawBoard(board)
    for r = 1, BH do
      for c = 1, BW do drawCell(c - 1, r - 1, board[r][c]) end
    end
  end

  -- Erase a piece's screen pixels by restoring the board cell underneath.
  -- Used to undraw a piece before moving/rotating it without a full redraw.
  local function eraseOverlay(pt, rot, ox, oy, board)
    for _, off in ipairs(PIECES[pt][rot]) do
      local c, r = ox + off[1], oy + off[2]
      if r >= 0 and r < BH and c >= 0 and c < BW then
        drawCell(c, r, board[r + 1][c + 1])
      end
    end
  end

  -- Draw piece cells (normal or ghost).
  local function drawOverlay(pt, rot, ox, oy, color, isGhost)
    for _, off in ipairs(PIECES[pt][rot]) do
      local c, r = ox + off[1], oy + off[2]
      if r >= 0 and r < BH and c >= 0 and c < BW then
        if isGhost then drawGhost(c, r) else drawCell(c, r, color) end
      end
    end
  end

  -- ── Static UI ───────────────────────────────────────────────────────────────

  local function drawFrame()
    D.clear()
    D.box(bx,    by, PF_BOX_W, PF_BOX_H, "TETRIS",
          {border = C.border, bg = C.empty, title = C.title})
    D.box(panBX, by, PANEL_W,  PF_BOX_H, nil,
          {border = C.border, bg = C.empty})

    -- Static panel section labels
    gpu.setBackground(C.empty)
    gpu.setForeground(C.score)
    gpu.set(pnx, pny,     "SCORE")
    gpu.set(pnx, pny + 3, "LINES")
    gpu.set(pnx, pny + 6, "LEVEL")
    gpu.set(pnx, pny + 9, "NEXT")

    -- Controls (only drawn if the panel has room below the preview)
    local cy = pny + 14
    if cy + 5 <= by + PF_BOX_H - 1 then
      gpu.setForeground(C.dim)
      gpu.set(pnx, cy,     "LR/AD: move")
      gpu.set(pnx, cy + 1, "U/W/X: rot")
      gpu.set(pnx, cy + 2, "Z: rot CCW")
      gpu.set(pnx, cy + 3, "D/dn: soft")
      gpu.set(pnx, cy + 4, "SPC: drop")
      gpu.set(pnx, cy + 5, "P:pause " .. quitLabel() .. ":quit")
    end
  end

  -- Update only the numeric values in the panel (fast path).
  local function updatePanel(score, lines, level, nxt)
    gpu.setBackground(C.empty)

    gpu.setForeground(C.text)
    gpu.set(pnx, pny + 1, D.fit(tostring(score), pniw))
    gpu.set(pnx, pny + 4, D.fit(tostring(lines), pniw))
    gpu.set(pnx, pny + 7, D.fit(tostring(level), pniw))

    -- Clear the 4×4 next-piece preview area then redraw
    for r = 0, 3 do
      gpu.setBackground(C.empty)
      gpu.fill(pnx, pny + 10 + r, pniw, 1, " ")
    end
    if nxt then
      for _, off in ipairs(PIECES[nxt][1]) do
        local sx = pnx + off[1] * CW
        local sy = pny + 10 + off[2]
        if tier == 1 then
          gpu.setForeground(0xFFFFFF); gpu.setBackground(C.empty)
          gpu.set(sx, sy, "[]")
        else
          gpu.setBackground(pCol[nxt]); gpu.fill(sx, sy, CW, 1, " ")
        end
      end
    end
  end

  -- ── Board logic ─────────────────────────────────────────────────────────────

  local function newBoard()
    local b = {}
    for r = 1, BH do
      b[r] = {}
      for c = 1, BW do b[r][c] = 0 end
    end
    return b
  end

  local function canPlace(board, pt, rot, ox, oy)
    for _, off in ipairs(PIECES[pt][rot]) do
      local c, r = ox + off[1], oy + off[2]
      if c < 0 or c >= BW          then return false end
      if r >= BH                   then return false end
      if r >= 0 and board[r + 1][c + 1] ~= 0 then return false end
    end
    return true
  end

  -- Drop the piece as far as it will go; return the landing Y.
  local function calcGhost(board, pt, rot, ox, oy)
    local gy = oy
    while canPlace(board, pt, rot, ox, gy + 1) do gy = gy + 1 end
    return gy
  end

  -- ── 7-bag randomiser ────────────────────────────────────────────────────────
  -- Fills successive bags of all 7 piece types in random order,
  -- preventing long piece droughts.

  local bag, bagI = {}, 0

  local function nextPiece()
    if bagI >= #bag then
      bag = {1, 2, 3, 4, 5, 6, 7}
      for i = #bag, 2, -1 do
        local j = math.random(i)
        bag[i], bag[j] = bag[j], bag[i]
      end
      bagI = 0
    end
    bagI = bagI + 1
    return bag[bagI]
  end

  -- ── Single game session ──────────────────────────────────────────────────────

  local function runGame()
    local board = newBoard()
    local score, lines, level = 0, 0, 1

    bag, bagI = {}, 0
    math.randomseed(math.floor(computer.uptime() * 7331) % 2147483647)

    -- Active piece state (all values 0-indexed relative to board)
    local pt, rot, ox, oy, gy

    -- Next piece type
    local nxt = nextPiece()

    -- ── Helpers ─────────────────────────────────────────────────────────────

    -- Centred pause overlay. Shared by Ctrl+P and the tos_focus resume,
    -- so a game coming back from the background looks paused in exactly
    -- the way a game the operator paused by hand does.
    local function drawPauseOverlay()
      local pw = 14
      local px2 = bx + math.floor((PF_BOX_W - pw) / 2)
      local py2 = by + math.floor(PF_BOX_H / 2) - 1
      D.dbox(px2, py2, pw, 3, "PAUSED", {border = C.title, bg = C.empty})
    end

    local function fullRender()
      drawFrame()
      drawBoard(board)
      updatePanel(score, lines, level, nxt)
      if pt then
        if gy ~= oy then drawOverlay(pt, rot, ox, gy, nil, true) end
        drawOverlay(pt, rot, ox, oy, pCol[pt], false)
      end
    end

    -- Erase old position, recalculate ghost, redraw. Called after every move.
    local function refresh(oP, oR, oX, oY, oG)
      if oG ~= oY then eraseOverlay(oP, oR, oX, oG, board) end
      eraseOverlay(oP, oR, oX, oY, board)
      if gy ~= oy then drawOverlay(pt, rot, ox, gy, nil, true) end
      drawOverlay(pt, rot, ox, oy, pCol[pt], false)
    end

    -- Spawn the queued piece; return false → game over (spawn blocked).
    local function spawn()
      pt  = nxt
      nxt = nextPiece()
      rot = 1
      ox  = math.floor(BW / 2) - 2   -- centre horizontally (0-indexed col 3)
      oy  = -2                         -- start two rows above the visible board
      gy  = calcGhost(board, pt, rot, ox, oy)
      return canPlace(board, pt, rot, ox, oy)
    end

    -- Lock piece to board, clear complete lines, spawn next piece.
    -- Returns false when the new spawn position is blocked (game over).
    local function lock()
      -- Stamp cells onto the board array AND draw them on screen.
      -- Drawing immediately ensures the piece is visible in its final
      -- position even when no lines are cleared (which skips drawBoard).
      local color = pCol[pt]
      local aboveBoard = false
      for _, off in ipairs(PIECES[pt][rot]) do
        local c, r = ox + off[1], oy + off[2]
        if r < 0 then
          aboveBoard = true  -- piece locked with cells above the playfield
        elseif r < BH and c >= 0 and c < BW then
          board[r + 1][c + 1] = color
          drawCell(c, r, color)
        end
      end

      -- Lock out: if any cell is above the visible board, game over
      if aboveBoard then return false end

      -- Detect complete rows (all of them, before removing any).
      local cleared = fullRows(board, BW, BH)

      if #cleared > 0 then
        -- Flash cleared rows white briefly
        for _, r in ipairs(cleared) do
          gpu.setBackground(0xFFFFFF)
          gpu.fill(pfx, pfy + r - 1, BW * CW, 1, " ")
        end
        E.pull(0.07)   -- brief pause; yields to scheduler properly

        -- Collapse ALL cleared rows at once (see removeRows — the old inline
        -- loop cleared the wrong rows when 2+ lines went together).
        removeRows(board, BW, cleared)

        -- Update score / lines / level
        local n = #cleared
        score = score + (LINE_PTS[n] or LINE_PTS[4]) * level
        lines = lines + n
        level = math.floor(lines / 10) + 1

        drawBoard(board)
      end

      -- Spawn next piece; return false signals game over
      if not spawn() then return false end

      -- AFTER spawn(), not before: spawn() consumes `nxt` and draws a new
      -- one, so painting the preview first showed the piece that had just
      -- appeared on the board and left the panel one piece stale. It only
      -- caught up on the next soft-drop, which is the one other place that
      -- calls updatePanel — hence "the NEXT box doesn't change until I
      -- press down".
      updatePanel(score, lines, level, nxt)

      if gy ~= oy then drawOverlay(pt, rot, ox, gy, nil, true) end
      drawOverlay(pt, rot, ox, oy, pCol[pt], false)
      return true
    end

    -- Try to move the current piece by (dx, dy); return success.
    local function move(dx, dy)
      if not canPlace(board, pt, rot, ox + dx, oy + dy) then return false end
      local oP, oR, oX, oY, oG = pt, rot, ox, oy, gy
      ox = ox + dx;  oy = oy + dy
      gy = calcGhost(board, pt, rot, ox, oy)
      refresh(oP, oR, oX, oY, oG)
      return true
    end

    -- Try to rotate the piece by dir (1=CW, -1=CCW); includes wall-kick offsets.
    local function rotate(dir)
      local nr    = ((rot - 1 + dir) % 4) + 1
      for _, k in ipairs(WALL_KICKS) do
        if canPlace(board, pt, nr, ox + k[1], oy + k[2]) then
          local oP, oR, oX, oY, oG = pt, rot, ox, oy, gy
          rot = nr;  ox = ox + k[1];  oy = oy + k[2]
          gy  = calcGhost(board, pt, rot, ox, oy)
          refresh(oP, oR, oX, oY, oG)
          return true
        end
      end
      return false
    end

    -- ── Game loop ────────────────────────────────────────────────────────────

    if not spawn() then return 0, 0, 1, false end
    fullRender()

    local lastDrop = computer.uptime()
    local paused   = false

    while true do
      local speed   = gravity(level)
      local now     = computer.uptime()
      local timeout = paused and 1.0 or math.max(0, speed - (now - lastDrop))

      -- key_down is (name, keyboardAddr, CHAR, code). The char was being
      -- thrown away into `_` and stdQuit was then handed a nil GLOBAL `ch`,
      -- so every CHARACTER binding for quit was dead: ^Q did nothing and
      -- only the F10/Esc scancodes still worked. An operator who rebinds
      -- quit to another ^key would have had no way out at all.
      -- (test_tetris_sandbox.lua)
      local sig, _, ch, code = E.pull(timeout)

      -- The seat came back after a Ctrl+B suspend. Repaint everything,
      -- and come back PAUSED: the piece was frozen while we were away
      -- (this package declares background = "freeze"), so resuming
      -- straight into gravity would cost a run the operator had no
      -- chance to react to.
      if sig == "tos_focus" then
        paused = true
        fullRender()
        drawPauseOverlay()
        lastDrop = computer.uptime()

      -- ── Input handling ───────────────────────────────────────────────────
      elseif sig == "key_down" then

        if code == K.Q or stdQuit(ch, code) then
          return score, lines, level, true   -- user quit (no score recorded)

        elseif code == K.P then
          paused = not paused
          if paused then drawPauseOverlay() else fullRender() end

        elseif not paused then

          if     code == K.LEFT  or code == K.A then  move(-1, 0)
          elseif code == K.RIGHT or code == K.D then  move( 1, 0)
          elseif code == K.UP    or code == K.W
              or code == K.X                    then  rotate(1)
          elseif code == K.Z                    then  rotate(-1)

          elseif code == K.DOWN or code == K.S then
            -- Soft drop: move down 1 (+1 pt per row); if blocked, lock immediately
            if move(0, 1) then
              score = score + 1
              updatePanel(score, lines, level, nxt)
              lastDrop = computer.uptime()
            else
              if not lock() then return score, lines, level, false end
              lastDrop = computer.uptime()
            end

          elseif code == K.SPACE then
            -- Hard drop: erase piece + ghost at current position first
            if gy ~= oy then eraseOverlay(pt, rot, ox, gy, board) end
            eraseOverlay(pt, rot, ox, oy, board)
            -- Teleport to ghost position, lock
            score    = score + 2 * math.max(0, gy - oy)
            oy       = gy
            if not lock() then return score, lines, level, false end
            lastDrop = computer.uptime()
          end
        end
      end

      -- ── Gravity tick ─────────────────────────────────────────────────────
      if not paused then
        now = computer.uptime()
        if now - lastDrop >= speed then
          lastDrop = now
          if not move(0, 1) then
            if not lock() then return score, lines, level, false end
          end
        end
      end
    end -- while true
  end -- runGame

  -- ── Game-over overlay ───────────────────────────────────────────────────────

  local function showGameOver(fs, fl, fv, bestScores)
    local dw = PF_BOX_W        -- full playfield box width (22 chars)
    local dh = 10
    local iw = dw - 4          -- interior usable width (text inset 2 from each edge)
    local dx = bx
    local dy = by + math.floor((PF_BOX_H - dh) / 2)

    D.dbox(dx, dy, dw, dh, "GAME OVER",
           {border = C.danger, bg = C.empty})

    gpu.setBackground(C.empty)

    gpu.setForeground(C.text)
    gpu.set(dx + 2, dy + 2, D.fit(string.format("Score: %d", fs), iw))
    gpu.set(dx + 2, dy + 3, D.fit(string.format("Ln: %d  Lv: %d", fl, fv), iw))

    if bestScores and #bestScores > 0 then
      gpu.setForeground(C.score)
      gpu.set(dx + 2, dy + 4, D.fit(string.format("Best: %d", bestScores[1].score), iw))
      -- Flag a new record: the player's score was just inserted at [1] if it's
      -- the best. It's a "new high score" if it's their first game ever (1 entry)
      -- or if it strictly beat the previous #1 (now at position 2).
      local isNew = fs > 0 and fs == bestScores[1].score
          and (#bestScores == 1 or fs > bestScores[2].score)
      if isNew then
        gpu.setForeground(C.hi)
        gpu.set(dx + 2, dy + 5, D.fit("* NEW HIGH SCORE! *", iw))
      end
    end

    gpu.setForeground(C.dim)
    gpu.set(dx + 2, dy + 7, D.fit("[R] Play Again", iw))
    gpu.set(dx + 2, dy + 8, D.fit("[Q] Quit", iw))

    -- Wait for R (replay) or Q/Esc (quit)
    while true do
      local sig, _, ch, code = E.pull(120)   -- 2-min idle timeout
      if sig == "key_down" then
        if code == K.R or code == K.ENTER then return true  end
        if code == K.Q or stdQuit(ch, code) then return false end
      elseif not sig then
        return false   -- timed out
      end
    end
  end

  -- ── Outer replay loop ───────────────────────────────────────────────────────
  -- Wrapped in pcall so the screen is always restored, even on runtime errors.

  local ok, err = pcall(function()
    local playing = true
    while playing do
      local fs, fl, fv, quit = runGame()
      if quit then
        playing = false
      else
        -- Persist the score and show the game-over screen
        local best = recordScore(path, fs, fl, fv)
        playing = showGameOver(fs, fl, fv, best)
      end
    end
  end)

  D.clear()  -- Hand screen back to the shell cleanly
  if not ok then
    o("Tetris crashed: " .. tostring(err), 0xFF0000)
  end
end

-- ── Show scores command ───────────────────────────────────────────────────────

local function showScores(o)
  local path = scorePath()
  if not path then
    o("Not logged in — no personal score file to read.", 0xFF6600)
    return
  end

  -- Display name from the home dir ("/home/alice/..." → alice,
  -- "/root/..." → root). The sandbox has no user-module access, but
  -- the home path is already the per-user identity we need.
  local user = path:match("^/home/([^/]+)/") or path:match("^/([^/]+)/") or "?"
  local scores = loadScores(path)

  if #scores == 0 then
    o("No high scores yet for " .. user .. ".", 0xAAAAAA)
    o("Play your first game:  tetris", 0x555555)
    return
  end

  o(string.format("  High scores — %s", user), 0xFFFF00)
  o(string.rep("─", 42), 0x444444)
  o(string.format("  %-3s  %-12s  %-8s  %s", "#", "SCORE", "LINES", "LEVEL"), 0xAAAAAA)
  for i, s in ipairs(scores) do
    local star = (i == 1) and " ★" or "  "
    o(string.format("  %-3d  %-12d  %-8d  %d%s", i, s.score, s.lines, s.level, star),
      i == 1 and 0xFFFF00 or 0xFFFFFF)
  end
end

-- ── Command dispatcher ────────────────────────────────────────────────────────

local function tetrisCmd(args, o)
  -- pkg dispatch convention (same as the tape module): args holds only
  -- the arguments, NOT the command name — so the subcommand is args[1].
  -- (The pre-pivot kernel.modules path passed the full argv; reading
  -- args[2] here made `tetris scores` silently launch the game.)
  local sub = args[1]

  if sub == nil then
    play(o)

  elseif sub == "scores" or sub == "hs" then
    showScores(o)

  elseif sub == "help" or sub == "--help" or sub == "-h" then
    o("=== Tetris ===", 0xFFFF00)
    o("", 0xFFFFFF)
    o("  tetris           Launch the game (requires T2+ screen, 80×24+)", 0xFFFFFF)
    o("  tetris scores    Show your personal high-score table", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" In-game controls:", 0xAAAAAA)
    o("  ← → / A D       Move left / right", 0xFFFFFF)
    o("  ↑ / W / X       Rotate clockwise", 0xFFFFFF)
    o("  Z               Rotate counter-clockwise", 0xFFFFFF)
    o("  ↓ / S           Soft drop  (+1 pt per row)", 0xFFFFFF)
    o("  Space           Hard drop  (+2 pts per row)", 0xFFFFFF)
    o("  P               Pause / unpause", 0xFFFFFF)
    o("  Q / Esc         Quit to shell", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" Scoring:", 0xAAAAAA)
    o("  1 line  = 100 × level    2 lines = 300 × level", 0xFFFFFF)
    o("  3 lines = 500 × level    4 lines = 800 × level  (Tetris!)", 0xFFFFFF)
    o("  Level increases every 10 lines; speed increases with level.", 0xAAAAAA)
    o("", 0xFFFFFF)
    o(" High scores are stored in ~/.tetris_hs (one file per user).", 0x555555)

  else
    o("Unknown subcommand: " .. tostring(sub), 0xFF6600)
    o("Usage: tetris [scores | help]", 0xAAAAAA)
  end
end

-- ── Module export ─────────────────────────────────────────────────────────────

mod.commands = { tetris = tetrisCmd }

return mod