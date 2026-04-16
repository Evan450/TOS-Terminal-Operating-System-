-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Display / TUI Engine   ║
-- ║  ASCII box-drawing, panels, menus    ║
-- ╚══════════════════════════════════════╝

local display = {}

-- GPU reference (set during init)
local gpu = nil
local W, H = 50, 16  -- Current resolution

-- Color scheme - uses ONLY colors guaranteed in OC's palette
-- on ALL GPU tiers (T1: black/white, T2: 16 MC colors, T3: 256)
-- Primary rule: backgrounds are ALWAYS 0x000000 (black)
-- This ensures visibility on any hardware combination.
local THEME = {
  bg           = 0x000000,  -- Black background (safe everywhere)
  fg           = 0xFFFFFF,  -- White text
  border       = 0x00FFFF,  -- Cyan borders
  title        = 0xFFFF00,  -- Yellow titles
  highlight    = 0x00FF00,  -- Green highlights
  selected_bg  = 0x00FFFF,  -- Cyan selection background
  selected_fg  = 0x000000,  -- Black text on selection
  menubar_bg   = 0xFFFFFF,  -- White menu bar
  menubar_fg   = 0x000000,  -- Black menu text
  menubar_hot  = 0xFF0000,  -- Red hotkeys
  statusbar_bg = 0x00FFFF,  -- Cyan status bar
  statusbar_fg = 0x000000,  -- Black status text
  error        = 0xFF0000,  -- Red errors
  warning      = 0xFFFF00,  -- Yellow warnings
  dim          = 0xC0C0C0,  -- Light gray (silver)
  panel_bg     = 0x000000,  -- Black panel background
  input_bg     = 0x000000,  -- Input field background
  input_fg     = 0xFFFFFF,  -- Input field text
  -- Syntax highlighting (T2/T3 only; T1 overrides to white)
  syn_keyword  = 0x5555FF,  -- Blue keywords
  syn_string   = 0x55FF55,  -- Green strings
  syn_comment  = 0xAAAAAA,  -- Gray comments
  syn_number   = 0xFFAA00,  -- Orange numbers
  syn_func     = 0xFFFF55,  -- Yellow builtins
  -- Extended file type colors
  file_lua     = 0x55FFFF,  -- Cyan for .lua
  dir_color    = 0x55FF55,  -- Green for directories
}

-- Box-drawing characters — two sets:
-- Unicode (T2/T3 GPUs that support the OC unicode font)
-- ASCII fallback (T1 GPUs where box-drawing chars may render as '?')
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
-- Active set (selected during init based on GPU tier)
local BOX = BOX_UNICODE

-- ============================================================
-- Initialization
-- ============================================================

-- GPU tier info
local gpuDepth = 1   -- Color depth (1, 4, or 8 bit)
local gpuTier = 1    -- 1, 2, or 3 (default to worst case)

function display.init(gpuProxy, width, height)
  gpu = gpuProxy
  if gpu then
    W, H = gpu.getResolution()

    -- Clamp resolution to maxResolution (accounts for screen tier).
    -- On T3 GPU + T2 screen, maxRes returns the screen's limit, not the GPU's.
    local ok0, maxW, maxH = pcall(gpu.maxResolution)
    if ok0 and maxW and maxH then
      if W > maxW or H > maxH then
        W = math.min(W, maxW)
        H = math.min(H, maxH)
        pcall(gpu.setResolution, W, H)
      end
    end

    local ok, depth = pcall(gpu.getDepth)
    if ok and depth then
      gpuDepth = depth
      if depth <= 1 then gpuTier = 1
      elseif depth <= 4 then gpuTier = 2
      else gpuTier = 3 end
    end

    -- Set safe colors; only clear screen on fresh boot (not BIOS continuation)
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    if not _G._BIOS_CY then
      gpu.fill(1, 1, W, H, " ")
    end

    if gpuTier == 1 then
      -- T1: Strictly monochrome (1-bit). Only black and white.
      -- Use ASCII box drawing since T1 GPUs may not render Unicode.
      BOX = BOX_ASCII

      THEME.bg           = 0x000000
      THEME.fg           = 0xFFFFFF

      THEME.border       = 0xFFFFFF
      THEME.title        = 0xFFFFFF
      THEME.highlight    = 0xFFFFFF
      THEME.dim          = 0xFFFFFF
      THEME.error        = 0xFFFFFF
      THEME.warning      = 0xFFFFFF

      -- Keep bg black to avoid “full white screen” on T1
      THEME.panel_bg     = 0x000000
      THEME.input_bg     = 0x000000

      -- Selection: inverted (white bg + black fg), localized only
      THEME.selected_bg  = 0xFFFFFF
      THEME.selected_fg  = 0x000000

      -- Menu/status bars: inverted for visual distinction
      THEME.menubar_bg   = 0xFFFFFF
      THEME.menubar_fg   = 0x000000
      THEME.menubar_hot  = 0x000000

      THEME.statusbar_bg = 0xFFFFFF
      THEME.statusbar_fg = 0x000000

      -- Syntax: all white on T1
      THEME.syn_keyword  = 0xFFFFFF
      THEME.syn_string   = 0xFFFFFF
      THEME.syn_comment  = 0xFFFFFF
      THEME.syn_number   = 0xFFFFFF
      THEME.syn_func     = 0xFFFFFF
      THEME.file_lua     = 0xFFFFFF
      THEME.dir_color    = 0xFFFFFF

      -- Re-sync derived fields
      THEME.panel_active   = THEME.border
      THEME.panel_inactive = THEME.dim
      THEME.sel_bg         = THEME.selected_bg
      THEME.sel_fg         = THEME.selected_fg
      THEME.dir            = THEME.highlight
      THEME.file_exec      = THEME.highlight
      THEME.file_cfg       = THEME.warning
      THEME.file_log       = THEME.dim

    elseif gpuTier == 2 then
      -- T2: 4-bit color (16 Minecraft dye palette colors).
      -- Map theme colors to nearest T2 palette entries.
      -- OC auto-maps, but explicit values avoid surprising shifts.
      THEME.dim          = 0xAAAAAA  -- Silver (exact T2 palette match)
      THEME.border       = 0x55FFFF  -- Aqua/cyan (T2 palette)
      THEME.selected_bg  = 0x55FFFF  -- Aqua/cyan
      THEME.statusbar_bg = 0x55FFFF  -- Aqua/cyan
      THEME.highlight    = 0x55FF55  -- Lime green (T2 palette)
      THEME.title        = 0xFFFF55  -- Yellow (T2 palette)
      THEME.warning      = 0xFFFF55  -- Yellow
      THEME.error        = 0xFF5555  -- Red (T2 palette)
      THEME.menubar_hot  = 0xFF5555  -- Red

      -- T2 syntax colors (map to nearest 16-color palette)
      THEME.syn_keyword  = 0x5555FF  -- Blue
      THEME.syn_string   = 0x55FF55  -- Lime green
      THEME.syn_comment  = 0xAAAAAA  -- Silver
      THEME.syn_number   = 0xFFFF55  -- Yellow (T2 has no orange)
      THEME.syn_func     = 0xFFFF55  -- Yellow
      THEME.file_lua     = 0x55FFFF  -- Aqua
      THEME.dir_color    = 0x55FF55  -- Lime green

      -- Re-sync derived fields for T2
      THEME.panel_active   = THEME.border
      THEME.panel_inactive = THEME.dim
      THEME.sel_bg         = THEME.selected_bg
      THEME.sel_fg         = THEME.selected_fg
      THEME.dir            = THEME.highlight
      THEME.file_exec      = THEME.highlight
      THEME.file_cfg       = THEME.warning
      THEME.file_log       = THEME.dim

    else
      -- T3: 8-bit color (256 colors). Richer palette.
      THEME.syn_keyword  = 0x6699FF  -- Soft blue
      THEME.syn_string   = 0x55FF55  -- Green
      THEME.syn_comment  = 0x888888  -- Medium gray
      THEME.syn_number   = 0xFFAA00  -- Orange
      THEME.syn_func     = 0xFFFF55  -- Yellow
      THEME.file_lua     = 0x55FFFF  -- Cyan
      THEME.dir_color    = 0x55FF55  -- Green

      -- Re-sync derived fields for T3
      THEME.panel_active   = THEME.border
      THEME.panel_inactive = THEME.dim
      THEME.sel_bg         = THEME.selected_bg
      THEME.sel_fg         = THEME.selected_fg
      THEME.dir            = THEME.highlight
      THEME.file_exec      = THEME.highlight
      THEME.file_cfg       = THEME.warning
      THEME.file_log       = THEME.dim
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

--- Returns true if the GPU is monochrome (T1, 1-bit)
function display.isMonochrome()
  return gpuDepth <= 1
end

function display.getSize()
  return W, H
end

function display.getTheme()
  return THEME
end

function display.setTheme(overrides)
  for k, v in pairs(overrides) do
    THEME[k] = v
  end
  syncDerivedTheme()
end

-- ----------------------------------------------------------------
-- Color helper: allow shell to ask for named colors via D.c("name")
-- ----------------------------------------------------------------
local COLOR_ALIAS = {
  -- Shell title bar
  bar_fg      = "menubar_fg",
  bar_bg      = "menubar_bg",
  bar_accent  = "menubar_hot",

  -- Shell status bar
  statusbar_fg = "statusbar_fg",
  statusbar_bg = "statusbar_bg",

  -- Generic UI labels
  prompt    = "highlight",
  title     = "title",
  dim       = "dim",
  border    = "border",

  -- File listing colors (shell uses these names)
  dir       = "dir_color",
  file      = "fg",
  file_exec = "highlight",
  file_cfg  = "warning",
  file_log  = "dim",
  file_lua  = "file_lua",

  -- Messages
  success   = "highlight",
  warning   = "warning",
  error     = "error",
}

function display.c(name)
  -- direct theme key?
  local v = THEME[name]
  if v ~= nil then return v end

  -- alias?
  local k = COLOR_ALIAS[name]
  if k and THEME[k] ~= nil then
    return THEME[k]
  end

  -- safe fallback
  return THEME.fg
end

-- Sync derived theme fields from base values.
-- Called at module load, after init(), and after setTheme().
local function syncDerivedTheme()
  THEME.panel_active   = THEME.border
  THEME.panel_inactive = THEME.dim

  THEME.sel_bg = THEME.selected_bg
  THEME.sel_fg = THEME.selected_fg

  THEME.dir       = THEME.highlight
  THEME.file      = THEME.fg
  THEME.file_exec = THEME.highlight
  THEME.file_cfg  = THEME.warning
  THEME.file_log  = THEME.dim
end
syncDerivedTheme()

-- ============================================================
-- Low-level drawing
-- ============================================================

function display.set(x, y, text, fg, bg)
  if not gpu then return end
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.set(x, y, text)
end

function display.fill(x, y, w, h, char, fg, bg)
  if not gpu then return end
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.fill(x, y, w, h, char or " ")
end

function display.clear(bg)
  display.fill(1, 1, W, H, " ", nil, bg or THEME.bg)
end

--- Get raw GPU proxy (for emergency shell etc.)
function display.getGpu()
  return gpu
end

--- Scroll the screen up by one line, clearing the bottom line
function display.scrollUp(startRow, endRow)
  if not gpu then return end
  startRow = startRow or 1
  endRow = endRow or H
  local rows = endRow - startRow
  if rows < 1 then return end
  -- Copy rows up by one
  gpu.copy(1, startRow + 1, W, rows, 0, -1)
  -- Clear the bottom row with explicit black background
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, endRow, W, 1, " ")
end

-- ============================================================
-- Box drawing
-- ============================================================

--- Draw a box with single-line border
function display.box(x, y, w, h, title, style)
  style = style or {}
  local fg = style.border or THEME.border
  local bg = style.bg or THEME.panel_bg
  local titleColor = style.title or THEME.title

  -- Fill interior
  display.fill(x, y, w, h, " ", THEME.fg, bg)

  -- Top border
  display.set(x, y, BOX.tl, fg, bg)
  display.set(x + 1, y, string.rep(BOX.h, w - 2), fg, bg)
  display.set(x + w - 1, y, BOX.tr, fg, bg)

  -- Bottom border
  display.set(x, y + h - 1, BOX.bl, fg, bg)
  display.set(x + 1, y + h - 1, string.rep(BOX.h, w - 2), fg, bg)
  display.set(x + w - 1, y + h - 1, BOX.br, fg, bg)

  -- Side borders
  for row = y + 1, y + h - 2 do
    display.set(x, row, BOX.v, fg, bg)
    display.set(x + w - 1, row, BOX.v, fg, bg)
  end

  -- Title
  if title then
    local tstr = " " .. title .. " "
    local tx = x + math.floor((w - #tstr) / 2)
    display.set(tx, y, tstr, titleColor, bg)
  end
end

--- Draw a double-line box (for emphasis/dialogs)
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

-- ============================================================
-- Horizontal divider (inside a box)
-- ============================================================
function display.hdivider(x, y, w, style)
  local fg = (style and style.border) or THEME.border
  local bg = (style and style.bg) or THEME.panel_bg
  display.set(x, y, BOX.lt, fg, bg)
  display.set(x + 1, y, string.rep(BOX.h, w - 2), fg, bg)
  display.set(x + w - 1, y, BOX.rt, fg, bg)
end

-- ============================================================
-- Menu bar (top of screen)
-- ============================================================

--- Draw a menu bar at the top
-- items: { {label="File", hotkey="F", action=fn}, ... }
function display.menuBar(items)
  display.fill(1, 1, W, 1, " ", THEME.menubar_fg, THEME.menubar_bg)
  local x = 2
  for _, item in ipairs(items) do
    local label = item.label or ""
    -- Highlight the hotkey character
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

-- ============================================================
-- Status bar (bottom of screen)
-- ============================================================

--- Draw a status bar at the bottom
-- left: left-aligned text, right: right-aligned text
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

-- ============================================================
-- Function key bar (like Norton Commander)
-- ============================================================

--- Draw F-key bar: { {key="F1", label="Help"}, ... }
-- Keys are shown as [F1] so the bracket delimiters remain readable on
-- monochrome T1 GPUs where color alone cannot distinguish key from label.
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

-- ============================================================
-- Text utilities
-- ============================================================

--- Truncate or pad a string to fit width
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

--- Write text within a region, word-wrapping
function display.writeWrapped(x, y, w, maxH, text, fg, bg)
  fg = fg or THEME.fg
  bg = bg or THEME.panel_bg
  local lines = 0
  -- Split preserving empty lines (gmatch("[^\n]+") skips them)
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

-- ============================================================
-- Simple dialog box
-- ============================================================

--- Show a centered message dialog
function display.dialog(title, message, buttons)
  buttons = buttons or {"OK"}
  local msgLines = {}
  -- Split preserving empty lines
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

  -- Message lines
  for i, line in ipairs(msgLines) do
    display.set(dx + 2, dy + 1 + i - 1, display.fit(line, dw - 4), THEME.fg, THEME.panel_bg)
  end

  -- Buttons
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

-- ============================================================
-- Enhanced menu bar with keyboard focus support
-- ============================================================

--- Draw a menu bar with optional focus/selection state
-- items: { {label="File"}, {label="Tools"}, ... }
-- activeIdx: which item is highlighted (nil = none)
-- focusMode: true when menu bar has keyboard focus
-- row: which row to draw on (default 1)
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
    -- Store position for dropdown alignment
    item._x = x
    item._w = #label
    x = x + #label + 1
  end
end

-- ============================================================
-- Dropdown / context menu
-- ============================================================

--- Draw a bordered dropdown menu at a given position
-- items: { {label="View", key="F3"}, {sep=true}, {label="Delete", key="F8"} }
-- selectedIdx: which non-separator item is highlighted
-- Returns: dw, dh (dimensions of the dropdown)
function display.dropdown(x, y, items, selectedIdx)
  -- Calculate dimensions
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
  local dw = innerW + 4  -- 2 border + 2 margin
  local dh = #items + 2  -- 2 border

  -- Clamp to screen
  if x + dw > W then x = W - dw end
  if x < 1 then x = 1 end
  if y + dh > H then y = H - dh end
  if y < 1 then y = 1 end

  -- Draw box
  display.box(x, y, dw, dh, nil, {
    border = THEME.border, bg = THEME.panel_bg,
  })

  -- Draw items
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

--- Alias: context menu uses the same rendering as dropdown
display.contextMenu = display.dropdown

--- Temporarily swap GPU/resolution context for a function call.
--- Used by screen.displayProxy to delegate high-level drawing to a
--- specific GPU+screen pair without duplicating all the TUI logic.
function display.withContext(gpuOverride, wOverride, hOverride, fn)
  local oldGpu, oldW, oldH = gpu, W, H
  gpu, W, H = gpuOverride, wOverride, hOverride
  local results = table.pack(pcall(fn))
  gpu, W, H = oldGpu, oldW, oldH
  if results[1] then return table.unpack(results, 2, results.n)
  else error(results[2], 2) end
end

-- Export constants
display.BOX = BOX
display.THEME = THEME

return display
