local display = {}

local gpu = nil
local W, H = 50, 16

local THEME = {
  bg           = 0x000000,
  fg           = 0xE6E6E6,
  border       = 0x2FB8C6,
  title        = 0xFFD75A,
  highlight    = 0x42D77D,
  selected_bg  = 0x0E5E70,
  selected_fg  = 0xFFFFFF,
  menubar_bg   = 0x262B33,
  menubar_fg   = 0xE6E6E6,
  menubar_hot  = 0xFFD75A,
  statusbar_bg = 0x103C4E,
  statusbar_fg = 0xBFE3EE,
  error        = 0xFF5C57,
  warning      = 0xFFA042,
  dim          = 0x909090,
  panel_bg     = 0x000000,
  input_bg     = 0x14181E,
  input_fg     = 0xFFFFFF,

  syn_keyword  = 0x61AFEF,
  syn_string   = 0x98C379,
  syn_comment  = 0x7A828E,
  syn_number   = 0xD19A66,
  syn_func     = 0xE5C07B,

  file_lua     = 0x56B6C2,
  dir_color    = 0x42D77D,
}

local BOX_UNICODE = {
  tl = "┌", tr = "┐", bl = "└", br = "┘",
  h  = "─", v  = "│",
  lt = "├", rt = "┤", tt = "┬", bt = "┴",
  cross = "┼",
  DTL = "╔", DTR = "╗", DBL = "╚", DBR = "╝",
  DH  = "═", DV  = "║",
}
local BOX_ASCII = {
  tl = "+", tr = "+", bl = "+", br = "+",
  h  = "-", v  = "|",
  lt = "+", rt = "+", tt = "+", bt = "+",
  cross = "+",
  DTL = "+", DTR = "+", DBL = "+", DBR = "+",
  DH  = "=", DV  = "|",
}

local BOX = BOX_UNICODE

local gpuDepth = 1
local gpuTier = 1

local _lastFg, _lastBg = nil, nil

local syncDerivedTheme

local displayLost = false
local function guardGpu(px)

  local fallback = {
    getResolution = function() return W, H end,
    maxResolution = function() return W, H end,
    getViewport   = function() return W, H end,
    getDepth      = function() return gpuDepth end,
    getBackground = function() return _lastBg or 0x000000 end,
    getForeground = function() return _lastFg or 0xFFFFFF end,
    get           = function() return " ", _lastFg or 0xFFFFFF, _lastBg or 0x000000 end,
  }
  local wrapped = { _tosRawGpu = px }
  return setmetatable(wrapped, { __index = function(t, k)
    local v = px[k]
    if type(v) ~= "function" then return v end
    local fn = function(...)
      if not displayLost then
        local ok, a, b, c, d, e = pcall(v, ...)
        if ok then return a, b, c, d, e end
        displayLost = true
        pcall(function()
          require("computer").pushSignal("tos_display_lost", tostring(a))
        end)
      end
      local fb = fallback[k]
      if fb then return fb() end
      return true
    end
    rawset(t, k, fn)
    return fn
  end })
end

function display.isLost() return displayLost end

function display.init(gpuProxy, width, height)

  displayLost = false
  if gpuProxy and not gpuProxy._tosRawGpu then
    gpuProxy = guardGpu(gpuProxy)
  end
  gpu = gpuProxy
  if gpu then

    if type(width) == "number" and type(height) == "number"
        and width > 0 and height > 0 then
      pcall(gpu.setResolution, width, height)
    else
      local ok0, maxW, maxH = pcall(gpu.maxResolution)
      if ok0 and maxW and maxH then
        pcall(gpu.setResolution, maxW, maxH)
      end
    end
    W, H = gpu.getResolution()

    local ok, depth = pcall(gpu.getDepth)
    if ok and depth then
      gpuDepth = depth
      if depth <= 1 then gpuTier = 1
      elseif depth <= 4 then gpuTier = 2
      else gpuTier = 3 end
    end

    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)

    _lastBg, _lastFg = 0x000000, 0xFFFFFF
    if not _G._BIOS_CY then
      gpu.fill(1, 1, W, H, " ")
    end

    if gpuTier == 1 then

      BOX = BOX_ASCII

      THEME.bg           = 0x000000
      THEME.fg           = 0xFFFFFF

      THEME.border       = 0xFFFFFF
      THEME.title        = 0xFFFFFF
      THEME.highlight    = 0xFFFFFF
      THEME.dim          = 0xFFFFFF
      THEME.error        = 0xFFFFFF
      THEME.warning      = 0xFFFFFF

      THEME.panel_bg     = 0x000000
      THEME.input_bg     = 0x000000

      THEME.selected_bg  = 0xFFFFFF
      THEME.selected_fg  = 0x000000

      THEME.menubar_bg   = 0xFFFFFF
      THEME.menubar_fg   = 0x000000
      THEME.menubar_hot  = 0x000000

      THEME.statusbar_bg = 0xFFFFFF
      THEME.statusbar_fg = 0x000000

      THEME.syn_keyword  = 0xFFFFFF
      THEME.syn_string   = 0xFFFFFF
      THEME.syn_comment  = 0xFFFFFF
      THEME.syn_number   = 0xFFFFFF
      THEME.syn_func     = 0xFFFFFF
      THEME.file_lua     = 0xFFFFFF
      THEME.dir_color    = 0xFFFFFF

      syncDerivedTheme()

    elseif gpuTier == 2 then

      THEME.fg           = 0xFFFFFF
      THEME.dim          = 0xCCCCCC
      THEME.border       = 0x6699FF
      THEME.title        = 0xFFFF33
      THEME.highlight    = 0x33CC33
      THEME.warning      = 0xFFCC33
      THEME.error        = 0xFF3333
      THEME.selected_bg  = 0x336699
      THEME.selected_fg  = 0xFFFFFF
      THEME.menubar_bg   = 0x333333
      THEME.menubar_fg   = 0xFFFFFF
      THEME.menubar_hot  = 0xFFCC33
      THEME.statusbar_bg = 0x336699
      THEME.statusbar_fg = 0xFFFFFF
      THEME.input_bg     = 0x333333

      THEME.syn_keyword  = 0x6699FF
      THEME.syn_string   = 0x33CC33
      THEME.syn_comment  = 0xCCCCCC
      THEME.syn_number   = 0xFFCC33
      THEME.syn_func     = 0xFFFF33
      THEME.file_lua     = 0x6699FF
      THEME.dir_color    = 0x33CC33

      syncDerivedTheme()

    else

      THEME.syn_keyword  = 0x61AFEF
      THEME.syn_string   = 0x98C379
      THEME.syn_comment  = 0x7A828E
      THEME.syn_number   = 0xD19A66
      THEME.syn_func     = 0xE5C07B
      THEME.file_lua     = 0x56B6C2
      THEME.dir_color    = 0x42D77D

      syncDerivedTheme()
    end
  end
  if width then W = width end
  if height then H = height end
end

function display.getGpuTier()
  return gpuTier
end

function display.getGpuDepth()
  return gpuDepth
end

function display.isMonochrome()
  return gpuDepth <= 1
end

function display.getSize()
  return W, H
end

function display.refreshSize()
  if gpu then
    local ok, w, h = pcall(gpu.getResolution)
    if ok and w and h then W, H = w, h end
  end
  return W, H
end

function display.getTheme()
  return THEME
end

local COLOR_ALIAS = {

  bar_fg      = "menubar_fg",
  bar_bg      = "menubar_bg",
  bar_accent  = "menubar_hot",

  statusbar_fg = "statusbar_fg",
  statusbar_bg = "statusbar_bg",

  prompt    = "highlight",
  title     = "title",
  dim       = "dim",
  border    = "border",

  dir       = "dir_color",
  file      = "fg",
  file_exec = "highlight",
  file_cfg  = "warning",
  file_log  = "dim",
  file_lua  = "file_lua",

  success   = "highlight",
  warning   = "warning",
  error     = "error",
}

function display.c(name)

  local v = THEME[name]
  if v ~= nil then return v end

  local k = COLOR_ALIAS[name]
  if k and THEME[k] ~= nil then
    return THEME[k]
  end

  return THEME.fg
end

local function ensureContrast(fg, bg, label)
  if fg ~= bg then return fg end

  local fixed
  if bg == 0xFFFFFF then fixed = 0x000000
  elseif bg == 0x000000 then fixed = 0xFFFFFF
  else

    fixed = 0xFFFFFF - bg
  end

  local ok, logMod = pcall(require, "kernel.log")
  if ok and logMod and logMod.warn then
    logMod.warn("display", string.format(
      "%s fg/bg collision (both 0x%06X); forcing fg to 0x%06X",
      label or "?", bg, fixed))
  end
  return fixed
end

syncDerivedTheme = function()
  THEME.panel_active   = THEME.border
  THEME.panel_inactive = THEME.dim

  THEME.sel_bg = THEME.selected_bg
  THEME.sel_fg = ensureContrast(THEME.selected_fg, THEME.selected_bg, "selection")

  THEME.dir       = THEME.highlight
  THEME.file      = THEME.fg
  THEME.file_exec = THEME.highlight
  THEME.file_cfg  = THEME.warning
  THEME.file_log  = THEME.dim

  THEME.bar_fg     = ensureContrast(THEME.menubar_fg, THEME.menubar_bg, "menubar")
  THEME.bar_bg     = THEME.menubar_bg
  THEME.bar_accent = THEME.menubar_hot

  THEME.statusbar_fg = ensureContrast(THEME.statusbar_fg, THEME.statusbar_bg, "statusbar")
end
syncDerivedTheme()

local OVERRIDABLE_KEYS = {
  bg = true, fg = true,
  border = true, title = true, highlight = true, dim = true,
  error = true, warning = true,

  panel_bg = true, input_bg = true, input_fg = true,
  selected_bg = true, selected_fg = true,
  menubar_bg = true, menubar_fg = true, menubar_hot = true,
  statusbar_bg = true, statusbar_fg = true,
  syn_keyword = true, syn_string = true, syn_comment = true,
  syn_number = true, syn_func = true,
  file_lua = true, dir_color = true,
}

local function isValidColor(v)
  return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 0xFFFFFF
end

local OC_T2_PALETTE = {
  0xFFFFFF, 0xFFCC33, 0xCC66CC, 0x6699FF, 0xFFFF33, 0x33CC33,
  0xFF6699, 0x333333, 0xCCCCCC, 0x336699, 0x9933CC, 0x333399,
  0x663300, 0x336600, 0xFF3333, 0x000000,
}

local OC_T2_GREYS = { 0xFFFFFF, 0xCCCCCC, 0x333333, 0x000000 }
local function snapToT2(rgb)
  local r = (rgb >> 16) & 0xFF
  local g = (rgb >> 8) & 0xFF
  local b = rgb & 0xFF
  local spread = math.max(r, g, b) - math.min(r, g, b)
  local candidates = (spread <= 32) and OC_T2_GREYS or OC_T2_PALETTE
  local best, bestD
  for _, c in ipairs(candidates) do
    local dr = r - ((c >> 16) & 0xFF)
    local dg = g - ((c >> 8) & 0xFF)
    local db = b - (c & 0xFF)

    local d = dr * dr * 3 + dg * dg * 4 + db * db * 2
    if not bestD or d < bestD then bestD, best = d, c end
  end
  return best
end
display._snapToT2 = snapToT2

function display.setTheme(overrides)
  if type(overrides) ~= "table" then return false, "overrides must be a table" end

  local snap = (gpuDepth == 4)
  local applied = 0
  for k, v in pairs(overrides) do
    if OVERRIDABLE_KEYS[k] and isValidColor(v) then
      THEME[k] = snap and snapToT2(v) or v
      applied = applied + 1
    end

  end
  syncDerivedTheme()
  return true, applied
end

local function _setFg(fg)
  if fg ~= _lastFg then
    gpu.setForeground(fg)
    _lastFg = fg
  end
end

local function _setBg(bg)
  if bg ~= _lastBg then
    gpu.setBackground(bg)
    _lastBg = bg
  end
end

function display.invalidateColors()
  _lastFg, _lastBg = nil, nil
end

function display.set(x, y, text, fg, bg)
  if not gpu then return end
  if fg then _setFg(fg) end
  if bg then _setBg(bg) end
  gpu.set(x, y, text)
end

function display.fill(x, y, w, h, char, fg, bg)
  if not gpu then return end
  if fg then _setFg(fg) end
  if bg then _setBg(bg) end
  gpu.fill(x, y, w, h, char or " ")
end

function display.clear(bg)
  display.fill(1, 1, W, H, " ", nil, bg or THEME.bg)
end

function display.getGpu()
  return gpu
end

function display.scrollUp(startRow, endRow)
  if not gpu then return end
  startRow = startRow or 1
  endRow = endRow or H
  local rows = endRow - startRow
  if rows < 1 then return end

  gpu.copy(1, startRow + 1, W, rows, 0, -1)

  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  _lastBg, _lastFg = 0x000000, 0xFFFFFF
  gpu.fill(1, endRow, W, 1, " ")
end

function display.box(x, y, w, h, title, style)
  style = style or {}
  local fg = style.border or THEME.border
  local bg = style.bg or THEME.panel_bg
  local titleColor = style.title or THEME.title

  display.fill(x, y, w, h, " ", THEME.fg, bg)

  display.set(x, y, BOX.tl, fg, bg)
  display.set(x + 1, y, string.rep(BOX.h, w - 2), fg, bg)
  display.set(x + w - 1, y, BOX.tr, fg, bg)

  display.set(x, y + h - 1, BOX.bl, fg, bg)
  display.set(x + 1, y + h - 1, string.rep(BOX.h, w - 2), fg, bg)
  display.set(x + w - 1, y + h - 1, BOX.br, fg, bg)

  for row = y + 1, y + h - 2 do
    display.set(x, row, BOX.v, fg, bg)
    display.set(x + w - 1, row, BOX.v, fg, bg)
  end

  if title then
    local tstr = " " .. title .. " "
    local tx = x + math.floor((w - #tstr) / 2)
    display.set(tx, y, tstr, titleColor, bg)
  end
end

function display.dbox(x, y, w, h, title, style)
  style = style or {}
  local fg = style.border or THEME.border
  local bg = style.bg or THEME.panel_bg
  local titleColor = style.title or THEME.title

  display.fill(x, y, w, h, " ", THEME.fg, bg)

  display.set(x, y, BOX.DTL, fg, bg)
  display.set(x + 1, y, string.rep(BOX.DH, w - 2), fg, bg)
  display.set(x + w - 1, y, BOX.DTR, fg, bg)

  display.set(x, y + h - 1, BOX.DBL, fg, bg)
  display.set(x + 1, y + h - 1, string.rep(BOX.DH, w - 2), fg, bg)
  display.set(x + w - 1, y + h - 1, BOX.DBR, fg, bg)

  for row = y + 1, y + h - 2 do
    display.set(x, row, BOX.DV, fg, bg)
    display.set(x + w - 1, row, BOX.DV, fg, bg)
  end

  if title then
    local tstr = " " .. title .. " "
    local tx = x + math.floor((w - #tstr) / 2)
    display.set(tx, y, tstr, titleColor, bg)
  end
end

function display.hdivider(x, y, w, style)
  local fg = (style and style.border) or THEME.border
  local bg = (style and style.bg) or THEME.panel_bg
  display.set(x, y, BOX.lt, fg, bg)
  display.set(x + 1, y, string.rep(BOX.h, w - 2), fg, bg)
  display.set(x + w - 1, y, BOX.rt, fg, bg)
end

function display.menuBar(items)
  display.fill(1, 1, W, 1, " ", THEME.menubar_fg, THEME.menubar_bg)
  local x = 2
  for _, item in ipairs(items) do
    local label = item.label or ""

    local hk = item.hotkey
    if hk then
      local pos = label:find(hk, 1, true)
      if pos then
        display.set(x, 1, label:sub(1, pos - 1), THEME.menubar_fg, THEME.menubar_bg)
        display.set(x + pos - 1, 1, hk, THEME.menubar_hot, THEME.menubar_bg)
        display.set(x + pos, 1, label:sub(pos + 1), THEME.menubar_fg, THEME.menubar_bg)
      else
        display.set(x, 1, label, THEME.menubar_fg, THEME.menubar_bg)
      end
    else
      display.set(x, 1, label, THEME.menubar_fg, THEME.menubar_bg)
    end
    x = x + #label + 2
  end
end

function display.statusBar(left, right, row)
  row = row or H
  display.fill(1, row, W, 1, " ", THEME.statusbar_fg, THEME.statusbar_bg)
  if left then
    display.set(2, row, left, THEME.statusbar_fg, THEME.statusbar_bg)
  end
  if right then
    display.set(W - #right + 1, row, right, THEME.statusbar_fg, THEME.statusbar_bg)
  end
end

function display.fkeyBar(items, row)
  row = row or H
  display.fill(1, row, W, 1, " ", THEME.fg, THEME.menubar_bg)
  local x = 1
  local itemW = math.floor(W / math.max(#items, 1))
  for _, item in ipairs(items) do
    local key   = "[" .. (item.key or "") .. "]"
    local label = item.label or ""
    display.set(x, row, key,   THEME.dim,       THEME.menubar_bg)
    display.set(x + #key, row, label, THEME.menubar_fg, THEME.menubar_bg)
    x = x + itemW
  end
end

function display.fit(text, width, align)
  text = tostring(text or "")
  if #text > width then
    return text:sub(1, width - 1) .. "…"
  elseif align == "right" then
    return string.rep(" ", width - #text) .. text
  elseif align == "center" then
    local pad = width - #text
    local left = math.floor(pad / 2)
    return string.rep(" ", left) .. text .. string.rep(" ", pad - left)
  else
    return text .. string.rep(" ", width - #text)
  end
end

function display.writeWrapped(x, y, w, maxH, text, fg, bg)
  fg = fg or THEME.fg
  bg = bg or THEME.panel_bg
  local lines = 0

  local pos = 1
  while pos <= #text + 1 and lines < maxH do
    local nl = text:find("\n", pos, true) or (#text + 1)
    local line = text:sub(pos, nl - 1)
    pos = nl + 1
    if #line == 0 then
      display.set(x, y + lines, display.fit("", w), fg, bg)
      lines = lines + 1
    else
      while #line > 0 and lines < maxH do
        local chunk = line:sub(1, w)
        display.set(x, y + lines, display.fit(chunk, w), fg, bg)
        line = line:sub(w + 1)
        lines = lines + 1
      end
    end
  end
  return lines
end

function display.dialog(title, message, buttons)
  buttons = buttons or {"OK"}
  local msgLines = {}

  local mpos = 1
  while mpos <= #message + 1 do
    local nl = message:find("\n", mpos, true) or (#message + 1)
    msgLines[#msgLines + 1] = message:sub(mpos, nl - 1)
    mpos = nl + 1
  end
  if #msgLines == 0 then msgLines[1] = "" end

  local maxLen = #title + 4
  for _, line in ipairs(msgLines) do
    if #line > maxLen then maxLen = #line end
  end
  local btnLen = 0
  for _, b in ipairs(buttons) do btnLen = btnLen + #b + 4 end
  if btnLen > maxLen then maxLen = btnLen end

  local dw = math.min(maxLen + 4, W - 4)
  local dh = #msgLines + 5
  local dx = math.floor((W - dw) / 2) + 1
  local dy = math.floor((H - dh) / 2) + 1

  display.dbox(dx, dy, dw, dh, title)

  for i, line in ipairs(msgLines) do
    display.set(dx + 2, dy + 1 + i - 1, display.fit(line, dw - 4), THEME.fg, THEME.panel_bg)
  end

  local bx = dx + math.floor((dw - btnLen) / 2)
  local by = dy + dh - 2
  local btnPositions = {}
  for i, b in ipairs(buttons) do
    local label = "[ " .. b .. " ]"
    btnPositions[i] = { x = bx, label = b }
    if i == 1 then
      display.set(bx, by, label, THEME.selected_fg, THEME.selected_bg)
    else
      display.set(bx, by, label, THEME.fg, THEME.panel_bg)
    end
    bx = bx + #label + 2
  end

  return btnPositions, by
end

function display.menuBarEx(items, activeIdx, focusMode, row)
  row = row or 1
  display.fill(1, row, W, 1, " ", THEME.menubar_fg, THEME.menubar_bg)
  local x = 2
  for i, item in ipairs(items) do
    local label = " " .. (item.label or "") .. " "
    if focusMode and i == activeIdx then
      display.set(x, row, label, THEME.sel_fg, THEME.sel_bg)
    else
      display.set(x, row, label, THEME.menubar_fg, THEME.menubar_bg)
    end

    item._x = x
    item._w = #label
    x = x + #label + 1
  end
end

function display.dropdown(x, y, items, selectedIdx)

  local maxLabelW = 0
  local maxKeyW = 0
  for _, item in ipairs(items) do
    if not item.sep then
      maxLabelW = math.max(maxLabelW, #(item.label or ""))
      maxKeyW = math.max(maxKeyW, #(item.key or ""))
    end
  end
  local gap = maxKeyW > 0 and 2 or 0
  local innerW = maxLabelW + gap + maxKeyW
  local dw = innerW + 4
  local dh = #items + 2

  if x + dw > W then x = W - dw end
  if x < 1 then x = 1 end
  if y + dh > H then y = H - dh end
  if y < 1 then y = 1 end

  display.box(x, y, dw, dh, nil, {
    border = THEME.border, bg = THEME.panel_bg,
  })

  local row = y + 1
  for i, item in ipairs(items) do
    if item.sep then
      display.hdivider(x, row, dw)
    else
      local line = " " .. display.fit(item.label or "", maxLabelW)
      if maxKeyW > 0 then
        line = line .. "  " .. display.fit(item.key or "", maxKeyW, "right")
      end
      line = line .. " "
      if i == selectedIdx then
        display.set(x + 1, row, line, THEME.sel_fg, THEME.sel_bg)
      else
        local fg = item.disabled and THEME.dim or THEME.fg
        display.set(x + 1, row, line, fg, THEME.panel_bg)
      end
    end
    row = row + 1
  end

  return dw, dh
end

display.contextMenu = display.dropdown

local function sameGpu(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return true end
  local okA, aa = pcall(function() return a.address end)
  local okB, bb = pcall(function() return b.address end)
  if not okA or not okB or aa == nil or bb == nil then return true end
  return aa == bb
end

function display.withContext(gpuOverride, wOverride, hOverride, fn)
  local oldGpu, oldW, oldH = gpu, W, H
  local oldFg, oldBg = _lastFg, _lastBg
  gpu, W, H = gpuOverride, wOverride, hOverride

  _lastFg, _lastBg = nil, nil
  local results = table.pack(pcall(fn))
  gpu, W, H = oldGpu, oldW, oldH

  if sameGpu(gpuOverride, oldGpu) then
    _lastFg, _lastBg = nil, nil
  else
    _lastFg, _lastBg = oldFg, oldBg
  end

  if results[1] then return table.unpack(results, 2, results.n)
  else error(results[2], 2) end
end

display.BOX = BOX
display.THEME = THEME

return display
