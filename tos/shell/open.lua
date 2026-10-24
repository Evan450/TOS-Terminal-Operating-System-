-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Which program opens a file                      ║
-- ║                                                              ║
-- ║  A package says what it can open in its manifest:            ║
-- ║                                                              ║
-- ║    handles = {                                               ║
-- ║      { ext = { "calc" }, as = "native" },  -- its own format ║
-- ║      { ext = { "csv" } },                  -- it can open it ║
-- ║      { ext = { "txt" }, markers = { ".title ", ".page" } },  ║
-- ║    }                       -- it SUITS a file that has these ║
-- ║                                                              ║
-- ║  and this module ranks every program that could open a file  ║
-- ║  -- by a rule, never by which package happened to install    ║
-- ║  first:                                                      ║
-- ║                                                              ║
-- ║    100  the operator's own choice  (~/.open.cfg, `open set`) ║
-- ║     90  the machine's choice       (/etc/open.cfg, admin)    ║
-- ║     60  the file's CONTENT is the package's: a line starts   ║
-- ║         with one of its markers (write's .title, .page...);  ║
-- ║         what is in a file says more than its name            ║
-- ║     50  the file is the package's own format                 ║
-- ║     40  edit, for plain-text types (.txt .lua .cfg ...)      ║
-- ║     20  the package can open files with that extension       ║
-- ║     10  edit, for any other text file                        ║
-- ║                                                              ║
-- ║  So installing a package that merely CAN open .txt does not  ║
-- ║  take every text file away from the editor. Ties go to the   ║
-- ║  more specific declaration (fewer extensions claimed), then  ║
-- ║  to the name. Markers are plain line prefixes ║
-- ║  -- never patterns -- because this reads a manifest's        ║
-- ║  strings against a user's file outside any sandbox, and a    ║
-- ║  prefix compare cannot be made to run long or do anything.   ║
-- ║                                                              ║
-- ║  Pure but for the reads it is handed: the shell passes the   ║
-- ║  caller's session fs, so a user's choices are read with the  ║
-- ║  user's own permissions.                                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

M.SCORE = { user = 100, system = 90, suits = 60, native = 50, plain = 40, opens = 20, text = 10 }
-- The editor's own: types that are plain text by name.
M.PLAIN = { txt = true, text = true, lua = true, cfg = true, conf = true, ini = true,
            log = true, md = true, man = true, json = true, xml = true, sh = true }
M.EDITOR = "edit"
M.SYSTEM_FILE = "/etc/open.cfg"
M.USER_FILE = ".open.cfg"
M.HEAD_BYTES = 4096

--- The extension of `path`, lower-cased, or nil.
function M.ext(path)
  local e = tostring(path or ""):match("%.([%w]+)$")
  return e and e:lower() or nil
end

-- ── Reading the declarations ──────────────────────────────────────────
-- A declaration as a manifest may carry it, checked again here: what is
-- under /var/pkg/installed was validated at install, but this module must
-- never be the thing that trusts a file blindly.
local function cleanDecl(pkgName, m, h)
  if type(h) ~= "table" or type(h.ext) ~= "table" then return nil end
  local exts, n = {}, 0
  for _, e in ipairs(h.ext) do
    if type(e) == "string" and e:match("^[%w]+$") and #e <= 8 then exts[e:lower()] = true; n = n + 1 end
  end
  if n == 0 then return nil end
  local cmd = h.cmd
  if cmd == nil and type(m.commands) == "table" then
    for name in pairs(m.commands) do
      if cmd then cmd = false; break end
      cmd = name
    end
  end
  if type(cmd) ~= "string" or type(m.commands) ~= "table" or not m.commands[cmd] then return nil end
  local markers
  if type(h.markers) == "table" then
    markers = {}
    for _, mk in ipairs(h.markers) do
      if type(mk) == "string" and #mk >= 2 and #mk <= 24 and not mk:find("[%c]") then markers[#markers + 1] = mk end
    end
    if #markers == 0 then return nil end
  end
  local as = (h.as == "native") and "native" or "open"
  return { pkg = pkgName, cmd = cmd, exts = exts, nExt = n, as = as, markers = markers }
end
M.cleanDecl = cleanDecl

--- Every enabled package's declarations. `src.manifests` (name ->
--- manifest, for tests) or `src.pkg` (kernel.pkg, when it is already
--- loaded) or `src.kfs` + `src.serialize` (read /var/pkg/installed
--- directly, without paying for the package manager).
function M.declarations(src)
  src = src or {}
  local manifests, enabled = {}, {}
  if src.manifests then
    for name, m in pairs(src.manifests) do manifests[name] = m; enabled[name] = (m.enabled ~= false) end
  elseif src.pkg and src.pkg.list then
    for _, e in ipairs(src.pkg.list()) do
      manifests[e.name] = src.pkg.info(e.name)
      enabled[e.name] = e.enabled
    end
  elseif src.kfs and src.serialize then
    local root = "/var/pkg/installed"
    local okL, list = pcall(src.kfs.list, root)
    if okL and type(list) == "table" then
      for _, raw in ipairs(list) do
        local name = tostring(raw):gsub("/$", "")
        if name:match("^[%w_%-]+$") then
          local okM, m = pcall(src.serialize.loadFile, src.kfs, root .. "/" .. name .. "/package.lua")
          if okM and type(m) == "table" and m.name == name and m.handles then
            manifests[name] = m
            local st = root .. "/" .. name .. "/state"
            local okS, s = pcall(src.kfs.readFile, st)
            enabled[name] = not (okS and type(s) == "string" and s:sub(1, 1) == "d")
          end
        end
      end
    end
  end
  local out = {}
  for name, m in pairs(manifests) do
    if enabled[name] and type(m) == "table" and type(m.handles) == "table" then
      for _, h in ipairs(m.handles) do
        local d = cleanDecl(name, m, h)
        if d then out[#out + 1] = d end
      end
    end
  end
  table.sort(out, function(a, b) return a.pkg < b.pkg end)
  return out
end

-- ── The operator's choices ────────────────────────────────────────────
-- One line per choice, "csv calc", and "hints off" to quiet edit's
-- suggestions. Read by hand: a typo costs a line, never the file.
function M.parseDefaults(text)
  local t = { ext = {}, hints = true }
  if type(text) ~= "string" then return t end
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local e, cmd = line:match("^%s*%.?([%w]+)%s+([%w_%-]+)%s*$")
    if e and e:lower() == "hints" then t.hints = (cmd:lower() ~= "off")
    elseif e and #e <= 8 then t.ext[e:lower()] = cmd end
  end
  return t
end

function M.serializeDefaults(t)
  local lines, keys = {}, {}
  for e in pairs(t.ext or {}) do keys[#keys + 1] = e end
  table.sort(keys)
  for _, e in ipairs(keys) do lines[#lines + 1] = e .. " " .. t.ext[e] end
  if t.hints == false then lines[#lines + 1] = "hints off" end
  return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

-- ── Ranking ───────────────────────────────────────────────────────────
--- The first of `markers` that starts a line of `head`, or nil.
function M.markersMatch(head, markers)
  if type(head) ~= "string" or not markers then return nil end
  local lines = 0
  for line in (head .. "\n"):gmatch("(.-)\n") do
    lines = lines + 1
    if lines > 200 then break end
    for _, mk in ipairs(markers) do
      if line:sub(1, #mk) == mk then return mk end
    end
  end
  return nil
end

--- Whether `head` looks like text: no NUL byte in it.
function M.isText(head)
  return type(head) ~= "string" or not head:find("%z")
end

--- Every program that could open `path`, best first. Each entry is
--- { cmd, pkg, score, why }. opts: decls, head (the file's first bytes,
--- for markers and the text test), user and system (parsed defaults).
function M.rank(path, opts)
  opts = opts or {}
  local e = M.ext(path)
  local byCmd, out = {}, {}
  local function add(cmd, pkg, score, why, spec)
    local cur = byCmd[cmd]
    if cur and cur.score >= score then return end
    if cur then cur.score, cur.why, cur.pkg, cur.spec = score, why, pkg, spec
    else
      cur = { cmd = cmd, pkg = pkg, score = score, why = why, spec = spec or 99 }
      byCmd[cmd] = cur
      out[#out + 1] = cur
    end
  end
  if e then
    for _, d in ipairs(opts.decls or {}) do
      if d.exts[e] then
        if d.markers then
          local mk = M.markersMatch(opts.head, d.markers)
          if mk then
            add(d.cmd, d.pkg, M.SCORE.suits, "it uses " .. d.pkg .. "'s \"" .. mk:gsub("%s+$", "") .. "\"", d.nExt)
          end
        elseif d.as == "native" then
          add(d.cmd, d.pkg, M.SCORE.native, "." .. e .. " is " .. d.pkg .. "'s own format", d.nExt)
        else
          add(d.cmd, d.pkg, M.SCORE.opens, d.pkg .. " opens ." .. e .. " files", d.nExt)
        end
      end
    end
  end
  if M.isText(opts.head) then
    if e and M.PLAIN[e] then add(M.EDITOR, nil, M.SCORE.plain, "." .. e .. " is plain text", 99)
    else add(M.EDITOR, nil, M.SCORE.text, "it is text") end
  end
  -- The operator's word is final, and theirs outranks the machine's.
  for _, layer in ipairs({ { opts.system, M.SCORE.system, "this machine's choice" },
                           { opts.user, M.SCORE.user, "your choice" } }) do
    local cmd = e and layer[1] and layer[1].ext and layer[1].ext[e]
    if cmd then
      local cur = byCmd[cmd]
      if cur then cur.score, cur.why = layer[2], layer[3] .. " for ." .. e
      else add(cmd, nil, layer[2], layer[3] .. " for ." .. e) end
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.spec ~= b.spec then return a.spec < b.spec end
    return a.cmd < b.cmd
  end)
  return out
end

--- The best program for `path` (nil when nothing can open it).
function M.best(path, opts)
  return M.rank(path, opts)[1]
end

--- What edit should suggest for a file it has just opened: the best
--- program when that is NOT edit and the operator has not turned the
--- hints off; otherwise nil.
function M.suggestion(path, opts)
  opts = opts or {}
  if opts.user and opts.user.hints == false then return nil end
  local b = M.best(path, opts)
  if b and b.cmd ~= M.EDITOR then return b end
  return nil
end

-- ── The shell's side: reading what it needs ───────────────────────────
--- Everything rank() needs for `path`, read through `F` (the caller's
--- session fs) and the kernel. `home` is the caller's home directory.
function M.gather(F, home, path, head)
  local src = {}
  local pkgMod = package.loaded["kernel.pkg"]
  if type(pkgMod) == "table" and pkgMod.list then src.pkg = pkgMod
  else
    local kfs = _G._TOS and _G._TOS.fs
    local okS, ser = pcall(require, "kernel.serialize")
    if type(kfs) == "table" and okS then src.kfs, src.serialize = kfs, ser end
  end
  local function read(p)
    if not (F and F.exists and F.readFile) then return nil end
    local okE, there = pcall(F.exists, p)
    if not okE or not there then return nil end
    local okR, data = pcall(F.readFile, p)
    return okR and type(data) == "string" and data or nil
  end
  if head == nil and path then
    local data = read(path)
    head = data and data:sub(1, M.HEAD_BYTES) or nil
  end
  return {
    decls = M.declarations(src),
    head = head,
    system = M.parseDefaults(read(M.SYSTEM_FILE)),
    user = M.parseDefaults(home and read(home .. "/" .. M.USER_FILE) or nil),
  }
end

--- A path quoted for a command line when it needs it.
function M.quote(path)
  if path:find("[%s\"'|<>]") then return '"' .. path:gsub('"', '\\"') .. '"' end
  return path
end

return M
