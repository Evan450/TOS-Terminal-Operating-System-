-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg's lists show names the remove can take   ║
-- ║                                                                ║
-- ║  `pkg trust list` cut every label at 16 characters and `pkg    ║
-- ║  repo list` every repo name at 14, though pkgsign allows a     ║
-- ║  48-character label and pkgremote a 32-character repo name.    ║
-- ║  Both lists exist to be read back into `pkg trust remove       ║
-- ║  <name>` and `pkg repo remove <name>`, which refused the cut    ║
-- ║  name. Found with ls doing the same to /etc on the headless    ║
-- ║  machine ("component_caps.cfg.examp").                         ║
-- ║                                                                ║
-- ║  Runs the real admin.lua against a stub kernel.pkg.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_list_names.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1024 * 1024 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local LONG_LABEL = "optional-utilities-official"        -- 27, pkgsign allows 48
local LONG_REPO  = "discover-interactive-main"          -- 25, pkgremote allows 32
package.loaded["kernel.pkg"] = {
  trustList = function()
    return { { label = "discover", fingerprint = "335F F7B2 43C5 1D97" },
             { label = LONG_LABEL, fingerprint = "AAAA BBBB CCCC DDDD" } }
  end,
  repos = function()
    return { { name = "local", url = "https://example.org/a" },
             { name = LONG_REPO, url = "https://example.org/b", description = "the main one" } }
  end,
  requireSigned = function() return false end,
  trustRequired = function() return false end,
  discoveredPolicy = function() return "tofu" end,
  knownRepos = function() return {} end,
}

local helpers = require("shell.panels.helpers")
local S = {
  T = setmetatable({}, { __index = function(_, k) return k end }),
  F = {}, K = {}, st = "tok", W = 80, H = 25,
  U = { getSession = function() return { user = "root", tier = 3 } end },
}
local deps = {
  rp = function(p) return p end,
  rootOnly = function(o) return helpers.rootOnly(S, o) end,
  adminOnly = function(o) return helpers.adminOnly(S, o) end,
  promptInput = function() return "" end,
  confirmBox = function() return false end,
  confirm = function() return false end, confirmTyped = function() return false end,
}
local C = {}
assert(loadfile("tos/shell/panels/commands/admin.lua"))()(C, S, deps)
local function run(...)
  local out = {}
  C.pkg({ ... }, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

print("=== pkg trust list ===")
local trust = run("trust", "list")
test("a 27-character label is listed whole", trust:find(LONG_LABEL, 1, true) ~= nil, trust)
local cols = {}
for line in trust:gmatch("[^\n]+") do
  local at = (line:find("^ name ") and line:find("fingerprint", 1, true))
    or line:find("335F", 1, true) or line:find("AAAA", 1, true)
  if at then cols[#cols + 1] = at end
end
test("...and the fingerprints line up under their heading", #cols == 3
  and cols[1] == cols[2] and cols[2] == cols[3], table.concat(cols, ","))

print("=== pkg repo list ===")
local repo = run("repo", "list")
test("a 25-character repo name is listed whole", repo:find(LONG_REPO, 1, true) ~= nil, repo)
local ucols = {}
for line in repo:gmatch("[^\n]+") do
  local at = line:find("https://", 1, true) or line:find(" url", 1, true)
  if at then ucols[#ucols + 1] = at + (line:find(" url", 1, true) and 1 or 0) end
end
test("...and the URLs line up under their heading", #ucols == 3
  and ucols[1] == ucols[2] and ucols[2] == ucols[3], table.concat(ucols, ","))
local descAt = (repo:match("\n( *)the main one") or "")
test("...with the description under the URL", #descAt == ucols[1] - 1, #descAt)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
