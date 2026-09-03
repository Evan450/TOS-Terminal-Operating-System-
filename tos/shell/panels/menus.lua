-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Menu Actions                     ║
-- ║  Handle menu bar item execution                      ║
-- ╚══════════════════════════════════════════════════════╝

local filebrowser = require("shell.panels.filebrowser")
local dialogs = require("shell.panels.dialogs")
local draw = require("shell.panels.draw")
local widgets = require("shell.panels.widgets")
local editor = require("shell.panels.editor")
local helpers = require("shell.panels.helpers")

local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return require("computer").pullSignal(0.05)
end

function M.execute(S, action, deps)
  local T = S.T
  local D = S.D
  local K = S.K
  local E = S.E
  local W = S.W
  local SC = S.SC
  local exec = deps.exec
  local drawAll = deps.drawAll
  local widgetDefs = deps.widgetDefs

  S.menuOpen = nil
  S.menuFocused = false

  -- #REV — modular command shortcut: any menu item with action
  -- "run:<command>" runs that command through the shell executor. This is
  -- what lets a per-user ~/.menu.cfg entry put any command in a drop-down.
  if type(action) == "string" then
    local cmd = action:match("^run:(.+)$")
    if cmd then exec(cmd); return nil end
  end

  if action == "newfile" then filebrowser.doNewFile(S)
  elseif action == "mkdir" then filebrowser.doMkdir(S)
  elseif action == "rename" then filebrowser.doRename(S)
  elseif action == "delete" then filebrowser.doDelete(S)
  elseif action == "refresh" then helpers.refreshBrowser(S)
  elseif action == "viewfile" then
    local path, f = helpers.selPath(S)
    if path and f and not f.dir and helpers.canRead(S, path) then
      local content = S.F.readFile(path)
      if content then
        local buf = { { " Viewing: " .. f.name, T.title } }
        for l in content:gmatch("([^\n]*)\n?") do buf[#buf + 1] = { l, T.fg } end
        editor.openViewTab(S, buf, f.name)
      else S.lastOut = { "Cannot read: " .. f.name, T.error } end
    end
  elseif action == "editfile" then
    local path, f = helpers.selPath(S)
    if path and f and not f.dir then editor.openEditTab(S, path) end
  elseif action == "logout" then
    helpers.logout(S); return "exit"
  elseif action == "quit" then
    drawAll()
    D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
    -- Kept identical to the ^Q prompt in events.lua — two spellings of
    -- the same four choices is how an operator learns to distrust both.
    D.set(1, S.OUT_ROW, (" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode [^Q]Cancel"):sub(1, W),
          T.title, T.bg)
    while true do
      local s2, _, c2 = pullSignal()
      if s2 == "key_down" then
        if c2 == 49 or c2 == 50 then  -- Reboot / Off — power-off gated (#9)
          local ok, reason = helpers.canPowerOff(S)
          if not ok then
            D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
            D.set(1, S.OUT_ROW, reason:sub(1, W), T.error, T.bg)
          elseif c2 == 49 then K.reboot(); return "exit"
          else K.shutdown(); return "exit" end
        elseif c2 == 51 then helpers.logout(S); return "exit"
        elseif c2 == 52 then return "cli"
        elseif c2 == 17 then S.lastOut = nil; return nil end
      end
    end
  elseif action == "lua" then exec("lua")
  elseif action == "verify" then exec("verify")
  elseif action == "flash" then
    local fpath = dialogs.promptInput(S, "Flash file: ", 60)
    if fpath and #fpath > 0 then exec("flash " .. fpath) end
  elseif action == "ps" then exec("ps")
  elseif action == "mem" then exec("mem")
  elseif action == "hw" then exec("hw")
  elseif action == "df" then exec("df")
  elseif action == "log" then exec("log")
  elseif action == "reboot" then
    local ok, reason = helpers.canPowerOff(S)
    if ok then K.reboot() else S.lastOut = { reason, T.error } end
  elseif action == "shutdown" then
    local ok, reason = helpers.canPowerOff(S)
    if ok then K.shutdown() else S.lastOut = { reason, T.error } end
  -- Help menu — all of these run an existing guest-accessible command,
  -- except keyhelp which renders a static read-only key reference.
  elseif action == "help" then exec("help")
  elseif action == "man" then exec("man")
  elseif action == "tutorial" then exec("tutorial")
  elseif action == "about" then exec("about")
  elseif action == "keyhelp" then
    local title = T.title or T.highlight
    local key   = T.highlight or T.title
    local body  = T.fg
    local okH, home = pcall(require, "shell.panels.home")
    local merged  = okH and home and home.enabled(S)
    local viewKey = merged and home.viewKeyLabel(S) or "F2"
    local cycle   = (okH and home) and home.cycleKeyLabel(S) or "F2"
    local function ck(action)
      local okK, keys = pcall(require, "shell.keys")
      if not (okK and keys) then return "?" end
      local l = keys.label(action, S.who)
      return (l ~= "" ) and l or "?"
    end
    local buf = {
      { " TOS Keyboard Shortcuts", title },
      { "", body },
    }
    local function add(t, c) buf[#buf + 1] = { t, c or body } end
    if merged then
      add(" Home", title)
      add("   " .. viewKey .. string.rep(" ", math.max(1, 17 - #viewKey))
            .. "Flip the view: tiles / files", key)
      add("   Up/Down/Left/Rt  Move the selection in whichever view is up")
      add("   Enter            Open the selection, or run the typed command")
      add("   Alt+1-9          Quick-launch a tile on this page")
      add("   PgUp / PgDn      Page the tiles / the file list")
      add("   " .. cycle .. string.rep(" ", math.max(1, 17 - #cycle))
            .. "Next tab (on an empty command line)", key)
      add("")
      add(" The prompt is always there, in both views. Anything you type")
      add(" goes to it — which is why quick-launch is Alt+1-9 and history")
      add(" is ^P / ^N rather than the arrows.", T.dim or body)
    else
      add(" File browser", title)
      add("   Up / Down        Move selection")
      add("   PgUp / PgDn      Page up / down")
      add("   Home / End       Jump to first / last")
      add("   Enter            Open folder / run typed command")
      add("   Backspace        Go up a directory (empty command line)")
    end
    add("")
    add(" Function keys", title)
    add("   F1   Help            " .. viewKey .. "   "
          .. (merged and "Flip view (tiles/files)" or "Next pane / tab"), key)
    add("   F3   View file       F4   Close tab", key)
    add("   F5   Copy a FILE      F6   Move a FILE", key)
    add("   F7   New directory   F8   Delete", key)
    add("   F9   Menu bar        F10  Power menu (reboot/off/logout)", key)
    add("")
    add(" Command line", title)
    add("   Type a command, then Enter to run it.")
    if merged then
      add("   Ctrl+P / Ctrl+N   Recall command history")
    else
      add("   Up / Down         Recall command history")
    end
    add("   Tab               Auto-complete")
    add("   Ctrl+Q            Close menu / cancel prompt")
    add("")
    add(" Selecting and the clipboard", title)
    add("   Shift + arrows   Select text (prompt, editor)")
    add("   Shift + Up/Down  Select lines in a view buffer")
    add("   " .. ck("copy") .. string.rep(" ", math.max(1, 17 - #ck("copy")))
          .. "Copy the selection", key)
    add("   " .. ck("cut") .. string.rep(" ", math.max(1, 17 - #ck("cut")))
          .. "Cut the selection", key)
    add("   " .. ck("paste") .. string.rep(" ", math.max(1, 17 - #ck("paste")))
          .. "Paste", key)
    add("   With nothing selected, copy and cut take the whole line.")
    add("   With the mouse driver, click and drag selects.")
    add("")
    add("   Copy is Ctrl+Insert, not Ctrl+C: the kernel takes Ctrl+C to")
    add("   interrupt the running program, so it never reaches a program")
    add("   at all. DOS moved copy to Ctrl+Insert for the same reason.",
        T.dim or body)
    add("   F5 and F6 in the file list are a separate FILE clipboard:")
    add("   they mark and copy files, not text.", T.dim or body)
    add("")
    add(" Editor / viewer", title)
    add("   Ctrl+S  Save     Ctrl+F  Find     Ctrl+Q  Close", key)
    add("")
    add(" Tip: type 'help' for commands, or 'man <topic>' for detail.", T.dim or body)
    editor.openViewTab(S, buf, "Keyboard")
  elseif action == "statusbar_cfg" then
    local available = { "memory", "disk", "clock", "user", "uptime" }
    for wname, _ in pairs(widgetDefs) do
      local found = false
      for _, a in ipairs(available) do if a == wname then found = true; break end end
      if not found then available[#available + 1] = wname end
    end
    local current = widgets.getWidgetList(S)
    local enabled = {}
    for _, wname in ipairs(current) do enabled[wname] = true end
    local wsel = 1
    while true do
      D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
      local wparts = {}
      for i, wname in ipairs(available) do
        local mark = enabled[wname] and "[x]" or "[ ]"
        if i == wsel then
          wparts[#wparts + 1] = ">" .. mark .. wname
        else
          wparts[#wparts + 1] = " " .. mark .. wname
        end
      end
      D.set(1, S.OUT_ROW, table.concat(wparts, " "):sub(1, W), T.title, T.bg)
      local sig, _, ch2, co2 = pullSignal()
      if sig == "touch" and type(S._mouseLib) == "table" and co2 == S.OUT_ROW then
        -- Mouse driver installed (probed by shell.panels.mouse): click a
        -- checkbox to toggle it. Touch tuple: (name, addr, x, y, ...) so
        -- ch2 = x, co2 = y. Mirror the widths used to draw wparts above:
        -- ">"/" " + "[x]"/"[ ]" + name, joined by single spaces from x=1.
        local x = 1
        for i, wname in ipairs(available) do
          local w2 = 4 + #wname
          if ch2 >= x and ch2 < x + w2 then
            wsel = i
            enabled[wname] = not enabled[wname]
            break
          end
          x = x + w2 + 1
        end
      elseif sig == "key_down" then
        if co2 == 203 then wsel = math.max(1, wsel - 1)
        elseif co2 == 205 then wsel = math.min(#available, wsel + 1)
        elseif co2 == 28 then
          local wname = available[wsel]
          enabled[wname] = not enabled[wname]
        elseif ch2 == 17 then
          local result = {}
          for _, wname in ipairs(available) do
            if enabled[wname] then result[#result + 1] = wname end
          end
          if SC and SC.set then
            SC.set("statusbar_widgets", result)
            if SC.save then SC.save() end
          end
          S.lastOut = { "Status bar updated", T.highlight }
          break
        end
      end
    end
  end
  return nil
end

function M.menuNextItem(S, dir)
  if not S.menuOpen then return end
  local items = (S.menuDefs or draw.menuDefs)[S.menuOpen].items
  local n = S.menuSel + dir
  while n >= 1 and n <= #items do
    if not items[n].sep then S.menuSel = n; return end
    n = n + dir
  end
end

return M
