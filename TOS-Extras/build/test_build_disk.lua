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
--! Hand-kept, so it is checked below against the set the build actually
--! produces: stock, printer, write and intercom shipped for weeks without
--! being here, which meant "the published pack matches a fresh build" never
--! compared a byte of them.
local EXPECTED = { "tetris", "tape", "rc-pilot", "mouse",
                   "tape-authenticator", "cluster-manager", "cluster-master",
                   "blockfs", "mail", "calc", "snake", "ttt",
                   "stock", "printer", "write", "intercom", "selftest", "warhead",
                   "web", "rbmk-control", "cluster-storage" }

-- The other half of the same guarantee. build-disk.lua's SKIP table holds
-- packages below 1.0.0 back off the public pack, and an exclusion is only
-- safe if it is as hard to undo by accident as a drop is: without this, a
-- half-finished package rejoining the disk would ship silently and an
-- operator would tick it in the picker and get a skeleton.
-- Move a name from here to EXPECTED when it reaches 1.0.0.
local NOT_SHIPPED = {}

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

-- Every package the build put in the set must be one this file checks,
-- or a new add-on ships without the content comparison further down.
do
  local chunk = loadfile(OUT .. "/optutil-set.lua", "t", {})
  local okS, set = false, nil
  if chunk then okS, set = pcall(chunk) end
  local listed, unlisted = {}, nil
  for _, n in ipairs(EXPECTED) do listed[n] = true end
  for name in pairs((okS and type(set) == "table" and set.packages) or {}) do
    if not listed[name] then unlisted = unlisted or name end
  end
  test("every package in the set is listed in EXPECTED", nil, unlisted)
end

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

-- rc-pilot carries the robot's EEPROM image, minified from robot/ by the
-- assembler (MINIFIED in build-disk.lua). The commented source is ~6 KB,
-- a chip holds 4096 bytes, and the burnable image used to exist only if
-- someone ran strip.lua by hand.
do
  local img = readAll(OUT .. "/rc-pilot/usr/share/rc-pilot/eeprom-rc-pilot.lua")
  local src = readAll(root .. "/robot/eeprom-rc-pilot.lua")
  test("rc-pilot ships the robot EEPROM image", true, img ~= nil)
  test("...that fits a 4096-byte chip", true, img ~= nil and #img <= 4096)
  test("...and parses", true, img ~= nil and load(img, "=img", "t", {}) ~= nil)
  test("...minified from robot/, no comment left", true, img ~= nil and src ~= nil
    and #img < #src and not img:find("^%-%-") and not img:find("\n%s*%-%-"))
end

-- Every .lua the pack ships is minified the way the release tree is:
-- comments and whitespace out, then locals renamed and repeated strings
-- hoisted (TOS-Dev/build/minify_vars.lua). rc.d scripts stop after the
-- whitespace, because the kernel reads them as text before it runs them.
-- The pack used to ship source as written (blockfs.lua: 53 KB to require,
-- all of it embedded in the TBFS boot blob), then comment-stripped only.
do
  local strip, mv
  for _, cand in ipairs({ root .. "/../TOS-Dev/build/strip.lua", root .. "/../build/strip.lua",
      "../TOS-Dev/build/strip.lua", "build/strip.lua" }) do
    local c = loadfile(cand)
    if c then
      local ok, mod = pcall(c)
      if ok and type(mod) == "table" and type(mod.strip) == "function" then
        strip = mod
        local mc = loadfile((cand:gsub("strip%.lua$", "minify_vars.lua")))
        if mc then local okM, m2 = pcall(mc); if okM then mv = m2 end end
        break
      end
    end
  end
  test("strip.lua reachable (for the minifying checks)", true, strip ~= nil)
  test("minify_vars.lua reachable beside it", true, mv ~= nil)
  -- Comments left in a file; `unmarkedOnly` skips `--!`, which the
  -- whitespace pass keeps on purpose (the marker means "ship this").
  local function comments(x, unmarkedOnly)
    local n = 0
    for _, tok in ipairs(strip.tokenize(x)) do
      if (tok.type == "line_comment" or tok.type == "block_comment")
          and not (unmarkedOnly and tok.marked) then n = n + 1 end
    end
    return n
  end
  if strip and mv then
    for _, f in ipairs({
        { pkg = "blockfs", src = "/modules/blockfs/usr/lib/blockfs.lua", target = "/usr/lib/blockfs.lua" },
        { pkg = "tape", src = "/modules/tape/init.lua", target = "/usr/modules/tape/init.lua" },
        { pkg = "selftest", src = "/modules/selftest/usr/lib/selftest/92-term.lua",
          target = "/usr/lib/selftest/92-term.lua" } }) do
      local src = readAll(root .. f.src)
      local shipped = readAll(OUT .. "/" .. f.pkg .. f.target)
      if src and shipped then
        src = src:gsub("\r\n", "\n")
        local spaced = strip.strip(src, { minify = true })
        test(f.pkg .. ": ships " .. f.target .. " fully minified", true,
          shipped == mv.minify(spaced, f.target))
        test("...smaller than with whitespace alone", true, #shipped < #spaced)
        test("...no comment left in it", 0, comments(shipped))
      else
        test(f.pkg .. ": " .. f.target .. " found in the source and the pack", true, false)
      end
    end

    -- rc.d keeps its names and its strings: the peek reads them.
    local svcSrc = readAll(root .. "/cluster/storage-skeleton/etc/rc.d/cluster-storaged.lua")
    local svc = readAll(OUT .. "/cluster-storage/etc/rc.d/cluster-storaged.lua")
    test("cluster-storage's rc.d script ships", true, svcSrc ~= nil and svc ~= nil)
    if svcSrc and svc then
      test("...with the whitespace pass only, names and strings as written", true,
        svc == strip.strip(svcSrc:gsub("\r\n", "\n"), { minify = true }))
      test("...so `needs = \"net\"` reads as the peek expects", true,
        svc:find('needs = "net"', 1, true) ~= nil)
    end
  end

  local broken, commented, manifestComment, manifestUndecodable
  local serialize
  for _, cand in ipairs({ root .. "/../TOS-Dev/tos/kernel/serialize.lua",
      "../TOS-Dev/tos/kernel/serialize.lua", "../tos/kernel/serialize.lua" }) do
    local c = loadfile(cand)
    if c then local ok, m = pcall(c); if ok and type(m) == "table" then serialize = m break end end
  end
  for _, name in ipairs(EXPECTED) do
    local mSrc = readAll(OUT .. "/" .. name .. "/package.lua") or ""
    local chunk = load(mSrc, "=manifest", "t", {})
    local m = chunk and chunk() or {}
    -- The manifest ships minified too; pkg reads it with serialize.decode.
    if strip and comments(mSrc, true) > 0 then manifestComment = manifestComment or name end
    if serialize and type(serialize.decode(mSrc, { maxBytes = 64 * 1024 })) ~= "table" then
      manifestUndecodable = manifestUndecodable or name
    end
    for _, target in ipairs(m.files or {}) do
      if target:match("%.lua$") then
        local d = readAll(OUT .. "/" .. name .. target)
        if d and not load(d, "=" .. target, "t", {}) then broken = broken or (name .. target) end
        if d and strip and mv and not strip.kernelReadsSource(target) and comments(d) > 0 then
          commented = commented or (name .. target)
        end
      end
    end
  end
  test("every .lua in the pack parses", nil, broken)
  test("no fully minified .lua holds a comment", nil, commented)
  test("no manifest ships its ordinary comments", nil, manifestComment)
  test("kernel/serialize.lua reachable (for the decode check)", true, serialize ~= nil)
  test("every manifest decodes the way pkg reads it", nil, manifestUndecodable)
end

-- And a build whose image would not fit the chip is refused, not shipped.
do
  local big = OUT .. "-big"
  rmrf(big)
  local function mk(d)
    if WINDOWS then os.execute('mkdir "' .. d:gsub("/", "\\") .. '" >nul 2>nul')
    else os.execute('mkdir -p "' .. d .. '" 2>/dev/null') end
  end
  local function put(path, data)
    local f = io.open(path, "wb"); if f then f:write(data); f:close() end
  end
  mk(big .. "/modules/rc-pilot"); mk(big .. "/robot")
  for _, f in ipairs({ "package.lua", "init.lua" }) do
    put(big .. "/modules/rc-pilot/" .. f, readAll(root .. "/modules/rc-pilot/" .. f) or "")
  end
  -- A string literal, which no minifying pass shortens: ~2.4 KB more. (It
  -- was 200 `local x = 1` lines, which only failed for the right reason
  -- while size was checked before anything else: that is past Lua's 200
  -- locals per function, and the build now refuses a file that does not
  -- compile as written before it measures it.)
  put(big .. "/robot/eeprom-rc-pilot.lua",
    (readAll(root .. "/robot/eeprom-rc-pilot.lua") or "")
    .. '\nlocal padding = "' .. string.rep("x", 2400) .. '"\n')
  local log = big .. "/build.log"
  local cmd = string.format('lua "%s/build-disk.lua" "%s" "%s/out" --limit 0 >"%s" 2>&1',
    buildDir, big, big, log)
  local ok = os.execute(cmd)
  ok = (ok == true or ok == 0)
  local said = readAll(log) or ""
  test("an image over 4096 bytes fails the build", false, ok)
  test("...saying which file and why", true,
    said:find("eeprom-rc-pilot.lua", 1, true) ~= nil and said:find("4096-byte limit", 1, true) ~= nil)
  test("...and ships no package", false, exists(big .. "/out/rc-pilot/package.lua"))
  rmrf(big)
end

-- A manifest pkg cannot decode fails the build. selftest's description
-- was `"..." .. "..."`: load() evaluates that, pkg's data-only decoder
-- refuses it, and the pack built and was signed before make-repo-index
-- turned it away at publish time. The same scratch package builds with
-- one literal and fails with the concatenation, so the failure is the
-- expression and nothing else about the fixture.
do
  local tree = OUT .. "-decode"
  local function mk(d)
    if WINDOWS then os.execute('mkdir "' .. d:gsub("/", "\\") .. '" >nul 2>nul')
    else os.execute('mkdir -p "' .. d .. '" 2>/dev/null') end
  end
  local function put(path, data)
    local f = io.open(path, "wb"); if f then f:write(data); f:close() end
  end
  local function build(description)
    rmrf(tree)
    mk(tree .. "/modules/twopart")
    put(tree .. "/modules/twopart/init.lua", "return function() end\n")
    put(tree .. "/modules/twopart/package.lua", table.concat({
      "return {",
      '  name = "twopart", version = "1.0.0", kind = "command", category = "dev",',
      "  description = " .. description .. ",",
      '  files = { "/usr/modules/twopart/init.lua" },',
      '  commands = { twopart = "/usr/modules/twopart/init.lua" },',
      "}", "" }, "\n"))
    local log = tree .. "/build.log"
    local ok = os.execute(string.format('lua "%s/build-disk.lua" "%s" "%s/out" --limit 0 >"%s" 2>&1',
      buildDir, tree, tree, log))
    return (ok == true or ok == 0), readAll(log) or "", exists(tree .. "/out/twopart/package.lua")
  end
  local okLit, _, shippedLit = build('"one literal"')
  test("(control) a one-literal description builds", true, okLit and shippedLit)
  local okCat, said, shippedCat = build('"two " .. "halves"')
  test("a description built with .. fails the build", false, okCat)
  test("...saying pkg cannot read it, and where", true,
    said:find("pkg cannot read this manifest", 1, true) ~= nil and said:find("line 3", 1, true) ~= nil)
  test("...and ships no package", false, shippedCat)
  rmrf(tree)
end

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

-- ── --sign actually runs, end to end ─────────────────────────
-- Nothing exercised the signing path, so it broke unseen: ed25519.lua grew a
-- require of kernel.curve25519field (the field math, shared with x25519) and
-- both signers preloaded kernel.sha512 for it but not that, so the operator's
-- first `tos.py pack --sign` died with "kernel/ed25519.lua not found" -- a
-- pcall in loadKernelModule swallowing the real failure. A throwaway key, a
-- scratch directory, never dist/: this proves the loader wiring, not a pack.
do
  local OUT3 = root .. "/dist/.test-sign"
  rmrf(OUT3)
  local env = WINDOWS
    and 'set "TOS_SIGNING_PASSPHRASE=throwaway test passphrase, not a real key" && set "TOS_SIGNING_NAME=testsuite" && '
    or  "TOS_SIGNING_PASSPHRASE='throwaway test passphrase, not a real key' TOS_SIGNING_NAME=testsuite "
  local cmd = string.format('%slua "%s/build-disk.lua" "%s" "%s" --limit 0 --sign%s',
    env, buildDir, root, OUT3, WINDOWS and " >nul 2>nul" or " >/dev/null 2>&1")
  local ok = os.execute(cmd)
  test("a --sign build with a throwaway key succeeds", true, ok == true or ok == 0)
  test("...and leaves a signature beside a package's manifest", true,
    exists(OUT3 .. "/mouse/package.sig"))
  test("...including the browser (web joined the pack unsigned-until-now)", true,
    exists(OUT3 .. "/web/package.sig"))
  rmrf(OUT3)
end

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

    --! WAITING FOR THE OPERATOR'S SIGNATURE. Only the operator can sign the
    --! pack (`python tos.py pack --sign` asks for the passphrase), and they
    --! batch it: several package fixes land, then ONE signing. Until then the
    --! checked-in pack is the last signed one and correctly differs from a
    --! fresh build -- and this test was red for days at a time, which left
    --! every other commit in between ungated. A package named here may
    --! differ; the difference is printed as pending, not passed silently. A
    --! difference in any package NOT named still fails, and an entry whose
    --! files no longer differ fails too, so the signing that empties the
    --! reason also empties the list.
    local PENDING_RESIGN = {
      -- The operator re-signed the pack on 2026-10-24 at 23:01, minified the
      -- way the release is. Name a package here when a fix to it lands ahead
      -- of the next signing.
      ["mail"] = "1.0.1: both UIs close and cancel on the quit binding (keys set quit)",
      ["intercom"] = "1.0.2: the tab closes on the quit binding (keys set quit)",
      ["rbmk-control"] = "1.0.1: SKALA quits on ^Q / F10 / the quit binding, not only Q",
      ["blockfs"] = "1.2.2: _VERSION says the package's version (it said 1.2.0 in 1.2.1)",
      ["selftest"] = "1.0.1: check 95 tests the editor column model on the glass instead of skipping it",
    }

    if nShipped == 0 then
      print("  SKIP: no checked-in pack at dist/optional-utilities (run build-disk.lua)")
    else
      local differs, onlyFresh, onlyShipped = nil, nil, nil
      local pendingSeen = {}
      local function pkgOf(k) return (k:match("^([^/]+)/")) end
      for k, v in pairs(fresh) do
        if shipped[k] == nil then
          if PENDING_RESIGN[pkgOf(k)] then pendingSeen[pkgOf(k)] = true
          else onlyFresh = onlyFresh or k end
        elseif shipped[k] ~= v then
          if PENDING_RESIGN[pkgOf(k)] then pendingSeen[pkgOf(k)] = true
          else differs = differs or k end
        end
      end
      for k in pairs(shipped) do
        if fresh[k] == nil then
          if PENDING_RESIGN[pkgOf(k)] then pendingSeen[pkgOf(k)] = true
          else onlyShipped = onlyShipped or k end
        end
      end
      for name, why in pairs(PENDING_RESIGN) do
        if pendingSeen[name] then
          print("  PENDING RE-SIGN: " .. name .. " -- " .. why)
        end
        test("pending re-sign entry '" .. name .. "' still differs from the signed pack "
          .. "(remove it once the pack is signed)", true, pendingSeen[name] == true)
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
