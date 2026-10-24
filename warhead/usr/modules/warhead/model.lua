














local D = require("warhead.data")

local M = {}
M.D = D







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

local function toInt(x)
  if x >= 0 then return floor(x) end
  return -floor(-x)
end
M.toInt = toInt



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






function M.conf(cfg)
  if type(cfg) == "table" and cfg.falloutRange ~= nil then return cfg end
  return M.config()
end


M.byKey = {}
M.byItem = {}
for _, it in ipairs(D.INGREDIENTS) do
  M.byKey[it.key] = it
  M.byItem[it.id .. (it.dmg and ("#" .. it.dmg) or "")] = it
end





function M.lookup(id, dmg)
  if type(id) ~= "string" then return nil end
  local hit = dmg and M.byItem[id .. "#" .. tostring(toInt(dmg))]
  return hit or M.byItem[id]
end


local function asIngredient(x)
  if type(x) == "table" then return x end
  if type(x) == "string" then return M.byKey[x] end
  return nil
end
M.asIngredient = asIngredient
















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








local function lut(ri, di)
  local r = f32(f32(f32(ri) / f32(255)) * f32(100))
  local d = f32(f32(di) / f32(255))
  return f32((r + 1) ^ (3 * d) - 1)
end





function M.lossFactor(res, t)
  res = f32(res)
  if res >= 2000000 then return res end
  if res <= 0 then return 0 end
  if res > 100 then return (res + 1) ^ (3 * t) - 1 end
  local ri = toInt(f32(f32(res * f32(255)) / f32(100)))
  if ri == 0 then return (res + 1) ^ (3 * t) - 1 end
  return lut(ri, toInt(t * 255))
end










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


function M.craterDepth(radius, res)
  return M.ray(radius, function(k) if k == 0 then return nil end return res end)
end



function M.wallStop(radius, res, dist)
  return M.ray(radius, function(k) if k >= dist then return res end return nil end)
end




local K = 0
for t = 2, 9 do K = K + 1 / (5 * t + 1) end
M.PULSE = 2500000 * K   




function M.dose(d, shield)
  if d <= 0 then return math.huge end
  return M.PULSE / math.max(1, shield or 0) / (d * d)
end


function M.doseRadius(rads) return math.sqrt(M.PULSE / rads) end




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
    if r == 0 then r = 25 end      
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




function M.num(x)
  if type(x) ~= "number" then return tostring(x) end
  if x == math.huge then return "inf" end
  local s = string.format("%.2f", x)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  if s == "-0" then s = "0" end
  return s
end

return M
