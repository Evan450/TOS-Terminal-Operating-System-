local M = {}

local MIN_PAGE_LINES = 120

local DEFAULT_PRESSURE_PCT = 25

local swapSeq = 0

local computerMod = nil
local function comp()
  if computerMod == nil then
    local ok, c = pcall(require, "computer")
    computerMod = (ok and type(c) == "table") and c or false
  end
  return computerMod or nil
end

local function swapMod()
  local K = _G._TOS and _G._TOS.kernel
  if not (K and K.getSwap) then return nil end
  local ok, sw = pcall(K.getSwap)
  if ok and type(sw) == "table" and sw.store and sw.fetch then return sw end
  return nil
end

local pagedMT
pagedMT = {
  __index = function(t, k)
    if k ~= "content" then return nil end
    local key = rawget(t, "_swapKey")
    if not key then return nil end
    local sw = swapMod()
    local data = sw and sw.fetch(key) or nil
    if type(data) ~= "table" then

      data = { { "(view content was paged out and could not be restored)" } }
    end
    if sw and sw.free then pcall(sw.free, key) end
    rawset(t, "_swapKey", nil)
    rawset(t, "_swapLines", nil)
    rawset(t, "content", data)
    if getmetatable(t) == pagedMT then setmetatable(t, nil) end
    return data
  end,
}

function M.isPaged(tab)
  return type(tab) == "table" and rawget(tab, "_swapKey") ~= nil
end

function M.pageOut(tab)
  if type(tab) ~= "table" or M.isPaged(tab) then return false end
  if tab.type ~= "view" and tab.type ~= "output" then return false end

  if tab.live then return false end
  local content = rawget(tab, "content")
  if type(content) ~= "table" or #content < MIN_PAGE_LINES then return false end
  local sw = swapMod()
  if not sw then return false end
  swapSeq = swapSeq + 1
  local key = "shell.view." .. swapSeq

  local pok, sok = pcall(sw.store, key, content)
  if not pok or not sok then return false end
  rawset(tab, "_swapKey", key)
  rawset(tab, "_swapLines", #content)
  rawset(tab, "content", nil)
  setmetatable(tab, pagedMT)
  return true
end

function M.dropPaged(tab)
  if not M.isPaged(tab) then return false end
  local sw = swapMod()
  if sw and sw.free then pcall(sw.free, rawget(tab, "_swapKey")) end
  rawset(tab, "_swapKey", nil)
  if getmetatable(tab) == pagedMT then setmetatable(tab, nil) end
  return true
end

function M.underPressure()
  local c = comp()
  if not c then return false end
  local total = c.totalMemory and c.totalMemory() or 0
  local free  = c.freeMemory  and c.freeMemory()  or 0
  if total <= 0 then return false end
  local pct = DEFAULT_PRESSURE_PCT
  local K = _G._TOS and _G._TOS.kernel
  if K and K.getConfig then
    local okC, cfg = pcall(K.getConfig)
    if okC and cfg and cfg.get then
      local v = tonumber(cfg.get("swapPressurePct"))
      if v and v >= 0 and v <= 100 then pct = v end
    end
  end
  return free < (total * pct / 100)
end

function M.sweepCold(S, force)
  if type(S) ~= "table" or type(S.tabs) ~= "table" then return 0 end
  if not force and not M.underPressure() then return 0 end
  local n = 0
  for i, tab in ipairs(S.tabs) do
    if i ~= S.activeTab and M.pageOut(tab) then n = n + 1 end
  end
  return n
end

function M.pagedStats(S)
  local tabsPaged, lines = 0, 0
  if type(S) == "table" and type(S.tabs) == "table" then
    for _, tab in ipairs(S.tabs) do
      if M.isPaged(tab) then
        tabsPaged = tabsPaged + 1
        lines = lines + (rawget(tab, "_swapLines") or 0)
      end
    end
  end
  return tabsPaged, lines
end

function M.create(S, tabType, label, data)
  local tab = { type = tabType, label = label }
  if data then for k, v in pairs(data) do tab[k] = v end end
  S.tabs[#S.tabs + 1] = tab
  S.activeTab = #S.tabs
  return tab
end

function M.close(S, idx)
  idx = idx or S.activeTab
  local tab = S.tabs[idx]
  if not tab or tab.type == "shell" then return false end

  local ok, apps = pcall(require, "shell.panels.apps")
  if ok and apps then
    if apps.ensureBuiltins then pcall(apps.ensureBuiltins) end
    local app = apps.get(tab.type)
    if app and app.onClose then pcall(app.onClose, S, tab) end
  end

  M.dropPaged(tab)
  table.remove(S.tabs, idx)
  if S.activeTab > #S.tabs then S.activeTab = #S.tabs end
  if S.activeTab < 1 then S.activeTab = 1 end
  return true
end

function M.cycle(S, dir)
  if #S.tabs <= 1 then return end
  S.activeTab = S.activeTab + (dir or 1)
  if S.activeTab > #S.tabs then S.activeTab = 1 end
  if S.activeTab < 1 then S.activeTab = #S.tabs end
end

function M.find(S, tabType, path)
  for i, tab in ipairs(S.tabs) do
    if tab.type == tabType and tab.path == path then return i end
  end
  return nil
end

return M
