-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: every pkg install gate names its error code  ║
-- ║                                                                ║
-- ║  The error registry's migration tags refusals as they are      ║
-- ║  touched, and pkg's install and upgrade gates were the largest  ║
-- ║  untagged set: unverified, hash mismatch, a signature that      ║
-- ║  does not verify, `pkg trust require on`, the wrong publisher,  ║
-- ║  a protected target, a conflict. Each refusal now carries its   ║
-- ║  E-6xx tag, so `why` can explain it. Driven through the real    ║
-- ║  pkg.install and pkgsign, with a real Ed25519 key, over a fake  ║
-- ║  floppy.                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_refusal_codes.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function loadMod(rel)
  for _, p in ipairs({ "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
  error("cannot find " .. rel)
end

package.loaded["kernel.sha512"] = loadMod("sha512.lua")
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
local ed = loadMod("ed25519.lua")
package.loaded["kernel.ed25519"] = ed
local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
package.loaded["kernel.pkgsign"] = loadMod("pkgsign.lua")
package.loaded["kernel.crypto"] = {
  hash = function(s) return sha256.hex(s) end,
  ctEquals = function(a, b) return a == b end,
}
local errors = loadMod("errors.lua")

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local SEED, OTHER = string.rep("S", 32), string.rep("O", 32)
local PUB, OPUB = hex(ed.publickey(SEED)), hex(ed.publickey(OTHER))

local files, dirs = {}, { ["/"] = true }
local F = {
  normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
  join = function(a, b) return tostring(a):gsub("/$", "") .. "/" .. tostring(b) end,
  exists = function(p) return files[p] ~= nil or dirs[p] == true end,
  isDirectory = function(p) return dirs[p] == true end,
  makeDirectory = function(p) dirs[p] = true; return true end,
  readFile = function(p) if files[p] == nil then return nil, "File not found: " .. p end return files[p] end,
  writeFile = function(p, c)
    local acc = ""
    for seg in tostring(p):gmatch("[^/]+") do
      acc = acc .. "/" .. seg
      if acc ~= p then dirs[acc] = true end
    end
    files[p] = c; return true
  end,
  remove = function(p)
    for k in pairs(files) do if k == p or k:sub(1, #p + 1) == p .. "/" then files[k] = nil end end
    dirs[p] = nil
    return true
  end,
  list = function(p)
    local out, seen = {}, {}
    for k in pairs(files) do
      local rest = k:sub(1, #p + 1) == p .. "/" and k:sub(#p + 2)
      local head = rest and rest:match("^([^/]+)")
      if head and not seen[head] then seen[head] = true; out[#out + 1] = head end
    end
    return out
  end,
}

local ADMIN = { user = "root", tier = 3 }
local users = { currentSession = function() return ADMIN end, TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 } }
local ps = package.loaded["kernel.pkgsign"]
ps.init({ fs = F, serialize = serialize })
local pkg = loadMod("pkg.lua")
pkg.init({ fs = F, log = nil, users = users })

-- A package on the floppy. opt: hashes=false, badHash, seed, tamper,
-- target, conflicts.
local function disk(name, opt)
  opt = opt or {}
  local dir = "/mnt/disk1/" .. name
  local target = opt.target or ("/usr/lib/" .. name .. ".lua")
  local body = "return '" .. name .. "'\n"
  local m = { name = name, version = opt.version or "1.0.0", kind = "lib", description = name,
    files = { target }, capabilities = {}, conflicts = opt.conflicts }
  if opt.hashes ~= false then
    m.hashes = { [target] = opt.badHash and string.rep("0", 64) or sha256.hex(body) }
  end
  local mbytes = serialize.encode(m)
  if opt.seed then
    local pub = ed.publickey(opt.seed)
    F.writeFile(dir .. "/package.sig", serialize.encode({ v = 1, alg = "ed25519", key = hex(pub),
      sig = hex(ed.sign(mbytes, opt.seed, pub)), covers = "package.lua" }))
  end
  if opt.tamper then mbytes = mbytes:gsub('"' .. name .. '"', '"' .. name .. '"', 1) .. " " end
  F.writeFile(dir .. "/package.lua", mbytes)
  F.writeFile(dir .. target, body)
  return dir
end
local function install(dir, extra)
  local opts = { session = ADMIN }
  for k, v in pairs(extra or {}) do opts[k] = v end
  local ok, why = pkg.install(dir, opts)
  return ok, tostring(why)
end
local function tagged(why, num)
  local e = errors.find(num)
  local sym = e and e.sym
  return sym ~= nil and why:find("[E-" .. num .. " " .. sym .. "]", 1, true) ~= nil
end

print("=== every pkg install gate names its error code ===")
print()

-- The registry knows all seven.
for num = 607, 613 do
  test("E-" .. num .. " is in the registry", errors.find(num) ~= nil)
end

local ok, why = install(disk("plain"))
test("control: a hashed package installs", ok, why)

ok, why = install(disk("nohash", { hashes = false }))
test("no hashes: refused with E-607", ok == false and tagged(why, 607), why)
ok = install(disk("nohash", { hashes = false }), { allowUnverified = true })
test("...and --allow-unverified still gets past it", ok == true)

ok, why = install(disk("badhash", { badHash = true }))
test("a file that is not what the manifest says: E-608", ok == false and tagged(why, 608), why)

ok, why = install(disk("tampered", { seed = SEED, tamper = true }))
test("a signature that does not verify: E-609", ok == false and tagged(why, 609), why)

ps.setRequireSignature(true)
ok, why = install(disk("unsigned2"))
test("require on, unsigned: E-610", ok == false and tagged(why, 610), why)
ok, why = install(disk("stranger", { seed = OTHER }))
test("require on, an unknown key: E-610", ok == false and tagged(why, 610), why)
ps.setRequireSignature(false)

ok, why = install(disk("pinned", { seed = OTHER }), { expectKey = PUB })
test("signed by someone other than the pinned publisher: E-611", ok == false and tagged(why, 611), why)

ok, why = install(disk("notmail", { target = "/usr/lib/mail.lua" }))
test("a target kept for another package's kernel library: E-612", ok == false and tagged(why, 612), why)

ok, why = install(disk("rival", { conflicts = { "plain" } }))
test("a declared conflict with something installed: E-613", ok == false and tagged(why, 613), why)

-- Upgrades go through the same gates, and carry the same codes.
ok = install(disk("keyed", { seed = SEED }))
test("control: a signed package installs", ok)
disk("keyed", { seed = OTHER, version = "2.0.0" })
local okU, whyU = pkg.upgrade("keyed", { session = ADMIN, extraRoots = { "/mnt/disk1" } })
test("an upgrade to another publisher: E-611", okU == false and tagged(tostring(whyU), 611), whyU)

-- `why` can explain every one of them.
local helpersSrc = ""
do
  for _, p in ipairs({ "tos/shell/panels/helpers.lua", "TOS-Dev/tos/shell/panels/helpers.lua" }) do
    local f = io.open(p, "rb"); if f then helpersSrc = f:read("*a"); f:close(); break end
  end
end
for num = 607, 613 do
  local e = errors.find(num)
  test("`why` has an explanation for E-" .. num,
    e and helpersSrc:find('sym = "' .. e.sym .. '"', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
