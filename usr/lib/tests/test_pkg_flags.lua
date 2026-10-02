-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: the flags pkg's refusals name, work     ║
-- ║                                                            ║
-- ║  With `pkg trust require on`, pkg refuses an unsigned      ║
-- ║  package and says to use "--allow-unsigned for one         ║
-- ║  install". No pkg verb parsed that flag: install dropped   ║
-- ║  any `--` argument it did not know, fetch and upgrade      ║
-- ║  likewise, and installByName/installWithDeps did not pass  ║
-- ║  allowUnsigned on to pkg.install even when a caller set    ║
-- ║  it. An operator who followed the advice was refused       ║
-- ║  again, with nothing to say the flag had been ignored.     ║
-- ║  `pkg upgrade` had the same hole for --allow-unverified,   ║
-- ║  which its own refusal names, and the media scan and the   ║
-- ║  picker never passed either flag on.                       ║
-- ║                                                            ║
-- ║  Driven end to end: the real `pkg` shell command, the real ║
-- ║  kernel.pkg and kernel.pkgsign, and the real picker in its ║
-- ║  line mode, on one in-memory disk.                         ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_flags.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

package.path = "tos/?.lua;tos/?/init.lua;../../../tos/?.lua;"
  .. "../../../tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_flags.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

-- No GPU anywhere, so the picker takes its line mode.
package.loaded["computer"]  = { uptime = function() return 0 end,
                                freeMemory = function() return 1e6 end,
                                pullSignal = function() return nil end,
                                beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.screen"]  = {}
package.loaded["kernel.display"] = {}

package.loaded["kernel.sha512"] = tryload("tos/kernel/sha512.lua")()
package.loaded["kernel.sha256"] = tryload("tos/kernel/sha256.lua")()
package.loaded["kernel.ed25519"] = tryload("tos/kernel/ed25519.lua")()
local serialize = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = {
  hash = function(d) return sha.hex(d) end,
  ctEquals = function(a, b) return a == b end,
}
package.loaded["kernel.sandbox"] = { build = function() return {} end }

local ROOT = { tier = 3, user = "root" }
local USERS = { TIER = { ADMIN = 2, ROOT = 3 },
                currentSession = function() return ROOT end }
package.loaded["kernel.users"] = USERS

print("=== pkg override flags Tests ===")
print()

-- ── A fake disk whose directories are implied by its files ───
local function makeFs(mounts)
  local F = { _f = {} }
  local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
  function F.exists(p)
    for k in pairs(F._f) do if under(p, k) then return true end end
    return false
  end
  function F.readFile(p) return F._f[p] end
  function F.writeFile(p, d) F._f[p] = d; return true end
  function F.remove(p)
    for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end
    return true
  end
  function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
  function F.makeDirectory() return true end
  function F.mounts()
    local out = {}
    for _, mp in ipairs(mounts or {}) do out[#out + 1] = { mountPoint = mp } end
    return out
  end
  function F.list(p)
    local out, seen = {}, {}
    for k in pairs(F._f) do
      if k:sub(1, #p + 1) == p .. "/" then
        local head = k:sub(#p + 2):match("^([^/]+)")
        if head and not seen[head] then seen[head] = true; out[#out + 1] = head end
      end
    end
    return out
  end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
  return F
end

-- One package directory. Hashed unless o.hashed == false, so only the gate
-- a test is about can refuse it. Unsigned: nothing here writes a .sig.
local function put(F, root, name, o)
  o = o or {}
  local version = o.version or "1.0.0"
  local target = o.path or ("/usr/lib/" .. name .. ".lua")
  local body = "-- " .. name .. " " .. version
  local hashes = (o.hashed == false) and ""
    or string.format("  hashes = { [%q] = %q },\n", target, sha.hex(body))
  F._f[root .. "/" .. name .. "/package.lua"] = string.format(
    'return { name = %q, version = %q, kind = "lib",\n'
    .. '  files = { %q },\n%s  requires = %s }\n',
    name, version, target, hashes, o.requires or "nil")
  F._f[root .. "/" .. name .. target] = body
end

-- The remote side of `pkg fetch`: stages a copy of what `put` wrote under
-- /repo, exactly as the real pkgremote lays one out.
local fetched
local REMOTE = {
  search = function() return {} end,
  fetch = function(name)
    local F = package.loaded["kernel.fs"]
    local src, dst = "/repo/" .. name, "/var/pkg/remote/" .. name
    if not F.exists(src .. "/package.lua") then return nil, "not in the repo: " .. name end
    fetched = name
    -- Collect first, then copy: adding keys to a table while pairs()
    -- walks it is undefined in Lua, and with per-run hash seeds it made
    -- this copy skip a file about one run in ten ("missing source file").
    local copies = {}
    for k, v in pairs(F._f) do
      if k:sub(1, #src + 1) == src .. "/" then copies[dst .. k:sub(#src + 1)] = v end
    end
    for k, v in pairs(copies) do F._f[k] = v end
    return dst, nil, { repo = "test", files = 1, bytes = 1 }
  end,
  cleanup = function(dir) package.loaded["kernel.fs"].remove(dir) end,
}
package.loaded["kernel.pkgremote"] = REMOTE

-- A fresh machine: a disk at /mnt/disk, and `pkg trust require on` when
-- asked. The real pkg is what the shell's require("kernel.pkg") returns.
local function world(requireSig)
  local F = makeFs({ "/mnt/disk" })
  if requireSig then
    F._f["/etc/pkg_trust.cfg"] = serialize.encode({ requireSignature = true, keys = {} })
  end
  package.loaded["kernel.pkgsign"] = nil
  local ps = tryload("tos/kernel/pkgsign.lua")()
  ps.init({ fs = F, serialize = serialize })
  package.loaded["kernel.pkgsign"] = ps
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = USERS })
  package.loaded["kernel.pkg"] = pkg
  package.loaded["kernel.fs"] = F
  package.loaded["shell.pkgpicker"] = nil
  fetched = nil
  return F, pkg
end

-- ── The real shell command ───────────────────────────────────
local okA, register = pcall(require, "shell.panels.commands.admin")
if not okA or type(register) ~= "function" then
  print("FAIL: could not load shell/panels/commands/admin.lua: " .. tostring(register))
  print("*** TESTS FAILED ***"); os.exit(1)
end
local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, D = {},
  U = USERS,
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local confirms = 0
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "y" end,
  confirm = function() confirms = confirms + 1; return true end,
  confirmTyped = function() return true end,
}
local C = {}
local okR, rerr = pcall(register, C, S, deps)
if not okR then
  print("FAIL: admin.lua did not register: " .. tostring(rerr))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local function pkgCmd(...)
  local lines = {}
  local okC, err = pcall(C.pkg, { ... }, function(t) lines[#lines + 1] = tostring(t) end)
  if not okC then lines[#lines + 1] = "THREW: " .. tostring(err) end
  return table.concat(lines, "\n")
end

-- The real picker in line mode: `answers` are what the operator types.
local function pickerCmd(answers, ...)
  local realRead, realWrite = io.read, io.write
  local shown, i = {}, 0
  io.read = function() i = i + 1; return answers[i] end
  io.write = function(...) for _, s in ipairs({ ... }) do shown[#shown + 1] = tostring(s) end end
  local okC, text = pcall(pkgCmd, ...)
  io.read, io.write = realRead, realWrite
  return (okC and text or ("THREW: " .. tostring(text))) .. "\n" .. table.concat(shown)
end

local function version(pkg, name) return pkg.info(name) and pkg.info(name).version end

-- ══════════════════════════════════════════════════════════════════════
print("-- the refusal's advice, followed, by name --")
do
  local F, pkg = world(true)
  put(F, "/mnt/disk", "app", { requires = '{ "applib" }' })
  put(F, "/mnt/disk", "applib")

  local out = pkgCmd("install", "app")
  test("unsigned app is refused under require on", nil, pkg.info("app"))
  ok("and the refusal says --allow-unsigned", out:find("--allow-unsigned", 1, true) ~= nil)

  out = pkgCmd("install", "app", "--allow-unsigned")
  ok("pkg install app --allow-unsigned installs it", pkg.info("app") ~= nil)
  if not pkg.info("app") then print("      (" .. out .. ")") end
  ok("and its dependency, which went in the same way", pkg.info("applib") ~= nil)
  test("recorded as unsigned, not as anything better", "unsigned",
    pkg.info("app") and pkg.info("app")._sigState)

  F, pkg = world(true)
  put(F, "/mnt/disk", "solo")
  pkgCmd("install", "--allow-unsigned", "solo")
  ok("the flag may come before the name", pkg.info("solo") ~= nil)
end

print("-- by path, and several names at once --")
do
  local F, pkg = world(true)
  put(F, "/mnt/disk", "solo")
  local out = pkgCmd("install", "/mnt/disk/solo", "--allow-unsigned")
  ok("pkg install <dir> --allow-unsigned installs it", pkg.info("solo") ~= nil)
  if not pkg.info("solo") then print("      (" .. out .. ")") end

  F, pkg = world(true)
  put(F, "/mnt/disk", "one")
  put(F, "/mnt/disk", "two")
  pkgCmd("install", "one", "two", "--allow-unsigned")
  ok("pkg install one two --allow-unsigned installs one", pkg.info("one") ~= nil)
  ok("...and two", pkg.info("two") ~= nil)
end

print("-- the kernel entry points pass it on --")
do
  local F, pkg = world(true)
  put(F, "/mnt/disk", "app", { requires = '{ "applib" }' })
  put(F, "/mnt/disk", "applib")
  local okI, err = pkg.installByName("app", { session = ROOT, allowUnsigned = true })
  ok("installByName honours allowUnsigned", okI == true)
  if not okI then print("      (" .. tostring(err) .. ")") end

  F, pkg = world(true)
  put(F, "/mnt/disk", "app", { requires = '{ "applib" }' })
  put(F, "/mnt/disk", "applib")
  okI = pkg.installWithDeps("/mnt/disk", "app", { session = ROOT, allowUnsigned = true })
  ok("installWithDeps honours allowUnsigned", okI == true)
end

print("-- pkg fetch --")
do
  local F, pkg = world(true)
  put(F, "/repo", "solo")
  local out = pkgCmd("fetch", "solo")
  test("an unsigned fetch is refused", nil, pkg.info("solo"))
  ok("naming --allow-unsigned", out:find("--allow-unsigned", 1, true) ~= nil)
  out = pkgCmd("fetch", "solo", "--allow-unsigned")
  ok("pkg fetch solo --allow-unsigned installs it", pkg.info("solo") ~= nil)
  if not pkg.info("solo") then print("      (" .. out .. ")") end
  test("and the staging copy is gone", false, F.exists("/var/pkg/remote/solo"))
end

print("-- pkg upgrade --")
do
  local F, pkg = world(true)
  put(F, "/stage", "solo", { version = "1.0.0" })
  assert(pkg.install("/stage/solo", { session = ROOT, allowUnsigned = true }))
  put(F, "/mnt/disk", "solo", { version = "1.1.0" })

  local out = pkgCmd("upgrade", "solo")
  test("an unsigned upgrade is refused", "1.0.0", version(pkg, "solo"))
  ok("naming --allow-unsigned", out:find("--allow-unsigned", 1, true) ~= nil)
  out = pkgCmd("upgrade", "solo", "--allow-unsigned")
  test("pkg upgrade solo --allow-unsigned upgrades it", "1.1.0", version(pkg, "solo"))
  if version(pkg, "solo") ~= "1.1.0" then print("      (" .. out .. ")") end

  -- The same hole, for the other flag upgrade's refusals name.
  F, pkg = world(false)
  put(F, "/stage", "solo", { version = "1.0.0" })
  assert(pkg.install("/stage/solo", { session = ROOT }))
  put(F, "/mnt/disk", "solo", { version = "1.1.0", hashed = false })
  out = pkgCmd("upgrade", "solo")
  test("a hashless upgrade is refused", "1.0.0", version(pkg, "solo"))
  ok("naming --allow-unverified", out:find("--allow-unverified", 1, true) ~= nil)
  out = pkgCmd("upgrade", "solo", "--allow-unverified")
  test("pkg upgrade solo --allow-unverified upgrades it", "1.1.0", version(pkg, "solo"))
  if version(pkg, "solo") ~= "1.1.0" then print("      (" .. out .. ")") end
end

print("-- the media scan (pkg install --prompts) --")
do
  local F, pkg = world(true)
  put(F, "/mnt/disk", "solo")
  confirms = 0
  pkgCmd("install", "--prompts", "--allow-unsigned")
  ok("the operator was asked", confirms > 0)
  ok("and the unsigned package they said yes to installed", pkg.info("solo") ~= nil)

  F, pkg = world(false)
  put(F, "/mnt/disk", "solo", { hashed = false })
  pkgCmd("install", "--prompts", "--allow-unverified")
  ok("--allow-unverified reaches the media scan too", pkg.info("solo") ~= nil)
end

print("-- the picker (pkg install, no name) --")
do
  local F, pkg = world(true)
  put(F, "/mnt/disk", "solo")
  local shown = pickerCmd({ "a", "i" }, "install", "--allow-unsigned")
  ok("the picker ran in line mode", shown:find("Optional Utilities", 1, true) ~= nil)
  ok("and installed the unsigned package picked", pkg.info("solo") ~= nil)
  if not pkg.info("solo") then print("      (" .. shown:gsub("\n", " | ") .. ")") end

  F, pkg = world(false)
  put(F, "/mnt/disk", "solo", { hashed = false })
  pickerCmd({ "a", "i" }, "install", "--allow-unverified")
  ok("--allow-unverified reaches the picker too", pkg.info("solo") ~= nil)

  -- Without the flag the picker still refuses: the override is carried,
  -- not granted.
  F, pkg = world(true)
  put(F, "/mnt/disk", "solo")
  pickerCmd({ "a", "i" }, "install")
  test("no flag, no install", nil, pkg.info("solo"))
end

-- MANUAL 7.3: an install that would take another package's file, or that
-- the plan finds contradicted, is refused, and "--force overrides either,
-- loudly". `pkg install` dropped --force like --allow-unsigned, and
-- installWithDeps did not pass force on to pkg.install, whose conflict
-- check is the one that reads it.
print("-- pkg install --force --")
do
  local F, pkg = world(false)
  put(F, "/stage", "lib", { version = "1.0.0" })
  assert(pkg.install("/stage/lib", { session = ROOT }))
  put(F, "/mnt/disk", "app", { requires = '{ "lib >=2.0" }' })
  local out = pkgCmd("install", "app")
  test("an install the plan contradicts is refused", nil, pkg.info("app"))
  ok("saying who needs what", out:find("app requires 'lib' >=2.0", 1, true) ~= nil)
  out = pkgCmd("install", "app", "--force")
  ok("pkg install app --force goes past it", pkg.info("app") ~= nil)
  if not pkg.info("app") then print("      (" .. out .. ")") end
end

local function takenFile()
  local F, pkg = world(false)
  put(F, "/stage", "owner", { path = "/usr/lib/shared.lua" })
  assert(pkg.install("/stage/owner", { session = ROOT }))
  put(F, "/mnt/disk", "intruder", { path = "/usr/lib/shared.lua" })
  return F, pkg
end
do
  local F, pkg = takenFile()
  local out = pkgCmd("install", "intruder")
  test("installing over another package's file is refused", nil, pkg.info("intruder"))
  ok("as a conflict", out:find("conflicts:", 1, true) ~= nil)
  test("and the file is still the owner's", "-- owner 1.0.0", F._f["/usr/lib/shared.lua"])
  out = pkgCmd("install", "intruder", "--force")
  ok("pkg install intruder --force installs it", pkg.info("intruder") ~= nil)
  if not pkg.info("intruder") then print("      (" .. out .. ")") end
  test("over the owner's file", "-- intruder 1.0.0", F._f["/usr/lib/shared.lua"])

  F, pkg = takenFile()
  pkgCmd("install", "/mnt/disk/intruder", "--force")
  ok("by path too", pkg.info("intruder") ~= nil)

  F, pkg = takenFile()
  pkgCmd("install", "--prompts", "--force")
  ok("through the media scan", pkg.info("intruder") ~= nil)

  F, pkg = takenFile()
  pickerCmd({ "a", "i" }, "install", "--force")
  ok("through the picker", pkg.info("intruder") ~= nil)

  F, pkg = takenFile()
  pickerCmd({ "a", "i" }, "install")
  test("and not without it", nil, pkg.info("intruder"))
end

-- MANUAL: `pkg install <names> --dry-run` prints the plan and changes
-- nothing. Only --all and several names ever looked at it: one name, a
-- path, and the no-argument picker installed for real.
print("-- --dry-run, in every install mode --")
local function oneOnDisk()
  local F, pkg = world(false)
  put(F, "/mnt/disk", "solo")
  put(F, "/mnt/disk", "one")
  return F, pkg
end
do
  local F, pkg = oneOnDisk()
  local out = pkgCmd("install", "solo", "--dry-run")
  test("pkg install <name> --dry-run installs nothing", nil, pkg.info("solo"))
  ok("and says what it would do", out:find("Would install", 1, true) ~= nil
    and out:find("solo", 1, true) ~= nil)
  test("and writes no file", nil, F._f["/usr/lib/solo.lua"])

  F, pkg = oneOnDisk()
  out = pkgCmd("install", "/mnt/disk/solo", "--dry-run")
  test("pkg install <dir> --dry-run installs nothing", nil, pkg.info("solo"))
  ok("and names the directory", out:find("/mnt/disk/solo", 1, true) ~= nil)

  F, pkg = oneOnDisk()
  confirms = 0
  pkgCmd("install", "--prompts", "--dry-run")
  test("pkg install --prompts --dry-run installs nothing", nil, pkg.info("solo"))
  test("without asking anything", 0, confirms)

  F, pkg = oneOnDisk()
  out = pickerCmd({ "a", "i" }, "install", "--dry-run")
  test("pkg install --dry-run installs nothing", nil, pkg.info("solo"))
  ok("the picker did not open", out:find("Optional Utilities", 1, true) == nil)
  ok("and it lists what there is to choose from", out:find("solo", 1, true) ~= nil
    and out:find("one", 1, true) ~= nil)

  F, pkg = oneOnDisk()
  pkgCmd("install", "solo", "one", "--dry-run")
  test("several names still dry-run", nil, pkg.info("solo"))
end

-- A dry run is for finding out what the install would hit. It used to
-- print the names it was given and nothing else, so the plan's
-- contradictions -- the refusal the real install would meet -- were only
-- found by running it.
print("-- --dry-run prints the plan --")
do
  local F, pkg = world(false)
  put(F, "/stage", "lib", { version = "1.0.0" })
  assert(pkg.install("/stage/lib", { session = ROOT }))
  put(F, "/mnt/disk", "app", { requires = '{ "lib >=2.0" }' })
  local out = pkgCmd("install", "app", "--dry-run")
  test("a contradicted dry run installs nothing", nil, pkg.info("app"))
  ok("it names the contradiction", out:find("app requires 'lib' >=2.0", 1, true) ~= nil)
  ok("and says the install would be refused", out:find("would be refused", 1, true) ~= nil)
  if not out:find("would be refused", 1, true) then print("      (" .. out .. ")") end

  out = pkgCmd("install", "app", "--dry-run", "--force")
  test("--force --dry-run still installs nothing", nil, pkg.info("app"))
  ok("and says --force would go past it", out:find("--force: would install past", 1, true) ~= nil)

  out = pkgCmd("install", "/mnt/disk/app", "--dry-run")
  ok("by path, the same contradiction", out:find("app requires 'lib' >=2.0", 1, true) ~= nil)

  F, pkg = world(false)
  put(F, "/mnt/disk", "app", { requires = '{ "applib" }' })
  put(F, "/mnt/disk", "applib")
  out = pkgCmd("install", "app", "--dry-run")
  ok("the order puts the dependency first", out:find("order: applib, app", 1, true) ~= nil)
  ok("and a clean plan is not called refused", out:find("would be refused", 1, true) == nil)
  test("nothing installed", nil, pkg.info("applib"))

  out = pkgCmd("install", "ghost", "--dry-run")
  ok("an unknown name says it would fail", out:find("would fail: package not found", 1, true) ~= nil)
  ok("and is counted", out:find("1 of 1 would not install", 1, true) ~= nil)
end

-- An option a verb does not know is refused before anything happens. It
-- was dropped, which is how --allow-unsigned went unnoticed; and a flag
-- that changes what happens is exactly the kind that must not be guessed
-- past: --dry-rn installed for real.
print("-- an option pkg does not know --")
do
  local F, pkg = oneOnDisk()
  local out = pkgCmd("install", "solo", "--dry-rn")
  test("a misspelt --dry-run installs nothing", nil, pkg.info("solo"))
  ok("the refusal names the option", out:find("'--dry-rn'", 1, true) ~= nil)
  ok("and says nothing was done", out:find("nothing was done", 1, true) ~= nil)
  ok("and lists the options there are", out:find("--allow-unsigned", 1, true) ~= nil)

  F, pkg = world(true)
  put(F, "/mnt/disk", "solo")
  out = pkgCmd("install", "solo", "--allow-unsgined")
  test("a misspelt --allow-unsigned installs nothing", nil, pkg.info("solo"))
  ok("and is reported as the misspelling, not as the gate",
    out:find("'--allow-unsgined'", 1, true) ~= nil
    and out:find("require signatures", 1, true) == nil)

  F, pkg = oneOnDisk()
  confirms = 0
  out = pickerCmd({ "a", "i" }, "install", "--prmpts")
  test("an unknown option stops the picker too", nil, pkg.info("solo"))
  ok("before it opens", out:find("Optional Utilities", 1, true) == nil)

  F, pkg = oneOnDisk()
  pkgCmd("install", "solo", "--key", "--not-an-option")
  ok("--key's value is a value, even one that starts with --", pkg.info("solo") ~= nil)

  F, pkg = world(false)
  put(F, "/stage", "solo", { version = "1.0.0" })
  assert(pkg.install("/stage/solo", { session = ROOT }))
  put(F, "/mnt/disk", "solo", { version = "1.1.0" })
  out = pkgCmd("upgrade", "solo", "--dry-rn")
  test("pkg upgrade: a misspelt --dry-run upgrades nothing", "1.0.0", version(pkg, "solo"))
  ok("and names the option", out:find("'--dry-rn'", 1, true) ~= nil)

  F, pkg = world(false)
  put(F, "/repo", "solo")
  out = pkgCmd("fetch", "solo", "--allow-unverifed")
  test("pkg fetch: an unknown option fetches nothing", nil, fetched)
  ok("and names the option", out:find("'--allow-unverifed'", 1, true) ~= nil)

  F, pkg = world(true)
  put(F, "/repo", "solo")
  pkgCmd("fetch", "--allow-unsigned", "solo")
  ok("pkg fetch takes its options before the name, as install does", pkg.info("solo") ~= nil)
  test("and fetched the package, not the option", "solo", fetched)

  -- Every flag the manual gives these verbs is still known.
  F, pkg = oneOnDisk()
  out = pkgCmd("install", "solo", "one", "--dry-run", "--yes", "--force",
    "--allow-unverified", "--allow-unsigned")
  ok("pkg install still takes every documented option",
    out:find("unknown option", 1, true) == nil and out:find("Would install", 1, true) ~= nil)
  F, pkg = oneOnDisk()
  out = pkgCmd("install", "--all", "--yes", "--dry-run")
  ok("including --all", out:find("unknown option", 1, true) == nil
    and out:find("Would install 2", 1, true) ~= nil)
  out = pkgCmd("install", "--prompts", "--classic", "--dry-run")
  ok("and --prompts / --classic", out:find("unknown option", 1, true) == nil)
  out = pkgCmd("upgrade", "--all", "--yes", "--force", "--dry-run",
    "--allow-unverified", "--allow-unsigned")
  ok("pkg upgrade still takes every documented option", out:find("unknown option", 1, true) == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  os.exit(1)
else
  print("All tests passed.")
end
