-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Home (the merged surface)               ║
-- ║                                                      ║
-- ║  ONE TAB, TWO VIEWS. The Desktop used to be a tab    ║
-- ║  beside the Shell, and F2 flipped between them —     ║
-- ║  which made "where is my prompt?" a question with    ║
-- ║  two answers. Home merges them: tiles and the file   ║
-- ║  list are two views of the SAME tab, the prompt is   ║
-- ║  resident in both at the row it has always been on,  ║
-- ║  and F2 flips the view rather than the tab.          ║
-- ║                                                      ║
-- ║  What that buys, and why it is worth a merge:        ║
-- ║    · one command surface, so one scrollback to       ║
-- ║      budget and one swap tenant (see tabs.lua)       ║
-- ║    · the bottom four rows never move, so a command's ║
-- ║      output lands where it always did and the tiles  ║
-- ║      don't jump under your hand                      ║
-- ║    · the chip zone carries only REAL tabs (editors,  ║
-- ║      Monitor, view buffers), so it stops competing   ║
-- ║      with view switching for the 80th column         ║
-- ║                                                      ║
-- ║  This module owns the TILES view only. The files     ║
-- ║  view is the file browser TOS has always drawn, and  ║
-- ║  it is untouched — that is the point.                ║
-- ║                                                      ║
-- ║  The app MODEL is desktop.lua's (buildApps /         ║
-- ║  resolveApp), deliberately not a second copy: tiles, ║
-- ║  the T1 numbered list and the keycard fallback all   ║
-- ║  consume one menu model, which is the surface        ║
-- ║  contract this rework is written against.            ║
-- ╚══════════════════════════════════════════════════════╝

local ui = require("shell.panels.ui")

local M = {}

-- Lazy: desktop.lua carries the app model and is ~9KB of source. An
-- operator who lands on the files view and never presses F2 should not
-- pay to parse it (the v1.4.0 emulator round OOM'd a ~230KB-free box
-- doing exactly that kind of eager load at shell start).
local _desktop = nil
local function desktopMod()
  if _desktop == nil then
    local ok, mod = pcall(require, "shell.panels.desktop")
    _desktop = (ok and mod) or false
  end
  return _desktop or nil
end

--- Test hook: drop the cached probe so a test can simulate the module
--- being unavailable (and then available again).
function M._forgetDesktop() _desktop = nil end

local function ustrLib()
  local ok, u = pcall(require, "kernel.ustr")
  return (ok and u) or nil
end
local function ufit(s, cols)
  local u = ustrLib()
  if u and u.fit then return u.fit(s, cols) end
  return tostring(s or ""):sub(1, cols)
end
local function uwidth(s)
  local u = ustrLib()
  if u and u.width then return u.width(s) end
  return #tostring(s or "")
end

--- Record where a "press this to flip the view" legend landed, so a
--- mouse can click the words instead of learning the key. Keyed by row
--- because two rows can carry one (the files rail and the legend), and
--- the writer of a row always owns that row's entry.
function M.markToggle(S, row, s, e)
  S._viewToggleSpans = S._viewToggleSpans or {}
  S._viewToggleSpans[row] = (s and e) and { s = s, e = e } or nil
end

--- Did this click land on a view-toggle legend?
function M.hitToggle(S, x, y)
  local sp = S._viewToggleSpans and S._viewToggleSpans[y]
  return sp ~= nil and x >= sp.s and x <= sp.e
end

local function tr(key, default, ...)
  local ok, i18n = pcall(require, "kernel.i18n")
  if ok and i18n and i18n.t then return i18n.t(key, default, ...) end
  if select("#", ...) > 0 then return string.format(default, ...) end
  return default
end

-- ============================================================
-- View state
-- ============================================================
-- The view lives on the TAB, not on S: it is per-tab state exactly like
-- tab.sel, so a future second Home (a second seat, a restored session)
-- carries its own and nothing has to be reset globally.

--- Is this session running the merged surface at all?
function M.enabled(S)
  return S and not S.uiSplit
end

local function homeTab(S)
  local tab = S.tabs and S.tabs[S.activeTab]
  if tab and (tab.type == nil or tab.type == "shell") then return tab end
  for _, t in ipairs(S.tabs or {}) do
    if t.type == "shell" then return t end
  end
  return nil
end
M.tab = homeTab

--- "tiles" | "files". Always "files" in split mode — there is a whole
--- separate Desktop tab there, and a tiles view inside the Shell tab
--- would be the same surface drawn twice.
function M.view(S, tab)
  if not M.enabled(S) then return "files" end
  tab = tab or homeTab(S)
  return (tab and tab.view == "tiles") and "tiles" or "files"
end

function M.isTiles(S, tab) return M.view(S, tab) == "tiles" end

--- Set the view. Returns true if it actually changed.
---
--- Flipping to tiles can FAIL, and has to say so rather than land the
--- operator on an empty grid. desktop.lua is loaded lazily (that
--- laziness is what keeps a ~230KB-free box from OOMing at shell start),
--- so the box that most needs the files view is the box where the tile
--- model may not fit. Refuse and stay put — a working file list beats a
--- surface that came up blank with no explanation.
function M.setView(S, view, tab)
  if not M.enabled(S) then return false end
  tab = tab or homeTab(S)
  if not tab then return false end
  local want = (view == "tiles") and "tiles" or "files"
  if tab.view == want then return false end
  if want == "tiles" and not desktopMod() then
    S.lastOut = { "Tiles unavailable: not enough memory to load the app list",
                  (S.T or {}).error }
    return false
  end
  tab.view = want
  if want == "tiles" then M.refresh(S, tab) end
  return true
end

--- The `view` action (F2 by default): flip the surface.
function M.toggle(S, tab)
  tab = tab or homeTab(S)
  return M.setView(S, M.isTiles(S, tab) and "files" or "tiles", tab)
end

--- The label an F-key legend should print for the flip, read from the
--- live keybind so a rebound `view` action can never leave a legend
--- advertising F2. Falls back to "F2" when shell.keys is unavailable.
function M.viewKeyLabel(S)
  local ok, keys = pcall(require, "shell.keys")
  if ok and keys and keys.label then
    local lbl = keys.label("view", S and S.who or nil)
    if lbl and lbl ~= "" then return (lbl:match("^[^/]+") or lbl):gsub("%s+$", "") end
  end
  return "F2"
end

--- What an operator should press to move between TABS. F2 used to do
--- it; the `view` action has F2 now, so on the merged surface it is Tab
--- (on an empty command line). Split mode keeps F2. Every help text and
--- footer asks this rather than spelling a key, so the two shapes can't
--- end up documented as one.
function M.cycleKeyLabel(S)
  return M.enabled(S) and "Tab" or "F2"
end

--- Does this keypress mean "flip the view"?
function M.isViewKey(S, ch, co)
  local ok, keys = pcall(require, "shell.keys")
  if ok and keys and keys.is then
    return keys.is("view", ch, co, S and S.who or nil)
  end
  return co == (S and S.KEYS and S.KEYS.homeView or 60)
end

-- ============================================================
-- Model
-- ============================================================

--- Rebuild the tile list. Home drops the "Files" builtin: F2 is the way
--- to the file list now, and a tile that duplicates a key which is drawn
--- in the legend two rows below it is just a tile you can't spend on
--- something else.
function M.refresh(S, tab)
  tab = tab or homeTab(S)
  if not tab then return end
  local d = desktopMod()
  if not d then tab.apps = tab.apps or {}; return end
  d.refresh(S, tab, { home = M.enabled(S) })
end

function M.apps(S, tab)
  tab = tab or homeTab(S)
  if not tab then return {} end
  if not tab.apps then M.refresh(S, tab) end
  return tab.apps or {}
end

-- ============================================================
-- Geometry
-- ============================================================
-- The tile region is whatever is left between the band rail and the
-- summary rail. Nothing here is a constant: recomputeLayout owns the
-- rows, so a live `screen res` change re-fits the grid for free.

--- T1 / narrow degradation: a numbered list where the tiles would be.
function M.listMode(S)
  return (S.tier or 1) < 2 or S.W < 46 or S.TILE_H < 4
end

function M.grid(S)
  local region = { x = 2, y = S.TILE_TOP, w = S.W - 2, h = math.max(3, S.TILE_H) }
  local tileW = (S.W >= 120) and 18 or 14
  local tileH = (S.H >= 40) and 5 or 4
  return ui.tileGrid(region, { tileW = tileW, tileH = tileH })
end

function M.perPage(S)
  if M.listMode(S) then return math.max(1, S.TILE_H) end
  return M.grid(S).perPage
end

--- (page, pages, pageStart) for the current selection. Paging is derived
--- from the selection rather than stored beside it, so the two can never
--- disagree — the bug you get from keeping both.
function M.pageOf(S, tab)
  local apps = M.apps(S, tab)
  local pp = M.perPage(S)
  local sel = (tab and tab.sel) or 1
  local pages = math.max(1, math.ceil(#apps / pp))
  local page = math.min(pages, math.floor((sel - 1) / pp) + 1)
  return page, pages, (page - 1) * pp, pp
end

-- ============================================================
-- Drawing
-- ============================================================

--- Row 2 in the tiles view: the same ⌂ user@host rail the Desktop tab
--- draws, plus the cwd — the prompt is right there on row H-1, so the
--- rail says which directory it will run in.
function M.drawHeader(S, tab)
  local D, T, W = S.D, S.T, S.W
  local host = (S.SC and S.SC.get and S.SC.get("hostname")) or "tos"
  local clock = "--:--"
  local okT, t = pcall(os.date, "*t")
  if okT and t then clock = string.format("%02d:%02d", t.hour, t.min) end
  -- One tabbed segment (who you are), then the cwd as plain rail text —
  -- ┤ x ├┤ y ├ reads as two separate claims, and these are one: this is
  -- the directory that prompt two rows down will run in.
  ui.drawRail(D, T, S.RAIL_ROW, W, {
    { label = "\226\140\130 " .. (S.who or "?") .. "@" .. host },
    { text = S.cwd or "/" },
    { text = clock, at = W - 8 },
  }, { labelFg = T.title or T.fg })
end

--- Row 3: the band rail. ui.tileGrid has always computed perPage; the
--- band is what makes it VISIBLE — before this, a tile past the first
--- page existed but nothing on screen said so.
function M.drawBand(S, tab)
  local D, T, W = S.D, S.T, S.W
  local apps = M.apps(S, tab)
  local page, pages, pageStart, pp = M.pageOf(S, tab)
  local shown = math.max(0, math.min(pp, #apps - pageStart))

  local parts = {}
  S._homeBand = nil
  if pages > 1 then
    parts[#parts + 1] = { label = "\226\128\185 page " .. page .. "/" .. pages .. " \226\128\186" }
  end
  local facts = tr("home.band", "%d tiles \194\183 %d shown", #apps, shown)
  if pages > 1 then
    facts = facts .. " \194\183 " .. ((page < pages)
      and tr("home.band.next", "PgDn next page")
      or  tr("home.band.back", "PgUp back"))
  end
  parts[#parts + 1] = { text = facts }

  local spans = ui.drawRail(D, T, S.BAND_ROW, W, parts, { labelFg = T.title or T.fg })
  -- Hit spans for the ‹ › markers: single cells at each end of the page
  -- label, so a mouse can page without learning PgUp/PgDn.
  if pages > 1 and spans[1] then
    S._homeBand = { row = S.BAND_ROW, prev = spans[1].s,
                    next = spans[1].e, pages = pages }
  end
end

--- The tile field (or the numbered list on T1). Never touches rows the
--- shell owns — the summary rail down is the shell's, in both views.
function M.drawTiles(S, tab)
  local D, T, W = S.D, S.T, S.W
  local apps = M.apps(S, tab)
  local _, _, pageStart, pp = M.pageOf(S, tab)
  local sel = tab.sel or 1

  D.fill(1, S.TILE_TOP, W, math.max(0, S.TILE_H), " ", T.fg, T.bg)

  if M.listMode(S) then
    for slot = 1, pp do
      local i = pageStart + slot
      local app = apps[i]
      if not app then break end
      local y = S.TILE_TOP + slot - 1
      local selected = (i == sel)
      local fg = selected and (T.sel_fg or T.bg) or T.fg
      local bg = selected and (T.sel_bg or T.highlight) or T.bg
      D.fill(1, y, W, 1, " ", fg, bg)
      local num = (slot <= 9) and ("[" .. slot .. "] ") or "    "
      D.set(2, y, num, selected and fg or (T.dim or T.fg), bg)
      D.set(6, y, app.glyph or "\194\183", selected and fg or (T.title or T.fg), bg)
      D.set(8, y, ufit(tostring(app.label), W - 9), fg, bg)
    end
    return
  end

  local g = M.grid(S)
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

--- The tiles view's summary-rail text (the shell draws the rail itself,
--- so both views keep one implementation of that row).
function M.summaryText(S, tab)
  local apps = M.apps(S, tab)
  local _, _, pageStart, pp = M.pageOf(S, tab)
  local shown = math.max(0, math.min(pp, #apps - pageStart))
  local txt = tr("home.sum", "%d tiles \194\183 %d shown", #apps, shown)
  if S.browser and S.browser.freeStr then
    txt = txt .. " \194\183 " .. S.browser.freeStr .. " free"
  end
  return txt
end

--- The tiles view's legend for the output row. Leads with what Enter
--- will do to the thing under the cursor — a tile whose label is a bare
--- package name is not self-explaining — then the keys, which drop from
--- the right on a narrow screen rather than wrapping.
---
--- Returns (text, spanStart, spanEnd) and marks NOTHING itself: the row
--- is shared with command output, so whoever actually draws it has to be
--- the one that records the click target, after the draw rather than
--- before it.
function M.hintText(S, tab)
  local apps = M.apps(S, tab)
  local app = apps[tab.sel or 1]
  local vk = M.viewKeyLabel(S)
  local page, pages = M.pageOf(S, tab)

  local lead
  if app and app.hint and app.hint ~= "" then
    lead = (app.label or "") .. " \226\128\148 " .. app.hint
  else
    lead = tr("home.keys", "Enter Open \194\183 Arrows Move \194\183 Alt+1-9 Quick")
  end

  local flip = vk .. " " .. tr("home.key.files", "Files")
  local keys = { flip }
  if pages > 1 then
    keys[#keys + 1] = ((page < pages) and "PgDn" or "PgUp") .. " " .. tr("home.key.page", "Page")
  end
  keys[#keys + 1] = "F10 " .. tr("home.key.quit", "Quit")

  -- Leading space, like the F-key legend it replaces: the output row is
  -- text on the background, not a bar, and butting it against column 1
  -- makes it read as chrome.
  local s = " " .. lead
  local spanS, spanE = nil, nil
  for _, k in ipairs(keys) do
    local cand = s .. " \194\183 " .. k
    -- COLUMNS, not bytes. The separator is a two-byte middot and the
    -- lead holds an em dash, so a byte test drops keys that would have
    -- fitted — which on a 50-column T1 meant the legend lost every key
    -- it had to say.
    if uwidth(cand) > S.W - 2 then break end
    -- The flip legend is a click target, not just prose (the design's
    -- "click the screen's F2 legend").
    if k == flip then
      spanS = uwidth(s) + 4
      spanE = spanS + uwidth(k) - 1
    end
    s = cand
  end
  if tab.dropped and tab.dropped > 0 then
    local cand = s .. tr("home.more", "   (+%d more via the prompt)", tab.dropped)
    if uwidth(cand) <= S.W - 2 then s = cand end
  end
  return ufit(s, S.W - 1), spanS, spanE
end

-- ============================================================
-- Activation
-- ============================================================

--- Activate tile `idx`. deps = { exec = fn(cmdline) }.
--- Returns (drawLevel[, result]); result "exit" propagates a logout.
--- NOTE the difference from the split Desktop: there is no "land on the
--- Shell tab first" step, because there is no other tab to land on. A
--- command's output routes to the same output region that is already on
--- screen, which is the whole reason the merge is worth doing.
function M.activate(S, tab, idx, deps)
  local d = desktopMod()
  if not d then return 0 end
  local act = d.resolveApp(tab.apps, idx)
  if act.type == "tab" then
    -- The Files builtin (split mode only): flip the view rather than
    -- hunting for a Shell tab.
    M.setView(S, "files", tab)
    return 3
  elseif act.type == "settings" then
    local ok, settingsMod = pcall(require, "shell.panels.settingsapp")
    if ok and settingsMod then settingsMod.open(S)
    else S.lastOut = { "Settings unavailable: " .. tostring(settingsMod), S.T.error } end
    return 3
  elseif act.type == "logout" then
    S.E.push("tos_logout", S.displayIdx)
    return 3, "exit"
  elseif act.type == "cmd" then
    if deps and deps.exec then deps.exec(act.cmd) end
    return 3
  end
  return 0
end

-- ============================================================
-- Input
-- ============================================================

-- Alt+digit, as OC delivers it. A bare digit arrives with its character
-- (49..57) AND its scancode (2..10); hold a modifier and the character
-- is suppressed while the scancode still arrives. That is the whole
-- discriminator, and it has to exist because on Home the bare digits
-- belong to the PROMPT — every printable key does. Ctrl+digit lands here
-- too, which is fine: both mean "the digit was a command, not text".
local DIGIT_CODE_BASE = 1   -- scancode 2 == "1" … scancode 10 == "9"
local function altDigit(ch, co)
  if type(co) ~= "number" or co < 2 or co > 10 then return nil end
  if ch ~= nil and ch ~= 0 then return nil end
  return co - DIGIT_CODE_BASE
end
M._altDigit = altDigit

--- Keyboard for the TILES view. Returns (drawLevel[, result]), or nil
--- when the key isn't ours — the caller then hands it to the prompt,
--- which is where anything printable belongs.
function M.handleKey(S, tab, ch, co, deps)
  local apps = M.apps(S, tab)
  local sel = tab.sel or 1
  local _, _, _, pp = M.pageOf(S, tab)
  local cols = M.listMode(S) and 1 or M.grid(S).cols

  -- Enter activates the SELECTION only when the prompt is empty; with a
  -- command on the line Enter runs it. Same rule the file browser has
  -- always used, so the merge adds no new one.
  if co == 28 and (S.cmdline == "" or S.cmdline == nil) then
    return M.activate(S, tab, sel, deps)
  end

  local n = altDigit(ch, co)
  if n then
    local _, _, pageStart = M.pageOf(S, tab)
    local i = pageStart + n
    if apps[i] then
      tab.sel = i
      return M.activate(S, tab, i, deps)
    end
    return 0
  end

  if co == 203 then                                   -- Left
    if sel > 1 then tab.sel = sel - 1; return 3 end
    return 0
  elseif co == 205 then                               -- Right
    if sel < #apps then tab.sel = sel + 1; return 3 end
    return 0
  elseif co == 200 then                               -- Up
    if sel - cols >= 1 then tab.sel = sel - cols; return 3 end
    return 0
  elseif co == 208 then                               -- Down
    if sel + cols <= #apps then tab.sel = sel + cols; return 3 end
    return 0
  elseif co == 201 then                               -- PgUp
    tab.sel = math.max(1, sel - pp); return 3
  elseif co == 209 then                               -- PgDn
    tab.sel = math.min(math.max(1, #apps), sel + pp); return 3
  elseif co == 199 and (S.cmdline == "" or S.cmdline == nil) then
    tab.sel = 1; return 3                             -- Home
  elseif co == 207 and (S.cmdline == "" or S.cmdline == nil) then
    tab.sel = math.max(1, #apps); return 3            -- End
  end
  return nil
end

--- Mouse click inside the tiles region, the band rail, or the legend.
function M.handleClick(S, tab, ev, deps)
  local apps = M.apps(S, tab)
  local _, _, pageStart, pp = M.pageOf(S, tab)

  -- Band rail: the ‹ › markers page.
  local band = S._homeBand
  if band and ev.y == band.row then
    if ev.x == band.prev then
      tab.sel = math.max(1, (tab.sel or 1) - pp); return 3
    elseif ev.x == band.next then
      tab.sel = math.min(math.max(1, #apps), (tab.sel or 1) + pp); return 3
    end
    return 0
  end

  if ev.y < S.TILE_TOP or ev.y >= S.TILE_TOP + S.TILE_H then return 0 end

  local hitIdx
  if M.listMode(S) then
    local slot = ev.y - S.TILE_TOP + 1
    if slot >= 1 and slot <= pp then hitIdx = pageStart + slot end
  else
    local slot = ui.tileHit(M.grid(S), ev.x, ev.y)
    if slot then hitIdx = pageStart + slot end
  end
  if not hitIdx or not apps[hitIdx] then return 0 end

  tab.sel = hitIdx
  if ev.button == 1 then return 3 end       -- right-click: select only
  return M.activate(S, tab, hitIdx, deps)   -- left-click: open
end

--- Mouse scroll: move the selection, like Up/Down.
function M.handleScroll(S, tab, ev)
  local apps = M.apps(S, tab)
  local delta = (ev.dir or 0) > 0 and -1 or 1
  local newSel = math.max(1, math.min(math.max(1, #apps), (tab.sel or 1) + delta))
  if newSel == tab.sel then return 0 end
  tab.sel = newSel
  return 3
end

return M
