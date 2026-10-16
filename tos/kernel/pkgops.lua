return function(pkg, C)
local PKG_ROOT, adminGate, findProvider = C.PKG_ROOT, C.adminGate, C.findProvider
local serviceInstallGate, targetKey = C.serviceInstallGate, C.targetKey
local validRepoHint, validateManifest = C.validRepoHint, C.validateManifest
local fs, log, serialize, installed = C.fs, C.log, C.serialize, C.installed
local remoteMod
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
name = name,
version = inner.version or "0.0.0",
kind = inner.kind or "command",
files = {},
fileMap = {},
requires = translateDeps(inner.dependencies),
commands = inner.commands,
capabilities = inner.capabilities,
description = inner.description or inner.note,
author = inner.author or inner.authors,
hashes = inner.hashes,
_srcBase = srcBase,
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
--! #SEC (pentest, Sep 2026) — a manifest is READ ONCE. The signature
--! layer verifies raw bytes and used to re-read the file for them, after
--! this reader had parsed its own copy. On storage that answers each read
--! afresh (a network mount, which repo discovery walks like any other
--! mount) the far end could hand the parser its own files and hashes and
--! the verifier a trusted publisher's signed manifest, and the package
--! installed as "trusted", past `pkg trust require on`. The bytes parsed
--! here are returned with the table, and signGate verifies exactly those.
--!
--! #SEC / #MEM (pentest, Sep 2026) — and bounded. A manifest comes off a
--! floppy or a network mount and is parsed before any signature is
--! checked. It was read whole and decoded with only the default 256 KB
--! byte cap, so a package.lua of "{{{}},{{}},...}" made `pkg list` build
--! 1.5 MB of tables before the per-table entry cap refused it. The largest
--! real manifest (Optional Utilities' programs.cfg, 8.6 KB) is charged 26
--! KB of the budget below. (test_untrusted_index_budget.lua)
local MANIFEST_MAX_BYTES = 64 * 1024
local MANIFEST_MAX_COST = 64 * 1024
local function readManifestFile(path)
local sz = fs.size and fs.size(path)
if type(sz) == "number" and sz > MANIFEST_MAX_BYTES then
return nil, "manifest too large (" .. sz .. " bytes; at most " .. MANIFEST_MAX_BYTES .. ")"
end
local bytes, err = fs.readFile(path)
if type(bytes) ~= "string" then return nil, err end
local m, dErr = serialize.decode(bytes, { maxBytes = MANIFEST_MAX_BYTES,
maxCost = MANIFEST_MAX_COST, maxKeys = 1024 })
return m, dErr, bytes
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
local raw, err, bytes = readManifestFile(cand.path)
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
return tm, nil, cand.path, bytes
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
local function fromDisk(m, kind, path, bytes)
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
return m, kind, path, bytes
end
local nativePath = fs.join(srcDir, "package.lua")
if fs.exists(nativePath) then
local m, err, bytes = readManifestFile(nativePath)
if m then return fromDisk(m, "native", nativePath, bytes) end
return nil, "package.lua parse error: " .. tostring(err)
end
local oppmPath = fs.join(srcDir, "package.oppm.lua")
if fs.exists(oppmPath) then
local raw, err, oppmBytes = readManifestFile(oppmPath)
if not raw then return nil, "package.oppm.lua parse error: " .. tostring(err) end
local outerName, inner = next(raw)
if not inner or type(inner) ~= "table" then
return nil, "OPPM manifest has no top-level package entry"
end
local translated = {
name = outerName,
version = inner.version or "0.0.0",
kind = inner.kind or "command",
files = {},
requires = {},
commands = inner.commands,
capabilities = inner.capabilities,
description = inner.description,
author = inner.author,
critical = inner.critical,
hashes = inner.hashes,
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
return fromDisk(translated, "oppm", oppmPath, oppmBytes)
end
local base = srcDir:match("([^/]+)/?$")
if base then
local cfgPath = fs.join(srcDir, base .. ".cfg")
if fs.exists(cfgPath) then
local raw, err, cfgBytes = readManifestFile(cfgPath)
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
name = inner.name or outerName,
version = inner.version or "0.0.0",
kind = inner.kind or "command",
files = {},
requires = {},
commands = inner.commands,
capabilities = inner.capabilities,
description = inner.description,
author = inner.author,
hashes = inner.hashes,
}
if type(inner.files) == "table" then
for k, v in pairs(inner.files) do
if type(v) == "string" then translated.files[#translated.files + 1] = v
elseif type(k) == "string" then translated.files[#translated.files + 1] = k end
end
end
translated.requires = translateDeps(inner.dependencies)
return fromDisk(translated, "oppm", cfgPath, cfgBytes)
end
end
local m, cfgErr, cfgPath2, idxBytes = loadFromProgramsCfg(srcDir)
if m then return m, "oppm", cfgPath2, idxBytes end
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
for _, f in ipairs(other.files or {}) do owner[targetKey(f)] = otherName end
end
end
for _, f in ipairs(m.files or {}) do
local o = owner[targetKey(f)]
if o then
out[#out + 1] = { kind = "file", other = o, detail = f, path = f }
end
end
return out
end
--! #SEC (pentest, Sep 2026) — findConflicts protects one PACKAGE's files
--! from another. Nothing protected the SYSTEM's: no package owns
--! /usr/bin/ssh.lua or /etc/rc.d/20-netfsd.lua, so writing over them was
--! not a conflict at all and needed no --force. This refusal has no
--! --force; an admin who means to replace a system file has an editor.
--! Refused, for every target:
--!   * any path /tos/system_manifest.lua lists (read as DATA);
--!   * a module the KERNEL would load. require() searches /tos and then
--!     /usr/lib and /usr/modules, and runs what it finds in the kernel's
--!     own _G. /usr/lib/kernel/* etc. would answer any kernel.* or shell.*
--!     name /tos lacks, and the add-on names the SHELL requires in kernel
--!     context (KERNEL_CONTEXT_LIBS) run unsandboxed at shell start, so
--!     only the first-party package of that name may ship them.
--!     test_pkg_protected_targets rescans the shell for new ones;
--!   * an existing /etc file no installed package owns: an operator's own
--!     rc.d script or config is not a package's to replace.
local SYSTEM_MANIFEST = "/tos/system_manifest.lua"
local RESERVED_LIB_NAMESPACES = {
kernel = true, shell = true, compat = true, peripheral = true,
system_manifest = true,
}
local KERNEL_CONTEXT_LIBS = {
mail = { mail = true }, mailapp = { mail = true },
intercom = { intercom = true }, intercomapp = { intercom = true },
blockfs = { blockfs = true }, mouse = { mouse = true },
["cluster-manager"] = { ["cluster-manager"] = true },
cluster = { ["cluster-manager"] = true, ["cluster-master"] = true,
["cluster-storage"] = true },
["rbmk-cmd"] = { ["rbmk-control"] = true },
}
local KERNEL_LIB_ROOTS = { "/usr/lib/", "/usr/modules/" }
local function protectedTargetRefusal(m, prior)
if type(m) ~= "table" or type(m.files) ~= "table" then return nil end
local sys = {}
local list = serialize and serialize.loadFile(fs, SYSTEM_MANIFEST)
if type(list) == "table" then
for _, e in ipairs(list) do
if type(e) == "table" and type(e.path) == "string" then sys[targetKey(e.path)] = true end
end
elseif log then
log.warn("pkg", "cannot read " .. SYSTEM_MANIFEST .. "; system files are not protected from packages")
end
local owned = {}
for _, other in pairs(installed) do
for _, f in ipairs(other.files or {}) do owned[targetKey(f)] = true end
end
for _, f in ipairs(prior or {}) do owned[targetKey(f)] = true end
for _, target in ipairs(m.files) do
local key = targetKey(target)
if sys[key] then return tostring(target) .. " is a TOS system file" end
for _, root in ipairs(KERNEL_LIB_ROOTS) do
if key:sub(1, #root) == root then
local mod = (key:sub(#root + 1):match("^([^/]+)") or ""):gsub("%.lua$", "")
if RESERVED_LIB_NAMESPACES[mod] then
return tostring(target) .. " would be loaded by the kernel as its own '"
.. mod .. "' module"
end
local owners = KERNEL_CONTEXT_LIBS[mod]
if owners and not owners[m.name] then
local names = {}
for n in pairs(owners) do names[#names + 1] = n end
table.sort(names)
return tostring(target) .. " is the '" .. mod .. "' library, which the shell "
.. "runs with full system authority; only " .. table.concat(names, " / ")
.. " may provide it"
end
end
end
if key:sub(1, 5) == "/etc/" and not owned[key] and fs.exists(target) then
return tostring(target) .. " already exists and no installed package owns it"
end
end
return nil
end
pkg._protectedTargetRefusal = protectedTargetRefusal
--! A package is its name PLUS the key that signs it
--! (docs/FEDERATED-REPOS.md). These are the one place a key is compared
--! and the one place it is described to an operator.
local function verifiedKey(verdict)
if type(verdict) ~= "table" or type(verdict.key) ~= "string" then return nil end
if verdict.state ~= "trusted" and verdict.state ~= "unknown" then return nil end
return verdict.key:lower()
end
local function describeKey(key, label)
if type(key) ~= "string" then return "no signature" end
local okS, ps = pcall(require, "kernel.pkgsign")
local fp = (okS and ps and ps.fingerprint) and ps.fingerprint(key) or key:sub(1, 16)
if okS and ps and ps.labelForKey and not label then label = ps.labelForKey(key) end
return (label and ("'" .. label .. "'") or "an untrusted key") .. " (" .. fp .. ")"
end
local function parseRequire(req)
if type(req) == "table" then
local key = (type(req.key) == "string" and #req.key == 64 and not req.key:find("[^%x]"))
and req.key:lower() or nil
return req.name, req.version, req.optional and true or false, key
elseif type(req) == "string" then
local n, c = req:match("^(%S+)%s+(.+)$")
if n then return n, c, false, nil end
return req, nil, false, nil
end
return nil
end
local function claimedKey(manifestPath)
if type(manifestPath) ~= "string" then return nil end
local okS, ps = pcall(require, "kernel.pkgsign")
if not okS or type(ps) ~= "table" or not ps.readSig or not ps.sigPathFor then return nil end
if ps.init then ps.init({ fs = fs, serialize = serialize, log = log }) end
local sigPath = ps.sigPathFor(manifestPath)
local rec = sigPath and ps.readSig(sigPath) or nil
return rec and rec.key or nil
end
local function installedKey(m)
return type(m) == "table" and type(m._sigKey) == "string" and m._sigKey:lower() or nil
end
--! The four kinds are in docs/FEDERATED-REPOS.md; slice 1 finds the ones
--! local sources can have. Each is { kind=, name=, text=, id= }: `text` is
--! for the operator and names who needs what, `id` is stable across
--! versions so an upgrade can tell a contradiction it INTRODUCES from one
--! that was already there.
local function requirementContradictions(pname, req, provider, providerKey, where)
local out = {}
local dep, constraint, _, pin = parseRequire(req)
if not dep or type(provider) ~= "table" then return out end
if constraint and not pkg.satisfiesConstraint(provider.version or "0.0.0", constraint) then
out[#out + 1] = { kind = "version", name = dep,
id = "version|" .. dep .. "|" .. constraint,
text = string.format("%s requires '%s' %s, and %s is %s",
pname, dep, constraint, where, tostring(provider.version)) }
end
if pin and providerKey ~= pin then
out[#out + 1] = { kind = "publisher", name = dep,
id = "publisher|" .. dep .. "|" .. pin,
text = string.format("%s requires '%s' signed by %s, and %s has %s",
pname, dep, describeKey(pin), where,
providerKey and describeKey(providerKey) or "no signature") }
end
return out
end
local function brokenDependents(m, key)
local out, names = {}, {}
local answers = { [m.name] = true }
for _, p in ipairs(type(m.provides) == "table" and m.provides or {}) do
if not installed[p] then answers[p] = true end
end
for dname in pairs(installed) do names[#names + 1] = dname end
table.sort(names)
for _, dname in ipairs(names) do
local d = installed[dname]
if dname ~= m.name and type(d.requires) == "table" then
for _, req in ipairs(d.requires) do
local dep = parseRequire(req)
if dep and answers[dep] then
for _, c in ipairs(requirementContradictions("the installed " .. dname, req, m, key,
"the " .. tostring(m.name) .. " being put in")) do
c.kind, c.id = "breaks", "breaks|" .. dname .. "|" .. c.id
out[#out + 1] = c
end
end
end
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
local m, source, manifestPath, manifestBytes = loadAnyManifest(pkgDir)
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
return false, "conflicts: " .. pkg.describeConflicts(conflicts) .. "  [E-613 ERR_PKG_CONFLICT]"
end
--! #SEC (pentest, Sep 2026) — refusals install() would make AFTER the old
--! version is gone are made here, while it is still installed. A candidate
--! that fails validation or targets a protected path otherwise costs the
--! operator the working version it was meant to replace.
local vmOk, vmErr = validateManifest(m)
if not vmOk then return false, "invalid manifest: " .. tostring(vmErr) end
local svcOk, svcErr = serviceInstallGate(m, opts)
if not svcOk then return false, "refusing to upgrade '" .. name .. "': " .. svcErr end
local prot = protectedTargetRefusal(m)
if prot then return false, "refusing to upgrade '" .. name .. "': " .. prot .. "  [E-612 ERR_PKG_PROTECTED_TARGET]" end
--! The signature gate, too. It lived only in install(), which runs AFTER
--! the old version is removed, so a candidate whose signature did not
--! verify -- or an unsigned one under `pkg trust require on` -- deleted
--! the working package and was then refused, leaving neither. (federated
--! repos slice 1, finding 3; test_pkg_upgrade_identity.lua)
local sigVerdict, sigRefusal = pkg._signGate(manifestPath, opts, manifestBytes)
if sigRefusal then return false, "refusing to upgrade '" .. name .. "': " .. sigRefusal end
--! An upgrade does not change who publishes a package. The candidate
--! was chosen by NAME (findInRepos is first-match), so a trusted
--! package upgraded silently to one signed by a stranger, or to an
--! unsigned one, and `pkg info` said so only afterwards. Signed by K
--! stays signed by K; gaining a signature is fine; --force is the way
--! through for a publisher that really did change keys, until rotation
--! notices exist (federated repos slice 4). expectKey makes install()
--! hold the same line against the bytes IT reads. (finding 2;
--! test_pkg_upgrade_identity.lua)
local expectKey
local curKey = type(cur._sigKey) == "string" and cur._sigKey:lower() or nil
if curKey then
local newKey = verifiedKey(sigVerdict)
if newKey ~= curKey then
if not opts.force then
return false, string.format(
"refusing to upgrade '%s': the installed version is signed by %s, and the "
.. "candidate in %s has %s. An upgrade does not change who publishes a package; "
.. "if the publisher really changed keys, confirm the new fingerprint with them "
.. "over another channel, then use --force.",
name, describeKey(curKey, cur._sigLabel), tostring(pkgDir),
newKey and ("a different key: " .. describeKey(newKey)) or "no valid signature")
.. "  [E-611 ERR_PKG_WRONG_PUBLISHER]"
end
if log then
log.warn("pkg", "Upgrading '" .. name .. "' to a different publisher (--force): "
.. describeKey(curKey, cur._sigLabel) .. " -> " .. describeKey(newKey))
end
else
expectKey = curKey
end
end
--! What this upgrade would contradict, found before anything is removed:
--! the candidate's requirements against what is installed, and installed
--! packages whose requirements the candidate would stop meeting (a
--! dependent that needs lib <2 while lib goes to 2.1). Both used to pass
--! unremarked. Only contradictions the upgrade INTRODUCES count: one the
--! installed version already had is not made worse by replacing it, and
--! refusing on it would leave a machine unable to upgrade its way out.
--! (federated repos slice 1, finding 4; test_pkg_plan.lua)
do
local function problemsOf(pm, key)
local out = {}
for _, req in ipairs(type(pm.requires) == "table" and pm.requires or {}) do
local dep, _, optional = parseRequire(req)
if dep and dep ~= name then
local have = findProvider(dep)
if have then
for _, c in ipairs(requirementContradictions(name .. " " .. tostring(pm.version),
req, have, installedKey(have), "the installed " .. tostring(have.name))) do
out[#out + 1] = c
end
elseif not optional then
out[#out + 1] = { kind = "missing", name = dep, id = "missing|" .. dep,
text = string.format("%s %s requires '%s', which is not installed (install it first)",
name, tostring(pm.version), dep) }
end
end
end
for _, c in ipairs(brokenDependents(pm, key)) do out[#out + 1] = c end
return out
end
local already = {}
for _, c in ipairs(problemsOf(cur, installedKey(cur))) do already[c.id] = true end
local introduced = {}
for _, c in ipairs(problemsOf(m, verifiedKey(sigVerdict))) do
if not already[c.id] then introduced[#introduced + 1] = c end
end
if #introduced > 0 then
local why = pkg.describeContradictions(introduced)
if not opts.force then return false, "refusing to upgrade '" .. name .. "': " .. why end
if log then log.warn("pkg", "Upgrading '" .. name .. "' past contradictions (--force): " .. why) end
end
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
allowUnsigned = opts.allowUnsigned,
expectKey = expectKey,
_priorFiles = cur.files,
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
function pkg.forgetModules(paths)
local from = package and package.loadedFrom
if type(from) ~= "table" or type(paths) ~= "table" then return 0 end
local gone = {}
for _, p in ipairs(paths) do gone[p] = true end
local n = 0
for modName, path in pairs(from) do
if gone[path] then
package.loaded[modName] = nil
from[modName] = nil
n = n + 1
end
end
return n
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
local function signGate(manifestPath, opts, manifestBytes)
if not manifestPath then
return { state = "unsigned", reason = "manifest path unknown" }, nil
end
local okS, ps = pcall(require, "kernel.pkgsign")
if not okS or not ps then
return { state = "unsigned", reason = "signature support unavailable" }, nil
end
ps.init({ fs = fs, serialize = serialize, log = log })
local verdict = ps.verifyManifest(manifestPath, manifestBytes)
if verdict.state == "invalid" then
return verdict, "refusing to install '" .. tostring(manifestPath)
.. "': its signature does not verify (" .. tostring(verdict.reason)
.. "). This is tampering or corruption, not a missing signature, and there is no override."
.. "  [E-609 ERR_PKG_SIGNATURE_INVALID]"
end
--! `pkg trust require on` has to mean signed BY SOMEONE THIS MACHINE
--! TRUSTS, not merely "carries a signature".
--!
--! It used to refuse only `unsigned`, so a package signed by a key
--! nobody had ever heard of installed with a warning. Anyone can
--! generate a key in seconds and sign anything with it, so that gate
--! stopped honest unsigned packages and nothing an attacker would
--! actually do -- while reading, to an operator who had switched it
--! on, like a guarantee of provenance.
--!
--! The two refusals are worded separately because the remedies are
--! different: an unsigned package needs the publisher to sign it, an
--! untrusted one needs a decision from the person at the keyboard.
if ps.requiresSignature() and not opts.allowUnsigned then
if verdict.state == "unsigned" then
return verdict, "refusing to install an unsigned package: this machine is set to "
.. "require signatures (pkg trust require off, or --allow-unsigned for one install)."
.. "  [E-610 ERR_PKG_SIGNATURE_REQUIRED]"
end
if verdict.state == "unknown" then
return verdict, "refusing to install '" .. tostring(manifestPath)
.. "': its signature is valid but the key is not trusted here, and this machine "
.. "is set to require signatures. Trust the publisher with 'pkg trust add <name> "
.. tostring(verdict.key) .. "' (fingerprint " .. tostring(verdict.fingerprint)
.. " -- compare it with the publisher over a channel that is NOT this package), "
.. "or use --allow-unsigned for one install." .. "  [E-610 ERR_PKG_SIGNATURE_REQUIRED]"
end
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
.. "' (" .. why .. "). Re-run with --allow-unverified to override." .. "  [E-607 ERR_PKG_UNVERIFIED]", false
end
function pkg.install(srcDir, opts)
opts = opts or {}
local g, gErr = adminGate(opts)
if not g then return false, gErr end
if type(srcDir) ~= "string" or srcDir == "" then
return false, "invalid source directory"
end
srcDir = fs.normalize(srcDir)
local m, source, manifestPath, manifestBytes = loadAnyManifest(srcDir)
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
local svcOk, svcErr = serviceInstallGate(m, opts)
if not svcOk then return false, svcErr end
do
local rt = pkg.runtimeRefusal(m)
if rt and not opts.force then return false, rt end
if rt and log then log.warn("pkg", "Installing past a runtime requirement (force): " .. rt) end
end
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
do
local why = protectedTargetRefusal(m, opts._priorFiles)
if why then return false, "refusing to install '" .. tostring(m.name) .. "': " .. why .. "  [E-612 ERR_PKG_PROTECTED_TARGET]" end
end
local conflicts = pkg.findConflicts(m, opts.upgrading and m.name or nil)
if #conflicts > 0 and not opts.force then
return false, "conflicts: " .. pkg.describeConflicts(conflicts) .. "  [E-613 ERR_PKG_CONFLICT]"
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
local verdict, refusal = signGate(manifestPath, opts, manifestBytes)
if refusal then return false, refusal end
--! opts.expectKey: the caller already decided WHICH publisher this
--! must be (an upgrade keeping its publisher; a pinned dependency),
--! having looked at the disk once. This is the check that counts,
--! because it is made on the bytes this install parsed and is about to
--! copy from. It only ever narrows: every gate above still applied.
if type(opts.expectKey) == "string" and verifiedKey(verdict) ~= opts.expectKey:lower() then
return false, string.format("refusing to install '%s': it must be signed by %s, "
.. "and this copy has %s", tostring(m.name), describeKey(opts.expectKey),
verifiedKey(verdict) and describeKey(verifiedKey(verdict)) or "no valid signature")
.. "  [E-611 ERR_PKG_WRONG_PUBLISHER]"
end
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
--! An OPPM key's first segment is the BRANCH ("master/gui/gui.lua"):
--! OPPM appends the key to a raw URL, where that is right, and `pkg
--! fetch` stages files the same way, so the literal path is tried
--! first and still wins when it exists. A git CHECKOUT of that branch
--! has no such directory -- the file is gui/gui.lua -- so a cloned
--! OPPM repo on a floppy read as "missing source file". Only for a
--! translated programs.cfg (_srcBase), and the hash check below
--! applies to whichever copy is read. (test_oppm_index.lua)
if m._srcBase and not fs.exists(src) then
local rest = mapped:match("^[^/]+/(.+)$")
if rest then
local alt = fs.normalize(m._srcBase .. "/" .. rest)
if fs.exists(alt) then src = alt end
end
end
else
src = fs.normalize(srcDir .. target)
end
local data, readErr = fs.readFile(src)
if not data then
for _, p in ipairs(copied) do pcall(fs.remove, p) end
if fs.exists(src) then
return false, "cannot read source file " .. src .. ": " .. tostring(readErr or "read failed")
.. "  [E-605 ERR_PKG_FILE_UNREADABLE]"
end
return false, "missing source file: " .. src .. "  [E-604 ERR_PKG_FILE_MISSING]"
end
if cryptoMod then
local expected = m.hashes[target]
if expected then
if not cryptoMod.ctEquals(cryptoMod.hash(data), expected) then
for _, p in ipairs(copied) do pcall(fs.remove, p) end
return false, "hash mismatch on " .. target .. "  [E-608 ERR_PKG_HASH_MISMATCH]"
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
m._sigKey = sigVerdict and sigVerdict.key or nil
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
local hints = pkg.repoHints(m)
if #hints > 0 then
local rm = remoteMod()
if rm and rm.learn then pcall(rm.learn, hints, m.name) end
end
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
--! An install used to be worked out one question at a time -- which
--! packages, in what order -- and everything else was found out while
--! files were being written, or after (checkRequires only WARNS, once the
--! package is down). pkg.plan answers it all first and touches nothing:
--! what goes in and in what order, which copy of each, which publisher
--! each pinned package must be signed by, and every contradiction found
--! on the way. installWithDeps refuses a plan with contradictions unless
--! forced, so a refusal costs nothing. (docs/FEDERATED-REPOS.md)
--! A package written for a newer Lua than the CPU runs used to fail at
--! LOAD, as a syntax error naming a line of someone else's code. The
--! manifest can say what it needs (`lua = "5.4"`, `tos = ">=1.5.0"`), and
--! the refusal then says what to do about it. (test_pkg_runtime.lua)
function pkg.runtimeRefusal(m)
if type(m) ~= "table" then return nil end
local name = tostring(m.name or "this package")
if type(m.lua) == "string" then
local want = m.lua:match("^(%d+%.%d+)$")
local have = tostring(_VERSION or ""):match("(%d+%.%d+)")
if want and have and pkg.compareVersion(have, want) < 0 then
return string.format("'%s' needs the Lua %s architecture; this CPU runs Lua %s. "
.. "Sneak-right-click the CPU (or APU) to switch its architecture, then reboot.",
name, want, have)
end
end
if type(m.tos) == "string" then
local T = rawget(_G, "_TOS")
local have = T and T.version
if have and not pkg.satisfiesConstraint(have, m.tos) then
return string.format("'%s' needs TOS %s; this is TOS %s.", name, m.tos, have)
end
end
return nil
end
function pkg.describeContradictions(list)
local out = {}
for _, c in ipairs(list or {}) do out[#out + 1] = tostring(c.text) end
return table.concat(out, "; ")
end
function pkg.plan(repoDir, targetName, opts)
opts = opts or {}
if type(repoDir) ~= "string" or repoDir == "" then
return nil, "invalid repo dir"
end
if type(targetName) ~= "string" or targetName == "" then
return nil, "invalid target name"
end
repoDir = fs.normalize(repoDir)
if not fs.exists(repoDir) or not fs.isDirectory(repoDir) then
return nil, "repo dir not found: " .. repoDir
end
local roots, seenRoot = {}, {}
local function addRoot(r)
if type(r) ~= "string" or r == "" then return end
r = fs.normalize(r)
if not seenRoot[r] then seenRoot[r] = true; roots[#roots + 1] = r end
end
addRoot(repoDir)
if type(opts.extraRoots) == "table" then
for _, r in ipairs(opts.extraRoots) do addRoot(r) end
end
local okR, known = pcall(pkg.repoRoots)
if okR and type(known) == "table" then
for _, r in ipairs(known) do addRoot(r) end
end
local manifestCache, chosenDir, chosenPath, pinMiss = {}, {}, {}, {}
local function lookup(name, req, requirer)
if installed[name] then return installed[name] end
if manifestCache[name] then return manifestCache[name] end
local _, constraint, _, want = parseRequire(req)
local fallback
for _, root in ipairs(roots) do
local pkgSrc = fs.join(root, name)
if fs.exists(pkgSrc) then
local m, _, mPath = loadAnyManifest(pkgSrc)
if m and m.name == name then
local have = want and claimedKey(mPath) or nil
if want and have ~= want then
pinMiss[name] = pinMiss[name] or { dir = pkgSrc, have = have, want = want, by = requirer }
if log then
log.warn("pkg", "Passing over '" .. name .. "' in " .. root .. ": "
.. tostring(requirer) .. " requires it signed by another key")
end
elseif constraint and not pkg.satisfiesConstraint(m.version or "0.0.0", constraint) then
fallback = fallback or { m = m, dir = pkgSrc, path = mPath }
else
manifestCache[name], chosenDir[name], chosenPath[name] = m, pkgSrc, mPath
return m
end
elseif m and log then
log.warn("pkg", "Ignoring '" .. tostring(name) .. "' in " .. root ..
": manifest name '" .. tostring(m.name) .. "' does not match directory")
end
end
end
if fallback then
manifestCache[name], chosenDir[name], chosenPath[name] = fallback.m, fallback.dir, fallback.path
return fallback.m
end
return nil
end
local order, resolveErr = pkg.resolveInstallOrder(targetName, lookup)
if not order then
local missing = tostring(resolveErr):match("^unknown package: (.+)$")
local miss = missing and pinMiss[missing]
if miss then
return nil, string.format("%s requires '%s' signed by %s; no copy signed by that "
.. "key was found (the one in %s has %s)", tostring(miss.by), missing,
describeKey(miss.want), miss.dir, miss.have and describeKey(miss.have) or "no signature")
end
return nil, "resolve failed: " .. tostring(resolveErr)
end
for _, pname in ipairs(order) do
local pm = manifestCache[pname]
if pm then
local okV, vErr = validateManifest(pm)
if not okV then return nil, "invalid manifest for '" .. pname .. "': " .. tostring(vErr) end
end
end
local plan = { order = order, dirs = chosenDir, expectKey = {}, contradictions = {} }
local function contradiction(kind, name, text)
plan.contradictions[#plan.contradictions + 1] =
{ kind = kind, name = name, text = text, id = kind .. "|" .. tostring(name) }
end
local pinned = {}
for _, pname in ipairs(order) do
local pm = manifestCache[pname]
if pm and type(pm.requires) == "table" then
for _, req in ipairs(pm.requires) do
local dep, _, _, key = parseRequire(req)
if dep and key then
local first = pinned[dep]
if not first then
pinned[dep] = { key = key, by = pname }
elseif first.key ~= key then
contradiction("pins", dep, string.format(
"%s requires '%s' signed by %s, but %s requires it signed by %s",
first.by, dep, describeKey(first.key), pname, describeKey(key)))
end
end
local have = dep and findProvider(dep)
local found = {}
if have then
found = requirementContradictions(pname, req, have, installedKey(have),
"the installed " .. tostring(have.name))
elseif dep and manifestCache[dep] then
local ck = claimedKey(chosenPath[dep])
found = requirementContradictions(pname, req, manifestCache[dep], ck,
"the copy in " .. tostring(chosenDir[dep]))
if key and ck == key and not plan.expectKey[dep] then plan.expectKey[dep] = key end
end
for _, c in ipairs(found) do plan.contradictions[#plan.contradictions + 1] = c end
end
end
if pm then
for _, c in ipairs(brokenDependents(pm, claimedKey(chosenPath[pname]))) do
plan.contradictions[#plan.contradictions + 1] = c
end
if not installed[pname] then
local rt = pkg.runtimeRefusal(pm)
if rt then contradiction("runtime", pname, rt) end
end
end
end
return plan
end
--! Dependencies used to be looked for in `repoDir` ONLY. A package on one
--! floppy that needed a library on another could not be installed, even
--! with both disks in and `pkg.findInRepos` finding the library, and
--! installByName's own comment claimed the opposite. (federated repos
--! slice 1, finding 1; test_pkg_cross_source.lua)
function pkg.installWithDeps(repoDir, targetName, opts)
opts = opts or {}
local g, gErr = adminGate(opts)
if not g then return false, gErr end
local plan, planErr = pkg.plan(repoDir, targetName, opts)
if not plan then return false, planErr end
if #plan.contradictions > 0 then
local why = pkg.describeContradictions(plan.contradictions)
if not opts.force then
return false, "refusing to install '" .. targetName .. "': " .. why
end
if log then log.warn("pkg", "Installing '" .. targetName .. "' past contradictions (force): " .. why) end
end
local installedList, skippedList = {}, {}
for _, name in ipairs(plan.order) do
if installed[name] then
skippedList[#skippedList + 1] = name
else
local pkgSrc = plan.dirs[name] or fs.join(fs.normalize(repoDir), name)
local perPkgKey = opts.licenseKey
if opts.licenseKeys and opts.licenseKeys[name] then
perPkgKey = opts.licenseKeys[name]
elseif name ~= targetName then
perPkgKey = nil
end
local ok, err = pkg.install(pkgSrc, { licenseKey = perPkgKey, session = opts.session,
allowUnverified = opts.allowUnverified, allowUnsigned = opts.allowUnsigned,
force = opts.force, expectKey = plan.expectKey[name] })
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
pkg.forgetModules(m.files)
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
name = m.name,
version = m.version,
description = m.description,
category = (type(m.category) == "string" and m.category ~= "")
and m.category or "misc",
author = m.author,
kind = m.kind,
source = source,
dir = pkgDir,
requires = m.requires,
recommends = m.recommends,
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
local function resolveTarget(targetName, extraRoots)
if type(targetName) == "string" and targetName:find("/") then
local cand = fs.normalize(targetName:gsub("/$", ""))
local base = cand:match("[^/]+$")
if base and fs.exists(cand) and fs.isDirectory(cand) then
local m = loadAnyManifest(cand)
if m and m.name == base then
local root = cand:match("^(.*)/[^/]+$"); if root == "" then root = "/" end
return root, base
end
return nil, "not a package directory (or name mismatch): " .. targetName
end
return nil, "package not found in any repo: " .. targetName
end
local pkgDir, root = pkg.findInRepos(targetName, extraRoots)
if not pkgDir then
return nil, "package not found in any repo: " .. tostring(targetName)
end
return root, targetName
end
--! `pkg install --dry-run` used to answer with the names it was given and
--! nothing else, so a version or publisher contradiction -- the thing a
--! dry run is for -- was found by the real install, as a refusal. Same
--! resolver as installByName, so the dry run and the install cannot
--! disagree about where a package comes from. (test_pkg_flags.lua)
function pkg.planByName(targetName, opts)
opts = opts or {}
local root, name = resolveTarget(targetName, opts.extraRoots)
if not root then return nil, name end
local plan, err = pkg.plan(root, name, { extraRoots = opts.extraRoots })
if not plan then return nil, err end
plan.target = name
return plan
end
function pkg.installByName(targetName, opts)
opts = opts or {}
local g, gErr = adminGate(opts)
if not g then return false, gErr end
local root, name = resolveTarget(targetName, opts.extraRoots)
if not root then return false, name end
targetName = name
return pkg.installWithDeps(root, targetName, {
licenseKey = opts.licenseKey,
licenseKeys = opts.licenseKeys,
session = opts.session,
allowUnverified = opts.allowUnverified,
allowUnsigned = opts.allowUnsigned,
extraRoots = opts.extraRoots,
force = opts.force,
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
--! (remoteMod is forward-declared above validRepoHint: pkg.install
--! calls it too, and that is earlier still.)
--! `opts.includeRemote` also lists what the CONFIGURED REPOS advertise,
--! not just what is on a disk right now.
--!
--! Without it `pkg search` answered "no packages available" on a machine
--! with a working repo and an internet card, because it only ever looked
--! at local roots -- so the operator had to already know a package's name
--! to fetch it, which is the opposite of searching.
--!
--! Remote entries are marked `remote = true` and carry `repo`; they have
--! no `root`, because they are not anywhere yet. Callers that INSTALL
--! must branch on that: a remote entry needs pkg.installRemote (fetch,
--! verify, then the ordinary local install), not installByName.
--!
--! A local copy always wins the dedup. If a package is already on a disk
--! there is no reason to make the operator wait on the network for it.
--!
--! No internet card, or no repos configured, means the remote pass
--! contributes nothing and says nothing: pkgremote.index returns an
--! error, search logs it and skips. The listing is simply shorter, which
--! is the correct behaviour for a machine that cannot reach a network --
--! not an error, and not an empty screen where a list should be.
function pkg.listAllAvailable(opts)
opts = opts or {}
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
if opts.includeRemote then
for _, e in ipairs(pkg.listRemoteAvailable(opts)) do
if not seen[e.name] then
seen[e.name] = true
out[#out + 1] = e
end
end
end
return out
end
function pkg.listRemoteAvailable(opts)
local m = remoteMod()
if not m or type(m.search) ~= "function" then return {} end
local okS, list = pcall(m.search, opts or {})
if not okS or type(list) ~= "table" then return {} end
local out = {}
for _, e in ipairs(list) do
if type(e) == "table" and type(e.name) == "string" then
out[#out + 1] = {
name = e.name,
version = e.version,
description = e.description,
category = e.category or "remote",
repo = e.repo,
remote = true,
}
end
end
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
--! ENUMERATE FIRST, then ask. The loop used to prompt as it walked, so
--! the callback could not know how many questions were coming -- and a
--! UI cannot show progress it has not been told about. An operator
--! being asked a fifth yes/no with no idea whether it is the last one
--! gives up and starts pressing whatever ends it soonest, which is the
--! opposite of what a confirmation is for.
--!
--! Two passes over listRepo would be wasteful, so the candidates are
--! collected once and reused.
local candidates = {}
for _, mountPath in ipairs(mountedRepoRoots()) do
for _, entry in ipairs(pkg.listRepo(mountPath)) do
candidates[#candidates + 1] =
{ name = entry.name, dir = entry.dir, mount = mountPath }
end
end
--! The callback signature GREW rather than changed: (name, dir) still
--! mean what they did, and index/total are extra trailing arguments an
--! older callback simply ignores.
local total = #candidates
for i, c in ipairs(candidates) do
if confirm(c.name, c.dir, i, total) then
local ok, err = pkg.installByName(c.name,
{ extraRoots = { c.mount }, session = opts.session,
allowUnverified = opts.allowUnverified, allowUnsigned = opts.allowUnsigned,
force = opts.force })
if ok then installed_pkgs[#installed_pkgs + 1] = c.name
else skipped_pkgs[#skipped_pkgs + 1] = c.name .. " (" .. tostring(err) .. ")" end
else
skipped_pkgs[#skipped_pkgs + 1] = c.name .. " (declined)"
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
local data, readErr = fs.readFile(target)
if not data then
problems[#problems + 1] = name .. (fs.exists(target)
and (": cannot read installed file " .. target .. ": " .. tostring(readErr or "read failed"))
or (": missing installed file " .. target))
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
pkg.DEFAULT_REPO_ROOTS = DEFAULT_REPO_ROOTS
pkg._loadAnyManifest = loadAnyManifest
function remoteMod()
local ok, m = pcall(require, "kernel.pkgremote")
if not ok or type(m) ~= "table" then return nil, "remote package support unavailable" end
if m.init then pcall(m.init, { log = log, validRepoHint = validRepoHint }) end
return m
end
function pkg.knownRepos()
local m = remoteMod()
if not m or not m.known then return {} end
return m.known()
end
function pkg.forgetRepo(which, opts)
local g, gErr = adminGate(opts)
if not g then return false, gErr end
local m, mErr = remoteMod()
if not m then return false, mErr end
return m.forget(which)
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
function pkg.discoveredPolicy()
local ps = withSign(); if not ps or not ps.discoveredPolicy then return "off" end
return ps.discoveredPolicy()
end
function pkg.trustDiscovered(v, opts)
local g, gErr = adminGate(opts); if not g then return false, gErr end
local ps, e = withSign(); if not ps then return false, e end
return ps.setDiscoveredPolicy(v)
end
function pkg.checkSignature(srcDir)
if type(srcDir) ~= "string" or srcDir == "" then return nil, "invalid directory" end
local ps, e = withSign(); if not ps then return nil, e end
local m, source, manifestPath, bytes = loadAnyManifest(fs.normalize(srcDir))
if not m then return nil, "no manifest in " .. srcDir .. ": " .. tostring(source) end
return ps.verifyManifest(manifestPath, bytes), m
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
--! `pkg fetch` installs what a package REQUIRES, too (the first part of
--! slice 2 in docs/FEDERATED-REPOS.md; it used to install the package with
--! its requirements unmet). Dependencies come only from the CONFIGURED
--! repos -- the admin's allowlist, the design's floor for anything
--! unsigned -- and each goes through the same door a hand-typed fetch
--! does: same hashes, same signature policy, same service gate, and the
--! --allow-* flags the operator gave for this fetch. The whole set is
--! staged and every requirement resolved BEFORE anything is installed, so
--! a dependency no repo has refuses the fetch instead of leaving half of
--! it on disk. Installed and satisfying: left alone. Installed but too
--! old, or a repo copy that does not meet the constraint: refused, with
--! the fix (re-choosing a shared copy is slice 3). Optional requirements
--! are not fetched. Bounded in depth and count; a cycle is not followed
--! twice. (test_pkgremote_deps.lua)
local MAX_FETCH_DEPTH, MAX_FETCH_PACKAGES = 8, 16
local function depRefusal(msg)
return (tostring(msg):gsub("%s*%[E%-%d%d%d ERR_[%w_]+%]", "")) .. "  [E-603 ERR_PKG_DEPENDENCY]"
end
local function requirementParts(req)
if type(req) == "table" then return req.name, req.version, req.optional == true end
if type(req) == "string" then
local n, c = req:match("^(%S+)%s+(.+)$")
if n then return n, c, false end
return req, nil, false
end
end
function pkg.installRemote(name, opts)
opts = opts or {}
local g, gErr = adminGate(opts)
if not g then return false, gErr end
local m, mErr = remoteMod()
if not m then return false, mErr end
local function with(extra)
local o = {}
for k, v in pairs(opts) do o[k] = v end
for k, v in pairs(extra) do o[k] = v end
return o
end
local policy = pkg.discoveredPolicy()
--! #SEC THE FLOOR, for a package found only in a repo nobody configured,
--! checked on the staged bytes before anything installs: a key trusted
--! here installs; an unknown key only under `tofu`, when the admin names
--! the publisher there and then (that is pkg trust add), and never for a
--! service or driver; unsigned or invalid never, whatever --allow-* says.
--! pkg.install then verifies again, on the bytes IT reads.
local TAG = "  [E-606 ERR_PKG_UNTRUSTED_SOURCE]"
local function floor(n, man, mpath, mbytes, url, by)
local ps = withSign()
local where = "'" .. n .. "' is only in an unconfigured repo ("
.. tostring(url) .. ")"
if not ps then return false, where .. ", and signatures cannot be checked here" .. TAG end
local v = ps.verifyManifest(mpath, mbytes)
if v.state == "trusted" then return true end
if v.state == "invalid" then
return false, where .. ", and its signature does not verify (" .. tostring(v.reason) .. ")" .. TAG
end
if v.state ~= "unknown" then
return false, where .. ", and it is unsigned. An unsigned package installs only from a "
.. "repo an admin added (pkg repo add)" .. TAG
end
local add = "pkg trust add <name> " .. tostring(v.key)
if man.kind == "service" or man.kind == "driver" then
return false, where .. ". It is a " .. man.kind .. ", which runs outside the sandbox, and "
.. "its key (" .. tostring(v.fingerprint) .. ") is not trusted here: trust it first, "
.. "with  " .. add .. TAG
end
if policy ~= "tofu" or type(opts.confirmKey) ~= "function" then
return false, where .. ", and its key (" .. tostring(v.fingerprint) .. ") is not trusted "
.. "here" .. (policy ~= "tofu" and (" (pkg trust discovered is " .. policy .. ")") or "")
.. ". To trust it:  " .. add .. TAG
end
local label = opts.confirmKey({ name = n, repo = url, by = by, kind = man.kind,
key = v.key, fingerprint = v.fingerprint, signer = v.signer })
if type(label) ~= "string" or label == "" then
return false, "not installed: the key of '" .. n .. "' (" .. tostring(v.fingerprint)
.. ") was not trusted" .. TAG
end
local okT, tErr = pkg.trustAdd(label, v.key, opts)
if not okT then
return false, "could not trust the key of '" .. n .. "': " .. tostring(tErr) .. TAG
end
if log then
log.info("pkg", "Trusted key " .. tostring(v.fingerprint) .. " as '" .. label
.. "' (first use, for '" .. n .. "' from " .. tostring(url) .. ")")
end
return true
end
local staged, order, seen = {}, {}, {}
local function cleanupAll()
for _, s in ipairs(staged) do m.cleanup(s.dir) end
end
local function stage(n, depth, wanted, by, hints, pin)
if seen[n] then return true end
local who = by and ("dependency '" .. tostring(n) .. "' of '" .. by .. "': ") or ""
if depth > MAX_FETCH_DEPTH then
return false, depRefusal(who .. "dependencies nest deeper than " .. MAX_FETCH_DEPTH)
end
if #staged >= MAX_FETCH_PACKAGES then
return false, depRefusal("the fetch would bring in more than " .. MAX_FETCH_PACKAGES .. " packages")
end
seen[n] = true
local dir, err, meta = m.fetch(n, with({ hints = hints, discoveredPolicy = policy }))
if not dir then
if by then
return false, depRefusal(who .. tostring(err) .. " (if you have it on a disk, `pkg install "
.. tostring(n) .. "` it first)")
end
return false, err
end
local entry = { name = n, dir = dir, meta = meta, expectKey = pin }
staged[#staged + 1] = entry
local man, _, mpath, mbytes = loadAnyManifest(dir)
if type(man) ~= "table" then return false, who .. "no readable manifest" end
if meta and meta.discovered then
local okF, fErr = floor(n, man, mpath, mbytes, meta.discovered, by)
if not okF then return false, by and depRefusal(who .. fErr) or fErr end
end
if wanted and not pkg.satisfiesConstraint(man.version or "0.0.0", wanted) then
return false, depRefusal(who .. "needs " .. wanted .. ", and the repo has "
.. tostring(man.version or "no version"))
end
for _, req in ipairs(type(man.requires) == "table" and man.requires or {}) do
local rn, rc, optional = requirementParts(req)
if rn and not optional then
local have = findProvider(rn)
if have then
if rc and not pkg.satisfiesConstraint(have.version or "0.0.0", rc) then
return false, depRefusal(("'%s' needs %s %s, and %s is installed -- `pkg upgrade %s` first"):format(
n, rn, rc, tostring(have.version or "?"), rn))
end
else
local rHints = type(req) == "table" and type(req.repos) == "table" and req.repos or nil
local rPin = type(req) == "table" and type(req.key) == "string" and req.key:lower() or nil
local ok, e = stage(rn, depth + 1, rc, n, rHints, rPin)
if not ok then return false, e end
end
end
end
order[#order + 1] = entry
return true
end
local okS, sErr = stage(name, 0)
if not okS then cleanupAll(); return false, sErr end
--! Each package -- the dependencies first -- reaches install through the
--! SAME door as a floppy. In particular the hash gate is unchanged: an
--! index that ships no hashes is unverified code, and installing it still
--! requires the operator to have said --allow-unverified. Remote
--! provenance is not a reason to relax that — it is the reason it exists.
--! A requirement's key pin goes to install as expectKey.
local done, meta = {}, nil
for _, s in ipairs(order) do
local ok, iErr = pkg.install(s.dir, s.expectKey and with({ expectKey = s.expectKey }) or opts)
if not ok then
cleanupAll()
local msg = (s.name ~= name and ("dependency '" .. s.name .. "': ") or "") .. tostring(iErr)
.. (#done > 0 and (" (installed before it stopped: " .. table.concat(done, ", ") .. ")") or "")
return false, s.name ~= name and depRefusal(msg) or msg
end
if log then
log.info("pkg", "Installed '" .. tostring(s.name) .. "' from "
.. (s.meta and s.meta.discovered and (tostring(s.meta.discovered) .. ", a repo nobody configured")
or ("repo '" .. tostring(s.meta and s.meta.repo) .. "'"))
.. (s.name ~= name and (" as a dependency of '" .. name .. "'") or ""))
end
if s.name == name then meta = s.meta else done[#done + 1] = s.name end
end
cleanupAll()
meta = meta or {}
meta.dependencies = done
return true, meta
end
end
