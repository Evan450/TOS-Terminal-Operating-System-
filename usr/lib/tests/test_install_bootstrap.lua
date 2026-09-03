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

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
