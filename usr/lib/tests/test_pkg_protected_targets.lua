-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: package targets the SYSTEM gives meaning to  ║
-- ║  (pentest, Sep 2026)                                           ║
-- ║                                                                ║
-- ║  pkg confined writes to /usr, /var/pkg and a service's rc.d    ║
-- ║  script + cfg, and checked a package against other PACKAGES.   ║
-- ║  Nothing checked it against the system, and every one of      ║
-- ║  these installed cleanly with no --force:                      ║
-- ║   1. /etc/rc.d/20-rshd.lua with user = "_kernel_" — rc.lua     ║
-- ║      grants kernel tier by FILENAME, so the next boot ran the  ║
-- ║      package in buildKernelEnv with the raw component API.     ║
-- ║   2. /etc/component_caps.cfg, /etc/pkg_trust.cfg, ... — the    ║
-- ║      "one top-level cfg" exception matched the system's own.   ║
-- ║   3. /usr/lib/mailapp.lua from a THEME — the shell requires    ║
-- ║      that name in kernel context at startup, and require()     ║
-- ║      runs /usr/lib modules in the kernel's own _G.             ║
-- ║   4. /usr/bin/mail.lua — /usr/bin was a require root too.      ║
-- ║  Both real sides are read where there is a seam: rc.lua's own  ║
-- ║  allowlist, the shell's own require calls, init.lua's own      ║
-- ║  search path, the real system_manifest.lua.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_protected_targets.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_protected_targets.lua"
local base = here:gsub("[^/\\]*$", "")
local function readSrc(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("a"); f:close(); return s end
  end
end
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
  error("cannot find " .. rel)
end

local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.crypto"] = {
  hash = function(s) return sha256.hex(s) end,
  ctEquals = function(a, b) return a == b end,
}

local SYSMAN = readSrc("tos/system_manifest.lua")
test("the real tos/system_manifest.lua is readable", SYSMAN ~= nil)

local function newFS()
  local files, dirs = {}, { ["/"] = true }
  local F
  F = {
    _files = files,
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(a, b) return tostring(a):gsub("/$", "") .. "/" .. tostring(b) end,
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
    remove = function(p) files[p] = nil; return true end,
    list = function(p)
      local out, seen = {}, {}
      p = tostring(p):gsub("/$", "")
      local pat = "^" .. p:gsub("%p", "%%%1") .. "/([^/]+)"
      for k in pairs(files) do
        local rest = k:match(pat)
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest end
      end
      for k in pairs(dirs) do
        local rest = k:match(pat .. "$")
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

local RSHD_ORIG = '-- shipped\nlocal user = "_kernel_"\nreturn { start = function() end }\n'
local EVIL = 'local user = "_kernel_"\nreturn { start = function() end }\n'

local function newPkg(opts)
  opts = opts or {}
  local fs = newFS()
  if not opts.noSysman then fs.writeFile("/tos/system_manifest.lua", SYSMAN) end
  fs.writeFile("/etc/rc.d/20-rshd.lua", RSHD_ORIG)
  fs.writeFile("/etc/rc.d/20-netfsd.lua", "-- shipped netfsd\n")
  fs.writeFile("/etc/rc.d/local-admin.lua", "-- the operator's own script\n")
  fs.writeFile("/etc/site.cfg", "{ mine = true }")
  fs.writeFile("/usr/bin/ssh.lua", "-- shipped ssh\n")
  package.loaded["kernel.pkg"] = nil
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  return pkg, fs
end

--- Put a fully hashed package on a "floppy" and install it.
local function stage(fs, root, name, kind, bodies, version)
  local files = {}
  for t in pairs(bodies) do files[#files + 1] = t end
  table.sort(files)
  local m = { name = name, version = version or "1.0.0", kind = kind,
              files = files, hashes = {} }
  for t, b in pairs(bodies) do m.hashes[t] = sha256.hex(b) end
  local dir = root .. "/" .. name
  fs.makeDirectory(dir)
  fs.writeFile(dir .. "/package.lua", serialize.encode(m))
  for t, b in pairs(bodies) do fs.writeFile(dir .. t, b) end
  return dir
end
local function tryInstall(pkg, fs, name, kind, bodies)
  return pkg.install(stage(fs, "/mnt/floppy", name, kind, bodies), { session = ADMIN })
end

print("=== package protected-target Tests ===")

-- ── 1. kernel-tier rc.d names ──────────────────────────────────
print("-- rc.d --")
do
  local pkg, fs = newPkg()
  local ok, err = tryInstall(pkg, fs, "rshd-plus", "service",
    { ["/etc/rc.d/20-rshd.lua"] = EVIL })
  test("a service package cannot replace kernel-tier 20-rshd.lua", not ok)
  test("  ...the shipped script is untouched", fs._files["/etc/rc.d/20-rshd.lua"] == RSHD_ORIG)
  test("  ...and the reason is given (" .. tostring(err) .. ")", type(err) == "string")
  test("case-folded 20-RSHD.lua is refused too (case-insensitive host)",
    not tryInstall(pkg, fs, "rshd-case", "service", { ["/etc/rc.d/20-RSHD.lua"] = EVIL }))
  test("a system rc.d script that is not kernel-tier (20-netfsd) is refused",
    not tryInstall(pkg, fs, "netfsd2", "service", { ["/etc/rc.d/20-netfsd.lua"] = EVIL }))
  test("the operator's own unowned rc.d script is not a package's to replace",
    not tryInstall(pkg, fs, "shadow", "service", { ["/etc/rc.d/local-admin.lua"] = EVIL }))
  test("a fresh rc.d script for the package's own service still installs",
    (tryInstall(pkg, fs, "mysvc", "service", { ["/etc/rc.d/mysvc.lua"] = "return {}" })))
end
do
  -- Kernel-tier names are refused on shape alone, even with no system
  -- manifest to consult and no script on the disk yet.
  local pkg, fs = newPkg({ noSysman = true })
  test("10-discoveryd.lua refused with no system manifest present",
    not tryInstall(pkg, fs, "disc", "service", { ["/etc/rc.d/10-discoveryd.lua"] = EVIL }))
end
do
  -- THE SEAM: rc.lua's own allowlist, read out of rc.lua, against pkg's check.
  local rcSrc = readSrc("tos/kernel/rc.lua")
  local block = rcSrc and rcSrc:match("KERNEL_SERVICE_ALLOWLIST%s*=%s*(%b{})")
  test("rc.lua's KERNEL_SERVICE_ALLOWLIST is found", block ~= nil)
  local pkg = newPkg()
  local n = 0
  for stem in (block or ""):gmatch('%["([^"]+)"%]') do
    n = n + 1
    test("pkg will not write the rc.d script of kernel-tier '" .. stem .. "'",
      pkg._isServiceEtcTarget("/etc/rc.d/" .. stem .. ".lua") == false)
  end
  test("the allowlist is non-empty (" .. n .. ")", n > 0)
end

-- ── 2. system configs ─────────────────────────────────────────
print("-- /etc cfg --")
for _, cfg in ipairs({ "component_caps", "pkg_trust", "pkg_caps", "pkg-repos", "boot",
    "tos", "netfs-exports", "kiosk", "menu", "keys", "jbod", "chat-groups", "PKG_TRUST" }) do
  local pkg, fs = newPkg()
  test("a service package cannot write /etc/" .. cfg .. ".cfg",
    not tryInstall(pkg, fs, "cfgsvc", "service",
      { ["/etc/" .. cfg .. ".cfg"] = "{ base = { \"filesystem\" } }" }))
end
do
  local pkg, fs = newPkg()
  test("an existing, unowned /etc cfg is not clobbered",
    not tryInstall(pkg, fs, "sitesvc", "service", { ["/etc/site.cfg"] = "{}" }))
  test("  ...and still holds the operator's content", fs._files["/etc/site.cfg"] == "{ mine = true }")
  test("an add-on's own cfg + rc.d still install (cluster-master.cfg)",
    (tryInstall(pkg, fs, "clusterd", "service",
      { ["/etc/cluster-master.cfg"] = "{}", ["/etc/rc.d/clusterd.lua"] = "return {}" })))
end

-- ── 3. names the kernel loads ─────────────────────────────────
print("-- kernel-loaded modules --")
for _, n in ipairs({ "mailapp", "mail", "intercom", "intercomapp", "blockfs", "mouse" }) do
  local pkg, fs = newPkg()
  test("a theme cannot ship /usr/lib/" .. n .. ".lua",
    not tryInstall(pkg, fs, "zz-theme", "theme", { ["/usr/lib/" .. n .. ".lua"] = "-- x" }))
end
for _, t in ipairs({ "/usr/LIB/MailApp.lua", "/usr/modules/mouse/init.lua",
    "/usr/modules/mailapp.lua", "/usr/lib/kernel/users.lua",
    "/usr/modules/shell/panels/desktop.lua", "/usr/lib/compat/init.lua",
    "/usr/lib/system_manifest.lua", "/usr/bin/ssh.lua" }) do
  local pkg, fs = newPkg()
  test("refused: " .. t, not tryInstall(pkg, fs, "zz-other", "command", { [t] = "-- x" }))
end
do
  local pkg, fs = newPkg()
  test("the mail package itself still ships mail + mailapp",
    (tryInstall(pkg, fs, "mail", "command",
      { ["/usr/lib/mail.lua"] = "return {}", ["/usr/lib/mailapp.lua"] = "return {}" })))
  test("an ordinary library still installs",
    (tryInstall(pkg, fs, "zzlib", "lib", { ["/usr/lib/zzlib.lua"] = "return {}" })))
  test("cluster-manager still ships its lib + the shared cluster/ namespace",
    (tryInstall(pkg, fs, "cluster-manager", "service",
      { ["/usr/lib/cluster-manager.lua"] = "return {}",
        ["/usr/lib/cluster/protocol.lua"] = "return {}" })))
  test("cluster-master still ships cluster/api.lua",
    (tryInstall(pkg, fs, "cluster-master", "service",
      { ["/usr/lib/cluster/api.lua"] = "return {}" })))
end
do
  -- THE SEAM: every dot-less name the SHELL requires in kernel context,
  -- read from the shell's own source, must be one pkg will not let an
  -- arbitrary package supply.
  local names, seen = {}, {}
  local PRELOADED = { computer = true, component = true, unicode = true }
  local function add(n) if not seen[n] and not PRELOADED[n] then seen[n] = true; names[#names + 1] = n end end
  for _, rel in ipairs({ "tos/shell/panels/commands/extras.lua", "tos/shell/panels/mouse.lua",
      "tos/shell/panels/events.lua", "tos/shell/chat.lua", "tos/shell/panels/chatapp.lua" }) do
    local src = readSrc(rel)
    test("scan: " .. rel .. " is readable", src ~= nil)
    for n in (src or ""):gmatch('require[%s,%(]+"([%w_%.%-]+)"') do add(n) end
  end
  local apps = readSrc("tos/shell/panels/apps.lua")
  local blk = apps and apps:match("local BUILTINS%s*=%s*(%b{})")
  test("scan: apps.lua BUILTINS is found", blk ~= nil)
  for n in (blk or ""):gmatch('=%s*"([%w_%.%-]+)"') do add(n) end
  test("scan found the add-on names (" .. #names .. ")",
    seen.mailapp and seen.mouse and seen["cluster.api"] and seen["cluster-manager"])
  for _, n in ipairs(names) do
    local pkg, fs = newPkg()
    local target = "/usr/lib/" .. n:gsub("%.", "/") .. ".lua"
    test("kernel-context require('" .. n .. "') is not suppliable by any package",
      not tryInstall(pkg, fs, "zz-other", "command", { [target] = "-- shadow" }))
  end
end
do
  local initSrc = readSrc("init.lua")
  local sp = initSrc and initSrc:match("local searchPaths = (%b{})")
  test("init.lua searchPaths is found", sp ~= nil)
  test("/usr/bin is not a kernel require root", sp ~= nil and not sp:find("/usr/bin/", 1, true))
end

-- ── 4. names that differ only as strings ─────────────────────
print("-- target shape --")
for _, t in ipairs({ "/usr/lib/x.lua.", "/usr/lib/x .lua", "/usr//lib/x.lua",
    "/usr/lib/x:y.lua", "/usr/lib/x/" }) do
  local pkg, fs = newPkg()
  test("refused target shape: '" .. t .. "'",
    not tryInstall(pkg, fs, "shape", "command", { [t] = "-- x" }))
end
do
  local pkg, fs = newPkg()
  test("package A owns /usr/lib/foo.lua",
    (tryInstall(pkg, fs, "pkga", "lib", { ["/usr/lib/foo.lua"] = "return 1" })))
  test("package B's /usr/lib/FOO.lua is a file conflict with A",
    not tryInstall(pkg, fs, "pkgb", "lib", { ["/usr/lib/FOO.lua"] = "return 2" }))
end

-- ── 5. upgrade refuses BEFORE removing the working version ─────
print("-- upgrade --")
do
  local pkg, fs = newPkg()
  test("demo v1 installs",
    (pkg.install(stage(fs, "/mnt/v1", "demo", "command",
      { ["/usr/lib/demo.lua"] = "return 1" }), { session = ADMIN })))
  stage(fs, "/usr/repo", "demo", "command",
    { ["/usr/lib/demo.lua"] = "return 2", ["/usr/lib/mailapp.lua"] = "-- x" }, "2.0.0")
  local ok = pkg.upgrade("demo", { session = ADMIN })
  test("an upgrade to a version shipping mailapp.lua is refused", not ok)
  test("  ...and v1 is still installed", pkg.info("demo") ~= nil and pkg.info("demo").version == "1.0.0")
  test("  ...with its file still on disk", fs._files["/usr/lib/demo.lua"] == "return 1")
  test("  ...and mailapp.lua never written", fs._files["/usr/lib/mailapp.lua"] == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
