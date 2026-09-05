-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: install.lua's disk detection + bootstrap.lua ║
-- ║                                                                ║
-- ║  Neither script is require()-able off-box (both are top-level ║
-- ║  chunks with real side effects the moment they run — term      ║
-- ║  clears, hardware surveys), so this pins them the same way     ║
-- ║  test_bios.lua and test_manifest_anchor.lua pin the EEPROM:     ║
-- ║  compile in text mode, and source-pattern checks against the   ║
-- ║  specific bugs/behaviors this pair is supposed to have.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_bootstrap.lua  (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end

print("=== install.lua + bootstrap.lua ===")
print()

local install = findUp("install.lua")
test("install.lua readable", install ~= nil)
local bootstrap = findUp("bootstrap.lua")
test("bootstrap.lua readable", bootstrap ~= nil)

if install then
  test("install.lua compiles (text mode)", (load(install, "=install.lua", "t")) ~= nil)
end
if bootstrap then
  test("bootstrap.lua compiles (text mode)", (load(bootstrap, "=bootstrap.lua", "t")) ~= nil)
end

-- ── findInstallDisk: explicit override + the /mnt/ assumption fix ──
-- A scripted/chain-loaded install (bootstrap.lua, or any future caller)
-- needs a way to name its source directory directly instead of relying
-- on path inference, and the inference path itself used to require a
-- literal /mnt/<name> prefix that broke for anything not mounted there.
if install then
  test("findInstallDisk takes an explicit source override",
    install:find("findInstallDisk(explicitSrc)", 1, true) ~= nil)
  test("the old hardcoded /mnt/<name> anchor is gone",
    install:find('"^(/mnt/[^/]+)"', 1, true) == nil)
  test("Method 1 now checks any containing directory, not just /mnt/",
    install:find('"^(.*)/[^/]+$"', 1, true) ~= nil)
  test("the main flow forwards its first CLI arg into findInstallDisk",
    install:find("findInstallDisk(args[1])", 1, true) ~= nil)
  test("Method 2's filesystem probes are pcall-guarded",
    install:find("local okE1, hasKernel = pcall(", 1, true) ~= nil)
end

-- ── bootstrap.lua: points at the right place, hands off the right way ──
if bootstrap then
  test("defaults to the canonical repo owner",
    bootstrap:find('"Evan450"', 1, true) ~= nil)
  test("defaults to the canonical repo name",
    bootstrap:find('"TOS-Terminal-Operating-System-"', 1, true) ~= nil)
  test("tries both the main and master branch conventions",
    bootstrap:find('{ "main", "master" }', 1, true) ~= nil)
  test("tries both a bare repo root and a TOS-Release subdir layout",
    bootstrap:find('{ "", "TOS-Release" }', 1, true) ~= nil)
  test("refuses to proceed without an Internet Card",
    bootstrap:find("No Internet Card found", 1, true) ~= nil)
  test("diagnoses a flat (structure-less) repo instead of just 404ing",
    bootstrap:find("FLAT layout", 1, true) ~= nil
      and bootstrap:find('"/system_manifest.lua"', 1, true) ~= nil)
  test("bounds a single downloaded file's size (OOM guard)",
    bootstrap:find("MAX_FILE_BYTES", 1, true) ~= nil)
  test("hands off via loadfile + pcall on the staged install.lua",
    bootstrap:find("loadfile(installPath)", 1, true) ~= nil)

  -- ── Download verification ────────────────────────────────────────
  -- The manifest carries a SHA-256 per entry; bootstrap must actually use
  -- them. Source-level pins, because bootstrap.lua is a top-level script
  -- with real side effects (it clears the screen and surveys hardware the
  -- moment it loads) and cannot be required into a harness.
  test("reads the manifest's hash field",
    bootstrap:find("entry.hash", 1, true) ~= nil)
  test("fetches the hasher before the payload",
    bootstrap:find("/tos/kernel/sha256.lua", 1, true) ~= nil)
  test("checks the hasher against its own manifest entry",
    bootstrap:find("does not match its own manifest entry", 1, true) ~= nil)
  test("verifies BEFORE writing to the staging tree",
    bootstrap:find("Verify BEFORE writing", 1, true) ~= nil)
  test("treats a digest mismatch as refusal, not a warning",
    bootstrap:find("DIGEST MISMATCH", 1, true) ~= nil
      and bootstrap:find("Refusing to install", 1, true) ~= nil)
  test("degrades honestly when a release ships no digests",
    bootstrap:find("ships no digests", 1, true) ~= nil)
  -- The claim has to stay calibrated: verifying downloads against a
  -- manifest fetched from the same host proves consistency, not
  -- provenance. If that ever gets overstated in the file, this fails.
  test("does not overstate what verification proves",
    bootstrap:find("does NOT prove the release is genuine", 1, true) ~= nil)
  test("passes the staging directory as install.lua's override arg",
    bootstrap:find("pcall(chunk, stagingDir)", 1, true) ~= nil)
end

-- ── safeToken: the actual behavior, not just its presence ──────────
if bootstrap then
  local safeSrc = bootstrap:match("(local function safeToken%(s%).-\nend)")
  test("found safeToken", safeSrc ~= nil)
  if safeSrc then
    local fn = load(safeSrc .. "\nreturn safeToken", "=safeToken", "t")
    test("safeToken compiles standalone", fn ~= nil)
    if fn then
      local safeToken = fn()
      test("accepts a plain repo owner", safeToken("Evan450") == true)
      test("accepts a branch/tag with dots and dashes", safeToken("v1.4.0-rc1") == true)
      test("accepts an owner/repo pair", safeToken("Evan450/TOS-Terminal-Operating-System-") == true)
      test("rejects embedded whitespace", safeToken("evil token") == false)
      test("rejects control characters", safeToken("bad\nurl") == false)
      test("rejects the empty string", safeToken("") == false)
      test("rejects a non-string", safeToken(nil) == false)
    end
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- The hasher sandbox, EXECUTED rather than grepped
-- ══════════════════════════════════════════════════════════════════════
-- Every other check in this file reads bootstrap.lua's text, and text is
-- exactly what could not catch this: the sandbox was `{}`, sha256.lua
-- loaded and returned a table quite happily because its body is all local
-- function definitions, and the install died on a real machine the first
-- time hex() reached for `string`. A missing global is not visible by
-- reading. So this pulls bootstrap's ACTUAL environment table out of the
-- file, loads the ACTUAL hasher into it, and hashes something.
do
  local bootstrapSrc = bootstrap
  local shaSrc       = findUp("tos/kernel/sha256.lua")
  test("bootstrap.lua and sha256.lua both readable",
    bootstrapSrc ~= nil and shaSrc ~= nil)

  if bootstrapSrc and shaSrc then
    -- %b{} matches the balanced braces, so a nested table cannot truncate it.
    local envExpr = bootstrapSrc:match("local HASHER_ENV = (%b{})")
    test("bootstrap declares a named HASHER_ENV the suite can reuse", envExpr ~= nil)

    if envExpr then
      local envChunk = load("return " .. envExpr, "=HASHER_ENV", "t")
      test("the environment table parses", envChunk ~= nil)
      local okEnv, env = false, nil
      if envChunk then okEnv, env = pcall(envChunk) end
      test("...and builds", okEnv and type(env) == "table")

      if okEnv and type(env) == "table" then
        -- The bug, stated as an assertion.
        test("the sandbox is not empty", next(env) ~= nil)
        test("it provides string (sha256 uses string.format/char/rep)",
          env.string ~= nil)
        test("it provides table (sha256 uses table.concat)", env.table ~= nil)

        -- Still a sandbox: downloaded code must not reach the machine.
        for _, forbidden in ipairs({ "load", "loadstring", "dofile", "require",
                                     "os", "io", "component", "computer", "fs" }) do
          test("the sandbox withholds " .. forbidden, env[forbidden] == nil)
        end

        -- The real thing, loaded the real way, actually hashing.
        local chunk = load(shaSrc, "=sha256", "t", env)
        test("sha256.lua loads inside that sandbox", chunk ~= nil)
        local okMod, mod = false, nil
        if chunk then okMod, mod = pcall(chunk) end
        test("...and returns a module", okMod and type(mod) == "table")

        if okMod and type(mod) == "table" and type(mod.hex) == "function" then
          -- Calling it is the whole point: loading proved nothing.
          local okHex, got = pcall(mod.hex, "abc")
          test("hex() RUNS in that sandbox (the bug: it did not)", okHex)
          test("and returns FIPS 180-4's SHA-256(\"abc\")",
            got == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
          local okEmpty, gotEmpty = pcall(mod.hex, "")
          test("and SHA-256(\"\")",
            okEmpty and gotEmpty ==
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        else
          test("sha256 module exposes hex()", false)
        end
      end
    end

    -- ── MAX_FILE_BYTES vs the actual release ──────────────────────
    --! The download cap was 96 KB and core.lua grew to 99,048 bytes, so
    --! every network install silently skipped the file holding most of
    --! the shell's commands. Nothing noticed, because the comment above
    --! the constant asserted "the largest individual TOS source file is
    --! well under this" and no code ever checked whether that was still
    --! true. This measures it.
    local capExpr = bootstrapSrc:match("MAX_FILE_BYTES%s*=%s*([%d%s%*]+)")
    test("bootstrap declares a download size cap", capExpr ~= nil)
    if capExpr then
      local capFn = load("return " .. capExpr, "=cap", "t")
      local cap = capFn and select(2, pcall(capFn)) or nil
      test("the cap is a number", type(cap) == "number")

      -- Measure the built release if it is there; the dev tree otherwise.
      local roots = { "../TOS-Release", "../../TOS-Release", "." }
      local biggest, biggestPath, scanned = 0, nil, 0
      local sep = package.config:sub(1, 1)
      for _, root in ipairs(roots) do
        local cmd = (sep == "\\")
          and ('dir /b /s "' .. root:gsub("/", "\\") .. '\\*.lua" 2>nul')
          or  ('find "' .. root .. '" -name "*.lua" 2>/dev/null')
        local pipe = io.popen(cmd)
        if pipe then
          for line in pipe:lines() do
            line = line:gsub("%s+$", "")
            local h = io.open(line, "rb")
            if h then
              local n = h:seek("end"); h:close()
              scanned = scanned + 1
              if n > biggest then biggest, biggestPath = n, line end
            end
          end
          pipe:close()
        end
        if scanned > 0 then break end
      end

      test("found a tree to measure against the cap", scanned > 0)
      if scanned > 0 and type(cap) == "number" then
        if biggest >= cap then
          print(string.format("    largest file %d bytes >= cap %d: %s",
            biggest, cap, tostring(biggestPath)))
        end
        test(string.format("every file fits under the cap (largest %d, cap %d)",
          biggest, cap), biggest < cap)
        -- Headroom, so the NEXT ordinary edit does not reintroduce this.
        test(string.format("...with room to grow (largest is %d%% of the cap)",
          math.floor(biggest / cap * 100)), biggest < cap * 0.75)
      end
    end

    test("an incomplete download refuses the install",
      bootstrapSrc:find("Refusing to install an incomplete release", 1, true) ~= nil)
    test("a successful install reclaims the staging copy",
      bootstrapSrc:find("Removed the staging copy", 1, true) ~= nil)

    -- Staging space. These are source-pattern checks and say so: the
    -- behaviour they guard needs a real machine with a real tmpfs to
    -- exercise, and pretending otherwise is what let the sandbox bug
    -- through. They catch the guards being DELETED, not them working.
    test("staging is chosen by free space, not hardcoded to /tmp",
      bootstrapSrc:find("spaceTotal", 1, true) ~= nil and
      bootstrapSrc:find("spaceUsed", 1, true) ~= nil)
    test("staging considers more than one candidate filesystem",
      bootstrapSrc:find("/home/tos%-netinstall") ~= nil)
    test("a full filesystem aborts instead of failing every file",
      bootstrapSrc:find("outOfSpace", 1, true) ~= nil)
    test("and the out-of-space message names space, not just the write",
      bootstrapSrc:find("OUT OF SPACE", 1, true) ~= nil)
    test("a failed netinstall does not leave the staging tree behind",
      bootstrapSrc:find("pcall(fs.remove, stagingDir)", 1, true) ~= nil)

    -- A long wait must LOOK like a wait, not like a hang. The probe used
    -- to print "probing main ... " and then go silent for however long
    -- the request took; the operator's only options were guess or reboot.
    test("httpGet accepts a wait tick", bootstrapSrc:find("onWait", 1, true) ~= nil)
    -- Parens escaped: unescaped, "tick()" is an empty capture group and
    -- the pattern matches nothing that looks like the code.
    test("the tick fires while waiting for bytes",
      bootstrapSrc:find("tick%(%)%s*pause%(0%)") ~= nil)
    test("the probe passes a ticker", bootstrapSrc:find("PROBE_RETRIES, tickDot", 1, true) ~= nil)
    test("dots are throttled, not one per read",
      bootstrapSrc:find("lastDot >= 0.3", 1, true) ~= nil)
    test("...and capped so they cannot wrap an 80-column line",
      bootstrapSrc:find("dots < 40", 1, true) ~= nil)
    test("a tick failure cannot take the install down",
      bootstrapSrc:find("pcall(onWait)", 1, true) ~= nil)

    -- The guard that turns a broken hasher into a refusal rather than a crash.
    test("bootstrap known-answer-tests the hasher before trusting it",
      bootstrapSrc:find("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        1, true) ~= nil)
    test("and the first hex() call is pcall-guarded",
      bootstrapSrc:find("pcall(mod.hex", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
