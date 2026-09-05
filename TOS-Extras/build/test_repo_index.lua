-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the Optional Utilities remote index           ║
-- ║                                                                ║
-- ║  programs.cfg is what `pkg fetch` reads over an internet card,  ║
-- ║  and it is PUBLISHED -- so an index that advertises a file the  ║
-- ║  published tree does not have is a download that fails on       ║
-- ║  someone else's machine, where we cannot see it. Everything     ║
-- ║  here is checkable from the built tree, so it is checked.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua build/test_repo_index.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local root = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]+$") or "."
root = root .. "/.."
local DIST = root .. "/dist/optional-utilities"

local function readAll(p)
  local fh = io.open(p, "rb"); if not fh then return nil end
  local s = fh:read("*a"); fh:close(); return s
end

print("=== Optional Utilities remote index ===")
print()

local idxSrc = readAll(DIST .. "/programs.cfg")
if not idxSrc then
  print("  SKIP: no built pack (run: lua build/build-disk.lua && lua build/make-repo-index.lua)")
  print("Results: 0 passed, 0 failed")
  print("All tests passed.")
  return true
end

package.path = root .. "/../TOS-Dev/tos/?.lua;" .. package.path
local okS, serialize = pcall(require, "kernel.serialize")
-- Same pure SHA-256 the builder used to compute the manifest hashes.
local okH, sha256 = pcall(require, "kernel.sha256")
if not okH then sha256 = nil end
test("kernel.serialize loads from the sibling TOS-Dev tree", okS)
if not okS then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***")
  return false
end

-- The decoder pkgremote actually uses. If this cannot read the index,
-- no amount of it looking right in an editor matters.
local index, dErr = serialize.decode(idxSrc, { maxBytes = 512 * 1024 })
test("the real decoder parses programs.cfg" .. (index and "" or " (" .. tostring(dErr) .. ")"),
  type(index) == "table")
if type(index) ~= "table" then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***")
  return false
end

local setSrc = readAll(DIST .. "/disk1/optutil-set.lua")
local set = setSrc and serialize.decode(setSrc, { maxBytes = 256 * 1024 })
test("the set manifest decodes", type(set) == "table" and type(set.packages) == "table")

-- Every shipped package is fetchable, and nothing else is.
if type(set) == "table" and type(set.packages) == "table" then
  local missing, extra = nil, nil
  for name in pairs(set.packages) do
    if type(index[name]) ~= "table" then missing = missing or name end
  end
  for name in pairs(index) do
    if type(set.packages[name]) ~= "table" then extra = extra or name end
  end
  test("every package on the disks is in the index" ..
    (missing and (" (missing " .. missing .. ")") or ""), missing == nil)
  test("the index advertises nothing that is not on a disk" ..
    (extra and (" (extra " .. extra .. ")") or ""), extra == nil)
end

-- Held back by build-disk.lua's SKIP: pre-1.0 packages must not be
-- reachable by `pkg fetch` either. The disk and the network are two doors
-- to the same set; locking one is not locking the set.
for _, name in ipairs({ "cluster-storage", "rbmk-control" }) do
  test("held-back package is not fetchable: " .. name, index[name] == nil)
end

-- Every advertised source path must exist in the published tree, and be
-- fetchable at all: pkgremote REFUSES an OPPM ':' directory-copy entry.
local badPath, ghost, ghostCount = nil, nil, 0
for name, entry in pairs(index) do
  local meta = set and set.packages and set.packages[name]
  local disk = meta and tonumber(meta.disk) or 1
  if type(entry.files) ~= "table" then
    badPath = badPath or (name .. ": no files table")
  else
    for src in pairs(entry.files) do
      if src:sub(1, 1) == ":" then
        badPath = badPath or (name .. ": OPPM dir-copy entry " .. src)
      elseif src:find("%.%.") then
        badPath = badPath or (name .. ": path escape " .. src)
      elseif not readAll(string.format("%s/disk%d/%s", DIST, disk, src)) then
        ghostCount = ghostCount + 1
        ghost = ghost or (name .. ": " .. src)
      end
    end
  end
end
test("no unfetchable path shapes" .. (badPath and (" (" .. badPath .. ")") or ""), badPath == nil)
test("every advertised file exists in the published tree" ..
  (ghost and (" (" .. ghostCount .. " missing, e.g. " .. ghost .. ")") or ""), ghost == nil)

-- ── The bytes must survive the trip through git ────────────────────
--! A CRLF anywhere in the pack silently breaks `pkg fetch`. The build
--! hashes the bytes it writes; publishing puts them through git, which
--! normalises text to LF in the stored blob; raw.githubusercontent.com
--! then serves LF bytes against a manifest hash computed over CRLF ones,
--! and pkg refuses the install. It shipped that way once -- 39 of 59
--! files -- and was invisible locally, because a physical floppy carries
--! the manifest and the files together unnormalised and verifies fine.
--! The disk path passing is exactly why this needs its own assertion.
do
  local crlf = nil
  for name, entry in pairs(index) do
    local meta = set and set.packages and set.packages[name]
    local disk = meta and tonumber(meta.disk) or 1
    if type(entry.files) == "table" then
      for src in pairs(entry.files) do
        local body = readAll(string.format("%s/disk%d/%s", DIST, disk, src))
        if body and body:find("\r") then crlf = crlf or src end
      end
    end
  end
  test("no CRLF in the published pack (git would rewrite it and break the hashes)"
    .. (crlf and (" -- " .. crlf) or ""), crlf == nil)
end

-- ── Manifest hashes describe the bytes actually shipped ────────────
-- The other half of the same guarantee: even with line endings right, a
-- hash recorded over different bytes than the ones on disk fails on the
-- installing machine, where we cannot see it.
do
  local mismatch, checked = nil, 0
  for name, entry in pairs(index) do
    local meta = set and set.packages and set.packages[name]
    local disk = meta and tonumber(meta.disk) or 1
    local manSrc = readAll(string.format("%s/disk%d/%s/package.lua", DIST, disk, name))
    local man = manSrc and serialize.decode(manSrc, { maxBytes = 256 * 1024 })
    if type(man) == "table" and type(man.hashes) == "table" then
      for target, want in pairs(man.hashes) do
        local body = readAll(string.format("%s/disk%d/%s%s", DIST, disk, name, target))
        if body then
          checked = checked + 1
          if sha256 and sha256.hex then
            if sha256.hex(body) ~= want then mismatch = mismatch or (name .. target) end
          end
        end
      end
    end
  end
  if sha256 and sha256.hex then
    test(("every manifest hash matches the shipped bytes (%d checked)"):format(checked)
      .. (mismatch and (" -- " .. mismatch) or ""), mismatch == nil and checked > 0)
  else
    print("  SKIP: kernel.sha256 has no sum(); cannot verify hashes here")
  end
end

-- ── A signature on disk must also be advertised ────────────────────
--! pkgremote downloads only what the index lists, and pkg.install looks
--! for the .sig beside the manifest. So a signature that exists in the
--! built pack but is missing from programs.cfg produces a package that
--! is signed on the floppy and arrives UNSIGNED over the network -- and
--! with `pkg trust require on` that is the difference between installing
--! and being refused, with nothing to tell the operator which half broke.
--! Signing is opt-in, so an unsigned pack is fine; a half-advertised one
--! is not.
do
  local unadvertised, sigCount = nil, 0
  for name, entry in pairs(index) do
    local meta = set and set.packages and set.packages[name]
    local disk = meta and tonumber(meta.disk) or 1
    local sigRel = name .. "/package.sig"
    if readAll(string.format("%s/disk%d/%s", DIST, disk, sigRel)) then
      sigCount = sigCount + 1
      if type(entry.files) ~= "table" or entry.files[sigRel] == nil then
        unadvertised = unadvertised or sigRel
      end
    end
  end
  if sigCount > 0 then
    test(("every built signature is advertised (%d signed)"):format(sigCount)
      .. (unadvertised and (" -- " .. unadvertised) or ""), unadvertised == nil)
  else
    print("  SKIP: pack is unsigned (build with --sign to exercise this)")
  end
end

-- Each package must ship its own manifest, or the installer has nothing
-- to verify the download against.
local noManifest = nil
for name, entry in pairs(index) do
  if type(entry.files) == "table" and entry.files[name .. "/package.lua"] == nil then
    noManifest = noManifest or name
  end
end
test("every package advertises its package.lua" ..
  (noManifest and (" (" .. noManifest .. ")") or ""), noManifest == nil)

-- Staleness: the index must match the built disks. Cross-process, which
-- is also what pins the generator's output as deterministic.
--! QUOTE THE PATH. arg[0] is absolute when the harness invokes this, and
--! this repo lives under a directory with a space and parentheses in its
--! name ("Programs (Scripts)"). Unquoted, cmd.exe split the command at the
--! space and reported `cannot open C:/Users/.../Programs` -- a failure that
--! only appeared under the test runner, never when run by hand from here.
local ok, _, code = os.execute('lua "' .. root .. '/build/make-repo-index.lua" --check')
local succeeded = (ok == true) or (ok == 0) or (code == 0)
if code == 127 or code == 126 then
  print("  SKIP: lua not on PATH for the staleness check")
else
  test("programs.cfg matches the built disks "
    .. "(if this fails: lua build/make-repo-index.lua)", succeeded)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
