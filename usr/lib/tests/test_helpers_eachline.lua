-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: grep/wc/head/tail read a line at a time       ║
-- ║                                                                ║
-- ║  Each of the four read the whole file into one string first, so ║
-- ║  `grep` over 200 KB needed ~400 KB on a 256 KB machine and      ║
-- ║  `head` read all of a file to show ten lines (Sep 2026 pentest, ║
-- ║  RAM pass). helpers.eachLine streams 4 KB blocks.               ║
-- ║                                                                ║
-- ║  The stand-in fs samples LIVE heap at every read, so the peak   ║
-- ║  measured is the reader's own. Drives the REAL helpers module.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_helpers_eachline.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
local helpers = require("shell.panels.helpers")

local FILES = {}
local peak, base, reads = 0, 0, 0
local F = {}
function F.open(path, mode)
  if mode ~= "r" or not FILES[path] then return nil, "cannot open " .. tostring(path) end
  local data, pos = FILES[path], 1
  return {
    read = function(_, n)
      reads = reads + 1
      collectgarbage(); collectgarbage()
      local live = collectgarbage("count") - base
      if live > peak then peak = live end
      if pos > #data then return nil end
      local c = data:sub(pos, pos + n - 1); pos = pos + #c; return c
    end,
    close = function() return true end,
  }
end

print("=== helpers.eachLine ===")
print()

do -- a 200 KB file, line by line, with a line straddling every block boundary
  local lines = {}
  for i = 1, 4000 do lines[i] = string.format("line %05d %s", i, string.rep("z", 36)) end
  FILES["/big.txt"] = table.concat(lines, "\n") .. "\n"
  local got, lastGot, bad = 0, nil, 0
  collectgarbage(); collectgarbage(); base = collectgarbage("count"); peak = 0
  local ok, bytes = helpers.eachLine(F, "/big.txt", function(line)
    got = got + 1
    if line ~= lines[got] then bad = bad + 1 end
  end)
  test("every line arrives intact across block edges", ok and got == 4000 and bad == 0)
  test("it reports the bytes read", bytes == #FILES["/big.txt"])
  test(string.format("peak live heap stays near one block (%.1f KB for a %d KB file)",
    peak, #FILES["/big.txt"] // 1024), peak < 32)
  reads = 0
  local seen = 0
  helpers.eachLine(F, "/big.txt", function() seen = seen + 1; if seen >= 10 then return false end end)
  test("stopping early stops reading (head needs one block, not " .. reads .. ")", reads <= 2)
end

do -- the edges
  FILES["/nl.txt"] = "a\nb\n"
  local out = {}
  helpers.eachLine(F, "/nl.txt", function(l) out[#out + 1] = l end)
  test("no phantom empty line after a final newline", #out == 2 and out[2] == "b")
  FILES["/nonl.txt"] = "a\nlast"
  out = {}
  helpers.eachLine(F, "/nonl.txt", function(l) out[#out + 1] = l end)
  test("a last line without a newline is still a line", #out == 2 and out[2] == "last")
  FILES["/crlf.txt"] = "x\r\ny\r\n"
  out = {}
  helpers.eachLine(F, "/crlf.txt", function(l) out[#out + 1] = l end)
  test("CR is left alone (grep on a CRLF file sees what is there)", out[1] == "x\r")
  FILES["/empty.txt"] = ""
  out = {}
  local okE = helpers.eachLine(F, "/empty.txt", function(l) out[#out + 1] = l end)
  test("an empty file yields no lines and no error", okE and #out == 0)
  FILES["/oneline.bin"] = string.rep("q", 200 * 1024)
  local pieces, maxLen = 0, 0
  helpers.eachLine(F, "/oneline.bin", function(l) pieces = pieces + 1; if #l > maxLen then maxLen = #l end end)
  test(string.format("a 200 KB line is handed over in pieces (%d, longest %d KB)", pieces, maxLen // 1024),
    pieces > 1 and maxLen <= 70 * 1024)
  local okM, err = helpers.eachLine(F, "/missing", function() end)
  test("a file that cannot be opened is (false, err)", okM == false and err ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
