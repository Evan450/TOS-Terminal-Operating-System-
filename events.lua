-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Main Event Loop                 ║
-- ║  Signal dispatch, input handling, draw scheduling   ║
-- ╚══════════════════════════════════════════════════════╝

local component = require("computer")
local helpers   = require("shell.panels.helpers")
local tabsMod   = require("shell.panels.tabs")
local dialogsMod= require("shell.panels.dialogs")
local drawMod   = require("shell.panels.draw")
local fbMod     = require("shell.panels.filebrowser")
local editorMod = require("shell.panels.editor")
local ctxMod    = require("shell.panels.context")
local menusMod  = require("shell.panels.menus")

local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return require("computer").pullSignal(0.05)
end

--- deps = { C, exec, autoMount, makeProgramEnv, widgetDefs }
function M.run(S, deps)
  local D, T, F = S.D, S.T, S.F
  local K, E = S.K, S.E
  local W, H = S.W, S.H
  local KEYS = S.KEYS
  local tier = S.tier
  local C = deps.C
  local exec = deps.exec
  local autoMount = deps.autoMount
  local makeProgramEnv = deps.makeProgramEnv
  local widgetDefs = deps.widgetDefs

  -- ── Drawing helpers (delegate to draw module) ──
  local function drawAll()        drawMod.all(S, widgetDefs) end
  local function drawTabBar()     drawMod.tabBar(S) end
  local function drawMenuBar()    drawMod.menuBar(S) end
  local function drawPathBar()    drawMod.pathBar(S) end
  local function drawColumnHeader() drawMod.columnHeader(S) end
  local function drawFileList()   drawMod.fileList(S) end
  local function drawOutRow(text, color) drawMod.outRow(S, text, color) end
  local function drawCmdRow()     drawMod.cmdRow(S) end
  local function drawStatusBar()  drawMod.statusBar(S, widgetDefs) end
  local function drawViewTab(tab) drawMod.viewTab(S, tab) end
  local function drawEditTab(tab) drawMod.editTab(S, tab) end
  local function drawMenuDropdown() drawMod.menuDropdown(S) end
  local function drawContextMenu()  drawMod.contextMenu(S) end

  -- Convenience accessors
  local function closeTab(idx)    return tabsMod.close(S, idx) end
  local function cycleTab(dir)    return tabsMod.cycle(S, dir) end
  local function selPath()        return helpers.selPath(S) end
  local function canRead(p, o)    return helpers.canRead(S, p, o) end
  local function canWrite(p, o)   return helpers.canWrite(S, p, o) end
  local function refreshBrowser() return helpers.refreshBrowser(S) end
  local function openViewTab(buf, label) return editorMod.openViewTab(S, buf, label) end
  local function openContextMenu() return ctxMod.open(S) end
  local function navigateUp()     return fbMod.navigateUp(S) end
  local function navigateInto(d)  return fbMod.navigateInto(S, d) end
  local function doCopy()         return fbMod.doCopy(S) end
  local function doMove()         return fbMod.doMove(S) end
  local function doMkdir()        return fbMod.doMkdir(S) end
  local function doDelete()       return fbMod.doDelete(S) end
  local function promptInput(msg, maxLen, isPw) return dialogsMod.promptInput(S, msg, maxLen, isPw) end
  local function promptSearch(term) return dialogsMod.promptSearch(S, term) end
  local function expandBuf(buf)   return helpers.expandBuf(S, buf) end

  -- Initialize
  helpers.loadFiles(S, S.browser)
  drawAll()

  local function applyDraw(level)
    if level <= 0 then return end
    local tab = S.tabs[S.activeTab]
    if not tab or tab.type == "shell" then
      if level == 1 then
        drawTabBar()
        if S.lastOut then drawOutRow(S.lastOut[1], S.lastOut[2]) else drawOutRow(nil) end
        drawCmdRow()
        drawStatusBar()
      elseif level == 2 then
        drawTabBar(); drawMenuBar(); drawPathBar(); drawColumnHeader(); drawFileList()
        if S.lastOut then drawOutRow(S.lastOut[1], S.lastOut[2]) else drawOutRow(nil) end
        drawCmdRow(); drawStatusBar()
      elseif level >= 3 then
        drawAll()
      end
      if S.menuOpen then drawMenuDropdown() end
      if S.ctxOpen then drawContextMenu() end
    elseif tab.type == "view" or tab.type == "output" then
      drawTabBar(); drawViewTab(tab)
    elseif tab.type == "edit" then
      drawTabBar(); drawEditTab(tab)
    end
  end

  while true do
    local sig, a2, ch, co = pullSignal()
    local draw = 0
    local tab = S.tabs[S.activeTab]

    if sig == "key_down" then
      if S.ctxOpen then
        if co == 200 then ctxMod.nextItem(S, -1)
        elseif co == 208 then ctxMod.nextItem(S, 1)
        elseif co == 28 then
          local item = S.ctxItems[S.ctxSel]
          if item and not item.sep then ctxMod.execute(S, item.action, makeProgramEnv) end
        elseif ch == 17 then S.ctxOpen = false end
        draw = 3
      elseif S.menuOpen then
        if co == 200 then menusMod.menuNextItem(S, -1)
        elseif co == 208 then menusMod.menuNextItem(S, 1)
        elseif co == 28 then
          local item = drawMod.menuDefs[S.menuOpen].items[S.menuSel]
          if item and not item.sep then
            local result = menusMod.execute(S, item.action, {
              exec = exec, drawAll = drawAll, widgetDefs = widgetDefs })
            if result then return result end
          end
        elseif ch == 17 then S.menuOpen = nil; S.menuFocused = false
        elseif co == 203 then S.menuOpen = S.menuOpen > 1 and S.menuOpen - 1 or #drawMod.menuDefs; S.menuSel = 1
        elseif co == 205 then S.menuOpen = S.menuOpen < #drawMod.menuDefs and S.menuOpen + 1 or 1; S.menuSel = 1
        end
        draw = 3
      elseif S.menuFocused then
        if co == 203 then S.menuIdx = S.menuIdx > 1 and S.menuIdx - 1 or #drawMod.menuDefs
        elseif co == 205 then S.menuIdx = S.menuIdx < #drawMod.menuDefs and S.menuIdx + 1 or 1
        elseif co == 28 then S.menuOpen = S.menuIdx; S.menuSel = 1
        elseif ch == 17 then S.menuFocused = false end
        draw = 3
      else
        local handled = false
        if co == KEYS.tabNext then cycleTab(1); draw = 3; handled = true
        elseif co == KEYS.tabClose then
          if tab and tab.type ~= "shell" then
            if tab.type == "edit" and tab.modified then
              D.fill(1, H, W, 1, " ", T.fg, T.bg)
              D.set(1, H, " Unsaved! [y]Close [n]Cancel", T.warning, T.bg)
              while true do
                local s3, _, c3 = pullSignal()
                if s3 == "key_down" then
                  if c3 == 121 or c3 == 89 then closeTab(); break else break end
                end
              end
            else closeTab() end
            draw = 3
          end
          handled = true
        elseif co == KEYS.menu then
          if tab and tab.type ~= "shell" then S.activeTab = 1 end
          S.menuFocused = not S.menuFocused
          if not S.menuFocused then S.menuOpen = nil end
          draw = 3; handled = true
        elseif co == KEYS.quit then
          S.activeTab = 1; drawAll()
          D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
          D.set(1, S.OUT_ROW, (" [1]Reboot [2]Off [3]Logout [4]Shell [^Q]Cancel"):sub(1, W), T.title, T.bg)
          while true do
            local s2, _, c2 = pullSignal()
            if s2 == "key_down" then
              if c2 == 49 then if _G._TOS.audio then _G._TOS.audio.shutdown() end; K.reboot(); return "exit"
              elseif c2 == 50 then if _G._TOS.audio then _G._TOS.audio.shutdown() end; K.shutdown(); return "exit"
              elseif c2 == 51 then if _G._TOS.audio then _G._TOS.audio.shutdown() end; E.push("tos_logout", S.displayIdx); return "exit"
              elseif c2 == 52 then return "cli"
              elseif c2 == 17 then S.lastOut = nil; break end
            end
          end
          draw = 3; handled = true
        end

        if not handled and tab then
          if tab.type == "shell" then
            if co == KEYS.help then
              local hbuf = {}; local function ho(t2, c2) hbuf[#hbuf+1] = {t2, c2} end
              C.help({}, ho)
              local helpIdx = nil
              for i, t2 in ipairs(S.tabs) do
                if t2.label == "Help" and t2.type == "view" then helpIdx = i; break end
              end
              if helpIdx then S.tabs[helpIdx].content = expandBuf(hbuf); S.tabs[helpIdx].offset = 0; S.activeTab = helpIdx
              else openViewTab(hbuf, "Help") end
              draw = 3
            elseif co == KEYS.view then
              local fpath, f = selPath()
              if fpath and f and not f.dir then
                if canRead(fpath) then
                  local content = F.readFile(fpath)
                  if content then
                    local vbuf = { { " Viewing: " .. f.name, T.title } }
                    for l in content:gmatch("([^\n]*)\n?") do vbuf[#vbuf+1] = {l, T.fg} end
                    openViewTab(vbuf, f.name)
                  else S.lastOut = { "Cannot read: " .. f.name, T.error } end
                end
              end
              draw = 3
            elseif co == KEYS.copy then doCopy(); draw = 3
            elseif co == KEYS.move then doMove(); draw = 3
            elseif co == KEYS.mkdir then doMkdir(); draw = 3
            elseif co == KEYS.delete then doDelete(); draw = 3
            elseif S.cmdline == "" and co == 200 then
              if S.browser.sel > 1 then S.browser.sel = S.browser.sel - 1
                if S.browser.sel <= S.browser.scroll then S.browser.scroll = S.browser.sel - 1 end
              end; draw = 2
            elseif S.cmdline == "" and co == 208 then
              if S.browser.sel < #S.browser.files then S.browser.sel = S.browser.sel + 1
                if S.browser.sel > S.browser.scroll + S.LIST_H then S.browser.scroll = S.browser.sel - S.LIST_H end
              end; draw = 2
            elseif co == 201 then S.browser.sel = math.max(1, S.browser.sel - S.LIST_H); S.browser.scroll = math.max(0, S.browser.scroll - S.LIST_H); draw = 2
            elseif co == 209 then S.browser.sel = math.min(#S.browser.files, S.browser.sel + S.LIST_H); S.browser.scroll = math.min(math.max(0, #S.browser.files - S.LIST_H), S.browser.scroll + S.LIST_H); draw = 2
            elseif co == 199 then S.browser.sel = 1; S.browser.scroll = 0; draw = 2
            elseif co == 207 then S.browser.sel = #S.browser.files; S.browser.scroll = math.max(0, #S.browser.files - S.LIST_H); draw = 2
            elseif co == 14 then
              if #S.cmdline > 0 then S.cmdline = S.cmdline:sub(1, -2); draw = 1
              else navigateUp(); draw = 3 end
            elseif co == 28 then
              if S.cmdline ~= "" then
                local input = S.cmdline; S.cmdline = ""; S.cmdHistIdx = 0
                if #S.cmdHistory == 0 or S.cmdHistory[#S.cmdHistory] ~= input then S.cmdHistory[#S.cmdHistory+1] = input end
                exec(input)
              else
                local f = S.browser.files[S.browser.sel]
                if f then
                  if f.name == ".." then navigateUp()
                  elseif f.dir then navigateInto(f.name)
                  else openContextMenu() end
                end
              end; draw = 3
            elseif ch == 17 then
              S.cmdline = ""
              if S.clipboard then S.clipboard = nil; S.lastOut = { "Copy cancelled", T.dim }; draw = 3
              else S.lastOut = nil; draw = 1 end
            elseif S.cmdline ~= "" and co == 200 then
              if S.cmdHistIdx == 0 then S.cmdHistIdx = #S.cmdHistory
              elseif S.cmdHistIdx > 1 then S.cmdHistIdx = S.cmdHistIdx - 1 end
              if S.cmdHistIdx > 0 then S.cmdline = S.cmdHistory[S.cmdHistIdx] end; draw = 1
            elseif S.cmdline ~= "" and co == 208 then
              if S.cmdHistIdx < #S.cmdHistory then S.cmdHistIdx = S.cmdHistIdx + 1; S.cmdline = S.cmdHistory[S.cmdHistIdx]
              else S.cmdHistIdx = 0; S.cmdline = "" end; draw = 1
            elseif ch and ch >= 32 and ch < 127 then
              S.cmdline = S.cmdline .. string.char(ch); S.cmdHistIdx = 0; draw = 1
            end

          elseif tab.type == "view" or tab.type == "output" then
            local content = tab.content or {}; local viewH = H - 2
            if ch == 17 or ch == 113 then closeTab(); draw = 3
            elseif ch == 6 then
              local term = promptSearch(tab.searchTerm); tab.searchTerm = term
              if term then for i = tab.offset + 1, #content do
                local e = content[i]; local txt = type(e) == "table" and e[1] or tostring(e)
                if txt:find(term, 1, true) then tab.offset = math.max(0, i - 1); break end
              end end; draw = 3
            elseif co == 200 and tab.offset > 0 then tab.offset = tab.offset - 1; draw = 1
            elseif co == 208 and tab.offset + viewH < #content then tab.offset = tab.offset + 1; draw = 1
            elseif co == 201 then tab.offset = math.max(0, tab.offset - viewH); draw = 1
            elseif co == 209 then tab.offset = math.min(math.max(0, #content - viewH), tab.offset + viewH); draw = 1
            elseif co == 199 then tab.offset = 0; draw = 1
            elseif co == 207 then tab.offset = math.max(0, #content - viewH); draw = 1 end

          elseif tab.type == "edit" then
            local lines = tab.lines; local edH = H - 2
            local function clampEdit()
              tab.curRow = math.max(1, math.min(#lines, tab.curRow))
              tab.curCol = math.max(1, math.min(#(lines[tab.curRow] or "") + 1, tab.curCol))
              if tab.curRow < tab.viewTop then tab.viewTop = tab.curRow end
              if tab.curRow > tab.viewTop + edH - 1 then tab.viewTop = tab.curRow - edH + 1 end
            end
            local function pushUndo()
              if not tab.undoStack then tab.undoStack = {} end
              local snap = {}; for j, ln in ipairs(lines) do snap[j] = ln end
              tab.undoStack[#tab.undoStack + 1] = { lines = snap, row = tab.curRow, col = tab.curCol }
              if #tab.undoStack > (tab.undoMax or 32) then table.remove(tab.undoStack, 1) end
            end

            if co == 200 then tab.curRow = tab.curRow - 1; clampEdit(); draw = 1
            elseif co == 208 then tab.curRow = tab.curRow + 1; clampEdit(); draw = 1
            elseif co == 203 then
              if tab.curCol > 1 then tab.curCol = tab.curCol - 1
              elseif tab.curRow > 1 then tab.curRow = tab.curRow - 1; tab.curCol = #lines[tab.curRow]+1 end
              clampEdit(); draw = 1
            elseif co == 205 then
              if tab.curCol <= #lines[tab.curRow] then tab.curCol = tab.curCol + 1
              elseif tab.curRow < #lines then tab.curRow = tab.curRow + 1; tab.curCol = 1 end
              clampEdit(); draw = 1
            elseif co == 199 then tab.curCol = 1; draw = 1
            elseif co == 207 then tab.curCol = #lines[tab.curRow]+1; draw = 1
            elseif co == 201 then tab.curRow = math.max(1, tab.curRow - edH); clampEdit(); draw = 1
            elseif co == 209 then tab.curRow = math.min(#lines, tab.curRow + edH); clampEdit(); draw = 1
            elseif co == 14 then
              if tab.curCol > 1 then
                local l = lines[tab.curRow]; lines[tab.curRow] = l:sub(1, tab.curCol-2) .. l:sub(tab.curCol)
                tab.curCol = tab.curCol - 1; tab.modified = true; draw = 1
              elseif tab.curRow > 1 then
                pushUndo(); tab.curCol = #lines[tab.curRow-1] + 1
                lines[tab.curRow-1] = lines[tab.curRow-1] .. lines[tab.curRow]
                table.remove(lines, tab.curRow); tab.curRow = tab.curRow - 1; tab.modified = true; clampEdit(); draw = 1
              end
            elseif co == 211 then
              local l = lines[tab.curRow]
              if tab.curCol <= #l then lines[tab.curRow] = l:sub(1, tab.curCol-1) .. l:sub(tab.curCol+1); tab.modified = true; draw = 1
              elseif tab.curRow < #lines then pushUndo(); lines[tab.curRow] = l .. lines[tab.curRow+1]; table.remove(lines, tab.curRow+1); tab.modified = true; draw = 1 end
            elseif co == 28 then
              pushUndo(); local l = lines[tab.curRow]; local before = l:sub(1, tab.curCol - 1); local after = l:sub(tab.curCol)
              lines[tab.curRow] = before
              local indent = before:match("^(%s*)") or ""; local trimmed = before:match("^%s*(.-)%s*$") or ""
              if trimmed:match("then$") or trimmed:match("do$") or trimmed:match("repeat$") or trimmed:match("else$") or trimmed:match("function%s*%(.*%)%s*$") or trimmed:match("{%s*$") then indent = indent .. "  " end
              table.insert(lines, tab.curRow + 1, indent .. after); tab.curRow = tab.curRow + 1; tab.curCol = #indent + 1; tab.modified = true; clampEdit(); draw = 1
            elseif co == 15 then
              local l = lines[tab.curRow]; lines[tab.curRow] = l:sub(1, tab.curCol-1) .. "  " .. l:sub(tab.curCol)
              tab.curCol = tab.curCol + 2; tab.modified = true; draw = 1
            elseif ch == 17 then
              if tab.modified then
                D.fill(1, H, W, 1, " ", T.fg, T.bg); D.set(1, H, " Save? [y]es [n]o [c]ancel", T.warning, T.bg)
                local s2, _, c2 = pullSignal()
                if s2 == "key_down" then
                  if c2 == 121 or c2 == 89 then
                    if tab.path and canWrite(tab.path) then F.writeFile(tab.path, table.concat(lines, "\n")); refreshBrowser() end
                    closeTab(); draw = 3
                  elseif c2 == 110 or c2 == 78 then closeTab(); draw = 3
                  else draw = 1 end
                end
              else closeTab(); draw = 3 end
            elseif ch == 19 then
              if tab.path and canWrite(tab.path) then
                if F.writeFile(tab.path, table.concat(lines, "\n")) then tab.modified = false; S.lastOut = { "Saved: " .. tab.label, T.highlight }; refreshBrowser()
                else S.lastOut = { "Save failed!", T.error } end
              elseif not tab.path then S.lastOut = { "No path set", T.error } end; draw = 1
            elseif ch == 6 then
              local term = promptSearch(tab.searchTerm)
              if term and #term > 0 then
                tab.searchTerm = term; local found = false
                for i = tab.curRow, #lines do
                  local startCol = i == tab.curRow and tab.curCol + 1 or 1
                  local col = lines[i]:find(term, startCol, true)
                  if col then tab.curRow = i; tab.curCol = col; found = true; break end
                end
                if not found then for i = 1, tab.curRow - 1 do
                  local col = lines[i]:find(term, 1, true)
                  if col then tab.curRow = i; tab.curCol = col; found = true; break end
                end end
                if not found then S.lastOut = { "Not found: " .. term, T.warning } end; clampEdit()
              elseif term == nil then tab.searchTerm = nil end; draw = 1
            elseif ch == 8 then
              local find = promptInput("Find: ", 40)
              if find and #find > 0 then
                local repl = promptInput("Replace with: ", 40)
                if repl then
                  local count = 0
                  if tab.undoStack then local snap = {}; for j, ln in ipairs(lines) do snap[j] = ln end
                    tab.undoStack[#tab.undoStack + 1] = { lines = snap, row = tab.curRow, col = tab.curCol }
                    if #tab.undoStack > (tab.undoMax or 32) then table.remove(tab.undoStack, 1) end end
                  for i = 1, #lines do local newLine, subs = lines[i]:gsub(find, repl, nil)
                    if subs > 0 then lines[i] = newLine; count = count + subs end end
                  if count > 0 then tab.modified = true; S.lastOut = { "Replaced " .. count .. " occurrence(s)", T.highlight }
                  else S.lastOut = { "Not found: " .. find, T.warning }
                    if tab.undoStack and #tab.undoStack > 0 then tab.undoStack[#tab.undoStack] = nil end end
                end
              end; draw = 1
            elseif ch == 26 then
              if tab.undoStack and #tab.undoStack > 0 then
                local st = table.remove(tab.undoStack); tab.lines = st.lines; lines = tab.lines
                tab.curRow = st.row; tab.curCol = st.col; tab.modified = true; clampEdit()
                S.lastOut = { "Undo", T.dim }
              else S.lastOut = { "Nothing to undo", T.dim } end; draw = 1
            elseif ch == 3 then S.editClipboard = { lines[tab.curRow] }; S.lastOut = { "Line copied", T.dim }; draw = 1
            elseif ch == 24 then
              if tab.undoStack then local snap = {}; for j, ln in ipairs(lines) do snap[j] = ln end
                tab.undoStack[#tab.undoStack + 1] = { lines = snap, row = tab.curRow, col = tab.curCol }
                if #tab.undoStack > (tab.undoMax or 32) then table.remove(tab.undoStack, 1) end end
              S.editClipboard = { lines[tab.curRow] }
              if #lines > 1 then table.remove(lines, tab.curRow) else lines[1] = "" end
              tab.modified = true; clampEdit(); S.lastOut = { "Line cut", T.dim }; draw = 1
            elseif ch == 22 then
              if S.editClipboard and #S.editClipboard > 0 then
                if tab.undoStack then local snap = {}; for j, ln in ipairs(lines) do snap[j] = ln end
                  tab.undoStack[#tab.undoStack + 1] = { lines = snap, row = tab.curRow, col = tab.curCol }
                  if #tab.undoStack > (tab.undoMax or 32) then table.remove(tab.undoStack, 1) end end
                for ci, cl in ipairs(S.editClipboard) do table.insert(lines, tab.curRow + ci, cl) end
                tab.curRow = tab.curRow + #S.editClipboard; tab.modified = true; clampEdit()
                S.lastOut = { "Pasted " .. #S.editClipboard .. " line(s)", T.dim }
              else S.lastOut = { "Clipboard empty", T.dim } end; draw = 1
            elseif ch and ch >= 32 and ch < 127 then
              local l = lines[tab.curRow]; lines[tab.curRow] = l:sub(1, tab.curCol-1) .. string.char(ch) .. l:sub(tab.curCol)
              tab.curCol = tab.curCol + 1; tab.modified = true; draw = 1
            end
          end -- tab type
        end -- not handled
      end -- priority

    elseif sig == "clipboard" and type(ch) == "string" then
      if tab and tab.type == "shell" then S.cmdline = S.cmdline .. ch:gsub("\n", ""); draw = 1
      elseif tab and tab.type == "edit" then
        local clean = ch:gsub("\n", " "):gsub("\r", ""); local l = tab.lines[tab.curRow]
        tab.lines[tab.curRow] = l:sub(1, tab.curCol-1) .. clean .. l:sub(tab.curCol)
        tab.curCol = tab.curCol + #clean; tab.modified = true; draw = 1
      end
    elseif sig == "tos_focus" then T = D.getTheme(); S.T = T; draw = 3
    elseif sig == "tos_interrupt" then
      if tab and tab.type == "shell" then
        if S.cmdline ~= "" then S.cmdline = ""; S.lastOut = { "^C", T.dim } end; draw = 1
      end
    elseif sig == "component_added" then
      local addr, ctype = a2, ch
      if ctype == "filesystem" then
        local bootAddr = _G._TOS and _G._TOS.bootFS and _G._TOS.bootFS.address
        if addr ~= bootAddr then
          local ok2, mntPath, lbl = pcall(autoMount, addr)
          if ok2 and mntPath then
            local hasModule = F.exists(F.join(mntPath, "module.cfg"))
            local hasTOS = F.exists(F.join(mntPath, "tos/kernel/init.lua"))
            if hasModule then S.lastOut = { 'Module disk: "' .. lbl .. '" -> ' .. mntPath .. '  (disk install ' .. mntPath .. ')', T.highlight }
            elseif hasTOS then S.lastOut = { 'TOS install disk: "' .. lbl .. '" -> ' .. mntPath, T.highlight }
            else S.lastOut = { 'Disk inserted: "' .. lbl .. '" -> ' .. mntPath, T.highlight } end
            pcall(refreshBrowser)
          elseif not ok2 then S.lastOut = { "Disk insert error: " .. tostring(mntPath), T.error } end
        end
      end; draw = 3
    elseif sig == "component_removed" then
      local addr = a2; local ok2, mnts = pcall(F.mounts)
      if ok2 and mnts then for _, m in ipairs(mnts) do
        if m.address == addr then pcall(F.unmount, m.mountPoint)
          S.lastOut = { 'Disk removed: "' .. (m.label or "disk") .. '"', T.dim }; pcall(refreshBrowser); break end
      end end; draw = 3
    end

    applyDraw(draw)
  end
end

return M
