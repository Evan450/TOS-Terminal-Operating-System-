-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: the narrow `crypto` capability        ║
-- ║  - sandbox.build exposes crypto ONLY with the cap        ║
-- ║  - secret() exists only when kernel.pkg threads a        ║
-- ║    pkgName, is admin-gated, persists, and is isolated    ║
-- ║    per package                                            ║
-- ║  - pkg's allowlist accepts "crypto" and passes pkgName   ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_crypto_cap.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_sandbox_crypto_cap.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- ── Stubs ────────────────────────────────────────────────────
local saltCounter = 0
package.loaded["kernel.crypto"] = {
  hash = function(s) return "H<" .. tostring(s) .. ">" end,
  hmac = function(k, m) return "M<" .. tostring(k) .. "|" .. tostring(m) .. ">" end,
  ctEquals = function(a, b) return a == b end,
  salt = function(n)
    saltCounter = saltCounter + 1
    return string.rep(string.char(64 + saltCounter), n or 32)
  end,
  _privateKDF = function() return "must not leak" end,
}
local fakeDisk = {}
package.loaded["kernel.fs"] = {
  exists = function(p) return fakeDisk[p] ~= nil or p == "/var/pkg/secrets" end,
  readFile = function(p) return fakeDisk[p] end,
  writeFile = function(p, d) fakeDisk[p] = d; return true end,
  makeDirectory = function() return true end,
}
local liveSession = nil
package.loaded["kernel.process"] = {
  currentSession = function() return liveSession end,
}

local sandbox = tryload("tos/kernel/sandbox.lua")()

print("=== sandbox crypto capability Tests ===")
print()

-- ── Exposure ─────────────────────────────────────────────────
local env = sandbox.build({ caps = { crypto = true }, pkgName = "tape-authenticator" })
test("crypto exposed with cap", "table", type(env.crypto))
test("hash exposed", "function", type(env.crypto and env.crypto.hash))
test("hmac exposed", "function", type(env.crypto and env.crypto.hmac))
test("ctEquals exposed", "function", type(env.crypto and env.crypto.ctEquals))
test("random exposed", "function", type(env.crypto and env.crypto.random))
test("secret exposed (pkgName threaded)", "function", type(env.crypto and env.crypto.secret))
test("kernel internals NOT exposed", nil, env.crypto and env.crypto._privateKDF)
test("hmac passes through", "M<k|m>", env.crypto.hmac("k", "m"))

local envNoCap = sandbox.build({ caps = {}, pkgName = "tape-authenticator" })
test("crypto NOT exposed without cap", nil, envNoCap.crypto)

local envNoName = sandbox.build({ caps = { crypto = true } })
test("no pkgName -> no secret()", nil, envNoName.crypto and envNoName.crypto.secret)
test("...but pure primitives still there", "function",
  type(envNoName.crypto and envNoName.crypto.hash))

local envBadName = sandbox.build({ caps = { crypto = true }, pkgName = "../etc" })
test("path-hostile pkgName -> no secret()", nil,
  envBadName.crypto and envBadName.crypto.secret)

do
  local ok = pcall(env.require, "kernel.crypto")
  test("require('kernel.crypto') still blocked", false, ok)
end

-- ── secret(): gating, persistence, isolation ─────────────────
liveSession = nil
do
  local s, err = env.crypto.secret()
  test("no session -> denied", nil, s)
  test("denial names the gate", true,
    tostring(err):find("admin", 1, true) ~= nil)
end

liveSession = { user = "guest", tier = 0 }
test("guest tier denied", nil, (env.crypto.secret()))
liveSession = { user = "bob", tier = 1 }
test("USER tier denied", nil, (env.crypto.secret()))

liveSession = { user = "alice", tier = 2 }
local s1 = env.crypto.secret()
test("admin gets a secret", "string", type(s1))
test("secret is 32 bytes", 32, s1 and #s1)
test("secret persisted under /var/pkg/secrets", s1,
  fakeDisk["/var/pkg/secrets/tape-authenticator"])
test("second call returns the SAME secret", s1, (env.crypto.secret()))

-- Kernel pseudo-sessions pass the gate too (rc.d / boot callers).
liveSession = { isKernel = true }
test("kernel session allowed", s1, (env.crypto.secret()))

-- Per-package isolation: a different pkgName gets a different secret.
liveSession = { user = "alice", tier = 2 }
local envOther = sandbox.build({ caps = { crypto = true }, pkgName = "other-pkg" })
local s2 = envOther.crypto.secret()
test("different package -> different secret", false, s1 == s2)
test("other secret stored under its own name", s2,
  fakeDisk["/var/pkg/secrets/other-pkg"])

-- ── pkg side: allowlist + pkgName threading ──────────────────
print()
local ENTRY_SRC = "return { commands = { c = function() return 'ran' end } }"
local DEMO = {
  name = "demo", version = "1.0", kind = "command",
  files = { "/usr/modules/demo/init.lua" },
  commands = { c = "/usr/modules/demo/init.lua" },
  capabilities = { "crypto", "legacy" },
}
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end,
  loadFile = function(_, path)
    if path:find("demo/package.lua", 1, true) then return DEMO end
    return nil
  end,
}
local lastOpts
package.loaded["kernel.sandbox"] = {
  build = function(opts) lastOpts = opts or {}; return {} end,
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
local pkg = tryload("tos/kernel/pkg.lua")()
pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })
local fn = pkg.getCommand("c")
test("pkg command with crypto cap resolves", "function", type(fn))
test("'crypto' cap passed to sandbox", true, lastOpts and lastOpts.caps
  and lastOpts.caps.crypto == true)
test("pkgName threaded to sandbox.build", "demo", lastOpts and lastOpts.pkgName)
test("'legacy' still DROPPED", nil, lastOpts and lastOpts.caps and lastOpts.caps.legacy)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
