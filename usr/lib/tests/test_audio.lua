-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: beeps do not stall the machine                ║
-- ║                                                                ║
-- ║  AUDIT 5, "every beep stops the machine, and the gaps between   ║
-- ║  them busy-spin":                                               ║
-- ║   * gap() spun 50 ms without yielding: every other seat froze   ║
-- ║     for each gap, even inside a process that could have yielded.║
-- ║   * each tone pauses the machine (Ocelot's Machine.beep), and   ║
-- ║     chat() ran on every incoming message: a chat flood was a    ║
-- ║     system-wide stall. Patterns now have a cooldown.            ║
-- ║   * the "volume" is a duration multiplier and tones under 10 ms ║
-- ║     were dropped, so a low volume muted notify/tick/chat only.  ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.audio and kernel.process.               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_audio.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
local clock = 100
local beeps = {}
local spins = 0
package.loaded["computer"] = {
  -- Every uptime read outside a process advances the clock a hair, so a
  -- spin-wait terminates; `spins` counts how many reads a gap took.
  uptime = function() spins = spins + 1; clock = clock + 0.001; return clock end,
  beep = function(f, d) beeps[#beeps + 1] = { f = f, d = d } end,
  freeMemory = function() return 1e6 end,
}
package.loaded["kernel.event"] = { removeSource = function() end }
local proc = require("kernel.process")
local audio = require("kernel.audio")

print("=== kernel.audio ===")
print()

print("-- a low volume no longer mutes the short sounds --")
audio.setVolume(0.1)
beeps = {}; (audio._resetCooldown or function() end)()
audio.notify()
test("notify at volume 10% still sounds", #beeps == 1)
test("...at OpenComputers' own 50 ms floor", beeps[1] and beeps[1].d == 0.05)
audio.setVolume(1.0)

print()
print("-- a flood of the same sound is one sound --")
beeps = {}; (audio._resetCooldown or function() end)()
for _ = 1, 20 do audio.chat() end
test("twenty chat chimes inside a second play once (2 tones)", #beeps == 2)
clock = clock + (audio.COOLDOWN or 1) + 0.1
audio.chat()
test("...and the next burst plays again", #beeps == 4)
beeps = {}
audio.warning(); audio.error()
test("different sounds are not held back by each other", #beeps == 3)
beeps = {}
audio.critical(); audio.critical()
test("critical is never held back (6 tones)", #beeps == 6)

print()
print("-- inside a process the gaps yield instead of spinning --")
do
  beeps = {}; (audio._resetCooldown or function() end)()
  local keys, finished = {}, false
  local pid = proc.spawn("beeper", function()
    while true do
      local a, b = coroutine.yield()
      if a == "go" then audio.warning(); finished = true
      elseif a == "key_down" then keys[#keys + 1] = b end
    end
  end)
  proc.tick(nil)
  proc.setForeground(pid, nil, { kernel = true })
  proc.signalKernel(pid, "go")
  proc.tick(nil)
  test("the first tone played and the gap handed control back", #beeps == 1 and not finished)
  proc.tick(table.pack("key_down", "typed-during-the-beep"))
  clock = clock + 0.1
  proc.tick(nil)
  test("after the gap the second tone plays", #beeps == 2 and finished)
  proc.tick(nil)
  test("a key typed during the gap is not lost", keys[1] == "typed-during-the-beep")
end

print()
print("-- outside a process there is nothing to yield to --")
beeps = {}; (audio._resetCooldown or function() end)(); spins = 0
audio.warning()
test("the gap still separates the two tones (and ends)", #beeps == 2 and spins > 1)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
