-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: the shell asks about a tie, and says so  ║
-- ║                                                            ║
-- ║  pkg.plan hands a tie between two copies of a dependency   ║
-- ║  (equal trust, version and size, different contents) to    ║
-- ║  opts.chooseCopy (test_pkg_winner_order.lua). The shell's  ║
-- ║  `pkg install` is where an operator can answer it, so:     ║
-- ║    - it asks, one box naming both whole paths;             ║
-- ║    - yes installs the other copy, no keeps the earliest;   ║
-- ║    - --yes never asks and keeps the earliest;              ║
-- ║    - --dry-run never asks and shows the tie;               ║
-- ║    - every install says which copy went in.                ║
-- ║                                                            ║
-- ║  Driven through the real `pkg` command, kernel.pkg and     ║
-- ║  kernel.pkgsign, on one in-memory disk with three mounts.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_tie_shell.lua   (from the TOS-Dev root)

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

package.path = "tos/?.lua;tos/?/init.lua;../../../tos/?.lua;"
  .. "../../../tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_tie_shell.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

package.loaded["computer"]  = { uptime = function() return 0 end,
                                freeMemory = function() return 1e6 end,
                                pullSignal = function() return nil end,
                                beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.screen"]  = {}
package.loaded["kernel.display"] = {}

package.loaded["kernel.sha512"] = tryload("tos/kernel/sha512.lua")()
package.loaded["kernel.sha256"] = tryload("tos/kernel/sha256.lua")()
package.loaded["kernel.curve25519field"] = tryload("tos/kernel/curve25519field.lua")()
package.loaded["kernel.ed25519"] = tryload("tos/kernel/ed25519.lua")()
local serialize = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = {
  hash = function(d) return sha.hex(d) end,
  ctEquals = function(a, b) return a == b end,
}
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.pkgremote"] = { search = function() return {} end }

local ROOT = { tier = 3, user = "root" }
local USERS = { TIER = { ADMIN = 2, ROOT = 3 },
                currentSession = function() return ROOT end }
package.loaded["kernel.users"] = USERS

print("=== pkg install asks about a tie Tests ===")
print()

-- ── A fake disk; list() marks directories with "/", as OC does ──
local function makeFs(mounts)
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
  function F.mounts()
    local out = {}
    for _, mp in ipairs(mounts or {}) do out[#out + 1] = { mountPoint = mp } end
    return out
  end
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

-- A hashed, unsigned package whose one file names the disk it is on.
-- "/mnt/a" and "/mnt/b" are the same length, so two copies tie on size.
local function put(F, root, name, requires)
  local target = "/usr/lib/" .. name .. ".lua"
  local body = "-- " .. name .. " from " .. root
  F._f[root .. "/" .. name .. "/package.lua"] = string.format(
    'return { name = %q, version = "1.0.0", kind = "lib",\n'
    .. '  files = { %q },\n  hashes = { [%q] = %q },\n  requires = %s }\n',
    name, target, target, sha.hex(body), requires or "nil")
  F._f[root .. "/" .. name .. target] = body
end

-- app on /mnt/disk needs lib; lib is on /mnt/a and /mnt/b, tied.
local function world()
  local F = makeFs({ "/mnt/disk", "/mnt/a", "/mnt/b" })
  package.loaded["kernel.pkgsign"] = nil
  local ps = tryload("tos/kernel/pkgsign.lua")()
  ps.init({ fs = F, serialize = serialize })
  package.loaded["kernel.pkgsign"] = ps
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = USERS })
  package.loaded["kernel.pkg"] = pkg
  package.loaded["kernel.fs"] = F
  put(F, "/mnt/disk", "app", '{ "lib" }')
  put(F, "/mnt/a", "lib")
  put(F, "/mnt/b", "lib")
  return F, pkg
end

-- ── The real shell command ───────────────────────────────────
local okA, register = pcall(require, "shell.panels.commands.admin")
if not okA or type(register) ~= "function" then
  print("FAIL: could not load shell/panels/commands/admin.lua: " .. tostring(register))
  print("*** TESTS FAILED ***"); os.exit(1)
end
local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, D = {},
  U = USERS,
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local answer, asked, lastMsg = true, 0, nil
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "y" end,
  confirm = function(msg) asked = asked + 1; lastMsg = msg; return answer end,
  confirmTyped = function() return true end,
}
local C = {}
local okR, rerr = pcall(register, C, S, deps)
if not okR then
  print("FAIL: admin.lua did not register: " .. tostring(rerr))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local function pkgCmd(...)
  local lines = {}
  local okC, err = pcall(C.pkg, { ... }, function(t) lines[#lines + 1] = tostring(t) end)
  if not okC then lines[#lines + 1] = "THREW: " .. tostring(err) end
  return table.concat(lines, "\n")
end
local function reset(a) answer, asked, lastMsg = a, 0, nil end

-- ══════════════════════════════════════════════════════════════════════
print("-- yes: the other copy installs --")
do
  local F, pkg = world()
  reset(true)
  local out = pkgCmd("install", "app")
  ok("app installs", pkg.info("app") ~= nil)
  if not pkg.info("app") then print("      (" .. out .. ")") end
  test("asked once", 1, asked)
  ok("the box names the copy kept", has(lastMsg, "/mnt/a/lib"))
  ok("and the other one", has(lastMsg, "/mnt/b/lib"))
  test("lib came off /mnt/b", "-- lib from /mnt/b", F._f["/usr/lib/lib.lua"])
  ok("the output says which copy went in", has(out, "tie: lib from /mnt/b/lib (your choice)\n       over /mnt/a/lib"))
end

print("-- no: the earliest copy stays --")
do
  local F, pkg = world()
  reset(false)
  local out = pkgCmd("install", "app")
  ok("app installs", pkg.info("app") ~= nil)
  test("asked once", 1, asked)
  test("lib came off /mnt/a", "-- lib from /mnt/a", F._f["/usr/lib/lib.lua"])
  ok("and the output says so", has(out, "tie: lib from /mnt/a/lib (your choice)\n       over /mnt/b/lib"))
end

print("-- --yes never asks --")
do
  local F, pkg = world()
  reset(true)
  local out = pkgCmd("install", "app", "--yes")
  ok("app installs", pkg.info("app") ~= nil)
  test("nobody was asked", 0, asked)
  test("the earliest copy went in", "-- lib from /mnt/a", F._f["/usr/lib/lib.lua"])
  ok("and the output says it was the earliest", has(out, "tie: lib from /mnt/a/lib (the earliest)"))
end

print("-- several names: each install asks and reports --")
do
  local F, pkg = world()
  put(F, "/mnt/disk", "solo")
  reset(true)
  local out = pkgCmd("install", "app", "solo")
  ok("both install", pkg.info("app") ~= nil and pkg.info("solo") ~= nil)
  test("asked once, for app's lib", 1, asked)
  test("the answer held", "-- lib from /mnt/b", F._f["/usr/lib/lib.lua"])
  ok("the tie is reported under app", has(out, "    tie: lib from /mnt/b/lib (your choice)"))
end

print("-- --dry-run shows the tie and asks nothing --")
do
  local F, pkg = world()
  reset(true)
  local out = pkgCmd("install", "app", "--dry-run")
  test("nothing installed", nil, pkg.info("app"))
  test("nobody was asked", 0, asked)
  ok("the tie is shown", has(out, "tie: lib from /mnt/a/lib (the earliest)\n         over /mnt/b/lib"))
  ok("each path on a line of its own, inside 80 columns", (function()
    for line in (out .. "\n"):gmatch("([^\n]*)\n") do if #line > 80 then return false end end
    return true
  end)())
  ok("with what a real install would do", has(out, "a real install asks which copy to use"))
end

print("-- no tie, no noise --")
do
  local F, pkg = world()
  F._f["/mnt/b/lib/package.lua"] = nil
  F._f["/mnt/b/lib/usr/lib/lib.lua"] = nil
  reset(true)
  local out = pkgCmd("install", "app")
  ok("app installs", pkg.info("app") ~= nil)
  test("nobody was asked", 0, asked)
  ok("and no tie line", not has(out, "tie:"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
