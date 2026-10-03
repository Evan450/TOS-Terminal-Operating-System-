-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: ls takes the flags its manual entry names    ║
-- ║                                                                ║
-- ║  The manual has always said `ls [-l|-a] [dir]`: -l the long    ║
-- ║  form, -a hidden files too, and "no such file" for a missing   ║
-- ║  directory. ls parsed no flags at all. On the headless         ║
-- ║  machine `alias ll ls -l` -- the manual's own example -- then  ║
-- ║  `ll /` printed "0 items": `-l` had become the PATH. A         ║
-- ║  directory that does not exist listed as empty the same way,   ║
-- ║  and the manual's "near-universal `alias ls "ls -a"`" did      ║
-- ║  nothing, since nothing was ever hidden.                       ║
-- ║                                                                ║
-- ║  Runs the real `ls` from core.lua over an in-memory disk.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ls_flags.lua   (from TOS-Dev)

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

local dirs = { ["/"] = { "etc/", "init.lua", ".profile.cfg", "notes.txt" } }
local F = {
  exists = function(p) return dirs[p] ~= nil or p == "/init.lua" or p == "/notes.txt" or p == "/.profile.cfg" end,
  list = function(p) return dirs[p] or {} end,
  size = function() return 2048 end,
  join = function(a, b) return (a:sub(-1) == "/" and a or a .. "/") .. b end,
  lastModified = function() return 1790000000 * 1000 end,
}
local S = { T = setmetatable({}, { __index = function(_, k) return k end }),
            F = F, P = {}, D = {}, K = {}, E = {}, W = 80, H = 25, cwd = "/" }
local deps = { rp = function(p) return p end, canRead = function() return true end,
               rootOnly = function() return true end, adminOnly = function() return true end }
local C = {}
assert(loadfile("tos/shell/panels/commands/core.lua"))()(C, S, deps)

local function ls(args)
  local out = {}
  C.ls(args, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

print("=== ls takes the flags its manual entry names ===")
local long = ls({ "-l", "/" })
test("ls -l / lists the directory, not a path called -l", long:find("init.lua", 1, true) ~= nil, long)
test("...in the long form, with a Modified column", long:find("Modified", 1, true) ~= nil)
local plain = ls({ "/" })
test("ls / leaves dotfiles out", plain:find("init.lua", 1, true) and not plain:find(".profile.cfg", 1, true), plain)
test("...and says they are there", plain:find("hidden", 1, true) ~= nil)
test("ls -a / includes them", ls({ "-a", "/" }):find(".profile.cfg", 1, true) ~= nil)
local la = ls({ "-la", "/" })
test("ls -la / does both", la:find(".profile.cfg", 1, true) and la:find("Modified", 1, true), la)
local missing = ls({ "/nope" })
test("a directory that is not there says so", missing:find("no such file", 1, true) ~= nil, missing)
test("an unknown flag is refused with the usage", ls({ "-x" }):find("Usage: ls", 1, true) ~= nil)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
