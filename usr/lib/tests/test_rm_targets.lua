-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `rm a b c` removes a, b AND c                 ║
-- ║                                                                ║
-- ║  rm collected every non-flag argument into `targets` and then   ║
-- ║  used targets[1] only. `rm a b c` printed "Removed: a" and left ║
-- ║  b and c exactly where they were, without a word -- the user    ║
-- ║  was told nothing was wrong.                                    ║
-- ║                                                                ║
-- ║  Each path now runs the same checks the single path always did, ║
-- ║  independently: a guard or a trash refusal on one path says so  ║
-- ║  and moves on to the next.                                      ║
-- ║                                                                ║
-- ║  Drives the REAL command table from shell/panels/commands/      ║
-- ║  core.lua against an in-memory filesystem.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rm_targets.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_rm_targets.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = "tos/?.lua;tos/?/init.lua;" .. base .. "../../../tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

-- The trash: refuses whatever `refuse` names, has no trash otherwise
-- (a guest's case, where rm deletes outright and says so).
local refuse = {}
package.loaded["kernel.trash"] = { put = function(p)
  if refuse[p] then return false, "file too large for trash (9 > 4)" end
  return false, "no trash for this session"
end }

local files, dirs
local function reset()
  files = { ["/tmp/a"] = true, ["/tmp/b"] = true, ["/tmp/c"] = true, ["/tmp/d/x"] = true }
  dirs  = { ["/tmp/d"] = true }
end
reset()
local F = {
  isDirectory = function(p) return dirs[p] == true end,
  list = function(p) return dirs[p] and { "x" } or {} end,
  exists = function(p) return files[p] == true or dirs[p] == true end,
  remove = function(p)
    if files[p] then files[p] = nil; return true end
    if dirs[p] then dirs[p] = nil; return true end
    return false, "no such file: " .. p
  end,
}
local S = { F = F, T = setmetatable({}, { __index = function() return 0 end }),
            cwd = "/tmp", K = {}, W = 80, H = 25 }
local C = {}
require("shell.panels.commands.core")(C, S, {
  rp = function(p) return p:sub(1, 1) == "/" and p or ("/tmp/" .. p) end,
  canWrite = function() return true end, canRead = function() return true end,
  refreshBrowser = function() end,
})
local out
local function rm(...)
  out = {}
  C.rm({ ... }, function(line) out[#out + 1] = line end)
  return table.concat(out, "\n")
end

print("=== rm removes every path it is given ===")
print()

reset()
local said = rm("a", "b", "c")
test("rm a b c removes a", files["/tmp/a"] == nil)
test("...and b", files["/tmp/b"] == nil)
test("...and c", files["/tmp/c"] == nil)
test("...and reports each", said:find("Removed: a", 1, true) and said:find("Removed: b", 1, true)
  and said:find("Removed: c", 1, true))

-- A guard on one path stops that path, not the others.
reset()
said = rm("a", "d", "c")
test("a directory without -r is refused...", dirs["/tmp/d"] == true)
test("...and says so", said:find("without -r", 1, true) ~= nil)
test("...while the paths around it still go", files["/tmp/a"] == nil and files["/tmp/c"] == nil)

-- So does a trash refusal: the refused file stays, named, the rest go.
reset()
refuse["/tmp/b"] = true
said = rm("a", "b", "c")
test("a file the trash refuses is kept", files["/tmp/b"] == true)
test("...and the reason is given", said:find("file too large for trash", 1, true) ~= nil)
test("...while a and c still go", files["/tmp/a"] == nil and files["/tmp/c"] == nil)
refuse = {}

-- The single-path command is unchanged.
reset()
said = rm("a")
test("rm a alone still removes a", files["/tmp/a"] == nil and files["/tmp/b"] == true)
test("rm with no path prints usage", rm():find("Usage: rm", 1, true) ~= nil)
reset()
rm("-r", "d")
test("rm -r d removes a directory", dirs["/tmp/d"] == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
