local ui = require("shell.panels.ui")

local M = {}

local _desktop = nil
local function desktopMod()
  if _desktop == nil then
    local ok, mod = pcall(require, "shell.panels.desktop")
    _desktop = (ok and mod) or false
  end
  return _desktop or nil
end

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

function M.markToggle(S, row, s, e)
  S._viewToggleSpans = S._viewToggleSpans or {}
  S._viewToggleSpans[row] = (s and e) and { s = s, e = e } or nil
end

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

function M.view(S, tab)
  if not M.enabled(S) then return "files" end
  tab = tab or homeTab(S)
  return (tab and tab.view == "tiles") and "tiles" or "files"
end

function M.isTiles(S, tab) return M.view(S, tab) == "tiles" end

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

function M.toggle(S, tab)
  tab = tab or homeTab(S)
  return M.setView(S, M.isTiles(S, tab) and "files" or "tiles", tab)
end

function M.viewKeyLabel(S)
  local ok, keys = pcall(require, "shell.keys")
  if ok and keys and keys.label then
    local lbl = keys.label("view", S and S.who or nil)
    if lbl and lbl ~= "" then return (lbl:match("^[^/]+") or lbl):gsub("%s+$", "") end
  end
  return "F2"
end

function M.cycleKeyLabel(S)
  return M.enabled(S) and "Tab" or "F2"
end

function M.isViewKey(S, ch, co)
  local ok, keys = pcall(require, "shell.keys")
  if ok and keys and keys.is then
    return keys.is("view", ch, co, S and S.who or nil)
  end
  return co == (S and S.KEYS and S.KEYS.homeView or 60)
end

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

function M.pageOf(S, tab)
  local apps = M.apps(S, tab)
  local pp = M.perPage(S)
  local sel = (tab and tab.sel) or 1
  local pages = math.max(1, math.ceil(#apps / pp))
  local page = math.min(pages, math.floor((sel - 1) / pp) + 1)
  return page, pages, (page - 1) * pp, pp
end

function M.drawHeader(S, tab)
  local D, T, W = S.D, S.T, S.W
  local host = (S.SC and S.SC.get and S.SC.get("hostname")) or "tos"
  local clock = "--:--"
  local okT, t = pcall(os.date, "*t")
  if okT and t then clock = string.format("%02d:%02d", t.hour, t.min) end

  ui.drawRail(D, T, S.RAIL_ROW, W, {
    { label = "\226\140\130 " .. (S.who or "?") .. "@" .. host },
    { text = S.cwd or "/" },
    { text = clock, at = W - 8 },
  }, { labelFg = T.title or T.fg })
end

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

  if pages > 1 and spans[1] then
    S._homeBand = { row = S.BAND_ROW, prev = spans[1].s,
                    next = spans[1].e, pages = pages }
  end
end

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

  local s = " " .. lead
  local spanS, spanE = nil, nil
  for _, k in ipairs(keys) do
    local cand = s .. " \194\183 " .. k

    if uwidth(cand) > S.W - 2 then break end

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

function M.activate(S, tab, idx, deps)
  local d = desktopMod()
  if not d then return 0 end
  local act = d.resolveApp(tab.apps, idx)
  if act.type == "tab" then

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

local DIGIT_CODE_BASE = 1
local function altDigit(ch, co)
  if type(co) ~= "number" or co < 2 or co > 10 then return nil end
  if ch ~= nil and ch ~= 0 then return nil end
  return co - DIGIT_CODE_BASE
end
M._altDigit = altDigit

function M.handleKey(S, tab, ch, co, deps)
  local apps = M.apps(S, tab)
  local sel = tab.sel or 1
  local _, _, _, pp = M.pageOf(S, tab)
  local cols = M.listMode(S) and 1 or M.grid(S).cols

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

  if co == 203 then
    if sel > 1 then tab.sel = sel - 1; return 3 end
    return 0
  elseif co == 205 then
    if sel < #apps then tab.sel = sel + 1; return 3 end
    return 0
  elseif co == 200 then
    if sel - cols >= 1 then tab.sel = sel - cols; return 3 end
    return 0
  elseif co == 208 then
    if sel + cols <= #apps then tab.sel = sel + cols; return 3 end
    return 0
  elseif co == 201 then
    tab.sel = math.max(1, sel - pp); return 3
  elseif co == 209 then
    tab.sel = math.min(math.max(1, #apps), sel + pp); return 3
  elseif co == 199 and (S.cmdline == "" or S.cmdline == nil) then
    tab.sel = 1; return 3
  elseif co == 207 and (S.cmdline == "" or S.cmdline == nil) then
    tab.sel = math.max(1, #apps); return 3
  end
  return nil
end

function M.handleClick(S, tab, ev, deps)
  local apps = M.apps(S, tab)
  local _, _, pageStart, pp = M.pageOf(S, tab)

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
  if ev.button == 1 then return 3 end
  return M.activate(S, tab, hitIdx, deps)
end

function M.handleScroll(S, tab, ev)
  local apps = M.apps(S, tab)
  local delta = (ev.dir or 0) > 0 and -1 or 1
  local newSel = math.max(1, math.min(math.max(1, #apps), (tab.sel or 1) + delta))
  if newSel == tab.sel then return 0 end
  tab.sel = newSel
  return 3
end

return M
