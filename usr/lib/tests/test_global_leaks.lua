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
-- ║  every runtime .lua file in the image — and, when TOS-Extras   ║
-- ║  is beside it, every add-on file against the environment that  ║
-- ║  file actually runs in (second half, below).                   ║
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

local function envNamesAt(path)
  local cmd = 'luac -p -l -l "' .. path .. '" 2>&1'
  local pipe = io.popen(cmd, "r")
  if not pipe then return nil, "popen unavailable" end
  local out = pipe:read("*a") or ""
  local ok = pipe:close()
  if not ok or out:find("luac:", 1, true) then return nil, out end
  return listingEnvNames(out)
end
local function envNames(relPath) return envNamesAt(root .. relPath) end

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

-- ============================================================
-- TOS-Extras: every add-on file, against the environment it runs in
-- ============================================================
--! AUDIT 5 found this lint's scope stopped at the manifest, and one leak
--! (80-pkg-signing.lua's `_ = v6`) had already got through it. Widening it
--! is not a longer file list, because an add-on's globals are not the
--! kernel's: a sandboxed package gets the sandbox's base env plus a name
--! per capability it declares (fs, vault, crypto, ...), and NOT the
--! standard library the stdlib list above assumes -- no os, io, load,
--! package or debug unless a cap or the kernel loader provides them. So
--! each file is checked against where it actually runs:
--!   * a package COMMAND entry: the sandbox base + its manifest's caps;
--!   * a /usr/bin program: the sandbox base + the caps progenv gives every
--!     PATH program (fs.read, fs.write, compat.io), whatever the package
--!     declared;
--!   * an /etc/rc.d shim: the sandbox base + the caps rc.lua's peek reads
--!     from the script, or rc's defaults;
--!   * a library (/usr/lib, /usr/modules): it runs in the kernel's _G when
--!     a service loads it (allowUserLibs) and in a sandbox when a command
--!     does, so only names NO environment provides are flagged;
--!   * an EEPROM: the OpenComputers BIOS env; a self-test check: the
--!     kernel's _G; an OpenOS satellite or tool: the standard library.
--! The cap -> name map below is checked against sandbox.lua, progenv.lua
--! and rc.lua, so the lint cannot quietly disagree with what it models.
print()
print("-- TOS-Extras add-ons --")

local extras
for _, p in ipairs({ root .. "../TOS-Extras/", root .. "TOS-Extras/" }) do
  local fh = io.open(p .. "README.md", "r")
  if fh then fh:close(); extras = p; break end
end

local function readText(path)
  local fh = io.open(path, "rb"); if not fh then return nil end
  local s = fh:read("*a"); fh:close()
  return (s:gsub("\r\n", "\n"))
end

if not extras then
  print("  SKIP: TOS-Extras is not beside TOS-Dev; add-ons not linted")
else
  -- What every sandbox has: sandbox.lua's base env.
  local SANDBOX_BASE = {}
  for n in ([[assert error pcall xpcall type tostring tonumber pairs ipairs next
    select unpack rawequal rawlen setmetatable getmetatable math string table
    utf8 coroutine print require _G _VERSION]]):gmatch("%S+") do SANDBOX_BASE[n] = true end
  -- ...and what each capability adds to it.
  local CAP_NAMES = {
    ["fs.read"] = { "fs" }, ["fs.write"] = { "fs" },
    ["compat.io"] = { "io", "os", "filesystem" }, legacy = { "io", "os" },
    component = { "component", "computer" }, load = { "load", "loadstring" },
    notify = { "notify" }, net = { "net" }, internet = { "internet" },
    swap = { "swap" }, vault = { "vault" }, crypto = { "crypto" },
  }
  local PATH_CAPS = { "fs.read", "fs.write", "compat.io" }          -- progenv.lua
  local RC_DEFAULT_CAPS = { "fs.read", "fs.write", "component", "net" } -- rc.lua
  local OC_GLOBALS = { component = true, computer = true, unicode = true }

  -- The model, checked against the source it models.
  do
    local sb = readText(root .. "tos/kernel/sandbox.lua") or ""
    local missing = {}
    for n in pairs(SANDBOX_BASE) do
      if n == "_G" or n == "_VERSION" then
        if not sb:find("env." .. n .. " = ", 1, true) then missing[#missing + 1] = n end
      elseif not sb:find("\n%s+" .. n .. "%s*=") then
        missing[#missing + 1] = n
      end
    end
    for cap, names in pairs(CAP_NAMES) do
      if not sb:find('caps["' .. cap .. '"]', 1, true) then missing[#missing + 1] = "caps[" .. cap .. "]" end
      for _, n in ipairs(names) do
        if not sb:find("env%." .. n .. "%s*=") then missing[#missing + 1] = "env." .. n end
      end
    end
    table.sort(missing)
    test("the sandbox model matches sandbox.lua" .. (#missing > 0
      and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""), #missing == 0)
    local pe = readText(root .. "tos/shell/progenv.lua") or ""
    local okPath = true
    for _, c in ipairs(PATH_CAPS) do
      if not pe:find('["' .. c .. '"]', 1, true) then okPath = false end
    end
    test("a PATH program's caps match progenv.lua", okPath)
    local rc = readText(root .. "tos/kernel/rc.lua") or ""
    local dflt = rc:match("local DEFAULT_SERVICE_CAPS = (%b{})") or ""
    local okRc = dflt ~= ""
    for _, c in ipairs(RC_DEFAULT_CAPS) do
      if not (dflt:find('["' .. c .. '"]', 1, true) or dflt:find("\n%s*" .. c .. "%s*=")) then okRc = false end
    end
    test("rc.d's default service caps match rc.lua", okRc)
  end

  local function envFor(caps)
    local env = {}
    for n in pairs(SANDBOX_BASE) do env[n] = true end
    for _, c in ipairs(caps) do
      for _, n in ipairs(CAP_NAMES[c] or {}) do env[n] = true end
    end
    return env
  end
  local PERMISSIVE = {}
  for n in pairs(STDLIB) do PERMISSIVE[n] = true end
  for n in pairs(OC_GLOBALS) do PERMISSIVE[n] = true end
  for _, names in pairs(CAP_NAMES) do for _, n in ipairs(names) do PERMISSIVE[n] = true end end
  local STANDALONE = {}
  for n in pairs(STDLIB) do STANDALONE[n] = true end
  for n in pairs(OC_GLOBALS) do STANDALONE[n] = true end

  -- rc.lua's peek, as it reads caps: quoted names inside `caps = {...}`.
  local function rcCaps(src)
    local braces = src:match("caps%s*=%s*(%b{})")
    if not braces then return RC_DEFAULT_CAPS end
    local out = {}
    for c in braces:gmatch('"([%w%._]+)"') do out[#out + 1] = c end
    for c in braces:gmatch("'([%w%._]+)'") do out[#out + 1] = c end
    return out
  end

  -- Every .lua under the tree (cmd's `dir /s /b` or `find`, as
  -- test_manifest_completeness does), minus tests, the build and dist/.
  local WINDOWS = package.config:sub(1, 1) == "\\"
  local all = {}
  do
    local base = extras:gsub("/+$", "")
    local absBase = base
    if WINDOWS then
      local p = io.popen('cd /d "' .. base:gsub("/", "\\") .. '" && cd')
      if p then absBase = (p:read("*l") or ""):gsub("\\", "/"):gsub("/+$", ""); p:close() end
    end
    local cmd = WINDOWS and ('dir /b /s "' .. base:gsub("/", "\\") .. '\\*.lua" 2>nul')
                        or ('find "' .. base .. '" -name "*.lua" 2>/dev/null')
    local fh = io.popen(cmd)
    if fh then
      for line in fh:lines() do
        line = line:gsub("\\", "/"):gsub("%s+$", "")
        local rel
        if line:sub(1, #absBase + 1) == absBase .. "/" then rel = line:sub(#absBase + 2)
        elseif line:sub(1, #base + 1) == base .. "/" then rel = line:sub(#base + 2) end
        if rel and not rel:match("^dist/") and not rel:match("^build/")
           and not (rel:match("[^/]+$") or ""):match("^test_") then
          all[#all + 1] = rel
        end
      end
      fh:close()
    end
    table.sort(all)
  end
  test("found the add-on sources (" .. #all .. " files)", #all > 50)

  -- Which env each file runs in, from the package manifests.
  local classOf, whyOf, seenPkgDir = {}, {}, {}
  for _, rel in ipairs(all) do
    local dir = rel:match("^(.*)/[^/]+$")
    while dir and not seenPkgDir[dir] do
      seenPkgDir[dir] = true
      local mf = extras .. dir .. "/package.lua"
      local chunk = loadfile(mf, "t", {})
      local okM, m = false, nil
      if chunk then okM, m = pcall(chunk) end
      if okM and type(m) == "table" then
        local cmdTargets = {}
        for _, t in pairs(type(m.commands) == "table" and m.commands or {}) do
          if type(t) == "string" then cmdTargets[t] = true end
        end
        local caps = {}
        for _, c in ipairs(type(m.capabilities) == "table" and m.capabilities or {}) do
          caps[#caps + 1] = c
        end
        for _, target in ipairs(type(m.files) == "table" and m.files or {}) do
          if type(target) == "string" and target:match("%.lua$") then
            -- build-disk's resolution: mirror, flat, then the tail.
            local src
            for _, cand in ipairs({ dir .. target, dir .. "/" .. target:match("[^/]+$") }) do
              local h = io.open(extras .. cand, "r")
              if h then h:close(); src = cand; break end
            end
            if not src then
              local tail = target:gsub("^/usr", "")
              for _, r in ipairs(all) do
                if r:sub(1, #dir + 1) == dir .. "/" and r:sub(-#tail) == tail then src = r; break end
              end
            end
            if src then
              if cmdTargets[target] then
                classOf[src], whyOf[src] = envFor(caps), "command entry of " .. tostring(m.name)
              elseif target:lower():match("^/usr/lib/selftest/") then
                -- kernel/selftest.lua load()s these into the kernel's _G.
                classOf[src], whyOf[src] = STANDALONE, "self-test check (kernel _G)"
              elseif target:match("^/usr/bin/") then
                classOf[src], whyOf[src] = envFor(PATH_CAPS), "PATH program " .. target
              elseif target:match("^/etc/rc%.d/") then
                classOf[src], whyOf[src] = envFor(rcCaps(readText(extras .. src) or "")),
                  "rc.d shim " .. target
              else
                classOf[src], whyOf[src] = PERMISSIVE, "library " .. target
              end
            end
          end
        end
      end
      dir = dir:match("^(.*)/[^/]+$")
    end
  end
  for _, rel in ipairs(all) do
    if not classOf[rel] then
      if rel:match("^robot/eeprom%-") then
        classOf[rel], whyOf[rel] = STANDALONE, "EEPROM (OC BIOS env)"
      else
        -- OpenOS satellites and tools, and anything a package does not
        -- install: the standard library, plus OC's own globals.
        classOf[rel], whyOf[rel] = STANDALONE, "standalone"
      end
    end
  end

  -- Deliberate exceptions, each with a reason (same rule as ALLOWED).
  local EXTRAS_ALLOWED = {
    -- `table.unpack or unpack`: an OpenOS worker box may run the Lua 5.2
    -- architecture, where only the global exists. Same as net/remote.lua.
    ["cluster/openos/cluster-worker.lua"] = { unpack = "5.2 fallback" },
  }

  --! KNOWN GAPS -- recorded, not endorsed. Each is a real defect with its
  --! own TODO entry; it is pinned so that FIXING it fails this lint and the
  --! entry has to be removed, rather than passing silently.
  local KNOWN_GAPS = {
    ["cluster/master-skeleton/cluster.lua"] = {
      loadfile = "THE CLUSTER CLIs CANNOT RUN IN THE SANDBOX THEY ARE GIVEN (TODO 2026-10-01)",
    },
  }
  local extOffenders, gapSeen, xScanned = {}, {}, 0
  for _, rel in ipairs(all) do
    local names, err = envNamesAt(extras .. rel)
    if not names then
      extOffenders[#extOffenders + 1] = rel .. ": could not compile (" ..
        tostring(err):gsub("%s+", " "):sub(1, 120) .. ")"
    else
      xScanned = xScanned + 1
      local env, gaps, bad = classOf[rel], KNOWN_GAPS[rel] or {}, {}
      local allow = EXTRAS_ALLOWED[rel] or {}
      for _, n in ipairs(names) do
        if not env[n] and not allow[n] then
          if gaps[n] then gapSeen[rel .. ":" .. n] = true
          else bad[#bad + 1] = n end
        end
      end
      if #bad > 0 then
        extOffenders[#extOffenders + 1] = rel .. " [" .. whyOf[rel] .. "]: " .. table.concat(bad, ", ")
      end
    end
  end
  test("every add-on file compiled (" .. xScanned .. "/" .. #all .. ")", xScanned == #all)
  if #extOffenders == 0 then
    passed = passed + 1
    print("  PASS: no add-on reaches for a name its environment does not have")
  else
    failed = failed + 1
    print("  FAIL: " .. #extOffenders .. " add-on file(s) touch a name their environment lacks:")
    for _, line in ipairs(extOffenders) do print("        " .. line) end
    print("        (declare the capability that provides it, require() it, or")
    print("         add a `local` -- a guard around a nil global is the bug.)")
  end
  for rel, gaps in pairs(KNOWN_GAPS) do
    for n, why in pairs(gaps) do
      local still = gapSeen[rel .. ":" .. n]
      test("[known gap] " .. rel .. " still reads `" .. n .. "` -- " .. why
        .. (still and "" or "  (FIXED? remove this entry)"), still)
    end
  end
  -- The env model must be able to fail: a sandboxed command that reads
  -- `os` without compat.io is exactly what it exists to catch.
  do
    local tmp = extras .. ".global_leak_env_probe.lua"
    local fh = io.open(tmp, "w")
    if fh then
      fh:write("return function() return os.time() end\n")
      fh:close()
      local names = envNamesAt(tmp) or {}
      os.remove(tmp)
      local cmdEnv, seenOs = envFor({ "fs.read" }), false
      for _, n in ipairs(names) do if n == "os" and not cmdEnv[n] then seenOs = true end end
      test("the env model flags `os` in a command without compat.io", seenOs)
    end
  end
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
