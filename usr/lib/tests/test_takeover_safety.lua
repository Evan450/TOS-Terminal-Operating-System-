-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: takeover cinematic photosensitivity      ║
-- ║                                                            ║
-- ║  Operator rule (round 4): the easter egg must NEVER strobe ║
-- ║  the full screen — the original "glitch flicker" was three ║
-- ║  red/black full-field alternations in ~0.4s, a seizure     ║
-- ║  risk. This drives the WHOLE cinematic (both interactive   ║
-- ║  paths) against a virtual clock + scripted keys and fails  ║
-- ║  if any three consecutive full-screen paints of differing  ║
-- ║  colors land inside one second (WCAG-style flash limit),   ║
-- ║  or if the old full-field white "impact flash" returns.    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_takeover_safety.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail and ("  [" .. detail .. "]") or ""))
  end
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- ── Virtual clock + scripted keyboard ──────────────────────────────
-- takeover's reader() distinguishes a blocking read (pullSignal(3600))
-- from a timed wait (finite timeout). Timed waits ALWAYS time out (so
-- scripted keys are never eaten as pause-skips); blocking reads pop the
-- script, falling back to Esc so an unexpected prompt can't hang.
local clock = { t = 0 }
local script = {}
package.loaded["computer"] = {
  uptime = function() return clock.t end,
  pullSignal = function(timeout)
    if timeout and timeout < 3599 then
      clock.t = clock.t + timeout
      return nil
    end
    clock.t = clock.t + 0.2
    local k = table.remove(script, 1)
    if k then return "key_down", "kb", k[1], k[2] end
    return "key_down", "kb", 0, 1              -- Esc fallback
  end,
}

local takeover = require("shell.panels.takeover")

-- ── Instrumented display: record full-screen paints with times ─────
local W, H = 80, 25
local paints
local function newDisplay()
  paints = {}
  return {
    getSize = function() return W, H end,
    clear = function(color) paints[#paints + 1] = { t = clock.t, color = color } end,
    set = function() end,                       -- partial: not a field flash
    fill = function(x, y, w, h, ch, fg, bg)
      if x == 1 and y == 1 and w == W and h == H then
        paints[#paints + 1] = { t = clock.t, color = bg or fg }
      end
    end,
  }
end

-- Any 3 consecutive full-field paints of differing colors inside 1s = strobe.
local function strobeViolation()
  for i = 3, #paints do
    local a, b, c = paints[i - 2], paints[i - 1], paints[i]
    local differing = not (a.color == b.color and b.color == c.color)
    if differing and (c.t - a.t) < 1.0 then
      return string.format("paints %d-%d within %.2fs", i - 2, i, c.t - a.t)
    end
  end
  return nil
end

local function hasColor(color)
  for _, p in ipairs(paints) do if p.color == color then return true end end
  return false
end

print("=== takeover photosensitivity Tests ===")
print()

-- ── Path 1: refuse to play (tic-tac-toe futility ending) ───────────
clock.t = 0
script = { {110, 49}, {111, 24}, {13, 28} }     -- "n", "o", Enter
local S = { who = "root", D = newDisplay() }
local ending = takeover.run(S)
test("tictactoe path completes", ending == "tictactoe", tostring(ending))
local v = strobeViolation()
test("tictactoe path never strobes the full field", v == nil, v)
test("no full-field red paint (old glitch flicker gone)", not hasColor(0xFF0000))

-- ── Path 2: play + launch (the drill ending, old white flash) ──────
clock.t = 0
script = {
  {121, 21}, {101, 18}, {115, 31}, {13, 28},    -- "y","e","s", Enter
  {108, 38}, {13, 28},                           -- "l", Enter
}
S = { who = "root", D = newDisplay() }
ending = takeover.run(S)
test("launch path completes", ending == "launch", tostring(ending))
v = strobeViolation()
test("launch path never strobes the full field", v == nil, v)
test("no full-field WHITE impact flash", not hasColor(0xFFFFFF))

-- ── Path 3: invalid answer ("why") → retort → re-prompt → "no" ─────
clock.t = 0
script = {
  {119, 17}, {104, 35}, {121, 21}, {13, 28},    -- "w","h","y", Enter
  {110, 49}, {111, 24}, {13, 28},               -- "n","o", Enter
}
S = { who = "root", D = newDisplay() }
ending = takeover.run(S)
test("invalid-answer path re-prompts and completes",
  ending == "tictactoe", tostring(ending))
v = strobeViolation()
test("retort path never strobes the full field", v == nil, v)

-- ── Sanity: the detector itself would have caught the old code ─────
paints = {
  { t = 0.00, color = 0xFF0000 }, { t = 0.05, color = 0x000000 },
  { t = 0.13, color = 0xFF0000 },
}
test("detector flags the ORIGINAL red/black flicker", strobeViolation() ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
