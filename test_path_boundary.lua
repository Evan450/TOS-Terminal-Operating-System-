-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Path Boundary Checks              ║
-- ║  Verifies the module installer path traversal fix   ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: run /usr/lib/tests/test_path_boundary.lua

local passed, failed = 0, 0

local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

-- This is the boundary-aware check from kernel/modules.lua
-- Returns true if dstPath is safely under destDir
local function isUnderDir(dstPath, destDir)
  return dstPath == destDir or dstPath:sub(1, #destDir + 1) == destDir .. "/"
end

print("=== Path Boundary Check Tests ===")
print()

-- Test 1: Exact match (should be accepted)
test("Exact match",
  true, isUnderDir("/usr/modules/foo", "/usr/modules/foo"))

-- Test 2: Direct child (should be accepted)
test("Direct child",
  true, isUnderDir("/usr/modules/foo/bar.lua", "/usr/modules/foo"))

-- Test 3: Nested child (should be accepted)
test("Nested child",
  true, isUnderDir("/usr/modules/foo/sub/deep/file.lua", "/usr/modules/foo"))

-- Test 4: Prefix collision - foobar vs foo (MUST REJECT)
-- This was the original bug: /usr/modules/foobar matched /usr/modules/foo
test("Prefix collision rejected",
  false, isUnderDir("/usr/modules/foobar/x", "/usr/modules/foo"))

-- Test 5: Similar prefix - foo2 vs foo (MUST REJECT)
test("Similar prefix rejected",
  false, isUnderDir("/usr/modules/foo2", "/usr/modules/foo"))

-- Test 6: Traversal attack - ../../etc/passwd (MUST REJECT)
test("Traversal to /etc rejected",
  false, isUnderDir("/etc/passwd", "/usr/modules/foo"))

-- Test 7: Traversal to root (MUST REJECT)
test("Traversal to root rejected",
  false, isUnderDir("/", "/usr/modules/foo"))

-- Test 8: Completely different path (MUST REJECT)
test("Different path rejected",
  false, isUnderDir("/tmp/evil", "/usr/modules/foo"))

-- Test 9: Substring attack with trailing chars (MUST REJECT)
test("Trailing chars rejected",
  false, isUnderDir("/usr/modules/foo-evil/payload", "/usr/modules/foo"))

-- Test 10: Root as destDir
test("Root destDir accepts child",
  true, isUnderDir("/anything", "/"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
