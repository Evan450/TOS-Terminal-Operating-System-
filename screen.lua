-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Multi-Screen Manager ║
-- ║  GPU ↔ Screen binding & switching  ║
-- ╚══════════════════════════════════════╝
-- OC allows multiple GPU+Screen pairs. This module manages bindings
-- and provides switching between displays.

local component = require("component")
local computer = require("computer")

local screen = {}

-- Active displays: { { gpu=proxy, screen=addr, w=num, h=num, depth=num, label=str, keyboards={addr,...} } }
local displays = {}
local activeIdx = 1  -- Currently focused display index
local initialized = false
-- Reverse map: keyboard address → display index
local kbToDisplay = {}
-- Reverse map: screen address → display index
local screenToDisplay = {}

--- Discover which keyboards belong to a screen.
-- In OC, keyboards are sub-components of screens. We check via
-- component.invoke(screen, "getKeyboards") if available, or fall
-- back to scanning all keyboard addresses.
local function findKeyboards(scrAddr)
  local kbs = {}
  -- Method 1: screen proxy has getKeyboards()
  local okList, kbList = pcall(component.invoke, scrAddr, "getKeyboards")
  if okList and type(kbList) == "table" then
    for _, kb in ipairs(kbList) do kbs[#kbs + 1] = kb end
    return kbs
  end
  -- Method 2: iterate keyboards and match by attached screen.
  -- In OC 1.7+, keyboards list their attached screen via the event
  -- address. As a fallback, just collect all keyboards — the first
  -- display gets them all (single-screen default).
  return kbs
end

--- Scan for all GPU+Screen pairs and create display entries.
function screen.init()
  displays = {}
  kbToDisplay = {}
  screenToDisplay = {}

  local gpus = {}
  for addr in component.list("gpu") do
    gpus[#gpus + 1] = component.proxy(addr)
  end

  local screens = {}
  for addr in component.list("screen") do
    screens[#screens + 1] = addr
  end

  -- Pair GPUs with screens (1:1 in order)
  for i = 1, math.min(#gpus, #screens) do
    local gpu = gpus[i]
    local scrAddr = screens[i]
    -- Bind GPU to screen
    pcall(gpu.bind, scrAddr)
    local w, h = gpu.getResolution()
    local depth = gpu.getDepth()
    local kbs = findKeyboards(scrAddr)
    displays[#displays + 1] = {
      gpu       = gpu,
      screen    = scrAddr,
      w         = w,
      h         = h,
      depth     = depth,
      label     = "Screen " .. i,
      keyboards = kbs,
    }
    -- Build reverse maps
    screenToDisplay[scrAddr] = #displays
    for _, kb in ipairs(kbs) do
      kbToDisplay[kb] = #displays
    end
  end

  if #displays == 0 then
    -- Fallback: try to use the primary GPU/screen from boot
    local gpuAddr = component.list("gpu")()
    local scrAddr = component.list("screen")()
    if gpuAddr and scrAddr then
      local gpu = component.proxy(gpuAddr)
      local w, h = gpu.getResolution()
      local kbs = findKeyboards(scrAddr)
      displays[1] = {
        gpu       = gpu,
        screen    = scrAddr,
        w         = w,
        h         = h,
        depth     = gpu.getDepth(),
        label     = "Primary",
        keyboards = kbs,
      }
      screenToDisplay[scrAddr] = 1
      for _, kb in ipairs(kbs) do
        kbToDisplay[kb] = 1
      end
    end
  end

  -- If no keyboard→screen mapping was discovered (OC version lacks
  -- getKeyboards), assign ALL keyboards to display 1 as a safe default.
  if next(kbToDisplay) == nil and #displays > 0 then
    for addr in component.list("keyboard") do
      kbToDisplay[addr] = 1
      displays[1].keyboards = displays[1].keyboards or {}
      displays[1].keyboards[#displays[1].keyboards + 1] = addr
    end
  end

  activeIdx = 1
  initialized = true
  return #displays
end

-- Ensure init has been called
local function ensureInit()
  if not initialized then screen.init() end
end

--- Get the number of available displays.
function screen.count()
  ensureInit()
  return #displays
end

--- Get the active display info.
function screen.active()
  ensureInit()
  return displays[activeIdx]
end

--- Get display by index.
function screen.get(idx)
  ensureInit()
  return displays[idx]
end

--- Switch active display.
function screen.setActive(idx)
  ensureInit()
  if idx >= 1 and idx <= #displays then
    activeIdx = idx
    return true
  end
  return false
end

--- Rebuild display list (for hot-plug). Returns added, removed indices.
function screen.rebuild()
  local oldScreens = {}
  for i, d in ipairs(displays) do oldScreens[d.screen] = i end

  screen.init()  -- re-enumerates everything

  local newScreens = {}
  for i, d in ipairs(displays) do newScreens[d.screen] = i end

  local added, removed = {}, {}
  for scrAddr, idx in pairs(newScreens) do
    if not oldScreens[scrAddr] then added[#added + 1] = idx end
  end
  for scrAddr, idx in pairs(oldScreens) do
    if not newScreens[scrAddr] then removed[#removed + 1] = idx end
  end
  return added, removed
end

--- Cycle to next display.
function screen.next()
  ensureInit()
  if #displays == 0 then return nil end
  activeIdx = (activeIdx % #displays) + 1
  return displays[activeIdx]
end

--- Get the GPU proxy for the active display.
function screen.gpu()
  ensureInit()
  local d = displays[activeIdx]
  return d and d.gpu
end

--- Get the resolution of the active display.
function screen.getResolution()
  ensureInit()
  local d = displays[activeIdx]
  if d then return d.w, d.h end
  return 50, 16
end

--- List all displays.
function screen.list()
  ensureInit()
  local result = {}
  for i, d in ipairs(displays) do
    result[#result + 1] = {
      index  = i,
      label  = d.label,
      w      = d.w,
      h      = d.h,
      depth  = d.depth,
      screen = d.screen,
      active = (i == activeIdx),
    }
  end
  return result
end

--- Set label for a display.
function screen.setLabel(idx, label)
  if displays[idx] then
    displays[idx].label = label
    return true
  end
  return false
end

--- Look up which display index owns a keyboard address.
-- Returns the display index (1-based) or nil if unknown.
function screen.displayForKeyboard(kbAddr)
  ensureInit()
  return kbToDisplay[kbAddr]
end

--- Look up which display index owns a screen address.
function screen.displayForScreen(scrAddr)
  ensureInit()
  return screenToDisplay[scrAddr]
end

--- Create a display proxy for index `idx`: a table that looks like
--- the kernel.display API but draws to a specific GPU/screen pair.
--- Core drawing methods (set/fill/clear) are implemented directly for
--- performance; higher-level TUI methods delegate to display.withContext.
function screen.displayProxy(idx)
  ensureInit()
  local d = displays[idx]
  if not d then return nil end

  local proxy = {}

  -- Core drawing calls (direct GPU access for performance)
  function proxy.set(x, y, text, fg, bg)
    if fg then pcall(d.gpu.setForeground, fg) end
    if bg then pcall(d.gpu.setBackground, bg) end
    pcall(d.gpu.set, x, y, text)
  end
  function proxy.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(d.gpu.setForeground, fg) end
    if bg then pcall(d.gpu.setBackground, bg) end
    pcall(d.gpu.fill, x, y, w, h, ch or " ")
  end
  function proxy.clear(bg)
    if bg then pcall(d.gpu.setBackground, bg) end
    pcall(d.gpu.fill, 1, 1, d.w, d.h, " ")
  end
  function proxy.getSize() return d.w, d.h end
  function proxy.getGpu() return d.gpu end
  function proxy.getGpuTier()
    local dp = d.depth or 1
    if dp >= 8 then return 3
    elseif dp >= 4 then return 2
    else return 1 end
  end
  function proxy.getGpuDepth() return d.depth or 1 end

  -- Theme access
  proxy.getTheme = function()
    local ok, disp = pcall(require, "kernel.display")
    if ok and disp and disp.getTheme then return disp.getTheme() end
    return setmetatable({}, { __index = function() return 0xFFFFFF end })
  end
  proxy.c = function(name)
    local theme = proxy.getTheme()
    return theme[name] or 0xFFFFFF
  end

  -- Delegate higher-level TUI methods via display.withContext so we
  -- don't duplicate complex drawing logic (box-drawing, menus, etc.)
  local ok, disp = pcall(require, "kernel.display")
  if ok and disp and disp.withContext then
    local FORWARDED = {
      "scrollUp", "box", "dbox", "hdivider", "menuBar", "statusBar",
      "fkeyBar", "fit", "writeWrapped", "dialog", "menuBarEx", "dropdown",
      "isMonochrome", "setTheme",
    }
    for _, name in ipairs(FORWARDED) do
      if disp[name] then
        proxy[name] = function(...)
          local args = table.pack(...)
          return disp.withContext(d.gpu, d.w, d.h, function()
            return disp[name](table.unpack(args, 1, args.n))
          end)
        end
      end
    end
    proxy.contextMenu = proxy.dropdown
    proxy.BOX = disp.BOX
    proxy.THEME = disp.THEME
  end

  return proxy
end

return screen
