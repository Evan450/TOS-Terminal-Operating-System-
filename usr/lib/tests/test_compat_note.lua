-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Test: compat/note.lua — note names, MIDI codes, frequencies      ║
-- ║                                                                    ║
-- ║  OpenOS's lib/note.lua builds a 75-entry name->MIDI table at load  ║
-- ║  time (a0..b6 = MIDI 21..95) plus a reverse table plus a third     ║
-- ║  pass for the flat spellings. Ours COMPUTES the same mapping, so   ║
-- ║  the interesting risk is an off-by-one that only shows on some     ║
-- ║  notes. The round-trip below walks every code in the range rather  ║
-- ║  than spot-checking: midi(name(m)) == m for all 75, which a        ║
-- ║  shifted octave or a wrong semitone table cannot survive.          ║
-- ║                                                                    ║
-- ║  The range is theirs on purpose: 21..95 is what computer.beep can  ║
-- ║  sound, so a name outside it must RAISE, not return a frequency    ║
-- ║  the sound card will refuse.                                       ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_note.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " (expected " .. tostring(expected) ..
          ", got " .. tostring(actual) .. ")")
  end
end
local function near(name, expected, actual)
  local ok = type(actual) == "number" and math.abs(expected - actual) < 1e-6
  if ok then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " (expected ~" .. tostring(expected) ..
          ", got " .. tostring(actual) .. ")")
  end
end

package.path = "tos/?.lua;" .. package.path

local beeps = {}
package.loaded["computer"] = {
  beep = function(freq, dur) beeps[#beeps + 1] = { freq = freq, dur = dur } end,
}

local note = require("compat.note")

print("── MIDI codes from names ──")
eq("a0 is the bottom of the range (21)", 21, note.midi("a0"))
eq("a4 is concert pitch (69)",           69, note.midi("a4"))
eq("c4 is middle C (60)",                60, note.midi("c4"))
eq("b6 is the top of the range (95)",    95, note.midi("b6"))
eq("names are case-insensitive",         69, note.midi("A4"))
eq("a#0 is 22",                          22, note.midi("a#0"))
eq("bb0 is a#0 (22)",                    22, note.midi("bb0"))
eq("gb4 is f#4",  note.midi("f#4"), note.midi("gb4"))

print("── frequencies ──")
near("a4 is 440 Hz",        440,  note.freq("a4"))
near("a5 is 880 Hz",        880,  note.freq("a5"))
near("a3 is 220 Hz",        220,  note.freq("a3"))
near("freq(69) is 440 Hz",  440,  note.freq(69))
near("c4 is ~261.6256 Hz",  261.6255653, note.freq("c4"))

print("── a number given to midi() is a FREQUENCY, not a code ──")
eq("midi(440) is 69", 69, note.midi(440))
eq("midi(880) is 81", 81, note.midi(880))

print("── names from MIDI codes ──")
eq("69 is A4",   "A4",   note.name(69))
eq("60 is C4",   "C4",   note.name(60))
eq("22 is A#0",  "A#0",  note.name(22))
eq("21 is A0",   "A0",   note.name(21))
eq("95 is B6",   "B6",   note.name(95))

print("── the whole range round-trips ──")
do
  local bad = nil
  for m = 21, 95 do
    local back = note.midi(note.name(m))
    if back ~= m then bad = m .. " -> " .. note.name(m) .. " -> " .. back; break end
  end
  test("midi(name(m)) == m for every code 21..95", bad == nil)
  if bad then print("    first mismatch: " .. bad) end
end

print("── the range is enforced ──")
test("c0 (below a0) raises",  not pcall(note.midi, "c0"))
test("c7 (above b6) raises",  not pcall(note.midi, "c7"))
test("a nonsense name raises", not pcall(note.midi, "zz9"))
test("freq of an out-of-range name raises", not pcall(note.freq, "c0"))
test("a table raises",          not pcall(note.midi, {}))
test("name() of 20 raises",     not pcall(note.name, 20))
test("name() of 96 raises",     not pcall(note.name, 96))
test("name() of a fraction raises", not pcall(note.name, 60.5))

print("── note-block ticks ──")
eq("tick 0 is MIDI 34",  34, note.ticks(0))
eq("tick 24 is MIDI 58", 58, note.ticks(24))
eq("MIDI 34 is tick 0",  0,  note.ticks(34))
eq("MIDI 58 is tick 24", 24, note.ticks(58))
test("tick 25 raises",   not pcall(note.ticks, 25))
test("tick -1 raises",   not pcall(note.ticks, -1))
test("a string raises",  not pcall(note.ticks, "0"))

print("── play ──")
beeps = {}
note.play("a4", 0.25)
eq("one beep",              1,    #beeps)
near("at 440 Hz",           440,  beeps[1] and beeps[1].freq)
near("for the asked time",  0.25, beeps[1] and beeps[1].dur)

beeps = {}
note.play("a4", 600)
eq("a 600-second note still beeps once", 1, #beeps)
near("clamped to 5 seconds", 5, beeps[1] and beeps[1].dur)

beeps = {}
note.play("a4", -1)
eq("a negative duration beeps not at all", 0, #beeps)

beeps = {}
note.play(69, 0.1)
eq("a MIDI code plays too", 1, #beeps)

print("── `audio off` silences it ──")
package.loaded["kernel.audio"] = { isEnabled = function() return false end }
beeps = {}
note.play("a4", 0.25)
eq("no beep while audio is disabled", 0, #beeps)
package.loaded["kernel.audio"] = { isEnabled = function() return true end }
beeps = {}
note.play("a4", 0.25)
eq("and it comes back when re-enabled", 1, #beeps)

print("")
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
print("All tests passed.")
