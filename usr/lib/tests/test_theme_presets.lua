-- ╔══════════════════════════════════════════════════════╗
-- ║  Test: theme presets + profile theme application       ║
-- ║                                                        ║
-- ║  Pins the 2026 palette refresh invariants:             ║
-- ║   - every preset carries the FULL overridable key set   ║
-- ║     (a partial preset leaves the previous theme's       ║
-- ║     syntax colors behind on switch)                     ║
-- ║   - every key is accepted by display.setTheme (catches  ║
-- ║     the input_fg silent-drop class of bug)              ║
-- ║   - contrast pairs are never fg==bg, and the severity   ║
-- ║     ladder title/warning/error stays distinct           ║
-- ║   - profile themes actually apply (REV-2: the old call  ║
-- ║     hit a function kernel.theme never exported), and    ║
-- ║     an explicit ~/.theme.cfg outranks the profile       ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_theme_presets.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_theme_presets.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

local display = tryload("tos/kernel/display.lua")()
local theme   = tryload("tos/kernel/theme.lua")()
local profileChunk = tryload("tos/kernel/profile.lua")
if not (display and theme and profileChunk) then
  print("FAIL: could not load display/theme/profile modules")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== theme preset Tests ===")
print()

-- Every color key a preset must carry (the display-overridable set).
local REQUIRED_KEYS = {
  "bg", "fg", "border", "title", "highlight", "dim",
  "selected_bg", "selected_fg",
  "menubar_bg", "menubar_fg", "menubar_hot",
  "statusbar_bg", "statusbar_fg",
  "error", "warning",
  "panel_bg", "input_bg", "input_fg",
  "syn_keyword", "syn_string", "syn_comment", "syn_number", "syn_func",
  "file_lua", "dir_color",
}
local REQUIRED_SET = {}
for _, k in ipairs(REQUIRED_KEYS) do REQUIRED_SET[k] = true end

local names = theme.list()
test("all 9 presets present", true, #names >= 9)
for _, want in ipairs({ "default", "midnight", "amber", "green", "plasma",
                        "classic", "contrast", "nord", "solarized" }) do
  test("preset exists: " .. want, "table", type(theme.preset(want)))
end

local function isValidColor(v)
  return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 0xFFFFFF
end

for _, name in ipairs(names) do
  local p = theme.preset(name)
  test(name .. ": has description", "string", type(p.description))

  -- Full coverage, no junk keys.
  local missing, extra, badColor = nil, nil, nil
  for _, k in ipairs(REQUIRED_KEYS) do
    if p[k] == nil then missing = missing or k end
    if p[k] ~= nil and not isValidColor(p[k]) then badColor = badColor or k end
  end
  for k in pairs(p) do
    if k ~= "description" and not REQUIRED_SET[k] then extra = extra or k end
  end
  test(name .. ": no missing keys", nil, missing)
  test(name .. ": no unknown keys", nil, extra)
  test(name .. ": all colors valid 24-bit ints", nil, badColor)

  -- Contrast invariants (so ensureContrast never has to self-heal).
  test(name .. ": fg ~= bg", true, p.fg ~= p.bg)
  test(name .. ": selection pair distinct", true, p.selected_fg ~= p.selected_bg)
  test(name .. ": menubar pair distinct", true, p.menubar_fg ~= p.menubar_bg)
  test(name .. ": statusbar pair distinct", true, p.statusbar_fg ~= p.statusbar_bg)
  test(name .. ": input pair distinct", true, p.input_fg ~= p.input_bg)
  test(name .. ": dim readable (~= bg)", true, p.dim ~= p.bg)

  -- Severity ladder: title / warning / error are three colors.
  test(name .. ": title ~= warning", true, p.title ~= p.warning)
  test(name .. ": warning ~= error", true, p.warning ~= p.error)

  -- display.setTheme accepts EVERY key (none silently dropped).
  local plain = {}
  local n = 0
  for k, v in pairs(p) do
    if k ~= "description" then plain[k] = v; n = n + 1 end
  end
  local ok, applied = display.setTheme(plain)
  test(name .. ": setTheme applies all " .. n .. " keys", n, ok and applied)
end

-- ── theme.apply + hasSavedTheme ──────────────────────────────
print()
print("=== theme module wiring ===")
print()

local applhistory = {}
local displayStub = {
  isMonochrome = function() return false end,
  setTheme = function(t)
    applhistory[#applhistory + 1] = t
    local n = 0; for _ in pairs(t) do n = n + 1 end
    return true, n
  end,
}
local savedFiles = {}
local securefsStub = {
  exists = function(path) return savedFiles[path] == true end,
}
theme.init({ display = displayStub, securefs = securefsStub, serialize = {} })

test("apply('nord') succeeds", true, (theme.apply("nord")))
test("current preset tracked", "nord", theme.current().preset)
test("apply('nope') rejected", false, (theme.apply("nope")))
do
  local merged = applhistory[#applhistory]
  local n = 0; for _ in pairs(merged) do n = n + 1 end
  test("apply passes the full key set to display", #REQUIRED_KEYS, n)
end

local sess = { user = "alice", home = "/home/alice" }
test("hasSavedTheme false when nothing saved", false, theme.hasSavedTheme(sess))
savedFiles["/home/alice/.theme.cfg"] = true
test("hasSavedTheme true when .theme.cfg exists", true, theme.hasSavedTheme(sess))

-- Per-key override of a syntax color now round-trips.
test("syn_string is overridable", true, theme.isOverridable("syn_string"))
test("setColor(syn_string) accepted", true, (theme.setColor("syn_string", 0x123456)))

-- ── profile theme application (REV-2 regression) ─────────────
print()
print("=== profile theme application ===")
print()

local appliedPresets = {}
local savedThemeExists = false
local themeStub = {
  apply = function(name) appliedPresets[#appliedPresets + 1] = name; return true end,
  hasSavedTheme = function() return savedThemeExists end,
}
local profile = profileChunk()
profile.init({ securefs = securefsStub, theme = themeStub, serialize = {} })

-- No saved .theme.cfg: the profile preset applies.
savedThemeExists = false
profile.apply({ theme = "amber", env = {}, startup = {} }, { session = sess })
test("profile theme applies when none saved", "amber", appliedPresets[1])

-- Saved .theme.cfg outranks the profile.
appliedPresets = {}
savedThemeExists = true
profile.apply({ theme = "amber", env = {}, startup = {} }, { session = sess })
test("saved theme outranks profile preset", nil, appliedPresets[1])

-- No theme in the profile: nothing applied.
appliedPresets = {}
savedThemeExists = false
profile.apply({ env = {}, startup = {} }, { session = sess })
test("nil profile theme applies nothing", nil, appliedPresets[1])

-- defaults() no longer force-fills a theme (load with no securefs
-- falls back to defaults).
local profile2 = profileChunk()
profile2.init({ serialize = {} })
local d = profile2.load(sess)
test("profile defaults leave theme unset", nil, d.theme)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
