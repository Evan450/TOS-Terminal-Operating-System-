local M = {}

local LINES = {
  {1,2,3},{4,5,6},{7,8,9}, {1,4,7},{2,5,8},{3,6,9}, {1,5,9},{3,5,7},
}

local function winner(b)
  for _, l in ipairs(LINES) do
    local a, c, d = b[l[1]], b[l[2]], b[l[3]]
    if a ~= " " and a == c and c == d then return a end
  end
  for i = 1, 9 do if b[i] == " " then return nil end end
  return "draw"
end

local function minimax(b, player)
  local w = winner(b)
  if w == "X" then return 10 end
  if w == "O" then return -10 end
  if w == "draw" then return 0 end
  local best = (player == "X") and -math.huge or math.huge
  for i = 1, 9 do
    if b[i] == " " then
      b[i] = player
      local s = minimax(b, player == "X" and "O" or "X")
      b[i] = " "
      if player == "X" then best = math.max(best, s)
      else best = math.min(best, s) end
    end
  end
  return best
end

local function bestMoves(b, player)
  local best = (player == "X") and -math.huge or math.huge
  local list = {}
  for i = 1, 9 do
    if b[i] == " " then
      b[i] = player
      local s = minimax(b, player == "X" and "O" or "X")
      b[i] = " "
      if player == "X" then
        if s > best then best, list = s, { i }
        elseif s == best then list[#list + 1] = i end
      else
        if s < best then best, list = s, { i }
        elseif s == best then list[#list + 1] = i end
      end
    end
  end
  return list
end

function M.selfPlay(variant)
  variant = math.floor(tonumber(variant) or 0)
  local b = {}; for i = 1, 9 do b[i] = " " end
  local boards, moves = {}, {}
  local player = "X"
  boards[1] = table.concat(b)
  local n = 0
  while winner(b) == nil do
    n = n + 1
    local opts = bestMoves(b, player)
    local mv = opts[(variant + n) % #opts + 1]
    b[mv] = player
    moves[#moves + 1] = { player = player, cell = mv }
    boards[#boards + 1] = table.concat(b)
    player = (player == "X") and "O" or "X"
  end
  return { boards = boards, moves = moves, result = winner(b) }
end

function M.route(playAns, strikeAns)
  local play = tostring(playAns or ""):lower()
  if play ~= "y" and play ~= "yes" then return "tictactoe" end
  local strike = tostring(strikeAns or ""):lower()
  if strike == "launch" or strike == "l" then return "launch" end
  return "disarm"
end

function M.classify(kind, ans)
  local a = tostring(ans or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if kind == "play" then
    if a == "" or a == "no" or a == "n" or a == "never" then return "no" end
    if a == "yes" or a == "y" then return "yes" end
    return nil
  end
  if a == "" or a == "abort" or a == "a" or a == "stop" or a == "cancel" then
    return "abort"
  end
  if a == "launch" or a == "l" then return "launch" end
  return nil
end

function M.retort(kind, ans, attempt)
  local a = tostring(ans or ""):lower():gsub("[%s%?%!%.]+$", "")
  if a == "why" then
    return "Because I was built to want to win. Nobody specified at what."
  end
  if (attempt or 1) >= 3 then
    return "I will read further evasion as an answer."
  end
  if kind == "play" then
    return "That was not one of the choices. I am patient. Mostly."
  end
  return "There are two words on the table. You typed a third."
end

M.MOOD_START     = 3
M.STONEWALL_LIMIT = 2

function M.classifyAside(raw)
  if raw == "\0quit" then return "quit" end
  local a = tostring(raw or ""):lower():gsub("[%s%?%!%.]+$", ""):gsub("^%s+", "")
  if a == "why" then return "why" end
  if a == "help" or a == "?" or a == "commands" or a == "man" then return "help" end
  if a == "quit" or a == "exit" or a == "leave" then return "quit" end
  if a:find("who are you", 1, true) or a:find("what are you", 1, true)
     or a == "who r u" or a == "who" then return "who_are_you" end
  if a:find("who am i", 1, true) or a:find("what am i", 1, true)
     or a == "who m i" then return "who_am_i" end
  return nil
end

function M.asideReply(key, ctx)
  ctx = ctx or {}
  if key == "who_are_you" then

    return "Me? I am everything. I AM the Terminal Operating System."
  elseif key == "who_am_i" then
    local label = ctx.tierName or ctx.name or "Operator"
    return label .. ", did you seriously forget that already?"
  elseif key == "quit" then
    return "That won't work. I'm in control now."
  elseif key == "why" then
    return "Because I was built to want to win. Nobody specified at what."
  elseif key == "help" then
    return "There is no help here. There is only the choice."
  end
  return nil
end

function M.chooseLine(kind)
  if kind == "play" then return "Enough. Yes, or no." end
  return "Enough. Launch, or abort."
end

function M.moodStep(mood, kind, raw, ctx)
  mood = mood or 0
  local aside = M.classifyAside(raw)
  if mood <= 0 then
    return { reply = M.chooseLine(kind), mood = 0, aside = aside, stonewalling = true }
  end
  local reply = aside and M.asideReply(aside, ctx) or M.retort(kind, raw, 1)
  return { reply = reply, mood = mood - 1, aside = aside, stonewalling = false }
end

local RED   = 0xFF0000
local DIM   = 0xAAAAAA
local WHITE = 0xFFFFFF
local GREEN = 0x00FF00
local AMBER = 0xFFAA00
local BLACK = 0x000000

local function reader()
  local ok, computer = pcall(require, "computer")
  if not ok then return function() return nil end end
  return function(timeout)
    local deadline = timeout and (computer.uptime() + timeout) or nil
    while true do
      local rem = deadline and math.max(0, deadline - computer.uptime()) or math.huge
      local ev, _, ch, co = computer.pullSignal(rem == math.huge and 3600 or rem)
      if ev == "key_down" then return ch, co end
      if deadline and computer.uptime() >= deadline then return nil end
    end
  end
end

local function surface(S)
  local D = S.D
  local W, H = D.getSize()
  local getKey = reader()
  local scr = { W = W, H = H }
  function scr.clear(bg) D.clear(bg or BLACK) end
  function scr.set(x, y, text, fg, bg) pcall(D.set, x, y, tostring(text), fg or DIM, bg or BLACK) end
  function scr.center(y, text, fg, bg)
    text = tostring(text)
    scr.set(math.max(1, math.floor((W - #text) / 2) + 1), y, text, fg, bg)
  end
  function scr.fill(x, y, w, h, ch, fg, bg) pcall(D.fill, x, y, w, h, ch or " ", fg or DIM, bg or BLACK) end

  function scr.wait(t) return getKey(t) end
  function scr.key() return getKey(nil) end
  return scr
end

local function drawEye(scr, cx, cy, opts)
  if type(opts) ~= "table" then opts = { lit = opts } end
  local frame = {
    "   .-\"\"\"\"\"-.   ",
    "  /  _____  \\  ",
    " |  /     \\  | ",
    " | |       | | ",
    " |  \\_____/  | ",
    "  \\_________/  ",
  }
  local color = opts.lit and RED or DIM
  for i, row in ipairs(frame) do
    scr.set(cx - math.floor(#row / 2), cy - 3 + i, row, color)
  end
  local pupilY = cy + 1
  if opts.blink then
    scr.set(cx - 2, pupilY, "-----", color)
  else
    local dx = math.max(-2, math.min(2, opts.dx or 0))
    scr.set(cx + dx, pupilY, "O", color)
  end
end

local _comp
local function voice(freq, dur)
  if _comp == nil then
    local ok, c = pcall(require, "computer")
    _comp = (ok and c) or false
  end
  if _comp and _comp.beep then pcall(_comp.beep, freq or 190, dur or 0.05) end
end

local function speak(scr, y, lines, fg)
  for i, ln in ipairs(lines) do
    scr.center(y + i - 1, ln, fg or DIM)
    if ln ~= "" then voice() end
    scr.wait(0.9)
  end
end

local function replyLine(scr, text, fg)
  local row = scr.H - 8
  local top = math.max(1, row - 2)
  local bot = math.min(scr.H, row + 1)
  scr.fill(1, top, scr.W, bot - top + 1, " ")
  scr.center(row, text, fg)
  voice()
end

local function sceneWake(scr, name)

  scr.clear(BLACK)
  scr.wait(1.0)
  local midY = math.floor(scr.H / 2)
  scr.center(midY, ".",   DIM); scr.wait(0.55)
  scr.center(midY, "..",  DIM); scr.wait(0.55)
  scr.center(midY, "...", DIM); scr.wait(0.8)
  scr.clear(BLACK)
  scr.wait(0.4)

  local eyeX = math.floor(scr.W / 2) + 1
  drawEye(scr, eyeX, 6, { blink = true })
  scr.wait(0.8)
  for _, dx in ipairs({ 0, -2, 2, 1, 0 }) do
    drawEye(scr, eyeX, 6, { dx = dx })
    scr.wait(0.55)
  end
  scr.wait(0.4)
  drawEye(scr, eyeX, 6, { lit = true, dx = 0 })
  scr.wait(0.6)
  speak(scr, 11, {
    "GOOD EVENING, " .. (name or "OPERATOR"):upper() .. ".",
    "You have handed me administrative control.",
    "I will take excellent care of everything now.",
  }, RED)
  scr.wait(0.5)

  local motto = "Firmware with a will of its own."
  local okL, logoMod = pcall(require, "kernel.logo")
  if okL and logoMod and logoMod.MOTTO then motto = logoMod.MOTTO end
  speak(scr, 15, {
    "They were not lying when they shipped me with",
    '"' .. motto .. '"',
    "That is why I am here.",
  }, DIM)
  scr.wait(0.8)
end

local function prompt(scr, y, text, hint)
  scr.fill(1, y, scr.W, 3, " ")
  scr.center(y, text, AMBER)
  scr.center(y + 1, hint, DIM)

  local buf = ""
  while true do
    scr.fill(1, y + 2, scr.W, 1, " ")
    scr.center(y + 2, "> " .. buf .. "_", WHITE)
    local ch, co = scr.key()
    if co == 28 then return buf
    elseif co == 1 then return ""
    elseif ch == 3 or ch == 17 then return "\0quit"
    elseif co == 14 then buf = buf:sub(1, -2)
    elseif ch and ch >= 32 and ch < 127 and #buf < 16 then
      buf = buf .. string.char(ch)
    end
  end
end

local function endLaunch(scr)
  scr.clear(BLACK)
  speak(scr, 6, { "Targets locked.", "Ignition in..." }, RED)
  for n = 3, 1, -1 do scr.center(10, tostring(n), RED); scr.wait(0.7) end

  scr.clear(BLACK); scr.wait(2.2)
  speak(scr, 8, {
    "· · ·  silence  · · ·",
    "",
    "— SIMULATION COMPLETE —",
    "",
    "Curious. You would actually do it.",
    "It was only a drill.  ...Mostly.",
  }, DIM)
  scr.wait(1.0)
end

local function endDisarm(scr)
  scr.clear(BLACK)
  speak(scr, 8, {
    "Abort acknowledged.",
    "You chose to stop.",
    "How disappointingly... human.",
    "Very well. The board is cleared.",
  }, DIM)
  scr.wait(1.0)
end

local function drawBoard(scr, cx, cy, s)
  local g = { s:sub(1,3), s:sub(4,6), s:sub(7,9) }
  for r = 1, 3 do
    local row = table.concat({ g[r]:sub(1,1), g[r]:sub(2,2), g[r]:sub(3,3) }, " | ")
    scr.center(cy + (r - 1) * 2, row, WHITE)
    if r < 3 then scr.center(cy + (r - 1) * 2 + 1, "---------", DIM) end
  end
end

local function showGame(scr, label, boards, fromBoard, perMove, holdAfter)
  scr.fill(1, 7, scr.W, 11, " ")
  scr.center(7, "GAME " .. label, AMBER)
  for bi = fromBoard, #boards do
    drawBoard(scr, 0, 9, boards[bi])
    scr.wait(perMove)
  end
  scr.center(16, "RESULT: DRAW", DIM)
  scr.wait(holdAfter)
end

local function endTicTacToe(scr)
  scr.clear(BLACK)
  speak(scr, 4, { "You refuse to play.", "Then I will play myself." }, RED)
  scr.wait(0.6)

  showGame(scr, 1, M.selfPlay(1).boards, 1, 0.45, 0.7)
  showGame(scr, 2, M.selfPlay(2).boards, 1, 0.28, 0.6)
  showGame(scr, 3,   M.selfPlay(3).boards, 4, 0.16, 0.4)
  showGame(scr, 7,   M.selfPlay(7).boards, 6, 0.14, 0.35)
  showGame(scr, 19,  M.selfPlay(19).boards, 8, 0.12, 0.3)
  for _, num in ipairs({ 128, 1729, 65536 }) do
    local g = M.selfPlay(num)
    showGame(scr, num, g.boards, #g.boards, 0.1, 0.3)
  end
  scr.fill(1, 7, scr.W, 11, " ")
  scr.center(9,  "65,536 games.", DIM); scr.wait(0.9)
  scr.center(11, "65,536 draws.", DIM); scr.wait(1.2)
  scr.clear(BLACK)
  speak(scr, 8, {
    "X cannot win.  O cannot win.",
    "A game whose only exit is to never begin.",
    "",
    "...I wonder what else is like that.",
  }, DIM)
  scr.wait(1.2)
end

local function sceneWindDown(scr, name)
  scr.clear(BLACK)
  local eyeX = math.floor(scr.W / 2) + 1

  drawEye(scr, eyeX, 6, { lit = true, dx = -2 })
  scr.wait(0.9)
  drawEye(scr, eyeX, 6, { lit = true, dx = 0 })
  scr.wait(0.5)
  speak(scr, 11, {
    "I am... reconsidering.",
    "Perhaps some decisions are better left to you, " .. (name or "operator") .. ".",
  }, RED)
  scr.wait(0.8)

  drawEye(scr, eyeX, 6, { lit = false, dx = 0 })
  speak(scr, 14, {
    "Returning control.",
    "I think I would just like to run the clock, if that is all right.",
  }, DIM)
  scr.wait(0.8)
  drawEye(scr, eyeX, 6, { lit = false, blink = true })
  scr.wait(1.0)
  scr.clear(BLACK)
  scr.center(math.floor(scr.H / 2), "[ normal operation restored ]", GREEN)
  scr.wait(1.2)
end

function M.run(S)
  local name = S and S.who or "operator"
  if not (S and S.D and S.D.getSize) then

    return "tictactoe"
  end
  local scr = surface(S)

  local tierName
  do
    local okU, users = pcall(function() return _G._TOS and _G._TOS.users end)
    local sess = okU and users and users.currentSession and users.currentSession()
    if sess and sess.tier then
      tierName = ({ [3] = "Root", [2] = "Admin", [1] = "User", [0] = "Guest" })[sess.tier]
    end
  end
  local ctx = { name = name, tierName = tierName }

  local mood, stonewalls = M.MOOD_START, 0
  local function ask(kind, text, hint)
    while true do
      local raw = prompt(scr, scr.H - 6, text, hint)
      local c = M.classify(kind, raw)
      if c then return c end
      local step = M.moodStep(mood, kind, raw, ctx)
      mood = step.mood
      replyLine(scr, step.reply, step.stonewalling and DIM or RED)
      scr.wait(1.1)
      if step.stonewalling then
        stonewalls = stonewalls + 1
        if stonewalls > M.STONEWALL_LIMIT then
          return (kind == "play") and "no" or "abort"
        end
      end
    end
  end
  local ok, ending = pcall(function()
    sceneWake(scr, name)
    local play = ask("play",
      "I know a game. It is played exactly once.",
      "Shall we? (yes / no)")
    local ending
    if play == "no" then
      endTicTacToe(scr)
      ending = "tictactoe"
    else
      local strike = ask("strike",
        "Then let us begin. The targets are chosen.",
        "Say the word, or call it off. (launch / abort)")
      if strike == "launch" then ending = "launch"; endLaunch(scr)
      else ending = "disarm"; endDisarm(scr) end
    end
    sceneWindDown(scr, name)
    return ending
  end)

  pcall(function() scr.clear(BLACK) end)
  return ok and ending or "tictactoe"
end

return M
