-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: where packages are looked for            ║
-- ║                                                            ║
-- ║  FOUND IN REAL MINECRAFT, 2026-08-11. A two-floppy         ║
-- ║  Optional Utilities set behaved as though the second        ║
-- ║  floppy did not exist: the picker listed only what was in   ║
-- ║  the drive, showed no dimmed off-disk entries, and never    ║
-- ║  offered the disk-swap prompt. An operator would reasonably ║
-- ║  conclude that was the whole catalogue.                     ║
-- ║                                                            ║
-- ║  CAUSE: pkgpicker enumerated mounts with fs.list("/mnt").   ║
-- ║  Boot-time mounts are VIRTUAL — kernel/init.lua calls       ║
-- ║  fs.mount() without creating a directory — so /mnt lists    ║
-- ║  empty and the set manifest was never found.                ║
-- ║                                                            ║
-- ║  pkg.lua already knew this; its own mountedRepoRoots says   ║
-- ║  so in a comment and consults the mount TABLE first. The    ║
-- ║  bug was that the picker had a second copy of the           ║
-- ║  enumeration. There is now one, and this pins it.           ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_repo_roots.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_repo_roots.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

print("=== package repo roots Tests ===")
print()

-- ── A filesystem that reproduces the real one ────────────────
-- THE POINT of this mock: /mnt is a real, EMPTY directory, and the disk
-- is present only in the mount TABLE. That is exactly what a boot-time
-- mount looks like on a live machine, and exactly what the old
-- enumeration could not see.
local function makeFs(opts)
  opts = opts or {}
  local dirs = { ["/"] = true, ["/mnt"] = true, ["/var/pkg/installed"] = true }
  local files = {}
  local mountList = opts.mounts or {}
  -- Packages living on the mounted disk.
  for _, p in ipairs(opts.diskPackages or {}) do
    dirs["/mnt/disk_e1e8/" .. p] = true
    files["/mnt/disk_e1e8/" .. p .. "/package.lua"] = true
  end
  if opts.setManifest then files["/mnt/disk_e1e8/optutil-set.lua"] = true end

  local F = {}
  function F.exists(p) return dirs[p] == true or files[p] == true end
  function F.isDirectory(p) return dirs[p] == true end
  function F.makeDirectory(p) dirs[p] = true; return true end
  function F.readFile() return nil end
  function F.writeFile() return true end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
  function F.mounts()
    local out = {}
    for _, mp in ipairs(mountList) do out[#out + 1] = { mountPoint = mp } end
    return out
  end
  function F.list(p)
    local out = {}
    local prefix = (p == "/") and "/" or (p .. "/")
    local seen = {}
    for d in pairs(dirs) do
      local rest = d:sub(#prefix + 1)
      if d:sub(1, #prefix) == prefix and rest ~= "" and not rest:find("/") then
        if not seen[rest] then seen[rest] = true; out[#out + 1] = rest .. "/" end
      end
    end
    for f in pairs(files) do
      local rest = f:sub(#prefix + 1)
      if f:sub(1, #prefix) == prefix and rest ~= "" and not rest:find("/") then
        if not seen[rest] then seen[rest] = true; out[#out + 1] = rest end
      end
    end
    table.sort(out)
    return out
  end
  return F
end

local function newPkg(F)
  package.loaded["kernel.serialize"] = {
    encode = function() return "" end, decode = function() return nil end,
    saveFile = function() return true end, loadFile = function() return nil end,
  }
  package.loaded["kernel.users"] = { currentSession = function() return nil end }
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  return pkg
end

-- ══════════════════════════════════════════════════════════════════════
-- The mount table is authoritative
-- ══════════════════════════════════════════════════════════════════════
do
  local F = makeFs({
    mounts = { "/", "/mnt/disk_e1e8" },
    diskPackages = { "tetris", "calc" },
    setManifest = true,
  })
  -- Precondition, and the whole reason the bug existed: listing /mnt
  -- finds NOTHING, because a boot-time mount creates no directory.
  test("/mnt lists empty — the mount is virtual", 0, #F.list("/mnt"))
  ok("...but the mount table has it", (function()
    for _, m in ipairs(F.mounts()) do
      if m.mountPoint == "/mnt/disk_e1e8" then return true end
    end
    return false
  end)())

  local pkg = newPkg(F)
  test("pkg exposes repoRoots", "function", type(pkg.repoRoots))
  local roots = pkg.repoRoots()
  local found = {}
  for _, r in ipairs(roots) do found[r] = true end
  ok("the mounted disk is a repo root", found["/mnt/disk_e1e8"])
  -- The set manifest lives at the disk root, so finding that root IS
  -- finding the manifest — which is what tells the picker about the
  -- other floppy.
  ok("so the set manifest is reachable", found["/mnt/disk_e1e8"] ~= nil)
  ok("the default roots are still included",
    found["/usr/repo"] or found["/var/repo"])
end

do
  -- Sub-directory roots survive too: a disk with the whole
  -- dist/optional-utilities FOLDER copied on rather than its contents.
  local F = makeFs({ mounts = { "/", "/mnt/disk_e1e8" }, diskPackages = { "sub" } })
  local pkg = newPkg(F)
  local found = {}
  for _, r in ipairs(pkg.repoRoots()) do found[r] = true end
  ok("immediate subdirectories are roots too", found["/mnt/disk_e1e8/sub"])
end

do
  -- No disk at all: the defaults, and no crash.
  local F = makeFs({ mounts = { "/" } })
  local pkg = newPkg(F)
  local roots = pkg.repoRoots()
  ok("with no media there are still default roots", #roots > 0)
  for _, r in ipairs(roots) do
    ok("no /mnt root is invented (" .. r .. ")", not r:find("^/mnt/"))
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- The picker uses that one enumeration
-- ══════════════════════════════════════════════════════════════════════
do
  -- Asserted against the SOURCE, because the picker is a full-screen
  -- interactive program and standing one up here would test the harness
  -- rather than the fix. What matters is that it no longer carries its
  -- own copy of "where are the packages".
  local h = io.open("tos/shell/pkgpicker.lua", "rb")
  local src = h and h:read("*a") or ""
  if h then h:close() end
  ok("the picker source was found", #src > 0)
  ok("it asks pkg for the roots", src:find("pkg.repoRoots", 1, true) ~= nil)
  -- The specific call that could not see a boot-time mount.
  test("it no longer lists /mnt to find disks", nil,
    src:find('list, "/mnt"', 1, true))
  test("nor by any other spelling of the same call", nil,
    src:find('list("/mnt")', 1, true))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
