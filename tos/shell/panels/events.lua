local computer  = require("computer")
local helpers   = require("shell.panels.helpers")
local tabsMod   = require("shell.panels.tabs")
local dialogsMod= require("shell.panels.dialogs")
local drawMod   = require("shell.panels.draw")
local fbMod     = require("shell.panels.filebrowser")
local editorMod = require("shell.panels.editor")
local ctxMod    = require("shell.panels.context")
local menusMod  = require("shell.panels.menus")
local mouseMod  = require("shell.panels.mouse")
local appsMod   = require("shell.panels.apps")
local homeMod   = require("shell.panels.home")
local keysMod   = require("shell.keys")
local selMod    = require("shell.panels.selection")
local clipMod   = require("kernel.clipboard")

local desktopMod = nil
local function getDesktop()
  if desktopMod == nil then
    local ok, mod = pcall(require, "shell.panels.desktop")
    desktopMod = ok and mod or false
  end
  return desktopMod or nil
end

local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end

  return require("computer").pullSignal(0.1)
end

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

  local function drawAll()        drawMod.all(S, widgetDefs) end
  local function drawTopBar()     drawMod.topBar(S) end
  local function drawRail()       drawMod.rail(S) end
  local function drawSumRail()    drawMod.sumRail(S) end
  local function drawFileList()   drawMod.fileList(S) end
  local function drawOutRow(text, color) drawMod.outRow(S, text, color) end
  local function drawOutLines()   drawMod.outLines(S) end

  local function drawOutputArea()
    if S.outLines and #S.outLines > 0 then drawOutLines()
    elseif S.lastOut then drawOutRow(S.lastOut[1], S.lastOut[2])
    elseif homeMod.isTiles(S) then

      local t = S.tabs[S.activeTab]
      local txt, ts, te = homeMod.hintText(S, t)
      drawOutRow(txt, S.T.dim)
      homeMod.markToggle(S, S.OUT_ROW, ts, te)
    else drawOutRow(nil) end
  end
  local function drawCmdRow()     drawMod.cmdRow(S) end
  local function drawStatusBar()  drawMod.statusBar(S, widgetDefs) end
  local function drawViewTab(tab) drawMod.viewTab(S, tab) end
  local function drawEditTab(tab) drawMod.editTab(S, tab) end
  local function drawMenuDropdown() drawMod.menuDropdown(S) end
  local function drawContextMenu()  drawMod.contextMenu(S) end

  local function closeTab(idx)    return tabsMod.close(S, idx) end
  local function cycleTab(dir)    return tabsMod.cycle(S, dir) end
  local function selPath()        return helpers.selPath(S) end
  local function canRead(p, o)    return helpers.canRead(S, p, o) end
  local function canWrite(p, o)   return helpers.canWrite(S, p, o) end
  local function refreshBrowser() return helpers.refreshBrowser(S) end
  local function openViewTab(buf, label) return editorMod.openViewTab(S, buf, label) end
  local function openContextMenu() return ctxMod.open(S) end

  local function viewSelected()
    local fpath, f = selPath()
    if not (fpath and f) or f.dir then return end
    if not canRead(fpath) then return end
    local content = F.readFile(fpath)
    if not content then S.lastOut = { "Cannot read: " .. f.name, T.error }; return end
    local vbuf = { { " Viewing: " .. f.name, T.title } }
    for l in content:gmatch("([^\n]*)\n?") do vbuf[#vbuf + 1] = { l, T.fg } end
    openViewTab(vbuf, f.name)
  end
  local function navigateUp()     return fbMod.navigateUp(S) end
  local function navigateInto(d)  return fbMod.navigateInto(S, d) end
  local function doCopy()         return fbMod.doCopy(S) end
  local function doMove()         return fbMod.doMove(S) end
  local function doMkdir()        return fbMod.doMkdir(S) end
  local function doDelete()       return fbMod.doDelete(S) end
  local function promptInput(msg, maxLen, isPw) return dialogsMod.promptInput(S, msg, maxLen, isPw) end
  local function promptSearch(term) return dialogsMod.promptSearch(S, term) end
  local function expandBuf(buf)   return helpers.expandBuf(S, buf) end

  local function shiftHeld()
    return keysMod.modDown(S.mods, "shift", computer.uptime())
  end
  local function isAction(name, ch, co)
    return keysMod.is(name, ch, co, S.who, S.mods)
  end
  local function clipSeat() return S.displayIdx end

  local function noteClip(verb)
    S.lastOut = { verb .. ": " .. clipMod.describe(clipSeat()), T.dim }
  end

  local function cmdMove(newCur)
    local cur = S.cmdCursor or (#S.cmdline + 1)
    newCur = math.max(1, math.min(#S.cmdline + 1, newCur))
    if shiftHeld() then
      if not S.cmdSel then S.cmdSel = cur end
      if S.cmdSel == newCur then S.cmdSel = nil end
    else
      S.cmdSel = nil
    end
    S.cmdCursor = newCur
  end

  local function cmdDropSel()
    local cut, _, at = selMod.remove(S.cmdline, S.cmdSel, S.cmdCursor)
    S.cmdline = cut
    S.cmdCursor = at or S.cmdCursor
    S.cmdSel = nil
    return S.cmdCursor
  end

  local function cmdClipboard(ch, co)
    if isAction("copy", ch, co) then
      local text = selMod.text(S.cmdline, S.cmdSel, S.cmdCursor)
      if not text and S.cmdline ~= "" then text = S.cmdline end
      if not text then

        local fpath = (not homeMod.isTiles(S)) and selPath() or nil
        if fpath then
          clipMod.set(fpath, clipSeat())
          S.lastOut = { "Copied path: " .. fpath, T.dim }
          return 1
        end
        S.lastOut = { "Nothing to copy", T.dim }
        return 1
      end
      clipMod.set(text, clipSeat())
      noteClip("Copied")
      return 1

    elseif isAction("cut", ch, co) then
      local text = selMod.text(S.cmdline, S.cmdSel, S.cmdCursor)
      if text then
        cmdDropSel()
      elseif S.cmdline ~= "" then
        text = S.cmdline
        S.cmdline, S.cmdCursor, S.cmdSel = "", 1, nil
      else
        S.lastOut = { "Nothing to cut", T.dim }
        return 1
      end
      clipMod.set(text, clipSeat())
      noteClip("Cut")
      return 1

    elseif isAction("paste", ch, co) then
      local text = clipMod.line(clipSeat())
      if not text or text == "" then
        S.lastOut = { "Clipboard empty", T.dim }
        return 1
      end
      local at = cmdDropSel()
      S.cmdline, S.cmdCursor = selMod.insert(S.cmdline, at, text)

      if clipMod.count(clipSeat()) > 1 then
        S.lastOut = { "Pasted " .. clipMod.count(clipSeat())
          .. " lines joined with spaces", T.warning }
      end
      return 1
    end
    return nil
  end

  local mouseDeps = {
    menuDefs = S.menuDefs or drawMod.menuDefs,
    menuExecute = function(item)
      return menusMod.execute(S, item.action, {
        exec = exec, drawAll = drawAll, widgetDefs = widgetDefs })
    end,
    ctxExecute = function(action) return ctxMod.execute(S, action, makeProgramEnv) end,
    openContextMenu = openContextMenu,
    viewFile        = viewSelected,
    navigateUp      = navigateUp,
    navigateInto    = navigateInto,
    closeTab        = closeTab,
    drawFileListRow = function(fi) drawMod.fileListRow(S, fi) end,

    cmdColAt        = function(x) return drawMod.cmdIndexAt(S, x) end,

    exec            = exec,
  }

  helpers.loadFiles(S, S.browser)

  pcall(function()
    local media = helpers.scanMountedMedia(F)
    if media then
      local msg = string.format('%s: "%s" -> %s', media.desc,
        media.label or "disk", media.mountPoint)
      if media.hint then msg = msg .. "   " .. media.hint end
      S.lastOut = { msg, T.highlight }
    end
  end)

  drawAll()

  local function applyDraw(level)
    if level <= 0 then return end

    if S.suspendIdleDraw then return end
    local tab = S.tabs[S.activeTab]
    if not tab or tab.type == "shell" then
      if level == 1 then
        drawTopBar()
        drawOutputArea()
        drawCmdRow()
        drawStatusBar()
      elseif level == 2 then

        if homeMod.isTiles(S, tab) then
          drawAll()
        else
          drawTopBar(); drawRail(); drawFileList(); drawSumRail()
          drawOutputArea()
          drawCmdRow(); drawStatusBar()
        end
      elseif level >= 3 then
        drawAll()
      end
      if S.menuOpen then drawMenuDropdown() end
      if S.ctxOpen then drawContextMenu() end
    elseif tab.type == "view" or tab.type == "output" then
      drawTopBar(); drawViewTab(tab)
    elseif tab.type == "edit" then
      drawTopBar(); drawEditTab(tab)
    else

      appsMod.ensureBuiltins()
      local app = appsMod.get(tab.type)
      if app and app.draw then drawTopBar(); app.draw(S, tab) end
    end
  end

  while true do

    if S._exitTo then
      local dest = S._exitTo
      S._exitTo = nil
      return dest
    end

    local sig, a2, ch, co, e5 = pullSignal()
    local draw = 0

    local isModKey = false
    if sig == "key_down" or sig == "key_up" then
      isModKey = keysMod.trackMods(S.mods, sig, ch, co, computer.uptime())
    end

    local hadOutLines       = S.outLines ~= nil
    local prevSel    = S.browser and S.browser.sel
    local prevScroll = S.browser and S.browser.scroll
    local tab = S.tabs[S.activeTab]

    if S.suspendIdleDraw and (sig == "key_down" or sig == "touch"
        or sig == "drag" or sig == "drop" or sig == "scroll"
        or sig == "clipboard" or sig == "tos_focus" or sig == "tos_monitor") then
      S.suspendIdleDraw = nil
    end

    if sig == "key_down" and not isModKey then
      if S.ctxOpen then
        if co == 200 then ctxMod.nextItem(S, -1)
        elseif co == 208 then ctxMod.nextItem(S, 1)
        elseif co == 28 then
          local item = S.ctxItems[S.ctxSel]
          if item and not item.sep then ctxMod.execute(S, item.action, makeProgramEnv) end
        elseif ch == 17 then S.ctxOpen = false end
        draw = 3
      elseif S.menuOpen then
        local menuDefs = S.menuDefs or drawMod.menuDefs
        if co == 200 then menusMod.menuNextItem(S, -1)
        elseif co == 208 then menusMod.menuNextItem(S, 1)
        elseif co == 28 then
          local item = menuDefs[S.menuOpen].items[S.menuSel]
          if item and not item.sep then
            local result = menusMod.execute(S, item.action, {
              exec = exec, drawAll = drawAll, widgetDefs = widgetDefs })
            if result then return result end
          end
        elseif ch == 17 then S.menuOpen = nil; S.menuFocused = false
        elseif co == 203 then S.menuOpen = S.menuOpen > 1 and S.menuOpen - 1 or #menuDefs; S.menuSel = 1
        elseif co == 205 then S.menuOpen = S.menuOpen < #menuDefs and S.menuOpen + 1 or 1; S.menuSel = 1
        end
        draw = 3
      elseif S.menuFocused then
        local menuDefs = S.menuDefs or drawMod.menuDefs
        if co == 203 then S.menuIdx = S.menuIdx > 1 and S.menuIdx - 1 or #menuDefs
        elseif co == 205 then S.menuIdx = S.menuIdx < #menuDefs and S.menuIdx + 1 or 1
        elseif co == 28 then S.menuOpen = S.menuIdx; S.menuSel = 1
        elseif ch == 17 then S.menuFocused = false end
        draw = 3
      else
        local handled = false

        if homeMod.isViewKey(S, ch, co) then
          if homeMod.enabled(S) then
            if tab and (tab.type == nil or tab.type == "shell") then
              homeMod.toggle(S, tab)
            else
              for i, t2 in ipairs(S.tabs) do
                if t2.type == "shell" then S.activeTab = i; break end
              end
            end
          else
            cycleTab(1)
          end
          draw = 3; handled = true
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

          D.set(1, S.OUT_ROW, (" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode [^Q]Cancel"):sub(1, W), T.title, T.bg)
          while true do
            local s2, _, c2 = pullSignal()
            if s2 == "key_down" then
              if c2 == 49 or c2 == 50 then
                local okPwr, reason = helpers.canPowerOff(S)
                if not okPwr then
                  D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
                  D.set(1, S.OUT_ROW, reason:sub(1, W), T.error, T.bg)
                else
                  if _G._TOS.audio then _G._TOS.audio.shutdown() end
                  if c2 == 49 then K.reboot() else K.shutdown() end
                  return "exit"
                end
              elseif c2 == 51 then if _G._TOS.audio then _G._TOS.audio.shutdown() end; helpers.logout(S); return "exit"
              elseif c2 == 52 then return "cli"
              elseif c2 == 17 then S.lastOut = nil; break end
            end
          end
          draw = 3; handled = true
        end

        if not handled and tab then
          if tab.type == "shell" then

            local tiles = homeMod.isTiles(S, tab)

            local clipDraw = cmdClipboard(ch, co)

            local selDraw = nil
            if not clipDraw and shiftHeld() and S.cmdline ~= "" then
              local cur = S.cmdCursor or (#S.cmdline + 1)
              if co == 203 then cmdMove(cur - 1); selDraw = 1
              elseif co == 205 then cmdMove(cur + 1); selDraw = 1
              elseif co == 199 then cmdMove(1); selDraw = 1
              elseif co == 207 then cmdMove(#S.cmdline + 1); selDraw = 1
              end
            end

            local hDraw, hResult
            if not clipDraw and not selDraw and tiles then
              hDraw, hResult = homeMod.handleKey(S, tab, ch, co, { exec = exec })
            end
            if clipDraw then
              draw = clipDraw
            elseif selDraw then
              draw = selDraw
            elseif hDraw ~= nil then
              if hResult == "exit" then return hResult end
              draw = hDraw
            elseif co == KEYS.help then
              local hbuf = {}; local function ho(t2, c2) hbuf[#hbuf+1] = {t2, c2} end
              C.help({}, ho)
              local helpIdx = nil
              for i, t2 in ipairs(S.tabs) do
                if t2.label == "Help" and t2.type == "view" then helpIdx = i; break end
              end
              if helpIdx then S.tabs[helpIdx].content = expandBuf(hbuf); S.tabs[helpIdx].offset = 0; S.activeTab = helpIdx
              else openViewTab(hbuf, "Help") end
              draw = 3

            elseif not tiles and co == KEYS.viewFile then
              viewSelected()
              draw = 3
            elseif not tiles and co == KEYS.copy then doCopy(); draw = 3
            elseif not tiles and co == KEYS.move then doMove(); draw = 3
            elseif not tiles and co == KEYS.mkdir then doMkdir(); draw = 3
            elseif not tiles and co == KEYS.delete then doDelete(); draw = 3
            elseif co == 200 and not tiles then
              if S.browser.sel > 1 then
                local prevSel = S.browser.sel
                local prevScroll = S.browser.scroll
                S.browser.sel = prevSel - 1
                if S.browser.sel <= S.browser.scroll then S.browser.scroll = S.browser.sel - 1 end
                if S.browser.scroll == prevScroll then
                  drawMod.fileListRow(S, prevSel); drawMod.fileListRow(S, S.browser.sel); draw = 0
                else draw = 2 end
              else draw = 0 end
            elseif co == 208 and not tiles then
              if S.browser.sel < #S.browser.files then
                local prevSel = S.browser.sel
                local prevScroll = S.browser.scroll
                S.browser.sel = prevSel + 1
                if S.browser.sel > S.browser.scroll + S.LIST_H then S.browser.scroll = S.browser.sel - S.LIST_H end
                if S.browser.scroll == prevScroll then
                  drawMod.fileListRow(S, prevSel); drawMod.fileListRow(S, S.browser.sel); draw = 0
                else draw = 2 end
              else draw = 0 end
            elseif co == 201 then S.browser.sel = math.max(1, S.browser.sel - S.LIST_H); S.browser.scroll = math.max(0, S.browser.scroll - S.LIST_H); draw = 2
            elseif co == 209 then S.browser.sel = math.min(#S.browser.files, S.browser.sel + S.LIST_H); S.browser.scroll = math.min(math.max(0, #S.browser.files - S.LIST_H), S.browser.scroll + S.LIST_H); draw = 2
            elseif co == 203 then

              if S.cmdline ~= "" then cmdMove((S.cmdCursor or (#S.cmdline + 1)) - 1); draw = 1 end
            elseif co == 205 then

              if S.cmdline ~= "" then cmdMove((S.cmdCursor or (#S.cmdline + 1)) + 1); draw = 1 end
            elseif co == 199 then

              if S.cmdline ~= "" then cmdMove(1); draw = 1
              else S.browser.sel = 1; S.browser.scroll = 0; draw = 2 end
            elseif co == 207 then
              if S.cmdline ~= "" then cmdMove(#S.cmdline + 1); draw = 1
              else S.browser.sel = #S.browser.files; S.browser.scroll = math.max(0, #S.browser.files - S.LIST_H); draw = 2 end
            elseif co == 14 then
              local cur = S.cmdCursor or (#S.cmdline + 1)
              if S.cmdSel then

                cmdDropSel(); draw = 1
              elseif cur > 1 then

                S.cmdline = S.cmdline:sub(1, cur - 2) .. S.cmdline:sub(cur)
                S.cmdCursor = cur - 1; draw = 1
              elseif S.cmdline == "" and not tiles then navigateUp(); draw = 3 end
            elseif co == 211 and S.cmdSel then
              cmdDropSel(); draw = 1
            elseif co == 211 then

              local cur = S.cmdCursor or (#S.cmdline + 1)
              if cur <= #S.cmdline then S.cmdline = S.cmdline:sub(1, cur - 1) .. S.cmdline:sub(cur + 1); draw = 1 end
            elseif co == 28 then
              if S.cmdline ~= "" then
                local input = S.cmdline; S.cmdline = ""; S.cmdCursor = 1; S.cmdHistIdx = 0; S.cmdSel = nil

                local lowInput = input:lower()
                local containsSecret =
                  lowInput:find("trust setsecret", 1, true) or
                  lowInput:find("trust generatesecret", 1, true) or
                  lowInput:find("changepass ", 1, true) or
                  lowInput:find("usermod ", 1, true) and lowInput:find(" pass", 1, true)
                if not containsSecret then

                  local HIST_MAX = 200
                  if #S.cmdHistory == 0 or S.cmdHistory[#S.cmdHistory] ~= input then
                    S.cmdHistory[#S.cmdHistory + 1] = input
                    if #S.cmdHistory > HIST_MAX then
                      table.remove(S.cmdHistory, 1)
                    end
                  end
                end

                S.outLines = nil
                local first = (input:match("^(%S+)") or ""):lower()
                local F = S.F
                local function willRunProgram(name)
                  if name == "" or (C and C[name]) then return false end
                  local okP, pkgMod = pcall(require, "kernel.pkg")
                  if okP and pkgMod and pkgMod.getCommand and pkgMod.getCommand(name) then return true end
                  if F and F.exists and F.join then
                    for _, dir in ipairs({ "/bin", "/usr/bin", "/tos/shell" }) do
                      if F.exists(F.join(dir, name .. ".lua")) or F.exists(F.join(dir, name)) then return true end
                    end
                  end
                  return false
                end
                if willRunProgram(first) then
                  drawOutRow("Running " .. first .. "\226\128\166", T.dim)
                end
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
              S.cmdline = ""; S.cmdCursor = 1; S.cmdSel = nil
              if S.clipboard then S.clipboard = nil; S.lastOut = { "Copy cancelled", T.dim }; draw = 3
              else S.lastOut = nil; draw = 1 end

            elseif ch == 16 and co ~= 200 then
              if S.cmdHistIdx == 0 then S.cmdHistIdx = #S.cmdHistory
              elseif S.cmdHistIdx > 1 then S.cmdHistIdx = S.cmdHistIdx - 1 end
              if S.cmdHistIdx > 0 then S.cmdline = S.cmdHistory[S.cmdHistIdx] end
              S.cmdCursor = #S.cmdline + 1; S.cmdSel = nil; draw = 1
            elseif ch == 14 and co ~= 14 then
              if S.cmdHistIdx < #S.cmdHistory then S.cmdHistIdx = S.cmdHistIdx + 1; S.cmdline = S.cmdHistory[S.cmdHistIdx]
              else S.cmdHistIdx = 0; S.cmdline = "" end
              S.cmdCursor = #S.cmdline + 1; S.cmdSel = nil; draw = 1
            elseif co == 15 and S.cmdline == "" and homeMod.enabled(S) then

              cycleTab(1); draw = 3
            elseif co == 15 then

              local okCm, commandsMod = pcall(require, "shell.panels.commands")
              local cmds = (okCm and commandsMod.commandNames) and commandsMod.commandNames() or {}

              local okP, pkgMod = pcall(require, "kernel.pkg")
              if okP and pkgMod and pkgMod.commands then
                local okL, list = pcall(pkgMod.commands)
                if okL and type(list) == "table" then
                  for n in pairs(list) do cmds[#cmds + 1] = n end
                end
              end
              local cwd = S.cwd or (S.browser and S.browser.path) or "/"
              local function listDir(dirPart)
                local dir = (dirPart:sub(1, 1) == "/") and dirPart
                  or (dirPart == "" and cwd or F.join(cwd, dirPart))
                local out = {}
                local ok, list = pcall(F.list, dir)
                if ok and list then
                  local names = {}
                  if type(list) == "table" then names = list
                  elseif type(list) == "function" then for n in list do names[#names + 1] = n end end
                  for _, n in ipairs(names) do
                    local clean = n:gsub("/$", "")
                    local isDir = n:sub(-1) == "/"
                    if not isDir then
                      local okD, dd = pcall(F.isDirectory, F.join(dir, clean)); isDir = okD and dd
                    end
                    out[#out + 1] = { name = clean, dir = isDir }
                  end
                end
                return out
              end
              local newCl, matches = helpers.completeCmdline(S.cmdline, cmds, listDir)
              if newCl ~= S.cmdline then S.cmdline = newCl; S.cmdHistIdx = 0 end
              S.cmdCursor = #S.cmdline + 1
              if #matches > 1 then
                S.outLines = nil
                S.lastOut = { (#matches .. " matches: " .. table.concat(matches, "  ")):sub(1, W), T.dim }
              end
              draw = 1
            elseif ch and ch >= 32 and ch < 127 then

              local cur = S.cmdSel and cmdDropSel() or (S.cmdCursor or (#S.cmdline + 1))
              S.cmdline = S.cmdline:sub(1, cur - 1) .. string.char(ch) .. S.cmdline:sub(cur)
              S.cmdCursor = cur + 1; S.cmdHistIdx = 0; draw = 1
            end

          elseif tab.type == "view" or tab.type == "output" then
            local content = tab.content or {}; local viewH = H - 2

            local function viewSelStep(delta)
              local cur = tab.selCur or (tab.offset + 1)
              local nxt = math.max(1, math.min(#content, cur + delta))
              if not tab.selAnchor then tab.selAnchor = cur end
              tab.selCur = nxt

              if nxt <= tab.offset then tab.offset = math.max(0, nxt - 1)
              elseif nxt > tab.offset + viewH then tab.offset = nxt - viewH end
            end

            if ch == 17 or ch == 113 then closeTab(); draw = 3
            elseif isAction("copy", ch, co) then
              local block = selMod.lines(content, tab.selAnchor, tab.selCur)
              if not block then

                block = selMod.lines(content, tab.offset + 1, tab.offset + 1)
              end
              if block then
                clipMod.set(block, clipSeat()); noteClip("Copied")
              else S.lastOut = { "Nothing to copy", T.dim } end
              draw = 3
            elseif shiftHeld() and co == 200 then viewSelStep(-1); draw = 3
            elseif shiftHeld() and co == 208 then viewSelStep(1); draw = 3
            elseif co == 200 or co == 208 or co == 201 or co == 209
                or co == 199 or co == 207 then

              tab.selAnchor, tab.selCur = nil, nil
              if co == 200 and tab.offset > 0 then tab.offset = tab.offset - 1; draw = 1
              elseif co == 208 and tab.offset + viewH < #content then tab.offset = tab.offset + 1; draw = 1
              elseif co == 201 then tab.offset = math.max(0, tab.offset - viewH); draw = 1
              elseif co == 209 then tab.offset = math.min(math.max(0, #content - viewH), tab.offset + viewH); draw = 1
              elseif co == 199 then tab.offset = 0; draw = 1
              elseif co == 207 then tab.offset = math.max(0, #content - viewH); draw = 1
              else draw = 1 end
            elseif tab.live and (ch == 114 or ch == 82) then
              editorMod.refreshLiveTab(S, tab); tab.lastRefresh = computer.uptime(); draw = 3
            elseif ch == 6 then
              local term = promptSearch(tab.searchTerm); tab.searchTerm = term
              if term then for i = tab.offset + 1, #content do
                local e = content[i]; local txt = type(e) == "table" and e[1] or tostring(e)
                if txt:find(term, 1, true) then tab.offset = math.max(0, i - 1); break end
              end end; draw = 3
            end

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

            local edClip = nil
            local herePos = { row = tab.curRow, col = tab.curCol }
            if isAction("copy", ch, co) then
              local block = selMod.extract(lines, tab.selAnchor, herePos)
                            or { lines[tab.curRow] }
              clipMod.set(block, clipSeat())
              noteClip("Copied")
              edClip = 1
            elseif isAction("cut", ch, co) then
              pushUndo()
              local block = selMod.extract(lines, tab.selAnchor, herePos)
              if block then
                local _, r, c = selMod.removeBlock(lines, tab.selAnchor, herePos)
                tab.curRow, tab.curCol = r, c
                tab.selAnchor = nil
              else
                block = { lines[tab.curRow] }
                if #lines > 1 then table.remove(lines, tab.curRow) else lines[1] = "" end
              end
              clipMod.set(block, clipSeat())
              tab.modified = true; clampEdit(); noteClip("Cut"); edClip = 1
            elseif isAction("paste", ch, co) then
              local block = clipMod.get(clipSeat())
              if block and #block > 0 then
                pushUndo()
                if tab.selAnchor then
                  local _, r, c = selMod.removeBlock(lines, tab.selAnchor, herePos)
                  tab.curRow, tab.curCol = r, c
                  tab.selAnchor = nil
                end
                tab.curRow, tab.curCol =
                  selMod.insertBlock(lines, tab.curRow, tab.curCol, block)
                tab.modified = true; clampEdit()
                S.lastOut = { "Pasted " .. #block .. " line(s)", T.dim }
              else S.lastOut = { "Clipboard empty", T.dim } end
              edClip = 1
            end

            local NAV_KEYS = { [200]=true, [208]=true, [203]=true, [205]=true,
                               [199]=true, [207]=true, [201]=true, [209]=true }
            if NAV_KEYS[co] then
              if shiftHeld() then
                if not tab.selAnchor then
                  tab.selAnchor = { row = tab.curRow, col = tab.curCol }
                end
              else
                tab.selAnchor = nil
              end
            end

            if edClip then draw = edClip
            elseif co == 200 then tab.curRow = tab.curRow - 1; clampEdit(); draw = 1
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
            elseif (co == 14 or co == 211) and tab.selAnchor then

              pushUndo()
              local _, r, c = selMod.removeBlock(lines, tab.selAnchor,
                                { row = tab.curRow, col = tab.curCol })
              tab.curRow, tab.curCol = r, c
              tab.selAnchor = nil; tab.modified = true; clampEdit(); draw = 1
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

                    if tab.path then
                      local normPath = (F.normalize and F.normalize(tab.path)) or tab.path
                      if canWrite(normPath) then
                        F.writeFile(normPath, table.concat(lines, "\n"))
                        refreshBrowser()
                      end
                    end
                    closeTab(); draw = 3
                  elseif c2 == 110 or c2 == 78 then closeTab(); draw = 3
                  else draw = 1 end
                end
              else closeTab(); draw = 3 end
            elseif ch == 19 then

              if tab.path then
                local normPath = (F.normalize and F.normalize(tab.path)) or tab.path
                if canWrite(normPath) then
                  if F.writeFile(normPath, table.concat(lines, "\n")) then
                    tab.path = normPath
                    tab.modified = false
                    S.lastOut = { "Saved: " .. tab.label, T.highlight }
                    refreshBrowser()
                  else S.lastOut = { "Save failed!", T.error } end
                end
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

                  local function escPat(s)
                    return (s:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"))
                  end
                  local function escRepl(s)
                    return (s:gsub("%%", "%%%%"))
                  end
                  local pat = escPat(find)
                  local rep = escRepl(repl)

                  local count = 0
                  if tab.undoStack then local snap = {}; for j, ln in ipairs(lines) do snap[j] = ln end
                    tab.undoStack[#tab.undoStack + 1] = { lines = snap, row = tab.curRow, col = tab.curCol }
                    if #tab.undoStack > (tab.undoMax or 32) then table.remove(tab.undoStack, 1) end end
                  local okRepl = true
                  for i = 1, #lines do
                    local ok, newLine, subs = pcall(string.gsub, lines[i], pat, rep, nil)
                    if not ok then okRepl = false; break end
                    if subs > 0 then lines[i] = newLine; count = count + subs end
                  end
                  if not okRepl then
                    S.lastOut = { "Replace failed (pattern error)", T.error }
                    if tab.undoStack and #tab.undoStack > 0 then tab.undoStack[#tab.undoStack] = nil end
                  elseif count > 0 then tab.modified = true; S.lastOut = { "Replaced " .. count .. " occurrence(s)", T.highlight }
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
            elseif ch and ch >= 32 and ch < 127 then

              if tab.selAnchor then
                pushUndo()
                local _, r, c = selMod.removeBlock(lines, tab.selAnchor,
                                  { row = tab.curRow, col = tab.curCol })
                tab.curRow, tab.curCol = r, c
                tab.selAnchor = nil
              end
              local l = lines[tab.curRow]; lines[tab.curRow] = l:sub(1, tab.curCol-1) .. string.char(ch) .. l:sub(tab.curCol)
              tab.curCol = tab.curCol + 1; tab.modified = true; draw = 1
            end

          else

            appsMod.ensureBuiltins()
            local app = appsMod.get(tab.type)
            if app and app.onKey then
              local dl, res = app.onKey(S, tab, { ch = ch, co = co, exec = exec })
              if res then return res end
              draw = dl or 0
            end
          end
        end
      end

    elseif sig == "touch" or sig == "drag" or sig == "drop" or sig == "scroll" then

      local mDraw, mResult = mouseMod.handle(S, mouseDeps, sig, a2, ch, co, e5)
      if mResult then return mResult end
      draw = mDraw or 0

    elseif sig == "clipboard" and type(ch) == "string" then
      if tab and tab.type == "shell" then

        local ins = ch:gsub("[\r\n]+", " ")
        local cur = S.cmdSel and cmdDropSel() or (S.cmdCursor or (#S.cmdline + 1))
        S.cmdline = S.cmdline:sub(1, cur - 1) .. ins .. S.cmdline:sub(cur)
        S.cmdCursor = cur + #ins; draw = 1
      elseif tab and tab.type == "edit" then
        local clean = ch:gsub("\n", " "):gsub("\r", ""); local l = tab.lines[tab.curRow]
        tab.lines[tab.curRow] = l:sub(1, tab.curCol-1) .. clean .. l:sub(tab.curCol)
        tab.curCol = tab.curCol + #clean; tab.modified = true; draw = 1
      end
    elseif sig == "tos_focus" then
      T = D.getTheme(); S.T = T; draw = 3

      local at = S.tabs and S.tabs[S.activeTab]
      if at and at.type == "program" then
        local shellIdx = 1
        for i, t in ipairs(S.tabs) do
          if t.type == "shell" or t.type == nil then shellIdx = i; break end
        end
        S.activeTab = shellIdx
      end
    elseif sig == "tos_monitor" then

      local okM, monMod = pcall(require, "shell.panels.monitorapp")
      if okM and monMod then
        S.menuOpen = nil; S.menuFocused = false; S.ctxOpen = false
        monMod.open(S); draw = 3
      end
    elseif sig == "tos_interrupt" then
      if tab and tab.type == "shell" then
        if S.cmdline ~= "" then S.cmdline = ""; S.cmdCursor = 1; S.cmdSel = nil; S.lastOut = { "^C", T.dim } end; draw = 1
      end
    elseif sig == "component_added" then
      local addr, ctype = a2, ch
      if ctype == "filesystem" then
        local bootAddr = _G._TOS and _G._TOS.bootFS and _G._TOS.bootFS.address
        if addr ~= bootAddr then
          local ok2, mntPath, lbl = pcall(autoMount, addr)
          if ok2 and mntPath then

            local info = helpers.classifyDisk(F, mntPath)
            local msg = string.format('%s: "%s" -> %s',
              info.desc, lbl or "disk", mntPath)
            if info.hint then msg = msg .. "   " .. info.hint end
            S.lastOut = { msg, T.highlight }
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
    elseif sig == "screen_resized" then

      local okSM, SM = pcall(require, "shell.panels.state")
      if okSM and SM and SM.recomputeLayout then pcall(SM.recomputeLayout, S) end
      pcall(refreshBrowser)
      draw = 3
    end

    if hadOutLines and S.outLines and S.browser
        and (S.browser.sel ~= prevSel or S.browser.scroll ~= prevScroll) then
      S.outLines = nil
      if draw < 2 then draw = 2 end
    end

    if hadOutLines and not S.outLines and draw < 2 then draw = 2 end
    applyDraw(draw)

    do
      local nowS = computer.uptime()
      if nowS - (S._lastSwapSweep or 0) >= 1 then
        S._lastSwapSweep = nowS
        pcall(tabsMod.sweepCold, S)
      end
    end

    do
      local nowS = computer.uptime()
      if nowS - (S._lastNotice or 0) >= 1
         and not S.suspendIdleDraw and not S.menuOpen and not S.ctxOpen then
        S._lastNotice = nowS
        local okN, nf = pcall(require, "kernel.notify")
        if okN and type(nf) == "table" then

          if S._noticeSeen == nil then S._noticeSeen = nf.highWater() end
          nf.sweep()
          local list = nf.pending(S._noticeSeen)
          local notice = nf.nextToShow(list, S._noticeShownAt)
          if notice then

            S._noticeSeen = notice.seq
            local okD, pick = pcall(dialogsMod.dialog, S, {
              style   = notice.style,

              title   = notice.title,
              message = notice.message .. "\n\nFrom: " .. notice.from,
              buttons = notice.buttons,
            })
            nf.settle(notice.id, okD and pick or 1)

            S._noticeShownAt = computer.uptime()
            drawAll()
          end
        end
      end
    end

    local curTab = S.tabs[S.activeTab]
    if S.suspendIdleDraw then

      local k = _G._TOS and _G._TOS.kernel
      if k and k.isForeground then
        local okF, fg = pcall(k.isForeground)
        if okF and fg then S.suspendIdleDraw = nil; drawAll() end
      end
    elseif curTab and (curTab.type == nil or curTab.type == "shell")
       and not S.menuOpen and not S.ctxOpen then
      local now = computer.uptime()
      if now - (S._lastStatusT or 0) >= 1 then
        S._lastStatusT = now
        drawStatusBar()

        if homeMod.isTiles(S, curTab) then homeMod.drawHeader(S, curTab) end
      end
    elseif curTab and curTab.type == "desktop"
       and not S.menuOpen and not S.ctxOpen then

      local now = computer.uptime()
      if now - (S._lastStatusT or 0) >= 1 then
        S._lastStatusT = now
        local dm = getDesktop()
        if dm then dm.drawHeader(S, curTab) end
      end
    elseif curTab and curTab.type == "view" and curTab.live
       and not S.menuOpen and not S.ctxOpen then

      local now = computer.uptime()
      if now - (curTab.lastRefresh or 0) >= (curTab.interval or 1) then
        curTab.lastRefresh = now
        editorMod.refreshLiveTab(S, curTab)
        drawMod.viewTab(S, curTab)
      end
    elseif curTab and not S.menuOpen and not S.ctxOpen then

      local app = appsMod.get(curTab.type)
      if app and app.tick then
        local now = computer.uptime()
        if now - (curTab.lastRefresh or 0) >= (curTab.interval or 2) then
          curTab.lastRefresh = now
          local dl = app.tick(S, curTab)
          if dl and dl > 0 then applyDraw(dl) end
        end
      end
    end
  end
end

return M
