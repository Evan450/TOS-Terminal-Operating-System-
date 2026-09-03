-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: log.lua splash boot-progress hook       ║
-- ║                                                            ║
-- ║  In "splash" verbosity the per-stage boot log is muted;    ║
-- ║  the muted INFO chatter instead drives a loading bar via a ║
-- ║  bootProgress callback. Verify INFO/WARN advance it,       ║
-- ║  DEBUG does not, a throwing callback can't break logging,  ║
-- ║  and the bar-fill math behaves.                            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_log_bootprogress.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local now = 0
package.loaded["computer"] = { uptime = function() return now end,
  freeMemory = function() return 1000000 end, totalMemory = function() return 2000000 end }
package.path = "tos/?.lua;" .. package.path
local log = require("kernel.log")

print("=== log boot-progress Tests ===")
print()

-- ── Callback fires for INFO and WARN, not DEBUG; carries level ─────
local hits = {}
log.init({ bootProgress = function(msg, lvl) hits[#hits + 1] = { msg, lvl } end,
  earlyPrint = nil, earlyMinLevel = 2 })   -- splash: minLevel WARN, info muted

log.debug("kernel", "spinning up debug")   -- below INFO: must NOT advance
log.info("kernel", "Initializing filesystem")
log.info("net", "Network ready")
log.warn("kernel", "low memory")           -- WARN >= INFO: advances too

eq("DEBUG did not advance the bar", false, hits[1] and hits[1][1] == "spinning up debug")
test("INFO advanced the bar", hits[1] and hits[1][1] == "Initializing filesystem")
eq("two INFO + one WARN advanced it", 3, #hits)
test("WARN message reached the bar", hits[3] and hits[3][1] == "low memory")
eq("INFO numeric level passed (1)", 1, hits[1] and hits[1][2])
eq("WARN numeric level passed (2, so the bar can colour it)", 2, hits[3] and hits[3][2])

-- ── detachEarlyPrint() also tears down the splash hook ─────────────
-- The splash bar/narration draw at FIXED screen rows; once login/shell owns the
-- screen, a later INFO log must NOT redraw them (the "splash reappears at login
-- and shutdown" bug). detachEarlyPrint clears the bootProgress hook too, not
-- just the early echo.
local beforeDetach = #hits
log.detachEarlyPrint()
log.info("kernel", "post-handoff message")
eq("no bootProgress calls after detachEarlyPrint", beforeDetach, #hits)

-- ── A throwing callback cannot break logging ───────────────────────
log.init({ bootProgress = function() error("boom") end, earlyMinLevel = 1 })
local okCall = pcall(log.info, "kernel", "still logging")
test("throwing bootProgress is swallowed (logging survives)", okCall)

-- ── No callback set: logging is unaffected (no error) ──────────────
log.init({ earlyMinLevel = 1 })
test("absent bootProgress is a no-op", pcall(log.info, "kernel", "ok"))

-- ── Bar-fill math (mirrors init.lua drawBar) ───────────────────────
local function fillFor(frac, barW)
  frac = math.max(0, math.min(1, frac))
  return math.floor(barW * frac + 0.5)
end
eq("0% -> empty", 0, fillFor(0, 40))
eq("100% -> full", 40, fillFor(1, 40))
eq("50% of 40 -> 20", 20, fillFor(0.5, 40))
eq("over-100% clamps to full", 40, fillFor(1.5, 40))
-- "Boot complete" snaps seen to EST -> full bar
local seen, EST = 30, 40
local label = "Boot complete! Free memory: 500KB"
if label:find("Boot complete", 1, true) then seen = EST end
eq("Boot complete snaps the bar to full", 1.0, seen / EST)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
