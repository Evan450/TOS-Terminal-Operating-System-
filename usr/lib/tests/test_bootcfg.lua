-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: bootcfg (boot spectrum config)      ║
-- ║  - fail-safe load (missing/corrupt/oversized)          ║
-- ║  - normalize (profile/verbosity/advanced/cpuTier)      ║
-- ║  - verbosity muter + feature resolution (wants/shows)  ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bootcfg.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_bootcfg.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize   -- bootcfg.load require()s it
local bootcfg = loadMod("bootcfg.lua")
if not bootcfg or not serialize then
  print("FAIL: could not load bootcfg/serialize")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- fs mock: holds one file's bytes.
local function fsWith(bytes)
  return { exists = function(p) return bytes ~= nil and p == bootcfg.PATH end,
           readFile = function() return bytes end }
end

print("=== bootcfg Tests ===")
print()

-- ── Fail-safe: no file => normal defaults ──────────────────────────
local d = bootcfg.load(fsWith(nil))
test("no file -> profile normal", "normal", d.profile)
test("no file -> verbosity nil (profile default)", nil, d.verbosity)
test("no file -> showConfig true", true, d.showConfig)
test("no file -> advanced empty", 0, (function() local n=0 for _ in pairs(d.advanced) do n=n+1 end return n end)())

-- ── Valid file parses + filters ────────────────────────────────────
local cfgBytes = serialize.encode({
  profile = "full", verbosity = "verbose", showConfig = false,
  advanced = { net = false, audio = true, bogus = true, theme = "yes" },
  cpuTier = 2,
})
local v = bootcfg.load(fsWith(cfgBytes))
test("parsed profile", "full", v.profile)
test("parsed verbosity", "verbose", v.verbosity)
test("parsed showConfig", false, v.showConfig)
test("advanced net override kept", false, v.advanced.net)
test("advanced audio override kept", true, v.advanced.audio)
test("unknown advanced key dropped", nil, v.advanced.bogus)
test("non-boolean advanced value dropped", nil, v.advanced.theme)
test("parsed cpuTier", 2, v.cpuTier)

-- ── Normalize guards ───────────────────────────────────────────────
test("bad profile -> normal", "normal", bootcfg.load(fsWith(serialize.encode({ profile = "hyperspeed" }))).profile)
test("bad verbosity -> nil", nil, bootcfg.load(fsWith(serialize.encode({ verbosity = "screaming" }))).verbosity)
test("cpuTier out of range -> nil", nil, bootcfg.load(fsWith(serialize.encode({ cpuTier = 9 }))).cpuTier)
test("cpuTier 3 kept", 3, bootcfg.load(fsWith(serialize.encode({ cpuTier = 3 }))).cpuTier)
test("dataTier out of range -> nil", nil, bootcfg.load(fsWith(serialize.encode({ dataTier = 0 }))).dataTier)
test("dataTier 3 kept", 3, bootcfg.load(fsWith(serialize.encode({ dataTier = 3 }))).dataTier)
test("dataTier default nil", nil, bootcfg.load(fsWith(nil)).dataTier)

-- ── Oversized file => fail-safe defaults ───────────────────────────
local big = "return {" .. string.rep("x=1,", 5000) .. "}"  -- > 8 KB
test("oversized file -> defaults (normal)", "normal", bootcfg.load(fsWith(big)).profile)

-- ── verbosity() muter resolution ───────────────────────────────────
test("minimal profile default verbosity = splash", "splash",
  bootcfg.verbosity(bootcfg._normalize({ profile = "minimal" })))
test("explicit verbosity overrides profile", "silent",
  bootcfg.verbosity(bootcfg._normalize({ profile = "full", verbosity = "silent" })))

-- ── shows(): rank comparison ───────────────────────────────────────
test("silent boot hides text", false, bootcfg.shows(bootcfg._normalize({ verbosity = "silent" }), "text"))
test("verbose boot shows text", true,  bootcfg.shows(bootcfg._normalize({ verbosity = "verbose" }), "text"))
test("text boot shows splash",  true,  bootcfg.shows(bootcfg._normalize({ verbosity = "text" }), "splash"))

-- ── wants(): feature resolution order ──────────────────────────────
test("full profile loads net", true,  bootcfg.wants(bootcfg._normalize({ profile = "full" }), "net", true))
test("minimal profile skips net", false, bootcfg.wants(bootcfg._normalize({ profile = "minimal" }), "net", true))
-- normal profile = follow RAM gate
test("normal + RAM ok loads net", true,  bootcfg.wants(bootcfg._normalize({ profile = "normal" }), "net", true))
test("normal + RAM low skips net", false, bootcfg.wants(bootcfg._normalize({ profile = "normal" }), "net", false))
-- advanced override beats the profile pin
test("advanced override beats profile", false,
  bootcfg.wants(bootcfg._normalize({ profile = "full", advanced = { net = false } }), "net", true))

-- ── Safe Mode profile (Jul 2026 operator knobs) ────────────────────
local safe = bootcfg._normalize({ profile = "safe" })
test("safe profile is known", "safe", safe.profile)
for _, feat in ipairs({ "services", "cron", "packages", "net", "theme",
    "compat", "audio", "swap", "jbod" }) do
  test("safe pins " .. feat .. " OFF (even with RAM to spare)", false,
    bootcfg.wants(safe, feat, true))
end
test("safe boots loud (text), never quiet", "text", bootcfg.verbosity(safe))
-- The new gates in the other profiles
test("minimal skips services too", false,
  bootcfg.wants(bootcfg._normalize({ profile = "minimal" }), "services", true))
test("normal: services follow the RAM gate", true,
  bootcfg.wants(bootcfg._normalize({ profile = "normal" }), "services", true))
test("full pins packages on", true,
  bootcfg.wants(bootcfg._normalize({ profile = "full" }), "packages", false))
-- Even in safe mode, an explicit advanced override still wins (operator
-- said so twice — e.g. safe + net for a remote-rescue session).
test("advanced override beats safe pin", true,
  bootcfg.wants(bootcfg._normalize({ profile = "safe", advanced = { net = true } }), "net", false))

-- ── ui / repair / ramGate fields ───────────────────────────────────
local knobs = bootcfg._normalize({ ui = "cli", repair = true, ramGate = false })
test("ui=cli survives normalize", "cli", knobs.ui)
test("ui helper resolves cli", "cli", bootcfg.ui(knobs))
test("ui default resolves home", "home", bootcfg.ui(bootcfg._normalize({})))
test("ui: junk collapses to home", "home",
  bootcfg.ui(bootcfg._normalize({ ui = "desktop" })))
-- split is the pre-merge panels shape (Shell tab + Desktop tab), kept as
-- an operator escape hatch, so it has to survive normalize like cli does.
test("ui helper resolves split", "split", bootcfg.ui(bootcfg._normalize({ ui = "split" })))
test("ui: split persists", "split", bootcfg._normalize({ ui = "split" }).ui)
test("repair one-shot flag survives", true, knobs.repair)
test("repair: junk collapses to false", false,
  bootcfg._normalize({ repair = "yes" }).repair)
test("ramGate=false (tight) survives", false, knobs.ramGate)
test("ramGate: junk collapses to auto", nil,
  bootcfg._normalize({ ramGate = "plenty" }).ramGate)
-- ramOK resolution: declaration wins, else measurement
test("ramOK: tight forces gates shut", false, bootcfg.ramOK(knobs, true))
test("ramOK: plenty forces gates open", true,
  bootcfg.ramOK(bootcfg._normalize({ ramGate = true }), false))
test("ramOK: auto follows the measurement", false,
  bootcfg.ramOK(bootcfg._normalize({}), false))

-- ── The new fields round-trip through save/load ────────────────────
do
  local store = {}
  local fsRW = {
    exists = function(p) return store[p] ~= nil end,
    readFile = function(p) return store[p] end,
    writeFile = function(p, d) store[p] = d; return true end,
  }
  test("save with knobs ok", true,
    (bootcfg.save(fsRW, { profile = "safe", ui = "cli", repair = true, ramGate = true })))
  local back = bootcfg.load(fsRW)
  test("round-trip: profile safe", "safe", back.profile)
  test("round-trip: ui cli", "cli", back.ui)
  test("round-trip: repair still armed", true, back.repair)
  test("round-trip: ramGate plenty", true, back.ramGate)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
