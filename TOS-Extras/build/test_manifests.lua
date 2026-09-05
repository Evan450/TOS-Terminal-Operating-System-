-- ╔══════════════════════════════════════════════════════════╗
-- ║  Lint: Optional Utilities package manifests are well-formed ║
-- ║                                                            ║
-- ║  Guards two real regressions found in review:              ║
-- ║   1. cluster packages declared `commands = { "cluster" }`  ║
-- ║      (array) instead of a name->path map, so pkg.commands  ║
-- ║      silently dropped them.                                ║
-- ║   2. rc-pilot used crypto but did not declare the "crypto" ║
-- ║      capability, so the sandbox left `crypto` nil and the  ║
-- ║      command died on first use.                            ║
-- ║  Also: service packages must ship an /etc/rc.d/<n>.lua,    ║
-- ║  and every command path must point at a file the package   ║
-- ║  actually ships.                                           ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua build/test_manifests.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readFile(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end

-- Enumerate SOURCE manifests (never the generated dist/ tree).
--! POSIX `find` is not available from cmd.exe, where `find` is a text
--! search utility instead -- and native Lua's io.popen goes through
--! cmd.exe whichever shell launched the suite. This passed from Git Bash
--! and failed from cmd, surfacing as "found source manifests to lint"
--! rather than as a shell problem. `dir /b /s` is a cmd builtin; it
--! prints absolute paths, which is fine here because every use below
--! only needs a path it can open.
local WINDOWS = package.config:sub(1, 1) == "\\"
local manifests = {}
for _, root in ipairs({ "modules", "cluster" }) do
  local cmd = WINDOWS
    and ('dir /b /s "' .. root .. '\\package.lua" 2>nul')
    or  ('find "' .. root .. '" -name package.lua 2>/dev/null')
  local fh = io.popen(cmd)
  if fh then
    for line in fh:lines() do
      line = line:gsub("\\", "/"):gsub("%s+$", "")
      if line:match("/package%.lua$") and not line:match("/dist/") then
        manifests[#manifests + 1] = line
      end
    end
    fh:close()
  end
end
test("found source manifests to lint", #manifests > 0)

-- Capabilities the package sandbox actually offers. A manifest asking for
-- anything else has its request dropped at load, so flag it.
--
-- ASKED OF pkg.lua ITSELF rather than mirrored here. The mirror that used
-- to live at this spot had already drifted: it never learned `internet`,
-- granted since the internet-card round, so a correct manifest declaring
-- it would have failed this lint. `pkg.runCaps()` returns the real table
-- and needs no pkg.init — it is a plain copy of a static allowlist.
--
-- The literal below is only a FALLBACK for a checkout with no TOS-Dev
-- beside it, and the lint says out loud which of the two it used, because
-- "the fallback passed" and "the real allowlist passed" are different
-- amounts of assurance.
local FALLBACK_CAPS = {
  ["fs.read"]=true, ["fs.write"]=true, component=true, ["compat.io"]=true,
  load=true, net=true, swap=true, vault=true, crypto=true, notify=true,
  internet=true,
  ["peripheral.modem"]=true, ["peripheral.redstone"]=true,
  ["peripheral.robot"]=true, ["peripheral.inventory"]=true,
  ["peripheral.tape"]=true, ["peripheral.tractor"]=true,
  ["peripheral.piston"]=true, ["peripheral.hologram"]=true,
  ["peripheral.printer"]=true,
}

local KNOWN_CAPS, capSource = FALLBACK_CAPS, "the fallback list in this file"
do
  for _, p in ipairs({ "../TOS-Dev/tos/kernel/pkg.lua", "../tos/kernel/pkg.lua",
                       "TOS-Dev/tos/kernel/pkg.lua" }) do
    local chunk = loadfile(p)
    if chunk then
      local okLoad, pkgMod = pcall(chunk)
      if okLoad and type(pkgMod) == "table" and type(pkgMod.runCaps) == "function" then
        local okCaps, caps = pcall(pkgMod.runCaps)
        if okCaps and type(caps) == "table" and next(caps) then
          KNOWN_CAPS, capSource = caps, "kernel/pkg.lua's own PKG_RUN_CAPS"
          break
        end
      end
    end
  end
end
print("  (capability list from: " .. capSource .. ")")

for _, mpath in ipairs(manifests) do
  local dir = mpath:gsub("/package%.lua$", "")
  local label = dir:gsub("^%./", "")
  local ok, m = pcall(dofile, mpath)
  test(label .. ": manifest loads to a table", ok and type(m) == "table")
  if ok and type(m) == "table" then
    -- (1) commands must be nil or a string->string MAP (no array entries).
    local cmdsOk = true
    if m.commands ~= nil then
      if type(m.commands) ~= "table" then cmdsOk = false
      else
        for k, v in pairs(m.commands) do
          if type(k) ~= "string" or type(v) ~= "string" then cmdsOk = false end
        end
      end
    end
    test(label .. ": commands is a name->path map", cmdsOk)

    -- (2) crypto/vault capability is declared if the package's SANDBOXED code
    -- uses it. Only `commands` entrypoints run in the package sandbox (where
    -- the cap injects the `crypto`/`vault` global); service daemons and
    -- /usr/bin CLIs run with full kernel `require`, so their crypto use needs
    -- no package cap. Scan ONLY the command entrypoint source files.
    local capSet = {}
    if type(m.capabilities) == "table" then
      for _, c in ipairs(m.capabilities) do capSet[(tostring(c):gsub(":.*$", ""))] = true end
    end
    local entryBlob = {}
    if type(m.commands) == "table" then
      for _, cmdPath in pairs(m.commands) do
        -- Source is flat in the package dir; map by basename (current packages
        -- ship a single init.lua entrypoint).
        local base = tostring(cmdPath):match("[^/]+$")
        local src = base and readFile(dir .. "/" .. base)
        if src then entryBlob[#entryBlob + 1] = src end
      end
    end
    local blob = table.concat(entryBlob, "\n")
    local usesCrypto = blob:match("crypto%.%a") or blob:match("kernel%.crypto")
    local usesVault  = blob:match("vault%.%a")  or blob:match("kernel%.vault")
    if usesCrypto then test(label .. ": declares 'crypto' cap (entrypoint uses crypto)", capSet["crypto"] == true) end
    if usesVault  then test(label .. ": declares 'vault' cap (entrypoint uses vault)",   capSet["vault"]  == true) end

    -- All declared caps must be ones the sandbox actually grants.
    local capsValid = true
    if type(m.capabilities) == "table" then
      for _, c in ipairs(m.capabilities) do
        if not KNOWN_CAPS[(tostring(c):gsub(":.*$", ""))] then capsValid = false end
      end
    end
    test(label .. ": all capabilities are sandbox-grantable", capsValid)

    -- (3) service packages must ship an /etc/rc.d/<name>.lua to start.
    if m.kind == "service" then
      local hasRc = false
      for _, f in ipairs(m.files or {}) do
        if tostring(f):match("^/etc/rc%.d/.+%.lua$") then hasRc = true end
      end
      test(label .. ": service package ships an /etc/rc.d script", hasRc)
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
