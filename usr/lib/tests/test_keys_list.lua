-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `keys` lists its bindings in a column        ║
-- ║                                                                ║
-- ║  The keys column was a fixed 14, and "Shift+Delete ^X" is 15:  ║
-- ║  on the headless machine it ran into its own description       ║
-- ║  ("Shift+Delete ^X Cut the selection"). Runs the real `keys`   ║
-- ║  from core.lua over the real shell.keys table.                 ║
-- ║                                                                ║
-- ║  Also: the CLI's one-shot live view told `watch ps` to type    ║
-- ║  "watch watch: ps", which is not a command.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_keys_list.lua   (from TOS-Dev)

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

local S = {
  T = setmetatable({}, { __index = function(_, k) return k end }),
  F = { exists = function() return false end, join = function(a, b) return a .. "/" .. b end },
  K = {}, E = {}, P = {}, D = {}, W = 80, H = 25, cwd = "/", who = "root",
}
local C = {}
assert(loadfile("tos/shell/panels/commands/core.lua"))()(C, S, { rp = function(p) return p end })
local out = {}
C.keys({}, function(line) out[#out + 1] = tostring(line) end)

print("=== keys ===")
local helpAt, rows, crowded = {}, 0, {}
for _, line in ipairs(out) do
  -- a binding row: two spaces, an action word, then its keys
  local action = line:match("^  (%l+) ")
  if action and not line:find("^  %^") then
    rows = rows + 1
    -- where the description starts: the first run of 2+ spaces after the keys
    local keysEnd = select(2, line:find("^  %l+%s+%S.-%S%s%s+")) or select(2, line:find("^  %l+%s+%S+%s%s+"))
    helpAt[#helpAt + 1] = keysEnd
    if not keysEnd then crowded[#crowded + 1] = line end
  end
end
test("it lists the bindings", rows >= 5, rows)
test("every binding has two spaces before its description", #crowded == 0, table.concat(crowded, " | "))
local same = true
for i = 2, #helpAt do if helpAt[i] ~= helpAt[1] then same = false end end
test("and the descriptions start in one column", same and #helpAt == rows, table.concat(helpAt, ","))
local widest = 0
for _, line in ipairs(out) do widest = math.max(widest, #line) end
test("no line is wider than 80 columns", widest <= 80, widest)

print("=== the CLI's one-shot live view ===")
local f = assert(io.open("tos/shell/cli.lua", "rb"))
local cli = f:read("a"); f:close()
local body = cli:match("openLiveTab%s*=%s*function(.-)\n    end,") or ""
test("found the one-shot", body ~= "")
test("it no longer builds a command out of the view's label",
  not body:find("'watch \" .. tostring(label)", 1, true), body)
test("it says how to see it again", body:find("Run it again", 1, true) ~= nil)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
