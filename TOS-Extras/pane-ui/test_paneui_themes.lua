-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: PaneUI's nine themes ARE TOS's nine themes    ║
-- ║                                                                ║
-- ║  PaneUI runs on OpenOS, so it cannot require kernel/theme.lua:  ║
-- ║  it keeps a COPY of the preset table with a comment saying it   ║
-- ║  is "kept in sync with tos/kernel/theme.lua PRESETS". Nothing   ║
-- ║  enforced that, and the README makes the claim out loud --      ║
-- ║  "PaneUI (OpenOS) now renders TOS's nine named themes           ║
-- ║  color-for-color."                                              ║
-- ║                                                                ║
-- ║  Duplicated data plus a promise in a comment is how prose       ║
-- ║  drifts from code, and this repo has been bitten by that twice  ║
-- ║  already. The two tables agree today; this is what keeps them   ║
-- ║  agreeing, and it fails with the exact colour that moved.       ║
-- ║                                                                ║
-- ║  It compares the keys PaneUI actually stores (its base set), so ║
-- ║  TOS adding a key PaneUI does not mirror is not a failure --    ║
-- ║  a key whose VALUE differs, or a whole preset going missing,    ║
-- ║  is.                                                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua pane-ui/test_paneui_themes.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "pane-ui/test_paneui_themes.lua"
local base = here:gsub("[^/\\]*$", "")

local function readFile(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("a"); f:close(); return s
end

-- The kernel sits in one of two places and both are correct: TOS-Extras is
-- a SIBLING of TOS-Dev in the monorepo, and NESTED inside the source tree
-- on the published dev branch. (A test that knew only the first shipped
-- once and failed from a clean clone.)
local themeSrc, themePath
for _, p in ipairs({ base .. "../../TOS-Dev/tos/kernel/theme.lua",
                     base .. "../../tos/kernel/theme.lua",
                     "../TOS-Dev/tos/kernel/theme.lua", "../tos/kernel/theme.lua",
                     "TOS-Dev/tos/kernel/theme.lua", "tos/kernel/theme.lua" }) do
  themeSrc = readFile(p); if themeSrc then themePath = p; break end
end
local paneSrc
for _, p in ipairs({ base .. "PaneUI.lua", "pane-ui/PaneUI.lua",
                     "TOS-Extras/pane-ui/PaneUI.lua" }) do
  paneSrc = readFile(p); if paneSrc then break end
end
if not (themeSrc and paneSrc) then
  print("FAIL: could not read " .. (themeSrc and "PaneUI.lua" or "kernel/theme.lua"))
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Lift each PRESETS literal out of its file and load it as data. Neither
-- module is executed: theme.lua wants the kernel, PaneUI wants OpenOS.
local function liftTable(src, decl)
  local at = src:find(decl)
  if not at then return nil end
  local body = src:sub(at):match("=%s*(%b{})")
  if not body then return nil end
  local chunk = load("return " .. body, "=presets", "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  return ok and t or nil
end

local TOS  = liftTable(themeSrc, "local PRESETS%s*=%s*{")
local PANE = liftTable(paneSrc,  "local TOS_PRESETS%s*=%s*{")

print("=== PaneUI themes match TOS themes ===")
print()
print("  (TOS presets from " .. tostring(themePath) .. ")")
print()

test("the TOS preset table was found", type(TOS) == "table" and next(TOS) ~= nil)
test("PaneUI's copy was found", type(PANE) == "table" and next(PANE) ~= nil)
if not (TOS and PANE) then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

local names = {}
for n in pairs(TOS) do names[#names + 1] = n end
table.sort(names)

test("TOS ships nine named presets (the number the README claims)", #names == 9)

local missing, extra, drift = {}, {}, {}
for _, n in ipairs(names) do
  if type(PANE[n]) ~= "table" then missing[#missing + 1] = n end
end
for n in pairs(PANE) do
  if type(TOS[n]) ~= "table" then extra[#extra + 1] = n end
end
test("PaneUI has every TOS preset (" .. (#missing == 0 and "all" or table.concat(missing, ", ")) .. ")",
  #missing == 0)
test("PaneUI invents none of its own (" .. (#extra == 0 and "none" or table.concat(extra, ", ")) .. ")",
  #extra == 0)

-- Every colour PaneUI stores must be the colour TOS stores.
for _, n in ipairs(names) do
  local tp, pp = TOS[n], PANE[n]
  if type(pp) == "table" then
    local keys, bad = {}, {}
    for k in pairs(pp) do if type(pp[k]) == "number" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do
      if type(tp[k]) ~= "number" then
        bad[#bad + 1] = string.format("%s: PaneUI has 0x%06X, TOS has no such key", k, pp[k])
      elseif tp[k] ~= pp[k] then
        bad[#bad + 1] = string.format("%s: TOS=0x%06X PaneUI=0x%06X", k, tp[k], pp[k])
      end
    end
    test(("theme '%s': %d colours, all matching TOS"):format(n, #keys), #bad == 0)
    for _, b in ipairs(bad) do print("        " .. b); drift[#drift + 1] = b end
  end
end

-- The base set PaneUI mirrors has to be worth mirroring: if it stopped
-- carrying the bar colours, "color-for-color" would be vacuously true.
do
  local d = PANE.default or {}
  local needed = { "bg", "fg", "border", "title", "highlight", "dim",
                   "statusbar_bg", "statusbar_fg", "menubar_bg", "menubar_fg" }
  local absent = {}
  for _, k in ipairs(needed) do if type(d[k]) ~= "number" then absent[#absent + 1] = k end end
  test("PaneUI mirrors the base colour set, not a token subset ("
    .. (#absent == 0 and "all present" or table.concat(absent, ", ")) .. ")", #absent == 0)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
