-- ╔══════════════════════════════════════════════════════╗
-- ║  Test: tetris runs under the pkg sandbox               ║
-- ║                                                        ║
-- ║  Regression for the kernel.modules→pkg pivot: the old   ║
-- ║  build required kernel.display/kernel.event (and four    ║
-- ║  more kernel.* modules), all of which the pkg sandbox    ║
-- ║  blocks — so the game could not launch at all. This      ║
-- ║  test loads the module inside a FAITHFUL fake of the     ║
-- ║  sandbox env (kernel.* requires raise, like the real     ║
-- ║  makeSafeRequire) and drives a play+quit session.        ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua modules/tetris/test_tetris_sandbox.lua   (from TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "modules/tetris/test_tetris_sandbox.lua"
local base = here:gsub("[^/\\]*$", "")
local function trypath(rels)
  for _, p in ipairs(rels) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- ── Serializer: prefer the real TOS-Dev pair for fidelity ───
local serialization
do
  local kserChunk = trypath({
    base .. "../../../TOS-Dev/tos/kernel/serialize.lua",
    "../TOS-Dev/tos/kernel/serialize.lua", "../tos/kernel/serialize.lua",
    "TOS-Dev/tos/kernel/serialize.lua",
  })
  local compatChunk = trypath({
    base .. "../../../TOS-Dev/tos/compat/serialization.lua",
    "../TOS-Dev/tos/compat/serialization.lua", "../tos/compat/serialization.lua",
    "TOS-Dev/tos/compat/serialization.lua",
  })
  if kserChunk and compatChunk then
    package.loaded["kernel.serialize"] = kserChunk()
    serialization = compatChunk()
    print("(using the real TOS-Dev compat.serialization)")
  else
    -- Minimal stand-in: encodes flat array-of-record tables, decodes
    -- via a sandboxed load. Enough for the score-file round trip.
    serialization = {
      serialize = function(v)
        local function enc(x)
          if type(x) == "table" then
            local parts = {}
            for k, val in pairs(x) do
              local key = type(k) == "number" and "" or ("[" .. string.format("%q", k) .. "]=")
              if type(k) == "string" then key = "[" .. string.format("%q", k) .. "]=" end
              parts[#parts + 1] = key .. enc(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
          elseif type(x) == "string" then return string.format("%q", x)
          else return tostring(x) end
        end
        return enc(v)
      end,
      unserialize = function(s)
        s = s:match("^%s*return%s+(.+)$") or s
        local fn = load("return " .. s, "=scores", "t", {})
        if not fn then return nil end
        local ok, v = pcall(fn)
        return ok and v or nil
      end,
    }
    print("(TOS-Dev tree not found; using fallback serializer)")
  end
end

-- ── Fake sandbox environment ────────────────────────────────
local function makeFixture(opts)
  opts = opts or {}
  local fx = { gpuCalls = {}, files = opts.files or {}, out = {} }

  local gpu = {
    getResolution = function() return opts.W or 80, opts.H or 25 end,
    getDepth      = function() return opts.depth or 8 end,
    setForeground = function() end,
    setBackground = function() end,
    set  = function(x, y, t) fx.gpuCalls[#fx.gpuCalls + 1] = { "set", x, y, t } end,
    fill = function(x, y, w, h, c) fx.gpuCalls[#fx.gpuCalls + 1] = { "fill", x, y, w, h, c } end,
  }
  local component = {
    list = function(ctype)
      local done = false
      return function()
        if done or ctype ~= "gpu" or opts.noGpu then return nil end
        done = true
        return "gpu-addr", "gpu"
      end
    end,
    proxy = function() return gpu end,
  }
  local queue = opts.signals or {}
  local t = 0
  local computer = {
    uptime = function() t = t + 0.05; return t end,
    pullSignal = function()
      local s = table.remove(queue, 1)
      if s then return table.unpack(s) end
      return nil
    end,
  }
  local fs = {
    home = function() return opts.home or "/home/tester" end,
    exists = function(p) return fx.files[p] ~= nil end,
    readFile = function(p) return fx.files[p] end,
    writeFile = function(p, d) fx.files[p] = d; return true end,
  }

  -- Faithful to kernel.sandbox: kernel.* raises; only the prebound
  -- component/computer and the compat whitelist resolve.
  local function sandboxRequire(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    if name == "compat.serialization" then return serialization end
    if type(name) == "string" and name:sub(1, 7) == "kernel." then
      error("sandbox: cannot require kernel module '" .. name .. "'", 2)
    end
    error("sandbox: module '" .. tostring(name) .. "' is not on the allowed list", 2)
  end

  fx.env = {
    assert = assert, error = error, pcall = pcall, xpcall = xpcall,
    type = type, tostring = tostring, tonumber = tonumber,
    pairs = pairs, ipairs = ipairs, next = next, select = select,
    setmetatable = setmetatable, getmetatable = getmetatable,
    math = math, string = string, table = table,
    require = sandboxRequire,
    fs = fs,
  }
  fx.env._G = fx.env

  fx.o = function(text, color) fx.out[#fx.out + 1] = tostring(text) end
  return fx
end

local function loadTetris(fx)
  local chunk = trypath({ base .. "init.lua", "modules/tetris/init.lua",
    "TOS-Extras/modules/tetris/init.lua" })
  if not chunk then return nil, "init.lua not found" end
  -- Re-load from source with the sandbox env (loadfile has no env on 5.1;
  -- read + load keeps this 5.3/5.4 clean).
  local path
  for _, p in ipairs({ base .. "init.lua", "modules/tetris/init.lua",
      "TOS-Extras/modules/tetris/init.lua" }) do
    local f = io.open(p, "r")
    if f then path = p; f:close(); break end
  end
  local f = io.open(path, "r")
  local src = f:read("*a")
  f:close()
  local fn, err = load(src, "=pkg:tetris", "t", fx.env)
  if not fn then return nil, err end
  local ok, mod = pcall(fn)
  if not ok then return nil, mod end
  return mod
end

print("=== tetris pkg-sandbox Tests ===")
print()

-- ── Entry loads inside the sandbox ───────────────────────────
local fx = makeFixture()
local mod, lerr = loadTetris(fx)
test("entry loads under sandbox env", "table", type(mod))
if not mod then
  print("  load error: " .. tostring(lerr))
  print(string.format("Results: %d passed, %d failed", passed, failed + 1))
  print("*** TESTS FAILED ***"); return false
end
test("exports commands.tetris", "function", type(mod.commands and mod.commands.tetris))

-- ── pkg dispatch convention: subcommand is args[1] ───────────
fx = makeFixture()
mod = loadTetris(fx)
mod.commands.tetris({ "help" }, fx.o)
test("`tetris help` shows help (args[1] convention)", "=== Tetris ===", fx.out[1])

fx = makeFixture()
mod = loadTetris(fx)
mod.commands.tetris({ "scores" }, fx.o)
test("`tetris scores` (no file) reports empty", true,
  (fx.out[1] or ""):find("No high scores yet", 1, true) ~= nil)
test("user derived from fs.home()", true,
  (fx.out[1] or ""):find("tester", 1, true) ~= nil)

-- ── Old-format score files still load ────────────────────────
fx = makeFixture()
fx.files["/home/tester/.tetris_hs"] =
  "return {{score=1200,lines=14,level=2,t=10},{score=300,lines=4,level=1,t=5}}"
mod = loadTetris(fx)
mod.commands.tetris({ "scores" }, fx.o)
local joined = table.concat(fx.out, "\n")
test("legacy 'return {...}' score file parses", true,
  joined:find("1200", 1, true) ~= nil)
test("both entries listed", true, joined:find("300", 1, true) ~= nil)

-- ── Launch + quit a real game session ────────────────────────
fx = makeFixture({ signals = {
  { "key_down", "kb", 113, 16 },  -- 'q' → quit cleanly
} })
mod = loadTetris(fx)
local okPlay, perr = pcall(mod.commands.tetris, {}, fx.o)
test("game launches and quits without error", true, okPlay)
if not okPlay then print("  error: " .. tostring(perr)) end
test("no kernel-unavailable message", nil,
  (function() for _, l in ipairs(fx.out) do
    if l:find("not available", 1, true) then return l end
  end end)())
do
  local drew = false
  for _, c in ipairs(fx.gpuCalls) do
    if c[1] == "set" and tostring(c[4]):find("TETRIS", 1, true) then drew = true; break end
  end
  test("playfield frame drawn via component GPU", true, drew)
end

-- ── Graceful degradation paths ───────────────────────────────
fx = makeFixture({ noGpu = true })
mod = loadTetris(fx)
mod.commands.tetris({}, fx.o)
test("no GPU → clean message", "No GPU found.", fx.out[1])

fx = makeFixture({ W = 30, H = 10 })
mod = loadTetris(fx)
mod.commands.tetris({}, fx.o)
test("small screen → size warning", true,
  (fx.out[1] or ""):find("Screen too small", 1, true) ~= nil)

-- ── Score write goes through the session fs ──────────────────
fx = makeFixture()
mod = loadTetris(fx)
-- No public save hook, so exercise via scores after a fake write the
-- way play() would: write with the serializer, read back via command.
fx.files["/home/tester/.tetris_hs"] = serialization.serialize(
  { { score = 777, lines = 9, level = 1, t = 1 } })
fx.out = {}
mod.commands.tetris({ "scores" }, fx.o)
test("new-format score file round-trips", true,
  table.concat(fx.out, "\n"):find("777", 1, true) ~= nil)

-- ── Line clearing collapses ALL completed rows at once ───────
-- Operator-reported bug: clearing 2+ simultaneous lines left some on the
-- board ("they clear one at a time"). The old loop interleaved remove+insert,
-- shifting the remaining cleared indices so it deleted the wrong rows.
mod = loadTetris(fx)
do
  local tt = mod._test
  test("exposes pure line-clear helpers", "table", type(tt))
  local BW, BH = 4, 4
  -- A non-full marker row (9 in col 1) sits ABOVE two FULL rows.
  local function board() return { {0,0,0,0}, {9,0,0,0}, {1,1,1,1}, {2,2,2,2} } end
  local b = board()
  test("detects BOTH full rows", "3,4", table.concat(tt.fullRows(b, BW, BH), ","))
  tt.removeRows(b, BW, tt.fullRows(b, BW, BH))
  test("NO completed line survives (the bug left one behind)", 0, #tt.fullRows(b, BW, BH))
  test("non-cleared marker row preserved + dropped to bottom", 9, b[BH][1])
  test("board height unchanged", BH, #b)

  -- A single-line clear still works.
  local s = { {0,0,0,0}, {0,0,0,0}, {0,0,0,0}, {5,5,5,5} }
  tt.removeRows(s, BW, tt.fullRows(s, BW, BH))
  test("single line still clears cleanly", 0, #tt.fullRows(s, BW, BH))

  -- A Tetris (4 lines) clears all four.
  local q = { {1,1,1,1}, {2,2,2,2}, {3,3,3,3}, {4,4,4,4} }
  test("a four-line clear detects 4", 4, #tt.fullRows(q, BW, BH))
  tt.removeRows(q, BW, tt.fullRows(q, BW, BH))
  test("four-line clear empties the board", 0, #tt.fullRows(q, BW, BH))
end

-- ── The NEXT preview refreshes when a piece locks ────────────
-- Operator report: "the next-piece panel doesn't update until I press the
-- down arrow." lock() painted the panel BEFORE spawn(), and spawn() is what
-- consumes `nxt` and draws a new one — so the preview kept showing the piece
-- that had just appeared on the board, and only caught up on a soft drop
-- (the one other updatePanel caller).
--
-- Deterministic without predicting any RNG: the 7-bag deals a permutation of
-- all seven pieces, so bag[2] and bag[3] are ALWAYS different pieces. The
-- preview at game start shows bag[2]; after the first lock it must show
-- bag[3]. With the bug the two are identical, whatever the shuffle did.
do
  -- depth 1 → tier-1 rendering, where preview cells are literal "[]" glyphs.
  local fxP = makeFixture({ depth = 1, signals = {
    { "key_down", "kb", 32, 57 },    -- SPACE: hard drop → lock + spawn
    { "key_down", "kb", 113, 16 },   -- 'q'  : quit
  } })
  local modP = loadTetris(fxP)
  pcall(modP.commands.tetris, {}, fxP.o)

  -- Anchor on the "NEXT" label; the 4x4 preview sits directly beneath it.
  local nx, ny
  for _, c in ipairs(fxP.gpuCalls) do
    if c[1] == "set" and c[4] == "NEXT" then nx, ny = c[2], c[3]; break end
  end
  test("found the NEXT label to anchor on", true, nx ~= nil)

  -- updatePanel clears the preview (a fill at the first preview row) and then
  -- draws the piece, so each such fill starts a fresh snapshot.
  local snaps = {}
  if nx then
    local cur = nil
    for _, c in ipairs(fxP.gpuCalls) do
      if c[1] == "fill" and c[2] == nx and c[3] == ny + 1 then
        cur = {}; snaps[#snaps + 1] = cur
      elseif cur and c[1] == "set" and c[4] == "[]"
             and c[2] >= nx and c[3] >= ny + 1 and c[3] <= ny + 4 then
        cur[#cur + 1] = (c[2] - nx) .. "," .. (c[3] - ny)
      end
    end
  end
  for _, s in ipairs(snaps) do table.sort(s) end

  test("preview was painted at least twice (start, then after the lock)",
    true, #snaps >= 2)
  if #snaps >= 2 then
    local first, second = table.concat(snaps[1], " "), table.concat(snaps[2], " ")
    test("first preview is not empty", true, #first > 0)
    -- The assertion that fails on the un-fixed build.
    test("preview CHANGES after a piece locks (bag[2] -> bag[3])",
      true, first ~= second)
  end
end

-- ── The quit key: the CHARACTER half of the binding must work ──
-- `quit` is bound to ^Q / F10 / Esc. ^Q is a CHAR binding (char 17); F10
-- and Esc are SCANCODE bindings. The game loop was destructuring
--   local sig, _, _, code = E.pull(timeout)
-- so the char arrived and was thrown away, and stdQuit was handed a nil
-- GLOBAL `ch` — which killed the char half outright. Nothing failed
-- visibly, because F10/Esc still worked and the test above quits with the
-- 'q' SCANCODE; an operator who rebound quit to another ^key would simply
-- have found the game had no exit.
--
-- The signal below is char 17 with a scancode that is NOT Q(16), F10(68)
-- or Esc(1), so ONLY the char half can match it.
fx = makeFixture({ signals = {
  { "key_down", "kb", 17, 0 },   -- ^Q, on a scancode no fallback matches
} })
mod = loadTetris(fx)
local okQuit, qerr = pcall(mod.commands.tetris, {}, fx.o)
test("game launches with only a ^Q waiting", true, okQuit)
if not okQuit then print("  error: " .. tostring(qerr)) end
do
  local gameOver = false
  for _, c in ipairs(fx.gpuCalls) do
    if c[1] == "set" and tostring(c[4]):find("GAME OVER", 1, true) then
      gameOver = true; break
    end
  end
  -- Quitting returns before a score is recorded, so the GAME OVER panel is
  -- the tell: if ^Q was ignored, the session ran on until the stack topped
  -- out and that panel is what ended it.
  test("^Q ended the session (no GAME OVER panel drawn)", false, gameOver)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
