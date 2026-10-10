-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a command makes room for the module it needs ║
-- ║                                                                ║
-- ║  The dispatcher gives back the other command categories when   ║
-- ║  a CATEGORY will not load. A command that then require()s a    ║
-- ║  module of its own had no such retry. Found by `tos.py         ║
-- ║  floorcheck`: at 1280 KB with a network card, `pkg list` as    ║
-- ║  the first command worked, but after `mem` it failed with      ║
-- ║  "The package manager needs 1280 KB of RAM; this machine has   ║
-- ║  1280 KB" -- the core category `mem` had left loaded was all   ║
-- ║  that stood in kernel.pkg's way.                               ║
-- ║                                                                ║
-- ║  helpers.requireRoomy retries once, after giving back every    ║
-- ║  category but the one running. Driven here through the real   ║
-- ║  dispatcher (commands.lua) and the real helper.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_require_roomy.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local root
for _, pre in ipairs({ "", "TOS-Dev/" }) do
  local h = io.open(pre .. "tos/shell/panels/commands.lua", "rb")
  if h then h:close(); root = pre; break end
end
if not root then
  print("FAIL: could not locate commands.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local function readSrc(rel)
  local f = io.open(root .. rel, "rb")
  if not f then return "" end
  local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n"))
end

package.loaded["computer"] = {
  freeMemory = function() return 999999 end,
  totalMemory = function() return 1310720 end,
  uptime = function() return 0 end,
}
package.loaded["component"] = { list = function() return function() return nil end end }

local helpers = dofile(root .. "tos/shell/panels/helpers.lua")
package.loaded["shell.panels.helpers"] = helpers
local M = dofile(root .. "tos/shell/panels/commands.lua")

print("=== a command makes room for the module it needs ===")
print()

-- ── The helper on its own ──────────────────────────────────────────
do
  local released = {}
  local S = { releaseCommands = function(keep) released[#released + 1] = keep; return 1 end }
  local tries = 0
  package.preload["fake.tight"] = function()
    tries = tries + 1
    if tries == 1 then error("not enough memory") end
    return { ok = true }
  end
  local ok, mod = helpers.requireRoomy(S, "fake.tight", "admin")
  test("out of memory: the categories are given back and it loads", ok and mod and mod.ok)
  test("...keeping the category that is running", released[1] == "admin" and #released == 1)

  released = {}
  package.preload["fake.broken"] = function() error("attempt to index a nil value") end
  local okB, errB = helpers.requireRoomy(S, "fake.broken", "admin")
  test("a code error is returned as it was", okB == false
    and tostring(errB):find("attempt to index", 1, true) ~= nil)
  test("...and gives nothing back (no memory to win)", #released == 0)

  package.preload["fake.fine"] = function() return { fine = true } end
  local okF = helpers.requireRoomy(S, "fake.fine", "admin")
  test("a module that loads gives nothing back", okF and #released == 0)

  package.preload["fake.hopeless"] = function() error("not enough memory") end
  local okH, errH = helpers.requireRoomy(S, "fake.hopeless", "core")
  test("still short after one retry: the failure comes back", okH == false
    and tostring(errH):find("not enough memory", 1, true) ~= nil)
  test("...after exactly one release", #released == 1 and released[1] == "core")

  local okN, errN = helpers.requireRoomy({}, "fake.never", "admin")
  test("a seat with no release (an older shell) is a plain require",
    okN == false and tostring(errN):find("fake.never", 1, true) ~= nil)
end

-- ── Through the real dispatcher: the bug as the floor check found it ─
do
  local loads = {}
  -- kernel.pkg stand-in: does not fit while the core category is resident.
  package.preload["fake.pkg"] = function()
    if package.loaded["shell.panels.commands.core"] ~= nil then
      error("not enough memory")
    end
    return { list = function() return "No packages installed." end }
  end
  package.preload["shell.panels.commands.core"] = function()
    loads.core = (loads.core or 0) + 1
    return function(C) C.ls = function() return "core" end end
  end
  package.preload["shell.panels.commands.admin"] = function()
    loads.admin = (loads.admin or 0) + 1
    return function(C, S)
      C.flash = function()
        local ok, pkg = helpers.requireRoomy(S, "fake.pkg", "admin")
        return ok and pkg.list() or ("failed: " .. tostring(pkg))
      end
    end
  end
  package.preload["shell.panels.commands.extras"] = function()
    return function(C) C.disk = function() return "extras" end end
  end

  local S = { T = {}, K = {} }
  local C = M.build(S, {})
  test("the dispatcher hands each seat its own release", type(S.releaseCommands) == "function")

  local _ = C.ls  -- `mem`: core is now resident
  test("core is loaded, as after `mem`", package.loaded["shell.panels.commands.core"] ~= nil)
  local out = C.flash()
  test("the module loads once core is given back", out == "No packages installed.", out)
  test("core went", package.loaded["shell.panels.commands.core"] == nil)
  test("the running category stayed", package.loaded["shell.panels.commands.admin"] ~= nil
    and loads.admin == 1)
  local again = C.ls
  test("...and core's commands still work: they reload", again and again() == "core"
    and loads.core == 2)
end

-- ── Every command that loads a module of its own uses it ───────────
do
  local admin = readSrc("tos/shell/panels/commands/admin.lua")
  local core = readSrc("tos/shell/panels/commands/core.lua")
  for _, name in ipairs({ "kernel.pkg", "shell.kiosk", "kernel.diag", "kernel.srm",
                          "kernel.netfs", "kernel.rc", "kernel.cron" }) do
    test("admin: " .. name .. " makes room",
      admin:find('helpers.requireRoomy(S, "' .. name .. '", "admin")', 1, true) ~= nil)
  end
  for _, name in ipairs({ "shell.tutorial", "kernel.vault" }) do
    test("core: " .. name .. " makes room",
      core:find('helpers.requireRoomy(S, "' .. name .. '", "core")', 1, true) ~= nil)
  end
  test("pkg says it needs more RAM only when the machine has less",
    admin:find("if total < PKG_MIN_KB then", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
