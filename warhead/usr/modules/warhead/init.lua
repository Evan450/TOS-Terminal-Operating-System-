













local component = require("component")
local computer  = require("computer")
local M = require("warhead.model")
local R = require("warhead.report")
local D = M.D
local num = M.num

local W = {}   





local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function isQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return ch == 17 or code == 68 or code == 1
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "^Q"
end
local K = { ENTER = 28, BACK = 14, DEL = 211, TAB = 15, UP = 200, DOWN = 208,
            LEFT = 203, RIGHT = 205, PGUP = 201, PGDN = 209, HOME = 199, END = 207 }


local function ulen(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
  end
  return n
end
local function usub(s, a, b)
  local starts, n = {}, 0
  for i = 1, #s do
    local by = s:byte(i)
    if by < 0x80 or by >= 0xC0 then n = n + 1; starts[n] = i end
  end
  starts[n + 1] = #s + 1
  a, b = math.max(1, a), math.min(n, b)
  if a > b then return "" end
  return s:sub(starts[a], starts[b + 1] - 1)
end
local function pad(s, n)
  s = tostring(s or "")
  local w = ulen(s)
  if w > n then return usub(s, 1, n) end
  return s .. string.rep(" ", n - w)
end
W.ulen, W.pad = ulen, pad




function W.fitKeys(hints, out, width)
  local sep = " \194\183 "
  local kept = {}
  for _, h in ipairs(hints) do
    kept[#kept + 1] = h
    if ulen(table.concat(kept, sep) .. sep .. out) > width then kept[#kept] = nil; break end
  end
  if #kept == 0 then return out end
  return table.concat(kept, sep) .. sep .. out
end



function W.wrap(text, width)
  if ulen(text) <= width then return { text } end
  local indent, body = 0, text
  local lead = text:match("^(%u%l+ +)%S")
  if lead and #lead <= 12 then
    
    
    
    indent = math.min(#lead, math.floor(width / 4))
    body = text:sub(#lead + 1)
  else
    lead = nil
  end
  local out, line = {}, lead or ""
  local fresh = true
  for word in body:gmatch("%S+") do
    local cand = fresh and (line .. word) or (line .. " " .. word)
    if ulen(cand) > width and not fresh then
      out[#out + 1] = line
      line = string.rep(" ", indent) .. word
    else
      line = cand
    end
    fresh = false
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end











local SETTINGS_FILE = ".warhead"

function W.newSettings() return { cfg = {}, designs = {}, order = {}, places = {} } end

function W.parseSettings(text)
  local st = W.newSettings()
  if type(text) ~= "string" then return st end
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local k, v = line:match("^cfg (%S+) (%S+)$")
    if k and D.CONFIG[k] ~= nil then
      if D.CONFIG_BOOL[k] then st.cfg[k] = (v == "true")
      else st.cfg[k] = tonumber(v) end
    end
    local name, list = line:match("^design ([^\t]+)\t(.*)$")
    if name then
      local slots = {}
      local i = 0
      for field in (list .. ","):gmatch("([^,]*),") do
        i = i + 1
        if i > D.CUSTOM_SLOTS then break end
        if field ~= "-" and field ~= "" and (M.byKey[field] or field == D.DROP_UPGRADE.key) then
          slots[i] = field
        end
      end
      if not st.designs[name] then st.order[#st.order + 1] = name end
      st.designs[name] = slots
    end
    local dx, dz, pname = line:match("^place (%-?%d+) (%-?%d+) (.+)$")
    if dx then st.places[#st.places + 1] = { dx = tonumber(dx), dz = tonumber(dz), name = pname } end
  end
  return st
end

function W.serializeSettings(st)
  local lines = { "WARHEAD1" }
  local keys = {}
  for k in pairs(st.cfg) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do lines[#lines + 1] = "cfg " .. k .. " " .. tostring(st.cfg[k]) end
  for _, name in ipairs(st.order) do
    local slots = st.designs[name]
    if slots then
      local f = {}
      for i = 1, D.CUSTOM_SLOTS do
        local x = slots[i]
        f[i] = (type(x) == "table" and x.key) or x or "-"
      end
      lines[#lines + 1] = "design " .. name .. "\t" .. table.concat(f, ",")
    end
  end
  for _, p in ipairs(st.places) do
    lines[#lines + 1] = string.format("place %d %d %s", p.dx, p.dz, p.name)
  end
  return table.concat(lines, "\n") .. "\n"
end

local function settingsPath()
  if not (fs and fs.home) then return nil end
  local okH, home = pcall(fs.home)
  if not okH or type(home) ~= "string" or home == "/tmp" then return nil end
  return home .. "/" .. SETTINGS_FILE
end

local function loadSettings()
  local p = settingsPath()
  if p and fs.exists and fs.exists(p) then
    local okR, data = pcall(fs.readFile, p)
    if okR and type(data) == "string" then return W.parseSettings(data) end
  end
  return W.newSettings()
end

local function saveSettings(st)
  local p = settingsPath()
  if not p or not fs.writeFile then return false, "no home directory to save in" end
  local okW, err = pcall(fs.writeFile, p, W.serializeSettings(st))
  if not okW or err == false then return false, tostring(err) end
  return true
end



function W.cleanName(s)
  s = tostring(s or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if ulen(s) > 24 then s = usub(s, 1, 24) end
  return s
end




function W.catalogue()
  local list = { { group = "Custom Nuke", kind = "custom", key = "custom", name = "Custom Nuke (designer)" } }
  for _, b in ipairs(D.BOMBS) do list[#list + 1] = { group = "Bombs", kind = "bomb", key = b.key, name = b.name, ref = b } end
  for _, m in ipairs(D.MISSILES) do list[#list + 1] = { group = "Missiles", kind = "missile", key = m.key, name = m.name, ref = m } end
  for _, m in ipairs(D.WARHEADS) do list[#list + 1] = { group = "Missile warheads", kind = "missile", key = m.key, name = m.name, ref = m } end
  return list
end


function W.find(what)
  if type(what) ~= "string" or what == "" then return nil end
  local q = what:lower()
  local list = W.catalogue()
  for _, e in ipairs(list) do if e.key == q then return e end end
  for _, e in ipairs(list) do if e.name:lower() == q then return e end end
  for _, e in ipairs(list) do if e.name:lower():find(q, 1, true) then return e end end
  return nil
end


function W.outcome(entry, cfg, slots)
  if entry.kind == "custom" then
    local v, info = M.stages(slots or {}, cfg)
    local o = M.customOutcome(v, cfg)
    o.name = "Custom Nuke"
    o.fall = info.fall
    return o, v, info
  elseif entry.kind == "bomb" then
    return M.bombOutcome(entry.ref, cfg)
  end
  return M.missileOutcome(entry.ref, cfg)
end




local function inventory()
  local okI, inv = pcall(require, "peripheral.inventory")
  if not okI or type(inv) ~= "table" or not inv.sides then
    return nil, "no transposer or inventory controller attached"
  end
  if inv.available and not inv.available() then
    return nil, "no transposer or inventory controller attached"
  end
  return inv
end

local SIDE_NAMES = { bottom = 0, down = 0, top = 1, up = 1, north = 2, south = 3, west = 4, east = 5 }

local function readSide(inv, side)
  local stacks, err = inv.stacks(side)
  if not stacks then return nil, err end
  local contents = {}
  for _, st in ipairs(stacks) do
    contents[st.slot] = { id = st.id, dmg = st.damage, count = st.count, label = st.label }
  end
  return contents
end




function W.identify(size, contents)
  if size == D.CUSTOM_SLOTS then return W.find("custom") end
  local best, bestScore
  for _, b in ipairs(D.BOMBS) do
    if b.slots == size then
      local score = 0
      for s, want in ipairs(b.parts or {}) do if M.partMatches(want, contents[s]) then score = score + 1 end end
      for s, want in pairs(b.filled or {}) do if M.partMatches(want, contents[s]) then score = score + 1 end end
      if b.perCharge then
        for s = 1, b.slots do if M.partMatches(b.perCharge, contents[s]) then score = score + 1 end end
      end
      if not bestScore or score > bestScore then best, bestScore = b, score end
    end
  end
  if not best then return nil end
  return W.find(best.key)
end



function W.slotsFromContents(contents)
  local slots, unknown = {}, {}
  for s = 1, D.CUSTOM_SLOTS do
    local c = contents[s]
    if c then
      local it = M.lookup(c.id, c.dmg)
      if it then slots[s] = it.key
      elseif c.id == D.DROP_UPGRADE.id then slots[s] = D.DROP_UPGRADE.key
      else unknown[#unknown + 1] = { slot = s, label = c.label or c.id } end
    end
  end
  return slots, unknown
end


function W.stockFromContents(contents)
  local stock, n = {}, 0
  for _, c in pairs(contents) do
    local it = M.lookup(c.id, c.dmg)
    if it then
      stock[it.key] = (stock[it.key] or 0) + (c.count or 1)
      n = n + 1
    end
  end
  return stock, n
end

local function resolveSide(inv, arg)
  local sides = inv.sides()
  if #sides == 0 then return nil, "nothing to read on any side" end
  if arg then
    local want = SIDE_NAMES[arg:lower()] or tonumber(arg)
    for _, s in ipairs(sides) do if s.side == want then return s end end
    return nil, "no inventory on side " .. arg
  end
  return sides
end




local TONE = { title = 0xFFFF55, fg = 0xFFFFFF, dim = 0xAAAAAA, hi = 0x55FF55, warn = 0xFF5555 }
local function printLines(o, lines)
  for _, l in ipairs(lines) do o(l[1], TONE[l[2]] or 0xFFFFFF) end
end

local function goalKeys()
  local B = require("warhead.best")
  local keys = {}
  for _, g in ipairs(B.ORDER) do keys[#keys + 1] = g end
  keys[#keys + 1] = "euph"
  return keys, B
end

local function designLines(d)
  local out = {}
  local count, order = {}, {}
  for _, it in ipairs(d.slots) do
    local k = type(it) == "table" and it.key or it
    if not count[k] then order[#order + 1] = k end
    count[k] = (count[k] or 0) + 1
  end
  for _, k in ipairs(order) do
    local it = M.byKey[k]
    local name = it and it.name or D.DROP_UPGRADE.name
    out[#out + 1] = { string.format("  %2d x %s", count[k], name), "fg" }
  end
  out[#out + 1] = { string.format("  %d of %d slots. One item per slot is enough; stacks count once.",
    #d.slots, D.CUSTOM_SLOTS), "dim" }
  return out
end

local function cliHelp(o)
  o("warhead — HBM Nuclear Tech nuke designer and simulator (" .. D.SOURCE .. ")", TONE.title)
  o("  warhead                         the full-screen simulator", TONE.fg)
  o("  warhead list                    every warhead it knows", TONE.fg)
  o("  warhead sim <name>              what one would do (e.g. warhead sim tsar)", TONE.fg)
  o("  warhead best <kind> [radius N] [salt] [stock <side>]", TONE.fg)
  o("                                  design the best custom nuke", TONE.dim)
  o("        kinds: tnt nuke hydro bale schrab sol euph", TONE.dim)
  o("  warhead scan [side]             read a bomb next to a transposer", TONE.fg)
  o("  warhead shelter <name> <dist> <material> [thick]", TONE.fg)
  o("  warhead materials               what a shelter can be built from", TONE.fg)
  o("  warhead config [set K V | reset [K]]   your server's hbm.cfg values", TONE.fg)
end

local function cliConfig(args, o, st)
  local sub = args[2]
  if sub == "set" then
    local k, v = args[3], args[4]
    if not k or D.CONFIG[k] == nil then o("Unknown key: " .. tostring(k), TONE.warn); return end
    if D.CONFIG_BOOL[k] then
      if v ~= "true" and v ~= "false" then o(k .. " is true or false.", TONE.warn); return end
      st.cfg[k] = (v == "true")
    else
      local n = tonumber(v)
      if not n or n < 0 then o(k .. " needs a number.", TONE.warn); return end
      st.cfg[k] = n
    end
    local okS, err = saveSettings(st)
    o(okS and ("Set " .. k .. " = " .. tostring(st.cfg[k])) or ("Not saved: " .. tostring(err)),
      okS and TONE.hi or TONE.warn)
    return
  elseif sub == "reset" then
    if args[3] then st.cfg[args[3]] = nil else st.cfg = {} end
    local okS, err = saveSettings(st)
    o(okS and "Reset." or ("Not saved: " .. tostring(err)), okS and TONE.hi or TONE.warn)
    return
  end
  local cfg = M.config(st.cfg)
  local keys = {}
  for k in pairs(D.CONFIG) do keys[#keys + 1] = k end
  table.sort(keys)
  o("Config (" .. D.SOURCE .. " defaults; * = yours):", TONE.title)
  for _, k in ipairs(keys) do
    o(string.format("  %-22s %-8s%s", k, tostring(cfg[k]), st.cfg[k] ~= nil and " *" or ""),
      st.cfg[k] ~= nil and TONE.hi or TONE.fg)
  end
end

local function cliScan(args, o, cfg)
  local inv, err = inventory()
  if not inv then o("Cannot scan: " .. err .. ".", TONE.warn); return end
  local sides, sErr = resolveSide(inv, args[2])
  if not sides then o("Cannot scan: " .. sErr .. ".", TONE.warn); return end
  if sides.side then sides = { sides } end
  local found = 0
  for _, s in ipairs(sides) do
    local contents = readSide(inv, s.side)
    local entry = contents and W.identify(s.size, contents)
    if entry then
      found = found + 1
      o(string.format("%s side (%d slots): %s", s.name, s.size, entry.name), TONE.title)
      local oc
      if entry.kind == "custom" then
        local slots, unknown = W.slotsFromContents(contents)
        local v
        oc, v = W.outcome(entry, cfg, slots)
        if oc.fall then o("  Has the Drop Upgrade: it falls, then goes off where it lands.", TONE.dim) end
        for _, u in ipairs(unknown) do
          o(string.format("  slot %d holds %s, which adds nothing", u.slot, u.label), TONE.dim)
        end
      else
        oc = M.bombOutcome(entry.ref, cfg, contents)
      end
      printLines(o, R.lines(oc, cfg))
      o("", TONE.fg)
    end
  end
  if found == 0 then o("No HBM bomb found next to the transposer.", TONE.warn) end
end

local function cliBest(args, o, cfg)
  local keys, B = goalKeys()
  local goal = args[2]
  local known = false
  for _, k in ipairs(keys) do if k == goal then known = true end end
  if not known then
    o("Which kind of blast? " .. table.concat(keys, " "), TONE.warn)
    for _, g in ipairs(B.ORDER) do o(string.format("  %-7s %s", g, B.GOALS[g].name), TONE.dim) end
    o("  euph    Anti Mass (beams)", TONE.dim)
    return
  end
  local opts = {}
  local i = 3
  while args[i] do
    local a = args[i]
    if a == "radius" then opts.radius = tonumber(args[i + 1]); i = i + 1
    elseif a == "salt" then opts.salt = true
    elseif a == "stock" then
      local inv, err = inventory()
      if not inv then o("Cannot read stock: " .. err .. ".", TONE.warn); return end
      local side, sErr = resolveSide(inv, args[i + 1])
      if not side or not side.side then o("Name the chest's side: stock <side>.", TONE.warn); return end
      local contents = readSide(inv, side.side)
      local n
      opts.stock, n = W.stockFromContents(contents or {})
      o(string.format("Designing from the %s chest (%d ingredient stacks).", side.name, n), TONE.dim)
      i = i + 1
    end
    i = i + 1
  end
  local d, err
  if goal == "euph" then d, err = B.designEuph(cfg, opts) else d, err = B.design(goal, cfg, opts) end
  if not d then o("No design: " .. tostring(err) .. ".", TONE.warn); return end
  o("Best " .. d.goal.name:lower() .. " custom nuke:", TONE.title)
  printLines(o, designLines(d))
  if d.short then o("It cannot reach radius " .. opts.radius .. "; this is the most it can do.", TONE.warn) end
  local oc = d.outcome
  oc.name = nil
  printLines(o, R.lines(oc, cfg))
end

local function cliShelter(args, o, cfg, st)
  local entry = W.find(args[2] or "")
  local dist, matKey, thick = tonumber(args[3] or ""), args[4], tonumber(args[5] or "3")
  if not entry or not dist or not matKey then
    o("Usage: warhead shelter <name> <distance> <material> [thickness]", TONE.warn)
    o("  e.g. warhead shelter tsar 120 concrete 4      (materials: warhead materials)", TONE.dim)
    return
  end
  local m = R.mat(matKey)
  if not m then o("Unknown material: " .. matKey .. " (see warhead materials).", TONE.warn); return end
  local oc = W.outcome(entry, cfg, st.designs[st.order[1] or ""])
  local e = M.effects(oc, cfg)
  o(string.format("%s, %s wall %d thick at %d blocks:", entry.name, m.name, thick, dist), TONE.title)
  printLines(o, R.shelterLines(M.shelter(oc, e, m, dist, thick), m, e))
end

local function cliMain(args, o)
  local st = loadSettings()
  local cfg = M.config(st.cfg)
  local sub = args[1]
  if sub == "help" or sub == "-h" or sub == "--help" then cliHelp(o)
  elseif sub == "list" then
    local last
    for _, e in ipairs(W.catalogue()) do
      if e.group ~= last then o(e.group, TONE.title); last = e.group end
      local line = string.format("  %-18s %s", e.key, e.name)
      if e.kind ~= "custom" then
        local oc = W.outcome(e, cfg)
        line = line .. "  -  " .. (R.ENGINE[oc.engine] or oc.engine)
          .. (oc.radius and (" r" .. oc.radius) or (oc.power and (" power " .. num(oc.power)) or ""))
      end
      o(line, TONE.fg)
    end
  elseif sub == "sim" then
    local what = table.concat(args, " ", 2)
    if what:match("^design ") or st.designs[what] then
      local name = st.designs[what] and what or what:gsub("^design ", "")
      local slots = st.designs[name]
      if not slots then o("No saved design called " .. name .. ".", TONE.warn); return end
      local oc = W.outcome(W.find("custom"), cfg, slots)
      oc.name = "Custom Nuke \"" .. name .. "\""
      printLines(o, R.lines(oc, cfg))
      return
    end
    local e = W.find(what)
    if not e or e.kind == "custom" then
      o("Which warhead? `warhead list` shows them; a saved design is `warhead sim design <name>`.", TONE.warn)
      return
    end
    printLines(o, R.lines(W.outcome(e, cfg), cfg))
  elseif sub == "best" then cliBest(args, o, cfg)
  elseif sub == "scan" then cliScan(args, o, cfg)
  elseif sub == "shelter" then cliShelter(args, o, cfg, st)
  elseif sub == "materials" then
    o("Material             nuke  radiation   (resistance; see README)", TONE.title)
    for _, m in ipairs(D.MATERIALS) do
      o(string.format("  %-10s %-24s %8s %8s", m.key, m.name, num(m.nuke), num(m.rad)), TONE.fg)
    end
  elseif sub == "config" then cliConfig(args, o, st)
  else
    return false   
  end
  return true
end




local function screen(o)
  local gpuAddr = component.list and component.list("gpu")()
  if not gpuAddr then return nil, "no GPU" end
  local okG, gpu = pcall(component.proxy, gpuAddr)
  if not okG or not gpu then return nil, "cannot open the GPU" end
  local Wd, Ht = gpu.getResolution()
  if not Wd or Wd < 80 or Ht < 24 then
    return nil, string.format("the full screen needs 80x24 (this one is %sx%s)", tostring(Wd), tostring(Ht))
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number") and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, bg = 0x000000, border = 0xFFFFFF, title = 0xFFFFFF,
    hi = 0xFFFFFF, warn = 0xFFFFFF, selfg = 0x000000, selbg = 0xFFFFFF,
    r1 = 0xFFFFFF, r2 = 0xFFFFFF, r3 = 0xFFFFFF, r4 = 0xFFFFFF,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA, bg = 0x000000,
    border = tier == 2 and 0x55FFFF or 0x00FFFF, title = tier == 2 and 0xFFFF55 or 0xFFFF00,
    hi = tier == 2 and 0x55FF55 or 0x00FF00, warn = tier == 2 and 0xFF5555 or 0xFF4040,
    selfg = 0x000000, selbg = tier == 2 and 0x55FFFF or 0x00FFFF,
    
    r1 = tier == 2 and 0xFF5555 or 0xFF3030, r2 = tier == 2 and 0xFFAA00 or 0xFF8000,
    r3 = tier == 2 and 0xFFFF55 or 0xFFE040, r4 = tier == 2 and 0x55FF55 or 0x80C040,
  }
  local S = { W = Wd, H = Ht, tier = tier, T = T, gpu = gpu, mono = tier == 1 }
  function S.set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  function S.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  return S
end

local function pullKey()
  local e = { computer.pullSignal() }
  if e[1] == "key_down" then return e[3], e[4], e[1] end
  if e[1] == "interrupted" then return 17, nil, e[1] end
  return nil, nil, e[1]
end

local function ui(o)
  local S, why = screen(o)
  if not S then
    o("warhead: " .. why .. ". The commands still work: warhead help", 0xFF6600)
    return
  end
  local T, Wd, Ht = S.T, S.W, S.H
  local st = loadSettings()
  local cfg = M.config(st.cfg)
  local B   

  local cat = W.catalogue()
  local sel, listTop = 1, 1
  local view = "list"
  local status, statusTone = nil, "hi"
  local design = {}          
  local designName = nil
  local cur = 1               
  local shelterDist, shelterMat, shelterThick = 50, 11, 3   
  for i, m in ipairs(D.MATERIALS) do if m.key == "concrete" then shelterMat = i end end

  local function say(msg, tone) status, statusTone = msg, tone or "hi" end
  local function tone(t) return T[t] or T.fg end

  local BODY_TOP, BODY_BOT = 3, Ht - 2

  local back = "list"        

  
  
  
  local function current()
    local fromDesign = view == "design" or ((view == "map" or view == "shelter") and back == "design")
    local entry = fromDesign and cat[1] or cat[sel]
    local oc, v, info = W.outcome(entry, cfg, design)
    if entry.kind == "custom" then
      oc.name = designName and ("Custom Nuke \"" .. designName .. "\"") or "Custom Nuke"
    end
    return oc, M.effects(oc, cfg), v, info, entry
  end

  
  local function header(title)
    S.fill(1, 1, Wd, 1, " ", T.bg, T.border)
    S.set(2, 1, pad("WARHEAD  " .. title, Wd - 30), T.bg, T.border)
    local right = D.SOURCE .. (next(st.cfg) and " +config" or "")
    S.set(Wd - ulen(right), 1, right, T.bg, T.border)
    S.fill(1, 2, Wd, 1, S.mono and "-" or "─", T.dim, T.bg)
  end

  local function footer(keys)
    S.fill(1, Ht - 1, Wd, 1, " ", T.fg, T.bg)
    if status then S.set(2, Ht - 1, pad(status, Wd - 2), tone(statusTone), T.bg) end
    S.fill(1, Ht, Wd, 1, " ", T.bg, T.border)
    S.set(2, Ht, pad(W.fitKeys(keys, quitLabel() .. " " .. (view == "list" and "Quit" or "Back"), Wd - 2),
      Wd - 2), T.bg, T.border)
  end

  local function drawLines(lines, x, y, w, maxY)
    for _, l in ipairs(lines) do
      for _, piece in ipairs(W.wrap(l[1], w)) do
        if y > maxY then return y end
        S.set(x, y, pad(piece, w), tone(l[2]), T.bg)
        y = y + 1
      end
    end
    return y
  end

  
  local function prompt(label, initial)
    local buf = tostring(initial or "")
    while true do
      S.fill(1, Ht - 1, Wd, 1, " ", T.fg, T.bg)
      S.set(2, Ht - 1, pad(label .. " " .. buf .. "_", Wd - 2), T.title, T.bg)
      local ch, code = pullKey()
      if code == K.ENTER then return buf end
      if isQuit(ch, code) then return nil end
      if code == K.BACK then buf = buf:sub(1, -2)
      elseif ch and ch >= 32 and ch < 127 then buf = buf .. string.char(ch) end
    end
  end
  local function yesNo(question)
    S.fill(1, Ht - 1, Wd, 1, " ", T.fg, T.bg)
    S.set(2, Ht - 1, pad(question .. "  (Y/N)", Wd - 2), T.warn, T.bg)
    while true do
      local ch, code = pullKey()
      if isQuit(ch, code) then return false end
      if ch then
        local c = string.char(ch):lower()
        if c == "y" then return true end
        if c == "n" then return false end
      end
    end
  end

  
  
  local function pickList(title, items, initialFilter)
    local filter = initialFilter or ""
    local i, top = 1, 1
    local bx, by, bw, bh = 6, 4, Wd - 12, Ht - 7
    while true do
      local shown = {}
      for _, it in ipairs(items) do
        if filter == "" or it[1]:lower():find(filter:lower(), 1, true) then shown[#shown + 1] = it end
      end
      if i > #shown then i = math.max(1, #shown) end
      local rows = bh - 3
      if i < top then top = i end
      if i > top + rows - 1 then top = i - rows + 1 end
      S.fill(bx, by, bw, bh, " ", T.fg, T.bg)
      S.set(bx, by, pad("[ " .. title .. " ]  filter: " .. filter .. "_", bw), T.title, T.bg)
      for r = 0, rows - 1 do
        local it = shown[top + r]
        if it then
          local isSel = (top + r == i)
          S.set(bx + 1, by + 2 + r, pad(it[1], bw - 2), isSel and T.selfg or tone(it[2]),
            isSel and T.selbg or T.bg)
        end
      end
      S.set(bx, by + bh - 1, pad("type to filter · Enter pick · " .. quitLabel() .. " cancel", bw), T.dim, T.bg)
      local ch, code = pullKey()
      if isQuit(ch, code) then return nil end
      if code == K.ENTER then return shown[i] and shown[i][3] end
      if code == K.UP then i = math.max(1, i - 1)
      elseif code == K.DOWN then i = math.min(#shown, i + 1)
      elseif code == K.PGUP then i = math.max(1, i - rows)
      elseif code == K.PGDN then i = math.min(#shown, i + rows)
      elseif code == K.BACK then filter = filter:sub(1, -2); i = 1
      elseif ch and ch >= 32 and ch < 127 then filter = filter .. string.char(ch); i = 1 end
    end
  end

  
  local LW = 30
  local function listRows()
    local rows, last = {}, nil
    for i, e in ipairs(cat) do
      if e.group ~= last then rows[#rows + 1] = { header = e.group }; last = e.group end
      rows[#rows + 1] = { index = i }
    end
    return rows
  end

  local function drawList()
    header("simulator")
    local rows = listRows()
    local selRow = 1
    for r, row in ipairs(rows) do if row.index == sel then selRow = r end end
    local visible = BODY_BOT - BODY_TOP + 1
    if selRow < listTop then listTop = selRow end
    if selRow > listTop + visible - 1 then listTop = selRow - visible + 1 end
    S.fill(1, BODY_TOP, Wd, visible, " ", T.fg, T.bg)
    for r = 0, visible - 1 do
      local row = rows[listTop + r]
      local y = BODY_TOP + r
      if row then
        if row.header then
          S.set(1, y, pad(" " .. row.header, LW), T.title, T.bg)
        else
          local e = cat[row.index]
          local isSel = row.index == sel
          S.set(1, y, pad("   " .. e.name, LW), isSel and T.selfg or T.fg, isSel and T.selbg or T.bg)
        end
      end
    end
    for y = BODY_TOP, BODY_BOT do S.set(LW + 1, y, S.mono and "|" or "│", T.dim, T.bg) end
    local oc, e = current()
    local lines = R.lines(oc, cfg, e)
    if cat[sel].kind == "custom" then
      lines[#lines + 1] = { "", "fg" }
      lines[#lines + 1] = { "Enter opens the designer.", "dim" }
    end
    drawLines(lines, LW + 3, BODY_TOP, Wd - LW - 3, BODY_BOT)
    footer({ "\226\134\145\226\134\147 Select", "Enter Design", "M Map", "S Shelter",
             "K Scan", "C Config" })
  end

  
  local CELL = 16
  local function slotName(x)
    if x == D.DROP_UPGRADE.key then return "Drop Upgrade" end
    local it = M.byKey[x]
    return it and it.name or ""
  end

  local function drawDesign()
    header("custom nuke designer" .. (designName and (" - " .. designName) or ""))
    S.fill(1, BODY_TOP, Wd, BODY_BOT - BODY_TOP + 1, " ", T.fg, T.bg)
    
    
    S.set(2, BODY_TOP, "Slots (one item each; a stack counts once)", T.dim, T.bg)
    for i = 1, D.CUSTOM_SLOTS do
      local col = (i - 1) % 3
      local row = math.floor((i - 1) / 3)
      local x = 2 + col * CELL
      local y = BODY_TOP + 1 + row
      local name = design[i] and slotName(design[i]) or "."
      local isCur = (i == cur)
      local it = design[i] and M.byKey[design[i]]
      local fg = it and (it.m and T.title or T.fg) or T.dim
      S.set(x, y, pad(string.format("%2d %s", i, name), CELL - 1), isCur and T.selfg or fg,
        isCur and T.selbg or T.bg)
    end
    local x0 = 2 + 3 * CELL + 1
    for y = BODY_TOP, BODY_BOT do S.set(x0 - 1, y, S.mono and "|" or "│", T.dim, T.bg) end
    local oc, e, v, info = current()
    local y = BODY_TOP
    S.set(x0 + 1, y, "Stages", T.dim, T.bg)
    y = drawLines(R.stageLines(v, info, cfg), x0 + 1, y + 1, Wd - x0 - 1, BODY_BOT)
    y = y + 1
    local lines = R.summary(oc, cfg, e)
    if info.fall then lines[#lines + 1] = { "Drop Upgrade: falls first, then goes off.", "dim" } end
    if info.unknown > 0 then lines[#lines + 1] = { info.unknown .. " slot(s) add nothing", "dim" } end
    lines[#lines + 1] = { "", "fg" }
    lines[#lines + 1] = { "M map, S shelter, ^Q back to the full report.", "dim" }
    drawLines(lines, x0 + 1, y, Wd - x0 - 1, BODY_BOT - 1)
    
    local it = design[cur] and M.byKey[design[cur]]
    if it then
      S.set(2, BODY_BOT, pad(string.format("Slot %d: %s, %s %s%s", cur, it.name,
        D.STAGE_NAME[it.stage], it.m and "x" or "+", num(it.v)), x0 - 3), T.dim, T.bg)
    end
    footer({ "Enter Pick", "Del Clear", "B Best", "G Save", "L Load", "K Scan", "M Map", "S Shelter" })
  end

  local function pickIngredient(initial)
    local items = { { "(empty slot)", "dim", false } }
    for _, it in ipairs(D.INGREDIENTS) do
      items[#items + 1] = { string.format("%-30s %-11s %s%s", it.name, D.STAGE_NAME[it.stage],
        it.m and "x" or "+", num(it.v)), it.m and "title" or "fg", it.key }
    end
    items[#items + 1] = { string.format("%-30s %-11s %s", D.DROP_UPGRADE.name, "(any)", "falls first"),
      "dim", D.DROP_UPGRADE.key }
    return pickList("ingredient for slot " .. cur, items, initial)
  end

  local function runBest()
    B = B or require("warhead.best")
    local goals = {}
    for _, g in ipairs(B.ORDER) do goals[#goals + 1] = { B.GOALS[g].name, "fg", g } end
    goals[#goals + 1] = { "Anti Mass (beams)", "fg", "euph" }
    local g = pickList("best design: which kind of blast?", goals)
    if not g then return end
    local opts = {}
    local inv = inventory()
    if inv and yesNo("Design from the materials in a chest on the transposer?") then
      local sides = inv.sides()
      local items = {}
      for _, s in ipairs(sides) do items[#items + 1] = { s.name .. " (" .. s.size .. " slots)", "fg", s.side } end
      local side = pickList("which chest?", items)
      if side == nil then return end
      local contents = readSide(inv, side) or {}
      local n
      opts.stock, n = W.stockFromContents(contents)
      if n == 0 then say("That chest holds no custom nuke ingredients.", "warn"); return end
    end
    if g == "nuke" or g == "hydro" then
      opts.salt = yesNo("Fill the spare slots with Salted material (longer fallout)?")
    end
    local d, err
    if g == "euph" then d, err = B.designEuph(cfg, opts) else d, err = B.design(g, cfg, opts) end
    if not d then say("No design: " .. tostring(err), "warn"); return end
    design = {}
    for i, it in ipairs(d.slots) do design[i] = it.key end
    designName = nil
    cur = 1
    say(string.format("Best %s: %d slots.", d.goal.name:lower(), #d.slots), "hi")
  end

  local function saveDesign()
    local name = prompt("Save design as:", designName or "")
    name = name and W.cleanName(name)
    if not name or name == "" then return end
    local copy = {}
    for i = 1, D.CUSTOM_SLOTS do copy[i] = design[i] end
    if not st.designs[name] then st.order[#st.order + 1] = name end
    st.designs[name] = copy
    local okS, err = saveSettings(st)
    designName = name
    say(okS and ("Saved \"" .. name .. "\".") or ("NOT saved: " .. tostring(err)), okS and "hi" or "warn")
  end

  local function loadDesign()
    if #st.order == 0 then say("No saved designs yet (G saves one).", "warn"); return end
    local items = {}
    for _, name in ipairs(st.order) do
      local oc = W.outcome(cat[1], cfg, st.designs[name])
      local e = M.effects(oc, cfg)
      items[#items + 1] = { string.format("%-24s %s %s", name, R.ENGINE[e.kind] or e.kind,
        e.radius and ("r" .. e.radius) or ""), "fg", name }
    end
    local name = pickList("load design", items)
    if not name then return end
    design = {}
    for i = 1, D.CUSTOM_SLOTS do design[i] = st.designs[name][i] end
    designName = name
    say("Loaded \"" .. name .. "\".")
  end

  local function scan()
    local inv, err = inventory()
    if not inv then say("Cannot scan: " .. err .. ".", "warn"); return end
    local found = {}
    for _, s in ipairs(inv.sides()) do
      local contents = readSide(inv, s.side)
      local entry = contents and W.identify(s.size, contents)
      if entry then found[#found + 1] = { entry = entry, contents = contents, side = s } end
    end
    if #found == 0 then say("No HBM bomb next to the transposer.", "warn"); return end
    local pick = found[1]
    if #found > 1 then
      local items = {}
      for i, f in ipairs(found) do items[#items + 1] = { f.side.name .. ": " .. f.entry.name, "fg", i } end
      local i = pickList("which bomb?", items)
      if not i then return end
      pick = found[i]
    end
    if pick.entry.kind == "custom" then
      local unknown
      design, unknown = W.slotsFromContents(pick.contents)
      designName = "scanned " .. pick.side.name
      view = "design"
      say(#unknown > 0 and string.format("Read it. %d slot(s) hold things that add nothing.", #unknown)
        or "Read the custom nuke on the " .. pick.side.name .. " side.", #unknown > 0 and "warn" or "hi")
    else
      
      local oc = M.bombOutcome(pick.entry.ref, cfg, pick.contents)
      local lines = R.lines(oc, cfg)
      header("scan - " .. pick.side.name .. " side")
      S.fill(1, BODY_TOP, Wd, BODY_BOT - BODY_TOP + 1, " ", T.fg, T.bg)
      drawLines(lines, 3, BODY_TOP, Wd - 4, BODY_BOT)
      say("As loaded. Any key to go back.")
      footer({})
      pullKey()
      status = nil
    end
  end

  
  local function rings(e)
    local out = {}
    if e.kind == "mk5" then
      out[#out + 1] = { r = e.radius, ch = "\226\150\136", mono = "#", c = "r1", label = "destroyed" }
      out[#out + 1] = { r = e.lethal, ch = "\226\150\147", mono = "%", c = "r2", label = "one tick kills" }
      out[#out + 1] = { r = e.blast, ch = "\226\150\146", mono = "+", c = "r3", label = "blast damage" }
      if e.fallout and e.fallout > e.blast then
        out[#out + 1] = { r = e.fallout, ch = "\226\150\145", mono = ".", c = "r4", label = "fallout" }
      end
    elseif e.radius then
      out[#out + 1] = { r = e.radius, ch = "\226\150\136", mono = "#", c = "r1",
        label = e.rinse and "rinsed" or "destroyed" }
      if e.blast then
        out[#out + 1] = { r = e.lethal, ch = "\226\150\147", mono = "%", c = "r2", label = "one tick kills" }
        out[#out + 1] = { r = e.blast, ch = "\226\150\146", mono = "+", c = "r3", label = "blast damage" }
      end
    elseif e.blast then
      out[#out + 1] = { r = e.blast, ch = "\226\150\146", mono = "+", c = "r3", label = "blast damage" }
    end
    return out
  end

  
  local function verdict(e, d)
    for _, rg in ipairs(rings(e)) do
      if d <= rg.r then return rg.label, rg.c end
    end
    return "untouched", "fg"
  end

  local function drawMap()
    local oc, e = current()
    header("map - " .. (oc.name or ""))
    S.fill(1, BODY_TOP, Wd, BODY_BOT - BODY_TOP + 1, " ", T.fg, T.bg)
    local rg = rings(e)
    local mapW = Wd - 34
    local mapH = BODY_BOT - BODY_TOP + 1
    local maxR = 1
    for _, x in ipairs(rg) do if x.r > maxR then maxR = x.r end end
    for _, p in ipairs(st.places) do
      local d = math.sqrt(p.dx * p.dx + p.dz * p.dz)
      if d > maxR then maxR = d end
    end
    maxR = maxR * 1.05
    
    
    local cx, cy = math.floor(mapW / 2) + 1, BODY_TOP + math.floor(mapH / 2)
    local scale = math.max(maxR / (mapW / 2), maxR / mapH)   
    for y = BODY_TOP, BODY_BOT do
      
      
      local runStart, runC, runText = 1, false, {}
      local function flush()
        if #runText > 0 then
          S.set(runStart, y, table.concat(runText), runC and T[runC] or T.fg, T.bg)
        end
      end
      for xx = 1, mapW do
        local dx = (xx - cx) * scale
        local dz = (y - cy) * scale * 2
        local d = math.sqrt(dx * dx + dz * dz)
        local ch, c = " ", nil
        for _, r in ipairs(rg) do
          if d <= r.r then ch = S.mono and r.mono or r.ch; c = r.c; break end
        end
        if c ~= runC then
          flush()
          runStart, runC, runText = xx, c, {}
        end
        runText[#runText + 1] = ch
      end
      flush()
    end
    S.set(cx, cy, "X", T.bg, T.fg)
    for i, p in ipairs(st.places) do
      local px = cx + math.floor(p.dx / scale + 0.5)
      local py = cy + math.floor(p.dz / (scale * 2) + 0.5)
      if px >= 1 and px <= mapW and py >= BODY_TOP and py <= BODY_BOT then
        S.set(px, py, tostring(i % 10), T.bg, T.title)
      end
    end
    
    local lx = mapW + 3
    local y = BODY_TOP
    S.set(lx, y, string.format("1 column = %s blocks", num(scale)), T.dim, T.bg); y = y + 1
    S.set(lx, y, "north is up; X is ground zero", T.dim, T.bg); y = y + 2
    for _, r in ipairs(rg) do
      S.set(lx, y, S.mono and r.mono or r.ch, T[r.c] or T.fg, T.bg)
      S.set(lx + 2, y, pad(string.format("%-15s %d", r.label, math.floor(r.r)), Wd - lx - 2), T.fg, T.bg)
      y = y + 1
    end
    y = y + 1
    if #st.places == 0 then
      drawLines({ { "A adds a place (your base, a farm) by its offset from ground zero.", "dim" } },
        lx, y, Wd - lx, BODY_BOT)
    else
      for i, p in ipairs(st.places) do
        if y > BODY_BOT then break end
        local d = math.sqrt(p.dx * p.dx + p.dz * p.dz)
        local label, c = verdict(e, d)
        S.set(lx, y, pad(string.format("%d %s", i % 10, p.name), Wd - lx), T.title, T.bg); y = y + 1
        S.set(lx + 2, y, pad(string.format("%s out: %s", num(d), label), Wd - lx - 2), T[c] or T.fg, T.bg)
        y = y + 1
      end
    end
    footer({ "A Add place", "X Remove place" })
  end

  local function addPlace()
    local name = prompt("Place name:", "")
    name = name and W.cleanName(name)
    if not name or name == "" then return end
    local dx = tonumber(prompt("Blocks east of ground zero (west is negative):", "0") or "")
    if not dx then return end
    local dz = tonumber(prompt("Blocks south of ground zero (north is negative):", "0") or "")
    if not dz then return end
    st.places[#st.places + 1] = { name = name, dx = math.floor(dx), dz = math.floor(dz) }
    local okS, err = saveSettings(st)
    say(okS and ("Added " .. name .. ".") or ("Added, but NOT saved: " .. tostring(err)), okS and "hi" or "warn")
  end

  local function removePlace()
    if #st.places == 0 then return end
    local items = {}
    for i, p in ipairs(st.places) do items[#items + 1] = { p.name, "fg", i } end
    local i = pickList("remove which place?", items)
    if not i then return end
    table.remove(st.places, i)
    saveSettings(st)
    say("Removed.")
  end

  
  local function drawShelter()
    local oc, e = current()
    local m = D.MATERIALS[shelterMat]
    header("shelter - " .. (oc.name or ""))
    S.fill(1, BODY_TOP, Wd, BODY_BOT - BODY_TOP + 1, " ", T.fg, T.bg)
    local y = BODY_TOP
    S.set(3, y, string.format("Distance  %-6d  (Up/Down 1, PgUp/PgDn 10)", shelterDist), T.fg, T.bg); y = y + 1
    S.set(3, y, string.format("Material  %-26s  (Left/Right)", m.name), T.fg, T.bg); y = y + 1
    S.set(3, y, string.format("Thickness %-6d  (+ / -)", shelterThick), T.fg, T.bg); y = y + 2
    local v = M.shelter(oc, e, m, shelterDist, shelterThick)
    y = drawLines(R.shelterLines(v, m, e), 3, y, Wd - 6, BODY_BOT)
    if e.kind == "mk5" then
      y = y + 1
      S.set(3, y, "Blocks of " .. m.name .. " that stop it, by distance:", T.dim, T.bg); y = y + 1
      local line = {}
      for _, f in ipairs({ 0.05, 0.1, 0.25, 0.5, 0.75, 0.9 }) do
        local d = math.max(1, math.floor(e.radius * f))
        local n, through = M.wallStop(e.radius, m.nuke, d)
        line[#line + 1] = string.format("%d: %s", d, through and "never" or tostring(n))
      end
      drawLines({ { table.concat(line, "   "), "fg" } }, 3, y, Wd - 6, BODY_BOT)
      y = y + 2
      drawLines({ { "A straight-on ray is the blast's shortest path through a wall; every slanted ray "
        .. "loses more. Radiation counts each block's own resistance, so obsidian shields it far "
        .. "better than it stops the blast.", "dim" } }, 3, y, Wd - 6, BODY_BOT)
    end
    footer({ "\226\134\145\226\134\147 Distance", "\226\134\144\226\134\146 Material", "+/- Thickness" })
  end

  
  local cfgSel = 1
  local cfgKeys = {}
  for k in pairs(D.CONFIG) do cfgKeys[#cfgKeys + 1] = k end
  table.sort(cfgKeys)

  local function drawConfig()
    header("config")
    S.fill(1, BODY_TOP, Wd, BODY_BOT - BODY_TOP + 1, " ", T.fg, T.bg)
    S.set(3, BODY_TOP, "Your server's hbm.cfg values (sections 03_nukes and 06_explosions).", T.dim, T.bg)
    local rows = BODY_BOT - BODY_TOP - 1
    local top = math.max(1, cfgSel - rows + 1)
    for r = 0, rows - 1 do
      local k = cfgKeys[top + r]
      if k then
        local isSel = (top + r == cfgSel)
        local mine = st.cfg[k] ~= nil
        local line = string.format("%-24s %-8s %s", k, tostring(cfg[k]),
          mine and ("(default " .. tostring(D.CONFIG[k]) .. ")") or "")
        S.set(3, BODY_TOP + 2 + r, pad(line, Wd - 6), isSel and T.selfg or (mine and T.hi or T.fg),
          isSel and T.selbg or T.bg)
      end
    end
    footer({ "Enter Change", "R Reset" })
  end

  local function editConfig()
    local k = cfgKeys[cfgSel]
    if D.CONFIG_BOOL[k] then
      st.cfg[k] = not cfg[k]
    else
      local v = tonumber(prompt(k .. ":", tostring(cfg[k])) or "")
      if not v or v < 0 then return end
      st.cfg[k] = v
    end
    if st.cfg[k] == D.CONFIG[k] then st.cfg[k] = nil end
    cfg = M.config(st.cfg)
    local okS, err = saveSettings(st)
    say(okS and "Saved." or ("NOT saved: " .. tostring(err)), okS and "hi" or "warn")
  end

  
  local function draw()
    if view == "list" then drawList()
    elseif view == "design" then drawDesign()
    elseif view == "map" then drawMap()
    elseif view == "shelter" then drawShelter()
    elseif view == "config" then drawConfig() end
  end

  draw()
  while true do
    local ch, code, ev = pullKey()
    if ev == "tos_focus" then draw()
    elseif ch or code then
      status = nil
      local c = ch and ch > 0 and string.char(ch):lower() or ""
      if isQuit(ch, code) then
        if view == "list" then break end
        view = (view == "map" or view == "shelter") and back or "list"
      elseif view == "list" then
        if code == K.UP then sel = math.max(1, sel - 1)
        elseif code == K.DOWN then sel = math.min(#cat, sel + 1)
        elseif code == K.PGUP then sel = math.max(1, sel - 10)
        elseif code == K.PGDN then sel = math.min(#cat, sel + 10)
        elseif code == K.ENTER and cat[sel].kind == "custom" then view = "design"
        elseif c == "m" then back = "list"; view = "map"
        elseif c == "s" then back = "list"; view = "shelter"
        elseif c == "c" then view = "config"
        elseif c == "k" then scan() end
      elseif view == "design" then
        if code == K.LEFT then cur = math.max(1, cur - 1)
        elseif code == K.RIGHT then cur = math.min(D.CUSTOM_SLOTS, cur + 1)
        elseif code == K.UP then if cur > 3 then cur = cur - 3 end
        elseif code == K.DOWN then if cur <= D.CUSTOM_SLOTS - 3 then cur = cur + 3 end
        elseif code == K.DEL or code == K.BACK then design[cur] = nil
        elseif code == K.ENTER then
          local key = pickIngredient()
          if key ~= nil then design[cur] = key or nil; cur = math.min(D.CUSTOM_SLOTS, cur + 1) end
        elseif c == "b" then runBest()
        elseif c == "g" then saveDesign()
        elseif c == "l" then loadDesign()
        elseif c == "k" then scan()
        elseif c == "m" then back = "design"; view = "map"
        elseif c == "s" then back = "design"; view = "shelter"
        elseif ch and ch >= 32 and ch < 127 then
          
          local key = pickIngredient(string.char(ch))
          if key ~= nil then design[cur] = key or nil; cur = math.min(D.CUSTOM_SLOTS, cur + 1) end
        end
      elseif view == "map" then
        if c == "a" then addPlace() elseif c == "x" then removePlace() end
      elseif view == "shelter" then
        if code == K.UP then shelterDist = shelterDist + 1
        elseif code == K.DOWN then shelterDist = math.max(1, shelterDist - 1)
        elseif code == K.PGUP then shelterDist = shelterDist + 10
        elseif code == K.PGDN then shelterDist = math.max(1, shelterDist - 10)
        elseif code == K.LEFT then shelterMat = (shelterMat - 2) % #D.MATERIALS + 1
        elseif code == K.RIGHT then shelterMat = shelterMat % #D.MATERIALS + 1
        elseif c == "+" or c == "=" then shelterThick = math.min(64, shelterThick + 1)
        elseif c == "-" then shelterThick = math.max(1, shelterThick - 1) end
      elseif view == "config" then
        if code == K.UP then cfgSel = math.max(1, cfgSel - 1)
        elseif code == K.DOWN then cfgSel = math.min(#cfgKeys, cfgSel + 1)
        elseif code == K.ENTER then editConfig()
        elseif c == "r" then st.cfg[cfgKeys[cfgSel]] = nil; cfg = M.config(st.cfg); saveSettings(st); say("Reset.") end
      end
      draw()
    end
  end
  S.fill(1, 1, Wd, Ht, " ", T.fg, T.bg)
end

local function warheadCmd(args, o)
  args = args or {}
  o = o or print
  if args[1] and cliMain(args, o) then return end
  if args[1] then cliHelp(o); return end
  ui(o)
end

return { commands = { warhead = warheadCmd }, text = W }
