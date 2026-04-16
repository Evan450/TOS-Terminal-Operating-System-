-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Helpers                         ║
-- ║  Path, file, text, and permission utility functions  ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local M = {}

-- ── Path / file helpers ─────────────────────────────

function M.resolvePath(S, p)
  if not p or p == "" then return S.cwd end
  if p:sub(1, 1) == "/" then return p end
  if p == "~" or p:sub(1, 2) == "~/" then
    local home = "/home/" .. S.who
    return home .. p:sub(2)
  end
  return S.F.join(S.cwd, p)
end

function M.loadFiles(S, b)
  b.files = {}
  if b.path ~= "/" then
    b.files[1] = { name = "..", dir = true, sz = 0 }
  end
  local ok, list = pcall(S.F.list, b.path)
  if not ok or not list then return end
  local raw = {}
  if type(list) == "table" then
    for _, n in ipairs(list) do raw[#raw + 1] = n end
  elseif type(list) == "function" then
    for n in list do raw[#raw + 1] = n end
  end
  table.sort(raw, function(a, b2)
    local ad, bd = a:sub(-1) == "/", b2:sub(-1) == "/"
    if ad ~= bd then return ad end
    return a < b2
  end)
  for _, n in ipairs(raw) do
    local isDir = n:sub(-1) == "/"
    local name  = isDir and n:sub(1, -2) or n
    local sz    = 0
    if not isDir then
      pcall(function() sz = S.F.size(S.F.join(b.path, name)) end)
    end
    b.files[#b.files + 1] = { name = name, dir = isDir, sz = sz }
  end
  if b.sel > #b.files then b.sel = math.max(1, #b.files) end
end

function M.refreshBrowser(S)
  M.loadFiles(S, S.browser)
end

function M.fileColor(S, f)
  local T = S.T
  if f.dir then return T.dir or T.dir_color or T.highlight end
  if f.name:match("%.lua$") then return T.file_lua or T.file_exec or T.highlight end
  if f.name:match("%.cfg$") or f.name:match("%.conf$") then return T.file_cfg or T.warning end
  if f.name:match("%.log$") then return T.file_log or T.dim end
  return T.fg
end

function M.fmtSz(sz)
  if sz >= 1048576 then return string.format("%.1fM", sz / 1048576) end
  if sz >= 1024    then return string.format("%dK", math.floor(sz / 1024)) end
  return sz .. "B"
end

function M.selPath(S)
  if S.browser.sel < 1 or S.browser.sel > #S.browser.files then return nil, nil end
  local f = S.browser.files[S.browser.sel]
  if f.name == ".." then return nil, nil end
  return S.F.join(S.browser.path, f.name), f
end

-- ── Text helpers ──────────────────────────────────

function M.wrapLine(text, width)
  if #text <= width then return { text } end
  local lines = {}
  while #text > width do
    local cut = width
    local foundSpace = false
    for i = width, math.max(1, width - 20), -1 do
      if text:sub(i, i) == " " then cut = i - 1; foundSpace = true; break end
    end
    lines[#lines + 1] = text:sub(1, cut)
    text = text:sub(cut + (foundSpace and 2 or 1))
  end
  if #text > 0 then lines[#lines + 1] = text end
  return lines
end

function M.expandBuf(S, rawBuf)
  local out = {}
  for _, e in ipairs(rawBuf) do
    local txt = type(e) == "table" and e[1] or tostring(e)
    local col = type(e) == "table" and e[2] or S.T.fg
    for _, l in ipairs(M.wrapLine(txt, S.W)) do
      out[#out + 1] = { l, col }
    end
  end
  return out
end

-- Safe pad: avoids string.format width limit of 99
function M.padR(s, w)
  s = tostring(s)
  if #s >= w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

function M.padL(s, w)
  s = tostring(s)
  if #s >= w then return s:sub(1, w) end
  return string.rep(" ", w - #s) .. s
end

-- ── Permission helpers ────────────────────────────
-- TIER constants: GUEST=0, USER=1, ADMIN=2, ROOT=3

function M.rootOnly(S, o)
  if S.userTier < 3 then
    local msg = "Permission denied: root only"
    if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
    return false
  end
  return true
end

function M.adminOnly(S, o)
  if S.userTier < 2 then
    local msg = "Permission denied: admin access required"
    if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
    return false
  end
  return true
end

function M.canAccess(S, path, mode, o)
  if S.U then
    local ok, reason = S.U.canAccess(path, mode)
    if not ok then
      local msg = "Permission denied: " .. (reason or path)
      if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
      return false
    end
    return true
  end
  if mode == "w" then
    for _, sp in ipairs({ "/tos", "/etc", "/var" }) do
      if path == sp or path:sub(1, #sp + 1) == sp .. "/" then
        if S.who ~= "root" then
          local msg = "Permission denied: system path"
          if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
          return false
        end
      end
    end
  end
  return true
end

function M.canWrite(S, path, o) return M.canAccess(S, path, "w", o) end
function M.canRead(S, path, o)  return M.canAccess(S, path, "r", o) end

return M
