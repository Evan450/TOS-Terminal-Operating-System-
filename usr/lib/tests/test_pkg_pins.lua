-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: publisher pins on `requires`                        ║
-- ║                                                            ║
-- ║  `{ name = "lib", key = "<64 hex>" }` means lib AS SIGNED  ║
-- ║  BY THAT KEY (docs/FEDERATED-REPOS.md, slice 1). Before    ║
-- ║  pins, a dependency was whatever same-named directory was  ║
-- ║  found first, so a disk could stand in for any library by  ║
-- ║  naming a directory after it.                              ║
-- ║                                                            ║
-- ║  Pinned here: the pin chooses among copies; a pin nothing  ║
-- ║  satisfies is refused with nothing written; an installed   ║
-- ║  dependency from the wrong publisher and two requirers     ║
-- ║  that disagree are contradictions the plan reports first;  ║
-- ║  a copy that only CLAIMS the key is caught by install;     ║
-- ║  pkg.plan itself changes nothing. Real pkg, pkgsign and    ║
-- ║  ed25519 against an in-memory disk.                        ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_pins.lua

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
local function has(s, needle) return tostring(s):find(needle, 1, true) ~= nil end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_pins.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

local sha256 = tryload("tos/kernel/sha256.lua")()
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.sha512"] = tryload("tos/kernel/sha512.lua")()
local ed = tryload("tos/kernel/ed25519.lua")()
package.loaded["kernel.ed25519"] = ed
local serialize = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.serialize"] = serialize
package.loaded["kernel.crypto"] = {
  hash = function(d) return sha256.hex(d) end,
  ctEquals = function(a, b) return a == b end,
}
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.users"] = { currentSession = function() return nil end }

print("=== publisher pins Tests ===")
print()

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local SEED_A, SEED_B = string.rep("A", 32), string.rep("B", 32)
local PUB_A, PUB_B = hex(ed.publickey(SEED_A)), hex(ed.publickey(SEED_B))

-- ── A fake disk whose directories are implied by its files ───
local function makeFs()
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
  function F.mounts() return {} end
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

-- A hashed package at root/name, signed by `opts.seed` (or unsigned).
-- `opts.requires` is Lua source for the requires table. `opts.claim` forges
-- a signature file that NAMES that key but is made with opts.seed.
local function put(F, root, name, opts)
  opts = opts or {}
  local body = "-- " .. name .. " from " .. root
  local m = string.format('return { name = %q, version = %q, kind = "lib",\n'
    .. '  files = { "/usr/lib/%s.lua" },\n'
    .. '  hashes = { ["/usr/lib/%s.lua"] = %q },\n'
    .. '  requires = %s }\n', name, opts.version or "1.0.0", name, name,
    sha256.hex(body), opts.requires or "nil")
  F._f[root .. "/" .. name .. "/package.lua"] = m
  F._f[root .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
  F._f[root .. "/" .. name .. "/package.sig"] = nil
  if opts.seed then
    local pub = ed.publickey(opts.seed)
    F._f[root .. "/" .. name .. "/package.sig"] = serialize.encode({ v = 1, alg = "ed25519",
      key = opts.claim or hex(pub), sig = hex(ed.sign(m, opts.seed, pub)) })
  end
end
local function pin(name, key) return string.format('{ name = %q, key = %q }', name, key) end

local KERNEL = { isKernel = true }
local function machine()
  local F = makeFs()
  F._f["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { alice = PUB_A } })
  package.loaded["kernel.pkgsign"] = nil
  local ps = tryload("tos/kernel/pkgsign.lua")()
  ps.init({ fs = F, serialize = serialize })
  package.loaded["kernel.pkgsign"] = ps
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  return pkg, F
end
local ROOTS = { "/x/a", "/x/b", "/x/c" }
local function install(pkg, name, extra)
  local o = { extraRoots = ROOTS, session = KERNEL }
  for k, v in pairs(extra or {}) do o[k] = v end
  return pkg.installByName(name, o)
end
local function fileCount(F) local n = 0; for _ in pairs(F._f) do n = n + 1 end; return n end

-- ══════════════════════════════════════════════════════════════════════
print("-- the pin chooses the publisher's copy over an earlier impostor --")
do
  local pkg, F = machine()
  -- Written in capitals on purpose: a pin compares case-blind.
  put(F, "/x/a", "app", { seed = SEED_A, requires = "{ " .. pin("lib", PUB_A:upper()) .. " }" })
  put(F, "/x/b", "lib", { seed = SEED_B })   -- found first, wrong publisher
  put(F, "/x/c", "lib", { seed = SEED_A })
  local okI, res = install(pkg, "app")
  ok("app installs", okI == true)
  if not okI then print("      (" .. tostring(res) .. ")") end
  test("lib came from the pinned publisher's disk", "-- lib from /x/c", F._f["/usr/lib/lib.lua"])
  test("recorded as alice's", PUB_A, pkg.info("lib") and pkg.info("lib")._sigKey)
end

print("-- no copy signed by the pinned key --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = "{ " .. pin("lib", PUB_A) .. " }" })
  put(F, "/x/b", "lib", { seed = SEED_B })
  local okI, err = install(pkg, "app")
  test("refused", false, okI)
  ok("saying who needs which publisher", has(err, "app requires 'lib' signed by 'alice'"))
  ok("and what was found instead", has(err, "/x/b/lib has an untrusted key"))
  test("app not installed", nil, pkg.info("app"))
  test("nor the impostor", nil, pkg.info("lib"))
end

print("-- an installed dependency from the wrong publisher --")
do
  local pkg, F = machine()
  put(F, "/x/b", "lib", {})                  -- unsigned, installed first
  ok("setup: lib installs unsigned", (install(pkg, "lib")))
  put(F, "/x/a", "app", { requires = "{ " .. pin("lib", PUB_A) .. " }" })

  local before = fileCount(F)
  local plan, perr = pkg.plan("/x/a", "app", { extraRoots = ROOTS })
  ok("pkg.plan answers", plan ~= nil)
  if not plan then print("      (" .. tostring(perr) .. ")") end
  local c = plan and plan.contradictions[1]
  test("with one contradiction", 1, plan and #plan.contradictions)
  test("of kind publisher", "publisher", c and c.kind)
  ok("naming the installed copy's state", c and has(c.text, "the installed lib has no signature"))
  test("and pkg.plan wrote nothing", before, fileCount(F))

  local okI, err = install(pkg, "app")
  test("install refuses", false, okI)
  ok("with the plan's words", has(err, "refusing to install 'app'") and has(err, "has no signature"))
  test("app not installed", nil, pkg.info("app"))

  ok("force goes past it", (install(pkg, "app", { force = true })) == true)
  test("leaving lib as it was", "unsigned", pkg.info("lib") and pkg.info("lib")._sigState)
end

print("-- two requirers pin different publishers --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = "{ " .. pin("lib", PUB_A) .. ', "helper" }' })
  put(F, "/x/a", "helper", { requires = "{ " .. pin("lib", PUB_B) .. " }" })
  put(F, "/x/a", "lib", { seed = SEED_A })
  local plan = pkg.plan("/x/a", "app", { extraRoots = ROOTS })
  local kinds = {}
  for _, c in ipairs(plan and plan.contradictions or {}) do kinds[#kinds + 1] = c.kind end
  ok("the plan reports the disagreement", table.concat(kinds, ","):find("pins", 1, true) ~= nil)
  local okI, err = install(pkg, "app")
  test("install refuses", false, okI)
  -- Dependencies come first in a plan, so helper's pin is met before app's.
  ok("naming both", has(err, "helper requires 'lib' signed by an untrusted key")
    and has(err, "but app requires it signed by 'alice'"))
  test("nothing installed", nil, pkg.info("lib"))
end

print("-- a copy that only CLAIMS the pinned key --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = "{ " .. pin("lib", PUB_A) .. ', "util" }' })
  put(F, "/x/a", "util", {})
  -- Signed with B's key, but the signature file names A's.
  put(F, "/x/b", "lib", { seed = SEED_B, claim = PUB_A })
  local okI, err = install(pkg, "app")
  test("refused", false, okI)
  ok("by install's signature check", has(err, "does not verify"))
  test("lib not installed", nil, pkg.info("lib"))
  test("and what went in before it was rolled back", nil, pkg.info("util"))
end

print("-- an unpinned requirement is unaffected --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { seed = SEED_B })
  ok("installs whoever signed lib", (install(pkg, "app")) == true)
  test("B's", PUB_B, pkg.info("lib") and pkg.info("lib")._sigKey)
end

print("-- a malformed pin is refused before anything installs --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "util", { name = "lib", key = "xyz" } }' })
  put(F, "/x/a", "util", {})
  put(F, "/x/a", "lib", {})
  local okI, err = install(pkg, "app")
  test("refused", false, okI)
  ok("as an invalid manifest", has(err, "invalid manifest for 'app'") and has(err, "not a 64-hex public key"))
  test("util, earlier in line, was not installed", nil, pkg.info("util"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
