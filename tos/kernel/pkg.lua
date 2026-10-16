local pkg = {}
local attachOps, opsAttached, OPS_NAMES, opsOwn
local PKG_ROOT = "/var/pkg/installed"
local CRITICAL_BACKUP = "/etc/critical.bak"
local fs = nil
local log = nil
local serialize = nil
local users = nil
local installed = {}
local ADMIN_TIER = 2
local ROOT_TIER = 3
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
pkg._serviceInstallGate = serviceInstallGate
local VALID_KINDS = {
app = true,
command = true,
program = true,
lib = true,
service = true,
runtime = true,
driver = true,
theme = true,
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
if p:sub(1, #root) == root and #p > #root then return true end
end
return false
end
--! #SEC (pentest, Sep 2026) — this comment used to say the rc.d service a
--! package installs "runs in the user-tier sandbox". It does not: rc.lua runs
--! a service as the principal it DECLARES and as root when it declares none,
--! and a service's libraries load through the kernel loader (allowUserLibs).
--! A service package is trusted with the machine; only command packages are
--! confined to their capabilities. MANUAL section 15 says so to operators.
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
["20-fileshare"] = true, ["20-rshd"] = true,
}
local SYSTEM_ETC_CFG = {
["tos"] = true, ["boot"] = true, ["pkg_trust"] = true, ["pkg_caps"] = true,
["pkg-repos"] = true, ["component_caps"] = true, ["netfs-exports"] = true,
["kiosk"] = true, ["menu"] = true, ["keys"] = true, ["jbod"] = true,
["chat-groups"] = true,
}
local function isServiceEtcTarget(p)
if type(p) ~= "string" then return false end
local stem = p:match("^/etc/rc%.d/([%w_%-]+)%.lua$")
if stem then return not KERNEL_TIER_RC[stem:lower()] end
local cfg = p:match("^/etc/([%w_%-]+)%.cfg$")
if cfg then return not SYSTEM_ETC_CFG[cfg:lower()] end
return false
end
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
for i, p in ipairs(m.files) do
if type(p) ~= "string" or p:sub(1, 1) ~= "/" then
return false, "files[" .. i .. "] is not an absolute path"
end
if pathHasTraversal(p) then
return false, "files[" .. i .. "] contains an unsafe path segment"
end
if not targetShapeOk(p) then
return false, "files[" .. i .. "] must use only letters, digits and _ . + - "
.. "with no empty segment or trailing dot (got " .. p .. ")"
end
if isReservedTarget(p) then
return false, "files[" .. i .. "] is the package manager's own space (" .. p
.. "): installed manifests, package secrets and remote staging are not a package's to write"
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
if m.lua ~= nil and (type(m.lua) ~= "string" or not m.lua:match("^%d+%.%d+$")) then
return false, 'lua must be a Lua version like "5.3" if present'
end
if m.tos ~= nil and (type(m.tos) ~= "string" or not m.tos:match("^%s*[<>=~%^]*%s*%d")) then
return false, 'tos must be a version constraint like ">=1.5.0" if present'
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
fs = deps.fs
log = deps.log
users = deps.users
serialize = require("kernel.serialize")
if opsAttached then
opsAttached = false
for k, v in pairs(opsOwn) do if rawget(pkg, k) == v then rawset(pkg, k, nil) end end
end
if not fs then return false, "fs module required" end
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
function pkg.scan()
for k in pairs(installed) do installed[k] = nil end
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
name = m.name,
version = m.version,
kind = m.kind,
description = m.description,
enabled = pkg.isEnabled(name),
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
local PKG_LOW_MEM = 48 * 1024
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
local _capAllow = {}
local _capDeny = {}
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
function pkg.capsForFile(path)
local owner = pkg.ownerOfFile(path)
if owner and pkg.isEnabled(owner) then
return grantedCaps(owner, installed[owner]), owner
end
return nil
end
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
trimCache(lowMemory() and 0 or (PKG_CACHE_MAX - 1))
if not fs.exists(entryPath) then return nil end
local source = fs.readFile(entryPath)
if not source then return nil end
local caps = grantedCaps(pkgName, m)
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
pkgUseTick = pkgUseTick + 1; pkgUse[pkgName] = pkgUseTick
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
if pkgName then pkgActive[pkgName] = nil; pkgUse[pkgName] = nil
else pkgActive = {}; pkgUse = {} end
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
if sa == "" then return 1 end
if sb == "" then return -1 end
if sa < sb then return -1 end
if sa > sb then return 1 end
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
if op == ">" then return cmp > 0 end
if op == ">=" then return cmp >= 0 end
if op == "<" then return cmp < 0 end
if op == "<=" then return cmp <= 0 end
if op == "=" or op == "==" then return cmp == 0 end
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
reqName = req.name
reqConstraint = req.version
optional = req.optional
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
local visited = {}
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
pkg.PKG_ROOT = PKG_ROOT
pkg.CRITICAL_BACKUP = CRITICAL_BACKUP
pkg.VALID_KINDS = VALID_KINDS
pkg._validateManifest = validateManifest
pkg._isUnderPkgWriteRoot = isUnderPkgWriteRoot
pkg._isServiceEtcTarget = isServiceEtcTarget
pkg.PKG_WRITE_ROOTS = PKG_WRITE_ROOTS
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
local SELF_DIR = (debug and debug.getinfo and (debug.getinfo(1, "S").source or "")
:match("^@(.*[/\\])")) or nil
function attachOps()
local okR, factory = pcall(require, "kernel.pkgops")
if not okR and SELF_DIR and tostring(factory):find("not found", 1, true) then
local chunk = loadfile(SELF_DIR .. "pkgops.lua")
if chunk then okR, factory = pcall(chunk) end
end
if not okR or type(factory) ~= "function" then
error(tostring(factory or "kernel.pkgops did not load"), 0)
end
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
setmetatable(pkg, { __index = function(t, k)
if not OPS_NAMES[k] or opsAttached then return nil end
local ok, err = pcall(attachOps)
if ok then return rawget(t, k) end
if k:match("^[%u_]+$") then return nil end
return function()
return false, "the package manager's operations could not load: " .. tostring(err)
end
end })
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
