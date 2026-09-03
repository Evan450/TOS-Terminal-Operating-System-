-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package command runs with ITS caps     ║
-- ║                                                            ║
-- ║  FOUND IN-GAME, 2026-08-11, and it had been true of every  ║
-- ║  peripheral capability since they were introduced.         ║
-- ║                                                            ║
-- ║  A manifest's capabilities reached the SANDBOX (where they ║
-- ║  filter component.proxy) and stopped there. The kernel's    ║
-- ║  peripheral modules gate on kernel.process.current().caps  ║
-- ║  — a DIFFERENT set, belonging to the running process. A     ║
-- ║  package command runs inside the shell's process, whose     ║
-- ║  caps are a fixed list that contained no peripheral entry   ║
-- ║  at all, so the gate could never open. `printer` reported   ║
-- ║  "peripheral.printer cap required" on a machine where       ║
-- ║  hotplug had logged the printer seconds earlier.            ║
-- ║                                                            ║
-- ║  Off-box tests could not have caught it: they stub the      ║
-- ║  sandbox, so the sandbox cap set was the only one they ever ║
-- ║  looked at. These assertions look at the PROCESS.           ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_capscope.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_capscope.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

print("=== package capability scope Tests ===")
print()

-- ── Harness ──────────────────────────────────────────────────
-- A fake process whose caps stand in for the shell's, and a package
-- whose entry reports what kernel.process.current().caps said while it
-- was running. That report is the whole test.
local shellProc
local function newProc()
  shellProc = { pid = 1, caps = {
    ["fs.read"] = true, ["fs.write"] = true, component = true,
    ["peripheral.printer"] = true, ["peripheral.redstone"] = true,
  } }
  return { current = function() return shellProc end }
end

local SEEN   -- caps observed from inside the command
local ENTRY = [[
return { commands = { demo = function()
  local p = require("kernel.process")
  local cur = p.current()
  local snap = {}
  for k, v in pairs(cur.caps or {}) do snap[k] = v end
  _G.__SEEN = snap
  return "ran"
end } }
]]

local function build(manifestCaps, entrySrc)
  local DEMO = {
    name = "demo", version = "1.0", kind = "command",
    files = { "/usr/modules/demo/init.lua" },
    commands = { demo = "/usr/modules/demo/init.lua" },
    capabilities = manifestCaps,
  }
  package.loaded["kernel.process"] = newProc()
  package.loaded["kernel.serialize"] = {
    encode = function() return "" end, decode = function() return nil end,
    saveFile = function() return true end,
    loadFile = function(_, path)
      if path:find("demo/package.lua", 1, true) then return DEMO end
      return nil
    end,
  }
  local sandboxCaps
  package.loaded["kernel.sandbox"] = {
    build = function(opts)
      sandboxCaps = opts and opts.caps or {}
      -- A real sandbox env; the entry needs require + pairs to report,
      -- and `error` for the crash case below.
      return { require = require, pairs = pairs, _G = _G, print = print,
               error = error, pcall = pcall }
    end,
  }
  package.loaded["kernel.users"] = { currentSession = function() return nil end }
  local fsMock = {
    exists = function(p) return not p:find("/state", 1, true) end,
    isDirectory = function() return true end,
    makeDirectory = function() return true end,
    list = function(p) if p == "/var/pkg/installed" then return { "demo" } end return {} end,
    join = function(...) return table.concat({ ... }, "/") end,
    normalize = function(p) return p end,
    readFile = function(p)
      if p == "/usr/modules/demo/init.lua" then return entrySrc or ENTRY end
      return nil
    end,
    writeFile = function() return true end,
  }
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })
  return pkg, function() return sandboxCaps end
end

-- ══════════════════════════════════════════════════════════════════════
-- THE BUG: a declared peripheral cap must reach the PROCESS
-- ══════════════════════════════════════════════════════════════════════
do
  _G.__SEEN = nil
  local pkg = build({ "fs.read", "component", "peripheral.printer" })
  local fn = pkg.getCommand("demo")
  test("the command resolves", "function", type(fn))
  test("it runs", "ran", fn())
  SEEN = _G.__SEEN
  ok("the command saw a cap table", type(SEEN) == "table")
  -- This is the assertion that would have failed before the fix.
  test("peripheral.printer reached the process", true, SEEN["peripheral.printer"])
  test("so did fs.read", true, SEEN["fs.read"])
  test("and component", true, SEEN.component)
end

-- ══════════════════════════════════════════════════════════════════════
-- ...and it must be the MANIFEST's set, not the shell's
-- ══════════════════════════════════════════════════════════════════════
do
  -- The shell process holds peripheral.redstone. A package that did not
  -- declare it must NOT see it — otherwise the fix would have been a
  -- privilege widening, which is worse than the bug it replaced.
  _G.__SEEN = nil
  local pkg = build({ "fs.read", "peripheral.printer" })
  pkg.getCommand("demo")()
  SEEN = _G.__SEEN
  test("the declared cap is present", true, SEEN["peripheral.printer"])
  test("the shell's undeclared cap is NOT", nil, SEEN["peripheral.redstone"])
  test("nor is a cap nobody has", nil, SEEN["peripheral.robot"])
end

do
  -- A package declaring nothing gets nothing, even though the shell
  -- process it runs inside holds five caps.
  _G.__SEEN = nil
  local pkg = build({})
  pkg.getCommand("demo")()
  SEEN = _G.__SEEN
  local n = 0
  for _ in pairs(SEEN or {}) do n = n + 1 end
  test("a capless package sees an empty set", 0, n)
end

do
  -- The allowlist still applies: `legacy` can never be requested, and it
  -- must not sneak in through the process either.
  _G.__SEEN = nil
  local pkg = build({ "fs.read", "legacy" })
  pkg.getCommand("demo")()
  SEEN = _G.__SEEN
  test("legacy is still dropped", nil, SEEN.legacy)
  test("and the legitimate cap survives", true, SEEN["fs.read"])
end

-- ══════════════════════════════════════════════════════════════════════
-- The scope is exactly the call
-- ══════════════════════════════════════════════════════════════════════
do
  -- The process gets its own caps back afterwards. A scope that leaked
  -- would leave the SHELL wearing a package's caps for the rest of the
  -- session — a quieter bug than the one being fixed, and worse.
  local pkg = build({ "peripheral.printer" })
  local before = {}
  for k, v in pairs(shellProc.caps) do before[k] = v end
  pkg.getCommand("demo")()
  local sameCount = 0
  for k, v in pairs(shellProc.caps) do
    test("shell cap '" .. k .. "' unchanged", before[k], v)
    sameCount = sameCount + 1
  end
  local beforeCount = 0
  for _ in pairs(before) do beforeCount = beforeCount + 1 end
  test("the shell kept exactly its own caps", beforeCount, sameCount)
end

do
  -- An ERROR inside the command must restore the caps too, or one
  -- crashing package permanently rewrites the shell's authority.
  local BOOM = "return { commands = { demo = function() error('boom') end } }"
  local pkg = build({ "peripheral.printer" }, BOOM)
  local before = {}
  for k, v in pairs(shellProc.caps) do before[k] = v end
  local fn = pkg.getCommand("demo")
  local okCall, err = pcall(fn)
  test("the error propagates", false, okCall)
  ok("and says what went wrong", tostring(err):find("boom") ~= nil)
  for k, v in pairs(before) do
    test("after an error, shell cap '" .. k .. "' is restored", v, shellProc.caps[k])
  end
  test("and nothing was added", nil, shellProc.caps["peripheral.tape"])
end

-- ══════════════════════════════════════════════════════════════════════
-- The shell's own caps are a superset (so first-party commands work)
-- ══════════════════════════════════════════════════════════════════════
do
  -- `redstone`, `robot` and `inventory` are FIRST-PARTY shell commands
  -- that reach the same peripheral modules. They run in the shell
  -- process, so the shell's cap list is what decides whether they work —
  -- and it had no peripheral entry at all, which is why they reported
  -- "no component" on machines where the device was attached.
  local h = io.open("tos/kernel/init.lua", "rb")
  local src = h and h:read("*a") or ""
  if h then h:close() end
  local caps = src:match("local shellCaps = %{(.-)%}")
  ok("shellCaps is still there to check", caps ~= nil and #caps > 0)
  if caps then
    for _, need in ipairs({ "peripheral.redstone", "peripheral.robot",
                            "peripheral.inventory", "peripheral.tape",
                            "peripheral.printer" }) do
      ok("the shell process holds " .. need, caps:find(need, 1, true) ~= nil)
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
