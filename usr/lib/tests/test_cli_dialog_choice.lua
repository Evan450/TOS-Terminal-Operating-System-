-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a choice is still a choice in CLI mode       ║
-- ║                                                                ║
-- ║  The CLI's stand-in for the framed dialog read `lines` and     ║
-- ║  `text` and asked y/N. cluster-setup passes `message` and      ║
-- ║  `buttons`, so on the CLI it asked "What is this machine?",    ║
-- ║  showed neither the explanation nor the choices, and offered   ║
-- ║  "OK? [y/N]". Whatever was typed, the wizard cancelled.        ║
-- ║                                                                ║
-- ║  The function is LIFTED from cli.lua.                          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cli_dialog_choice.lua   (from TOS-Dev)

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
local from = src:find("dialog         = function(opts)", 1, true)
local to = from and src:find("\n    end,\n", from, true)
test("found dialog in cli.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local function dialog(opts, answer)
  local out, asked = {}, nil
  local env = {
    o = function(s) out[#out + 1] = s end,
    readLine = function(p) asked = p; return answer end,
    D = { c = function() return 0 end },
    tostring = tostring, tonumber = tonumber, ipairs = ipairs, type = type,
  }
  local body = src:sub(from, to + 7):gsub("^dialog%s*=%s*", "return "):gsub(",%s*$", "")
  local fn = assert(load(body, "=dialog", "t", env))()
  return fn(opts), table.concat(out, "\n"), asked
end

print("=== buttons are offered, and answered by number ===")
do
  local opts = { title = "Machine?", message = "line one\nline two",
                 buttons = { "Master", "Manager", "Cancel" } }
  local pick, out, asked = dialog(opts, "2")
  test("the number picks that button", pick == 2, pick)
  test("the title is shown", out:find("Machine?", 1, true) ~= nil)
  test("the message is shown", out:find("line one", 1, true) ~= nil)
  test("each of its lines stays a line", out:find("line one\nline two", 1, true) ~= nil, out)
  test("every button is listed", out:find("1. Master", 1, true) and out:find("2. Manager", 1, true)
    and out:find("3. Cancel", 1, true))
  test("it asks for a choice, not y/N", asked == "Choice: ", asked)
  test("a number not on the list takes the last button", (dialog(opts, "9")) == 3)
  test("so does anything else", (dialog(opts, "master")) == 3)
  test("so does an interrupted read", (dialog(opts, nil)) == 3)
end

print("=== a plain question is still y/N ===")
do
  local pick, _, asked = dialog({ title = "Sure?", text = "Really." }, "y")
  test("y answers 1", pick == 1, pick)
  test("it asks y/N", tostring(asked):find("[y/N]", 1, true) ~= nil, asked)
  test("n answers 2", (dialog({ title = "Sure?" }, "n")) == 2)
  test("an empty button list is a plain question", (dialog({ buttons = {} }, "y")) == 1)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
