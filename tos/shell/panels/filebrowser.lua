local helpers = require("shell.panels.helpers")
local dialogs = require("shell.panels.dialogs")

local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return require("computer").pullSignal(0.05)
end

function M.navigateUp(S)

  local parent = S.browser.path:match("^(.*)/[^/]+/?$") or "/"
  if parent == "" then parent = "/" end
  S.browser.path = S.F.normalize and S.F.normalize(parent) or parent
  S.browser.sel = 1; S.browser.scroll = 0; helpers.loadFiles(S, S.browser)
  S.cwd = S.browser.path
end

function M.navigateInto(S, dirName)
  local target = S.F.join(S.browser.path, dirName)
  if not helpers.canRead(S, target) then return end
  S.browser.path = target
  S.browser.sel = 1; S.browser.scroll = 0; helpers.loadFiles(S, S.browser)
  S.cwd = S.browser.path
end

local function promptYN(S, message)
  local D, T, W = S.D, S.T, S.W
  D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
  D.set(1, S.OUT_ROW, (message .. " (y/n)"):sub(1, W), T.warning, T.bg)
  while true do
    local sig, _, ch = pullSignal()
    if sig == "key_down" then
      if ch == 121 or ch == 89 then return true end
      return false
    end
  end
end

function M.doCopy(S)
  local T = S.T
  if S.clipboard then
    local dst = S.F.join(S.browser.path, S.clipboard.name)

    if S.F.exists(dst) and not promptYN(S, "Overwrite '" .. S.clipboard.name .. "'?") then
      S.lastOut = { "Cancelled", T.dim }
      S.clipboard = nil
      return
    end
    local ok2, err2 = S.F.copy(S.clipboard.path, dst)
    if ok2 then
      helpers.refreshBrowser(S)
      S.lastOut = { "Pasted: " .. S.clipboard.name .. " -> " .. S.browser.path, T.highlight }
    else
      S.lastOut = { "Paste failed: " .. tostring(err2 or "unknown"), T.error }
    end
    S.clipboard = nil
  else
    local path, f = helpers.selPath(S)
    if not path then S.lastOut = { "Select a file or folder to copy", T.warning }; return end
    if not helpers.canRead(S, path) then return end
    S.clipboard = { path = path, name = f.name }
    S.lastOut = { "Marked: " .. f.name .. "  -- navigate & F5 to paste", T.highlight }
  end
end

function M.doMove(S, path, f)
  local T = S.T
  if not path then
    path, f = helpers.selPath(S)
    if not path or f.dir then S.lastOut = { "Select a file to move", T.warning }; return end
  end
  if not helpers.canWrite(S, path) then return end
  local dest = dialogs.promptInput(S, "Move to: ", 60)
  if not dest or #dest == 0 then S.lastOut = { "Cancelled", T.dim }; return end
  local dst = helpers.resolvePath(S, dest)
  if S.F.isDirectory(dst) then dst = S.F.join(dst, f.name) end
  if not helpers.canWrite(S, dst) then return end

  if S.F.exists(dst) and dst ~= path then
    if not promptYN(S, "Overwrite '" .. dst .. "'?") then
      S.lastOut = { "Cancelled", T.dim }; return
    end
  end

  local renamed = S.F.rename(path, dst)
  if not renamed then
    local cok, cerr = S.F.copy(path, dst)
    if not cok then
      S.lastOut = { "Move failed: " .. tostring(cerr or "copy failed"), T.error }
      return
    end
    local rok, rerr = S.F.remove(path)
    if not rok then

      S.lastOut = { "Copied to " .. dst .. " but could not remove source: " ..
        tostring(rerr or "?"), T.warning }
      helpers.refreshBrowser(S)
      return
    end
  end
  helpers.refreshBrowser(S)
  S.lastOut = { "Moved: " .. f.name .. " -> " .. dst, T.highlight }
end

function M.doDelete(S, path, f)
  local T = S.T
  if not path then
    path, f = helpers.selPath(S)
    if not path then S.lastOut = { "Nothing selected", T.warning }; return end
  end
  if path == "/" then S.lastOut = { "Cannot delete root", T.error }; return end
  if not helpers.canWrite(S, path) then return end

  local go = dialogs.confirm(S,
    "Delete '" .. f.name .. "'?\nThis cannot be undone.",
    { title = "Delete File", severity = "danger",
      yes = "Delete", no = "Cancel", default = "no" })
  if not go then S.lastOut = { "Cancelled", T.dim }; return end

  local ok, err = S.F.remove(path)
  helpers.refreshBrowser(S)
  if ok then
    S.lastOut = { "Deleted: " .. f.name, T.highlight }
  else
    S.lastOut = { "Delete failed: " .. tostring(err or "is the directory non-empty?"), T.error }
  end
end

function M.doMkdir(S)
  local T = S.T
  if not helpers.canWrite(S, S.browser.path) then return end
  local name = dialogs.promptInput(S, "New directory name: ", 40)
  if not name or #name == 0 then S.lastOut = { "Cancelled", T.dim }; return end
  if S.F.makeDirectory(S.F.join(S.browser.path, name)) then
    helpers.refreshBrowser(S)
    S.lastOut = { "Created: " .. name, T.highlight }
  else
    S.lastOut = { "Failed", T.error }
  end
end

function M.doRename(S, path, f)
  local T = S.T
  if not path then
    path, f = helpers.selPath(S)
    if not path then S.lastOut = { "Nothing selected", T.warning }; return end
  end
  if not helpers.canWrite(S, path) then return end
  local newName = dialogs.promptInput(S, "Rename to: ", 60)
  if not newName or #newName == 0 then S.lastOut = { "Cancelled", T.dim }; return end
  local dst = S.F.join(S.browser.path, newName)
  if dst == path then S.lastOut = { "Cancelled", T.dim }; return end

  if S.F.exists(dst) then
    if not promptYN(S, "Overwrite '" .. newName .. "'?") then
      S.lastOut = { "Cancelled", T.dim }; return
    end

    pcall(S.F.remove, dst)
  end
  if S.F.rename(path, dst) then
    helpers.refreshBrowser(S)
    S.lastOut = { "Renamed: " .. f.name .. " -> " .. newName, T.highlight }
  else
    S.lastOut = { "Rename failed (cross-fs? use F6 Move instead)", T.error }
  end
end

function M.doNewFile(S)
  local T = S.T
  if not helpers.canWrite(S, S.browser.path) then return end
  local name = dialogs.promptInput(S, "New file name: ", 40)
  if not name or #name == 0 then S.lastOut = { "Cancelled", T.dim }; return end
  local p = S.F.join(S.browser.path, name)
  if S.F.writeFile(p, "") then
    helpers.refreshBrowser(S)
    S.lastOut = { "Created: " .. name, T.highlight }
  else
    S.lastOut = { "Failed", T.error }
  end
end

return M
