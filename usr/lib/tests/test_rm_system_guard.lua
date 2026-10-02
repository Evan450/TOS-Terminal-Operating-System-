-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: rm's system-path guard asks securefs first    ║
-- ║                                                                ║
-- ║  rm refused a system path "without -r" BEFORE asking securefs.  ║
-- ║  So `rm /tos/x` said to add -r, and `rm -r /tos/x` then met     ║
-- ║  securefs's protected-path refusal: a second, different error   ║
-- ║  whose fix is `protect off`, after advice that could not help   ║
-- ║  (AUDIT 5). Now securefs's verdict comes first, in its own      ║
-- ║  words, and the -r guard only runs where securefs would let     ║
-- ║  the delete happen -- after root has lifted protection -- as    ║
-- ║  the typed confirmation.                                        ║
-- ║                                                                ║
-- ║  Drives the REAL rm in commands/core.lua and the REAL           ║
-- ║  securefs.removeRefusal, with the override armed for real.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rm_system_guard.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.trash"] = { put = function() return false, "no trash for this session" end }

-- The real securefs, over a disk that only needs to normalize paths.
local ROOT = { user = "root", tier = 3 }
local USERS = { TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 },
                currentSession = function() return ROOT end }
local securefs = require("kernel.securefs")
securefs.init({ fs = { normalize = function(p) return (p:gsub("/+$", "")) end }, users = USERS })
_G._TOS = { securefs = securefs }

local files
local function reset()
  files = { ["/tos/x"] = true, ["/home/a"] = true }
end
local F = {
  isDirectory = function() return false end,
  exists = function(p) return files[p] == true end,
  remove = function(p)
    files[p] = nil; return true
  end,
}
local S = { F = F, U = USERS, T = setmetatable({}, { __index = function() return 0 end }),
            cwd = "/home", K = {}, W = 80, H = 25 }
local C = {}
require("shell.panels.commands.core")(C, S, {
  rp = function(p) return p end,
  canWrite = function() return true end, canRead = function() return true end,
  refreshBrowser = function() end,
})
local function rm(...)
  local out = {}
  C.rm({ ... }, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

print("=== rm asks securefs before demanding -r ===")
print()

test("securefs exposes removeRefusal", type(securefs.removeRefusal) == "function")
test("it refuses /tos/x while protection is on", securefs.removeRefusal("/tos/x", ROOT) ~= nil)
test("...and not /home/a", securefs.removeRefusal("/home/a", ROOT) == nil)

-- Protection ON (the default): one refusal, securefs's, either way.
reset()
local said = rm("/tos/x")
test("rm /tos/x is refused", files["/tos/x"] == true)
test("...with securefs's reason", said:find(securefs.removeRefusal("/tos/x", ROOT), 1, true) ~= nil)
test("...and NOT told to add -r, which could not help", said:find("without -r", 1, true) == nil)
said = rm("-r", "/tos/x")
test("rm -r /tos/x is refused the same way", files["/tos/x"] == true
  and said:find(securefs.removeRefusal("/tos/x", ROOT), 1, true) ~= nil)

-- Protection OFF (root armed the override): -r is the confirmation.
assert(securefs.setOperatorOverride(ROOT, true))
test("with protection off securefs would allow it", securefs.removeRefusal("/tos/x", ROOT) == nil)
reset()
said = rm("/tos/x")
test("rm /tos/x still asks for -r", files["/tos/x"] == true
  and said:find("without -r", 1, true) ~= nil)
test("...saying why: the delete would be real", said:find("Protection is off", 1, true) ~= nil)
rm("-r", "/tos/x")
test("rm -r /tos/x removes it", files["/tos/x"] == nil)
assert(securefs.setOperatorOverride(ROOT, false))

-- Ordinary paths are untouched by either guard.
reset()
rm("/home/a")
test("rm /home/a still removes it", files["/home/a"] == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
