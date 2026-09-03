-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: splash screen ownership + RAM reporting ║
-- ║                                                            ║
-- ║  Play-test round (2026-07-24) found the splash loading    ║
-- ║  screen visibly corrupted — a ghost second progress bar   ║
-- ║  with self-repair / Safe Mode text overlapping the        ║
-- ║  narration column. Cause: on a splash boot the SAME       ║
-- ║  message went to two incompatible screen owners — the     ║
-- ║  free-scrolling earlyPrint AND the fixed-row loading bar. ║
-- ║                                                            ║
-- ║  Also pins the Boot Settings RAM report, which used to    ║
-- ║  say "plenty" (a word about the override, not about the   ║
-- ║  hardware) and now names the sticks actually installed.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_boot_screen_and_ram.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 1000000 end,
  totalMemory = function() return 2097152 end,
}
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- ============================================================
-- 1. Splash: the loading bar is the ONLY screen owner
-- ============================================================
print("\n-- splash screen ownership --")

do
  local log = require("kernel.log")
  local echoed, barred = {}, {}

  -- A splash boot: muter at WARN (2), and BOTH sinks wired, exactly as
  -- /init.lua wires them when verbosity == "splash".
  log.init({
    earlyPrint    = function(text) echoed[#echoed + 1] = text end,
    bootProgress  = function(msg, lvl) barred[#barred + 1] = { msg, lvl } end,
    earlyMinLevel = 2,
  })

  log.warn("kernel", "Startup services skipped (boot profile)")
  log.warn("repair", "Self-repair: 0 fixed, 0 warning(s)")
  log.error("kernel", "something broke")

  -- The bug: each of these ALSO scrolled the screen via earlyPrint, dragging
  -- the fixed-row bar out from under itself. Safe Mode emits one such warning
  -- per disabled subsystem, so it corrupted the splash every time.
  eq("splash: warnings do NOT go to the scrolling earlyPrint", 0, #echoed)
  eq("splash: all three still reach the loading bar", 3, #barred)
  test("splash: the bar receives the message verbatim",
    barred[2] and barred[2][1] == "Self-repair: 0 fixed, 0 warning(s)")
  eq("splash: WARN level reaches the bar so it can colour it", 2,
    barred[1] and barred[1][2])
  eq("splash: ERROR level is distinguishable", 3, barred[3] and barred[3][2])
end

do
  -- Without a bar (text/verbose boot) the early echo is unchanged — this is
  -- the path that prints the familiar boot log, and it must not regress.
  local log = require("kernel.log")
  local echoed = {}
  log.init({
    earlyPrint    = function(text) echoed[#echoed + 1] = text end,
    bootProgress  = nil,
    earlyMinLevel = 1,
  })
  log.info("kernel", "Mounting filesystems")
  log.warn("kernel", "heads up")
  eq("text boot: early echo still prints (no bar to defer to)", 2, #echoed)
  test("text boot: echo carries the level prefix",
    echoed[1] and echoed[1]:find("[INF]", 1, true) ~= nil)
end

-- ============================================================
-- 2. RAM reporting names the real sticks
-- ============================================================
print("\n-- RAM tier reporting --")

do
  package.loaded["component"] = {
    list = function() return function() return nil end end,
  }
  local hal = require("kernel.hal")

  -- Stock OpenComputers stick sizes.
  eq("192K stick is T1",    "T1",   hal.stickTier(192))
  eq("256K stick is T1.5",  "T1.5", hal.stickTier(256))
  eq("384K stick is T2",    "T2",   hal.stickTier(384))
  eq("512K stick is T2.5",  "T2.5", hal.stickTier(512))
  eq("768K stick is T3",    "T3",   hal.stickTier(768))
  eq("1024K stick is T3.5", "T3.5", hal.stickTier(1024))
  -- There is no Tier 4 memory in standard OC — never extrapolate past T3.5.
  eq("2048K is NOT a stick tier (no T4 exists)", nil, hal.stickTier(2048))
  eq("a non-stock size yields no tier", nil, hal.stickTier(900))

  -- Per-stick summaries. Matching sticks collapse to a count...
  eq("two T3.5 sticks", "2x T3.5", hal.ramSummary({ 1024, 1024 }))
  eq("one stick names the tier alone", "T3.5", hal.ramSummary({ 1024 }))
  eq("four T2 sticks", "4x T2", hal.ramSummary({ 384, 384, 384, 384 }))

  -- ...and MIXED tiers are named separately, largest first. This is the
  -- reported bug: 1024K + 512K totals 1536K over two sticks, so any
  -- total-based guess divides to 768K and confidently reports "T3" —
  -- a tier the machine does not contain.
  eq("T3.5 + T2.5 is not 'T3'", "T3.5 + T2.5", hal.ramSummary({ 1024, 512 }))
  eq("mixed sticks sort largest first", "T3.5 + T2.5",
    hal.ramSummary({ 512, 1024 }))
  eq("repeats within a mix still collapse", "2x T3.5 + T2.5",
    hal.ramSummary({ 1024, 512, 1024 }))
  eq("three distinct tiers", "T3.5 + T3 + T1", hal.ramSummary({ 768, 192, 1024 }))
  eq("non-stock sticks report raw capacity", "2x 900K",
    hal.ramSummary({ 900, 900 }))

  -- Without per-stick data, report honestly instead of guessing a tier:
  -- 1536K/2 lands exactly on T3, which is how the wrong answer looked right.
  eq("no stick data, many sticks: capacity, not a guessed tier",
    "2 sticks, 1536K", hal.ramSummary(nil, 1536, 2))
  eq("no stick data, ONE stick is unambiguous", "T3.5",
    hal.ramSummary(nil, 1024, 1))
  eq("no stick data and no count", "2048K", hal.ramSummary(nil, 2048, 0))
  eq("no memory at all is not a crash", "?", hal.ramSummary(nil, 0, 0))

  -- ramSticks reads capacities out of getDeviceInfo, in bytes or KB.
  local sticks = hal.ramSticks({
    ["a"] = { class = "memory", capacity = "1048576" },   -- 1024K, bytes
    ["b"] = { class = "memory", capacity = "524288"  },   -- 512K,  bytes
    ["c"] = { class = "processor", capacity = "999" },    -- ignored
  })
  test("ramSticks found both sticks", sticks and #sticks == 2)
  eq("ramSticks converts bytes to KB, largest first", 1024, sticks and sticks[1])
  eq("...and the smaller one", 512, sticks and sticks[2])
  eq("the operator's mixed box summarises correctly", "T3.5 + T2.5",
    hal.ramSummary(sticks))
  eq("no memory entries yields nil", nil,
    hal.ramSticks({ ["a"] = { class = "processor" } }))

  -- ── The unit is DETERMINED, not guessed ────────────────────────────
  -- #FIX (real Minecraft, 2026-08-11). The old code decided whether a
  -- capacity was bytes or kilobytes with `>= 4096`, and a real machine
  -- printed these two lines three apart in its own boot log:
  --     CPU T3 | GPU T2 | RAM 4K | 11 components
  --     Boot complete! Free memory: 1300KB
  -- The sticks now have to reconcile with computer.totalMemory (stubbed
  -- at 2048K above), and a set that reconciles with NEITHER reading is
  -- refused rather than reported.
  do
    -- Capacities in KILOBYTES that add up correctly: left alone.
    local kb = hal.ramSticks({
      ["a"] = { class = "memory", capacity = "1024" },
      ["b"] = { class = "memory", capacity = "1024" },
    })
    test("KB capacities are recognised", kb and #kb == 2)
    eq("...and not divided again", 1024, kb and kb[1])
    eq("...so the summary is right", "2x T3.5", hal.ramSummary(kb))

    -- The in-game shape: one entry that reconciles with nothing. Under
    -- the old heuristic 4096 crossed the threshold and became "4K".
    local bogus = hal.ramSticks({ ["a"] = { class = "memory", capacity = "4096" } })
    eq("a capacity that matches no reading is refused", nil, bogus)
    -- And the display falls back to the machine's real total instead of
    -- inventing a tier. 2097152 bytes stubbed above.
    eq("the summary reports the honest total", "2048K", hal.ramSummary(bogus))
    test("...which is emphatically not '4K'", hal.ramSummary(bogus) ~= "4K")
  end

  -- sysinfo delegates to the SAME implementation (one tier table, not two).
  local sysinfo = require("kernel.sysinfo")
  eq("sysinfo.stickTier delegates", "T2.5", sysinfo.stickTier(512))
  eq("sysinfo.ramSummary delegates", "T3.5 + T2.5",
    sysinfo.ramSummary(1536, 2, { 1024, 512 }))
end

-- ============================================================
-- 3. Boot Settings surfaces it on the RAM row
-- ============================================================
print("\n-- Boot Settings RAM row --")

do
  local bootsettings = require("kernel.bootsettings")

  local function rowFor(fields, key)
    for _, f in ipairs(fields) do if f.key == key then return f end end
  end

  -- Injected probe: the play-test machine (two matching T3.5 sticks).
  local label = bootsettings.ramLabel(function()
    return { totalKB = 2048, modules = 2, sticks = { 1024, 1024 } }
  end)
  eq("ramLabel names the installed sticks", "2x T3.5", label)

  -- And the MIXED machine that reported itself as "tier 3".
  local mixed = bootsettings.ramLabel(function()
    return { totalKB = 1536, modules = 2, sticks = { 1024, 512 } }
  end)
  eq("ramLabel names mixed tiers separately", "T3.5 + T2.5", mixed)

  local row = rowFor(bootsettings.fields({}, label), "ramGate")
  test("RAM row label carries the hardware", row and row.label == "RAM for extras [2x T3.5]")
  -- Labels are clipped to 31 columns by the runner; keep it inside that.
  test("RAM row label fits the settings column", row and #row.label <= 31)
  local mixedRow = rowFor(bootsettings.fields({}, mixed), "ramGate")
  test("the mixed label also fits the column", mixedRow and #mixedRow.label <= 31)

  -- The values now describe what the override DOES; "plenty" is gone.
  eq("auto value unchanged", "auto (measure)", row and row.value)
  local forced = rowFor(bootsettings.fields({ ramGate = true }, label), "ramGate")
  eq("forced-on reads plainly", "always load", forced and forced.value)
  test("the word 'plenty' is gone", forced and not forced.value:find("plenty"))
  local off = rowFor(bootsettings.fields({ ramGate = false }, label), "ramGate")
  eq("forced-off reads plainly", "never load", off and off.value)

  -- No hardware answer (off-box, or a probe failure) must not break the model.
  local generic = rowFor(bootsettings.fields({}), "ramGate")
  test("without a probe the row keeps generic wording",
    generic and generic.label == "RAM for extras (override)")
  eq("a failing probe yields no label", nil,
    bootsettings.ramLabel(function() error("no hardware") end))
end

-- ============================================================
print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
end
print("*** ALL TESTS PASSED ***")
return true
