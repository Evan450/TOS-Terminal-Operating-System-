-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: saving in the editor never costs the file    ║
-- ║                                                                ║
-- ║  Both saves went through writeFile, which opens with           ║
-- ║  truncation: a save that ran out of room left a cut-off file.  ║
-- ║  The quit prompt's "[y]es" also ignored what the write         ║
-- ║  answered and closed the tab, so a failed save threw the text  ║
-- ║  away too, without a word. ^S said only "Save failed!".        ║
-- ║                                                                ║
-- ║  editor.save is driven for real against a disk that models     ║
-- ║  OpenComputers (truncate on open, a hard capacity); the quit   ║
-- ║  path is pinned in events.lua's source.                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_editor_save.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end,
                                freeMemory = function() return 1e6 end,
                                pullSignal = function() return nil end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.screen"]  = {}
package.loaded["kernel.display"] = {}
local editor = require("shell.panels.editor")

-- ── A disk with a capacity, truncating on open ───────────────────
local files, capacity, calls, readOnly
local function used() local n = 0; for _, d in pairs(files) do n = n + #d end; return n end
local F = {
  exists = function(p) return files[p] ~= nil end,
  size = function(p) return files[p] and #files[p] or 0 end,
  spaceFree = function() return capacity - used() end,
  writeFile = function(p, d)
    calls.writeFile = (calls.writeFile or 0) + 1
    if readOnly then return false, "Write failed: filesystem is read only" end
    files[p] = ""
    if #d > capacity - used() then files[p] = d:sub(1, capacity - used()); return false, "Write failed: not enough space" end
    files[p] = d
    return true
  end,
  writeFileAtomic = function(p, d)
    calls.atomic = (calls.atomic or 0) + 1
    if readOnly then return false, "Write failed: filesystem is read only" end
    if #d > capacity - used() then return false, "Write failed: not enough space" end
    files[p] = d
    return true
  end,
}
local OLD = string.rep("an old line\n", 1000)        -- 12,000 bytes
local NEW = OLD .. "and one more line\n"
local function disk(spare)
  files, calls, readOnly = { ["/d/notes.txt"] = OLD }, {}, false
  capacity = #OLD + spare
end

print("=== room for a second copy: atomic ===")
disk(100000)
local ok, why = editor.save(F, "/d/notes.txt", NEW)
test("saved", ok == true, why)
test("atomically", calls.atomic == 1 and not calls.writeFile)
test("with the new text", files["/d/notes.txt"] == NEW)

print("=== room only once the old bytes are freed: in place ===")
disk(100)
ok, why = editor.save(F, "/d/notes.txt", NEW)
test("saved", ok == true, why)
test("in place", calls.writeFile == 1 and not calls.atomic)
test("with the new text", files["/d/notes.txt"] == NEW)

print("=== less room than the text grew by: refused, untouched ===")
disk(5)
ok, why = editor.save(F, "/d/notes.txt", NEW)
test("refused", ok == false)
test("saying how short", tostring(why):find("13 bytes short", 1, true) ~= nil, why)
test("the file is still the old text", files["/d/notes.txt"] == OLD, #files["/d/notes.txt"])
test("and nothing was written", not calls.writeFile and not calls.atomic)

print("=== a refused write says why, once ===")
disk(100000); readOnly = true
ok, why = editor.save(F, "/d/notes.txt", NEW)
test("refused", ok == false)
test("with the reason", tostring(why) == "filesystem is read only", why)

print("=== a new file saves ===")
disk(100000)
ok = editor.save(F, "/d/new.txt", "hello")
test("saved", ok == true and files["/d/new.txt"] == "hello")

print("=== the quit prompt closes only on a save that landed ===")
do
  local h = assert(io.open("tos/shell/panels/events.lua", "rb"))
  local src = h:read("a"):gsub("\r\n", "\n"); h:close()
  local at = src:find('" Save? [y]es [n]o [c]ancel"', 1, true)
  test("found the quit prompt", at ~= nil)
  local block = at and src:sub(at, at + 3000) or ""
  test("it saves through editor.save", block:find("editorMod.save(F, normPath", 1, true) ~= nil)
  test("and closes only if saved", block:find("if saved then closeTab(); draw = 3 else draw = 1 end", 1, true) ~= nil)
  test("a failed quit-save says so where the editor shows it", block:find("tab.flash = \"NOT SAVED, not closed: \"", 1, true) ~= nil)
  test("and so does a failed ^S", src:find("tab.flash = \"NOT SAVED: \"", 1, true) ~= nil)
  test("no bare writeFile left in either save", not src:find("F.writeFile(normPath", 1, true))
end

print("=== the quit prompt waits for a key press with a character ===")
do
  local h = assert(io.open("tos/shell/panels/events.lua", "rb"))
  local src = h:read("a"):gsub("\r\n", "\n"); h:close()
  local at = src:find('" Save? [y]es [n]o [c]ancel"', 1, true)
  local block = at and src:sub(at, at + 1200) or ""
  -- Lift the wait loop and feed it what a real keyboard sends after ^Q:
  -- the release of Q, the release of Ctrl, a timeout, Shift, then Y.
  local loopSrc = block:match("(local s2, c2 = nil, nil%s+repeat.-until s2)")
  test("found the wait loop", loopSrc ~= nil)
  if loopSrc then
    local feed = {
      { "key_up", "kb", 17, 16 },        -- Q released
      { "key_up", "kb", 0, 29 },         -- Ctrl released
      {},                                -- pullSignal timed out
      { "key_down", "kb", 0, 42 },       -- Shift pressed
      { "key_down", "kb", 89, 21 },      -- Y
    }
    local i = 0
    local env = { pullSignal = function() i = i + 1; return table.unpack(feed[i] or {}) end }
    local fn = load(loopSrc .. "\nreturn s2, c2", "=loop", "t", env)
    local s2, c2 = fn()
    test("releases, a timeout and Shift are not an answer", i == 5, i)
    test("Y is", s2 == "key_down" and c2 == 89, tostring(c2))
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
