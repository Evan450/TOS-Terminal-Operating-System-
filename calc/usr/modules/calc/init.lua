



















local component = require("component")
local computer  = require("computer")
local S         = require("calc.sheet")





local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function stdQuit(ch, code)
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

local M = {}

local COLW    = 9         
local ROWHDR  = 5         
local DEFAULT_EXT = ".calc"








function M.ulen(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
  end
  return n
end
function M.usub(s, a, b)
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
function M.pad(s, n)
  s = tostring(s or "")
  local w = M.ulen(s)
  if w > n then return M.usub(s, 1, n) end
  return s .. string.rep(" ", n - w)
end
function M.padLeft(s, n)
  s = tostring(s or "")
  local w = M.ulen(s)
  if w > n then return M.usub(s, 1, n) end
  return string.rep(" ", n - w) .. s
end








function M.fitHints(hints, cols, must)
  local function join(list)
    return (#list == 0) and "" or (" " .. table.concat(list, " · ") .. " ")
  end
  local kept = {}
  for _, h in ipairs(hints) do
    kept[#kept + 1] = h
    if M.ulen(join(kept)) > cols then kept[#kept] = nil; break end
  end
  if must then
    local have = false
    for _, h in ipairs(kept) do if h == must then have = true end end
    while not have do
      kept[#kept + 1] = must
      if M.ulen(join(kept)) <= cols then have = true
      else
        kept[#kept] = nil                 
        if #kept == 0 then return join({ must }) end
        kept[#kept] = nil
      end
    end
  end
  return join(kept)
end

local function run(args, o)
  o = o or print

  local gpuAddr = component.list and component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return end
  local okG, gpu = pcall(component.proxy, gpuAddr)
  if not okG or not gpu then o("Cannot open the GPU.", 0xFF0000); return end
  local W, H = gpu.getResolution()
  if not W or not H or W < 40 or H < 12 then
    o("calc needs at least a 40x12 screen.", 0xFF6600); return
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number")
    and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local mono = (tier == 1)

  local T = mono and {
    bg = 0x000000, fg = 0xFFFFFF, dim = 0xFFFFFF, title = 0xFFFFFF,
    selfg = 0x000000, selbg = 0xFFFFFF, err = 0xFFFFFF, hi = 0xFFFFFF,
  } or {
    bg = 0x000000, fg = 0xFFFFFF, dim = 0xAAAAAA,
    title = tier == 2 and 0xFFFF55 or 0xFFFF00,
    selfg = 0x000000, selbg = tier == 2 and 0x55FFFF or 0x00FFFF,
    err = tier == 2 and 0xFF5555 or 0xFF4040,
    hi = tier == 2 and 0x55FF55 or 0x00FF00,
  }

  local function set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  local function fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  local pad, padLeft, fitHints = M.pad, M.padLeft, M.fitHints

  
  local sh = S.new()
  local ctx = S.evaluator(sh)
  local cur = { c = 1, r = 1 }
  local off = { c = 1, r = 1 }            
  local path = args and args[1] or nil
  local dirty = false
  local status, statusCol = "", nil

  local GRID_TOP = 4                      
  local GRID_BOT = H - 2                  
  local function visRows() return GRID_BOT - GRID_TOP + 1 end
  local function visCols() return math.max(1, math.floor((W - ROWHDR) / COLW)) end

  local function recalc() ctx = S.evaluator(sh) end
  local function say(msg, col) status, statusCol = msg or "", col end

  
  local function drawChrome()
    fill(1, 1, W, 1, " ", T.fg, T.bg)
    set(2, 1, "TOS calc", T.title, T.bg)
    local name = path and path:match("[^/]+$") or "(unsaved)"
    local title = name .. (dirty and " *" or "")
    set(math.max(12, math.floor((W - #title) / 2)), 1, title, T.fg, T.bg)
    local cells = 0
    for _ in pairs(sh.cells) do cells = cells + 1 end
    local right = cells .. " cells"
    set(math.max(1, W - #right), 1, right, T.dim, T.bg)

    
    local dash = mono and "-" or "─"
    local lt, rt = (mono and "|" or "┤"), (mono and "|" or "├")
    local label = S.refName(cur.c, cur.r)
    local rail = dash .. lt .. " " .. label .. " " .. rt
    set(1, 2, rail .. string.rep(dash, math.max(0, W - #rail)), T.dim, T.bg)
    set(4, 2, label, T.fg, T.bg)
  end

  local function drawHeaders()
    fill(1, 3, W, 1, " ", T.dim, T.bg)
    set(1, 3, string.rep(" ", ROWHDR), T.dim, T.bg)
    local n = visCols()
    for i = 0, n - 1 do
      local c = off.c + i
      local x = ROWHDR + i * COLW + 1
      local nameTxt = S.colName(c)
      local isCur = (c == cur.c)
      
      local lead = math.floor((COLW - #nameTxt) / 2)
      set(x, 3, string.rep(" ", COLW), isCur and T.selfg or T.dim,
        isCur and T.selbg or T.bg)
      set(x + lead, 3, nameTxt, isCur and T.selfg or T.dim,
        isCur and T.selbg or T.bg)
    end
  end

  local function drawGrid()
    local nc, nr = visCols(), visRows()
    for i = 0, nr - 1 do
      local r = off.r + i
      local y = GRID_TOP + i
      fill(1, y, W, 1, " ", T.fg, T.bg)
      
      local isCurRow = (r == cur.r)
      set(1, y, padLeft(tostring(r), ROWHDR - 1) .. " ",
        isCurRow and T.selfg or T.dim, isCurRow and T.selbg or T.bg)
      for j = 0, nc - 1 do
        local c = off.c + j
        local x = ROWHDR + j * COLW + 1
        local isCur = (c == cur.c and r == cur.r)
        local disp = S.display(sh, ctx, c, r)
        local v = ctx.get(c, r)
        local fg = T.fg
        if S.isErr(v) then fg = T.err
        elseif type(v) == "number" then fg = T.fg
        elseif v ~= nil then fg = T.dim end          
        
        
        local cellTxt
        if type(v) == "number" then cellTxt = padLeft(disp, COLW - 1) .. " "
        else cellTxt = " " .. pad(disp, COLW - 1) end
        set(x, y, cellTxt, isCur and T.selfg or fg, isCur and T.selbg or T.bg)
      end
    end
  end

  local function drawStatus()
    fill(1, H - 1, W, 1, " ", T.fg, T.bg)
    local raw = S.raw(sh, cur.c, cur.r)
    if status ~= "" then
      set(2, H - 1, pad(status, W - 2), statusCol or T.hi, T.bg)
    else
      set(2, H - 1, pad(raw ~= "" and raw or "(empty)", W - 2),
        raw ~= "" and T.fg or T.dim, T.bg)
    end
    
    fill(1, H, W, 1, mono and " " or "░", T.dim, T.bg)
    if not mono then
      set(1, H, "▓▒░", T.dim, T.bg)
      if W > 6 then set(W - 2, H, "░▒▓", T.dim, T.bg) end
    end
    local keys = fitHints({ "Click/Type Edit", "^S Save", "^O Open",
                            "^E CSV", "Del Clear", "^B Bg", "^Q Quit" },
                          math.max(0, W - 9), "^Q Quit")
    set(5, H, pad(keys, math.max(0, W - 9)), T.fg, T.bg)
  end

  local function redraw()
    fill(1, 1, W, H, " ", T.fg, T.bg)
    drawChrome(); drawHeaders(); drawGrid(); drawStatus()
  end

  local function ensureVisible()
    local nc, nr = visCols(), visRows()
    if cur.c < off.c then off.c = cur.c end
    if cur.c > off.c + nc - 1 then off.c = cur.c - nc + 1 end
    if cur.r < off.r then off.r = cur.r end
    if cur.r > off.r + nr - 1 then off.r = cur.r - nr + 1 end
    if off.c < 1 then off.c = 1 end
    if off.r < 1 then off.r = 1 end
  end

  
  
  local function editLine(prompt, initial)
    local buf = initial or ""
    while true do
      fill(1, H - 1, W, 1, " ", T.fg, T.bg)
      set(1, H - 1, prompt, T.hi, T.bg)
      local avail = W - #prompt - 2
      local shown = (#buf > avail) and buf:sub(#buf - avail + 1) or buf
      set(#prompt + 1, H - 1, shown, T.fg, T.bg)
      set(#prompt + 1 + #shown, H - 1, "_", T.hi, T.bg)
      local ev, _, ch, code = computer.pullSignal()
      if ev == "key_down" then
        if code == 28 then return buf                     
        elseif code == 1 or ch == 17 then return nil      
        elseif code == 14 then                            
          if #buf > 0 then buf = buf:sub(1, -2) end
        elseif ch and ch >= 32 and ch < 127 then
          buf = buf .. string.char(ch)
        end
      elseif ev == "clipboard" and type(ch) == "string" then
        buf = buf .. ch:gsub("[\r\n\t]", " ")
      end
    end
  end

  
  local function haveFs() return fs and fs.writeFile and fs.readFile end

  local function doSave(target)
    if not haveFs() then say("No filesystem access.", T.err); return end
    target = target or path
    if not target or target == "" then return end
    if not target:find("%.") then target = target .. DEFAULT_EXT end
    local okW, e = pcall(fs.writeFile, target, S.serialize(sh))
    if okW and e ~= false then
      path, dirty = target, false
      say("Saved " .. target, T.hi)
    else
      say("Save failed: " .. tostring(e), T.err)
    end
  end

  local function doOpen(target)
    if not haveFs() then say("No filesystem access.", T.err); return end
    if not target or target == "" then return end
    if not fs.exists(target) and not target:find("%.") then
      target = target .. DEFAULT_EXT
    end
    if not fs.exists(target) then say("No such file: " .. target, T.err); return end
    local okR, data = pcall(fs.readFile, target)
    if not okR or type(data) ~= "string" then
      say("Cannot read " .. target, T.err); return
    end
    sh = S.deserialize(data)
    recalc()
    path, dirty = target, false
    cur.c, cur.r, off.c, off.r = 1, 1, 1, 1
    local note = "Opened " .. target
    if (sh.skipped or 0) > 0 then
      note = note .. "  (" .. sh.skipped .. " unreadable line(s) skipped)"
    end
    say(note, (sh.skipped or 0) > 0 and T.err or T.hi)
  end

  local function doExportCSV(target)
    if not haveFs() then say("No filesystem access.", T.err); return end
    if not target or target == "" then return end
    if not target:find("%.") then target = target .. ".csv" end
    local okW, e = pcall(fs.writeFile, target, S.toCSV(sh, ctx))
    if okW and e ~= false then say("Exported " .. target, T.hi)
    else say("Export failed: " .. tostring(e), T.err) end
  end

  
  if path then doOpen(path) end

  
  
  
  
  
  
  local function cellAtPixel(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if y < GRID_TOP or y > GRID_BOT then return nil end
    if x <= ROWHDR then return nil end               
    local j = math.floor((x - ROWHDR - 1) / COLW)
    if j < 0 or j >= visCols() then return nil end
    local i = y - GRID_TOP
    if i < 0 or i >= visRows() then return nil end
    local c = off.c + j
    local r = off.r + i
    if c > S.MAX_COLS or r > S.MAX_ROWS then return nil end
    return c, r
  end

  
  redraw()
  while true do
    
    
    local ev, _, ch, code, arg5 = computer.pullSignal()
    
    
    if ev == "tos_focus" then
      redraw()
    elseif ev == "touch" or ev == "drag" then
      
      
      local c, r = cellAtPixel(ch, code)
      if c then cur.c, cur.r = c, r; say(""); redraw() end
    elseif ev == "scroll" then
      
      local step = (arg5 or 0) > 0 and -3 or 3
      cur.r = math.max(1, math.min(S.MAX_ROWS, cur.r + step))
      ensureVisible(); redraw()
    elseif ev == "key_down" then
      local handled = true
      say("")
      if stdQuit(ch, code) then                           
        if dirty then
          local ans = editLine("Unsaved changes — save first? (y/n/esc): ", "")
          if ans == nil then handled = true              
          elseif ans:lower():sub(1, 1) == "y" then
            local t = path or editLine("Save as: ", "")
            if t then doSave(t); fill(1, 1, W, H, " ", T.fg, T.bg); return end
          else
            fill(1, 1, W, H, " ", T.fg, T.bg); return
          end
        else
          fill(1, 1, W, H, " ", T.fg, T.bg); return
        end
      elseif ch == 19 then                               
        local t = path
        if not t then t = editLine("Save as: ", "") end
        if t then doSave(t) end
      elseif ch == 15 then                               
        local t = editLine("Open: ", path or "")
        if t then doOpen(t) end
      elseif ch == 5 then                                
        local suggest = (path and path:gsub("%.%w+$", "") or "sheet") .. ".csv"
        local t = editLine("Export CSV as: ", suggest)
        if t then doExportCSV(t) end
      elseif code == 200 then cur.r = math.max(1, cur.r - 1)
      elseif code == 208 then cur.r = math.min(S.MAX_ROWS, cur.r + 1)
      elseif code == 203 then cur.c = math.max(1, cur.c - 1)
      elseif code == 205 then cur.c = math.min(S.MAX_COLS, cur.c + 1)
      elseif code == 201 then cur.r = math.max(1, cur.r - visRows())
      elseif code == 209 then cur.r = math.min(S.MAX_ROWS, cur.r + visRows())
      elseif code == 199 then cur.c = 1                  
      elseif code == 207 then                            
        local maxc = 1
        for k in pairs(sh.cells) do
          local c = tonumber(k:match("^(%d+):"))
          if c and c > maxc then maxc = c end
        end
        cur.c = maxc
      elseif code == 211 or code == 14 then              
        if S.raw(sh, cur.c, cur.r) ~= "" then
          S.set(sh, cur.c, cur.r, nil); recalc(); dirty = true
        end
      elseif code == 28 then                             
        local v = editLine(S.refName(cur.c, cur.r) .. ": ", S.raw(sh, cur.c, cur.r))
        if v ~= nil then
          S.set(sh, cur.c, cur.r, v); recalc(); dirty = true
          cur.r = math.min(S.MAX_ROWS, cur.r + 1)        
        end
      elseif ch and ch >= 32 and ch < 127 then
        
        
        local v = editLine(S.refName(cur.c, cur.r) .. ": ", string.char(ch))
        if v ~= nil then
          S.set(sh, cur.c, cur.r, v); recalc(); dirty = true
          cur.r = math.min(S.MAX_ROWS, cur.r + 1)
        end
      else
        handled = false
      end
      if handled then ensureVisible(); redraw() end
    end
  end
end

return { commands = { calc = run }, text = M }
