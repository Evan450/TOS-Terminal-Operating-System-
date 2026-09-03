-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: ROADMAP.md is not stale                  ║
-- ║                                                            ║
-- ║  ROADMAP.md is PUBLISHED -- it is the public view of the   ║
-- ║  open queue, and the only roadmap contributors ever see.   ║
-- ║  It is generated from TODO.txt, which means it can drift   ║
-- ║  from it silently, which is exactly the failure this repo  ║
-- ║  keeps finding in its own docs. So: ask the generator.     ║
-- ║                                                            ║
-- ║  Skips when TODO.txt / the generator are absent -- they    ║
-- ║  are deliberately NOT published to the dev branch (the     ║
-- ║  working notes carry machine-local paths), so a            ║
-- ║  contributor running the suite from a clone must not see   ║
-- ║  a failure for a file they were never given.               ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_roadmap.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

print("=== ROADMAP.md freshness ===")
print()

local function fileExists(p)
  local fh = io.open(p, "r")
  if fh then fh:close(); return true end
  return false
end

if not fileExists("build/make_roadmap.py") or not fileExists("TODO.txt") then
  print("  SKIP: generator or TODO.txt absent (expected on a dev-branch clone)")
  print("Results: 0 passed, 0 failed")
  print("All tests passed.")
  return true
end

test("build/make_roadmap.py is present", true)
test("ROADMAP.md is present", fileExists("ROADMAP.md"))

-- Same exit-code care as test_todo_index.lua: Lua 5.4's os.execute returns
-- `nil, "exit", <code>` for any non-zero exit, so a bare `ok == nil` cannot
-- tell "the roadmap is stale" (1) from "no python here" (127).
local ok, _, code = os.execute("python build/make_roadmap.py --check")
local succeeded = (ok == true) or (ok == 0) or (code == 0)
local missing = (code == 127 or code == 126)

if missing then
  print("  SKIP: python not available; cannot verify the roadmap")
else
  test("ROADMAP.md matches TODO.txt's open entries "
    .. "(if this fails: python build/make_roadmap.py)", succeeded)
end

-- The published file must not leak machine-local paths. The generator
-- scrubs them, but the scrub is only as good as its patterns, and this is
-- the file a stranger reads.
if fileExists("ROADMAP.md") then
  local fh = io.open("ROADMAP.md", "r")
  local body = fh:read("*a")
  fh:close()
  test("no Windows drive paths leaked", body:find("%a:\\") == nil)
  test("no /home/<user> paths leaked", body:find("/home/%a") == nil)
  test("no email addresses leaked", body:find("[%w%.]+@[%w%.]+%.%a%a") == nil)
  test("it actually has content", #body > 2000)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
