-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: serialize.decode tolerates Lua comments  ║
-- ║                                                            ║
-- ║  Hand-authored serialized files — notably pkg              ║
-- ║  `package.lua` manifests — carry a "-- ..." comment header ║
-- ║  before `return {…}` and inline "-- note" comments inside  ║
-- ║  the table. The decoder used to choke on the first "--"    ║
-- ║  ("Invalid number: -"), so EVERY commented manifest failed ║
-- ║  to parse and pkg discovery/install silently found nothing ║
-- ║  on an inserted Optional Utilities disk. decode() now skips ║
-- ║  comments like a real Lua tokenizer.                       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_serialize_comments.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local serialize
for _, p in ipairs({ "tos/kernel/serialize.lua", "TOS-Dev/tos/kernel/serialize.lua" }) do
  local chunk = loadfile(p); if chunk then serialize = chunk(); break end
end
assert(serialize, "could not load serialize.lua")

print("=== serialize comment-tolerance Tests ===")
print()

-- ── Comment header before `return` ─────────────────────────────────
do
  local src = [[
-- a header comment
-- spanning several lines (like a package.lua banner)
return { name = "x", version = "1.0.0" }
]]
  local m = serialize.decode(src)
  test("header + return parses", m ~= nil)
  eq("name read past the header", "x", m and m.name)
end

-- ── Inline comments inside the table body ──────────────────────────
do
  local src = [[
return {
  name = "mouse",          -- the package name
  files = {
    "/usr/lib/mouse.lua",          -- driver
    "/usr/modules/mouse/init.lua", -- demo command
  },
  caps = { "component", "fs.read" },  -- trailing note
}
]]
  local m = serialize.decode(src)
  test("inline comments parse", m ~= nil)
  eq("name", "mouse", m and m.name)
  eq("array of files survived", 2, m and m.files and #m.files)
  eq("first file value", "/usr/lib/mouse.lua", m and m.files and m.files[1])
end

-- ── Block comment --[[ ]] ──────────────────────────────────────────
do
  local src = "--[[ block\nheader ]] return { ok = true }"
  local m = serialize.decode(src)
  test("block comment header parses", m ~= nil and m.ok == true)
end

-- ── Unterminated block comment fails cleanly (no hang) ─────────────
do
  local m, err = serialize.decode("--[[ never closed return { a = 1 }")
  test("unterminated block comment -> nil+err (no hang)", m == nil and err ~= nil)
end

-- ── Existing behaviour preserved ───────────────────────────────────
do
  local enc = serialize.encode({ a = 1, b = { 2, 3 }, s = "hi" })
  local back = serialize.decode(enc)
  test("encode/decode round-trip intact", back and back.a == 1 and back.b[2] == 3 and back.s == "hi")
  eq("raw compact (no return) still parses", 2, (serialize.decode("{1,2,3}") or {})[2])
  -- A literal '-' that IS data (negative number) must still parse.
  eq("negative number still parses", -5, serialize.decode("return -5"))
  -- A '--' that is NOT a comment can't appear in valid serialized data, so
  -- there's nothing to mis-skip; confirm a normal string with a dash is fine.
  eq("string containing a dash", "a-b", serialize.decode('"a-b"'))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
