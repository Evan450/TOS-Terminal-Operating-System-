-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: warhead (model, data, optimizer)           ║
-- ║                                                              ║
-- ║  Every expected number below came out of a SEPARATE Python   ║
-- ║  reference written from the same javap listings (float32     ║
-- ║  rounding included), not out of this package: a test that    ║
-- ║  asks model.lua what model.lua thinks would pass whatever    ║
-- ║  model.lua got wrong. Where a number is checkable by hand    ║
-- ║  the arithmetic is in the comment.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/warhead/test_warhead.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (want " .. tostring(expected) .. ", got " .. tostring(actual) .. ")", expected == actual)
end
local function near(name, expected, actual, tol)
  test(name .. "  (want " .. tostring(expected) .. ", got " .. tostring(actual) .. ")",
    type(actual) == "number" and math.abs(expected - actual) <= (tol or 1e-6))
end

package.path = "modules/?.lua;modules/?/init.lua;" .. package.path
local M = require("warhead.model")
local B = require("warhead.best")
local D = M.D

local function slots(spec)
  local out = {}
  for _, p in ipairs(spec) do for _ = 1, p[2] do out[#out + 1] = p[1] end end
  return out
end

print("=== The data matches the mod ===")
eq("65 custom nuke ingredients (registerBombItems)", 65, #D.INGREDIENTS)
do
  local seen, dup = {}, nil
  for _, it in ipairs(D.INGREDIENTS) do
    if seen[it.key] then dup = it.key end
    seen[it.key] = true
  end
  test("ingredient keys are unique" .. (dup and (" (" .. dup .. ")") or ""), dup == nil)
end
eq("Plutonium-239 Ingot adds 25 to Nuclear", 25, M.byKey.pu239.v)
eq("Block of Redstone multiplies TNT by 1.5", true, M.byKey.redstone_block.m)
eq("a Diesel Canister is identified by its fluid id (20)", "canister_diesel", M.lookup("hbm:canister_fuel", 20).key)
eq("a Kerosene Canister is fluid id 22", "canister_kerosene", M.lookup("hbm:canister_fuel", 22).key)
eq("an empty canister is no ingredient", nil, M.lookup("hbm:canister_fuel", 0))
eq("a Tritium Cell is cell #9", "cell_tritium", M.lookup("hbm:cell", 9).key)
eq("a plain item ignores its damage value", "pu239", M.lookup("hbm:ingot_pu239", 3).key)
eq("the Tsar Bomba's default radius is 500", 500, D.CONFIG.tsarRadius)

print()
print("=== Custom nuke stages (TileEntityNukeCustom.update) ===")
do
  -- 20 x 0.8f summed in floats is 16.0000019, over the 16 the Nuclear
  -- stage needs. In doubles it is exactly 16 — also over, but only by
  -- luck of the comparison being >=.
  local v = M.stages(slots({ { "gunpowder", 20 } }))
  if M.EXACT then
    near("20 Gunpowder sum like Java floats (16.0000019)", 16.000001907348633, v.TNT, 1e-12)
  else
    near("20 Gunpowder sum to 16", 16, v.TNT, 1e-6)
  end
  local v2 = M.stages(slots({ { "gunpowder", 1 }, { "gunpowder", 1 } }))
  near("each slot counts once, whatever it holds (2 slots = 1.6)", 1.6, v2.TNT, 1e-6)
end
do
  local v, info = M.stages(slots({ { "c4", 1 }, { "pu239", 4 } }))
  eq("Nuclear switches off with TNT under 16", 0, v.NUKE)
  test("and says why", info.off.NUKE ~= nil and info.off.NUKE:find("under the 16") ~= nil)
end
do
  local v, info = M.stages(slots({ { "det_charge", 2 }, { "neptunium", 7 } }))
  eq("7 Neptunium = 210, capped at maxCustomNukeRadius 200", 200, v.NUKE)
  eq("the cap is reported", 200, info.capped.NUKE)
  local o = M.customOutcome(v)
  eq("fires as a fission MK5", "mk5", o.engine)
  eq("radius = min(200 + 30/2, 200) = 200", 200, o.radius)
end
do
  local v = M.stages(slots({ { "det_charge", 2 }, { "neptunium", 4 }, { "td_cake", 2 } }))
  eq("Hydrogen 400 caps at 350", 350, v.HYDRO)
  local o = M.customOutcome(v)
  eq("thermonuclear radius 350", 350, o.radius)
  eq("fires through the Hydrogen stage", "HYDRO", o.via)
end
do
  local v = M.stages(slots({ { "det_charge", 2 }, { "neptunium", 3 }, { "td_cake", 1 } }))
  eq("Hydrogen needs Nuclear 100 (90 here): off", 0, v.HYDRO)
end
do
  -- Python reference: d5 -> ('zomg', 300)
  local d = slots({ { "det_charge", 2 }, { "powder_neptunium", 2 }, { "block_solinium", 2 },
                    { "block_schrabidium", 1 }, { "euphemium", 3 } })
  local o = M.customOutcome(M.stages(d))
  eq("Euphemium with Schrab and Sol live: Anti Mass", "zomg", o.engine)
  eq("3 levels = 300 beams", 300, o.beams)
  -- d6: drop the Schrabidium and Anti Mass dies; Solinium fires instead.
  local d6 = slots({ { "det_charge", 2 }, { "powder_neptunium", 2 }, { "block_solinium", 2 }, { "euphemium", 3 } })
  local v6, info6 = M.stages(d6)
  eq("no Schrabidium: Anti Mass is off", 0, v6.EUPH)
  test("and says why", info6.off.EUPH ~= nil)
  local o6 = M.customOutcome(v6)
  eq("Solinium = 100 + 60/16 + 30/32 = 104.69 -> 104", 104, o6.radius)
end
do
  local o = M.customOutcome(M.stages(slots({ { "c4", 8 }, { "redstone_block", 1 } })))
  eq("80 TNT x 1.5 = 120, over 75: a clean MK5", "mk5", o.engine)
  eq("no fallout on a TNT nuke (statFacNoRad)", false, o.fallout)
  eq("radius 120", 120, o.radius)
  local o2 = M.customOutcome(M.stages(slots({ { "c4", 3 } })))
  eq("30 TNT is an ordinary explosion", "large", o2.engine)
end
do
  -- d8: 75 Nuclear, Salted 30 x 1.25 = 37.5 -> moreFallout(37)
  local o = M.customOutcome(M.stages(slots({ { "det_charge", 2 }, { "pu239", 3 },
    { "custom_dirty", 3 }, { "block_waste", 1 } })))
  eq("fission radius 75 + 15 = 90", 90, o.radius)
  eq("Salted adds (int)37.5 = 37 to the fallout", 37, o.falloutAdd)
  local o2 = M.customOutcome(M.stages(slots({ { "det_charge", 2 }, { "neptunium", 4 },
    { "td_cake", 1 }, { "custom_dirty", 4 } })))
  eq("a thermonuclear passes on only a quarter: 40 * 0.25 = 10", 10, o2.falloutAdd)
end
do
  local o = M.customOutcome(M.stages(slots({ { "det_charge", 2 }, { "pu239", 2 }, { "balefire_egg", 1 } })))
  eq("balefire 150 + 50/4 + 30/8 = 166.25 -> 166", 166, o.radius)
end

print()
print("=== Fixed bombs (explode / isReady / isFilled) ===")
local function bomb(key) for _, b in ipairs(D.BOMBS) do if b.key == key then return b end end end
eq("Little Boy, loaded: boyRadius 120", 120, M.bombOutcome(bomb("boy")).radius)
do
  local mike = bomb("mike")
  local readyOnly = {}
  for s, id in ipairs(mike.parts) do readyOnly[s] = { id = id } end
  local o = M.bombOutcome(mike, nil, readyOnly)
  eq("Ivy Mike without its deuterium stage fizzles to Fat Man's 175", 175, o.radius)
  eq("and the simulator says so", true, o.fizzle)
  local full = {}
  for s, id in ipairs(mike.parts) do full[s] = { id = id } end
  for s, id in pairs(mike.filled) do full[s] = { id = id } end
  eq("filled: mikeRadius 250", 250, M.bombOutcome(mike, nil, full).radius)
  local o2 = M.bombOutcome(mike, nil, { [1] = { id = "hbm:man_explosive8" } })
  eq("missing lenses and core: not ready", false, o2.ready)
  eq("four parts named as missing", 4, #o2.missing)
end
do
  local n2 = bomb("n2")
  eq("N2 mine, 12 charges: 200", 200, M.bombOutcome(n2).radius)
  local five = {}
  for s = 1, 5 do five[s] = { id = "hbm:n2_charge" } end
  eq("5 charges: (int)(200*5/12f) = 83", 83, M.bombOutcome(n2, nil, five).radius)
  eq("N2 has no fallout", false, M.bombOutcome(n2).fallout)
end
do
  local proto = bomb("prototype")
  local c = {}
  for s, want in ipairs(proto.parts) do
    local id, dmg = want:match("^(.-)#(%d+)$")
    c[s] = { id = id, dmg = tonumber(dmg) }
  end
  eq("the Prototype reads its rods by metadata: ready", true, M.bombOutcome(proto, nil, c).ready)
  c[5] = { id = "hbm:rod_quad", dmg = 14 }       -- uranium where lead goes
  eq("a uranium rod in a lead slot is caught", false, M.bombOutcome(proto, nil, c).ready)
end
eq("the Balefire Bomb's 250 is hard-coded", 250, M.bombOutcome(bomb("balefire")).radius)
do
  local cfg = M.config({ boyRadius = 150 })
  eq("a server's config override is honoured", 150, M.bombOutcome(bomb("boy"), cfg).radius)
  eq("an override of the wrong type is ignored", 120, M.config({ boyRadius = "big" }).boyRadius)
end

print()
print("=== Missiles ===")
local function missile(key)
  for _, m in ipairs(D.MISSILES) do if m.key == key then return m end end
  for _, m in ipairs(D.WARHEADS) do if m.key == key then return m end end
end
eq("Thermonuclear Missile = 2 x missileRadius", 200, M.missileOutcome(missile("m_thermo")).radius)
eq("N2 Missile = (200 / 12) * 5 in ints = 80", 80, M.missileOutcome(missile("m_n2")).radius)
eq("Doomsday adds 100 to its fallout", 100, M.missileOutcome(missile("m_doomsday")).falloutAdd)
eq("MIRV warhead strength is mirvRadius (70)", 70, M.missileOutcome(missile("w15_mirv")).radius)
eq("a Boxcar warhead is 500", 500, M.missileOutcome(missile("w15_boxcar")).radius)

print()
print("=== The blast (ExplosionNukeRayParallelized) ===")
-- Python reference: loss_factor(6, 0.5) = 16.85161590576172 (LUT, bins);
-- the exact 7^1.5 - 1 = 17.52 shows the table is quantised, as in-game.
near("lossFactor(stone 6, t 0.5) from the LUT", 16.85161590576172, M.lossFactor(6, 0.5), 1e-9)
near("lossFactor(dirt 0.5, t 0.3)", 0.3442317545413971, M.lossFactor(0.5, 0.3), 1e-9)
near("lossFactor(concrete 84, t 0.25)", 25.899410247802734, M.lossFactor(84, 0.25), 1e-9)
near("lossFactor over 100 is exact: 151^0.3 - 1", 3.504982250263681, M.lossFactor(150, 0.1), 1e-9)
eq("nothing is lost at ground zero", 0, M.lossFactor(6, 0))

local CRATER = {   -- radius -> stone, dirt, concrete, obsidian (Python reference)
  [100] = { 33, 94, 19, 25 }, [120] = { 39, 112, 23, 30 }, [175] = { 57, 164, 33, 43 },
  [250] = { 81, 234, 47, 62 }, [500] = { 161, 467, 93, 123 },
}
for _, r in ipairs({ 100, 120, 175, 250, 500 }) do
  local want = CRATER[r]
  local got = {}
  for i, res in ipairs({ 6, 0.5, 84, 18 }) do got[i] = (M.craterDepth(r, res)) end
  test(string.format("crater depth r=%d: stone/dirt/concrete/obsidian = %d/%d/%d/%d (got %d/%d/%d/%d)",
    r, want[1], want[2], want[3], want[4], got[1], got[2], got[3], got[4]),
    got[1] == want[1] and got[2] == want[2] and got[3] == want[3] and got[4] == want[4])
end
do
  local n, through = M.craterDepth(100, 0.1)
  test("water barely slows a blast: the ray reaches the full radius", through and n == 100)
end
local WALL = { { 100, 6, 50, 4 }, { 100, 6, 90, 1 }, { 100, 84, 10, 11 }, { 100, 84, 50, 1 },
               { 175, 84, 30, 9 }, { 500, 84, 100, 19 }, { 500, 6, 250, 17 }, { 250, 96, 5, 42 } }
for _, w in ipairs(WALL) do
  local n = M.wallStop(w[1], w[2], w[3])
  eq(string.format("wall: r=%d, resistance %g, %d out, stops in", w[1], w[2], w[3]), w[4], n)
end
eq("bedrock stops a ray in one block", 1, (M.wallStop(500, 3600000, 3)))

print()
print("=== Effects (EntityNukeExplosionMK5.onUpdate) ===")
do
  local e = M.effects({ engine = "mk5", radius = 120, fallout = true, falloutAdd = 0 })
  eq("Little Boy hurts entities out to 2r = 240", 240, e.blast)
  near("one tick kills an unarmoured player inside 0.92 x 240", 220.8, e.lethal, 1e-9)
  eq("fallout zone (int)(120 * 2.5) * 100/100 = 300", 300, e.fallout)
  near("glowing ones out to 1.5r", 180, e.glow, 1e-9)
  eq("ray count (int)(2.5 pi (2r)^2) = 452389", 452389, e.rays)
  -- Python reference: lethal open-air dose radius 29.396211219339367
  near("1000 RAD in open air at 29.40 m", 29.396211219339367, e.death, 1e-9)
  near("dose at 10 m in open air: 8641.37", 8641.372340520136, M.dose(10, 0), 1e-6)
  near("dose behind 10 blocks of obsidian (1200 each) at 10 m", 8641.372340520136 / 12000, M.dose(10, 12000), 1e-9)
end
do
  local e = M.effects({ engine = "mk5", radius = 100, falloutAdd = 100 })
  eq("Doomsday fallout (int)(250 + 100) = 350", 350, e.fallout)
  local e2 = M.effects({ engine = "mk5", radius = 100, falloutAdd = 100 }, M.config({ falloutRange = 50 }))
  eq("falloutRange 50% halves it: 175", 175, e2.fallout)
  local e3 = M.effects({ engine = "mk5", radius = 30, fallout = true })
  eq("radius 30 (strength 60) is under the pulse's 75", nil, e3.pulse)
  local e4 = M.effects({ engine = "mk5", radius = 100 }, M.config({ disableNuclear = true }))
  eq("disableNuclear: no fallout", nil, e4.fallout)
end
do
  local mat = { nuke = 84, rad = 84 }
  local e = M.effects({ engine = "mk5", radius = 100 })
  local v = M.shelter(nil, e, mat, 50, 1)
  eq("1 block of concrete at 50 m stops r=100", false, v.breached)
  local v2 = M.shelter(nil, e, mat, 10, 5)
  eq("5 blocks at 10 m do not (it needs 11)", true, v2.breached)
  eq("and the shelter says how many it needs", 11, v2.need)
end

print()
print("=== The best design (best.lua) ===")
local CAPS = { tnt = 150, nuke = 200, hydro = 350, bale = 350, schrab = 250, sol = 350 }
local MINSLOTS = { tnt = 6, nuke = 9, hydro = 8, bale = 7, schrab = 8, sol = 10 }
for _, g in ipairs(B.ORDER) do
  local d, err = B.design(g)
  test(g .. ": a design exists" .. (err and (" (" .. err .. ")") or ""), d ~= nil)
  if d then
    eq(g .. ": reaches its cap", CAPS[g], d.outcome.radius)
    eq(g .. ": in the fewest slots", MINSLOTS[g], #d.slots)
    -- Recompute from scratch: the design must really do what it claims.
    local o = M.customOutcome(M.stages(d.slots))
    eq(g .. ": the stored design re-simulates to the same radius", d.outcome.radius, o.radius)
  end
end
do
  -- 6 Neptunium = 180 + 15/2... a nuke design must use the weakest TNT
  -- that still clears 16: a Det Cord (1.5) with one Explosive Charge (15).
  local d = B.design("nuke")
  local keys = {}
  for _, it in ipairs(d.slots) do keys[it.key] = (keys[it.key] or 0) + 1 end
  eq("downgrading spent a Det Cord, not a second Explosive Charge", 1, keys.det_cord)
end
do
  local d = B.design("hydro", nil, { stock = { det_charge = 1, c4 = 1, pu239 = 5, cell_deuterium = 6 } })
  -- 25 TNT, 125 Nuclear, 120 Hydrogen: 120 + 62.5 + 6.25 = 188.75 -> 188
  eq("from a limited stock: 188", 188, d and d.outcome.radius)
  local none = B.design("hydro", nil, { stock = { det_charge = 2, pu239 = 3, cell_deuterium = 9 } })
  eq("75 Nuclear cannot light Hydrogen: no design", nil, none)
end
do
  local d = B.design("nuke", nil, { radius = 100 })
  test("a target radius takes the first design that reaches it", d and d.outcome.radius >= 100 and #d.slots < 9)
end
do
  local d = B.design("hydro", nil, { salt = true })
  eq("salting fills every spare slot", 27, #d.slots)
  eq("and the blast is unchanged", 350, d.outcome.radius)
  test("the fallout grows", (d.outcome.falloutAdd or 0) > 0)
end
do
  local d = B.designEuph()
  eq("Anti Mass: 20 levels (the cap) = 2000 beams", 2000, d.outcome.beams)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All tests passed.")
