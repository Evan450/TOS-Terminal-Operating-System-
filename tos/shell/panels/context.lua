local helpers = require("shell.panels.helpers")
local filebrowser = require("shell.panels.filebrowser")
local editor = require("shell.panels.editor")

local M = {}

function M.buildItems(f, path)
  local items = {
    { label = "View",   action = "ctx_view",  key = "F3" },
    { label = "Edit",   action = "ctx_edit" },
  }
  if path:match("%.lua$") then
    items[#items + 1] = { label = "Run", action = "ctx_run" }
  end
  items[#items + 1] = { sep = true }
  items[#items + 1] = { label = "Copy",   action = "ctx_copy",   key = "F5" }
  items[#items + 1] = { label = "Move",   action = "ctx_move",   key = "F6" }
  items[#items + 1] = { label = "Delete", action = "ctx_delete", key = "F8" }
  items[#items + 1] = { label = "Rename", action = "ctx_rename" }
  items[#items + 1] = { sep = true }
  items[#items + 1] = { label = "Properties", action = "ctx_props" }
  return items
end

function M.open(S)
  local path, f = helpers.selPath(S)
  if not path or not f then return end
  S.ctxItems = M.buildItems(f, path)
  S.ctxPath = path
  S.ctxFile = f
  S.ctxSel = 1
  local selRow = S.LIST_TOP + (S.browser.sel - S.browser.scroll) - 1
  S.ctxX = math.max(1, math.floor(S.W / 2) - 10)
  S.ctxY = math.min(selRow, S.H - #S.ctxItems - 3)
  if S.ctxY < 2 then S.ctxY = 2 end
  S.ctxOpen = true
end

function M.nextItem(S, dir)
  local n = S.ctxSel + dir
  while n >= 1 and n <= #S.ctxItems do
    if not S.ctxItems[n].sep then S.ctxSel = n; return end
    n = n + dir
  end
end

function M.execute(S, action, makeProgramEnv)
  local T = S.T
  local F = S.F
  S.ctxOpen = false

  if action == "ctx_view" then
    if not helpers.canRead(S, S.ctxPath) then return end
    local content = F.readFile(S.ctxPath)
    if not content then S.lastOut = { "Cannot read: " .. S.ctxFile.name, T.error }; return end
    local buf = { { " Viewing: " .. S.ctxFile.name, T.title } }
    for l in content:gmatch("([^\n]*)\n?") do buf[#buf + 1] = { l, T.fg } end
    editor.openViewTab(S, buf, S.ctxFile.name)
  elseif action == "ctx_edit" then
    editor.openEditTab(S, S.ctxPath)
  elseif action == "ctx_run" then
    local buf = {}
    local function o(t, c) buf[#buf + 1] = { tostring(t), c or T.fg } end
    local data = F.readFile(S.ctxPath)
    if not data then o("Cannot read: " .. S.ctxFile.name, T.error)
    else
      local fn2, err2 = load(data, "=" .. S.ctxFile.name, "t", makeProgramEnv{ name = S.ctxFile.name })
      if not fn2 then o("Compile error: " .. tostring(err2), T.error)
      else
        local ok2, result = pcall(fn2)
        if not ok2 then o("Runtime error: " .. tostring(result), T.error)
        elseif result ~= nil then o(tostring(result), T.fg) end
      end
    end
    if #buf > 0 then
      local wrapped = helpers.expandBuf(S, buf)
      if #wrapped == 1 then S.lastOut = wrapped[1]
      else editor.openViewTab(S, wrapped, S.ctxFile.name) end
    end
  elseif action == "ctx_copy" then
    if not helpers.canRead(S, S.ctxPath) then return end
    S.clipboard = { path = S.ctxPath, name = S.ctxFile.name }
    S.lastOut = { "Marked: " .. S.ctxFile.name .. "  -- navigate & F5 to paste", T.highlight }
  elseif action == "ctx_move" then
    filebrowser.doMove(S, S.ctxPath, S.ctxFile)
  elseif action == "ctx_delete" then
    filebrowser.doDelete(S, S.ctxPath, S.ctxFile)
  elseif action == "ctx_rename" then
    filebrowser.doRename(S, S.ctxPath, S.ctxFile)
  elseif action == "ctx_props" then

    local sizeText
    if S.ctxFile.dir then
      local F = S.F
      local function join(a, b) return a:sub(-1) == "/" and (a .. b) or (a .. "/" .. b) end
      local function fileSize(p)
        if not F.size then return 0 end
        local ok, s = pcall(F.size, p)
        return (ok and tonumber(s)) or 0
      end
      local total, count = 0, 0
      local function walk(path)
        local ok, list = pcall(F.list, path)
        if not ok or type(list) ~= "table" then return end
        for _, name in ipairs(list) do
          local p = join(path, (name:gsub("/$", "")))
          local okD, isDir = pcall(F.isDirectory, p)
          if okD and isDir then walk(p)
          else count = count + 1; total = total + fileSize(p) end
        end
      end
      walk(S.ctxPath)
      sizeText = helpers.fmtSz(total) .. "  (" .. count .. " file" .. (count == 1 and "" or "s") .. ")"
    else
      sizeText = helpers.fmtSz(S.ctxFile.sz)
    end
    local buf = {
      { " Properties: " .. S.ctxFile.name, T.title },
      { "", T.fg },
      { " Name:  " .. S.ctxFile.name, T.fg },
      { " Path:  " .. S.ctxPath, T.fg },
      { " Size:  " .. sizeText, T.fg },
      { " Type:  " .. (S.ctxFile.dir and "Directory" or (S.ctxFile.name:match("%.(%w+)$") or "File")), T.fg },
    }
    editor.openViewTab(S, buf, "Props:" .. S.ctxFile.name:sub(1, 8))
  end
end

return M
