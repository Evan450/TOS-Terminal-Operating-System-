-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels File Browser Operations         ║
-- ║  Navigate, copy, move, delete, rename, mkdir, etc.  ║
-- ╚══════════════════════════════════════════════════════╝

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
  S.browser.path = S.browser.path:match("^(.*)/[^/]+/?$") or "/"
  if S.browser.path == "" then S.browser.path = "/" end
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

function M.doCopy(S)
  local T = S.T
  if S.clipboard then
    local dst = S.F.join(S.browser.path, S.clipboard.name)
    local ok2, err2 = S.F.copy(S.clipboard.path, dst)
    if ok2 then
      helpers.refreshBrowser(S)
      S.lastOut = { "Pasted: " .. S.clipboard.name .. " -> " .. S.browser.path, T.highlight }
    else
      S.lastOut = { err2 or "Paste failed", T.error }
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
  if S.F.rename(path, dst) then
    helpers.refreshBrowser(S)
    S.lastOut = { "Moved: " .. f.name .. " -> " .. dst, T.highlight }
  else
    S.lastOut = { "Move failed", T.error }
  end
end

function M.doDelete(S, path, f)
  local D, T, W = S.D, S.T, S.W
  if not path then
    path, f = helpers.selPath(S)
    if not path then S.lastOut = { "Nothing selected", T.warning }; return end
  end
  if path == "/" then S.lastOut = { "Cannot delete root", T.error }; return end
  if not helpers.canWrite(S, path) then return end
  D.fill(1, S.OUT_ROW, W, 1, " ", T.fg, T.bg)
  D.set(1, S.OUT_ROW, ("Delete '" .. f.name .. "'? (y/n)"):sub(1, W), T.error, T.bg)
  while true do
    local sig, _, ch2 = pullSignal()
    if sig == "key_down" then
      if ch2 == 121 or ch2 == 89 then
        S.F.remove(path); helpers.refreshBrowser(S)
        S.lastOut = { "Deleted: " .. f.name, T.highlight }
      else
        S.lastOut = { "Cancelled", T.dim }
      end
      break
    end
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
  if S.F.rename(path, dst) then
    helpers.refreshBrowser(S)
    S.lastOut = { "Renamed: " .. f.name .. " -> " .. newName, T.highlight }
  else
    S.lastOut = { "Rename failed", T.error }
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
