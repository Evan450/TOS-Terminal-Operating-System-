-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Context Menu                     ║
-- ║  Build and execute right-click context menu actions  ║
-- ╚══════════════════════════════════════════════════════╝

local helpers = require("shell.panels.helpers")
local filebrowser = require("shell.panels.filebrowser")
local editor = require("shell.panels.editor")

local M = {}

--- The programs other than edit that could open `path`, best first, as
--- shell/open.lua ranks them. Only where a package could be installed:
--- with none there is nothing to offer beyond View and Edit, and asking
--- must not cost a machine at its memory floor anything.
function M.openChoices(S, path)
  if not helpers.mayHavePackages() then return {} end
  local okO, OP = pcall(require, "shell.open")
  if not okO then return {} end
  local sess = helpers.sessionOf(S)
  local okR, ranked = pcall(OP.rank, path, OP.gather(S.F, sess and sess.home, path))
  if not okR then return {} end
  local out = {}
  for _, c in ipairs(ranked) do
    if c.cmd ~= OP.EDITOR then out[#out + 1] = c end
  end
  return out
end

function M.buildItems(f, path, opens)
  local items = {}
  -- Every program that could open it, the best first: Enter then Enter
  -- opens a spreadsheet in the spreadsheet.
  for _, c in ipairs(opens or {}) do
    items[#items + 1] = { label = "Open in " .. c.cmd, action = "ctx_open:" .. c.cmd }
  end
  items[#items + 1] = { label = "View",   action = "ctx_view",  key = "F3" }
  items[#items + 1] = { label = "Edit",   action = "ctx_edit" }
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
  S.ctxItems = M.buildItems(f, path, (not f.dir) and M.openChoices(S, path) or nil)
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

function M.execute(S, action, makeProgramEnv, exec)
  local T = S.T
  local F = S.F
  S.ctxOpen = false

  local openCmd = action:match("^ctx_open:(.+)$")
  if openCmd then
    -- The same road a typed command takes, so a full-screen program gets
    -- the seat exactly as `calc file` at the prompt would give it.
    local okO, OP = pcall(require, "shell.open")
    if exec and okO then exec(openCmd .. " " .. OP.quote(S.ctxPath)) end
    return
  end

  if action == "ctx_view" then
    if not helpers.canRead(S, S.ctxPath) then return end
    -- Streamed, with a memory floor (#MEM — see helpers.readLinesCapped).
    local buf = { { " Viewing: " .. S.ctxFile.name, T.title } }
    local ok, shown, stopped = helpers.readLinesCapped(F, S.ctxPath, function(l) buf[#buf + 1] = { l, T.fg } end)
    if not ok then S.lastOut = { "Cannot read: " .. S.ctxFile.name, T.error }; return end
    if stopped then buf[#buf + 1] = { string.format(helpers.VIEW_STOPPED, shown), T.warning } end
    editor.openViewTab(S, buf, S.ctxFile.name)
  elseif action == "ctx_edit" then
    editor.openEditTab(S, S.ctxPath)
  elseif action == "ctx_run" then
    local buf = {}
    local function o(t, c) buf[#buf + 1] = { tostring(t), c or T.fg } end
    local refused = helpers.safeModeRefusal(S.ctxPath)
    local data = not refused and F.readFile(S.ctxPath)
    if refused then o(refused, T.error)
    elseif not data then o("Cannot read: " .. S.ctxFile.name, T.error)
    else
      -- Output goes in the view tab with any error, not wherever the global
      -- print happens to point.
      local runEnv = makeProgramEnv{ name = S.ctxFile.name, stdout = function(line) o(line, T.fg) end }
      local fn2, err2 = load(data, "=" .. S.ctxFile.name, "t", runEnv)
      if not fn2 then o("Compile error: " .. tostring(err2), T.error)
      else
        local ok2, result = pcall(fn2)
        helpers.reportProgramEnd(S, o, ok2, result, "Runtime error: ", runEnv)
      end
    end
    if #buf > 0 then
      local wrapped = helpers.expandBuf(S, buf)
      if #wrapped == 1 then S.lastOut = wrapped[1]
      else editor.openViewTab(S, wrapped, S.ctxFile.name, true) end   -- already wrapped (#MEM)
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
    -- A directory's own `sz` is 0 (the fs reports 0 for dir entries), so sum
    -- its contents recursively — otherwise folder properties always read 0B.
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
