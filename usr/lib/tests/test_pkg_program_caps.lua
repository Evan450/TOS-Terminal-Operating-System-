-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package's PROGRAMS get its granted caps     ║
-- ║                                                                ║
-- ║  An OPPM package has no `commands` table. Its programs land in  ║
-- ║  /usr/bin and the shell runs them as PATH programs, with the    ║
-- ║  shell's fixed set (fs.read, fs.write, compat.io). So the caps  ║
-- ║  pkg granted at install -- the compat surface's `component` --  ║
-- ║  never reached them: the data loot disk's base64 died requiring ║
-- ║  the data card (headless machine, 2026-10-09).                  ║
-- ║  pkg.capsForFile answers "which caps does this program file    ║
-- ║  run with?" through the SAME filter package commands use.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_program_caps.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_program_caps.lua"
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

local function newFS()
  local files, dirs = {}, { ["/"] = true }
  local F
  F = {
    _files = files,
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(a, b) return (tostring(a):gsub("/$", "")) .. "/" .. tostring(b) end,
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

local function newPkg(fs)
  package.loaded["kernel.pkg"] = nil
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  return pkg
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

print("=== a package's programs run with its granted caps ===")
print()

do
  local fs = newFS()
  -- An OPPM repo checkout: the data loot disk's shape.
  fs.makeDirectory("/mnt/repo/b64")
  fs.writeFile("/mnt/repo/programs.cfg", serialize.encode({
    b64 = { files = { ["master/b64/base64.lua"] = "/bin" } },
  }))
  fs.writeFile("/mnt/repo/b64/base64.lua", "local data = require('data')")
  -- A TOS package that DECLARES its caps and ships a /usr/bin program.
  local tool = "print('tool')"
  fs.makeDirectory("/usr/repo/tool")
  fs.writeFile("/usr/repo/tool/package.lua", serialize.encode({
    name = "tool", version = "1.0.0", kind = "command",
    files = { "/usr/bin/tool.lua" },
    capabilities = { "fs.read", "net" },
    hashes = { ["/usr/bin/tool.lua"] = sha256.hex(tool) },
  }))
  fs.writeFile("/usr/repo/tool/usr/bin/tool.lua", tool)

  local pkg = newPkg(fs)
  local ok, err = pkg.install("/mnt/repo/b64", { session = ADMIN, allowUnverified = true })
  test("the OPPM package installs (" .. tostring(err) .. ")", ok)
  local ok2, err2 = pkg.install("/usr/repo/tool", { session = ADMIN })
  test("the TOS package installs (" .. tostring(err2) .. ")", ok2)

  local caps, owner = pkg.capsForFile("/usr/bin/base64.lua")
  test("base64.lua is owned by b64", owner == "b64")
  test("...and runs with the compat surface it was granted",
    caps and caps["compat.io"] and caps["fs.read"] and caps["fs.write"] and caps["component"])
  test("...and nothing it was not (no net, no legacy)",
    caps and not caps.net and not caps.legacy and count(caps) == 4)

  local tcaps, towner = pkg.capsForFile("/usr/bin/tool.lua")
  test("tool.lua runs with exactly what tool declared",
    towner == "tool" and tcaps and tcaps["fs.read"] and tcaps.net and count(tcaps) == 2)

  test("a path written //usr/bin/... is the same file",
    select(2, pkg.capsForFile("//usr/bin/base64.lua")) == "b64")
  test("a file no package owns gets nothing extra", pkg.capsForFile("/usr/bin/other.lua") == nil)
  test("nil and empty paths get nothing", pkg.capsForFile(nil) == nil and pkg.capsForFile("") == nil)

  -- A disabled package's programs get no grant: disabled means its code is
  -- not to be trusted with anything.
  pkg.setEnabled("b64", false)
  test("a disabled package's program gets nothing extra", pkg.capsForFile("/usr/bin/base64.lua") == nil)
  pkg.setEnabled("b64", true)

  -- The operator's veto applies here exactly as it does to package commands.
  fs.writeFile("/etc/pkg_caps.cfg", serialize.encode({ deny = { b64 = { "component" } } }))
  pkg.reloadCapConfig()
  local vcaps = pkg.capsForFile("/usr/bin/base64.lua")
  test("a cap denied in /etc/pkg_caps.cfg is dropped",
    vcaps and not vcaps.component and vcaps["compat.io"])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
