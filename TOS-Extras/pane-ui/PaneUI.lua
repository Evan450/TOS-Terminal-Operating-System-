-- ╔════════════════════════════════════════════════════════════════════╗
-- ║  PaneUI — a TOS-style environment for OpenOS  v0.4                 ║
-- ║                                                                    ║
-- ║  What Windows 3.x was to DOS, PaneUI is to OpenOS: a graphical     ║
-- ║  shell you live in. Browse files, edit with syntax highlighting,   ║
-- ║  and run OpenOS programs from the in-window command line — all in  ║
-- ║  the TOS look-and-feel, returning to the environment afterward.    ║
-- ║  Single-file install: copy to /home/paneui.lua, then `paneui`.     ║
-- ║                                                                    ║
-- ║  v0.4 — adopts TOS's VISUAL GRAMMAR (operator-approved 2026-07-04, ║
-- ║    the five rules TOS's own TUI follows) plus the v1.4.0 "Iris"    ║
-- ║    browser glyphs, so PaneUI and TOS proper still read as one      ║
-- ║    system:                                                         ║
-- ║      1. Frames rank attention — double-line + drop shadow marks a  ║
-- ║         modal (the confirm dialog); single-line stays passive.     ║
-- ║      2. Rails are the skeleton — the path row is now a DIM         ║
-- ║         ─┤ label ├─ rail rather than a filled bar.                 ║
-- ║      3. Ramps ░▒▓ at EDGES ONLY — the status row gets ramp caps;   ║
-- ║         never texture inside content.                              ║
-- ║      4. Hierarchy by contrast, not whitespace — chrome dim, data   ║
-- ║         bright, selection inverse. Density stays.                  ║
-- ║      5. Tabs speak state — inverse = active · [brackets] = busy    ║
-- ║         (unsaved edit / live output) · plain = idle, right-aligned ║
-- ║         with a «N overflow chip when they don't fit.               ║
-- ║    Plus CP437-flavoured file-type glyphs (♦ ≡ ¶ § ▓ · ■ «) drawn   ║
-- ║    one cell at a time, mono-safe on tier-1 GPUs.                   ║
-- ║                                                                    ║
-- ║  v0.3 — UI synced with TOS proper:                                 ║
-- ║    • The NINE TOS named themes (default / midnight / amber /       ║
-- ║      green / plasma / classic / contrast / nord / solarized),      ║
-- ║      color-for-color identical to TOS, derived per GPU tier.       ║
-- ║    • `theme <name>` / `themes` commands, persisted to              ║
-- ║      /home/.paneui-theme (mirrors TOS's `theme set`).              ║
-- ║                                                                    ║
-- ║  v0.2 — tabs, inline editor (undo + Lua highlighting), in-window   ║
-- ║    command line, F5 Copy / F6 Move-Rename.                         ║
-- ║                                                                    ║
-- ║  This is NOT a security boundary. It runs with whatever            ║
-- ║  permissions OpenOS gave it — there's no securefs underneath.      ║
-- ║  It's an environment + file manager, not a sandbox.                ║
-- ╚════════════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local event     = require("event")
local fs        = require("filesystem")
local term      = require("term")
local unicode   = require("unicode")
local shell     = require("shell")

local gpu = component.gpu

-- ============================================================
-- Hardware detection
-- ============================================================

local depth = gpu.getDepth()
local mono  = depth <= 1
local tier  = mono and 1 or (depth <= 4 and 2 or 3)

-- ============================================================
-- Theme
-- ============================================================
-- v0.2 naming rule: a theme key MUST name where it lands, not
-- what it metaphorically represents. So `titlebar_bg` instead of
-- `bar_bg`, `editor_cursor_bg` instead of `selected_bg`. This
-- makes a UI tweak ("the cmd-row prompt is the wrong colour")
-- straightforward to track to the right key.
--
-- Tier-aware: tier-1 collapses everything to fg/bg inversion since
-- we only have black-and-white; tier-2 sticks to the 16-color
-- Minecraft dye palette so OC's color-snapping isn't surprising;
-- tier-3 uses an 8-bit palette tuned for legibility on the OC
-- terminal font.

-- TOS named presets — kept in sync with tos/kernel/theme.lua PRESETS so
-- PaneUI shows the SAME look-and-feel as TOS proper (minus the security
-- backend). Only the small base-color set is stored; deriveTheme() expands
-- it into PaneUI's UI keys the same way TOS's display.syncDerivedTheme does,
-- so the two render identically on the same GPU tier.
local TOS_PRESETS = {
  -- 2026 palette refresh — mirrors tos/kernel/theme.lua. Tinted bars
  -- instead of solid accent blocks; title/warning/error kept distinct.
  default = {
    bg=0x000000, fg=0xE6E6E6, border=0x2FB8C6, title=0xFFD75A,
    highlight=0x42D77D, dim=0x909090, selected_bg=0x0E5E70, selected_fg=0xFFFFFF,
    menubar_bg=0x262B33, menubar_fg=0xE6E6E6, menubar_hot=0xFFD75A,
    statusbar_bg=0x103C4E, statusbar_fg=0xBFE3EE, error=0xFF5C57, warning=0xFFA042,
    panel_bg=0x000000, input_bg=0x14181E, input_fg=0xFFFFFF,
  },
  midnight = {
    bg=0x0D1420, fg=0xD6E2F0, border=0x3E7CB8, title=0x9CC4F0,
    highlight=0x59C2A0, dim=0x7388A6, selected_bg=0x24466B, selected_fg=0xFFFFFF,
    menubar_bg=0x16243A, menubar_fg=0xC4D6EC, menubar_hot=0xF0B35E,
    statusbar_bg=0x16243A, statusbar_fg=0x8FB2D9, error=0xE8606B, warning=0xE8B44C,
    panel_bg=0x0D1420, input_bg=0x1A2C46, input_fg=0xF0F6FF,
  },
  amber = {
    bg=0x0A0500, fg=0xFFB000, border=0xCC8400, title=0xFFD75A,
    highlight=0xFFE599, dim=0x8F5E00, selected_bg=0xFFB000, selected_fg=0x1A0D00,
    menubar_bg=0x241200, menubar_fg=0xFFB000, menubar_hot=0xFFE599,
    statusbar_bg=0x241200, statusbar_fg=0xCC8400, error=0xFF5C57, warning=0xFFE599,
    panel_bg=0x0A0500, input_bg=0x1A0D00, input_fg=0xFFC840,
  },
  green = {
    bg=0x020A02, fg=0x3FD23F, border=0x2AA62A, title=0xA8F0A8,
    highlight=0x88E888, dim=0x1E7A1E, selected_bg=0x3FD23F, selected_fg=0x031003,
    menubar_bg=0x0A2410, menubar_fg=0x66E866, menubar_hot=0xCCFFCC,
    statusbar_bg=0x0A2410, statusbar_fg=0x2AA62A, error=0xFF5C57, warning=0xE8E84C,
    panel_bg=0x020A02, input_bg=0x07180A, input_fg=0x88E888,
  },
  classic = {
    bg=0x0000A8, fg=0xFFFFFF, border=0x55FFFF, title=0xFFFF55,
    highlight=0x55FF55, dim=0xA8B8D8, selected_bg=0x00A8A8, selected_fg=0x000000,
    menubar_bg=0x00A8A8, menubar_fg=0x000000, menubar_hot=0xFFFF55,
    statusbar_bg=0x00A8A8, statusbar_fg=0x000000, error=0xFF5555, warning=0xFFAA55,
    panel_bg=0x0000A8, input_bg=0x000054, input_fg=0xFFFF55,
  },
  contrast = {
    bg=0x000000, fg=0xFFFFFF, border=0xFFFFFF, title=0xFFFF00,
    highlight=0xFFFFFF, dim=0xD0D0D0, selected_bg=0xFFFF00, selected_fg=0x000000,
    menubar_bg=0xFFFFFF, menubar_fg=0x000000, menubar_hot=0xAA0000,
    statusbar_bg=0xFFFFFF, statusbar_fg=0x000000, error=0xFF4040, warning=0xFF9900,
    panel_bg=0x000000, input_bg=0x000000, input_fg=0xFFFFFF,
  },
  plasma = {
    bg=0x000000, fg=0xFF6A33, border=0xCC4A1F, title=0xFFA64D,
    highlight=0xFFC78F, dim=0x8F2E14, selected_bg=0xFF6A33, selected_fg=0x1F0900,
    menubar_bg=0x260C00, menubar_fg=0xFF6A33, menubar_hot=0xFFC78F,
    statusbar_bg=0x260C00, statusbar_fg=0xCC4A1F, error=0xFF2424, warning=0xFF8A1F,
    panel_bg=0x000000, input_bg=0x1F0900, input_fg=0xFFA64D,
  },
  nord = {
    bg=0x2E3440, fg=0xD8DEE9, border=0x81A1C1, title=0x88C0D0,
    highlight=0xA3BE8C, dim=0x616E88, selected_bg=0x434C5E, selected_fg=0xECEFF4,
    menubar_bg=0x3B4252, menubar_fg=0xD8DEE9, menubar_hot=0xEBCB8B,
    statusbar_bg=0x3B4252, statusbar_fg=0x88C0D0, error=0xBF616A, warning=0xEBCB8B,
    panel_bg=0x2E3440, input_bg=0x434C5E, input_fg=0xECEFF4,
  },
  solarized = {
    bg=0x002B36, fg=0x93A1A1, border=0x268BD2, title=0xB58900,
    highlight=0x859900, dim=0x586E75, selected_bg=0x586E75, selected_fg=0xFDF6E3,
    menubar_bg=0x073642, menubar_fg=0x93A1A1, menubar_hot=0xCB4B16,
    statusbar_bg=0x073642, statusbar_fg=0x2AA198, error=0xDC322F, warning=0xCB4B16,
    panel_bg=0x002B36, input_bg=0x073642, input_fg=0xFDF6E3,
  },
}
local THEME_ORDER = { "default", "midnight", "amber", "green", "plasma",
                      "classic", "contrast", "nord", "solarized" }

-- Expand a TOS base preset into PaneUI's UI keys. The role each TOS base
-- color plays mirrors tos/kernel/display.syncDerivedTheme: dir=highlight,
-- file_cfg=warning, menu/status bars use the menubar/statusbar pairs,
-- selection uses selected_*, syntax/feedback tie to the palette accents.
local function deriveTheme(b)
  return {
    bg=b.bg, fg=b.fg,
    -- panel_bg backs MODAL interiors (rule 1): TOS dialogs sit on the
    -- panel colour, not the desktop bg, so the frame reads as a layer
    -- above the content rather than a hole cut into it.
    panel_bg=b.panel_bg or b.bg,
    titlebar_bg=b.statusbar_bg, titlebar_fg=b.statusbar_fg,
    menubar_bg=b.menubar_bg, menubar_fg=b.menubar_fg, menubar_accent=b.menubar_hot,
    pathbar_bg=b.bg, pathbar_fg=b.dim,
    statusbar_bg=b.statusbar_bg, statusbar_fg=b.statusbar_fg,
    cmdbar_bg=b.input_bg, cmdbar_fg=b.input_fg, cmdbar_prompt=b.highlight,
    fkey_num_fg=b.fg, fkey_num_bg=b.bg,
    fkey_lbl_fg=b.selected_fg, fkey_lbl_bg=b.selected_bg,
    selection_bg=b.selected_bg, selection_fg=b.selected_fg,
    file_dir=b.highlight, file_text=b.fg, file_lua=b.border,
    file_cfg=b.warning, file_log=b.dim, file_dim=b.dim,
    editor_cursor_bg=b.fg, editor_cursor_fg=b.bg,
    syntax_keyword=b.border, syntax_string=b.highlight, syntax_comment=b.dim,
    syntax_number=b.warning, syntax_ident=b.fg, syntax_op=b.dim,
    ok=b.highlight, err=b.error, warn=b.warning, dim=b.dim,
    accent=b.border, border=b.border,
  }
end

-- Tier-1: monochrome. TOS disables color themes on 1-bit GPUs (RGB collapses
-- to black/white and would be unreadable); PaneUI does the same — every key
-- is fg/bg or its inverse, regardless of the chosen preset.
local MONO_THEME = {
  bg=0x000000, fg=0xFFFFFF,
  panel_bg=0x000000,
  titlebar_bg=0xFFFFFF, titlebar_fg=0x000000,
  menubar_bg=0xFFFFFF, menubar_fg=0x000000, menubar_accent=0x000000,
  pathbar_bg=0x000000, pathbar_fg=0xFFFFFF,
  statusbar_bg=0xFFFFFF, statusbar_fg=0x000000,
  cmdbar_bg=0x000000, cmdbar_fg=0xFFFFFF, cmdbar_prompt=0xFFFFFF,
  fkey_num_fg=0x000000, fkey_num_bg=0xFFFFFF,
  fkey_lbl_fg=0xFFFFFF, fkey_lbl_bg=0x000000,
  selection_bg=0xFFFFFF, selection_fg=0x000000,
  file_dir=0xFFFFFF, file_text=0xFFFFFF, file_lua=0xFFFFFF, file_cfg=0xFFFFFF,
  file_log=0xFFFFFF, file_dim=0xFFFFFF,
  editor_cursor_bg=0xFFFFFF, editor_cursor_fg=0x000000,
  syntax_keyword=0xFFFFFF, syntax_string=0xFFFFFF, syntax_comment=0xFFFFFF,
  syntax_number=0xFFFFFF, syntax_ident=0xFFFFFF, syntax_op=0xFFFFFF,
  ok=0xFFFFFF, err=0xFFFFFF, warn=0xFFFFFF, dim=0xFFFFFF,
  accent=0xFFFFFF, border=0xFFFFFF,
}

local THEME = {}
local THEME_NAME = "default"
local function c(name) return THEME[name] or 0xFFFFFF end
local function themeNames() return THEME_ORDER end

-- Rebuild THEME in place (so existing closures over it stay valid) from a
-- named preset. On a mono GPU the preset is ignored (mono table used),
-- matching TOS. Returns false for an unknown name (THEME left unchanged).
local function applyTheme(name)
  if not TOS_PRESETS[name] then return false end
  local t = mono and MONO_THEME or deriveTheme(TOS_PRESETS[name])
  for k in pairs(THEME) do THEME[k] = nil end
  for k, v in pairs(t) do THEME[k] = v end
  THEME_NAME = name
  return true
end

-- Persisted choice: one line (the theme name) in the user's home.
local THEME_CFG = "/home/.paneui-theme"
local function saveThemeName(name)
  pcall(function()
    local h = io.open(THEME_CFG, "w")
    if h then h:write(name .. "\n"); h:close() end
  end)
end
local function loadThemeName()
  local name
  pcall(function()
    local h = io.open(THEME_CFG, "r")
    if h then name = (h:read("*l") or ""):match("^%s*(%S*)"); h:close() end
  end)
  return (name and TOS_PRESETS[name]) and name or "default"
end

applyTheme(loadThemeName())

-- Box-drawing characters; ASCII fallback on T1 because some T1
-- screens render unicode but the column widths are unreliable.
--
-- VISUAL GRAMMAR RULE 1 — frames rank attention. Single-line (BOX) is
-- PASSIVE chrome (panes, dividers); DOUBLE-line (DBOX) + a drop shadow
-- marks a MODAL that has taken over input. Mono collapses the two to
-- "+/-" vs "#/=" so the ranking survives without unicode.
local BOX, DBOX
if mono then
  BOX  = { hl = "-", vt = "|", tl = "+", tr = "+", bl = "+", br = "+",
           tt = "+", bt = "+", lt = "+", rt = "+", x = "+" }
  DBOX = { hl = "=", vt = "#", tl = "#", tr = "#", bl = "#", br = "#" }
else
  BOX  = { hl = "─", vt = "│", tl = "┌", tr = "┐", bl = "└", br = "┘",
           tt = "┬", bt = "┴", lt = "├", rt = "┤", x = "┼" }
  DBOX = { hl = "═", vt = "║", tl = "╔", tr = "╗", bl = "╚", br = "╝" }
end

-- RULE 3 — ramps ░▒▓ live at EDGES ONLY (bar caps/filler, dialog
-- shadow). Never inside content. Mono has no shade blocks worth the
-- name, so it degrades to plain (the rule says "ramps→plain on T1").
local RAMP = mono and { l = "", r = "", fill = " ", shadow = " " }
                  or  { l = "▓▒░", r = "░▒▓", fill = "░", shadow = "░" }

-- ── File-type glyphs (v1.4.0 "Iris") ────────────────────────────────
-- One CELL per row in the browser, CP437-flavoured so the DOS aesthetic
-- holds on every GPU tier. Shape-coded rather than colour-coded, so a
-- mono screen still distinguishes types. Mirrors tos/shell/panels/ui.lua
-- fileGlyph(); keep the two tables in step.
local EXT_GLYPHS = {
  lua = "♦",
  txt = "≡", md = "≡", log = "≡",
  man = "¶",
  cfg = "§", conf = "§", json = "§",
  dat = "▓", tcz = "▓", bak = "▓", bin = "▓",
}
local EXT_GLYPHS_MONO = {
  lua = "*",
  txt = "=", md = "=", log = "=",
  man = "P",
  cfg = "$", conf = "$", json = "$",
  dat = "#", tcz = "#", bak = "#", bin = "#",
}

local function fileGlyph(name, isDir)
  if isDir then
    if name == ".." then return mono and "<" or "«" end
    return mono and "D" or "■"
  end
  local ext = type(name) == "string" and name:match("%.(%w+)$") or nil
  local tbl = mono and EXT_GLYPHS_MONO or EXT_GLYPHS
  return (ext and tbl[ext:lower()]) or (mono and "." or "·")
end

-- ============================================================
-- Terminal save / restore
-- ============================================================

local saved = {}

local function saveTerm()
  saved.fg = (gpu.getForeground())
  saved.bg = (gpu.getBackground())
  saved.w, saved.h = gpu.getResolution()
  local cx, cy = term.getCursor()
  saved.cx, saved.cy = cx, cy
  saved.blink = term.getCursorBlink and term.getCursorBlink() or true
end

local function restoreTerm()
  pcall(gpu.setBackground, saved.bg or 0x000000)
  pcall(gpu.setForeground, saved.fg or 0xFFFFFF)
  if saved.w and saved.h then
    pcall(gpu.setResolution, saved.w, saved.h)
    pcall(gpu.fill, 1, 1, saved.w, saved.h, " ")
  end
  pcall(term.setCursor, 1, 1)
  pcall(term.setCursorBlink, saved.blink ~= false)
end

-- ============================================================
-- Drawing primitives
-- ============================================================

local W, H = gpu.getResolution()
-- Pre-built blank string of full width. Substring-of-this beats a
-- per-call string.rep when we're filling rows on every redraw.
local PAD_W = string.rep(" ", W)

local function setFg(col) pcall(gpu.setForeground, col) end
local function setBg(col) pcall(gpu.setBackground, col) end

local function clearScreen()
  setBg(c("bg")); setFg(c("fg"))
  gpu.fill(1, 1, W, H, " ")
end

local function fillRow(y, bg, ch)
  setBg(bg)
  gpu.fill(1, y, W, 1, ch or " ")
end

local function setText(x, y, s, fg, bg)
  if bg then setBg(bg) end
  if fg then setFg(fg) end
  gpu.set(x, y, s)
end

local function fit(s, n)
  s = s or ""
  local len = unicode.len(s)
  if len > n then
    if n <= 1 then return unicode.sub(s, 1, n) end
    return unicode.sub(s, 1, n - 1) .. (mono and ">" or "…")
  end
  return s .. PAD_W:sub(1, n - len)
end

-- ============================================================
-- Filesystem helpers
-- ============================================================

local function listDir(path)
  if not fs.exists(path) then return nil, "no such path" end
  if not fs.isDirectory(path) then return nil, "not a directory" end
  local out = {}
  for name in fs.list(path) do
    local clean = name:gsub("/$", "")
    if clean ~= "" and clean ~= "." and clean ~= ".." then
      local full = fs.concat(path, clean)
      out[#out + 1] = {
        name  = clean,
        path  = full,
        isDir = fs.isDirectory(full),
        size  = fs.size(full) or 0,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.isDir ~= b.isDir then return a.isDir end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

local function fmtSize(bytes)
  if bytes < 1024 then return tostring(bytes) .. "B" end
  if bytes < 1024 * 1024 then return string.format("%.1fK", bytes / 1024) end
  return string.format("%.1fM", bytes / (1024 * 1024))
end

local function isProbablyText(path)
  local ext = path:match("%.([%w]+)$")
  if not ext then return true end
  ext = ext:lower()
  local binary = { png=1, jpg=1, jpeg=1, gif=1, bin=1, exe=1, zip=1, gz=1, tar=1 }
  return binary[ext] == nil
end

local function readTextFile(path, maxBytes)
  maxBytes = maxBytes or 65536
  local h = fs.open(path, "r")
  if not h then return nil, "cannot open" end
  local parts, total = {}, 0
  while total < maxBytes do
    local chunk = h:read(math.min(4096, maxBytes - total))
    if not chunk then break end
    parts[#parts + 1] = chunk
    total = total + #chunk
  end
  h:close()
  return table.concat(parts), total
end

local function writeTextFile(path, content)
  local h = fs.open(path, "w")
  if not h then return false, "cannot open for write" end
  local ok, err = pcall(function() h:write(content) end)
  h:close()
  if not ok then return false, err end
  return true
end

local function copyFile(src, dst)
  -- Binary-safe streaming copy through fs handles. Fixed-size chunks
  -- so a multi-MB asset doesn't blow past the OC memory cap.
  local ih = fs.open(src, "rb") or fs.open(src, "r")
  if not ih then return false, "cannot read source" end
  local oh = fs.open(dst, "wb") or fs.open(dst, "w")
  if not oh then ih:close(); return false, "cannot write dest" end
  while true do
    local chunk = ih:read(4096)
    if not chunk then break end
    oh:write(chunk)
  end
  ih:close(); oh:close()
  return true
end

-- ============================================================
-- Lua syntax tokenizer (inline port of /tos/shell/syntax.lua)
-- ============================================================
-- Used by the editor when the buffer's path ends in .lua. Cheap
-- enough to run per-line per-frame; a real incremental tokenizer
-- isn't worth the bookkeeping at this scale.

local SYN_KEYWORDS = {
  ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,
  ["false"]=1,["for"]=1,["function"]=1,["goto"]=1,["if"]=1,["in"]=1,
  ["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,
  ["then"]=1,["true"]=1,["until"]=1,["while"]=1,
}

local function synTokenize(line)
  local tokens = {}
  local i, len = 1, #line
  while i <= len do
    local ch = line:sub(i, i)

    if ch == "-" and line:sub(i + 1, i + 1) == "-" then
      tokens[#tokens + 1] = { type = "comment", text = line:sub(i) }
      break

    elseif ch == '"' or ch == "'" then
      local quote = ch
      local j = i + 1
      while j <= len do
        local cc = line:sub(j, j)
        if cc == "\\" then j = j + 2
        elseif cc == quote then j = j + 1; break
        else j = j + 1 end
      end
      tokens[#tokens + 1] = { type = "string", text = line:sub(i, j - 1) }
      i = j

    elseif ch == "[" and (line:sub(i + 1, i + 1) == "[" or line:sub(i + 1, i + 1) == "=") then
      local eqs = line:match("^%[(=*)%[", i)
      if eqs then
        local close = "]" .. eqs .. "]"
        local j = line:find(close, i + 2 + #eqs, true)
        j = j and (j + #close) or (len + 1)
        tokens[#tokens + 1] = { type = "string", text = line:sub(i, j - 1) }
        i = j
      else
        tokens[#tokens + 1] = { type = "op", text = ch }
        i = i + 1
      end

    elseif ch:match("%d") or (ch == "." and line:sub(i + 1, i + 1):match("%d")) then
      local j = i
      if line:sub(j, j + 1):lower() == "0x" then
        j = j + 2
        while j <= len and line:sub(j, j):match("[%da-fA-F]") do j = j + 1 end
      else
        while j <= len and line:sub(j, j):match("[%d.]") do j = j + 1 end
        if j <= len and line:sub(j, j):match("[eE]") then
          j = j + 1
          if j <= len and line:sub(j, j):match("[%+%-]") then j = j + 1 end
          while j <= len and line:sub(j, j):match("%d") do j = j + 1 end
        end
      end
      tokens[#tokens + 1] = { type = "number", text = line:sub(i, j - 1) }
      i = j

    elseif ch:match("[%a_]") then
      local j = i + 1
      while j <= len and line:sub(j, j):match("[%w_]") do j = j + 1 end
      local word = line:sub(i, j - 1)
      tokens[#tokens + 1] = {
        type = SYN_KEYWORDS[word] and "keyword" or "ident",
        text = word,
      }
      i = j

    elseif ch:match("%s") then
      local j = i + 1
      while j <= len and line:sub(j, j):match("%s") do j = j + 1 end
      tokens[#tokens + 1] = { type = "space", text = line:sub(i, j - 1) }
      i = j

    else
      tokens[#tokens + 1] = { type = "op", text = ch }
      i = i + 1
    end
  end
  return tokens
end

local function synColor(tokType)
  if tokType == "keyword" then return c("syntax_keyword") end
  if tokType == "string"  then return c("syntax_string")  end
  if tokType == "comment" then return c("syntax_comment") end
  if tokType == "number"  then return c("syntax_number")  end
  if tokType == "ident"   then return c("syntax_ident")   end
  if tokType == "op"      then return c("syntax_op")      end
  return c("fg")
end

-- ============================================================
-- Application state
-- ============================================================
-- Tabs replace v0.1's State.mode. The browser is always tab #1
-- and can't be closed; viewer/editor/output/help tabs come and go.
-- This matches TOS panels' tab model and gives the user something
-- to switch between when running multiple commands or editing
-- multiple files.

local State = {
  cwd          = nil,    -- current directory (browser)
  files        = {},     -- list of entries from listDir
  sel          = 1,      -- selected index (1-based)
  scroll       = 0,      -- top of visible window
  tabs         = {},     -- array of tab tables (see tabCreate)
  activeTab    = 1,      -- index into tabs
  out          = "",     -- transient status message
  outCol       = nil,
  cmdline      = "",     -- pending command in the cmd row
  cmdHist      = {},     -- previously-executed commands
  cmdHistIdx   = 0,      -- 0 = "current edit", N = browsing history
  lastClockSec = -1,
  quitting     = false,
}

-- ============================================================
-- Layout
-- ============================================================
--   1            Title bar (mem + clock + tab strip)
--   2            Menu bar
--   3            Path breadcrumb / viewer-or-editor title
--   4 .. H-3     Content (file list, viewer, editor)
--   H-2          Status / output line
--   H-1          Command line
--   H            F-key bar

local TITLE_ROW   = 1
local MENU_ROW    = 2
local PATH_ROW    = 3
local CONTENT_TOP = 4
local STATUS_ROW
local CMD_ROW
local FKEY_ROW
local CONTENT_BOT

local function recomputeLayout()
  W, H = gpu.getResolution()
  PAD_W = string.rep(" ", W)
  STATUS_ROW  = H - 2
  CMD_ROW     = H - 1
  FKEY_ROW    = H
  CONTENT_BOT = STATUS_ROW - 1
end
recomputeLayout()

-- ============================================================
-- Tabs
-- ============================================================

local function tabCreate(tabType, label, data)
  local tab = { type = tabType, label = label }
  if data then for k, v in pairs(data) do tab[k] = v end end
  State.tabs[#State.tabs + 1] = tab
  State.activeTab = #State.tabs
  return tab
end

local function tabClose(idx)
  idx = idx or State.activeTab
  -- Tab #1 is the browser and can't be closed (matches TOS panels;
  -- also avoids the empty-tabs degenerate state).
  if idx == 1 or State.tabs[idx].type == "browser" then return false end
  table.remove(State.tabs, idx)
  if State.activeTab > #State.tabs then State.activeTab = #State.tabs end
  if State.activeTab < 1 then State.activeTab = 1 end
  return true
end

local function tabCycle(dir)
  if #State.tabs <= 1 then return end
  State.activeTab = State.activeTab + (dir or 1)
  if State.activeTab > #State.tabs then State.activeTab = 1 end
  if State.activeTab < 1 then State.activeTab = #State.tabs end
end

local function tabFind(tabType, path)
  for i, tab in ipairs(State.tabs) do
    if tab.type == tabType and tab.path == path then return i end
  end
  return nil
end

local function activeTab() return State.tabs[State.activeTab] end

-- ============================================================
-- Drawing — title bar + tab strip
-- ============================================================

-- RULE 5 — tabs speak state. A chip renders INVERSE when it's the
-- active tab, [bracketed] when it's BUSY (an edit with unsaved changes,
-- or a live output tab), and plain when idle. Pure: builds the chip
-- models, no drawing, so the fitting math below can measure them.
local function tabChips(labelW)
  local chips = {}
  for i, tab in ipairs(State.tabs) do
    local label = tab.label or "?"
    if unicode.len(label) > labelW then
      label = unicode.sub(label, 1, labelW - 1) .. (mono and ">" or "~")
    end
    local state = "idle"
    if i == State.activeTab then state = "active"
    elseif tab.live or (tab.type == "edit" and tab.modified) then state = "busy" end
    local text = (state == "busy") and ("[" .. label .. "]") or (" " .. label .. " ")
    chips[#chips + 1] = { text = text, state = state, idx = i }
  end
  return chips
end

-- Lay chips out RIGHT-ALIGNED ending at `rightEnd`, never starting left
-- of `leftMin`. Drops from the FRONT when they don't fit — but never the
-- active one. Returns (spans, hiddenCount). Mirrors TOS ui.chipSpans.
local function chipSpans(chips, rightEnd, leftMin)
  local keep = {}
  for i, ch in ipairs(chips) do keep[i] = ch end
  local total = #keep
  local function totalW(list)
    local w = 0
    for i, ch in ipairs(list) do w = w + unicode.len(ch.text) + (i > 1 and 1 or 0) end
    return w
  end
  while #keep > 1 and totalW(keep) > (rightEnd - leftMin + 1) do
    if keep[1].state == "active" then table.remove(keep, 2)
    else table.remove(keep, 1) end
  end
  if #keep == 1 and totalW(keep) > (rightEnd - leftMin + 1) then return {}, total end
  local spans = {}
  local x = rightEnd - totalW(keep) + 1
  for i, ch in ipairs(keep) do
    if i > 1 then x = x + 1 end
    local w = unicode.len(ch.text)
    spans[#spans + 1] = { s = x, idx = ch.idx, text = ch.text, state = ch.state }
    x = x + w
  end
  return spans, total - #keep
end

-- Full fitting policy: try label widths 10 → 8 → 6 → 5, then lead with a
-- «N overflow chip so the hidden count is always visible.
local function fitChips(rightEnd, leftMin)
  local spans, hidden
  for _, lw in ipairs({ 10, 8, 6, 5 }) do
    local chips = tabChips(lw)
    spans, hidden = chipSpans(chips, rightEnd, leftMin)
    if hidden == 0 then return spans end
    if lw == 5 then
      local moreText = (mono and "<" or "«") .. hidden
      spans, hidden = chipSpans(chips, rightEnd, leftMin + unicode.len(moreText) + 3)
      moreText = (mono and "<" or "«") .. hidden
      local s = ((spans[1] and spans[1].s) or (rightEnd - unicode.len(moreText) + 1))
        - unicode.len(moreText) - 1
      if s >= leftMin then
        table.insert(spans, 1,
          { s = s, idx = 0, text = moreText, state = "more" })
      end
      return spans
    end
  end
  return spans or {}
end

local function drawTitle()
  fillRow(TITLE_ROW, c("titlebar_bg"))

  -- Left: the wordmark, so the bar identifies the environment the way
  -- TOS's own merged header does.
  setText(2, TITLE_ROW, "PaneUI", c("menubar_accent"), c("titlebar_bg"))

  -- Right: vitals (machine-generated ASCII, so byte math is exact).
  local freeKB = math.floor(computer.freeMemory() / 1024)
  local totKB  = math.floor(computer.totalMemory() / 1024)
  local up     = computer.uptime()
  local mins   = math.floor(up / 60)
  local secs   = math.floor(up % 60)
  local right  = string.format(" %d/%dK  %d:%02d ", freeKB, totKB, mins, secs)
  local rightX = W - #right + 1
  if rightX < 16 then rightX = 16 end
  setText(rightX, TITLE_ROW, right, c("dim"), c("titlebar_bg"))

  -- Tab chips fill the middle, right-aligned against the vitals block.
  for _, sp in ipairs(fitChips(rightX - 2, 9)) do
    local fg, bg = c("titlebar_fg"), c("titlebar_bg")
    if sp.state == "active" then
      fg, bg = c("selection_fg"), c("selection_bg")     -- inverse = active
    elseif sp.state == "busy" then
      fg = c("menubar_accent")                          -- [brackets] = busy
    elseif sp.state == "more" then
      fg = c("dim")
    end
    setText(sp.s, TITLE_ROW, sp.text, fg, bg)
  end
end

-- ============================================================
-- Drawing — menu bar
-- ============================================================
-- v0.2 keeps the menu non-interactive (the F-key bar provides the
-- same actions). The hotkey letter is highlighted so users know it
-- exists; making it Alt-activatable would need keyboard-modifier
-- state OpenOS doesn't expose cleanly.

local MENU_ITEMS = { " File ", " Edit ", " View ", " Tools ", " Help " }

local function drawMenu()
  fillRow(MENU_ROW, c("menubar_bg"))
  local x = 1
  for _, item in ipairs(MENU_ITEMS) do
    setText(x, MENU_ROW, item, c("menubar_fg"), c("menubar_bg"))
    setText(x + 1, MENU_ROW, unicode.sub(item, 2, 2),
      c("menubar_accent"), c("menubar_bg"))
    x = x + unicode.len(item) + 1
  end
end

-- ============================================================
-- Drawing — path / title row
-- ============================================================

-- RULE 2 — rails are the skeleton. A rail is a DIM ─ line carrying
-- tabbed labels (─┤ label ├─); RULE 4 then re-draws the label text
-- brighter so data pops over structure. Composition is column-tracked
-- (the tees are multi-byte) so a long path can't skew the line.
-- Mirrors TOS ui.railText / ui.drawRail.
local function drawRail(y, parts, opts)
  opts = opts or {}
  local bg = opts.bg or c("bg")
  local segs, spans = {}, {}
  local col = 1
  local function fill(n)
    if n > 0 then segs[#segs + 1] = string.rep(BOX.hl, n); col = col + n end
  end
  for _, p in ipairs(parts) do
    local tabbed = p.label ~= nil
    local label = tostring(p.label or p.text or "")
    local lw = unicode.len(label)
    if col == 1 then fill(1) end            -- a rail never opens with a tee
    local cellW = lw + (tabbed and 4 or 2)  -- "┤ x ├" or " x "
    if col + cellW - 1 > W then
      local avail = W - col - (tabbed and 4 or 2)
      if avail < 1 then break end
      label = unicode.sub(label, 1, avail)
      lw = unicode.len(label)
      cellW = lw + (tabbed and 4 or 2)
    end
    if tabbed then
      segs[#segs + 1] = BOX.rt .. " " .. label .. " " .. BOX.lt
      spans[#spans + 1] = { s = col + 2, label = label }
    else
      segs[#segs + 1] = " " .. label .. " "
      spans[#spans + 1] = { s = col + 1, label = label }
    end
    col = col + cellW
  end
  fill(W - col + 1)
  fillRow(y, bg)
  setText(1, y, table.concat(segs), opts.fg or c("dim"), bg)
  for _, sp in ipairs(spans) do
    setText(sp.s, y, sp.label, opts.labelFg or c("fg"), bg)
  end
  return spans
end

local function drawPath()
  local tab = activeTab()
  local label
  if tab and tab.type == "view" then
    label = "VIEW: " .. (tab.path or tab.label or "(buffer)")
  elseif tab and tab.type == "edit" then
    local mod = tab.modified and " [+]" or ""
    label = "EDIT: " .. (tab.path or tab.label or "(new)") .. mod
  elseif tab and tab.type == "output" then
    label = "OUTPUT: " .. (tab.label or "(cmd)")
  elseif tab and tab.type == "help" then
    label = "HELP"
  else
    label = State.cwd or "/"
  end
  -- Browser rows get a second, right-hand rail label with the entry
  -- count — the "summary rail" TOS merged into its header.
  local parts = { { label = label } }
  if (not tab) or tab.type == "browser" then
    parts[#parts + 1] = { label = #State.files .. " items" }
  end
  drawRail(PATH_ROW, parts, { labelFg = c("pathbar_fg") })
end

-- ============================================================
-- Drawing — file list (browser tab)
-- ============================================================

local function visibleRows() return CONTENT_BOT - CONTENT_TOP + 1 end

local function ensureSelectionVisible()
  local rows = visibleRows()
  if State.sel < State.scroll + 1 then
    State.scroll = State.sel - 1
  elseif State.sel > State.scroll + rows then
    State.scroll = State.sel - rows
  end
  if State.scroll < 0 then State.scroll = 0 end
end

local function fileRowColor(f)
  if f.isDir then return c("file_dir") end
  local n = f.name:lower()
  if n:match("%.lua$") then return c("file_lua") end
  if n:match("%.cfg$") or n:match("%.conf$") then return c("file_cfg") end
  if n:match("%.log$") then return c("file_log") end
  return c("file_text")
end

local function drawFileList()
  setBg(c("bg")); setFg(c("fg"))
  for r = CONTENT_TOP, CONTENT_BOT do
    gpu.fill(1, r, W, 1, " ")
  end

  local rows  = visibleRows()
  local files = State.files

  if #files == 0 then
    setText(2, CONTENT_TOP, "(empty directory)", c("dim"), c("bg"))
    return
  end

  ensureSelectionVisible()

  for i = 1, rows do
    local idx = State.scroll + i
    local f = files[idx]
    if not f then break end

    local y = CONTENT_TOP + i - 1
    local isSel = (idx == State.sel)
    local bg = isSel and c("selection_bg") or c("bg")
    local fg = isSel and c("selection_fg") or fileRowColor(f)

    setBg(bg)
    gpu.fill(1, y, W, 1, " ")

    local sizeStr = f.isDir and "<DIR>" or fmtSize(f.size)
    local nameMax = W - 6 - #sizeStr

    -- v1.4.0 "Iris" file-type glyph. Drawn as its OWN single-cell set,
    -- never concatenated into a padded ASCII run — the glyphs are
    -- multi-byte UTF-8 and `fit()`'s padding math counts columns, so
    -- mixing them would skew every column to the right of it.
    setText(2, y, fileGlyph(f.name, f.isDir),
      isSel and c("selection_fg") or fg, bg)
    setText(4, y, fit(f.name, nameMax), fg, bg)
    setText(W - #sizeStr - 1, y, sizeStr,
      isSel and c("selection_fg") or c("file_dim"), bg)
  end

  if #files > rows then
    local thumbPos = math.floor(
      (State.scroll / math.max(1, #files - rows)) * (rows - 1) + 0.5)
    setBg(c("bg")); setFg(c("border"))
    for i = 0, rows - 1 do
      local ch = (i == thumbPos) and (mono and "#" or "█") or (mono and "|" or BOX.vt)
      gpu.set(W, CONTENT_TOP + i, ch)
    end
  end
end

-- ============================================================
-- Drawing — viewer tab
-- ============================================================

local function splitLines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function drawViewer(tab)
  setBg(c("bg")); setFg(c("fg"))
  for r = CONTENT_TOP, CONTENT_BOT do
    gpu.fill(1, r, W, 1, " ")
  end

  local rows = visibleRows()
  local lines = tab.lines or {}
  if #lines == 0 then
    setText(2, CONTENT_TOP, "(empty)", c("dim"), c("bg"))
    return
  end

  for i = 1, rows do
    local idx = (tab.scroll or 0) + i
    local line = lines[idx]
    if not line then break end
    line = line:gsub("\t", "  ")
    local y = CONTENT_TOP + i - 1
    local ln = string.format("%4d ", idx)
    setText(1, y, ln, c("dim"), c("bg"))
    setText(6, y, fit(line, W - 6), c("fg"), c("bg"))
  end

  if #lines > rows then
    local thumbPos = math.floor(
      ((tab.scroll or 0) / math.max(1, #lines - rows)) * (rows - 1) + 0.5)
    setBg(c("bg")); setFg(c("border"))
    for i = 0, rows - 1 do
      local ch = (i == thumbPos) and (mono and "#" or "█") or (mono and "|" or BOX.vt)
      gpu.set(W, CONTENT_TOP + i, ch)
    end
  end
end

-- ============================================================
-- Drawing — editor tab
-- ============================================================
-- Ports the layout from /tos/shell/panels/draw.lua editTab:
--   • 4-char gutter shows the line number; current row is brighter
--   • Lua syntax highlighting on .lua files only (cheap-enough
--     per-frame; no incremental tokenizer)
--   • Cursor drawn as a single inverted cell

local function drawEditor(tab)
  setBg(c("bg")); setFg(c("fg"))
  for r = CONTENT_TOP, CONTENT_BOT do
    gpu.fill(1, r, W, 1, " ")
  end

  local lines   = tab.lines or { "" }
  local edRows  = CONTENT_BOT - CONTENT_TOP + 1
  local gutterW = math.max(#tostring(#lines), 2) + 1
  local editW   = W - gutterW
  local isLua   = tab.path and tab.path:match("%.lua$")

  for i = 1, edRows do
    local li = (tab.viewTop or 1) + i - 1
    if li > #lines then break end

    local y = CONTENT_TOP + i - 1
    local lnColor = (li == tab.curRow) and c("accent") or c("dim")
    local lnText  = string.format("%" .. (gutterW - 1) .. "d ", li)
    setText(1, y, lnText, lnColor, c("bg"))

    local lineText = lines[li] or ""

    if isLua then
      local tokens = synTokenize(lineText)
      local x = gutterW + 1
      for _, tok in ipairs(tokens) do
        local txt = tok.text
        if x - gutterW - 1 + #txt > editW then
          txt = txt:sub(1, editW - (x - gutterW - 1))
        end
        if #txt > 0 then
          setText(x, y, txt, synColor(tok.type), c("bg"))
          x = x + #txt
        end
        if x > W then break end
      end
    else
      setText(gutterW + 1, y, fit(lineText, editW), c("fg"), c("bg"))
    end
  end

  -- Cursor: inverted cell, drawn only when row is in viewport.
  local cy = (tab.curRow or 1) - (tab.viewTop or 1) + CONTENT_TOP
  if cy >= CONTENT_TOP and cy <= CONTENT_BOT then
    local curX = gutterW + (tab.curCol or 1)
    if curX <= W then
      local rowText = lines[tab.curRow] or ""
      local ch = rowText:sub(tab.curCol, tab.curCol)
      if ch == "" then ch = " " end
      setText(curX, cy, ch, c("editor_cursor_fg"), c("editor_cursor_bg"))
    end
  end
end

-- ============================================================
-- Drawing — status, command line, F-key bar
-- ============================================================

-- RULE 3 — ramps at the EDGES only: ▓▒░ caps with ░ filler across the
-- status row, the bright text inset between them. Mirrors TOS
-- ui.drawRampBar. On mono this degrades to a plain filled row.
local function drawRampBar(y, text, fg, bg)
  bg = bg or c("statusbar_bg")
  fg = fg or c("statusbar_fg")
  fillRow(y, bg, RAMP.fill)
  if not mono then
    setText(1, y, RAMP.l, c("dim"), bg)
    if W > 6 then setText(W - 2, y, RAMP.r, c("dim"), bg) end
  end
  local inset = mono and 2 or 5
  local avail = math.max(0, W - inset - (mono and 1 or 4))
  local t = text or ""
  if unicode.len(t) > avail then t = unicode.sub(t, 1, avail) end
  if #t > 0 then setText(inset, y, " " .. t .. " ", fg, bg) end
end

local function drawStatus()
  local txt = State.out
  if txt == "" or not txt then
    local tab = activeTab()
    local t = tab and tab.type or "browser"
    if t == "browser" then
      txt = "↑↓ Move  Enter Open  Bksp Up  F3 View  F4 Edit  F8 Del  F10 Quit"
    elseif t == "view" then
      txt = "↑↓ Scroll  PgUp/PgDn  Home/End  ^Q or Esc to close tab"
    elseif t == "edit" then
      txt = "↑↓←→ Move  ^S Save  ^Z Undo  ^Q Close  Type to insert"
    elseif t == "output" then
      txt = "↑↓ Scroll  ^Q Close tab"
    elseif t == "help" then
      txt = "Press any key or ^Q to close help"
    end
    if mono then
      txt = txt:gsub("↑", "U"):gsub("↓", "D"):gsub("←", "L"):gsub("→", "R")
    end
  end
  drawRampBar(STATUS_ROW, txt, State.outCol or c("statusbar_fg"))
end

local function drawCmdRow()
  fillRow(CMD_ROW, c("cmdbar_bg"))
  local who    = (os.getenv and os.getenv("USER")) or "user"
  local cwd    = State.cwd or "/"
  local prompt = who .. "@openos:" .. cwd .. "$ "
  if #prompt > math.floor(W / 2) then
    prompt = who .. "$ "
  end
  setText(1, CMD_ROW, prompt, c("cmdbar_prompt"), c("cmdbar_bg"))

  local px    = #prompt + 1
  local avail = W - #prompt
  local cmd   = State.cmdline
  local shown = #cmd > avail - 1 and cmd:sub(#cmd - (avail - 2)) or cmd
  setText(px, CMD_ROW, fit(shown, avail - 1), c("cmdbar_fg"), c("cmdbar_bg"))

  -- Cursor only when the browser tab is active — that's the only mode
  -- where keystrokes actually go into the cmdline. In editor/viewer
  -- tabs the cmdline is preserved but inert; the inert cursor would
  -- be misleading.
  local tab = activeTab()
  local active = tab and tab.type == "browser"
  if active then
    local cx = px + #shown
    if cx <= W then
      setText(cx, CMD_ROW, "_", c("cmdbar_prompt"), c("cmdbar_bg"))
    end
  end
end

local FKEYS_BROWSER = {
  {1,"Help"},{3,"View"},{4,"Edit"},{5,"Copy"},{6,"Move"},
  {7,"MkDir"},{8,"Del"},{9,"Shell"},{10,"Quit"},
}
local FKEYS_VIEWER = { {1,"Help"},{2,"NextTab"},{10,"Quit"} }
local FKEYS_EDITOR = { {1,"Help"},{2,"NextTab"},{10,"Quit"} }
local FKEYS_OUTPUT = { {1,"Help"},{2,"NextTab"},{10,"Quit"} }
local FKEYS_HELP   = { {2,"NextTab"},{10,"Quit"} }

local function drawFkeys()
  fillRow(FKEY_ROW, c("fkey_lbl_bg"))
  local tab = activeTab()
  local t = tab and tab.type or "browser"
  local items
  if t == "view"   then items = FKEYS_VIEWER
  elseif t == "edit"   then items = FKEYS_EDITOR
  elseif t == "output" then items = FKEYS_OUTPUT
  elseif t == "help"   then items = FKEYS_HELP
  else                      items = FKEYS_BROWSER end

  local x = 1
  for _, item in ipairs(items) do
    local num = tostring(item[1])
    local lbl = item[2]
    setText(x, FKEY_ROW, num, c("fkey_num_fg"), c("fkey_num_bg"))
    x = x + #num
    setText(x, FKEY_ROW, lbl .. " ", c("fkey_lbl_fg"), c("fkey_lbl_bg"))
    x = x + #lbl + 1
    if x >= W - 4 then break end
  end
end

-- ============================================================
-- Drawing — help screen
-- ============================================================

local HELP_LINES = {
  "PaneUI v0.4 — TOS panels look-and-feel for OpenOS",
  "",
  "BROWSER",
  "  Up/Down      Move selection",
  "  Page Up/Dn   Page through long lists",
  "  Home/End     First / last entry",
  "  Enter        Open dir / view file",
  "  Backspace    Up one directory",
  "  F3           View selected file (text)",
  "  F4           Edit selected (or new file if empty selection)",
  "  F5           Copy selected file",
  "  F6           Move / rename selected",
  "  F7           Make new directory",
  "  F8           Delete selected (with confirm)",
  "  F9           Drop to OpenOS shell (resume after exit)",
  "  F10 / Ctrl+Q Quit back to OpenOS",
  "",
  "COMMAND LINE (cmd row above F-keys, always active in browser)",
  "  Type a command, Enter to run.",
  "  Output captured to a viewer tab.",
  "  Up/Down arrows recall history when cmdline is non-empty.",
  "  Builtins handled in-process: cd, clear, exit/quit.",
  "",
  "VIEWER",
  "  Up/Down/PgUp/PgDn/Home/End to scroll",
  "  Ctrl+Q or Esc to close the tab",
  "",
  "EDITOR",
  "  Arrows / PgUp / PgDn / Home / End move the cursor",
  "  Type to insert; Backspace / Delete to remove",
  "  Tab inserts two spaces",
  "  Ctrl+S         Save",
  "  Ctrl+Z         Undo (structural edits only: Enter, line-merges, paste)",
  "  Ctrl+Q / F10   Close tab (prompts to save if modified)",
  "",
  "TABS",
  "  F2             Next tab",
  "  Ctrl+Q         Close current tab (browser tab is permanent)",
  "",
}

local function drawHelpScreen()
  setBg(c("bg")); setFg(c("fg"))
  for r = CONTENT_TOP, CONTENT_BOT do
    gpu.fill(1, r, W, 1, " ")
  end
  setFg(c("border"))
  gpu.set(2, CONTENT_TOP, BOX.tl .. string.rep(BOX.hl, W - 4) .. BOX.tr)
  for r = CONTENT_TOP + 1, CONTENT_BOT - 1 do
    gpu.set(2, r, BOX.vt)
    gpu.set(W - 1, r, BOX.vt)
  end
  gpu.set(2, CONTENT_BOT, BOX.bl .. string.rep(BOX.hl, W - 4) .. BOX.br)

  for i, line in ipairs(HELP_LINES) do
    local y = CONTENT_TOP + i
    if y >= CONTENT_BOT then break end
    local fg = c("fg")
    if line:match("^[A-Z][A-Z]+$") or i == 1 then fg = c("accent") end
    setText(4, y, fit(line, W - 8), fg, c("bg"))
  end
end

-- ============================================================
-- Repaint dispatcher
-- ============================================================

local function repaint()
  recomputeLayout()
  clearScreen()
  drawTitle()
  drawMenu()
  drawPath()

  local tab = activeTab()
  local t = tab and tab.type or "browser"
  if t == "browser" then drawFileList()
  elseif t == "view" or t == "output" then drawViewer(tab)
  elseif t == "edit" then drawEditor(tab)
  elseif t == "help" then drawHelpScreen() end

  drawStatus()
  drawCmdRow()
  drawFkeys()
end

-- ============================================================
-- Confirmation dialog
-- ============================================================

-- RULE 1 — frames rank attention: a modal that has taken over input
-- gets the DOUBLE-line frame plus a drop shadow (rule 3's one sanctioned
-- interior use of a ramp: it's an edge, not content). Panes and
-- dividers keep the single-line BOX.
local function confirmDialog(prompt)
  local boxW = math.min(W - 4, math.max(40, #prompt + 6))
  local boxH = 7
  local x = math.floor((W - boxW) / 2) + 1
  local y = math.floor((H - boxH) / 2) + 1

  -- Shadow first, so the frame paints over its own top-left corner.
  if not mono then
    setBg(c("bg")); setFg(c("dim"))
    for r = y + 1, y + boxH do
      if r <= H and x + boxW <= W then gpu.set(x + boxW, r, RAMP.shadow) end
    end
    if y + boxH <= H then
      gpu.set(x + 1, y + boxH, string.rep(RAMP.shadow, math.min(boxW - 1, W - x)))
    end
  end

  setBg(c("panel_bg")); setFg(c("border"))
  gpu.fill(x, y, boxW, boxH, " ")
  gpu.set(x, y, DBOX.tl .. string.rep(DBOX.hl, boxW - 2) .. DBOX.tr)
  gpu.set(x, y + boxH - 1, DBOX.bl .. string.rep(DBOX.hl, boxW - 2) .. DBOX.br)
  for r = y + 1, y + boxH - 2 do
    gpu.set(x, r, DBOX.vt)
    gpu.set(x + boxW - 1, r, DBOX.vt)
  end

  local bg = c("panel_bg")
  setText(x + 2, y, " Confirm ", c("accent"), bg)
  setText(x + 3, y + 2, fit(prompt, boxW - 6), c("fg"), bg)
  setText(x + 3, y + 4, "[Y]es   [N]o", c("dim"), bg)

  while true do
    local _, _, ch = event.pull("key_down")
    if ch == 89 or ch == 121 then return true end
    if ch == 78 or ch == 110 or ch == 27 then return false end
  end
end

-- ============================================================
-- Inline prompt (used for mkdir, copy-to, move-to, save-as)
-- ============================================================

local function promptInput(prompt, prefill)
  fillRow(STATUS_ROW, c("statusbar_bg"))
  setText(2, STATUS_ROW, prompt .. " ", c("statusbar_fg"), c("statusbar_bg"))
  setFg(c("statusbar_fg"))

  local buf    = prefill or ""
  local startX = 2 + #prompt + 1
  local function redraw()
    setBg(c("statusbar_bg"))
    gpu.fill(startX, STATUS_ROW, W - startX, 1, " ")
    setText(startX, STATUS_ROW, fit(buf, W - startX - 1),
      c("statusbar_fg"), c("statusbar_bg"))
  end
  redraw()

  while true do
    local _, _, ch, code = event.pull("key_down")
    if code == 28 then return buf
    elseif code == 1 then return nil
    elseif code == 14 then
      if #buf > 0 then buf = buf:sub(1, -2); redraw() end
    elseif ch and ch >= 32 and ch < 127 then
      if startX + #buf < W then
        buf = buf .. string.char(ch)
        redraw()
      end
    end
  end
end

-- ============================================================
-- Browser file operations
-- ============================================================

local function refresh()
  local list, err = listDir(State.cwd)
  if not list then
    State.out = "Error: " .. tostring(err)
    State.outCol = c("err")
    State.files = {}
  else
    State.files = list
    if State.sel > #list then State.sel = math.max(1, #list) end
    if State.sel < 1 then State.sel = 1 end
  end
end

local function goUp()
  if State.cwd == "/" then return end
  local parent = fs.path(State.cwd) or "/"
  parent = parent:gsub("/$", "")
  if parent == "" then parent = "/" end
  local prevName = State.cwd:match("([^/]+)/?$")
  State.cwd   = parent
  State.sel   = 1
  State.scroll = 0
  refresh()
  if prevName then
    for i, f in ipairs(State.files) do
      if f.name == prevName then State.sel = i; break end
    end
  end
end

local function selectedEntry() return State.files[State.sel] end

local function navigateInto(f)
  State.cwd    = f.path
  State.sel    = 1
  State.scroll = 0
  refresh()
end

local function deleteSelected()
  local f = selectedEntry()
  if not f then return end
  if not confirmDialog("Delete '" .. f.name .. "'? Cannot be undone.") then
    State.out = "Cancelled"
    return
  end
  local ok, err = pcall(fs.remove, f.path)
  if not ok or ok == false then
    State.out = "Delete failed: " .. tostring(err or "unknown")
    State.outCol = c("err")
  else
    State.out = "Deleted: " .. f.name
    State.outCol = c("ok")
    refresh()
  end
end

local function mkdirHere()
  local name = promptInput("New directory name:")
  if not name or name == "" then State.out = "Cancelled"; return end
  if name:find("/") then
    State.out = "Name cannot contain '/'"
    State.outCol = c("err")
    return
  end
  local target = fs.concat(State.cwd, name)
  local ok, err = fs.makeDirectory(target)
  if not ok then
    State.out = "mkdir failed: " .. tostring(err or "exists?")
    State.outCol = c("err")
  else
    State.out = "Created: " .. name
    State.outCol = c("ok")
    refresh()
    for i, f in ipairs(State.files) do
      if f.name == name then State.sel = i; break end
    end
  end
end

local function copySelected()
  local f = selectedEntry()
  if not f then return end
  if f.isDir then
    State.out = "Directory copy not yet supported"
    State.outCol = c("warn")
    return
  end
  local dst = promptInput("Copy to:", fs.concat(State.cwd, f.name .. ".bak"))
  if not dst or dst == "" then State.out = "Cancelled"; return end
  if fs.exists(dst) then
    if not confirmDialog("Overwrite '" .. dst .. "'?") then
      State.out = "Cancelled"; return
    end
  end
  local ok, err = copyFile(f.path, dst)
  if ok then
    State.out = "Copied to: " .. dst
    State.outCol = c("ok")
    refresh()
  else
    State.out = "Copy failed: " .. tostring(err)
    State.outCol = c("err")
  end
end

local function moveSelected()
  local f = selectedEntry()
  if not f then return end
  local dst = promptInput("Move to:", fs.concat(State.cwd, f.name))
  if not dst or dst == "" then State.out = "Cancelled"; return end
  if dst == f.path then State.out = "Cancelled"; return end
  if fs.exists(dst) then
    if not confirmDialog("Overwrite '" .. dst .. "'?") then
      State.out = "Cancelled"; return
    end
  end
  -- fs.rename works only same-fs; on cross-fs OpenOS returns
  -- false+err and we fall back to copy+remove.
  local renameOk = pcall(fs.rename, f.path, dst)
  if not renameOk or not fs.exists(dst) then
    local cok, cerr = copyFile(f.path, dst)
    if not cok then
      State.out = "Move failed: " .. tostring(cerr)
      State.outCol = c("err")
      return
    end
    pcall(fs.remove, f.path)
  end
  State.out = "Moved to: " .. dst
  State.outCol = c("ok")
  refresh()
end

local function dropToShell()
  -- Hand the screen back to OpenOS, run a sub-shell, come back when
  -- the user types `exit`.
  restoreTerm()
  io.write("\n[PaneUI] Type 'exit' to return.\n")
  pcall(shell.execute, "/bin/sh.lua")
  saveTerm()
  recomputeLayout()
  pcall(term.setCursorBlink, false)
end

-- ============================================================
-- Editor operations
-- ============================================================

local UNDO_MAX = 32

local function pushUndo(tab)
  tab.undoStack = tab.undoStack or {}
  -- Snapshot a shallow copy of the lines array. String values are
  -- immutable in Lua so the inner copies are reference-only — cheap.
  local snap = {}
  for i, l in ipairs(tab.lines) do snap[i] = l end
  tab.undoStack[#tab.undoStack + 1] = {
    lines = snap, row = tab.curRow, col = tab.curCol,
  }
  if #tab.undoStack > UNDO_MAX then
    table.remove(tab.undoStack, 1)
  end
end

local function clampEditor(tab)
  local edRows = CONTENT_BOT - CONTENT_TOP + 1
  tab.curRow = math.max(1, math.min(#tab.lines, tab.curRow))
  tab.curCol = math.max(1, math.min(#(tab.lines[tab.curRow] or "") + 1, tab.curCol))
  if tab.curRow < tab.viewTop then tab.viewTop = tab.curRow end
  if tab.curRow > tab.viewTop + edRows - 1 then
    tab.viewTop = tab.curRow - edRows + 1
  end
end

local function openEditTab(path)
  if path then
    local existing = tabFind("edit", path)
    if existing then State.activeTab = existing; return end
  end
  local lines = { "" }
  if path and fs.exists(path) then
    local content = readTextFile(path)
    if content then
      lines = {}
      for l in content:gmatch("([^\n]*)\n?") do lines[#lines + 1] = l end
      if #lines == 0 then lines[1] = "" end
      if lines[#lines] == "" and #lines > 1 then lines[#lines] = nil end
    end
  end
  local fname = (path and path:match("[^/]+$")) or "new file"
  tabCreate("edit", fname, {
    path      = path,
    lines     = lines,
    curRow    = 1,
    curCol    = 1,
    viewTop   = 1,
    modified  = false,
    undoStack = {},
  })
end

local function saveEditTab(tab)
  if not tab.path then
    local p = promptInput("Save as:", fs.concat(State.cwd, tab.label or "untitled"))
    if not p or p == "" then State.out = "Save cancelled"; return false end
    tab.path = p
    tab.label = p:match("[^/]+$") or p
  end
  local ok, err = writeTextFile(tab.path, table.concat(tab.lines, "\n"))
  if ok then
    tab.modified = false
    State.out = "Saved: " .. tab.path
    State.outCol = c("ok")
    -- Reflect the new file in the browser if we just saved into cwd.
    local parent = fs.path(tab.path) or ""
    parent = parent:gsub("/$", "")
    if parent == State.cwd or parent == "" and State.cwd == "/" then
      refresh()
    end
    return true
  else
    State.out = "Save failed: " .. tostring(err)
    State.outCol = c("err")
    return false
  end
end

-- ============================================================
-- View tab open
-- ============================================================

local function openViewTab(content, label, path)
  local lines = splitLines(content)
  return tabCreate("view", label or "view", {
    lines  = lines,
    scroll = 0,
    path   = path,
  })
end

-- ============================================================
-- Command-line execution
-- ============================================================
-- Strategy: shell-redirect to a tmp file, read it back, open as a
-- viewer tab. Keeps PaneUI's screen ownership intact (output is
-- captured rather than streamed to gpu). Programs that bypass the
-- redirect by writing directly to the GPU will briefly trash the
-- screen — repaint() at the end papers over it.
--
-- For commands that legitimately need stdin, the user can press F9
-- to drop to a real shell instead.

local CMD_OUT = "/tmp/paneui_cmdout.txt"

local function runCommand(cmdLine)
  if cmdLine == "" then return end

  -- A few common builtins handled in-process so they're instant
  -- and we don't shell out for trivia.
  local stripped = cmdLine:match("^%s*(.-)%s*$") or cmdLine
  local builtin, builtinArg = stripped:match("^(%S+)%s*(.*)$")
  if builtin == "cd" then
    local target = builtinArg ~= "" and builtinArg or "/home"
    target = shell.resolve(target)
    if fs.isDirectory(target) then
      State.cwd = target
      State.sel = 1; State.scroll = 0
      refresh()
      State.out = "cwd: " .. target
      State.outCol = c("ok")
    else
      State.out = "Not a directory: " .. target
      State.outCol = c("err")
    end
    return
  elseif builtin == "clear" then
    State.out = "(clear is a no-op in PaneUI)"
    State.outCol = c("dim")
    return
  elseif builtin == "exit" or builtin == "quit" then
    State.quitting = true
    return
  elseif builtin == "themes" then
    State.out = "Themes: " .. table.concat(themeNames(), ", ") ..
      "  (active: " .. THEME_NAME .. ")"
    State.outCol = c("dim")
    return
  elseif builtin == "theme" then
    -- Matches TOS's `theme set <name>`: switch the live palette to one of
    -- the synced TOS presets and remember it across runs.
    local name = (builtinArg or ""):match("^(%S*)")
    if not name or name == "" then
      State.out = "Active theme: " .. THEME_NAME .. "  ·  theme <name>  ·  'themes' to list"
      State.outCol = c("dim")
    elseif applyTheme(name) then
      saveThemeName(name)
      State.out = mono and ("Theme set to " .. name .. " (monochrome GPU — colors disabled)")
        or ("Theme: " .. name)
      State.outCol = c("ok")
      repaint()
    else
      State.out = "Unknown theme '" .. name .. "'  (try: themes)"
      State.outCol = c("err")
    end
    return
  end

  -- Real command.
  --
  -- Note on capture: OpenOS shell parses `>` for stdout redirect but
  -- does NOT recognize `2>&1`, so stderr is NOT captured here. Errors
  -- from the command print briefly to the terminal during execute;
  -- PaneUI's full repaint() afterwards papers over the corruption.
  -- For commands you specifically want stderr from, append `2>file`
  -- yourself if your OpenOS build supports it, or use F9 to drop to
  -- a real shell.
  --
  -- User-supplied redirects (`>`, `>>`, `<`, `|`) take precedence:
  -- appending our own `> /tmp/...` after a user redirect would either
  -- chain into `cmd > userfile > tmp` (parse error) or silently
  -- clobber whatever the user pointed at. Detect and skip our capture
  -- in that case — output flows wherever the user's redirect points,
  -- and PaneUI just shows a "ran (uncaptured)" status. The detector
  -- is character-class based, NOT quote-aware, so a literal `>` inside
  -- a quoted argument disables capture too. Acceptable trade-off:
  -- false negatives lose only the auto-capture convenience, never
  -- correctness.
  local userRedirect = cmdLine:find("[<>|]") ~= nil

  pcall(fs.remove, CMD_OUT)
  local fullCmd = userRedirect and cmdLine or (cmdLine .. " > " .. CMD_OUT)

  local pcOk, exOk, exErr = pcall(shell.execute, fullCmd)

  -- Read whatever made it to the tmp file even if execute errored.
  local content = ""
  if fs.exists(CMD_OUT) then
    content = readTextFile(CMD_OUT, 256 * 1024) or ""
    pcall(fs.remove, CMD_OUT)
  end

  if not pcOk then
    content = (content or "") .. "\n[PaneUI] shell.execute crashed: " .. tostring(exOk)
  elseif exOk == false then
    -- Command returned a failure code; surface the error string if any.
    content = (content or "") .. "\n[PaneUI] command failed: " .. tostring(exErr or "(no error message)")
  end

  if userRedirect then
    -- User did their own redirect, so we don't have captured output
    -- to show. Just acknowledge the run.
    State.out = "$ " .. cmdLine .. "  (output went to user redirect)"
    State.outCol = c("ok")
  elseif content == "" then
    State.out = "$ " .. cmdLine .. "  (no output)"
    State.outCol = c("ok")
  else
    local lbl = "$ " .. cmdLine
    if #lbl > 14 then lbl = lbl:sub(1, 13) .. "~" end
    openViewTab(content, lbl)
  end
end

-- ============================================================
-- Key handlers
-- ============================================================

local SCANCODE = {
  esc = 1, tab = 15, enter = 28, backspace = 14, delete = 211,
  up = 200, down = 208, left = 203, right = 205,
  pgup = 201, pgdn = 209, home = 199, ["end"] = 207,
  f1 = 59, f2 = 60, f3 = 61, f4 = 62, f5 = 63, f6 = 64,
  f7 = 65, f8 = 66, f9 = 67, f10 = 68,
}

-- True if the current ch is "Ctrl+letter". OpenOS gives us
-- Ctrl+A..Z as char codes 1..26, with `code` matching the
-- underlying physical key — so we can disambiguate Ctrl+Q
-- from a literal "q" by looking at the ch range.
local function isCtrl(ch) return ch and ch >= 1 and ch <= 26 end

-- Help tab is always a singleton. F1 from any context either
-- switches to the existing help tab or creates one.
local function openHelp()
  for i, t in ipairs(State.tabs) do
    if t.type == "help" then State.activeTab = i; return end
  end
  tabCreate("help", "Help")
end

local function handleBrowserKey(ch, code)
  local cl = State.cmdline

  -- Always-available global keys
  if code == SCANCODE.f10 or (isCtrl(ch) and ch == 17) then
    State.quitting = true; return
  elseif code == SCANCODE.f1 then
    openHelp(); return
  elseif code == SCANCODE.f2 then
    tabCycle(1); return
  elseif code == SCANCODE.f9 then
    dropToShell(); return
  end

  -- Cmdline editing & history.
  -- Empty cmdline + arrow keys move file-list selection (TOS-style).
  if code == SCANCODE.up and cl == "" then
    State.sel = math.max(1, State.sel - 1)
  elseif code == SCANCODE.down and cl == "" then
    State.sel = math.min(#State.files, State.sel + 1)
  elseif code == SCANCODE.up and cl ~= "" then
    if State.cmdHistIdx == 0 then State.cmdHistIdx = #State.cmdHist
    elseif State.cmdHistIdx > 1 then State.cmdHistIdx = State.cmdHistIdx - 1 end
    if State.cmdHistIdx > 0 then State.cmdline = State.cmdHist[State.cmdHistIdx] end
  elseif code == SCANCODE.down and cl ~= "" then
    if State.cmdHistIdx < #State.cmdHist then
      State.cmdHistIdx = State.cmdHistIdx + 1
      State.cmdline = State.cmdHist[State.cmdHistIdx]
    else
      State.cmdHistIdx = 0
      State.cmdline = ""
    end
  elseif code == SCANCODE.pgup then
    State.sel = math.max(1, State.sel - visibleRows())
  elseif code == SCANCODE.pgdn then
    State.sel = math.min(#State.files, State.sel + visibleRows())
  elseif code == SCANCODE.home then
    State.sel = 1
  elseif code == SCANCODE["end"] then
    State.sel = #State.files
  elseif code == SCANCODE.backspace then
    -- Edit cmdline if non-empty, else navigate up
    if cl ~= "" then
      State.cmdline = cl:sub(1, -2)
    else
      goUp()
    end
  elseif code == SCANCODE.enter then
    if cl ~= "" then
      local input = cl
      State.cmdline = ""
      State.cmdHistIdx = 0
      if #State.cmdHist == 0 or State.cmdHist[#State.cmdHist] ~= input then
        State.cmdHist[#State.cmdHist + 1] = input
      end
      runCommand(input)
    else
      local f = selectedEntry()
      if f then
        if f.isDir then
          navigateInto(f)
        else
          if isProbablyText(f.path) then
            local content, err = readTextFile(f.path)
            if content then
              openViewTab(content, f.name, f.path)
            else
              State.out = "Cannot read: " .. tostring(err)
              State.outCol = c("err")
            end
          else
            State.out = "Cannot view: looks like a binary file"
            State.outCol = c("err")
          end
        end
      end
    end
  elseif code == SCANCODE.f3 then
    local f = selectedEntry()
    if f and not f.isDir and isProbablyText(f.path) then
      local content = readTextFile(f.path)
      if content then openViewTab(content, f.name, f.path) end
    end
  elseif code == SCANCODE.f4 then
    local f = selectedEntry()
    if f and not f.isDir then
      openEditTab(f.path)
    else
      local name = promptInput("New file name:")
      if name and name ~= "" then
        openEditTab(fs.concat(State.cwd, name))
      end
    end
  elseif code == SCANCODE.f5 then copySelected()
  elseif code == SCANCODE.f6 then moveSelected()
  elseif code == SCANCODE.f7 then mkdirHere()
  elseif code == SCANCODE.f8 then deleteSelected()
  elseif ch and ch >= 32 and ch < 127 then
    State.cmdline = cl .. string.char(ch)
    State.cmdHistIdx = 0
  elseif code == SCANCODE.esc then
    State.cmdline = ""
    State.cmdHistIdx = 0
  end
end

local function handleViewerKey(ch, code, tab)
  local rows = visibleRows()
  local maxScroll = math.max(0, #(tab.lines or {}) - rows)

  if code == SCANCODE.f10 then
    State.quitting = true
  elseif isCtrl(ch) and ch == 17 then
    tabClose()
  elseif code == SCANCODE.f1 then
    openHelp()
  elseif code == SCANCODE.f2 then
    tabCycle(1)
  elseif code == SCANCODE.up then
    tab.scroll = math.max(0, (tab.scroll or 0) - 1)
  elseif code == SCANCODE.down then
    tab.scroll = math.min(maxScroll, (tab.scroll or 0) + 1)
  elseif code == SCANCODE.pgup then
    tab.scroll = math.max(0, (tab.scroll or 0) - rows)
  elseif code == SCANCODE.pgdn then
    tab.scroll = math.min(maxScroll, (tab.scroll or 0) + rows)
  elseif code == SCANCODE.home then
    tab.scroll = 0
  elseif code == SCANCODE["end"] then
    tab.scroll = maxScroll
  elseif code == SCANCODE.esc or ch == 113 or ch == 81 then
    -- Accept both lowercase q (113) and uppercase Q (81). Closing
    -- on lowercase only was an undocumented inconsistency.
    tabClose()
  end
end

-- Helper: prompt to save the buffer if modified, then run `after`.
-- Used by both Ctrl+Q (close-tab) and F10 (quit-program) so neither
-- one silently discards changes.
local function maybeSaveAndContinue(tab, after)
  if not tab.modified then after(); return end
  if confirmDialog("Save changes to '" .. (tab.label or "this file") .. "' before continuing?") then
    -- saveEditTab returns false if the user cancelled the Save-As prompt.
    -- In that case we abort the F10 / Ctrl+Q rather than discarding the
    -- buffer — consistent with "the user said save, then bailed".
    if saveEditTab(tab) then after() end
  else
    after()
  end
end

local function handleEditorKey(ch, code, tab)
  -- Global F-keys still work — but F10 now goes through the
  -- save-prompt path so a tap on F10 with unsaved work doesn't
  -- silently lose it (the previous F10 behaviour skipped the
  -- Ctrl+Q prompt).
  if code == SCANCODE.f10 then
    maybeSaveAndContinue(tab, function() State.quitting = true end)
    return
  end
  if code == SCANCODE.f1 then
    -- Dedupe: switch to the existing help tab if there is one.
    local existing
    for i, t in ipairs(State.tabs) do
      if t.type == "help" then existing = i; break end
    end
    if existing then State.activeTab = existing
    else tabCreate("help", "Help") end
    return
  end
  if code == SCANCODE.f2 then tabCycle(1); return end

  local lines = tab.lines

  if code == SCANCODE.up then
    tab.curRow = tab.curRow - 1; clampEditor(tab)
  elseif code == SCANCODE.down then
    tab.curRow = tab.curRow + 1; clampEditor(tab)
  elseif code == SCANCODE.left then
    if tab.curCol > 1 then tab.curCol = tab.curCol - 1
    elseif tab.curRow > 1 then
      tab.curRow = tab.curRow - 1
      tab.curCol = #lines[tab.curRow] + 1
    end
    clampEditor(tab)
  elseif code == SCANCODE.right then
    if tab.curCol <= #lines[tab.curRow] then tab.curCol = tab.curCol + 1
    elseif tab.curRow < #lines then
      tab.curRow = tab.curRow + 1
      tab.curCol = 1
    end
    clampEditor(tab)
  elseif code == SCANCODE.home then
    tab.curCol = 1
  elseif code == SCANCODE["end"] then
    tab.curCol = #lines[tab.curRow] + 1
  elseif code == SCANCODE.pgup then
    tab.curRow = math.max(1, tab.curRow - visibleRows())
    clampEditor(tab)
  elseif code == SCANCODE.pgdn then
    tab.curRow = math.min(#lines, tab.curRow + visibleRows())
    clampEditor(tab)
  elseif code == SCANCODE.backspace then
    if tab.curCol > 1 then
      local l = lines[tab.curRow]
      lines[tab.curRow] = l:sub(1, tab.curCol - 2) .. l:sub(tab.curCol)
      tab.curCol = tab.curCol - 1
      tab.modified = true
    elseif tab.curRow > 1 then
      pushUndo(tab)
      tab.curCol = #lines[tab.curRow - 1] + 1
      lines[tab.curRow - 1] = lines[tab.curRow - 1] .. lines[tab.curRow]
      table.remove(lines, tab.curRow)
      tab.curRow = tab.curRow - 1
      tab.modified = true
      clampEditor(tab)
    end
  elseif code == SCANCODE.delete then
    local l = lines[tab.curRow]
    if tab.curCol <= #l then
      lines[tab.curRow] = l:sub(1, tab.curCol - 1) .. l:sub(tab.curCol + 1)
      tab.modified = true
    elseif tab.curRow < #lines then
      pushUndo(tab)
      lines[tab.curRow] = l .. lines[tab.curRow + 1]
      table.remove(lines, tab.curRow + 1)
      tab.modified = true
    end
  elseif code == SCANCODE.enter then
    pushUndo(tab)
    local l = lines[tab.curRow]
    local before = l:sub(1, tab.curCol - 1)
    local after  = l:sub(tab.curCol)
    lines[tab.curRow] = before
    -- Auto-indent: copy leading whitespace; bump one level after
    -- common Lua block-openers.
    local indent = before:match("^(%s*)") or ""
    local trimmed = before:match("^%s*(.-)%s*$") or ""
    if trimmed:match("then$") or trimmed:match("do$")
       or trimmed:match("repeat$") or trimmed:match("else$")
       or trimmed:match("function%s*%(.*%)%s*$")
       or trimmed:match("{%s*$") then
      indent = indent .. "  "
    end
    table.insert(lines, tab.curRow + 1, indent .. after)
    tab.curRow = tab.curRow + 1
    tab.curCol = #indent + 1
    tab.modified = true
    clampEditor(tab)
  elseif code == SCANCODE.tab then
    local l = lines[tab.curRow]
    lines[tab.curRow] = l:sub(1, tab.curCol - 1) .. "  " .. l:sub(tab.curCol)
    tab.curCol = tab.curCol + 2
    tab.modified = true
  elseif isCtrl(ch) and ch == 19 then  -- Ctrl+S
    saveEditTab(tab)
  elseif isCtrl(ch) and ch == 26 then  -- Ctrl+Z
    if tab.undoStack and #tab.undoStack > 0 then
      local snap = table.remove(tab.undoStack)
      tab.lines  = snap.lines
      tab.curRow = snap.row
      tab.curCol = snap.col
      tab.modified = true
      clampEditor(tab)
      State.out = "Undo"
      State.outCol = c("dim")
    else
      State.out = "Nothing to undo"
      State.outCol = c("dim")
    end
  elseif isCtrl(ch) and ch == 17 then  -- Ctrl+Q
    if tab.modified then
      if confirmDialog("Save changes to '" .. (tab.label or "this file") .. "' before closing?") then
        if saveEditTab(tab) then tabClose() end
      else
        tabClose()
      end
    else
      tabClose()
    end
  elseif ch and ch >= 32 and ch < 127 then
    local l = lines[tab.curRow]
    lines[tab.curRow] = l:sub(1, tab.curCol - 1) .. string.char(ch) .. l:sub(tab.curCol)
    tab.curCol = tab.curCol + 1
    tab.modified = true
  end
end

local function handleHelpKey(ch, code)
  -- Any key dismisses help (but F10 still quits the program).
  if code == SCANCODE.f10 then State.quitting = true; return end
  if code == SCANCODE.f2 then tabCycle(1); return end
  if code == SCANCODE.f1 then return end  -- F1 on help is a no-op (already open)
  tabClose()
end

-- ============================================================
-- Main event loop
-- ============================================================

local function eventLoop()
  repaint()
  while not State.quitting do
    local ev, _, p2, p3 = event.pull(1)

    if ev and State.out ~= "" then
      State.out = ""
      State.outCol = nil
    end

    if ev == "key_down" then
      local ch, code = p2, p3
      local tab = activeTab()
      local t = tab and tab.type or "browser"
      if t == "browser" then handleBrowserKey(ch, code)
      elseif t == "view" or t == "output" then handleViewerKey(ch, code, tab)
      elseif t == "edit" then handleEditorKey(ch, code, tab)
      elseif t == "help" then handleHelpKey(ch, code) end
      repaint()

    elseif ev == "interrupted" then
      State.quitting = true

    elseif ev == "screen_resized" then
      recomputeLayout()
      repaint()

    else
      -- Timeout: tick the clock if a second elapsed.
      local sec = math.floor(computer.uptime())
      if sec ~= State.lastClockSec then
        State.lastClockSec = sec
        drawTitle()
        drawCmdRow()  -- cursor block looks odd without periodic refresh
      end
    end
  end
end

-- ============================================================
-- Main
-- ============================================================

local function main(args)
  -- Initial cwd: arg[1] if given and a directory, else /home, else /
  local startDir = args[1]
  if startDir then
    startDir = shell.resolve(startDir)
    if not fs.isDirectory(startDir) then
      io.stderr:write("Not a directory: " .. tostring(startDir) .. "\n")
      return 1
    end
  else
    if fs.isDirectory("/home") then startDir = "/home" else startDir = "/" end
  end

  saveTerm()
  pcall(term.setCursorBlink, false)

  State.cwd = startDir
  -- Tab #1 is the always-on browser; subsequent tabs are user-opened.
  tabCreate("browser", "Files")
  refresh()

  local ok, err = pcall(eventLoop)

  pcall(term.setCursorBlink, true)
  restoreTerm()

  if not ok then
    io.stderr:write("[PaneUI] crashed: " .. tostring(err) .. "\n")
    return 1
  end
  return 0
end

return main({...})
