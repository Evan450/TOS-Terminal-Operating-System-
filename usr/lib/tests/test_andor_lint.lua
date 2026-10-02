-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Lint: `x and nil or y` and `x and false or y` are always y    ║
-- ║                                                                ║
-- ║  Lua's `cond and a or b` idiom is a ternary only while `a` is   ║
-- ║  truthy. With `a` nil or false it collapses to `b` whatever     ║
-- ║  `cond` is -- and it reads exactly like the code that was        ║
-- ║  meant. It was in four places at once:                          ║
-- ║    * net/transfer.lua  a SUCCESSFUL request returned             ║
-- ║        (true, "Timeout waiting for response")                    ║
-- ║    * bootsettings.lua  choosing AUTO stored the string "auto"    ║
-- ║        in /etc/boot.cfg instead of removing the key -- six       ║
-- ║        setters                                                    ║
-- ║    * keychain.lua      a slot that EXISTS came back as            ║
-- ║        (passphrase, "no such slot")                               ║
-- ║    * commands/admin.lua  `redraw = (i < n) and false or nil` was  ║
-- ║        always nil, so every media-install question repainted the  ║
-- ║        whole shell -- the flicker its own comment says it avoids  ║
-- ║                                                                ║
-- ║  Scope: every file tos/system_manifest.lua ships. Comments and   ║
-- ║  strings are stripped first, so a note ABOUT the trap is fine.   ║
-- ║  Write an if, or `if c then x = nil else x = v end`.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_andor_lint.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_andor_lint.lua"
local base = here:gsub("[^/\\]*$", "")
local root
for _, p in ipairs({ base .. "../../../", "", "TOS-Dev/" }) do
  local fh = io.open(p .. "tos/system_manifest.lua", "rb")
  if fh then fh:close(); root = p; break end
end

print("=== lint: and-nil-or / and-false-or ===")
print()
if not root then
  print("FAIL: could not find tos/system_manifest.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Code with every comment and string literal removed. Newlines inside what
-- is removed are kept, so a finding still has its real line number.
local function codeOnly(src)
  local out, i, n = {}, 1, #src
  local function newlines(s) return (s:gsub("[^\n]", "")) end
  local function longEnd(from, eq)                 -- index past "]=*]"
    local close = "]" .. eq .. "]"
    local e = src:find(close, from, true)
    return e and (e + #close) or (n + 1)
  end
  while i <= n do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i + 1, i + 1) == "-" then
      local eq = src:match("^%[(=*)%[", i + 2)
      if eq then                                   -- --[==[ block comment ]==]
        local stop = longEnd(i + 4 + #eq, eq)
        out[#out + 1] = newlines(src:sub(i, stop - 1)); i = stop
      else                                         -- -- line comment
        local e = src:find("\n", i, true) or (n + 1)
        i = e                                      -- keep the newline itself
      end
    elseif c == "[" and src:match("^%[=*%[", i) then -- [==[ long string ]==]
      local eq = src:match("^%[(=*)%[", i)
      local stop = longEnd(i + 2 + #eq, eq)
      out[#out + 1] = ' "" ' .. newlines(src:sub(i, stop - 1)); i = stop
    elseif c == '"' or c == "'" then               -- short string
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c or d == "\n" then break
        else j = j + 1 end
      end
      out[#out + 1] = ' "" ' .. newlines(src:sub(i, j)); i = j + 1
    else
      local j = src:find("[%-%[\"']", i) or (n + 1)
      if j == i then j = i + 1 end                 -- a lone minus or index bracket
      out[#out + 1] = src:sub(i, j - 1); i = j
    end
  end
  return table.concat(out)
end

local TRAPS = { "%f[%w_]and%s+nil%s+or%f[^%w_]", "%f[%w_]and%s+false%s+or%f[^%w_]" }
local function findings(src)
  local code, hits = codeOnly(src), {}
  for _, pat in ipairs(TRAPS) do
    local from = 1
    while true do
      local s, e = code:find(pat, from)
      if not s then break end
      local _, lines = code:sub(1, s):gsub("\n", "")
      hits[#hits + 1] = lines + 1
      from = e + 1
    end
  end
  table.sort(hits)
  return hits
end

-- ── The lint can fail, and does not cry wolf ───────────────────────
print("-- fixtures --")
test("catches `and nil or`", #findings("local a = x and nil or y") == 1)
test("catches `and false or`", #findings("local a = (i < n) and false or nil") == 1)
test("...across a line break", #findings("local a = x and nil\n  or y") == 1)
test("reports the right line", findings("local a\n\nlocal b = c and nil or d")[1] == 3)
test("ignores it in a line comment", #findings("-- x and nil or y\nlocal a = 1") == 0)
test("ignores it in a block comment", #findings("--[==[ x and nil or y ]==] local a") == 0)
test("ignores it in a string", #findings('local s = "x and nil or y"') == 0)
test("ignores it in a long string", #findings("local s = [[x and false or y]]") == 0)
test("a real ternary is fine", #findings("local a = x and y or nil") == 0)
test("so is a word that merely contains it", #findings("local band = brand and nilly or y") == 0)
test("a string does not hide code after it",
  #findings('local s = "a" .. (x and nil or "b")') == 1)

-- ── The tree ───────────────────────────────────────────────────────
print()
print("-- every file the manifest ships --")
local okM, manifest = pcall(dofile, root .. "tos/system_manifest.lua")
test("manifest loads", okM and type(manifest) == "table")
local scanned, bad = 0, {}
for _, e in ipairs(okM and manifest or {}) do
  if type(e) == "table" and type(e.path) == "string" and e.path:match("%.lua$") then
    local fh = io.open(root .. e.path:sub(2), "rb")
    if fh then
      local src = fh:read("*a"); fh:close()
      scanned = scanned + 1
      for _, line in ipairs(findings(src)) do bad[#bad + 1] = e.path .. ":" .. line end
    end
  end
end
test("scanned a real tree (" .. scanned .. " files)", scanned > 100)
for _, where in ipairs(bad) do print("        trap at " .. where) end
test("no `and nil or` / `and false or` anywhere it ships", #bad == 0)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
