local bootsettings = {}

local bootcfg = require("kernel.bootcfg")

local AUTO = "auto"

function bootsettings.ramLabel(probe)
  local okH, hal = pcall(require, "kernel.hal")
  if not okH or not hal or not hal.ramSummary then return nil end
  local ok, hw = pcall(function()
    if probe then return probe() end
    local computer  = require("computer")
    local component = require("component")
    local totalKB = math.floor(((computer.totalMemory and computer.totalMemory()) or 0) / 1024)
    local modules = 0
    for _ in component.list("memory") do modules = modules + 1 end

    return { totalKB = totalKB, modules = modules, sticks = hal.ramSticks() }
  end)
  if not ok or type(hw) ~= "table" or (hw.totalKB or 0) <= 0 then return nil end
  return hal.ramSummary(hw.sticks, hw.totalKB, hw.modules)
end

local function buildFields(ramLabel)
  local fields = {
    { key = "profile", label = "Profile (what loads)", group = "basic",
      values = { "minimal", "normal", "full", "diagnostic", "safe" },
      get = function(c) return c.profile end,
      set = function(c, v) c.profile = v end,
      show = function(v) return (v == "safe") and "SAFE MODE" or v end },
    { key = "verbosity", label = "Verbosity (what it says)", group = "basic",
      values = { AUTO, "silent", "splash", "text", "verbose" },
      get = function(c) return c.verbosity or AUTO end,
      set = function(c, v) c.verbosity = (v == AUTO) and nil or v end,
      show = function(v) return v end },
    { key = "ui", label = "Interface (all seats)", group = "basic",
      values = { "home", "split", "cli" },
      get = function(c) return c.ui or "home" end,
      set = function(c, v) c.ui = (v == "home") and nil or v end,
      show = function(v)
        if v == "cli" then return "CLI shell" end
        if v == "split" then return "panels (split: Shell + Desktop)" end
        return "panels (Home: one tab, two views)"
      end },
    { key = "repair", label = "Self-repair next boot", group = "basic",
      values = { false, true },
      get = function(c) return c.repair == true end,
      set = function(c, v) c.repair = v end,
      show = function(v) return v and "RUN ONCE" or "off" end },
    { key = "showConfig", label = "Show this screen at boot", group = "basic",
      values = { true, false },
      get = function(c) return c.showConfig and true or false end,
      set = function(c, v) c.showConfig = v end,
      show = function(v) return v and "on" or "off" end },

    { key = "cpuTier", label = "CPU tier (override)", group = "advanced",
      values = { AUTO, 1, 2, 3 },
      get = function(c) return c.cpuTier or AUTO end,
      set = function(c, v) c.cpuTier = (v == AUTO) and nil or v end,
      show = function(v) return (v == AUTO) and "auto (detect)" or ("Tier " .. v) end },
    { key = "dataTier", label = "Data Card tier (override)", group = "advanced",
      values = { AUTO, 1, 2, 3 },
      get = function(c) return c.dataTier or AUTO end,
      set = function(c, v) c.dataTier = (v == AUTO) and nil or v end,
      show = function(v) return (v == AUTO) and "auto (detect)" or ("Tier " .. v) end },

    { key = "ramGate",
      label = ramLabel and ("RAM for extras [" .. ramLabel .. "]")
                        or "RAM for extras (override)",
      group = "advanced",
      values = { AUTO, true, false },
      get = function(c)
        if c.ramGate == nil then return AUTO end
        return c.ramGate
      end,
      set = function(c, v) c.ramGate = (v == AUTO) and nil or v end,
      show = function(v)
        if v == AUTO then return "auto (measure)" end
        return v and "always load" or "never load"
      end },
  }

  for _, feat in ipairs(bootcfg.FEATURES) do
    fields[#fields + 1] = {
      key = "adv." .. feat, label = "  + " .. feat, group = "advanced",
      values = { AUTO, true, false },
      get = function(c)
        local v = c.advanced and c.advanced[feat]
        if v == nil then return AUTO end
        return v
      end,
      set = function(c, v)
        c.advanced = c.advanced or {}
        c.advanced[feat] = (v == AUTO) and nil or v
      end,
      show = function(v)
        if v == AUTO then return "auto" end
        return v and "on" or "off"
      end,
    }
  end
  return fields
end

function bootsettings.fields(cfg, ramLabel)
  cfg = bootcfg._normalize(cfg or {})
  local out = {}
  for _, f in ipairs(buildFields(ramLabel)) do
    out[#out + 1] = { key = f.key, label = f.label, group = f.group,
      value = f.show(f.get(cfg)) }
  end
  return out
end

function bootsettings.cycle(cfg, idx, dir)
  local fields = buildFields()
  local f = fields[idx]
  if not f then return cfg end
  local cur = f.get(cfg)
  local ring = f.values
  local i = 1
  for k, v in ipairs(ring) do if v == cur then i = k break end end
  i = ((i - 1 + (dir or 1)) % #ring) + 1
  f.set(cfg, ring[i])
  return bootcfg._normalize(cfg)
end

function bootsettings.cycleKey(cfg, key, dir)
  local fields = buildFields()
  for i, f in ipairs(fields) do
    if f.key == key then return bootsettings.cycle(cfg, i, dir) end
  end
  return bootcfg._normalize(cfg)
end

local function visibleRows(cfg, showAdvanced, ramLabel)
  local rows = {}
  for _, f in ipairs(bootsettings.fields(cfg, ramLabel)) do
    if f.group == "basic" then rows[#rows + 1] = f end
  end
  if showAdvanced then
    rows[#rows + 1] = { header = true,
      label = "Advanced - boot overrides & manual device checks" }
    for _, f in ipairs(bootsettings.fields(cfg, ramLabel)) do
      if f.group == "advanced" then rows[#rows + 1] = f end
    end
  end
  return rows
end

local function stepSel(rows, sel, dir)
  local n = #rows
  for _ = 1, n do
    sel = ((sel - 1 + dir) % n) + 1
    if rows[sel] and not rows[sel].header then return sel end
  end
  return sel
end

function bootsettings.run(cfg, ctx)
  cfg = bootcfg._normalize(cfg or {})
  local sel = 1
  local scroll = 0
  local showHw = false
  local showAdvanced = false
  local col = ctx.color or function() return 0xFFFFFF end

  local hwInv, hwKey = nil, nil

  local ramLabel = bootsettings.ramLabel(ctx.ramProbe)

  while true do
    ctx.clear()
    ctx.set(2, 1, "TOS Boot Settings", col("title"))
    ctx.set(2, 2, "/etc/boot.cfg - applies on next boot", col("dim"))

    local rows = visibleRows(cfg, showAdvanced, ramLabel)
    if sel > #rows or (rows[sel] and rows[sel].header) then
      sel = stepSel(rows, 1, 0)
      if rows[sel] and rows[sel].header then sel = stepSel(rows, sel, 1) end
    end

    local hwRows = nil
    if showHw and ctx.sysinfo then
      local key = tostring(cfg.cpuTier) .. "/" .. tostring(cfg.dataTier)
      if not hwInv or hwKey ~= key then
        hwInv = ctx.sysinfo.gather(nil, { cpuTier = cfg.cpuTier, dataTier = cfg.dataTier })
        hwKey = key
      end
      hwRows = ctx.sysinfo.rows(hwInv)
    end

    local listTop = 4
    local H2 = ctx.H or 25
    local hwWant = hwRows and math.min(#hwRows + 1, math.floor(H2 / 2)) or 0
    local listH = (H2 - listTop + 1) - 3 - hwWant
    if listH < 4 then listH = 4 end
    if listH > #rows then listH = #rows end
    if sel - scroll > listH then scroll = sel - listH end
    if sel - scroll < 1 then scroll = math.max(0, sel - 1) end
    if scroll > #rows - listH then scroll = math.max(0, #rows - listH) end

    for i = 1, listH do
      local ri = scroll + i
      local f = rows[ri]
      if not f then break end
      local y = listTop + i - 1
      if f.header then
        ctx.set(2, y, "-- " .. f.label, col("title"))
      else
        local selFg = (ri == sel) and col("section") or col("dim")

        ctx.set(2, y, ((ri == sel and "> " or "  ") .. f.label):sub(1, 31), selFg)
        ctx.set(34, y, f.value, (ri == sel) and col("value") or col("dim"))
      end
    end

    if scroll > 0 then ctx.set(46, listTop, "^ more", col("title")) end
    if scroll + listH < #rows then
      ctx.set(46, listTop + listH - 1, "v more", col("title"))
    end

    local hy = listTop + listH + 1
    ctx.set(2, hy, "Up/Down: select   Left/Right or Space: change", col("dim"))
    ctx.set(2, hy + 1, ("[S] save   [R] save+reboot   [A] advanced %s   [H] hardware   [Q] cancel")
      :format(showAdvanced and "shown" or "hidden"), col("dim"))

    if hwRows then

      local ry = hy + 3
      for _, r in ipairs(hwRows) do
        if ry >= H2 then break end
        if r.role == "section" then
          ctx.set(2, ry, "-- " .. r.value, col("title"))
        else
          ctx.set(4, ry, (r.label ~= "" and (r.label .. ": ") or "  ") .. r.value,
            col(r.role))
        end
        ry = ry + 1
      end
    end

    local _, char, code = ctx.readKey()
    if code == 200 then
      sel = stepSel(rows, sel, -1)
    elseif code == 208 then
      sel = stepSel(rows, sel, 1)
    elseif code == 203 then
      if rows[sel] and rows[sel].key then bootsettings.cycleKey(cfg, rows[sel].key, -1) end
    elseif code == 205 or char == 32 then
      if rows[sel] and rows[sel].key then bootsettings.cycleKey(cfg, rows[sel].key, 1) end
    elseif char == 115 or char == 83 then
      return "save", cfg
    elseif char == 114 or char == 82 then
      return "reboot", cfg
    elseif char == 97 or char == 65 then
      showAdvanced = not showAdvanced
    elseif char == 104 or char == 72 then
      showHw = not showHw
    elseif char == 113 or char == 81 or code == 1 then
      return "cancel", cfg
    end
  end
end

return bootsettings
