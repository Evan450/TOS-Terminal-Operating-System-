-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: boot verbosity behaves as labelled      ║
-- ║                                                            ║
-- ║  Each option must do what it says (the operator reported   ║
-- ║  suspecting e.g. "text" blank / "silent" showing text):    ║
-- ║    silent  → nothing on screen (only a FATAL/panic)        ║
-- ║    splash  → per-stage INFO muted (the bar narrates),      ║
-- ║              WARN+ still shown                              ║
-- ║    text    → per-stage INFO lines shown                    ║
-- ║    verbose → everything incl. DEBUG                        ║
-- ║  Drives the REAL kernel.log echo gate with the REAL        ║
-- ║  kernel.bootcfg threshold, so the mapping can't drift.     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_verbosity.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1000000 end, totalMemory = function() return 2000000 end }
package.path = "tos/?.lua;" .. package.path
local bootcfg = require("kernel.bootcfg")
local log = require("kernel.log")

print("=== boot verbosity Tests ===")
print()

-- ── Canonical threshold mapping (single source of truth) ───────────
eq("silent  -> FATAL-only (4)", 4, bootcfg.echoMinLevel("silent"))
eq("splash  -> WARN+ (2)",      2, bootcfg.echoMinLevel("splash"))
eq("text    -> INFO+ (1)",      1, bootcfg.echoMinLevel("text"))
eq("verbose -> DEBUG+ (0)",     0, bootcfg.echoMinLevel("verbose"))
eq("unknown -> text-equivalent (1)", 1, bootcfg.echoMinLevel("bogus"))

-- ── End-to-end: what actually ECHOES to the boot screen per mode ───
-- Init log with the real threshold + a capturing earlyPrint, emit one
-- message at each level, and record which levels reached the screen.
local function echoedLevels(verbosity)
  local seen = {}
  log.init({ earlyMinLevel = bootcfg.echoMinLevel(verbosity),
    earlyPrint = function(line) seen[#seen + 1] = line end })
  log.debug("t", "DBG"); log.info("t", "INF"); log.warn("t", "WRN")
  log.error("t", "ERR"); log.fatal("t", "FTL")
  local got = {}
  for _, l in ipairs(seen) do
    if l:find("DBG", 1, true) then got.debug = true end
    if l:find("INF", 1, true) then got.info  = true end
    if l:find("WRN", 1, true) then got.warn  = true end
    if l:find("ERR", 1, true) then got.error = true end
    if l:find("FTL", 1, true) then got.fatal = true end
  end
  return got
end

local s = echoedLevels("silent")
test("silent: INFO muted",  not s.info)
test("silent: WARN muted",  not s.warn)
test("silent: nothing but a FATAL", not s.info and not s.warn and not s.error and s.fatal)

local sp = echoedLevels("splash")
test("splash: per-stage INFO muted (the bar narrates)", not sp.info)
test("splash: WARN still shown", sp.warn)
test("splash: ERROR still shown", sp.error)

local tx = echoedLevels("text")
test("text: per-stage INFO lines shown", tx.info)
test("text: DEBUG still muted", not tx.debug)

local vb = echoedLevels("verbose")
test("verbose: INFO shown", vb.info)
test("verbose: DEBUG shown (the extra detail)", vb.debug)

-- ── The boot-chrome gate (kernel bootEcho): the cosmetic "Loading
--    kernel modules" / "Boot complete" lines that DON'T go through the
--    log must still respect the muter — shown only at INFO-and-louder. ──
local function chromeShows(verbosity) return bootcfg.echoMinLevel(verbosity) <= 1 end
test("chrome hidden on silent", not chromeShows("silent"))
test("chrome hidden on splash (bar shows instead)", not chromeShows("splash"))
test("chrome shown on text", chromeShows("text"))
test("chrome shown on verbose", chromeShows("verbose"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
