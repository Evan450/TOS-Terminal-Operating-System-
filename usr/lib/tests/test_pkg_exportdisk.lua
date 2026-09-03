-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg.exportDisk (in-TOS add-on builder)   ║
-- ║  - emits <target>/<name>/package.lua + mirrored files      ║
-- ║  - carries the set manifest + README (NOT a picker copy)   ║
-- ║  - admin-gated and refuses system paths                    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_exportdisk.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local TETRIS = {
  name = "tetris", version = "1.1.0", kind = "command",
  files = { "/usr/modules/tetris/init.lua" },
  commands = { tetris = "/usr/modules/tetris/init.lua" },
}
local MOUSE = {
  name = "mouse", version = "1.1.0", kind = "command",
  files = { "/usr/lib/mouse.lua", "/usr/modules/mouse/init.lua" },
}

-- Record every manifest serialize.saveFile writes.
local saved = {}
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function(_, path, m) saved[path] = m; return true end,
  loadFile = function(_, path)
    if path:find("tetris/package.lua", 1, true) then return TETRIS end
    if path:find("mouse/package.lua", 1, true)  then return MOUSE end
    return nil
  end,
}
-- users present so the admin gate is live (not the inert no-users path).
package.loaded["kernel.users"] = { currentSession = function() return nil end }

-- Record every writeFile.
local written = {}
local function norm(p)
  p = p:gsub("/+", "/")
  if #p > 1 and p:sub(-1) == "/" then p = p:sub(1, -2) end
  return p
end
local fsMock = {
  exists = function(p)
    if p:find("/state", 1, true) then return false end     -- absent => enabled
    return true                                             -- PKG_ROOT, target, files
  end,
  isDirectory   = function() return true end,
  makeDirectory = function() return true end,
  list = function(p)
    if p == "/var/pkg/installed" then return { "mouse/", "tetris/" } end
    return {}
  end,
  join = function(...) return norm(table.concat({ ... }, "/")) end,
  normalize = function(p) return norm(p) end,
  readFile = function(p)
    if p:find("/state", 1, true) then return "e" end
    return "-- contents of " .. p .. "\n"                   -- any installed file
  end,
  writeFile = function(p, c) written[p] = c; return true end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_exportdisk.lua"
local base = here:gsub("[^/\\]*$", "")
local pkg
for _, p in ipairs({ base .. "../../../tos/kernel/pkg.lua", "tos/kernel/pkg.lua",
    "TOS-Dev/tos/kernel/pkg.lua" }) do
  local chunk = loadfile(p)
  if chunk then pkg = chunk(); break end
end
if not pkg then
  print("FAIL: could not load pkg.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })

print("=== pkg.exportDisk Tests ===")
print()

test("both packages scanned", true,
  pkg.info("tetris") ~= nil and pkg.info("mouse") ~= nil)

local ADMIN = { tier = 2 }
local ok, summary = pkg.exportDisk("/mnt/out", { session = ADMIN })
test("export succeeds", true, ok)
test("summary lists 2 packages", 2, ok and #summary.packages or -1)
test("summary file count = 3", 3, ok and summary.files or -1)

-- Manifests emitted at <target>/<name>/package.lua.
test("tetris manifest written", TETRIS, saved["/mnt/out/tetris/package.lua"])
test("mouse manifest written",  MOUSE,  saved["/mnt/out/mouse/package.lua"])

-- Files mirrored at their absolute install path under the package dir.
test("tetris file mirrored", true,
  written["/mnt/out/tetris/usr/modules/tetris/init.lua"] ~= nil)
test("mouse lib mirrored", true,
  written["/mnt/out/mouse/usr/lib/mouse.lua"] ~= nil)
test("mouse init mirrored", true,
  written["/mnt/out/mouse/usr/modules/mouse/init.lua"] ~= nil)

-- The disk carries a SET MANIFEST and a README instead of a copy of the
-- picker. The picker moved into the base image: it can only run on a TOS
-- machine (its first act is require("kernel.pkg")), so every machine that
-- could use a shipped copy already has one, and the 40 KB is better spent
-- on packages.
local setSrc = written["/mnt/out/optutil-set.lua"]
test("set manifest written", true, type(setSrc) == "string" and #setSrc > 40)
test("no installer copy shipped", nil, written["/mnt/out/install.lua"])
test("set manifest compiles", "function",
  type(setSrc) == "string" and type((load(setSrc, "=set", "t"))) or "nil")
do
  local okS, setT = pcall(function() return load(setSrc, "=set", "t")() end)
  test("set manifest loads to a table", true, okS and type(setT) == "table")
  test("...naming this disk's packages", true,
    okS and type(setT.packages) == "table" and setT.packages.tetris ~= nil)
  -- The media detector keys on this file to tell an Optional Utilities disk
  -- from a loose pile of packages, so the marker field has to be there.
  test("...and marking it as the utilities set", "optional-utilities",
    okS and setT.set or "?")
end
local readme = written["/mnt/out/README.txt"]
test("README written", true, type(readme) == "string" and #readme > 40)
test("README names the command to run", true,
  type(readme) == "string" and readme:find("pkg install", 1, true) ~= nil)

-- A target subset limits the export and flags unknowns.
saved, written = {}, {}
local ok2, sum2 = pkg.exportDisk("/mnt/out", { only = { "tetris", "ghost" }, session = ADMIN })
test("subset export succeeds", true, ok2)
test("subset includes only tetris", 1, ok2 and #sum2.packages or -1)
test("unknown name reported", true, ok2 and (function()
  for _, p in ipairs(sum2.problems) do if p:find("ghost", 1, true) then return true end end
  return false
end)() or false)

-- Security: refuse system roots and non-admin callers.
local sOk = pkg.exportDisk("/usr", { session = ADMIN })
test("refuses system path /usr", false, sOk)
local gOk, gErr = pkg.exportDisk("/mnt/out", { session = { tier = 1 } })
test("refuses non-admin caller", false, gOk)
test("non-admin error mentions privilege", true,
  type(gErr) == "string" and gErr:find("privileg", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
