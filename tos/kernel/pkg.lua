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

-- #MEM -- kernel.pkg is TWO files. This one is what a package COMMAND
-- needs: the registry (scan, list, info, enabled), validation, the
-- capability grant and command dispatch, versions, the critical-file
-- backup. kernel.pkgops is everything that CHANGES the system: install,
-- upgrade, plan, uninstall, repos, disks, trust, remote fetch -- about
-- two thirds of the code. Every unknown command, every package command
-- and every `pkg list` loaded all of it (~190 KB compiled, off-box), and it
-- stayed loaded. Now the operations load the first time anything asks
-- pkg for one of them (OPS_NAMES, at the end of this file). Callers see one
-- module either way. (test_pkg_split.lua)
local attachOps, opsAttached, OPS_NAMES, opsOwn

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
local ROOT_TIER  = 3
local function adminGate(opts)
  if not users then return true end
  local session = (type(opts) == "table" and opts.session) or nil
  if not session and users.currentSession then session = users.currentSession() end
  if not session then return false, "Insufficient privileges: admin required" end
  if session.isKernel or session.isLogin then return true end
  if type(session.tier) == "number" and session.tier >= ADMIN_TIER then return true end
  return false, "Insufficient privileges: admin required"
end

--! #SEC (pentest, Sep 2026) — a service package is trusted with the whole
--! machine, and installing one is a ROOT act, not merely ADMIN. rc.d runs a
--! service as the principal it declares and as ROOT when it declares none,
--! through the KERNEL loader (allowUserLibs), OUTSIDE the capability sandbox
--! that confines a command package (MANUAL §15). So an ADMIN who could
--! install a service could run code as root at the next boot -- which made
--! every ROOT-only line elsewhere (the shadow file's write, root accounts,
--! `protect off`, mounting over a protected path) a courtesy an ADMIN could
--! walk around. The other kinds stay ADMIN: command/app/lib/runtime/theme run
--! sandboxed with only their declared capabilities, and a `driver` reaches
--! raw hardware but only the component types its caps name, still inside the
--! sandbox. A kernel/boot session (the installer) is exempt; the login
--! principal, which adminGate lets through, is NOT -- it is guest-tier and has
--! no business installing anything. (test_pkg_service_root.lua)
--! #SEC — and so does a package that installs a boot SELF-TEST CHECK.
--! kernel/selftest.lua runs every check in /usr/lib/selftest/ inside the
--! kernel whenever the machine is armed, and arming is ROOT-only because
--! that is more than an admin holds. But /usr/lib/selftest/ was ordinary
--! package space: an ADMIN install could leave a check there, and the next
--! time root armed the battery, for any reason, it ran as the kernel.
--! Compared case-folded (targetKey), as every target is.
--! (test_pkg_service_root.lua)
local SELFTEST_ROOT = "/usr/lib/selftest/"
local function installsSelftestCheck(m)
  if type(m) ~= "table" or type(m.files) ~= "table" then return false end
  for _, t in ipairs(m.files) do
    -- targetKey's fold, inline: targetKey is defined further down.
    if type(t) == "string" and t:lower():sub(1, #SELFTEST_ROOT) == SELFTEST_ROOT then
      return true
    end
  end
  return false
end
local function serviceInstallGate(m, opts)
  local selftestCheck = installsSelftestCheck(m)
  if type(m) ~= "table" or (m.kind ~= "service" and not selftestCheck) then return true end
  if not users then return true end
  local session = (type(opts) == "table" and opts.session) or nil
  if not session and users.currentSession then session = users.currentSession() end
  if session and session.isKernel then return true end
  if session and type(session.tier) == "number" and session.tier >= ROOT_TIER then return true end
  if m.kind ~= "service" then
    return false, "this package installs a boot self-test check, which runs inside the "
      .. "kernel when the battery is armed; only root may install one"
  end
  return false, "installing a service package runs its code as root at boot; "
    .. "only root may install a service (this one runs outside the package sandbox)"
end
pkg._serviceInstallGate = serviceInstallGate   -- test hook

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

--! #SEC (pentest, Sep 2026) — an install TARGET is compared as a STRING
--! (against system files, other packages' files, reserved names), but the
--! HOST decides which file it names. OpenComputers keeps each disk as a
--! directory on the Minecraft host; on Windows and default macOS that is
--! case-insensitive, and Win32 silently drops a trailing dot or space. So
--! "/usr/lib/MailApp.lua." and "/usr/lib/mailapp.lua" are two strings and
--! one file. Targets are held to a plain character set with no empty
--! segment and no trailing dot, and every comparison goes through targetKey.
local function targetShapeOk(p)
  if p:find("//", 1, true) or p:sub(-1) == "/" then return false end
  for seg in p:gmatch("[^/]+") do
    if not seg:match("^[%w_%.%+%-]+$") or seg:sub(-1) == "." then return false end
  end
  return true
end
local function targetKey(p) return (tostring(p):lower()) end

-- #SEC CR-4 — write-root allowlist. pkg.install writes each files[] entry
-- to its declared ABSOLUTE path. pathHasTraversal already blocks "../"
-- escapes, but an entry like "/tos/kernel/sandbox.lua" is traversal-free
-- and would overwrite the kernel (inserted-media → full compromise).
-- Confine package writes to package-owned roots so a manifest can never
-- target /tos, /etc, /boot, etc. Roots are matched on a normalized,
-- segment-boundary basis so "/usr-evil/x" can't masquerade as "/usr".
local PKG_WRITE_ROOTS = { "/usr/", "/var/pkg/" }
--! #SEC (pentest, Sep 2026) — /var/pkg/ is package space, but three trees in
--! it belong to the package MANAGER, and files[] could name any of them:
--!   /var/pkg/installed/<name>/  every package's manifest: its commands, its
--!       capabilities, and the signature verdict pkg.scan believes because
--!       only install() writes it. A package could rewrite another's (so
--!       that package's command ran the writer's code) or plant one for a
--!       package never installed, "signed by a trusted publisher".
--!   /var/pkg/secrets/<name>     each package's crypto.secret(), read back
--!       raw: plant or overwrite one and that package's key is the writer's.
--!   /var/pkg/remote/            the remote-fetch staging area.
--! Refused case-folded, like every other target comparison (targetKey).
--! (test_pkg_reserved_targets.lua)
local PKG_RESERVED_ROOTS = { "/var/pkg/installed", "/var/pkg/secrets", "/var/pkg/remote" }
local function isReservedTarget(p)
  local key = targetKey(p)
  for _, r in ipairs(PKG_RESERVED_ROOTS) do
    if key == r or key:sub(1, #r + 1) == r .. "/" then return true end
  end
  return false
end
local function isUnderPkgWriteRoot(p)
  if type(p) ~= "string" or p == "" then return false end
  if isReservedTarget(p) then return false end
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
-- (pathHasTraversal already ran). The file is still admin-gated (CR-5) and
-- hash-verified (CR-4) on install.
--! #SEC (pentest, Sep 2026) — this comment used to say the rc.d service a
--! package installs "runs in the user-tier sandbox". It does not: rc.lua runs
--! a service as the principal it DECLARES and as root when it declares none,
--! and a service's libraries load through the kernel loader (allowUserLibs).
--! A service package is trusted with the machine; only command packages are
--! confined to their capabilities. MANUAL section 15 says so to operators.
--
--! #SEC (pentest, Sep 2026) — the exception was enforced as a SHAPE, and
--! the shape matched the system's own files. Two of them made a service
--! package the kernel:
--!   * /etc/rc.d/<stem>.lua with <stem> on rc.lua's KERNEL_SERVICE_ALLOWLIST.
--!     rc grants `_kernel_` by FILENAME and no package owns the shipped
--!     scripts, so findConflicts never fired: a package replacing
--!     20-rshd.lua with `user = "_kernel_"` ran in buildKernelEnv at the
--!     next boot, where require("component") is the raw component API.
--!   * /etc/<name>.cfg for a config the SYSTEM reads: component_caps.cfg
--!     (base = {"filesystem"} hands every sandbox holding `component` a raw
--!     disk proxy), pkg_trust.cfg (trust the attacker's key), boot.cfg ...
--! Both are refused by name, case-folded (20-RSHD.lua IS 20-rshd.lua on a
--! case-insensitive host). Add-on cfgs (cluster-master.cfg, rbmk.cfg) stay
--! writable; a cfg the kernel starts reading goes in SYSTEM_ETC_CFG in the
--! same commit. KERNEL_TIER_RC mirrors rc.lua; test_pkg_protected_targets
--! reads rc.lua's list and fails on any stem this one does not refuse.
local KERNEL_TIER_RC = {
  ["10-discoveryd"] = true, ["20-chatrelay"] = true,
  ["20-fileshare"]  = true, ["20-rshd"]      = true,
}
local SYSTEM_ETC_CFG = {
  ["tos"] = true, ["boot"] = true, ["pkg_trust"] = true, ["pkg_caps"] = true,
  ["pkg-repos"] = true, ["component_caps"] = true, ["netfs-exports"] = true,
  ["kiosk"] = true, ["menu"] = true, ["keys"] = true, ["jbod"] = true,
  ["chat-groups"] = true,
}
local function isServiceEtcTarget(p)
  if type(p) ~= "string" then return false end
  local stem = p:match("^/etc/rc%.d/([%w_%-]+)%.lua$")   -- rc.d entry
  if stem then return not KERNEL_TIER_RC[stem:lower()] end
  local cfg = p:match("^/etc/([%w_%-]+)%.cfg$")            -- top-level cfg
  if cfg then return not SYSTEM_ETC_CFG[cfg:lower()] end
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

--! #SEC A REPO HINT is a URL from a stranger's manifest that this machine
--! may later REQUEST: http(s), a plain host and port, a path of plain
--! characters -- no user@, query, fragment, dot segment, backslash, space or
--! control character. pkgremote is handed this one rule at init.
local MAX_REPO_HINTS = 4
local function validRepoHint(u)
  if type(u) ~= "string" or #u > 200 then return false end
  local host, rest = u:match("^https?://([%w%.%-]+)(.*)$")
  if not host or host:sub(1, 1) == "." or host:sub(1, 1) == "-"
     or host:find("..", 1, true) then
    return false
  end
  local port, path = rest:match("^:(%d+)(.*)$")
  if port then
    if #port > 5 then return false end
    rest = path
  end
  if rest == "" then return true end
  if not rest:match("^/[%w%-%._~/%%+]*$") then return false end
  for seg in rest:gmatch("[^/]+") do
    if seg == "." or seg == ".." then return false end
  end
  return true
end

--- The repo URLs a manifest names, for itself and for what it requires,
--- in order and once each. Not validated here: validateManifest has, for
--- anything that installed.
function pkg.repoHints(m)
  local out, seen = {}, {}
  local function add(list)
    if type(list) ~= "table" then return end
    for _, u in ipairs(list) do
      local k = type(u) == "string" and (u:gsub("/+$", "")) or nil
      if k and not seen[k] then seen[k] = true; out[#out + 1] = k end
    end
  end
  if type(m) ~= "table" then return out end
  add(m.repos)
  for _, req in ipairs(type(m.requires) == "table" and m.requires or {}) do
    if type(req) == "table" then add(req.repos) end
  end
  return out
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
    if not targetShapeOk(p) then   -- #SEC (pentest, Sep 2026) — see targetShapeOk
      return false, "files[" .. i .. "] must use only letters, digits and _ . + - "
        .. "with no empty segment or trailing dot (got " .. p .. ")"
    end
    if isReservedTarget(p) then   -- #SEC (pentest, Sep 2026) — see PKG_RESERVED_ROOTS
      return false, "files[" .. i .. "] is the package manager's own space (" .. p
        .. "): installed manifests, package secrets and remote staging are not a package's to write"
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

  -- Declared runtime (optional): the Lua architecture and the TOS a package
  -- needs. Only the SHAPE is checked here; whether this machine meets them
  -- is runtimeRefusal's question, asked at install and in the plan.
  if m.lua ~= nil and (type(m.lua) ~= "string" or not m.lua:match("^%d+%.%d+$")) then
    return false, 'lua must be a Lua version like "5.3" if present'
  end
  if m.tos ~= nil and (type(m.tos) ~= "string" or not m.tos:match("^%s*[<>=~%^]*%s*%d")) then
    return false, 'tos must be a version constraint like ">=1.5.0" if present'
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
  -- A publisher pin: `{ name = "libgui", key = "<64 hex>" }` means "libgui
  -- as signed by this key" (docs/FEDERATED-REPOS.md). The FULL public key,
  -- not the 16-hex fingerprint: a pin is read by a machine, and truncating
  -- it would only make it cheaper to collide.
  if type(m.requires) == "table" then
    for i, req in ipairs(m.requires) do
      if type(req) == "table" and req.key ~= nil then
        if type(req.key) ~= "string" or #req.key ~= 64 or req.key:find("[^%x]") then
          return false, "requires[" .. i .. "].key is not a 64-hex public key"
        end
        if type(req.name) ~= "string" or req.name == "" then
          return false, "requires[" .. i .. "] pins a key but names no package"
        end
      end
    end
  end
  -- `repos`, on the manifest (where THIS package can be found) and on a
  -- table-form requirement (where THAT one can). Hints only: installing
  -- the package records them as KNOWN, never configured and never
  -- trusted. See validRepoHint for why each string is checked so closely.
  local function checkRepos(list, where)
    if list == nil then return true end
    if type(list) ~= "table" then return false, where .. " must be an array of repo URLs" end
    local n = 0
    for j, u in pairs(list) do
      n = n + 1
      if type(j) ~= "number" or not validRepoHint(u) then
        return false, where .. "[" .. tostring(j) .. "] is not an http(s) repo URL"
      end
    end
    if n > MAX_REPO_HINTS then
      return false, where .. " names more than " .. MAX_REPO_HINTS .. " repos"
    end
    return true
  end
  do
    local okR, rErr = checkRepos(m.repos, "repos")
    if not okR then return false, rErr end
    for i, req in ipairs(type(m.requires) == "table" and m.requires or {}) do
      if type(req) == "table" and req.repos ~= nil then
        if type(req.name) ~= "string" or req.name == "" then
          return false, "requires[" .. i .. "] names repos but no package"
        end
        local okQ, qErr = checkRepos(req.repos, "requires[" .. i .. "].repos")
        if not okQ then return false, qErr end
      end
    end
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
  -- `handles`: the files this package opens, which shell/open.lua ranks
  -- (its own format, files it can open, files whose content is its). A
  -- marker is a plain line prefix the shell compares outside any sandbox,
  -- so it is short and has no control characters; `cmd` must be one of
  -- the package's own commands, or the package must have exactly one.
  if m.handles ~= nil then
    if type(m.handles) ~= "table" or #m.handles > 8 then
      return false, "handles must be an array of at most 8 entries if present"
    end
    local nCmds = 0
    for _ in pairs(type(m.commands) == "table" and m.commands or {}) do nCmds = nCmds + 1 end
    for i, h in ipairs(m.handles) do
      local where = "handles[" .. i .. "]"
      if type(h) ~= "table" or type(h.ext) ~= "table" or #h.ext == 0 or #h.ext > 8 then
        return false, where .. ".ext must list 1 to 8 extensions"
      end
      for _, e in ipairs(h.ext) do
        if type(e) ~= "string" or not e:match("^[%w]+$") or #e > 8 then
          return false, where .. " names an extension that is not 1-8 letters or digits"
        end
      end
      if h.as ~= nil and h.as ~= "native" and h.as ~= "open" then
        return false, where .. '.as must be "native" or "open"'
      end
      if h.markers ~= nil then
        if type(h.markers) ~= "table" or #h.markers == 0 or #h.markers > 8 then
          return false, where .. ".markers must list 1 to 8 line prefixes"
        end
        if h.as == "native" then
          return false, where .. " has markers, so it is not the package's own format"
        end
        for _, mk in ipairs(h.markers) do
          if type(mk) ~= "string" or #mk < 2 or #mk > 24 or mk:find("[%c]") then
            return false, where .. " has a marker that is not 2-24 plain characters"
          end
        end
      end
      if h.cmd ~= nil then
        if type(h.cmd) ~= "string" or type(m.commands) ~= "table" or not m.commands[h.cmd] then
          return false, where .. ".cmd is not one of the package's commands"
        end
      elseif nCmds ~= 1 then
        return false, where .. " names no cmd, and the package has " .. nCmds .. " commands"
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
  -- kernel.pkgops closed over the old fs/log/serialize: drop it, and the
  -- next call to one of its functions loads it again over the new ones.
  if opsAttached then
    opsAttached = false
    for k, v in pairs(opsOwn) do if rawget(pkg, k) == v then rawset(pkg, k, nil) end end
  end

  if not fs then return false, "fs module required" end

  -- Ensure storage root exists. kernel.fs.makeDirectory creates the parent
  -- chain itself, so one call covers /var, /var/pkg, /var/pkg/installed.
  --! It says so because it DOES it: this comment used to claim the OC
  --! proxy recursed, which is false on every backend (see the note on
  --! fs.makeDirectory). On a fresh managed disk this call failed at
  --! /var/pkg and only logged a warning, so a first install had no
  --! package store until something else happened to create the parent.
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
  -- In place, not `installed = {}`: kernel.pkgops holds this table.
  for k in pairs(installed) do installed[k] = nil end
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
--- @tier admin
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
--! #MEM (pentest, Sep 2026) — the cache is BOUNDED. A package command's
--! entry and sandbox stayed resident for good once it had run, and one
--! entry costs 20-82 KB (measured: tetris 69, calc 82, write 82, tape 76,
--! printer 60 -- its own library copies included), so playing tetris and
--! then opening calc and a document pinned ~230 KB on a 256 KB machine
--! until an uninstall. The PKG_CACHE_MAX most recently used entries stay;
--! with free memory under PKG_LOW_MEM, only the one in use. Eviction drops
--! only the cache's reference: a command already running keeps its
--! closures, and the next call recompiles the entry from disk.
--! (test_pkg_cache_bound.lua)
local PKG_CACHE_MAX = 2
local PKG_LOW_MEM   = 48 * 1024
local pkgUse, pkgUseTick = {}, 0
local function lowMemory()
  local okC, comp = pcall(require, "computer")
  return okC and type(comp) == "table" and type(comp.freeMemory) == "function"
    and comp.freeMemory() < PKG_LOW_MEM
end
local function trimCache(limit)
  local names = {}
  for n in pairs(pkgActive) do names[#names + 1] = n end
  if #names <= limit then return end
  table.sort(names, function(a, b) return (pkgUse[a] or 0) > (pkgUse[b] or 0) end)
  for i = limit + 1, #names do pkgActive[names[i]] = nil; pkgUse[names[i]] = nil end
end

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

-- Caps from the manifest's `capabilities` (facet strings, or "facet:scope"),
-- filtered through the allowlist above before reaching the sandbox.
local function grantedCaps(pkgName, m)
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
  return caps
end

--! An OPPM package has no `commands` table: its programs land in /usr/bin
--! and the shell runs them as PATH programs, with the shell's fixed set
--! (fs.read, fs.write, compat.io). So the capabilities granted at install --
--! the compat surface's `component`, or anything the manifest declared and
--! the admin accepted -- never reached the program they were granted for,
--! and the data loot disk's base64 died requiring the data card. The shell
--! asks this for a resolved PATH program and adds what comes back; a file no
--! package owns runs exactly as before. (test_pkg_program_caps.lua)
--- The caps a program FILE that a package installed runs with, and that
--- package's name -- or nil when no enabled package owns `path`.
function pkg.capsForFile(path)
  local owner = pkg.ownerOfFile(path)
  if owner and pkg.isEnabled(owner) then
    return grantedCaps(owner, installed[owner]), owner
  end
  return nil
end

--- Which installed package ships `path`, enabled or not -- or nil.
function pkg.ownerOfFile(path)
  if type(path) ~= "string" or path == "" then return nil end
  local key = targetKey(fs.normalize and fs.normalize(path) or path)
  for pkgName, m in pairs(installed) do
    if type(m.files) == "table" then
      for _, f in ipairs(m.files) do
        if type(f) == "string" and targetKey(f) == key then return pkgName end
      end
    end
  end
  return nil
end

--! A service package that declares defaultState = "disabled" (mail,
--! intercom, cluster-master, cluster-manager) installs with BOTH its rc.d
--! boot marker and its package byte off. `service start` cleared only the
--! marker, so a service the operator had started still read "disabled" to
--! `pkg list`, `pkg upgrade` reported "(was disabled; left disabled)" for
--! it (headless machine, 2026-10-08), and its programs never got the
--! package's caps. Starting the service is the operator's decision to
--! enable the package, so the byte follows. (test_pkg_service_enable.lua)
--- `service start <svc>` succeeded: enable the package that ships its rc.d
--- script, if one does and it is disabled. Returns that package's name
--- when it changed anything, else nil.
--- @tier admin
function pkg.noteServiceStarted(svcName, opts)
  local g = adminGate(opts)
  if not g then return nil end
  if type(svcName) ~= "string" or not svcName:match("^[%w_%-%.]+$") then return nil end
  local owner = pkg.ownerOfFile("/etc/rc.d/" .. svcName .. ".lua")
  if not owner or pkg.isEnabled(owner) then return nil end
  if pkg.setEnabled(owner, true, opts) then return owner end
  return nil
end

local function loadPkgEntry(pkgName, m, entryPath)
  if pkgActive[pkgName] then
    pkgUseTick = pkgUseTick + 1; pkgUse[pkgName] = pkgUseTick
    return pkgActive[pkgName]
  end
  -- Make room BEFORE building, so the new entry is not loaded on top of
  -- every old one (#MEM, see PKG_CACHE_MAX).
  trimCache(lowMemory() and 0 or (PKG_CACHE_MAX - 1))
  if not fs.exists(entryPath) then return nil end
  local source = fs.readFile(entryPath)
  if not source then return nil end
  local caps = grantedCaps(pkgName, m)
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
  pkgUseTick = pkgUseTick + 1; pkgUse[pkgName] = pkgUseTick
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
  if pkgName then pkgActive[pkgName] = nil; pkgUse[pkgName] = nil
  else pkgActive = {}; pkgUse = {} end
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

  -- `req` (the requires entry that led here) and `requirer` are passed to
  -- lookup so it can choose among candidates -- a pinned dependency must
  -- come from its publisher. Lookups that ignore them behave as before.
  local function visit(name, req, requirer)
    if visited[name] then return true end
    if visiting[name] then
      return false, "dependency cycle through " .. name
    end
    local m = lookup(name, req, requirer)
    if not m then
      return false, "unknown package: " .. name
    end
    visiting[name] = true
    if type(m.requires) == "table" then
      for _, req in ipairs(m.requires) do
        local depName, optional
        if type(req) == "table" then depName, optional = req.name, req.optional
        elseif type(req) == "string" then depName = req:match("^(%S+)") end
        if depName then
          -- Already-installed packages don't need to be reinstalled —
          -- skip them in the resolved order. Also accept anything in
          -- the `provides` set of an installed package (EXP-1).
          --! An OPTIONAL requirement that no source can answer is left
          --! out, not an error. It used to be visited like any other, so
          --! a package that could run without a library could not be
          --! installed at all unless the library was somewhere to hand
          --! ("resolve failed: unknown package"). One that IS available
          --! is still installed with it. (test_pkg_optional_requires.lua)
          if not findProvider(depName) and not (optional and not lookup(depName, req, name)) then
            local ok, err = visit(depName, req, name)
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

-- ============================================================
-- Constants exposed for callers that want to know the layout
-- ============================================================

pkg.PKG_ROOT          = PKG_ROOT
pkg.CRITICAL_BACKUP   = CRITICAL_BACKUP
pkg.VALID_KINDS       = VALID_KINDS

-- Test hooks (not part of the public API; mirror crypto._makeIv16).
pkg._validateManifest    = validateManifest
pkg._isUnderPkgWriteRoot = isUnderPkgWriteRoot
pkg._isServiceEtcTarget  = isServiceEtcTarget
pkg.PKG_WRITE_ROOTS      = PKG_WRITE_ROOTS
-- Reading a source directory in ALL four manifest formats, exposed because
-- the OPPM index TOS publishes on its own `master` branch has to be checked
-- against the parser TOS ships — the two are a seam, and the only honest
-- checker for a programs.cfg we publish is our own programs.cfg reader.
-- (test_oppm_index.lua)


-- ============================================================
-- #MEM — the operations half, loaded on first use
-- ============================================================
-- Every name kernel.pkgops defines on `pkg`. test_pkg_split.lua holds this
-- to what the file really defines: a name missing here would read as nil
-- instead of loading the half that has it.
OPS_NAMES = {}
for n in ([[
DEFAULT_REPO_ROOTS _loadAnyManifest _protectedTargetRefusal _signGate
_verificationGate addRepo checkSignature computeLicenseHash
describeConflicts describeContradictions discoveredPolicy exportDisk
findConflicts findInRepos foreignDefaultCaps forgetModules forgetRepo
install installByName installFromFloppy installRemote installWithDeps
knownRepos listAllAvailable listRemoteAvailable listRepo outdated plan
planByName removeRepo repoRoots repos runInstaller runtimeRefusal
searchRemote signPackage signingKey trustAdd trustDiscovered trustList
trustRemove trustRequire trustRequired uninstall upgrade
verifyLicenseKey
]]):gmatch("%S+") do OPS_NAMES[n] = true end
pkg._OPS_NAMES = OPS_NAMES

-- Where this file was loaded from, for an off-box loader with no
-- kernel.* path: the operations sit beside it.
local SELF_DIR = (debug and debug.getinfo and (debug.getinfo(1, "S").source or "")
  :match("^@(.*[/\\])")) or nil

-- The operations are a FACTORY: called with this table and what they share
-- with the core, they define their functions on it. Called again by
-- pkg.init, so they always close over the live fs, log and serialize.
-- `installed` is the same table for the module's life (scan clears it in
-- place).
function attachOps()
  local okR, factory = pcall(require, "kernel.pkgops")
  -- Only when there is no kernel.* path at all: an out-of-memory load is
  -- not retried by compiling the same file again.
  if not okR and SELF_DIR and tostring(factory):find("not found", 1, true) then
    local chunk = loadfile(SELF_DIR .. "pkgops.lua")
    if chunk then okR, factory = pcall(chunk) end
  end
  if not okR or type(factory) ~= "function" then
    error(tostring(factory or "kernel.pkgops did not load"), 0)
  end
  -- A value a caller already put on `pkg` (an off-box test's stub of
  -- listRepo, say) stays: the single-file module never replaced one.
  local kept = {}
  for k in pairs(OPS_NAMES) do kept[k] = rawget(pkg, k) end
  factory(pkg, {
    PKG_ROOT = PKG_ROOT, adminGate = adminGate, findProvider = findProvider,
    serviceInstallGate = serviceInstallGate, targetKey = targetKey,
    validRepoHint = validRepoHint, validateManifest = validateManifest,
    fs = fs, log = log, serialize = serialize, installed = installed,
  })
  opsOwn = {}
  for k in pairs(OPS_NAMES) do
    if kept[k] ~= nil then rawset(pkg, k, kept[k]) else opsOwn[k] = rawget(pkg, k) end
  end
  opsAttached = true
end

-- A name the operations define loads them. If they cannot load -- out of
-- memory, most likely -- the caller gets an ordinary failure, ok=false and
-- the reason, instead of calling nil; nothing is cached, so the next call
-- tries again once memory has freed.
setmetatable(pkg, { __index = function(t, k)
  if not OPS_NAMES[k] or opsAttached then return nil end
  local ok, err = pcall(attachOps)
  if ok then return rawget(t, k) end
  if k:match("^[%u_]+$") then return nil end   -- a constant, not a function
  return function()
    return false, "the package manager's operations could not load: " .. tostring(err)
  end
end })

-- ============================================================
-- #MEM — lazy self-initialization
-- ============================================================
-- The kernel no longer require()s pkg at boot (it is the second-largest
-- module in the OS and most sessions never touch it). Every existing
-- consumer reaches it via pcall(require, "kernel.pkg") — executor command
-- dispatch, the `pkg` command, the installer — so the module initializes
-- itself HERE, on first load, from the live _TOS handles. The boot-time
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
