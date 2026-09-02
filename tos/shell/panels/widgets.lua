local computer = require("computer")
local M = {}

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
      return nil
    end,

    view = function()
      local okH, home = pcall(require, "shell.panels.home")
      if not (okH and home and home.enabled(S)) then return nil end
      return home.isTiles(S) and "TILES" or "FILES"
    end,
  }
  return defs
end

function M.getWidgetList(S)
  local cfg = S.SC and S.SC.get("statusbar_widgets")
  if type(cfg) == "table" then return cfg end
  local pm = _G._TOS and _G._TOS.power
  if pm and pm.isActive() then
    return { "battery", "memory", "disk", "view" }
  end
  return { "memory", "disk", "view" }
end

local _widgetCache = setmetatable({}, { __mode = "k" })

function M.loadCustomWidgets(S, widgetDefs)
  if _widgetCache[S] then return end
  _widgetCache[S] = true

  local F = S.F
  if not F.isDirectory("/etc/widgets") then return end

  local U = S.U
  local st = S.st
  local function silentCanRead(p)
    if not U or not U.canAccessAs then return true end

    local sess = (st and U.getSession and U.getSession(st))
      or (U.currentSession and U.currentSession())
    local ok = U.canAccessAs(sess, p, "r")
    return ok
  end
  if not silentCanRead("/etc/widgets") then return end

  local ok, list = pcall(F.list, "/etc/widgets")
  if not ok or not list then return end
  local items = {}
  if type(list) == "table" then items = list
  elseif type(list) == "function" then for n in list do items[#items + 1] = n end end

  local MAX_WIDGETS = 32
  local loaded = 0
  for _, n in ipairs(items) do
    if loaded >= MAX_WIDGETS then break end
    if n:match("%.lua$") then
      local wname = n:gsub("%.lua$", "")
      if not widgetDefs[wname] then
        local full = "/etc/widgets/" .. n
        if silentCanRead(full) then
          local data = F.readFile(full)
          if data and #data <= 8192 then
            local fn, _ = load(data, "=widget:" .. wname, "t", {})
            if fn then
              local ok2, widget = pcall(fn)
              if ok2 and type(widget) == "function" then
                widgetDefs[wname] = widget
                loaded = loaded + 1
              end
            end
          end
        end
      end
    end
  end
end

return M
