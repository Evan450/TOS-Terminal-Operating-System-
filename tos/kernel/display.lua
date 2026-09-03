-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Display / TUI Engine   ║
-- ║  ASCII box-drawing, panels, menus    ║
-- ╚══════════════════════════════════════╝

local display = {}

-- GPU reference (set during init)
local gpu = nil
local W, H = 50, 16  -- Current resolution

-- Color scheme — the "TOS classic" default, 2026 refresh.
-- Design language (matches kernel.theme's `default` preset):
--   * pure-black background (best on OC screens, free on every tier),
--     soft-white text instead of full 0xFFFFFF glare;
--   * the old solid-white menu bar and solid-cyan status bar are now
--     dark slate / deep sea-blue bars with light text — the bright
--     bars dominated the screen and clashed with everything;
--   * accents form one family: teal-cyan frames (the TOS identity
--     hue), warm-gold titles/hotkeys, green for success/highlight;
--   * title (gold), warning (orange) and error (red) are three
--     DIFFERENT colors so the severity ladder reads at a glance;
--   * syntax colors are a One-Dark-style set tuned for dark bg.
-- display.init() overrides per tier: T1 collapses to mono, T2 repicks
-- from the 16-color dye palette (see the tier branches below).
local THEME = {
  bg           = 0x000000,  -- Black background (safe everywhere)
  fg           = 0xE6E6E6,  -- Soft white body text
  border       = 0x2FB8C6,  -- Teal-cyan frames (TOS identity hue)
  title        = 0xFFD75A,  -- Warm gold titles
  highlight    = 0x42D77D,  -- Success / positive-feedback green
  selected_bg  = 0x0E5E70,  -- Deep-teal selection bar
  selected_fg  = 0xFFFFFF,  -- White text on selection
  menubar_bg   = 0x262B33,  -- Dark slate menu bar
  menubar_fg   = 0xE6E6E6,  -- Light menu text
  menubar_hot  = 0xFFD75A,  -- Gold hotkeys
  statusbar_bg = 0x103C4E,  -- Deep sea-blue status bar
  statusbar_fg = 0xBFE3EE,  -- Pale cyan status text
  error        = 0xFF5C57,  -- Soft red errors
  warning      = 0xFFA042,  -- Orange warnings (≠ gold titles)
  dim          = 0x909090,  -- Mid gray secondary text
  panel_bg     = 0x000000,  -- Black panel background
  input_bg     = 0x14181E,  -- Slightly lifted input wells
  input_fg     = 0xFFFFFF,  -- Input field text
  -- Syntax highlighting (T2/T3 only; T1 overrides to white)
  syn_keyword  = 0x61AFEF,  -- Blue keywords
  syn_string   = 0x98C379,  -- Green strings
  syn_comment  = 0x7A828E,  -- Gray-blue comments
  syn_number   = 0xD19A66,  -- Amber numbers
  syn_func     = 0xE5C07B,  -- Gold builtins
  -- Extended file type colors
  file_lua     = 0x56B6C2,  -- Teal for .lua
  dir_color    = 0x42D77D,  -- Green for directories
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

-- GPU fg/bg state cache (see "Low-level drawing" below for rationale).
-- Declared here so display.init can keep them in sync after its
-- direct setBackground/setForeground calls.
local _lastFg, _lastBg = nil, nil

-- Forward declaration so display.init() can re-sync after overriding
-- tier-specific base colors. The body is defined later in the file.
local syncDerivedTheme

-- ============================================================
-- GPU hot-removal guard (#REV review finding #3)
-- ============================================================
-- A player can pull the screen or GPU mid-frame; every raw gpu.set/
-- fill/copy then raises ("no screen" / "no such component") straight
-- out of whatever was drawing — shell draw code, dialogs, POST. Wrap
-- the proxy ONCE here so every method is pcall'd at a single choke
-- point: on the first failure the display goes quiet (draws no-op,
-- getters return last-known-good values so `W,H = gpu.getResolution()`
-- callers keep getting numbers) and a `tos_display_lost` signal is
-- pushed for interested code. This is deliberately NOT a retry loop —
-- OC gpu calls don't fail spuriously; if one raised, the hardware is
-- gone or unbound, and hammering it raises everywhere. Reattach path:
-- display.init(newProxy) re-wraps fresh and clears the lost flag.
local displayLost = false
local function guardGpu(px)
  -- Last-known-good fallbacks for value-returning methods.
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
    rawset(t, k, fn)   -- memoize: one wrapper closure per method
    return fn
  end })
end

--- Has the guard tripped (GPU/screen vanished mid-session)?
function display.isLost() return displayLost end

function display.init(gpuProxy, width, height)
  -- Re-wrap fresh on every init: init IS the reattach path, so a new
  -- (or rebound) proxy clears the lost state.
  displayLost = false
  if gpuProxy and not gpuProxy._tosRawGpu then
    gpuProxy = guardGpu(gpuProxy)
  end
  gpu = gpuProxy
  if gpu then
    -- Resolution policy (see kernel.screen): the caller passes the chosen
    -- working resolution as (width, height). The kernel computes it from the
    -- screen-size policy — density-based "auto" by default — which keeps text
    -- a readable size instead of forcing the hardware max (160x50 on a T3 GPU
    -- + large screen renders tiny, unreadable glyphs). If no target is given
    -- we fall back to the hardware maximum (maxResolution() already returns the
    -- GPU-vs-screen lower bound, so it's always safe).
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

    -- Set safe colors; only clear screen on fresh boot (not BIOS continuation)
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    -- Keep the fg/bg cache in sync with the direct calls above.
    -- Without this, the first cache-aware setFg/setBg would think
    -- _lastFg is nil and issue a redundant SetForeground call.
    _lastBg, _lastFg = 0x000000, 0xFFFFFF
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

      syncDerivedTheme()

    elseif gpuTier == 2 then
      -- T2: 4-bit color. Pick entries from OC's ACTUAL default 4-bit
      -- palette (PackedColor: white 0xFFFFFF, orange 0xFFCC33, magenta
      -- 0xCC66CC, lightblue 0x6699FF, yellow 0xFFFF33, lime 0x33CC33,
      -- pink 0xFF6699, gray 0x333333, silver 0xCCCCCC, cyan 0x336699,
      -- purple 0x9933CC, blue 0x333399, brown 0x663300, green 0x336600,
      -- red 0xFF3333, black 0x000000) so no snap occurs. The old values
      -- here were CGA colors (0x55FFFF, 0xAAAAAA, …) that snapped
      -- unpredictably. Layout mirrors the T3 default: dark bars with
      -- light text, three-step title/warning/error severity ladder.
      THEME.fg           = 0xFFFFFF  -- White (T2 has no soft white)
      THEME.dim          = 0xCCCCCC  -- Silver
      THEME.border       = 0x6699FF  -- Light blue frames
      THEME.title        = 0xFFFF33  -- Yellow titles
      THEME.highlight    = 0x33CC33  -- Lime success
      THEME.warning      = 0xFFCC33  -- Orange warnings (≠ title)
      THEME.error        = 0xFF3333  -- Red
      THEME.selected_bg  = 0x336699  -- Cyan selection bar
      THEME.selected_fg  = 0xFFFFFF
      THEME.menubar_bg   = 0x333333  -- Dark gray bar (was solid aqua/white)
      THEME.menubar_fg   = 0xFFFFFF
      THEME.menubar_hot  = 0xFFCC33  -- Orange hotkeys on the dark bar
      THEME.statusbar_bg = 0x336699  -- Cyan status bar
      THEME.statusbar_fg = 0xFFFFFF
      THEME.input_bg     = 0x333333  -- Lifted input wells

      -- T2 syntax colors (exact palette entries)
      THEME.syn_keyword  = 0x6699FF  -- Light blue
      THEME.syn_string   = 0x33CC33  -- Lime
      THEME.syn_comment  = 0xCCCCCC  -- Silver
      THEME.syn_number   = 0xFFCC33  -- Orange
      THEME.syn_func     = 0xFFFF33  -- Yellow
      THEME.file_lua     = 0x6699FF  -- Light blue
      THEME.dir_color    = 0x33CC33  -- Lime

      syncDerivedTheme()

    else
      -- T3: 8-bit color (256 colors). The base THEME table above IS the
      -- T3 palette; re-affirm the syntax set here so a prior tier's
      -- overrides can never leak through a re-init on the same boot.
      THEME.syn_keyword  = 0x61AFEF  -- Blue
      THEME.syn_string   = 0x98C379  -- Green
      THEME.syn_comment  = 0x7A828E  -- Gray-blue
      THEME.syn_number   = 0xD19A66  -- Amber
      THEME.syn_func     = 0xE5C07B  -- Gold
      THEME.file_lua     = 0x56B6C2  -- Teal
      THEME.dir_color    = 0x42D77D  -- Green

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

--- Returns true if the GPU is monochrome (T1, 1-bit)
function display.isMonochrome()
  return gpuDepth <= 1
end

function display.getSize()
  return W, H
end

--- Re-read the GPU's current resolution into the cached W/H. Call after an
--- external setResolution (the `screen res` command / a program size request)
--- so display.clear() and callers of getSize() use the new dimensions instead
--- of the stale boot values. Returns the refreshed W, H.
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
-- Panels access T.bar_fg / T.bar_bg / T.bar_accent directly (not via
-- D.c()), so these must be materialized as real THEME keys — otherwise
-- gpu.setForeground is skipped and the top bar inherits whatever colors
-- the previous draw call left behind (top-bar flicker).
-- Force a usable contrast on a fg/bg pair: if they collapsed to the
-- same value (typically because a saved override clobbered one of
-- them with a bad value), flip fg to the inverse so tab/menu/status
-- text stays visible. Returns the (possibly-fixed) fg.
--
-- Why a hard failsafe rather than just logging: the user reported
-- "white-on-white tab text" with the default theme; once you can't
-- read the menu bar you can't run `theme reset`, so the system has
-- to self-heal.
local function ensureContrast(fg, bg, label)
  if fg ~= bg then return fg end
  -- Same colour — pick the inverse. For pure-white bg → black,
  -- pure-black bg → white, anything else → bitwise complement
  -- masked to 24 bits.
  local fixed
  if bg == 0xFFFFFF then fixed = 0x000000
  elseif bg == 0x000000 then fixed = 0xFFFFFF
  else
    -- Lua 5.3 has bitwise ops; older 5.2 doesn't. Use a value
    -- arithmetic that works on both: 0xFFFFFF - bg gives the
    -- 24-bit complement, which has guaranteed contrast.
    fixed = 0xFFFFFF - bg
  end
  -- Best-effort log so an operator can chase the misconfigured
  -- override. log isn't required for the heal itself.
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

  -- Same protection for status bar (statusbar_fg/bg used directly by
  -- panels/draw.statusBar). Status text invisibility looks identical
  -- to a clean-but-empty status bar, so it's easy to overlook.
  THEME.statusbar_fg = ensureContrast(THEME.statusbar_fg, THEME.statusbar_bg, "statusbar")
end
syncDerivedTheme()

-- #SEC H25 — strict allowlist of theme keys a caller may override, and
-- strict validation of their values. The old implementation accepted
-- any key/value pair; setting `bg = "string"` made every gpu.setBackground
-- call throw, instantly bricking the UI. Color values must fit in 24 bits.
local OVERRIDABLE_KEYS = {
  bg = true, fg = true,
  border = true, title = true, highlight = true, dim = true,
  error = true, warning = true,
  -- input_fg was missing here while kernel.theme presets (and its own
  -- `theme color` allowlist) include it — so a preset's input text
  -- color was silently dropped. Same validation as every other key.
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

-- OpenComputers' DEFAULT 4-bit (T2) palette. On a T2 GPU the hardware
-- snaps any setForeground/setBackground value to the nearest of these 16
-- entries — but OC's snap is a naive per-channel nearest that can turn a
-- dark-slate bar into pure black (text vanishes) or shift an accent into a
-- clashing hue. #REV — we snap deliberately to the SAME palette before
-- storing, so (a) the colours TOS records match what's on screen, and (b)
-- syncDerivedTheme's ensureContrast runs on the snapped values and can heal
-- any fg/bg pair that collapsed. This is what made non-default presets
-- "snap to weird colours" on T2.
local OC_T2_PALETTE = {
  0xFFFFFF, 0xFFCC33, 0xCC66CC, 0x6699FF, 0xFFFF33, 0x33CC33,
  0xFF6699, 0x333333, 0xCCCCCC, 0x336699, 0x9933CC, 0x333399,
  0x663300, 0x336600, 0xFF3333, 0x000000,
}
-- The palette's achromatic entries. #REV (v1.4.0 emulator round) — a
-- GREY must snap to a GREY: the palette has no mid-grey, and by raw
-- channel distance 0x909090 is genuinely CLOSER to 0xCC66CC (pale
-- magenta) than to 0xCCCCCC. That's why the default preset's `dim`
-- text (0x909090) rendered PINK on a T2 GPU. Near-achromatic input
-- (small max-min channel spread) only considers these.
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
    -- Perceptual-ish weighting (eye is most sensitive to green) so e.g. a
    -- teal doesn't snap to brown just because raw RGB distance ties.
    local d = dr * dr * 3 + dg * dg * 4 + db * db * 2
    if not bestD or d < bestD then bestD, best = d, c end
  end
  return best
end
display._snapToT2 = snapToT2  -- test hook

function display.setTheme(overrides)
  if type(overrides) ~= "table" then return false, "overrides must be a table" end
  -- On a T2 GPU, snap to the OC palette ourselves (see snapToT2). T3 (8-bit)
  -- has the range to show RGB directly; T1 never reaches here (theme.apply
  -- refuses on monochrome).
  local snap = (gpuDepth == 4)
  local applied = 0
  for k, v in pairs(overrides) do
    if OVERRIDABLE_KEYS[k] and isValidColor(v) then
      THEME[k] = snap and snapToT2(v) or v
      applied = applied + 1
    end
    -- silently skip invalid entries — a malformed theme file should not
    -- error out, just leave the offending field at its default.
  end
  syncDerivedTheme()
  return true, applied
end

-- ============================================================
-- Low-level drawing
-- ============================================================
-- GPU foreground/background state cache.
--
-- Each gpu.setForeground / gpu.setBackground call crosses the OC
-- bridge — it's not free. A typical full-redraw of the panels shell
-- issues 50-100 of those, and many of them set the same color the
-- GPU is already at (e.g. the entire file list runs in fg=fg, bg=bg
-- with selection rows the only deviation). Caching the last value
-- and skipping the call when it hasn't changed cuts most of those.
--
-- Cleared whenever we re-bind to a new GPU (display.init replays
-- bg=black/fg=white) so the cache can never go stale across context
-- swaps. display.withContext also resets so per-seat draws can't
-- inherit the parent's cached state.
--
-- _lastFg / _lastBg are declared near the top of this file (alongside
-- gpuTier) so display.init can keep them in sync after its direct
-- setBackground/setForeground calls.

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

--- Forget what colour the hardware is currently set to.
---
--- The cache above is only correct while EVERY write goes through this
--- module. Anything that touches the GPU directly moves the hardware
--- without moving the cache, and then _setFg/_setBg compare, match, and
--- skip the call they believe is redundant -- so the next fill paints in
--- whatever colour the outsider left behind. That is what makes the
--- status bar go black: not a bad colour, a call that never happened.
---
--- In practice the outsider is the OpenOS-compat term.gpu() proxy, which
--- forwards set/fill/setBackground/setForeground straight to hardware for
--- any program holding a display capability. Callers that go around this
--- module must call this afterwards; the proxy now does.
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
  -- Clear the bottom row with explicit black background.
  --
  -- These are RAW gpu calls, deliberately: the new bottom row must be
  -- black regardless of what the cache thinks. But raw calls move the
  -- hardware WITHOUT moving _lastFg/_lastBg, and _setFg/_setBg skip the
  -- gpu call whenever the requested colour already matches the cache.
  -- Leaving the cache claiming the pre-scroll colour therefore made the
  -- next draw in THAT colour a no-op, and it painted on black.
  --
  -- Seen as the status bar's widgets rendering on black instead of
  -- statusbar_bg: the shell scrolls output, then repaints the status
  -- row in the same colour it last used, and the call is skipped. The
  -- menu bar escaped it only because its colour differed from the
  -- stale value, so its call still fired.
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  _lastBg, _lastFg = 0x000000, 0xFFFFFF   -- the cache must not outlive the truth
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

--- Do two GPU handles drive the same physical screen?
---
--- Identity is not enough: component.proxy hands back a FRESH table each
--- call, so the same GPU compares unequal to itself. Compare addresses,
--- and when that cannot be determined, answer "yes" -- a wrong yes costs
--- one redundant colour call, a wrong no installs a cache that lies.
local function sameGpu(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return true end
  local okA, aa = pcall(function() return a.address end)
  local okB, bb = pcall(function() return b.address end)
  if not okA or not okB or aa == nil or bb == nil then return true end
  return aa == bb
end

--- Temporarily swap GPU/resolution context for a function call.
--- Used by screen.displayProxy to delegate high-level drawing to a
--- specific GPU+screen pair without duplicating all the TUI logic.
function display.withContext(gpuOverride, wOverride, hOverride, fn)
  local oldGpu, oldW, oldH = gpu, W, H
  local oldFg, oldBg = _lastFg, _lastBg
  gpu, W, H = gpuOverride, wOverride, hOverride
  -- Different GPU = stale cache. Reset so the first setFg/setBg under
  -- the new GPU actually issues the call rather than thinking the
  -- GPU is already at the cached colour.
  _lastFg, _lastBg = nil, nil
  local results = table.pack(pcall(fn))
  gpu, W, H = oldGpu, oldW, oldH

  -- The restore is only SYMMETRIC when the context was other hardware.
  -- Then `fn` drew somewhere else and oldFg/oldBg still describe this
  -- GPU exactly. But screen.displayProxy forwards statusBar, menuBar,
  -- scrollUp and box through here with the SEAT's gpu -- and on a
  -- one-GPU machine that is this very GPU. `fn` just moved the glass
  -- that oldFg/oldBg claim to describe, so putting them back installs a
  -- cache that is confidently wrong, and the next fill in that colour is
  -- skipped as redundant and lands on whatever `fn` left behind.
  --
  -- scrollUp leaves the glass BLACK, and the status bar is drawn through
  -- this path. That is the status bar going black: four rounds on real
  -- hardware, and the answer was a restore that assumed two GPUs.
  if sameGpu(gpuOverride, oldGpu) then
    _lastFg, _lastBg = nil, nil
  else
    _lastFg, _lastBg = oldFg, oldBg
  end

  if results[1] then return table.unpack(results, 2, results.n)
  else error(results[2], 2) end
end

-- Export constants
display.BOX = BOX
display.THEME = THEME

return display
