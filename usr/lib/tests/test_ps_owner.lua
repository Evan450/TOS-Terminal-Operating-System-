-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `ps` names who owns each process             ║
-- ║                                                                ║
-- ║  On the headless machine, `ps` listed root's own shell with    ║
-- ║  Owner "?". It read `proc.principal.user` from proc.list(),    ║
-- ║  whose entries never carried a principal -- the owner is a     ║
-- ║  plain `user` field there, which the Monitor reads correctly.  ║
-- ║  So every owner was "?", and the visibility rule built on it   ║
-- ║  ("a USER sees their own processes") matched nothing: a USER   ║
-- ║  saw even their own processes as "(other user)". `ps -v`'s     ║
-- ║  caps column was always "-" for the same reason.               ║
-- ║                                                                ║
-- ║  Spawns real processes with the real kernel/process.lua and    ║
-- ║  runs the real `ps` against them.                              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ps_owner.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 1e6 end,
  totalMemory = function() return 4e6 end, pullSignal = function() return nil end,
}
package.loaded["kernel.event"] = { removeSource = function() end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local P = assert(loadfile("tos/kernel/process.lua"))()
package.loaded["kernel.process"] = P
P.spawn("shell:root@1", function() coroutine.yield() end,
  { principal = { user = "root", tier = 3 }, display = 1, inherit = false,
    caps = { component = true } })
P.spawn("job:alice@2", function() coroutine.yield() end,
  { principal = { user = "alice", tier = 1 }, display = 2, inherit = false })

print("=== ps names who owns each process ===")

local function runPs(viewer, args)
  local S = {
    T = setmetatable({}, { __index = function(_, k) return k end }),
    P = P, D = {}, F = {}, K = {}, E = {},
    U = { getSession = function() return viewer end },
    st = "tok", displayIdx = 1, W = 80, H = 25,
  }
  local deps = { rp = function(p) return p end, rootOnly = function() return true end,
                 adminOnly = function() return true end }
  local C = {}
  assert(loadfile("tos/shell/panels/commands/core.lua"))()(C, S, deps)
  local out = {}
  C.ps(args or {}, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

local asRoot = runPs({ user = "root", tier = 3 })
test("root's own shell shows root as its owner", asRoot:find("shell:root@1%s+%S+%s+%S*%s*root") ~= nil, asRoot)
test("alice's job shows alice", asRoot:find("job:alice@2[^\n]*alice") ~= nil)
test("no owner is \"?\"", not asRoot:find(" %?%s+%d") , asRoot)

local asAlice = runPs({ user = "alice", tier = 1 })
test("a USER sees their own process in full", asAlice:find("job:alice@2[^\n]*alice") ~= nil, asAlice)
test("...and someone else's as \"(other user)\"", asAlice:find("(other user)", 1, true) ~= nil)
test("...without its name", not asAlice:find("shell:root@1", 1, true))

local verbose = runPs({ user = "root", tier = 3 }, { "-v" })
test("ps -v lists a process's capabilities", verbose:find("shell:root@1[^\n]*component") ~= nil, verbose)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
