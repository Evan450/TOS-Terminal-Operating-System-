-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `man pkg` names every pkg subcommand         ║
-- ║                                                                ║
-- ║  usr/man/pkg.man showed install, uninstall, list, info, search ║
-- ║  and make-disk. The network, trust and upgrade verbs -- fetch, ║
-- ║  repo, remote, trust, outdated, upgrade -- and enable/disable  ║
-- ║  were in MANUAL.md only, or nowhere (AUDIT 2). This reads the  ║
-- ║  verbs C.pkg actually dispatches and requires the man page to  ║
-- ║  name each one, so a new verb fails here until it is written   ║
-- ║  down. Aliases (remove, updates, ...) need not be.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_man_complete.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("a"); h:close(); return (s:gsub("\r\n", "\n"))
end

local admin = readAll("tos/shell/panels/commands/admin.lua")
local man = readAll("usr/man/pkg.man")
test("admin.lua and pkg.man are readable", admin ~= nil and man ~= nil)
if not (admin and man) then
  print(string.format("Results: %d passed, %d failed", passed, failed)); print("*** TESTS FAILED ***"); os.exit(1)
end

-- C.pkg's body: from its definition to the next command's.
local from = admin:find("C.pkg = function", 1, true)
local to = from and admin:find("\n  C%.[%w_]+ = function", from + 1)
local body = from and admin:sub(from, to or #admin) or ""
test("found C.pkg's body", #body > 1000, #body)

-- Spellings that are another verb's alias, and need not be in the page.
local ALIAS = {
  available = "search", repos = "repo", checksig = "verify-sig", updates = "outdated",
  ["install-dir"] = "install", ["from-floppy"] = "install", fromfloppy = "install",
  remove = "uninstall", ["export-disk"] = "make-disk",
}
local verbs, seen = {}, {}
for v in body:gmatch('sub == "([%w%-]+)"') do
  if not seen[v] then seen[v] = true; verbs[#verbs + 1] = v end
end
table.sort(verbs)
test("C.pkg dispatches a dozen or more verbs (the scan works)", #verbs >= 12, #verbs)
for _, v in ipairs(verbs) do
  if ALIAS[v] then
    test("'" .. v .. "' is an alias of '" .. ALIAS[v] .. "', which is a verb too", seen[ALIAS[v]] == true)
  else
    test("man pkg names 'pkg " .. v .. "'", man:find("pkg " .. v, 1, true) ~= nil
      or man:find("\n    " .. v .. " ", 1, true) ~= nil or man:find("| " .. v, 1, true) ~= nil)
  end
end

-- The trust and repo actions, which the AUDIT named.
for _, a in ipairs({ "trust list", "trust add", "trust remove", "trust require",
                     "trust discovered", "trust key", "repo list", "repo add",
                     "repo remove", "repo forget" }) do
  test("man pkg names '" .. a .. "'", man:find(a, 1, true) ~= nil)
end

local manual = readAll("MANUAL.md") or ""
test("MANUAL.md names pkg enable", manual:find("pkg enable", 1, true) ~= nil)

-- No line wider than an 80-column screen.
local wide
for line in man:gmatch("[^\n]*") do
  if #line > 80 and not wide then wide = line end
end
test("pkg.man fits an 80-column screen", wide == nil, wide)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
