-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg Trust Model (CR-4 / H-20)      ║
-- ║  - write-root confinement (no /tos, /etc overwrite)   ║
-- ║  - manifest validation incl. hashes shape             ║
-- ║  - installFromFloppy never default-accepts            ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_trust.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- pkg.lua requires kernel.serialize; preload a stub (validateManifest /
-- isUnderPkgWriteRoot don't use it).
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_trust.lua"
local base = here:gsub("[^/\\]*$", "")
local pkg
for _, p in ipairs({ base .. "../../../tos/kernel/pkg.lua", "tos/kernel/pkg.lua",
    "TOS-Dev/tos/kernel/pkg.lua" }) do
  local chunk = loadfile(p)
  if chunk then pkg = chunk(); break end
end
if not pkg then
  print("FAIL: could not load pkg.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local underRoot = pkg._isUnderPkgWriteRoot
local validate  = pkg._validateManifest

print("=== pkg Trust Model Tests ===")
print()

-- ── Write-root confinement (CR-4) ──────────────────────────────────
test("/usr/bin/foo under root", true, underRoot("/usr/bin/foo"))
test("/var/pkg/x under root",   true, underRoot("/var/pkg/x"))
test("/tos/kernel/sandbox.lua rejected", false, underRoot("/tos/kernel/sandbox.lua"))
test("/etc/users.dat rejected", false, underRoot("/etc/users.dat"))
test("/usr (root itself) rejected", false, underRoot("/usr"))
test("/usr/ (root dir, no child) rejected", false, underRoot("/usr/"))
test("/usrevil/x prefix-collision rejected", false, underRoot("/usrevil/x"))
test("nil rejected", false, underRoot(nil))

-- ── Manifest validation (CR-4) ─────────────────────────────────────
local function manifest(over)
  local m = { name = "pkgx", version = "1.0", kind = "lib",
    files = { "/usr/lib/pkgx.lua" } }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

test("valid manifest accepted", true, (validate(manifest())))
-- A manifest that targets the kernel must be refused.
test("kernel-overwrite manifest rejected", false,
  (validate(manifest({ files = { "/tos/kernel/sandbox.lua" } }))))
test("etc-overwrite manifest rejected", false,
  (validate(manifest({ files = { "/etc/users.dat" } }))))
-- hashes shape validation.
test("good hashes accepted", true,
  (validate(manifest({ hashes = { ["/usr/lib/pkgx.lua"] = string.rep("a", 64) } }))))
test("short hash rejected", false,
  (validate(manifest({ hashes = { ["/usr/lib/pkgx.lua"] = "abc" } }))))
test("non-table hashes rejected", false,
  (validate(manifest({ hashes = "nope" }))))

-- ── Reject-unverified-by-default gate (#SEC, Jul 2026) ─────────────
-- A package installs only if it declares a SHA-256 for every file in
-- files[]; otherwise it's refused unless --allow-unverified is passed.
local gate = pkg._verificationGate
local H = string.rep("a", 64)   -- a well-formed digest
-- No hashes at all → refused by default, allowed with the override flag.
test("no hashes: refused by default", false, (gate(manifest())))
test("no hashes: reason mentions unverified", true,
  select(2, gate(manifest())):find("unverified") ~= nil)
test("no hashes + --allow-unverified: accepted", true, (gate(manifest(), true)))
test("no hashes + override: flagged incomplete", false,
  select(3, gate(manifest(), true)))
-- Full hash set → accepted with no override, and marked complete.
local full = manifest({ hashes = { ["/usr/lib/pkgx.lua"] = H } })
test("complete hashes: accepted by default", true, (gate(full)))
test("complete hashes: marked complete", true, select(3, gate(full)))
-- Partial hash set (a second file unhashed) → refused by default.
local partial = manifest({
  files = { "/usr/lib/pkgx.lua", "/usr/lib/pkgy.lua" },
  hashes = { ["/usr/lib/pkgx.lua"] = H },   -- pkgy missing
})
test("partial hashes: refused by default", false, (gate(partial)))
test("partial hashes: reason names the gap", true,
  select(2, gate(partial)):find("missing hashes") ~= nil)
test("partial hashes + override: accepted", true, (gate(partial, true)))

-- ── kind="command"/"program" are first-class (Extras modules use them) ──
test("command kind accepted", true,
  (validate(manifest({ kind = "command", files = { "/usr/modules/tetris/init.lua" } }))))
test("program kind accepted", true,
  (validate(manifest({ kind = "program", files = { "/usr/bin/x.lua" } }))))
test("bogus kind still rejected", false,
  (validate(manifest({ kind = "frobnicate" }))))

-- ── Service /etc exception (narrow CR-4 relaxation) ────────────────
local svc = pkg._isServiceEtcTarget
test("rc.d entry is a service /etc target",  true,  svc("/etc/rc.d/clusterd.lua"))
test("top-level cfg is a service /etc target", true, svc("/etc/cluster-master.cfg"))
test("shadow DB is NOT a service /etc target", false, svc("/etc/users.dat"))
test("nested /etc path is NOT allowed",        false, svc("/etc/rc.d/sub/x.lua"))

-- A service manifest may ship its rc.d entry + cfg; a command one may not.
local function svcManifest(files)
  return { name = "cluster-master", version = "1.0", kind = "service", files = files }
end
test("service may write rc.d + cfg + /usr", true,
  (validate(svcManifest({ "/usr/bin/cluster.lua", "/etc/rc.d/clusterd.lua",
    "/etc/cluster-master.cfg" }))))
test("service may NOT write the kernel", false,
  (validate(svcManifest({ "/tos/kernel/init.lua" }))))
test("service may NOT write the shadow DB", false,
  (validate(svcManifest({ "/etc/users.dat" }))))
test("command kind may NOT use the /etc exception", false,
  (validate(manifest({ kind = "command", files = { "/etc/rc.d/x.lua" } }))))

-- ── installFromFloppy never default-accepts (H-20) ─────────────────
-- Mock fs so /mnt exists with one labelled mount that exposes a package;
-- with no confirm callback the package must be DECLINED, not installed.
local installCalls = 0
pkg.init({
  fs = {
    exists = function(p) return p == "/mnt" end,
    list   = function(p) if p == "/mnt" then return { "disk1" } end return {} end,
    isDirectory = function() return true end,
    makeDirectory = function() return true end,
    join = function(a, b) return (a:gsub("/$", "")) .. "/" .. b end,
    normalize = function(p) return p end,
    readFile = function() return nil end,
    writeFile = function() return true end,
  },
  log = nil,
})
-- Make listRepo see one package on the floppy, and installByName observable.
pkg.listRepo = function() return { { name = "evilpkg", dir = "/mnt/disk1/evilpkg" } } end
pkg.installByName = function() installCalls = installCalls + 1; return true end

local okF, resF = pkg.installFromFloppy({})  -- no confirm => default decline
test("installFromFloppy returns ok", true, okF == true)
test("nothing installed without explicit confirm", 0, installCalls)
test("candidate recorded as skipped", 1, resF and #resF.skipped or -1)

-- With an explicit accept, it installs.
installCalls = 0
pkg.installFromFloppy({ confirm = function() return true end })
test("explicit confirm installs", 1, installCalls)

-- ══════════════════════════════════════════════════════════════════════
-- `pkg trust require on` must mean TRUSTED, not merely SIGNED
-- ══════════════════════════════════════════════════════════════════════
--! Reported from a real machine: trust-require was on, a package signed
--! by a key the machine had never seen installed anyway with a warning,
--! and the operator could not find the refusal because there was none.
--!
--! The gate refused only `unsigned`. Anyone can generate a key in
--! seconds and sign anything with it, so that stopped honest unsigned
--! packages and nothing an attacker would do -- while reading, to
--! someone who had deliberately switched it on, like a guarantee of
--! provenance.
--!
--! Driven through pkg._signGate directly: it is the one place the
--! decision is made, and the states it switches on come from pkgsign.
do
  print()
  print("-- trust require covers untrusted keys --")

  -- `pkg` is already loaded at the top of this file.
  local function ok(name, cond) test(name, true, cond and true or false) end
  if not pkg._signGate then
    ok("pkg._signGate reachable", false)
  else
    -- Stand in for kernel.pkgsign with a scripted verdict + policy.
    local verdictState, requireOn = "unsigned", false
    package.loaded["kernel.pkgsign"] = {
      -- signGate calls init() before verifying; the real module needs fs
      -- and serialize, the stub needs nothing.
      init               = function() return true end,
      verifyManifest     = function()
        return { state = verdictState, key = "deadbeef", fingerprint = "AAAA BBBB" }
      end,
      requiresSignature  = function() return requireOn end,
      describe           = function() return {} end,
    }

    local function gate(state, req, opts)
      verdictState, requireOn = state, req
      local _, err = pkg._signGate("/d/package.lua", opts or {})
      return err
    end

    -- Off: everything but tampering installs, as before.
    test("require OFF: unsigned installs", nil, gate("unsigned", false))
    test("require OFF: untrusted key installs", nil, gate("unknown", false))
    test("require OFF: trusted installs", nil, gate("trusted", false))

    -- On: the two that are not trusted are both refused.
    local unsignedErr = gate("unsigned", true)
    local unknownErr  = gate("unknown", true)
    ok("require ON: unsigned is refused", unsignedErr ~= nil)
    ok("require ON: an UNTRUSTED key is refused (the bug: it was not)",
      unknownErr ~= nil)
    test("require ON: a trusted key still installs", nil, gate("trusted", true))

    -- The two refusals need different remedies, so they must not share
    -- wording: one needs the publisher to sign, one needs a decision here.
    ok("the untrusted refusal names the key to trust",
      unknownErr and unknownErr:find("pkg trust add", 1, true) ~= nil)
    ok("...and the fingerprint to compare",
      unknownErr and unknownErr:find("AAAA BBBB", 1, true) ~= nil)
    ok("...and says to compare it out of band",
      unknownErr and unknownErr:find("NOT this package", 1, true) ~= nil)
    ok("the unsigned refusal is worded differently",
      unsignedErr and unsignedErr ~= unknownErr)

    -- Tampering is never overridable, and that must not have regressed.
    ok("invalid is refused even with require OFF", gate("invalid", false) ~= nil)
    ok("...and with the override flag",
      gate("invalid", true, { allowUnsigned = true }) ~= nil)

    -- The per-install escape hatch still works for the softer cases.
    test("--allow-unsigned lets an unsigned one through", nil,
      gate("unsigned", true, { allowUnsigned = true }))
    test("--allow-unsigned lets an untrusted one through", nil,
      gate("unknown", true, { allowUnsigned = true }))

    package.loaded["kernel.pkgsign"] = nil
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- `pkg search` has to see the repos, not just the disks
-- ══════════════════════════════════════════════════════════════════════
--! Reported from a real machine: a configured repo, a working internet
--! card, a successful `pkg fetch mouse` -- and `pkg search` said nothing
--! was available. It only ever looked at local roots, so the only way to
--! find a package was to already know its name.
do
  print()
  print("-- search spans configured repos --")
  local function ok2(name, cond) test(name, true, cond and true or false) end

  ok2("pkg.listRemoteAvailable exists", type(pkg.listRemoteAvailable) == "function")

  -- No pkgremote at all: empty, and above all not an error. A machine
  -- with no internet card must get a SHORTER list, not a broken one.
  package.loaded["kernel.pkgremote"] = nil
  local okA, a = pcall(pkg.listRemoteAvailable, {})
  ok2("no remote module: does not throw", okA)
  test("no remote module: no entries", 0, okA and #a or -1)

  -- A repo that answers.
  package.loaded["kernel.pkgremote"] = {
    init   = function() end,
    search = function()
      return {
        { name = "calc",  version = "1.2.0", repo = "utils", description = "a spreadsheet" },
        { name = "snake", version = "1.0.0", repo = "utils" },
      }
    end,
  }
  local list = pkg.listRemoteAvailable({})
  test("a configured repo contributes its packages", 2, #list)
  ok2("entries are marked remote", list[1].remote == true)
  ok2("...and carry the repo name", list[1].repo == "utils")
  ok2("...and have no root, because they are not anywhere yet",
    list[1].root == nil)

  -- An index that blows up must not take the listing with it.
  package.loaded["kernel.pkgremote"] = {
    init = function() end, search = function() error("no card") end,
  }
  local okB, b = pcall(pkg.listRemoteAvailable, {})
  ok2("a failing repo does not throw", okB)
  test("...and contributes nothing", 0, okB and #b or -1)

  package.loaded["kernel.pkgremote"] = nil
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
