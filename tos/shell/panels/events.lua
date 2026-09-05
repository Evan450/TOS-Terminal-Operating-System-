-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Main Event Loop                  ║
-- ║  Signal dispatch, input handling, draw scheduling    ║
-- ╚══════════════════════════════════════════════════════╝

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
local appsMod   = require("shell.panels.apps")   -- app-tab registry (Stage 2)
local homeMod   = require("shell.panels.home")   -- the merged Home surface
local keysMod   = require("shell.keys")           -- bindings + modifier state
local selMod    = require("shell.panels.selection")
local clipMod   = require("kernel.clipboard")
-- Desktop/Settings input + full draw now dispatch through the app registry
-- (shell.panels.apps), which lazy-loads those modules on first use — the
-- same laziness that keeps a ~230KB-free box from OOMing at shell start
-- (v1.4.0 emulator round). getDesktop stays only for the Desktop clock's
-- 1s header-only refresh (drawHeader), which isn't part of the app draw.
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
  -- 0.1s = 2 OC ticks. Anything shorter than one tick (50 ms) just busy-yields
  -- without delivering more events, so we avoid the wasted wake-ups.
  return require("computer").pullSignal(0.1)
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
  local function drawTopBar()     drawMod.topBar(S) end
  local function drawRail()       drawMod.rail(S) end
  local function drawSumRail()    drawMod.sumRail(S) end
  local function drawFileList()   drawMod.fileList(S) end
  local function drawOutRow(text, color) drawMod.outRow(S, text, color) end
  local function drawOutLines()   drawMod.outLines(S) end
  -- Draw the output area: a transient multi-line result (S.outLines) wins over
  -- the single-line status (S.lastOut), else the idle F-key hint / blank line.
  local function drawOutputArea()
    if S.outLines and #S.outLines > 0 then drawOutLines()
    elseif S.lastOut then drawOutRow(S.lastOut[1], S.lastOut[2])
    elseif homeMod.isTiles(S) then
      -- The tiles legend is not decoration: it names the selected tile
      -- and carries the only on-screen "F2 → files" affordance in this
      -- view, so a partial repaint restores it rather than blanking the
      -- row the way the F-key legend has always been happy to.
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

  -- Convenience accessors
  local function closeTab(idx)    return tabsMod.close(S, idx) end
  local function cycleTab(dir)    return tabsMod.cycle(S, dir) end
  local function selPath()        return helpers.selPath(S) end
  local function canRead(p, o)    return helpers.canRead(S, p, o) end
  local function canWrite(p, o)   return helpers.canWrite(S, p, o) end
  local function refreshBrowser() return helpers.refreshBrowser(S) end
  local function openViewTab(buf, label) return editorMod.openViewTab(S, buf, label) end
  local function openContextMenu() return ctxMod.open(S) end
  -- Primary "open" action for the selected FILE: read it into a view tab.
  -- Shared by the F3 View key and a mouse LEFT-click activation, so a click
  -- performs the quick action while RIGHT-click opens the context menu —
  -- they no longer do the same thing. Dirs/".." are navigated by the caller.
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

  -- ── Selection + clipboard ────────────────────────────────────
  -- Shared by the prompt, the editor and view buffers. The maths lives
  -- in panels/selection.lua (pure, unit-tested); what is here is only
  -- the wiring: which key means what, and what the operator is told.
  local function shiftHeld()
    return keysMod.modDown(S.mods, "shift", computer.uptime())
  end
  local function isAction(name, ch, co)
    return keysMod.is(name, ch, co, S.who, S.mods)
  end
  local function clipSeat() return S.displayIdx end

  --- Say what just went on the clipboard. Copying is silent feedback-free
  --- otherwise — nothing on screen changes — and an operator who is not
  --- sure it worked will press it again rather than trust it.
  local function noteClip(verb)
    S.lastOut = { verb .. ": " .. clipMod.describe(clipSeat()), T.dim }
  end

  --- Move the prompt cursor to `newCur`, extending the selection when
  --- Shift is held and dropping it when it isn't. One place, because
  --- "arrow without shift clears the selection" has to be true of every
  --- arrow or the selection outlives what the operator can see.
  local function cmdMove(newCur)
    local cur = S.cmdCursor or (#S.cmdline + 1)
    newCur = math.max(1, math.min(#S.cmdline + 1, newCur))
    if shiftHeld() then
      if not S.cmdSel then S.cmdSel = cur end
      if S.cmdSel == newCur then S.cmdSel = nil end   -- collapsed again
    else
      S.cmdSel = nil
    end
    S.cmdCursor = newCur
  end

  --- Drop the selection and return the cursor, for the edit paths.
  local function cmdDropSel()
    local cut, _, at = selMod.remove(S.cmdline, S.cmdSel, S.cmdCursor)
    S.cmdline = cut
    S.cmdCursor = at or S.cmdCursor
    S.cmdSel = nil
    return S.cmdCursor
  end

  --- copy / cut / paste at the prompt. Returns a draw level, or nil when
  --- the key wasn't one of them.
  local function cmdClipboard(ch, co)
    if isAction("copy", ch, co) then
      local text = selMod.text(S.cmdline, S.cmdSel, S.cmdCursor)
      if not text and S.cmdline ~= "" then text = S.cmdline end
      if not text then
        -- Nothing typed and nothing selected: copy the PATH of the file
        -- under the cursor. It is the only thing on this surface the
        -- operator could plausibly have meant, and it is the answer to
        -- "how do I get this path onto the command line" — paste it.
        -- Only in the FILES view: the browser selection still exists
        -- behind the tile grid, and copying the path of a file that is
        -- not on screen would be a silent guess.
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
      -- A multi-line clipboard arrives space-joined (kernel.clipboard
      -- explains why), which is a real edit to what they copied — say so
      -- rather than letting them run a command they did not assemble.
      if clipMod.count(clipSeat()) > 1 then
        S.lastOut = { "Pasted " .. clipMod.count(clipSeat())
          .. " lines joined with spaces", T.warning }
      end
      return 1
    end
    return nil
  end

  -- Mouse input (live only when the optional Extras mouse driver,
  -- require("mouse"), is installed — see shell.panels.mouse). The deps
  -- table hands the handler the same state-mutating closures the
  -- keyboard paths use, so click and keypress stay behavior-identical.
  local mouseDeps = {
    menuDefs = S.menuDefs or drawMod.menuDefs,
    menuExecute = function(item)
      return menusMod.execute(S, item.action, {
        exec = exec, drawAll = drawAll, widgetDefs = widgetDefs })
    end,
    ctxExecute = function(action) return ctxMod.execute(S, action, makeProgramEnv) end,
    openContextMenu = openContextMenu,
    viewFile        = viewSelected,   -- left-click quick action (open/view)
    navigateUp      = navigateUp,
    navigateInto    = navigateInto,
    closeTab        = closeTab,
    drawFileListRow = function(fi) drawMod.fileListRow(S, fi) end,
    -- Screen column -> command-line index, computed by the same function
    -- that laid the prompt out, so a click lands on the character the
    -- operator is pointing at even when the line is scrolled sideways.
    cmdColAt        = function(x) return drawMod.cmdIndexAt(S, x) end,
    -- Desktop / Settings tabs dispatch tile+row activations through the
    -- same executor as the keyboard paths.
    exec            = exec,
  }

  -- Initialize
  helpers.loadFiles(S, S.browser)

  -- Announce media that was already mounted at boot. The hot-plug
  -- auto-detect (component_added, below) only fires on INSERT, so a disk
  -- present at startup would go unnoticed; surface the first actionable one
  -- on the status row so e.g. an Optional Utilities disk gets seen.
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
    -- Something else owns the screen (a handed-off full-screen program,
    -- or the monitor-tab switch). This shell keeps ticking in the
    -- background on nil resumes; painting now would trash the program.
    -- tos_focus clears the flag ABOVE this call, so the repaint that
    -- brings us back still lands.
    if S.suspendIdleDraw then return end
    local tab = S.tabs[S.activeTab]
    if not tab or tab.type == "shell" then
      if level == 1 then
        drawTopBar()
        drawOutputArea()
        drawCmdRow()
        drawStatusBar()
      elseif level == 2 then
        -- Level 2 is the FILE LIST fast path (repaint the list without a
        -- full frame). The tiles view has no such path and never asks for
        -- one; fall back to a whole frame rather than painting the file
        -- rail over the tile grid if some future edit ever does.
        if homeMod.isTiles(S, tab) then
          drawAll()
        else
          drawTopBar(); drawRail(); drawFileList(); drawSumRail()
          drawOutputArea()
          drawCmdRow(); drawStatusBar()
        end
      elseif level >= 3 then
        drawAll()  -- M.shell renders the output area (incl. S.outLines)
      end
      if S.menuOpen then drawMenuDropdown() end
      if S.ctxOpen then drawContextMenu() end
    elseif tab.type == "view" or tab.type == "output" then
      drawTopBar(); drawViewTab(tab)
    elseif tab.type == "edit" then
      drawTopBar(); drawEditTab(tab)
    else
      -- Registered app tab (Desktop/Settings/…): draw via the registry.
      -- ensureBuiltins is idempotent and only parses the app modules the
      -- first time a non-core tab is actually shown (preserves the lazy
      -- load that keeps tight boxes from paying for Desktop/Settings).
      appsMod.ensureBuiltins()
      local app = appsMod.get(tab.type)
      if app and app.draw then drawTopBar(); app.draw(S, tab) end
    end
  end

  while true do
    -- A command can ask the shell to hand the seat over — today only
    -- `cli`, which drops to the command-line shell. It is a FLAG rather
    -- than a return value because command bodies return nothing: they
    -- are called for their output, and threading an exit code back out
    -- through exec, the pipeline and the sudo path would touch every one
    -- of them for the sake of a single verb.
    if S._exitTo then
      local dest = S._exitTo
      S._exitTo = nil
      return dest
    end

    local sig, a2, ch, co, e5 = pullSignal()
    local draw = 0

    -- Modifier bookkeeping, before anything looks at the key. Shift+Left
    -- and Left are the same scancode with no character, so the only way
    -- to tell "extend the selection" from "move the cursor" is to have
    -- been watching the key_up/key_down of the modifier keys themselves.
    -- keys.trackMods also expires the state, so a Shift left held when
    -- the player closed the screen GUI cannot wedge the selection on.
    --
    -- A modifier press is not a keystroke: it is filtered out below
    -- rather than dispatched, or merely holding Shift would clear the
    -- last command's output and repaint the screen.
    local isModKey = false
    if sig == "key_down" or sig == "key_up" then
      isModKey = keysMod.trackMods(S.mods, sig, ch, co, computer.uptime())
    end

    -- A transient inline command result (S.outLines) overlays the file list.
    -- It should persist while you EDIT the command line (cursor moves, typing)
    -- or land a no-op click, and clear only when the BROWSER actually moves
    -- under it (so the list it covers repaints) — a new command clears it via
    -- exec. We snapshot the browser view now and decide after the handlers run.
    -- (Previously it was wiped by ANY key/touch/scroll, so moving the cursor or
    -- clicking with no mouse driver erased the last command's output.)
    local hadOutLines       = S.outLines ~= nil
    local prevSel    = S.browser and S.browser.sel
    local prevScroll = S.browser and S.browser.scroll
    local tab = S.tabs[S.activeTab]

    -- Input only ever routes to the FOREGROUND process, so any of these
    -- arriving proves the shell is back in front — lift the idle-repaint
    -- suspension a monitor-tab "switch" set (see the idle section below).
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
        -- ── The `view` action (F2 by default) ────────────────────
        -- It used to be tabNext, and tabNext used to mean "Desktop <->
        -- Shell" because those were the two tabs. They are one tab now,
        -- so F2 flips the VIEW inside it and never switches tabs — that
        -- was the whole point of merging them. Off Home it takes you TO
        -- Home rather than doing nothing, which keeps its meaning one
        -- sentence long: "show me the Home view."
        --
        -- Read through shell.keys, not a raw scancode, so an operator who
        -- rebinds `view` in /etc/keys.cfg gets it everywhere at once and
        -- every legend re-labels itself to match.
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
            cycleTab(1)   -- split mode: the pre-merge behaviour, intact
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
          -- The fourth entry used to be labelled "Shell", which told you
          -- nothing — every one of these four leaves the shell you are
          -- in. It IS the CLI, so it says so now.
          D.set(1, S.OUT_ROW, (" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode [^Q]Cancel"):sub(1, W), T.title, T.bg)
          while true do
            local s2, _, c2 = pullSignal()
            if s2 == "key_down" then
              if c2 == 49 or c2 == 50 then  -- Reboot / Off — power-off gated (#9)
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
            -- ── Home, tiles view ──────────────────────────────────
            -- The tile grid gets first refusal on selection keys; it
            -- returns nil for anything it doesn't own, and that falls
            -- through to the prompt below. Which is the contract: on a
            -- CLI-first machine every printable key belongs to the
            -- command line, so quick-launch moved to Alt+1-9 and the
            -- arrows moved off the history (^P/^N have it now).
            local tiles = homeMod.isTiles(S, tab)

            -- Clipboard first: copy/cut/paste mean the same thing in
            -- both views and must not be shadowed by the tile grid or by
            -- a file-list key that happens to share a scancode.
            local clipDraw = cmdClipboard(ch, co)

            -- Shift + a cursor key SELECTS instead of navigating. Only
            -- while there is something on the line to select — with an
            -- empty prompt these stay the browser's keys, which is what
            -- an operator holding Shift out of habit expects.
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
            -- The file-operation keys act on the FILE LIST, so they are
            -- only live while the file list is what you are looking at.
            -- Leaving F8 armed over a tile grid would let an operator
            -- delete a file they cannot see, which is the kind of thing a
            -- merged surface has to get right to be worth merging.
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
              -- Left: move the cmdline cursor while typing (no-op otherwise).
              -- cmdMove drops the selection, which is what an unshifted
              -- arrow has to mean.
              if S.cmdline ~= "" then cmdMove((S.cmdCursor or (#S.cmdline + 1)) - 1); draw = 1 end
            elseif co == 205 then
              -- Right: move the cmdline cursor while typing.
              if S.cmdline ~= "" then cmdMove((S.cmdCursor or (#S.cmdline + 1)) + 1); draw = 1 end
            elseif co == 199 then
              -- Home jumps the cmdline cursor to the start when typing; else the browser top.
              if S.cmdline ~= "" then cmdMove(1); draw = 1
              else S.browser.sel = 1; S.browser.scroll = 0; draw = 2 end
            elseif co == 207 then
              if S.cmdline ~= "" then cmdMove(#S.cmdline + 1); draw = 1
              else S.browser.sel = #S.browser.files; S.browser.scroll = math.max(0, #S.browser.files - S.LIST_H); draw = 2 end
            elseif co == 14 then
              local cur = S.cmdCursor or (#S.cmdline + 1)
              if S.cmdSel then
                -- With a selection, Backspace deletes THE SELECTION. Every
                -- editor on earth does this and an operator who selected
                -- something first is telling you what they meant.
                cmdDropSel(); draw = 1
              elseif cur > 1 then
                -- Backspace deletes the char BEFORE the cursor (not the line tail).
                S.cmdline = S.cmdline:sub(1, cur - 2) .. S.cmdline:sub(cur)
                S.cmdCursor = cur - 1; draw = 1
              elseif S.cmdline == "" and not tiles then navigateUp(); draw = 3 end
            elseif co == 211 and S.cmdSel then
              cmdDropSel(); draw = 1
            elseif co == 211 then
              -- Delete removes the char AT the cursor (forward delete).
              local cur = S.cmdCursor or (#S.cmdline + 1)
              if cur <= #S.cmdline then S.cmdline = S.cmdline:sub(1, cur - 1) .. S.cmdline:sub(cur + 1); draw = 1 end
            elseif co == 28 then
              if S.cmdline ~= "" then
                local input = S.cmdline; S.cmdline = ""; S.cmdCursor = 1; S.cmdHistIdx = 0; S.cmdSel = nil
                -- #SEC M5 — don't record commands that carry secret material.
                -- `net trust setSecret <hex>` and friends would otherwise sit
                -- plain in S.cmdHistory and remain accessible to anyone with
                -- access to the same seat via Up-arrow.
                local lowInput = input:lower()
                local containsSecret =
                  lowInput:find("trust setsecret", 1, true) or
                  lowInput:find("trust generatesecret", 1, true) or
                  -- `pkg trust key` no longer ACCEPTS a passphrase on the
                  -- command line, but someone who learned the old form
                  -- will type it once before finding that out, and by then
                  -- the line already exists. Keep it out of the recall
                  -- buffer; the refusal cannot un-type it.
                  lowInput:find("trust key ", 1, true) or
                  lowInput:find("changepass ", 1, true) or
                  lowInput:find("usermod ", 1, true) and lowInput:find(" pass", 1, true)
                if not containsSecret then
                  -- #SEC L (history dedup) — skip consecutive duplicates
                  -- (already done) AND cap total entries so a heavy
                  -- user doesn't accumulate thousands.
                  local HIST_MAX = 200
                  if #S.cmdHistory == 0 or S.cmdHistory[#S.cmdHistory] ~= input then
                    S.cmdHistory[#S.cmdHistory + 1] = input
                    if #S.cmdHistory > HIST_MAX then
                      table.remove(S.cmdHistory, 1)
                    end
                  end
                end
                -- Live feedback: show the command is RUNNING before it blocks,
                -- so a slow script/network command doesn't look frozen. Only do
                -- this for an actual PROGRAM (a /usr/bin script or a package
                -- command) — NOT for instant builtins (they render their own
                -- result) and NOT for unknown commands (which should just error,
                -- not flash "Running test…" first). Mirrors the executor's own
                -- resolution order so it announces exactly what will run.
                S.outLines = nil
                local first = (input:match("^(%S+)") or ""):lower()
                local F = S.F
                local function willRunProgram(name)
                  if name == "" or (C and C[name]) then return false end  -- builtin/empty
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
            -- ── Command history: ^P / ^N ──────────────────────────
            -- It used to be Up/Down "while the line is not empty", which
            -- made the arrows mean two things and made WHICH one depend
            -- on invisible state. The merged surface can't afford that:
            -- the arrows drive the selection in whichever view is up, and
            -- there is no focus mode to learn because the prompt never
            -- competes for them. ^P/^N are the readline names for the
            -- same pair, so the muscle memory that matters is preserved.
            -- (Guarded on `co` because ^N arrives as ch 14 and Backspace
            -- as SCANCODE 14 — the same number in two different fields.)
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
              -- Tab on an EMPTY line cycles tabs. F2 used to, and the
              -- merge took F2 for the view; Tab is what the design drew
              -- in its place, and the split is unambiguous because Tab's
              -- other job — completion — needs something to complete.
              -- Merged mode only: split mode still has F2 for this, and
              -- "the pre-merge behaviour" should mean exactly that.
              cycleTab(1); draw = 3
            elseif co == 15 then
              -- Tab: complete the command (first word) or a path (later args).
              -- Single match → filled in (+ space / "/"); several → fill the
              -- common prefix and list the matches on the status row.
              local okCm, commandsMod = pcall(require, "shell.panels.commands")
              local cmds = (okCm and commandsMod.commandNames) and commandsMod.commandNames() or {}
              -- Also offer installed package commands (mousetest, tetris, …),
              -- which aren't in the static builtin registry.
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
              -- Insert the typed char AT the cursor (not always at the end),
              -- replacing the selection if there is one.
              local cur = S.cmdSel and cmdDropSel() or (S.cmdCursor or (#S.cmdline + 1))
              S.cmdline = S.cmdline:sub(1, cur - 1) .. string.char(ch) .. S.cmdline:sub(cur)
              S.cmdCursor = cur + 1; S.cmdHistIdx = 0; draw = 1
            end

          elseif tab.type == "view" or tab.type == "output" then
            local content = tab.content or {}; local viewH = H - 2
            -- Selection in a READ-ONLY buffer is whole lines: there is no
            -- cursor here, so "line 12 to line 30" is the only granularity
            -- the surface can honestly offer — and copying a run of a
            -- command's output is the thing anyone actually wants from a
            -- scrollback. Shift+Up/Down grows it, copy takes it, and there
            -- is no cut or paste because there is nothing to write back to.
            local function viewSelStep(delta)
              local cur = tab.selCur or (tab.offset + 1)
              local nxt = math.max(1, math.min(#content, cur + delta))
              if not tab.selAnchor then tab.selAnchor = cur end
              tab.selCur = nxt
              -- Follow the selection if it walks off the visible window.
              if nxt <= tab.offset then tab.offset = math.max(0, nxt - 1)
              elseif nxt > tab.offset + viewH then tab.offset = nxt - viewH end
            end

            if ch == 17 or ch == 113 then closeTab(); draw = 3
            elseif isAction("copy", ch, co) then
              local block = selMod.lines(content, tab.selAnchor, tab.selCur)
              if not block then
                -- Nothing selected: copy the line at the top of the
                -- window rather than refusing. It is what is under the
                -- operator's eye and it beats "select something first".
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
              -- Any unshifted movement drops the selection, same rule as
              -- the prompt and the editor.
              tab.selAnchor, tab.selCur = nil, nil
              if co == 200 and tab.offset > 0 then tab.offset = tab.offset - 1; draw = 1
              elseif co == 208 and tab.offset + viewH < #content then tab.offset = tab.offset + 1; draw = 1
              elseif co == 201 then tab.offset = math.max(0, tab.offset - viewH); draw = 1
              elseif co == 209 then tab.offset = math.min(math.max(0, #content - viewH), tab.offset + viewH); draw = 1
              elseif co == 199 then tab.offset = 0; draw = 1
              elseif co == 207 then tab.offset = math.max(0, #content - viewH); draw = 1
              else draw = 1 end
            elseif tab.live and (ch == 114 or ch == 82) then    -- r/R: refresh a live tab now
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

              --! Horizontal scrolling is decided in draw.lua, which is
              --! the only place that knows the gutter width and the
              --! current screen width. Deliberately NOT duplicated here.
            end
            local function pushUndo()
              if not tab.undoStack then tab.undoStack = {} end
              local snap = {}; for j, ln in ipairs(lines) do snap[j] = ln end
              tab.undoStack[#tab.undoStack + 1] = { lines = snap, row = tab.curRow, col = tab.curCol }
              if #tab.undoStack > (tab.undoMax or 32) then table.remove(tab.undoStack, 1) end
            end

            -- ── Clipboard, BEFORE the movement chain ───────────
            -- Order matters and this is why: Shift+Delete is `cut`, and
            -- Delete is also the plain forward-delete two dozen lines
            -- down. Whichever is tested first wins, and if it is the
            -- delete branch then Shift+Delete removes the selection
            -- WITHOUT copying it — the operator loses the text and the
            -- clipboard never sees it.
            --
            -- These used to be ^C / ^X / ^V against a private
            -- `S.editClipboard` of whole LINES, and ^C among them never
            -- fired once: kernel/init.lua consumes char 3 to interrupt
            -- the foreground process and blanks the signal, so the
            -- editor's advertised "Ctrl+C = copy line" was dead the day
            -- it was written. Copy is Ctrl+Insert now — the reason DOS
            -- used it too — and all three work on a SELECTION, falling
            -- back to the whole line when there isn't one so the old
            -- muscle memory still does the old thing.
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

            -- Selection bookkeeping for every cursor move below. Shift
            -- sets the anchor once and keeps it; an unshifted cursor key
            -- drops it. Done ONCE here rather than in each of the eight
            -- movement branches, which is how the prompt's version of
            -- this used to grow an inconsistency per branch.
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
              -- Backspace or Delete over a selection removes THE
              -- SELECTION, not one character next to it.
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
                    -- #SEC H8 — re-check at save (see ch==19 branch).
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
              -- #SEC H8 — re-normalize + re-check write access AT save
              -- time. Between `edit /home/alice/x` being typed and the
              -- save firing, alice could have been demoted, the path
              -- could have been symlink-swapped, etc. Re-checking
              -- closes the TOCTOU window between open and save.
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
                  -- #SEC H30 — guard against malformed/over-aggressive
                  -- patterns. `Find: .  Replace: foo` would gsub every
                  -- char in the file with "foo" — almost never the
                  -- user's intent and a hand-grenade if they meant a
                  -- literal dot. Use plain-string match: escape Lua
                  -- pattern magic chars in `find`, and escape `%` in
                  -- `repl` so back-references can't fire accidentally.
                  -- A power user can paste a regex into a future
                  -- "advanced replace" prompt if we add one.
                  local function escPat(s)
                    return (s:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"))
                  end
                  local function escRepl(s)
                    return (s:gsub("%%", "%%%%"))
                  end
                  local pat = escPat(find)
                  local rep = escRepl(repl)
                  -- Also pcall-guard the actual gsub so even an edge
                  -- case (e.g. an enormous line) drops a readable
                  -- error instead of crashing the panels event loop.
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
              -- Typing over a selection replaces it.
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
            -- Any other tab type is a registered app (Desktop, Settings,
            -- and — as later stages land — Monitor/Chat/Mail). Dispatch the
            -- key to its onKey; the (draw, result) contract is unchanged.
            appsMod.ensureBuiltins()
            local app = appsMod.get(tab.type)
            if app and app.onKey then
              local dl, res = app.onKey(S, tab, { ch = ch, co = co, exec = exec })
              if res then return res end
              draw = dl or 0
            end
          end -- tab type
        end -- not handled
      end -- priority

    elseif sig == "touch" or sig == "drag" or sig == "drop" or sig == "scroll" then
      -- Mouse signals: routed through the optional userspace mouse
      -- driver. Ignored (as always) when the driver isn't installed.
      -- Touch tuple: (name, screenAddr, x, y, button, player).
      local mDraw, mResult = mouseMod.handle(S, mouseDeps, sig, a2, ch, co, e5)
      if mResult then return mResult end
      draw = mDraw or 0

    elseif sig == "clipboard" and type(ch) == "string" then
      if tab and tab.type == "shell" then
        -- The PLAYER's clipboard (an OC signal), not TOS's own. It
        -- replaces a selection like any other insertion. Newlines become
        -- SPACES rather than vanishing: stripping them glued "ls" and
        -- "cd" into "lscd", which is a command nobody typed.
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
      -- We just got the seat back. If the ACTIVE tab is the program that
      -- was holding it (Ctrl+B, or the program exited), move off it —
      -- otherwise the repaint below would call its `draw`, which hands
      -- the seat straight back and the operator can never leave.
      local at = S.tabs and S.tabs[S.activeTab]
      if at and at.type == "program" then
        local shellIdx = 1
        for i, t in ipairs(S.tabs) do
          if t.type == "shell" or t.type == nil then shellIdx = i; break end
        end
        S.activeTab = shellIdx
      end
    elseif sig == "tos_monitor" then
      -- Ctrl+T (kernel hotkey): open/focus the System Monitor tab. The
      -- kernel already put this shell in the foreground. Close any open
      -- menu/context overlay first — those route keys BEFORE the app
      -- dispatch, so leaving them "open" would show the Monitor while
      -- the keyboard still drove an invisible menu.
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
            -- Auto-detect & guide on insert: classify the disk and surface
            -- the one most useful next step, instead of a bare "inserted".
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
      -- Somebody added or broke a screen block. Every layout constant is
      -- derived from S.H — SUM_ROW, OUT_ROW, CMD_ROW, STAT_ROW and LIST_H all
      -- count back from it — so until this runs the shell is drawing to rows
      -- that may no longer exist: on a screen that shrank the status bar and
      -- the prompt are painted past the bottom edge and clipped away, which
      -- reads as both of them simply vanishing. The kernel re-syncs
      -- kernel.screen off the same signal; this is the shell's half.
      -- recomputeLayout asks the GPU directly, so it does not matter which of
      -- the two handlers runs first. (test_screen_resize.lua)
      local okSM, SM = pcall(require, "shell.panels.state")
      if okSM and SM and SM.recomputeLayout then pcall(SM.recomputeLayout, S) end
      pcall(refreshBrowser)   -- LIST_H changed, so the visible window did too
      draw = 3
    end

    -- Clear the inline output overlay once the browser has moved under it, so
    -- the file list it covered repaints. Editing the command line or a no-op
    -- click leaves the output in place. Floor the draw so the list is repainted.
    if hadOutLines and S.outLines and S.browser
        and (S.browser.sel ~= prevSel or S.browser.scroll ~= prevScroll) then
      S.outLines = nil
      if draw < 2 then draw = 2 end
    end
    -- ...and floor it the same way when the overlay has gone for any OTHER
    -- reason, whoever cleared it.
    --
    -- The overlay is drawn UPWARD from OUT_ROW over the bottom of the file
    -- list, so removing it means those list rows have to be repainted. Level
    -- 1 repaints the output row and nothing above it, which is enough to
    -- erase a one-line result and not nearly enough to erase a fifteen-line
    -- one. Tab-completion with an ambiguous prefix does exactly that: it
    -- clears S.outLines to make room for its "N matches:" line and asks for
    -- draw = 1, so the rows the previous command's output covered kept
    -- showing it, over the file list, until something else forced a bigger
    -- redraw. Measured at 1,119 stale cells for a 15-line result.
    --
    -- Stated here rather than at each site that clears the overlay, because
    -- the rule belongs to the overlay, not to the callers: a future handler
    -- that clears it should not have to know this. (test_shell_glass.lua)
    if hadOutLines and not S.outLines and draw < 2 then draw = 2 end
    applyDraw(draw)

    -- #REV (live status bar) — the loop blocks up to 0.1s per tick and only
    -- redraws on input, so time-based widgets (clock, uptime, free mem) sat
    -- frozen when idle. On a shell tab with no menu/context overlay open,
    -- refresh just the status bar about once a second. It's the bottom row
    -- only, so it never disturbs the command line the operator is typing.
    -- #MEM — cold view buffers are the shell's largest reclaimable heap: a
    -- `cat` of a big file keeps every line resident in a tab nobody is
    -- reading. Under memory pressure they spill to kernel.swap and page back
    -- transparently on the next read (see tabs.lua). Checked on the same ~1s
    -- idle cadence as the status bar, and a no-op when RAM is comfortable, so
    -- a roomy box never pays a disk write for this.
    do
      local nowS = computer.uptime()
      if nowS - (S._lastSwapSweep or 0) >= 1 then
        S._lastSwapSweep = nowS
        pcall(tabsMod.sweepCold, S)
      end
    end

    -- ── Notify: raise a program's dialog box in the operator's face ──
    -- The output area above the command line is polite — you see it when
    -- you look. A dialog box is not: it is centred, modal and blocks until
    -- answered. Programs that need the second kind (the Intercom's
    -- announcements, and anything else that posts to kernel.notify) can't
    -- draw one themselves — a service or a mesh handler runs where another
    -- process may own the screen. They post; THIS loop, which owns the
    -- display, raises it.
    --
    -- Three gates, all about not stealing the screen from someone:
    --   * suspendIdleDraw — another process has the seat (a backgrounded
    --     program); painting a modal over it would trash its output.
    --   * menuOpen/ctxOpen — an overlay is up and mid-interaction; the
    --     notice waits a beat rather than fighting it.
    --   * notify's own rate limits — a per-source gap, and MIN_GAP of quiet
    --     after every dismissal, which no caller can opt out of. That is
    --     what keeps "any program can interrupt you" from meaning "any
    --     program can lock you out of your keyboard".
    -- Tab-independent on purpose: an evacuation alert has to appear whether
    -- you were in the file browser, the editor or a game.
    -- Per-shell cursor (S._noticeSeen), so on a multi-seat box each seat
    -- raises each notice once instead of one seat swallowing it.
    do
      local nowS = computer.uptime()
      if nowS - (S._lastNotice or 0) >= 1
         and not S.suspendIdleDraw and not S.menuOpen and not S.ctxOpen then
        S._lastNotice = nowS
        local okN, nf = pcall(require, "kernel.notify")
        if okN and type(nf) == "table" then
          -- A shell joining mid-life starts at the high-water mark rather
          -- than replaying a backlog the operator already dealt with.
          if S._noticeSeen == nil then S._noticeSeen = nf.highWater() end
          nf.sweep()
          local list = nf.pending(S._noticeSeen)
          local notice = nf.nextToShow(list, S._noticeShownAt)
          if notice then
            -- Advance ONLY past the notice actually shown. Jumping to the
            -- queue's high-water mark here would mark every other pending
            -- notice as seen after displaying one of them, silently
            -- dropping the rest. Nothing is advanced at all when nothing
            -- was showable (quiet window / all expired), so a notice the
            -- rate limiter suppressed still gets its turn afterwards.
            S._noticeSeen = notice.seq
            local okD, pick = pcall(dialogsMod.dialog, S, {
              style   = notice.style,
              -- Name the source. An operator being interrupted is owed the
              -- answer to "by what?" alongside "about what?".
              title   = notice.title,
              message = notice.message .. "\n\nFrom: " .. notice.from,
              buttons = notice.buttons,
            })
            nf.settle(notice.id, okD and pick or 1)
            -- Stamp the quiet window AFTER the box closes, from a fresh
            -- clock. dialogs.dialog BLOCKS until answered, so stamping it
            -- beforehand would spend the operator's guaranteed keyboard
            -- time while they were still reading — an operator who took 30s
            -- to decide would get no gap at all before the next interruption.
            S._noticeShownAt = computer.uptime()
            drawAll()
          end
        end
      end
    end

    local curTab = S.tabs[S.activeTab]
    if S.suspendIdleDraw then
      -- A monitor-tab "switch" handed the screen to another process; this
      -- shell keeps ticking in the background (nil resumes), so painting
      -- anything now would trash the foreground program. Poll the kernel:
      -- when the target exits without signalling us, foreground falls back
      -- and we repaint instead of leaving the seat looking dead.
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
        -- The tiles view's header rail carries the clock the file view
        -- doesn't have room for, so it ticks on the same 1s cadence as
        -- the status bar rather than getting its own timer.
        if homeMod.isTiles(S, curTab) then homeMod.drawHeader(S, curTab) end
      end
    elseif curTab and curTab.type == "desktop"
       and not S.menuOpen and not S.ctxOpen then
      -- Desktop clock (header row only, same 1s cadence as the status bar).
      local now = computer.uptime()
      if now - (S._lastStatusT or 0) >= 1 then
        S._lastStatusT = now
        local dm = getDesktop()
        if dm then dm.drawHeader(S, curTab) end
      end
    elseif curTab and curTab.type == "view" and curTab.live
       and not S.menuOpen and not S.ctxOpen then
      -- A LIVE tab in front regenerates its content on its interval and repaints
      -- the view in place. Only the active tab ticks (backgrounded ones don't
      -- burn cycles), mirroring the status-bar refresh above.
      local now = computer.uptime()
      if now - (curTab.lastRefresh or 0) >= (curTab.interval or 1) then
        curTab.lastRefresh = now
        editorMod.refreshLiveTab(S, curTab)
        drawMod.viewTab(S, curTab)
      end
    elseif curTab and not S.menuOpen and not S.ctxOpen then
      -- A registered app with a `tick` (the Monitor's live refresh) gets
      -- the same front-tab-only idle callback, on the tab's interval.
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
