-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Desktop (home screen tab)               ║
-- ║                                                      ║
-- ║  A tile grid of the things this machine can DO —     ║
-- ║  built-in apps (Files, Chat, Mail, Monitor, ...) and ║
-- ║  every command an installed package provides — so a  ║
-- ║  fresh operator lands on a menu of capabilities, not ║
-- ║  a bare prompt. Runs as a panels TAB (type           ║
-- ║  "desktop"), so activating a tile dispatches through ║
-- ║  the SAME command executor the prompt uses: tier     ║
-- ║  gates, output routing and screen-taking commands    ║
-- ║  all behave identically to typing the command.       ║
-- ║                                                      ║
-- ║  Tier degradation: T2+ draws bordered tiles; a T1    ║
-- ║  (50x16 mono) or very narrow screen gets a numbered  ║
-- ║  list — same model, launcher-style presentation.     ║
-- ║                                                      ║
-- ║  Keyboard-first: arrows/Enter, 1-9 quick-launch,     ║
-- ║  Ctrl+Q jumps to the Shell tab. Mouse (optional      ║
-- ║  driver): click a tile to open it, scroll to move.   ║
-- ╚══════════════════════════════════════════════════════╝

local ui = require("shell.panels.ui")
local tabsMod = require("shell.panels.tabs")

local M = {}

-- Show at most this many package-provided tiles; the footer says how
-- many more exist so the cap is never silent.
local MAX_PKG_APPS = 24

-- ============================================================
-- App model (pure given deps — unit-tested off-box)
-- ============================================================

-- Built-in tiles, in display order. `cmd` entries dispatch through the
-- shell executor and are gated by the command registry's tier + needs;
-- `kind` entries are handled by the desktop itself.
local BUILTINS = {
  { id = "files",    label = "Files",    glyph = "≡", kind = "tab",
    hint = "File browser and command prompt" },
  { id = "monitor",  label = "Monitor",  glyph = "▒", cmd = "monitor",
    hint = "Live processes, services, memory" },
  { id = "chat",     label = "Chat",     glyph = "»", cmd = "chat",
    hint = "Network chat" },
  { id = "mail",     label = "Mail",     glyph = "@", cmd = "mail",
    hint = "Mesh email inbox" },
  -- (v1.4.0 consolidation: the Launcher tile is gone — the Desktop IS
  -- the menu surface now. Its surviving unique feature, the keycard
  -- menu, is the tape-menu tile below, auto-hidden without a drive.)
  { id = "settings", label = "Settings", glyph = "§", kind = "settings",
    hint = "Theme, status bar, desktop, system" },
  { id = "tapemenu", label = "Tape Menu", glyph = "▓", cmd = "tape-menu",
    hint = "Personal command menu from your identity tape" },
  { id = "help",     label = "Help",     glyph = "?", cmd = "help",
    hint = "Command reference" },
  { id = "tutorial", label = "Tutorial", glyph = "¶", cmd = "tutorial",
    hint = "Replay the welcome walkthrough" },
  { id = "logout",   label = "Log Out",  glyph = "«", kind = "logout",
    hint = "End this session" },
}

--- Build the app list. deps = {
---   entry       = fn(name) -> { tier, help } | nil   (command registry)
---   needMet     = fn(token) -> bool                  (live availability)
---   needs       = { cmd = token, ... }
---   pkgCommands = { name = path, ... }               (installed pkg cmds)
---   userTier    = number
---   translate   = fn(key, default) -> string         (i18n.t; optional)
---   home        = bool   building for the MERGED Home surface
--- }
--- Returns (apps, droppedCount). Pure — no requires, no globals.
function M.buildApps(deps)
  deps = deps or {}
  local entry    = deps.entry or function() return nil end
  local needMet  = deps.needMet or function() return true end
  local needs    = deps.needs or {}
  local userTier = deps.userTier or 0
  local tr       = deps.translate or function(_, default) return default end

  local apps = {}
  local builtinCmd = {}
  for _, b in ipairs(BUILTINS) do
    local keep = true
    -- On Home the file browser is a VIEW, one F2 away and named in the
    -- legend two rows below the grid. A tile for it would spend a tile
    -- slot restating a key the operator can already see.
    if deps.home and b.kind == "tab" then keep = false end
    if keep and b.cmd then
      builtinCmd[b.cmd] = true
      local e = entry(b.cmd)
      if e and (e.tier or 0) > userTier then keep = false end
      if keep and not needMet(needs[b.cmd]) then keep = false end
    end
    if keep then
      -- Clone (never hand out the shared BUILTINS row) with translated
      -- label/hint; English defaults stay inline in BUILTINS.
      apps[#apps + 1] = {
        id = b.id, kind = b.kind, cmd = b.cmd, glyph = b.glyph,
        label = tr("desktop." .. b.id, b.label),
        hint  = tr("desktop." .. b.id .. ".hint", b.hint),
      }
    end
  end

  -- Personal tiles (v1.4.0: absorbed from the retired launcher) — flat
  -- {label, run} entries from ~/.launcher.cfg become tiles, so an
  -- operator's hand-built menu lives on the Desktop now. Validated and
  -- bounded by the caller (launcher.normalizeMenu); submenu entries are
  -- skipped (tiles are flat by design).
  for i, e in ipairs(deps.personal or {}) do
    if i > 12 then break end
    apps[#apps + 1] = {
      id = "my:" .. e.label, label = tostring(e.label):sub(1, 12), glyph = "◆",
      cmd = e.run, personal = true,
      hint = tr("desktop.my.hint", "From your ~/.launcher.cfg menu"),
    }
  end

  -- Package-provided commands become tiles too — that's the point of a
  -- desktop: an installed program should be visible, not memorized.
  local names = {}
  for name in pairs(deps.pkgCommands or {}) do
    if type(name) == "string" and not builtinCmd[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local dropped = 0
  for i, name in ipairs(names) do
    if i <= MAX_PKG_APPS then
      apps[#apps + 1] = {
        id = "pkg:" .. name, label = name:sub(1, 12), glyph = "•",
        cmd = name, pkg = true,
        hint = tr("desktop.pkg.hint", "Installed package command"),
      }
    else
      dropped = dropped + 1
    end
  end
  return apps, dropped
end

--- Resolve what activating `apps[idx]` should do. Pure.
--- Returns { type = "tab"|"settings"|"logout"|"cmd"|"none", cmd = ... }.
function M.resolveApp(apps, idx)
  local app = apps and apps[idx]
  if not app then return { type = "none" } end
  if app.kind == "tab"      then return { type = "tab" } end
  if app.kind == "settings" then return { type = "settings" } end
  if app.kind == "logout"   then return { type = "logout" } end
  if app.cmd then return { type = "cmd", cmd = app.cmd } end
  return { type = "none" }
end

-- ============================================================
-- Live model refresh
-- ============================================================

-- Lazy width-aware fit: real unicode math on-box, byte fallback off-box.
local function ufit(s, cols)
  local ok, u = pcall(require, "kernel.ustr")
  if ok and u and u.fit then return u.fit(s, cols) end
  return tostring(s or ""):sub(1, cols)
end

local function liveDeps(S)
  local d = { userTier = S.userTier or 0 }
  local okC, commandsMod = pcall(require, "shell.panels.commands")
  if okC and commandsMod then
    d.entry   = commandsMod.entry
    d.needMet = commandsMod.needMet
    d.needs   = commandsMod.NEEDS
  end
  local okI, i18nMod = pcall(require, "kernel.i18n")
  if okI and i18nMod and i18nMod.t then d.translate = i18nMod.t end
  -- Personal menu entries (~/.launcher.cfg): flat run-items become
  -- tiles. normalizeMenu bounds/validates every field, so a malformed
  -- or hostile file yields tiles or nothing — never code.
  d.personal = {}
  pcall(function()
    local home = (S.who == "root") and "/root" or ("/home/" .. (S.who or ""))
    local cfgPath = home .. "/.launcher.cfg"
    if not (S.F and S.F.exists and S.F.exists(cfgPath)) then return end
    local raw = S.F.readFile and S.F.readFile(cfgPath)
    if not raw or #raw == 0 or #raw > 8192 then return end
    local okSer, ser = pcall(require, "kernel.serialize")
    local okL, L = pcall(require, "shell.launcher")
    if not (okSer and ser and ser.decode and okL and L and L.normalizeMenu) then return end
    local okD, parsed = pcall(ser.decode, raw, { maxBytes = 8192 })
    if not okD then return end
    local menu = L.normalizeMenu(parsed)
    for _, item in ipairs(menu.items or {}) do
      if item.run then d.personal[#d.personal + 1] = { label = item.label, run = item.run } end
    end
  end)
  d.pkgCommands = {}
  local okP, pkgMod = pcall(require, "kernel.pkg")
  if okP and pkgMod and pkgMod.commands then
    local okL, list = pcall(pkgMod.commands)
    if okL and type(list) == "table" then d.pkgCommands = list end
  end
  return d
end

--- opts.home = true builds the merged Home tile set (no Files tile).
function M.refresh(S, tab, opts)
  local deps = liveDeps(S)
  deps.home = opts and opts.home or false
  local apps, dropped = M.buildApps(deps)
  tab.apps = apps
  tab.dropped = dropped
  if not tab.sel or tab.sel > #apps then tab.sel = 1 end
end

--- Find-or-create the Desktop tab. opts.background = true creates it
--- without focusing it (used at startup when the landing is "shell").
---
--- On the MERGED surface there is no Desktop tab to find: `desktop` and
--- System → Desktop mean "show me the tiles", which is a view flip. The
--- old entry points keep working rather than being removed — an operator
--- who types `desktop` should land on tiles, not read an error about a
--- surface that was reorganised out from under them.
function M.open(S, opts)
  opts = opts or {}
  local okH, home = pcall(require, "shell.panels.home")
  if okH and home and home.enabled(S) then
    local tab = home.tab(S)
    if tab then
      if not opts.background then
        for i, t in ipairs(S.tabs) do
          if t == tab then S.activeTab = i; break end
        end
        home.setView(S, "tiles", tab)
      end
      home.refresh(S, tab)
      return tab
    end
  end
  local idx = tabsMod.find(S, "desktop")
  local tab
  if idx then
    tab = S.tabs[idx]
    if not opts.background then S.activeTab = idx end
  else
    local prevActive = S.activeTab
    tab = tabsMod.create(S, "desktop", "Desktop", { sel = 1 })
    if opts.background then S.activeTab = prevActive end
  end
  M.refresh(S, tab)   -- re-scan on every open so new packages show up
  return tab
end

-- ============================================================
-- Layout helpers
-- ============================================================

local function shellTabIndex(S)
  for i, t in ipairs(S.tabs) do
    if t.type == "shell" then return i end
  end
  return 1
end

-- List mode is the T1 / narrow-screen degradation.
local function listMode(S)
  return (S.tier or 1) < 2 or S.W < 46 or S.H < 14
end

local function gridFor(S)
  -- Rows: 1 tab bar, 2 header, 3 blank, grid, H-1 hint, H footer.
  local region = { x = 2, y = 4, w = S.W - 2, h = math.max(3, S.H - 5 - 2) }
  local tileW = (S.W >= 120) and 18 or 14
  local tileH = (S.H >= 40) and 5 or 4
  return ui.tileGrid(region, { tileW = tileW, tileH = tileH })
end

local function perPage(S, tab)
  if listMode(S) then return math.max(1, S.H - 6) end
  return gridFor(S).perPage
end

-- ============================================================
-- Drawing
-- ============================================================

function M.drawHeader(S, tab)
  local D, T, W = S.D, S.T, S.W
  local host = (S.SC and S.SC.get and S.SC.get("hostname")) or "tos"
  local clock = "--:--"
  local okT, t = pcall(os.date, "*t")
  if okT and t then clock = string.format("%02d:%02d", t.hour, t.min) end
  -- Grammar rule 2: the header is a rail. drawRail's column math is
  -- ustr-based, so the multi-byte ⌂ can't skew the clock position.
  ui.drawRail(D, T, 2, W, {
    { label = "⌂ " .. (S.who or "?") .. "@" .. host },
    { text = clock, at = W - 8 },
  }, { labelFg = T.title or T.fg })
end

local function drawFooter(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local apps = tab.apps or {}
  local pp = perPage(S, tab)
  local pages = math.max(1, math.ceil(#apps / pp))
  local page = math.floor(((tab.sel or 1) - 1) / pp) + 1

  -- Hint row: the selected app's one-liner (the tile-grid equivalent of
  -- the shell's idle F-key legend). Width-fitted, not byte-sliced —
  -- translated hints are multi-byte UTF-8.
  local okI, i18nMod = pcall(require, "kernel.i18n")
  local t = (okI and i18nMod and i18nMod.t)
    or function(_, default, ...) return select("#", ...) > 0 and string.format(default, ...) or default end
  local app = apps[tab.sel]
  local hint = app and ((app.label or "") .. " — " .. (app.hint or "")) or ""
  if tab.dropped and tab.dropped > 0 then
    hint = hint .. t("desktop.more", "   (+%d more via the prompt)", tab.dropped)
  end
  local parts = (hint ~= "") and { { label = ufit(hint, W - 8) } } or {}
  ui.drawRail(D, T, H - 1, W, parts)

  local keys = t("desktop.keys", "Enter Open · Arrows Move · 1-9 Quick · F2 Tabs · ^Q Shell")
  local right = (pages > 1) and (page .. "/" .. pages) or nil
  ui.drawRampBar(D, T, H, W, keys, right, T.statusbar_fg or T.bar_fg, T.statusbar_bg or T.bar_bg)
end

function M.draw(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  if not tab.apps then M.refresh(S, tab) end
  local apps = tab.apps or {}

  D.fill(1, 2, W, H - 1, " ", T.fg, T.bg)
  M.drawHeader(S, tab)

  local pp = perPage(S, tab)
  local sel = tab.sel or 1
  local pageStart = math.floor((sel - 1) / pp) * pp

  if listMode(S) then
    for slot = 1, pp do
      local i = pageStart + slot
      local app = apps[i]
      if not app then break end
      local y = 3 + slot
      local selected = (i == sel)
      local fg = selected and (T.sel_fg or T.bg) or T.fg
      local bg = selected and (T.sel_bg or T.highlight) or T.bg
      D.fill(1, y, W, 1, " ", fg, bg)
      local num = (slot <= 9) and ("[" .. slot .. "] ") or "    "
      D.set(2, y, num, selected and fg or T.dim, bg)
      D.set(6, y, app.glyph or "•", selected and fg or (T.title or T.fg), bg)
      D.set(8, y, ufit(tostring(app.label), W - 9), fg, bg)
    end
  else
    local g = gridFor(S)
    for slot = 1, g.perPage do
      local i = pageStart + slot
      local app = apps[i]
      if not app then break end
      local r = ui.tileRect(g, slot)
      if r then
        ui.drawTile(D, T, r, {
          glyph = app.glyph, label = app.label,
          selected = (i == sel), dim = app.pkg,
        })
      end
    end
  end

  drawFooter(S, tab)
end

-- ============================================================
-- Activation
-- ============================================================

--- Activate app `idx`. deps = { exec = fn(cmdline) }.
--- Returns (drawLevel, result) — result "exit" propagates a logout.
local function activate(S, tab, idx, deps)
  local act = M.resolveApp(tab.apps, idx)
  if act.type == "tab" then
    S.activeTab = shellTabIndex(S)
    return 3
  elseif act.type == "settings" then
    local ok, settingsMod = pcall(require, "shell.panels.settingsapp")
    if ok and settingsMod then settingsMod.open(S)
    else S.lastOut = { "Settings unavailable: " .. tostring(settingsMod), S.T.error } end
    return 3
  elseif act.type == "logout" then
    -- Lazily, like the settings app above: this file is loaded on demand
    -- and a hard require would drag kernel.computer in behind it, which
    -- is the wrong direction on a box already short of memory.
    local okH, helpers = pcall(require, "shell.panels.helpers")
    if okH and helpers and helpers.logout then
      helpers.logout(S)
    else
      -- Same rule inline: never carry an elevation across a logout.
      if S._sudo and S.sudoDrop then pcall(S.sudoDrop) end
      S.E.push("tos_logout", S.displayIdx)
    end
    return 3, "exit"
  elseif act.type == "cmd" then
    -- Land on the Shell tab FIRST so the command's output routing
    -- (inline lines, view tabs, screen-taking TUIs) behaves exactly as
    -- if the operator had typed it at the prompt.
    S.activeTab = shellTabIndex(S)
    if deps and deps.exec then deps.exec(act.cmd) end
    return 3
  end
  return 0
end

-- ============================================================
-- Input handling
-- ============================================================

--- Keyboard. Returns (drawLevel[, result]).
function M.handleKey(S, tab, ch, co, deps)
  local apps = tab.apps or {}
  if #apps == 0 then M.refresh(S, tab); apps = tab.apps end
  local sel = tab.sel or 1
  local pp = perPage(S, tab)
  local cols = listMode(S) and 1 or gridFor(S).cols

  if co == 28 or ch == 32 then                        -- Enter / Space
    return activate(S, tab, sel, deps)
  elseif ch == 17 then                                -- Ctrl+Q → Shell tab
    S.activeTab = shellTabIndex(S)
    return 3
  elseif ch == 114 or ch == 82 then                   -- r / R: rescan apps
    M.refresh(S, tab)
    return 3
  elseif co == 203 then                               -- Left
    if sel > 1 then tab.sel = sel - 1; return 3 end
  elseif co == 205 then                               -- Right
    if sel < #apps then tab.sel = sel + 1; return 3 end
  elseif co == 200 then                               -- Up
    if sel - cols >= 1 then tab.sel = sel - cols; return 3 end
  elseif co == 208 then                               -- Down
    if sel + cols <= #apps then tab.sel = sel + cols; return 3 end
  elseif co == 201 then                               -- PgUp
    tab.sel = math.max(1, sel - pp); return 3
  elseif co == 209 then                               -- PgDn
    tab.sel = math.min(#apps, sel + pp); return 3
  elseif co == 199 then tab.sel = 1; return 3         -- Home
  elseif co == 207 then tab.sel = #apps; return 3     -- End
  elseif ch and ch >= 49 and ch <= 57 then            -- 1..9: page slot
    local pageStart = math.floor((sel - 1) / pp) * pp
    local i = pageStart + (ch - 48)
    if apps[i] then
      tab.sel = i
      return activate(S, tab, i, deps)
    end
  end
  return 0
end

--- Mouse click (optional driver). Returns (drawLevel[, result]).
function M.handleClick(S, tab, ev, deps)
  local apps = tab.apps or {}
  local pp = perPage(S, tab)
  local pageStart = math.floor(((tab.sel or 1) - 1) / pp) * pp
  local hitIdx = nil

  if listMode(S) then
    local slot = ev.y - 3
    if slot >= 1 and slot <= pp then hitIdx = pageStart + slot end
  else
    local slot = ui.tileHit(gridFor(S), ev.x, ev.y)
    if slot then hitIdx = pageStart + slot end
  end
  if not hitIdx or not apps[hitIdx] then return 0 end

  tab.sel = hitIdx
  if ev.button == 1 then return 3 end   -- right-click: select only
  return activate(S, tab, hitIdx, deps) -- left-click: open
end

--- Mouse scroll: move the selection like Up/Down. Returns drawLevel.
function M.handleScroll(S, tab, ev)
  local apps = tab.apps or {}
  local delta = (ev.dir or 0) > 0 and -1 or 1
  local newSel = math.max(1, math.min(#apps, (tab.sel or 1) + delta))
  if newSel == tab.sel then return 0 end
  tab.sel = newSel
  return 3
end

return M
