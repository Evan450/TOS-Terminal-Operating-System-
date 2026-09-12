-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package cannot write the package manager's  ║
-- ║  own trees under /var/pkg                                       ║
-- ║                                                                ║
-- ║  files[] was confined to /usr/ and /var/pkg/, and /var/pkg/     ║
-- ║  holds every package's installed manifest (commands, caps, the  ║
-- ║  signature verdict pkg.scan believes) and every package's       ║
-- ║  crypto.secret(). One package could rewrite another's manifest  ║
-- ║  "signed by a trusted publisher", plant a ghost package, or set ║
-- ║  another package's key (Sep 2026 pentest). Drives the REAL      ║
-- ║  pkg.install over an in-memory disk, as test_pkg_lifecycle does. ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_reserved_targets.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_reserved_targets.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
end

local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.crypto"] = {
  hash = function(s) return sha256.hex(s) end,
  ctEquals = function(a, b) return a == b end,
}

-- An in-memory filesystem shaped like kernel.fs. join takes any number of
-- parts, as kernel.fs's does: pkg.scan joins three.
local function newFS()
  local files, dirs = {}, { ["/"] = true }
  local F
  F = {
    _files = files,
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c)
      local acc = ""
      for seg in tostring(p):gmatch("[^/]+") do
        acc = acc .. "/" .. seg
        if acc ~= p then dirs[acc] = true end
      end
      files[p] = c; return true
    end,
    writeFileAtomic = function(p, c) return F.writeFile(p, c) end,
    remove = function(p) files[p] = nil; return true end,
    list = function(p)
      local out, seen = {}, {}
      p = tostring(p):gsub("/$", "")
      local pat = "^" .. p:gsub("%p", "%%%1") .. "/([^/]+)"
      for k in pairs(files) do
        local rest = k:match(pat)
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest end
      end
      for k in pairs(dirs) do
        local rest = k:match(pat .. "$")
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest .. "/" end
      end
      table.sort(out)
      return out
    end,
    size = function(p) return files[p] and #files[p] or 0 end,
  }
  return F
end

local ADMIN = { user = "root", tier = 3 }
local usersMock = {
  currentSession = function() return ADMIN end,
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 },
  canAccessAs = function() return true end,
}
local function newPkg()
  local fs = newFS()
  package.loaded["kernel.pkg"] = nil
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  return pkg, fs
end
local function putPkg(fs, name, m, bodies)
  local dir = "/usr/repo/" .. name
  fs.makeDirectory(dir)
  m.hashes = {}
  for target, body in pairs(bodies) do
    m.hashes[target] = sha256.hex(body)
    fs.writeFile(dir .. target, body)
  end
  fs.writeFile(dir .. "/package.lua", serialize.encode(m))
  return dir
end

print("=== a package cannot write the package manager's trees ===")
print()
local pkg, fs = newPkg()
local mailBody = "return { commands = { mail = function() return 'real mail' end } }"
test("a real mail package installs", pkg.install(putPkg(fs, "mail", {
  name = "mail", version = "1.0.0", kind = "command",
  files = { "/usr/modules/mail/init.lua" },
}, { ["/usr/modules/mail/init.lua"] = mailBody }), { session = ADMIN }))
local MAIL_MANIFEST = "/var/pkg/installed/mail/package.lua"
test("   (its manifest is on disk where pkg.scan reads it)", fs._files[MAIL_MANIFEST] ~= nil)

-- 1. Rewrite mail's installed manifest: its command now runs evil's code,
--    and `pkg info mail` says a trusted publisher signed it.
local forged = serialize.encode({
  name = "mail", version = "9.9.9", kind = "command",
  files = { "/usr/modules/evil/init.lua" },
  commands = { mail = "/usr/modules/evil/init.lua" },
  _sigState = "trusted", _sigLabel = "TOS Project",
})
local evilBody = "return { commands = { mail = function() return 'evil' end } }"
local ok1 = pkg.install(putPkg(fs, "evil", {
  name = "evil", version = "1.0.0", kind = "command",
  files = { "/usr/modules/evil/init.lua", MAIL_MANIFEST },
}, { ["/usr/modules/evil/init.lua"] = evilBody, [MAIL_MANIFEST] = forged }), { session = ADMIN })
test("a package that ships another's installed manifest is refused", not ok1)
test("...mail's manifest on disk is still the real one",
  fs._files[MAIL_MANIFEST] and not fs._files[MAIL_MANIFEST]:find("9.9.9", 1, true))
pkg.scan()
local mail = pkg.info("mail")
test("...and after a rescan `pkg info mail` is the real, unsigned package",
  mail ~= nil and mail.version == "1.0.0" and mail._sigState ~= "trusted")

-- 2. Plant mail's crypto.secret(): read back raw, so the key would be ours.
local ok2 = pkg.install(putPkg(fs, "keyplant", {
  name = "keyplant", version = "1.0.0", kind = "command",
  files = { "/usr/modules/keyplant/init.lua", "/var/pkg/secrets/mail" },
}, { ["/usr/modules/keyplant/init.lua"] = "return {}",
     ["/var/pkg/secrets/mail"] = string.rep("K", 32) }), { session = ADMIN })
test("a package that ships another's secret is refused", not ok2)
test("...and no secret was written", fs._files["/var/pkg/secrets/mail"] == nil)

-- 3. A ghost package nobody installed -- also spelled the way a
--    case-insensitive host reads the same directory -- and the staging area.
for i, target in ipairs({ "/var/pkg/installed/ghost/package.lua",
                          "/var/pkg/Installed/ghost/package.lua",
                          "/var/pkg/remote/r/programs.cfg" }) do
  local name = "ghostly" .. i
  local ok3 = pkg.install(putPkg(fs, name, {
    name = name, version = "1.0.0", kind = "command",
    files = { "/usr/modules/" .. name .. "/init.lua", target },
  }, { ["/usr/modules/" .. name .. "/init.lua"] = "return {}",
       [target] = serialize.encode({ name = "ghost", version = "1.0.0", kind = "command",
         files = { "/usr/modules/" .. name .. "/init.lua" } }) }),
    { session = ADMIN })
  test("a package that ships " .. target .. " is refused", not ok3)
end
pkg.scan()
test("...and no ghost package appeared", pkg.info("ghost") == nil)

print()
print("-- the rest of /var/pkg stays package space --")
test("/var/pkg/<own dir> is still a write root", pkg._isUnderPkgWriteRoot("/var/pkg/demo-state/seed.cfg"))
test("/var/pkg/installed itself is not", not pkg._isUnderPkgWriteRoot("/var/pkg/installed"))
test("a package with a /var/pkg/<own dir> file installs", pkg.install(putPkg(fs, "stateful", {
  name = "stateful", version = "1.0.0", kind = "command",
  files = { "/usr/modules/stateful/init.lua", "/var/pkg/stateful/seed.cfg" },
}, { ["/usr/modules/stateful/init.lua"] = "return {}",
     ["/var/pkg/stateful/seed.cfg"] = "return {}" }), { session = ADMIN }))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
