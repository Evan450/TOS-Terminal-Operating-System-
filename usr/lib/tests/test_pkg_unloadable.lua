-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: an add-on that will not load says why        ║
-- ║                                                                ║
-- ║  On the headless machine at 1 MB, "Installed: pic" was followed ║
-- ║  by "Unknown command: pic" with nothing in the log: the sandbox ║
-- ║  would not fit, and loadPkgEntry returned nil without a word.  ║
-- ║  Each way of failing now keeps its reason for the shell.       ║
-- ║                                                                ║
-- ║  Drives the real pkg.install and pkg.getCommand over an        ║
-- ║  in-memory disk.                                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_unloadable.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
local ROOT = { tier = 3, user = "root" }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return ROOT end }
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end,
                                    ctEquals = function(a, b) return a == b end }

local F = { _f = {} }
local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
function F.exists(p) for k in pairs(F._f) do if under(p, k) then return true end end return false end
function F.readFile(p) return F._f[p] end
function F.writeFile(p, d) F._f[p] = d; return true end
function F.writeFileAtomic(p, d) F._f[p] = d; return true end
function F.remove(p) for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end return true end
function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
function F.makeDirectory() return true end
function F.mounts() return {} end
function F.list(p)
  local out, seen = {}, {}
  for k in pairs(F._f) do
    if k:sub(1, #p + 1) == p .. "/" then
      local h = k:sub(#p + 2):match("^([^/]+)")
      if h and not seen[h] then seen[h] = true; out[#out + 1] = h end
    end
  end
  return out
end
function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
package.loaded["kernel.fs"] = F

local warned = {}
local log = { warn = function(_, m) warned[#warned + 1] = m end, info = function() end, error = function() end }
local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
package.loaded["kernel.pkgsign"] = pkgsign

-- The sandbox: fine, or too big for this machine.
local tooBig = false
package.preload["kernel.sandbox"] = function()
  if tooBig then error("not enough memory", 0) end
  return { build = function() return setmetatable({}, { __index = _G }) end }
end

local pkg = dofile("tos/kernel/pkg.lua")
pkg.init({ fs = F, log = log, users = package.loaded["kernel.users"] })

local function install(name, source)
  local path = "/usr/modules/" .. name .. "/init.lua"
  local dir = "/repo/" .. name
  F._f[dir .. "/package.lua"] = serialize.encode({
    name = name, version = "1.0.0", kind = "command", description = "d",
    files = { path }, hashes = { [path] = sha.hex(source) },
    commands = { [name] = path }, capabilities = {},
  })
  F._f[dir .. path] = source
  local ok, err = pkg.install(dir, { session = ROOT, allowUnverified = true })
  test("installed " .. name, ok == true, err)
end

print("=== an add-on that will not load says why ===")
print()

local GOOD = "return { commands = { good = function() return 'ran' end } }"
install("good", GOOD)
install("broken", "return {{{")
install("angry", "error('no thank you', 0)")
install("wrong", "return { commands = { other = function() end } }")

tooBig = true
package.loaded["kernel.sandbox"] = nil
test("a sandbox too big for the machine: no command", pkg.getCommand("good") == nil)
local why = pkg.commandFailure("good")
test("...and the reason is kept", tostring(why):find("not enough memory", 1, true) ~= nil, why)
local logged = table.concat(warned, "\n")
test("...and logged, which it was not", logged:find("cannot load good", 1, true) ~= nil, logged)

tooBig = false
package.loaded["kernel.sandbox"] = nil
local fn = pkg.getCommand("good")
test("once there is room it loads", fn ~= nil and fn() == "ran")
test("...and the old reason is forgotten",
  not tostring(pkg.commandFailure("good")):find("memory", 1, true), pkg.commandFailure("good"))

test("a syntax error is a failure with a reason", pkg.getCommand("broken") == nil
  and tostring(pkg.commandFailure("broken")) ~= "nil")
test("an entry that errors gives its error", pkg.getCommand("angry") == nil
  and tostring(pkg.commandFailure("angry")):find("no thank you", 1, true) ~= nil)
test("a manifest naming a command the entry lacks says so", pkg.getCommand("wrong") == nil
  and tostring(pkg.commandFailure("wrong")):find("no such command", 1, true) ~= nil,
  pkg.commandFailure("wrong"))
test("a name nothing provides has no failure: it is simply unknown", pkg.commandFailure("xyzzy") == nil)

local path = "/usr/modules/angry/init.lua"
F._f[path] = nil
test("a missing entry file says which", pkg.getCommand("angry") == nil
  and tostring(pkg.commandFailure("angry")):find(path, 1, true) ~= nil, pkg.commandFailure("angry"))

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
