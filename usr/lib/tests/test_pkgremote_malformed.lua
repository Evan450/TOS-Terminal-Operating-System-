-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a malformed remote index is refused, not      ║
-- ║  thrown                                                         ║
-- ║                                                                ║
-- ║  pkgremote.fetch used every key of an entry's `files` table as  ║
-- ║  a string. An index that wrote the list as an array             ║
-- ║  ({ "a.lua" }) has number keys, and `src:gsub` on one threw out ║
-- ║  of `pkg fetch`. Two refusals (an OPPM directory copy, an       ║
-- ║  unsafe path) left the staged index on disk, and a repo whose   ║
-- ║  index would not load disappeared from the answer ("not in any  ║
-- ║  configured repo").                                             ║
-- ║                                                                ║
-- ║  Drives the REAL pkg.installRemote -> pkgremote.fetch ->        ║
-- ║  pkg.install chain against a fake card and an in-memory disk.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkgremote_malformed.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
package.loaded["kernel.sandbox"] = { build = function() return {} end }
local ROOT = { tier = 3, user = "root" }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return ROOT end }
package.loaded["kernel.sha256"] = loadfile("tos/kernel/sha256.lua")()
package.loaded["kernel.sha512"] = loadfile("tos/kernel/sha512.lua")()
package.loaded["kernel.ed25519"] = loadfile("tos/kernel/ed25519.lua")()
local serialize = loadfile("tos/kernel/serialize.lua")()
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end, ctEquals = function(a,b) return a==b end }

local F = { _f = {} }
local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
function F.exists(p) for k in pairs(F._f) do if under(p, k) then return true end end return false end
function F.readFile(p) return F._f[p] end
function F.writeFile(p, d) F._f[p] = d; return true end
function F.remove(p) for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end return true end
function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
function F.makeDirectory() return true end
function F.mounts() return {} end
function F.list(p) local out, seen = {}, {} for k in pairs(F._f) do if k:sub(1,#p+1)==p.."/" then local h=k:sub(#p+2):match("^([^/]+)") if h and not seen[h] then seen[h]=true out[#out+1]=h end end end return out end
function F.join(...) return (table.concat({...}, "/"):gsub("//+", "/")) end
function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
package.loaded["kernel.fs"] = F

local INDEX
local SERVED = { ["a.lua"] = "print('a')" }
package.loaded["kernel.internet"] = {
  available = function() return true end,
  status = function() return { ok = true } end,
  parseUrl = function() return true end,
  hostOf = function() return "r.example" end,
  -- A miss answers as kernel.internet does: the status, in the error and in meta.
  get = function(url) if url:match("programs%.cfg$") then return INDEX end return nil, "HTTP 404 Not Found", { status = 404, bytes = 0 } end,
  download = function(url, dest) local rel = url:match("https://r%.example/(.*)$"); local b = SERVED[rel]; if not b then return false, "404" end; F._f[dest] = b; return true, nil, { bytes = #b } end,
}
F._f["/etc/pkg-repos.cfg"] = serialize.encode({ { name = "r", url = "https://r.example" } })

local ps = loadfile("tos/kernel/pkgsign.lua")(); ps.init({ fs = F, serialize = serialize }); package.loaded["kernel.pkgsign"] = ps
local pkgremote = loadfile("tos/kernel/pkgremote.lua")(); package.loaded["kernel.pkgremote"] = pkgremote
if pkgremote.init then pkgremote.init({ fs = F, serialize = serialize }) end
local pkg = loadfile("tos/kernel/pkg.lua")(); pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })


local h = sha.hex(SERVED["a.lua"])
local function hashed(extra)
  return '{ app = { files = { ["a.lua"] = "/bin" }' .. (extra or "")
    .. ', hashes = { ["/usr/bin/a.lua"] = "' .. h .. '" } } }'
end

local function staged()
  for k in pairs(F._f) do
    if k:sub(1, #"/var/pkg/remote/") == "/var/pkg/remote/" then return k end
  end
end

-- One fetch: never throws, and leaves staging empty whatever happened.
local function fetch(index)
  INDEX = index
  pkgremote.clearCache()
  F._f["/usr/bin/a.lua"] = nil
  local okC, a, b = pcall(pkg.installRemote, "app", { session = ROOT })
  local installed = pkg.info("app") ~= nil
  pcall(pkg.uninstall, "app", { session = ROOT })
  return okC, a, b, installed
end

print("=== a malformed remote index is refused, not thrown ===")
print()

local refusals = {
  { "a files list written as an array", '{ app = { files = { "a.lua" } } }', "malformed file list" },
  { "a destination that is not a string", '{ app = { files = { ["a.lua"] = 5 } } }', "malformed file list" },
  { "files that are not a table", '{ app = { files = "a.lua" } }', "declares no files" },
  { "hashes that are not a table", '{ app = { files = { ["a.lua"] = "/bin" }, hashes = "zz" } }', "hashes must be a table" },
  { "a version that is not a string", hashed(", version = {}"), "invalid version" },
  { "commands that are not a table", hashed(', commands = "x"'), "commands must be a table" },
  { "an OPPM directory copy", '{ app = { files = { [":dir"] = "/bin" } } }', "directory-copy" },
  { "an unsafe source path", '{ app = { files = { ["../etc/x"] = "/bin" } } }', "unsafe file path" },
}
for _, c in ipairs(refusals) do
  local okC, ok2, err, installed = fetch(c[2])
  test(c[1] .. ": no throw", okC)
  if not okC then print("      (" .. tostring(ok2) .. ")") end
  test(c[1] .. ": refused, saying so", okC and ok2 == false
    and tostring(err):find(c[3], 1, true) ~= nil)
  if okC and not (ok2 == false and tostring(err):find(c[3], 1, true)) then
    print("      (" .. tostring(ok2) .. " " .. tostring(err) .. ")")
  end
  test(c[1] .. ": nothing installed", not installed)
  test(c[1] .. ": staging left empty", staged() == nil)
  if staged() then print("      (left: " .. staged() .. ")") end
end

-- An index that is not a table must not read as "no such package".
for _, c in ipairs({ { "an index that is not a table", "5" }, { "an index that will not parse", "{{{" } }) do
  local okC, ok2, err = fetch(c[2])
  test(c[1] .. ": no throw", okC)
  test(c[1] .. ": the broken repo is named", okC and ok2 == false
    and tostring(err):find("repo 'r' returned an index that is not a table", 1, true) ~= nil)
end

-- The ordinary case still works.
local okC, ok2, _, installed = fetch(hashed())
test("a sane, hashed entry still installs", okC and ok2 == true and installed)
test("...and staging is cleared after it", staged() == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
