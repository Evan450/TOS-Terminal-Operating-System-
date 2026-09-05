#!/usr/bin/env lua
-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Optional Utilities — disk assembler                   ║
-- ║                                                            ║
-- ║  Gathers the TOS-Extras add-ons into one or more pkg       ║
-- ║  REPOs laid out the way kernel.pkg.install expects:         ║
-- ║                                                            ║
-- ║    <out>/README.txt                    (what to run)        ║
-- ║    <out>/<pkgname>/package.lua         (manifest)           ║
-- ║    <out>/<pkgname>/<install target>    (each file, mirrored ║
-- ║                                         at its real path)   ║
-- ║                                                            ║
-- ║  Packages are AUTO-DISCOVERED: any directory under          ║
-- ║  modules/ or cluster/ that contains a package.lua is        ║
-- ║  assembled, no builder edit needed. Each manifest files[]   ║
-- ║  target is resolved in order:                               ║
-- ║    1. mirror — <srcdir><target> (source laid out at its     ║
-- ║       install path, e.g. modules/mouse/usr/lib/mouse.lua)   ║
-- ║    2. flat   — <srcdir>/<basename> (single-file modules     ║
-- ║       keep init.lua at their root, e.g. modules/tetris)     ║
-- ║    3. legacy — explicit map below (master-skeleton's        ║
-- ║       lib/cluster/* layout predates both conventions)       ║
-- ║                                                            ║
-- ║  MULTI-FLOPPY SPLIT: when the assembled set exceeds         ║
-- ║  --limit (default 512K, the OC default floppy), packages    ║
-- ║  are bin-packed into <out>/disk1..N — each disk gets its    ║
-- ║  own set manifest, and packages connected by non-optional   ║
-- ║  requires[] are kept on the SAME disk so kernel.pkg's       ║
-- ║  dependency resolver always finds deps in the repo it is    ║
-- ║  installing from. Size model: file bytes + --overhead per   ║
-- ║  file (default 512, approximating OC's per-file fileCost).  ║
-- ║                                                            ║
-- ║  Runs anywhere: dev box with LuaFileSystem, plain Lua       ║
-- ║  (shell fallbacks), or under OpenOS.                        ║
-- ║                                                            ║
-- ║  Usage:                                                     ║
-- ║    lua build/build-disk.lua [<extras-root>] [<out>]         ║
-- ║        [--install <dir>] [--limit <n>[K|M]|0]               ║
-- ║        [--overhead <bytes>]                                 ║
-- ║    defaults: extras-root = ".." of this script              ║
-- ║              out = <extras-root>/dist/optional-utilities    ║
-- ║              limit = 512K, overhead = 512                   ║
-- ║    --install copies a SINGLE-disk build into <dir> — point  ║
-- ║    it at an OpenComputers floppy folder                     ║
-- ║    (saves/<world>/opencomputers/<address>/) to "burn" it.   ║
-- ║                                                            ║
-- ║  Wrappers: build-disk.cmd (Windows) / build-disk.sh.        ║
-- ╚══════════════════════════════════════════════════════════╝

-- ── Portable fs (LuaFileSystem, OpenOS, or plain-Lua shell fallbacks) ──
local lfs_ok, lfs = pcall(require, "lfs")
local fs_ok, ocfs = pcall(require, "filesystem")
local WINDOWS = package.config:sub(1, 1) == "\\"

local function exists(path)
  if fs_ok then return ocfs.exists(path) end
  if lfs_ok then return lfs.attributes(path) ~= nil end
  local h = io.open(path, "rb")
  if h then h:close(); return true end
  -- Plain Lua: io.open CANNOT see a directory (opening one fails), so the
  -- check above reported every existing directory as missing. mkdirp then
  -- shelled out a `mkdir` for every ancestor of an absolute output path —
  -- including "C:" — and each one printed an error. Whether that noise was
  -- visible depended purely on which shell launched the build (cmd's
  -- `>nul 2>nul` swallowed it; PowerShell invoking the .cmd did not),
  -- which is exactly the shell-dependent trap CLAUDE.md warns about.
  -- os.rename(p, p) is the portable existence test that works for
  -- directories as well as files.
  return os.rename(path, path) == true
end
local function mkdir1(path)
  if fs_ok then return ocfs.makeDirectory(path) end
  if lfs_ok then return lfs.mkdir(path) end
  -- Plain Lua: shell out. cmd's mkdir creates parents (extensions on);
  -- POSIX needs -p. Failures (already exists) are silenced — writeAll
  -- surfaces any real problem.
  if WINDOWS then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" >nul 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
  end
  return true
end
--- Sorted list of subdirectory names directly under `path` ({} if none).
local function listSubdirs(path)
  local out = {}
  if fs_ok then
    for e in ocfs.list(path) do
      if e:sub(-1) == "/" then out[#out + 1] = (e:gsub("/$", "")) end
    end
  elseif lfs_ok then
    if lfs.attributes(path, "mode") == "directory" then
      for e in lfs.dir(path) do
        if e ~= "." and e ~= ".."
           and lfs.attributes(path .. "/" .. e, "mode") == "directory" then
          out[#out + 1] = e
        end
      end
    end
  else
    local cmd
    if WINDOWS then
      cmd = 'dir /b /ad "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
      cmd = 'find "' .. path .. '" -maxdepth 1 -mindepth 1 -type d 2>/dev/null'
    end
    local p = io.popen(cmd)
    if p then
      for line in p:lines() do
        local name = line:match("[^/\\]+%s*$")
        if name then out[#out + 1] = (name:gsub("%s+$", "")) end
      end
      p:close()
    end
  end
  table.sort(out)
  return out
end
--- Remove a directory tree. The output dirs are build artifacts; a
--- stale file from a previous layout (e.g. a renamed install path)
--- must never linger on the disk wasting floppy space.
local function rmTree(path)
  if not exists(path) then return end
  if lfs_ok then
    -- With LuaFileSystem present the whole builder becomes
    -- SUBPROCESS-FREE. That matters beyond tidiness: every shell-out
    -- inherits the quoting rules of whichever shell launched the build
    -- (cmd / PowerShell / Git Bash), which is the documented source of
    -- this repo's build-noise gremlins. rmTree was the last helper still
    -- shelling out even when lfs was available.
    local function walk(p)
      for e in lfs.dir(p) do
        if e ~= "." and e ~= ".." then
          local child = p .. "/" .. e
          if lfs.attributes(child, "mode") == "directory" then walk(child)
          else os.remove(child) end
        end
      end
      lfs.rmdir(p)
    end
    local ok = pcall(walk, path)
    if ok and not exists(path) then return end
    -- Fall through to the shell path if lfs couldn't finish (a locked
    -- file, a permission quirk) rather than leaving stale output.
  end
  if fs_ok then
    -- OpenOS: recursive remove via list+remove.
    local function walk(p)
      for e in ocfs.list(p) do
        local child = p .. "/" .. e:gsub("/$", "")
        if e:sub(-1) == "/" then walk(child) end
        ocfs.remove(child)
      end
    end
    walk(path)
    ocfs.remove(path)
  elseif WINDOWS then
    os.execute('rmdir /s /q "' .. path:gsub("/", "\\") .. '" >nul 2>nul')
  else
    os.execute('rm -rf "' .. path .. '" 2>/dev/null')
  end
end
local function readAll(path)
  local h = io.open(path, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function writeAll(path, content)
  local h = io.open(path, "wb"); if not h then return false, "open failed: " .. path end
  h:write(content); h:close(); return true
end

--! NORMALISE LINE ENDINGS BEFORE HASHING OR WRITING. This is not
--! cosmetic; it is what makes `pkg fetch` work at all.
--!
--! The source tree is checked out on Windows with core.autocrlf=true, so
--! 64 of its 87 Lua files have CRLF in the working copy. build-disk reads
--! and writes bytes verbatim, so those CRLFs used to land in the built
--! pack AND in the SHA-256 recorded for each file. Publishing then put
--! the pack through git, which normalises text to LF in the stored blob
--! -- so raw.githubusercontent.com served LF bytes while the shipped
--! manifest carried a hash computed over CRLF bytes. Every one of the 39
--! affected files failed pkg's hash check on arrival, and the failure was
--! invisible from here: on a physical floppy the manifest and the files
--! travel together unnormalised, so the disk path verified fine.
--!
--! Normalising at the single point where package content is read means
--! the bytes we hash, the bytes we write, and the bytes git stores are
--! the same bytes. Matches what strip.lua already does for the release
--! build. Binary content is left alone (a NUL byte means it is not text).
local function normalizeEOL(data)
  if not data or data:find("\0", 1, true) then return data end
  return (data:gsub("\r\n", "\n"):gsub("\r", "\n"))
end
-- Recursive mkdir -p.
local function mkdirp(path)
  local accum = ""
  for seg in path:gmatch("[^/\\]+") do
    accum = (accum == "") and seg or (accum .. "/" .. seg)
    -- Preserve a leading slash on absolute POSIX paths.
    if path:sub(1, 1) == "/" and accum:sub(1, 1) ~= "/" then accum = "/" .. accum end
    if not exists(accum) then mkdir1(accum) end
  end
end
-- Both helpers accept / and \ so wrapper-supplied Windows paths work.
local function dirname(p) return (p:gsub("[/\\][^/\\]*$", "")) end
local function basename(p) return p:match("[^/\\]+$") end

-- ── Args ───────────────────────────────────────────────────────────
local scriptPath = (arg and arg[0]) or "build/build-disk.lua"
local scriptDir  = dirname(scriptPath)

local function parseLimit(s)
  if s == "0" or s == "none" or s == "unlimited" then return math.huge end
  local n, suffix = s:match("^(%d+)([KkMm]?)$")
  if not n then return nil end
  n = tonumber(n)
  if suffix:lower() == "k" then n = n * 1024
  elseif suffix:lower() == "m" then n = n * 1024 * 1024 end
  return n
end

local positional, installDir = {}, nil
local wantSign = false
local LIMIT    = 512 * 1024   -- OC default floppy capacity
local OVERHEAD = 512          -- ~OC per-file fileCost
do
  local i = 1
  while arg and arg[i] do
    if arg[i] == "--install" then
      installDir = arg[i + 1]
      if not installDir then
        io.write("error: --install needs a target directory\n"); os.exit(1)
      end
      i = i + 2
    elseif arg[i] == "--limit" then
      local v = parseLimit(arg[i + 1] or "")
      if not v then
        io.write("error: --limit wants <n>[K|M] or 0 for unlimited\n"); os.exit(1)
      end
      LIMIT = v
      i = i + 2
    elseif arg[i] == "--overhead" then
      OVERHEAD = tonumber(arg[i + 1] or "")
      if not OVERHEAD then
        io.write("error: --overhead wants a byte count\n"); os.exit(1)
      end
      i = i + 2
    elseif arg[i] == "--sign" then
      wantSign = true
      i = i + 1
    else
      positional[#positional + 1] = arg[i]
      i = i + 1
    end
  end
end
local extrasRoot = positional[1] or (scriptDir .. "/..")
local outDir     = positional[2] or (extrasRoot .. "/dist/optional-utilities")
extrasRoot = extrasRoot:gsub("[/\\]+$", "")
outDir     = outDir:gsub("[/\\]+$", "")
if installDir then installDir = installDir:gsub("[/\\]+$", "") end

-- ── Package integrity: generate SHA-256 hashes into each dist manifest ──
-- pkg.install (in TOS-Dev) REJECTS packages with no/partial file hashes
-- unless --allow-unverified. So a shipped Optional Utilities disk must carry
-- hashes or nothing on it would install. We compute them here from the same
-- pure SHA-256 the kernel uses (kernel.sha256), loaded from the sibling
-- TOS-Dev tree. If it can't be found, WARN loudly and ship unhashed (the
-- operator would then need --allow-unverified) rather than hard-failing.
local sha256
do
  --! Two tree shapes, both legitimate. In the monorepo TOS-Extras is a
  --! SIBLING of TOS-Dev, so the kernel is at ../TOS-Dev/tos/. On the
  --! published dev branch TOS-Extras sits INSIDE the repo root, so it is
  --! at ../tos/. Missing the second one is not cosmetic: without sha256
  --! this builds packages with no hashes at all, which is precisely the
  --! state a package developer must not be silently dropped into --
  --! pkg.install refuses an unverified package unless the operator
  --! passes --allow-unverified, so their first build would look broken.
  for _, cand in ipairs({
      extrasRoot .. "/../TOS-Dev/tos/kernel/sha256.lua",
      extrasRoot .. "/../tos/kernel/sha256.lua",
      scriptDir  .. "/../../TOS-Dev/tos/kernel/sha256.lua",
      scriptDir  .. "/../../tos/kernel/sha256.lua",
      "TOS-Dev/tos/kernel/sha256.lua",
      "../tos/kernel/sha256.lua" }) do
    local chunk = loadfile(cand)
    if chunk then local ok, m = pcall(chunk); if ok then sha256 = m break end end
  end
  if not sha256 then
    io.write("WARNING: kernel.sha256 not found — dist packages will ship "
      .. "UNHASHED (installs need --allow-unverified)\n")
  end
end

-- ── Publisher signing (optional) ────────────────────────────────────
-- `--sign` signs each emitted manifest with an Ed25519 key derived from
-- a passphrase, writing package.sig beside package.lua.
--
-- SIGNING HAPPENS HERE AND NOT ON THE SOURCE TREE, and the ordering is
-- not negotiable: this builder REWRITES each manifest to inject the file
-- hashes, so a signature made over the source manifest would not match
-- what lands on the floppy. The chain is signature → manifest → hashes →
-- files, and the hashes have to be final before the signature is taken.
--
-- The passphrase comes from the ENVIRONMENT (TOS_SIGNING_PASSPHRASE) and
-- never from argv. A command line ends up in shell history, which is a
-- file, which is the one place a signing key must never be.
local signer, signSeed
--! Both tree shapes, for the same reason as the sha256 loader above: a
--! SIBLING TOS-Dev in the monorepo, and an INSIDE-the-root layout on the
--! published dev branch. Getting this wrong breaks `--sign` outright --
--! setupSigning hard-exits when sha512/ed25519/pkgsign are missing, so a
--! contributor's first attempt to sign a package would die on a path
--! problem rather than anything to do with their key.
local function loadKernelModule(rel)
  for _, cand in ipairs({
      extrasRoot .. "/../TOS-Dev/tos/kernel/" .. rel,
      extrasRoot .. "/../tos/kernel/" .. rel,
      scriptDir  .. "/../../TOS-Dev/tos/kernel/" .. rel,
      scriptDir  .. "/../../tos/kernel/" .. rel,
      "TOS-Dev/tos/kernel/" .. rel,
      "../tos/kernel/" .. rel }) do
    local chunk = loadfile(cand)
    if chunk then local ok, m = pcall(chunk); if ok then return m end end
  end
end

local function setupSigning()
  local pass = os.getenv("TOS_SIGNING_PASSPHRASE")
  if not pass or pass == "" then
    io.write("error: --sign needs the TOS_SIGNING_PASSPHRASE environment variable.\n")
    io.write("       It is deliberately not a command-line flag: argv lands in\n")
    io.write("       shell history, and this passphrase IS the private key.\n")
    os.exit(1)
  end
  local sha512 = loadKernelModule("sha512.lua")
  if not sha512 then io.write("error: kernel/sha512.lua not found.\n"); os.exit(1) end
  package.loaded["kernel.sha512"] = sha512
  package.loaded["kernel.sha256"] = sha256
  local ed = loadKernelModule("ed25519.lua")
  if not ed then io.write("error: kernel/ed25519.lua not found.\n"); os.exit(1) end
  package.loaded["kernel.ed25519"] = ed
  local serializeMod = loadKernelModule("serialize.lua")
  if not serializeMod then io.write("error: kernel/serialize.lua not found.\n"); os.exit(1) end
  local ps = loadKernelModule("pkgsign.lua")
  if not ps then io.write("error: kernel/pkgsign.lua not found.\n"); os.exit(1) end
  package.loaded["kernel.pkgsign"] = ps
  -- The signature format is defined in exactly one place. This builder
  -- drives kernel/pkgsign.lua over a filesystem shim rather than
  -- reimplementing the record, so a disk built here and a package signed
  -- on-box with `pkg sign` cannot disagree about what a signature is.
  local shim = {
    exists    = function(p) return exists(p) end,
    readFile  = function(p) return readAll(p) end,
    writeFile = function(p, d) return writeAll(p, d) end,
  }
  ps.init({ fs = shim, serialize = serializeMod })
  local seed, sErr = ps.seedFromPassphrase(pass)
  if not seed then io.write("error: " .. tostring(sErr) .. "\n"); os.exit(1) end
  signer, signSeed = ps, seed
  local pub = ed.publickey(seed)
  local pubHex = ps.binToHex(pub)
  io.write("Signing as " .. pubHex .. "\n")
  io.write("           " .. ps.fingerprint(pubHex) .. "\n")
  io.write("Recipients trust this build with:  pkg trust add <name> " .. pubHex .. "\n\n")
end

if wantSign then setupSigning() end

-- Insert a `hashes = { [target]=digest, ... }` block right after the
-- manifest's opening `return {`. Function-form replacement so digests/paths
-- can't be misread as gsub `%` escapes. Deterministic key order.
local function injectHashes(src, hashes)
  if not hashes or not next(hashes) then return src end
  local keys = {}
  for k in pairs(hashes) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = { "  -- Generated by build-disk.lua (package integrity)", "  hashes = {" }
  for _, k in ipairs(keys) do
    lines[#lines + 1] = string.format("    [%q] = %q,", k, hashes[k])
  end
  lines[#lines + 1] = "  },"
  local block = table.concat(lines, "\n")
  local out, n = src:gsub("(return%s*{)", function(m) return m .. "\n" .. block end, 1)
  return (n > 0) and out or src
end

-- ── Discovery configuration ────────────────────────────────────────
-- Roots scanned for <root>/<dir>/package.lua. (rbmk/ holds only a
-- Plan.md today; listing it here means its packages ship the moment
-- they grow manifests.)
local DISCOVERY_ROOTS = { "modules", "cluster", "rbmk" }

-- Packages excluded from the disk, keyed by MANIFEST name, with the
-- reason printed at build time (so an exclusion is a visible decision,
-- not a silent gap).
--
-- The rule is the version, not an opinion: a package below 1.0.0 is not
-- finished, and shipping it on a public pack means an operator ticks it
-- in the picker and gets a skeleton. Both entries below are 0.1.0 and
-- both still have an open spec draft beside them (cluster/
-- storage-spec-draft.md, rbmk/Plan.md). Delete the entry when the
-- package reaches 1.0.0 — nothing else needs changing, the assembler
-- discovers it again on the next build.
local SKIP = {
  ["cluster-storage"] = "0.1.0 — storage-spec-draft.md still open",
  ["rbmk-control"]    = "0.1.0 — component names in Plan.md still a guess",
}

-- Explicit target→source maps for layouts that predate the mirror/flat
-- conventions. Only entries the automatic resolution can NOT find are
-- needed; everything else in the same package resolves normally.
local LEGACY_SOURCES = {
  ["cluster-master"] = {  -- master-skeleton keeps libs under lib/cluster/
    ["/usr/lib/cluster/state.lua"]     = "cluster/master-skeleton/lib/cluster/state.lua",
    ["/usr/lib/cluster/scheduler.lua"] = "cluster/master-skeleton/lib/cluster/scheduler.lua",
    ["/usr/lib/cluster/jobs.lua"]      = "cluster/master-skeleton/lib/cluster/jobs.lua",
    ["/usr/lib/cluster/net.lua"]       = "cluster/master-skeleton/lib/cluster/net.lua",
    ["/usr/lib/cluster/api.lua"]       = "cluster/master-skeleton/lib/cluster/api.lua",
    ["/usr/lib/cluster/pair.lua"]      = "cluster/master-skeleton/lib/cluster/pair.lua",
  },
}

-- ── Manifest loading ───────────────────────────────────────────────
local function loadManifest(path)
  local src = readAll(path)
  if not src then return nil, "cannot read " .. path end
  -- Manifests are pure data: `return { ... }`. Loading them is safe here
  -- (this is a dev/deploy build tool, not the kernel's untrusted path).
  local chunk, err = load(src, "=" .. path, "t", {})
  if not chunk then return nil, "parse error: " .. tostring(err) end
  local ok, m = pcall(chunk)
  if not ok then return nil, "eval error: " .. tostring(m) end
  if type(m) ~= "table" or type(m.name) ~= "string" then
    return nil, "manifest did not return a named package table"
  end
  return m
end

-- Resolve an install target to its source path (relative to extrasRoot).
local function resolveTarget(srcDirRel, name, target)
  local mirror = srcDirRel .. target
  if exists(extrasRoot .. "/" .. mirror) then return mirror end
  local flat = srcDirRel .. "/" .. basename(target)
  if exists(extrasRoot .. "/" .. flat) then return flat end
  local legacy = LEGACY_SOURCES[name]
  if legacy and legacy[target] then return legacy[target] end
  return nil
end

-- ── Phase 1: discover + collect ────────────────────────────────────
local problems = {}
local entries = {}   -- { name, srcDirRel, manifestSrc, manifest,
                     --   files = { {target=, data=} }, size }

for _, root in ipairs(DISCOVERY_ROOTS) do
  for _, sub in ipairs(listSubdirs(extrasRoot .. "/" .. root)) do
    local srcDirRel = root .. "/" .. sub
    local mpath = extrasRoot .. "/" .. srcDirRel .. "/package.lua"
    if exists(mpath) then
      local m, err = loadManifest(mpath)
      if not m then
        problems[#problems + 1] = srcDirRel .. ": " .. tostring(err)
      elseif SKIP[m.name] then
        io.write(string.format("  %-18s SKIPPED (%s)\n", m.name, SKIP[m.name]))
      else
        local manifestSrc = normalizeEOL(readAll(mpath))
        local e = { name = m.name, srcDirRel = srcDirRel, manifest = m,
                    manifestSrc = manifestSrc, files = {},
                    size = #manifestSrc + OVERHEAD }
        for _, target in ipairs(m.files or {}) do
          local srcRel = resolveTarget(srcDirRel, m.name, target)
          local data = srcRel and normalizeEOL(readAll(extrasRoot .. "/" .. srcRel))
          if not data then
            problems[#problems + 1] = m.name .. ": no source found for " .. target
              .. " (tried " .. srcDirRel .. target .. " and "
              .. srcDirRel .. "/" .. basename(target) .. ")"
          else
            e.files[#e.files + 1] = { target = target, data = data }
            e.size = e.size + #data + OVERHEAD
          end
        end
        entries[#entries + 1] = e
      end
    end
  end
end
table.sort(entries, function(a, b) return a.name < b.name end)

-- The disk no longer carries an installer. It never needed to: the picker's
-- first act is require("kernel.pkg"), so it can only run on a TOS machine —
-- which already has the picker in its base image (tos/shell/pkgpicker.lua,
-- reached by `pkg install`). Shipping a ~40 KB copy to a machine that has
-- one cost every disk 40 KB for nothing. A short README says what to run.
local README = table.concat({
  "TOS Optional Utilities",
  "",
  "Insert this disk on a TOS machine and run, as admin:",
  "",
  "    pkg install",
  "",
  "That opens the picker: tick what you want, press Enter.",
  "The set may span several disks -- the picker lists ALL of them",
  "and asks you to swap when it needs the next one.",
  "",
  "Non-interactive (scripts):",
  "    pkg install <name> [<name>...]",
  "    pkg install --all --yes",
  "",
}, "\n")
-- Every disk carries the set manifest and the README, so both are reserved
-- before packing or a disk can overflow by their size. The manifest is ~1
-- line-pair per package plus a small header; 320 bytes each is a deliberate
-- over-estimate (real entries run ~200-280), because guessing high costs a
-- little slack and guessing low costs a broken floppy.
local setManifestCost = 512 + (#entries * 320)
local installerCost = #README + OVERHEAD + setManifestCost

if #problems > 0 then
  io.write("\nPROBLEMS:\n")
  for _, p in ipairs(problems) do io.write("  - " .. p .. "\n") end
  os.exit(1)
end

-- ── Phase 2: dependency grouping ───────────────────────────────────
-- kernel.pkg resolves a package's deps from the repo it installs from,
-- so packages joined by a NON-OPTIONAL requires[] edge must share a
-- disk. Resolve dep names against both manifest names and provides[].
local providerOf = {}   -- dep-name -> entry
for _, e in ipairs(entries) do
  providerOf[e.name] = e
  for _, p in ipairs(e.manifest.provides or {}) do providerOf[p] = e end
end

local groupOf = {}      -- entry -> group table (array of entries)
for _, e in ipairs(entries) do groupOf[e] = { e } end
local function mergeGroups(a, b)
  if groupOf[a] == groupOf[b] then return end
  local ga, gb = groupOf[a], groupOf[b]
  for _, m in ipairs(gb) do
    ga[#ga + 1] = m
    groupOf[m] = ga
  end
end
for _, e in ipairs(entries) do
  for _, req in ipairs(e.manifest.requires or {}) do
    local depName, optional
    if type(req) == "table" then depName, optional = req.name, req.optional
    elseif type(req) == "string" then depName = req:match("^(%S+)") end
    local dep = depName and providerOf[depName]
    if dep and not optional then mergeGroups(e, dep) end
  end
end

local groups, seenGroup = {}, {}
-- raw member-array -> its wrapper. groupOf[] hands back the RAW array while
-- everything downstream works with the { members=, size= } wrapper; without
-- this map the soft-affinity pass below looks up wrappers by raw array,
-- gets nil for every one, and silently merges nothing.
local wrapperOf = {}
for _, e in ipairs(entries) do
  local g = groupOf[e]
  if not seenGroup[g] then
    seenGroup[g] = true
    table.sort(g, function(a, b) return a.name < b.name end)
    local size = 0
    for _, m in ipairs(g) do size = size + m.size end
    local w = { members = g, size = size }
    groups[#groups + 1] = w
    wrapperOf[g] = w
  end
end

-- ── Phase 2b: SOFT affinity from recommends[] ──────────────────────
-- `requires` is a hard edge — kernel.pkg resolves deps from the repo it
-- installs from, so a split group simply cannot install. `recommends` is a
-- soft edge, and splitting one is merely miserable: tape-authenticator
-- landed on disk2 while the `tape` package it recommends sat on disk1, so
-- an operator with one floppy got the keycard tool and no way to manage the
-- tapes it writes. That is worth avoiding, but never at the cost of a hard
-- group, so soft edges are handled as a SECOND tier: clusters of groups
-- that we TRY to keep together and report on when we can't.
local clusterOf = {}    -- group -> cluster (array of groups)
for _, g in ipairs(groups) do clusterOf[g] = { g } end
local function mergeClusters(a, b)
  if clusterOf[a] == clusterOf[b] then return end
  local ca, cb = clusterOf[a], clusterOf[b]
  for _, m in ipairs(cb) do
    ca[#ca + 1] = m
    clusterOf[m] = ca
  end
end
local softEdges = {}    -- { {from=name, to=name}, ... } for the report
for _, e in ipairs(entries) do
  for _, rec in ipairs(e.manifest.recommends or {}) do
    local dep = providerOf[rec]
    if dep and groupOf[dep] ~= groupOf[e] then
      softEdges[#softEdges + 1] = { from = e.name, to = dep.name }
      -- Cluster by WRAPPER (see wrapperOf above), not by the raw array.
      mergeClusters(wrapperOf[groupOf[e]], wrapperOf[groupOf[dep]])
    end
  end
end

local clusters, seenCluster = {}, {}
for _, g in ipairs(groups) do
  local c = clusterOf[g]
  if not seenCluster[c] then
    seenCluster[c] = true
    local size = 0
    for _, m in ipairs(c) do size = size + m.size end
    clusters[#clusters + 1] = { groups = c, size = size }
  end
end

-- ── Phase 3: pack groups into disks ────────────────────────────────
-- First-fit decreasing over HARD groups, but a soft cluster is offered to
-- the packer whole first: if the whole cluster fits somewhere, everything
-- it links stays together. When it doesn't fit, its groups fall back to
-- being packed individually — soft means best-effort, not a build failure.
table.sort(groups, function(a, b)
  if a.size ~= b.size then return a.size > b.size end
  return a.members[1].name < b.members[1].name
end)
table.sort(clusters, function(a, b)
  if a.size ~= b.size then return a.size > b.size end
  return a.groups[1].members[1].name < b.groups[1].members[1].name
end)

for _, g in ipairs(groups) do
  if g.size + installerCost > LIMIT then
    local names = {}
    for _, m in ipairs(g.members) do names[#names + 1] = m.name end
    io.write(string.format(
      "error: package group [%s] needs ~%d bytes — over the %d-byte disk limit.\n",
      table.concat(names, " + "), g.size + installerCost, LIMIT))
    io.write("       raise --limit (or 0 for unlimited) or slim the package.\n")
    os.exit(1)
  end
end

local disks = {}   -- { used=, groups={} }
local diskOfGroup = {}   -- group -> disk index, for the split report

--- Pick an existing disk for `size` bytes using `fits(disk, size, best)`,
--- which returns true when `disk` is a better candidate than `best`.
--- First-fit short-circuits on the first yes; worst-fit keeps looking for
--- the emptiest disk. Returns the index, or nil for "open a new one".
local function pick(size, fits)
  local bestIdx, best = nil, nil
  for i, d in ipairs(disks) do
    if fits(d, size, best) then bestIdx, best = i, d end
  end
  return bestIdx
end

local function placeGroup(g, fits)
  local i = pick(g.size, fits)
  if i then
    local d = disks[i]
    d.groups[#d.groups + 1] = g
    d.used = d.used + g.size
    diskOfGroup[g] = i
    return i
  end
  disks[#disks + 1] = { used = installerCost + g.size, groups = { g } }
  diskOfGroup[g] = #disks
  return #disks
end

--- Try to put a whole cluster on ONE disk. Returns the disk index, or nil
--- when nothing has room for all of it.
local function placeClusterWhole(c, fits)
  local i = pick(c.size, fits)
  if i then
    local d = disks[i]
    for _, g in ipairs(c.groups) do
      d.groups[#d.groups + 1] = g
      diskOfGroup[g] = i
    end
    d.used = d.used + c.size
    return i
  end
  -- A fresh disk, if the cluster fits on one at all.
  if c.size + installerCost <= LIMIT then
    disks[#disks + 1] = { used = installerCost + c.size, groups = {} }
    for _, g in ipairs(c.groups) do
      disks[#disks].groups[#disks[#disks].groups + 1] = g
      diskOfGroup[g] = #disks
    end
    return #disks
  end
end

local function packAll(fitPicker)
  disks = {}
  diskOfGroup = {}
  for _, c in ipairs(clusters) do
    if #c.groups == 1 then
      placeGroup(c.groups[1], fitPicker)
    elseif not placeClusterWhole(c, fitPicker) then
      -- Too big to keep together. Place its groups individually — largest
      -- first, so the packing stays decreasing — and let the report below
      -- name what got separated.
      local sorted = {}
      for _, g in ipairs(c.groups) do sorted[#sorted + 1] = g end
      table.sort(sorted, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        return a.members[1].name < b.members[1].name
      end)
      for _, g in ipairs(sorted) do placeGroup(g, fitPicker) end
    end
  end
  if #disks == 0 then disks[1] = { used = installerCost, groups = {} } end
  return #disks
end

-- ── Phase 3b: balance, once the disk COUNT is settled ──────────────
-- First-fit fills disk 1 to the brim before it opens disk 2, which is
-- correct for minimising the disk count and awful for living with the
-- result: the set that produced this note had disk 1 at 99.2% of a
-- 512K floppy with 3,930 bytes spare, while disk 2 sat half empty. The
-- next add-on of any size is then a BUILD ERROR rather than a split,
-- and the error names a package that did nothing wrong.
--
-- So: run first-fit to learn how many disks the set actually needs, then
-- re-pack into that same number using WORST fit — each group goes to the
-- disk with the most room left. Same disk count, headroom spread evenly.
-- If the re-pack somehow needs more disks than first-fit did (possible
-- with awkward cluster sizes), the first-fit layout is kept: fewer
-- floppies beats tidier ones.
-- Both pickers take (disk, size, bestSoFar) and answer "is this a better
-- candidate than bestSoFar?". First-fit says yes only while there is no
-- candidate yet, which is what makes it stop at the first disk that fits
-- without needing a break out of the scan.
local FIRST_FIT = function(d, size, best)
  return best == nil and d.used + size <= LIMIT
end
local WORST_FIT = function(d, size, best)
  if d.used + size > LIMIT then return false end
  return best == nil or d.used < best.used
end

local minDisks = packAll(FIRST_FIT)
local firstFitLayout = { disks = disks, diskOfGroup = diskOfGroup }
if minDisks > 1 then
  local balancedCount = packAll(WORST_FIT)
  if balancedCount > minDisks then
    disks, diskOfGroup = firstFitLayout.disks, firstFitLayout.diskOfGroup
  end
end

-- Which disk did each package land on? (Also feeds the set manifest.)
local diskOfPackage = {}
for di, d in ipairs(disks) do
  for _, g in ipairs(d.groups) do
    for _, m in ipairs(g.members) do diskOfPackage[m.name] = di end
  end
end

-- Report soft pairs we could NOT keep together. Silence here would be the
-- bad kind: the operator finds out by installing half a toolset.
local separated = {}
for _, edge in ipairs(softEdges) do
  local a, b = diskOfPackage[edge.from], diskOfPackage[edge.to]
  if a and b and a ~= b then
    separated[#separated + 1] = string.format("%s (disk%d) recommends %s (disk%d)",
      edge.from, a, edge.to, b)
  end
end

-- ── Phase 4: emit ──────────────────────────────────────────────────
rmTree(outDir)
mkdirp(outDir)

local written = {}   -- paths relative to outDir, for the --install copy
-- ── The SET manifest ───────────────────────────────────────────────
-- Every disk carries a description of the WHOLE set, not just itself. The
-- picker can only list what is mounted, so without this a one-floppy
-- machine shows half the catalogue and no hint that the rest exists — the
-- operator has to already know what they're missing. With it, the picker
-- lists everything, marks what is reachable right now, and knows which
-- disk to ask for.
--
-- Written as a plain `return { ... }` table: the picker parses it with the
-- kernel serializer, so it must contain data only.
local function quote(s) return string.format("%q", tostring(s or "")) end

local function setManifestSrc(diskCount)
  local out = {
    "-- Optional Utilities set manifest — generated by build-disk.lua.",
    "-- Lists the WHOLE set so the installer can show packages that live",
    "-- on a disk which is not currently inserted, and name the disk to",
    "-- ask for. Data only.",
    "return {",
    "  set = \"optional-utilities\",",
    string.format("  disks = %d,", diskCount),
    "  packages = {",
  }
  local names = {}
  for _, e in ipairs(entries) do names[#names + 1] = e.name end
  table.sort(names)
  for _, n in ipairs(names) do
    local e
    for _, x in ipairs(entries) do if x.name == n then e = x end end
    local m = e.manifest
    local reqs, recs = {}, {}
    for _, r in ipairs(m.requires or {}) do
      local rn = (type(r) == "table") and r.name or tostring(r):match("^(%S+)")
      if rn then reqs[#reqs + 1] = quote(rn) end
    end
    for _, r in ipairs(m.recommends or {}) do recs[#recs + 1] = quote(r) end
    out[#out + 1] = string.format(
      "    [%s] = { disk = %d, version = %s, category = %s, kind = %s,",
      quote(n), diskOfPackage[n] or 1, quote(m.version), quote(m.category or "misc"),
      quote(m.kind))
    out[#out + 1] = string.format("      description = %s,", quote(m.description))
    out[#out + 1] = string.format("      requires = { %s }, recommends = { %s } },",
      table.concat(reqs, ", "), table.concat(recs, ", "))
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local function emitDisk(diskRoot, relPrefix, disk, diskCount)
  mkdirp(diskRoot)
  writeAll(diskRoot .. "/README.txt", README)
  written[#written + 1] = relPrefix .. "README.txt"
  writeAll(diskRoot .. "/optutil-set.lua", setManifestSrc(diskCount or 1))
  written[#written + 1] = relPrefix .. "optutil-set.lua"
  local names = {}
  for _, g in ipairs(disk.groups) do
    for _, e in ipairs(g.members) do
      names[#names + 1] = e.name
      local pkgOut = diskRoot .. "/" .. e.name
      mkdirp(pkgOut)
      -- Ship the manifest WITH generated file hashes so pkg.install's
      -- integrity gate (reject-unverified-by-default) accepts the disk.
      local manifestOut = e.manifestSrc
      if sha256 then
        local hashes = {}
        for _, f in ipairs(e.files) do hashes[f.target] = sha256.hex(f.data) end
        manifestOut = injectHashes(e.manifestSrc, hashes)
      end
      writeAll(pkgOut .. "/package.lua", manifestOut)
      written[#written + 1] = relPrefix .. e.name .. "/package.lua"
      -- Signed AFTER the hashes were injected, never before: the
      -- signature covers the manifest, the manifest carries the hashes,
      -- and the hashes cover the files. Signing the source manifest
      -- would attest to a document this builder then rewrote.
      if signer then
        local key, sigPathOrErr = signer.signManifest(pkgOut .. "/package.lua", signSeed,
          { signer = os.getenv("TOS_SIGNING_NAME") })
        if not key then
          io.write("error: signing " .. e.name .. " failed: " .. tostring(sigPathOrErr) .. "\n")
          os.exit(1)
        end
        written[#written + 1] = relPrefix .. e.name .. "/package.sig"
      end
      for _, f in ipairs(e.files) do
        local dst = pkgOut .. f.target
        mkdirp(dirname(dst))
        local wok, werr = writeAll(dst, f.data)
        if not wok then
          io.write("error: " .. tostring(werr) .. "\n"); os.exit(1)
        end
        written[#written + 1] = relPrefix .. e.name .. f.target
      end
    end
  end
  table.sort(names)
  return names
end

local totalFiles = 0
for _, e in ipairs(entries) do totalFiles = totalFiles + #e.files end

if #disks == 1 then
  local names = emitDisk(outDir, "", disks[1], 1)
  for _, n in ipairs(names) do
    for _, e in ipairs(entries) do
      if e.name == n then
        io.write(string.format("  %-18s %d file(s)  (from %s)\n",
          n, #e.files, e.srcDirRel))
      end
    end
  end
  io.write("  README.txt\n")
  io.write(string.format(
    "\nAssembled %d package(s), %d file(s) (~%d bytes of %s) into:\n  %s\n",
    #entries, totalFiles, disks[1].used,
    LIMIT == math.huge and "unlimited" or tostring(LIMIT), outDir))
else
  io.write(string.format(
    "Set exceeds one %d-byte disk — splitting across %d disks:\n", LIMIT, #disks))
  for i, d in ipairs(disks) do
    local names = emitDisk(outDir .. "/disk" .. i, "disk" .. i .. "/", d, #disks)
    io.write(string.format("  disk%d (~%d bytes): %s + README.txt\n",
      i, d.used, table.concat(names, ", ")))
  end
  io.write(string.format(
    "\nAssembled %d package(s), %d file(s) into %d disk dirs under:\n  %s\n",
    #entries, totalFiles, #disks, outDir))
  io.write("Copy each diskN/'s CONTENTS onto its own floppy.\n")
end

-- Soft pairs the packer could NOT keep together. Named, because the failure
-- mode is an operator with one floppy holding half a toolset and no way to
-- know the other half exists.
if #separated > 0 then
  io.write("\nNOTE: these recommended pairs did not fit on one disk:\n")
  for _, line in ipairs(separated) do io.write("  " .. line .. "\n") end
  io.write("  (the installer lists both and offers to swap disks)\n")
end

-- ── Optional install copy ──────────────────────────────────────────
-- The builder tracked everything it wrote, so the copy needs no
-- directory walking — it replays the same relative paths into the
-- target (an OC floppy folder, a mounted drive, a staging dir, …).
if installDir then
  if #disks > 1 then
    io.write("\nerror: --install targets ONE floppy but the build split into "
      .. #disks .. " disks.\n")
    io.write("       Copy each " .. outDir .. "/diskN/ manually, or raise --limit.\n")
    os.exit(1)
  end
  mkdirp(installDir)
  local copied = 0
  for _, rel in ipairs(written) do
    local data = readAll(outDir .. "/" .. rel)
    if data then
      local dst = installDir .. "/" .. rel
      mkdirp(dirname(dst))
      if writeAll(dst, data) then copied = copied + 1 end
    end
  end
  io.write(string.format("\nInstalled %d file(s) to:\n  %s\n", copied, installDir))
end

io.write("\nOK. Insert the disk on a TOS machine and run\n")
io.write("run `pkg install` as admin to pick add-ons.\n")
