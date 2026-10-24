




















local M = require("warhead.model")
local D = M.D

local B = {}




B.GOALS = {
  tnt    = { name = "Conventional (no fallout)", fires = "TNT",
             w = { TNT = 1 }, min = { TNT = 75 }, cap = "maxCustomTNTRadius" },
  nuke   = { name = "Fission", fires = "NUKE",
             w = { NUKE = 1, TNT = 1 / 2 }, min = { TNT = 16, NUKE = 0.0001 }, cap = "maxCustomNukeRadius" },
  hydro  = { name = "Thermonuclear", fires = "HYDRO",
             w = { HYDRO = 1, NUKE = 1 / 2, TNT = 1 / 4 }, min = { TNT = 16, NUKE = 100, HYDRO = 0.0001 },
             cap = "maxCustomHydroRadius" },
  bale   = { name = "Balefire", fires = "BALE",
             w = { BALE = 1, HYDRO = 1 / 2, NUKE = 1 / 4, TNT = 1 / 8 },
             min = { TNT = 16, NUKE = 50, BALE = 0.0001 }, cap = "maxCustomBaleRadius" },
  schrab = { name = "Antimatter (FLEIJA-type)", fires = "SCHRAB",
             w = { SCHRAB = 1, BALE = 1 / 2, HYDRO = 1 / 4, NUKE = 1 / 8, TNT = 1 / 16 },
             min = { TNT = 16, NUKE = 50, SCHRAB = 0.0001 }, cap = "maxCustomSchrabRadius" },
  sol    = { name = "Solinium (Blue Rinse)", fires = "SOL",
             w = { SOL = 1, SCHRAB = 1 / 2, BALE = 1 / 4, HYDRO = 1 / 8, NUKE = 1 / 16, TNT = 1 / 32 },
             min = { TNT = 16, NUKE = 25, SOL = 0.0001 }, cap = "maxCustomSolRadius" },
}
B.ORDER = { "tnt", "nuke", "hydro", "bale", "schrab", "sol" }





local function stageTable(stage, stock, nmax)
  local adds, muls = {}, {}
  for _, it in ipairs(D.INGREDIENTS) do
    if it.stage == stage then
      local have = stock and (stock[it.key] or 0) or nmax
      have = math.min(have, nmax)
      for _ = 1, have do
        if it.m then if it.v > 1 then muls[#muls + 1] = it end
        else adds[#adds + 1] = it end
      end
    end
  end
  table.sort(adds, function(a, b) return a.v > b.v end)
  table.sort(muls, function(a, b) return a.v > b.v end)
  
  local sumA, prodM = { [0] = 0 }, { [0] = 1 }
  for i, it in ipairs(adds) do sumA[i] = sumA[i - 1] + it.v end
  for i, it in ipairs(muls) do prodM[i] = prodM[i - 1] * it.v end
  local val, pick = { [0] = 0 }, { [0] = {} }
  for n = 1, nmax do
    local best, bestK = 0, nil
    for k = 0, math.min(n - 1, #muls) do
      local na = n - k
      if na <= #adds then
        local x = sumA[na] * prodM[k]
        if x > best + 1e-9 then best, bestK = x, k end
      end
    end
    val[n] = best
    if bestK then
      local items = {}
      for i = 1, n - bestK do items[#items + 1] = adds[i] end
      for i = 1, bestK do items[#items + 1] = muls[i] end
      pick[n] = items
    else
      val[n], pick[n] = val[n - 1], pick[n - 1]   
    end
  end
  return val, pick
end



local NUKE_GATE = { HYDRO = 100, BALE = 50, SCHRAB = 50, SOL = 25 }





local function allocate(goal, tables, cfg, slots, nukeMin)
  local stages = {}
  for _, s in ipairs(D.STAGES) do
    if goal.w[s] and (NUKE_GATE[s] or 0) <= nukeMin then
      stages[#stages + 1] = s
    end
  end
  local function minFor(s)
    local m = goal.min[s] or 0
    if s == "NUKE" then m = math.max(m, nukeMin) end
    return m
  end
  
  local dp, how = { [0] = {} }, {}
  for u = 0, slots do dp[0][u] = (u == 0) and 0 or nil end
  for i, s in ipairs(stages) do
    dp[i], how[i] = {}, {}
    local val = tables[s].val
    local cap = cfg[D.STAGE_CAP[s]]
    local need = minFor(s)
    for u = 0, slots do
      local best, bestN
      for n = 0, u do
        local prev = dp[i - 1][u - n]
        if prev ~= nil then
          local raw = val[n] or 0
          local live = (need <= 0) and true or (raw >= need)
          if n == 0 and need <= 0 then live = true end
          if live and (n == 0 or raw > 0) then
            local sum = prev + goal.w[s] * math.min(raw, cap)
            if best == nil or sum > best + 1e-9 then best, bestN = sum, n end
          end
        end
      end
      dp[i][u], how[i][u] = best, bestN
    end
  end
  local last = #stages
  local finalCap = cfg[goal.cap]
  local function result(u)
    local s = dp[last][u]
    if s == nil then return nil end
    return M.toInt(math.min(s, finalCap))
  end
  return {
    stages = stages, dp = dp, how = how, result = result,
    split = function(u)
      local out = {}
      for i = last, 1, -1 do
        local n = how[i][u]
        out[stages[i]] = n
        u = u - n
      end
      return out
    end,
  }
end


local function assemble(split, tables)
  local slots = {}
  for _, s in ipairs(D.STAGES) do
    local n = split[s] or 0
    if n > 0 then
      for _, it in ipairs(tables[s].pick[n]) do slots[#slots + 1] = it end
    end
  end
  return slots
end

local function evaluate(slots, cfg)
  local v, info = M.stages(slots, cfg)
  return M.customOutcome(v, cfg), v, info
end

local function sameBlast(a, b)
  return a.engine == b.engine and a.radius == b.radius and (a.falloutAdd or 0) == (b.falloutAdd or 0)
end



local function downgrade(slots, stock, cfg, want)
  local used = {}
  for _, it in ipairs(slots) do used[it.key] = (used[it.key] or 0) + 1 end
  local function available(it)
    if not stock then return true end
    return (stock[it.key] or 0) - (used[it.key] or 0) > 0
  end
  local byStage = {}
  for _, it in ipairs(D.INGREDIENTS) do
    byStage[it.stage] = byStage[it.stage] or {}
    table.insert(byStage[it.stage], it)
  end
  for _, list in pairs(byStage) do table.sort(list, function(a, b) return a.v < b.v end) end
  for i = 1, #slots do
    local cur = slots[i]
    for _, alt in ipairs(byStage[cur.stage]) do
      if alt.v >= cur.v then break end
      if alt.m == cur.m and available(alt) then
        slots[i] = alt
        if sameBlast(evaluate(slots, cfg), want) then
          used[cur.key] = used[cur.key] - 1
          used[alt.key] = (used[alt.key] or 0) + 1
          break
        end
        slots[i] = cur
      end
    end
  end
  
  local i = 1
  while i <= #slots do
    local it = table.remove(slots, i)
    if sameBlast(evaluate(slots, cfg), want) then
      used[it.key] = used[it.key] - 1
    else
      table.insert(slots, i, it)
      i = i + 1
    end
  end
  return slots
end






function B.design(goalKey, cfg, opts)
  opts = opts or {}
  cfg = M.conf(cfg)
  local goal = B.GOALS[goalKey]
  if not goal then return nil, "unknown kind of blast: " .. tostring(goalKey) end
  local slots = opts.slots or D.CUSTOM_SLOTS
  local tables = {}
  for _, s in ipairs(D.STAGES) do
    local val, pick = stageTable(s, opts.stock, slots)
    tables[s] = { val = val, pick = pick }
  end

  local runs = {}
  local base = goal.min.NUKE or 0
  local tiers = { base }
  if goal.w.NUKE then
    for _, t in ipairs({ 25, 50, 100 }) do if t > base then tiers[#tiers + 1] = t end end
  end
  for _, tier in ipairs(tiers) do
    runs[#runs + 1] = allocate(goal, tables, cfg, slots, tier)
  end

  local best
  for _, run in ipairs(runs) do
    
    local top
    for u = 0, slots do
      local r = run.result(u)
      if r and (top == nil or r > top) then top = r end
    end
    if top then
      local target = opts.radius and math.min(opts.radius, top) or top
      for u = 1, slots do
        local r = run.result(u)
        if r and r >= target then
          if not best or r > best.r or (r == best.r and u < best.u) then
            best = { r = r, u = u, run = run }
          end
          break
        end
      end
    end
  end
  if not best or best.r <= 0 then
    return nil, "the materials on hand cannot make a " .. goal.name:lower() .. " blast"
  end
  if opts.radius and best.r < opts.radius then
    best.short = true
  end

  local design = assemble(best.run.split(best.u), tables)
  local o = evaluate(design, cfg)
  if o.via ~= goal.fires or (goal.fires == "TNT" and o.engine ~= "mk5") then
    
    return nil, "no design clears the mod's thresholds with these materials"
  end
  design = downgrade(design, opts.stock, cfg, o)

  
  
  
  if opts.salt and (goal.fires == "NUKE" or goal.fires == "HYDRO") then
    local stock = opts.stock
    if stock then
      stock = {}
      for k, n in pairs(opts.stock) do stock[k] = n end
      for _, it in ipairs(design) do stock[it.key] = (stock[it.key] or 0) - 1 end
    end
    local room = slots - #design
    if room > 0 then
      local _, pick = stageTable("DIRTY", stock, room)
      for _, it in ipairs(pick[room] or {}) do design[#design + 1] = it end
    end
  end

  o = evaluate(design, cfg)
  local v = M.stages(design, cfg)
  return { slots = design, outcome = o, stages = v, short = best.short, goal = goal }
end



function B.designEuph(cfg, opts)
  opts = opts or {}
  cfg = M.conf(cfg)
  local slots = opts.slots or D.CUSTOM_SLOTS
  
  
  
  local base = {}
  local function cheapest(stage, need)
    local list = {}
    for _, it in ipairs(D.INGREDIENTS) do
      if it.stage == stage and not it.m then
        local have = opts.stock and (opts.stock[it.key] or 0) or slots
        for _ = 1, have do list[#list + 1] = it end
      end
    end
    table.sort(list, function(a, b) return a.v > b.v end)
    local sum, out = 0, {}
    for _, it in ipairs(list) do
      if sum >= need then break end
      out[#out + 1] = it; sum = sum + it.v
    end
    if sum < need then return nil end
    return out
  end
  for _, req in ipairs({ { "TNT", 16 }, { "NUKE", 50 }, { "SCHRAB", 1 }, { "SOL", 1 } }) do
    local got = cheapest(req[1], req[2])
    if not got then return nil, "not enough " .. D.STAGE_NAME[req[1]] .. " material to keep Anti Mass live" end
    for _, it in ipairs(got) do base[#base + 1] = it end
  end
  local euphs = {}
  for _, it in ipairs(D.INGREDIENTS) do
    if it.stage == "EUPH" then
      local have = opts.stock and (opts.stock[it.key] or 0) or slots
      for _ = 1, have do euphs[#euphs + 1] = it end
    end
  end
  table.sort(euphs, function(a, b) return a.key < b.key end)  
  local room = math.min(slots - #base, cfg.maxCustomEuphLvl)
  if room <= 0 or #euphs == 0 then return nil, "no Euphemium on hand" end
  for i = 1, math.min(room, #euphs) do base[#base + 1] = euphs[i] end
  local v = M.stages(base, cfg)
  local o = M.customOutcome(v, cfg)
  return { slots = base, outcome = o, stages = v, goal = { name = "Anti Mass", fires = "EUPH" } }
end

return B
