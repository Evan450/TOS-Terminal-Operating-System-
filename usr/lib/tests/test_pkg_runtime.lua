-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package says what runtime it needs          ║
-- ║                                                                ║
-- ║  A package written for a newer Lua than the CPU runs failed at  ║
-- ║  LOAD, as a syntax error in somebody else's code. A manifest    ║
-- ║  may now declare `lua = "5.4"` and `tos = ">=1.5.0"`; install   ║
-- ║  and the install plan refuse a machine that does not meet       ║
-- ║  them, and say what to do (sneak-click the CPU). --force goes   ║
-- ║  past it, like any other contradiction.                         ║
-- ║                                                                ║
-- ║  Drives the REAL kernel/pkg.lua over an in-memory disk.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_runtime.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha256 = dofile("tos/kernel/sha256.lua")
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.crypto"] = { hash = function(s) return sha256.hex(s) end,
                                    ctEquals = function(a, b) return a == b end }
_G._TOS = { version = "1.5.0" }

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
    mounts = function() return {} end,
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
      table.sort(out); return out
    end,
    size = function(p) return files[p] and #files[p] or 0 end,
  }
  return F
end

local ROOT = { user = "root", tier = 3 }
local users = { currentSession = function() return ROOT end,
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 },
  canAccessAs = function() return true end,
  getUser = function() return { name = "root", tier = 3 } end }
local function newPkg()
  local fs = newFS()
  local pkg = dofile("tos/kernel/pkg.lua")
  pkg.init({ fs = fs, log = nil, users = users })
  return pkg, fs
end
local function put(fs, name, extra)
  local dir = "/usr/repo/" .. name
  local target = "/usr/lib/" .. name .. ".lua"
  local body = "return '" .. name .. "'"
  local m = { name = name, version = "1.0.0", kind = "lib", files = { target },
              hashes = { [target] = sha256.hex(body) } }
  for k, v in pairs(extra or {}) do m[k] = v end
  fs.writeFile(dir .. "/package.lua", serialize.encode(m))
  fs.writeFile(dir .. target, body)
  return dir
end

local have = tostring(_VERSION):match("(%d+%.%d+)")
print("=== a package says what runtime it needs (this Lua: " .. tostring(have) .. ") ===")
print()

print("-- the Lua architecture --")
do
  local pkg, fs = newPkg()
  local ok, err = pkg.install(put(fs, "future", { lua = "5.9" }), { session = ROOT })
  test("a package needing a newer Lua is refused", not ok)
  test("...saying which Lua it needs and which this is",
    tostring(err):find("needs the Lua 5.9 architecture; this CPU runs Lua " .. have, 1, true) ~= nil)
  test("...and what to do about it", tostring(err):find("Sneak-right-click the CPU", 1, true) ~= nil)
  test("...writing nothing", fs._files["/usr/lib/future.lua"] == nil)
  test("an older requirement installs", pkg.install(put(fs, "old", { lua = "5.3" }), { session = ROOT }) == true)
  test("--force goes past it", pkg.install(put(fs, "forced", { lua = "5.9" }),
    { session = ROOT, force = true }) == true)
end

print()
print("-- the TOS version --")
do
  local pkg, fs = newPkg()
  local ok, err = pkg.install(put(fs, "nextgen", { tos = ">=9.0" }), { session = ROOT })
  test("a package needing a newer TOS is refused", not ok
    and tostring(err):find("needs TOS >=9.0; this is TOS 1.5.0", 1, true) ~= nil)
  test("a satisfied constraint installs", pkg.install(put(fs, "fits", { tos = ">=1.0" }), { session = ROOT }) == true)
  test("pkg.runtimeRefusal is quiet for a package that declares nothing",
    pkg.runtimeRefusal({ name = "plain" }) == nil)
end

print()
print("-- shapes --")
do
  local pkg, fs = newPkg()
  local ok, err = pkg.install(put(fs, "numlua", { lua = 5.3 }), { session = ROOT })
  test("lua must be a string", not ok and tostring(err):find("lua must be", 1, true) ~= nil)
  ok, err = pkg.install(put(fs, "wordlua", { lua = "five" }), { session = ROOT })
  test("...shaped like a version", not ok and tostring(err):find("lua must be", 1, true) ~= nil)
  ok, err = pkg.install(put(fs, "wordtos", { tos = "latest" }), { session = ROOT })
  test("tos must be a constraint", not ok and tostring(err):find("tos must be", 1, true) ~= nil)
end

print()
print("-- the plan sees it first --")
do
  local pkg, fs = newPkg()
  put(fs, "app", { requires = { "deplib" } })
  put(fs, "deplib", { lua = "5.9" })
  local plan = pkg.planByName("/usr/repo/app")
  local found
  for _, c in ipairs(plan and plan.contradictions or {}) do
    if c.kind == "runtime" and c.name == "deplib" then found = c end
  end
  test("a dependency's runtime is a contradiction in the plan", found ~= nil)
  local ok, err = pkg.installByName("/usr/repo/app", { session = ROOT })
  test("...so the install by name is refused before anything is written", not ok
    and fs._files["/usr/lib/app.lua"] == nil and fs._files["/usr/lib/deplib.lua"] == nil)
  test("...naming the dependency", tostring(err):find("'deplib' needs the Lua 5.9", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
