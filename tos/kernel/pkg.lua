-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Package Manager                            ║
-- ║                                                          ║
-- ║  Reads package manifests from /var/pkg/installed/<n>/    ║
-- ║  package.lua, exposes install/uninstall/enable/disable   ║
-- ║  primitives, and surfaces capability + dependency        ║
-- ║  metadata for the sandbox to consume in phase 2.         ║
-- ║                                                          ║
-- ║  This module is the foundation of the optional-utilities ║
-- ║  architecture. As of v1.3.1 it fully REPLACES the legacy ║
-- ║  module manager: install/enable/uninstall + command      ║
-- ║  dispatch (pkg.getCommand) all live here; kernel.modules ║
-- ║  is gone.                                                ║
-- ╚══════════════════════════════════════════════════════════╝

local pkg = {}

local PKG_ROOT        = "/var/pkg/installed"
local CRITICAL_BACKUP = "/etc/critical.bak"

-- Module dependencies (set during pkg.init)
local fs        = nil
local log       = nil
local serialize = nil
local users     = nil

-- name → manifest (loaded at init / scan)
local installed = {}

-- #SEC CR-5 — privilege gate for install/uninstall/enable. The audit
-- found NO caller verified admin, so inserted media or a sandboxed
-- program could install code, write to system paths, or toggle packages.
-- `adminGate(opts)` requires the caller's session to be ADMIN+ (or a
-- kernel/login pseudo-session). The session is threaded explicitly via
-- opts.session (the shell passes its seat-bound session); we fall back to
-- users.currentSession() for process-bound callers. When no users module
-- is wired (early boot / standalone tests) the gate is inert.
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

-- ============================================================
-- Validation
-- ============================================================

local VALID_KINDS = {
  app     = true,  -- runs on launch (e.g. panels)
  command = true,  -- a shell command / runnable program (tetris, tape, rc).
                   -- Also the OPPM idiom, so native + OPPM manifests agree.
  program = true,  -- alias many OPPM authors use for the same idea
  lib     = true,  -- pure library, loaded via require
  service = true,  -- has rc.d entry, lifecycle hooks
  runtime = true,  -- broader-than-lib system layer (e.g. compat)
  driver  = true,  -- raw component access; highest risk
  theme   = true,  -- data only, no code
}

-- name = alphanumerics + dashes; nothing else allowed.
-- Path separators, dots, leading/trailing dashes are all rejected
-- so a malicious manifest can't create a /var/pkg/installed/../etc
-- directory and clobber config.
local function validName(s)
  if type(s) ~= "string" then return false end
  if s == "" or #s > 64 then return false end
  if s == "." or s == ".." then return false end  -- traversal guard
  if #s == 1 then return s:match("^[%w]$") ~= nil end
  -- 2+ chars: must start and end with alphanumeric; dashes only between.
  return s:match("^[%w][%w%-]*[%w]$") ~= nil
end

-- #SEC H14 — reject any path that contains a traversal ("..") or
-- current-dir (".") segment, a NUL byte, or backslashes. files[] /
-- critical[] entries are absolute install targets that pkg.install
-- both READS (fs.normalize(srcDir .. target)) and WRITES (target). A
-- manifest entry like "/../../etc/users.dat" otherwise passes the
-- "starts with /" check, escapes the source dir on read, and clobbers
-- a system file on write. Requiring canonical, traversal-free segments
-- keeps a declared path identical to where it actually lands.
local function pathHasTraversal(p)
  if type(p) ~= "string" then return true end
  if p:find("\0", 1, true) then return true end
  if p:find("\\", 1, true) then return true end
  for seg in p:gmatch("[^/]+") do
    if seg == "." or seg == ".." then return true end
  end
  return false
end

-- #SEC CR-4 — write-root allowlist. pkg.install writes each files[] entry
-- to its declared ABSOLUTE path. pathHasTraversal already blocks "../"
-- escapes, but an entry like "/tos/kernel/sandbox.lua" is traversal-free
-- and would overwrite the kernel (inserted-media → full compromise).
-- Confine package writes to package-owned roots so a manifest can never
-- target /tos, /etc, /boot, etc. Roots are matched on a normalized,
-- segment-boundary basis so "/usr-evil/x" can't masquerade as "/usr".
local PKG_WRITE_ROOTS = { "/usr/", "/var/pkg/" }
local function isUnderPkgWriteRoot(p)
  if type(p) ~= "string" or p == "" then return false end
  for _, root in ipairs(PKG_WRITE_ROOTS) do
    -- root carries its trailing slash; require at least one path segment
    -- after it (no writing the root dir itself).
    if p:sub(1, #root) == root and #p > #root then return true end
  end
  return false
end

-- #SEC CR-4 (narrow service exception) — a kind="service" package must be
-- able to register itself: drop ONE rc.d entry and ONE top-level cfg under
-- /etc. We permit exactly those two shapes and nothing else, so the audit's
-- actual concern (inserted media overwriting the KERNEL or the shadow DB) is
-- untouched: /tos, /init.lua, /etc/users.dat (.dat, not .cfg) and every other
-- /etc path stay rejected. Single path segment + fixed extension only
-- (pathHasTraversal already ran). The rc.d service a package installs runs in
-- the user-tier sandbox — the _kernel_ tier allowlist is hardcoded elsewhere —
-- and the file is still admin-gated (CR-5) and hash-verified (CR-4) on install.
local function isServiceEtcTarget(p)
  if type(p) ~= "string" then return false end
  if p:match("^/etc/rc%.d/[%w_%-]+%.lua$") then return true end   -- rc.d entry
  if p:match("^/etc/[%w_%-]+%.cfg$")        then return true end   -- top-level cfg
  return false
end

-- Loose semver-ish: accept "1.2.3", "1.2", "1", "1.2.3-beta", etc.
-- The version comparator (phase 2) parses out leading numerics; for
-- now we just refuse obvious garbage.
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
  -- files entries must all be absolute paths (so install/uninstall can't
  -- be tricked into walking out of the install root).
  for i, p in ipairs(m.files) do
    if type(p) ~= "string" or p:sub(1, 1) ~= "/" then
      return false, "files[" .. i .. "] is not an absolute path"
    end
    if pathHasTraversal(p) then
      return false, "files[" .. i .. "] contains an unsafe path segment"
    end
    -- #SEC CR-4 — confine writes to package-owned roots, plus the narrow
    -- /etc rc.d+cfg exception for service packages (isServiceEtcTarget).
    if not isUnderPkgWriteRoot(p)
       and not (m.kind == "service" and isServiceEtcTarget(p)) then
      return false, "files[" .. i .. "] must be under " ..
        table.concat(PKG_WRITE_ROOTS, " or ") ..
        " (service packages may also write /etc/rc.d/<f>.lua and /etc/<name>.cfg) (got "
        .. p .. ")"
    end
  end
  -- fileMap: optional target → SOURCE-path map, used when a package's
  -- files are not laid out at their install paths (an OPPM repo keeps
  -- them under master/<pkg>/...). Absent for native TOS packages, where
  -- source and target are the same path.
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

  -- #SEC CR-4 — if the manifest declares hashes, they must be a table of
  -- 64-hex digests. (Per-file presence/verification happens at install.)
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
    -- #SEC H14 — critical[] entries are absolute paths that /init.lua's
    -- boot verification reads and can restore from backup; apply the
    -- same traversal-free, absolute-path rule as files[].
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
  -- `recommends` is the SOFT counterpart of `requires`: packages that make
  -- this one better but are not needed for it to work. The installer offers
  -- them; nothing ever installs one behind the operator's back, and a
  -- missing recommendation is never an error. Deliberately just names — a
  -- version constraint on something optional is a promise we'd have to keep.
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
  -- `conflicts` — packages that must NOT be installed alongside this one
  -- (two drivers for the same device, two shells claiming the same command).
  -- Names only: a version-scoped conflict is a promise we would have to keep
  -- across upgrades, and the honest answer for a genuine incompatibility is
  -- "not together".
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
  -- Optional screen-size request: a program declares the resolution it wants
  -- (kernel.screen fits the display to it, or warns if it can't). Both fields
  -- are positive integers. mode is "exact" (default) or "min".
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
  -- EXP-1 — `provides` lets a renamed package claim its old name(s).
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
  -- FEAT-14 — optional soft-DRM. Author publishes a list of acceptable
  -- key-hash values; a user with one of the matching keys can install.
  -- Verification: hash(name || "|" || userKey) must equal one of the
  -- listed hex64 strings. The hex64s are NOT secrets — they're the
  -- public commitment. Keys ARE secrets.
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

-- ============================================================
-- Capability string parser
-- ============================================================
-- Format: "<facet>" or "<facet>:<scope>"
--   "fs.read"          → { facet = "fs.read" }
--   "fs.read:/home"    → { facet = "fs.read", scope = "/home" }
--   "net.listen:PONG"  → { facet = "net.listen", scope = "PONG" }
--
-- The parser is forgiving on input (trims whitespace, accepts colon-less
-- form) but strict on output structure: bad strings return nil + error
-- and the caller skips them rather than crashing the whole package.

function pkg.parseCap(s)
  if type(s) ~= "string" then return nil, "not a string" end
  s = s:match("^%s*(.-)%s*$")  -- trim
  if s == "" then return nil, "empty" end

  local colon = s:find(":", 1, true)
  if not colon then
    -- Bare facet, no scope
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

-- ============================================================
-- Initialization
-- ============================================================

function pkg.init(deps)
  fs        = deps.fs
  log       = deps.log
  users     = deps.users  -- #SEC CR-5 — principal source for the admin gate
  serialize = require("kernel.serialize")

  if not fs then return false, "fs module required" end

  -- Ensure storage root exists. fs.makeDirectory in the kernel layer
  -- delegates to the OC proxy which creates parents recursively, so a
  -- single call covers /var, /var/pkg, /var/pkg/installed.
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

-- ============================================================
-- Manifest scan (rebuilds the in-memory installed table)
-- ============================================================

--- Re-scan /var/pkg/installed and refresh the in-memory table.
-- Call this after install/uninstall to pick up changes; pkg.install
-- and pkg.uninstall already do so internally.
function pkg.scan()
  installed = {}
  if not fs.exists(PKG_ROOT) then return 0 end
  local entries = fs.list(PKG_ROOT) or {}
  local count = 0
  for _, name in ipairs(entries) do
    -- fs.list trails directory entries with "/"; strip it so we get
    -- the bare package name.
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
          -- Defensive: the directory name and manifest.name MUST match.
          -- A mismatch means someone hand-edited the manifest or the
          -- install logic itself broke; either way we refuse to load
          -- a manifest from the wrong directory.
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

-- ============================================================
-- Read API
-- ============================================================

--- List all installed packages.
-- @return array of { name, version, kind, description, enabled }
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

--- Full manifest for a single package (or nil if not installed).
function pkg.info(name)
  return installed[name]
end

--- Whether a package is enabled. Default = true if no state file exists.
-- The state file is a single byte 'e' (enabled) or 'd' (disabled);
-- anything else, missing, or unreadable defaults to enabled.
function pkg.isEnabled(name)
  if not installed[name] then return false end
  local p = fs.join(PKG_ROOT, name, "state")
  if not fs.exists(p) then return true end
  local data = fs.readFile(p)
  if not data then return true end
  return data:sub(1, 1) ~= "d"
end

--- Mark a package enabled or disabled.
-- Service start/stop is the caller's responsibility — pkg.lua just
-- records the bit; rc.d hooks (commit 2) will read it and act.
function pkg.setEnabled(name, on, opts)
  local g, gErr = adminGate(opts)  -- #SEC CR-5
  if not g then return false, gErr end
  if not installed[name] then return false, "not installed: " .. name end
  local p = fs.join(PKG_ROOT, name, "state")
  return fs.writeFile(p, on and "e" or "d")
end

--- Merged map of shell command name → script path, restricted to
--- enabled packages. Used by the shell PATH resolver instead of
--- (or in addition to) the alphabetic /usr/bin scan.
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

--- Which enabled package provides shell command `name`? Returns the package
--- name, or nil.
--
-- Deliberately does NOT go through getCommand: that loads and caches the
-- package entry, i.e. runs the package's top-level code in a sandbox. Asking
-- "what would run?" must not be answered by running it — `which` is the
-- caller, and a question about a command should never have side effects.
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

-- ── Command execution (the kernel.modules pivot) ─────────────
-- Load a package's entry once, in a sandbox built from its declared
-- capabilities + the current session, and cache the returned module table.
-- Mirrors kernel.modules.enable()'s execution model so module-style packages
-- (an entry returning { commands = { name = fn } }) run under pkg WITHOUT the
-- legacy modules system. This is the dispatch path that lets pkg eventually
-- replace kernel.modules.
local pkgActive = {}  -- pkgName -> loaded module table (cache)

-- #SEC — capability allowlist for package-run code. ONLY these facets may be
-- requested by a manifest; anything else (notably "legacy", which unlocks raw
-- os/io and is "do anything") is silently dropped. Mirrors the old
-- kernel.modules ALLOWED_MANIFEST_CAPS exactly so the pivot doesn't reopen the
-- hole that allowlist closed.
local PKG_RUN_CAPS = {
  ["fs.read"] = true, ["fs.write"] = true, component = true,
  ["compat.io"] = true, load = true, net = true, swap = true,
  -- Outbound access to the real world (internet card). Allowed to be
  -- REQUESTED by a manifest — a package that fetches anything needs it —
  -- but it is not implied by `component`, so an operator installing a game
  -- is not also granting it the network. See sandbox.lua's threat note.
  internet = true,
  vault = true,  -- narrow passphrase-crypto surface (encrypt/decrypt/isEncrypted)
  crypto = true, -- hash/hmac/ctEquals/random + the per-package machine secret
  notify = true, -- raise a modal dialog box (post/result only; kernel.notify
                 -- rate-limits it and stamps the source from the pkg name)
  ["peripheral.modem"] = true, ["peripheral.redstone"] = true,
  ["peripheral.robot"] = true, ["peripheral.inventory"] = true,
  ["peripheral.tape"] = true, ["peripheral.tractor"] = true,
  ["peripheral.piston"] = true, ["peripheral.hologram"] = true,
  -- OpenPrinter, for the first-party `printer` driver package. Paired with
  -- sandbox.lua's `openprinter` gated component type — see the note there
  -- for why this one mod type is coded rather than left to config.
  ["peripheral.printer"] = true,
  -- "legacy" deliberately excluded — a manifest can never opt into raw os/io.
}

-- ============================================================
-- OVERRIDES AS DATA, DEFAULTS AS CODE — /etc/pkg_caps.cfg
-- ============================================================
-- The table above is the DEFAULT policy and stays code: it is the list a
-- reader should be able to audit in one sitting. What it cannot be is the
-- WHOLE policy, because of an asymmetry FEAT-5 left open:
-- /etc/component_caps.cfg lets an operator name a modded component type and
-- the cap that gates it, but a PACKAGE's declared caps are filtered through
-- PKG_RUN_CAPS, which is static. So an operator who added
-- `reactor_control -> peripheral.reactor` to component_caps.cfg could grant
-- that cap to a shell REPL and never to a package — the manifest's request
-- was silently dropped and the package ran without hardware, with no error
-- naming the reason. A cap you can add to one side and not the other is a
-- cap that does nothing.
--
-- Schema (decoded as DATA, never load()ed — a config is a table an operator
-- typed, and the /etc write gate is what makes it trustworthy, not its
-- syntax):
--   {
--     allow = { "peripheral.reactor", "peripheral.security" },
--     deny  = {
--       ["*"]       = { "internet" },   -- no package on this box, ever
--       ["someGame"] = { "net" },       -- this one package, specifically
--     },
--   }
--
-- WHAT IS DELIBERATELY ABSENT: there is no `grant`. KittenOS's settings can
-- pre-ANSWER a permission prompt because it asks at first use; TOS accepts a
-- manifest's declared set at install time and the manifest is the record of
-- what the package touches. Handing a package a facet it never declared
-- would make `pkg info` lie about it and would defeat the install-time
-- consent the admin gate exists to collect. Operators can WIDEN what may be
-- requested and NARROW what is honoured; they cannot request on a package's
-- behalf.
--
-- PRECEDENCE, in one line: deny beats allow beats the coded default, and a
-- per-package deny and a "*" deny are both absolute (there is nothing to
-- resolve between them — either one refuses).
--
-- FAIL-CLOSED: a file that will not read, will not decode, or is not a table
-- yields NO allow entries and NO deny entries, and logs at warn. Losing the
-- allow half is the safe direction (packages fall back to the coded
-- default). Losing the deny half is not, so it is loud: an operator who
-- wrote a veto needs to know it is not in force.
local PKG_CAPS_CFG = "/etc/pkg_caps.cfg"
local _capAllow  = {}   -- facet -> true, extends PKG_RUN_CAPS
local _capDeny   = {}   -- pkgName ("*" for all) -> { facet -> true }
local _capLoaded = false

local function loadCapConfig()
  if _capLoaded then return end
  _capLoaded = true  -- mark before trying, so a failure cannot loop
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
  -- A facet name has the same shape parseCap accepts, bounded.
  local function validFacet(f)
    return type(f) == "string" and #f <= 64 and f:match("^[%w%.]+$") ~= nil
  end
  if type(cfg.allow) == "table" then
    for _, f in ipairs(cfg.allow) do
      -- "legacy" is not negotiable. It unlocks raw os/io, i.e. everything
      -- the sandbox exists to withhold; an operator config must not be a
      -- route to it. Same for a bare "component" bypass of the gated split.
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

--- The coded default set, as a copy. Exists so nothing has to keep a
--- SECOND hand-written list of grantable facets in step with this one —
--- TOS-Extras' manifest lint did, and had already drifted: it rejected
--- `internet`, which pkg has granted since the internet-card round, so a
--- correct manifest would have failed the lint. A mirror of a security
--- allowlist is a mirror that goes stale silently.
function pkg.runCaps()
  local out = {}
  for facet in pairs(PKG_RUN_CAPS) do out[facet] = true end
  return out
end

--- Reload /etc/pkg_caps.cfg. Sibling of sandbox.reloadComponentConfig, and
--- reached the same way (`component reload-caps`). Already-loaded package
--- entries keep the cap set they were built with — flush the command cache
--- (or reboot) for a change to reach a package that has already run.
function pkg.reloadCapConfig()
  _capAllow, _capDeny, _capLoaded = {}, {}, false
  loadCapConfig()
  return _capAllow, _capDeny
end

--- Is `facet` permitted for package `pkgName`? Single auditable answer, so
--- every caller (the loader, `pkg info`, the install-time report) agrees.
--- @return boolean allowed, string|nil reason  reason is set only on a refusal
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
  -- Caps from the manifest's `capabilities` (facet strings, or "facet:scope"),
  -- filtered through the allowlist above before reaching the sandbox.
  local caps = {}
  if type(m.capabilities) == "table" then
    for _, c in ipairs(m.capabilities) do
      local parsed = pkg.parseCap(c)
      if parsed and parsed.facet then
        local allowed, why = pkg.capAllowed(pkgName, parsed.facet)
        if allowed then
          caps[parsed.facet] = true
        elseif log then
          -- A dropped cap used to be silent, which is how "the package
          -- installed fine and then did nothing" became a debugging session.
          -- Say which facet and why; an operator veto and an unknown facet
          -- are different problems.
          log.warn("pkg", "capability '" .. parsed.facet .. "' refused for " ..
            pkgName .. ": " .. tostring(why))
        end
      end
    end
  end
  -- #SEC — DO NOT capture a fixed session here. The sandbox env built below
  -- (including its securefs-bound `fs` proxy) is cached in `pkgActive` and
  -- REUSED for every later caller via pkg.getCommand. Binding it to whoever
  -- loaded the package FIRST (e.g. root, or the root-tier boot session) let a
  -- subsequently logged-in lower-tier user run the same command with the first
  -- loader's filesystem ACL — a confused-deputy privilege escalation for any
  -- package declaring fs.read/fs.write.
  --
  -- Passing NO session makes sandbox.build call securefs.forSession(nil), whose
  -- proxy appends no session to each call; securefs then resolves the LIVE
  -- running process's principal per-call (sessionOf -> process.currentSession),
  -- exactly as compat.filesystem already does. So a command's fs ops follow the
  -- actual caller, not the cache's first user, and fail closed (post-boot, no
  -- live session -> nil session -> access denied) rather than defaulting to
  -- root. The one-time entry `pcall(fn)` top-level still runs under whoever
  -- loads it, but that path returns the command table and is not a per-user
  -- privileged-fs surface; per-invocation command code is what callers reach.
  local okSB, sandbox = pcall(require, "kernel.sandbox")
  if not okSB or not sandbox or not sandbox.build then return nil end
  -- pkgName scopes the crypto cap's per-package machine secret. It comes
  -- from the validated manifest (validName), never from the entry code.
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
  -- #SEC — CAP SCOPE. Found in-game 2026-08-11, and it had been true of
  -- every peripheral cap since they were introduced.
  --
  -- A manifest's capabilities reached the SANDBOX (they filter
  -- component.proxy) and stopped there. But the kernel's peripheral
  -- modules — peripheral.redstone, peripheral.inventory, and now the
  -- printer driver — gate on `kernel.process.current().caps`, which is a
  -- DIFFERENT set: the caps of the running process. A package command
  -- runs inside the SHELL's process, whose caps are the fixed shellCaps
  -- list in kernel/init.lua, and that list contains no peripheral entry
  -- at all. So the gate could never open: `stock` could not read a
  -- chest, `printer` could not find a printer that hotplug had just
  -- logged, and the message blamed a missing capability the manifest
  -- plainly declared.
  --
  -- Fixing it by widening shellCaps alone would have been worse than the
  -- bug: every package command runs in that process, so all of them
  -- would have held every peripheral cap regardless of what they
  -- declared. Instead the process wears the PACKAGE's caps for exactly
  -- the duration of the call, and its own again afterwards. That is
  -- strictly narrower than the shell's set for anything the package did
  -- not ask for, and it makes the declared list mean what it says.
  --
  -- Nesting and yields are both safe: each wrapper restores the value it
  -- saved, and a coroutine that yields mid-call suspends this process
  -- entirely, so nothing else in it observes the narrowed set. A process
  -- SPAWNED during the call (a fullscreen program) intersects with the
  -- narrowed caps, which is exactly the intended inheritance.
  local scoped = {}
  for cmdName, fn2 in pairs(result.commands or {}) do
    if type(fn2) == "function" then
      scoped[cmdName] = function(...)
        local okP, procMod = pcall(require, "kernel.process")
        local cur = (okP and procMod and procMod.current) and procMod.current() or nil
        if not cur then return fn2(...) end   -- kernel context: unchanged
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

-- Safe Mode switch (#REV Boot Settings, Jul 2026): when the boot profile
-- gates `packages` off, package-PROVIDED commands stop dispatching — no
-- third-party code runs — while the pkg ADMIN verbs (list/info/install/
-- uninstall/enable/disable) keep working so a broken add-on can still be
-- removed. The kernel flips this at boot; nothing else should.
local dispatchEnabled = true
function pkg.setDispatchEnabled(on)
  dispatchEnabled = on and true or false
end
function pkg.dispatchEnabled() return dispatchEnabled end

--- Resolve a shell command name to a callable provided by an enabled
--- package, or nil. The package entry (returning { commands = { name = fn } })
--- is loaded once and cached. The shell's command dispatcher calls this as a
--- fallback after its built-ins.
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

--- The screen-size request declared by the package that provides `name`, or
--- nil. Shape: { width=, height=, mode="exact"|"min" }. The shell uses this to
--- fit the display before running the command and restore it afterwards.
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

--- Does the package that provides `name` declare it a FULL-SCREEN
--- program (manifest `fullscreen = true`)? Such a command is handed the
--- seat as its own process so the operator can suspend it and go back to
--- the shell; everything else keeps running inline in the shell exactly
--- as before. Opt-in on purpose: a third-party package that has never
--- heard of this is unaffected until it asks.
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

--- The BACKGROUND POLICY declared by the package that provides `name`.
--- A full-screen program that gets pushed to the background is resumed
--- at a reduced rate and then frozen (see kernel.process's background
--- lifecycle). A package may override that:
---
---   background = "drowsy"   (default) half rate, then frozen
---   background = "always"   half rate forever, never frozen
---   background = "freeze"   stops the moment you switch away
---
--- Anything else — including no declaration — resolves to "drowsy", so
--- a manifest typo degrades to the sane default rather than pinning a
--- program at full rate behind the operator's back.
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

--- Drop the loaded-entry cache (e.g. after uninstall/disable so a stale
--- command can't keep running). Internal; the lifecycle calls it.
function pkg.flushCommandCache(pkgName)
  if pkgName then pkgActive[pkgName] = nil else pkgActive = {} end
end

--- Parsed capabilities for a package. Returns an array of structured
--- entries ({facet=, scope=}); malformed strings are dropped with a
--- warning rather than failing the whole call.
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

--- Check that all required dependencies of `name` are installed.
--- Optional requires are silently skipped.
--- Version constraints are deferred to phase 2 (needs a semver parser).
--- @return ok, missing  where missing is an array of names
-- ============================================================
-- FEAT-7 — Version comparison + dependency resolution.
-- ============================================================
-- TOS versions are dotted decimal: "1.2.3" or "1.2.3-beta". We split
-- on dots and compare each segment numerically (with non-numeric
-- segments compared lexicographically as a fallback). Pre-release
-- suffixes ("-beta", "-rc1") sort BEFORE the release ("1.2.3-beta" <
-- "1.2.3") — matching semver expectations closely enough for the
-- relatively informal OC ecosystem.

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

--- Compare two version strings. Returns -1, 0, 1 like strcmp.
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
  -- Numeric parts equal: any suffix means pre-release (sorts BEFORE).
  if sa == "" and sb == "" then return 0 end
  if sa == "" then return 1   end
  if sb == "" then return -1  end
  if sa < sb then return -1 end
  if sa > sb then return 1  end
  return 0
end

--- Test a version against a constraint string.
-- Constraints supported (all space-tolerant):
--   ">=1.2"   ">1.2"   "<1.2"   "<=1.2"   "=1.2" / "==1.2"
--   "^1.2"   (compatible: same major, >= 1.2)
--   "~1.2.3" (compatible: same major+minor, >= 1.2.3)
-- No constraint at all (nil / "") matches any version.
function pkg.satisfiesConstraint(version, constraint)
  if not constraint or constraint == "" then return true end
  constraint = constraint:match("^%s*(.-)%s*$")
  local op, target = constraint:match("^(>=?)(.+)$")
  if not op then op, target = constraint:match("^(<=?)(.+)$") end
  if not op then op, target = constraint:match("^(==?)(.+)$") end
  if not op then op, target = constraint:match("^(%^)(.+)$") end
  if not op then op, target = constraint:match("^(~)(.+)$") end
  if not op then
    -- Bare version is treated as exact equality.
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
    -- ^1.2.3 matches >=1.2.3 and same major
    if cmp < 0 then return false end
    local va = splitVersion(version); local vt = splitVersion(target)
    if not va or not vt then return false end
    return (va[1] or 0) == (vt[1] or 0)
  end
  if op == "~" then
    -- ~1.2.3 matches >=1.2.3 and same major+minor
    if cmp < 0 then return false end
    local va = splitVersion(version); local vt = splitVersion(target)
    if not va or not vt then return false end
    return (va[1] or 0) == (vt[1] or 0) and (va[2] or 0) == (vt[2] or 0)
  end
  return false
end

-- EXP-1 — build a name → providing-package map so `requires = "tape-storage"`
-- can be satisfied by a package whose `provides = { "tape-storage" }` list
-- includes it. The canonical name still wins (an explicitly-installed
-- "tape-storage" beats a "tape" that also provides it).
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
    -- Support two shapes:
    --   1. Table form: { name = "tape-storage", version = ">=1.0", optional = false }
    --   2. String form: "tape-storage" or "tape-storage >=1.0"
    -- The string form keeps OPPM-style manifests usable.
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
      -- EXP-1 — check both canonical name and `provides` entries.
      local dep = findProvider(reqName)
      if not dep then
        if not optional then
          missing[#missing + 1] = reqName ..
            (reqConstraint and (" (" .. reqConstraint .. ")") or "")
        end
      elseif reqConstraint then
        -- Dep is installed; check the version constraint.
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

--- Resolve install order for a target package, given a `lookup`
--- function `lookup(name) -> manifest` that knows about both
--- already-installed packages and packages-available-to-install.
--- Returns (order, err) where `order` is an array of package names
--- in the order they should be installed. Cycles cause an error.
function pkg.resolveInstallOrder(targetName, lookup)
  local order = {}
  local visiting = {}   -- name -> true while in DFS stack (cycle detection)
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
          -- Already-installed packages don't need to be reinstalled —
          -- skip them in the resolved order. Also accept anything in
          -- the `provides` set of an installed package (EXP-1).
          if not findProvider(depName) then
            local ok, err = visit(depName)
            if not ok then return false, err end
          end
        end
      end
    end
    visiting[name] = nil
    visited[name] = true
    -- EXP-1 — record the manifest's CANONICAL name in the order, not
    -- the (possibly alias) lookup key. Otherwise `pkg install
    -- tape-authenticator` would report installing "tape-storage" but
    -- pkg.install() would try to find a directory literally named
    -- "tape-storage" — which doesn't exist when only its replacement
    -- "tape" is in the repo.
    local canonical = (m.name and m.name ~= "") and m.name or name
    -- Don't add the same canonical name twice (alias + direct request).
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

--- Boot-critical files: union of every package's critical[] array.
--- Used by /init.lua's stage-4 verification and synced to the on-disk
--- backup so a corrupted tos-core/package.lua doesn't brick boot.
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

--- Sync the critical-files list to /etc/critical.bak. The backup is
--- read by /init.lua at boot if the primary list (tos-core's
--- package.lua) is missing or corrupt — and fed through one more
--- fallback to a hardcoded minimal list if the backup is also gone.
--- Three layers of defense against griefing or disk corruption.
---
--- Only writes if the list has actually changed, to reduce write wear
--- on filesystems and to avoid a useless metadata churn on every boot.
function pkg.syncCriticalBackup()
  local list = pkg.criticalFiles()
  if #list == 0 then
    -- No packages declare critical files yet (e.g. before commit 2's
    -- migration). Don't touch the backup; let /init.lua use whatever
    -- the previous run left or the hardcoded fallback.
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

-- ============================================================
-- Install / Uninstall
-- ============================================================

--- Install a package from a source directory.
--
-- The source dir must contain a `package.lua` manifest at its root.
-- Each entry in manifest.files is interpreted as an absolute target
-- path; the source file is read from `<srcDir><target>` (so a manifest
-- file list like {"/tos/shell/foo.lua"} pulls from
-- "<srcDir>/tos/shell/foo.lua" and writes to "/tos/shell/foo.lua").
--
-- Refuses to install over an existing package — the caller must
-- explicitly uninstall first. This avoids partial-overwrite states
-- where the new manifest is written before all the new files arrive.
--
-- @return ok, info
-- FEAT-7 — OPPM-compatible manifest reader. OPPM packages ship a
-- `programs.cfg` at the top of the repo plus a per-package metadata
-- file; many community projects also use a single `<name>.cfg` Lua
-- table. We normalize all three into the TOS manifest shape so the
-- rest of pkg.install (validation, file copy, registry) doesn't care.
--
-- Recognized files at `srcDir` (first hit wins):
--   1. /package.lua          (TOS native)
--   2. /package.oppm.lua     (OPPM-compatible, our own convention)
--   3. /<srcDir basename>.cfg (OPPM-style flat config — best-effort)
--   4. /programs.cfg         (a REAL OPPM repo index — see below)

--- Translate an OPPM `dependencies` table into TOS `requires` entries.
--
-- OPPM's dependency VALUE is an install PATH, not a version constraint:
--   dependencies = { ["libGUI"] = "/" }
-- means "install libGUI, at /". TOS's requires entries carry a version
-- constraint in that slot, and the old translator copied the value across
-- verbatim — so `pkg info` showed operators `libGUI /` as though a path
-- were a version. (It never failed an install: satisfiesConstraint can't
-- parse "/" as a version, compareVersion returns 0, and the implicit "=="
-- passes. Working by accident is still worth fixing.)
--
-- A value starting with "/" is therefore treated as OPPM's path and
-- dropped; anything else is kept, since a repo that really does write a
-- version constraint there should keep it.
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

-- ── Real OPPM repo indexes (`programs.cfg`) ──────────────────
--! OPPM's actual index format, which loadAnyManifest's own header has
--! described since FEAT-7 without anything ever reading it: a repo-root
--! `programs.cfg` holding EVERY package, keyed by name. A genuine OPPM
--! repo checkout therefore read as "no manifest here" and the operator was
--! told the disk was empty.
--
-- The shape:
--   { ["pkgname"] = {
--       files = { ["master/pkgname/foo.lua"] = "/bin" },
--       dependencies = { ["libGUI"] = "/" },
--       description = "...", authors = "...", note = "...", hidden = false,
--     }, ... }
--
-- The FILES table is the part that needs real translation, and is why TOS
-- manifests grew a source→target map (see `fileMap` in validateManifest).
-- In OPPM the KEY is the source path relative to the repo root and the
-- VALUE is the destination DIRECTORY — the installed filename is the
-- source's basename. TOS's own manifests use one absolute path for both
-- roles, so the old translator (which pushed the VALUE into the files
-- array) produced `files = {"/bin"}`: a directory, in the slot where a
-- file path belongs, rejected by validateManifest as outside the write
-- roots. Nothing shaped like a real OPPM manifest could install.
--
-- Destination rules, matching oppm.lua:
--   "//bin"  → absolute /bin          (usually refused: outside the write
--                                      roots, which is the boundary working)
--   "/bin"   → prefix-relative /usr/bin
local OPPM_PREFIX = "/usr"

local function oppmDestDir(value)
  if type(value) ~= "string" or value == "" then return nil end
  if value:sub(1, 2) == "//" then return "/" .. value:gsub("^/+", "") end
  return OPPM_PREFIX .. "/" .. value:gsub("^/+", "")
end

local function basenameOf(p)
  return (tostring(p):gsub("/+$", ""):match("([^/]+)$"))
end

--- Translate one programs.cfg entry into a TOS manifest.
--- Returns manifest, err. `srcBase` (the repo root the sources are
--- relative to) is carried on the returned manifest as `_srcBase`, which
--- is INTERNAL: nothing read off disk may set it (loadAnyManifest strips
--- it from every on-disk form), so a manifest file can never point the
--- installer's reads at an arbitrary directory.
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
    -- programs.cfg spells it `authors`; `note` is its long description.
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

--- Look for a programs.cfg describing `srcDir`'s package. Checked in the
--- PARENT directory first, because that is where a real repo keeps it:
--- one index at the root, one subdirectory per package. Falling back to
--- srcDir itself covers a single package carried on a floppy with its
--- index beside it.
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
        -- An index beside a single package: accept it when there is
        -- exactly one entry and no ambiguity about which is meant.
        local only, count = nil, 0
        for k, v in pairs(raw) do
          if type(k) == "string" and type(v) == "table" then only, count = k, count + 1 end
        end
        if count == 1 and cand.root == srcDir then
          base, entry = only, raw[only]
        end
      end
      if type(entry) == "table" then
        -- The index path travels with the manifest: a repo signs its
        -- programs.cfg as programs.sig, and only this loop knows which
        -- of the candidate paths actually answered.
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
    -- OPPM-style shape: { ["pkgname"] = { files = {...}, dependencies = {...}, ... } }
    -- Pick the first top-level package and translate field names.
    local outerName, inner = next(raw)
    if not inner or type(inner) ~= "table" then
      return nil, "OPPM manifest has no top-level package entry"
    end
    -- "command"/"program" are now first-class VALID_KINDS (see pkg's
    -- VALID_KINDS table), so OPPM manifests pass through unchanged; default
    -- a kind-less OPPM entry to "command" (its runnable-script idiom).
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
    -- OPPM `files = { ["repo/path"] = "/install/path", ... }` form
    if type(inner.files) == "table" then
      for k, v in pairs(inner.files) do
        if type(k) == "number" and type(v) == "string" then
          translated.files[#translated.files + 1] = v
        elseif type(k) == "string" and type(v) == "string" then
          translated.files[#translated.files + 1] = v
        end
      end
    end
    -- OPPM `dependencies = { ["pkgname"] = "<install path>", ... }`
    translated.requires = translateDeps(inner.dependencies)
    return fromDisk(translated, "oppm", oppmPath)
  end
  -- 3. /<dirname>.cfg — the flat OPPM-style config many community repos
  -- ship. This form was DOCUMENTED in the header above for a long time
  -- without ever being implemented, so a disk carrying one read as "no
  -- manifest" and the operator was told the disk was empty.
  local base = srcDir:match("([^/]+)/?$")
  if base then
    local cfgPath = fs.join(srcDir, base .. ".cfg")
    if fs.exists(cfgPath) then
      local raw, err = serialize.loadFile(fs, cfgPath)
      if not raw then return nil, base .. ".cfg parse error: " .. tostring(err) end
      -- Either the OPPM outer-table shape or a bare package table.
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

  -- 4. A real OPPM repo index. Checked LAST so a package that ships its
  -- own manifest keeps using it — the index is the fallback for a repo
  -- checkout whose packages carry no per-directory metadata at all.
  local m, cfgErr, cfgPath2 = loadFromProgramsCfg(srcDir)
  if m then return m, "oppm", cfgPath2 end
  if cfgErr then return nil, cfgErr end

  return nil, "no package.lua, package.oppm.lua, <name>.cfg or programs.cfg entry for "
    .. srcDir
end

-- ============================================================
-- Foreign packages (OpenOS / OPPM)
-- ============================================================
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

--- Capabilities a foreign package gets when its manifest declares none.
--- Pure; exposed for the tests.
function pkg.foreignDefaultCaps()
  local out = {}
  for i, c in ipairs(FOREIGN_DEFAULT_CAPS) do out[i] = c end
  return out
end

-- ============================================================
-- Conflicts
-- ============================================================
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

--- Conflicts between `m` and what is installed.
--- @return list of { kind = "declared"|"file", other = name, detail = ... }
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

  -- File ownership. Build the owner map once; a package with 200 files
  -- against a dozen installed packages is still trivial here.
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

-- ============================================================
-- Upgrades
-- ============================================================
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

--- Packages with a newer version available. Pure w.r.t. side effects.
--- @return { { name=, from=, to=, dir=, root= }, ... }, sorted by name
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

--- Upgrade one installed package to the newest version on offer.
--- opts.force            proceed past conflicts / allow a downgrade
--- opts.allowUnverified  same meaning as install's
--- @return ok, summary | false, err
function pkg.upgrade(name, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)  -- #SEC CR-5
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

  -- Verify BEFORE touching anything: a failed gate must not leave the
  -- machine with the old version already deleted.
  local vOk, vErr = pkg._verificationGate(m, opts.allowUnverified)
  if not vOk then return false, vErr end
  local licOk, licErr = pkg.verifyLicenseKey(m, opts.licenseKey)
  if not licOk then return false, "license check failed: " .. tostring(licErr) end
  local conflicts = pkg.findConflicts(m, name)
  if #conflicts > 0 and not opts.force then
    return false, "conflicts: " .. pkg.describeConflicts(conflicts)
  end

  -- Remember what to restore. `state` is the package-enable byte;
  -- the rc `.disabled` marker is the SEPARATE boot-start flag (they are
  -- different things — see the cluster-setup notes).
  local wasEnabled = pkg.isEnabled(name)
  local markers = {}
  for _, f in ipairs(cur.files or {}) do
    local stem = tostring(f):match("^/etc/rc%.d/(.+)%.lua$")
    if stem then
      markers[stem] = fs.exists("/etc/rc.d/" .. stem .. ".disabled")
    end
  end

  -- Files the new version drops. An install-over would leave these behind
  -- forever, owned by nothing.
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

  -- Restore the operator's choices.
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

--- One-line summary of a conflict list, for an error message.
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

-- FEAT-14 — soft-DRM key verification helper.
-- Returns (true) iff `userKey` hashes (with the package name as salt)
-- to one of the manifest's `license.keys` entries.
function pkg.verifyLicenseKey(manifest, userKey)
  if type(manifest) ~= "table" or type(manifest.license) ~= "table" then
    return true  -- no license attached → no check needed
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

-- #SEC (review, Jul 2026) — the reject-unverified-by-default decision.
-- Pure + exposed so it's unit-tested directly. A package passes when it
-- declares a SHA-256 for EVERY file in m.files. Returns
-- (ok, reason, complete): `complete` is whether the hash set was full
-- (false + allowUnverified = installed-but-flagged).
-- ============================================================
-- Publisher signatures
-- ============================================================
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

  -- An INVALID signature is refused outright and has no override. It is
  -- not the absence of a signature; it is evidence that something
  -- rewrote a package that was signed. If this were overridable, or if
  -- it degraded to "unsigned", then corrupting a signature would be a
  -- way to reach the permissive path — which hands the gate away.
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
  local g, gErr = adminGate(opts)  -- #SEC CR-5
  if not g then return false, gErr end
  if type(srcDir) ~= "string" or srcDir == "" then
    return false, "invalid source directory"
  end
  srcDir = fs.normalize(srcDir)

  local m, source, manifestPath = loadAnyManifest(srcDir)
  if not m then return false, "no manifest in " .. srcDir .. ": " .. tostring(source) end
  if source == "oppm" then
    -- Provenance is recorded ON THE MANIFEST, so it survives into the
    -- installed registry (`installed[m.name] = m` below) and can be shown
    -- by `pkg info`. It used to be logged once at install time and then
    -- thrown away, which meant nothing downstream could ever act on it.
    m.origin = "openos"
    if type(m.capabilities) ~= "table" or #m.capabilities == 0 then
      m.capabilities = pkg.foreignDefaultCaps()
      m.capsFromCompat = true      -- shown by `pkg info`, not a manifest field
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

  -- FEAT-14 — soft-DRM gate. Run before the on-disk side effects.
  local licOk, licErr = pkg.verifyLicenseKey(m, opts.licenseKey)
  if not licOk then
    return false, "license check failed: " .. tostring(licErr)
  end
  local ok, vErr = validateManifest(m)
  if not ok then return false, "invalid manifest: " .. vErr end

  -- `opts.upgrading` is set by pkg.upgrade, which has already removed the
  -- old version's files and is entitled to reuse its paths.
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

  -- #SEC/#SAFETY — conflicts. Checked BEFORE any file is written, because
  -- the failure this prevents is a half-overwritten pair of packages.
  local conflicts = pkg.findConflicts(m, opts.upgrading and m.name or nil)
  if #conflicts > 0 and not opts.force then
    return false, "conflicts: " .. pkg.describeConflicts(conflicts)
  end
  if #conflicts > 0 and log then
    log.warn("pkg", "Installing " .. tostring(m.name) .. " over conflicts (--force): "
      .. pkg.describeConflicts(conflicts))
  end

  -- #SEC (review, Jul 2026) — REJECT unverified packages by default (see
  -- pkg._verificationGate). A package is executable code; installing one
  -- with no declared file hashes means running untrusted code with no
  -- integrity check. First-party Extras ship build-generated hashes, so
  -- the default path is unaffected; --allow-unverified is the escape hatch.
  do
    local ok2, reason, complete = pkg._verificationGate(m, opts.allowUnverified)
    if not ok2 then return false, reason end
    if not complete and opts.allowUnverified and log then
      log.warn("pkg", "Installing UNVERIFIED package '" .. tostring(m.name)
        .. "' (no/partial hashes) — operator override")
    end
  end

  -- Publisher signature. Runs AFTER the hash gate and before a single
  -- byte is written, so a package that fails either one has changed
  -- nothing on this machine.
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
        -- Deliberately a WARNING and not an error. The signature is
        -- real and checks out; what is missing is the operator's
        -- decision about the key, and `pkg trust add` is one command.
        log.warn("pkg", "'" .. tostring(m.name) .. "' is signed by an UNTRUSTED key "
          .. tostring(verdict.fingerprint) .. " — 'pkg trust add <name> " .. tostring(verdict.key) .. "'")
      else
        log.warn("pkg", "'" .. tostring(m.name)
          .. "' is UNSIGNED — installed on admin privilege alone")
      end
    end
  end

  -- Copy each declared file. We track copied/failed and abort on any
  -- write failure rather than partially install — a half-installed
  -- package is worse than no install because a later run might assume
  -- enabled = files-on-disk and skip a fresh deploy.
  -- #SEC CR-4 — integrity gate. When the manifest declares hashes, every
  -- file is verified against m.hashes[target] with a constant-time compare
  -- BEFORE it is written. A mismatch (tamper or transport corruption)
  -- aborts the whole install. Mirrors the kernel.modules C3 path.
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
    -- Cooperative slice between files (#REV multi-seat freeze): each
    -- file's read→hash-verify→write stays atomic within its resume;
    -- other seats get a turn between files (hashing is the slow part
    -- on software-crypto boxes). No-op outside a yieldable process.
    do
      local okP, procMod = pcall(require, "kernel.process")
      if okP and procMod and procMod.yieldCooperative then procMod.yieldCooperative() end
    end
    -- Source path. Native packages lay their files out AT their install
    -- paths, so source and target are the same and this is `srcDir .. target`
    -- exactly as it always was. A translated OPPM manifest carries a
    -- fileMap (target → repo-relative source) and, for a repo index, the
    -- _srcBase those sources are relative to; both are produced by
    -- loadAnyManifest and validated above.
    local mapped = m.fileMap and m.fileMap[target]
    local src
    if mapped then
      src = fs.normalize((m._srcBase or srcDir) .. "/" .. mapped)
    else
      -- Unchanged from before fileMap existed: a native package's files
      -- sit at their install paths under the package directory. Kept as
      -- the literal old expression so the common path cannot regress.
      src = fs.normalize(srcDir .. target)
    end
    local data = fs.readFile(src)
    if not data then
      -- Roll back: remove what we already wrote.
      for _, p in ipairs(copied) do pcall(fs.remove, p) end
      return false, "missing source file: " .. src
    end
    -- #SEC CR-4 — verify before write when a hash is declared for this file.
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

  -- Write the metadata directory.
  local destDir = fs.join(PKG_ROOT, m.name)
  if not fs.exists(destDir) then fs.makeDirectory(destDir) end

  -- Record provenance in the installed DB: whether this package was
  -- verified against declared hashes, and where it came from. `pkg info`
  -- surfaces `_unverified` so an operator can see a package installed via
  -- the --allow-unverified escape hatch.
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

  -- The signature verdict is recorded ON the installed manifest, the same
  -- way `origin` is, so `pkg info` can answer "where did this come from"
  -- months later. Only the verdict and the key are kept — re-verifying at
  -- read time would mean re-running the whole scalar multiplication every
  -- time somebody typed `pkg list`.
  m._sigState = sigVerdict and sigVerdict.state or "unsigned"
  m._sigKey   = sigVerdict and sigVerdict.key or nil
  m._sigLabel = sigVerdict and sigVerdict.label or nil

  local saveOk, saveErr = serialize.saveFile(fs, fs.join(destDir, "package.lua"), m)
  if not saveOk then
    -- Roll back the file copies. The metadata dir stays — it's empty
    -- and pkg.scan ignores names with no readable manifest.
    for _, p in ipairs(copied) do pcall(fs.remove, p) end
    return false, "manifest write failed: " .. tostring(saveErr)
  end

  -- Default state. Services with defaultState="disabled" start off;
  -- everything else defaults to enabled.
  local defaultEnabled = "e"
  if type(m.service) == "table" and m.service.defaultState == "disabled" then
    defaultEnabled = "d"
    -- #SVC — enforce "disabled by default" at the rc layer too. The package
    -- `state` byte above is pkg-internal; the rc.d loader (kernel.rc) never
    -- reads it, so without this it would auto-START the freshly installed
    -- daemon on the very next boot — exactly what defaultState=disabled is
    -- meant to prevent. Drop a sibling `<svc>.disabled` marker next to each
    -- rc.d script; rc.runAll registers but does NOT start a marked service,
    -- and `service start <svc>` clears the marker to persist the enable.
    for _, target in ipairs(m.files) do
      local stem = tostring(target):match("^/etc/rc%.d/(.+)%.lua$")
      if stem then
        pcall(fs.writeFile, "/etc/rc.d/" .. stem .. ".disabled", "1")
      end
    end
  end
  fs.writeFile(fs.join(destDir, "state"), defaultEnabled)

  installed[m.name] = m

  -- Critical-files set may have grown; sync the backup.
  pkg.syncCriticalBackup()

  if log then
    log.info("pkg", string.format("Installed %s v%s (%d files)",
      m.name, m.version, #copied))
  end

  -- Verify declared dependency constraints now that the package is
  -- registered. resolveInstallOrder only orders by NAME; this is the
  -- one place version constraints ("tape-storage >=1.0") are actually
  -- enforced. Unmet constraints don't fail the install (the files are
  -- already down and may still work) but the operator gets told.
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

--- FEAT-7 — install a package and all its dependencies in resolved
--- order. `repoDir` is a directory containing one subdir per package
--- (each with its own package.lua). For a target package "foo", we
--- look at repoDir/foo/, read its manifest, resolve its dep graph,
--- and install everything in topological order — skipping packages
--- that are already installed at a satisfying version.
---
--- Returns (true, { installed = {names}, skipped = {names} }) on
--- success, or (false, err) on resolution / install failure.
function pkg.installWithDeps(repoDir, targetName, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)  -- #SEC CR-5
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

  -- Cache loaded manifests so the resolver can call lookup() many
  -- times without re-reading the same package.lua.
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
      -- FEAT-14 — only the target package consumes the supplied key;
      -- dependencies that ALSO require keys must be pre-installed
      -- separately (or the caller can pass `licenseKeys = { [name] = key, ... }`).
      local perPkgKey = opts.licenseKey
      if opts.licenseKeys and opts.licenseKeys[name] then
        perPkgKey = opts.licenseKeys[name]
      elseif name ~= targetName then
        perPkgKey = nil  -- don't reuse the target's key on deps
      end
      -- #SEC CR-5 — forward the authorized session to the nested install
      -- so the per-dep gate sees the same admin principal.
      local ok, err = pkg.install(pkgSrc, { licenseKey = perPkgKey, session = opts.session,
        allowUnverified = opts.allowUnverified })
      if not ok then
        -- Roll back: uninstall what we installed in this transaction.
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

--- Uninstall a package by name.
--
-- Refuses if anything else still depends on it (transitive checks
-- left to phase 2). Refuses unconditionally for tos-core — that's
-- the only package whose removal can brick the boot path.
--
-- @return ok, info
function pkg.uninstall(name, opts)
  local g, gErr = adminGate(opts)  -- #SEC CR-5
  if not g then return false, gErr end
  if name == "tos-core" then
    return false, "refusing to uninstall tos-core"
  end
  local m = installed[name]
  if not m then return false, "not installed: " .. name end

  -- Reverse-dependency check: if any OTHER installed package lists
  -- `name` as a non-optional require, we refuse.
  --
  -- `_internalUpgrade` is pkg.upgrade removing the OLD version a moment
  -- before installing the new one. Refusing there would make every
  -- depended-upon package permanently un-upgradable — the dependency is
  -- satisfied again before control returns to the operator, and upgrade
  -- has already verified the replacement (hashes, licence, conflicts)
  -- before it removed anything.
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

  -- Remove the files this package owns. Best-effort: failures are
  -- logged but don't abort the uninstall, because the manifest is
  -- removed at the end and a half-removed package is still better
  -- than a manifest pointing at files we can't delete.
  for _, target in ipairs(m.files or {}) do
    local rmOk, rmErr = pcall(fs.remove, target)
    if not rmOk and log then
      log.warn("pkg", "Could not remove " .. target .. ": " .. tostring(rmErr))
    end
  end

  -- Remove the metadata directory recursively. We could end up with
  -- subdirs (state file is at the top, but future versions might
  -- store more), so walk the tree.
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

  -- Critical-files set may have shrunk; sync the backup.
  pkg.syncCriticalBackup()

  if log then log.info("pkg", "Uninstalled " .. name) end
  return true
end

-- ============================================================
-- FEAT-9 — repository helpers (multi-source install)
-- ============================================================
-- A "repository" is any directory containing one subdirectory per
-- package, each with a `package.lua` (or `package.oppm.lua`) at its
-- root. Three real-world cases all reduce to this shape:
--
--   1. The bundled Extras tree on disk (/usr/repo/ when an admin
--      copies TOS-Extras there).
--   2. A floppy disk auto-mounted at /mnt/<label>/ that contains
--      one or more packages. The H26 floppy gate already restricts
--      auto-mount of the boot disk; this code happily mounts data
--      floppies as repositories.
--   3. An OPPM-style remote checkout placed locally — same layout.
--
-- This unification is the answer to the user's "package manager needs
-- to handle floppies AND OPPM AND our own format" goal: as long as
-- the floppy has a package.lua at /mnt/<label>/<pkgname>/, the
-- existing install path Just Works.

local DEFAULT_REPO_ROOTS = {
  "/usr/repo",          -- conventional local repo
  "/var/repo",          -- alternative, sometimes used by sysadmins
}

-- Candidate repo roots from removable media. #FIX — a disk mounted by the
-- KERNEL at boot is a virtual mount point: fs.mount records it in the mount
-- table but does NOT create a real /mnt/<label> directory, so it never shows
-- up in fs.list("/mnt"). Discovery that scanned only /mnt therefore found
-- single-package installs (explicit path works) but MISSED every package on a
-- multi-package Optional Utilities disk. Enumerate the authoritative mount
-- table instead, and still fold in any real /mnt subdir (shell-side
-- auto-mounts DO create those). Deduped; "/" excluded.
local function mountedRepoRoots()
  -- Step 1: candidate mount points (authoritative mount table + real /mnt
  -- subdirs; boot-time mounts are virtual and don't appear in fs.list).
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
  -- Step 2: each mount root is a candidate, AND so is each of its immediate
  -- subdirectories — so a disk whose packages sit under one folder (the whole
  -- dist/optional-utilities FOLDER copied on, instead of its contents) is
  -- still found. listRepo() filters non-repo dirs (returns empty), so handing
  -- it the extra roots is harmless; no separate "is this a repo?" probe (that
  -- coupled discovery to fs internals the package mocks don't implement).
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

--- Every directory `pkg` will look in for installable packages: the
--- default repo roots plus every mounted disk and its immediate
--- subdirectories.
--- Exported because the PICKER needs the identical enumeration and had
--- written its own — which is how it came to miss boot-time mounts (see
--- the note in mountedRepoRoots) and therefore never found the set
--- manifest that tells it about the OTHER floppy. Two implementations of
--- "where are the packages" is one too many.
function pkg.repoRoots()
  local roots = {}
  for _, r in ipairs(DEFAULT_REPO_ROOTS) do roots[#roots + 1] = r end
  for _, r in ipairs(mountedRepoRoots()) do roots[#roots + 1] = r end
  return roots
end

--- List packages available in a repository directory. Returns an
--- array of { name, version, description, source } entries.
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
            -- Surface the grouping + provenance the installer shows.
            -- category is the pick-list bucket ("games", "network", …);
            -- default "misc" so an uncategorised package still lists.
            category    = (type(m.category) == "string" and m.category ~= "")
                          and m.category or "misc",
            author      = m.author,
            kind        = m.kind,
            source      = source,
            dir         = pkgDir,
            -- The installer shows both, and auto-selects `requires` so the
            -- operator sees what is coming along rather than discovering it
            -- in the install log.
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

--- Search every configured repo root + every mounted floppy for a
--- package by name. Returns the first match's directory (or nil).
function pkg.findInRepos(targetName, extraRoots)
  local roots = {}
  for _, r in ipairs(DEFAULT_REPO_ROOTS) do roots[#roots + 1] = r end
  if type(extraRoots) == "table" then
    for _, r in ipairs(extraRoots) do roots[#roots + 1] = r end
  end
  -- Mounted media: reuse the SAME enumeration as listing (mountedRepoRoots),
  -- which includes each mount AND its immediate subdirectories — so a disk
  -- whose packages sit under one folder (e.g. /mnt/<disk>/optional-utilities/)
  -- is found by `pkg install <name>` exactly as it is by `pkg list`. Before
  -- this, install scanned only /mnt/<label> (one level) and could not find a
  -- package that listing happily showed — the bundled disk's whole failure.
  for _, root in ipairs(mountedRepoRoots()) do roots[#roots + 1] = root end
  for _, root in ipairs(roots) do
    local pkgDir = fs.join(root, targetName)
    if fs.exists(pkgDir) and fs.isDirectory(pkgDir) then
      local m = loadAnyManifest(pkgDir)
      -- #SEC H-20 — dependency confusion. The directory name is the
      -- requested identity; the manifest's self-declared `name` is
      -- attacker-controlled (a floppy package can claim to be "tos-core").
      -- Require them to match, exactly as pkg.scan() does, instead of
      -- trusting the manifest's claim. A mismatch is skipped, not accepted.
      if m and m.name == targetName then return pkgDir, root end
      if m and log then
        log.warn("pkg", "Ignoring '" .. tostring(targetName) .. "' in " .. root ..
          ": manifest name '" .. tostring(m.name) .. "' does not match directory")
      end
    end
  end
  return nil
end

--- Install one or more packages by name, looking them up in
--- configured repos + mounted media + extraRoots. Resolves deps
--- across all available sources. Returns (true, summary) or (false, err).
function pkg.installByName(targetName, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)  -- #SEC CR-5
  if not g then return false, gErr end
  -- Accept a full PATH to a package directory as well as a bare name, so
  -- `pkg install /mnt/<disk>/optional-utilities/tetris` works too. Normalize
  -- it to (name, repoRoot=parent); H-20 still requires the manifest's name to
  -- match the directory base name.
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
  -- Use the directory containing pkgDir as the repo for dep resolution
  -- (so siblings of targetName are reachable via installWithDeps).
  -- FEAT-14 — forward license key + per-package keys.
  return pkg.installWithDeps(root, targetName, {
    licenseKey      = opts.licenseKey,
    licenseKeys     = opts.licenseKeys,
    session         = opts.session,  -- #SEC CR-5 — carry the authorized principal
    allowUnverified = opts.allowUnverified,  -- #SEC — hash-requirement escape hatch
  })
end

-- FEAT-14 helper — compute the hash an author should publish in a
-- manifest's license.keys[] for a chosen key. Saves authors from
-- having to figure out the construction themselves.
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

--- List packages across every configured repo + mounted media. Useful
--- for `pkg search` UI: shows what's installable right now.
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

--- One-shot helper: scan every mount under /mnt/ for packages, and
--- prompt the caller via a `confirm(pkgName, dir)` callback before
--- installing each. Used by the floppy-detection panel command.
function pkg.installFromFloppy(opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)  -- #SEC CR-5
  if not g then return false, gErr end
  -- #SEC H-20 — never default-accept. Inserting a disk must not silently
  -- install (unverified) code. Without an explicit confirm callback every
  -- candidate is declined.
  local confirm = (type(opts.confirm) == "function") and opts.confirm
    or function() return false end
  local installed_pkgs = {}
  local skipped_pkgs = {}
  -- #FIX — enumerate mounted filesystems (incl. boot-time virtual mount
  -- points that fs.list("/mnt") can't see), not just real /mnt subdirs.
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

-- ============================================================
-- In-TOS Optional Utilities disk builder (parity with `deploy`)
-- ============================================================
-- `deploy` builds a whole-OS install image from the running system; this
-- builds the ADD-ON counterpart from the running system's INSTALLED
-- packages, so an operator can replicate their add-on set onto another TOS
-- machine without a dev box (and without the TOS-Extras source tree). The
-- emitted layout is exactly what pkg.install/listAllAvailable expect:
--   <target>/install.lua            the picker (embedded below)
--   <target>/<name>/package.lua     each package's manifest
--   <target>/<name>/<install path>  each file, mirrored at its abs path

-- Embedded pick-and-choose installer. Behaviour-identical to the dev-box
-- TOS-Extras/build/install.lua (same kernel.pkg backend: admin gate, dep
-- resolution, hash verification); carried on the disk so it self-installs
-- on any TOS machine. ASCII status markers (no Unicode) so the string
-- survives the Release minifier untouched. Keep in sync with the Extras copy.
-- (The picker used to be embedded here as a ~40 KB PICKER_SRC string,
-- byte-identical to a copy on every Optional Utilities floppy. It now lives
-- once, at tos/shell/pkgpicker.lua — see pkg.runInstaller below.)

--- Run the Optional Utilities TUI picker — the SAME installer that ships
--- on the disk (PICKER_SRC above), so `pkg install` (no argument) offers
--- the full-screen category menu instead of a sequence of y/N prompts.
---
--- We run the TRUSTED embedded copy rather than the disk's install.lua:
--- it's byte-identical (pinned by test_picker_sync), always present, and
--- — unlike arbitrary code on untrusted media — safe to execute at the
--- shell's full privilege. A corrupt or malicious disk installer can't
--- hijack this path; a third-party disk that ships its OWN installer is a
--- future question (running untrusted install code at full priv is
--- exactly what we don't want to do implicitly).
---
--- The picker requires a reachable GPU for its TUI; on a GPU-less machine
--- it degrades to its own line mode, which needs io.read (absent in the
--- panels shell). The caller (`pkg install`) treats ANY failure — load
--- error, no usable front-end — as a signal to fall back to the
--- prompt-based installFromFloppy path. Returns (true) if the picker ran,
--- or (false, reason).
function pkg.runInstaller(opts)
  -- #MEM — the OpenOS compat layer now loads on first use rather than at
  -- boot, and the picker reads the `io` GLOBAL (compat.init is what sets
  -- it) to choose between its io.write path and bare print. Touch `io`
  -- through require so compat is up before the chunk's own top-level
  -- `local hasIO = io and ...` runs; without this the picker would always
  -- take the print fallback. Guarded: on a compat-disabled (Safe Mode)
  -- boot this is a no-op and the picker degrades exactly as documented.
  pcall(require, "io")
  -- One copy, required like any other module. This used to load a ~40 KB
  -- PICKER_SRC string embedded right here, kept byte-identical to a copy on
  -- every Optional Utilities floppy — two duplicates of a program whose
  -- first act is require("kernel.pkg"), i.e. which can only ever run on a
  -- machine that already has it. The floppies got their 40 KB back and the
  -- sync test that policed the duplication is gone with it.
  local okM, picker = pcall(require, "shell.pkgpicker")
  if not okM or type(picker) ~= "table" or not picker.run then
    return false, "picker unavailable: " .. tostring(picker)
  end
  -- It draws through a raw GPU proxy and restores nothing — the caller
  -- repaints the shell afterwards.
  local ok, res, why = pcall(picker.run, opts)
  if not ok then return false, "installer error: " .. tostring(res) end
  -- A picker that declined because it had nothing to show must not read as
  -- success. The shell returns early when the picker "ran", so reporting
  -- success here is what turned an empty disk into no output at all.
  if res == false then return false, why or "no installable packages found" end
  return true
end

-- tos-core is the OS itself (shipped by `deploy`), never an add-on; always
-- skip it so a make-disk never tries to bundle the kernel as a package.
local SELF_PKG = { ["tos-core"] = true }

--- Build an Optional Utilities (add-on) disk from the installed packages.
--- opts.only = { "tetris", ... } restricts to named packages (default: all).
--- @return ok, summary | false, err
function pkg.exportDisk(targetDir, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)  -- #SEC CR-5 — admin-gated like install
  if not g then return false, gErr end
  if type(targetDir) ~= "string" or targetDir == "" then
    return false, "invalid target directory"
  end
  targetDir = fs.normalize(targetDir)
  if not targetDir then return false, "invalid target path" end  -- #SEC M-1
  -- #SEC — refuse to scribble a package repo into a system root (mirrors the
  -- deploy command's FORBIDDEN guard). Export targets removable media only.
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
  -- Deterministic order so the build output is stable across runs.
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
          local data = fs.readFile(target)  -- read the live installed file
          if not data then
            problems[#problems + 1] = name .. ": missing installed file " .. target
            clean = false
          else
            -- Mirror at <pkgDir><target>: fs.join normalises the doubled
            -- slash so the file lands at its absolute path under the pkg
            -- dir — exactly where pkg.install(srcDir) reads it from.
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

  -- Surface names the operator asked for that aren't actually installed.
  if only then
    for n in pairs(only) do
      if not installed[n] then
        problems[#problems + 1] = n .. ": not installed (skipped)"
      elseif SELF_PKG[n] then
        problems[#problems + 1] = n .. ": is the OS core, not an add-on (skipped)"
      end
    end
  end

  -- The disk carries a SET MANIFEST (what's on it, and where) and a short
  -- README — not a copy of the picker. The picker is in the base image of
  -- every machine that could run it, so shipping one was 40 KB of floppy
  -- spent proving a machine has software it must already have.
  --
  -- The manifest is what makes this an "Optional Utilities disk" rather than
  -- a loose pile of packages: the media detector keys on it, and the picker
  -- reads it to list packages that live on a disk which isn't inserted.
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

-- ============================================================
-- Constants exposed for callers that want to know the layout
-- ============================================================

pkg.PKG_ROOT          = PKG_ROOT
pkg.CRITICAL_BACKUP   = CRITICAL_BACKUP
pkg.VALID_KINDS       = VALID_KINDS
pkg.DEFAULT_REPO_ROOTS = DEFAULT_REPO_ROOTS

-- Test hooks (not part of the public API; mirror crypto._makeIv16).
pkg._validateManifest    = validateManifest
pkg._isUnderPkgWriteRoot = isUnderPkgWriteRoot
pkg._isServiceEtcTarget  = isServiceEtcTarget
pkg.PKG_WRITE_ROOTS      = PKG_WRITE_ROOTS

-- ============================================================
-- #MEM — lazy self-initialization
-- ============================================================
-- The kernel no longer require()s pkg at boot (it is the second-largest
-- module in the OS and most sessions never touch it). Every existing
-- consumer reaches it via pcall(require, "kernel.pkg") — executor command
-- dispatch, the `pkg` command, the installer — so the module initializes
-- itself HERE, on first load, from the live _TOS handles. The boot-time
-- ============================================================
-- Remote repositories (internet card)
-- ============================================================
-- Thin front on kernel.pkgremote, which is required LAZILY: a machine that
-- never fetches anything never parses it.
--
-- The division of labour is the point. pkgremote DOWNLOADS a repo into a
-- staging directory shaped exactly like a repo on a floppy; this then runs
-- the ORDINARY install against it. Manifest validation, write-root
-- confinement, hash verification, conflict and file-ownership checks,
-- dependency resolution and the unverified-package gate are the same code
-- for a remote package as for a local one, because it IS the same code.

local function remoteMod()
  local ok, m = pcall(require, "kernel.pkgremote")
  if not ok or type(m) ~= "table" then return nil, "remote package support unavailable" end
  if m.init and log then pcall(m.init, { log = log }) end
  return m
end

--- Configured remote repos.
-- ============================================================
-- Publisher trust store (admin API)
-- ============================================================
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

--- Trusted publisher keys: { {label=, key=, fingerprint=}, ... }
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

--- Verify (without installing) whatever is in `srcDir`. This is the
--- `pkg verify-sig <dir>` path: an operator should be able to ask who
--- signed a floppy BEFORE deciding to install from it.
function pkg.checkSignature(srcDir)
  if type(srcDir) ~= "string" or srcDir == "" then return nil, "invalid directory" end
  local ps, e = withSign(); if not ps then return nil, e end
  local m, source, manifestPath = loadAnyManifest(fs.normalize(srcDir))
  if not m then return nil, "no manifest in " .. srcDir .. ": " .. tostring(source) end
  return ps.verifyManifest(manifestPath), m
end

--- Sign the manifest in `srcDir` with a passphrase-derived key.
-- Admin-gated because it writes into a package directory, and because
-- being able to sign as a publisher on this machine is a privilege in
-- its own right.
function pkg.signPackage(srcDir, passphrase, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts); if not g then return nil, gErr end
  local ps, e = withSign(); if not ps then return nil, e end
  if type(srcDir) ~= "string" or srcDir == "" then return nil, "invalid directory" end
  local m, source, manifestPath = loadAnyManifest(fs.normalize(srcDir))
  if not m then return nil, "no manifest in " .. srcDir .. ": " .. tostring(source) end
  local seed, sErr = ps.seedFromPassphrase(passphrase)
  if not seed then return nil, sErr end
  return ps.signManifest(manifestPath, seed, { signer = opts.signer })
end

--- The public key a passphrase would sign as — so a publisher can print
--- their own key to hand out without signing anything.
function pkg.signingKey(passphrase)
  local ps, e = withSign(); if not ps then return nil, e end
  local seed, sErr = ps.seedFromPassphrase(passphrase)
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

--- Add/remove a repo. #SEC CR-5 — same admin gate as install: a repo entry
--- is a standing decision about where this machine will accept code from,
--- which is at least as consequential as one install.
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

--- Everything available across the configured repos.
function pkg.searchRemote(opts)
  local m = remoteMod()
  if not m then return {} end
  return m.search(opts)
end

--- Fetch `name` from a configured repo and install it.
--
-- Returns ok, err. The staging tree is removed either way — a failed
-- install must not leave a stranger's source files sitting on the disk,
-- and a successful one has no further use for them.
function pkg.installRemote(name, opts)
  opts = opts or {}
  local g, gErr = adminGate(opts)   -- #SEC CR-5
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

-- work moved with it: scan() runs inside init, and the critical-files
-- backup sync + the boot profile's dispatch gate follow right after.
-- Off-box tests see no _TOS (or no _TOS.fs) and land in the explicit
-- pkg.init(deps) path exactly as before; a later explicit init simply
-- re-scans, which is idempotent.
do
  local T = rawget(_G, "_TOS")
  if T and T.fs and not fs then
    -- #SEC — apply the boot profile's dispatch gate FIRST and
    -- unconditionally. Doing it only on a successful init would fail
    -- OPEN: a Safe Mode boot whose pkg.init errored would leave
    -- package-provided commands dispatching, which is exactly the
    -- third-party code that profile refuses to run.
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
