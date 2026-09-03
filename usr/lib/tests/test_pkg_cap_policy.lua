-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: package-capability policy                          ║
-- ║  - the CODED default (PKG_RUN_CAPS) still governs         ║
-- ║  - /etc/pkg_caps.cfg can WIDEN what a manifest may ask    ║
-- ║  - /etc/pkg_caps.cfg can NARROW what is honoured, per     ║
-- ║    package and globally, and a denial always wins          ║
-- ║  - a config that will not load leaves NO overrides         ║
-- ║  - peripheral.printer is grantable (the printer add-on)   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_cap_policy.lua
--
-- Why this exists: FEAT-5 let an operator name a modded component type
-- and the cap that gates it in /etc/component_caps.cfg, but a PACKAGE's
-- declared caps were filtered through a static table in pkg.lua. So the
-- operator could grant that cap to a REPL and never to a package — the
-- manifest's request was dropped in silence and the package ran with no
-- hardware and no error saying why. These assertions pin the fix and,
-- more importantly, pin the thing the fix must NOT become: there is no
-- way to hand a package a capability its manifest never declared.

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_cap_policy.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

print("=== package capability policy Tests ===")
print()

-- ── Harness ──────────────────────────────────────────────────
-- One fake disk holding one package and (optionally) the cap config.
-- Each case rebuilds pkg from source so the module-level cache starts
-- empty; a cache shared across cases would have the first config
-- answering every later question.
local ENTRY_SRC = "return { commands = { d = function() return 'ran' end } }"

local function buildPkg(manifestCaps, cfgText)
  local DEMO = {
    name = "demo", version = "1.0", kind = "command",
    files = { "/usr/modules/demo/init.lua" },
    commands = { d = "/usr/modules/demo/init.lua" },
    capabilities = manifestCaps,
  }
  package.loaded["kernel.serialize"] = {
    encode = function() return "" end,
    saveFile = function() return true end,
    loadFile = function(_, path)
      if path:find("demo/package.lua", 1, true) then return DEMO end
      return nil
    end,
    -- The config is decoded as DATA, never load()ed. The real decoder is
    -- kernel.serialize's; here a tiny stand-in returns the table the case
    -- wants, or fails, so the fail-closed path is reachable.
    decode = function(raw)
      if raw == "BROKEN" then error("bad table") end
      if raw == "NOTATABLE" then return "just a string" end
      local fn = load("return " .. raw)
      if not fn then error("no parse") end
      return fn()
    end,
  }
  local lastCaps
  package.loaded["kernel.sandbox"] = {
    build = function(opts) lastCaps = opts and opts.caps or {}; return {} end,
  }
  package.loaded["kernel.users"] = { currentSession = function() return nil end }
  local warnings = {}
  local logMock = {
    info = function() end,
    warn = function(_, msg) warnings[#warnings + 1] = tostring(msg) end,
    error = function() end,
  }
  local fsMock = {
    exists = function(p)
      if p == "/etc/pkg_caps.cfg" then return cfgText ~= nil end
      return not p:find("/state", 1, true)
    end,
    isDirectory = function() return true end,
    makeDirectory = function() return true end,
    list = function(p)
      if p == "/var/pkg/installed" then return { "demo" } end
      return {}
    end,
    join = function(...) return table.concat({ ... }, "/") end,
    normalize = function(p) return p end,
    readFile = function(p)
      if p == "/usr/modules/demo/init.lua" then return ENTRY_SRC end
      if p == "/etc/pkg_caps.cfg" then return cfgText end
      return nil
    end,
    writeFile = function() return true end,
  }
  local chunk = tryload("tos/kernel/pkg.lua")
  if not chunk then return nil end
  local pkg = chunk()
  pkg.init({ fs = fsMock, log = logMock, users = package.loaded["kernel.users"] })
  local fn = pkg.getCommand("d")
  return pkg, lastCaps or {}, fn, warnings
end

-- ── The coded default, unchanged ─────────────────────────────
do
  local pkg, caps, fn = buildPkg({ "fs.read", "component", "legacy" })
  ok("pkg loaded", pkg ~= nil)
  test("the command resolves", "function", type(fn))
  test("fs.read granted", true, caps["fs.read"])
  test("component granted", true, caps.component)
  -- The one facet a manifest can never opt into: it unlocks raw os/io.
  test("legacy still dropped", nil, caps.legacy)
  test("an unknown facet is dropped", nil, caps.nonsense)

  -- capAllowed is the single auditable answer; every caller uses it.
  ok("capAllowed says yes to a coded cap", (pkg.capAllowed("demo", "fs.read")))
  ok("capAllowed says no to legacy", not (pkg.capAllowed("demo", "legacy")))
  local _, why = pkg.capAllowed("demo", "nonsense")
  ok("and gives a reason", tostring(why):find("not a package%-grantable") ~= nil)
end

-- ── peripheral.printer, for the printer add-on ───────────────
do
  local pkg, caps = buildPkg({ "peripheral.printer" })
  test("peripheral.printer is grantable", true, caps["peripheral.printer"])
  ok("and capAllowed agrees", (pkg.capAllowed("printer", "peripheral.printer")))
end

-- ── allow: widening what a manifest may request ──────────────
do
  -- Without the config, a cap for a modded component type is dropped —
  -- this is exactly the gap the feature closes, asserted from both sides.
  local _, before = buildPkg({ "peripheral.reactor" })
  test("an unknown peripheral cap is dropped by default", nil, before["peripheral.reactor"])

  local pkg, after = buildPkg({ "peripheral.reactor" },
    '{ allow = { "peripheral.reactor" } }')
  test("allow-listed cap is granted", true, after["peripheral.reactor"])
  ok("capAllowed agrees", (pkg.capAllowed("demo", "peripheral.reactor")))

  -- Widening does NOT reach `legacy`. An operator config must not be a
  -- route to raw os/io.
  local _, evil = buildPkg({ "legacy" }, '{ allow = { "legacy" } }')
  test("allow cannot re-enable legacy", nil, evil.legacy)
end

-- ── The manifest still has to ask ────────────────────────────
do
  -- The property that keeps `pkg info` honest: allow WIDENS what may be
  -- requested, it does not request on the package's behalf. A package
  -- declaring nothing gets nothing, however permissive the config.
  local _, caps = buildPkg({}, '{ allow = { "peripheral.reactor", "net" } }')
  test("an undeclared cap is not granted", nil, caps["peripheral.reactor"])
  test("nor a coded one", nil, caps.net)
end

-- ── deny: narrowing, per package and globally ────────────────
do
  local pkg, caps = buildPkg({ "fs.read", "net" },
    '{ deny = { ["*"] = { "net" } } }')
  test("a global denial removes the cap", nil, caps.net)
  test("and leaves the others alone", true, caps["fs.read"])
  local _, why = pkg.capAllowed("demo", "net")
  ok("the refusal names the config", tostring(why):find("pkg_caps.cfg") ~= nil)
end

do
  local _, caps = buildPkg({ "fs.read", "net" },
    '{ deny = { demo = { "net" } } }')
  test("a per-package denial removes the cap", nil, caps.net)
  test("and leaves the others alone", true, caps["fs.read"])
end

do
  -- Naming a DIFFERENT package must not affect this one.
  local _, caps = buildPkg({ "net" }, '{ deny = { other = { "net" } } }')
  test("another package's denial does not apply", true, caps.net)
end

do
  -- Deny beats allow: there is nothing to resolve, either one refuses.
  local pkg, caps = buildPkg({ "peripheral.reactor" },
    '{ allow = { "peripheral.reactor" }, deny = { ["*"] = { "peripheral.reactor" } } }')
  test("deny outranks allow", nil, caps["peripheral.reactor"])
  ok("capAllowed agrees", not (pkg.capAllowed("demo", "peripheral.reactor")))
end

-- ── A dropped cap is no longer silent ────────────────────────
do
  local _, _, _, warnings = buildPkg({ "net" }, '{ deny = { ["*"] = { "net" } } }')
  local found = false
  for _, w in ipairs(warnings) do
    if w:find("net") and w:find("refused") then found = true end
  end
  ok("the refusal is logged with the facet named", found)
end

-- ── Fail-closed on a config that will not load ───────────────
do
  -- Losing the ALLOW half is the safe direction: packages fall back to
  -- the coded default rather than gaining anything.
  local pkg, caps, _, warnings = buildPkg({ "peripheral.reactor" }, "BROKEN")
  test("an undecodable config grants nothing extra", nil, caps["peripheral.reactor"])
  ok("capAllowed still refuses", not (pkg.capAllowed("demo", "peripheral.reactor")))
  -- Losing the DENY half is not safe, so it has to be loud.
  local loud = false
  for _, w in ipairs(warnings) do
    if w:find("pkg_caps.cfg") then loud = true end
  end
  ok("and it says so out loud", loud)
end

do
  local _, caps = buildPkg({ "peripheral.reactor" }, "NOTATABLE")
  test("a non-table config grants nothing extra", nil, caps["peripheral.reactor"])
end

do
  -- Junk entries are skipped individually rather than voiding the file.
  local pkg = buildPkg({ "fs.read" },
    '{ allow = { "peripheral.reactor", "has spaces", 42 } }')
  ok("a valid entry survives junk beside it", (pkg.capAllowed("demo", "peripheral.reactor")))
  ok("the junk does not", not (pkg.capAllowed("demo", "has spaces")))
end

-- ── Reload ───────────────────────────────────────────────────
do
  local pkg = buildPkg({ "fs.read" }, '{ allow = { "peripheral.reactor" } }')
  test("reloadCapConfig exists", "function", type(pkg.reloadCapConfig))
  local allow = pkg.reloadCapConfig()
  ok("and re-reads the file", allow["peripheral.reactor"])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
