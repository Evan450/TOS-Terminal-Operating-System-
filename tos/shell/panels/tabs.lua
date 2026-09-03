-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Tab Management                   ║
-- ║  Create, close, cycle, and find tabs                 ║
-- ╚══════════════════════════════════════════════════════╝

local M = {}

-- ============================================================
-- Cold view-buffer paging (the first real consumer of kernel.swap)
-- ============================================================
-- kernel.swap shipped as a complete but UNWIRED subsystem: nothing ever
-- called swap.store, so "swap enabled" could never turn into swap used.
-- View tabs are the natural first tenant. `cat` of a large file, a long
-- listing or a `watch` snapshot each open a tab holding EVERY line, and the
-- operator reads exactly one tab at a time — the rest are pure cold strings
-- sitting in the shell's heap. They are also loss-tolerant: the worst case
-- for a dropped buffer is re-running the command.
--
-- Paging is PRESSURE-TRIGGERED, not automatic on blur. Spilling a tab the
-- moment it loses focus would write to disk every time the operator flicks
-- between two tabs, and OC's disk I/O has a per-tick budget — that trade is
-- only worth making when RAM is actually short. On a roomy box nothing pages
-- and nothing is slower; on a tight one the cold buffers leave RAM.
--
-- Restore is TRANSPARENT: a paged tab gets a metatable whose __index pages
-- the content back on first read, so every existing `tab.content` reader
-- (draw.viewTab, the scroll/search handlers, mouse) is untouched.

-- Below this a buffer isn't worth a disk round-trip.
local MIN_PAGE_LINES = 120
-- Default pressure point: page cold buffers when free RAM drops under this
-- share of total. Operator-tunable via `swapPressurePct` in /etc/tos.cfg.
local DEFAULT_PRESSURE_PCT = 25

local swapSeq = 0

-- `computer` is resolved LAZILY, never at module load. tabs.lua has always
-- been dependency-free on load, and several off-box tests pull it in
-- transitively (desktop.lua, settingsapp) without stubbing the machine
-- globals — a top-level require here breaks them at import time.
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
      -- Swap is scratch: a clear, an over-cap eviction or a bad decode can
      -- lose the entry. Fail SOFT with a visible note rather than a blank
      -- tab or an error — the operator can just re-run the command.
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

--- Is this tab's content currently on disk?
function M.isPaged(tab)
  return type(tab) == "table" and rawget(tab, "_swapKey") ~= nil
end

--- Spill one tab's view buffer to swap. Returns true if it actually paged.
--- Safe to call repeatedly: an already-paged (or ineligible) tab is a no-op.
function M.pageOut(tab)
  if type(tab) ~= "table" or M.isPaged(tab) then return false end
  if tab.type ~= "view" and tab.type ~= "output" then return false end
  -- A LIVE tab rebuilds its own content on a timer; paging it out would just
  -- be undone on the next refresh.
  if tab.live then return false end
  local content = rawget(tab, "content")
  if type(content) ~= "table" or #content < MIN_PAGE_LINES then return false end
  local sw = swapMod()
  if not sw then return false end
  swapSeq = swapSeq + 1
  local key = "shell.view." .. swapSeq
  -- store() reports a full/over-cap swap as (false, err) rather than raising.
  local pok, sok = pcall(sw.store, key, content)
  if not pok or not sok then return false end
  rawset(tab, "_swapKey", key)
  rawset(tab, "_swapLines", #content)
  rawset(tab, "content", nil)
  setmetatable(tab, pagedMT)
  return true
end

--- Free a paged tab's swap entry without restoring it (tab is going away).
function M.dropPaged(tab)
  if not M.isPaged(tab) then return false end
  local sw = swapMod()
  if sw and sw.free then pcall(sw.free, rawget(tab, "_swapKey")) end
  rawset(tab, "_swapKey", nil)
  if getmetatable(tab) == pagedMT then setmetatable(tab, nil) end
  return true
end

--- Free RAM is under the configured pressure point.
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

--- Page out every cold (non-active, non-live) view buffer. Returns the
--- number of tabs paged. `force` skips the pressure check — that's how
--- `optimize swap now` makes the mechanism observable on a roomy box.
function M.sweepCold(S, force)
  if type(S) ~= "table" or type(S.tabs) ~= "table" then return 0 end
  if not force and not M.underPressure() then return 0 end
  local n = 0
  for i, tab in ipairs(S.tabs) do
    if i ~= S.activeTab and M.pageOut(tab) then n = n + 1 end
  end
  return n
end

--- How many tabs are currently paged, and how many lines that represents.
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
  -- App lifecycle: a registered app gets to release what it holds
  -- (Chat's net listener, future process-backed apps' processes) no
  -- matter which path closed the tab (^Q, F4, /quit, menu).
  local ok, apps = pcall(require, "shell.panels.apps")
  if ok and apps then
    if apps.ensureBuiltins then pcall(apps.ensureBuiltins) end
    local app = apps.get(tab.type)
    if app and app.onClose then pcall(app.onClose, S, tab) end
  end
  -- Release the swap entry rather than paging the buffer back in just to
  -- throw it away — closing a paged tab must not cost a disk read, and
  -- leaving the entry behind would hold cap until the next reboot wipes it.
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
