-- ╔═══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `optimize power` conservation profiles        ║
-- ║                                                                 ║
-- ║  Operator request: expand `optimize` past swap — "e.g. optimize  ║
-- ║  power which optimizes TOS for power conservation".              ║
-- ║                                                                  ║
-- ║  The hazard in a feature like this is that it is trivially easy   ║
-- ║  to fake: TOS already carried `powerSave` and `refreshRate` in    ║
-- ║  /etc/tos.cfg, both documented as doing this, both read by        ║
-- ║  literally nothing. So this test pins the WIRING as much as the    ║
-- ║  policy — the globals a profile publishes, the loop that reads     ║
-- ║  them, and the boot that applies the saved one.                    ║
-- ║                                                                     ║
-- ║  Energy facts the profiles are built on are verified against        ║
-- ║  OpenComputers' own shipped config (power.cost: sleepFactor 0.1,   ║
-- ║  screen billed per non-blank cell, gpuSet per changed cell), not   ║
-- ║  from memory. See the note atop tos/kernel/power.lua.              ║
-- ╚════════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_power_profile.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local uptimeNow = 0
package.loaded["computer"] = {
  uptime = function() return uptimeNow end,
  energy = function() return 300 end,
  maxEnergy = function() return 500 end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_power_profile.lua"
local base = here:gsub("[^/\\]*$", "")
local function findFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "r")
    if f then f:close(); return p end
  end
end
local function loadMod(rel)
  local p = findFile(rel)
  if p then local chunk = loadfile(p); if chunk then return chunk() end end
end

local power = loadMod("tos/kernel/power.lua")
if not power then
  print("FAIL: could not load kernel/power.lua")
  print("*** TESTS FAILED ***"); os.exit(1)
end

print("=== power profile Tests ===\n")

_G._TOS = {}

-- ── Profile table sanity ────────────────────────────────────────────
do
  test("three profiles exist", power.PROFILES.off and power.PROFILES.balanced
    and power.PROFILES.save)
  local off, bal, save = power.PROFILES.off, power.PROFILES.balanced, power.PROFILES.save
  -- 'off' must be exactly the behaviour TOS had before this existed, or
  -- an operator who dislikes the feature has no way back to it.
  eq("off: 1s idle cadence (the old constant)", 1, off.idleSec)
  eq("off: never blanks", 0, off.blankSec)
  test("save conserves more than balanced, which conserves more than off",
    save.idleSec >= bal.idleSec and bal.idleSec >= off.idleSec
    and save.blankSec > 0 and save.blankSec < bal.blankSec)
  -- A blank timeout short enough to fire while someone is reading the
  -- screen is a bug, not a saving.
  test("even the aggressive profile waits a minute+", save.blankSec >= 60)
end

-- ── normalizeProfile: what an operator might actually type ──────────
do
  eq("save", "save", power.normalizeProfile("save"))
  eq("SAVE (case)", "save", power.normalizeProfile("SAVE"))
  eq("saver -> save", "save", power.normalizeProfile("saver"))
  eq("conserve -> save", "save", power.normalizeProfile("conserve"))
  eq("none -> off", "off", power.normalizeProfile("none"))
  eq("performance -> off", "off", power.normalizeProfile("performance"))
  eq("default -> balanced", "balanced", power.normalizeProfile("default"))
  eq("nonsense -> nil", nil, power.normalizeProfile("turbo"))
  eq("nil -> nil", nil, power.normalizeProfile(nil))
end

-- ── applyProfile publishes the globals the SHELL LOOP reads ─────────
-- This is the seam: kernel.power writes _G._TOS.powerIdleSec /
-- screenBlankSec, and shell/panels/events.lua reads them back through
-- this module. A rename on either side is what this catches.
do
  eq("applyProfile returns the key", "save", power.applyProfile("save"))
  eq("published idle cadence", power.PROFILES.save.idleSec, _G._TOS.powerIdleSec)
  eq("published blank timeout", power.PROFILES.save.blankSec, _G._TOS.screenBlankSec)
  eq("profile() reports it", "save", power.profile())
  eq("idleSeconds reads it back", power.PROFILES.save.idleSec, power.idleSeconds())
  eq("blankSeconds reads it back", power.PROFILES.save.blankSec, power.blankSeconds())

  local ok, err = power.applyProfile("turbo")
  eq("unknown profile refused", nil, ok)
  test("...with a reason", type(err) == "string" and err:find("turbo", 1, true))
  eq("...and the old profile survives", "save", power.profile())
end

-- ── Fallbacks when the power module never loaded ───────────────────
-- A low-memory boot skips kernel.power on purpose. Nothing may then
-- behave WORSE than the old hardcoded constants.
do
  _G._TOS = {}
  eq("no globals -> 1s idle (the old constant)", 1, power.idleSeconds())
  eq("no globals -> no blanking", 0, power.blankSeconds())
  test("no globals -> never blanks", power.shouldBlank(99999, 0, nil) == false)
end

-- ── An unapplied profile reports as `off`, not as its default ───────
-- Loading the module is not applying it. A `show` that named a profile
-- the machine is not running would be the same class of claim as the
-- dead `powerSave` key this feature replaced.
do
  local fresh = loadMod("tos/kernel/power.lua")
  _G._TOS = {}
  eq("a freshly loaded module reports 'off'", "off", fresh.profile())
  eq("...matching the knobs it is actually running", 0, fresh.blankSeconds())
end

-- ── shouldBlank: the decision the event loop makes every tick ──────
do
  power.applyProfile("save")
  local bs = power.blankSeconds()
  test("not idle long enough -> no", power.shouldBlank(100, 100 - (bs - 1), nil) == false)
  test("idle exactly the timeout -> yes", power.shouldBlank(100, 100 - bs, nil) == true)
  test("idle well past it -> yes", power.shouldBlank(bs * 3, 0, nil) == true)
  test("already blanked -> no (edge-triggered, not level)",
    power.shouldBlank(bs * 3, 0, true) == false)
  power.applyProfile("off")
  test("profile off -> never, however idle", power.shouldBlank(99999, 0, nil) == false)
end

-- ── Loop-shaped sequencing: blank once, wake on input, re-blank ────
-- The event loop's real order of operations, driven against the real
-- function: idle ticks call shouldBlank; input clears the flag and
-- stamps the clock. Anything that blanks twice, or fails to re-blank
-- after the operator walks away again, shows up here.
do
  power.applyProfile("save")
  local bs = power.blankSeconds()
  local state = { blanked = nil, lastInput = 0 }
  local blanks = 0
  local function tick(now, input)
    if input then
      state.lastInput = now
      if state.blanked then state.blanked = nil end
      return
    end
    if power.shouldBlank(now, state.lastInput, state.blanked) then
      state.blanked = true; blanks = blanks + 1
    end
  end
  for t = 1, bs - 1 do tick(t, false) end
  eq("no blank before the timeout", 0, blanks)
  tick(bs, false)
  eq("blanks once at the timeout", 1, blanks)
  for t = bs + 1, bs + 20 do tick(t, false) end
  eq("stays blanked without re-blanking", 1, blanks)
  tick(bs + 21, true)
  test("input wakes it", state.blanked == nil)
  for t = bs + 22, bs + 21 + bs - 1 do tick(t, false) end
  eq("no immediate re-blank after waking", 1, blanks)
  tick(bs + 21 + bs, false)
  eq("re-blanks after another full idle period", 2, blanks)
end

-- ── setKnob: hand-tuning, with the guards that keep it sane ────────
do
  power.applyProfile("balanced")
  eq("blank 300 accepted", 300, power.setKnob("blank", 300))
  eq("...and published", 300, _G._TOS.screenBlankSec)
  eq("blank 0 = off", 0, power.setKnob("blank", 0))
  eq("...and published", 0, _G._TOS.screenBlankSec)
  eq("blank 3s refused (would blank while reading)", nil, power.setKnob("blank", 3))
  eq("idle 5 accepted", 5, power.setKnob("idle", 5))
  eq("idle 0 refused (would spin)", nil, power.setKnob("idle", 0))
  eq("negative refused", nil, power.setKnob("blank", -1))
  eq("non-numeric refused", nil, power.setKnob("blank", "soon"))
  eq("unknown knob refused", nil, power.setKnob("brightness", 5))
end

-- ── WIRING: the consumers really are wired to this module ──────────
--! Source assertions, and named as such: they prove the call sites exist,
--! not that they behave. The behaviour above is worthless if the loop
--! quietly went back to a hardcoded 1, and that is exactly the kind of
--! regression a pure-module test cannot see.
do
  local ev = findFile("tos/shell/panels/events.lua")
  local src = ev and io.open(ev):read("a") or ""
  test("[wiring] the shell loop asks power.shouldBlank",
    src:find("shouldBlank(", 1, true) ~= nil)
  test("[wiring] the idle cadence comes from power.idleSeconds",
    src:find("idleSeconds()", 1, true) ~= nil)
  test("[wiring] no hardcoded 1s status cadence is left",
    src:find("(S._lastStatusT or 0) >= 1", 1, true) == nil)

  local ini = findFile("tos/kernel/init.lua")
  local isrc = ini and io.open(ini):read("a") or ""
  test("[wiring] the kernel applies the saved profile at boot",
    isrc:find("applyProfile", 1, true) ~= nil
    and isrc:find("powerProfile", 1, true) ~= nil)

  --! The two dead knobs this replaced must not come back. They claimed
  --! to do this job and were read by nothing, which is the failure mode
  --! this whole feature is trying not to repeat.
  local cfg = findFile("tos/kernel/config.lua")
  local csrc = cfg and io.open(cfg):read("a") or ""
  test("[wiring] config declares powerProfile",
    csrc:find("powerProfile", 1, true) ~= nil)
  local function declaresKey(s, key)
    return s:find("\n%s*" .. key .. "%s*=") ~= nil
  end
  test("[wiring] the dead powerSave key is gone", not declaresKey(csrc, "powerSave"))
  test("[wiring] the dead refreshRate key is gone", not declaresKey(csrc, "refreshRate"))
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
