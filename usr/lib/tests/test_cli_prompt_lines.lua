-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a prompt of several lines, at the CLI        ║
-- ║                                                                ║
-- ║  The CLI's readLine paints `prompt .. input` on ONE row.       ║
-- ║  `confirm` and `promptInput` pass their whole message as the   ║
-- ║  prompt, so a message of several lines -- pkg's "Which copy?", ║
-- ║  the media scan's "Install X?\n\nFrom: ..." -- was painted as  ║
-- ║  one row, sliced to its last 80 characters, newlines and all.  ║
-- ║  On the headless runner the question ended at "[y/" and the    ║
-- ║  operator could not see what was being asked.                  ║
-- ║                                                                ║
-- ║  readLine now prints every line but the last, and keeps the    ║
-- ║  last as the prompt. splitPrompt is LIFTED from cli.lua.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cli_prompt_lines.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("tos/shell/cli.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()

local from = src:find("local function splitPrompt(prompt)", 1, true)
local to = from and src:find("\n  end\n", from, true)
test("found splitPrompt in cli.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end
local body = src:sub(from, to + 6):gsub("^local function splitPrompt", "return function")
local splitPrompt = assert(load(body, "=splitPrompt", "t",
  { tostring = tostring })())

print("=== splitting a prompt ===")
do
  local lead, last = splitPrompt("Install x? [y/N]: ")
  test("one line: nothing printed above", #lead == 0, #lead)
  test("and the prompt is unchanged", last == "Install x? [y/N]: ", last)

  lead, last = splitPrompt("Two copies tie.\n\nKept:\n  /mnt/a/lib\nUse the other? [y/N]: ")
  test("several lines: all but the last go above", #lead == 4, #lead)
  test("in order", lead[1] == "Two copies tie." and lead[3] == "Kept:"
    and lead[4] == "  /mnt/a/lib", table.concat(lead, "|"))
  test("a blank line stays a blank line", lead[2] == "", lead[2])
  test("the last line is the prompt", last == "Use the other? [y/N]: ", last)
  test("so the [y/N] fits one row", #last < 80, #last)

  lead, last = splitPrompt("Name it:\n")
  test("a trailing newline leaves an empty prompt", last == "" and #lead == 1
    and lead[1] == "Name it:", tostring(last) .. "|" .. #lead)

  lead, last = splitPrompt(nil)
  test("nil is an empty prompt", last == "" and #lead == 0)
end

print("=== readLine uses it, before it paints ===")
do
  local rl = src:find("local function readLine(prompt, mask, maxLen)", 1, true)
  local paint = rl and src:find("local function paint()", rl, true)
  local split = rl and src:find("splitPrompt(prompt)", rl, true)
  test("readLine calls splitPrompt", split ~= nil)
  test("before the row is painted", split and paint and split < paint)
  local lead = rl and src:sub(rl, paint or rl):find("for _, l in ipairs(lead) do o(l) end", 1, true)
  test("and prints the lead lines with o()", lead ~= nil)
  test("splitPrompt is defined above readLine (a local must be)", from < (rl or 0))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
