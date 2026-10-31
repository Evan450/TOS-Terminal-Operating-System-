-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `trash restore` takes the file's own name   ║
-- ║                                                               ║
-- ║  The manual says `trash restore <name>`, and `rm` says to     ║
-- ║  restore what it just took. But an entry is stored as         ║
-- ║  k.txt~25041.6, so on a headless machine `trash restore       ║
-- ║  k.txt` answered "no such trash entry" for a file `trash      ║
-- ║  list` was showing. Stamped names stay, so two deletions of   ║
-- ║  one name can both be kept; restoring by the old name now     ║
-- ║  works when it means one entry, and names the entries when    ║
-- ║  it means several. Drives the real kernel.trash.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_trash_restore_name.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
local serialize = require("kernel.serialize")
local trash = require("kernel.trash")

local files
local TRASH = "/home/alice/.trash"
local function entry(stored, origin, body)
  files[TRASH .. "/" .. stored] = body
  files[TRASH .. "/" .. stored .. ".trashmeta"] = serialize.encode({ origin = origin, deletedAt = 1 })
end

local securefs = {
  exists = function(p) return files[p] ~= nil end,
  normalize = function(p) return p end,
  readFile = function(p) return files[p] end,
  size = function(p) return #(files[p] or "") end,
  remove = function(p) files[p] = nil; return true end,
  rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
  list = function(dir)
    local out = {}
    for p in pairs(files) do
      if p:sub(1, #dir + 1) == dir .. "/" then out[#out + 1] = p:sub(#dir + 2) end
    end
    return out
  end,
}
local session = { user = "alice", tier = 1, home = "/home/alice" }
trash.init({ securefs = securefs, fs = securefs, users = { currentSession = function() return session end },
             serialize = serialize })

print("=== restoring by the name a person has ===")
files = {}
entry("k.txt~25041.6", "/public/t/k.txt", "keep me")
local ok, where = trash.restore("k.txt", { session = session })
test("the file's own name restores it", ok == true, where)
test("...to where it came from", files["/public/t/k.txt"] == "keep me", where)
test("...and the entry is gone from the trash", files[TRASH .. "/k.txt~25041.6"] == nil
  and files[TRASH .. "/k.txt~25041.6.trashmeta"] == nil)

files = {}
entry("k.txt~25041.6", "/public/t/k.txt", "keep me")
ok, where = trash.restore("k.txt~25041.6", { session = session })
test("the stored name still works", ok == true and files["/public/t/k.txt"] == "keep me", where)

files = {}
entry("k.txt~1.0", "/public/k.txt", "old")
entry("k.txt~2.0", "/home/alice/k.txt", "new")
ok, where = trash.restore("k.txt", { session = session })
test("a name that means two entries restores neither", ok == false
  and files["/public/k.txt"] == nil and files["/home/alice/k.txt"] == nil, where)
test("...and names both", tostring(where):find("k.txt~1.0", 1, true) ~= nil
  and tostring(where):find("k.txt~2.0", 1, true) ~= nil, where)

ok, where = trash.restore("nothing.txt", { session = session })
test("a name nothing matches says so", ok == false
  and tostring(where):find("no such trash entry", 1, true) ~= nil, where)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
