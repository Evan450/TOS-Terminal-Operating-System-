-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: bootsettings (DEL-setup field model) ║
-- ║  - fields() enumerates editable settings               ║
-- ║  - cycle()/cycleKey() advance each field's value ring  ║
-- ║  - edits round-trip through bootcfg.save/load           ║
-- ║  Field order (Jul 2026 operator knobs): profile,       ║
-- ║  verbosity, ui, repair, showConfig | cpuTier, dataTier, ║
-- ║  ramGate, then one toggle per optional feature.         ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bootsettings.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_bootsettings.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local serialize = loadMod("serialize.lua"); package.loaded["kernel.serialize"] = serialize
local bootcfg   = loadMod("bootcfg.lua");   package.loaded["kernel.bootcfg"]   = bootcfg
local bs        = loadMod("bootsettings.lua")
if not (serialize and bootcfg and bs) then
  print("FAIL: could not load modules")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== bootsettings Tests ===")
print()

-- ── fields(): 8 base + one per optional feature ────────────────────
local fields = bs.fields({})
test("field count = 8 + #FEATURES", 8 + #bootcfg.FEATURES, #fields)
test("field 1 is profile", "Profile (what loads)", fields[1].label)
test("default profile value shown", "normal", fields[1].value)
test("default verbosity shows auto", "auto", fields[2].value)
test("field 3 is interface", "Interface (all seats)", fields[3].label)
test("default interface shows Home", "panels (Home: one tab, two views)", fields[3].value)
test("field 4 is self-repair", "Self-repair next boot", fields[4].label)
test("default repair shows off", "off", fields[4].value)
test("default showConfig shows on", "on", fields[5].value)
test("default cpuTier shows auto", "auto (detect)", fields[6].value)
test("field 7 is dataTier", "Data Card tier (override)", fields[7].label)
test("default dataTier shows auto", "auto (detect)", fields[7].value)
test("field 8 is the RAM gate", "RAM for extras (override)", fields[8].label)
test("default ramGate shows auto", "auto (measure)", fields[8].value)

-- ── basic/advanced grouping ────────────────────────────────────────
-- Everyday choices are "basic" (shown up front); overrides + device
-- checks are "advanced" (hidden behind the [A] toggle).
test("profile is basic", "basic", fields[1].group)
test("verbosity is basic", "basic", fields[2].group)
test("interface is basic", "basic", fields[3].group)
test("repair is basic", "basic", fields[4].group)
test("showConfig is basic", "basic", fields[5].group)
test("cpuTier is advanced", "advanced", fields[6].group)
test("dataTier is advanced", "advanced", fields[7].group)
test("ramGate is advanced", "advanced", fields[8].group)
test("feature toggle is advanced", "advanced", fields[9].group)
local nBasic = 0
for _, f in ipairs(fields) do if f.group == "basic" then nBasic = nBasic + 1 end end
test("exactly 5 basic fields", 5, nBasic)

-- ── cycleKey(): cycle a field by identity, not list index ──────────
local ck = bootcfg._normalize({})
bs.cycleKey(ck, "profile", 1)
test("cycleKey profile normal -> full", "full", ck.profile)
bs.cycleKey(ck, "cpuTier", 1)
test("cycleKey cpuTier auto -> 1", 1, ck.cpuTier)
local before = ck.profile
bs.cycleKey(ck, "no.such.key", 1)
test("cycleKey unknown key is a no-op", before, ck.profile)

-- ── profile ring includes Safe Mode ────────────────────────────────
local c = bootcfg._normalize({})
bs.cycleKey(c, "profile", -1)   -- normal -> minimal? ring is m,n,f,d,safe: -1 wraps to minimal? normal(2)-1=minimal(1)
test("profile normal -> minimal (-1)", "minimal", c.profile)
bs.cycleKey(c, "profile", -1)   -- minimal -1 wraps to safe
test("profile wraps to safe", "safe", c.profile)
local shown = bs.fields(c)
test("safe shows as SAFE MODE", "SAFE MODE", shown[1].value)

-- ── interface ring: home -> split -> cli -> home ──────────────────────
local cu = bootcfg._normalize({})
bs.cycleKey(cu, "ui", 1)
test("interface home -> split", "split", cu.ui)
bs.cycleKey(cu, "ui", 1)
test("interface split -> cli", "cli", cu.ui)
bs.cycleKey(cu, "ui", 1)
test("interface cli -> home (nil in config)", nil, cu.ui)

-- ── self-repair one-shot toggle ────────────────────────────────────
local cr = bootcfg._normalize({})
bs.cycleKey(cr, "repair", 1)
test("repair off -> RUN ONCE", true, cr.repair)
bs.cycleKey(cr, "repair", 1)
test("repair wraps back off", false, cr.repair)

-- ── RAM gate ring: auto -> plenty -> tight -> auto ─────────────────
local cg = bootcfg._normalize({})
bs.cycleKey(cg, "ramGate", 1)
test("ramGate auto -> plenty(true)", true, cg.ramGate)
bs.cycleKey(cg, "ramGate", 1)
test("ramGate plenty -> tight(false)", false, cg.ramGate)
bs.cycleKey(cg, "ramGate", 1)
test("ramGate tight -> auto(nil)", nil, cg.ramGate)

-- ── cycle(): positional still works (verbosity=2, showConfig=5) ────
local c2 = bootcfg._normalize({})
bs.cycle(c2, 2, 1)
test("verbosity auto -> silent", "silent", c2.verbosity)
local c3 = bootcfg._normalize({})
bs.cycle(c3, 5, 1)
test("showConfig on -> off", false, c3.showConfig)

-- ── cycle(): cpuTier (6) and dataTier (7) rings ────────────────────
local c4 = bootcfg._normalize({})
bs.cycle(c4, 6, 1)
test("cpuTier auto -> 1", 1, c4.cpuTier)
bs.cycle(c4, 6, 1); bs.cycle(c4, 6, 1)
test("cpuTier -> 3", 3, c4.cpuTier)
bs.cycle(c4, 6, 1)
test("cpuTier 3 -> auto (nil)", nil, c4.cpuTier)
local cd = bootcfg._normalize({})
bs.cycle(cd, 7, 1)
test("dataTier auto -> 1", 1, cd.dataTier)
bs.cycle(cd, 7, 1); bs.cycle(cd, 7, 1)
test("dataTier -> 3", 3, cd.dataTier)
bs.cycle(cd, 7, 1)
test("dataTier 3 -> auto (nil)", nil, cd.dataTier)

-- ── cycle(): an advanced feature toggle (field 9 = first feature) ──
local c5 = bootcfg._normalize({})
bs.cycle(c5, 9, 1)
test("advanced feature auto -> true", true, c5.advanced[bootcfg.FEATURES[1]])
bs.cycle(c5, 9, 1)
test("advanced feature true -> false", false, c5.advanced[bootcfg.FEATURES[1]])
bs.cycle(c5, 9, 1)
test("advanced feature false -> auto (nil)", nil, c5.advanced[bootcfg.FEATURES[1]])

-- ── Edits round-trip through bootcfg.save/load ─────────────────────
local store = {}
local mockFS = {
  exists = function(p) return store[p] ~= nil end,
  readFile = function(p) return store[p] end,
  writeFile = function(p, d) store[p] = d; return true end,
}
local edited = bootcfg._normalize({})
bs.cycleKey(edited, "profile", 1)      -- normal -> full
bs.cycleKey(edited, "cpuTier", 3)      -- auto -> 3 (three steps)
bs.cycleKey(edited, "dataTier", 2)     -- auto -> 2 (two steps)
bs.cycleKey(edited, "ui", 1)           -- home -> split
bs.cycleKey(edited, "repair", 1)       -- off -> run once
bs.cycleKey(edited, "ramGate", 2)      -- auto -> tight
bootcfg.save(mockFS, edited)
local reloaded = bootcfg.load(mockFS)
test("saved profile round-trips", "full", reloaded.profile)
test("saved cpuTier round-trips", 3, reloaded.cpuTier)
test("saved dataTier round-trips", 2, reloaded.dataTier)
test("saved interface round-trips", "split", reloaded.ui)
test("saved repair round-trips", true, reloaded.repair)
test("saved ramGate round-trips", false, reloaded.ramGate)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
