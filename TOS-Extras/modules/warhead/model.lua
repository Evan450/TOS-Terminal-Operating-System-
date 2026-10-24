-- ╔══════════════════════════════════════════════════════════════╗
-- ║  warhead — the arithmetic, done the way the mod does it      ║
-- ║                                                              ║
-- ║  Each function here mirrors one method of NTM-CE 2.5.0.5     ║
-- ║  (named in its comment), down to where the mod casts to int  ║
-- ║  and where it works in 32-bit floats. That matters: a custom ║
-- ║  nuke's Nuclear stage switches off below exactly 16 TNT, and ║
-- ║  twenty Gunpowder sum to 16.0000019 in floats — over the     ║
-- ║  line — where doubles would say 16.0 and a careless          ║
-- ║  rewrite could say 15.99999.                                 ║
-- ║                                                              ║
-- ║  Pure: no component, no fs, no screen. test_warhead.lua      ║
-- ║  checks it against an independent Python reference.          ║
-- ╚══════════════════════════════════════════════════════════════╝

local D = require("warhead.data")

local M = {}
M.D = D

-- ── 32-bit floats ─────────────────────────────────────────────────────
-- Java keeps the custom nuke's stage totals in `float`. Lua 5.3 can round
-- a number to a 32-bit float through string.pack; Lua 5.2 cannot, and
-- there the sums run in doubles. EXACT says which this machine got, so
-- the UI can flag a total sitting on a threshold as "the game's rounding
-- decides" instead of claiming a verdict it cannot make.
local f32 = function(x) return x end
do
  local okP = pcall(function() return string.pack("f", 1.5) end)
  if okP then
    f32 = function(x) return (string.unpack("f", string.pack("f", x))) end
  end
end
M.f32 = f32
M.EXACT = (f32(0.1) ~= 0.1)

local floor = math.floor
--- Java's (int) cast: truncates toward zero.
local function toInt(x)
  if x >= 0 then return floor(x) end
  return -floor(-x)
end
M.toInt = toInt

-- ── Configuration ─────────────────────────────────────────────────────
--- The mod's defaults with this machine's overrides on top.
function M.config(over)
  local c = {}
  for k, v in pairs(D.CONFIG) do c[k] = v end
  if type(over) == "table" then
    for k, v in pairs(over) do
      if D.CONFIG[k] ~= nil and type(v) == type(D.CONFIG[k]) then c[k] = v end
    end
  end
  return c
end

--- `cfg` as every function below takes it: a config, or nil for the
--- defaults. Anything else is refused in favour of the defaults, because
--- the easy mistake is real — M.stages returns (v, info), so
--- customOutcome(M.stages(x)) hands it `info` as the config and every
--- cap reads as nil.
function M.conf(cfg)
  if type(cfg) == "table" and cfg.falloutRange ~= nil then return cfg end
  return M.config()
end

-- ── Ingredient lookup ─────────────────────────────────────────────────
M.byKey = {}
M.byItem = {}
for _, it in ipairs(D.INGREDIENTS) do
  M.byKey[it.key] = it
  M.byItem[it.id .. (it.dmg and ("#" .. it.dmg) or "")] = it
end

--- The ingredient an item stack is, or nil. A canister or cell is only
--- an ingredient with the right fluid in it, so for those the metadata
--- has to match; for everything else it is ignored, the way the mod's
--- ComparableStack ignores a plain item's damage.
function M.lookup(id, dmg)
  if type(id) ~= "string" then return nil end
  local hit = dmg and M.byItem[id .. "#" .. tostring(toInt(dmg))]
  return hit or M.byItem[id]
end

--- Accept an ingredient table, a key, or nil.
local function asIngredient(x)
  if type(x) == "table" then return x end
  if type(x) == "string" then return M.byKey[x] end
  return nil
end
M.asIngredient = asIngredient

-- ══════════════════════════════════════════════════════════════════════
-- The custom nuke
-- ══════════════════════════════════════════════════════════════════════

--- TileEntityNukeCustom.update(): the eight stage values the block stores.
---
--- `slots` is an array of up to 27 entries (ingredient, key or nil).
--- Returns v, info:
---   v[stage]        what the tile entity keeps (after thresholds + caps)
---   info.raw[stage] the total before thresholds and caps
---   info.off[stage] why a stage was switched off (a sentence)
---   info.capped[stage] the cap it hit
---   info.edge[stage]   true when the total is within float noise of a
---                      threshold and this machine cannot round like Java
---   info.used, info.unknown, info.fall
function M.stages(slots, cfg)
  cfg = M.conf(cfg)
  local add, mul = {}, {}
  for _, s in ipairs(D.STAGES) do add[s] = f32(0); mul[s] = f32(1) end
  local info = { raw = {}, off = {}, capped = {}, edge = {}, used = 0, unknown = 0, fall = false }
  for i = 1, D.CUSTOM_SLOTS do
    local x = slots and slots[i]
    if x ~= nil and x ~= false then
      info.used = info.used + 1
      if x == D.DROP_UPGRADE.key or (type(x) == "table" and x.key == D.DROP_UPGRADE.key) then
        info.fall = true
      else
        local it = asIngredient(x)
        if not it then
          info.unknown = info.unknown + 1
        elseif it.m then
          -- MULT entries exist for every stage but EUPH: update()'s second
          -- tableswitch stops at ordinal 6.
          if it.stage ~= "EUPH" then mul[it.stage] = f32(mul[it.stage] * f32(it.v)) end
        else
          add[it.stage] = f32(add[it.stage] + f32(it.v))
        end
      end
    end
  end

  local v = {}
  for _, s in ipairs(D.STAGES) do
    v[s] = (s == "EUPH") and add[s] or f32(add[s] * mul[s])
    info.raw[s] = v[s]
  end

  -- The thresholds, in update()'s order. Each compares a value that may
  -- already have been zeroed by the one before it.
  local function gate(stage, by, limit)
    if v[stage] > 0 and v[by] < limit then
      info.off[stage] = string.format("%s is %s, under the %s it needs",
        D.STAGE_NAME[by], M.num(v[by]), M.num(limit))
      v[stage] = 0
    end
    if not M.EXACT and v[by] > 0 and math.abs(v[by] - limit) < 1e-3 then info.edge[by] = true end
  end
  gate("NUKE",   "TNT",  16)
  gate("HYDRO",  "NUKE", 100)
  gate("BALE",   "NUKE", 50)
  gate("SCHRAB", "NUKE", 50)
  gate("SOL",    "NUKE", 25)
  if v.EUPH > 0 and (v.SCHRAB < 1 or v.SOL < 1) then
    info.off.EUPH = "Anti Mass needs both Schrabidium and Solinium of at least 1"
    v.EUPH = 0
  end

  for _, s in ipairs(D.STAGES) do
    local cap = cfg[D.STAGE_CAP[s]]
    if v[s] > cap then v[s] = cap; info.capped[s] = cap end
  end
  return v, info
end

--- NukeCustom.explodeCustom(): which explosion the stored stages make.
--- The first non-zero stage in EUPH, SOL, SCHRAB, BALE, HYDRO, NUKE order
--- wins outright and takes a falling share of every stage below it.
function M.customOutcome(v, cfg)
  cfg = M.conf(cfg)
  local tnt, nuke, hydro, bale = v.TNT, v.NUKE, v.HYDRO, v.BALE
  local schrab, sol, euph = v.SCHRAB, v.SOL, v.EUPH
  local dirty = math.min(v.DIRTY, cfg.maxCustomDirtyRadius)
  local o
  if euph > 0 then
    local lvl = math.min(euph, cfg.maxCustomEuphLvl)
    o = { engine = "zomg", via = "EUPH", beams = toInt(100 * lvl), level = lvl }
  elseif sol > 0 then
    local r = sol + schrab / 2 + bale / 4 + hydro / 8 + nuke / 16 + tnt / 32
    o = { engine = "solinium", via = "SOL", raw = r, radius = toInt(math.min(r, cfg.maxCustomSolRadius)),
          formula = "Sol + Schrab/2 + Bale/4 + Hydro/8 + Nuke/16 + TNT/32" }
  elseif schrab > 0 then
    local r = schrab + bale / 2 + hydro / 4 + nuke / 8 + tnt / 16
    o = { engine = "fleija", via = "SCHRAB", raw = r, radius = toInt(math.min(r, cfg.maxCustomSchrabRadius)),
          formula = "Schrab + Bale/2 + Hydro/4 + Nuke/8 + TNT/16" }
  elseif bale > 0 then
    local r = bale + hydro / 2 + nuke / 4 + tnt / 8
    o = { engine = "balefire", via = "BALE", raw = r, radius = toInt(math.min(r, cfg.maxCustomBaleRadius)),
          formula = "Bale + Hydro/2 + Nuke/4 + TNT/8" }
  elseif hydro > 0 then
    local r = hydro + nuke / 2 + tnt / 4
    -- The Salted stage only feeds a quarter of itself to a thermonuclear.
    o = { engine = "mk5", via = "HYDRO", raw = r, radius = toInt(math.min(r, cfg.maxCustomHydroRadius)),
          falloutAdd = toInt(dirty * 0.25), formula = "Hydro + Nuke/2 + TNT/4" }
  elseif nuke > 0 then
    local r = nuke + tnt / 2
    o = { engine = "mk5", via = "NUKE", raw = r, radius = toInt(math.min(r, cfg.maxCustomNukeRadius)),
          falloutAdd = toInt(dirty), formula = "Nuke + TNT/2" }
  elseif tnt >= 75 then
    o = { engine = "mk5", via = "TNT", fallout = false, raw = tnt,
          radius = toInt(math.min(tnt, cfg.maxCustomTNTRadius)), formula = "TNT (75 and over)" }
  elseif tnt > 0 then
    o = { engine = "large", via = "TNT", power = tnt, formula = "TNT (under 75)" }
  else
    o = { engine = "none" }
  end
  if o.raw and o.radius and o.raw > o.radius + 1 then o.cappedAt = o.radius end
  return o
end

-- ══════════════════════════════════════════════════════════════════════
-- Fixed bombs and missiles
-- ══════════════════════════════════════════════════════════════════════

local function partKey(stack)
  if type(stack) ~= "table" or type(stack.id) ~= "string" then return nil end
  local dmg = tonumber(stack.dmg or stack.damage) or 0
  return stack.id, stack.id .. "#" .. toInt(dmg)
end

local function partMatches(want, stack)
  local id, idDmg = partKey(stack)
  if not id then return false end
  if type(want) == "table" then
    for _, w in ipairs(want) do if partMatches(w, stack) then return true end end
    return false
  end
  if want:find("#") then return want == idDmg end
  return want == id
end
M.partMatches = partMatches

function M.partName(want)
  if type(want) == "table" then
    local n = {}
    for _, w in ipairs(want) do n[#n + 1] = M.partName(w) end
    return table.concat(n, " or ")
  end
  return D.PART_NAME[want] or want
end

--- A fixed bomb's detonation. `contents` is optional: a map of slot ->
--- { id = "hbm:...", dmg = n } as a transposer reads the block. Without
--- it the bomb is assumed loaded and armed, which is what "simulate a
--- Little Boy" means.
function M.bombOutcome(b, cfg, contents)
  cfg = M.conf(cfg)
  local o = { engine = b.engine, fallout = (b.fallout ~= false), falloutAdd = 0,
              name = b.name, ready = true, missing = {} }
  local function check(slot, want)
    if contents and not partMatches(want, contents[slot]) then
      o.missing[#o.missing + 1] = { slot = slot, want = want }
      return false
    end
    return true
  end

  if b.perCharge then
    -- NukeN2: (int)(n2Radius * charges / 12f), charges = slots holding one.
    local charges = 12
    if contents then
      charges = 0
      for s = 1, b.slots do if partMatches(b.perCharge, contents[s]) then charges = charges + 1 end end
    end
    o.charges = charges
    if charges == 0 then
      o.ready = false
      o.missing[1] = { slot = 1, want = b.perCharge }
      o.radius = 0
    else
      o.radius = toInt(f32(cfg[b.radius] * charges) / 12)
    end
    return o
  end

  for s, want in ipairs(b.parts or {}) do
    if not check(s, want) then o.ready = false end
  end

  if b.fixed then
    o.radius = b.fixed
  elseif b.filled then
    local full = true
    for s, want in pairs(b.filled) do
      if contents and not partMatches(want, contents[s]) then full = false end
    end
    if o.ready and not full then
      -- NukeMike/NukeTsar.explode: ready and not filled = a Fat Man.
      o.radius = cfg[b.fizzle]
      o.fizzle = true
      for s, want in pairs(b.filled) do
        if not partMatches(want, contents[s]) then
          o.missing[#o.missing + 1] = { slot = s, want = want, optional = true }
        end
      end
    else
      o.radius = cfg[b.radius]
    end
  else
    o.radius = cfg[b.radius]
  end
  if not o.ready then o.radius = 0 end
  return o
end

--- A missile or a customizable-missile warhead.
function M.missileOutcome(m, cfg)
  cfg = M.conf(cfg)
  local r
  if m.strength then r = toInt(m.strength)
  else
    r = cfg[m.radius]
    if m.div then r = toInt(r / m.div) end
    if m.mult then r = r * m.mult end
  end
  local o = { engine = m.engine, fallout = (m.fallout ~= false), falloutAdd = m.falloutAdd or 0,
              name = m.name, ready = true, missing = {} }
  if m.engine == "large" then o.power = r else o.radius = r end
  return o
end

-- ══════════════════════════════════════════════════════════════════════
-- What a detonation does
-- ══════════════════════════════════════════════════════════════════════

-- ExplosionNukeRayParallelized.ENERGY_LOSS_LUT, computed per lookup rather
-- than stored: 65,536 numbers would cost a megabyte of Lua table, and the
-- formula is one pow.
local function lut(ri, di)
  local r = f32(f32(f32(ri) / f32(255)) * f32(100))
  local d = f32(f32(di) / f32(255))
  return f32((r + 1) ^ (3 * d) - 1)
end

--- getEnergyLossFactor(res, t): energy a ray loses per block of a
--- material of nuke resistance `res`, at fraction `t` of the radius out.
--- Zero at ground zero, steep at the rim — which is why a nuke always
--- digs a crater and a wall near the edge of its reach stops it cold.
function M.lossFactor(res, t)
  res = f32(res)
  if res >= 2000000 then return res end
  if res <= 0 then return 0 end
  if res > 100 then return (res + 1) ^ (3 * t) - 1 end
  local ri = toInt(f32(f32(res * f32(255)) / f32(100)))
  if ri == 0 then return (res + 1) ^ (3 * t) - 1 end
  return lut(ri, toInt(t * 255))
end

--- One ray of an MK5 blast, straight along an axis from the centre of the
--- bomb's block (traceSingle's DDA). `materialAt(k)` gives the nuke
--- resistance of the k-th block out (k = 0 is the bomb's own) or nil for
--- air. Returns the number of solid blocks the ray reached with energy
--- left, and whether it still had energy at the end of its radius.
---
--- An axis-aligned ray crosses each block by the shortest possible path,
--- so every slanted ray loses MORE: this is the blast's best case, and
--- the right one to plan a shelter against.
function M.ray(radius, materialAt)
  local energy = f32(f32(2 * radius) * f32(0.3))
  local entry, k, reached = 0, 0, 0
  local inv = 1 / radius
  while energy > 0 do
    local exit = k + 0.5
    local seg = exit - entry
    local rem = radius - entry
    if rem <= 1e-9 then break end
    local clipped = seg > rem - 1e-12
    if clipped then seg = rem end
    local res = materialAt(k)
    if res and seg > 1e-9 then
      if f32(res) >= 2000000 then energy = 0
      else
        local t = math.max(entry, 0.009999999776482582) * inv
        energy = energy - M.lossFactor(res, t) * seg
      end
      reached = reached + 1
    end
    entry = exit
    if energy <= 0 or clipped then break end
    k = k + 1
  end
  return reached, energy > 0
end

--- How deep the crater goes straight down into one material.
function M.craterDepth(radius, res)
  return M.ray(radius, function(k) if k == 0 then return nil end return res end)
end

--- How many blocks of a wall, starting `dist` blocks out, the blast eats
--- through before it runs out of energy. `through` = it never does.
function M.wallStop(radius, res, dist)
  return M.ray(radius, function(k) if k >= dist then return res end return nil end)
end

-- EntityNukeExplosionMK5.onUpdate: the radiation pulse runs on ticks 2-9
-- (tick 1 has no explosion object yet) at 2,500,000 / (5t + 1) RAD, each
-- divided by the shielding along the line and the distance squared.
local K = 0
for t = 2, 9 do K = K + 1 / (5 * t + 1) end
M.PULSE = 2500000 * K   -- about 864,137 RAD at one metre through air

--- Radiation dose from an MK5 blast at distance d, behind `shield` total
--- explosion resistance (getExplosionResistance, summed over the blocks on
--- the line; below 1 counts as 1).
function M.dose(d, shield)
  if d <= 0 then return math.huge end
  return M.PULSE / math.max(1, shield or 0) / (d * d)
end

--- The distance at which the dose falls to `rads` in open air.
function M.doseRadius(rads) return math.sqrt(M.PULSE / rads) end

--- Everything a detonation does, as numbers. Returns a table:
---   kind, radius, rays, energy, blast (2r), lethal (one tick, 20 HP),
---   pulse, sick, death (radiation radii), glow, fallout, notes = {...}
function M.effects(o, cfg)
  cfg = M.conf(cfg)
  local e = { kind = o.engine, notes = {} }
  local function note(s) e.notes[#e.notes + 1] = s end
  if o.engine == "none" or (o.radius == 0 and o.engine ~= "large" and o.engine ~= "zomg") then
    e.kind = "none"
    note("Nothing happens: no stage of this bomb is live.")
    return e
  end
  if o.engine == "mk5" then
    local r = o.radius
    if r == 0 then r = 25 end      -- statFac(world, 0, ...) means 25
    local s = 2 * r
    e.radius, e.strength = r, s
    e.rays = toInt(7.853981633974483 * s * s)
    e.energy = f32(f32(s) * f32(0.3))
    e.blast = 2 * r
    e.lethal = e.blast * (1 - D.PLAYER_HP / 250)
    local nuclear = o.fallout ~= false and not cfg.disableNuclear
    e.nuclear = nuclear
    if nuclear then
      if s >= 75 then
        e.pulse = true
        e.sick = math.min(M.doseRadius(D.RAD_SICK), e.blast)
        e.death = math.min(M.doseRadius(D.RAD_DEATH), e.blast)
      else
        note("Too small for the radiation pulse (it needs a radius of 38 or more).")
      end
      e.glow = r * 1.5
      e.fallout = toInt(toInt(r * 2.5 + (o.falloutAdd or 0)) * cfg.falloutRange / 100)
      e.falloutAdd = o.falloutAdd or 0
    else
      note(cfg.disableNuclear and "This server's config disables the nuclear part of nukes."
        or "A clean blast: no radiation pulse, no fallout.")
    end
  elseif o.engine == "fleija" then
    e.radius = o.radius
    e.blast = 2 * o.radius
    e.lethal = e.blast * (1 - D.PLAYER_HP / 250)
    e.sphere = true
    note("Antimatter: every block in the sphere is deleted except bedrock-class ones.")
    note("A Field Disturber or a DFC core within 300 blocks jams it: nothing happens.")
  elseif o.engine == "solinium" then
    e.radius = o.radius
    e.sphere = true
    e.rinse = true
    note("Everything living inside the sphere takes 15,000-250,000 RAD every tick.")
    note("Plants, leaves and wood go; wasteland, trinitite and taint revert to land.")
  elseif o.engine == "balefire" then
    e.radius = o.radius
    e.blast = 2 * o.radius
    e.lethal = e.blast * (1 - D.PLAYER_HP / 250)
    note("Balefire: carves the sphere and sets it alight with balefire.")
  elseif o.engine == "large" then
    e.power = o.power
    e.reachMin, e.reachMax = 0.7 * o.power / 0.225 * 0.3, 1.3 * o.power / 0.225 * 0.3
    e.blast = 2 * o.power
    note("An ordinary explosion (vanilla rules), with HBM's debris on top.")
  elseif o.engine == "zomg" then
    e.beams = o.beams
    note(string.format("Anti Mass: %d rainbow beams fire off in random directions.", o.beams))
  end
  return e
end

--- A shelter at `dist` blocks from ground zero built of `mat` (a
--- D.MATERIALS entry), `thick` blocks thick. Returns a verdict table.
function M.shelter(o, e, mat, dist, thick)
  local v = { dist = dist, thick = thick }
  if e.kind == "mk5" then
    local used, through = M.wallStop(e.radius, mat.nuke, dist)
    v.need = through and nil or used
    v.breached = through or used > thick
    if dist >= e.radius then v.need = 0; v.breached = false; v.outside = true end
    v.blastRange = dist <= e.blast
    if e.pulse and dist <= e.blast then
      v.dose = M.dose(dist, mat.rad * thick)
    end
  elseif e.sphere or e.kind == "balefire" then
    v.need = nil
    v.breached = dist <= e.radius
    v.outside = not v.breached
    v.blastRange = e.blast and dist <= e.blast or false
    if e.rinse and dist <= e.radius then
      v.dose = 15000 + (250000 - 15000) * (1 - dist / e.radius)
    end
  end
  return v
end

-- ── Formatting ────────────────────────────────────────────────────────
--- A number the way a person writes it: no trailing zeros, at most two
--- decimals, and a float's 16.0000019 shown as 16.
function M.num(x)
  if type(x) ~= "number" then return tostring(x) end
  if x == math.huge then return "inf" end
  local s = string.format("%.2f", x)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  if s == "-0" then s = "0" end
  return s
end

return M
