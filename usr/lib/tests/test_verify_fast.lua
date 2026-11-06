-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: verify does not compile a file twice         ║
-- ║                                                                ║
-- ║  `verify` hashed every file against the manifest and then      ║
-- ║  compiled every .lua to check its syntax. A file whose hash    ║
-- ║  matched is byte for byte the one the release shipped, which   ║
-- ║  compiled when it was built, so the second pass proved nothing ║
-- ║  new: on the headless machine skipping it took verify from     ║
-- ║  81 s to 69 s. A file that does NOT match must still be caught ║
-- ║  (seen there: a changed man page reported HASH, 170 OK, 1      ║
-- ║  damaged), and a file with no hash must still be compiled.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_verify_fast.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local f = assert(io.open("tos/kernel/init.lua", "rb"))
local src = f:read("a"); f:close()
local body = src:match("function kernel%.verifySystem(.-)\nend\n") or ""
test("found verifySystem", body ~= "")

local hashBlock = body:match("if file%.hash and cryptoMod and cryptoMod%.hash then(.-)\n        end\n") or ""
test("found its hash check", hashBlock ~= "")
local mismatchAt = hashBlock:find("hashMismatch = hashMismatch + 1", 1, true)
local okAt = hashBlock:find('printFn("  OK  " .. file.path, cOK)', 1, true)
local skipAt = okAt and hashBlock:find("goto continue_verify", okAt, true)
test("a mismatch is still reported first", mismatchAt ~= nil and okAt ~= nil and mismatchAt < okAt)
test("a match counts as OK", okAt ~= nil and hashBlock:find("ok = ok + 1", okAt, true) ~= nil)
test("...and skips the second compile", skipAt ~= nil)
local syntaxAt = body:find("streamLoad(file.path)", 1, true)
local blockEnd = body:find(hashBlock, 1, true)
test("a file with no hash still reaches the syntax check",
  syntaxAt ~= nil and blockEnd ~= nil and syntaxAt > blockEnd + #hashBlock)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
