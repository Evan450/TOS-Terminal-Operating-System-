-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Tab Management                  ║
-- ║  Create, close, cycle, and find tabs                ║
-- ╚══════════════════════════════════════════════════════╝

local M = {}

function M.create(S, tabType, label, data)
  local tab = { type = tabType, label = label }
  if data then for k, v in pairs(data) do tab[k] = v end end
  S.tabs[#S.tabs + 1] = tab
  S.activeTab = #S.tabs
  return tab
end

function M.close(S, idx)
  idx = idx or S.activeTab
  if S.tabs[idx].type == "shell" then return false end
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
