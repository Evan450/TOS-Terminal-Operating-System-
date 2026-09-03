-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg discovery sees mounted disks        ║
-- ║                                                            ║
-- ║  A disk mounted by the KERNEL at boot is a VIRTUAL mount   ║
-- ║  point — fs.mount records it but creates no real           ║
-- ║  /mnt/<label> directory, so it never appears in            ║
-- ║  fs.list("/mnt"). pkg discovery used to scan only /mnt, so ║
-- ║  single-package installs (explicit path) worked but a      ║
-- ║  multi-package Optional Utilities disk's packages were     ║
-- ║  invisible to `pkg search` / `from-floppy` / install.lua.  ║
-- ║  listAllAvailable now enumerates fs.mounts().              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_discovery.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["kernel.serialize"] = assert(loadfile("tos/kernel/serialize.lua"))()

-- ── Fake fs: a virtual disk mounted at /mnt/disk_X that is NOT a child of
--    /mnt in a directory listing, but IS in the mount table. The two
--    package dirs carry comment headers (the real manifest shape). ──
local MANIFEST_MOUSE  = "-- mouse driver\nreturn { name = \"mouse\", version = \"1.0\", files = {} }"
local MANIFEST_TETRIS = "return { name = \"tetris\", version = \"1.0\", files = {} }"

local function norm(p) p = (p or ""):gsub("//+", "/"); if #p > 1 then p = p:gsub("/$", "") end; return p end
local fakeFS = {
  normalize = norm,
  join = function(a, b)
    a = norm(a); if b:sub(1, 1) == "/" then return norm(a .. b) end
    return norm(a .. "/" .. b)
  end,
  exists = function(p)
    p = norm(p)
    local known = {
      ["/mnt"] = true, ["/mnt/disk_X"] = true,
      ["/mnt/disk_X/mouse"] = true, ["/mnt/disk_X/tetris"] = true,
      ["/mnt/disk_X/mouse/package.lua"] = true,
      ["/mnt/disk_X/tetris/package.lua"] = true,
      ["/var/pkg/installed"] = true,
    }
    return known[p] == true
  end,
  isDirectory = function(p)
    p = norm(p)
    local d = { ["/mnt"] = true, ["/mnt/disk_X"] = true,
      ["/mnt/disk_X/mouse"] = true, ["/mnt/disk_X/tetris"] = true,
      ["/var/pkg/installed"] = true }
    return d[p] == true
  end,
  list = function(p)
    p = norm(p)
    -- The crux: listing /mnt does NOT reveal the virtual mount point.
    if p == "/mnt" then return {} end
    if p == "/mnt/disk_X" then return { "mouse/", "tetris/" } end
    if p == "/mnt/disk_X/mouse" then return { "package.lua" } end
    if p == "/mnt/disk_X/tetris" then return { "package.lua" } end
    if p == "/var/pkg/installed" then return {} end
    return {}
  end,
  readFile = function(p)
    p = norm(p)
    if p == "/mnt/disk_X/mouse/package.lua" then return MANIFEST_MOUSE end
    if p == "/mnt/disk_X/tetris/package.lua" then return MANIFEST_TETRIS end
    return nil
  end,
  makeDirectory = function() return true end,
  -- The authoritative mount table — this is where the virtual disk shows up.
  mounts = function()
    return { { mountPoint = "/" }, { mountPoint = "/mnt/disk_X", label = "disk_X" } }
  end,
}

local pkg = require("kernel.pkg")
pkg.init({ fs = fakeFS, log = nil, users = nil })

print("=== pkg discovery Tests ===")
print()

-- Sanity: the bug's precondition — /mnt listing is blind to the mount.
test("precondition: fs.list('/mnt') is empty (virtual mount)", #fakeFS.list("/mnt") == 0)

local avail = pkg.listAllAvailable()
local byName = {}
for _, e in ipairs(avail) do byName[e.name] = e end

test("found packages despite the blind /mnt listing", #avail >= 2)
test("mouse discovered on the mounted disk", byName["mouse"] ~= nil)
test("tetris discovered on the mounted disk", byName["tetris"] ~= nil)
test("discovered root points at the mount", byName["mouse"] and byName["mouse"].root == "/mnt/disk_X")

-- ── Nested layout + the INSTALL path (findInRepos) ──────────────────────────
-- The whole optional-utilities FOLDER copied onto a disk puts packages one
-- level down: /mnt/<disk>/optional-utilities/<pkg>. Listing already descended
-- one level, but `pkg install <name>` uses findInRepos, which only scanned
-- /mnt/<label> (one level) — so listing showed the package while install said
-- "not found in any repo". Both must agree now.
do
  local known = {
    ["/mnt"] = true, ["/mnt/d"] = true, ["/mnt/d/optional-utilities"] = true,
    ["/mnt/d/optional-utilities/tetris"] = true,
    ["/mnt/d/optional-utilities/tetris/package.lua"] = true,
    ["/var/pkg/installed"] = true,
  }
  local dirs = {
    ["/mnt"] = true, ["/mnt/d"] = true, ["/mnt/d/optional-utilities"] = true,
    ["/mnt/d/optional-utilities/tetris"] = true, ["/var/pkg/installed"] = true,
  }
  local nestedFS = {
    normalize = norm,
    join = fakeFS.join,
    exists = function(p) return known[norm(p)] == true end,
    isDirectory = function(p) return dirs[norm(p)] == true end,
    list = function(p)
      p = norm(p)
      if p == "/mnt" then return {} end                       -- virtual mount, blind
      if p == "/mnt/d" then return { "optional-utilities/" } end
      if p == "/mnt/d/optional-utilities" then return { "tetris/" } end
      if p == "/mnt/d/optional-utilities/tetris" then return { "package.lua" } end
      return {}
    end,
    readFile = function(p)
      if norm(p) == "/mnt/d/optional-utilities/tetris/package.lua" then return MANIFEST_TETRIS end
      return nil
    end,
    makeDirectory = function() return true end,
    mounts = function()
      return { { mountPoint = "/" }, { mountPoint = "/mnt/d", label = "d" } }
    end,
  }
  pkg.init({ fs = nestedFS, log = nil, users = nil })

  local nestedAvail = pkg.listAllAvailable()
  local seenTetris = false
  for _, e in ipairs(nestedAvail) do if e.name == "tetris" then seenTetris = true end end
  test("nested: listing finds the package", seenTetris)

  local dir, root = pkg.findInRepos("tetris")
  test("nested: findInRepos (install path) finds it too", dir == "/mnt/d/optional-utilities/tetris")
  test("nested: findInRepos returns the nested repo root", root == "/mnt/d/optional-utilities")
end

-- ── runInstaller must not report an empty catalogue as success ──────
-- Bug: inserting a disk with no TOS packages on it (an OPPM disk, say)
-- made `pkg install` look like it refused in total silence. The picker
-- DID print "No installable packages found" -- but it draws through a
-- raw GPU proxy, so the shell repaints over it the instant run()
-- returns, and the shell also returns early whenever the picker "ran".
-- The message existed for about one frame.
--
-- The picker now returns false + reason, and runInstaller propagates it,
-- so the shell falls through to the prompt scan and says so in ordinary
-- output that survives the repaint.
do
  local realPicker = package.loaded["shell.pkgpicker"]

  package.loaded["shell.pkgpicker"] = {
    run = function() return false, "no installable packages found" end,
  }
  local ok, why = pkg.runInstaller({})
  test("a declining picker is not success", ok == false)
  test("...and the reason is carried out", why == "no installable packages found")

  package.loaded["shell.pkgpicker"] = {
    run = function() return true end,
  }
  test("a picker that ran normally still succeeds", pkg.runInstaller({}) == true)

  -- A picker that returns nothing at all (the old shape) must stay
  -- success, or every normal install would start reporting a failure.
  package.loaded["shell.pkgpicker"] = { run = function() return end }
  test("a picker returning nil still succeeds", pkg.runInstaller({}) == true)

  -- A picker that throws is a different failure and must stay one.
  package.loaded["shell.pkgpicker"] = { run = function() error("boom") end }
  local eok, eerr = pkg.runInstaller({})
  test("a throwing picker still fails", eok == false)
  test("...as an installer error", tostring(eerr):find("installer error", 1, true) ~= nil)

  package.loaded["shell.pkgpicker"] = realPicker
end

-- ── ...and the picker really does decline, not just a stub of it ────
-- The block above stubs the picker, so it pins runInstaller's half of
-- the contract and nothing more. This drives the REAL picker down the
-- empty-catalogue path -- which is the half that actually shipped
-- broken. It never reaches a GPU: the guard sits above all drawing,
-- and everything before it is a require the test can satisfy.
do
  local realPkg  = package.loaded["kernel.pkg"]
  local realUsr  = package.loaded["kernel.users"]
  local realFS   = package.loaded["kernel.fs"]
  local realSer  = package.loaded["kernel.serialize"]
  local realPick = package.loaded["shell.pkgpicker"]

  package.loaded["kernel.pkg"] = {
    installByName    = function() return false end,
    listAllAvailable = function() return {} end,   -- nothing anywhere
  }
  package.loaded["kernel.users"] = {
    TIER = { ADMIN = 2 },
    currentSession = function() return { tier = 3, user = "root" } end,
  }
  package.loaded["kernel.fs"] = {
    exists = function() return false end,
    list   = function() return {} end,
    mounts = function() return {} end,
    readFile = function() return nil end,
  }
  package.loaded["kernel.serialize"] = { decode = function() return nil end }
  package.loaded["shell.pkgpicker"] = nil        -- force a fresh load

  -- Swallow the picker's own stdout so the suite stays readable, but
  -- keep it: standalone use still wants those two lines.
  local realWrite = io.write
  local printed = {}
  io.write = function(x) printed[#printed + 1] = tostring(x) end

  local okLoad, picker = pcall(require, "shell.pkgpicker")
  local ranOk, res, why
  if okLoad and type(picker) == "table" and picker.run then
    ranOk, res, why = pcall(picker.run, {})
  end
  io.write = realWrite

  test("the real picker loads", okLoad and type(picker) == "table")
  test("...and does not throw on an empty catalogue", ranOk == true)
  test("...it returns false, not a bare return", res == false)
  test("...with a reason the caller can print", why == "no installable packages found")
  test("...while still saying so on its own screen",
    table.concat(printed):find("No installable packages found", 1, true) ~= nil)

  package.loaded["kernel.pkg"]       = realPkg
  package.loaded["kernel.users"]     = realUsr
  package.loaded["kernel.fs"]        = realFS
  package.loaded["kernel.serialize"] = realSer
  package.loaded["shell.pkgpicker"]  = realPick
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
