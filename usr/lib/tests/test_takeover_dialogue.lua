-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the egg's answer line doesn't slice the     ║
-- ║  motto, and the machine beeps when it talks                   ║
-- ║                                                              ║
-- ║  The reply row is H-8, which on an 80x25 screen is EXACTLY    ║
-- ║  the motto's last line ("That is why I am here."). Drawing    ║
-- ║  one line there left the greeting above visibly cut in half   ║
-- ║  — the operator's report was that asking the machine a        ║
-- ║  question "clears the 'they weren't lying...' text            ║
-- ║  (somewhat)". The answer now clears its whole neighbourhood   ║
-- ║  first, so every reply lands on clean space.                  ║
-- ║                                                              ║
-- ║  Drives the REAL cinematic with a recording surface and a     ║
-- ║  scripted keyboard, so this is behavioural, not a source      ║
-- ║  grep.                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_takeover_dialogue.lua  (from TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- ── Virtual clock, scripted keys, and a beep counter ──────────────
local clock = { t = 0 }
local script = {}
local beeps = 0
package.loaded["computer"] = {
  uptime = function() return clock.t end,
  beep = function() beeps = beeps + 1 end,
  pullSignal = function(timeout)
    -- Timed waits always time out (so scripted keys aren't eaten as
    -- pause-skips); blocking reads pop the script, Esc as a fallback.
    if timeout and timeout < 3599 then
      clock.t = clock.t + timeout
      return nil
    end
    clock.t = clock.t + 0.2
    local k = table.remove(script, 1)
    if k then return "key_down", "kb", k[1], k[2] end
    return "key_down", "kb", 0, 1
  end,
}

local takeover = require("shell.panels.takeover")

-- ── A surface that records what lands on each row ─────────────────
local W, H = 80, 25
local rows, events
local function newDisplay()
  rows, events = {}, {}
  local function put(y, text)
    rows[y] = text
    events[#events + 1] = { kind = "set", y = y, text = text }
  end
  return {
    getSize = function() return W, H end,
    clear = function() rows = {}; events[#events + 1] = { kind = "clear" } end,
    set = function(x, y, text) put(y, tostring(text)) end,
    fill = function(x, y, w, h, ch)
      for yy = y, y + (h or 1) - 1 do rows[yy] = nil end
      events[#events + 1] = { kind = "fill", y = y, h = h or 1 }
    end,
  }
end

-- Type a word, then Enter.
local function typeWord(word)
  for i = 1, #word do script[#script + 1] = { word:byte(i), 0 } end
  script[#script + 1] = { 13, 28 }        -- Enter
end

print("=== takeover dialogue: clean answers + voice ===")
print()

-- ── Ask an aside, then refuse — the reply must not leave a stub ───
do
  clock.t, beeps = 0, 0
  script = {}
  typeWord("who are you")     -- an aside: the machine answers
  script[#script + 1] = { 0, 1 }          -- Esc: quiet refusal -> peaceful end

  local S = { who = "root", D = newDisplay() }
  local ok, ending = pcall(takeover.run, S)
  test("the cinematic ran with an aside in it", ok)
  test("an aside still reaches an ending", ending ~= nil)

  -- Find the moment the answer was drawn, and prove the rows around it
  -- were cleared in the SAME beat (not left holding motto fragments).
  local replyRow = H - 8
  local answerIdx
  for i, e in ipairs(events) do
    if e.kind == "set" and e.y == replyRow
       and type(e.text) == "string" and e.text:find("I AM", 1, true) then
      answerIdx = i
    end
  end
  test("the machine's answer was drawn on the reply row", answerIdx ~= nil)

  if answerIdx then
    -- The fill immediately preceding the answer must span more than the
    -- single reply row — that is the fix.
    local cleared = false
    for i = answerIdx - 1, math.max(1, answerIdx - 3), -1 do
      local e = events[i]
      if e.kind == "fill" and e.y <= replyRow and (e.y + e.h - 1) >= replyRow
         and e.h > 1 then
        cleared = true
      end
    end
    test("the answer clears a BLOCK, not just its own row", cleared)

    -- And nothing above it is left half-written: the motto's rows are
    -- either fully gone or fully intact, never a stub.
    local stub = false
    for y = replyRow - 2, replyRow - 1 do
      local t = rows[y]
      if type(t) == "string" and t:find("They were not lying", 1, true) then
        stub = true      -- the first motto line survived while its tail died
      end
    end
    test("no sliced motto line is left on screen", not stub)
  end

  test("the machine beeped while speaking (" .. beeps .. " blips)", beeps > 0)
end

-- ── A silent box must not crash the cinematic ─────────────────────
do
  clock.t = 0
  script = {}
  script[#script + 1] = { 0, 1 }           -- Esc straight away
  local saved = package.loaded["computer"].beep
  package.loaded["computer"].beep = nil    -- no sound support at all
  -- takeover caches its `computer` handle on first use; the guard has to
  -- cope with a handle that simply has no beep().
  local S = { who = "root", D = newDisplay() }
  local ok = pcall(takeover.run, S)
  test("a machine with no beep() still runs the cinematic", ok)
  package.loaded["computer"].beep = saved
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
