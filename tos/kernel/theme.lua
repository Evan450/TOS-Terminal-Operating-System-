-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Theme Manager                              ║
-- ║                                                          ║
-- ║  Named color themes + per-user persistence. The display  ║
-- ║  module owns the live THEME table; this module owns the  ║
-- ║  presets, the per-user save/load dance, and the policy   ║
-- ║  that "set this theme" should mean on each GPU tier.     ║
-- ║                                                          ║
-- ║  Customization rules by tier:                            ║
-- ║    T1 (1-bit / monochrome) — colour overrides are        ║
-- ║      ignored and apply() returns false. There is no      ║
-- ║      "blue title" on a black-and-white screen.           ║
-- ║    T2 (4-bit / 16 dye colours) — full customization,     ║
-- ║      but RGB values not on the palette will snap to      ║
-- ║      their nearest neighbour. We don't pretend           ║
-- ║      otherwise; users see the snapped result live.       ║
-- ║    T3 (8-bit / 256 colours) — full RGB freedom.          ║
-- ║                                                          ║
-- ║  Persistence path is each user's home directory          ║
-- ║  (/root/.theme.cfg for root, /home/<user>/.theme.cfg     ║
-- ║  for everyone else). securefs handles the ACL — if a     ║
-- ║  user can't write their own home, themes don't save      ║
-- ║  but the live appearance still updates for the session.  ║
-- ╚══════════════════════════════════════════════════════════╝

local theme = {}

local SAVE_NAME = ".theme.cfg"

-- Module references (set during init)
local display, securefs, log, serialize

-- ============================================================
-- Built-in presets — 2026 palette refresh
-- ============================================================
-- Design rules every preset follows (the old set broke most of them,
-- which is why they read as garish or flat):
--   * Bars (menubar/statusbar) are TINTED, not solid accent blocks —
--     the old solid white/amber/green bars dominated the screen.
--   * title, warning, and error are three DIFFERENT colors so the
--     severity ladder reads at a glance (the old presets collapsed
--     two or three of them into one yellow).
--   * Body text is soft (not full 0xFFFFFF glare) and `dim` keeps
--     enough contrast against bg to stay legible.
--   * Every preset carries the FULL overridable key set, including
--     syntax + file-type colors. display.setTheme only writes the
--     keys it's given, so a partial preset would leave the previous
--     theme's syntax colors behind when switching.
--
-- Colors are 24-bit RGB; OC snaps to the nearest palette entry on
-- T2 (16 dye colors) and to the 6x8x5 cube on T3. Palettes are tuned
-- for T3 and chosen to snap sanely on T2.
local PRESETS = {
  default = {
    description  = "TOS classic — teal frames, gold titles on black",
    bg           = 0x000000, fg           = 0xE6E6E6,
    border       = 0x2FB8C6, title        = 0xFFD75A,
    highlight    = 0x42D77D, dim          = 0x909090,
    selected_bg  = 0x0E5E70, selected_fg  = 0xFFFFFF,
    menubar_bg   = 0x262B33, menubar_fg   = 0xE6E6E6, menubar_hot  = 0xFFD75A,
    statusbar_bg = 0x103C4E, statusbar_fg = 0xBFE3EE,
    error        = 0xFF5C57, warning      = 0xFFA042,
    panel_bg     = 0x000000, input_bg     = 0x14181E, input_fg     = 0xFFFFFF,
    syn_keyword  = 0x61AFEF, syn_string   = 0x98C379, syn_comment  = 0x7A828E,
    syn_number   = 0xD19A66, syn_func     = 0xE5C07B,
    file_lua     = 0x56B6C2, dir_color    = 0x42D77D,
  },
  midnight = {
    description  = "Tokyo night — indigo panels, neon accents",
    bg           = 0x0D1420, fg           = 0xD6E2F0,
    border       = 0x3E7CB8, title        = 0x9CC4F0,
    highlight    = 0x59C2A0, dim          = 0x7388A6,
    selected_bg  = 0x24466B, selected_fg  = 0xFFFFFF,
    menubar_bg   = 0x16243A, menubar_fg   = 0xC4D6EC, menubar_hot  = 0xF0B35E,
    statusbar_bg = 0x16243A, statusbar_fg = 0x8FB2D9,
    error        = 0xE8606B, warning      = 0xE8B44C,
    panel_bg     = 0x0D1420, input_bg     = 0x1A2C46, input_fg     = 0xF0F6FF,
    syn_keyword  = 0x7AA2F7, syn_string   = 0x9ECE6A, syn_comment  = 0x565F89,
    syn_number   = 0xFF9E64, syn_func     = 0xE0AF68,
    file_lua     = 0x7DCFFF, dir_color    = 0x73DACA,
  },
  amber = {
    description  = "Retro CRT — warm amber phosphor",
    bg           = 0x0A0500, fg           = 0xFFB000,
    border       = 0xCC8400, title        = 0xFFD75A,
    highlight    = 0xFFE599, dim          = 0x8F5E00,
    -- Selection keeps the inverted-phosphor look (it's the one place
    -- a solid amber block belongs), but the bars are now dark with
    -- amber text instead of wall-to-wall amber.
    selected_bg  = 0xFFB000, selected_fg  = 0x1A0D00,
    menubar_bg   = 0x241200, menubar_fg   = 0xFFB000, menubar_hot  = 0xFFE599,
    statusbar_bg = 0x241200, statusbar_fg = 0xCC8400,
    error        = 0xFF5C57, warning      = 0xFFE599,
    panel_bg     = 0x0A0500, input_bg     = 0x1A0D00, input_fg     = 0xFFC840,
    syn_keyword  = 0xFFD75A, syn_string   = 0xE59E00, syn_comment  = 0x8F5E00,
    syn_number   = 0xFFE599, syn_func     = 0xFFC840,
    file_lua     = 0xFFC840, dir_color    = 0xFFD75A,
  },
  green = {
    description  = "Matrix — green phosphor on black",
    bg           = 0x020A02, fg           = 0x3FD23F,
    border       = 0x2AA62A, title        = 0xA8F0A8,
    highlight    = 0x88E888, dim          = 0x1E7A1E,
    selected_bg  = 0x3FD23F, selected_fg  = 0x031003,
    menubar_bg   = 0x0A2410, menubar_fg   = 0x66E866, menubar_hot  = 0xCCFFCC,
    statusbar_bg = 0x0A2410, statusbar_fg = 0x2AA62A,
    error        = 0xFF5C57, warning      = 0xE8E84C,
    panel_bg     = 0x020A02, input_bg     = 0x07180A, input_fg     = 0x88E888,
    syn_keyword  = 0x88E888, syn_string   = 0x2AA62A, syn_comment  = 0x1E7A1E,
    syn_number   = 0xCCFFCC, syn_func     = 0xA8F0A8,
    file_lua     = 0x66E866, dir_color    = 0x88E888,
  },
  plasma = {
    description  = "Plasma display — neon red-orange on black (night-vision friendly)",
    -- Early monochrome plasma panels (PLATO terminals, the first
    -- "luggable" PCs) glowed a characteristic neon red-orange. Every
    -- color here stays in the red-orange band — no blue or green
    -- light — and the background is pure black (gas off), so an
    -- operator working in the dark keeps their dark adaptation.
    -- Severity still reads: title pale orange, warning vivid orange,
    -- error pure red (the "hottest" tone in the family).
    bg           = 0x000000, fg           = 0xFF6A33,
    border       = 0xCC4A1F, title        = 0xFFA64D,
    highlight    = 0xFFC78F, dim          = 0x8F2E14,
    selected_bg  = 0xFF6A33, selected_fg  = 0x1F0900,
    menubar_bg   = 0x260C00, menubar_fg   = 0xFF6A33, menubar_hot  = 0xFFC78F,
    statusbar_bg = 0x260C00, statusbar_fg = 0xCC4A1F,
    error        = 0xFF2424, warning      = 0xFF8A1F,
    panel_bg     = 0x000000, input_bg     = 0x1F0900, input_fg     = 0xFFA64D,
    syn_keyword  = 0xFFA64D, syn_string   = 0xCC4A1F, syn_comment  = 0x8F2E14,
    syn_number   = 0xFFC78F, syn_func     = 0xFF8A1F,
    file_lua     = 0xFF8A1F, dir_color    = 0xFFC78F,
  },
  classic = {
    description  = "Norton-style — white on blue, cyan bars",
    -- True to the NC look this time: CGA blue field, cyan menu/status
    -- bars with black text (the old silver bars were a DOS-edit
    -- mashup), yellow titles + hotkeys, cyan double-line borders.
    -- title (yellow) / warning (orange) / error (red) stay distinct.
    bg           = 0x0000A8, fg           = 0xFFFFFF,
    border       = 0x55FFFF, title        = 0xFFFF55,
    highlight    = 0x55FF55, dim          = 0xA8B8D8,
    selected_bg  = 0x00A8A8, selected_fg  = 0x000000,
    menubar_bg   = 0x00A8A8, menubar_fg   = 0x000000, menubar_hot  = 0xFFFF55,
    statusbar_bg = 0x00A8A8, statusbar_fg = 0x000000,
    error        = 0xFF5555, warning      = 0xFFAA55,
    panel_bg     = 0x0000A8, input_bg     = 0x000054, input_fg     = 0xFFFF55,
    syn_keyword  = 0x55FFFF, syn_string   = 0x55FF55, syn_comment  = 0xA8B8D8,
    syn_number   = 0xFFAA55, syn_func     = 0xFFFF55,
    file_lua     = 0x55FFFF, dir_color    = 0x55FF55,
  },
  contrast = {
    description  = "High contrast — readability first",
    -- Stark by design. Yellow joins white as the main accents (both
    -- at or near maximum contrast on black); the selection bar is
    -- yellow-on-black inverted for maximum visibility; the menubar
    -- hotkey red is darkened to keep ~8:1 contrast on the white bar;
    -- warning is a bright orange (~9:1 on black) so the title /
    -- warning / error ladder stays distinct even here.
    bg           = 0x000000, fg           = 0xFFFFFF,
    border       = 0xFFFFFF, title        = 0xFFFF00,
    highlight    = 0xFFFFFF, dim          = 0xD0D0D0,
    selected_bg  = 0xFFFF00, selected_fg  = 0x000000,
    menubar_bg   = 0xFFFFFF, menubar_fg   = 0x000000, menubar_hot  = 0xAA0000,
    statusbar_bg = 0xFFFFFF, statusbar_fg = 0x000000,
    error        = 0xFF4040, warning      = 0xFF9900,
    panel_bg     = 0x000000, input_bg     = 0x000000, input_fg     = 0xFFFFFF,
    syn_keyword  = 0xFFFFFF, syn_string   = 0xFFFF00, syn_comment  = 0xD0D0D0,
    syn_number   = 0xFFFF00, syn_func     = 0xFFFFFF,
    file_lua     = 0xFFFFFF, dir_color    = 0xFFFF00,
  },
  nord = {
    description  = "Nord — arctic blues and frost",
    bg           = 0x2E3440, fg           = 0xD8DEE9,
    border       = 0x81A1C1, title        = 0x88C0D0,
    highlight    = 0xA3BE8C, dim          = 0x616E88,
    selected_bg  = 0x434C5E, selected_fg  = 0xECEFF4,
    menubar_bg   = 0x3B4252, menubar_fg   = 0xD8DEE9, menubar_hot  = 0xEBCB8B,
    statusbar_bg = 0x3B4252, statusbar_fg = 0x88C0D0,
    error        = 0xBF616A, warning      = 0xEBCB8B,
    panel_bg     = 0x2E3440, input_bg     = 0x434C5E, input_fg     = 0xECEFF4,
    syn_keyword  = 0x81A1C1, syn_string   = 0xA3BE8C, syn_comment  = 0x616E88,
    syn_number   = 0xB48EAD, syn_func     = 0x88C0D0,
    file_lua     = 0x88C0D0, dir_color    = 0xA3BE8C,
  },
  solarized = {
    description  = "Solarized dark — muted teal + earth accents",
    bg           = 0x002B36, fg           = 0x93A1A1,
    border       = 0x268BD2, title        = 0xB58900,
    highlight    = 0x859900, dim          = 0x586E75,
    selected_bg  = 0x586E75, selected_fg  = 0xFDF6E3,
    menubar_bg   = 0x073642, menubar_fg   = 0x93A1A1, menubar_hot  = 0xCB4B16,
    statusbar_bg = 0x073642, statusbar_fg = 0x2AA198,
    error        = 0xDC322F, warning      = 0xCB4B16,
    panel_bg     = 0x002B36, input_bg     = 0x073642, input_fg     = 0xFDF6E3,
    syn_keyword  = 0x268BD2, syn_string   = 0x2AA198, syn_comment  = 0x586E75,
    syn_number   = 0xD33682, syn_func     = 0xB58900,
    file_lua     = 0x2AA198, dir_color    = 0x859900,
  },
}

-- The keys a user is allowed to override individually via
-- `theme color <key> <value>`. We keep this list explicit so a
-- typo doesn't silently insert a junk key into the live THEME.
local OVERRIDABLE_KEYS = {
  bg = true, fg = true, border = true, title = true, highlight = true, dim = true,
  selected_bg = true, selected_fg = true,
  menubar_bg = true, menubar_fg = true, menubar_hot = true,
  statusbar_bg = true, statusbar_fg = true,
  error = true, warning = true,
  panel_bg = true, input_bg = true, input_fg = true,
  -- Syntax + file-type colors: presets carry these now (palette
  -- refresh), so per-key override and save/load round-tripping must
  -- accept them too. display.setTheme validates them like any key.
  syn_keyword = true, syn_string = true, syn_comment = true,
  syn_number = true, syn_func = true,
  file_lua = true, dir_color = true,
}

-- Live state. `current` is what's actually applied right now; it
-- exists so `theme show` can describe what the user is looking at
-- without re-deriving it from the THEME table.
local current = { preset = "default", overrides = {} }

-- ============================================================
-- Init
-- ============================================================

function theme.init(modules)
  display   = modules.display
  securefs  = modules.securefs
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
end

-- ============================================================
-- Introspection
-- ============================================================

function theme.list()
  local names = {}
  for name in pairs(PRESETS) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function theme.preset(name)
  return PRESETS[name]
end

function theme.describe(name)
  local p = PRESETS[name]
  return p and p.description or nil
end

function theme.current()
  return {
    preset    = current.preset,
    overrides = current.overrides,  -- shared reference; readers shouldn't mutate
  }
end

function theme.isOverridable(key)
  return OVERRIDABLE_KEYS[key] == true
end

function theme.overridableKeys()
  local keys = {}
  for k in pairs(OVERRIDABLE_KEYS) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- ============================================================
-- Apply
-- ============================================================

-- Returns (ok, err). On T1 GPUs apply() refuses to clobber the
-- monochrome theme that display.init() picked, since RGB values
-- collapse to white-or-black and the result would be unreadable.
local function applyToDisplay(presetTable, overrides)
  if not display then return false, "display module not available" end

  if display.isMonochrome and display.isMonochrome() then
    return false, "Color themes require a Tier 2+ GPU (display is monochrome)"
  end

  local merged = {}
  for k, v in pairs(presetTable) do
    if k ~= "description" then merged[k] = v end
  end
  if overrides then
    for k, v in pairs(overrides) do
      if OVERRIDABLE_KEYS[k] then merged[k] = v end
    end
  end

  display.setTheme(merged)
  return true
end

-- Apply a preset by name, with optional ad-hoc overrides on top.
-- Updates the in-memory `current` so subsequent `theme show` is
-- accurate. Does NOT persist; that's saveForUser's job.
function theme.apply(name, overrides)
  local p = PRESETS[name]
  if not p then return false, "Unknown theme: " .. tostring(name) end
  local ok, err = applyToDisplay(p, overrides)
  if not ok then return false, err end
  current.preset    = name
  current.overrides = overrides or {}
  if log then log.info("theme", "Applied preset '" .. name .. "'") end
  return true
end

-- Set a single color override on top of the current preset.
-- value must already be a number (decoded by the caller).
function theme.setColor(key, value)
  if not OVERRIDABLE_KEYS[key] then
    return false, "Not an overridable color: " .. tostring(key)
  end
  if type(value) ~= "number" then
    return false, "Color must be a number (e.g. 0xFF8800)"
  end
  if value < 0 or value > 0xFFFFFF then
    return false, "Color out of range (0x000000 - 0xFFFFFF)"
  end
  current.overrides[key] = value
  return theme.apply(current.preset, current.overrides)
end

-- Drop all overrides and re-apply the base preset.
function theme.resetOverrides()
  current.overrides = {}
  return theme.apply(current.preset, current.overrides)
end

-- ============================================================
-- Persistence
-- ============================================================

local function configPathFor(session)
  if not session or not session.home then return nil end
  return session.home:gsub("/$", "") .. "/" .. SAVE_NAME
end

--- True if `session` has an explicit saved theme (~/.theme.cfg).
-- kernel.profile consults this: a saved `theme set` choice (which can
-- carry per-key color overrides) outranks the profile's coarse preset
-- name, so the profile theme only applies when nothing is saved.
function theme.hasSavedTheme(session)
  local path = configPathFor(session)
  if not path or not securefs then return false end
  local ok, exists = pcall(securefs.exists, path, session)
  return ok and exists == true
end

-- Write the user's theme choice to their home directory. We go
-- through securefs deliberately: a guest with no writable home
-- gets a clean "couldn't save" rather than a kernel-level write.
function theme.saveForUser(session)
  local path = configPathFor(session)
  if not path then return false, "no session / no home" end
  if not securefs then return false, "securefs not available" end

  local payload = {
    preset    = current.preset,
    overrides = current.overrides,
  }
  local ok, encoded = pcall(serialize.encode, payload)
  if not ok then return false, "serialize failed: " .. tostring(encoded) end

  local wOk, wErr = securefs.writeFile(path, encoded, session)
  if not wOk then return false, wErr end
  if log then log.info("theme", "Saved theme for " .. session.user .. " -> " .. path) end
  return true
end

-- Load + apply the user's saved theme, if any. Silently no-ops
-- when there's nothing on disk so a brand-new account just sees
-- the default. Returns (ok, name_or_err).
function theme.applyForUser(session)
  local path = configPathFor(session)
  if not path or not securefs then return false, "no session" end
  if not securefs.exists(path, session) then return false, "no saved theme" end

  local data, err = securefs.readFile(path, session)
  if not data then return false, err or "read failed" end

  -- #SEC H24 — a few KB is more than enough for a theme file (preset name
  -- plus a handful of color overrides). Reject anything larger before
  -- handing it to the serializer; a multi-megabyte theme file otherwise
  -- crashes the kernel main loop at every login.
  if #data > 8192 then
    if log then log.warn("theme", "Theme file too large at " .. path .. " (" .. #data .. " bytes)") end
    return false, "theme file too large"
  end

  local ok, parsed = pcall(serialize.decode, data, { maxBytes = 8192 })
  if not ok or type(parsed) ~= "table" then
    if log then log.warn("theme", "Corrupt theme file at " .. path) end
    return false, "corrupt theme file"
  end

  local presetName = parsed.preset or "default"
  if not PRESETS[presetName] then
    if log then log.warn("theme", "Unknown preset '" .. tostring(presetName) .. "', falling back to default") end
    presetName = "default"
  end

  -- Filter overrides to known keys with valid numbers — guard against
  -- a tampered file injecting arbitrary keys into the THEME table.
  local cleanOverrides = {}
  if type(parsed.overrides) == "table" then
    for k, v in pairs(parsed.overrides) do
      if OVERRIDABLE_KEYS[k] and type(v) == "number"
         and v >= 0 and v <= 0xFFFFFF then
        cleanOverrides[k] = v
      end
    end
  end

  local applied, aerr = theme.apply(presetName, cleanOverrides)
  if not applied then return false, aerr end
  return true, presetName
end

-- Drop the saved theme file (if any) and revert to default.
function theme.clearForUser(session)
  local path = configPathFor(session)
  if not path or not securefs then return false, "no session" end
  if securefs.exists(path, session) then
    local ok, err = securefs.remove(path, session)
    if not ok then return false, err end
  end
  current.overrides = {}
  return theme.apply("default")
end

return theme
