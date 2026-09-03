-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ttt — PURE tic-tac-toe logic (no component, no I/O)         ║
-- ║                                                              ║
-- ║  Value-in/value-out so the rules unit-test off-box           ║
-- ║  (test_ttt.lua) — including a proof that the AI is genuinely  ║
-- ║  unbeatable — while init.lua keeps only drawing + input.     ║
-- ║  The pkg sandbox resolves this via the /usr/modules user-lib ║
-- ║  root: require("ttt.logic").                                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local L = {}

-- The board is a flat 9-element array: 1..9 reading left→right,
-- top→bottom. Cells hold "X", "O", or nil.

local LINES = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },      -- rows
  { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },      -- columns
  { 1, 5, 9 }, { 3, 5, 7 },                   -- diagonals
}
L.LINES = LINES

function L.newBoard() return {} end

--- "X" | "O" when someone has three in a row (plus the winning line),
--- "draw" when the board is full, nil while the game is live. Pure.
function L.winner(b)
  for _, ln in ipairs(LINES) do
    local a = b[ln[1]]
    if a and b[ln[2]] == a and b[ln[3]] == a then return a, ln end
  end
  for i = 1, 9 do if not b[i] then return nil end end
  return "draw"
end

local function other(p) return (p == "X") and "O" or "X" end
L.other = other

-- Minimax with depth preference AND alpha-beta pruning. Depth preference:
-- win SOONER and lose LATER (10-depth / depth-10), so the AI takes an
-- immediate win over an equally-scored longer one and drags out a lost
-- game rather than conceding at once. Alpha-beta: prune any branch that
-- can't change the parent's decision.
--
-- The pruning does NOT change a single return value — the score of a
-- position is identical with or without it — it only skips work. That
-- matters here for two reasons: (1) this evaluates LIVE after every human
-- move, so the machine should reply instantly on a weak box; (2) the
-- self-play property test calls bestMove ~9x per game over 200 games,
-- which was ~87s of pure search unpruned.
--
-- alpha = best score the maximizer (me) can already guarantee above;
-- beta  = best score the minimizer (opponent) can already guarantee.
-- When they cross, the remaining siblings can't matter.
local function minimax(b, player, me, depth, alpha, beta)
  local w = L.winner(b)
  if w == me then return 10 - depth end
  if w == other(me) then return depth - 10 end
  if w == "draw" then return 0 end

  if player == me then
    local best = -math.huge
    for i = 1, 9 do
      if not b[i] then
        b[i] = player
        local score = minimax(b, other(player), me, depth + 1, alpha, beta)
        b[i] = nil
        if score > best then best = score end
        if best > alpha then alpha = best end
        if alpha >= beta then break end        -- opponent won't allow this line
      end
    end
    return best
  else
    local best = math.huge
    for i = 1, 9 do
      if not b[i] then
        b[i] = player
        local score = minimax(b, other(player), me, depth + 1, alpha, beta)
        b[i] = nil
        if score < best then best = score end
        if best < beta then beta = best end
        if alpha >= beta then break end        -- we won't allow this line
      end
    end
    return best
  end
end

--- The optimal move for `player`, or nil on a finished/full board.
--- Perfect play: this AI cannot be beaten, only drawn. `tieBreak(n)`
--- (optional, returns 1..n) picks among equally-optimal moves so the
--- machine doesn't play an identical game every time — inject it for
--- deterministic tests. Pure w.r.t. the caller's board (restored).
function L.bestMove(b, player, tieBreak)
  if L.winner(b) then return nil end
  local bestScore, moves = nil, {}
  for i = 1, 9 do
    if not b[i] then
      b[i] = player
      -- Full alpha-beta window at the root: we want the TRUE score of
      -- every move (to collect all equally-optimal ones for the
      -- tie-break), so don't narrow the window across root siblings.
      local score = minimax(b, other(player), player, 1, -math.huge, math.huge)
      b[i] = nil
      if not bestScore or score > bestScore then
        bestScore, moves = score, { i }
      elseif score == bestScore then
        moves[#moves + 1] = i
      end
    end
  end
  if #moves == 0 then return nil end
  if tieBreak then return moves[tieBreak(#moves)] end
  return moves[1]
end

--- Perfect play against itself. `variant` picks among equally-optimal
--- moves (deterministically, so a variant always replays identically)
--- which makes consecutive games DIFFERENT while every one of them is
--- still optimal — and therefore always a draw.
---
--- Returns { boards = { <copy after each move>, ... }, result = "draw" }.
--- The board copies are what the zero-player easter-egg montage renders;
--- `result` is what the property test asserts. Mirrors the base OS
--- easter egg's own self-play (tos/shell/panels/takeover.lua).
function L.selfPlay(variant)
  variant = tonumber(variant) or 1
  local b = L.newBoard()
  local boards, player, step = {}, "X", 0
  while not L.winner(b) do
    step = step + 1
    -- A cheap, well-spread deterministic index: the variant and the move
    -- number both stir it, so game 3 and game 7 diverge early rather
    -- than sharing a prefix.
    local m = L.bestMove(b, player, function(n)
      return ((variant * 7 + step * 13 + variant * step) % n) + 1
    end)
    if not m then break end
    L.play(b, m, player)
    local copy = {}
    for i = 1, 9 do copy[i] = b[i] end
    boards[#boards + 1] = copy
    player = other(player)
  end
  return { boards = boards, result = L.winner(b) or "draw" }
end

--- Place a mark if the cell is free and the game is live. Mutates.
--- Returns true when the move was made.
function L.play(b, cell, player)
  if type(cell) ~= "number" or cell < 1 or cell > 9 then return false end
  if b[cell] or L.winner(b) then return false end
  b[cell] = player
  return true
end

--- PURE — which cell (1..9) does a click at (x, y) land in? nil when the
--- click misses the board entirely, INCLUDING the separator columns and
--- rows between cells: a click on a grid line is not a move, and
--- rounding it into a neighbouring cell would place a piece the operator
--- did not aim at. Geometry mirrors cellOrigin() in init.lua — cell i
--- occupies (gx + c*(cw+1), gy + r*(ch+1)) for cw x ch columns.
function L.cellAt(x, y, gx, gy, cw, ch)
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  local col, row
  for c = 0, 2 do
    local x0 = gx + c * (cw + 1)
    if x >= x0 and x < x0 + cw then col = c; break end
  end
  for r = 0, 2 do
    local y0 = gy + r * (ch + 1)
    if y >= y0 and y < y0 + ch then row = r; break end
  end
  if not col or not row then return nil end
  return row * 3 + col + 1
end

return L
