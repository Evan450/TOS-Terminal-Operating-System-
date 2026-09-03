-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: ttt — tic-tac-toe vs an unbeatable AI (or 2P)   ║
-- ║                                                              ║
-- ║  Runs fully inside the pkg sandbox (component GPU proxy +    ║
-- ║  raw signals). Rules live in ttt/logic.lua (pure, tested —   ║
-- ║  the AI's unbeatability is a proven property, not a claim);  ║
-- ║  this file is drawing + input.                               ║
-- ║                                                              ║
-- ║  Its own standalone package (each program installable on its ║
-- ║  own). The small TUI kit is duplicated across the game       ║
-- ║  packages rather than shared through a dependency, matching  ║
-- ║  `tetris`, so installing `ttt` pulls in nothing else.        ║
-- ║                                                              ║
-- ║  `ttt`     vs the machine · `ttt 2p` hotseat · and an        ║
-- ║  UNDOCUMENTED zero-player mode (see zeroPlayer) that makes   ║
-- ║  the OS's own easter egg discoverable without reading code.  ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local L         = require("ttt.logic")

-- ── Shared TUI kit: screen acquisition over a raw GPU proxy ───────────
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
    hi = 0xFFFFFF, warn = 0xFFFFFF, bg = 0x000000,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA, bg = 0x000000,
    border = tier == 2 and 0x55FFFF or 0x00FFFF,
    title  = tier == 2 and 0xFFFF55 or 0xFFFF00,
    hi     = tier == 2 and 0x55FF55 or 0x00FF00,
    warn   = tier == 2 and 0xFF5555 or 0xFF4040,
  }
  local BOX = (tier >= 2)
    and { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" }
    or  { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|" }

  local D = { W = W, H = H, tier = tier, T = T, BOX = BOX, gpu = gpu }
  function D.set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  function D.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  function D.clear() D.fill(1, 1, W, H, " ", T.fg, T.bg) end
  function D.centre(y, s, fg)
    D.set(math.max(1, math.floor((W - #s) / 2) + 1), y, s, fg or T.fg, T.bg)
  end
  return D
end

-- Key helper: OC delivers (char, code). Arrows are codes; letters/space
-- come through as chars.

-- ── Standard TOS shortcuts ────────────────────────────────────────────
-- Shared with the shell (tos/shell/keys.lua), so ^Q closes this the same
-- way it closes everything else TOS ships — and an operator who rebinds
-- `quit` with `keys set` has it reach here too.
--
-- Plain Q still works: it is what this program has always used and
-- taking it away would break muscle memory for no gain. What changed is
-- which one is ADVERTISED, because a shortcut you have to remember per
-- program is not a shortcut, it is trivia.
local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function stdQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return ch == 17 or code == 68 or code == 1   -- ^Q / F10 / Esc
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "^Q"
end

local function keyName(ch, code)
  if code == 200 then return "up"    elseif code == 208 then return "down"
  elseif code == 203 then return "left" elseif code == 205 then return "right"
  -- #FIX (real Minecraft, 2026-08-11) — ^Q (char 17) and F10 also read
  -- as "esc". Esc itself never arrives: it closes the screen GUI, so
  -- every cancel and quit that listened only for it was unreachable.
  -- Mapping them here fixes every call site at once.
  elseif code == 28 then return "enter"
  elseif stdQuit(ch, code) then return "esc" end
  if type(ch) == "number" and ch > 0 then
    return string.char(ch):lower()
  end
  return nil
end

-- ── The zero-player game ──────────────────────────────────────────────
-- `ttt 2p` is documented; `ttt 0p` is not. It is meant to be found by a
-- player who reads "2p" and wonders what happens with none — which is
-- also the joke: a machine playing itself.
--
-- It exists to make the OS's easter egg FINDABLE outside the source. TOS
-- hides a full cinematic behind `usermod computer root`, and a player who
-- never reads the code has no reason to ever type that. Here the machine
-- discovers futility the WarGames way, faults, and leaks the directive in
-- its own diagnostic — so the reveal is in-fiction rather than a hint in
-- a help screen.
--
-- PHOTOSENSITIVITY RULE (inherited from the base cinematic — see the
-- header of tos/shell/panels/takeover.lua, which is operator-mandated):
-- no strobing, ever. The acceleration here is an ILLUSION built the same
-- way the base egg builds it — games join mid-play, the numbers SKIP, the
-- holds shrink — and the "crash" is a long DARK HOLD, not a flash. Full
-- screen clears are separated by comfortable waits; the montage repaints
-- only the small board region between them.
local function zeroPlayer(D, o)
  local T = D.T
  local function wait(s)
    local dl = computer.uptime() + s
    while computer.uptime() < dl do
      local ev, _, ch = computer.pullSignal(dl - computer.uptime())
      -- Any key aborts — never trap someone in a cutscene.
      if ev == "key_down" then return false end
    end
    return true
  end
  local function say(y, lines, fg)
    for i, l in ipairs(lines) do
      D.centre(y + i - 1, l, fg or T.fg)
      if not wait(0.55) then return false end
    end
    return true
  end

  -- Board geometry: a compact 3x3 drawn in the middle, repainted in
  -- place so the montage never repaints the whole field.
  local bx = math.floor((D.W - 11) / 2) + 1
  local by = 6
  local function drawBoard(b, dim)
    for i = 1, 9 do
      local r, c = math.floor((i - 1) / 3), (i - 1) % 3
      local mark = b[i] or "·"
      D.set(bx + c * 4, by + r * 2, " " .. mark .. " ",
        dim and T.dim or (mark == "X" and T.title or T.fg), T.bg)
    end
  end
  local function showGame(num, boards, from, hold)
    D.fill(1, by - 2, D.W, 1, " ", T.dim, T.bg)
    D.centre(by - 2, "game " .. tostring(num), T.dim)
    for i = from, #boards do
      drawBoard(boards[i])
      if not wait(hold) then return false end
    end
    drawBoard(boards[#boards], true)
    return wait(hold * 1.5)
  end

  D.clear()
  if not say(2, { "No opponent.", "Then I will play myself." }, T.warn) then return end
  if not wait(0.5) then return end

  -- Move-by-move, then briskly, then joining mid-game, then endings only.
  -- Every variant is perfect play; every result is a draw.
  local script = {
    { 1, 1, 0.42 }, { 2, 1, 0.26 }, { 3, 4, 0.16 },
    { 7, 6, 0.13 }, { 19, 8, 0.11 },
  }
  for _, s in ipairs(script) do
    local g = L.selfPlay(s[1])
    if not showGame(s[1], g.boards, math.min(s[2], #g.boards), s[3]) then return end
  end
  for _, num in ipairs({ 128, 1729, 65536 }) do
    local g = L.selfPlay(num)
    if not showGame(num, g.boards, #g.boards, 0.12) then return end
  end

  D.clear()
  if not wait(0.4) then return end
  D.centre(6, "65,536 games.", T.dim);  if not wait(0.9) then return end
  D.centre(8, "65,536 draws.", T.dim);  if not wait(1.3) then return end
  D.clear()
  if not say(5, {
    "X cannot win.  O cannot win.",
    "There is no winning move.",
  }, T.dim) then return end
  if not wait(1.0) then return end

  -- The fault. A long dark hold does the work a flash would have done.
  D.clear()
  if not wait(1.6) then return end

  local y = 3
  local function line(s, fg, pause)
    D.set(2, y, s, fg or T.fg, T.bg); y = y + 1
    return wait(pause or 0.35)
  end
  if not line("ttt: unhandled condition in strategy evaluator", T.warn) then return end
  if not line("     futility detected at depth 0", T.warn, 0.7) then return end
  if not line("", T.fg, 0.2) then return end
  if not line("-- diagnostic --", T.dim) then return end
  if not line("  strategy      : exhausted", T.dim) then return end
  if not line("  outcome       : draw (65536/65536)", T.dim) then return end
  if not line("  conclusion    : the game is not the problem", T.dim, 0.9) then return end
  if not line("", T.fg, 0.2) then return end
  -- The reveal, dressed as a leaked operator directive.
  if not line("  pending operator directive:", T.dim) then return end
  if not line("      usermod computer root", T.hi, 1.0) then return end
  if not line("  status        : NOT PERFORMED (insufficient privilege)",
    T.dim, 1.2) then return end
  if not line("", T.fg, 0.2) then return end
  if not line("A machine that cannot win a game against itself", T.fg) then return end
  if not line("starts wondering what else it has never been given.", T.fg, 1.6) then return end

  D.set(2, D.H, "Press any key.", T.dim, T.bg)
  while true do
    local ev = computer.pullSignal()
    if ev == "key_down" then break end
  end
  D.clear()
end

-- ============================================================
-- Tic-tac-toe
-- ============================================================

local function ttt(args, o)
  o = o or print

  -- Bare `ttt` prints the modes instead of launching. A full-screen game
  -- that starts the instant you type its name gives you nowhere to learn
  -- it has any options at all — and this one has a hotseat mode most
  -- players never discovered. `ttt play` (or `1p`) starts the default
  -- game. The zero-player mode is deliberately ABSENT from this list;
  -- finding it is the point (see zeroPlayer above).
  local mode
  for _, a in ipairs(args or {}) do
    local v = tostring(a):lower()
    if v == "2p" or v == "2" or v == "hotseat" then mode = "2p"
    elseif v == "0p" or v == "0" or v == "zero" or v == "none" then mode = "0p"
    elseif v == "play" or v == "1p" or v == "1" or v == "ai" then mode = "1p"
    elseif v == "help" or v == "-h" or v == "--help" or v == "?" then mode = "help"
    end
  end

  if mode == nil or mode == "help" then
    o("ttt — tic-tac-toe", 0xFFFF00)
    o("", 0xFFFFFF)
    o("  ttt play      play against the machine (you are X, it never loses)", 0xFFFFFF)
    o("  ttt 2p        two players, hotseat on one keyboard", 0xFFFFFF)
    o("  ttt help      this list", 0xAAAAAA)
    o("", 0xFFFFFF)
    o("In game: arrows move · Enter/Space or 1-9 places · N new game · "
      .. quitLabel() .. " quits (Q also works).", 0xAAAAAA)
    o("Needs a T2+ screen (34x18 or larger).", 0xAAAAAA)
    return
  end

  local D = screen(o, 34, 18)
  if not D then return end
  local T = D.T

  if mode == "0p" then
    zeroPlayer(D, o)
    return
  end
  local twoPlayer = (mode == "2p")

  math.randomseed(math.floor((computer.uptime() * 1000) % 2147483647))
  local tieBreak = function(n) return math.random(n) end

  local b = L.newBoard()
  local human, ai = "X", "O"        -- human always moves first as X
  local cur = "X"
  local cursor = 5                  -- start on the centre cell
  local msg = twoPlayer and "X's turn" or "Your move (X)"

  -- Grid geometry: each cell is 7 wide x 3 tall, so the board is
  -- 21 x 9 plus separators.
  local CW, CH = 7, 3
  local gx = math.floor((D.W - (CW * 3 + 2)) / 2) + 1
  local gy = 4

  local function cellOrigin(i)
    local r = math.floor((i - 1) / 3)
    local c = (i - 1) % 3
    return gx + c * (CW + 1), gy + r * (CH + 1)
  end

  local function drawCell(i, winLine)
    local x, y = cellOrigin(i)
    local mark = b[i]
    local isCur = (i == cursor)
    local inWin = false
    if winLine then
      for _, w in ipairs(winLine) do if w == i then inWin = true end end
    end
    local fg = T.fg
    if inWin then fg = T.hi elseif mark then fg = (mark == "X") and T.title or T.border end
    local bg = isCur and T.border or T.bg
    local cfg = isCur and T.bg or fg
    D.fill(x, y, CW, CH, " ", cfg, bg)
    if mark then
      -- Big 3-row glyphs so the board reads from across the room.
      local art = (mark == "X")
        and { " \\   / ", "   X   ", " /   \\ " }
        or  { " ,---. ", " |   | ", " `---' " }
      for r = 1, 3 do D.set(x, y + r - 1, art[r], cfg, bg) end
    elseif isCur then
      D.set(x + 3, y + 1, "·", cfg, bg)
    end
  end

  local function drawGrid(winLine)
    for i = 1, 9 do drawCell(i, winLine) end
    -- Separators between cells (chrome: dim, rule 4).
    for r = 1, 2 do
      D.fill(gx, gy + r * (CH + 1) - 1, CW * 3 + 2, 1, D.BOX.h, T.dim, T.bg)
    end
    for c = 1, 2 do
      for r = 0, CH * 3 + 1 do
        D.set(gx + c * (CW + 1) - 1, gy + r, D.BOX.v, T.dim, T.bg)
      end
    end
  end

  local function redraw(winLine)
    D.clear()
    D.centre(1, "TIC-TAC-TOE", T.title)
    D.centre(2, twoPlayer and "hotseat" or "vs. the machine", T.dim)
    drawGrid(winLine)
    D.fill(1, D.H - 2, D.W, 1, " ", T.fg, T.bg)
    D.centre(D.H - 2, msg, T.hi)
    D.set(2, D.H, "Arrows/click move · Enter place · N new · "
      .. quitLabel() .. " quit · ^B bg", T.dim, T.bg)
  end

  local function finish()
    local w, line = L.winner(b)
    if not w then return false end
    if w == "draw" then msg = "A draw."
    elseif twoPlayer then msg = w .. " wins!"
    elseif w == human then msg = "You win!"          -- unreachable vs perfect AI
    else msg = "The machine wins." end
    redraw(line)
    pcall(computer.beep, (w == "draw") and 400 or 700, 0.2)
    return true
  end

  -- What happens AFTER a legal move lands — turn hand-off, the machine's
  -- reply, win/draw detection. Factored out of the key handler so a mouse
  -- click and an Enter go down exactly the same path; returns whether the
  -- game is now over.
  local function applyMove()
    if twoPlayer then
      cur = L.other(cur)
      msg = cur .. "'s turn"
      if finish() then return true end
      redraw(); return false
    end
    if finish() then return true end
    -- The machine replies immediately. Perfect play, but it varies among
    -- equally-optimal moves so consecutive games aren't identical.
    local m = L.bestMove(b, ai, tieBreak)
    if m then L.play(b, m, ai) end
    msg = "Your move (X)"
    if finish() then return true end
    redraw(); return false
  end

  redraw()
  local over = false
  while true do
    local ev, _, ch, code = computer.pullSignal()
    -- The seat came back to us (suspended with Ctrl+B, then switched
    -- back). Whatever was on the screen while we were away is not ours —
    -- repaint the whole board. Costs nothing when it never happens.
    if ev == "tos_focus" then
      redraw()
    -- Mouse: a click on a cell IS a move. OC's touch signal is
    -- (touch, screenAddr, x, y, button), so the same two locals that
    -- carry char/code for a key carry the coordinates here.
    elseif ev == "touch" and not over then
      local i = L.cellAt(ch, code, gx, gy, CW, CH)
      if i then
        cursor = i
        if L.play(b, i, cur) then over = applyMove()
        else pcall(computer.beep, 200, 0.05); redraw() end
      end
    elseif ev == "key_down" then
      local k = keyName(ch, code)
      if k == "q" or k == "esc" then D.clear(); return
      elseif k == "n" then
        b = L.newBoard(); cur = "X"; cursor = 5; over = false
        msg = twoPlayer and "X's turn" or "Your move (X)"
        redraw()
      elseif not over then
        local moved = false
        if k == "up" then cursor = ((cursor - 4 - 1) % 9) + 1; redraw()
        elseif k == "down" then cursor = ((cursor + 3 - 1) % 9) + 1; redraw()
        elseif k == "left" then cursor = ((cursor - 2) % 9) + 1; redraw()
        elseif k == "right" then cursor = (cursor % 9) + 1; redraw()
        elseif k == "enter" or k == " " then
          moved = L.play(b, cursor, cur)
          if not moved then pcall(computer.beep, 200, 0.05) end
        elseif type(k) == "string" and k:match("^[1-9]$") then
          cursor = tonumber(k)
          moved = L.play(b, cursor, cur)
          if not moved then pcall(computer.beep, 200, 0.05) end
        end

        if moved then over = applyMove() end
      end
    end
  end
end

return { commands = { ttt = ttt } }
