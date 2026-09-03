-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: fs.read does not grant fs.write         ║
-- ║                                                            ║
-- ║  sandbox.build bound securefs whenever EITHER cap was      ║
-- ║  present and then handed the WHOLE surface to the sandbox, ║
-- ║  so a package declaring `capabilities = { "fs.read" }` got ║
-- ║  writeFile, remove and rename. securefs still applied the  ║
-- ║  user's ACLs, so it was not privilege escalation -- it was ║
-- ║  the DECLARATION being false, and the capability list is   ║
-- ║  exactly what an operator reads before installing.         ║
-- ║                                                            ║
-- ║  Found by the in-emulator battery, not by this suite. The  ║
-- ║  off-box sandbox tests all build an environment by hand    ║
-- ║  and then assert about the thing they just built; the      ║
-- ║  battery asked the LIVE sandbox what a cap set yields.     ║
-- ║  This is that question, brought off-box so it stays asked. ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_fs_caps.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 500000 end,
  pushSignal = function() end, address = function() return "addr" end,
}
package.loaded["component"] = {
  list = function() return function() end end, proxy = function() end,
}

-- A securefs stand-in exposing both halves, so the only thing deciding
-- what reaches the sandbox is the capability logic under test.
local WRITERS = { "writeFile", "appendFile", "remove", "rename",
                  "makeDirectory", "copy", "mount", "unmount" }
local READERS = { "exists", "isDirectory", "list", "readFile", "size",
                  "lastModified", "spaceTotal", "spaceUsed" }
package.loaded["kernel.securefs"] = {
  forSession = function()
    local t = { open = function(p, m) return { mode = m or "r" } end }
    for _, n in ipairs(READERS) do t[n] = function() return true end end
    for _, n in ipairs(WRITERS) do t[n] = function() return true end end
    return t
  end,
}

local sandbox = require("kernel.sandbox")

local function build(caps)
  local ok, env = pcall(sandbox.build,
    { caps = caps, session = { user = "root", tier = 3 } })
  if not ok then return nil, env end
  return env
end

print("=== sandbox fs capability Tests ===")
print()

print("-- fs.read alone --")
do
  local env = build({ ["fs.read"] = true })
  test("an env is produced", type(env) == "table")
  test("fs is present", env and type(env.fs) == "table")
  if env and type(env.fs) == "table" then
    for _, n in ipairs(READERS) do
      test("reader " .. n .. " is available", env.fs[n] ~= nil)
    end
    for _, n in ipairs(WRITERS) do
      test("writer " .. n .. " is ABSENT", env.fs[n] == nil)
    end
    -- open is the reader that is also a writer; a view forwarding it
    -- unfiltered would hand back everything it just withheld.
    test("open in read mode works", env.fs.open("/x", "r") ~= nil)
    test("open in write mode is refused", env.fs.open("/x", "w") == nil)
    test("open in append mode is refused", env.fs.open("/x", "a") == nil)
    test("open in r+ mode is refused", env.fs.open("/x", "r+") == nil)
    local _, err = env.fs.open("/x", "w")
    test("...and says which capability is missing",
      tostring(err):find("fs.write", 1, true) ~= nil)
    -- Absent, not present-and-refusing: a nil is unambiguous.
    test("a missing writer is nil, not a stub", env.fs.writeFile == nil)
  end
end

print()
print("-- fs.read + fs.write --")
do
  local env = build({ ["fs.read"] = true, ["fs.write"] = true })
  test("fs is present", env and type(env.fs) == "table")
  if env and type(env.fs) == "table" then
    for _, n in ipairs(WRITERS) do
      test("writer " .. n .. " is available", env.fs[n] ~= nil)
    end
    test("open in write mode works", env.fs.open("/x", "w") ~= nil)
  end
end

print()
print("-- neither cap --")
do
  local env = build({})
  test("no fs at all without a cap", env == nil or env.fs == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
