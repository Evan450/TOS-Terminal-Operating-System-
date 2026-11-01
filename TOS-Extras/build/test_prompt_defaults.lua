-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: typing at a prompt replaces what it shows    ║
-- ║                                                                ║
-- ║  A prompt that opens with a value and adds what you type to    ║
-- ║  the end of it is a trap. `stock` read 50 typed over 64 as a   ║
-- ║  threshold of 6450, saved it and said so. `calc` read 4 over a ║
-- ║  default of 2 as 24, and refused it with a range error. The    ║
-- ║  first key typed replaces the value now, and backspace edits   ║
-- ║  it. Every add-on prompt that can open with a value is named   ║
-- ║  here, so a new one has to say which it is.                    ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua build/test_prompt_defaults.lua   (from TOS-Extras)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function read(path)
  for _, pre in ipairs({ "", "../TOS-Extras/", "TOS-Extras/" }) do
    local h = io.open(pre .. path, "rb")
    if h then
      local s = h:read("a"):gsub("\r\n", "\n")
      h:close()
      return s
    end
  end
end

-- Files whose prompts replace, with the mark each uses.
local REPLACES = {
  ["modules/calc/init.lua"]    = "local fresh = buf ~= \"\" and not typed",
  ["modules/warhead/init.lua"] = "local fresh = buf ~= \"\"",
  ["modules/write/init.lua"]   = "local fresh = s ~= \"\"",
  ["modules/prefab/tui.lua"]   = "local fresh = buf ~= \"\"",
  ["modules/stock/init.lua"]   = "S.numberKey(buf, fresh, k)",
}
-- Prefilled on purpose, where adding to the text is the point: a reply's
-- subject and addressee.
local APPENDS = {
  ["modules/mail/usr/lib/mailapp.lua"] = "local buf = initial or \"\"",
  ["modules/mail/usr/lib/mailui.lua"]  = "local buf = initial or \"\"",
}

print("=== a prompt that opens with a value ===")
print()
for path, mark in pairs(REPLACES) do
  local src = read(path)
  test(path .. " is readable", src ~= nil)
  test(path .. " replaces on the first key", src and src:find(mark, 1, true) ~= nil)
end
for path, mark in pairs(APPENDS) do
  local src = read(path)
  test(path .. " is still the kind that appends, and its reason still holds",
    src and src:find(mark, 1, true) ~= nil)
end

do
  local calc = read("modules/calc/init.lua")
  test("calc's column width carries on from the digit that opened it",
    calc:find('string.char(ch), 1, 60, true)', 1, true) ~= nil)
end

-- Run the real calc prompt, the one with the two behaviours.
do
  local calc = read("modules/calc/init.lua")
  local from = calc:find("local function promptText", 1, true)
  local to = calc:find("local function promptNumber", 1, true)
  test("found calc's prompt", from ~= nil and to ~= nil)
  local keys
  local env = setmetatable({
    mode = "READY", stdQuit = function() return false end, redraw = function() end,
    pull = function()
      local k = table.remove(keys, 1)
      return "key", k.ch, k.code
    end,
  }, { __index = _G })
  local fn = assert(load(calc:sub(from, to - 1) .. "\nreturn promptText", "=prompt", "t", env))()
  local function press(text)
    local out = {}
    for c in text:gmatch(".") do
      out[#out + 1] = c == "\b" and { ch = 8, code = 14 } or { ch = c:byte(), code = 0 }
    end
    out[#out + 1] = { ch = 13, code = 28 }
    return out
  end
  keys = press("4")
  test("4 over a default of 2 is 4", fn("label", "2") == "4")
  keys = press("12")
  test("12 over 9 is 12", fn("label", "9") == "12")
  keys = press("\b3")
  test("backspace edits, so 12 becomes 13", fn("label", "12") == "13")
  keys = press("")
  test("Enter alone takes the default", fn("label", "9") == "9")
  keys = press("5")
  test("a digit that opened the prompt is kept", fn("label", "1", nil, true) == "15")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
