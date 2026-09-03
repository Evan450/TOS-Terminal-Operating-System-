-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: SHA-256 against FIPS 180-4, at size      ║
-- ║                                                            ║
-- ║  sha256.lua built its padded message with                  ║
-- ║      local bytes = { msg:byte(1, #msg) }                    ║
-- ║  which returns ONE LUA VALUE PER BYTE and overflows the    ║
-- ║  stack ("string slice too long") somewhere past a few      ║
-- ║  hundred thousand bytes.                                    ║
-- ║                                                            ║
-- ║  TODO.txt recorded it as latent, on the stated grounds     ║
-- ║  that "nothing feeds it a file today". That premise has    ║
-- ║  since stopped being true: kernel/backup.lua hashes file   ║
-- ║  bodies through crypto.hash, and crypto.hash falls back to ║
-- ║  this pure-Lua path whenever there is no data card.        ║
-- ║                                                            ║
-- ║  sha512.lua already indexes its padded string in place.    ║
-- ║  This pins that sha256 does too — and that porting it did  ║
-- ║  not change a single digest.                               ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sha256.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "\n        expected " .. tostring(expected)
      .. "\n        got      " .. tostring(actual))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_sha256.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

local sha256 = tryload("tos/kernel/sha256.lua")()

print("=== SHA-256 Tests ===")
print()

-- ── FIPS 180-4 published vectors ───────────────────────────────────
-- Correctness is not a matter of opinion here: these are the values
-- every other implementation on earth produces.
print("-- FIPS 180-4 vectors --")
test("empty string",
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  sha256.hex(""))
test("abc",
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  sha256.hex("abc"))
test("448-bit (two-block boundary)",
  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
test("896-bit",
  "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
  sha256.hex("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
          .. "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"))

-- ── Padding boundaries ─────────────────────────────────────────────
-- 55/56/57 and 63/64/65 straddle the length-field and block edges,
-- which is where an off-by-one in padding hides.
print()
print("-- padding boundaries --")
test("55 bytes (last that fits with its length)",
  "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
  sha256.hex(string.rep("a", 55)))
test("56 bytes (forces a second block)",
  "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
  sha256.hex(string.rep("a", 56)))
test("63 bytes",
  "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
  sha256.hex(string.rep("a", 63)))
test("64 bytes (exactly one block)",
  "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  sha256.hex(string.rep("a", 64)))
test("65 bytes",
  "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
  sha256.hex(string.rep("a", 65)))

-- ── The regression itself ──────────────────────────────────────────
-- The one-million-'a' FIPS vector is the case the old implementation
-- could not reach at all: it raised "stack overflow (string slice too
-- long)" before hashing a byte. A correct digest here proves both that
-- the padding port is faithful AND that the size limit is gone.
print()
print("-- at size (the regression) --")
do
  local big = string.rep("a", 1000000)
  local ok, digest = pcall(sha256.hex, big)
  test("one million 'a' does not overflow the stack", true, ok)
  if ok then
    test("...and matches the FIPS vector",
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
      digest)
  end
end

do
  -- A file-sized input is the case that actually arrives: backup.lua
  -- hashes file bodies, and a TOS disk is 4 MB.
  local ok = pcall(sha256.hex, string.rep("x", 600000))
  test("600 KB (a plausible file) hashes", true, ok)
end

-- ── Shape ──────────────────────────────────────────────────────────
print()
print("-- shape --")
test("digest is 64 hex chars", 64, #sha256.hex("anything"))
test("lowercase hex only", true, sha256.hex("Z"):match("^[0-9a-f]+$") ~= nil)
test("a one-bit change changes the digest", true,
  sha256.hex("a") ~= sha256.hex("b"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
