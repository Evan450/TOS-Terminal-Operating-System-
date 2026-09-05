-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the Release manifest's content digests        ║
-- ║                                                                ║
-- ║  kernel.verifySystem has read a per-entry `hash` field since    ║
-- ║  #SEC C1, but nothing wrote one, so `verify` was confirming     ║
-- ║  that files EXIST rather than that they are UNMODIFIED.         ║
-- ║  strip.lua now injects a SHA-256 over the emitted bytes.        ║
-- ║                                                                ║
-- ║  Two things have to hold, and the first one bit immediately:    ║
-- ║   1. The manifest must parse with REAL Lua. The first version   ║
-- ║      emitted `critical = false hash = "..."` with no comma --   ║
-- ║      a syntax error that serialize.decode's permissive parser   ║
-- ║      accepted, so it read back fine while init.lua, install.lua ║
-- ║      and bootstrap.lua (all load()) would have refused to boot. ║
-- ║   2. Every digest must match the file actually shipped.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_manifest_digests.lua   (from TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end

print("=== Release manifest digests ===")
print()

-- The Release tree is a build artifact and a sibling of this one. Absent
-- means "not built here" (a fresh clone, CI without a build step), which
-- is not a failure of the code under test.
local REL = nil
for _, base in ipairs({ "../TOS-Release", "TOS-Release", "../../TOS-Release" }) do
  if readAll(base .. "/tos/system_manifest.lua") then REL = base break end
end
if not REL then
  print("  SKIP: no built TOS-Release (run build/build-release.sh)")
  print("Results: 0 passed, 0 failed")
  print("All tests passed.")
  return true
end

local src = readAll(REL .. "/tos/system_manifest.lua")

--! REAL Lua, deliberately. Reading this back with kernel.serialize would
--! test the forgiving parser rather than the one that actually has to
--! load it at boot, and that is exactly how the missing comma survived.
local fn, err = load(src, "=manifest", "t", {})
test("the Release manifest parses with real Lua" .. (fn and "" or (" -- " .. tostring(err))),
  fn ~= nil)
if not fn then
  print()
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***")
  return false
end

local okRun, manifest = pcall(fn)
test("...and returns a table", okRun and type(manifest) == "table")
if not okRun or type(manifest) ~= "table" then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***")
  return false
end

-- The same pure SHA-256 the build used.
local sha
for _, cand in ipairs({ "tos/kernel/sha256.lua", REL .. "/tos/kernel/sha256.lua" }) do
  local chunk = loadfile(cand)
  if chunk then local ok, m = pcall(chunk); if ok then sha = m break end end
end
test("kernel.sha256 loadable", sha ~= nil and sha.hex ~= nil)

local withHash, malformed, mismatched, unreadable = 0, nil, nil, 0
for _, e in ipairs(manifest) do
  if e.hash then
    withHash = withHash + 1
    if type(e.hash) ~= "string" or #e.hash ~= 64 or e.hash:find("[^%x]") then
      malformed = malformed or e.path
    elseif sha and sha.hex then
      local body = readAll(REL .. e.path)
      if not body then unreadable = unreadable + 1
      elseif sha.hex(body) ~= e.hash then mismatched = mismatched or e.path end
    end
  end
end

-- Exactly one entry is expected to lack a digest: the manifest itself.
-- A file cannot contain its own hash, so that one is vouched for by the
-- EEPROM anchor instead. Anything ELSE missing a digest is a real gap.
local noHash = {}
for _, e in ipairs(manifest) do
  if not e.hash then noHash[#noHash + 1] = e.path end
end
test(("every entry carries a digest except the manifest (%d/%d)")
  :format(withHash, #manifest),
  withHash == #manifest - 1 and #manifest > 0)
test("the only entry without one is the manifest itself" ..
  ((#noHash == 1 and noHash[1] == "/tos/system_manifest.lua") and ""
    or (" -- got: " .. table.concat(noHash, ", "))),
  #noHash == 1 and noHash[1] == "/tos/system_manifest.lua")
test("no malformed digest" .. (malformed and (" -- " .. malformed) or ""), malformed == nil)
test("every file the manifest lists is readable in the Release tree",
  unreadable == 0)
if sha and sha.hex then
  test("every digest matches the shipped bytes" ..
    (mismatched and (" -- " .. mismatched) or ""), mismatched == nil)
end

-- The Dev manifest is deliberately digest-free: its files differ from the
-- stripped ones, so a hash taken here would be wrong for every release,
-- and regenerating it on every source edit would dirty the tree constantly.
do
  local devSrc = readAll("tos/system_manifest.lua")
  if devSrc then
    local devFn = load(devSrc, "=devmanifest", "t", {})
    test("the Dev manifest also parses with real Lua", devFn ~= nil)
    if devFn then
      local okD, devMan = pcall(devFn)
      local anyHash = false
      if okD and type(devMan) == "table" then
        for _, e in ipairs(devMan) do if e.hash then anyHash = true end end
      end
      test("the Dev manifest carries no digests (release-only, by design)", not anyHash)
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
