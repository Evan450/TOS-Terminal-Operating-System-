-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: rbmk.core — driver binding + SAFETY RULES  ║
-- ║                                                              ║
-- ║  The console BINDING can only be verified in-world (HBM's OC ║
-- ║  method names are Plan.md open question #1). The SAFETY      ║
-- ║  LOGIC cannot wait for that — it is pure arithmetic, and     ║
-- ║  it's the half that decides whether a reactor gets shut      ║
-- ║  down. So it is proved here, exhaustively:                   ║
-- ║                                                              ║
-- ║   • limits escalate ok -> warn -> scram at the right edges;  ║
-- ║   • a MISSING or STALE reading is a SCRAM, never an "ok"     ║
-- ║     (supervising blind is not supervising);                  ║
-- ║   • a typo'd config falls back to the DEFAULT limit, never   ║
-- ║     to "no limit";                                           ║
-- ║   • binding refuses to declare itself usable without a       ║
-- ║     temperature reading or any SCRAM path;                   ║
-- ║   • telemetry frames are read-only — a frame carrying a      ║
-- ║     control field is REFUSED, so the unauthenticated         ║
-- ║     broadcast channel can never become reactor control.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua rbmk/test_rbmk.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- Normally run from the TOS-Extras root; `base` lets a direct
-- `lua rbmk/test_rbmk.lua` from elsewhere still find the skeleton.
local base = ((arg and arg[0]) or "rbmk/test_rbmk.lua"):gsub("[^/\\]*$", "")

package.path = "rbmk/controller-skeleton/usr/lib/?.lua;"
  .. "rbmk/controller-skeleton/usr/lib/?/init.lua;"
  .. base .. "controller-skeleton/usr/lib/?.lua;"
  .. base .. "controller-skeleton/usr/lib/?/init.lua;" .. package.path
local core = require("rbmk.core")

print("=== rbmk.core Tests ===")
print()

-- ── Driver binding ─────────────────────────────────────────────────
do
  local profile = core.PROFILES["hbm-generic"]
  test("a generic profile ships", type(profile) == "table")

  -- A console offering the first-choice names binds everything.
  local b = core.bind(profile, {
    "getTemp", "getFlux", "getRodDepth", "getSteam", "getWater",
    "getFuel", "setAZ5",
  })
  eq("temp bound", "getTemp", b.bound.temp)
  eq("scram bound", "setAZ5", b.bound.scram)
  eq("nothing missing", 0, #b.missing)

  -- Second-choice names are accepted (that's the point of candidates).
  local b2 = core.bind(profile, { "getTemperature", "scram" })
  eq("falls through to an alternate name", "getTemperature", b2.bound.temp)
  eq("alternate scram name too", "scram", b2.bound.scram)
  test("unbound readings are reported", #b2.missing > 0)

  -- Set-form method lists (component.methods returns a set) work too.
  local b3 = core.bind(profile, { getTemp = true, setAZ5 = true })
  eq("set-form method lists bind", "getTemp", b3.bound.temp)

  -- Bulk accessor detection.
  local b4 = core.bind(profile, { "getInfo", "getTemp", "setAZ5" })
  eq("a bulk accessor is detected", "getInfo", b4.bulk)

  local b5 = core.bind(profile, {})
  eq("an empty console binds nothing", nil, b5.bound.temp)
end

-- ── Binding usability: refuse to supervise blind ───────────────────
do
  local profile = core.PROFILES["hbm-generic"]
  local full = core.bind(profile, { "getTemp", "setAZ5" })
  eq("temp + scram is usable", true, (core.bindingUsable(full, false)))

  local noTemp = core.bind(profile, { "setAZ5" })
  local ok, why = core.bindingUsable(noTemp, false)
  eq("no temperature -> unusable", false, ok)
  test("...and says why", type(why) == "string" and why:find("temperature"))

  local noScram = core.bind(profile, { "getTemp" })
  local ok2, why2 = core.bindingUsable(noScram, false)
  eq("no SCRAM path -> unusable", false, ok2)
  test("...and says why", type(why2) == "string" and why2:find("SCRAM"))

  -- The redstone AZ-5 backup satisfies the SCRAM requirement on its own.
  eq("a redstone AZ-5 line counts as a SCRAM path", true,
    (core.bindingUsable(noScram, true)))

  -- A bulk accessor can stand in for the temperature getter.
  local bulkOnly = core.bind(core.PROFILES["hbm-generic"], { "getInfo", "setAZ5" })
  eq("a bulk accessor satisfies the temperature floor", true,
    (core.bindingUsable(bulkOnly, false)))
end

-- ── Normalization: missing is NOT zero ─────────────────────────────
do
  local n = core.normalize({ temp = "850", flux = 42, junk = "ignored" })
  eq("numeric strings coerce", 850, n.temp)
  eq("numbers pass through", 42, n.flux)
  eq("unknown fields are dropped", nil, n.junk)
  eq("an absent reading stays NIL, not 0", nil, n.water)
  local n2 = core.normalize({ temp = "not a number" })
  eq("unparseable readings become nil (not 0)", nil, n2.temp)
  local n3 = core.normalize(nil)
  eq("a nil reading table is safe", nil, n3.temp)
end

-- ── Safety evaluation ──────────────────────────────────────────────
do
  local lim = core.DEFAULT_LIMITS

  local level = core.evaluate({ temp = 100, flux = 10, water = 90 }, lim, 0)
  eq("a cold, healthy reactor is ok", "ok", level)

  level = core.evaluate({ temp = lim.tempWarn, water = 90 }, lim, 0)
  eq("temperature at the warn limit warns", "warn", level)

  level = core.evaluate({ temp = lim.tempWarn - 1, water = 90 }, lim, 0)
  eq("just below the warn limit is ok", "ok", level)

  local reasons
  level, reasons = core.evaluate({ temp = lim.tempScram, water = 90 }, lim, 0)
  eq("temperature at the scram limit SCRAMs", "scram", level)
  test("...and gives a reason", #reasons > 0 and reasons[1]:find("scram limit"))

  level = core.evaluate({ temp = 100, flux = lim.fluxScram, water = 90 }, lim, 0)
  eq("flux over its limit SCRAMs", "scram", level)

  level = core.evaluate({ temp = 100, flux = lim.fluxWarn, water = 90 }, lim, 0)
  eq("flux at the warn limit warns", "warn", level)

  level = core.evaluate({ temp = 100, water = lim.waterMin - 1 }, lim, 0)
  eq("losing coolant SCRAMs", "scram", level)

  -- SCRAM outranks warn when both fire.
  level, reasons = core.evaluate(
    { temp = lim.tempScram, flux = lim.fluxWarn, water = 90 }, lim, 0)
  eq("scram outranks warn", "scram", level)
  test("both conditions are reported", #reasons >= 2)
end

-- ── The failure modes that matter most ─────────────────────────────
do
  local lim = core.DEFAULT_LIMITS

  -- A reading we could not take is NOT a cold reactor.
  local level, reasons = core.evaluate({ temp = nil, water = 90 }, lim, 0)
  eq("a MISSING temperature SCRAMs", "scram", level)
  test("...and says so plainly",
    #reasons > 0 and reasons[1]:find("no temperature"))

  -- Losing the console mid-run is exactly when you want the rods in.
  level, reasons = core.evaluate({ temp = 100, water = 90 }, lim, lim.staleAfter + 1)
  eq("STALE telemetry SCRAMs", "scram", level)
  test("...and names staleness", #reasons > 0 and reasons[1]:find("stale"))

  level = core.evaluate({ temp = 100, water = 90 }, lim, lim.staleAfter - 0.1)
  eq("a fresh-enough reading does not scram", "ok", level)

  -- Optional readings simply don't participate.
  level = core.evaluate({ temp = 100 }, lim, 0)
  eq("absent optional readings don't scram", "ok", level)
end

-- ── Limit merging: a typo must never disable a limit ───────────────
do
  local merged = core.mergeLimits({ tempScram = 1200 })
  eq("an operator value is taken", 1200, merged.tempScram)
  eq("unspecified limits keep their default",
    core.DEFAULT_LIMITS.tempWarn, merged.tempWarn)

  local bad = core.mergeLimits({ tempScram = "hot", fluxScram = -5, waterMin = 0 })
  eq("a non-numeric limit falls back to the DEFAULT",
    core.DEFAULT_LIMITS.tempScram, bad.tempScram)
  eq("a negative limit falls back to the DEFAULT",
    core.DEFAULT_LIMITS.fluxScram, bad.fluxScram)
  eq("a zero limit falls back to the DEFAULT",
    core.DEFAULT_LIMITS.waterMin, bad.waterMin)

  local junk = core.mergeLimits({ notALimit = 5 })
  eq("unknown keys are ignored", nil, junk.notALimit)
  eq("a nil config yields the defaults",
    core.DEFAULT_LIMITS.tempScram, core.mergeLimits(nil).tempScram)

  -- The merged limits must still drive a scram correctly.
  eq("a raised limit actually applies", "ok",
    (core.evaluate({ temp = 1100, water = 90 }, core.mergeLimits({ tempScram = 1200, tempWarn = 1150 }), 0)))
end

-- ── Telemetry frames are READ-ONLY ─────────────────────────────────
do
  local f = core.frame({ temp = 500, flux = 100 }, "ok", 7, 1234, "rbmk-1")
  eq("frames carry the magic", "RBMK", f.magic)
  eq("frames carry a sequence", 7, f.seq)
  eq("frames carry the level", "ok", f.level)
  eq("frames carry readings", 500, f.temp)
  eq("frames name the reactor", "rbmk-1", f.name)
  eq("a good frame validates", true, (core.validateFrame(f)))

  eq("a non-table is refused", false, (core.validateFrame("nope")))
  eq("wrong magic is refused", false, (core.validateFrame({ magic = "XXXX", v = 1, seq = 1 })))
  eq("a future version is refused", false,
    (core.validateFrame({ magic = "RBMK", v = 99, seq = 1 })))
  eq("a frame with no sequence is refused", false,
    (core.validateFrame({ magic = "RBMK", v = 1 })))

  -- THE important one: a display must never accept anything that looks
  -- like a command, or the open broadcast channel becomes rod control.
  for _, field in ipairs({ "cmd", "command", "setRod", "rod", "scram", "exec" }) do
    local hostile = core.frame({ temp = 1 }, "ok", 1, 1)
    hostile[field] = "do the thing"
    local ok, why = core.validateFrame(hostile)
    test("a frame carrying '" .. field .. "' is REFUSED", ok == false)
    test("...and explains (" .. field .. ")",
      type(why) == "string" and why:find("control field"))
  end
end

-- ── Display-side staleness ─────────────────────────────────────────
do
  eq("never having received a frame is stale", true, core.frameStale(nil, nil, 100, 5))
  eq("a recent frame is fresh", false, core.frameStale(1, 98, 100, 5))
  eq("an old frame is stale", true, core.frameStale(1, 90, 100, 5))
end

-- ── The daemon keeps its state to itself ──────────────
-- rbmk-controld holds its whole running state in file locals — _seq,
-- _scrammed, _lastGood, _binding, _cfg, _limits. _lastLevel was written
-- without a `local`, so it was a plain GLOBAL, landing in whatever
-- environment the service happened to be loaded under. That is the only
-- piece of reactor state that escaped the module, and the one the warn-
-- once-per-transition rule depends on: an environment that refuses new
-- globals (or shares one between services) turns a 1 Hz log flood back on,
-- or worse, lets another service's value decide whether this reactor's
-- warning is printed.
--
-- Nothing in the SOURCE distinguishes a global from a local read, so this
-- asks the compiler. luac ships with the same Lua install this suite
-- already needs.
do
  local path = "rbmk/controller-skeleton/usr/lib/rbmk-controld.lua"
  local probe = io.open(path, "r")
  if not probe then
    path = base .. "controller-skeleton/usr/lib/rbmk-controld.lua"
    probe = io.open(path, "r")
  end
  if not probe then
    test("could find rbmk-controld.lua to inspect", false)
  else
    probe:close()
    local pipe = io.popen('luac -p -l -l "' .. path .. '" 2>&1', "r")
    local dump = pipe and pipe:read("*a") or ""
    local okPipe = pipe and pipe:close()
    if not okPipe or dump:find("luac:", 1, true) then
      print("  (skipped: luac not usable here — cannot read _ENV accesses)")
    else
      -- Every name the daemon touches through _ENV, with the Lua standard
      -- library filtered out.
      local STD = {}
      for n in ([[assert collectgarbage coroutine debug error getmetatable io
        ipairs load math next os package pairs pcall print rawequal rawget
        rawlen rawset require select setmetatable string table tonumber
        tostring type xpcall utf8 _G _VERSION]]):gmatch("%S+") do STD[n] = true end
      local leaked, seen = {}, {}
      for name in dump:gmatch('_ENV%s+"([A-Za-z_][A-Za-z0-9_]*)"') do
        if not STD[name] and not seen[name] then
          seen[name] = true; leaked[#leaked + 1] = name
        end
      end
      test("the daemon touches no undeclared global ("
        .. (#leaked == 0 and "none" or table.concat(leaked, ", ")) .. ")", #leaked == 0)
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
