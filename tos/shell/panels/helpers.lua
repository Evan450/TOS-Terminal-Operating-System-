local computer = require("computer")
local M = {}

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

  b.freeStr = nil
  pcall(function()
    local best, bestLen = nil, -1
    for _, m in ipairs(S.F.mounts() or {}) do
      local mp = m.mountPoint or ""
      if mp ~= "" and b.path:sub(1, #mp) == mp and #mp > bestLen then
        best, bestLen = m, #mp
      end
    end
    if best and best.total then
      b.freeStr = M.fmtSz(math.max(0, (best.total or 0) - (best.used or 0)))
    end
  end)
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

function M.classifyDisk(F, mnt)
  if not F or not mnt or mnt == "" then return { kind = "data", desc = "disk" } end
  local function exists(p)
    local ok, r = pcall(F.exists, p)
    return ok and r or false
  end
  local function has(rel) return exists(F.join(mnt, rel)) end
  local function listNames(dir)
    local names = {}
    local ok, list = pcall(F.list, dir)
    if ok and list then
      if type(list) == "table" then for _, n in ipairs(list) do names[#names + 1] = n end
      elseif type(list) == "function" then for n in list do names[#names + 1] = n end end
    end
    return names
  end

  local function hasPackageDir(dir)
    for _, n in ipairs(listNames(dir)) do
      local clean = n:gsub("/$", "")
      if clean ~= "" and clean ~= "." and clean ~= ".."
         and not clean:find("[/\\]")
         and exists(F.join(F.join(dir, clean), "package.lua")) then
        return true
      end
    end
    return false
  end

  if has("tos/kernel/init.lua") then
    return { kind = "tos-install", desc = "TOS install disk",
      hint = "(install image — run its install.lua on the target machine)" }
  end

  if hasPackageDir(mnt) then

    if has("optutil-set.lua") then
      return { kind = "optional-utilities", desc = "Optional Utilities disk",
        hint = "pkg install" }
    end
    return { kind = "package-repo", desc = "package repo disk", hint = "pkg install" }
  end

  for _, n in ipairs(listNames(mnt)) do
    local clean = n:gsub("/$", "")
    if clean ~= "" and clean ~= "." and clean ~= ".." and not clean:find("[/\\]") then
      local sub = F.join(mnt, clean)
      if hasPackageDir(sub) then
        if exists(F.join(sub, "optutil-set.lua")) then

          return { kind = "optional-utilities", desc = "Optional Utilities disk",
            hint = "pkg install" }
        end
        return { kind = "package-repo", desc = "package repo disk", hint = "pkg install" }
      end
    end
  end

  if has("package.lua") then
    return { kind = "package", desc = "single-package disk",
      hint = "disk install " .. mnt }
  end

  if has("module.cfg") then
    return { kind = "module", desc = "module disk (legacy)",
      hint = "disk install " .. mnt }
  end
  return { kind = "data", desc = "data / blank disk" }
end

function M.scanMountedMedia(F)
  if not F or not F.mounts then return nil end
  local ok, mnts = pcall(F.mounts)
  if not ok or type(mnts) ~= "table" then return nil end
  for _, m in ipairs(mnts) do
    if m.mountPoint and m.mountPoint ~= "/" then
      local info = M.classifyDisk(F, m.mountPoint)
      if info and info.kind ~= "data" then
        info.mountPoint = m.mountPoint
        info.label = m.label
        return info
      end
    end
  end
  return nil
end

function M.routeOutput(n, maxInline)
  n = tonumber(n) or 0
  if n <= 0 then return "none" end
  if n == 1 then return "status" end
  if n <= (maxInline or 8) then return "inline" end
  return "tab"
end

function M.completeToken(prefix, candidates)
  prefix = prefix or ""
  local matches = {}
  for _, c in ipairs(candidates or {}) do
    if c:sub(1, #prefix) == prefix then matches[#matches + 1] = c end
  end
  if #matches == 0 then return prefix, matches end
  if #matches == 1 then return matches[1], matches end
  local cp = matches[1]
  for i = 2, #matches do
    local m, n = matches[i], 0
    while n < #cp and n < #m and cp:sub(n + 1, n + 1) == m:sub(n + 1, n + 1) do n = n + 1 end
    cp = cp:sub(1, n)
  end
  return cp, matches
end

function M.completeCmdline(cmdline, cmds, listDir)
  local before, token = (cmdline or ""):match("^(.-)(%S*)$")
  if not before:find("%S") then
    local comp, matches = M.completeToken(token, cmds or {})
    if #matches == 1 then comp = comp .. " " end
    return before .. comp, matches
  end
  local dirPart, base = token:match("^(.*/)([^/]*)$")
  dirPart, base = dirPart or "", base or token
  local entries = (listDir and listDir(dirPart)) or {}
  local names = {}
  for _, e in ipairs(entries) do names[#names + 1] = (type(e) == "table" and e.name or e) end
  local comp, matches = M.completeToken(base, names)
  if #matches == 1 then
    for _, e in ipairs(entries) do
      local nm = type(e) == "table" and e.name or e
      if nm == comp then comp = comp .. ((type(e) == "table" and e.dir) and "/" or " "); break end
    end
  end
  return before .. dirPart .. comp, matches
end

function M.cmdScroll(len, cursor, avail)
  if avail < 1 then avail = 1 end
  local cur0 = (cursor or (len + 1)) - 1
  if cur0 < 0 then cur0 = 0 elseif cur0 > len then cur0 = len end
  local hs = 0
  if cur0 > avail - 1 then hs = cur0 - (avail - 1) end
  if hs < 0 then hs = 0 end
  return hs
end

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

  local reserve = (S.tier and S.tier >= 2) and 6 or 0
  local wrapW = math.max(8, S.W - reserve)
  for _, e in ipairs(rawBuf) do
    local txt = type(e) == "table" and e[1] or tostring(e)
    local col = type(e) == "table" and e[2] or S.T.fg
    for _, l in ipairs(M.wrapLine(txt, wrapW)) do
      out[#out + 1] = { l, col }
    end
  end
  return out
end

local lineNumFmtCache = {}

function M.formatLineNum(n, gutterW)
  local fmt = lineNumFmtCache[gutterW]
  if not fmt then
    fmt = "%" .. (gutterW - 1) .. "d "
    lineNumFmtCache[gutterW] = fmt
  end
  return string.format(fmt, n)
end

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

function M.liveTier(S)
  if S and S.U and S.st then

    if S.U.getSession then
      local s = S.U.getSession(S.st)
      if s and type(s.tier) == "number" then return s.tier end
    end
    return 0
  end
  return (S and S.userTier) or 0
end

function M.rootOnly(S, o)
  if M.liveTier(S) < 3 then

    S.lastDenial = { cmd = S.curCmd, need = 3, have = M.liveTier(S) }
    local msg = "Permission denied: root only"
    if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
    return false
  end
  return true
end

function M.adminOnly(S, o)
  if M.liveTier(S) < 2 then
    S.lastDenial = { cmd = S.curCmd, need = 2, have = M.liveTier(S) }
    local msg = "Permission denied: admin access required"
    if o then o(msg, S.T.error) else S.lastOut = { msg, S.T.error } end
    return false
  end
  return true
end

function M.tierName(n)
  n = tonumber(n) or 0
  return ({ [0] = "GUEST", [1] = "USER", [2] = "ADMIN", [3] = "ROOT" })[n]
    or ("tier " .. n)
end

function M.whyExplain(cmd, need, have, known)
  local out = {}
  local function add(t, tone) out[#out + 1] = { text = t, tone = tone } end
  cmd = cmd or "?"
  if not known then
    add("Unknown command: " .. cmd, "err")
    add("It isn't a built-in. If it came from a package, check `pkg list`;", "dim")
    add("otherwise check the spelling — Tab completes command names.", "dim")
    return out
  end
  need = tonumber(need) or 0
  have = tonumber(have) or 0
  add(cmd .. " — needs " .. M.tierName(need) .. "; you are " .. M.tierName(have) .. ".", "title")
  if have >= need then
    add("You have the access to run this.", "ok")
    add("If it still failed, the cause is something else (a missing", "dim")
    add("resource, file, or capability) — check `doctor` and `log`.", "dim")
  elseif need >= 3 then
    add("This is ROOT-only.", "err")
    add("Fix: log in on the root account to run it (`logout`, then", "fix")
    add("sign in as root).", "fix")
  else
    add("This needs administrator access.", "err")
    add("Fix: have an admin run it, or sign in on an admin account", "fix")
    add("(`logout`, then log in as an admin). An admin can also grant", "fix")
    add("your account admin rights.", "fix")
  end
  return out
end

--! The ONE way to log a seat out.
--!
--! There were five: the `logout` command, the System menu, the F10 power
--! menu, the ^Q prompt and the Desktop. Only the command dropped an active
--! `sudo -s` elevation first -- and its own comment calls that an invariant
--! ("never carry elevation across logout"). The other four pushed the signal
--! straight out, so the elevated SESSION the sudo path registered was never
--! logged out: the kernel's handler retires sessionTokens[seat], which is the
--! ORIGINAL login token, a different object entirely.
--!
--! What that costs TODAY is small, and worth stating precisely rather than
--! dressing up: the elevated token is discarded with the shell state, so
--! nobody can present it; there is no session cap to exhaust; and nothing
--! enumerates sessions to an operator. It lingers as a phantom entry until
--! sweepSessions retires it, within SESSION_TIMEOUT.
--!
--! It is fixed anyway, and centrally, for two reasons. sudoDrop does not only
--! retire the token -- it also restores the shell process's principal, and
--! that only stays harmless while every logout path also KILLS the process.
--! The kernel's handler does today; a future "switch user" or a CLI handoff
--! that reuses the process would not, and then the elevation rides across.
--! And five copies of a security rule is four chances to update it in the
--! wrong number of places. (test_logout_elevation.lua)
function M.logout(S)
  if S and S._sudo and S.sudoDrop then pcall(S.sudoDrop) end
  if S and S.E and S.E.push then S.E.push("tos_logout", S.displayIdx) end
end

function M.canPowerOff(S)
  if M.liveTier(S) >= 2 then return true end

  local n = 0
  local pids = _G._TOS and _G._TOS.shellPIDs
  if type(pids) == "table" then
    for _, pid in pairs(pids) do if pid then n = n + 1 end end
  end
  if n <= 1 then return true end
  return false, n .. " operators are logged in. Ask an admin to power off, "
    .. "or wait for the others to log out."
end

function M.sessionOf(S)
  if S and S.U then
    if S.st and S.U.getSession then
      local s = S.U.getSession(S.st)
      if s then return s end
    end
    if S.U.currentSession then
      local s = S.U.currentSession()
      if s then return s end
    end
  end
  return nil
end

function M.canAccess(S, path, mode, o)
  if S.U then

    local session = M.sessionOf(S)
    local ok, reason
    if session and S.U.canAccessAs then
      ok, reason = S.U.canAccessAs(session, path, mode)
    elseif S.U.canAccess then
      ok, reason = S.U.canAccess(path, mode)
    else

      ok, reason = false, "access check unavailable"
    end
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

--! #SEC H9 — an unqualified command name resolves only against a fixed set
--! of system bin directories. PATH is honoured only where its entries are
--! also on the safe list: anything under /mnt, /tmp, /public, /home or
--! /root is REJECTED, so an attacker setting PATH=/mnt/floppy:/bin and
--! running `ls` cannot silently shadow the system binary.

M.SYSTEM_BIN_DIRS  = { "/bin", "/usr/bin", "/tos/shell" }
M.UNSAFE_PREFIXES  = { "/mnt/", "/tmp/", "/public/", "/home/", "/root/" }

--! #SEC — BUG FOUND WHEN THIS MOVED OUT OF executor.lua (2026-08-04).
--! The prefix list is written with trailing slashes, and the old check
--! compared the PATH entry against them raw. A PATH entry of exactly
--! "/tmp" (or "/mnt", "/home", "/root", "/public") therefore matched
--! NOTHING and was treated as safe — `PATH=/tmp` plus a planted
--! /tmp/<name>.lua would run for any name that isn't a built-in and
--! isn't in a system bin dir. Subdirectories ("/tmp/x") were caught
--! correctly all along, which is why it survived: the shape people
--! actually write in a PATH is the bare root.
--! Normalizing to a trailing slash before comparing closes it.
function M.dirIsSafe(dir)
  local d = tostring(dir or "")
  if d == "" then return false end
  if d:sub(-1) ~= "/" then d = d .. "/" end
  for _, p in ipairs(M.UNSAFE_PREFIXES) do
    if d:sub(1, #p) == p then return false end
  end
  return true
end

--! An alias carries NO privilege. It is expanded before dispatch, so the
--! expansion meets exactly the same tier gates as if it had been typed —
--! aliasing a name to an admin command does not make it runnable. The
--! table is read from the caller's OWN profile through securefs, so one
--! user cannot plant an alias in another user's shell.
function M.aliases(S)
  if S._aliases then return S._aliases end
  local out = {}
  local pmod = _G._TOS and _G._TOS.profile
  if pmod and pmod.load then
    local ok, p = pcall(pmod.load, M.sessionOf(S))
    if ok and type(p) == "table" and type(p.aliases) == "table" then
      for k, v in pairs(p.aliases) do
        if type(k) == "string" and type(v) == "string" then out[k:lower()] = v end
      end
    end
  end
  S._aliases = out
  return out
end

function M.invalidateAliases(S) S._aliases = nil end

local ALIAS_MAX_DEPTH = 8
function M.expandAlias(S, parts)
  if type(parts) ~= "table" or #parts == 0 then return parts end
  local table_ = M.aliases(S)
  if next(table_) == nil then return parts end
  local seen = {}
  for _ = 1, ALIAS_MAX_DEPTH do
    local head = tostring(parts[1] or ""):lower()
    local expansion = table_[head]
    if not expansion or seen[head] then break end
    seen[head] = true
    local repl = M.tokenizeSimple(expansion)
    if #repl == 0 then break end
    local rest = {}
    for i = 2, #parts do rest[#rest + 1] = parts[i] end
    for _, a in ipairs(rest) do repl[#repl + 1] = a end
    parts = repl
  end
  return parts
end

function M.tokenizeSimple(s)
  local t = {}
  for word in tostring(s):gmatch("%S+") do t[#t + 1] = word end
  return t
end

function M.resolveProgram(F, name)
  if type(name) ~= "string" or name == "" then return nil end
  local function probe(dir)
    local full = F.join(dir, name .. ".lua")
    if F.exists(full) then return full end
    full = F.join(dir, name)
    if F.exists(full) then return full end
    return nil
  end
  for _, dir in ipairs(M.SYSTEM_BIN_DIRS) do
    local hit = probe(dir)
    if hit then return hit, "system" end
  end
  local ok, envMod = pcall(require, "kernel.env")
  if ok then
    local pathStr = envMod.read(nil, "PATH") or "/usr/bin:/bin"
    for dir in pathStr:gmatch("[^:]+") do
      if M.dirIsSafe(dir) then
        local hit = probe(dir)
        if hit then return hit, "path" end
      end
    end
  end
  return nil
end

return M
