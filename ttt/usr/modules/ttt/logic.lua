









local L = {}




local LINES = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },      
  { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },      
  { 1, 5, 9 }, { 3, 5, 7 },                   
}
L.LINES = LINES

function L.newBoard() return {} end



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
        if alpha >= beta then break end        
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
        if alpha >= beta then break end        
      end
    end
    return best
  end
end






function L.bestMove(b, player, tieBreak)
  if L.winner(b) then return nil end
  local bestScore, moves = nil, {}
  for i = 1, 9 do
    if not b[i] then
      b[i] = player
      
      
      
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










function L.selfPlay(variant)
  variant = tonumber(variant) or 1
  local b = L.newBoard()
  local boards, player, step = {}, "X", 0
  while not L.winner(b) do
    step = step + 1
    
    
    
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



function L.play(b, cell, player)
  if type(cell) ~= "number" or cell < 1 or cell > 9 then return false end
  if b[cell] or L.winner(b) then return false end
  b[cell] = player
  return true
end







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
