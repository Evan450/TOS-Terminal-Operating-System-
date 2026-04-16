-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Drawing                         ║
-- ║  All TUI rendering: tabs, menus, file list, editor  ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local helpers = require("shell.panels.helpers")
local widgets = require("shell.panels.widgets")

local M = {}

-- Menu bar definitions (constant)
M.menuDefs = {
  { label = "File", items = {
    { label = "New File",      action = "newfile" },
    { label = "New Directory", action = "mkdir",  key = "F7" },
    { sep = true },
    { label = "Rename",       action = "rename" },
    { sep = true },
    { label = "Quit",         action = "quit",   key = "F10" },
  }},
  { label = "Tools", items = {
    { label = "Lua REPL",      action = "lua" },
    { label = "Verify System", action = "verify" },
    { label = "Flash EEPROM",  action = "flash" },
  }},
  { label = "System", items = {
    { label = "Processes",   action = "ps" },
    { label = "Memory",     action = "mem" },
    { label = "Hardware",   action = "hw" },
    { label = "Disk Usage", action = "df" },
    { label = "System Log", action = "log" },
    { sep = true },
    { label = "Reboot",     action = "reboot" },
    { label = "Shutdown",   action = "shutdown" },
  }},
  { label = "Settings", items = {
    { label = "Status Bar",  action = "statusbar_cfg" },
  }},
}

function M.tabBar(S)
  local D, T, W = S.D, S.T, S.W
  D.fill(1, 1, W, 1, " ", T.bar_fg, T.bar_bg)
  local x = 2
  for i, tab in ipairs(S.tabs) do
    local label = tab.label
    if tab.type == "edit" and tab.modified then label = label .. "[+]" end
    if #label > 14 then label = label:sub(1, 13) .. "~" end
    label = " " .. label .. " "
    if i == S.activeTab then
      D.set(x, 1, label, T.sel_fg, T.sel_bg)
    else
      D.set(x, 1, label, T.bar_fg, T.bar_bg)
    end
    x = x + #label + 1
    if x >= W - 12 then
      D.set(x, 1, "..", T.dim, T.bar_bg)
      break
    end
  end
  local mem = math.floor(computer.freeMemory() / 1024) .. "K"
  local right = mem .. " "
  D.set(W - #right + 1, 1, right, T.bar_fg, T.bar_bg)
end

function M.menuBar(S)
  local D = S.D
  local activeIdx2 = S.menuOpen or (S.menuFocused and S.menuIdx or nil)
  local showFocus = S.menuFocused or S.menuOpen ~= nil
  D.menuBarEx(M.menuDefs, activeIdx2, showFocus, S.MENU_ROW)
end

function M.pathBar(S)
  local D, T, W = S.D, S.T, S.W
  D.fill(1, S.PATH_ROW, W, 1, " ", T.fg, T.bg)
  local pathStr = " " .. S.browser.path
  if #pathStr > W then pathStr = pathStr:sub(1, W - 3) .. "..." end
  D.set(1, S.PATH_ROW, pathStr, T.title, T.bg)
end

function M.columnHeader(S)
  local D, T, W = S.D, S.T, S.W
  if not S.HDR_ROW then return end
  D.fill(1, S.HDR_ROW, W, 1, " ", T.title, T.bg)
  local SZ_W = 7
  local nameW = W - SZ_W - 3
  if S.tier >= 3 and W >= 80 then
    local typeW = 6
    nameW = W - SZ_W - typeW - 4
    local hdr = " " .. helpers.padR("Name", nameW) .. " " .. helpers.padL("Size", SZ_W) .. " " .. helpers.padR("Type", typeW)
    D.set(1, S.HDR_ROW, hdr:sub(1, W), T.title, T.bg)
  else
    local hdr = " " .. helpers.padR("Name", nameW) .. " " .. helpers.padL("Size", SZ_W)
    D.set(1, S.HDR_ROW, hdr:sub(1, W), T.title, T.bg)
  end
end

function M.fileList(S)
  local D, T, W = S.D, S.T, S.W
  local SZ_W = 7
  local nameW = W - SZ_W - 3
  local extraCols = S.tier >= 3 and W >= 80
  local typeW = extraCols and 6 or 0
  if extraCols then nameW = W - SZ_W - typeW - 4 end

  for row = 1, S.LIST_H do
    local fi = S.browser.scroll + row
    local y  = S.LIST_TOP + row - 1
    if fi >= 1 and fi <= #S.browser.files then
      local f = S.browser.files[fi]
      local name = f.dir and ("[" .. f.name .. "]") or f.name
      local szStr = f.dir and " <DIR> " or helpers.padL(helpers.fmtSz(f.sz), SZ_W)
      name = name:sub(1, nameW)
      local namePad = " " .. helpers.padR(name, nameW)
      local line
      if extraCols then
        local ext = f.dir and "dir" or (f.name:match("%.(%w+)$") or "")
        line = namePad .. " " .. szStr .. " " .. helpers.padR(ext:sub(1, typeW), typeW)
      else
        line = namePad .. " " .. szStr
      end
      if fi == S.browser.sel then
        D.set(1, y, line:sub(1, W), T.sel_fg, T.sel_bg)
      else
        D.set(1, y, line:sub(1, W), helpers.fileColor(S, f), T.bg)
      end
    else
      D.fill(1, y, W, 1, " ", T.bg, T.bg)
    end
  end
end

function M.outRow(S, text, color)
  local D, T, W = S.D, S.T, S.W
  local s = text and tostring(text) or ""
  local padded = (s .. string.rep(" ", W)):sub(1, W)
  D.set(1, S.OUT_ROW, padded, color or T.dim, T.bg)
end

function M.cmdRow(S)
  local D, T, W = S.D, S.T, S.W
  local host = S.SC and S.SC.get("hostname") or "tos"
  local pr   = S.who .. "@" .. host .. ":" .. S.cwd .. "$ "
  if #pr > math.floor(W / 2) then pr = S.who .. "$ " end
  local px    = #pr + 1
  local avail = W - #pr
  local sh    = #S.cmdline > avail - 1 and S.cmdline:sub(#S.cmdline - (avail - 2)) or S.cmdline
  local trail = string.rep(" ", math.max(0, avail - #sh - 1))
  D.set(1,        S.CMD_ROW, pr,                T.highlight, T.bg)
  D.set(px,       S.CMD_ROW, sh .. " " .. trail, T.fg,       T.bg)
  D.set(px + #sh, S.CMD_ROW, "_",               T.highlight, T.bg)
end

function M.statusBar(S, widgetDefs)
  local D, T, W = S.D, S.T, S.W
  D.fill(1, S.STAT_ROW, W, 1, " ", T.statusbar_fg, T.statusbar_bg)
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
  local status = " " .. table.concat(parts, " | ")
  D.set(1, S.STAT_ROW, status:sub(1, W), T.statusbar_fg, T.statusbar_bg)
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
        local ln = string.format("%" .. (gutterW - 1) .. "d ", li)
        D.set(1, 1 + i, ln, T.dim, T.bg)
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
    end
  end
  local shown = math.min(viewH, math.max(0, #content - tab.offset))
  local searchInfo = tab.searchTerm and (" [/" .. tab.searchTerm .. "]") or ""
  local info = string.format(" %d-%d / %d%s  [^Q]Close [^F]Find [F2]Tab",
    tab.offset + 1, tab.offset + shown, #content, searchInfo)
  D.fill(1, H, W, 1, " ", T.bar_fg, T.bar_bg)
  D.set(1, H, info:sub(1, W), T.bar_fg, T.bar_bg)
end

function M.editTab(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local lines = tab.lines or { "" }
  local edH = H - 2
  local gutterW = S.tier >= 2 and (math.max(#tostring(#lines), 2) + 1) or 0
  local editW = W - gutterW
  local isLua = tab.path and tab.path:match("%.lua$")
  local syn = isLua and widgets.getSyntax(S)

  D.fill(1, 2, W, edH, " ", T.fg, T.bg)
  for i = 1, edH do
    local li = tab.viewTop + i - 1
    if li <= #lines then
      local lineText = lines[li]
      local y = 1 + i

      if gutterW > 0 then
        local lnColor = li == tab.curRow and T.title or T.dim
        local ln = string.format("%" .. (gutterW - 1) .. "d ", li)
        D.set(1, y, ln, lnColor, T.bg)
      end

      if syn then
        local tokens = syn.tokenize(lineText)
        local x = gutterW + 1
        for _, tok in ipairs(tokens) do
          local tokText = tok.text
          if x - gutterW - 1 + #tokText > editW then
            tokText = tokText:sub(1, editW - (x - gutterW - 1))
          end
          if #tokText > 0 then
            local tc = syn.tokenColor(tok.type, T)
            D.set(x, y, tokText, tc, T.bg)
            x = x + #tokText
          end
          if x > W then break end
        end
      else
        D.set(gutterW + 1, y, lineText:sub(1, editW), T.fg, T.bg)
      end
    end
  end

  -- Cursor
  local cy = tab.curRow - tab.viewTop + 2
  if cy >= 2 and cy < 2 + edH then
    local curX = gutterW + tab.curCol
    if curX <= W then
      local char = (lines[tab.curRow] or ""):sub(tab.curCol, tab.curCol)
      if char == "" then char = " " end
      D.set(curX, cy, char, T.sel_fg, T.sel_bg)
    end
  end

  -- Status bar
  local mod = tab.modified and " [+]" or ""
  local searchInfo = tab.searchTerm and (" [/" .. tab.searchTerm .. "]") or ""
  local stat = string.format(" %s%s  Ln %d, Col %d%s  [^S]Save [^F]Find [^Q]Close",
    tab.label, mod, tab.curRow, tab.curCol, searchInfo)
  D.fill(1, H, W, 1, " ", T.bar_fg, T.bar_bg)
  D.set(1, H, stat:sub(1, W), T.bar_fg, T.bar_bg)
end

function M.shell(S, widgetDefs)
  M.menuBar(S)
  M.pathBar(S)
  M.columnHeader(S)
  M.fileList(S)
  if S.lastOut then M.outRow(S, S.lastOut[1], S.lastOut[2])
  else               M.outRow(S, nil) end
  M.cmdRow(S)
  M.statusBar(S, widgetDefs)
end

function M.all(S, widgetDefs)
  M.tabBar(S)
  local tab = S.tabs[S.activeTab]
  if not tab or tab.type == "shell" then
    M.shell(S, widgetDefs)
  elseif tab.type == "view" or tab.type == "output" then
    M.viewTab(S, tab)
  elseif tab.type == "edit" then
    M.editTab(S, tab)
  end
end

function M.menuDropdown(S)
  if not S.menuOpen then return end
  local def = M.menuDefs[S.menuOpen]
  local x = def._x or 2
  S.D.dropdown(x, S.MENU_ROW + 1, def.items, S.menuSel)
end

function M.contextMenu(S)
  if not S.ctxOpen then return end
  S.D.dropdown(S.ctxX, S.ctxY, S.ctxItems, S.ctxSel)
end

return M
