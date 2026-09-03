-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the OpenOS compat lookup tables             ║
-- ║                                                                ║
-- ║  `sides`, `colors` and `keyboard.keys` are all two-way: a name ║
-- ║  maps to a number AND the number maps back to the name. An     ║
-- ║  OpenOS program reads BOTH directions — sides[n] to label a    ║
-- ║  face, colors[n] to name a wool colour, keyboard.keys[code] to ║
-- ║  say which key was pressed.                                    ║
-- ║                                                                ║
-- ║  All three built the reverse half like this:                   ║
-- ║                                                                ║
-- ║      for name, num in pairs(t) do                              ║
-- ║        if not t[num] then t[num] = name end   -- <-- adds keys ║
-- ║      end                                                       ║
-- ║                                                                ║
-- ║  Adding a NEW key to a table mid-pairs() is undefined in Lua   ║
-- ║  ("you may clear or modify existing fields, but not add new    ║
-- ║  ones"), and it did not stay theoretical: the rehash triggered ║
-- ║  by the first insert made next() skip entries, so a random     ║
-- ║  subset of the reverse map never got written. Measured on the  ║
-- ║  real files: colors lost 0-13 of its 16 entries and keyboard   ║
-- ║  kept only 32-75 of ~99, a DIFFERENT set on every boot,        ║
-- ║  because Lua seeds string hashing per process. `sides` was     ║
-- ║  worse still — every face there has two names, so even a walk  ║
-- ║  that finished picked the winner by hash order: sides[0] came  ║
-- ║  back "bottom" one boot and "down" the next.                   ║
-- ║                                                                ║
-- ║  OpenOS's own lib/colors.lua snapshots the keys into a second  ║
-- ║  array before writing, and lib/sides.lua spells the canonical  ║
-- ║  reverse names out literally. TOS now does both.               ║
-- ║                                                                ║
-- ║  Value assertions alone would be FLAKY against the old code    ║
-- ║  (it passed on the boots where the walk happened to survive),  ║
-- ║  so the source lint at the bottom is the deterministic half:   ║
-- ║  it fails on the PATTERN, not on the day's hash seed.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_tables.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_compat_tables.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

local sides    = require("compat.sides")
local colors   = require("compat.colors")
local keyboard = require("compat.keyboard")

print("=== OpenOS compat lookup table Tests ===")
print()

-- ============================================================
-- 1. sides — canonical names, matching OpenOS lib/sides.lua
-- ============================================================
print("-- sides --")

-- The canonical face names. OpenOS puts these on 0..5 and treats
-- down/up/north/south/west/east as ALIASES that resolve forward only.
local CANON = { [0] = "bottom", [1] = "top", [2] = "back",
                [3] = "front",  [4] = "right", [5] = "left" }
for n = 0, 5 do
  eq("sides[" .. n .. "] is the canonical name", CANON[n], sides[n])
end

-- Forward direction: canonical names AND every alias still resolve.
local FORWARD = {
  bottom = 0, down = 0, top = 1, up = 1, back = 2, north = 2,
  front = 3, south = 3, right = 4, west = 4, left = 5, east = 5,
}
do
  local bad = {}
  for name, n in pairs(FORWARD) do
    if sides[name] ~= n then bad[#bad + 1] = name end
  end
  test("every side name still resolves forward ("
    .. (#bad == 0 and "all 12" or table.concat(bad, ",") .. " wrong") .. ")", #bad == 0)
end

-- Round trip: the reverse name must itself resolve back to the number.
do
  local bad = {}
  for n = 0, 5 do
    if sides[sides[n]] ~= n then bad[#bad + 1] = n end
  end
  test("sides[sides[n]] == n for every face", #bad == 0)
end

-- ============================================================
-- 2. colors — all sixteen, both ways
-- ============================================================
print()
print("-- colors --")

local COLOR_NAMES = { [0]="white", [1]="orange", [2]="magenta", [3]="lightblue",
  [4]="yellow", [5]="lime", [6]="pink", [7]="gray", [8]="silver", [9]="cyan",
  [10]="purple", [11]="blue", [12]="brown", [13]="green", [14]="red", [15]="black" }

do
  local missing = {}
  for n = 0, 15 do
    if colors[n] == nil then missing[#missing + 1] = n end
  end
  test("all 16 reverse entries exist ("
    .. (#missing == 0 and "none missing" or "missing " .. table.concat(missing, ","))
    .. ")", #missing == 0)
end
do
  local wrong = {}
  for n = 0, 15 do
    if colors[n] ~= COLOR_NAMES[n] then wrong[#wrong + 1] = n end
  end
  test("...and each names the right colour", #wrong == 0)
end
do
  local bad = {}
  for n, name in pairs(COLOR_NAMES) do
    if colors[name] ~= n then bad[#bad + 1] = name end
  end
  test("the forward direction is untouched", #bad == 0)
end

-- ============================================================
-- 3. keyboard.keys — every named key has a reverse entry
-- ============================================================
print()
print("-- keyboard.keys --")

do
  local names, missing = 0, {}
  for name, code in pairs(keyboard.keys) do
    if type(name) == "string" and type(code) == "number" then
      names = names + 1
      if keyboard.keys[code] == nil then missing[#missing + 1] = name end
    end
  end
  test("the table has the full key set (" .. names .. " names)", names > 90)
  test("every named key has a reverse entry ("
    .. (#missing == 0 and "none missing" or #missing .. " missing")
    .. ")", #missing == 0)
end
-- A spot check on the two an OpenOS program is most likely to print.
eq("keys[28] is enter", "enter", keyboard.keys[28])
eq("keys[57] is space", "space", keyboard.keys[57])
eq("keys.a still resolves forward", 30, keyboard.keys.a)
eq("keys[30] is a", "a", keyboard.keys[30])

-- ============================================================
-- 4. The deterministic half: nobody may add keys mid-pairs()
-- ============================================================
-- Walks the real sources. Value assertions above would have passed on
-- a lucky boot even with the bug present; this cannot.
print()
print("-- source lint: no table grown while pairs() walks it --")

local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end

-- Listed, not walked: a walk that silently stops finding a renamed file
-- reports success for coverage it lost. These are the files that build a
-- lookup table, plus the compat layer they live in.
local LINT_FILES = {
  "tos/compat/sides.lua",
  "tos/compat/colors.lua",
  "tos/compat/keyboard.lua",
  "tos/compat/init.lua",
  "tos/compat/text.lua",
  "tos/kernel/theme.lua",
  "tos/shell/keys.lua",
}

local checked = 0
for _, rel in ipairs(LINT_FILES) do
  local src = readFile(rel)
  if not src then
    failed = failed + 1
    print("  FAIL: lint could not read " .. rel)
  else
    checked = checked + 1
    -- Split into lines so a hit can be reported by number.
    local lines = {}
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    -- Scope the search to the loop's own body, by indentation: the body of
    -- `for ... in pairs(t) do` runs until the next non-blank, non-comment
    -- line indented no further than the `for` itself. A fixed lookahead
    -- window instead would flag the FIX — snapshot-then-write puts a legal
    -- `t[num] = name` a few lines below a pairs() walk of the same table.
    local function indentOf(l) return #(l:match("^[ \t]*") or "") end
    local function bodyEnd(i)
      local base_i = indentOf(lines[i])
      for j = i + 1, #lines do
        local l = lines[j]
        if l:match("%S") and not l:match("^%s*%-%-") and indentOf(l) <= base_i then
          return j - 1
        end
      end
      return #lines
    end

    local hits = {}
    for i, l in ipairs(lines) do
      local tbl = l:match("in%s+pairs%(%s*([%w_%.]+)%s*%)")
      if tbl then
        local pat = tbl:gsub("%p", "%%%0")
        -- The write has to be an INSERT to count: `t[k] = nil` on a key the
        -- walk already handed us is explicitly legal and is how half this
        -- codebase clears a table.
        for j = i, bodyEnd(i) do
          local idx, rhs = lines[j]:match(pat .. "%s*%[%s*([^%]]+)%s*%]%s*=%s*(.+)$")
          if idx and rhs and not rhs:match("^nil%s*$") and not rhs:match("^nil[%s;]") then
            hits[#hits + 1] = rel .. ":" .. j .. "  " .. lines[j]:gsub("^%s+", "")
            break
          end
        end
      end
    end
    if #hits == 0 then
      passed = passed + 1
      print("  PASS: " .. rel .. " never grows a table it is walking")
    else
      failed = failed + 1
      print("  FAIL: " .. rel .. " adds keys during a pairs() walk:")
      for _, h in ipairs(hits) do print("        " .. h) end
    end
  end
end
test("the lint actually read files (" .. checked .. "/" .. #LINT_FILES .. ")",
  checked == #LINT_FILES)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
