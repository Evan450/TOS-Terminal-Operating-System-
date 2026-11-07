-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the log's last-resort append keeps the log   ║
-- ║                                                                ║
-- ║  On a filesystem with writeFile and neither appendFile nor     ║
-- ║  open, log.flush appends by reading the file and writing it    ║
-- ║  back. It read with `readFile(path) or ""`, so a read that     ║
-- ║  failed rewrote the log with only the new entries. Same shape  ║
-- ║  as the lost files in kernel.backup, tape store and the        ║
-- ║  editor; kernel.fs has appendFile, so TOS itself never takes   ║
-- ║  this path, but anything that attaches another fs does.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_log_fallback_append.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }
local log = dofile("tos/kernel/log.lua")

-- writeFile and readFile only: the last-resort path.
local files, failRead = {}, false
local FS = {
  exists = function(p) return files[p] ~= nil end,
  readFile = function(p)
    if failRead then return nil, "not enough memory" end
    return files[p]
  end,
  writeFile = function(p, d) files[p] = d; return true end,
}

print("=== appending through read + write ===")
log.attachFile(FS, "/var/log/kernel.log")
files["/var/log/kernel.log"] = "OLD LINE\n"
log.info("test", "first new entry")
local ok = log.flush()
test("a flush succeeds", ok == true, ok)
local text = files["/var/log/kernel.log"] or ""
test("the old line is kept", text:find("OLD LINE", 1, true) ~= nil, text)
test("the new entry is added", text:find("first new entry", 1, true) ~= nil, text)

print("=== a read that fails leaves the log alone ===")
failRead = true
log.info("test", "second new entry")
local ok2, why = log.flush()
failRead = false
test("the flush reports failure", ok2 == false, ok2)
test("saying why", tostring(why):find("cannot read the log", 1, true) ~= nil, why)
text = files["/var/log/kernel.log"] or ""
test("the old line is still there", text:find("OLD LINE", 1, true) ~= nil, text)

print("=== an absent log starts empty ===")
files = {}
log.info("test", "third new entry")
local ok3 = log.flush()
test("a flush to a missing log succeeds", ok3 == true, ok3)
test("and writes the entry", (files["/var/log/kernel.log"] or ""):find("third new entry", 1, true) ~= nil)

log.detachFile()
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
