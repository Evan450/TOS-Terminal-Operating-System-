






















local component = require("component")
local computer  = require("computer")





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

local mod = {}


local BW       = 10          
local BH       = 20          
local CW       = 2           
local PANEL_W  = 18          
local PF_BOX_W = BW * CW + 2 
local PF_BOX_H = BH + 2      
local MIN_W    = PF_BOX_W + 1 + PANEL_W  
local MIN_H    = PF_BOX_H + 2            





local PIECES = {
  
  {{{0,1},{1,1},{2,1},{3,1}}, {{2,0},{2,1},{2,2},{2,3}},
   {{0,2},{1,2},{2,2},{3,2}}, {{1,0},{1,1},{1,2},{1,3}}},
  
  
  {{{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}},
   {{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}}},
  
  
  {{{1,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{2,1},{1,2}},
   {{0,1},{1,1},{2,1},{1,2}}, {{1,0},{0,1},{1,1},{1,2}}},
  
  
  {{{1,0},{2,0},{0,1},{1,1}}, {{1,0},{1,1},{2,1},{2,2}},
   {{1,1},{2,1},{0,2},{1,2}}, {{0,0},{0,1},{1,1},{1,2}}},
  
  
  {{{0,0},{1,0},{1,1},{2,1}}, {{2,0},{1,1},{2,1},{1,2}},
   {{0,1},{1,1},{1,2},{2,2}}, {{1,0},{0,1},{1,1},{0,2}}},
  
  
  {{{0,0},{0,1},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{1,2}},
   {{0,1},{1,1},{2,1},{2,2}}, {{1,0},{1,1},{0,2},{1,2}}},
  
  
  {{{2,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{1,2},{2,2}},
   {{0,1},{1,1},{2,1},{0,2}}, {{0,0},{1,0},{1,1},{1,2}}},
}



local PCOLORS = {
  [3] = {0x00FFFF, 0xFFFF00, 0xFF00FF, 0x00FF00, 0xFF0000, 0x5555FF, 0xFF8800},
  [2] = {0x55FFFF, 0xFFFF55, 0xFF55FF, 0x55FF55, 0xFF5555, 0x5555FF, 0xFFAA00},
  [1] = {0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF},
}


local K = {
  LEFT=203, RIGHT=205, UP=200, DOWN=208,
  SPACE=57, ESC=1, ENTER=28,
  Q=16, W=17, A=30, S=31, D=32, P=25, R=19, Z=44, X=45,
}



local WALL_KICKS = {{0,0},{-1,0},{1,0},{-2,0},{2,0},{0,-1}}


local LINE_PTS = {100, 300, 500, 800}


local function gravity(lv)
  return math.max(0.05, 0.75 - (lv - 1) * 0.07)
end




local function fullRows(bd, bw, bh)
  local rows = {}
  for r = 1, bh do
    local full = true
    for c = 1, bw do
      if bd[r][c] == 0 then full = false; break end
    end
    if full then rows[#rows + 1] = r end
  end
  return rows
end











local function removeRows(bd, bw, rows)
  if #rows == 0 then return end
  local order = {}
  for i, r in ipairs(rows) do order[i] = r end
  table.sort(order, function(a, b) return a > b end)
  for _, r in ipairs(order) do table.remove(bd, r) end
  for _ = 1, #rows do
    local blank = {}
    for c = 1, bw do blank[c] = 0 end
    table.insert(bd, 1, blank)
  end
end

mod._test = { fullRows = fullRows, removeRows = removeRows }



local SCORE_FILE = ".tetris_hs"
local MAX_SCORES = 5






local function scorePath()
  if type(fs) ~= "table" or not fs.home then return nil end
  local ok, home = pcall(fs.home)
  if not ok or type(home) ~= "string" then return nil end
  
  
  if home == "/tmp" then return nil end
  return home .. "/" .. SCORE_FILE
end







local function getSerializer()
  
  
  
  local ok, ser = pcall(require, "compat.serialization")
  if ok and type(ser) == "table" then return ser end
  return nil
end

local function loadScores(path)
  if not path or type(fs) ~= "table" then return {} end
  if not fs.exists(path) then return {} end
  local data = fs.readFile(path)
  if not data then return {} end
  local SZ = getSerializer()
  if not SZ then return {} end
  local t = SZ.unserialize(data)
  return type(t) == "table" and t or {}
end

local function saveScores(path, tbl)
  if not path or type(fs) ~= "table" then return end
  local SZ = getSerializer()
  if SZ then fs.writeFile(path, SZ.serialize(tbl)) end
end


local function recordScore(path, score, lines, level)
  local tbl = loadScores(path)
  tbl[#tbl + 1] = {
    score = score, lines = lines, level = level,
    t = math.floor(computer.uptime()),
  }
  table.sort(tbl, function(a, b) return a.score > b.score end)
  while #tbl > MAX_SCORES do tbl[#tbl] = nil end
  saveScores(path, tbl)
  return tbl
end



local function play(o)
  
  
  
  
  local gpuAddr = component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return end
  local gpu = component.proxy(gpuAddr)

  local W, H = gpu.getResolution()
  if not W or not H then o("Cannot detect screen size.", 0xFF0000); return end

  
  local okDepth, depth = pcall(gpu.getDepth)
  if not okDepth or type(depth) ~= "number" then depth = 1 end
  local tier = depth <= 1 and 1 or (depth <= 4 and 2 or 3)

  if W < MIN_W or H < MIN_H then
    o(string.format("Screen too small: need %dx%d, have %dx%d.",
                    MIN_W, MIN_H, W, H), 0xFF6600)
    o("A Tier 2+ screen (80×24 minimum) is required.", 0xAAAAAA)
    return
  end

  
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, border = 0xFFFFFF,
    title = 0xFFFFFF, highlight = 0xFFFFFF,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA,
    border    = tier == 2 and 0x55FFFF or 0x00FFFF,
    title     = tier == 2 and 0xFFFF55 or 0xFFFF00,
    highlight = tier == 2 and 0x55FF55 or 0x00FF00,
  }

  
  
  
  local BOX = tier >= 2
    and { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│",
          DTL = "╔", DTR = "╗", DBL = "╚", DBR = "╝", DH = "═", DV = "║" }
    or  { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|",
          DTL = "+", DTR = "+", DBL = "+", DBR = "+", DH = "=", DV = "|" }

  local D = {}
  function D.set(x, y, text, fg, bg)
    if fg then gpu.setForeground(fg) end
    if bg then gpu.setBackground(bg) end
    gpu.set(x, y, text)
  end
  function D.fill(x, y, w, h, char, fg, bg)
    if fg then gpu.setForeground(fg) end
    if bg then gpu.setBackground(bg) end
    gpu.fill(x, y, w, h, char or " ")
  end
  function D.clear() D.fill(1, 1, W, H, " ", T.fg, 0x000000) end
  function D.fit(text, width)
    text = tostring(text or "")
    if #text > width then return text:sub(1, width - 1) .. "…" end
    return text .. string.rep(" ", width - #text)
  end
  local function drawBoxKind(x, y, w, h, title, style, double)
    style = style or {}
    local bfg = style.border or T.border
    local bbg = style.bg or 0x000000
    local tl  = double and BOX.DTL or BOX.tl
    local tr  = double and BOX.DTR or BOX.tr
    local bl  = double and BOX.DBL or BOX.bl
    local br  = double and BOX.DBR or BOX.br
    local hch = double and BOX.DH  or BOX.h
    local vch = double and BOX.DV  or BOX.v
    D.fill(x, y, w, h, " ", T.fg, bbg)
    D.set(x, y,         tl .. string.rep(hch, w - 2) .. tr, bfg, bbg)
    D.set(x, y + h - 1, bl .. string.rep(hch, w - 2) .. br, bfg, bbg)
    for row = y + 1, y + h - 2 do
      D.set(x,         row, vch, bfg, bbg)
      D.set(x + w - 1, row, vch, bfg, bbg)
    end
    if title then
      local tstr = " " .. title .. " "
      D.set(x + math.floor((w - #tstr) / 2), y, tstr, style.title or T.title, bbg)
    end
  end
  function D.box(x, y, w, h, title, style)  drawBoxKind(x, y, w, h, title, style, false) end
  function D.dbox(x, y, w, h, title, style) drawBoxKind(x, y, w, h, title, style, true)  end

  
  
  
  local E = { pull = function(timeout) return computer.pullSignal(timeout) end }

  
  local pCol = PCOLORS[tier] or PCOLORS[1]

  local C = {
    ghost  = tier >= 3 and 0x1A1A3A or (tier == 2 and 0x222255 or 0x555555),
    empty  = 0x000000,
    border = tier >= 2 and T.border   or 0xFFFFFF,
    title  = tier >= 2 and T.title    or 0xFFFFFF,
    text   = T.fg,
    dim    = T.dim,
    hi     = tier >= 2 and T.highlight or 0xFFFFFF,
    score  = tier == 3 and 0xFFFF00 or (tier == 2 and 0xFFFF55 or 0xFFFFFF),
    danger = tier >= 2 and 0xFF5555   or 0xFFFFFF,
  }

  
  local totalW  = PF_BOX_W + 1 + PANEL_W
  local bx      = math.max(1, math.floor((W - totalW) / 2) + 1)
  local by      = math.max(1, math.floor((H - PF_BOX_H) / 2) + 1)
  local pfx     = bx + 1            
  local pfy     = by + 1            
  local panBX   = bx + PF_BOX_W + 1 
  local pnx     = panBX + 1         
  local pny     = by + 1            
  local pniw    = PANEL_W - 2       

  local path    = scorePath()       

  

  
  local function cxy(col, row) return pfx + col * CW, pfy + row end

  
  local function drawCell(col, row, color)
    local sx, sy = cxy(col, row)
    if tier == 1 then
      gpu.setForeground(color ~= 0 and 0xFFFFFF or 0x000000)
      gpu.setBackground(0x000000)
      gpu.set(sx, sy, color ~= 0 and "[]" or "  ")
    else
      gpu.setBackground(color)
      gpu.fill(sx, sy, CW, 1, " ")
    end
  end

  
  local function drawGhost(col, row)
    local sx, sy = cxy(col, row)
    if tier == 1 then
      gpu.setForeground(C.dim); gpu.setBackground(C.empty)
      gpu.set(sx, sy, "::")
    else
      gpu.setBackground(C.ghost); gpu.fill(sx, sy, CW, 1, " ")
    end
  end

  

  
  local function drawBoard(board)
    for r = 1, BH do
      for c = 1, BW do drawCell(c - 1, r - 1, board[r][c]) end
    end
  end

  
  
  local function eraseOverlay(pt, rot, ox, oy, board)
    for _, off in ipairs(PIECES[pt][rot]) do
      local c, r = ox + off[1], oy + off[2]
      if r >= 0 and r < BH and c >= 0 and c < BW then
        drawCell(c, r, board[r + 1][c + 1])
      end
    end
  end

  
  local function drawOverlay(pt, rot, ox, oy, color, isGhost)
    for _, off in ipairs(PIECES[pt][rot]) do
      local c, r = ox + off[1], oy + off[2]
      if r >= 0 and r < BH and c >= 0 and c < BW then
        if isGhost then drawGhost(c, r) else drawCell(c, r, color) end
      end
    end
  end

  

  local function drawFrame()
    D.clear()
    D.box(bx,    by, PF_BOX_W, PF_BOX_H, "TETRIS",
          {border = C.border, bg = C.empty, title = C.title})
    D.box(panBX, by, PANEL_W,  PF_BOX_H, nil,
          {border = C.border, bg = C.empty})

    
    gpu.setBackground(C.empty)
    gpu.setForeground(C.score)
    gpu.set(pnx, pny,     "SCORE")
    gpu.set(pnx, pny + 3, "LINES")
    gpu.set(pnx, pny + 6, "LEVEL")
    gpu.set(pnx, pny + 9, "NEXT")

    
    local cy = pny + 14
    if cy + 5 <= by + PF_BOX_H - 1 then
      gpu.setForeground(C.dim)
      gpu.set(pnx, cy,     "LR/AD: move")
      gpu.set(pnx, cy + 1, "U/W/X: rot")
      gpu.set(pnx, cy + 2, "Z: rot CCW")
      gpu.set(pnx, cy + 3, "D/dn: soft")
      gpu.set(pnx, cy + 4, "SPC: drop")
      gpu.set(pnx, cy + 5, "P:pause " .. quitLabel() .. ":quit")
    end
  end

  
  local function updatePanel(score, lines, level, nxt)
    gpu.setBackground(C.empty)

    gpu.setForeground(C.text)
    gpu.set(pnx, pny + 1, D.fit(tostring(score), pniw))
    gpu.set(pnx, pny + 4, D.fit(tostring(lines), pniw))
    gpu.set(pnx, pny + 7, D.fit(tostring(level), pniw))

    
    for r = 0, 3 do
      gpu.setBackground(C.empty)
      gpu.fill(pnx, pny + 10 + r, pniw, 1, " ")
    end
    if nxt then
      for _, off in ipairs(PIECES[nxt][1]) do
        local sx = pnx + off[1] * CW
        local sy = pny + 10 + off[2]
        if tier == 1 then
          gpu.setForeground(0xFFFFFF); gpu.setBackground(C.empty)
          gpu.set(sx, sy, "[]")
        else
          gpu.setBackground(pCol[nxt]); gpu.fill(sx, sy, CW, 1, " ")
        end
      end
    end
  end

  

  local function newBoard()
    local b = {}
    for r = 1, BH do
      b[r] = {}
      for c = 1, BW do b[r][c] = 0 end
    end
    return b
  end

  local function canPlace(board, pt, rot, ox, oy)
    for _, off in ipairs(PIECES[pt][rot]) do
      local c, r = ox + off[1], oy + off[2]
      if c < 0 or c >= BW          then return false end
      if r >= BH                   then return false end
      if r >= 0 and board[r + 1][c + 1] ~= 0 then return false end
    end
    return true
  end

  
  local function calcGhost(board, pt, rot, ox, oy)
    local gy = oy
    while canPlace(board, pt, rot, ox, gy + 1) do gy = gy + 1 end
    return gy
  end

  
  
  

  local bag, bagI = {}, 0

  local function nextPiece()
    if bagI >= #bag then
      bag = {1, 2, 3, 4, 5, 6, 7}
      for i = #bag, 2, -1 do
        local j = math.random(i)
        bag[i], bag[j] = bag[j], bag[i]
      end
      bagI = 0
    end
    bagI = bagI + 1
    return bag[bagI]
  end

  

  local function runGame()
    local board = newBoard()
    local score, lines, level = 0, 0, 1

    bag, bagI = {}, 0
    math.randomseed(math.floor(computer.uptime() * 7331) % 2147483647)

    
    local pt, rot, ox, oy, gy

    
    local nxt = nextPiece()

    

    
    
    
    local function drawPauseOverlay()
      local pw = 14
      local px2 = bx + math.floor((PF_BOX_W - pw) / 2)
      local py2 = by + math.floor(PF_BOX_H / 2) - 1
      D.dbox(px2, py2, pw, 3, "PAUSED", {border = C.title, bg = C.empty})
    end

    local function fullRender()
      drawFrame()
      drawBoard(board)
      updatePanel(score, lines, level, nxt)
      if pt then
        if gy ~= oy then drawOverlay(pt, rot, ox, gy, nil, true) end
        drawOverlay(pt, rot, ox, oy, pCol[pt], false)
      end
    end

    
    local function refresh(oP, oR, oX, oY, oG)
      if oG ~= oY then eraseOverlay(oP, oR, oX, oG, board) end
      eraseOverlay(oP, oR, oX, oY, board)
      if gy ~= oy then drawOverlay(pt, rot, ox, gy, nil, true) end
      drawOverlay(pt, rot, ox, oy, pCol[pt], false)
    end

    
    local function spawn()
      pt  = nxt
      nxt = nextPiece()
      rot = 1
      ox  = math.floor(BW / 2) - 2   
      oy  = -2                         
      gy  = calcGhost(board, pt, rot, ox, oy)
      return canPlace(board, pt, rot, ox, oy)
    end

    
    
    local function lock()
      
      
      
      local color = pCol[pt]
      local aboveBoard = false
      for _, off in ipairs(PIECES[pt][rot]) do
        local c, r = ox + off[1], oy + off[2]
        if r < 0 then
          aboveBoard = true  
        elseif r < BH and c >= 0 and c < BW then
          board[r + 1][c + 1] = color
          drawCell(c, r, color)
        end
      end

      
      if aboveBoard then return false end

      
      local cleared = fullRows(board, BW, BH)

      if #cleared > 0 then
        
        for _, r in ipairs(cleared) do
          gpu.setBackground(0xFFFFFF)
          gpu.fill(pfx, pfy + r - 1, BW * CW, 1, " ")
        end
        E.pull(0.07)   

        
        
        removeRows(board, BW, cleared)

        
        local n = #cleared
        score = score + (LINE_PTS[n] or LINE_PTS[4]) * level
        lines = lines + n
        level = math.floor(lines / 10) + 1

        drawBoard(board)
      end

      
      if not spawn() then return false end

      
      
      
      
      
      
      updatePanel(score, lines, level, nxt)

      if gy ~= oy then drawOverlay(pt, rot, ox, gy, nil, true) end
      drawOverlay(pt, rot, ox, oy, pCol[pt], false)
      return true
    end

    
    local function move(dx, dy)
      if not canPlace(board, pt, rot, ox + dx, oy + dy) then return false end
      local oP, oR, oX, oY, oG = pt, rot, ox, oy, gy
      ox = ox + dx;  oy = oy + dy
      gy = calcGhost(board, pt, rot, ox, oy)
      refresh(oP, oR, oX, oY, oG)
      return true
    end

    
    local function rotate(dir)
      local nr    = ((rot - 1 + dir) % 4) + 1
      for _, k in ipairs(WALL_KICKS) do
        if canPlace(board, pt, nr, ox + k[1], oy + k[2]) then
          local oP, oR, oX, oY, oG = pt, rot, ox, oy, gy
          rot = nr;  ox = ox + k[1];  oy = oy + k[2]
          gy  = calcGhost(board, pt, rot, ox, oy)
          refresh(oP, oR, oX, oY, oG)
          return true
        end
      end
      return false
    end

    

    if not spawn() then return 0, 0, 1, false end
    fullRender()

    local lastDrop = computer.uptime()
    local paused   = false

    while true do
      local speed   = gravity(level)
      local now     = computer.uptime()
      local timeout = paused and 1.0 or math.max(0, speed - (now - lastDrop))

      
      
      
      
      
      
      local sig, _, ch, code = E.pull(timeout)

      
      
      
      
      
      if sig == "tos_focus" then
        paused = true
        fullRender()
        drawPauseOverlay()
        lastDrop = computer.uptime()

      
      elseif sig == "key_down" then

        if code == K.Q or stdQuit(ch, code) then
          return score, lines, level, true   

        elseif code == K.P then
          paused = not paused
          if paused then drawPauseOverlay() else fullRender() end

        elseif not paused then

          if     code == K.LEFT  or code == K.A then  move(-1, 0)
          elseif code == K.RIGHT or code == K.D then  move( 1, 0)
          elseif code == K.UP    or code == K.W
              or code == K.X                    then  rotate(1)
          elseif code == K.Z                    then  rotate(-1)

          elseif code == K.DOWN or code == K.S then
            
            if move(0, 1) then
              score = score + 1
              updatePanel(score, lines, level, nxt)
              lastDrop = computer.uptime()
            else
              if not lock() then return score, lines, level, false end
              lastDrop = computer.uptime()
            end

          elseif code == K.SPACE then
            
            if gy ~= oy then eraseOverlay(pt, rot, ox, gy, board) end
            eraseOverlay(pt, rot, ox, oy, board)
            
            score    = score + 2 * math.max(0, gy - oy)
            oy       = gy
            if not lock() then return score, lines, level, false end
            lastDrop = computer.uptime()
          end
        end
      end

      
      if not paused then
        now = computer.uptime()
        if now - lastDrop >= speed then
          lastDrop = now
          if not move(0, 1) then
            if not lock() then return score, lines, level, false end
          end
        end
      end
    end 
  end 

  

  local function showGameOver(fs, fl, fv, bestScores)
    local dw = PF_BOX_W        
    local dh = 10
    local iw = dw - 4          
    local dx = bx
    local dy = by + math.floor((PF_BOX_H - dh) / 2)

    D.dbox(dx, dy, dw, dh, "GAME OVER",
           {border = C.danger, bg = C.empty})

    gpu.setBackground(C.empty)

    gpu.setForeground(C.text)
    gpu.set(dx + 2, dy + 2, D.fit(string.format("Score: %d", fs), iw))
    gpu.set(dx + 2, dy + 3, D.fit(string.format("Ln: %d  Lv: %d", fl, fv), iw))

    if bestScores and #bestScores > 0 then
      gpu.setForeground(C.score)
      gpu.set(dx + 2, dy + 4, D.fit(string.format("Best: %d", bestScores[1].score), iw))
      
      
      
      local isNew = fs > 0 and fs == bestScores[1].score
          and (#bestScores == 1 or fs > bestScores[2].score)
      if isNew then
        gpu.setForeground(C.hi)
        gpu.set(dx + 2, dy + 5, D.fit("* NEW HIGH SCORE! *", iw))
      end
    end

    gpu.setForeground(C.dim)
    gpu.set(dx + 2, dy + 7, D.fit("[R] Play Again", iw))
    gpu.set(dx + 2, dy + 8, D.fit("[Q] Quit", iw))

    
    while true do
      local sig, _, ch, code = E.pull(120)   
      if sig == "key_down" then
        if code == K.R or code == K.ENTER then return true  end
        if code == K.Q or stdQuit(ch, code) then return false end
      elseif not sig then
        return false   
      end
    end
  end

  
  

  local ok, err = pcall(function()
    local playing = true
    while playing do
      local fs, fl, fv, quit = runGame()
      if quit then
        playing = false
      else
        
        local best = recordScore(path, fs, fl, fv)
        playing = showGameOver(fs, fl, fv, best)
      end
    end
  end)

  D.clear()  
  if not ok then
    o("Tetris crashed: " .. tostring(err), 0xFF0000)
  end
end



local function showScores(o)
  local path = scorePath()
  if not path then
    o("Not logged in — no personal score file to read.", 0xFF6600)
    return
  end

  
  
  
  local user = path:match("^/home/([^/]+)/") or path:match("^/([^/]+)/") or "?"
  local scores = loadScores(path)

  if #scores == 0 then
    o("No high scores yet for " .. user .. ".", 0xAAAAAA)
    o("Play your first game:  tetris", 0x555555)
    return
  end

  o(string.format("  High scores — %s", user), 0xFFFF00)
  o(string.rep("─", 42), 0x444444)
  o(string.format("  %-3s  %-12s  %-8s  %s", "#", "SCORE", "LINES", "LEVEL"), 0xAAAAAA)
  for i, s in ipairs(scores) do
    local star = (i == 1) and " ★" or "  "
    o(string.format("  %-3d  %-12d  %-8d  %d%s", i, s.score, s.lines, s.level, star),
      i == 1 and 0xFFFF00 or 0xFFFFFF)
  end
end



local function tetrisCmd(args, o)
  
  
  
  
  local sub = args[1]

  if sub == nil then
    play(o)

  elseif sub == "scores" or sub == "hs" then
    showScores(o)

  elseif sub == "help" or sub == "--help" or sub == "-h" then
    o("=== Tetris ===", 0xFFFF00)
    o("", 0xFFFFFF)
    o("  tetris           Launch the game (requires T2+ screen, 80×24+)", 0xFFFFFF)
    o("  tetris scores    Show your personal high-score table", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" In-game controls:", 0xAAAAAA)
    o("  ← → / A D       Move left / right", 0xFFFFFF)
    o("  ↑ / W / X       Rotate clockwise", 0xFFFFFF)
    o("  Z               Rotate counter-clockwise", 0xFFFFFF)
    o("  ↓ / S           Soft drop  (+1 pt per row)", 0xFFFFFF)
    o("  Space           Hard drop  (+2 pts per row)", 0xFFFFFF)
    o("  P               Pause / unpause", 0xFFFFFF)
    o("  Q / Esc         Quit to shell", 0xFFFFFF)
    o("", 0xFFFFFF)
    o(" Scoring:", 0xAAAAAA)
    o("  1 line  = 100 × level    2 lines = 300 × level", 0xFFFFFF)
    o("  3 lines = 500 × level    4 lines = 800 × level  (Tetris!)", 0xFFFFFF)
    o("  Level increases every 10 lines; speed increases with level.", 0xAAAAAA)
    o("", 0xFFFFFF)
    o(" High scores are stored in ~/.tetris_hs (one file per user).", 0x555555)

  else
    o("Unknown subcommand: " .. tostring(sub), 0xFF6600)
    o("Usage: tetris [scores | help]", 0xAAAAAA)
  end
end



mod.commands = { tetris = tetrisCmd }

return mod