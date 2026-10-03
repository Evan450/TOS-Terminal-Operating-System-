








local L = {}





L.DIRS = {
  up    = { x =  0, y = -1 },
  down  = { x =  0, y =  1 },
  left  = { x = -1, y =  0 },
  right = { x =  1, y =  0 },
}




local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }


function L.newSnake(w, h)
  local cx, cy = math.floor(w / 2), math.floor(h / 2)
  return {
    w = w, h = h,
    body = { { x = cx, y = cy }, { x = cx - 1, y = cy }, { x = cx - 2, y = cy } },
    dir = "right",
    pendingDir = "right",
    food = nil,
    score = 0,
    alive = true,
    grew = false,        
  }
end





function L.turn(s, dir)
  if not L.DIRS[dir] then return false end
  if #s.body > 1 and OPPOSITE[s.dir] == dir then return false end
  s.pendingDir = dir
  return true
end



function L.hits(s, x, y, skipTail)
  local last = #s.body - (skipTail and 1 or 0)
  for i = 1, last do
    local seg = s.body[i]
    if seg.x == x and seg.y == y then return true end
  end
  return false
end



function L.placeFood(s, rand)
  local free = {}
  for y = 1, s.h do
    for x = 1, s.w do
      if not L.hits(s, x, y, false) then free[#free + 1] = { x = x, y = y } end
    end
  end
  if #free == 0 then s.food = nil; return false end
  s.food = free[rand(#free)]
  return true
end




function L.step(s, rand)
  if not s.alive then return s end
  s.grew = false
  s.dir = s.pendingDir
  local d = L.DIRS[s.dir]
  local head = s.body[1]
  local nx, ny = head.x + d.x, head.y + d.y

  
  if nx < 1 or ny < 1 or nx > s.w or ny > s.h then
    s.alive = false
    return s
  end
  
  
  local eating = (s.food ~= nil and s.food.x == nx and s.food.y == ny)
  if L.hits(s, nx, ny, not eating) then
    s.alive = false
    return s
  end

  table.insert(s.body, 1, { x = nx, y = ny })
  if eating then
    s.score = s.score + 1
    s.grew = true
    L.placeFood(s, rand)
  else
    table.remove(s.body)          
  end
  return s
end



function L.snakeDelay(score)
  local d = 0.22 - (score * 0.006)
  if d < 0.07 then d = 0.07 end
  return d
end

return L
