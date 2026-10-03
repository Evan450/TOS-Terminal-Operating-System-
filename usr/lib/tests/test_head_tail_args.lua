-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: head and tail take -n, and say why they fail ║
-- ║                                                                ║
-- ║  On the headless machine, `head -n 2 /var/log/kernel.log`      ║
-- ║  answered "Cannot read: -n": the manual documents              ║
-- ║  `head [-n N] <file>`, and head took its FIRST word as the     ║
-- ║  file. And `tail /var/log/kernel.log` answered "Cannot read",  ║
-- ║  with no reason, when the file simply did not exist yet (the   ║
-- ║  kernel writes it every 30 seconds).                           ║
-- ║                                                                ║
-- ║  Runs the real `head` and `tail` from core.lua over an         ║
-- ║  in-memory filesystem.                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_head_tail_args.lua   (from TOS-Dev)

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

local files = { ["/f.txt"] = "one\ntwo\nthree\nfour\nfive\n" }
local F = {
  exists = function(p) return files[p] ~= nil end,
  open = function(p, mode)
    local data = files[p]
    if not data then return nil, "file not found" end
    local pos = 1
    return {
      read = function(_, n)
        if pos > #data then return nil end
        local s = data:sub(pos, pos + n - 1); pos = pos + n; return s
      end,
      close = function() end,
    }
  end,
}
local S = { T = setmetatable({}, { __index = function(_, k) return k end }),
            F = F, P = {}, D = {}, K = {}, E = {}, W = 80, H = 25 }
local deps = { rp = function(p) return p end, canRead = function() return true end,
               rootOnly = function() return true end, adminOnly = function() return true end }
local C = {}
assert(loadfile("tos/shell/panels/commands/core.lua"))()(C, S, deps)

local function run(cmd, args)
  local out = {}
  C[cmd](args, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "|")
end

print("=== head and tail take -n, and say why they fail ===")
test("head -n 2 FILE (as the manual has it)", run("head", { "-n", "2", "/f.txt" }) == "one|two",
  run("head", { "-n", "2", "/f.txt" }))
test("head FILE 2 still works", run("head", { "/f.txt", "2" }) == "one|two")
test("head -2 FILE", run("head", { "-2", "/f.txt" }) == "one|two")
test("head FILE: ten lines by default", run("head", { "/f.txt" }) == "one|two|three|four|five")
test("tail -n 2 FILE", run("tail", { "-n", "2", "/f.txt" }) == "four|five",
  run("tail", { "-n", "2", "/f.txt" }))
test("tail FILE 1 still works", run("tail", { "/f.txt", "1" }) == "five")
local missing = run("tail", { "/var/log/kernel.log" })
test("a file that is not there says so", missing:find("No such file", 1, true) ~= nil, missing)
test("head with no file prints its usage with -n", run("head", {}):find("-n", 1, true) ~= nil)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
