-- ╔══════════════════════════════════════════════════════════╗
-- ║  Lint: dev-only files don't leak into TOS-Release         ║
-- ║                                                            ║
-- ║  TOS-Release is a stripped copy of TOS-Dev. The build      ║
-- ║  excludes dev trees, but the test RUNNER (run_tests.sh)    ║
-- ║  once slipped through — it shipped in Release with no       ║
-- ║  tests to run. This guards the exclude list so the same    ║
-- ║  class can't regress: both build-release.sh and .cmd must  ║
-- ║  exclude every dev-only path. And IF a TOS-Release tree is  ║
-- ║  present next to us, it must contain no test artifacts.    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_release_excludes.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readFile(p)
  local fh = io.open(p, "r")
  if not fh then return nil end
  local s = fh:read("*a"); fh:close(); return s
end

print("=== release-exclude lint ===")
print()

-- Paths every Release build MUST exclude (dev-only). Add here when a new
-- dev-only tree/file appears so both build scripts stay honest.
local MUST_EXCLUDE = {
  "/build/", "/usr/lib/tests/", "/run_tests.sh", "/run_tests.py", "/.claude/",
  -- todo_index.py shipped in a Release because it was added beside
  -- run_tests.py without being added HERE. Dev tooling reaches the
  -- image by default; staying out of it is the thing that needs
  -- doing. Any new top-level .py belongs on this list.
  "/todo_index.py",
  "/README.md", "/CHANGELOG.md", "/Codenames.txt", "/TODO.txt",
  -- The manual is an external "sits beside you" reference book, not part of the
  -- lean OS image (`man`/`help` are the in-OS help). The dev roadmap + the
  -- in-emulator checklist are working docs, not shipped.
  "/MANUAL.md", "/EMULATOR_CHECKLIST.md",
  -- Contributor-facing docs, added when the repo went public. They were
  -- excluded in build-release.sh and NOT in build-release.cmd for a
  -- while, because the pin below only covers names listed here -- which
  -- is exactly the drift this list exists to stop. Both now, both pinned.
  "/CONTRIBUTING.md", "/ROADMAP.md", "/SECURITY.md",
  -- The add-on source. It is a SIBLING of TOS-Dev in the monorepo but
  -- sits INSIDE the repo root on the published dev branch, so a
  -- contributor running build-release would otherwise sweep every
  -- package's source into their OS image.
  "/TOS-Extras/",
}

for _, script in ipairs({ "build/build-release.sh", "build/build-release.cmd" }) do
  local src = readFile(script) or readFile("TOS-Dev/" .. script)
  test(script .. " exists", src ~= nil)
  if src then
    for _, ex in ipairs(MUST_EXCLUDE) do
      test(script .. " excludes " .. ex,
        src:find("--exclude " .. ex, 1, true) ~= nil)
    end
  end
end

-- If a built TOS-Release sits beside us, it must carry NO test files or the
-- dev runner. (Best-effort: only checks paths we can open without listing.)
local relRoot
for _, p in ipairs({ "../TOS-Release", "TOS-Release" }) do
  if readFile(p .. "/init.lua") then relRoot = p; break end
end
if relRoot then
  test("Release does NOT ship run_tests.sh", readFile(relRoot .. "/run_tests.sh") == nil)
  test("Release does NOT ship run_tests.py", readFile(relRoot .. "/run_tests.py") == nil)
  -- A couple of known test files that previously could have leaked.
  test("Release has no usr/lib/tests/ unit test",
    readFile(relRoot .. "/usr/lib/tests/test_mesh.lua") == nil)
else
  print("  (no built TOS-Release beside us — skipped on-disk checks)")
end

-- ── Every top-level dev script must be covered ──────────────────
-- The list above catches the scripts someone remembered. todo_index.py
-- shipped in a Release precisely because it was added beside run_tests.py
-- without anyone remembering this file, so pin the RULE rather than the
-- instances: a .py or .sh sitting in the TOS-Dev root is dev tooling, and
-- dev tooling reaches the image unless something stops it.
print()
print("-- top-level dev scripts --")
do
  local ok, pipe = pcall(io.popen, "ls")
  if not ok or not pipe then
    print("  SKIP: io.popen unavailable; cannot enumerate the root")
  else
    local names = {}
    for line in pipe:lines() do names[#names + 1] = line end
    pipe:close()
    local checked = 0
    for _, name in ipairs(names) do
      if name:match("%.py$") or name:match("%.sh$") then
        checked = checked + 1
        local needle = "--exclude /" .. name
        for _, script in ipairs({ "build/build-release.sh", "build/build-release.cmd" }) do
          local src = readFile(script)
          test(script .. " excludes /" .. name,
            src ~= nil and src:find(needle, 1, true) ~= nil)
        end
      end
    end
    test("found at least one top-level dev script to check", checked > 0)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
