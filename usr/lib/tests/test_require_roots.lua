-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: require() can reach everywhere the sandbox ║
-- ║  says package code may require FROM                          ║
-- ║                                                              ║
-- ║  Two lists have to agree and lived apart:                    ║
-- ║    • init.lua's `searchPaths` — where tosRequire actually     ║
-- ║      LOOKS for a module;                                     ║
-- ║    • sandbox.lua's `USER_LIB_ROOTS` — where the sandbox's     ║
-- ║      safe-require will AUTHORIZE a user-lib load from.        ║
-- ║                                                              ║
-- ║  They disagreed on /usr/modules: the sandbox checked the file ║
-- ║  existed there and handed off to require, which never looked  ║
-- ║  there and failed with "Module not found". Any package with a ║
-- ║  multi-file module under /usr/modules therefore could not     ║
-- ║  start (emulator round: `calc` requiring calc.sheet, `games`  ║
-- ║  requiring games.logic — both dead on arrival). Single-file   ║
-- ║  packages never noticed, because pkg loads a command entry by ║
-- ║  absolute PATH rather than by module name — which is exactly  ║
-- ║  why this went unnoticed until a package grew a second file.  ║
-- ║                                                              ║
-- ║  The invariant, pinned here: AUTHORIZED implies LOADABLE.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_require_roots.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(path)
  local h = io.open(path, "rb")
  if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, prefix in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(prefix .. rel)
    if s then return s end
  end
end

print("=== require roots vs sandbox user-lib roots ===")
print()

local initSrc    = findUp("init.lua")
local sandboxSrc = findUp("tos/kernel/sandbox.lua")
test("init.lua readable", initSrc ~= nil)
test("kernel/sandbox.lua readable", sandboxSrc ~= nil)
if not (initSrc and sandboxSrc) then
  print(); print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

-- ── Extract both lists from source ─────────────────────────────────
local spBlock = initSrc:match("local searchPaths = (%b{})")
test("searchPaths table found in init.lua", spBlock ~= nil)
local searchPaths = {}
if spBlock then
  for p in spBlock:gmatch('"([^"]+)"') do searchPaths[#searchPaths + 1] = p end
end
test("searchPaths is non-empty (" .. #searchPaths .. " patterns)", #searchPaths > 0)

local rootsBlock = sandboxSrc:match("local USER_LIB_ROOTS = (%b{})")
test("USER_LIB_ROOTS found in sandbox.lua", rootsBlock ~= nil)
local userRoots = {}
if rootsBlock then
  for p in rootsBlock:gmatch('"([^"]+)"') do userRoots[#userRoots + 1] = p end
end
test("USER_LIB_ROOTS is non-empty (" .. #userRoots .. " roots)", #userRoots > 0)

-- ── THE INVARIANT ──────────────────────────────────────────────────
-- The sandbox resolves `a.b` to "<root>/a/b.lua" and "<root>/a/b/init.lua"
-- (nameToCandidatePaths). require must therefore carry BOTH shapes for
-- every root, or an authorized name still fails to load.
local function hasPattern(pat)
  for _, p in ipairs(searchPaths) do if p == pat then return true end end
  return false
end

local missing = {}
for _, root in ipairs(userRoots) do
  local flat = root .. "/?.lua"
  local dir  = root .. "/?/init.lua"
  if not hasPattern(flat) then missing[#missing + 1] = flat end
  -- The dir shape only matters where a package may ship <name>/init.lua.
  -- /usr/modules is exactly that layout, so require it there.
  if root == "/usr/modules" and not hasPattern(dir) then
    missing[#missing + 1] = dir
  end
end
test("every sandbox user-lib root is on require's searchPaths"
  .. (#missing > 0 and ("  [missing: " .. table.concat(missing, ", ") .. "]") or ""),
  #missing == 0)

-- The specific regression, called out by name so a future reader knows
-- which bug this line is about.
test("/usr/modules/?.lua is searchable (calc.sheet / games.logic)",
  hasPattern("/usr/modules/?.lua"))
test("/usr/modules/?/init.lua is searchable (package dir modules)",
  hasPattern("/usr/modules/?/init.lua"))
test("/usr/lib/?.lua is searchable (mail, blockfs, mouse)",
  hasPattern("/usr/lib/?.lua"))

-- ── Precedence: a package must never shadow a kernel module ────────
do
  local firstTos, firstUser
  for i, p in ipairs(searchPaths) do
    if not firstTos and p:sub(1, 5) == "/tos/" then firstTos = i end
    if not firstUser and (p:sub(1, 9) == "/usr/lib/"
      or p:sub(1, 13) == "/usr/modules/") then firstUser = i end
  end
  test("kernel /tos is searched BEFORE any user root",
    firstTos ~= nil and firstUser ~= nil and firstTos < firstUser)
end

-- ── Resolution shape matches the sandbox's own candidate builder ────
-- sandbox.nameToCandidatePaths turns "a.b" into "a/b.lua" + "a/b/init.lua";
-- require substitutes "?" with the same dotted-to-slash name. If those two
-- ever disagree the authorization gate and the loader diverge again.
do
  -- Plain (non-pattern) find: the source literally contains  %.  here.
  local DOT_TO_SLASH = 'name:gsub("%.", "/")'
  test("sandbox resolves dotted names to a slash path",
    sandboxSrc:find(DOT_TO_SLASH, 1, true) ~= nil)
  test("require substitutes the same way",
    initSrc:find(DOT_TO_SLASH, 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
