-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Editor Tab Operations           ║
-- ║  Open view/edit tabs                                ║
-- ╚══════════════════════════════════════════════════════╝

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
    modified   = false,
    searchTerm = nil,
    undoStack  = {},
    undoMax    = 32,
  })
end

return M
