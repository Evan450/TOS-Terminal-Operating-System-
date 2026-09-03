-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: the shared keybind table                            ║
-- ║                                                            ║
-- ║  Operator, 2026-08-11: "^Q is the close combination, the   ║
-- ║  ttt game just uses Q to exit, which can be confusing for  ║
-- ║  Operators who prefer one standard" — plus: let operators  ║
-- ║  set their own binds.                                      ║
-- ║                                                            ║
-- ║  Both halves are checked here: ^Q closes everything TOS    ║
-- ║  ships, and an operator's rebind reaches all of it. The    ║
-- ║  second half is the one that can rot quietly — a program   ║
-- ║  that hard-codes a scancode keeps working, so nothing      ║
-- ║  fails until an operator changes a key and finds one       ║
-- ║  program ignoring them.                                     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_keys.lua

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

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local serialize = require("kernel.serialize")

-- A stub kernel.fs so the module's config layering can be driven.
local FILES = {}
package.loaded["kernel.fs"] = {
  exists   = function(p) return FILES[p] ~= nil end,
  readFile = function(p) return FILES[p] end,
}
package.loaded["kernel.users"] = { currentSession = function() return nil end }

local keys = require("shell.keys")

print("=== keybind Tests ===")
print()

local function withConfigs(cfgs, who)
  FILES = {}
  for path, t in pairs(cfgs) do FILES[path] = serialize.encode(t) end
  keys.reload()
  return who
end

-- ══════════════════════════════════════════════════════════════════════
-- Key names are written the way a person says them
-- ══════════════════════════════════════════════════════════════════════
-- A config nobody can read back is a config nobody will edit, which is
-- how "adjustable" becomes theoretical.
do
  test("^Q parses", 17, keys.parse("^Q").ch)
  test("Ctrl+Q parses the same", 17, keys.parse("Ctrl+Q").ch)
  test("ctrl-s too", 19, keys.parse("ctrl-s").ch)
  test("F1 is a scancode", 59, keys.parse("F1").code)
  test("F10 is a scancode", 68, keys.parse("F10").code)
  test("Esc", 1, keys.parse("Esc").code)
  test("Enter", 28, keys.parse("Enter").code)
  test("PageUp", 201, keys.parse("PageUp").code)
  test("a bare character binds to itself", 47, keys.parse("/").ch)
  test("nonsense is refused", nil, keys.parse("wibble"))
  test("an empty name is refused", nil, keys.parse(""))
  test("a non-string is refused", nil, keys.parse(42))

  -- Round trip, because the names are shown back in help text.
  test("^Q renders back", "^Q", keys.name(keys.parse("^Q")))
  test("F10 renders back", "F10", keys.name(keys.parse("F10")))
  test("/ renders back", "/", keys.name(keys.parse("/")))
end

-- ══════════════════════════════════════════════════════════════════════
-- The standard: ^Q closes things
-- ══════════════════════════════════════════════════════════════════════
do
  withConfigs({})
  ok("^Q is quit", keys.is("quit", 17, nil))
  ok("F10 is quit", keys.is("quit", nil, 68))
  -- Esc is honoured in case something ever delivers it...
  ok("Esc is still honoured", keys.is("quit", nil, 1))
  -- ...but never ADVERTISED. Telling an operator to press Esc is the bug
  -- the whole convention came from.
  test("the label does not mention Esc", nil, keys.label("quit"):find("Esc"))
  test("the label leads with the standard", "^Q / F10", keys.label("quit"))
  ok("a plain letter is not quit", not keys.is("quit", 113, nil))
  ok("F1 is help", keys.is("help", nil, 59))
  ok("^S is save", keys.is("save", 19, nil))
  ok("/ is find", keys.is("find", 47, nil))
end

-- ══════════════════════════════════════════════════════════════════════
-- The operator's binds
-- ══════════════════════════════════════════════════════════════════════
do
  withConfigs({ ["/etc/keys.cfg"] = { quit = { "F4" } } })
  ok("a system rebind takes effect", keys.is("quit", nil, 62))
  -- A rebind REPLACES rather than adds: "quit is F4" has to be able to
  -- mean only F4, or an operator can never take a binding away.
  ok("...and replaces the default", not keys.is("quit", 17, nil))
  test("the label follows", "F4", keys.label("quit"))
  ok("other actions are untouched", keys.is("help", nil, 59))
end

do
  withConfigs({
    ["/etc/keys.cfg"]   = { quit = { "F4" } },
    ["/root/.keys.cfg"] = { quit = { "^X" } },
  }, "root")
  ok("a user rebind layers over the system one", keys.is("quit", 24, nil, "root"))
  ok("...and the system one no longer applies", not keys.is("quit", nil, 62, "root"))
end

do
  withConfigs({ ["/etc/keys.cfg"] = { quit = { "^Q", "F10", "F4" } } })
  ok("several keys can share one action (1)", keys.is("quit", 17, nil))
  ok("several keys can share one action (2)", keys.is("quit", nil, 68))
  ok("several keys can share one action (3)", keys.is("quit", nil, 62))
end

do
  -- A single key, not a list, is accepted — it is what a person writes.
  withConfigs({ ["/etc/keys.cfg"] = { find = "^F" } })
  ok("a bare string binding works", keys.is("find", 6, nil))
end

-- ══════════════════════════════════════════════════════════════════════
-- A bad config must not cost you the key that closes things
-- ══════════════════════════════════════════════════════════════════════
do
  local cases = {
    { "an unknown action",   { wibble = { "^X" } } },
    { "an unparseable key",  { quit = { "Squiggle" } } },
    { "an empty list",       { quit = {} } },
    { "a number",            { quit = 42 } },
    { "junk beside a good one", { quit = { "Squiggle", "F4" } } },
  }
  for _, c in ipairs(cases) do
    withConfigs({ ["/etc/keys.cfg"] = c[2] })
    local okQ = keys.is("quit", 17, nil) or keys.is("quit", nil, 62)
    ok(c[1] .. ": something still quits", okQ)
  end
  -- The last case specifically: the good half survives the bad half.
  withConfigs({ ["/etc/keys.cfg"] = { quit = { "Squiggle", "F4" } } })
  ok("a valid key survives junk beside it", keys.is("quit", nil, 62))
end

do
  FILES = { ["/etc/keys.cfg"] = "this is not a table at all" }
  keys.reload()
  ok("an undecodable config falls back to the defaults", keys.is("quit", 17, nil))
end

-- ══════════════════════════════════════════════════════════════════════
-- The kernel's chords are not up for grabs
-- ══════════════════════════════════════════════════════════════════════
-- ^B, ^T and ^C are consumed by the kernel before a program sees them.
-- Accepting a rebind onto one would write a setting that silently does
-- nothing, which is worse than refusing it.
do
  ok("^B is reserved", keys.isReserved("^B"))
  ok("^T is reserved", keys.isReserved("^T"))
  ok("^C is reserved", keys.isReserved("^C"))
  ok("^Q is not", not keys.isReserved("^Q"))
  ok("F10 is not", not keys.isReserved("F10"))
  ok("the reserved set is listed for the operator", #keys.reserved() >= 3)
  for _, r in ipairs(keys.reserved()) do
    ok("reserved " .. r.key .. " says why", type(r.help) == "string" and #r.help > 0)
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- The listing an operator reads
-- ══════════════════════════════════════════════════════════════════════
do
  withConfigs({})
  local rows = keys.actions()
  ok("every action is listed", #rows == 9)
  for _, r in ipairs(rows) do
    ok(r.action .. " has keys", #r.keys > 0)
    ok(r.action .. " has a description", #r.help > 0)
    ok(r.action .. " is flagged as default", r.isDefault)
  end
  withConfigs({ ["/etc/keys.cfg"] = { quit = { "F4" } } })
  for _, r in ipairs(keys.actions()) do
    if r.action == "quit" then
      ok("a changed binding is flagged as NOT default", not r.isDefault)
    end
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- Packages can reach it
-- ══════════════════════════════════════════════════════════════════════
do
  -- A keybind table only the base image could read would standardise
  -- nothing — the whole point is that a bundled package and the shell
  -- agree on ^Q and both follow an operator rebind.
  local h = io.open("tos/kernel/sandbox.lua", "rb")
  local src = h and h:read("*a") or ""
  if h then h:close() end
  ok("sandboxed code may require shell.keys",
    src:find('%["shell%.keys"%] = true') ~= nil)
end

do
  -- Each first-party program that can be quit reads the shared table.
  -- Checked against SOURCE: the failure mode is silent (a hard-coded
  -- scancode keeps working) until an operator rebinds and finds one
  -- program ignoring them.
  local function extras(rel)
    for _, r in ipairs({ "../TOS-Extras/", "TOS-Extras/", "" }) do
      local h = io.open(r .. rel, "rb")
      if h then local s = h:read("*a"); h:close(); return s end
    end
  end
  for _, m in ipairs({ "write", "ttt", "snake", "stock", "tetris", "calc", "rc-pilot" }) do
    local src = extras("modules/" .. m .. "/init.lua")
    ok(m .. " exists", src ~= nil)
    if src then
      -- The module NAME, not one spelling of the call: these load it
      -- through pcall so an older base image degrades instead of
      -- crashing, and the test should not care which form is used.
      ok(m .. " consults the shared keybinds",
        src:find('"shell.keys"', 1, true) ~= nil)
      ok(m .. " degrades when the module is absent",
        src:find("pcall(require", 1, true) ~= nil)
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
