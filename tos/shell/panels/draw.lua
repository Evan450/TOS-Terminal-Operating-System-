local computer = require("computer")
local helpers = require("shell.panels.helpers")
local widgets = require("shell.panels.widgets")
local ui = require("shell.panels.ui")
local selMod = require("shell.panels.selection")

local M = {}

local function ustrLib()
  local ok, u = pcall(require, "kernel.ustr")
  return (ok and u) or nil
end
local function ufitRow(s, cols)
  local u = ustrLib()
  if u and u.fit then return u.fit(s, cols) end
  return tostring(s or ""):sub(1, cols)
end
local function uwidthRow(s)
  local u = ustrLib()
  if u and u.width then return u.width(s) end
  return #tostring(s or "")
end

local BASE_MENUS = {
  { label = "File", items = {
    { label = "New File",      action = "newfile" },
    { label = "New Directory", action = "mkdir",   key = "F7" },
    { label = "Rename",        action = "rename" },
    { label = "Delete",        action = "delete",  key = "F8" },
    { sep = true },
    { label = "Refresh",       action = "refresh" },
  }},
  { label = "View", items = {
    { label = "View File",     action = "viewfile", key = "F3" },
    { label = "Edit File",     action = "editfile" },
  }},
  { label = "Tools", items = {
    { label = "Lua REPL",      action = "lua" },
    { label = "Verify System", action = "verify" },
    { label = "Flash EEPROM",  action = "flash" },
    { sep = true },

    { label = "Packages",      action = "run:pkg" },
    { label = "Repair (SRM)",  action = "run:srm" },
    { label = "Diagnostics",   action = "run:doctor" },
  }},
  { label = "System", items = {
    { label = "Desktop",    action = "run:desktop" },
    { label = "Processes",  action = "ps" },
    { label = "Memory",     action = "mem" },
    { label = "Hardware",   action = "hw" },
    { label = "Disk Usage", action = "df" },
    { label = "System Log", action = "log" },
    { sep = true },

    { label = "CLI Mode",   action = "run:cli" },
    { sep = true },
    { label = "Log Out",    action = "logout" },
    { label = "Reboot",     action = "reboot" },
    { label = "Shut Down",  action = "shutdown" },
  }},
  { label = "Settings", items = {
    { label = "Settings App", action = "run:settings" },
    { label = "Theme",      action = "run:theme list" },
    { label = "Status Bar", action = "statusbar_cfg" },
    { label = "Menu Bar",   action = "run:menu" },
    { label = "Boot Settings", action = "run:bootsettings" },
  }},

  { label = "Help", items = {
    { label = "Quick Help",         action = "help",     key = "F1" },
    { label = "Keyboard Shortcuts", action = "keyhelp" },
    { label = "Manual Pages",       action = "man" },
    { sep = true },
    { label = "Tutorial",           action = "tutorial" },
    { label = "About TOS",          action = "about" },
  }},
}

M.menuDefs = BASE_MENUS

local function cloneMenus()
  local out = {}
  for _, menu in ipairs(BASE_MENUS) do
    local m = { label = menu.label, items = {} }
    for _, it in ipairs(menu.items) do
      local c = {}
      for k, v in pairs(it) do c[k] = v end
      m.items[#m.items + 1] = c
    end
    out[#out + 1] = m
  end
  return out
end

--! Two files, applied in this order, both decoded as DATA (never
--! load()ed — a menu config can arrive on a floppy in someone's home
--! directory):
--!
--!   /etc/menu.cfg    system-wide. Admin-writable via securefs, so it is
--!                    the machine's bar: every user sees it.
--!   ~/.menu.cfg      per-user, layered on top.
--!
--! Each file is a LIST OF EDITS, and the reason it is edits rather than a
--! whole replacement bar is that a replacement goes stale the moment TOS
--! adds a command — which is exactly how the built-in set came to be a
--! year out of date. An edit list survives an upgrade.
--!
--!   { label = "Tetris", cmd = "tetris", menu = "Tools" }   -- add (legacy shape)
--!   { add    = "Tetris", cmd = "tetris", menu = "Tools", after = "Lua REPL" }
--!   { remove = "Flash EEPROM" }              -- an item, by label
--!   { remove = "Help", menu = true }         -- a whole top-level menu
--!   { rename = "Tools", to = "Utilities" }   -- a menu or an item
--!   { move   = "Desktop", menu = "Tools" }   -- item to another menu
--!   { menu   = "Reactor", after = "System" } -- a new empty top-level menu
--!
--! The legacy add shape is kept working byte-for-byte: `menu` config
--! files written before this existed must not break, and an operator who
--! only ever wanted "put my command in a drop-down" should not have to
--! learn the rest of it.

local function findMenu(menus, label)
  for i, m in ipairs(menus) do
    if m.label == label then return m, i end
  end
end

local function findItem(menus, label)
  for _, m in ipairs(menus) do
    for i, it in ipairs(m.items) do
      if it.label == label then return it, i, m end
    end
  end
end

local function applyEdit(menus, e)
  if type(e) ~= "table" then return end
  local function str(v, max)
    return (type(v) == "string" and #v > 0 and #v <= (max or 24)) and v or nil
  end

  if e.remove ~= nil then
    local target = str(e.remove, 32)
    if not target then return end
    if e.menu == true then
      local _, idx = findMenu(menus, target)
      if idx then table.remove(menus, idx) end
    else
      local _, idx, owner = findItem(menus, target)
      if owner then table.remove(owner.items, idx) end
    end
    return
  end

  if e.rename ~= nil then
    local from, to = str(e.rename, 32), str(e.to, 24)
    if not (from and to) then return end
    local m = findMenu(menus, from)
    if m then m.label = to; return end
    local it = findItem(menus, from)
    if it then it.label = to end
    return
  end

  if e.move ~= nil then
    local target, dest = str(e.move, 32), str(e.menu, 24)
    if not (target and dest) then return end
    local it, idx, owner = findItem(menus, target)
    local into = findMenu(menus, dest)
    if it and owner and into then
      table.remove(owner.items, idx)
      into.items[#into.items + 1] = it
    end
    return
  end

  if e.menu ~= nil and e.cmd == nil and e.label == nil and e.add == nil then
    local name = str(e.menu, 24)
    if not name or findMenu(menus, name) then return end
    local newM = { label = name, items = {} }
    local _, at = findMenu(menus, str(e.after, 24) or "")
    if at then table.insert(menus, at + 1, newM)
    else table.insert(menus, math.max(1, #menus), newM) end
    return
  end

  local label = str(e.add, 24) or str(e.label, 24)
  local cmd   = (type(e.cmd) == "string" and #e.cmd > 0 and #e.cmd <= 200) and e.cmd or nil
  if not (label and cmd) then return end
  local target = findMenu(menus, e.menu or "")
  if not target then
    target = findMenu(menus, "Custom")
    if not target then
      target = { label = "Custom", items = {} }
      table.insert(menus, math.max(1, #menus), target)
    end
  end
  local item = { label = label, action = "run:" .. cmd }
  local _, at, owner = findItem(menus, str(e.after, 32) or "")
  if at and owner == target then
    table.insert(target.items, at + 1, item)
  else
    target.items[#target.items + 1] = item
  end
end

local function applyConfig(menus, S, path)
  if not (S and S.F and S.F.exists and S.F.exists(path)) then return end
  local data = S.F.readFile(path)
  local okS, ser = pcall(require, "kernel.serialize")
  if not (data and okS and ser and ser.decode) then return end
  local okD, list = pcall(ser.decode, data, { maxBytes = 8192 })
  if not okD or type(list) ~= "table" then return end
  for _, e in ipairs(list) do applyEdit(menus, e) end
end

function M.buildMenuDefs(S)
  local menus = cloneMenus()
  applyConfig(menus, S, "/etc/menu.cfg")
  if S and S.who then
    local home = (S.who == "root") and "/root" or ("/home/" .. S.who)
    applyConfig(menus, S, home .. "/.menu.cfg")
  end

  if #menus == 0 then return cloneMenus() end
  return menus
end

M._applyEdit = applyEdit

function M.topBar(S)
  local D, T, W = S.D, S.T, S.W
  local bfg = T.menubar_fg or T.bar_fg or T.fg
  local bbg = T.menubar_bg or T.bar_bg or T.bg
  D.fill(1, 1, W, 1, " ", bfg, bbg)

  --! `dim` IS NOT ALWAYS LEGIBLE ON A BAR. T1 collapses the palette to
  --! 1-bit and sets dim = 0xFFFFFF, while menubar_bg is also white — so
  --! every inactive menu label used to be drawn white-on-white and simply
  --! vanish. Found while mocking the rework against the real theme
  --! tables. Fall back to the bar's own foreground whenever dim collides
  --! with the bar's background; this is theme-general, so a future preset
  --! that picks the same two colours can't reintroduce it.
  local mdim = (T.dim and T.dim ~= bbg) and T.dim or bfg
  local menuDefs = S.menuDefs or M.menuDefs
  local mSpans = ui.menuSpans(menuDefs)
  local activeIdx = S.menuOpen or (S.menuFocused and S.menuIdx or nil)
  for i, sp in ipairs(mSpans) do
    if menuDefs[i] then menuDefs[i]._x = sp.s end
    if i == activeIdx then
      D.set(sp.s, 1, sp.text, T.sel_fg or bbg, T.sel_bg or T.highlight)
    else
      D.set(sp.s, 1, sp.text, mdim, bbg)
    end
  end
  S._menuSpans = mSpans
  local menuEnd = #mSpans > 0 and mSpans[#mSpans].e or 1

  local mem = math.floor(computer.freeMemory() / 1024) .. "K"
  D.set(W - #mem, 1, mem, mdim, bbg)

  do
    local okA, appsMod = pcall(require, "shell.panels.apps")
    if okA and appsMod and appsMod.refreshTabs then
      pcall(appsMod.refreshTabs, S)
    end
  end

  local spans = ui.fitChips(S.tabs, S.activeTab, W - #mem - 2, menuEnd + 2)
  for _, sp in ipairs(spans) do
    if sp.state == "active" then
      D.set(sp.s, 1, sp.text, T.sel_fg or bbg, T.sel_bg or T.highlight)
    elseif sp.state == "busy" then
      D.set(sp.s, 1, sp.text, T.title or bfg, bbg)
    elseif sp.state == "more" then
      D.set(sp.s, 1, sp.text, T.highlight or T.title or bfg, bbg)
    else
      D.set(sp.s, 1, sp.text, bfg, bbg)
    end
  end
  S._tabSpans = spans

  local fillS = menuEnd + 2
  local fillE = ((spans[1] and spans[1].s) or (W - #mem - 1)) - 2
  if fillE >= fillS then
    D.set(fillS, 1, string.rep("░", fillE - fillS + 1), mdim, bbg)
  end
end

M.tabBar = M.topBar
function M.menuBar(S) end

function M.rail(S)
  local T, W = S.T, S.W
  local SZ_W = 7
  local extraCols = S.tier >= 3 and W >= 80
  local typeW = extraCols and 6 or 0
  local nameW = extraCols and (W - SZ_W - typeW - 4) or (W - SZ_W - 3)
  local sizeAt = nameW + SZ_W - 3
  local parts = {
    { label = S.browser.path },
    { text = "Name" },
  }

  local okH, home = pcall(require, "shell.panels.home")
  local viewPart = nil
  if okH and home and home.enabled(S) then
    local label = home.viewKeyLabel(S) .. " \226\150\184 tiles"

    local at = sizeAt - (uwidthRow(label) + 5)
    if at > 14 then
      viewPart = { label = label, at = at }
      parts[#parts + 1] = viewPart
    end
  end
  parts[#parts + 1] = { text = "Size", at = sizeAt }
  if extraCols then
    parts[#parts + 1] = { text = "Type", at = nameW + SZ_W + 2 }
  end
  local spans = ui.drawRail(S.D, T, S.RAIL_ROW, W, parts, { labelFg = T.title or T.fg })

  if okH and home then
    home.markToggle(S, S.RAIL_ROW, nil, nil)
    for i, p in ipairs(parts) do
      if p == viewPart and spans[i] then
        home.markToggle(S, S.RAIL_ROW, spans[i].s, spans[i].e)
      end
    end
  end
end

function M.sumRail(S, text)
  local txt = text
  if not txt then
    local files = S.browser.files or {}
    local n = #files
    if files[1] and files[1].name == ".." then n = n - 1 end
    txt = n .. " items"
    if S.browser.freeStr then txt = txt .. " · " .. S.browser.freeStr .. " free" end
  end
  ui.drawRail(S.D, S.T, S.SUM_ROW, S.W, { { label = txt } })
end

local function fileListLayout(S)
  local W = S.W
  local SZ_W = 7
  local extraCols = S.tier >= 3 and W >= 80
  local typeW = extraCols and 6 or 0
  local nameW = extraCols and (W - SZ_W - typeW - 4) or (W - SZ_W - 3)
  return SZ_W, typeW, nameW, extraCols
end

local function renderFileListRow(S, fi, y, SZ_W, typeW, nameW, extraCols)
  local D, T, W = S.D, S.T, S.W
  if fi < 1 or fi > #S.browser.files then
    D.fill(1, y, W, 1, " ", T.bg, T.bg)
    return
  end
  local f = S.browser.files[fi]
  local name = f.dir and ("[" .. f.name .. "]") or f.name
  local szStr = f.dir and " <DIR> " or helpers.padL(helpers.fmtSz(f.sz), SZ_W)

  name = name:sub(1, nameW - 2)
  local namePad = "   " .. helpers.padR(name, nameW - 2)
  local line
  if extraCols then
    local ext = f.dir and "dir" or (f.name:match("%.(%w+)$") or "")
    line = namePad .. " " .. szStr .. " " .. helpers.padR(ext:sub(1, typeW), typeW)
  else
    line = namePad .. " " .. szStr
  end
  local fg, bg
  if fi == S.browser.sel then
    fg, bg = T.sel_fg, T.sel_bg
  else
    fg, bg = helpers.fileColor(S, f), T.bg
  end

  D.set(1, y, (line .. S.padW):sub(1, W), fg, bg)
  if W >= 4 then
    D.set(2, y, ui.fileGlyph(f.name, f.dir), fg, bg)
  end
end

function M.fileList(S)
  local SZ_W, typeW, nameW, extraCols = fileListLayout(S)
  for row = 1, S.LIST_H do
    local fi = S.browser.scroll + row
    local y  = S.LIST_TOP + row - 1
    renderFileListRow(S, fi, y, SZ_W, typeW, nameW, extraCols)
  end
end

function M.fileListRow(S, fi)
  local row = fi - S.browser.scroll
  if row < 1 or row > S.LIST_H then return end
  local SZ_W, typeW, nameW, extraCols = fileListLayout(S)
  renderFileListRow(S, fi, S.LIST_TOP + row - 1, SZ_W, typeW, nameW, extraCols)
end

function M.outRow(S, text, color)
  local D, T, W = S.D, S.T, S.W

  if S._viewToggleSpans then S._viewToggleSpans[S.OUT_ROW] = nil end
  local s = ufitRow(text and tostring(text) or "", W)
  D.set(1, S.OUT_ROW, s .. S.padW:sub(1, math.max(0, W - uwidthRow(s))),
    color or T.dim, T.bg)
end

local HINT_PARTS = {
  "F1 Help", "F3 View", "F5 Copy", "F6 Move",
  "F7 New", "F8 Del", "F9 Menu", "F10 Quit", "Tab Complete",
}
function M.idleHint(S)
  local D, T, W = S.D, S.T, S.W
  local parts = HINT_PARTS

  local okH, home = pcall(require, "shell.panels.home")
  local flip = nil
  if okH and home and home.enabled(S) then
    flip = home.viewKeyLabel(S) .. " Tiles"
    parts = { HINT_PARTS[1], flip }
    for i = 2, #HINT_PARTS do parts[#parts + 1] = HINT_PARTS[i] end
    home.markToggle(S, S.OUT_ROW, nil, nil)
  end
  local sep, s = "  ", ""
  for _, part in ipairs(parts) do
    local cand = (s == "") and (" " .. part) or (s .. sep .. part)
    if #cand > W then break end

    if flip and part == flip then home.markToggle(S, S.OUT_ROW, #cand - #part + 1, #cand) end
    s = cand
  end
  local padded = (s .. S.padW):sub(1, W)
  D.set(1, S.OUT_ROW, padded, T.dim, T.bg)
end

function M.cmdGeom(S)
  local W = S.W
  local host = S.SC and S.SC.get("hostname") or "tos"

  local elevated = S._sudo ~= nil
  local mark  = elevated and "[sudo] " or ""
  local sigil = elevated and "# " or "$ "
  local pr   = mark .. S.who .. "@" .. host .. ":" .. S.cwd .. sigil
  if #pr > math.floor(W / 2) then pr = mark .. S.who .. sigil end
  local px    = #pr + 1
  local avail = W - #pr
  if avail < 1 then avail = 1 end
  local cl    = S.cmdline
  local cur   = S.cmdCursor or (#cl + 1)
  if cur < 1 then cur = 1 elseif cur > #cl + 1 then cur = #cl + 1 end
  local hs    = helpers.cmdScroll(#cl, cur, avail)
  return pr, px, avail, hs, cur, elevated
end

function M.cmdIndexAt(S, x)
  local _, px, avail, hs = M.cmdGeom(S)
  if not x or x < px then return nil end
  if x > px + avail - 1 then x = px + avail - 1 end
  local i = (x - px) + 1 + hs
  return math.max(1, math.min(#S.cmdline + 1, i))
end

function M.cmdRow(S)
  local D, T, W = S.D, S.T, S.W
  local pr, px, avail, hs, cur, elevated = M.cmdGeom(S)
  local cl = S.cmdline
  local visible = cl:sub(hs + 1, hs + avail)
  local trail   = S.padW:sub(1, math.max(0, avail - #visible))
  D.set(1,  S.CMD_ROW, pr,               T.highlight, T.bg)

  if elevated then D.set(1, S.CMD_ROW, "[sudo]", T.warning, T.bg) end
  D.set(px, S.CMD_ROW, visible .. trail, T.fg,        T.bg)

  local selFrom, selTo = selMod.range(S.cmdSel, cur)
  if selFrom then
    local sfg = T.sel_fg or T.bg
    local sbg = T.sel_bg or T.highlight
    for i = selFrom, selTo - 1 do
      local x = px + (i - 1) - hs
      if x >= px and x <= W then
        D.set(x, S.CMD_ROW, cl:sub(i, i), sfg, sbg)
      end
    end
  end

  local curCol = px + ((cur - 1) - hs)
  if curCol >= px and curCol <= W then
    local under = (cur <= #cl) and cl:sub(cur, cur) or "_"
    if under == " " then under = "_" end
    D.set(curCol, S.CMD_ROW, under, T.bg, T.highlight)
  end
end

function M.statusBar(S, widgetDefs)
  local D, T, W = S.D, S.T, S.W
  local wlist = widgets.getWidgetList(S)
  local parts = {}
  for _, wname in ipairs(wlist) do
    local fn = widgetDefs[wname]
    if fn then
      local ok2, val = pcall(fn)
      if ok2 and val then
        parts[#parts + 1] = wname:sub(1, 1):upper() .. wname:sub(2) .. ":" .. val
      end
    end
  end
  ui.drawRampBar(D, T, S.STAT_ROW, W, table.concat(parts, " │ "), nil,
    T.statusbar_fg, T.statusbar_bg)
end

function M.viewTab(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local content = tab.content or {}
  local gutterW = S.tier >= 2 and (#tostring(#content) + 1) or 0
  local viewW = W - gutterW
  local viewH = H - 2

  D.fill(1, 2, W, viewH, " ", T.fg, T.bg)
  for i = 1, viewH do
    local li = tab.offset + i
    if li <= #content then
      local e   = content[li]
      local txt = type(e) == "table" and e[1] or tostring(e)
      local col = type(e) == "table" and e[2] or T.fg

      if gutterW > 0 then
        D.set(1, 1 + i, helpers.formatLineNum(li, gutterW), T.dim, T.bg)
      end

      if tab.searchTerm and #tab.searchTerm > 0 then
        local pos = txt:find(tab.searchTerm, 1, true)
        if pos then
          D.set(gutterW + 1, 1 + i, txt:sub(1, viewW), col, T.bg)
          local matchText = txt:sub(pos, pos + #tab.searchTerm - 1)
          if pos <= viewW then
            D.set(gutterW + pos, 1 + i, matchText:sub(1, viewW - pos + 1), T.sel_fg, T.sel_bg)
          end
        else
          D.set(gutterW + 1, 1 + i, txt:sub(1, viewW), col, T.bg)
        end
      else
        D.set(gutterW + 1, 1 + i, txt:sub(1, viewW), col, T.bg)
      end

      if tab.selAnchor and selMod.lineRange(tab.selAnchor, tab.selCur or tab.selAnchor) then
        local from, to = selMod.lineRange(tab.selAnchor, tab.selCur or tab.selAnchor)
        if li >= from and li <= to then
          D.set(gutterW + 1, 1 + i,
            (txt .. S.padW):sub(1, viewW), T.sel_fg or T.bg, T.sel_bg or T.highlight)
        end
      end
    end
  end
  local shown = math.min(viewH, math.max(0, #content - tab.offset))
  local searchInfo = tab.searchTerm and (" [/" .. tab.searchTerm .. "]") or ""
  local okH, home = pcall(require, "shell.panels.home")
  local cyc = (okH and home) and home.cycleKeyLabel(S) or "F2"
  local info = string.format("%d-%d / %d%s  [^Q]Close [^F]Find [%s]Tab",
    tab.offset + 1, tab.offset + shown, #content, searchInfo, cyc)
  ui.drawRampBar(D, T, H, W, info, nil, T.bar_fg, T.bar_bg)
end

function M.editTab(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local lines = tab.lines or { "" }
  local edH = H - 2
  local gutterW = S.tier >= 2 and (math.max(#tostring(#lines), 2) + 1) or 0
  local editW = W - gutterW
  local isLua = tab.path and tab.path:match("%.lua$")
  local syn = isLua and widgets.getSyntax(S)
  --! Horizontal scroll offset, decided HERE and nowhere else.
  --!
  --! This is the only code that knows the real geometry: gutterW depends
  --! on the tier and the line count, editW on the current screen width.
  --! Computing it in the key handler as well would be two places
  --! deriving the same number from different information -- and the one
  --! that gets it wrong is invisible, because a mis-scrolled view just
  --! looks like the editor lost your cursor.
  --!
  --! Deciding it at draw time also means a screen RESIZE needs no
  --! special handling: the next repaint recomputes from the new width.
  local viewLeft = tab.viewLeft or 1
  if tab.curCol < viewLeft then viewLeft = tab.curCol end
  if tab.curCol > viewLeft + editW - 1 then viewLeft = tab.curCol - editW + 1 end
  if viewLeft < 1 then viewLeft = 1 end
  tab.viewLeft = viewLeft
  local lastCol = viewLeft + editW - 1

  D.fill(1, 2, W, edH, " ", T.fg, T.bg)
  for i = 1, edH do
    local li = tab.viewTop + i - 1
    if li <= #lines then
      local lineText = lines[li]
      local y = 1 + i

      if gutterW > 0 then
        local lnColor = li == tab.curRow and T.title or T.dim
        D.set(1, y, helpers.formatLineNum(li, gutterW), lnColor, T.bg)
      end

      if syn then
        --! Tokenize the WHOLE line, then clip each token to the visible
        --! window. Tokenizing only the visible slice would be simpler
        --! and wrong: a slice can cut a string literal or comment in
        --! half, and the highlighter would then colour the remainder as
        --! code from there to the end of the line.
        local tokens = syn.tokenize(lineText)
        local col = 1
        for _, tok in ipairs(tokens) do
          local tokText = tok.text
          local tokEnd  = col + #tokText - 1
          local from = math.max(col, viewLeft)
          local to   = math.min(tokEnd, lastCol)
          if to >= from then
            local piece = tokText:sub(from - col + 1, to - col + 1)
            if #piece > 0 then
              D.set(gutterW + (from - viewLeft) + 1, y,
                piece, syn.tokenColor(tok.type, T), T.bg)
            end
          end
          col = tokEnd + 1
          if col > lastCol then break end
        end
      else
        D.set(gutterW + 1, y, lineText:sub(viewLeft, lastCol), T.fg, T.bg)
      end

      --! Say when a line runs past either edge, the way nano does. Only
      --! drawn when there IS more text that way, so the markers are
      --! information rather than decoration -- and only over the edge
      --! cell, which is the one column they cost.
      if viewLeft > 1 then
        D.set(gutterW + 1, y, "<", T.dim, T.bg)
      end
      if #lineText > lastCol then
        D.set(gutterW + editW, y, ">", T.dim, T.bg)
      end
    end
  end

  if tab.selAnchor then
    local sfg = T.sel_fg or T.bg
    local sbg = T.sel_bg or T.highlight
    local here = { row = tab.curRow, col = tab.curCol }
    for i = 1, edH do
      local li = tab.viewTop + i - 1
      local lineText = lines[li]
      if lineText then
        --! Walk the VISIBLE columns, not 1..editW. Iterating from 1
        --! painted the selection at the wrong x once the view scrolled,
        --! and highlighted cells the operator could not see.
        for cix = viewLeft, math.min(#lineText, lastCol) do
          if selMod.contains(tab.selAnchor, here, li, cix) then
            D.set(gutterW + (cix - viewLeft) + 1, 1 + i, lineText:sub(cix, cix), sfg, sbg)
          end
        end

        local eol = #lineText + 1
        if eol >= viewLeft and eol <= lastCol
           and selMod.contains(tab.selAnchor, here, li, eol) then
          D.set(gutterW + (eol - viewLeft) + 1, 1 + i, " ", sfg, sbg)
        end
      end
    end
  end

  local cy = tab.curRow - tab.viewTop + 2
  if cy >= 2 and cy < 2 + edH then
    --! Offset by the scroll, so the cursor is drawn where the character
    --! it sits on actually IS. Previously this was gutterW + curCol and
    --! simply skipped when that fell past the screen -- which is what
    --! made typing past the right edge look like a frozen editor.
    local curX = gutterW + (tab.curCol - viewLeft) + 1
    if curX >= gutterW + 1 and curX <= gutterW + editW then
      local char = (lines[tab.curRow] or ""):sub(tab.curCol, tab.curCol)
      if char == "" then char = " " end
      D.set(curX, cy, char, T.sel_fg, T.sel_bg)
    end
  end

  local mod = tab.modified and " [+]" or ""
  local searchInfo = tab.searchTerm and (" [/" .. tab.searchTerm .. "]") or ""
  local stat = string.format("%s%s  Ln %d, Col %d%s  [^S]Save [^F]Find [^Q]Close",
    tab.label, mod, tab.curRow, tab.curCol, searchInfo)
  ui.drawRampBar(D, T, H, W, stat, nil, T.bar_fg, T.bar_bg)
end

function M.shell(S, widgetDefs)
  local okH, home = pcall(require, "shell.panels.home")
  local tab = S.tabs[S.activeTab]
  local tiles = okH and home and home.isTiles(S, tab)

  if tiles then
    home.drawHeader(S, tab)
    home.drawBand(S, tab)
    home.drawTiles(S, tab)
    M.sumRail(S, home.summaryText(S, tab))
  else
    S._homeBand = nil
    M.rail(S)
    M.fileList(S)
    M.sumRail(S)
  end

  if okH and home then home.markToggle(S, S.OUT_ROW, nil, nil) end
  if S.outLines and #S.outLines > 0 then M.outLines(S)
  elseif S.lastOut then M.outRow(S, S.lastOut[1], S.lastOut[2])
  elseif tiles then
    local txt, ts, te = home.hintText(S, tab)
    M.outRow(S, txt, S.T.dim)
    home.markToggle(S, S.OUT_ROW, ts, te)
  else M.idleHint(S) end
  M.cmdRow(S)
  M.statusBar(S, widgetDefs)
end

function M.outLines(S)
  local D, T, W = S.D, S.T, S.W
  local lines = S.outLines
  if not lines or #lines == 0 then return end

  local top = S.LIST_TOP
  local okH, home = pcall(require, "shell.panels.home")
  if okH and home and home.isTiles(S) then top = S.TILE_TOP end
  local n = math.min(#lines, S.OUT_ROW - top + 1)
  local top = S.OUT_ROW - n + 1
  for i = 1, n do
    local e = lines[i] or { "", T.fg }
    D.set(1, top + i - 1, (tostring(e[1] or "") .. S.padW):sub(1, W),
      e[2] or T.fg, T.bg)
  end
end

function M.all(S, widgetDefs)
  local framed = S.D and S.D.beginFrame and S.D.beginFrame()
  if not framed then return M._allBody(S, widgetDefs) end
  local ok, err = pcall(M._allBody, S, widgetDefs)
  S.D.endFrame()
  if not ok then error(err, 0) end
end

function M._allBody(S, widgetDefs)
  M.topBar(S)
  local tab = S.tabs[S.activeTab]

  if not tab or tab.type == "shell" then
    M.shell(S, widgetDefs)
  elseif tab.type == "view" or tab.type == "output" then
    M.viewTab(S, tab)
  elseif tab.type == "edit" then
    M.editTab(S, tab)
  else
    local ok, apps = pcall(require, "shell.panels.apps")
    if ok and apps then
      apps.ensureBuiltins()
      local app = apps.get(tab.type)
      if app and app.draw then app.draw(S, tab) end
    end
  end
end

function M.menuDropdown(S)
  if not S.menuOpen then return end
  local def = (S.menuDefs or M.menuDefs)[S.menuOpen]
  if not def then return end
  local x = def._x or 2
  S.D.dropdown(x, S.MENU_ROW + 1, def.items, S.menuSel)
end

function M.contextMenu(S)
  if not S.ctxOpen then return end
  S.D.dropdown(S.ctxX, S.ctxY, S.ctxItems, S.ctxSel)
end

return M
