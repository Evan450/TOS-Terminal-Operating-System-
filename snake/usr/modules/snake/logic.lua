-- ╔══════════════════════════════════════════════════════════════╗
-- ║  snake — PURE game logic (no component, no computer, no I/O) ║
-- ║                                                              ║
-- ║  Value-in/value-out so the rules unit-test off-box           ║
-- ║  (test_snake.lua) while init.lua keeps only drawing + input. ║
-- ║  The pkg sandbox resolves this via the /usr/modules user-lib ║
-- ║  root: require("snake.logic").                               ║
-- ╚══════════════════════════════════════════════════════════════╝

local L = {}

-- Board coordinates are 1-based (col, row). The snake is an array of
-- {x, y} segments, HEAD FIRST — so growth is a table.insert at 1 and
-- movement is insert-head + remove-tail, both O(n) but n is tiny.

L.DIRS = {
  up    = { x =  0, y = -1 },
  down  = { x =  0, y =  1 },
  left  = { x = -1, y =  0 },
  right = { x =  1, y =  0 },
}

-- Opposite directions can't be entered directly: on a body longer than
-- one segment, reversing would drive the head straight into the neck,
-- which reads as an instant unfair death rather than a move.
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

--- A fresh game state on a `w` x `h` board. Pure.
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
    grew = false,        -- set on the tick the snake ate (for the UI/beep)
  }
end

--- Queue a direction change for the next step. Rejects reversals and
--- unknown names. Queuing (rather than applying immediately) means two
--- fast keypresses in one tick can't turn the snake back into itself.
--- Mutates `s`; returns true when the input was accepted.
function L.turn(s, dir)
  if not L.DIRS[dir] then return false end
  if #s.body > 1 and OPPOSITE[s.dir] == dir then return false end
  s.pendingDir = dir
  return true
end

--- Is (x, y) occupied by the snake? `skipTail` ignores the last segment,
--- which is about to move away this tick. Pure.
function L.hits(s, x, y, skipTail)
  local last = #s.body - (skipTail and 1 or 0)
  for i = 1, last do
    local seg = s.body[i]
    if seg.x == x and seg.y == y then return true end
  end
  return false
end

--- Place food on a free cell. `rand(n)` must return 1..n — inject it so
--- tests are deterministic. Returns false when the board is full (a win).
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

--- Advance one tick: apply the queued turn, move the head, resolve food
--- and collisions. Mutates `s` and returns it. `rand` is only consulted
--- when food is eaten. A dead snake is a no-op.
function L.step(s, rand)
  if not s.alive then return s end
  s.grew = false
  s.dir = s.pendingDir
  local d = L.DIRS[s.dir]
  local head = s.body[1]
  local nx, ny = head.x + d.x, head.y + d.y

  -- Walls kill (classic rules — no wrapping).
  if nx < 1 or ny < 1 or nx > s.w or ny > s.h then
    s.alive = false
    return s
  end
  -- Self-collision. The tail cell is exempt: it vacates this same tick,
  -- so following your own tail at full speed is legal, as in the arcade.
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
    table.remove(s.body)          -- move: head in, tail out
  end
  return s
end

--- Tick delay in seconds for a score — the difficulty ramp. Starts
--- leisurely, floors so it never becomes unplayable. Pure.
function L.snakeDelay(score)
  local d = 0.22 - (score * 0.006)
  if d < 0.07 then d = 0.07 end
  return d
end

return L
