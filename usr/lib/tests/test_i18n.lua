-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.i18n (language catalogs)          ║
-- ║                                                            ║
-- ║  Pins the framework contract: English inline defaults are  ║
-- ║  the guaranteed fallback (no catalog / missing key /       ║
-- ║  corrupt file / broken %-spec), catalogs are validated     ║
-- ║  data, codes are sanitized (path traversal), and the       ║
-- ║  runtime key registry feeds `lang dump`.                   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_i18n.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local i18n = require("kernel.i18n")
local serialize = require("kernel.serialize")

print("=== kernel.i18n Tests ===")
print()

-- In-memory fs stub over /usr/lang.
local disk = {}
local fs = {
  exists   = function(p) return disk[p] ~= nil or p == "/usr/lang" end,
  readFile = function(p) return disk[p] end,
  list     = function(p)
    local out = {}
    for k in pairs(disk) do
      local n = k:match("^/usr/lang/(.+)$")
      if n then out[#out + 1] = n end
    end
    return out
  end,
}
i18n.init({ fs = fs, serialize = serialize, config = nil })

-- ── English defaults with no catalog ───────────────────────────────
eq("no catalog: language is en", "en", i18n.language())
eq("no catalog: t returns the default", "Username:", i18n.t("login.username", "Username:"))
eq("no catalog: format args work", "Welcome, root!", i18n.t("login.welcome", "Welcome, %s!", "root"))
eq("no key, no default: returns the key", "x.y", i18n.t("x.y"))

-- ── Load a catalog ─────────────────────────────────────────────────
disk["/usr/lang/ru.lang"] = serialize.encode({
  meta = { code = "ru", name = "Russkij" },
  strings = {
    ["login.username"] = "Imya:",
    ["login.welcome"]  = "Privet, %s!",
    ["bad.format"]     = "polomano %d",   -- expects a number
  },
})
local ok, err = i18n.setLanguage("ru")
test("setLanguage ru succeeds", ok == true)
eq("language reads back", "ru", i18n.language())
eq("languageName from meta", "Russkij", i18n.languageName())
eq("translated key wins", "Imya:", i18n.t("login.username", "Username:"))
eq("missing key falls back per-key", "Password:", i18n.t("login.password", "Password:"))
eq("translated format string", "Privet, root!", i18n.t("login.welcome", "Welcome, %s!", "root"))

-- Broken %-spec in the catalog: fall back to formatting the ENGLISH default.
eq("broken catalog %-spec falls back to formatted default",
  "broken abc", i18n.t("bad.format", "broken %s", "abc"))

-- ── Reset to English ───────────────────────────────────────────────
test("setLanguage en resets", i18n.setLanguage("en") == true)
eq("back to defaults", "Username:", i18n.t("login.username", "Username:"))

-- ── Validation / sanitization ──────────────────────────────────────
test("unknown catalog refused", not i18n.setLanguage("zz"))
test("traversal code refused", not i18n.setLanguage("../etc/passwd"))
test("uppercase code refused", not i18n.setLanguage("RU"))
test("one-letter code refused", not i18n.setLanguage("r"))
test("valid regional code accepted by pattern", i18n.validCode("pt-br"))

disk["/usr/lang/xx.lang"] = "this is not a table {{{"
test("corrupt catalog refused, language unchanged",
  not i18n.setLanguage("xx") and i18n.language() == "en")

disk["/usr/lang/yy.lang"] = serialize.encode({ meta = {} })  -- no strings
test("catalog without strings refused", not i18n.setLanguage("yy"))

disk["/usr/lang/zz.lang"] = string.rep("-", 70 * 1024)
test("oversized catalog refused", not i18n.setLanguage("zz"))

-- Junk entries inside a valid catalog are dropped, good ones kept.
disk["/usr/lang/aa.lang"] = serialize.encode({
  strings = {
    good = "kept",
    [42]  = "dropped (non-string key)",
    huge  = string.rep("x", 600),        -- over MAX_VAL_LEN
  },
})
test("mixed catalog loads", i18n.setLanguage("aa") == true)
eq("good entry kept", "kept", i18n.t("good", "default"))
eq("oversized value dropped -> default", "default", i18n.t("huge", "default"))
i18n.setLanguage("en")

-- ── available() scan ───────────────────────────────────────────────
local avail = i18n.available()
eq("available: English always first", "en", avail[1].code)
local hasRu = false
for _, l in ipairs(avail) do if l.code == "ru" then hasRu = true end end
test("available: finds ru catalog", hasRu)

-- ── keysSeen registry (feeds `lang dump`) ──────────────────────────
local found = {}
for _, e in ipairs(i18n.keysSeen()) do found[e.key] = e.default end
eq("keysSeen records the English default", "Username:", found["login.username"])
test("keysSeen is sorted", (function()
  local last
  for _, e in ipairs(i18n.keysSeen()) do
    if last and e.key < last then return false end
    last = e.key
  end
  return true
end)())

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
