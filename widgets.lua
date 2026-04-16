-- ╔═════════════════════════════════���════════════════════╗
-- ║  TOS Shell - Panels Widgets                         ║
-- ║  Syntax highlighting + status bar widget defs       ║
-- ╚══════════��═══════════════════════════��═══════════════╝

local computer = require("computer")
local M = {}

-- Syntax highlighting (lazy-loaded)
local syntaxMod = nil

function M.getSyntax(S)
  if syntaxMod == nil then
    if S.tier >= 2 then
      local ok, mod = pcall(require, "shell.syntax")
      syntaxMod = ok and mod or false
    else
      syntaxMod = false
    end
  end
  return syntaxMod
end

-- ── Status bar widgets ────────────────────────────

function M.makeWidgetDefs(S)
  local F = S.F
  local K = S.K
  local defs = {
    memory = function()
      return math.floor(computer.freeMemory() / 1024) .. "K"
    end,
    disk = function()
      local mnts = F.mounts and F.mounts() or {}
      for _, m in ipairs(mnts) do
        if m.mountPoint == "/" then
          local free = (m.total or 0) - (m.used or 0)
          local helpers = require("shell.panels.helpers")
          return helpers.fmtSz(free)
        end
      end
      return "?"
    end,
    clock = function()
      local ok2, t = pcall(os.date, "*t")
      if ok2 and t then return string.format("%02d:%02d", t.hour, t.min) end
      return "--:--"
    end,
    user = function()
      return S.who
    end,
    uptime = function()
      local up = K.uptime()
      local h2 = math.floor(up / 3600)
      local m2 = math.floor((up % 3600) / 60)
      return string.format("%dh%dm", h2, m2)
    end,
    battery = function()
      local pm = _G._TOS and _G._TOS.power
      if pm and pm.isActive() then
        return pm.level() .. "%"
      end
      return nil  -- nil = don't show this widget
    end,
  }
  return defs
end

function M.getWidgetList(S)
  local cfg = S.SC and S.SC.get("statusbar_widgets")
  if type(cfg) == "table" then return cfg end
  local pm = _G._TOS and _G._TOS.power
  if pm and pm.isActive() then
    return { "battery", "memory", "disk" }
  end
  return { "memory", "disk" }
end

function M.loadCustomWidgets(S, widgetDefs)
  local F = S.F
  if not F.isDirectory("/etc/widgets") then return end
  local ok, list = pcall(F.list, "/etc/widgets")
  if not ok or not list then return end
  local items = {}
  if type(list) == "table" then items = list
  elseif type(list) == "function" then for n in list do items[#items + 1] = n end end
  for _, n in ipairs(items) do
    if n:match("%.lua$") then
      local wname = n:gsub("%.lua$", "")
      if not widgetDefs[wname] then
        local data = F.readFile("/etc/widgets/" .. n)
        if data then
          local fn, _ = load(data, "=widget:" .. wname, "t", {})
          if fn then
            local ok2, widget = pcall(fn)
            if ok2 and type(widget) == "function" then
              widgetDefs[wname] = widget
            end
          end
        end
      end
    end
  end
end

return M
