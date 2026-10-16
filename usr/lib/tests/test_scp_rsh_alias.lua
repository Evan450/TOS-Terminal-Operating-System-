-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: scp and rsh take a peer the way `net` does   ║
-- ║                                                                ║
-- ║  On the headless machine, two machines trusted and paired:     ║
-- ║  `scp <full address>:/public/hello.txt /tmp/h.txt` downloaded  ║
-- ║  it, and `scp two:/public/hello.txt ...` -- `two` being the    ║
-- ║  alias `net alias add` had just given that same peer --        ║
-- ║  answered "Peer is not TRUSTED". scp and rsh passed the word   ║
-- ║  on as typed; every `net` subcommand resolves it. scp's usage  ║
-- ║  also offered an upload form that nothing implements. Drives   ║
-- ║  the real commands with recording backends.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_scp_rsh_alias.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
                                totalMemory = function() return 2097152 end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end, proxy = function() end }

local FULL = "c5d0c7b6-ba29-42f0-a5b1-e38ff3bacf63"
local asked = {}
package.loaded["kernel.net.transfer"] = {
  request = function(addr, rpath, lpath) asked.scp = addr; return true end,
}
package.loaded["kernel.net.remote"] = {
  execute = function(addr, cmd) asked.rsh = addr; return "ok from " .. addr end,
}
-- The real resolver's contract: an alias, a full address, or a unique prefix.
_G._TOS = { net = { aliases = { resolve = function(s)
  if s == "two" then return FULL end
  if s:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then return s end
  if #s >= 4 and FULL:sub(1, #s) == s then return FULL end
  return nil, "unknown"
end } } }

local okE, register = pcall(require, "shell.panels.commands.extras")
assert(okE and type(register) == "function", tostring(register))
local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, D = {}, U = {}, NM = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end, openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end, canRead = function() return true end,
  canWrite = function() return true end, canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end, promptInput = function() return "" end,
  confirm = function() return true end, confirmTyped = function() return true end,
}
local C = {}
assert(pcall(register, C, S, deps))
local function run(fn, ...)
  local out = {}
  local ok, err = pcall(fn, { ... }, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n"), ok, err
end

print("=== scp and rsh take a peer the way `net` does ===")
print()

local out, ok, err = run(C.scp, "two:/public/hello.txt", "/tmp/h.txt")
test("scp with an alias runs", ok, err)
test("...and asks the ALIASED peer, by its address", asked.scp == FULL, asked.scp)
test("...and says both names", out:find("from two (c5d0c7b6)", 1, true) ~= nil, out)

asked.scp = nil
run(C.scp, FULL .. ":/public/hello.txt", "/tmp/h.txt")
test("a full address still works as before", asked.scp == FULL, asked.scp)
asked.scp = nil
run(C.scp, "c5d0:/public/hello.txt", "/tmp/h.txt")
test("so does a prefix that matches one peer", asked.scp == FULL, asked.scp)
asked.scp = nil
run(C.scp, "nobody:/public/hello.txt", "/tmp/h.txt")
test("an unknown name is passed on, for the trust check to refuse", asked.scp == "nobody", asked.scp)

out = run(C.rsh, "two", "ls")
test("rsh with an alias runs the command on that peer", asked.rsh == FULL, asked.rsh)

out = run(C.scp)
test("scp's usage no longer offers an upload", not out:find("<local_path> <", 1, true)
  and out:find("scp <peer>:<remote_path> <local_path>", 1, true) ~= nil, out)

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
