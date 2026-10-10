-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a file that cannot be READ is not "missing"  ║
-- ║                                                                ║
-- ║  On the headless machine at 1 MB, `pkg install calc` from a    ║
-- ║  floppy said "missing source file: /mnt/disk1/calc/usr/        ║
-- ║  modules/calc/init.lua". The file was there -- the same disk   ║
-- ║  installed at 1.25 MB. The read had run out of memory, and     ║
-- ║  fs.readFile said so, but pkg kept only the nil. A player is   ║
-- ║  sent looking for a damaged disk. Now a file that exists and   ║
-- ║  will not read gives the reason; only an absent one is         ║
-- ║  "missing". pkg and pkgsign are the real modules.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_read_reason.lua

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_read_reason.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
  error("cannot find " .. rel)
end
local function readSrc(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n")) end
  end
  return ""
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

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local SEED = string.rep("S", 32)
local PUB  = hex(ed.publickey(SEED))

local DIR   = "/mnt/disk1/demo"
local SRC   = DIR .. "/usr/lib/demo.lua"
local BODY  = "return 'the publisher's code'"
local MANIFEST = serialize.encode({ name = "demo", version = "1.0.0", kind = "command",
  files = { "/usr/lib/demo.lua" }, hashes = { ["/usr/lib/demo.lua"] = sha256.hex(BODY) } })
local SIG = serialize.encode({ v = 1, alg = "ed25519", key = PUB,
  sig = hex(ed.sign(MANIFEST, SEED, ed.publickey(SEED))), covers = "package.lua" })

--- A floppy whose source file is there, absent, or there but unreadable
--- the way OC's out-of-memory read is: readFile -> nil, reason.
local function newFS(mode)
  local files, dirs = {}, { ["/"] = true }
  local F
  F = {
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(a, b) return tostring(a):gsub("/$", "") .. "/" .. tostring(b) end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    readFile = function(p)
      if p == SRC and mode == "unreadable" then return nil, "not enough memory" end
      if files[p] == nil then return nil, "File not found: " .. p end
      return files[p]
    end,
    writeFile = function(p, c)
      local acc = ""
      for seg in tostring(p):gmatch("[^/]+") do
        acc = acc .. "/" .. seg
        if acc ~= p then dirs[acc] = true end
      end
      files[p] = c; return true
    end,
    remove = function(p) files[p] = nil; return true end,
    list = function() return {} end,
  }
  F.writeFile(DIR .. "/package.lua", MANIFEST)
  F.writeFile(DIR .. "/package.sig", SIG)
  if mode ~= "absent" then F.writeFile(SRC, BODY) end
  F.writeFile("/etc/pkg_trust.cfg", serialize.encode({ requireSignature = true,
    keys = { publisher = PUB } }))
  return F
end

local ADMIN = { user = "root", tier = 3 }
local usersMock = { currentSession = function() return ADMIN end,
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 } }

local function install(mode)
  local fs = newFS(mode)
  package.loaded["kernel.pkg"] = nil
  local ps = package.loaded["kernel.pkgsign"]
  ps.init({ fs = fs, serialize = serialize }); ps.reloadTrust()
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  local ok, why = pkg.install(DIR, { session = ADMIN })
  return ok, tostring(why), fs
end

print("=== a file that cannot be read is not missing ===")
print()

local ok, why, fs = install("present")
test("control: the package installs", ok, why)
test("...and its file is in place", fs.exists("/usr/lib/demo.lua"))

ok, why, fs = install("unreadable")
test("a file that will not read fails the install", ok == false)
test("...saying it could not be READ, with the reason",
  why:find("cannot read source file " .. SRC .. ": not enough memory", 1, true) ~= nil, why)
test("...not that it is missing", why:find("missing", 1, true) == nil, why)
test("...and nothing is left installed", not fs.exists("/usr/lib/demo.lua"))

ok, why = install("absent")
test("a file that is not there is still \"missing\"",
  ok == false and why:find("missing source file: " .. SRC, 1, true) ~= nil, why)

local pkgSrc = readSrc("tos/kernel/pkg.lua")
test("the installed-file mirror says the same (cannot read vs missing)",
  pkgSrc:find('": cannot read installed file "', 1, true) ~= nil
  and pkgSrc:find('": missing installed file "', 1, true) ~= nil)

local admin = readSrc("tos/shell/panels/commands/admin.lua")
local _, hints = admin:gsub('memoryHint%((%w+), o, "Installing packages"%)', "")
test("both `pkg install` failure paths say what the machine needs", hints == 2, hints)
test("...as the load failure does", admin:find('memoryHint(line, o, "The package manager")', 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
