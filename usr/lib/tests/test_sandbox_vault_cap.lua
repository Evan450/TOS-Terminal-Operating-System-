-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: the narrow `vault` capability        ║
-- ║  - sandbox.build exposes vault ONLY with the cap        ║
-- ║  - only encrypt/decrypt/isEncrypted are exposed         ║
-- ║  - pkg's PKG_RUN_CAPS accepts "vault" (and still drops  ║
-- ║    "legacy")                                             ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_vault_cap.lua
--
-- Why this exists: the tape package's encrypt/decrypt commands used
-- require("kernel.vault"), which the pkg sandbox blocks — a latent
-- regression from the kernel.modules→pkg pivot. The fix routes the
-- three pure data-in/data-out vault functions through a new "vault"
-- capability; this test pins down both the exposure and its bounds.

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_sandbox_vault_cap.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- Stub kernel.vault: records calls, includes a function that must NOT
-- leak through the cap (the exposure is an explicit trio, not a
-- passthrough of the whole module).
local vaultCalls = {}
package.loaded["kernel.vault"] = {
  encrypt = function(pt, pp, o)
    vaultCalls[#vaultCalls + 1] = { "encrypt", pt, pp }
    return "BLOB:" .. pt, { algo = "stub" }
  end,
  decrypt = function(blob, pp)
    vaultCalls[#vaultCalls + 1] = { "decrypt", blob, pp }
    return (blob:gsub("^BLOB:", "")), { algo = "stub" }
  end,
  isEncrypted = function(s) return s:sub(1, 5) == "BLOB:" end,
  _dangerousInternal = function() return "must not be exposed" end,
}

print("=== sandbox vault capability Tests ===")
print()

-- ── Part 1: sandbox.build exposure ───────────────────────────
local sandboxChunk = tryload("tos/kernel/sandbox.lua")
if not sandboxChunk then
  print("FAIL: could not load sandbox.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local sandbox = sandboxChunk()

local envWith = sandbox.build({ caps = { vault = true } })
test("vault exposed with cap", "table", type(envWith.vault))
test("vault.encrypt exposed", "function", type(envWith.vault and envWith.vault.encrypt))
test("vault.decrypt exposed", "function", type(envWith.vault and envWith.vault.decrypt))
test("vault.isEncrypted exposed", "function", type(envWith.vault and envWith.vault.isEncrypted))
test("internal vault functions NOT exposed", nil,
  envWith.vault and envWith.vault._dangerousInternal)
do
  local n = 0
  for _ in pairs(envWith.vault or {}) do n = n + 1 end
  test("exactly the 3-function surface", 3, n)
end

-- Round trip through the exposed surface.
local blob = envWith.vault.encrypt("secret", "pw")
test("encrypt passes through", "BLOB:secret", blob)
test("isEncrypted true on blob", true, envWith.vault.isEncrypted(blob))
test("isEncrypted false on plain", false, envWith.vault.isEncrypted("plain"))
test("decrypt round-trips", "secret", (envWith.vault.decrypt(blob, "pw")))

local envWithout = sandbox.build({ caps = {} })
test("vault NOT exposed without cap", nil, envWithout.vault)

-- The require() path must stay closed even WITH the cap.
do
  local ok, err = pcall(envWith.require, "kernel.vault")
  test("require('kernel.vault') still blocked", false, ok)
  test("block message names the sandbox", true,
    tostring(err):find("sandbox", 1, true) ~= nil)
end

-- ── Part 2: pkg's manifest-cap allowlist accepts "vault" ─────
-- Mirror test_pkg_command.lua's stubbing so loadPkgEntry runs.
local ENTRY_SRC = "return { commands = { v = function() return 'ran' end } }"
local DEMO = {
  name = "demo", version = "1.0", kind = "command",
  files = { "/usr/modules/demo/init.lua" },
  commands = { v = "/usr/modules/demo/init.lua" },
  -- "legacy" included to prove the allowlist still drops it.
  capabilities = { "vault", "fs.read", "legacy" },
}
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end,
  loadFile = function(_, path)
    if path:find("demo/package.lua", 1, true) then return DEMO end
    return nil
  end,
}
local lastCaps
package.loaded["kernel.sandbox"] = {
  build = function(opts) lastCaps = opts and opts.caps or {}; return {} end,
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
    if p == "/usr/modules/demo/init.lua" then return ENTRY_SRC end
    return nil
  end,
  writeFile = function() return true end,
}

local pkgChunk = tryload("tos/kernel/pkg.lua")
if not pkgChunk then
  print("FAIL: could not load pkg.lua")
  failed = failed + 1
else
  local pkg = pkgChunk()
  pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })
  local fn = pkg.getCommand("v")
  test("pkg command with vault cap resolves", "function", type(fn))
  test("'vault' cap passed to sandbox", true, lastCaps and lastCaps.vault == true)
  test("'fs.read' cap passed alongside", true, lastCaps and lastCaps["fs.read"] == true)
  test("'legacy' still DROPPED", nil, lastCaps and lastCaps.legacy)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
