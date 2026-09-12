-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the package-command cache is bounded          ║
-- ║                                                                ║
-- ║  pkg cached every package command's entry and sandbox forever   ║
-- ║  once it had run, at 20-82 KB apiece measured on the real       ║
-- ║  add-ons: tetris, calc and write together pinned ~230 KB on a   ║
-- ║  256 KB machine (Sep 2026 pentest, RAM pass). The two most      ║
-- ║  recently used stay; under memory pressure, one.                ║
-- ║                                                                ║
-- ║  Each fake entry holds a 100 KB blob, so what stays resident is ║
-- ║  visible. Drives the REAL pkg.getCommand.                       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_cache_bound.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local NAMES = { "pa", "pb", "pc", "pd" }
local MANIFEST = {}
for _, n in ipairs(NAMES) do
  MANIFEST[n] = { name = n, version = "1.0", kind = "command",
    files = { "/usr/modules/" .. n .. "/init.lua" },
    commands = { ["cmd" .. n] = "/usr/modules/" .. n .. "/init.lua" },
    capabilities = { "fs.read" } }
end
local BLOB_KB = 100
local function entrySrc(n)
  return 'local blob = string.rep("x", ' .. BLOB_KB .. ' * 1024)\n'
    .. 'return { commands = { cmd' .. n .. ' = function() return "ran-' .. n .. '", #blob end } }'
end

local FREE = 1e6
package.loaded["computer"] = { freeMemory = function() return FREE end, uptime = function() return 0 end }
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end,
  loadFile = function(_, path)
    local n = path:match("/([%w]+)/package%.lua$")
    return n and MANIFEST[n] or nil
  end,
}
local builds = 0
package.loaded["kernel.sandbox"] = {
  build = function() builds = builds + 1; return { string = string } end,
}
package.loaded["kernel.users"] = { currentSession = function() return nil end }
local fsMock = {
  exists = function(p) if p:find("/state", 1, true) then return false end; return true end,
  isDirectory = function() return true end, makeDirectory = function() return true end,
  list = function(p) if p == "/var/pkg/installed" then return { "pa", "pb", "pc", "pd" } end; return {} end,
  join = function(...) return table.concat({ ... }, "/") end,
  normalize = function(p) return p end,
  readFile = function(p)
    local n = p:match("^/usr/modules/(%w+)/init%.lua$")
    if n then return entrySrc(n) end
    return nil
  end,
  writeFile = function() return true end,
}

local pkg
for _, p in ipairs({ "tos/kernel/pkg.lua", "TOS-Dev/tos/kernel/pkg.lua" }) do
  local chunk = loadfile(p); if chunk then pkg = chunk(); break end
end
assert(pkg, "could not load pkg.lua")
pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })

local function kb() collectgarbage(); collectgarbage(); return collectgarbage("count") end
local function run(name) local f = pkg.getCommand(name); return f and f() end

print("=== the package-command cache is bounded ===")
print()
local base = kb()
test("a package command resolves and runs", run("cmdpa") == "ran-pa")
run("cmdpb"); run("cmdpc"); run("cmdpd")
local held = kb() - base
test(string.format("after four packages at most two stay resident (%.0f KB; %d KB each)", held, BLOB_KB),
  held < 2.6 * BLOB_KB)

local before = builds
run("cmdpd")
test("the most recent entry is still cached (no rebuild)", builds == before)
run("cmdpc")
test("...and so is the one before it", builds == before)
run("cmdpa")
test("an evicted entry is rebuilt from disk when needed", builds == before + 1)

local fnB = pkg.getCommand("cmdpb")
run("cmdpc"); run("cmdpd")                      -- pushes pb out of the cache
test("a command fetched before its entry was evicted still runs", fnB and fnB() == "ran-pb")
fnB = nil

pkg.flushCommandCache()
FREE = 10 * 1024
base = kb()
run("cmdpa"); run("cmdpb")
held = kb() - base
test(string.format("under memory pressure only one stays (%.0f KB)", held), held < 1.6 * BLOB_KB)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
