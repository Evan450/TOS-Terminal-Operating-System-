-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: which copy of a dependency wins          ║
-- ║                                                            ║
-- ║  With several acceptable copies of a dependency on         ║
-- ║  different disks, the FIRST root to have one used to win,  ║
-- ║  so the order the disks were mounted in decided what       ║
-- ║  installed. Federated repos slice 3 ranks them instead, as ║
-- ║  docs/FEDERATED-REPOS.md decided on 2026-11-06:            ║
-- ║    1. one copy that satisfies every requirer               ║
-- ║    2. higher trust (trusted key > any key > unsigned)      ║
-- ║    3. newer version                                        ║
-- ║    4. less disk                                            ║
-- ║  and a tie (different bytes, equal on all four) goes to    ║
-- ║  opts.chooseCopy, else the earliest root, recorded in      ║
-- ║  plan.ties. Slice 1's rule stands above all of it: a       ║
-- ║  dependency shipped on the target's own disk wins.         ║
-- ║                                                            ║
-- ║  Every case puts the copy that should LOSE on the earlier  ║
-- ║  disk, so first-found-wins fails each one.                 ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_winner_order.lua

package.path = package.path .. ";tos/?.lua;TOS-Dev/tos/?.lua;../TOS-Dev/tos/?.lua"  -- kernel.policy
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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_winner_order.lua"
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
package.loaded["kernel.curve25519field"] = tryload("tos/kernel/curve25519field.lua")()
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

print("=== dependency winner order Tests ===")
print()

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local SEED_A, SEED_B = string.rep("A", 32), string.rep("B", 32)
local PUB_A = hex(ed.publickey(SEED_A))

-- ── A fake disk whose directories are implied by its files ───
-- list() marks a directory with a trailing "/", as OpenComputers does: the
-- size rule walks the package directory and needs to tell the two apart.
local function makeFs()
  local F = { _f = {} }
  local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
  function F.exists(p)
    for k in pairs(F._f) do if under(p, k) then return true end end
    return false
  end
  function F.readFile(p) return F._f[p] end
  function F.writeFile(p, d) F._f[p] = d; return true end
  function F.size(p) return F._f[p] and #F._f[p] or 0 end
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
        local rest = k:sub(#p + 2)
        local head = rest:match("^([^/]+)")
        if head and not seen[head] then
          seen[head] = true
          out[#out + 1] = rest:find("/", 1, true) and (head .. "/") or head
        end
      end
    end
    table.sort(out)
    return out
  end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
  return F
end

-- A hashed package at root/name. Its one file says which disk it came from
-- unless opts.body says otherwise; opts.pad grows that file, for the size
-- rule. opts.seed signs it. opts.requires is Lua source for the table.
-- opts.unhashed leaves the hashes out, so the manifest says nothing about
-- the file and two copies' manifests can match while their files differ.
local function put(F, root, name, opts)
  opts = opts or {}
  local body = (opts.body or ("-- " .. name .. " from " .. root)) .. string.rep("x", opts.pad or 0)
  local hashes = opts.unhashed and ""
    or string.format('  hashes = { ["/usr/lib/%s.lua"] = %q },\n', name, sha256.hex(body))
  local m = string.format('return { name = %q, version = %q, kind = "lib",\n'
    .. '  files = { "/usr/lib/%s.lua" },\n%s'
    .. '  requires = %s }\n', name, opts.version or "1.0.0", name, hashes,
    opts.requires or "nil")
  F._f[root .. "/" .. name .. "/package.lua"] = m
  F._f[root .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
  if opts.seed then
    local pub = ed.publickey(opts.seed)
    F._f[root .. "/" .. name .. "/package.sig"] = serialize.encode({ v = 1, alg = "ed25519",
      key = hex(pub), sig = hex(ed.sign(m, opts.seed, pub)) })
  end
end

local KERNEL = { isKernel = true }
-- alice (SEED_A) is trusted here; SEED_B is a key nobody trusted.
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
local function plan(pkg, name, extra)
  local o = { extraRoots = ROOTS }
  for k, v in pairs(extra or {}) do o[k] = v end
  return pkg.plan("/x/a", name, o)
end
local function tieOf(p) return p and p.ties and p.ties.lib or nil end
local function fileCount(F) local n = 0; for _ in pairs(F._f) do n = n + 1 end; return n end

-- ══════════════════════════════════════════════════════════════════════
print("-- 3. the newer copy wins, not the first one found --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { version = "1.0.0" })
  put(F, "/x/c", "lib", { version = "2.0.0" })
  local before = fileCount(F)
  local p, perr = plan(pkg, "app")
  ok("pkg.plan answers", p ~= nil)
  if not p then print("      (" .. tostring(perr) .. ")") end
  test("lib comes from the disk with 2.0.0", "/x/c/lib", p and p.dirs.lib)
  test("no contradictions", 0, p and #p.contradictions)
  test("no tie: the versions differ", nil, tieOf(p))
  test("and the plan wrote nothing", before, fileCount(F))
end

print("-- 1. one copy that satisfies everyone beats the newer one --")
do
  -- app wants any lib; user (on app's disk) wants lib below 2. The newest
  -- lib satisfies app and breaks user, so the plan has to learn user's
  -- constraint before it chooses: that is what the passes are for.
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib", "user" }' })
  put(F, "/x/a", "user", { requires = '{ "lib <2.0.0" }' })
  put(F, "/x/b", "lib", { version = "2.0.0" })
  put(F, "/x/c", "lib", { version = "1.5.0" })
  local p = plan(pkg, "app")
  test("lib is the 1.5.0 both can use", "/x/c/lib", p and p.dirs.lib)
  test("so nothing contradicts", 0, p and #p.contradictions)
  local order = p and table.concat(p.order, ",") or ""
  ok("lib is ordered before what needs it", order:find("^lib,") ~= nil)
end

print("-- 1, failing: no copy satisfies everyone --")
do
  -- app wants lib >= 2, user wants lib < 2: no single copy works. The
  -- fallback keeps the copy that satisfies whoever asked, and the plan
  -- names the requirer it leaves out instead of saying "unknown package".
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib >=2.0.0", "user" }' })
  put(F, "/x/a", "user", { requires = '{ "lib <2.0.0" }' })
  put(F, "/x/b", "lib", { version = "1.5.0" })
  put(F, "/x/c", "lib", { version = "2.0.0" })
  local p, perr = plan(pkg, "app")
  ok("pkg.plan still answers", p ~= nil)
  if not p then print("      (" .. tostring(perr) .. ")") end
  test("lib is the copy app (who asked first) can use", "/x/c/lib", p and p.dirs.lib)
  ok("and the plan reports a contradiction", p and #p.contradictions > 0)
  local text = p and pkg.describeContradictions(p.contradictions) or ""
  ok("naming user", text:find("user", 1, true) ~= nil)
end

print("-- 2. a trusted signer beats a newer unsigned copy --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { version = "3.0.0" })                 -- unsigned
  put(F, "/x/c", "lib", { version = "1.0.0", seed = SEED_A })  -- alice, trusted
  local p = plan(pkg, "app")
  test("lib comes from alice's disk", "/x/c/lib", p and p.dirs.lib)
end

print("-- 2. any key beats no key; a trusted key beats an untrusted one --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib", "lib2" }' })
  put(F, "/x/b", "lib", { version = "2.0.0" })                 -- unsigned
  put(F, "/x/c", "lib", { version = "1.0.0", seed = SEED_B })  -- signed, not trusted
  put(F, "/x/b", "lib2", { version = "2.0.0", seed = SEED_B })
  put(F, "/x/c", "lib2", { version = "1.0.0", seed = SEED_A })
  local p = plan(pkg, "app")
  test("an untrusted signature still outranks none", "/x/c/lib", p and p.dirs.lib)
  test("and a trusted one outranks it", "/x/c/lib2", p and p.dirs.lib2)
end

print("-- 4. same trust and version: the smaller copy wins --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { pad = 400 })
  put(F, "/x/c", "lib", { pad = 10 })
  local p = plan(pkg, "app")
  test("lib comes from the disk with the smaller copy", "/x/c/lib", p and p.dirs.lib)
  test("which is not a tie", nil, tieOf(p))
end

print("-- slice 1 stands above the ranking --")
do
  -- A lib shipped beside the target wins even against a newer, trusted
  -- copy elsewhere: a self-contained disk installs what it was built with.
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/a", "lib", { version = "1.0.0" })
  put(F, "/x/b", "lib", { version = "9.0.0", seed = SEED_A })
  local p = plan(pkg, "app")
  test("lib comes from app's own disk", "/x/a/lib", p and p.dirs.lib)
end

print("-- a tie with nobody to ask keeps the earliest disk, and says so --")
do
  -- Same version, trust and size; the bodies differ ("from /x/b" and
  -- "from /x/c" are the same length), so the manifests' hashes differ.
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib")
  put(F, "/x/c", "lib")
  local p = plan(pkg, "app")
  test("the earliest disk keeps it", "/x/b/lib", p and p.dirs.lib)
  local t = tieOf(p)
  ok("plan.ties records it", t ~= nil)
  test("with the copy chosen", "/x/b/lib", t and t.chosen)
  test("and the one passed over", "/x/c/lib", t and t.over and t.over[1])
  test("and that nobody was asked", false, t and t.asked)
  test("a tie is not a contradiction", 0, p and #p.contradictions)
end

print("-- identical copies are not a tie --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { body = "-- the same lib" })
  put(F, "/x/c", "lib", { body = "-- the same lib" })
  local asked = 0
  local p = plan(pkg, "app", { chooseCopy = function() asked = asked + 1 end })
  test("the earliest disk answers", "/x/b/lib", p and p.dirs.lib)
  test("nothing is recorded as a tie", nil, tieOf(p))
  test("and nobody is asked", 0, asked)
end

print("-- without hashes, the same manifest is not proof of the same copy --")
do
  -- Found on the headless runner: two hand-made copies, one package.lua,
  -- different files. Comparing manifests alone called them identical, so
  -- the operator was never asked which one to install.
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { unhashed = true })
  put(F, "/x/c", "lib", { unhashed = true })
  test("setup: the two manifests are byte-identical",
    F._f["/x/b/lib/package.lua"], F._f["/x/c/lib/package.lua"])
  local asked = 0
  local p = plan(pkg, "app", { chooseCopy = function() asked = asked + 1 end })
  ok("their different files make it a tie", tieOf(p) ~= nil)
  test("so the operator is asked", 1, asked)

  local pkg2, F2 = machine()
  put(F2, "/x/a", "app", { requires = '{ "lib" }' })
  put(F2, "/x/b", "lib", { unhashed = true, body = "-- one lib" })
  put(F2, "/x/c", "lib", { unhashed = true, body = "-- one lib" })
  asked = 0
  local p2 = plan(pkg2, "app", { chooseCopy = function() asked = asked + 1 end })
  test("unhashed and identical in every file is still no tie", nil, tieOf(p2))
  test("and nobody is asked", 0, asked)
end

print("-- a tie goes to chooseCopy, asked ONCE across the passes --")
do
  -- user's constraint is learned in pass 1 and changes wantedBy, so the
  -- plan resolves twice; the same question must not be put twice.
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib", "user" }' })
  put(F, "/x/a", "user", { requires = '{ "lib >=1.0.0" }' })
  put(F, "/x/b", "lib")
  put(F, "/x/c", "lib")
  local calls, gotName, gotDirs = 0, nil, nil
  local p = plan(pkg, "app", { chooseCopy = function(name, dirs)
    calls = calls + 1; gotName, gotDirs = name, dirs
    return dirs[2]
  end })
  test("asked once", 1, calls)
  test("about lib", "lib", gotName)
  test("offering both copies, earliest first", "/x/b/lib,/x/c/lib",
    gotDirs and table.concat(gotDirs, ","))
  test("the answer wins", "/x/c/lib", p and p.dirs.lib)
  local t = tieOf(p)
  test("recorded as asked", true, t and t.asked)
  test("over the earliest", "/x/b/lib", t and t.over and t.over[1])
end

print("-- a chooser that answers nonsense, or fails, changes nothing --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib")
  put(F, "/x/c", "lib")
  local p1 = plan(pkg, "app", { chooseCopy = function() return "/etc" end })
  test("a dir it was not offered is ignored", "/x/b/lib", p1 and p1.dirs.lib)
  test("and counts as not asked", false, tieOf(p1) and tieOf(p1).asked)
  local p2 = plan(pkg, "app", { chooseCopy = function() error("no screen") end })
  test("an error keeps the earliest", "/x/b/lib", p2 and p2.dirs.lib)
end

print("-- installByName installs the chosen copy and reports the tie --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib")
  put(F, "/x/c", "lib")
  local okI, res = pkg.installByName("app", { extraRoots = ROOTS, session = KERNEL,
    chooseCopy = function(_, dirs) return dirs[2] end })
  ok("app installs", okI == true)
  if not okI then print("      (" .. tostring(res) .. ")") end
  test("lib's file came off the chosen disk", "-- lib from /x/c", F._f["/usr/lib/lib.lua"])
  local t = type(res) == "table" and res.ties and res.ties.lib
  test("the summary carries the tie", "/x/c/lib", t and t.chosen)
end

print("-- the newer copy is what actually installs --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib", { version = "1.0.0" })
  put(F, "/x/c", "lib", { version = "2.0.0" })
  local okI, res = pkg.installByName("app", { extraRoots = ROOTS, session = KERNEL })
  ok("app installs", okI == true)
  if not okI then print("      (" .. tostring(res) .. ")") end
  test("at lib 2.0.0", "2.0.0", pkg.info("lib") and pkg.info("lib").version)
  test("from /x/c", "-- lib from /x/c", F._f["/usr/lib/lib.lua"])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
