-- ╔══════════════════════════════════════════════════════╗
-- ║  Test: Optional Utilities disk assembler               ║
-- ║                                                        ║
-- ║  Runs build-disk.lua into scratch dirs and verifies:    ║
-- ║   - every disk package assembles with its manifest      ║
-- ║     name as the dir name (pkg's H-20 check)             ║
-- ║   - every manifest files[] target exists in the output  ║
-- ║     (mirror/flat/legacy resolution all worked)           ║
-- ║   - the set manifest + README are on the disk root       ║
-- ║   - stale output files are cleaned between builds        ║
-- ║   - --install replays a single-disk build                ║
-- ║   - --limit splits into diskN dirs (each with the        ║
-- ║     picker, every package exactly once) and refuses      ║
-- ║     both an impossible limit and a multi-disk --install  ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua build/test_build_disk.lua   (from TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "build/test_build_disk.lua"
local buildDir = here:gsub("[/\\][^/\\]*$", "")
local root = buildDir:gsub("[/\\][^/\\]*$", "")
if root == "" or root == buildDir then root = "." end

local WINDOWS = package.config:sub(1, 1) == "\\"
local function exists(p)
  local h = io.open(p, "rb"); if h then h:close(); return true end; return false
end
local function rmrf(p)
  if WINDOWS then
    os.execute('rmdir /s /q "' .. p:gsub("/", "\\") .. '" >nul 2>nul')
  else
    os.execute('rm -rf "' .. p .. '" 2>/dev/null')
  end
end
local function run(extra, quiet)
  local cmd = string.format('lua "%s/build-disk.lua" "%s" %s', buildDir, root, extra)
  if quiet ~= false then cmd = cmd .. (WINDOWS and " >nul 2>nul" or " >/dev/null 2>&1") end
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local OUT  = root .. "/dist/.test-build"
local OUT2 = root .. "/dist/.test-install"
rmrf(OUT); rmrf(OUT2)

-- Every package that must ship. Deliberately an explicit list rather than
-- "whatever discovery found": that way a package silently dropping off the
-- disk (renamed dir, broken manifest) FAILS here instead of quietly
-- shrinking the product.
local EXPECTED = { "tetris", "tape", "rc-pilot", "mouse",
                   "tape-authenticator", "cluster-manager", "cluster-master",
                   "blockfs", "mail", "calc", "snake", "ttt" }

-- The other half of the same guarantee. build-disk.lua's SKIP table holds
-- packages below 1.0.0 back off the public pack, and an exclusion is only
-- safe if it is as hard to undo by accident as a drop is: without this, a
-- half-finished package rejoining the disk would ship silently and an
-- operator would tick it in the picker and get a skeleton.
-- Move a name from here to EXPECTED when it reaches 1.0.0.
local NOT_SHIPPED = { "cluster-storage", "rbmk-control" }

-- The pure SHA-256 the build uses; loaded from the sibling TOS-Dev tree so
-- the test can independently recompute each hash.
local sha256
for _, cand in ipairs({ root .. "/../TOS-Dev/tos/kernel/sha256.lua",
    "../TOS-Dev/tos/kernel/sha256.lua", "TOS-Dev/tos/kernel/sha256.lua",
    "../tos/kernel/sha256.lua" }) do
  local chunk = loadfile(cand)
  if chunk then local ok, m = pcall(chunk); if ok then sha256 = m break end end
end
local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local d = h:read("*a"); h:close(); return d
end

print("=== build-disk Tests ===")
print()
test("sha256 module loadable (for hash checks)", true, sha256 ~= nil)

-- ── Single-disk build ────────────────────────────────────────
-- `--limit 0` (unlimited) forces the flat one-disk layout so the
-- per-package assembly assertions below have a stable shape to check.
-- This USED to be the default build, but the add-on set has outgrown a
-- 512K floppy — the default now splits, which the multi-disk section
-- covers and the assertion right after this one pins.
test("assembler exits cleanly", true, run('"' .. OUT .. '" --limit 0'))
-- The disk no longer carries a picker copy (it moved into the base
-- image); it carries the SET MANIFEST that identifies it as a set, and a
-- README naming the command to run.
test("set manifest on disk root", true, exists(OUT .. "/optutil-set.lua"))
test("README on disk root", true, exists(OUT .. "/README.txt"))
test("no picker copy shipped", false, exists(OUT .. "/install.lua"))

for _, name in ipairs(EXPECTED) do
  local mpath = OUT .. "/" .. name .. "/package.lua"
  test(name .. ": manifest present", true, exists(mpath))
  local chunk = loadfile(mpath)
  local m = chunk and chunk() or nil
  test(name .. ": dir matches manifest name (H-20)", name, m and m.name)
  local missing = nil
  for _, target in ipairs((m and m.files) or {}) do
    if not exists(OUT .. "/" .. name .. target) then
      missing = missing or target
    end
  end
  test(name .. ": all files[] targets assembled", nil, missing)

  -- #SEC — the dist manifest MUST carry a correct SHA-256 for every file,
  -- or pkg.install (reject-unverified-by-default) would refuse the disk.
  if sha256 then
    test(name .. ": manifest declares a hashes table", "table",
      type(m and m.hashes))
    local badHash = nil
    for _, target in ipairs((m and m.files) or {}) do
      local data = readAll(OUT .. "/" .. name .. target)
      local want = data and sha256.hex(data)
      local got = m.hashes and m.hashes[target]
      if got ~= want then badHash = badHash or target end
    end
    test(name .. ": every file hash matches its contents", nil, badHash)
  end
end

-- tape lives at its renamed path, with the legacy path gone.
test("tape at /usr/modules/tape/", true,
  exists(OUT .. "/tape/usr/modules/tape/init.lua"))
test("no stale /usr/modules/tape-storage/", false,
  exists(OUT .. "/tape/usr/modules/tape-storage/init.lua"))

-- ── Output cleaning between builds ───────────────────────────
local stale = OUT .. "/tape/usr/modules/left-behind.lua"
local h = io.open(stale, "wb")
test("(setup) stale file plantable", true, h ~= nil)
if h then h:write("stale"); h:close() end
test("(setup) stale file planted", true, exists(stale))
test("rebuild exits cleanly", true, run('"' .. OUT .. '" --limit 0'))
test("rebuild removes stale output files", false, exists(stale))

-- ── --install replay (single disk) ───────────────────────────
test("--install build ok", true,
  run('"' .. OUT .. '" --limit 0 --install "' .. OUT2 .. '"'))
test("--install copied the set manifest", true, exists(OUT2 .. "/optutil-set.lua"))
test("--install copied a package file", true,
  exists(OUT2 .. "/mouse/usr/lib/mouse.lua"))

-- ── The DEFAULT build now needs more than one floppy ─────────
-- The add-on set outgrew a 512K floppy once calc/games/mail/rbmk-control
-- joined. That's expected — but it must SPLIT, never silently truncate,
-- so pin it: a default build produces diskN dirs and no flat root picker.
do
  rmrf(OUT)
  test("default build exits cleanly", true, run('"' .. OUT .. '"'))
  local splitNow = exists(OUT .. "/disk1/optutil-set.lua")
  test("default build splits across floppies", true, splitNow)
  test("...with no flat set manifest at the root", false,
    exists(OUT .. "/optutil-set.lua"))
  if splitNow then
    -- Nothing may be lost to the split: every package lands somewhere.
    local seen = {}
    for d = 1, 9 do
      if not exists(OUT .. "/disk" .. d .. "/optutil-set.lua") then break end
      for _, name in ipairs(EXPECTED) do
        if exists(OUT .. "/disk" .. d .. "/" .. name .. "/package.lua") then
          seen[name] = true
        end
      end
    end
    local lost = nil
    for _, name in ipairs(EXPECTED) do
      if not seen[name] then lost = lost or name end
    end
    test("default build ships every package", nil, lost)

    -- ...and ships nothing that SKIP holds back.
    local leaked = nil
    for _, name in ipairs(NOT_SHIPPED) do
      for d = 1, 9 do
        if exists(OUT .. "/disk" .. d .. "/" .. name .. "/package.lua") then
          leaked = leaked or name
        end
      end
    end
    test("default build ships no pre-1.0 package", nil, leaked)

    -- The set manifest drives the picker, so a held-back package must not
    -- be advertised there either -- otherwise it lists as "not on any
    -- installed disk", which reads as a missing floppy rather than as a
    -- deliberate omission. That was the reported symptom.
    local advertised = nil
    for d = 1, 9 do
      local setPath = OUT .. "/disk" .. d .. "/optutil-set.lua"
      if not exists(setPath) then break end
      local fh = io.open(setPath, "r")
      if fh then
        local body = fh:read("*a"); fh:close()
        for _, name in ipairs(NOT_SHIPPED) do
          if body:find('"' .. name .. '"', 1, true) then advertised = advertised or name end
        end
      end
    end
    test("the set manifest does not advertise a held-back package", nil, advertised)

    -- ── The CHECKED-IN pack must equal a fresh build ────────────────
    --! dist/optional-utilities is what gets published, and it is a build
    --! artifact: edit a package and forget to rebuild, and the pack ships
    --! the old bytes with a manifest hash computed over those old bytes,
    --! so the installer verifies them as correct on arrival. That exact
    --! thing happened -- a blockfs fix sat in source while the pack still
    --! carried the pre-fix file.
    --!
    --! publish.ps1 guards it by comparing mtimes, which is a proxy: touch
    --! a file and it looks stale, rewrite one byte-identically and it
    --! looks fresh. This compares CONTENT, and does it by diffing the
    --! fresh build we just made against the checked-in one, so the source
    --! resolution logic is the builder's own rather than a second copy
    --! here that could drift from it.
    --!
    --! Keyed by "<pkg>/<path>" rather than by disk, so a change in how
    --! the set splits across floppies is not reported as a content
    --! difference.
    local function collect(dir)
      local map = {}
      for d = 1, 9 do
        local base = dir .. "/disk" .. d
        if not exists(base .. "/optutil-set.lua") then break end
        for _, name in ipairs(EXPECTED) do
          local mpath = base .. "/" .. name .. "/package.lua"
          local man = readAll(mpath)
          if man then
            map[name .. "/package.lua"] = man
            for target in man:gmatch('%["(/[^"]+)"%]%s*=%s*"%x+"') do
              local body = readAll(base .. "/" .. name .. target)
              if body then map[name .. target] = body end
            end
          end
        end
      end
      return map
    end

    local fresh = collect(OUT)
    local shipped = collect(root .. "/dist/optional-utilities")
    local nFresh = 0; for _ in pairs(fresh) do nFresh = nFresh + 1 end
    local nShipped = 0; for _ in pairs(shipped) do nShipped = nShipped + 1 end

    if nShipped == 0 then
      print("  SKIP: no checked-in pack at dist/optional-utilities (run build-disk.lua)")
    else
      local differs, onlyFresh, onlyShipped = nil, nil, nil
      for k, v in pairs(fresh) do
        if shipped[k] == nil then onlyFresh = onlyFresh or k
        elseif shipped[k] ~= v then differs = differs or k end
      end
      for k in pairs(shipped) do
        if fresh[k] == nil then onlyShipped = onlyShipped or k end
      end
      test(("the published pack matches a fresh build (%d files)"):format(nFresh),
        nil, differs)
      test("no file in the fresh build is missing from the published pack",
        nil, onlyFresh)
      test("the published pack ships nothing the build does not produce",
        nil, onlyShipped)
    end
  end
end

-- ── Multi-disk split ─────────────────────────────────────────
-- SPLIT_LIMIT has to be small enough to force a split (the whole set is
-- ~700K) but large enough to still hold the biggest single package plus a
-- disk's fixed overhead — the installer AND the set manifest, both written
-- to every disk. It was 160K, which stopped fitting when the picker grew a
-- detail pane and a multi-disk install flow; a limit below the largest
-- package is a legitimate build ERROR, not a split, so the test was
-- asserting the wrong thing rather than catching a regression.
local SPLIT_LIMIT = "320K"
rmrf(OUT)
test("split build (" .. SPLIT_LIMIT .. ") exits cleanly", true,
  run('"' .. OUT .. '" --limit ' .. SPLIT_LIMIT))
test("split: no flat set manifest at root", false, exists(OUT .. "/optutil-set.lua"))
test("split: disk1 exists", true, exists(OUT .. "/disk1/optutil-set.lua"))
test("split: disk2 exists", true, exists(OUT .. "/disk2/optutil-set.lua"))
do
  -- Every expected package appears on exactly one disk.
  local count = {}
  for d = 1, 9 do
    if not exists(OUT .. "/disk" .. d .. "/optutil-set.lua") then break end
    for _, name in ipairs(EXPECTED) do
      if exists(OUT .. "/disk" .. d .. "/" .. name .. "/package.lua") then
        count[name] = (count[name] or 0) + 1
      end
    end
  end
  local bad = nil
  for _, name in ipairs(EXPECTED) do
    if count[name] ~= 1 then bad = bad or (name .. "=" .. tostring(count[name])) end
  end
  test("split: every package on exactly one disk", nil, bad)
end

-- ── Refusals ─────────────────────────────────────────────────
test("impossible limit (4K) refused", false, run('"' .. OUT .. '" --limit 4K'))
test("--install refused for a multi-disk build", false,
  run('"' .. OUT .. '" --limit ' .. SPLIT_LIMIT .. ' --install "' .. OUT2 .. '"'))

rmrf(OUT); rmrf(OUT2)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
