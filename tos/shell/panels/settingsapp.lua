local ui = require("shell.panels.ui")
local tabsMod = require("shell.panels.tabs")

local M = {}

function M.buildPages(deps)
  deps = deps or {}
  local pages = {}

  local appearance = {
    { kind = "header", label = "Appearance" },
    { kind = "choice", id = "theme", label = "Theme preset",
      values = deps.themeNames or {}, value = deps.themeCurrent },
    { kind = "info",   text = "Left/Right previews the theme live." },
    { kind = "button", id = "theme_save",  label = "Save as my theme" },
    { kind = "button", id = "theme_reset", label = "Forget my saved theme" },
  }
  pages[#pages + 1] = { id = "appearance", label = "Appearance", rows = appearance }

  local sb = {
    { kind = "header", label = "Status Bar" },
    { kind = "info",   text = "Widgets on the bottom bar. Changes save immediately." },
  }
  for _, wname in ipairs(deps.widgetsAvailable or {}) do
    sb[#sb + 1] = { kind = "toggle", id = "widget:" .. wname, label = wname,
                    value = (deps.widgetsEnabled or {})[wname] or false }
  end
  pages[#pages + 1] = { id = "statusbar", label = "Status Bar", rows = sb }

  local LANDING_VIEW = { desktop = "tiles", shell = "files" }
  local landingValue = LANDING_VIEW[deps.landing] or deps.landing or "tiles"
  local desktop = {
    { kind = "header", label = "Home" },
    { kind = "choice", id = "landing", label = "After login, show",
      values = { "tiles", "files" }, value = landingValue },
  }
  if deps.canProfile == false then
    desktop[#desktop + 1] = { kind = "info",
      text = "No home directory — this session can't save a profile." }
  else
    desktop[#desktop + 1] = { kind = "info",
      text = "Saved to your profile immediately." }
  end
  pages[#pages + 1] = { id = "desktop", label = "Home", rows = desktop }

  local lang = {
    { kind = "header", label = "Language" },
    { kind = "choice", id = "uilang", label = "UI language",
      values = deps.langCodes or { "en" }, value = deps.language or "en" },
    { kind = "info",   text = "Applies now; saved to your profile. Catalogs live in /usr/lang." },
  }
  if deps.langName and deps.langName ~= "" then
    table.insert(lang, 3, { kind = "info", text = "Current: " .. deps.langName })
  end
  pages[#pages + 1] = { id = "language", label = "Language", rows = lang }

  local sys = { { kind = "header", label = "System" } }
  if (deps.userTier or 0) >= 2 then
    sys[#sys + 1] = { kind = "button", id = "run:bootsettings", label = "Boot Settings" }
    sys[#sys + 1] = { kind = "button", id = "run:users",        label = "User Accounts" }
  end
  sys[#sys + 1] = { kind = "button", id = "run:doctor", label = "Health Check (doctor)" }
  sys[#sys + 1] = { kind = "button", id = "run:about",  label = "About TOS" }
  pages[#pages + 1] = { id = "system", label = "System", rows = sys }

  return pages
end

local function sessionOf(S)
  if S.U and S.st and S.U.getSession then
    local ok, sess = pcall(S.U.getSession, S.st)
    if ok and sess then return sess end
  end
  if S.U and S.U.currentSession then
    local ok, sess = pcall(S.U.currentSession)
    if ok then return sess end
  end
  return nil
end

function M.defaultLanding(who)
  return (who == "root") and "shell" or "desktop"
end

local function liveDeps(S)
  local d = { userTier = S.userTier or 0 }

  local okT, themeMod = pcall(require, "kernel.theme")
  if okT and themeMod then
    local okL, names = pcall(themeMod.list)
    d.themeNames = okL and names or {}
    local okC, cur = pcall(themeMod.current)
    d.themeCurrent = (okC and type(cur) == "table" and cur.preset) or nil
  end

  local base = { "memory", "disk", "clock", "user", "uptime", "battery" }
  local seen, avail = {}, {}
  for _, w in ipairs(base) do seen[w] = true; avail[#avail + 1] = w end
  local okW, widgetsMod = pcall(require, "shell.panels.widgets")
  if okW and widgetsMod then
    local okD2, defs = pcall(widgetsMod.makeWidgetDefs, S)
    if okD2 and type(defs) == "table" then
      pcall(widgetsMod.loadCustomWidgets, S, defs)
      for wname in pairs(defs) do
        if not seen[wname] then seen[wname] = true; avail[#avail + 1] = wname end
      end
    end
    local enabled = {}
    local okL2, list = pcall(widgetsMod.getWidgetList, S)
    if okL2 and type(list) == "table" then
      for _, wname in ipairs(list) do enabled[wname] = true end
    end
    d.widgetsEnabled = enabled
  end
  d.widgetsAvailable = avail

  local okI, i18nMod = pcall(require, "kernel.i18n")
  if okI and i18nMod then
    local codes = {}
    local okA, avail = pcall(i18nMod.available)
    if okA and type(avail) == "table" then
      for _, l in ipairs(avail) do codes[#codes + 1] = l.code end
    end
    if #codes == 0 then codes = { "en" } end
    d.langCodes = codes
    local okC2, cur = pcall(i18nMod.language)
    d.language = okC2 and cur or "en"
    local okN, name = pcall(i18nMod.languageName)
    d.langName = okN and name or nil
  end

  local sess = sessionOf(S)
  d.canProfile = not not (sess and sess.home and sess.home ~= "" and sess.home ~= "/")
  local okP, profileMod = pcall(require, "kernel.profile")
  if okP and profileMod and profileMod.load then
    local okL3, p = pcall(profileMod.load, sess)
    if okL3 and type(p) == "table" and p.landing then d.landing = p.landing end
  end
  d.landing = d.landing or M.defaultLanding(S.who)

  return d
end

function M.refresh(S, tab)
  tab.pages = M.buildPages(liveDeps(S))
  tab.page = math.max(1, math.min(tab.page or 1, #tab.pages))
  local rows = tab.pages[tab.page].rows
  tab.sel = ui.firstSelectable(rows) or 1
end

function M.open(S)
  local idx = tabsMod.find(S, "settings")
  local tab
  if idx then
    tab = S.tabs[idx]
    S.activeTab = idx
  else
    tab = tabsMod.create(S, "settings", "Settings", { page = 1, sel = 1 })
  end
  M.refresh(S, tab)
  return tab
end

local function shellTabIndex(S)
  for i, t in ipairs(S.tabs) do
    if t.type == "shell" then return i end
  end
  return 1
end

local function saveLanding(S, tab, value)
  local sess = sessionOf(S)
  local okP, profileMod = pcall(require, "kernel.profile")
  if not (okP and profileMod and profileMod.load and profileMod.save) then
    tab.msg = { "Profile module unavailable", S.T.error }; return
  end
  local p = profileMod.load(sess)
  p.landing = value
  local ok, err = profileMod.save(p, sess)
  tab.msg = ok and { "Landing saved: " .. value, S.T.highlight }
             or { "Save failed: " .. tostring(err), S.T.error }
end

local function saveLanguage(S, tab, code)
  local okI, i18nMod = pcall(require, "kernel.i18n")
  if not (okI and i18nMod and i18nMod.setLanguage) then
    tab.msg = { "i18n unavailable", S.T.error }; return
  end
  local ok, err = i18nMod.setLanguage(code)
  if not ok then
    tab.msg = { "Cannot set '" .. tostring(code) .. "': " .. tostring(err), S.T.error }
    return
  end

  local sess = sessionOf(S)
  local okP, profileMod = pcall(require, "kernel.profile")
  if okP and profileMod and profileMod.load and profileMod.save then
    local p = profileMod.load(sess)
    p.lang = (i18nMod.language() ~= "en") and i18nMod.language() or nil
    local okSave, sErr = profileMod.save(p, sess)
    tab.msg = okSave and { "Language: " .. i18nMod.language() .. " (saved)", S.T.highlight }
               or { "Language set (profile save failed: " .. tostring(sErr) .. ")", S.T.warning }
  else
    tab.msg = { "Language: " .. i18nMod.language() .. " (this session)", S.T.highlight }
  end
end

local function saveStatusbar(S, tab)

  local page = tab.pages[tab.page]
  local result = {}
  for _, row in ipairs(page.rows) do
    local wname = type(row.id) == "string" and row.id:match("^widget:(.+)$")
    if wname and row.value then result[#result + 1] = wname end
  end
  if S.SC and S.SC.set then
    S.SC.set("statusbar_widgets", result)
    if S.SC.save then S.SC.save() end
    tab.msg = { "Status bar updated", S.T.highlight }
  else
    tab.msg = { "Config unavailable", S.T.error }
  end
end

local function applyTheme(S, tab, name)
  local okT, themeMod = pcall(require, "kernel.theme")
  if not (okT and themeMod and themeMod.apply) then
    tab.msg = { "Theme module unavailable", S.T.error }; return
  end

  local okCall, ok, err = pcall(themeMod.apply, name)
  if not okCall then ok, err = false, ok end
  if ok then

    S.T = S.D.getTheme()
    tab.msg = { "Previewing: " .. name .. "  (use Save to keep it)", S.T.highlight }
  else
    tab.msg = { "Theme failed: " .. tostring(err), S.T.error }
  end
end

local function activateRow(S, tab, row, dir, deps)
  if not row then return 0 end

  if row.kind == "toggle" then
    row.value = not row.value
    if type(row.id) == "string" and row.id:match("^widget:") then
      saveStatusbar(S, tab)
    end
    return 3
  end

  if row.kind == "choice" then
    local newVal = ui.cycle(row.values, row.value, dir)
    if newVal == row.value then return 0 end
    row.value = newVal
    if row.id == "theme" then applyTheme(S, tab, newVal)
    elseif row.id == "landing" then saveLanding(S, tab, newVal)
    elseif row.id == "uilang" then saveLanguage(S, tab, newVal) end
    return 3
  end

  if row.kind == "button" then
    local cmd = type(row.id) == "string" and row.id:match("^run:(.+)$")
    if cmd then

      S.activeTab = shellTabIndex(S)
      if deps and deps.exec then deps.exec(cmd) end
      return 3
    end
    if row.id == "theme_save" then
      local okT, themeMod = pcall(require, "kernel.theme")
      if okT and themeMod and themeMod.saveForUser then

        local okCall, ok, err = pcall(themeMod.saveForUser, sessionOf(S))
        if not okCall then ok, err = false, ok end
        tab.msg = ok and { "Theme saved for " .. (S.who or "?"), S.T.highlight }
                   or { "Save failed: " .. tostring(err), S.T.error }
      end
      return 3
    end
    if row.id == "theme_reset" then
      local okT, themeMod = pcall(require, "kernel.theme")
      if okT and themeMod and themeMod.clearForUser then
        local okCall, ok, err = pcall(themeMod.clearForUser, sessionOf(S))
        if not okCall then ok, err = false, ok end
        tab.msg = ok and { "Saved theme forgotten", S.T.highlight }
                   or { "Reset failed: " .. tostring(err), S.T.error }
      end
      return 3
    end
  end
  return 0
end

local function chipSpans(pages)
  local spans, x = {}, 2
  for i, p in ipairs(pages) do
    local cell = " " .. p.label .. " "
    spans[i] = { s = x, e = x + #cell - 1, cell = cell }
    x = x + #cell + 1
  end
  return spans
end

function M.draw(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  if not tab.pages then M.refresh(S, tab) end
  local pages = tab.pages
  local page = pages[tab.page]

  D.fill(1, 2, W, H - 1, " ", T.fg, T.bg)
  ui.drawRail(D, T, 2, W, { { label = "§ Settings" } },
    { labelFg = T.title or T.fg })

  for i, sp in ipairs(chipSpans(pages)) do
    if sp.s <= W then
      if i == tab.page then
        D.set(sp.s, 3, sp.cell, T.sel_fg or T.bg, T.sel_bg or T.highlight)
      else
        D.set(sp.s, 3, sp.cell, T.dim or T.fg, T.bg)
      end
    end
  end

  local top = 5
  local capacity = H - top - 1
  tab.scroll = tab.scroll or 0
  if tab.sel - tab.scroll > capacity then tab.scroll = tab.sel - capacity end
  if tab.sel - tab.scroll < 1 then tab.scroll = math.max(0, tab.sel - 1) end
  for i = 1, capacity do
    local ri = tab.scroll + i
    local row = page.rows[ri]
    if not row then break end
    ui.drawSettingRow(D, T, top + i - 1, 2, W - 2, row, ri == tab.sel)
  end

  if tab.msg then
    D.fill(1, H - 1, W, 1, " ", T.fg, T.bg)
    D.set(2, H - 1, tostring(tab.msg[1]):sub(1, W - 2), tab.msg[2] or T.dim, T.bg)
  end
  ui.drawRampBar(D, T, H, W,
    "Arrows Move · Left/Right Change · Enter Apply · Tab Page · ^Q Close",
    nil, T.statusbar_fg or T.bar_fg, T.statusbar_bg or T.bar_bg)
end

local function switchPage(S, tab, dir)
  tab.page = tab.page + dir
  if tab.page > #tab.pages then tab.page = 1 end
  if tab.page < 1 then tab.page = #tab.pages end
  tab.scroll = 0
  tab.msg = nil
  tab.sel = ui.firstSelectable(tab.pages[tab.page].rows) or 1
end

function M.handleKey(S, tab, ch, co, deps)
  if not tab.pages then M.refresh(S, tab) end
  local rows = tab.pages[tab.page].rows
  local row = rows[tab.sel]

  if ch == 17 then
    tabsMod.close(S)
    return 3
  elseif co == 15 or co == 209 then
    switchPage(S, tab, 1); return 3
  elseif co == 201 then
    switchPage(S, tab, -1); return 3
  elseif co == 200 then
    tab.sel = ui.nextSelectable(rows, tab.sel, -1); return 3
  elseif co == 208 then
    tab.sel = ui.nextSelectable(rows, tab.sel, 1); return 3
  elseif co == 203 then
    return activateRow(S, tab, row, -1, deps)
  elseif co == 205 then
    return activateRow(S, tab, row, 1, deps)
  elseif co == 28 then
    return activateRow(S, tab, row, 1, deps)
  end
  return 0
end

function M.handleClick(S, tab, ev, deps)
  if not tab.pages then M.refresh(S, tab) end

  if ev.y == 3 then
    for i, sp in ipairs(chipSpans(tab.pages)) do
      if ev.x >= sp.s and ev.x <= sp.e then
        if i ~= tab.page then
          tab.page = i; tab.scroll = 0; tab.msg = nil
          tab.sel = ui.firstSelectable(tab.pages[i].rows) or 1
        end
        return 3
      end
    end
    return 0
  end

  local top = 5
  local ri = (tab.scroll or 0) + (ev.y - top + 1)
  local rows = tab.pages[tab.page].rows
  local row = rows[ri]
  if ev.y >= top and row and ui.rowSelectable(row) then
    tab.sel = ri
    if ev.button == 1 then return 3 end
    return activateRow(S, tab, row, 1, deps)
  end
  return 0
end

function M.handleScroll(S, tab, ev)
  if not tab.pages then M.refresh(S, tab) end
  local rows = tab.pages[tab.page].rows
  local dir = (ev.dir or 0) > 0 and -1 or 1
  local newSel = ui.nextSelectable(rows, tab.sel, dir)
  if newSel == tab.sel then return 0 end
  tab.sel = newSel
  return 3
end

return M
