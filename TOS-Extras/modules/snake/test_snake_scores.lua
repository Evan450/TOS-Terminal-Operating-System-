-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: snake keeps a board PER PLAYER              ║
-- ║                                                              ║
-- ║  The package promises per-user high scores, and the comment   ║
-- ║  above its score code said "~/ resolves to the calling        ║
-- ║  user's home". The code wrote "/home/.snake_hs": one file in  ║
-- ║  /home itself, outside every home. So an admin's scores went  ║
-- ║  into a board every admin shared, and an ordinary user, who   ║
-- ║  may not write there, never had a score saved at all (the     ║
-- ║  write is pcall'd, so nobody was told).                       ║
-- ║                                                              ║
-- ║  This plays real games through the real init.lua, in a fake   ║
-- ║  of the sandbox env, as two players, and checks where the     ║
-- ║  scores land and which board the game-over screen shows.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/snake/test_snake_scores.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "modules/snake/test_snake_scores.lua"
local base = here:gsub("[^/\\]*$", "")
local function chunk(name)
  local f, err = loadfile(base .. name)
  if not f then f, err = loadfile("modules/snake/" .. name) end
  assert(f, err)
  return f
end

-- One shared disk for every game, so a board one player leaves behind is
-- there for the next.
local disk = {}

--- Play one game of snake as the player whose home is `home`. Nothing is
--- pressed, so the snake runs right until it hits the wall; then a key
--- leaves the game-over screen. Returns what the screen showed.
local function play(home)
  local clock = 0
  local drawn = {}
  local gpu = {
    getResolution = function() return 80, 25 end,
    getDepth = function() return 8 end,
    setForeground = function() end, setBackground = function() end,
    fill = function() end,
    set = function(_, _, s) drawn[#drawn + 1] = s end,
  }
  local computer = {
    uptime = function() return clock end,
    beep = function() end,
    pullSignal = function(timeout)
      -- The game loop always passes a timeout; only the game-over screen
      -- waits for a key with none.
      if timeout == nil then return "key_down", "kbd", 32, 57 end
      clock = clock + timeout + 0.001
      assert(clock < 600, "the game never ended")
      return nil
    end,
  }
  local component = {
    list = function(kind)
      local done = false
      return function()
        if kind == "gpu" and not done then done = true; return "gpu-1" end
      end
    end,
    proxy = function() return gpu end,
  }
  local logic = chunk("logic.lua")()
  local fs = {
    home = function() return home end,
    exists = function(p) return disk[p] ~= nil end,
    readFile = function(p)
      if disk[p] == nil then error("no such file: " .. p) end
      return disk[p]
    end,
    writeFile = function(p, data) disk[p] = data end,
  }
  local env = setmetatable({
    fs = fs,
    require = function(name)
      if name == "component" then return component end
      if name == "computer" then return computer end
      if name == "snake.logic" then return logic end
      error("module not found: " .. name)   -- shell.keys: pcall'd, falls back
    end,
  }, { __index = _G })
  local mod = assert(load(io.open(base .. "init.lua"):read("a"), "=snake/init.lua", "t", env))
  local cmd = mod().commands.snake
  local out = {}
  cmd({}, function(line) out[#out + 1] = line end)
  return drawn, out
end

local function showed(drawn, text)
  for _, s in ipairs(drawn) do
    if s == text then return true end
  end
  return false
end

local function filesUnder(prefix)
  local n = 0
  for p in pairs(disk) do
    if p:sub(1, #prefix) == prefix then n = n + 1 end
  end
  return n
end

print("Snake keeps a board per player")

-- A board alice already has, from an earlier game.
disk["/home/alice/.snake_hs"] = "7 up 120s"

local drawn = play("/home/alice")
test("alice's game reaches the game-over screen", showed(drawn, " Game Over "))
test("alice's score is saved in her own home",
  disk["/home/alice/.snake_hs"] ~= nil and disk["/home/alice/.snake_hs"] ~= "7 up 120s")
test("alice's earlier best is still on her board",
  (disk["/home/alice/.snake_hs"] or ""):find("^7 ") ~= nil)
test("the game-over screen shows alice's board", showed(drawn, "1. 7"))
test("nothing is written in /home itself", disk["/home/.snake_hs"] == nil)

drawn = play("/home/bob")
test("bob's score is saved in his own home", disk["/home/bob/.snake_hs"] ~= nil)
test("bob does not see alice's best", not showed(drawn, "1. 7"))
test("alice's board is untouched by bob's game",
  (disk["/home/alice/.snake_hs"] or ""):find("^7 ") ~= nil)

-- No live session: securefs.home() answers /tmp. A board there would be
-- shared by everyone who ever played logged out, so there is none.
local before = {}
for p, data in pairs(disk) do before[p] = data end
drawn = play("/tmp")
local changed = 0
for p, data in pairs(disk) do
  if before[p] ~= data then changed = changed + 1 end
end
test("with no session nothing is saved", changed == 0 and filesUnder("/tmp") == 0)
test("with no session the game still ends normally", showed(drawn, " Game Over "))

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
