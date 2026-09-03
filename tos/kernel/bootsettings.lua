-- ╔═══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Boot Settings (the "DEL to enter setup" UI) ║
-- ║                                                           ║
-- ║  Edits /etc/boot.cfg: the boot spectrum (profile +        ║
-- ║  verbosity muter), the System Configuration screen        ║
-- ║  toggle, the CPU-tier confirmation, and the per-feature   ║
-- ║  advanced overrides. Reached two ways:                    ║
-- ║    • press DELETE during the boot POST screen, or         ║
-- ║    • run `bootsettings` from the shell if you missed it.  ║
-- ║                                                           ║
-- ║  The field MODEL (fields/cycle) is pure + unit-tested;    ║
-- ║  run() drives it through an abstract ctx so the same UI   ║
-- ║  works in early boot (raw GPU) and from the shell.        ║
-- ╚═══════════════════════════════════════════════════════════╝

local bootsettings = {}

local bootcfg = require("kernel.bootcfg")

-- "auto" sentinel for the value lists below — maps to nil in the config
-- (i.e. "follow the profile / let detection decide").
local AUTO = "auto"

-- ============================================================
-- Field model (pure)
-- ============================================================
-- Each field: { key, label, group, values, get(cfg), set(cfg,v), show(v) }.
-- `values` is the cycle ring; get/set translate config <-> a ring token.
-- `group` is "basic" (always shown) or "advanced" (behind the [A] toggle).
-- The split keeps the everyday choices (what loads / how loud / show this
-- screen) up front, and tucks the boot-overrides + manual device checks the
-- Operator rarely needs to touch out of the way until they ask for them.

--- Describe the machine's installed memory for the RAM field's label, e.g.
--- "2x T3.5". Returns nil when we can't tell (off-box unit tests, no
--- component API), in which case the field keeps its generic wording.
--- `probe` is injectable so the model stays testable without hardware.
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
    -- Per-stick capacities are what let mixed tiers be named honestly
    -- ("T3.5 + T2.5"); without them the summary reports capacity instead.
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
    -- Advanced: manual device checks (tell the boot what hardware to expect
    -- instead of trusting detection). Only genuinely-uncertain things are
    -- overridable — CPU/Data Card tier are heuristics, and RAM *headroom*
    -- is a judgement call. GPU/screen/modem are reliably detected, so
    -- TOS deliberately offers no override for them.
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
    -- The label names the memory ACTUALLY installed ("RAM for extras
    -- [2x T3.5]") rather than leaving the operator to guess what the old
    -- "plenty"/"tight" wording meant on their box — those words described
    -- the override's effect, not the hardware, and "plenty" told you nothing
    -- about whether you had one T2 stick or two T3.5s. The values now say
    -- plainly what the override DOES; the hardware answer lives in the label,
    -- so it stays visible whichever way the setting is cycled.
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
  -- Advanced: boot overrides — one toggle per optional feature
  -- (auto = follow the profile).
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

--- Return the editable fields with their current display values for `cfg`.
--- @return array of { key, label, group, value(display string) }
--- @param ramLabel string|nil  installed-memory summary for the RAM row's
---   label (see bootsettings.ramLabel). Omitted → generic wording, which is
---   what the pure field-model tests exercise.
function bootsettings.fields(cfg, ramLabel)
  cfg = bootcfg._normalize(cfg or {})
  local out = {}
  for _, f in ipairs(buildFields(ramLabel)) do
    out[#out + 1] = { key = f.key, label = f.label, group = f.group,
      value = f.show(f.get(cfg)) }
  end
  return out
end

--- Advance field #idx of `cfg` by `dir` (+1/-1) through its value ring.
--- Mutates and returns `cfg`. Out-of-range idx is a no-op.
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

--- Advance the field whose key is `key` by `dir`. Lets the runner cycle a
--- field by identity, so the visible (filtered basic/advanced) list never
--- has to map its row back to a full-list index. No-op on unknown key.
function bootsettings.cycleKey(cfg, key, dir)
  local fields = buildFields()
  for i, f in ipairs(fields) do
    if f.key == key then return bootsettings.cycle(cfg, i, dir) end
  end
  return bootcfg._normalize(cfg)
end

-- ============================================================
-- Interactive runner (ctx-driven)
-- ============================================================
-- ctx = {
--   clear  = function() end,                       wipe screen
--   set    = function(x, y, text, fg, bg) end,     draw text
--   readKey= function() return name, char, code end, block for a key_down
--   color  = function(role) return rgb end,        role -> color
--   sysinfo = <kernel.sysinfo or nil>,             optional H/W view
--   W, H,
-- }
-- Returns (action, cfg) where action is "save" | "reboot" | "cancel".
-- Build the list of rows the runner actually draws: the basic fields, plus
-- (when expanded) an "Advanced" header sentinel followed by the advanced
-- fields. Header rows carry no `key` and are skipped by selection/cycling.
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

-- First/next/prev *selectable* row index (skips the Advanced header).
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
  -- #FIX — cache the hardware inventory. sysinfo.gather() probes every
  -- component (slow); re-running it on EVERY keystroke made cursor movement
  -- crawl while the hardware view was open. Re-gather ONLY when the view is
  -- first opened or when a tier override actually changes (the only inputs
  -- that affect it), keyed below.
  local hwInv, hwKey = nil, nil
  -- Installed-memory summary for the RAM row's label. Probed ONCE (it can't
  -- change while the machine is running) and never re-read in the draw loop.
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

    -- Hardware inventory first: the SETTINGS list is what shrinks when
    -- space runs out (operator request) — so the hw view's row count
    -- must be known before the list height is budgeted.
    local hwRows = nil
    if showHw and ctx.sysinfo then
      local key = tostring(cfg.cpuTier) .. "/" .. tostring(cfg.dataTier)
      if not hwInv or hwKey ~= key then
        hwInv = ctx.sysinfo.gather(nil, { cpuTier = cfg.cpuTier, dataTier = cfg.dataTier })
        hwKey = key
      end
      hwRows = ctx.sysinfo.rows(hwInv)
    end

    -- Budget: rows 1-2 header, list from row 4, then 1 gap + 2 help
    -- lines, then (optionally) 1 gap + the hardware view. The list gets
    -- whatever is left, scrolls to keep the selection visible, and
    -- never drops below 4 rows (the hw view truncates at H instead).
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
        -- Clip the label so it can't run into the value column at x=34.
        ctx.set(2, y, ((ri == sel and "> " or "  ") .. f.label):sub(1, 31), selFg)
        ctx.set(34, y, f.value, (ri == sel) and col("value") or col("dim"))
      end
    end
    -- Scroll markers: plain ASCII so this pre-theme screen stays safe.
    if scroll > 0 then ctx.set(46, listTop, "^ more", col("title")) end
    if scroll + listH < #rows then
      ctx.set(46, listTop + listH - 1, "v more", col("title"))
    end

    local hy = listTop + listH + 1
    ctx.set(2, hy, "Up/Down: select   Left/Right or Space: change", col("dim"))
    ctx.set(2, hy + 1, ("[S] save   [R] save+reboot   [A] advanced %s   [H] hardware   [Q] cancel")
      :format(showAdvanced and "shown" or "hidden"), col("dim"))

    if hwRows then
      -- The System Configuration viewer on the lower half, from the
      -- cached inventory (re-gathered only when a tier override changed).
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
    if code == 200 then           -- up
      sel = stepSel(rows, sel, -1)
    elseif code == 208 then       -- down
      sel = stepSel(rows, sel, 1)
    elseif code == 203 then       -- left
      if rows[sel] and rows[sel].key then bootsettings.cycleKey(cfg, rows[sel].key, -1) end
    elseif code == 205 or char == 32 then  -- right / space
      if rows[sel] and rows[sel].key then bootsettings.cycleKey(cfg, rows[sel].key, 1) end
    elseif char == 115 or char == 83 then  -- s / S
      return "save", cfg
    elseif char == 114 or char == 82 then  -- r / R
      return "reboot", cfg
    elseif char == 97 or char == 65 then  -- a / A — reveal/hide advanced
      showAdvanced = not showAdvanced
    elseif char == 104 or char == 72 then  -- h / H
      showHw = not showHw
    elseif char == 113 or char == 81 or code == 1 then  -- q / Q / Esc
      return "cancel", cfg
    end
  end
end

return bootsettings
