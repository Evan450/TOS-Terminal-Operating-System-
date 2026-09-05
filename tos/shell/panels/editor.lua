local helpers = require("shell.panels.helpers")
local tabs = require("shell.panels.tabs")

local M = {}

function M.openViewTab(S, rawBuf, label)
  local content = helpers.expandBuf(S, rawBuf)
  if #content == 0 then return end
  label = label or "Output"
  if #label > 16 then label = label:sub(1, 15) .. "~" end
  tabs.create(S, "view", label, {
    content    = content,
    offset     = 0,
    searchTerm = nil,
  })
end

function M.refreshLiveTab(S, tab)
  if not tab or type(tab.refresh) ~= "function" then return end
  local T = S.T or {}
  local okR, raw = pcall(tab.refresh)
  if not okR or type(raw) ~= "table" then
    raw = { { "(refresh error: " .. tostring(raw) .. ")", T.error } }
  end

  tab.refreshCount = (tab.refreshCount or 0) + 1
  local full = {
    { "\226\151\143 LIVE  " .. (tab.liveLabel or tab.label or "")
      .. "   ~" .. (tab.interval or 1) .. "s  \194\183  \226\159\179 " .. tab.refreshCount
      .. "  \194\183  r refresh  \194\183  q/F4 close", T.dim },
    { "", T.fg },
  }
  for _, l in ipairs(raw) do full[#full + 1] = l end
  tab.content = helpers.expandBuf(S, full)
  local viewH  = (S.H or 25) - 2
  local maxOff = math.max(0, #tab.content - viewH)
  if (tab.offset or 0) > maxOff then tab.offset = maxOff end
end

function M.openLiveTab(S, label, refreshFn, interval)
  if type(refreshFn) ~= "function" then return end
  label = label or "Live"
  interval = tonumber(interval) or 1
  if interval < 1 then interval = 1 end
  local short = (#label > 13) and (label:sub(1, 12) .. "~") or label
  local tab = tabs.create(S, "view", "\226\151\143" .. short, {
    content     = {},
    offset      = 0,
    searchTerm  = nil,
    live        = true,
    refresh     = refreshFn,
    interval    = interval,
    liveLabel   = label,
    lastRefresh = 0,
  })
  M.refreshLiveTab(S, tab)
  return tab
end

function M.openEditTab(S, path)
  local existing = tabs.find(S, "edit", path)
  if existing then
    S.activeTab = existing
    return
  end
  if path and S.F.exists(path) and not helpers.canRead(S, path) then return end
  local lines = { "" }
  if path and S.F.exists(path) then
    local content = S.F.readFile(path) or ""
    lines = {}
    for l in content:gmatch("([^\n]*)\n?") do lines[#lines + 1] = l end
    if #lines == 0 then lines[1] = "" end
    if lines[#lines] == "" and #lines > 1 then lines[#lines] = nil end
  end
  local fname = (path and path:match("[^/]+$")) or "new file"
  tabs.create(S, "edit", fname, {
    path       = path,
    lines      = lines,
    curRow     = 1,
    curCol     = 1,
    viewTop    = 1,
    --! Horizontal companion to viewTop: the leftmost visible column.
    --! Maintained by clampEdit on every cursor move. draw.lua defaults
    --! it too, so a tab from an older session cannot render blank.
    viewLeft   = 1,
    modified   = false,
    searchTerm = nil,
    undoStack  = {},
    undoMax    = 32,
  })
end

return M
