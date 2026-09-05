local pkg = {}

local PKG_ROOT        = "/var/pkg/installed"
local CRITICAL_BACKUP = "/etc/critical.bak"

local fs        = nil
local log       = nil
local serialize = nil
local users     = nil

local installed = {}

local ADMIN_TIER = 2
local function adminGate(opts)
  if not users then return true end
  local session = (type(opts) == "table" and opts.session) or nil
  if not session and users.currentSession then session = users.currentSession() end
  if not session then return false, "Insufficient privileges: admin required" end
  if session.isKernel or session.isLogin then return true end
  if type(session.tier) == "number" and session.tier >= ADMIN_TIER then return true end
  return false, "Insufficient privileges: admin required"
end

local VALID_KINDS = {
  app     = true,
  command = true,

  program = true,
  lib     = true,
  service = true,
  runtime = true,
  driver  = true,
  theme   = true,
}

local function validName(s)
  if type(s) ~= "string" then return false end
  if s == "" or #s > 64 then return false end
  if s == "." or s == ".." then return false end
  if #s == 1 then return s:match("^[%w]$") ~= nil end

  return s:match("^[%w][%w%-]*[%w]$") ~= nil
end

local function pathHasTraversal(p)
  if type(p) ~= "string" then return true end
  if p:find("\0", 1, true) then return true end
  if p:find("\\", 1, true) then return true end
  for seg in p:gmatch("[^/]+") do
    if seg == "." or seg == ".." then return true end
  end
  return false
end

local PKG_WRITE_ROOTS = { "/usr/", "/var/pkg/" }
local function isUnderPkgWriteRoot(p)
  if type(p) ~= "string" or p == "" then return false end
  for _, root in ipairs(PKG_WRITE_ROOTS) do

    if p:sub(1, #root) == root and #p > #root then return true end
  end
  return false
end

local function isServiceEtcTarget(p)
  if type(p) ~= "string" then return false end
  if p:match("^/etc/rc%.d/[%w_%-]+%.lua$") then return true end
  if p:match("^/etc/[%w_%-]+%.cfg$")        then return true end
  return false
end

local function validVersion(s)
  return type(s) == "string"
     and s ~= ""
     and #s <= 32
     and s:match("^[%w%.%-]+$") ~= nil
end

local function validateManifest(m)
  if type(m) ~= "table" then return false, "manifest is not a table" end
  if not validName(m.name) then return false, "invalid name: " .. tostring(m.name) end
  if not validVersion(m.version) then return false, "invalid version: " .. tostring(m.version) end
  if not VALID_KINDS[m.kind] then return false, "invalid kind: " .. tostring(m.kind) end
  if type(m.files) ~= "table" then return false, "missing files array" end

  for i, p in ipairs(m.files) do
    if type(p) ~= "string" or p:sub(1, 1) ~= "/" then
      return false, "files[" .. i .. "] is not an absolute path"
    end
    if pathHasTraversal(p) then
      return false, "files[" .. i .. "] contains an unsafe path segment"
    end

    if not isUnderPkgWriteRoot(p)
       and not (m.kind == "service" and isServiceEtcTarget(p)) then
      return false, "files[" .. i .. "] must be under " ..
        table.concat(PKG_WRITE_ROOTS, " or ") ..
        " (service packages may also write /etc/rc.d/<f>.lua and /etc/<name>.cfg) (got "
        .. p .. ")"
    end
  end

  --! Every entry must name a target the manifest actually declares — a
  --! source for an undeclared target would be copied by nothing, but it
  --! must not be possible to smuggle extra paths past the files[] loop
  --! above, which is where the write-root confinement lives.
  --! Sources are RELATIVE and traversal-checked: the installer joins them
  --! onto the package directory, so a "../" or absolute source would read
  --! outside the media being installed from.
  if m.fileMap ~= nil then
    if type(m.fileMap) ~= "table" then
      return false, "fileMap must be a table if present"
    end
    local declared = {}
    for _, p in ipairs(m.files) do declared[p] = true end
    for target, src in pairs(m.fileMap) do
      if type(target) ~= "string" or type(src) ~= "string" then
        return false, "fileMap entries must be string -> string"
      end
      if not declared[target] then
        return false, "fileMap names a target not in files[]: " .. target
      end
      if src == "" or src:sub(1, 1) == "/" then
        return false, "fileMap source must be a relative path: " .. src
      end
      if pathHasTraversal(src) then
        return false, "fileMap source contains an unsafe path segment: " .. src
      end
    end
  end

  if m.hashes ~= nil then
    if type(m.hashes) ~= "table" then
      return false, "hashes must be a table if present"
    end
    for k, h in pairs(m.hashes) do
      if type(k) ~= "string" or type(h) ~= "string" or #h ~= 64 or h:find("[^%x]") then
        return false, "hashes['" .. tostring(k) .. "'] is not a 64-hex digest"
      end
    end
  end
  if m.critical ~= nil then
    if type(m.critical) ~= "table" then
      return false, "critical must be an array if present"
    end

    for i, p in ipairs(m.critical) do
      if type(p) ~= "string" or p:sub(1, 1) ~= "/" or pathHasTraversal(p) then
        return false, "critical[" .. i .. "] is not a safe absolute path"
      end
    end
  end
  if m.commands ~= nil and type(m.commands) ~= "table" then
    return false, "commands must be a table if present"
  end
  if m.requires ~= nil and type(m.requires) ~= "table" then
    return false, "requires must be an array if present"
  end

  if m.recommends ~= nil then
    if type(m.recommends) ~= "table" then
      return false, "recommends must be an array of package names if present"
    end
    for i, r in ipairs(m.recommends) do
      if type(r) ~= "string" or r == "" then
        return false, "recommends[" .. i .. "] is not a package name"
      end
    end
  end

  if m.conflicts ~= nil then
    if type(m.conflicts) ~= "table" then
      return false, "conflicts must be an array of package names if present"
    end
    for i, c in ipairs(m.conflicts) do
      if type(c) ~= "string" or c == "" then
        return false, "conflicts[" .. i .. "] is not a package name"
      end
      if c == m.name then
        return false, "conflicts[" .. i .. "] lists the package itself"
      end
    end
  end
  if m.capabilities ~= nil and type(m.capabilities) ~= "table" then
    return false, "capabilities must be an array if present"
  end

  if m.screen ~= nil then
    if type(m.screen) ~= "table" then
      return false, "screen must be a table { width=, height= } if present"
    end
    local sw, sh = m.screen.width, m.screen.height
    if type(sw) ~= "number" or sw < 1 or sw ~= math.floor(sw)
       or type(sh) ~= "number" or sh < 1 or sh ~= math.floor(sh) then
      return false, "screen.width/height must be positive integers"
    end
    if m.screen.mode ~= nil and m.screen.mode ~= "exact" and m.screen.mode ~= "min" then
      return false, "screen.mode must be 'exact' or 'min'"
    end
  end

  if m.provides ~= nil then
    if type(m.provides) ~= "table" then
      return false, "provides must be an array if present"
    end
    for i, n in ipairs(m.provides) do
      if not validName(n) then
        return false, "provides[" .. i .. "] is not a valid name"
      end
    end
  end

  if m.license ~= nil then
    if type(m.license) ~= "table" then
      return false, "license must be a table if present"
    end
    if m.license.requireKey ~= nil and type(m.license.requireKey) ~= "boolean" then
      return false, "license.requireKey must be boolean"
    end
    if m.license.keys ~= nil then
      if type(m.license.keys) ~= "table" then
        return false, "license.keys must be an array"
      end
      for i, h in ipairs(m.license.keys) do
        if type(h) ~= "string" or #h ~= 64 or h:find("[^%x]") then
          return false, "license.keys[" .. i .. "] is not a 64-hex digest"
        end
      end
    end
  end
  return true
end

function pkg.parseCap(s)
  if type(s) ~= "string" then return nil, "not a string" end
  s = s:match("^%s*(.-)%s*$")
  if s == "" then return nil, "empty" end

  local colon = s:find(":", 1, true)
  if not colon then

    if s:match("^[%w%.]+$") then return { facet = s } end
    return nil, "invalid facet: " .. s
  end

  local facet = s:sub(1, colon - 1)
  local scope = s:sub(colon + 1)
  if facet == "" then return nil, "empty facet before ':'" end
  if not facet:match("^[%w%.]+$") then return nil, "invalid facet: " .. facet end
  if scope == "" then return nil, "empty scope after ':'" end
  return { facet = facet, scope = scope }
end

function pkg.init(deps)
  fs        = deps.fs
  log       = deps.log
  users     = deps.users
  serialize = require("kernel.serialize")

  if not fs then return false, "fs module required" end

  if not fs.exists(PKG_ROOT) then
    local ok, err = fs.makeDirectory(PKG_ROOT)
    if not ok and log then
      log.warn("pkg", "Could not create " .. PKG_ROOT .. ": " .. tostring(err))
    end
  end

  pkg.scan()

  if log then
    local n = 0
    for _ in pairs(installed) do n = n + 1 end
    log.info("pkg", "Package manager initialized (" .. n .. " installed)")
  end
  return true
end

function pkg.scan()
  installed = {}
  if not fs.exists(PKG_ROOT) then return 0 end
  local entries = fs.list(PKG_ROOT) or {}
  local count = 0
  for _, name in ipairs(entries) do

    local clean = name:gsub("/$", "")
    if clean ~= "" and validName(clean) then
      --! Read with serialize.loadFile and NOT loadAnyManifest, which
      --! matters for the signature verdict: loadAnyManifest strips
      --! `_sigState` because a manifest on MEDIA must not be able to
      --! declare itself trusted, while a manifest already in
      --! /var/pkg/installed had that field written by install() after a
      --! real verification. The asymmetry is the point — and /var is
      --! securefs-protected, so forging it needs privilege the attacker
      --! would no longer need this for.
      local manifestPath = fs.join(PKG_ROOT, clean, "package.lua")
      local m, err = serialize.loadFile(fs, manifestPath)
      if type(m) == "table" then
        local ok, vErr = validateManifest(m)
        if ok then

          if m.name == clean then
            installed[m.name] = m
            count = count + 1
          elseif log then
            log.warn("pkg", "Manifest name '" .. m.name .. "' does not match dir '" .. clean .. "'")
          end
        elseif log then
          log.warn("pkg", "Invalid manifest at " .. manifestPath .. ": " .. tostring(vErr))
        end
      elseif err and log then
        log.warn("pkg", "Failed to load " .. manifestPath .. ": " .. tostring(err))
      end
    end
  end
  return count
end

function pkg.list()
  local result = {}
  for name, m in pairs(installed) do
    result[#result + 1] = {
      name        = m.name,
      version     = m.version,
      kind        = m.kind,
      description = m.description,
      enabled     = pkg.isEnabled(name),
    }
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

function pkg.info(name)
  return installed[name]
end

function pkg.isEnabled(name)
  if not installed[name] then return false end
  local p = fs.join(PKG_ROOT, name, "state")
  if not fs.exists(p) then return true end
  local data = fs.readFile(p)
  if not data then return true end
  return data:sub(1, 1) ~= "d"
end

function pkg.setEnabled(name, on, opts)
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  if not installed[name] then return false, "not installed: " .. name end
  local p = fs.join(PKG_ROOT, name, "state")
  return fs.writeFile(p, on and "e" or "d")
end

function pkg.commands()
  local result = {}
  for name, m in pairs(installed) do
    if pkg.isEnabled(name) and type(m.commands) == "table" then
      for cmdName, cmdPath in pairs(m.commands) do
        if type(cmdName) == "string" and type(cmdPath) == "string" then
          result[cmdName] = cmdPath
        end
      end
    end
  end
  return result
end

function pkg.ownerOfCommand(name)
  if type(name) ~= "string" then return nil end
  for pkgName, m in pairs(installed) do
    if type(m.commands) == "table" and type(m.commands[name]) == "string"
       and pkg.isEnabled(pkgName) then
      return pkgName
    end
  end
  return nil
end

local pkgActive = {}

local PKG_RUN_CAPS = {
  ["fs.read"] = true, ["fs.write"] = true, component = true,
  ["compat.io"] = true, load = true, net = true, swap = true,

  internet = true,
  vault = true,
  crypto = true,
  notify = true,

  ["peripheral.modem"] = true, ["peripheral.redstone"] = true,
  ["peripheral.robot"] = true, ["peripheral.inventory"] = true,
  ["peripheral.tape"] = true, ["peripheral.tractor"] = true,
  ["peripheral.piston"] = true, ["peripheral.hologram"] = true,

  ["peripheral.printer"] = true,

}

local PKG_CAPS_CFG = "/etc/pkg_caps.cfg"
local _capAllow  = {}
local _capDeny   = {}
local _capLoaded = false

local function loadCapConfig()
  if _capLoaded then return end
  _capLoaded = true
  if not fs or not fs.exists or not fs.exists(PKG_CAPS_CFG) then return end
  local raw = fs.readFile(PKG_CAPS_CFG)
  if not raw or #raw == 0 or #raw > 8192 then
    if log then log.warn("pkg", "pkg_caps.cfg unreadable or oversized — overrides NOT in force") end
    return
  end
  local serMod = serialize or require("kernel.serialize")
  local ok, cfg = pcall(serMod.decode, raw, { maxBytes = 8192 })
  if not ok or type(cfg) ~= "table" then
    if log then log.warn("pkg", "pkg_caps.cfg did not decode — overrides NOT in force") end
    return
  end

  local function validFacet(f)
    return type(f) == "string" and #f <= 64 and f:match("^[%w%.]+$") ~= nil
  end
  if type(cfg.allow) == "table" then
    for _, f in ipairs(cfg.allow) do

      if validFacet(f) and f ~= "legacy" then _capAllow[f] = true end
    end
  end
  if type(cfg.deny) == "table" then
    for pkgName, list in pairs(cfg.deny) do
      if type(pkgName) == "string" and #pkgName <= 64 and type(list) == "table" then
        local set = _capDeny[pkgName] or {}
        for _, f in ipairs(list) do
          if validFacet(f) then set[f] = true end
        end
        _capDeny[pkgName] = set
      end
    end
  end
end

function pkg.runCaps()
  local out = {}
  for facet in pairs(PKG_RUN_CAPS) do out[facet] = true end
  return out
end

function pkg.reloadCapConfig()
  _capAllow, _capDeny, _capLoaded = {}, {}, false
  loadCapConfig()
  return _capAllow, _capDeny
end

function pkg.capAllowed(pkgName, facet)
  if type(facet) ~= "string" then return false, "invalid facet" end
  loadCapConfig()
  local denied = (_capDeny["*"] and _capDeny["*"][facet])
              or (pkgName and _capDeny[pkgName] and _capDeny[pkgName][facet])
  if denied then return false, "denied by /etc/pkg_caps.cfg" end
  if PKG_RUN_CAPS[facet] then return true end
  if _capAllow[facet] then return true end
  return false, "not a package-grantable capability"
end

local function loadPkgEntry(pkgName, m, entryPath)
  if pkgActive[pkgName] then return pkgActive[pkgName] end
  if not fs.exists(entryPath) then return nil end
  local source = fs.readFile(entryPath)
  if not source then return nil end

  local caps = {}
  if type(m.capabilities) == "table" then
    for _, c in ipairs(m.capabilities) do
      local parsed = pkg.parseCap(c)
      if parsed and parsed.facet then
        local allowed, why = pkg.capAllowed(pkgName, parsed.facet)
        if allowed then
          caps[parsed.facet] = true
        elseif log then

          log.warn("pkg", "capability '" .. parsed.facet .. "' refused for " ..
            pkgName .. ": " .. tostring(why))
        end
      end
    end
  end

  local okSB, sandbox = pcall(require, "kernel.sandbox")
  if not okSB or not sandbox or not sandbox.build then return nil end

  local env = sandbox.build({ caps = caps, pkgName = pkgName })
  local fn, lerr = load(source, "=pkg:" .. pkgName, "t", env)
  if not fn then
    if log then log.warn("pkg", "command load error in " .. pkgName .. ": " .. tostring(lerr)) end
    return nil
  end
  local ok, result = pcall(fn)
  if not ok or type(result) ~= "table" then
    if log then log.warn("pkg", "entry failed in " .. pkgName .. ": " .. tostring(result)) end
    return nil
  end

  local scoped = {}
  for cmdName, fn2 in pairs(result.commands or {}) do
    if type(fn2) == "function" then
      scoped[cmdName] = function(...)
        local okP, procMod = pcall(require, "kernel.process")
        local cur = (okP and procMod and procMod.current) and procMod.current() or nil
        if not cur then return fn2(...) end
        local saved = cur.caps
        cur.caps = caps
        local r = table.pack(pcall(fn2, ...))
        cur.caps = saved
        if not r[1] then error(r[2], 0) end
        return table.unpack(r, 2, r.n)
      end
    end
  end
  result.commands = scoped

  pkgActive[pkgName] = result
  return result
end

local dispatchEnabled = true
function pkg.setDispatchEnabled(on)
  dispatchEnabled = on and true or false
end
function pkg.dispatchEnabled() return dispatchEnabled end

function pkg.getCommand(name)
  if not dispatchEnabled then return nil end
  if type(name) ~= "string" then return nil end
  for pkgName, m in pairs(installed) do
    if type(m.commands) == "table" then
      local entryPath = m.commands[name]
      if type(entryPath) == "string" and pkg.isEnabled(pkgName) then
        local mod = loadPkgEntry(pkgName, m, entryPath)
        if mod and type(mod.commands) == "table"
           and type(mod.commands[name]) == "function" then
          return mod.commands[name]
        end
      end
    end
  end
  return nil
end

function pkg.getCommandScreen(name)
  if type(name) ~= "string" then return nil end
  for pkgName, m in pairs(installed) do
    if type(m.commands) == "table" and m.commands[name] ~= nil
       and type(m.screen) == "table" and pkg.isEnabled(pkgName) then
      return { width = m.screen.width, height = m.screen.height,
               mode = m.screen.mode or "exact" }
    end
  end
  return nil
end

function pkg.getCommandFullscreen(name)
  if type(name) ~= "string" then return false end
  for pkgName, m in pairs(installed) do
    if type(m.commands) == "table" and m.commands[name] ~= nil
       and pkg.isEnabled(pkgName) then
      return m.fullscreen == true
    end
  end
  return false
end

local BG_POLICIES = { drowsy = true, always = true, freeze = true }
function pkg.getCommandBackground(name)
  if type(name) ~= "string" then return "drowsy" end
  for pkgName, m in pairs(installed) do
    if type(m.commands) == "table" and m.commands[name] ~= nil
       and pkg.isEnabled(pkgName) then
      local b = m.background
      if type(b) == "string" and BG_POLICIES[b] then return b end
      return "drowsy"
    end
  end
  return "drowsy"
end

function pkg.flushCommandCache(pkgName)
  if pkgName then pkgActive[pkgName] = nil else pkgActive = {} end
end

function pkg.capabilities(name)
  local m = installed[name]
  if not m or type(m.capabilities) ~= "table" then return {} end
  local result = {}
  for _, capStr in ipairs(m.capabilities) do
    local parsed, err = pkg.parseCap(capStr)
    if parsed then
      result[#result + 1] = parsed
    elseif log then
      log.warn("pkg", "Bad capability '" .. tostring(capStr) ..
        "' in " .. name .. ": " .. tostring(err))
    end
  end
  return result
end

local function splitVersion(v)
  if type(v) ~= "string" then return nil end
  local base, suffix = v:match("^([%d%.]+)%-?(.*)$")
  if not base then return nil end
  local parts = {}
  for seg in base:gmatch("[^%.]+") do
    parts[#parts + 1] = tonumber(seg) or 0
  end
  return parts, suffix
end

function pkg.compareVersion(a, b)
  local pa, sa = splitVersion(a)
  local pb, sb = splitVersion(b)
  if not pa or not pb then return 0 end
  local n = math.max(#pa, #pb)
  for i = 1, n do
    local va, vb = pa[i] or 0, pb[i] or 0
    if va < vb then return -1 end
    if va > vb then return 1 end
  end

  if sa == "" and sb == "" then return 0 end
  if sa == "" then return 1   end
  if sb == "" then return -1  end
  if sa < sb then return -1 end
  if sa > sb then return 1  end
  return 0
end

function pkg.satisfiesConstraint(version, constraint)
  if not constraint or constraint == "" then return true end
  constraint = constraint:match("^%s*(.-)%s*$")
  local op, target = constraint:match("^(>=?)(.+)$")
  if not op then op, target = constraint:match("^(<=?)(.+)$") end
  if not op then op, target = constraint:match("^(==?)(.+)$") end
  if not op then op, target = constraint:match("^(%^)(.+)$") end
  if not op then op, target = constraint:match("^(~)(.+)$") end
  if not op then

    op = "=="; target = constraint
  end
  target = target:match("^%s*(.-)%s*$")
  local cmp = pkg.compareVersion(version, target)
  if op == ">"  then return cmp >  0 end
  if op == ">=" then return cmp >= 0 end
  if op == "<"  then return cmp <  0 end
  if op == "<=" then return cmp <= 0 end
  if op == "="  or op == "==" then return cmp == 0 end
  if op == "^" then

    if cmp < 0 then return false end
    local va = splitVersion(version); local vt = splitVersion(target)
    if not va or not vt then return false end
    return (va[1] or 0) == (vt[1] or 0)
  end
  if op == "~" then

    if cmp < 0 then return false end
    local va = splitVersion(version); local vt = splitVersion(target)
    if not va or not vt then return false end
    return (va[1] or 0) == (vt[1] or 0) and (va[2] or 0) == (vt[2] or 0)
  end
  return false
end

local function findProvider(name)
  if installed[name] then return installed[name] end
  for _, pkgRec in pairs(installed) do
    if type(pkgRec.provides) == "table" then
      for _, p in ipairs(pkgRec.provides) do
        if p == name then return pkgRec end
      end
    end
  end
  return nil
end

function pkg.checkRequires(name)
  local m = installed[name]
  if not m then return false, { name } end
  if type(m.requires) ~= "table" then return true, {} end
  local missing = {}
  for _, req in ipairs(m.requires) do

    local reqName, reqConstraint, optional
    if type(req) == "table" then
      reqName       = req.name
      reqConstraint = req.version
      optional      = req.optional
    elseif type(req) == "string" then
      local n, c = req:match("^(%S+)%s+(.+)$")
      if n then reqName, reqConstraint = n, c
      else reqName, reqConstraint = req, nil end
      optional = false
    end
    if reqName then

      local dep = findProvider(reqName)
      if not dep then
        if not optional then
          missing[#missing + 1] = reqName ..
            (reqConstraint and (" (" .. reqConstraint .. ")") or "")
        end
      elseif reqConstraint then

        if not pkg.satisfiesConstraint(dep.version or "0.0.0", reqConstraint) then
          missing[#missing + 1] = reqName .. " " .. reqConstraint ..
            " (have " .. (dep.version or "?") .. " via " ..
            (dep.name or "?") .. ")"
        end
      end
    end
  end
  return #missing == 0, missing
end

function pkg.resolveInstallOrder(targetName, lookup)
  local order = {}
  local visiting = {}
  local visited  = {}

  local function visit(name)
    if visited[name] then return true end
    if visiting[name] then
      return false, "dependency cycle through " .. name
    end
    local m = lookup(name)
    if not m then
      return false, "unknown package: " .. name
    end
    visiting[name] = true
    if type(m.requires) == "table" then
      for _, req in ipairs(m.requires) do
        local depName
        if type(req) == "table" then depName = req.name
        elseif type(req) == "string" then depName = req:match("^(%S+)") end
        if depName then

          if not findProvider(depName) then
            local ok, err = visit(depName)
            if not ok then return false, err end
          end
        end
      end
    end
    visiting[name] = nil
    visited[name] = true

    local canonical = (m.name and m.name ~= "") and m.name or name

    if not visited[canonical] or canonical == name then
      visited[canonical] = true
      order[#order + 1] = canonical
    end
    return true
  end

  local ok, err = visit(targetName)
  if not ok then return nil, err end
  return order
end

function pkg.criticalFiles()
  local seen = {}
  local result = {}
  for _, m in pairs(installed) do
    if type(m.critical) == "table" then
      for _, p in ipairs(m.critical) do
        if type(p) == "string" and not seen[p] then
          seen[p] = true
          result[#result + 1] = p
        end
      end
    end
  end
  table.sort(result)
  return result
end

function pkg.syncCriticalBackup()
  local list = pkg.criticalFiles()
  if #list == 0 then

    return false, "no critical files declared by any package"
  end

  local current = serialize.loadFile(fs, CRITICAL_BACKUP)
  if type(current) == "table" and #current == #list then
    local same = true
    for i = 1, #list do
      if current[i] ~= list[i] then same = false; break end
    end
    if same then return true, "already in sync" end
  end

  local ok, err = serialize.saveFile(fs, CRITICAL_BACKUP, list)
  if ok and log then
    log.info("pkg", "Critical-files backup updated: " .. #list .. " entries")
  elseif not ok and log then
    log.warn("pkg", "Failed to update critical backup: " .. tostring(err))
  end
  return ok, err
end

local function translateDeps(dependencies)
  local out = {}
  if type(dependencies) ~= "table" then return out end
  for depName, value in pairs(dependencies) do
    if type(depName) == "string" and depName ~= "" then
      local constraint = nil
      if type(value) == "string" and value ~= "" and value:sub(1, 1) ~= "/" then
        constraint = value
      end
      out[#out + 1] = { name = depName, version = constraint, optional = false }
    end
  end
  return out
end

--! OPPM's actual index format, which loadAnyManifest's own header has
--! described since FEAT-7 without anything ever reading it: a repo-root
--! `programs.cfg` holding EVERY package, keyed by name. A genuine OPPM
--! repo checkout therefore read as "no manifest here" and the operator was
--! told the disk was empty.

local OPPM_PREFIX = "/usr"

local function oppmDestDir(value)
  if type(value) ~= "string" or value == "" then return nil end
  if value:sub(1, 2) == "//" then return "/" .. value:gsub("^/+", "") end
  return OPPM_PREFIX .. "/" .. value:gsub("^/+", "")
end

local function basenameOf(p)
  return (tostring(p):gsub("/+$", ""):match("([^/]+)$"))
end

local function translateProgramsEntry(name, inner, srcBase)
  if type(inner) ~= "table" then return nil, "programs.cfg entry is not a table" end
  local m = {
    name        = name,
    version     = inner.version or "0.0.0",
    kind        = inner.kind or "command",
    files       = {},
    fileMap     = {},
    requires    = translateDeps(inner.dependencies),
    commands    = inner.commands,
    capabilities = inner.capabilities,

    description = inner.description or inner.note,
    author      = inner.author or inner.authors,
    hashes      = inner.hashes,
    _srcBase    = srcBase,
  }
  if type(inner.files) ~= "table" then
    return nil, "programs.cfg entry '" .. tostring(name) .. "' has no files table"
  end
  local dirCopies = {}
  for src, dest in pairs(inner.files) do
    if type(src) == "string" and type(dest) == "string" then
      --! OPPM's ":" key prefix means "copy this whole DIRECTORY". TOS
      --! installs a declared file list — each path validated, hashed and
      --! owned — and cannot honour a wildcard without giving up the
      --! ownership map that conflict detection and uninstall depend on.
      --! Refuse LOUDLY: silently dropping the entry would install a
      --! package that is quietly missing its data files.
      if src:sub(1, 1) == ":" then
        dirCopies[#dirCopies + 1] = src:sub(2)
      else
        local destDir = oppmDestDir(dest)
        local leaf = basenameOf(src)
        if destDir and leaf and leaf ~= "" then
          local target = (destDir:gsub("/+$", "")) .. "/" .. leaf
          m.files[#m.files + 1] = target
          m.fileMap[target] = src:gsub("^/+", "")
        end
      end
    end
  end
  if #dirCopies > 0 then
    return nil, "package '" .. tostring(name) ..
      "' uses OPPM directory-copy entries (" .. table.concat(dirCopies, ", ") ..
      "); TOS installs a declared file list — list the files individually"
  end
  if #m.files == 0 then
    return nil, "programs.cfg entry '" .. tostring(name) .. "' lists no installable files"
  end
  return m
end

local function loadFromProgramsCfg(srcDir)
  local base = basenameOf(srcDir)
  if not base then return nil end
  local parent = srcDir:gsub("/+$", ""):match("^(.*)/[^/]+$")
  local candidates = {}
  if parent and parent ~= "" then
    candidates[#candidates + 1] = { path = fs.join(parent, "programs.cfg"), root = parent }
  end
  candidates[#candidates + 1] = { path = fs.join(srcDir, "programs.cfg"), root = srcDir }

  for _, cand in ipairs(candidates) do
    if fs.exists(cand.path) then
      local raw, err = serialize.loadFile(fs, cand.path)
      if type(raw) ~= "table" then
        return nil, "programs.cfg parse error: " .. tostring(err)
      end
      local entry = raw[base]
      if type(entry) ~= "table" then

        local only, count = nil, 0
        for k, v in pairs(raw) do
          if type(k) == "string" and type(v) == "table" then only, count = k, count + 1 end
        end
        if count == 1 and cand.root == srcDir then
          base, entry = only, raw[only]
        end
      end
      if type(entry) == "table" then

        local tm, tErr = translateProgramsEntry(base, entry, cand.root)
        if not tm then return nil, tErr end
        return tm, nil, cand.path
      end
    end
  end
  return nil
end

--! Returns (manifest, kind, manifestPath). The THIRD value is what the
--! signature layer needs: a signature covers the raw bytes of the file
--! the manifest was read from, and there are four possible files, so the
--! only honest way to know which one to check is for the reader to say.
local function loadAnyManifest(srcDir)
  --! `_srcBase` redirects where the installer READS a package's files
  --! from. It is set only by the programs.cfg translator, to a directory
  --! this function chose itself. Clearing it on every on-disk form is what
  --! keeps that true — otherwise a hand-written package.lua could declare
  --! one and have its files sourced from anywhere on the machine.
  local function fromDisk(m, kind, path)
    if type(m) == "table" then
      m._srcBase = nil
      --! Same rule, and for a sharper reason: `_sigState`/`_sigKey`/
      --! `_sigLabel` are what `pkg info` reads to tell an operator who
      --! signed a package. A manifest that could set them itself would
      --! be a package that declares itself trusted — the shortest
      --! possible forgery. They are computed at install time from an
      --! actual verification and are stripped from every on-disk form.
      m._sigState, m._sigKey, m._sigLabel = nil, nil, nil
    end
    return m, kind, path
  end

  local nativePath = fs.join(srcDir, "package.lua")
  if fs.exists(nativePath) then
    local m, err = serialize.loadFile(fs, nativePath)
    if m then return fromDisk(m, "native", nativePath) end
    return nil, "package.lua parse error: " .. tostring(err)
  end
  local oppmPath = fs.join(srcDir, "package.oppm.lua")
  if fs.exists(oppmPath) then
    local raw, err = serialize.loadFile(fs, oppmPath)
    if not raw then return nil, "package.oppm.lua parse error: " .. tostring(err) end

    local outerName, inner = next(raw)
    if not inner or type(inner) ~= "table" then
      return nil, "OPPM manifest has no top-level package entry"
    end

    local translated = {
      name        = outerName,
      version     = inner.version or "0.0.0",
      kind        = inner.kind or "command",
      files       = {},
      requires    = {},
      commands    = inner.commands,
      capabilities = inner.capabilities,
      description = inner.description,
      author      = inner.author,
      critical    = inner.critical,
      hashes      = inner.hashes,
    }

    if type(inner.files) == "table" then
      for k, v in pairs(inner.files) do
        if type(k) == "number" and type(v) == "string" then
          translated.files[#translated.files + 1] = v
        elseif type(k) == "string" and type(v) == "string" then
          translated.files[#translated.files + 1] = v
        end
      end
    end

    translated.requires = translateDeps(inner.dependencies)
    return fromDisk(translated, "oppm", oppmPath)
  end

  local base = srcDir:match("([^/]+)/?$")
  if base then
    local cfgPath = fs.join(srcDir, base .. ".cfg")
    if fs.exists(cfgPath) then
      local raw, err = serialize.loadFile(fs, cfgPath)
      if not raw then return nil, base .. ".cfg parse error: " .. tostring(err) end

      local inner, outerName = raw, base
      if raw[base] and type(raw[base]) == "table" then
        inner = raw[base]
      elseif not raw.files then
        local n, v = next(raw)
        if type(v) == "table" then outerName, inner = n, v end
      end
      if type(inner) ~= "table" then return nil, base .. ".cfg has no package table" end
      local translated = {
        name        = inner.name or outerName,
        version     = inner.version or "0.0.0",
        kind        = inner.kind or "command",
        files       = {},
        requires    = {},
        commands    = inner.commands,
        capabilities = inner.capabilities,
        description = inner.description,
        author      = inner.author,
        hashes      = inner.hashes,
      }
      if type(inner.files) == "table" then
        for k, v in pairs(inner.files) do
          if type(v) == "string" then translated.files[#translated.files + 1] = v
          elseif type(k) == "string" then translated.files[#translated.files + 1] = k end
        end
      end
      translated.requires = translateDeps(inner.dependencies)
      return fromDisk(translated, "oppm", cfgPath)
    end
  end

  local m, cfgErr, cfgPath2 = loadFromProgramsCfg(srcDir)
  if m then return m, "oppm", cfgPath2 end
  if cfgErr then return nil, cfgErr end

  return nil, "no package.lua, package.oppm.lua, <name>.cfg or programs.cfg entry for "
    .. srcDir
end

--! A package written for OpenOS is not written for TOS's sandbox. Its code
--! reaches for `io`, `term`, `filesystem`, `component` — the OpenOS
--! userland — which TOS provides through its compat layer, but ONLY to a
--! sandbox that was granted the capabilities for it. An OPPM manifest has
--! no TOS capabilities to declare, so translating one produced a package
--! that installed cleanly and then could not run a single line.
--!
--! Recognising the package as foreign is therefore not a label, it is the
--! thing that makes it work: a foreign package is granted the compat
--! surface by default. That is a REAL privilege grant, so it is recorded on
--! the installed manifest (`origin`) and surfaced by `pkg info`/`pkg list`
--! — an operator should be able to see which of their packages arrived
--! trusting an OpenOS-shaped world.
--!
--! It is deliberately NOT a blank cheque: the foreign default is the
--! OpenOS-userland surface, not `legacy` (raw os/io, which no manifest can
--! ever request) and not the peripheral caps. A package needing a modem or
--! a robot still has to say so.
local FOREIGN_DEFAULT_CAPS = { "compat.io", "fs.read", "fs.write", "component" }

function pkg.foreignDefaultCaps()
  local out = {}
  for i, c in ipairs(FOREIGN_DEFAULT_CAPS) do out[i] = c end
  return out
end

--! Two kinds, and the second is the one that actually bites.
--!
--! DECLARED — a manifest's `conflicts = { "other" }`. Checked both ways:
--! we refuse if the incoming package names an installed one, AND if an
--! installed one names the incoming. A conflict is symmetric in fact even
--! when only one author wrote it down.
--!
--! FILE OWNERSHIP — two packages shipping the SAME install target. Nothing
--! checked this: install copied its files over whatever was there, so the
--! second package silently clobbered the first's, and uninstalling either
--! then deleted files the other still needed. No manifest has to declare
--! anything for this to happen; it is the default outcome of two authors
--! picking the same path.
--!
--! `ignoreName` lets an UPGRADE skip its own previous version's files,
--! which are exactly the ones it is entitled to replace.

function pkg.findConflicts(m, ignoreName)
  local out = {}
  if type(m) ~= "table" then return out end

  for _, c in ipairs(m.conflicts or {}) do
    if c ~= ignoreName and installed[c] then
      out[#out + 1] = { kind = "declared", other = c,
        detail = tostring(m.name) .. " declares a conflict with " .. c }
    end
  end
  for otherName, other in pairs(installed) do
    if otherName ~= m.name and otherName ~= ignoreName then
      for _, c in ipairs(other.conflicts or {}) do
        if c == m.name then
          out[#out + 1] = { kind = "declared", other = otherName,
            detail = otherName .. " declares a conflict with " .. tostring(m.name) }
        end
      end
    end
  end

  local owner = {}
  for otherName, other in pairs(installed) do
    if otherName ~= m.name and otherName ~= ignoreName then
      for _, f in ipairs(other.files or {}) do owner[f] = otherName end
    end
  end
  for _, f in ipairs(m.files or {}) do
    if owner[f] then
      out[#out + 1] = { kind = "file", other = owner[f], detail = f,
        path = f }
    end
  end
  return out
end

--! There was no update path at all: `pkg.install` refused over an existing
--! package ("uninstall first"), and nothing ever compared what is installed
--! against what a disk is offering. The version machinery
--! (compareVersion / satisfiesConstraint) already existed — it was only
--! being used to satisfy dependency constraints, never to notice that the
--! floppy in the drive has something newer.
--!
--! An upgrade is deliberately NOT "install over the top". It is:
--!   1. verify the candidate (hash gate, licence, conflicts) FIRST
--!   2. remember the enable state and the rc boot marker
--!   3. remove the old version's files, INCLUDING the ones the new version
--!      no longer ships (an install-over would strand those forever)
--!   4. install the new one
--!   5. put the enable state and boot marker back
--! Step 3 is why this cannot be a flag on install: the set of files to
--! delete is the difference between two manifests.

function pkg.outdated(opts)
  opts = opts or {}
  local out = {}
  for _, e in ipairs(pkg.listAllAvailable() or {}) do
    local cur = installed[e.name]
    if cur and e.version and cur.version then
      if pkg.compareVersion(e.version, cur.version) > 0 then
        out[#out + 1] = { name = e.name, from = cur.version, to = e.version,
                          dir = e.dir, root = e.root }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function pkg.upgrade(name, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  local cur = installed[name]
  if not cur then return false, "not installed: " .. tostring(name) end

  local pkgDir, root = pkg.findInRepos(name, opts.extraRoots)
  if not pkgDir then
    return false, "no source for " .. name .. " on any repo or inserted disk"
  end
  local m, source = loadAnyManifest(pkgDir)
  if not m then return false, "unreadable manifest for " .. name end

  local cmp = pkg.compareVersion(m.version or "0.0.0", cur.version or "0.0.0")
  if cmp == 0 and not opts.force then
    return false, string.format("%s is already at %s", name, tostring(cur.version))
  end
  if cmp < 0 and not opts.force then
    return false, string.format(
      "%s on the disk is OLDER (%s < %s) — pass force to downgrade",
      name, tostring(m.version), tostring(cur.version))
  end

  local vOk, vErr = pkg._verificationGate(m, opts.allowUnverified)
  if not vOk then return false, vErr end
  local licOk, licErr = pkg.verifyLicenseKey(m, opts.licenseKey)
  if not licOk then return false, "license check failed: " .. tostring(licErr) end
  local conflicts = pkg.findConflicts(m, name)
  if #conflicts > 0 and not opts.force then
    return false, "conflicts: " .. pkg.describeConflicts(conflicts)
  end

  local wasEnabled = pkg.isEnabled(name)
  local markers = {}
  for _, f in ipairs(cur.files or {}) do
    local stem = tostring(f):match("^/etc/rc%.d/(.+)%.lua$")
    if stem then
      markers[stem] = fs.exists("/etc/rc.d/" .. stem .. ".disabled")
    end
  end

  local keep = {}
  for _, f in ipairs(m.files or {}) do keep[f] = true end
  local orphaned = {}
  for _, f in ipairs(cur.files or {}) do
    if not keep[f] then orphaned[#orphaned + 1] = f end
  end

  local upOk, upErr = pkg.uninstall(name, { session = opts.session,
                                            _internalUpgrade = true })
  if not upOk then return false, "could not remove the old version: " .. tostring(upErr) end

  local inOk, inErr = pkg.install(pkgDir, {
    session = opts.session, upgrading = true, force = opts.force,
    allowUnverified = opts.allowUnverified, licenseKey = opts.licenseKey,
  })
  if not inOk then
    return false, "upgrade FAILED after removing " .. name .. ": " .. tostring(inErr)
      .. " — reinstall it from the disk"
  end

  pcall(pkg.setEnabled, name, wasEnabled, { session = opts.session })
  for stem, wasDisabled in pairs(markers) do
    local marker = "/etc/rc.d/" .. stem .. ".disabled"
    if wasDisabled and not fs.exists(marker) then pcall(fs.writeFile, marker, "1")
    elseif not wasDisabled and fs.exists(marker) then pcall(fs.remove, marker) end
  end

  if log then
    log.info("pkg", string.format("Upgraded %s %s -> %s (%d file(s) dropped)",
      name, tostring(cur.version), tostring(m.version), #orphaned))
  end
  return true, { name = name, from = cur.version, to = m.version,
                 dropped = orphaned, origin = source, enabled = wasEnabled }
end

function pkg.describeConflicts(list)
  local parts = {}
  for _, c in ipairs(list or {}) do
    if c.kind == "file" then
      parts[#parts + 1] = string.format("%s is already installed by %s",
        c.path, c.other)
    else
      parts[#parts + 1] = c.detail
    end
  end
  return table.concat(parts, "; ")
end

function pkg.verifyLicenseKey(manifest, userKey)
  if type(manifest) ~= "table" or type(manifest.license) ~= "table" then
    return true
  end
  if not manifest.license.requireKey then
    return true
  end
  if type(userKey) ~= "string" or userKey == "" then
    return false, "license key required"
  end
  local cryptoMod
  do local okC, c = pcall(require, "kernel.crypto"); if okC then cryptoMod = c end end
  if not cryptoMod or not cryptoMod.hash or not cryptoMod.ctEquals then
    return false, "crypto unavailable for license verification"
  end
  local actual = cryptoMod.hash(manifest.name .. "|" .. userKey)
  local keys = manifest.license.keys or {}
  for _, expected in ipairs(keys) do
    if cryptoMod.ctEquals(actual, expected) then return true end
  end
  return false, "license key rejected (no matching hash)"
end

--! The hash gate below and this one answer DIFFERENT questions, and
--! collapsing them was the whole bug. `hashes` prove the bytes on the
--! disk are the bytes the manifest describes — i.e. the disk is not
--! corrupt. They cannot prove anything about WHO wrote the disk, because
--! whoever wrote the files also wrote the digests. A signature over the
--! manifest is what makes the digests attributable, and then the chain
--! runs signature → manifest → hashes → files.
--!
--! So: a signed package with no hashes is NOT verified (the signature
--! vouches for a manifest that promises nothing about the code), and a
--! hashed package with no signature is NOT attributed. Both gates run.
--!
--! `pkgsign` is required lazily. A machine that never meets a signed
--! package never loads the signature layer, and never loads the several
--! hundred lines of field arithmetic underneath it.
local function signGate(manifestPath, opts)
  if not manifestPath then
    return { state = "unsigned", reason = "manifest path unknown" }, nil
  end
  local okS, ps = pcall(require, "kernel.pkgsign")
  if not okS or not ps then
    return { state = "unsigned", reason = "signature support unavailable" }, nil
  end
  ps.init({ fs = fs, serialize = serialize, log = log })
  local verdict = ps.verifyManifest(manifestPath)

  if verdict.state == "invalid" then
    return verdict, "refusing to install '" .. tostring(manifestPath)
      .. "': its signature does not verify (" .. tostring(verdict.reason)
      .. "). This is tampering or corruption, not a missing signature, and there is no override."
  end

  if verdict.state == "unsigned" and ps.requiresSignature() and not opts.allowUnsigned then
    return verdict, "refusing to install an unsigned package: this machine is set to "
      .. "require signatures (pkg trust require off, or --allow-unsigned for one install)."
  end

  return verdict, nil
end

pkg._signGate = signGate

function pkg._verificationGate(m, allowUnverified)
  local files = (m and m.files) or {}
  local haveHashes = type(m and m.hashes) == "table"
  local complete = haveHashes
  if haveHashes then
    for _, target in ipairs(files) do
      if type(m.hashes[target]) ~= "string" then complete = false; break end
    end
  end
  if complete then return true, nil, true end
  if allowUnverified then return true, nil, false end
  local why = haveHashes and "manifest is missing hashes for some files"
    or "manifest declares no file hashes"
  return false, "refusing to install unverified package '" .. tostring(m and m.name)
    .. "' (" .. why .. "). Re-run with --allow-unverified to override.", false
end

function pkg.install(srcDir, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  if type(srcDir) ~= "string" or srcDir == "" then
    return false, "invalid source directory"
  end
  srcDir = fs.normalize(srcDir)

  local m, source, manifestPath = loadAnyManifest(srcDir)
  if not m then return false, "no manifest in " .. srcDir .. ": " .. tostring(source) end
  if source == "oppm" then

    m.origin = "openos"
    if type(m.capabilities) ~= "table" or #m.capabilities == 0 then
      m.capabilities = pkg.foreignDefaultCaps()
      m.capsFromCompat = true
      if log then
        log.warn("pkg", "Foreign (OpenOS/OPPM) package '" .. tostring(m.name)
          .. "' declared no capabilities — granting the compat surface: "
          .. table.concat(m.capabilities, ", "))
      end
    end
    if log then
      log.info("pkg", "Loaded OPPM-compat manifest for " .. tostring(m.name))
    end
  end

  local licOk, licErr = pkg.verifyLicenseKey(m, opts.licenseKey)
  if not licOk then
    return false, "license check failed: " .. tostring(licErr)
  end
  local ok, vErr = validateManifest(m)
  if not ok then return false, "invalid manifest: " .. vErr end

  if installed[m.name] and not opts.upgrading then
    local cur = installed[m.name].version
    local cmp = pkg.compareVersion(m.version or "0.0.0", cur or "0.0.0")
    if cmp > 0 then
      return false, string.format(
        "%s %s is already installed and %s is newer — use `pkg upgrade %s`",
        m.name, tostring(cur), tostring(m.version), m.name)
    end
    return false, "already installed (uninstall first): " .. m.name
  end

  local conflicts = pkg.findConflicts(m, opts.upgrading and m.name or nil)
  if #conflicts > 0 and not opts.force then
    return false, "conflicts: " .. pkg.describeConflicts(conflicts)
  end
  if #conflicts > 0 and log then
    log.warn("pkg", "Installing " .. tostring(m.name) .. " over conflicts (--force): "
      .. pkg.describeConflicts(conflicts))
  end

  do
    local ok2, reason, complete = pkg._verificationGate(m, opts.allowUnverified)
    if not ok2 then return false, reason end
    if not complete and opts.allowUnverified and log then
      log.warn("pkg", "Installing UNVERIFIED package '" .. tostring(m.name)
        .. "' (no/partial hashes) — operator override")
    end
  end

  local sigVerdict
  do
    local verdict, refusal = signGate(manifestPath, opts)
    if refusal then return false, refusal end
    sigVerdict = verdict
    if log then
      if verdict.state == "trusted" then
        log.info("pkg", "'" .. tostring(m.name) .. "' signed by trusted publisher '"
          .. tostring(verdict.label) .. "' (" .. tostring(verdict.fingerprint) .. ")")
      elseif verdict.state == "unknown" then

        log.warn("pkg", "'" .. tostring(m.name) .. "' is signed by an UNTRUSTED key "
          .. tostring(verdict.fingerprint) .. " — 'pkg trust add <name> " .. tostring(verdict.key) .. "'")
      else
        log.warn("pkg", "'" .. tostring(m.name)
          .. "' is UNSIGNED — installed on admin privilege alone")
      end
    end
  end

  local cryptoMod = nil
  if type(m.hashes) == "table" then
    local okC, c = pcall(require, "kernel.crypto")
    if not okC or not c or not c.hash or not c.ctEquals then
      return false, "crypto unavailable; cannot verify install hashes"
    end
    cryptoMod = c
  end

  local copied = {}
  for _, target in ipairs(m.files) do

    do
      local okP, procMod = pcall(require, "kernel.process")
      if okP and procMod and procMod.yieldCooperative then procMod.yieldCooperative() end
    end

    local mapped = m.fileMap and m.fileMap[target]
    local src
    if mapped then
      src = fs.normalize((m._srcBase or srcDir) .. "/" .. mapped)
    else

      src = fs.normalize(srcDir .. target)
    end
    local data = fs.readFile(src)
    if not data then

      for _, p in ipairs(copied) do pcall(fs.remove, p) end
      return false, "missing source file: " .. src
    end

    if cryptoMod then
      local expected = m.hashes[target]
      if expected then
        if not cryptoMod.ctEquals(cryptoMod.hash(data), expected) then
          for _, p in ipairs(copied) do pcall(fs.remove, p) end
          return false, "hash mismatch on " .. target
        end
      end
    end
    local writeOk, writeErr = fs.writeFile(target, data)
    if not writeOk then
      for _, p in ipairs(copied) do pcall(fs.remove, p) end
      return false, "write failed for " .. target .. ": " .. tostring(writeErr)
    end
    copied[#copied + 1] = target
  end

  local destDir = fs.join(PKG_ROOT, m.name)
  if not fs.exists(destDir) then fs.makeDirectory(destDir) end

  m._unverified = (type(m.hashes) ~= "table") and true or nil
  do
    local files = m.files or {}
    if type(m.hashes) == "table" then
      for _, target in ipairs(files) do
        if type(m.hashes[target]) ~= "string" then m._unverified = true break end
      end
    end
  end
  m._installedFrom = tostring(srcDir)

  m._sigState = sigVerdict and sigVerdict.state or "unsigned"
  m._sigKey   = sigVerdict and sigVerdict.key or nil
  m._sigLabel = sigVerdict and sigVerdict.label or nil

  local saveOk, saveErr = serialize.saveFile(fs, fs.join(destDir, "package.lua"), m)
  if not saveOk then

    for _, p in ipairs(copied) do pcall(fs.remove, p) end
    return false, "manifest write failed: " .. tostring(saveErr)
  end

  local defaultEnabled = "e"
  if type(m.service) == "table" and m.service.defaultState == "disabled" then
    defaultEnabled = "d"

    for _, target in ipairs(m.files) do
      local stem = tostring(target):match("^/etc/rc%.d/(.+)%.lua$")
      if stem then
        pcall(fs.writeFile, "/etc/rc.d/" .. stem .. ".disabled", "1")
      end
    end
  end
  fs.writeFile(fs.join(destDir, "state"), defaultEnabled)

  installed[m.name] = m

  pkg.syncCriticalBackup()

  if log then
    log.info("pkg", string.format("Installed %s v%s (%d files)",
      m.name, m.version, #copied))
  end

  local reqOk, missing = pkg.checkRequires(m.name)
  if not reqOk and log then
    log.warn("pkg", string.format("%s installed with unmet requires: %s",
      m.name, table.concat(missing, ", ")))
  end
  if not reqOk then
    return true, #copied .. " files (unmet requires: "
      .. table.concat(missing, ", ") .. ")"
  end
  return true, #copied .. " files"
end

function pkg.installWithDeps(repoDir, targetName, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  if type(repoDir) ~= "string" or repoDir == "" then
    return false, "invalid repo dir"
  end
  if type(targetName) ~= "string" or targetName == "" then
    return false, "invalid target name"
  end
  repoDir = fs.normalize(repoDir)
  if not fs.exists(repoDir) or not fs.isDirectory(repoDir) then
    return false, "repo dir not found: " .. repoDir
  end

  local manifestCache = {}
  local function lookup(name)
    if installed[name] then return installed[name] end
    if manifestCache[name] then return manifestCache[name] end
    local pkgSrc = fs.join(repoDir, name)
    if not fs.exists(pkgSrc) then return nil end
    local m = loadAnyManifest(pkgSrc)
    if m then manifestCache[name] = m end
    return m
  end

  local order, resolveErr = pkg.resolveInstallOrder(targetName, lookup)
  if not order then return false, "resolve failed: " .. tostring(resolveErr) end

  local installedList, skippedList = {}, {}
  for _, name in ipairs(order) do
    if installed[name] then
      skippedList[#skippedList + 1] = name
    else
      local pkgSrc = fs.join(repoDir, name)

      local perPkgKey = opts.licenseKey
      if opts.licenseKeys and opts.licenseKeys[name] then
        perPkgKey = opts.licenseKeys[name]
      elseif name ~= targetName then
        perPkgKey = nil
      end

      local ok, err = pkg.install(pkgSrc, { licenseKey = perPkgKey, session = opts.session,
        allowUnverified = opts.allowUnverified })
      if not ok then

        for _, prev in ipairs(installedList) do
          pcall(pkg.uninstall, prev, { session = opts.session })
        end
        return false, "install of " .. name .. " failed: " .. tostring(err)
      end
      installedList[#installedList + 1] = name
    end
  end

  return true, { installed = installedList, skipped = skippedList }
end

function pkg.uninstall(name, opts)
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  if name == "tos-core" then
    return false, "refusing to uninstall tos-core"
  end
  local m = installed[name]
  if not m then return false, "not installed: " .. name end

  if not opts or not opts._internalUpgrade then
    for otherName, other in pairs(installed) do
      if otherName ~= name and type(other.requires) == "table" then
        for _, req in ipairs(other.requires) do
          if type(req) == "table" and req.name == name and not req.optional then
            return false, "required by " .. otherName
          end
        end
      end
    end
  end

  for _, target in ipairs(m.files or {}) do
    local rmOk, rmErr = pcall(fs.remove, target)
    if not rmOk and log then
      log.warn("pkg", "Could not remove " .. target .. ": " .. tostring(rmErr))
    end
  end

  local destDir = fs.join(PKG_ROOT, name)
  local function rmrf(path)
    if fs.isDirectory(path) then
      local entries = fs.list(path) or {}
      for _, n in ipairs(entries) do
        local clean = n:gsub("/$", "")
        if clean ~= "" then rmrf(fs.join(path, clean)) end
      end
    end
    pcall(fs.remove, path)
  end
  rmrf(destDir)

  installed[name] = nil

  pkg.syncCriticalBackup()

  if log then log.info("pkg", "Uninstalled " .. name) end
  return true
end

local DEFAULT_REPO_ROOTS = {
  "/usr/repo",
  "/var/repo",
}

local function mountedRepoRoots()

  local mountPts, seenM = {}, {}
  local function addMount(p)
    if p and p ~= "" and p ~= "/" and not seenM[p] then
      seenM[p] = true; mountPts[#mountPts + 1] = p
    end
  end
  if fs.mounts then
    local ok, list = pcall(fs.mounts)
    if ok and type(list) == "table" then
      for _, m in ipairs(list) do addMount(m.mountPoint) end
    end
  end
  if fs.exists("/mnt") then
    for _, label in ipairs(fs.list("/mnt") or {}) do
      local clean = label:gsub("/$", "")
      if clean ~= "" then addMount("/mnt/" .. clean) end
    end
  end

  local roots, seen = {}, {}
  local function add(p) if p and not seen[p] then seen[p] = true; roots[#roots + 1] = p end end
  for _, m in ipairs(mountPts) do
    add(m)
    for _, name in ipairs(fs.list(m) or {}) do
      local clean = name:gsub("/$", "")
      if clean ~= "" and not clean:find("[/\\]") then
        local sub = fs.join(m, clean)
        local okD, isDir = pcall(function() return fs.isDirectory(sub) end)
        if okD and isDir then add(sub) end
      end
    end
  end
  return roots
end

function pkg.repoRoots()
  local roots = {}
  for _, r in ipairs(DEFAULT_REPO_ROOTS) do roots[#roots + 1] = r end
  for _, r in ipairs(mountedRepoRoots()) do roots[#roots + 1] = r end
  return roots
end

function pkg.listRepo(repoDir)
  if type(repoDir) ~= "string" or repoDir == "" then return {} end
  repoDir = fs.normalize(repoDir)
  if not fs.exists(repoDir) or not fs.isDirectory(repoDir) then return {} end
  local out = {}
  local entries = fs.list(repoDir) or {}
  for _, name in ipairs(entries) do
    local clean = name:gsub("/$", "")
    if clean ~= "" then
      local pkgDir = fs.join(repoDir, clean)
      if fs.isDirectory(pkgDir) then
        local m, source = loadAnyManifest(pkgDir)
        if m then
          out[#out + 1] = {
            name        = m.name,
            version     = m.version,
            description = m.description,

            category    = (type(m.category) == "string" and m.category ~= "")
                          and m.category or "misc",
            author      = m.author,
            kind        = m.kind,
            source      = source,
            dir         = pkgDir,

            requires    = m.requires,
            recommends  = m.recommends,
          }
        end
      end
    end
  end
  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  return out
end

function pkg.findInRepos(targetName, extraRoots)
  local roots = {}
  for _, r in ipairs(DEFAULT_REPO_ROOTS) do roots[#roots + 1] = r end
  if type(extraRoots) == "table" then
    for _, r in ipairs(extraRoots) do roots[#roots + 1] = r end
  end

  for _, root in ipairs(mountedRepoRoots()) do roots[#roots + 1] = root end
  for _, root in ipairs(roots) do
    local pkgDir = fs.join(root, targetName)
    if fs.exists(pkgDir) and fs.isDirectory(pkgDir) then
      local m = loadAnyManifest(pkgDir)

      if m and m.name == targetName then return pkgDir, root end
      if m and log then
        log.warn("pkg", "Ignoring '" .. tostring(targetName) .. "' in " .. root ..
          ": manifest name '" .. tostring(m.name) .. "' does not match directory")
      end
    end
  end
  return nil
end

function pkg.installByName(targetName, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end

  local root
  if type(targetName) == "string" and targetName:find("/") then
    local cand = fs.normalize(targetName:gsub("/$", ""))
    local base = cand:match("[^/]+$")
    if base and fs.exists(cand) and fs.isDirectory(cand) then
      local m = loadAnyManifest(cand)
      if m and m.name == base then
        root = cand:match("^(.*)/[^/]+$"); if root == "" then root = "/" end
        targetName = base
      else
        return false, "not a package directory (or name mismatch): " .. targetName
      end
    else
      return false, "package not found in any repo: " .. targetName
    end
  end
  if not root then
    local pkgDir
    pkgDir, root = pkg.findInRepos(targetName, opts.extraRoots)
    if not pkgDir then
      return false, "package not found in any repo: " .. targetName
    end
  end

  return pkg.installWithDeps(root, targetName, {
    licenseKey      = opts.licenseKey,
    licenseKeys     = opts.licenseKeys,
    session         = opts.session,
    allowUnverified = opts.allowUnverified,
  })
end

function pkg.computeLicenseHash(packageName, userKey)
  if type(packageName) ~= "string" or type(userKey) ~= "string" then
    return nil, "package name and key must be strings"
  end
  local okC, cryptoMod = pcall(require, "kernel.crypto")
  if not okC or not cryptoMod or not cryptoMod.hash then
    return nil, "crypto unavailable"
  end
  return cryptoMod.hash(packageName .. "|" .. userKey)
end

function pkg.listAllAvailable()
  local seen = {}
  local out = {}
  local function addFrom(root)
    if not fs.exists(root) or not fs.isDirectory(root) then return end
    for _, e in ipairs(pkg.listRepo(root)) do
      if not seen[e.name] then
        seen[e.name] = true
        e.root = root
        out[#out + 1] = e
      end
    end
  end
  for _, r in ipairs(DEFAULT_REPO_ROOTS) do addFrom(r) end
  for _, root in ipairs(mountedRepoRoots()) do addFrom(root) end
  return out
end

function pkg.installFromFloppy(opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end

  local confirm = (type(opts.confirm) == "function") and opts.confirm
    or function() return false end
  local installed_pkgs = {}
  local skipped_pkgs = {}

  for _, mountPath in ipairs(mountedRepoRoots()) do
    for _, entry in ipairs(pkg.listRepo(mountPath)) do
      if confirm(entry.name, entry.dir) then
        local ok, err = pkg.installByName(entry.name,
          { extraRoots = { mountPath }, session = opts.session })
        if ok then installed_pkgs[#installed_pkgs + 1] = entry.name
        else skipped_pkgs[#skipped_pkgs + 1] = entry.name .. " (" .. tostring(err) .. ")" end
      else
        skipped_pkgs[#skipped_pkgs + 1] = entry.name .. " (declined)"
      end
    end
  end
  return true, { installed = installed_pkgs, skipped = skipped_pkgs }
end

function pkg.runInstaller(opts)

  pcall(require, "io")

  local okM, picker = pcall(require, "shell.pkgpicker")
  if not okM or type(picker) ~= "table" or not picker.run then
    return false, "picker unavailable: " .. tostring(picker)
  end

  local ok, res, why = pcall(picker.run, opts)
  if not ok then return false, "installer error: " .. tostring(res) end

  if res == false then return false, why or "no installable packages found" end
  return true
end

local SELF_PKG = { ["tos-core"] = true }

function pkg.exportDisk(targetDir, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  if type(targetDir) ~= "string" or targetDir == "" then
    return false, "invalid target directory"
  end
  targetDir = fs.normalize(targetDir)
  if not targetDir then return false, "invalid target path" end

  local FORBIDDEN = { "/", "/tos", "/etc", "/var", "/usr", "/home",
                      "/root", "/public", "/init.lua", "/bios.lua" }
  for _, p in ipairs(FORBIDDEN) do
    if targetDir == p or targetDir:sub(1, #p + 1) == p .. "/" then
      return false, "refusing to export into a system path: " .. targetDir
    end
  end
  if not fs.exists(targetDir) or not fs.isDirectory(targetDir) then
    return false, "target does not exist or is not a directory: " .. targetDir
  end

  local only = nil
  if type(opts.only) == "table" and #opts.only > 0 then
    only = {}
    for _, n in ipairs(opts.only) do only[n] = true end
  end

  local exported, fileCount, problems = {}, 0, {}

  local names = {}
  for name in pairs(installed) do names[#names + 1] = name end
  table.sort(names)

  for _, name in ipairs(names) do
    local m = installed[name]
    if not SELF_PKG[name] and (not only or only[name]) then
      local pkgDir = fs.join(targetDir, name)
      local okM, mErr = serialize.saveFile(fs, fs.join(pkgDir, "package.lua"), m)
      if not okM then
        problems[#problems + 1] = name .. ": manifest write failed (" .. tostring(mErr) .. ")"
      else
        local clean = true
        for _, target in ipairs(m.files or {}) do
          local data = fs.readFile(target)
          if not data then
            problems[#problems + 1] = name .. ": missing installed file " .. target
            clean = false
          else

            local wOk, wErr = fs.writeFile(fs.join(pkgDir, target), data)
            if not wOk then
              problems[#problems + 1] = name .. ": write " .. target .. " (" .. tostring(wErr) .. ")"
              clean = false
            else
              fileCount = fileCount + 1
            end
          end
        end
        if clean then exported[#exported + 1] = name end
      end
    end
  end

  if only then
    for n in pairs(only) do
      if not installed[n] then
        problems[#problems + 1] = n .. ": not installed (skipped)"
      elseif SELF_PKG[n] then
        problems[#problems + 1] = n .. ": is the OS core, not an add-on (skipped)"
      end
    end
  end

  do
    local lines = {
      "-- Optional Utilities set manifest — generated by `pkg make-disk`.",
      "return {",
      "  set = \"optional-utilities\",",
      "  disks = 1,",
      "  packages = {",
    }
    for _, n in ipairs(exported) do
      local m = installed[n] or {}
      local reqs, recs = {}, {}
      for _, r in ipairs(m.requires or {}) do
        local rn = (type(r) == "table") and r.name or tostring(r):match("^(%S+)")
        if rn then reqs[#reqs + 1] = string.format("%q", rn) end
      end
      for _, r in ipairs(m.recommends or {}) do
        recs[#recs + 1] = string.format("%q", tostring(r))
      end
      lines[#lines + 1] = string.format(
        "    [%q] = { disk = 1, version = %q, category = %q, kind = %q,",
        n, tostring(m.version or "?"), tostring(m.category or "misc"),
        tostring(m.kind or "?"))
      lines[#lines + 1] = string.format("      description = %q,",
        tostring(m.description or ""))
      lines[#lines + 1] = string.format(
        "      requires = { %s }, recommends = { %s } },",
        table.concat(reqs, ", "), table.concat(recs, ", "))
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    local sOk, sErr = fs.writeFile(fs.join(targetDir, "optutil-set.lua"),
      table.concat(lines, "\n"))
    if not sOk then
      problems[#problems + 1] = "optutil-set.lua: " .. tostring(sErr)
    end
  end
  do
    local readme = table.concat({
      "TOS Optional Utilities",
      "",
      "Insert this disk on a TOS machine and run, as admin:",
      "",
      "    pkg install",
      "",
      "That opens the picker: tick what you want, press Enter.",
      "",
      "Non-interactive (scripts):",
      "    pkg install <name> [<name>...]",
      "    pkg install --all --yes",
      "",
    }, "\n")
    local rOk, rErr = fs.writeFile(fs.join(targetDir, "README.txt"), readme)
    if not rOk then problems[#problems + 1] = "README.txt: " .. tostring(rErr) end
  end

  if log then
    log.info("pkg", string.format("Exported %d package(s), %d file(s) to %s",
      #exported, fileCount, targetDir))
  end
  return true, { packages = exported, files = fileCount,
                 problems = problems, target = targetDir }
end

pkg.PKG_ROOT          = PKG_ROOT
pkg.CRITICAL_BACKUP   = CRITICAL_BACKUP
pkg.VALID_KINDS       = VALID_KINDS
pkg.DEFAULT_REPO_ROOTS = DEFAULT_REPO_ROOTS

pkg._validateManifest    = validateManifest
pkg._isUnderPkgWriteRoot = isUnderPkgWriteRoot
pkg._isServiceEtcTarget  = isServiceEtcTarget
pkg.PKG_WRITE_ROOTS      = PKG_WRITE_ROOTS

local function remoteMod()
  local ok, m = pcall(require, "kernel.pkgremote")
  if not ok or type(m) ~= "table" then return nil, "remote package support unavailable" end
  if m.init and log then pcall(m.init, { log = log }) end
  return m
end

--! The gate lives HERE and the storage lives in kernel.pkgsign, so there
--! is exactly one implementation of "may this caller change what this
--! machine trusts". Adding a publisher key is a standing decision about
--! where code comes from — the same class of decision as `pkg repo add`,
--! and gated the same way.

local function withSign()
  local okS, ps = pcall(require, "kernel.pkgsign")
  if not okS or not ps then return nil, "signature support unavailable" end
  ps.init({ fs = fs, serialize = serialize, log = log })
  return ps
end

function pkg.trustList()
  local ps = withSign(); if not ps then return {} end
  return ps.listKeys()
end

function pkg.trustAdd(label, pubHex, opts)
  local g, gErr = adminGate(opts); if not g then return false, gErr end
  local ps, e = withSign(); if not ps then return false, e end
  return ps.addKey(label, pubHex)
end

function pkg.trustRemove(label, opts)
  local g, gErr = adminGate(opts); if not g then return false, gErr end
  local ps, e = withSign(); if not ps then return false, e end
  return ps.removeKey(label)
end

function pkg.trustRequire(on, opts)
  local g, gErr = adminGate(opts); if not g then return false, gErr end
  local ps, e = withSign(); if not ps then return false, e end
  return ps.setRequireSignature(on)
end

function pkg.trustRequired()
  local ps = withSign(); if not ps then return false end
  return ps.requiresSignature()
end

function pkg.checkSignature(srcDir)
  if type(srcDir) ~= "string" or srcDir == "" then return nil, "invalid directory" end
  local ps, e = withSign(); if not ps then return nil, e end
  local m, source, manifestPath = loadAnyManifest(fs.normalize(srcDir))
  if not m then return nil, "no manifest in " .. srcDir .. ": " .. tostring(source) end
  return ps.verifyManifest(manifestPath), m
end

--! `opts.signer` is REQUIRED: it is the KDF salt, not decoration. Signing
--! without it would derive a different key than signing with it, so the
--! same passphrase would produce two identities depending on whether a
--! flag was typed.
function pkg.signPackage(srcDir, passphrase, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts); if not g then return nil, gErr end
  local ps, e = withSign(); if not ps then return nil, e end
  if type(srcDir) ~= "string" or srcDir == "" then return nil, "invalid directory" end
  local m, source, manifestPath = loadAnyManifest(fs.normalize(srcDir))
  if not m then return nil, "no manifest in " .. srcDir .. ": " .. tostring(source) end
  local seed, sErr = ps.seedFromPassphrase(passphrase, opts.signer)
  if not seed then return nil, sErr end
  --! Record the NORMALIZED label, so what the signature says its
  --! publisher is matches the string that actually salted the key.
  return ps.signManifest(manifestPath, seed, { signer = ps.normalizeLabel(opts.signer) })
end

function pkg.signingKey(passphrase, label)
  local ps, e = withSign(); if not ps then return nil, e end
  local seed, sErr = ps.seedFromPassphrase(passphrase, label)
  if not seed then return nil, sErr end
  local okE, ed = pcall(require, "kernel.ed25519")
  if not okE or not ed then return nil, "ed25519 support unavailable" end
  local pub = ed.publickey(seed)
  if not pub then return nil, "cannot derive the key" end
  return ps.binToHex(pub)
end

function pkg.repos()
  local m = remoteMod()
  if not m then return {} end
  return m.repos()
end

function pkg.addRepo(name, url, description, opts)
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  local m, mErr = remoteMod()
  if not m then return false, mErr end
  return m.addRepo(name, url, description)
end

function pkg.removeRepo(name, opts)
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  local m, mErr = remoteMod()
  if not m then return false, mErr end
  return m.removeRepo(name)
end

function pkg.searchRemote(opts)
  local m = remoteMod()
  if not m then return {} end
  return m.search(opts)
end

function pkg.installRemote(name, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)
  if not g then return false, gErr end
  local m, mErr = remoteMod()
  if not m then return false, mErr end

  local pkgDir, err, meta = m.fetch(name, opts)
  if not pkgDir then return false, err end

  --! The fetched package reaches install through the SAME door as a
  --! floppy. In particular the hash gate is unchanged: an index that
  --! ships no hashes is unverified code, and installing it still requires
  --! the operator to have said --allow-unverified. Remote provenance is
  --! not a reason to relax that — it is the reason it exists.
  local ok, iErr = pkg.install(pkgDir, opts)
  m.cleanup(pkgDir)
  if not ok then return false, iErr end
  if log then
    log.info("pkg", "Installed '" .. tostring(name) .. "' from repo '"
      .. tostring(meta and meta.repo) .. "'")
  end
  return true, meta
end

do
  local T = rawget(_G, "_TOS")
  if T and T.fs and not fs then

    if T.pkgDispatchDisabled then
      pkg.setDispatchEnabled(false)
    end
    if pcall(pkg.init, {
      fs = T.fs, log = T.logObj, event = T.event, users = T.users,
    }) then
      pcall(pkg.syncCriticalBackup)
    end
  end
end

return pkg
