-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Lint: no accidental globals                                  ║
-- ║                                                                ║
-- ║  A missing `local`, or a name that is a PARAMETER of one       ║
-- ║  function being used inside another, compiles perfectly and    ║
-- ║  reads perfectly. It just resolves against _ENV at run time,   ║
-- ║  where the name is nil. Three separate versions of that bug    ║
-- ║  were living in the tree when this lint was written, and every ║
-- ║  one of them had been read past by a human:                    ║
-- ║                                                                ║
-- ║   * commands/core.lua — sudo's failure report called `o`, the  ║
-- ║     output function, from a helper that never took it. The     ║
-- ║     line that tells you an elevated command died was itself    ║
-- ║     a crash. (test_sudo_report.lua covers the behaviour.)      ║
-- ║   * kernel/init.lua — three module inits were handed           ║
-- ║     `serialize = serialize` with no such local in the file, so ║
-- ║     each got nil and quietly fell back to its own require.     ║
-- ║     The dependency wiring said something that wasn't true.     ║
-- ║   * panels/commands.lua — `computer.freeMemory` behind an      ║
-- ║     `if computer and ...` guard, in a file that requires       ║
-- ║     nothing. The guard was always false, so the free-RAM       ║
-- ║     figure never appeared in an out-of-memory message.         ║
-- ║                                                                ║
-- ║  Note the shape: two of the three FAILED SILENTLY. A guard or  ║
-- ║  a fallback turned "this name is nil" into "this feature is    ║
-- ║  quietly absent", which is why reviewing did not catch them.   ║
-- ║                                                                ║
-- ║  THE RULE. Every name a shipped file reads or writes through   ║
-- ║  _ENV must be either a Lua standard-library global, or listed  ║
-- ║  in ALLOWED below WITH A REASON.                               ║
-- ║                                                                ║
-- ║  Scope: everything /tos/system_manifest.lua declares — which,  ║
-- ║  by its own coverage rule (test_manifest_completeness.lua), is ║
-- ║  every runtime .lua file in the image. TOS-Extras add-ons are  ║
-- ║  not covered here; their own tests are.                        ║
-- ║                                                                ║
-- ║  Needs `luac` (ships with the same Lua install as the `lua`    ║
-- ║  this suite already needs) to read the compiled _ENV accesses. ║
-- ║  Nothing else can see them: the whole point of this bug class  ║
-- ║  is that the source looks identical either way.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_global_leaks.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_global_leaks.lua"
local base = here:gsub("[^/\\]*$", "")

-- Locate the dev root (the directory holding tos/system_manifest.lua).
local root
for _, p in ipairs({ base .. "../../../", "", "TOS-Dev/" }) do
  local fh = io.open(p .. "tos/system_manifest.lua", "r")
  if fh then fh:close(); root = p; break end
end
if not root then
  print("FAIL: could not find tos/system_manifest.lua from " .. here)
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- ============================================================
-- What counts as a legitimate global
-- ============================================================

-- The Lua standard library, plus the two names OpenComputers itself puts
-- in _ENV for every chunk. Reading these is never the bug being hunted.
local STDLIB = {}
for name in ([[
  assert collectgarbage coroutine debug dofile error getmetatable io ipairs
  load loadfile loadstring math next os package pairs pcall print rawequal
  rawget rawlen rawset require select setmetatable string table tonumber
  tostring type xpcall utf8 bit32 checkArg _G _VERSION arg
]]):gmatch("%S+") do STDLIB[name] = true end

--! Deliberate exceptions. Each needs a reason, and the reason has to be
--! "this name really is global HERE" — never "the guard makes it safe".
--! A guard around a nil global is the failure mode, not the defence.
local ALLOWED = {
  -- The two boot files run under the OpenComputers BIOS environment,
  -- before TOS has a require() system to ask. `component`, `computer` and
  -- `unicode` genuinely are globals at that point — that is how OC hands
  -- the machine over.
  ["init.lua"] = { component = "OC BIOS env", computer = "OC BIOS env",
                   unicode = "OC BIOS env" },
  ["bios.lua"] = { component = "OC BIOS env", computer = "OC BIOS env" },
  -- `table.unpack or unpack` — the Lua 5.2 architecture fallback. The
  -- read is the POINT: on 5.2 the global exists, on 5.3/5.4 it doesn't
  -- and table.unpack has already answered.
  ["tos/kernel/net/remote.lua"] = { unpack = "table.unpack or unpack, 5.2 fallback" },
}

-- ============================================================
-- Read the manifest for the file list
-- ============================================================

local chunk = loadfile(root .. "tos/system_manifest.lua")
if not chunk then
  print("FAIL: could not load the system manifest")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local okM, manifest = pcall(chunk)
if not okM or type(manifest) ~= "table" then
  print("FAIL: the system manifest did not return a table")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local files = {}
for _, entry in ipairs(manifest) do
  local p = type(entry) == "table" and entry.path or nil
  if type(p) == "string" and p:sub(-4) == ".lua" then
    files[#files + 1] = p:gsub("^/", "")
  end
end

print("=== accidental-global lint ===")
print()
test("the manifest listed a plausible number of Lua files (" .. #files .. ")",
  #files > 100)

-- ============================================================
-- Ask luac what each chunk actually reaches for
-- ============================================================

-- -p so nothing is written to disk; -l -l for the full listing including
-- the constant each _ENV access names.
--!
--! THE NAME IS NOT ALWAYS ON THE _ENV LINE. An instruction operand can
--! only address the first 256 constants of a function. Past that, the
--! compiler LOADKs the name into a register and indexes _ENV with the
--! register, and luac prints the access with no name at all:
--!   5.3   LOADK 30 -316 ; "usersmod"    GETTABUP 30 3 30 ; _ENV
--!   5.4   GETUPVAL 1 0 ; _ENV   LOADK 2 300 ; "x"   GETTABLE 1 1 2
--! Matching only `_ENV "name"` skipped every global touched late in a
--! big function, which is how kernel/init.lua handed aliases.init two nil
--! globals (securefs, usersmod) past this lint -- the ONE file most
--! likely to have that many constants. So the listing is walked, and the
--! string each register was last loaded with is remembered per function.
local function listingEnvNames(out)
  local seen, order = {}, {}
  local function add(name)
    if name and not seen[name] then seen[name] = true; order[#order + 1] = name end
  end
  local kreg, envreg = {}, {}   -- register -> LOADKed string / holds _ENV
  for line in out:gmatch("[^\n]+") do
    if line:match("^%s*main <") or line:match("^%s*function <") then
      kreg, envreg = {}, {}
    end
    local op, args, comment = line:match("^%s*%d+%s+%[[^%]]*%]%s+(%u[%u%d]*)%s*([^;]*);?%s*(.*)$")
    if op then
      local r = {}
      for n in args:gmatch("%-?%d+") do r[#r + 1] = tonumber(n) end
      local a, b, c = r[1], r[2], r[3]
      local named = comment:match('^_ENV%s+"([A-Za-z_][A-Za-z0-9_]*)"')
      local str = comment:match('^"(.*)"$')
      if named then
        add(named)
      elseif comment == "_ENV" and op == "GETTABUP" and c and c >= 0 then
        add(kreg[c])                                  -- 5.3, key in R[C]
      elseif comment == "_ENV" and op == "SETTABUP" and b and b >= 0 then
        add(kreg[b])                                  -- 5.3, key in R[B]
      elseif op == "GETTABLE" and envreg[b] then
        add(kreg[c])                                  -- 5.4, _ENV in R[B]
      elseif op == "SETTABLE" and envreg[a] then
        add(kreg[b])                                  -- 5.4, _ENV in R[A]
      elseif op == "GETFIELD" and envreg[b] then
        add(str)
      elseif op == "SETFIELD" and envreg[a] then
        add(comment:match('^"([A-Za-z_][A-Za-z0-9_]*)"'))
      end
      -- Every op but the stores writes R[A]; forget what it held.
      if a and not op:match("^SET") then
        kreg[a], envreg[a] = nil, nil
        if op == "LOADK" and str then kreg[a] = str end
        if op == "GETUPVAL" and comment == "_ENV" then envreg[a] = true end
      end
    end
  end
  return order
end

local function envNames(relPath)
  local cmd = 'luac -p -l -l "' .. root .. relPath .. '" 2>&1'
  local pipe = io.popen(cmd, "r")
  if not pipe then return nil, "popen unavailable" end
  local out = pipe:read("*a") or ""
  local ok = pipe:close()
  if not ok or out:find("luac:", 1, true) then return nil, out end
  return listingEnvNames(out)
end

-- Probe once so a missing luac is reported as itself rather than as 150
-- identical failures.
local probe, probeErr = envNames(files[1] or "tos/system_manifest.lua")
if not probe then
  print()
  print("  !! LINT DID NOT RUN: luac is not usable here.")
  print("     " .. tostring(probeErr):gsub("%s+$", ""))
  print("     luac ships with the same Lua install as the `lua` this suite")
  print("     needs; without it nothing can see _ENV accesses, so this")
  print("     whole check was SKIPPED — not passed.")
  print()
  print("Results: " .. passed .. " passed, " .. failed .. " failed")
  print("global lint not available; run inside TOS or install luac")
  return true
end

local scanned, offenders = 0, {}
for _, rel in ipairs(files) do
  local names, err = envNames(rel)
  if not names then
    offenders[#offenders + 1] = rel .. ": could not compile (" ..
      tostring(err):gsub("%s+", " "):sub(1, 120) .. ")"
  else
    scanned = scanned + 1
    local allow = ALLOWED[rel] or {}
    local bad = {}
    for _, n in ipairs(names) do
      if not STDLIB[n] and not allow[n] then bad[#bad + 1] = n end
    end
    if #bad > 0 then
      offenders[#offenders + 1] = rel .. ": " .. table.concat(bad, ", ")
    end
  end
end

test("every manifest file compiled (" .. scanned .. "/" .. #files .. ")",
  scanned == #files)

if #offenders == 0 then
  passed = passed + 1
  print("  PASS: no file reaches for a name that isn't there")
else
  failed = failed + 1
  print("  FAIL: " .. #offenders .. " file(s) touch an undeclared global:")
  for _, line in ipairs(offenders) do print("        " .. line) end
  print("        (add a `local`, pass it as a parameter, or require() it —")
  print("         or list it in ALLOWED above WITH a reason if it really is")
  print("         global in that file.)")
end

-- The lint must be able to fail. If ALLOWED ever grows to cover
-- everything, or the manifest empties, the check above goes green for the
-- wrong reason — so prove the machinery still detects a known-bad chunk.
do
  local tmp = root .. "usr/lib/tests/.global_leak_probe.lua"
  local fh = io.open(tmp, "w")
  if fh then
    fh:write("local function f() undeclared_probe_name = 1 end\nreturn f\n")
    fh:close()
    local names = envNames("usr/lib/tests/.global_leak_probe.lua")
    local found = false
    for _, n in ipairs(names or {}) do
      if n == "undeclared_probe_name" then found = true end
    end
    os.remove(tmp)
    test("the lint still detects a deliberately leaked global", found)
  else
    test("the lint could write its self-check probe", false)
  end
end

-- And past the 256th constant, where the name leaves the _ENV line (see
-- listingEnvNames). A read, a write, and a read inside a table
-- constructor, which is exactly the shape of the kernel/init.lua bug.
do
  local tmp = root .. "usr/lib/tests/.global_leak_probe_big.lua"
  local fh = io.open(tmp, "w")
  if fh then
    local parts = { "local t = {" }
    for i = 1, 300 do parts[#parts + 1] = string.format('  "k%d",', i) end
    parts[#parts + 1] = "}"
    parts[#parts + 1] = "local x = late_read_probe"
    parts[#parts + 1] = "late_write_probe = 1"
    parts[#parts + 1] = "local y = { users = late_field_probe }"
    parts[#parts + 1] = "return t, x, y"
    fh:write(table.concat(parts, "\n"), "\n")
    fh:close()
    local got = {}
    for _, n in ipairs(envNames("usr/lib/tests/.global_leak_probe_big.lua") or {}) do
      got[n] = true
    end
    os.remove(tmp)
    test("...and one read past the 256th constant", got.late_read_probe == true)
    test("...and one written past the 256th constant", got.late_write_probe == true)
    test("...and one read inside a table constructor", got.late_field_probe == true)
    test("...without reporting the constants themselves", not got.k1 and not got.k300)
  else
    test("the lint could write its big-function probe", false)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
