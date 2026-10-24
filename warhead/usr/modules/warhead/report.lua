








local M = require("warhead.model")
local D = M.D
local num = M.num

local R = {}

R.ENGINE = {
  mk5 = "Nuclear blast (MK5)", fleija = "Antimatter sphere (MK3)",
  solinium = "Solinium rinse (MK3)", balefire = "Balefire",
  large = "Ordinary explosion", zomg = "Anti Mass", none = "Nothing",
}


R.CRATER_MATS = { "stone", "dirt", "concrete" }

local function mat(key)
  for _, m in ipairs(D.MATERIALS) do if m.key == key then return m end end
end
R.mat = mat


function R.lines(o, cfg, e)
  cfg = M.conf(cfg)
  e = e or M.effects(o, cfg)
  local out = {}
  local function add(t, tone) out[#out + 1] = { t, tone or "fg" } end

  if o.name then add(o.name, "title") end
  if o.ready == false then
    add("WILL NOT DETONATE. Missing:", "warn")
    for _, miss in ipairs(o.missing or {}) do
      if not miss.optional then
        add(string.format("  slot %d: %s", miss.slot, M.partName(miss.want)), "warn")
      end
    end
    return out
  end
  if o.fizzle then
    add(string.format("Fizzles to Fat Man's %d: its second stage is incomplete.", o.radius), "warn")
    for _, miss in ipairs(o.missing or {}) do
      if miss.optional then
        add(string.format("  slot %d wants %s", miss.slot, M.partName(miss.want)), "dim")
      end
    end
  end
  if o.charges and o.charges < 12 then
    add(string.format("%d of 12 charges loaded: %d%% of the full yield.", o.charges,
      math.floor(o.charges * 100 / 12)), "dim")
  end

  local kind = e.kind
  if kind == "none" then
    add("Nothing happens: no stage of this bomb is live.", "warn")
    return out
  end
  local head = R.ENGINE[kind] or kind
  if e.radius then head = head .. ", radius " .. e.radius
  elseif e.power then head = head .. ", power " .. num(e.power) end
  add(head, "hi")
  if o.formula and o.raw then
    local f = o.formula .. " = " .. num(o.raw)
    if o.cappedAt then f = f .. ", capped at " .. o.cappedAt end
    add(f, "dim")
  end

  if kind == "mk5" then
    local parts = {}
    for _, k in ipairs(R.CRATER_MATS) do
      local m = mat(k)
      local n, through = M.craterDepth(e.radius, m.nuke)
      parts[#parts + 1] = (through and ("all " .. n) or tostring(n)) .. " into " .. m.name:lower():match("^[%w]+")
    end
    add("Blocks    carved to " .. e.radius .. " through air; digs " .. table.concat(parts, ", "))
    add(string.format("Blast     hurts to %d in line of sight; one tick kills (20 HP) inside %d",
      e.blast, math.floor(e.lethal)))
    if e.pulse then
      
      add(string.format("Radiation 1000 RAD inside %d, 200 RAD inside %d (open air)",
        math.floor(e.death), math.floor(e.sick)))
    end
    if e.fallout then
      local f = "Fallout   rain out to " .. e.fallout
      if (e.falloutAdd or 0) > 0 then f = f .. " (+" .. e.falloutAdd .. " salted)" end
      if cfg.falloutRange ~= 100 then f = f .. " at falloutRange " .. cfg.falloutRange .. "%" end
      add(f)
      add("Mobs      within " .. num(e.glow) .. " may turn into Glowing Ones", "dim")
    end
  elseif kind == "fleija" then
    add("Sphere    every block within " .. e.radius .. " is deleted (bedrock-class excepted)")
    add(string.format("Blast     hurts to %d in line of sight; one tick kills (20 HP) inside %d",
      e.blast, math.floor(e.lethal)))
  elseif kind == "solinium" then
    add("Sphere    " .. e.radius .. ": everything alive takes 15,000-250,000 RAD a tick")
  elseif kind == "balefire" then
    add("Sphere    " .. e.radius .. " carved column by column and set alight")
    add(string.format("Blast     hurts to %d in line of sight; one tick kills (20 HP) inside %d",
      e.blast, math.floor(e.lethal)))
  elseif kind == "large" then
    add(string.format("Blocks    broken out to %s-%s in open air; hurts to %s",
      num(e.reachMin), num(e.reachMax), num(e.blast)))
  end
  for _, n in ipairs(e.notes) do add(n, "dim") end
  return out
end



function R.summary(o, cfg, e)
  cfg = M.conf(cfg)
  e = e or M.effects(o, cfg)
  local out = {}
  local function add(t, tone) out[#out + 1] = { t, tone or "fg" } end
  if e.kind == "none" then add("Nothing fires yet.", "warn"); return out end
  add((R.ENGINE[e.kind] or e.kind) .. (e.radius and (" r" .. e.radius) or ""), "hi")
  if o.formula and o.raw then
    add(o.formula .. " = " .. num(o.raw) .. (o.cappedAt and (" (cap " .. o.cappedAt .. ")") or ""), "dim")
  end
  if e.beams then add(e.beams .. " beams") end
  if e.radius then add("Destroyed   " .. e.radius) end
  if e.blast then add("Blast       " .. math.floor(e.blast) .. ", kills in " .. math.floor(e.lethal or 0)) end
  if e.fallout then
    add("Fallout     " .. e.fallout .. ((e.falloutAdd or 0) > 0 and (" (+" .. e.falloutAdd .. " salted)") or ""))
  elseif e.kind == "mk5" and not e.nuclear then
    add("Clean: no fallout", "dim")
  end
  if e.rinse then add("Kills all life inside it", "warn") end
  return out
end


function R.stageLines(v, info, cfg)
  cfg = M.conf(cfg)
  local out = {}
  for _, s in ipairs(D.STAGES) do
    local raw = info.raw[s] or 0
    if raw > 0 or v[s] > 0 then
      local line = string.format("%-11s %7s", D.STAGE_NAME[s], num(v[s]))
      local tone = "fg"
      if info.off[s] then line = line .. "  OFF"; tone = "warn"
      elseif info.capped[s] then line = line .. "  cap " .. info.capped[s]; tone = "dim" end
      if info.edge[s] then line = line .. "  (on the line)"; tone = "warn" end
      out[#out + 1] = { line, tone }
      if info.off[s] then out[#out + 1] = { "  " .. info.off[s], "dim" } end
    end
  end
  if #out == 0 then out[1] = { "(empty: put something in a slot)", "dim" } end
  return out
end


function R.shelterLines(v, m, e)
  local out = {}
  local function add(t, tone) out[#out + 1] = { t, tone or "fg" } end
  if v.outside then
    add(string.format("At %d blocks you are outside the destruction radius.", v.dist), "hi")
  elseif e.kind == "mk5" then
    if v.need == nil then
      add(m.name .. " cannot stop it short of the radius.", "warn")
    else
      add(string.format("%d block%s of %s stop%s it at %d out.", v.need, v.need == 1 and "" or "s",
        m.name, v.need == 1 and "s" or "", v.dist), v.breached and "warn" or "hi")
    end
    add(v.breached and string.format("Your %d block%s will NOT hold.", v.thick, v.thick == 1 and "" or "s")
      or string.format("Your %d block%s hold%s.", v.thick, v.thick == 1 and "" or "s",
        v.thick == 1 and "s" or ""), v.breached and "warn" or "hi")
  else
    add("Inside the sphere: no wall survives it.", "warn")
  end
  if v.blastRange then
    add("In blast range: only a wall between you and ground zero blocks the damage.", "dim")
  end
  if v.dose then
    local verdict = v.dose >= D.RAD_DEATH and "lethal" or (v.dose >= D.RAD_SICK and "sickening" or "survivable")
    add(string.format("Radiation behind it: %s RAD (%s)", num(v.dose), verdict),
      v.dose >= D.RAD_SICK and "warn" or "fg")
  end
  return out
end

return R
