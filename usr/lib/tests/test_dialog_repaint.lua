-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a dialog repaints when it CHANGES            ║
-- ║                                                                ║
-- ║  Operator report, real emulator: "the dialog box options       ║
-- ║  flicker when updating."                                       ║
-- ║                                                                ║
-- ║  Both modal loops called drawDialog at the top of every        ║
-- ║  iteration, so the whole box -- shadow, frame runs, title tab, ║
-- ║  every message line, every button -- was re-emitted for ANY    ║
-- ║  signal that woke the loop. A dialog waits inside              ║
-- ║  coroutine.yield(), which returns on whatever the scheduler    ║
-- ║  resumes it with: a timer tick, a modem message, a component   ║
-- ║  event. None of those change the box.                          ║
-- ║                                                                ║
-- ║  With room for the dirty-cell shadow that is invisible --      ║
-- ║  identical cells elide. On a tight seat the shadow is gated    ║
-- ║  off, every repaint reaches the GPU, and the buttons flicker   ║
-- ║  while the box just sits there. So this counts DRAWS, which is ║
-- ║  the thing that was wrong, rather than pixels.                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_dialog_repaint.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local here = (arg and arg[0]) or "usr/lib/tests/test_dialog_repaint.lua"
local base = here:gsub("[^/\\]*$", "")

-- A signal queue the test controls, delivered the way the real loops get
-- theirs: dialogs.lua uses coroutine.yield() when it is yieldable, so the
-- whole dialog runs inside a coroutine and every yield hands back one
-- signal from this list.
local dialogs
for _, p in ipairs({ base .. "../../../tos/shell/panels/dialogs.lua",
    "tos/shell/panels/dialogs.lua", "TOS-Dev/tos/shell/panels/dialogs.lua" }) do
  local chunk = loadfile(p); if chunk then dialogs = chunk(); break end
end
if not dialogs then
  print("FAIL: could not load dialogs.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); os.exit(1)
end

-- A display that counts what reaches it. `sets` is the number of draw
-- calls; `frames` counts begin/endFrame pairs.
local function newDisplay(withFrames)
  local D = { sets = 0, fills = 0, frames = 0, open = 0, maxOpen = 0 }
  function D.set() D.sets = D.sets + 1 end
  function D.fill() D.fills = D.fills + 1 end
  if withFrames then
    function D.beginFrame() D.open = D.open + 1
      if D.open > D.maxOpen then D.maxOpen = D.open end
      D.frames = D.frames + 1; return true end
    function D.endFrame() D.open = D.open - 1; return true end
  end
  return D
end

local function newState(D)
  return { D = D, W = 80, H = 25,
           T = setmetatable({}, { __index = function() return 0 end }) }
end

-- Run a dialog inside a coroutine, feeding it `signals` one at a time.
-- Returns what the dialog returned, plus the display.
local function runDialog(signals, fn, withFrames)
  local D = newDisplay(withFrames)
  local S = newState(D)
  local co = coroutine.create(function() return fn(S) end)
  local ok, res = coroutine.resume(co)
  local i = 0
  while coroutine.status(co) ~= "dead" do
    i = i + 1
    local sig = signals[i]
    if not sig then error("dialog never answered after " .. #signals .. " signals", 0) end
    ok, res = coroutine.resume(co, table.unpack(sig, 1, sig.n or #sig))
    if not ok then error(res, 0) end
  end
  return res, D
end

local KEY  = function(char, code) return { n = 4, "key_down", "kb", char, code } end
local ENTER = KEY(13, 28)
local RIGHT = KEY(0, 205)
local NOISE = { n = 4, "modem_message", "addr", "from", 1234 }
local TIMER = { n = 2, "timer", 1 }

print("=== a dialog repaints only when it changes ===")
print()

-- ── The bug: signals that change nothing must not repaint ────────
print("-- signals that change nothing --")
local pick, D = runDialog({ ENTER }, function(S)
  return dialogs.dialog(S, { message = "Delete this?", buttons = { "No", "Yes" },
                             title = "Delete", default = 1, escIndex = 1 })
end)
eq("the dialog answered", 1, pick)
local baseline = D.sets
test("one paint before the first signal (" .. baseline .. " draw calls)", baseline > 0)

local _, D2 = runDialog({ NOISE, TIMER, NOISE, NOISE, TIMER, ENTER }, function(S)
  return dialogs.dialog(S, { message = "Delete this?", buttons = { "No", "Yes" },
                             title = "Delete", default = 1, escIndex = 1 })
end)
eq("five irrelevant signals cost NOT ONE extra draw call", baseline, D2.sets)

-- ── ...but a focus change must ────────────────────────────────────
print()
print("-- a focus change --")
local pick3, D3 = runDialog({ RIGHT, ENTER }, function(S)
  return dialogs.dialog(S, { message = "Delete this?", buttons = { "No", "Yes" },
                             title = "Delete", default = 1, escIndex = 1 })
end)
eq("moving focus and confirming picks the second button", 2, pick3)
test("...and it repainted exactly once more (" .. D3.sets .. " vs " .. baseline .. ")",
  D3.sets == baseline * 2)

local _, D4 = runDialog({ RIGHT, NOISE, TIMER, NOISE, ENTER }, function(S)
  return dialogs.dialog(S, { message = "Delete this?", buttons = { "No", "Yes" },
                             title = "Delete", default = 1, escIndex = 1 })
end)
eq("noise around a focus change still costs only the one repaint", D3.sets, D4.sets)

-- ── The repaint lands in a frame when the seat has one ───────────
print()
print("-- the repaint is atomic where it can be --")
local _, D5 = runDialog({ RIGHT, ENTER }, function(S)
  return dialogs.dialog(S, { message = "Delete this?", buttons = { "No", "Yes" },
                             title = "Delete", default = 1, escIndex = 1 })
end, true)
eq("both paints opened a frame", 2, D5.frames)
eq("every frame was closed", 0, D5.open)
eq("frames never nested", 1, D5.maxOpen)

-- A display with no frame support must still work untouched.
local pick6 = runDialog({ ENTER }, function(S)
  return dialogs.dialog(S, { message = "No frames here", buttons = { "OK" } })
end)
eq("a display without beginFrame still answers", 1, pick6)

-- ── confirmTyped: the same rule, plus the typed text ─────────────
print()
print("-- confirmTyped --")
local function typeWord(word)
  local sigs = {}
  for i = 1, #word do sigs[#sigs + 1] = KEY(word:byte(i), 0) end
  return sigs
end
-- One render's worth of draw calls, measured: open the box and cancel at
-- once. Noise first, to prove the very first signal cannot repaint it.
local okTyped2, D6 = runDialog({ NOISE, TIMER, KEY(0, 1) }, function(S)   -- Esc
  return dialogs.confirmTyped(S, "Everything goes.", "wipe", { title = "Wipe" })
end)
test("Esc still cancels", okTyped2 == false)
local oneRender = D6.sets
test("a typed-confirm box is one render before any input (" .. oneRender .. " draws)",
  oneRender > 0)

do
  local sigs = { NOISE, TIMER }
  for _, s in ipairs(typeWord("wipe")) do sigs[#sigs + 1] = s end
  sigs[#sigs + 1] = NOISE
  sigs[#sigs + 1] = RIGHT      -- focus Confirm
  sigs[#sigs + 1] = ENTER
  local okTyped, D7 = runDialog(sigs, function(S)
    return dialogs.confirmTyped(S, "Everything goes.", "wipe", { title = "Wipe" })
  end)
  test("typing the word and confirming returns true", okTyped == true)
  -- Six renders: the first paint, one per keystroke of "wipe", and one
  -- for the focus move. The three noise signals must add none.
  eq("it repainted once per REAL change, not once per signal",
     oneRender * 6, D7.sets)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
