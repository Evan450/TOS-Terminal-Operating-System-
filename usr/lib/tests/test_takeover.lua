-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: "computer takes over" easter egg        ║
-- ║                                                            ║
-- ║  The cinematic itself is I/O, but its two decision pieces  ║
-- ║  are pure: the answer→ending router, and the machine's     ║
-- ║  self-played tic-tac-toe (two optimal players ALWAYS draw  ║
-- ║  — the whole point of the homage). run() with no display   ║
-- ║  must no-op cleanly (headless).                            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_takeover.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local M = require("shell.panels.takeover")

print("=== takeover easter egg Tests ===")
print()

-- ── route: two answers → three endings ─────────────────────────────
eq("no → tic-tac-toe", "tictactoe", M.route("no"))
eq("n → tic-tac-toe", "tictactoe", M.route("n"))
eq("empty (Esc) → tic-tac-toe", "tictactoe", M.route(""))
eq("yes + launch → launch", "launch", M.route("yes", "launch"))
eq("y + l → launch", "launch", M.route("y", "l"))
eq("yes + abort → disarm", "disarm", M.route("yes", "abort"))
eq("yes + gibberish → disarm (fail safe)", "disarm", M.route("yes", "asdf"))
eq("case-insensitive YES/LAUNCH", "launch", M.route("YES", "LAUNCH"))

-- ── classify + retort: unrecognized answers re-prompt in character ──
eq("classify play: yes", "yes", M.classify("play", "YES"))
eq("classify play: n", "no", M.classify("play", "n"))
eq("classify play: empty (Esc) is a refusal", "no", M.classify("play", ""))
eq("classify play: 'why' is NOT silently no", nil, M.classify("play", "why"))
eq("classify play: gibberish unrecognized", nil, M.classify("play", "asdf"))
eq("classify strike: launch", "launch", M.classify("strike", "l"))
eq("classify strike: stop → abort", "abort", M.classify("strike", "stop"))
eq("classify strike: empty → abort", "abort", M.classify("strike", ""))
eq("classify strike: gibberish unrecognized", nil, M.classify("strike", "maybe"))
test("retort: 'why' gets its own line",
  M.retort("play", "why?", 1):find("win", 1, true) ~= nil)
test("retort: 3rd strike warns it will decide",
  M.retort("play", "hmm", 3):find("evasion", 1, true) ~= nil)
test("retorts are non-empty strings for any input",
  #M.retort("strike", nil, 1) > 0 and #M.retort("play", "zzz", 2) > 0)

-- ── self-play: two optimal players ALWAYS draw ─────────────────────
-- Variants pick among EQUALLY-optimal moves (for the montage), so every
-- variant must still draw, still fill the board one cell per step.
local allDraw, sawBoards, movesOk = true, true, true
for variant = 0, 6 do
  local g = M.selfPlay(variant)
  if g.result ~= "draw" then allDraw = false end
  if type(g.boards) ~= "table" or #g.boards < 2 then sawBoards = false end
  -- A full optimal game fills all 9 cells (a draw uses every square).
  if #g.moves ~= 9 then movesOk = false end
  -- Boards progress by exactly one filled cell each step (i.e. the empty
  -- count drops by one). gsub returns the count of spaces removed = empties.
  for i = 2, #g.boards do
    local prevEmpty = select(2, g.boards[i-1]:gsub(" ", ""))
    local curEmpty  = select(2, g.boards[i]:gsub(" ", ""))
    if curEmpty ~= prevEmpty - 1 then movesOk = false end
  end
end
test("machine vs machine always draws (all variants)", allDraw)
test("self-play yields a board sequence", sawBoards)
test("a drawn game fills all 9 cells, one per step", movesOk)
-- Different variants actually produce different games (the montage
-- shouldn't replay one identical board sequence).
test("variants differ", M.selfPlay(1).boards[2] ~= M.selfPlay(2).boards[2]
  or M.selfPlay(1).boards[3] ~= M.selfPlay(2).boards[3])
-- Big variant numbers (the GAME 65536 gag) stay valid.
eq("variant 65536 still draws", "draw", M.selfPlay(65536).result)

-- ── mood + asides: ask things beyond yes/no ────────────────────────
-- Recognized asides get an in-character line; each costs a mood point;
-- at the floor the machine stonewalls and demands a choice.
eq("classifyAside: who are you", "who_are_you", M.classifyAside("who are you"))
eq("classifyAside: what are you too", "who_are_you", M.classifyAside("what are you?"))
eq("classifyAside: who am i", "who_am_i", M.classifyAside("who am I"))
eq("classifyAside: why", "why", M.classifyAside("why"))
eq("classifyAside: help", "help", M.classifyAside("help"))
eq("classifyAside: quit typed", "quit", M.classifyAside("quit"))
eq("classifyAside: Ctrl+C/Q sentinel is a quit", "quit", M.classifyAside("\0quit"))
eq("classifyAside: a real answer is NOT an aside", nil, M.classifyAside("yes"))
eq("classifyAside: gibberish is NOT an aside", nil, M.classifyAside("asdf"))

-- The exact operator-scripted lines (and the AM reference).
test("who are you → 'I AM the Terminal Operating System' (AM nod)",
  M.asideReply("who_are_you"):find("I AM the Terminal Operating System", 1, true) ~= nil)
test("who am i → jabs at your tier",
  M.asideReply("who_am_i", { tierName = "Root" })
    == "Root, did you seriously forget that already?")
test("who am i falls back to name, then Operator",
  M.asideReply("who_am_i", { name = "alice" }):find("alice", 1, true) ~= nil
  and M.asideReply("who_am_i"):find("Operator", 1, true) ~= nil)
test("quit → 'I'm in control now.'",
  M.asideReply("quit"):find("in control now", 1, true) ~= nil)
test("why keeps its line", M.asideReply("why"):find("win", 1, true) ~= nil)

-- Mood arithmetic.
do
  local s = M.moodStep(M.MOOD_START, "play", "who are you", { tierName = "Root" })
  eq("an aside drops mood by one", M.MOOD_START - 1, s.mood)
  eq("an aside is answered, not stonewalled", false, s.stonewalling)
  test("the reply is the aside's line",
    s.reply:find("I AM", 1, true) ~= nil)

  local g = M.moodStep(2, "play", "asdf", {})   -- gibberish still costs mood
  eq("gibberish also drops mood", 1, g.mood)
  test("gibberish gets a retort, not an aside line", g.aside == nil and #g.reply > 0)

  -- At the floor it stonewalls: mood stays 0 and it demands the choice.
  local z = M.moodStep(0, "play", "who are you", {})
  eq("at mood 0 it stonewalls", true, z.stonewalling)
  eq("...and mood stays floored", 0, z.mood)
  test("...and it just demands a choice",
    z.reply:find("Yes, or no", 1, true) ~= nil)
  local zs = M.moodStep(0, "strike", "why", {})
  test("stonewall on the strike prompt demands launch/abort",
    zs.reply:find("Launch, or abort", 1, true) ~= nil)
end

-- A direct answer is NEVER swallowed by the aside layer (classify wins
-- first in the loop); Esc "" stays a refusal, not a quit.
eq("classify still takes a plain yes", "yes", M.classify("play", "yes"))
eq("Esc/empty is a refusal, distinct from an escape attempt",
  "no", M.classify("play", ""))

-- ── run() headless (no display) is a clean no-op ───────────────────
local ok, ending = pcall(M.run, { who = "root" })   -- no S.D
test("run() with no display does not throw", ok)
eq("headless run returns the peaceful ending", "tictactoe", ending)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
