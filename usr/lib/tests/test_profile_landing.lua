-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.profile `landing` field           ║
-- ║                                                            ║
-- ║  Round-trips the new landing preference through save/load  ║
-- ║  against an in-memory securefs stub, and checks the        ║
-- ║  sanitizer drops junk values instead of persisting them.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_profile_landing.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local profile = require("kernel.profile")
local serialize = require("kernel.serialize")

print("=== kernel.profile landing Tests ===")
print()

-- In-memory securefs stub (session-aware signatures, storage ignores them).
local disk = {}
local securefs = {
  exists    = function(path) return disk[path] ~= nil end,
  readFile  = function(path) return disk[path] end,
  writeFile = function(path, data) disk[path] = data; return true end,
}

profile.init({
  securefs = securefs,
  users = nil, theme = nil, env = nil, log = nil,
  serialize = serialize,
})

local sess = { user = "alice", home = "/home/alice" }

-- ── Round trip ─────────────────────────────────────────────────────
local p = profile.load(sess)
eq("fresh profile: landing has no preference", nil, p.landing)

p.landing = "shell"
local ok, err = profile.save(p, sess)
test("save with landing=shell succeeds", ok == true)

local p2, exists = profile.load(sess)
test("profile file exists after save", exists == true)
eq("landing survives the round trip", "shell", p2.landing)

p2.landing = "desktop"
profile.save(p2, sess)
eq("landing updates to desktop", "desktop", profile.load(sess).landing)

-- ── Sanitizer drops junk ───────────────────────────────────────────
-- Write a profile with a nonsense landing straight to the stub disk;
-- load() must sanitize it back to "no preference", not propagate it.
disk["/home/alice/.profile.cfg"] = serialize.encode({
  name = "default", landing = "kiosk-of-doom",
})
eq("junk landing sanitized to nil", nil, profile.load(sess).landing)

disk["/home/alice/.profile.cfg"] = serialize.encode({
  name = "default", landing = 42,
})
eq("non-string landing sanitized to nil", nil, profile.load(sess).landing)

-- Other fields keep working alongside landing.
profile.save({ landing = "desktop", theme = "amber",
               startup = { "echo hi" } }, sess)
local p3 = profile.load(sess)
eq("theme rides along", "amber", p3.theme)
eq("startup rides along", 1, #p3.startup)
eq("landing rides along", "desktop", p3.landing)

-- ── lang field (kernel.i18n language preference) ───────────────────
profile.save({ lang = "ru" }, sess)
eq("lang survives the round trip", "ru", profile.load(sess).lang)

disk["/home/alice/.profile.cfg"] = serialize.encode({ lang = "../etc" })
eq("traversal lang sanitized to nil", nil, profile.load(sess).lang)

disk["/home/alice/.profile.cfg"] = serialize.encode({ lang = "RU" })
eq("uppercase lang sanitized to nil", nil, profile.load(sess).lang)

disk["/home/alice/.profile.cfg"] = serialize.encode({ lang = "pt-br" })
eq("regional lang code accepted", "pt-br", profile.load(sess).lang)

-- ── Guests (no home) still can't save ──────────────────────────────
local ok2 = profile.save({ landing = "desktop" }, { user = "guest", home = nil })
test("no-home session refuses to save", ok2 == false)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
