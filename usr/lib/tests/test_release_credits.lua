-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the release keeps its licence credits        ║
-- ║                                                                ║
-- ║  --minify-vars re-emits each file through LuaMinify's          ║
-- ║  formatter, which writes no comments, so from 2026-10-17 every ║
-- ║  `--!` line was gone from the release -- compat/internet.lua's ║
-- ║  credit to OpenOS's MIT-licensed lib/internet.lua with them.   ║
-- ║  test_provenance.py checks the SOURCE carries the credit, and  ║
-- ║  that was enough while `--!` survived the build. This checks   ║
-- ║  the minifier puts notices back, and the BUILT tree has them.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_release_credits.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("a"); h:close(); return (s:gsub("\r\n", "\n"))
end

package.path = "build/?.lua;" .. package.path
local mv = require("minify_vars")

print("=== The minifier keeps licence notices ===")
print()

local SRC = table.concat({
  "-- an ordinary comment",
  "--! PROVENANCE. Parts of this follow Somebody's code (MIT licence),",
  "--! credited here.",
  "",
  "--! #SEC an invariant note, not a notice",
  "local function add(alpha, beta) return alpha + beta end",
  "  --! Copyright (C) 2026 Somebody",
  "return add(1, 2)",
}, "\n")

local out, err = mv.minify(SRC, "=credits")
test("a file with notices minifies (" .. tostring(err) .. ")", out ~= nil)
out = out or ""
test("the PROVENANCE paragraph survives, both lines",
  out:find("--! PROVENANCE. Parts of this follow", 1, true) ~= nil
  and out:find("--! credited here.", 1, true) ~= nil)
test("an indented Copyright line survives, unindented",
  out:find("\n--! Copyright (C) 2026 Somebody\n", 1, true) ~= nil)
test("a #SEC note is not a notice and is still dropped",
  out:find("#SEC", 1, true) == nil)
test("an ordinary comment is still dropped", out:find("ordinary", 1, true) == nil)
test("the notices come first, ahead of the code", out:sub(1, 4) == "--! ")
local chunk = load(out, "=credits", "t", {})
test("the output still loads and runs the same", chunk ~= nil and chunk() == 3)
test("locals are still renamed", out:find("alpha", 1, true) == nil)
test("a file with no notices gets nothing added",
  (mv.minify("local x = 1 return x", "=plain") or ""):sub(1, 2) ~= "--")
test("a word test is not the rule: 'licence' in a design note is not a notice",
  mv.noticesOf("--! verify the candidate (hash gate, licence, conflicts)\n") == "")

-- The credit lines the provenance lint asks for (build/test_provenance.py's
-- credited()): a `--!` line naming both OpenOS and MIT.
local function creditLines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local s = line:match("^%s*(%-%-!.*)$")
    if s and s:find("OpenOS", 1, true) and s:find("MIT", 1, true) then out[#out + 1] = s end
  end
  return out
end

local CREDITED = {}
local p = io.popen(package.config:sub(1, 1) == "\\"
  and 'dir /s /b tos\\*.lua usr\\bin\\*.lua etc\\*.lua 2>nul'
  or "find tos usr/bin etc -name '*.lua' 2>/dev/null")
for line in p:lines() do
  local rel = line:gsub("\\", "/"):match("(tos/.*)$") or line:gsub("\\", "/"):match("(usr/bin/.*)$")
    or line:gsub("\\", "/"):match("(etc/.*)$")
  local text = rel and readAll(rel)
  if text and #creditLines(text) > 0 then CREDITED[#CREDITED + 1] = rel end
end
p:close()
table.sort(CREDITED)

print()
print("=== Every credit in the source is a notice ===")
print()
test("compat/internet.lua is found as credited (the scan works)",
  (function() for _, r in ipairs(CREDITED) do if r == "tos/compat/internet.lua" then return true end end end)())
for _, rel in ipairs(CREDITED) do
  local text = readAll(rel)
  local notices = mv.noticesOf(text)
  local ok = true
  for _, c in ipairs(creditLines(text)) do
    if not notices:find(c, 1, true) then ok = false end
  end
  test(rel .. ": its credit opens a PROVENANCE/Copyright/SPDX paragraph", ok)
end

print()
print("=== The built release carries the credits ===")
print()
local REL = nil
for _, base in ipairs({ "../TOS-Release", "TOS-Release", "../../TOS-Release" }) do
  if readAll(base .. "/tos/system_manifest.lua") then REL = base break end
end
if not REL then
  print("  SKIP: no built TOS-Release (python tos.py build)")
else
  for _, rel in ipairs(CREDITED) do
    local built = readAll(REL .. "/" .. rel)
    local ok = built ~= nil
    for _, c in ipairs(creditLines(readAll(rel))) do
      if not (built and built:find(c, 1, true)) then ok = false end
    end
    test("TOS-Release/" .. rel .. " still credits OpenOS's MIT code", ok)
    -- Read from the stripped text, the credit ran on into the next `--!`
    -- paragraph, because stripping takes out the `--` lines between them.
    local notices = mv.noticesOf(readAll(rel))
    test("TOS-Release/" .. rel .. " opens with its notices and nothing more",
      built ~= nil and built:sub(1, #notices) == notices
      and built:sub(#notices + 1, #notices + 3) ~= "--!")
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
