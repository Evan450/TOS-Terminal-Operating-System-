-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Lint: TOS may only use the Lua OpenComputers actually gives   ║
-- ║                                                                ║
-- ║  THE BLIND SPOT THIS EXISTS FOR. The off-box suite runs on      ║
-- ║  stock Lua 5.4, where the whole standard library is present.    ║
-- ║  OC runs TOS inside a SANDBOX that hands out a deliberately     ║
-- ║  trimmed subset. So a call to something OC withholds passes     ║
-- ║  every test here and is nil on the only platform TOS ships      ║
-- ║  for — and, being nil rather than an error at load time, it     ║
-- ║  usually fails silently behind a guard.                         ║
-- ║                                                                ║
-- ║  That is not hypothetical. debug.sethook is not in the sandbox, ║
-- ║  and TOS built two limits on it: the scheduler's preemption     ║
-- ║  budget and remote-exec's step budget. Both were dead on every  ║
-- ║  real machine, silently, while the suite was green.             ║
-- ║  (test_sethook_absent.lua covers that one specifically.)        ║
-- ║                                                                ║
-- ║  WHERE THE LIST COMES FROM. OpenComputers' own machine.lua      ║
-- ║  builds the sandbox as one big table literal. It ships inside   ║
-- ║  the Ocelot jar, so it can be read rather than guessed at:      ║
-- ║                                                                ║
-- ║    jar xf ocelot-desktop-*.jar assets/opencomputers/lua/machine.lua
-- ║                                                                ║
-- ║  and the `sandbox = {` literal near the bottom is the whole     ║
-- ║  surface. Regenerate SANDBOX below from that file if OC ever    ║
-- ║  changes it; do not edit it to make a red check go green.       ║
-- ║                                                                ║
-- ║  THE RULE. A shipped file may reference `lib.member` only when  ║
-- ║  the sandbox provides it, or when the pair is listed in         ║
-- ║  ALLOWED with a reason — and the only acceptable reason is      ║
-- ║  that the call site GUARDS and has a real fallback.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_oc_api_surface.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_oc_api_surface.lua"
local base = here:gsub("[^/\\]*$", "")

local root
for _, p in ipairs({ base .. "../../../", "", "TOS-Dev/" }) do
  local fh = io.open(p .. "tos/system_manifest.lua", "r")
  if fh then fh:close(); root = p; break end
end
if not root then
  print("FAIL: could not find tos/system_manifest.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- ============================================================
-- The sandbox surface, from OpenComputers' machine.lua
-- ============================================================
local SANDBOX = {
  os        = { clock=1, date=1, difftime=1, time=1 },
  string    = { byte=1, char=1, dump=1, find=1, format=1, gmatch=1, gsub=1, len=1,
                lower=1, match=1, pack=1, packsize=1, rep=1, reverse=1, sub=1,
                unpack=1, upper=1 },
  table     = { concat=1, insert=1, move=1, pack=1, remove=1, sort=1, unpack=1 },
  coroutine = { create=1, isyieldable=1, resume=1, running=1, status=1, wrap=1, yield=1 },
  debug     = { getinfo=1, getlocal=1, getupvalue=1, traceback=1 },
  utf8      = { char=1, charpattern=1, codepoint=1, codes=1, len=1, offset=1 },
  math      = { abs=1, acos=1, asin=1, atan=1, atan2=1, ceil=1, cos=1, cosh=1, deg=1,
                exp=1, floor=1, fmod=1, frexp=1, huge=1, ldexp=1, log=1, max=1,
                maxinteger=1, min=1, mininteger=1, modf=1, pi=1, pow=1, rad=1,
                random=1, randomseed=1, sin=1, sinh=1, sqrt=1, tan=1, tanh=1,
                tointeger=1, type=1, ult=1 },
}

--! Exceptions. Each needs a REASON, and the only good one is "the call site
--! guards and falls back". A guard with no fallback is the bug, not the fix.
local ALLOWED = {
  ["debug.sethook"] = "guarded; the budget is a no-op on OC and says so (test_sethook_absent)",
  ["debug.gethook"] = "guarded, and only reached when sethook exists",
  ["os.getenv"]     = "install.lua, `os.getenv and os.getenv(...)`; also runs off-box",
  ["os.sleep"]      = "redstone pulse, guarded with a computer.pullSignal fallback",
  ["os.tmpname"]    = "compat/init.lua implements it; the hit is its own error text",
  ["os.execute"]    = "boot-script provided on OpenOS; never called unguarded",
  ["os.exit"]       = "boot-script provided; TOS uses computer.shutdown instead",
  ["os.remove"]     = "boot-script provided; TOS uses kernel.fs",
  ["os.rename"]     = "boot-script provided; TOS uses kernel.fs",
}

-- ============================================================
local chunk = loadfile(root .. "tos/system_manifest.lua")
if not chunk then
  print("FAIL: could not load the manifest")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local okM, manifest = pcall(chunk)
if not okM or type(manifest) ~= "table" then
  print("FAIL: the manifest did not return a table")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local files = {}
for _, e in ipairs(manifest) do
  if type(e) == "table" and type(e.path) == "string" and e.path:sub(-4) == ".lua" then
    files[#files + 1] = e.path:gsub("^/", "")
  end
end

print("=== OpenComputers API surface lint ===")
print()
test("the manifest listed a plausible number of Lua files (" .. #files .. ")", #files > 100)

local scanned, offenders = 0, {}
for _, rel in ipairs(files) do
  local fh = io.open(root .. rel, "r")
  if fh then
    local src = fh:read("*a"); fh:close()
    scanned = scanned + 1
    local ln = 0
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      ln = ln + 1
      -- Drop comments: a note ABOUT an unavailable call is not a call.
      local code = line:gsub("%-%-.*$", "")
      for lib, member in code:gmatch("([%a_][%w_]*)%.([%a_][%w_]*)") do
        local set = SANDBOX[lib]
        if set and not set[member] and not ALLOWED[lib .. "." .. member] then
          offenders[#offenders + 1] = string.format("%s:%d  %s.%s", rel, ln, lib, member)
        end
      end
    end
  end
end

test("every manifest file was readable (" .. scanned .. "/" .. #files .. ")",
  scanned == #files)

if #offenders == 0 then
  passed = passed + 1
  print("  PASS: nothing reaches outside the sandbox surface")
else
  failed = failed + 1
  print("  FAIL: " .. #offenders .. " reference(s) OpenComputers does not provide:")
  for i = 1, math.min(#offenders, 25) do print("        " .. offenders[i]) end
  if #offenders > 25 then print("        ... and " .. (#offenders - 25) .. " more") end
  print("        (use the OC-provided equivalent, or guard it WITH A FALLBACK")
  print("         and add it to ALLOWED above with that reason.)")
end

-- The lint has to be able to fail: a SANDBOX table that accidentally grew to
-- cover everything, or a scan that stopped matching, would go green for the
-- wrong reason.
do
  local probe = root .. "usr/lib/tests/.oc_api_probe.lua"
  local fh = io.open(probe, "w")
  if fh then
    fh:write("local x = os.getenv2('HOME')\nreturn x\n")
    fh:close()
    local hit = false
    local rf = io.open(probe, "r")
    local src = rf:read("*a"); rf:close()
    for lib, member in src:gmatch("([%a_][%w_]*)%.([%a_][%w_]*)") do
      if SANDBOX[lib] and not SANDBOX[lib][member] then hit = true end
    end
    os.remove(probe)
    test("the lint still detects a call outside the surface", hit)
  else
    test("the lint could write its self-check probe", false)
  end
end

-- And the surface itself must look like OC's, not like stock Lua.
test("os is trimmed (no getenv in the surface)", SANDBOX.os.getenv == nil)
test("debug is trimmed (no sethook in the surface)", SANDBOX.debug.sethook == nil)
test("coroutine has no 5.4-only close", SANDBOX.coroutine.close == nil)
test("string.format is present (the surface is not empty)", SANDBOX.string.format ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
