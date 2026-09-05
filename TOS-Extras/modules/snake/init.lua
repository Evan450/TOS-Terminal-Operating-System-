-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: snake — classic snake, per-user high scores     ║
-- ║                                                              ║
-- ║  Runs fully inside the pkg sandbox: draws through the        ║
-- ║  sandboxed `component` GPU proxy and pulls raw signals with  ║
-- ║  computer.pullSignal (kernel.display / kernel.event are NOT  ║
-- ║  reachable from package code). Rules live in snake/logic.lua ║
-- ║  (pure, unit-tested); this file is drawing + input only.     ║
-- ║                                                              ║
-- ║  Its own package on purpose (operator's model: each program  ║
-- ║  is independently installable). The small TUI kit below is   ║
-- ║  deliberately duplicated across the game packages rather     ║
-- ║  than shared through a dependency — the same way `tetris`    ║
-- ║  carries its own — so installing `snake` pulls in nothing    ║
-- ║  else.                                                       ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local L         = require("snake.logic")

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
  function D.box(x, y, w, h, title)
    D.set(x, y, BOX.tl .. string.rep(BOX.h, w - 2) .. BOX.tr, T.border, T.bg)
    for r = 1, h - 2 do
      D.set(x, y + r, BOX.v, T.border, T.bg)
      D.set(x + w - 1, y + r, BOX.v, T.border, T.bg)
    end
    D.set(x, y + h - 1, BOX.bl .. string.rep(BOX.h, w - 2) .. BOX.br, T.border, T.bg)
    if title then
      D.set(x + math.floor((w - #title - 2) / 2), y, " " .. title .. " ", T.title, T.bg)
    end
  end
  function D.centre(y, s, fg)
    D.set(math.max(1, math.floor((W - #s) / 2) + 1), y, s, fg or T.fg, T.bg)
  end
  return D
end

-- Per-user high scores. The sandbox hands us a session-bound `fs`, so
-- ~/ resolves to the CALLING user's home — every player keeps their own
-- board, exactly like tetris.
local MAX_SCORES = 5
local function loadScores(path)
  if not (fs and fs.exists and fs.exists(path)) then return {} end
  local okR, data = pcall(fs.readFile, path)
  if not okR or type(data) ~= "string" then return {} end
  local t = {}
  for line in (data .. "\n"):gmatch("(.-)\n") do
    local n, s = line:match("^(%d+)%s+(.*)$")
    if n then t[#t + 1] = { score = tonumber(n), when = s } end
  end
  return t
end
local function saveScores(path, t)
  if not (fs and fs.writeFile) then return end
  local out = {}
  for i, e in ipairs(t) do
    if i > MAX_SCORES then break end
    out[#out + 1] = tostring(e.score) .. " " .. tostring(e.when or "")
  end
  pcall(fs.writeFile, path, table.concat(out, "\n"))
end
local function recordScore(path, score)
  local t = loadScores(path)
  t[#t + 1] = { score = score, when = string.format("up %.0fs", computer.uptime()) }
  table.sort(t, function(a, b) return (a.score or 0) > (b.score or 0) end)
  while #t > MAX_SCORES do t[#t] = nil end
  saveScores(path, t)
  return t
end

-- Key helper: OC delivers (char, code). Arrows are codes; letters chars.

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

-- ============================================================
-- Snake
-- ============================================================

local function snake(args, o)
  o = o or print
  local BW, BH = 40, 16                     -- board cells
  local D = screen(o, BW + 4, BH + 6)
  if not D then return end
  local T = D.T

  math.randomseed(math.floor((computer.uptime() * 1000) % 2147483647))
  local rand = function(n) return math.random(n) end

  local ox = math.floor((D.W - BW) / 2)      -- board origin (inside the box)
  local oy = 3
  local s = L.newSnake(BW, BH)
  L.placeFood(s, rand)

  local HEAD = (D.tier >= 2) and "█" or "@"
  local BODY = (D.tier >= 2) and "▒" or "o"
  local FOOD = (D.tier >= 2) and "♦" or "*"

  local function drawFrame()
    D.clear()
    D.box(ox - 1, oy - 1, BW + 2, BH + 2, "Snake")
    D.centre(1, "SNAKE", T.title)
    D.set(2, D.H, "Arrows/WASD move · P pause · " .. quitLabel() .. " quit", T.dim, T.bg)
  end
  local function drawScore()
    local txt = string.format(" Score %d ", s.score)
    D.set(D.W - #txt - 1, 1, txt, T.hi, T.bg)
  end
  -- Incremental drawing: only the cells that changed. A full board
  -- repaint every tick would be BW*BH gpu.set calls across the OC
  -- bridge — the single most expensive thing a game can do here.
  local function drawCell(x, y, ch, fg)
    D.set(ox + x - 1, oy + y - 1, ch, fg, T.bg)
  end

  drawFrame(); drawScore()
  for i, seg in ipairs(s.body) do
    drawCell(seg.x, seg.y, i == 1 and HEAD or BODY, i == 1 and T.hi or T.fg)
  end
  if s.food then drawCell(s.food.x, s.food.y, FOOD, T.warn) end

  local paused = false
  local nextTick = computer.uptime() + L.snakeDelay(0)
  while true do
    local timeout = math.max(0, nextTick - computer.uptime())
    local ev, _, ch, code = computer.pullSignal(timeout)
    -- The seat came back after a Ctrl+B suspend. Repaint the whole
    -- board — and come back PAUSED, because the snake was frozen while
    -- we were away and dropping the operator straight back into motion
    -- would kill a run they had no chance to react to.
    if ev == "tos_focus" then
      paused = true
      drawFrame(); drawScore()
      D.centre(oy + math.floor(BH / 2), " PAUSED ", T.warn)
      nextTick = computer.uptime() + L.snakeDelay(0)
    elseif ev == "key_down" then
      local k = keyName(ch, code)
      if k == "q" or k == "esc" then D.clear(); return
      elseif k == "p" then
        paused = not paused
        if paused then D.centre(oy + math.floor(BH / 2), " PAUSED ", T.warn)
        else drawFrame(); drawScore()
          for i, seg in ipairs(s.body) do
            drawCell(seg.x, seg.y, i == 1 and HEAD or BODY, i == 1 and T.hi or T.fg)
          end
          if s.food then drawCell(s.food.x, s.food.y, FOOD, T.warn) end
        end
        nextTick = computer.uptime() + L.snakeDelay(s.score)
      elseif k == "up" or k == "w" then L.turn(s, "up")
      elseif k == "down" or k == "s" then L.turn(s, "down")
      elseif k == "left" or k == "a" then L.turn(s, "left")
      elseif k == "right" or k == "d" then L.turn(s, "right")
      end
    end

    if not paused and computer.uptime() >= nextTick then
      local oldTail = s.body[#s.body]
      local prevHead = s.body[1]
      L.step(s, rand)
      if not s.alive then break end
      -- Erase the vacated tail (unless we grew), demote the old head to
      -- body, and paint the new head + any new food.
      if not s.grew and oldTail then drawCell(oldTail.x, oldTail.y, " ", T.fg) end
      if prevHead then drawCell(prevHead.x, prevHead.y, BODY, T.fg) end
      local h = s.body[1]
      drawCell(h.x, h.y, HEAD, T.hi)
      if s.grew then
        drawScore()
        if s.food then drawCell(s.food.x, s.food.y, FOOD, T.warn) end
        pcall(computer.beep, 800, 0.05)
      end
      nextTick = computer.uptime() + L.snakeDelay(s.score)
    end
  end

  -- Game over.
  pcall(computer.beep, 200, 0.4)
  local scores = recordScore("/home/.snake_hs", s.score)
  local by = oy + math.floor(BH / 2) - 3
  D.box(ox + 4, by, BW - 8, 8, "Game Over")
  D.centre(by + 2, "Score: " .. s.score, T.hi)
  D.centre(by + 3, "Best scores", T.dim)
  for i = 1, math.min(3, #scores) do
    D.centre(by + 3 + i, string.format("%d. %d", i, scores[i].score),
      (scores[i].score == s.score) and T.hi or T.fg)
  end
  D.centre(by + 7, "Press any key", T.dim)
  while true do
    local ev = computer.pullSignal()
    if ev == "key_down" then break end
  end
  D.clear()
end

return { commands = { snake = snake } }
