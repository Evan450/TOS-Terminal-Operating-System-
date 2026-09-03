-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg command session isolation       ║
-- ║                                                        ║
-- ║  loadPkgEntry caches one sandbox per package and       ║
-- ║  shares it across all callers. It must NOT bind that   ║
-- ║  sandbox to whoever loads the command FIRST, or a      ║
-- ║  root/boot first-loader's filesystem ACL leaks to a    ║
-- ║  later lower-tier caller (confused-deputy priv-esc).   ║
-- ║  The fix: build with NO session so securefs resolves   ║
-- ║  the LIVE caller per-call (forSession(nil)).           ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_session_isolation.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- The "live" principal, as securefs.sessionOf would resolve from the running
-- process. We flip this between calls to model different callers reaching the
-- SAME cached package command.
local LIVE = nil
local usersStub = {
  currentSession = function()
    if not LIVE then return nil end
    return { user = LIVE, tier = (LIVE == "root") and 3 or 0 }
  end,
}

-- The package command writes a file and returns the user the write ran AS.
-- `fs` resolves from the sandbox env built below.
local ENTRY_SRC = [[
return { commands = { wcmd = function()
  local ok, who = fs.writeFile("/root/secret", "x")
  return who
end } }
]]

local DEMO = {
  name = "demo", version = "1.0", kind = "command",
  files = { "/usr/modules/demo/init.lua" },
  commands = { wcmd = "/usr/modules/demo/init.lua" },
  capabilities = { "fs.write" },
}

package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end,
  loadFile = function(_, path)
    if path:find("demo/package.lua", 1, true) then return DEMO end
    return nil
  end,
}

-- Fake sandbox that mimics the securefs identity model precisely:
--   * `bound` = opts.session (what loadPkgEntry passes). After the fix this is
--     nil; securefs.forSession(nil) appends no session, so each fs call
--     resolves the LIVE process principal.
--   * If a session WERE captured (the bug), `bound` wins on every call — the
--     write always runs as the first loader regardless of who calls later.
local capturedBuildSession = "UNSET"
package.loaded["kernel.sandbox"] = {
  build = function(opts)
    capturedBuildSession = opts and opts.session
    local bound = opts and opts.session
    return {
      fs = {
        writeFile = function(_path, _data)
          local sess = bound or usersStub.currentSession()  -- sessionOf semantics
          return true, sess and sess.user or nil
        end,
      },
    }
  end,
}
package.loaded["kernel.users"] = usersStub

local STATE_DISABLED = false
local fsMock = {
  exists = function(p) if p:find("/state", 1, true) then return STATE_DISABLED end return true end,
  isDirectory = function() return true end,
  makeDirectory = function() return true end,
  list = function(p) if p == "/var/pkg/installed" then return { "demo" } end return {} end,
  join = function(...) return table.concat({ ... }, "/") end,
  normalize = function(p) return p end,
  readFile = function(p)
    if p == "/usr/modules/demo/init.lua" then return ENTRY_SRC end
    if p:find("/state", 1, true) then return STATE_DISABLED and "d" or "e" end
    return nil
  end,
  writeFile = function() return true end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_session_isolation.lua"
local base = here:gsub("[^/\\]*$", "")
local pkg
for _, p in ipairs({ base .. "../../../tos/kernel/pkg.lua", "tos/kernel/pkg.lua",
    "TOS-Dev/tos/kernel/pkg.lua" }) do
  local chunk = loadfile(p); if chunk then pkg = chunk(); break end
end
if not pkg then
  print("FAIL: could not load pkg.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
pkg.init({ fs = fsMock, log = nil, users = usersStub })

print("=== pkg Command Session-Isolation Tests ===")
print()

-- ROOT loads (and caches) the command first.
LIVE = "root"
local fn = pkg.getCommand("wcmd")
test("getCommand returns a function", "function", type(fn))
test("loadPkgEntry binds NO fixed session (fix)", nil, capturedBuildSession)
test("root's own invocation runs as root", "root", fn and fn())

-- A GUEST now runs the SAME cached command. It must run as the guest, NOT
-- inherit root's session from the cached sandbox.
LIVE = "guest"
local who = pkg.getCommand("wcmd")()
test("guest invocation of cached command runs as guest (no priv-esc)", "guest", who)

-- And with no live session (post-boot, unattributed), it must fail closed —
-- resolve to nil rather than defaulting to a privileged session.
LIVE = nil
local who2 = pkg.getCommand("wcmd")()
test("no live session -> no implicit privileged session", nil, who2)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
