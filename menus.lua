-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Menu Actions                    ║
-- ║  Handle menu bar item execution                     ║
-- ╚══════════════════════════════════════════════════════╝

local filebrowser = require("shell.panels.filebrowser")
local dialogs = require("shell.panels.dialogs")
local draw = require("shell.panels.draw")
local widgets = require("shell.panels.widgets")

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

  if action == "newfile" then filebrowser.doNewFile(S)
  elseif action == "mkdir" then filebrowser.doMkdir(S)
  elseif action == "rename" then filebrowser.doRename(S)
  elseif action == "quit" then
    drawAll()
    D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
    D.set(1, S.OUT_ROW, (" [1]Reboot [2]Off [3]Logout [4]Shell [^Q]Cancel"):sub(1, W),
          T.title, T.bg)
    while true do
      local s2, _, c2 = pullSignal()
      if s2 == "key_down" then
        if c2 == 49 then K.reboot(); return "exit"
        elseif c2 == 50 then K.shutdown(); return "exit"
        elseif c2 == 51 then E.push("tos_logout", S.displayIdx); return "exit"
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
  elseif action == "reboot" then K.reboot()
  elseif action == "shutdown" then K.shutdown()
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
      if sig == "key_down" then
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
  local items = draw.menuDefs[S.menuOpen].items
  local n = S.menuSel + dir
  while n >= 1 and n <= #items do
    if not items[n].sep then S.menuSel = n; return end
    n = n + dir
  end
end

return M
