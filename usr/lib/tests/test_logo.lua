-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.logo branding                     ║
-- ║  The shared wordmark must load with NO dependencies (it    ║
-- ║  is required during early boot) and centre/align correctly.║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_logo.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Visual width = character count (the wordmark uses 3-byte block glyphs, so
-- #string is NOT the display width).
local function vis(s)
  if utf8 and utf8.len then return utf8.len(s) end
  local n = 0
  for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
  return n
end

package.path = "tos/?.lua;" .. package.path
local logo = require("kernel.logo")

print("=== logo branding Tests ===")
print()

-- All wordmark rows are exactly MARK_W display columns wide.
local rowsOk = true
for _, ln in ipairs(logo.MARK) do if vis(ln) ~= logo.MARK_W then rowsOk = false end end
test("block wordmark rows are MARK_W wide", true, rowsOk)
test("block wordmark is 5 rows", 5, #logo.MARK)

local asciiOk = true
for _, ln in ipairs(logo.MARK_ASCII) do if #ln ~= logo.MARK_ASCII_W then asciiOk = false end end
test("ascii wordmark rows are MARK_ASCII_W wide", true, asciiOk)

-- banner() centres: a wordmark row gets ~equal padding inside the width.
local b = logo.banner({ width = 50 })
test("banner has mark + tagline + vendor + motto", 9, #b)   -- 5 mark + blank + 3 text
local firstMark = b[1][1]
local leadSpaces = #(firstMark:match("^( *)"))
test("centred: left pad is (width-MARK_W)/2", math.floor((50 - logo.MARK_W) / 2), leadSpaces)
test("first line tagged 'mark'", "mark", b[1][2])

-- compact drops vendor + motto.
local c = logo.banner({ width = 50, compact = true })
test("compact banner has mark + tagline only", 7, #c)       -- 5 mark + blank + tagline

-- indent left-aligns instead of centring.
local ind = logo.banner({ indent = 2 })
test("indent gives a fixed 2-space lead", 2, #(ind[1][1]:match("^( *)")))

-- ASCII variant is selected on request.
local a = logo.banner({ ascii = true, width = 40 })
test("ascii banner uses the ascii mark", true, a[1][1]:find("TTTTTTT", 1, true) ~= nil)

-- COLORS has an entry for every role banner() emits.
local roles = {}
for _, ln in ipairs(b) do roles[ln[2]] = true end
local haveAll = true
for role in pairs(roles) do if role ~= "blank" and not logo.COLORS[role] then haveAll = false end end
test("COLORS covers every emitted role", true, haveAll)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
