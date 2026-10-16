-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Lint: no statement may start with "("                         ║
-- ║                                                                ║
-- ║  Lua reads a line that begins with "(" as a CALL on whatever   ║
-- ║  ended the line before it. In the Ctrl+T monitor's wrapper,    ║
-- ║      proc.setForeground(shellPid, ctrlTIdx, { kernel = true }) ║
-- ║      (proc.signalKernel or proc.signal)(shellPid, "tos_focus") ║
-- ║  is one expression: it calls the boolean setForeground         ║
-- ║  returned, which errors, so the seat's shell never got its     ║
-- ║  tos_focus. On the headless machine, closing the CLI's System  ║
-- ║  Monitor left the monitor on screen with the prompt typed over ║
-- ║  it; Enter-switch to a process hit the same line shape. The    ║
-- ║  code base's other sites already write ";(" for this. This     ║
-- ║  scans every shipped Lua source for a "(" at the start of a    ║
-- ║  line that follows something able to end a statement.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_call_chain_lint.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

-- Words after which a line break is a continuation, not a statement end.
local CONTINUES = {
  ["and"] = true, ["or"] = true, ["not"] = true, ["return"] = true,
  ["then"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
  ["in"] = true, ["until"] = true, ["while"] = true, ["if"] = true,
  ["local"] = true, ["repeat"] = true,
}

--- The offending lines of one source text: { {line, text}, ... }.
local function findAmbiguous(src)
  local hits = {}
  local prevEnd, inLong = nil, false
  local n = 0
  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local line = raw:gsub("\r$", "")
    if inLong then
      if line:find("]]", 1, true) or line:find("]=]", 1, true) then inLong = false end
      prevEnd = nil
    else
      -- Drop a trailing comment (good enough: none of the sources hide
      -- "--" inside a string at the end of a statement line).
      local code = line:gsub("%-%-.*$", "")
      if line:match("^%s*%-%-%[=*%[") and not line:find("]]", 1, true) then
        inLong = true
      end
      local trimmed = code:match("^%s*(.-)%s*$")
      if trimmed ~= "" then
        if trimmed:sub(1, 1) == "(" and prevEnd then hits[#hits + 1] = { n, line } end
        local last = trimmed:sub(-1)
        local word = trimmed:match("([%a_][%w_]*)$")
        if last:match("[%)%]%}\"']") or (word and not CONTINUES[word]) then
          prevEnd = true
        else
          prevEnd = nil
        end
        if trimmed:find("%[%[") and not trimmed:find("%]%]") then inLong = true; prevEnd = nil end
      end
    end
  end
  return hits
end

print("=== no statement starts with \"(\" ===")
print()

-- The detector itself, on the shape that shipped and on the fix.
local bad = "proc.setForeground(pid, 1, { kernel = true })\n"
  .. "-- a comment between them changes nothing\n"
  .. "(proc.signalKernel or proc.signal)(pid, \"tos_focus\")\n"
test("the shipped shape is caught, comment and all", #findAmbiguous(bad) == 1)
local good = "proc.setForeground(pid, 1, { kernel = true })\n"
  .. ";(proc.signalKernel or proc.signal)(pid, \"tos_focus\")\n"
test("the ;( form passes", #findAmbiguous(good) == 0)
local cont = "o(string.format(\"%d %s\",\n  (x or 0), y))\nlocal v = a or\n  (b and c)\n"
test("a ( that continues an argument list or an expression passes", #findAmbiguous(cont) == 0)

-- Every shipped Lua source.
local roots = { "tos", "etc", "usr/bin", "../TOS-Extras/modules" }
local files = {}
local function addFile(p) files[#files + 1] = p end
for _, f in ipairs({ "init.lua", "bios.lua", "bootstrap.lua", "install.lua" }) do addFile(f) end
local isWin = package.config:sub(1, 1) == "\\"
for _, root in ipairs(roots) do
  local cmd = isWin and ('dir /b /s "' .. root:gsub("/", "\\") .. '\\*.lua" 2>nul')
    or ('find "' .. root .. '" -name "*.lua" 2>/dev/null')
  local h = io.popen(cmd)
  if h then
    for p in h:lines() do
      if not p:find("[/\\]tests?[/\\]") then addFile(p) end
    end
    h:close()
  end
end
test("found the sources to scan", #files > 100, #files)

local found = {}
for _, p in ipairs(files) do
  local fh = io.open(p, "rb")
  if fh then
    local src = fh:read("a"); fh:close()
    for _, hit in ipairs(findAmbiguous(src)) do
      found[#found + 1] = p .. ":" .. hit[1] .. ": " .. hit[2]:match("^%s*(.-)%s*$")
    end
  end
end
for _, f in ipairs(found) do print("    " .. f) end
test("no shipped line starts a statement with \"(\"", #found == 0, #found .. " found")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
