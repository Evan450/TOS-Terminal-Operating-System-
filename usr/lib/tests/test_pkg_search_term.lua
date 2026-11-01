-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `pkg search <term>` searches                 ║
-- ║                                                                ║
-- ║  `pkg search` took no term and ignored one, so on a machine    ║
-- ║  pointed at the published repo `pkg search snake` printed all  ║
-- ║  22 packages, with snake among the games.                      ║
-- ║                                                                ║
-- ║  searchHit is LIFTED from C.pkg and run on repo-shaped entries.║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_search_term.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("tos/shell/panels/commands/admin.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local from = src:find("local function searchHit", 1, true)
local to = from and src:find("\n    end\n", from, true)
test("found searchHit in admin.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end
local hit = assert(load(src:sub(from, to + 8) .. "\nreturn searchHit", "=hit", "t", {}))()

local snake = { name = "snake", description = "Classic snake with high scores.", category = "games" }
local mail = { name = "mail", description = "Mesh mail.", category = "network" }
local bare = { name = "web" }

print("=== pkg search matches what a person would look for ===")
test("the name", hit(snake, "snake"))
test("any case", hit(snake, "SNAKE"))
test("part of the description", hit(snake, "high scores"))
test("the category", hit(mail, "network"))
test("not another package", not hit(mail, "snake"))
test("a term is plain text, not a pattern", not hit(snake, "s.ake"))
test("a magic character does not throw", not hit(snake, "%("))
test("an entry with only a name still works", hit(bare, "web") and not hit(bare, "games"))

print("=== the verb uses it ===")
local body = src:match('elseif sub == "search" or sub == "available" then.-\n    elseif sub == "trust"') or ""
test("search reads its term", body:find("local term = args[2]", 1, true) ~= nil)
test("a term with no hits says so", body:find("Nothing available matches", 1, true) ~= nil)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
