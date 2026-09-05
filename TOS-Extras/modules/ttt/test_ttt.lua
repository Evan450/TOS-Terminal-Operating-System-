-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: ttt/logic.lua                              ║
-- ║                                                              ║
-- ║  Pure rules, no hardware. Winner detection, move legality,   ║
-- ║  the AI taking a win / blocking a loss, and — the headline — ║
-- ║  a proof the AI is genuinely UNBEATABLE by exhaustively      ║
-- ║  playing EVERY human line against it. Also the self-play     ║
-- ║  that feeds the zero-player easter-egg montage, and a pin    ║
-- ║  that the command that montage reveals is still the command  ║
-- ║  the base image actually fires the cinematic on.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/ttt/test_ttt.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "modules/?.lua;modules/?/init.lua;" .. package.path
local L = require("ttt.logic")

print("=== ttt/logic Tests ===")
print()

-- ── Winner detection ───────────────────────────────────────────────
do
  eq("empty board has no winner", nil, L.winner({}))
  eq("top row wins", "X", L.winner({ "X", "X", "X" }))
  eq("a column wins", "O",
    L.winner({ "O", nil, nil, "O", nil, nil, "O" }))
  eq("a diagonal wins", "X",
    L.winner({ "X", nil, nil, nil, "X", nil, nil, nil, "X" }))
  local _, line = L.winner({ "X", "X", "X" })
  test("the winning line is reported", line and line[1] == 1 and line[3] == 3)
  eq("a full board with no line is a draw", "draw",
    L.winner({ "X","O","X", "X","O","O", "O","X","X" }))
end

-- ── Move legality ──────────────────────────────────────────────────
do
  local b = L.newBoard()
  eq("a legal move succeeds", true, L.play(b, 5, "X"))
  eq("the mark landed", "X", b[5])
  eq("an occupied cell is refused", false, L.play(b, 5, "O"))
  eq("out-of-range is refused", false, L.play(b, 99, "O"))
  eq("non-numeric is refused", false, L.play(b, "five", "O"))
  local done = { "X","X","X" }
  eq("no moves after the game ends", false, L.play(done, 5, "O"))
end

-- ── The AI takes a win and blocks a loss ───────────────────────────
do
  local b = { "O", "O", nil, "X", "X", nil, nil, nil, nil }
  eq("the AI takes an immediate win", 3, L.bestMove(b, "O"))
  local b2 = { "X", "X", nil, nil, "O", nil, nil, nil, nil }
  eq("the AI blocks an immediate loss", 3, L.bestMove(b2, "O"))
  eq("no move on a finished board", nil, L.bestMove({ "X","X","X" }, "O"))
end

-- ── The AI is genuinely UNBEATABLE ─────────────────────────────────
-- Exhaustive search over EVERY human line: human (X) moves first and
-- tries every legal reply at every depth; the AI (O) answers with
-- bestMove. If any leaf has X winning, the AI is beatable.
do
  local humanWins, draws, aiWins, games = 0, 0, 0, 0
  local function explore(b)
    local w = L.winner(b)
    if w then
      games = games + 1
      if w == "X" then humanWins = humanWins + 1
      elseif w == "O" then aiWins = aiWins + 1
      else draws = draws + 1 end
      return
    end
    for i = 1, 9 do
      if not b[i] then
        b[i] = "X"
        local w2 = L.winner(b)
        if w2 then
          games = games + 1
          if w2 == "X" then humanWins = humanWins + 1
          elseif w2 == "O" then aiWins = aiWins + 1
          else draws = draws + 1 end
        else
          local m = L.bestMove(b, "O")
          if m then b[m] = "O"; explore(b); b[m] = nil end
        end
        b[i] = nil
      end
    end
  end
  explore(L.newBoard())
  test("the exhaustive search actually ran (" .. games .. " terminal positions)",
    games > 100)
  eq("the human NEVER wins — the AI is unbeatable", 0, humanWins)
  test("the AI does win when the human errs (" .. aiWins .. " wins)", aiWins > 0)
  test("perfect human play draws (" .. draws .. " draws)", draws > 0)
end

-- ── Tie-breaking varies the machine's play ─────────────────────────
do
  local seen = {}
  for pick = 1, 9 do
    local m = L.bestMove(L.newBoard(), "X", function(n)
      return ((pick - 1) % n) + 1
    end)
    if m then seen[m] = true end
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  test("tie-breaking yields more than one opening (" .. distinct .. ")", distinct > 1)
  test("a tie-broken opener is still an optimal move",
    L.bestMove(L.newBoard(), "X", function() return 1 end) ~= nil)
end

-- ── Self-play (feeds the zero-player easter-egg montage) ───────────
do
  local nonDraw, shortest, longest = nil, 99, 0
  for v = 1, 200 do
    local g = L.selfPlay(v)
    if g.result ~= "draw" then nonDraw = nonDraw or (v .. "->" .. tostring(g.result)) end
    if #g.boards < shortest then shortest = #g.boards end
    if #g.boards > longest then longest = #g.boards end
  end
  test("200 self-play variants ALL draw"
    .. (nonDraw and ("  [" .. nonDraw .. "]") or ""), nonDraw == nil)
  eq("a full game is always 9 moves (nobody ever wins early)", 9, shortest)
  eq("...and never more", 9, longest)

  local a1 = L.selfPlay(3)
  local a2 = L.selfPlay(3)
  local same = true
  for i = 1, 9 do if a1.boards[9][i] ~= a2.boards[9][i] then same = false end end
  test("a variant replays identically", same)

  local seen, distinct = {}, 0
  for _, v in ipairs({ 1, 2, 3, 7, 19, 128, 1729, 65536 }) do
    local key = table.concat(L.selfPlay(v).boards[9], "")
    if not seen[key] then seen[key] = true; distinct = distinct + 1 end
  end
  test("the montage's variants are genuinely different games ("
    .. distinct .. "/8 distinct)", distinct > 1)

  local g = L.selfPlay(42)
  local marksOK = true
  for step, b in ipairs(g.boards) do
    local x, o2 = 0, 0
    for i = 1, 9 do
      if b[i] == "X" then x = x + 1 elseif b[i] == "O" then o2 = o2 + 1 end
    end
    if x + o2 ~= step or x < o2 or x - o2 > 1 then marksOK = false end
  end
  test("every montage frame is a legal alternating position", marksOK)
end

-- ── The easter-egg reveal must name the REAL trigger ───────────────
-- The zero-player scene exists to make the OS's hidden cinematic
-- findable without reading source. If the command it prints ever drifts
-- from the command the OS actually listens for, the scene silently
-- becomes a dead end — so pin it against the base image.
do
  local function readAll(p)
    local h = io.open(p, "rb"); if not h then return nil end
    local s = h:read("*a"); h:close(); return s
  end
  local function findUp(rel)
    for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
      local s = readAll(pre .. rel)
      if s then return s end
    end
  end

  local tttSrc = findUp("modules/ttt/init.lua")
  test("ttt/init.lua readable", tttSrc ~= nil)
  local adminSrc = findUp("../TOS-Dev/tos/shell/panels/commands/admin.lua")
    or findUp("../tos/shell/panels/commands/admin.lua")
  test("the base image's admin.lua readable (holds the trigger)",
    adminSrc ~= nil)

  if tttSrc and adminSrc then
    test("the scene reveals a command",
      tttSrc:match("usermod computer root") ~= nil)
    test("the base image really listens for that command",
      adminSrc:find("usermod computer root", 1, true) ~= nil)
    test("...and it is wired to the takeover cinematic",
      adminSrc:find("takeover", 1, true) ~= nil)
  end

  if tttSrc then
    test("but 0p IS accepted as an argument",
      tttSrc:find('v == "0p"', 1, true) ~= nil)
    test("the scene honours the photosensitivity rule (documented)",
      tttSrc:find("PHOTOSENSITIVITY RULE", 1, true) ~= nil)
    test("...and every montage hold is >= 0.1s",
      not tttSrc:find("wait%(0%.0"))
  end
end

-- ── Bare `ttt` lists the modes instead of launching ────────────────
-- A full-screen game that starts the moment you type its name gives you
-- nowhere to learn it has options (the hotseat mode went unnoticed).
-- The zero-player mode must stay OFF this list — discovery is the point.
do
  package.loaded["component"] = {
    list = function() return function() return nil end end,
    proxy = function() return nil end,
  }
  package.loaded["computer"] = {
    uptime = function() return 0 end,
    pullSignal = function() return nil end,
    beep = function() end,
  }
  local mod = dofile("modules/ttt/init.lua")
  test("the package exposes a ttt command",
    type(mod) == "table" and type(mod.commands) == "table"
    and type(mod.commands.ttt) == "function")

  local function capture(args)
    local lines = {}
    local ok = pcall(mod.commands.ttt, args, function(s) lines[#lines + 1] = tostring(s) end)
    return ok, table.concat(lines, "\n")
  end

  local ok, out = capture({})
  test("bare `ttt` runs without a GPU (it must not try to launch)", ok)
  test("bare `ttt` lists the play mode", out:find("ttt play", 1, true) ~= nil)
  test("bare `ttt` lists the hotseat mode", out:find("ttt 2p", 1, true) ~= nil)
  test("bare `ttt` explains the in-game keys", out:find("arrows move", 1, true) ~= nil
    or out:find("Arrows move", 1, true) ~= nil)
  test("bare `ttt` does NOT leak the zero-player mode",
    out:find("0p", 1, true) == nil and out:lower():find("zero", 1, true) == nil)

  local okH, outH = capture({ "help" })
  test("`ttt help` prints the same list", okH and outH == out)

  -- A real mode must NOT print help — it should try to open a screen and
  -- bail cleanly on this GPU-less stub rather than listing modes.
  local okP, outP = capture({ "play" })
  test("`ttt play` does not print the mode list", okP
    and outP:find("ttt 2p", 1, true) == nil)
  local okZ, outZ = capture({ "0p" })
  test("`ttt 0p` does not print the mode list either", okZ
    and outZ:find("ttt 2p", 1, true) == nil)
end

-- ── Mouse: which cell did the operator click? ─────────────────────
-- The grid is 3 cells of CW x CH with ONE separator column/row between
-- them (init.lua's cellOrigin: gx + c*(CW+1), gy + r*(CH+1)). A click on
-- a separator is NOT a move: rounding it into a neighbour would place a
-- piece where the operator did not aim.
--
-- NOTE this file's helpers: test(name, cond) and eq(name, expected,
-- actual). Using test() for a value comparison silently passes on any
-- truthy value — which it did, for four asserts, until these were
-- rewritten.
do
  local gx, gy, CW, CH = 5, 4, 7, 3
  local function origin(i)
    local r, c = math.floor((i - 1) / 3), (i - 1) % 3
    return gx + c * (CW + 1), gy + r * (CH + 1)
  end

  -- Every cell: top-left, bottom-right and centre all resolve to it.
  local allOk = true
  for i = 1, 9 do
    local x, y = origin(i)
    for _, pt in ipairs({ {x, y}, {x + CW - 1, y + CH - 1},
                          {x + math.floor(CW/2), y + math.floor(CH/2)} }) do
      if L.cellAt(pt[1], pt[2], gx, gy, CW, CH) ~= i then allOk = false end
    end
  end
  test("every corner and centre of all 9 cells maps to its own cell", allOk)

  -- The corners specifically — the clicks most likely to land a pixel off.
  eq("top-left cell is 1", 1, L.cellAt(gx, gy, gx, gy, CW, CH))
  eq("top-right cell is 3", 3, L.cellAt(gx + 2 * (CW + 1), gy, gx, gy, CW, CH))
  eq("bottom-left cell is 7", 7, L.cellAt(gx, gy + 2 * (CH + 1), gx, gy, CW, CH))
  eq("bottom-right cell is 9", 9,
    L.cellAt(gx + 2 * (CW + 1) + CW - 1, gy + 2 * (CH + 1) + CH - 1, gx, gy, CW, CH))

  -- Separators and everything off the board return nil.
  test("a click on the vertical separator is not a move",
    L.cellAt(gx + CW, gy, gx, gy, CW, CH) == nil)
  test("a click on the horizontal separator is not a move",
    L.cellAt(gx, gy + CH, gx, gy, CW, CH) == nil)
  test("a click above the board is not a move",
    L.cellAt(gx, gy - 1, gx, gy, CW, CH) == nil)
  test("a click left of the board is not a move",
    L.cellAt(gx - 1, gy, gx, gy, CW, CH) == nil)
  test("a click past the last column is not a move",
    L.cellAt(gx + 3 * (CW + 1), gy, gx, gy, CW, CH) == nil)
  test("a click below the last row is not a move",
    L.cellAt(gx, gy + 3 * (CH + 1), gx, gy, CW, CH) == nil)

  -- Garbage in, nil out: a signal with missing coordinates must not
  -- throw inside the game loop.
  test("non-numeric coordinates are refused",
    L.cellAt(nil, nil, gx, gy, CW, CH) == nil)
  test("...and do not raise", (pcall(L.cellAt, "x", {}, gx, gy, CW, CH)))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
