-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: panels.settingsapp (page model)          ║
-- ║                                                            ║
-- ║  Pure model only: buildPages (page/row construction, tier  ║
-- ║  gating of System buttons, widget toggles) and             ║
-- ║  defaultLanding. Live persistence paths run in-emulator.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_settings_model.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local settings = require("shell.panels.settingsapp")

print("=== panels.settingsapp Tests ===")
print()

local deps = {
  themeNames = { "default", "green", "amber" },
  themeCurrent = "green",
  langCodes = { "en", "ru" },
  language = "ru",
  langName = "Russkij",
  widgetsAvailable = { "memory", "disk", "clock" },
  widgetsEnabled = { memory = true, disk = true },
  landing = "shell",
  userTier = 3,
  canProfile = true,
}
local pages = settings.buildPages(deps)

local byId = {}
for _, p in ipairs(pages) do byId[p.id] = p end

eq("pages: five pages", 5, #pages)
test("pages: appearance/statusbar/desktop/language/system", byId.appearance ~= nil
  and byId.statusbar ~= nil and byId.desktop ~= nil
  and byId.language ~= nil and byId.system ~= nil)

-- ── Appearance ─────────────────────────────────────────────────────
local themeRow
for _, r in ipairs(byId.appearance.rows) do
  if r.id == "theme" then themeRow = r end
end
test("appearance: theme choice row present", themeRow ~= nil)
eq("appearance: current theme carried", "green", themeRow.value)
eq("appearance: presets carried", 3, #themeRow.values)
local haveSave, haveReset = false, false
for _, r in ipairs(byId.appearance.rows) do
  if r.id == "theme_save" then haveSave = true end
  if r.id == "theme_reset" then haveReset = true end
end
test("appearance: save + reset buttons", haveSave and haveReset)

-- ── Status bar ─────────────────────────────────────────────────────
local toggles = {}
for _, r in ipairs(byId.statusbar.rows) do
  if r.kind == "toggle" then toggles[r.label] = r.value end
end
eq("statusbar: enabled widget checked", true, toggles.memory)
eq("statusbar: disabled widget unchecked", false, toggles.clock)

-- ── Desktop page ───────────────────────────────────────────────────
local landingRow
for _, r in ipairs(byId.desktop.rows) do
  if r.id == "landing" then landingRow = r end
end
-- The Desktop and the Shell are one tab now, so this picks a VIEW. The
-- stored value is unchanged for back-compat, which is why the page maps
-- "shell" onto "files" rather than showing it raw.
test("home: landing row present", landingRow ~= nil)
eq("home: a stored 'shell' shows as the files view", "files", landingRow.value)
eq("home: two landing choices", 2, #landingRow.values)
eq("home: the choices are views", "tiles files",
  table.concat(landingRow.values, " "))

-- ── Language page ──────────────────────────────────────────────────
local langRow
for _, r in ipairs(byId.language.rows) do
  if r.id == "uilang" then langRow = r end
end
test("language: choice row present", langRow ~= nil)
eq("language: current code carried", "ru", langRow.value)
eq("language: catalog codes carried", 2, #langRow.values)

-- ── System page: tier gating ───────────────────────────────────────
local function hasButton(page, id)
  for _, r in ipairs(page.rows) do if r.id == id then return true end end
  return false
end
test("system: admin sees bootsettings", hasButton(byId.system, "run:bootsettings"))
test("system: everyone sees doctor", hasButton(byId.system, "run:doctor"))

local userPages = settings.buildPages({
  themeNames = {}, widgetsAvailable = {}, widgetsEnabled = {},
  landing = "desktop", userTier = 1, canProfile = true,
})
local userSys
for _, p in ipairs(userPages) do if p.id == "system" then userSys = p end end
test("system: tier-1 user does NOT see bootsettings",
  not hasButton(userSys, "run:bootsettings"))
test("system: tier-1 user does NOT see users",
  not hasButton(userSys, "run:users"))
test("system: tier-1 user still sees doctor", hasButton(userSys, "run:doctor"))

-- ── No-home session gets the explanatory info line ─────────────────
local guestPages = settings.buildPages({
  themeNames = {}, widgetsAvailable = {}, widgetsEnabled = {},
  landing = "desktop", userTier = 0, canProfile = false,
})
local guestDesk
for _, p in ipairs(guestPages) do if p.id == "desktop" then guestDesk = p end end
local saysNoHome = false
for _, r in ipairs(guestDesk.rows) do
  if r.kind == "info" and tostring(r.text):find("home", 1, true) then saysNoHome = true end
end
test("desktop: guest sees the no-profile explanation", saysNoHome)

-- ── defaultLanding ─────────────────────────────────────────────────
eq("landing default: root -> shell", "shell", settings.defaultLanding("root"))
eq("landing default: user -> desktop", "desktop", settings.defaultLanding("alice"))
eq("landing default: guest -> desktop", "desktop", settings.defaultLanding("guest"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
