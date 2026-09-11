-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the error registry (tos/kernel/errors.lua)    ║
-- ║                                                                 ║
-- ║  Every error has three spellings from one entry -- E-401 for     ║
-- ║  operators, ERR_PERM_DENIED for programs and `why`, 0x00040001    ║
-- ║  on the stop screen. Codes are forever once shipped, so what      ║
-- ║  this pins is identity: nothing collides, the hex is derived      ║
-- ║  rather than stored, the EEPROM's beep codes all map, srm reads   ║
-- ║  the same table, and no message anywhere in the shipped tree is   ║
-- ║  tagged with a code the registry does not have.                   ║
-- ╚═════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_error_registry.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end
local function eq(name, want, got)
  test(name, want == got, "want " .. tostring(want) .. ", got " .. tostring(got))
end
local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end }
package.loaded["component"] = { list = function() return function() end end }

local ok, errors = pcall(require, "kernel.errors")
test("kernel.errors loads", ok and type(errors) == "table", errors)
if not ok then print("*** TESTS FAILED ***"); os.exit(1) end

print("=== error registry ===")

-- ── 1. Identity: nothing collides, everything is well-formed ───────
print("\n-- identity --")
local all = errors.all()
test("the registry has entries", #all >= 10, #all)
local nums, syms, problems = {}, {}, {}
for _, e in ipairs(all) do
  if nums[e.num] then problems[#problems + 1] = "number " .. e.num .. " used twice" end
  if syms[e.sym] then problems[#problems + 1] = e.sym .. " used twice" end
  nums[e.num], syms[e.sym] = true, true
  if not e.sym:match("^ERR_[A-Z0-9_]+$") then problems[#problems + 1] = "bad symbol " .. e.sym end
  if not (errors.SUBSYSTEMS[e.num // 100] and e.num % 100 >= 1) then
    problems[#problems + 1] = "E-" .. e.num .. " is in no subsystem"
  end
  if type(e.title) ~= "string" or #e.title < 8 then problems[#problems + 1] = e.sym .. " has no title" end
end
for _, p in ipairs(problems) do print("    " .. p) end
eq("no collisions, no malformed entries", 0, #problems)

-- ── 2. The three spellings ──────────────────────────────────────────
print("\n-- spellings --")
local pd = errors.find("ERR_PERM_DENIED")
test("ERR_PERM_DENIED exists", pd ~= nil)
eq("E-number", "E-401", errors.code(pd))
eq("label", "E-401 ERR_PERM_DENIED", errors.label(pd))
eq("hex is derived: (subsystem << 16) | index", "0x00040001", errors.hex(pd))
eq("tag, for appending to a message", "  [E-401 ERR_PERM_DENIED]", errors.tag("ERR_PERM_DENIED"))
eq("an unknown symbol tags as nothing", "", errors.tag("ERR_NOPE"))
eq("subsystem name", "access", errors.subsystem(pd))
do
  local bad = {}
  for _, e in ipairs(all) do
    if errors.find(errors.hex(e)) ~= e then bad[#bad + 1] = e.sym end
    if errors.find(errors.code(e)) ~= e then bad[#bad + 1] = e.sym .. " (code)" end
  end
  eq("every hex and every E-number round-trips to its entry", 0, #bad)
end

-- ── 3. What an operator might type ──────────────────────────────────
print("\n-- lookups --")
for _, q in ipairs({ "E-401", "e-401", "E401", "401", " E-401 ", "ERR_PERM_DENIED",
                     "err_perm_denied", "PERM_DENIED", "perm_denied", "0x00040001" }) do
  test(string.format("find(%q) -> E-401", q), errors.find(q) == pd)
end
test("find(401) as a number", errors.find(401) == pd)
test("find(\"C1\") -> the CPU-architecture boot fault", errors.find("C1") == errors.find("ERR_CPU_ARCH"))
--! `why ls` has to keep meaning the command: anything that is not
--! recognisably a code must come back nil, never a fuzzy match.
for _, q in ipairs({ "ls", "why", "", "E-999", "0xZZ", "ERR_", "401x" }) do
  test(string.format("find(%q) is nil", q), errors.find(q) == nil)
end
test("find(nil) is nil", errors.find(nil) == nil)

-- ── 4. Tags in messages ─────────────────────────────────────────────
print("\n-- parse --")
test("parse pulls the tag out of a message",
  errors.parse("Permission denied: no  [E-401 ERR_PERM_DENIED]") == pd)
test("parse finds a tag mid-message",
  errors.parse("Refused: x  [E-402 ERR_PATH_PROTECTED] — then more text") == errors.find("ERR_PATH_PROTECTED"))
test("an untagged message parses to nil", errors.parse("Permission denied: no") == nil)
test("a non-string parses to nil", errors.parse(nil) == nil)

-- ── 5. The EEPROM's beep codes ──────────────────────────────────────
--! bios.lua is the one producer that cannot carry a name: 4 KiB, ~150
--! bytes free. So every code it can emit must map here, and the E-number's
--! index must equal the beep count its digit already encodes.
print("\n-- BIOS codes --")
do
  local bios = readAll("bios.lua") or readAll("TOS-Dev/bios.lua")
  test("bios.lua is readable", bios ~= nil)
  local emitted = {}
  for code in (bios or ""):gmatch('F%("(%u%d)"') do emitted[code] = true end
  local n = 0
  for code in pairs(emitted) do
    n = n + 1
    local e = errors.find(code)
    test("BIOS " .. code .. " maps to a registry entry", e ~= nil)
    if e then
      eq("BIOS " .. code .. " is a boot code (1xx)", 1, e.num // 100)
      eq("BIOS " .. code .. ": E-10N's index is its beep count", tonumber(code:sub(2)), e.num % 100)
      eq("BIOS " .. code .. " records its own EEPROM code", code, e.bios)
    end
  end
  test("found the BIOS's fault codes", n >= 6, n)
  for _, e in ipairs(all) do
    if e.bios then test("registry's " .. e.bios .. " is one bios.lua really emits", emitted[e.bios]) end
  end
end

-- ── 6. srm reads the same table ─────────────────────────────────────
print("\n-- srm --")
do
  local okS, srm = pcall(require, "kernel.srm")
  test("kernel.srm loads", okS and type(srm) == "table", srm)
  if okS then
    local n = 0
    for code, why in pairs(srm.BASIC_CODES) do
      n = n + 1
      local e = errors.find(code)
      eq("srm's " .. code .. " text IS the registry's", e and e.title, why)
    end
    local want = 0
    for _, e in ipairs(all) do if e.bios then want = want + 1 end end
    eq("srm has exactly the registry's BIOS codes", want, n)
  end
end

-- ── 7. No message anywhere names a code the registry lacks ──────────
--! Producers embed their tag as a literal ("  [E-402 ERR_PATH_PROTECTED]"),
--! so they need no runtime dependency on this module. The price is that a
--! literal can drift. This closes it: every Lua file the manifest ships is
--! scanned, and every tag in it must name a real code WITH its real symbol.
print("\n-- tags in shipped files --")
do
  local okM, manifest = pcall(dofile, "tos/system_manifest.lua")
  if not okM then okM, manifest = pcall(dofile, "TOS-Dev/tos/system_manifest.lua") end
  test("the system manifest loads", okM and type(manifest) == "table")
  local scanned, tags, bad = 0, 0, {}
  for _, entry in ipairs(okM and manifest or {}) do
    local path = type(entry) == "table" and entry.path
    if path and path:match("%.lua$") then
      local src = readAll("." .. path) or readAll("TOS-Dev" .. path)
      if src then
        scanned = scanned + 1
        for num, sym in src:gmatch("%[E%-(%d%d%d) (ERR_[%w_]+)%]") do
          tags = tags + 1
          local e = errors.find(tonumber(num))
          if not e then bad[#bad + 1] = path .. ": E-" .. num .. " is not in the registry"
          elseif e.sym ~= sym then bad[#bad + 1] = path .. ": E-" .. num .. " is " .. e.sym .. ", not " .. sym end
        end
      end
    end
  end
  for _, b in ipairs(bad) do print("    " .. b) end
  test("scanned the shipped Lua files", scanned > 50, scanned)
  test("found tags to check", tags > 0, tags)
  eq("every tag names a real code with its real symbol", 0, #bad)
end

-- ── 8. The MANUAL's table is the registry's ─────────────────────────
--! Appendix C lists every code for operators who read the Manual rather
--! than the source. A hand-written table drifts -- this project has been
--! caught by prose drifting from code often enough to know -- so both
--! directions are checked: every entry has its row, and every row names a
--! real code with its real symbol.
print("\n-- MANUAL appendix --")
do
  local manual = readAll("MANUAL.md") or readAll("TOS-Dev/MANUAL.md")
  test("MANUAL.md is readable", manual ~= nil)
  local rows, bad = {}, {}
  for num, sym in (manual or ""):gmatch("|%s*E%-(%d%d%d)%s*|%s*`?(ERR_[%w_]+)`?%s*|") do
    rows[tonumber(num)] = sym
    local e = errors.find(tonumber(num))
    if not e then bad[#bad + 1] = "row E-" .. num .. " is not in the registry"
    elseif e.sym ~= sym then bad[#bad + 1] = "row E-" .. num .. " says " .. sym .. ", the registry says " .. e.sym end
  end
  for _, e in ipairs(all) do
    if not rows[e.num] then bad[#bad + 1] = errors.label(e) .. " has no row in the MANUAL" end
  end
  for _, b in ipairs(bad) do print("    " .. b) end
  eq("the MANUAL's error table matches the registry, both ways", 0, #bad)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
