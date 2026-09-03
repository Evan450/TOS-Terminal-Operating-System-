-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: package manager lifecycle                   ║
-- ║                                                                ║
-- ║  The three things it could not do, and now can:                ║
-- ║                                                                ║
-- ║   1. UPGRADE. install refused over an existing package         ║
-- ║      ("uninstall first") and nothing compared installed        ║
-- ║      against available. The version machinery existed and was  ║
-- ║      only ever used for dependency constraints.                ║
-- ║   2. CONFLICTS. Nothing detected them — neither a declared     ║
-- ║      `conflicts` nor the case that actually bites, two         ║
-- ║      packages shipping the same install target.                ║
-- ║   3. FOREIGN PACKAGES. An OPPM manifest was translated and     ║
-- ║      its provenance thrown away, so an OpenOS program          ║
-- ║      installed cleanly with NO capabilities and then could     ║
-- ║      not use io/term/filesystem — it could not run at all.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_lifecycle.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_lifecycle.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
end

local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
-- pkg.install verifies every file against the manifest's hashes, so it
-- needs crypto. crypto.lua reaches for machine globals at load time; give
-- it the real SHA-256 instead, which is what crypto.hash resolves to on a
-- box with no data card anyway.
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.crypto"] = {
  hash = function(s) return sha256.hex(s) end,
  ctEquals = function(a, b) return a == b end,
}

-- ── An in-memory filesystem shaped like kernel.fs ──
local FS = {}
local function newFS()
  local files, dirs = {}, { ["/"] = true }
  local F
  F = {
    _files = files,
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(a, b)
      a = tostring(a):gsub("/$", "")
      return a .. "/" .. tostring(b)
    end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c)
      local acc = ""
      for seg in tostring(p):gmatch("[^/]+") do
        acc = acc .. "/" .. seg
        if acc ~= p then dirs[acc] = true end
      end
      files[p] = c; return true
    end,
    writeFileAtomic = function(p, c) return F.writeFile(p, c) end,
    remove = function(p) files[p] = nil; return true end,
    list = function(p)
      local out, seen = {}, {}
      p = tostring(p):gsub("/$", "")
      for k in pairs(files) do
        local rest = k:match("^" .. p:gsub("%p", "%%%1") .. "/([^/]+)")
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest end
      end
      for k in pairs(dirs) do
        local rest = k:match("^" .. p:gsub("%p", "%%%1") .. "/([^/]+)$")
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest .. "/" end
      end
      table.sort(out)
      return out
    end,
    size = function(p) return files[p] and #files[p] or 0 end,
  }
  return F
end

local ADMIN = { user = "root", tier = 3 }
local usersMock = {
  currentSession = function() return ADMIN end,
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 },
  canAccessAs = function() return true end,
}

--- Fresh package manager over a fresh disk.
local function newPkg()
  local fs = newFS()
  package.loaded["kernel.pkg"] = nil
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  return pkg, fs
end

--- Lay a package repo dir down on the fake disk.
local function putPkg(fs, root, name, manifestTable, fileBodies)
  local dir = root .. "/" .. name
  fs.makeDirectory(dir)
  fs.writeFile(dir .. "/package.lua", serialize.encode(manifestTable))
  for target, body in pairs(fileBodies or {}) do
    fs.writeFile(dir .. target, body)
  end
end

--- A manifest with hashes for every file, so the verification gate passes.
local function manifest(t, fileBodies)
  local sha = loadMod("sha256.lua")
  t.hashes = {}
  for target, body in pairs(fileBodies or {}) do
    t.hashes[target] = sha.hex(body)
  end
  return t
end

print("=== package manager lifecycle Tests ===")
print()

-- ============================================================
-- 1. Upgrades
-- ============================================================
print("-- upgrade --")

do
  local pkg, fs = newPkg()
  local body1 = "return { commands = { demo = function() return 'v1' end } }"
  local files1 = { ["/usr/modules/demo/init.lua"] = body1,
                   ["/usr/modules/demo/old.lua"] = "-- dropped in v2" }
  putPkg(fs, "/usr/repo", "demo", manifest({
    name = "demo", version = "1.0.0", kind = "command",
    files = { "/usr/modules/demo/init.lua", "/usr/modules/demo/old.lua" },
  }, files1), files1)

  local ok = pkg.install("/usr/repo/demo", { session = ADMIN })
  test("v1 installs", ok)
  eq("registry records v1", "1.0.0", pkg.info("demo").version)
  test("both v1 files are on disk", fs._files["/usr/modules/demo/old.lua"] ~= nil)

  -- Nothing newer on offer yet.
  eq("nothing outdated yet", 0, #pkg.outdated())

  -- Now put v2 on the disk. It DROPS old.lua.
  local body2 = "return { commands = { demo = function() return 'v2' end } }"
  local files2 = { ["/usr/modules/demo/init.lua"] = body2 }
  putPkg(fs, "/usr/repo", "demo", manifest({
    name = "demo", version = "2.0.0", kind = "command",
    files = { "/usr/modules/demo/init.lua" },
  }, files2), files2)

  local out = pkg.outdated()
  eq("v2 shows as outdated", 1, #out)
  eq("...naming the package", "demo", out[1] and out[1].name)
  eq("...from", "1.0.0", out[1] and out[1].from)
  eq("...to", "2.0.0", out[1] and out[1].to)

  -- A plain install must now POINT AT upgrade instead of the old
  -- "uninstall first", which gave no hint that an upgrade path exists.
  local iOk, iErr = pkg.install("/usr/repo/demo", { session = ADMIN })
  test("plain install over a newer version is refused", not iOk)
  test("...and names `pkg upgrade`", tostring(iErr):find("pkg upgrade", 1, true) ~= nil)

  local uOk, res = pkg.upgrade("demo", { session = ADMIN })
  test("upgrade succeeds", uOk)
  eq("registry now says v2", "2.0.0", pkg.info("demo").version)
  eq("upgrade reports the jump", "1.0.0", res and res.from)
  -- The reason upgrade can't just be "install over the top": the file the
  -- new version stopped shipping has to go, or it is stranded forever.
  eq("a file dropped by v2 was removed", nil, fs._files["/usr/modules/demo/old.lua"])
  eq("...and is reported", 1, res and #res.dropped)
  test("the kept file was replaced with v2's copy",
    fs._files["/usr/modules/demo/init.lua"] == body2)
  eq("nothing outdated after upgrading", 0, #pkg.outdated())
end

do
  -- Re-upgrading when already current is refused, with a reason.
  local pkg, fs = newPkg()
  local b = "return {}"
  local f = { ["/usr/modules/x/init.lua"] = b }
  putPkg(fs, "/usr/repo", "x", manifest({ name = "x", version = "1.0.0",
    kind = "command", files = { "/usr/modules/x/init.lua" } }, f), f)
  pkg.install("/usr/repo/x", { session = ADMIN })
  local ok, err = pkg.upgrade("x", { session = ADMIN })
  test("upgrading an up-to-date package is refused", not ok)
  test("...saying it is already at that version",
    tostring(err):find("already at", 1, true) ~= nil)
end

do
  -- A DOWNGRADE needs force: the disk in the drive being older than what
  -- is installed is far more often a mistake than an intention.
  local pkg, fs = newPkg()
  local b = "return {}"
  local f = { ["/usr/modules/x/init.lua"] = b }
  putPkg(fs, "/usr/repo", "x", manifest({ name = "x", version = "2.0.0",
    kind = "command", files = { "/usr/modules/x/init.lua" } }, f), f)
  pkg.install("/usr/repo/x", { session = ADMIN })
  putPkg(fs, "/usr/repo", "x", manifest({ name = "x", version = "1.0.0",
    kind = "command", files = { "/usr/modules/x/init.lua" } }, f), f)
  local ok, err = pkg.upgrade("x", { session = ADMIN })
  test("a downgrade is refused by default", not ok)
  test("...and says the disk is older", tostring(err):find("OLDER", 1, true) ~= nil)
  local ok2 = pkg.upgrade("x", { session = ADMIN, force = true })
  test("force allows the downgrade", ok2)
  eq("...and it took effect", "1.0.0", pkg.info("x").version)
end

do
  -- A package something else DEPENDS on must still be upgradable. The
  -- reverse-dependency guard on uninstall would otherwise make every
  -- depended-upon package permanently frozen.
  local pkg, fs = newPkg()
  local lb = "return {}"
  local lf = { ["/usr/lib/libx.lua"] = lb }
  putPkg(fs, "/usr/repo", "libx", manifest({ name = "libx", version = "1.0.0",
    kind = "lib", files = { "/usr/lib/libx.lua" } }, lf), lf)
  local ab = "return {}"
  local af = { ["/usr/modules/app/init.lua"] = ab }
  putPkg(fs, "/usr/repo", "app", manifest({ name = "app", version = "1.0.0",
    kind = "command", files = { "/usr/modules/app/init.lua" },
    requires = { { name = "libx" } } }, af), af)
  pkg.install("/usr/repo/libx", { session = ADMIN })
  pkg.install("/usr/repo/app", { session = ADMIN })

  -- Sanity: a plain uninstall IS still refused.
  local dOk, dErr = pkg.uninstall("libx", { session = ADMIN })
  test("uninstalling a depended-upon package is still refused", not dOk)
  test("...naming the dependant", tostring(dErr):find("app", 1, true) ~= nil)

  putPkg(fs, "/usr/repo", "libx", manifest({ name = "libx", version = "1.5.0",
    kind = "lib", files = { "/usr/lib/libx.lua" } }, lf), lf)
  local uOk, uErr = pkg.upgrade("libx", { session = ADMIN })
  test("but UPGRADING it is allowed", uOk)
  if not uOk then print("        " .. tostring(uErr)) end
  eq("...and lands the new version", "1.5.0", pkg.info("libx").version)
  test("the dependant is still installed", pkg.info("app") ~= nil)
end

-- ============================================================
-- 2. Conflicts
-- ============================================================
print()
print("-- conflicts --")

do
  -- File ownership: the case nobody has to declare for it to happen.
  local pkg, fs = newPkg()
  local b = "return {}"
  local f = { ["/usr/bin/shared.lua"] = b }
  putPkg(fs, "/usr/repo", "alpha", manifest({ name = "alpha", version = "1.0.0",
    kind = "command", files = { "/usr/bin/shared.lua" } }, f), f)
  putPkg(fs, "/usr/repo", "beta", manifest({ name = "beta", version = "1.0.0",
    kind = "command", files = { "/usr/bin/shared.lua" } }, f), f)

  test("alpha installs", (pkg.install("/usr/repo/alpha", { session = ADMIN })))
  local ok, err = pkg.install("/usr/repo/beta", { session = ADMIN })
  test("beta is refused for clobbering alpha's file", not ok)
  test("...naming the file", tostring(err):find("/usr/bin/shared.lua", 1, true) ~= nil)
  test("...and the owner", tostring(err):find("alpha", 1, true) ~= nil)
  test("alpha is still installed", pkg.info("alpha") ~= nil)
  test("beta was NOT installed", pkg.info("beta") == nil)

  -- force is the escape hatch, and it must actually work.
  local okF = pkg.install("/usr/repo/beta", { session = ADMIN, force = true })
  test("force installs anyway", okF)
end

do
  -- Declared conflicts, checked in BOTH directions.
  local pkg, fs = newPkg()
  local b = "return {}"
  local fa = { ["/usr/bin/a.lua"] = b }
  local fb = { ["/usr/bin/b.lua"] = b }
  putPkg(fs, "/usr/repo", "aaa", manifest({ name = "aaa", version = "1.0.0",
    kind = "command", files = { "/usr/bin/a.lua" } }, fa), fa)
  putPkg(fs, "/usr/repo", "bbb", manifest({ name = "bbb", version = "1.0.0",
    kind = "command", files = { "/usr/bin/b.lua" },
    conflicts = { "aaa" } }, fb), fb)

  pkg.install("/usr/repo/aaa", { session = ADMIN })
  local ok, err = pkg.install("/usr/repo/bbb", { session = ADMIN })
  test("a declared conflict blocks the install", not ok)
  test("...and says which package", tostring(err):find("aaa", 1, true) ~= nil)
end

do
  -- The other direction: the INSTALLED package is the one that declared it.
  local pkg, fs = newPkg()
  local b = "return {}"
  local fa = { ["/usr/bin/a.lua"] = b }
  local fb = { ["/usr/bin/b.lua"] = b }
  putPkg(fs, "/usr/repo", "aaa", manifest({ name = "aaa", version = "1.0.0",
    kind = "command", files = { "/usr/bin/a.lua" },
    conflicts = { "bbb" } }, fa), fa)
  putPkg(fs, "/usr/repo", "bbb", manifest({ name = "bbb", version = "1.0.0",
    kind = "command", files = { "/usr/bin/b.lua" } }, fb), fb)
  pkg.install("/usr/repo/aaa", { session = ADMIN })
  local ok = pkg.install("/usr/repo/bbb", { session = ADMIN })
  -- A conflict is symmetric in fact even when only one author wrote it down.
  test("a conflict declared by the INSTALLED package also blocks", not ok)
end

do
  -- An upgrade must not conflict with ITSELF over its own files.
  local pkg, fs = newPkg()
  local b = "return {}"
  local f = { ["/usr/bin/self.lua"] = b }
  putPkg(fs, "/usr/repo", "selfy", manifest({ name = "selfy", version = "1.0.0",
    kind = "command", files = { "/usr/bin/self.lua" } }, f), f)
  pkg.install("/usr/repo/selfy", { session = ADMIN })
  putPkg(fs, "/usr/repo", "selfy", manifest({ name = "selfy", version = "2.0.0",
    kind = "command", files = { "/usr/bin/self.lua" } }, f), f)
  local ok, err = pkg.upgrade("selfy", { session = ADMIN })
  test("upgrading does not self-conflict on its own files", ok)
  if not ok then print("        " .. tostring(err)) end
end

do
  -- The validator rejects nonsense.
  local pkg = newPkg()
  local list = pkg.findConflicts({ name = "z", files = {} })
  eq("no conflicts on an empty system", 0, #list)
end

-- ============================================================
-- 3. Foreign (OpenOS / OPPM) packages
-- ============================================================
print()
print("-- foreign packages --")

do
  local pkg, fs = newPkg()
  local body = "return { commands = { oldtool = function() end } }"
  local dir = "/mnt/loot/oldtool"
  fs.makeDirectory(dir)
  -- An OPPM manifest: outer name, `dependencies`, no TOS capabilities.
  fs.writeFile(dir .. "/package.oppm.lua", serialize.encode({
    oldtool = {
      version = "1.2.0",
      description = "an OpenOS-era tool",
      files = { ["master/oldtool.lua"] = "/usr/bin/oldtool.lua" },
    },
  }))
  fs.writeFile(dir .. "/usr/bin/oldtool.lua", body)

  -- No hashes in an OPPM manifest, so the verification gate needs the
  -- explicit override — same as any unverified package.
  local ok, err = pkg.install(dir, { session = ADMIN, allowUnverified = true })
  test("an OPPM package installs", ok)
  if not ok then print("        " .. tostring(err)) end

  local m = pkg.info("oldtool")
  test("it is in the registry", m ~= nil)
  -- The whole point: the provenance SURVIVES install. It used to be
  -- computed, logged once, and thrown away.
  eq("recorded as an OpenOS package", "openos", m and m.origin)
  eq("version translated", "1.2.0", m and m.version)

  -- ...and the recognition DOES something. Without capabilities this
  -- package installs cleanly and then cannot use io/term/filesystem —
  -- i.e. cannot run a single line of OpenOS-shaped code.
  test("it was granted capabilities", m and type(m.capabilities) == "table"
    and #m.capabilities > 0)
  local caps = {}
  for _, c in ipairs((m and m.capabilities) or {}) do caps[c] = true end
  test("compat.io granted (the OpenOS userland)", caps["compat.io"] == true)
  test("fs.read granted", caps["fs.read"] == true)
  test("flagged as compat-granted for `pkg info`", m and m.capsFromCompat == true)
  -- NOT a blank cheque: `legacy` (raw os/io) can never be granted, and
  -- peripherals still have to be asked for.
  test("legacy is NOT granted", caps["legacy"] ~= true)
  test("no peripheral caps granted", caps["peripheral.modem"] ~= true)

  local resolved = pkg.capabilities("oldtool")
  test("the sandbox can resolve those caps", #resolved > 0)
end

do
  -- A foreign manifest that DOES declare capabilities keeps its own set —
  -- the default is a fallback, not an override.
  local pkg, fs = newPkg()
  local dir = "/mnt/loot/declared"
  fs.makeDirectory(dir)
  fs.writeFile(dir .. "/package.oppm.lua", serialize.encode({
    declared = { version = "1.0.0", capabilities = { "fs.read" },
                 files = { ["m/x.lua"] = "/usr/bin/x.lua" } },
  }))
  fs.writeFile(dir .. "/usr/bin/x.lua", "return {}")
  pkg.install(dir, { session = ADMIN, allowUnverified = true })
  local m = pkg.info("declared")
  eq("its own capability set is kept", 1, m and #m.capabilities)
  eq("...exactly as declared", "fs.read", m and m.capabilities[1])
  test("not flagged as compat-granted", not (m and m.capsFromCompat))
  eq("still recorded as foreign", "openos", m and m.origin)
end

do
  -- The third manifest form, <dirname>.cfg, was DOCUMENTED in
  -- loadAnyManifest's header for a long time and never implemented — a
  -- disk carrying one read as "no manifest here".
  local pkg, fs = newPkg()
  local dir = "/mnt/loot/flatcfg"
  fs.makeDirectory(dir)
  fs.writeFile(dir .. "/flatcfg.cfg", serialize.encode({
    version = "0.9.0", description = "flat OPPM-style config",
    files = { ["m/f.lua"] = "/usr/bin/f.lua" },
  }))
  fs.writeFile(dir .. "/usr/bin/f.lua", "return {}")
  local ok, err = pkg.install(dir, { session = ADMIN, allowUnverified = true })
  test("a <name>.cfg package installs", ok)
  if not ok then print("        " .. tostring(err)) end
  local m = pkg.info("flatcfg")
  eq("named from the directory", "flatcfg", m and m.name)
  eq("version read", "0.9.0", m and m.version)
  eq("also recorded as foreign", "openos", m and m.origin)
end

do
  -- A directory with nothing recognisable still fails cleanly, and the
  -- message now names all three forms it looked for.
  local pkg, fs = newPkg()
  fs.makeDirectory("/mnt/loot/empty")
  local ok, err = pkg.install("/mnt/loot/empty", { session = ADMIN })
  test("a package-less directory is refused", not ok)
  test("...listing the forms it looked for",
    tostring(err):find("%.cfg", 1, false) ~= nil)
end

-- ============================================================
-- 4. Real OPPM repo indexes (programs.cfg)
-- ============================================================
-- loadAnyManifest's header has described programs.cfg since FEAT-7 and
-- nothing read it, so a genuine OPPM repo checkout reported "no manifest".
-- The translation is the interesting part: OPPM keys `files` by SOURCE
-- path and the value is the destination DIRECTORY, the opposite of TOS's
-- one-absolute-path-for-both convention.
print()
print("-- programs.cfg (real OPPM repo index) --")

do
  local pkg, fs = newPkg()
  -- A repo checkout: index at the root, sources under master/<pkg>/.
  fs.makeDirectory("/mnt/repo/gui")
  fs.writeFile("/mnt/repo/programs.cfg", serialize.encode({
    gui = {
      files = {
        ["master/gui/gui.lua"]     = "/lib",     -- prefix-relative -> /usr/lib
        ["master/gui/bin/run.lua"] = "//usr/bin", -- absolute
      },
      dependencies = { libcore = "/" },
      description = "a GUI library",
      authors = "somebody",
    },
    other = { files = { ["master/other/o.lua"] = "/bin" } },
  }))
  fs.writeFile("/mnt/repo/master/gui/gui.lua", "return { gui = true }")
  fs.writeFile("/mnt/repo/master/gui/bin/run.lua", "return {}")

  local ok, err = pkg.install("/mnt/repo/gui",
    { session = ADMIN, allowUnverified = true, force = true })
  test("a programs.cfg package installs", ok)
  if not ok then print("        " .. tostring(err)) end

  local m = pkg.info("gui")
  test("it is in the registry", m ~= nil)
  eq("recorded as foreign", "openos", m and m.origin)
  eq("description read from the index", "a GUI library", m and m.description)

  -- The destination rules: value is a DIRECTORY, filename is the source's
  -- basename, "//" means absolute and a bare path is prefix-relative.
  local targets = {}
  for _, p in ipairs((m and m.files) or {}) do targets[p] = true end
  test("prefix-relative dest resolved to /usr/lib/gui.lua",
    targets["/usr/lib/gui.lua"] == true)
  test("absolute (//) dest resolved to /usr/bin/run.lua",
    targets["/usr/bin/run.lua"] == true)

  -- ...and the files really arrived, read from their SOURCE locations.
  eq("file copied from its repo-relative source",
    "return { gui = true }", fs.readFile("/usr/lib/gui.lua"))
  test("second file copied too", fs.readFile("/usr/bin/run.lua") ~= nil)

  -- OPPM dependency VALUES are install paths, not version constraints.
  -- "/" must not survive into requires as a version.
  local req = (m and m.requires) or {}
  eq("dependency translated", 1, #req)
  eq("...named", "libcore", req[1] and (req[1].name or req[1]))
  eq("...with the OPPM path dropped, not kept as a version",
    nil, req[1] and req[1].version)

  -- Only the entry matching the directory is taken, not the whole index.
  test("the other index entry did not install", pkg.info("other") == nil)
end

do
  -- Directory-copy entries (":" prefix) cannot be honoured without giving
  -- up the per-file ownership map. Refusing LOUDLY beats installing a
  -- package that is silently missing its data files.
  local pkg, fs = newPkg()
  fs.makeDirectory("/mnt/repo2/dircopy")
  fs.writeFile("/mnt/repo2/programs.cfg", serialize.encode({
    dircopy = { files = { [":master/dircopy/data"] = "/share" } },
  }))
  local ok, err = pkg.install("/mnt/repo2/dircopy",
    { session = ADMIN, allowUnverified = true })
  test("a directory-copy entry is refused", not ok)
  test("...and the message says which entry",
    tostring(err):find("dircopy", 1, true) ~= nil)
end

do
  -- A per-package manifest still wins: the index is the fallback for a
  -- checkout whose packages carry no metadata of their own.
  local pkg, fs = newPkg()
  fs.makeDirectory("/mnt/repo3/both")
  fs.writeFile("/mnt/repo3/programs.cfg", serialize.encode({
    both = { version = "9.9.9", files = { ["master/both/x.lua"] = "/bin" } },
  }))
  fs.writeFile("/mnt/repo3/both/package.lua", serialize.encode({
    name = "both", version = "1.0.0", kind = "command",
    files = { "/usr/bin/both.lua" },
  }))
  fs.writeFile("/mnt/repo3/both/usr/bin/both.lua", "return {}")
  local ok = pkg.install("/mnt/repo3/both", { session = ADMIN, allowUnverified = true })
  test("installs from the package's own manifest", ok)
  eq("...and the native version wins over the index",
    "1.0.0", pkg.info("both") and pkg.info("both").version)
end

do
  --! A manifest read off disk must never be able to redirect where the
  --! installer READS from. _srcBase is internal, set only by the
  --! programs.cfg translator; loadAnyManifest strips it from every
  --! on-disk form. Without that, a hand-written package.lua could source
  --! its "files" from anywhere on the machine.
  local pkg, fs = newPkg()
  fs.makeDirectory("/mnt/eve/evil")
  fs.writeFile("/tos/kernel/secret.lua", "SYSTEM SECRET")
  fs.writeFile("/mnt/eve/evil/package.lua", serialize.encode({
    name = "evil", version = "1.0.0", kind = "command",
    files = { "/usr/bin/stolen.lua" },
    fileMap = { ["/usr/bin/stolen.lua"] = "kernel/secret.lua" },
    _srcBase = "/tos",
  }))
  local ok = pkg.install("/mnt/eve/evil", { session = ADMIN, allowUnverified = true })
  test("a disk manifest cannot set _srcBase to steal files", not ok)
  eq("...and nothing was written", nil, fs.readFile("/usr/bin/stolen.lua"))
end

do
  -- fileMap is validated: a source that escapes the package directory,
  -- or names a target the manifest never declared, is refused.
  local pkg, fs = newPkg()
  fs.makeDirectory("/mnt/eve/trav")
  fs.writeFile("/mnt/eve/trav/package.lua", serialize.encode({
    name = "trav", version = "1.0.0", kind = "command",
    files = { "/usr/bin/t.lua" },
    fileMap = { ["/usr/bin/t.lua"] = "../../../tos/kernel/fs.lua" },
  }))
  local ok, err = pkg.install("/mnt/eve/trav", { session = ADMIN, allowUnverified = true })
  test("a traversing fileMap source is refused", not ok)
  test("...naming the reason", tostring(err):find("unsafe", 1, true) ~= nil)

  local pkg2, fs2 = newPkg()
  fs2.makeDirectory("/mnt/eve/undecl")
  fs2.writeFile("/mnt/eve/undecl/package.lua", serialize.encode({
    name = "undecl", version = "1.0.0", kind = "command",
    files = { "/usr/bin/u.lua" },
    fileMap = { ["/usr/bin/elsewhere.lua"] = "u.lua" },
  }))
  local ok2 = pkg2.install("/mnt/eve/undecl", { session = ADMIN, allowUnverified = true })
  test("a fileMap target not in files[] is refused", not ok2)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
