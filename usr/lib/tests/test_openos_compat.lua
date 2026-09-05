-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the two OpenOS-shim lists must agree        ║
-- ║                                                                ║
-- ║  compat.init() registers OpenOS module names into              ║
-- ║  package.loaded. /init.lua's OPENOS_SHIMS decides which names  ║
-- ║  LAZILY trigger that registration on first require().          ║
-- ║                                                                ║
-- ║  They are separate literals in separate files and nothing kept ║
-- ║  them in step. `internet` was in the first and not the second, ║
-- ║  so require("internet") fell past the hook into the search     ║
-- ║  path and loaded OpenOS's /lib/internet.lua instead of ours.   ║
-- ║                                                                ║
-- ║  It was ORDER-DEPENDENT, which is why nobody noticed: require  ║
-- ║  any other shim name first and compat is already initialized,  ║
-- ║  so package.loaded answers correctly. Require `internet` first ║
-- ║  on a disk with no OpenOS underneath and it fails outright.    ║
-- ║                                                                ║
-- ║  Source-parsed rather than executed: /init.lua is a boot chunk ║
-- ║  with real side effects and cannot be required off-box.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_openos_compat.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end

print("=== OpenOS compat shim lists ===")
print()

local initSrc   = findUp("init.lua")
local compatSrc = findUp("tos/compat/init.lua")
test("/init.lua readable", initSrc ~= nil)
test("tos/compat/init.lua readable", compatSrc ~= nil)

if initSrc and compatSrc then
  -- The lazy-trigger set in /init.lua.
  local lazyBlock = initSrc:match("local OPENOS_SHIMS = (%b{})")
  test("OPENOS_SHIMS found in /init.lua", lazyBlock ~= nil)

  -- The registration map in compat.init(). Keys are the OpenOS names.
  local shimBlock = compatSrc:match("local shims = (%b{})")
  test("the shims map found in compat.init", shimBlock ~= nil)

  if lazyBlock and shimBlock then
    local lazy, registered = {}, {}
    for name in lazyBlock:gmatch("([%a_][%w_]*)%s*=%s*true") do lazy[name] = true end
    for name in shimBlock:gmatch('%["([%a_][%w_]*)"%]%s*=') do registered[name] = true end

    local nLazy, nReg = 0, 0
    for _ in pairs(lazy) do nLazy = nLazy + 1 end
    for _ in pairs(registered) do nReg = nReg + 1 end
    test("parsed the lazy-trigger list (" .. nLazy .. " names)", nLazy > 5)
    test("parsed the registration map (" .. nReg .. " names)", nReg > 5)

    -- The bug: registered but never lazily triggered. That name resolves
    -- through the search path instead, which on a machine with OpenOS
    -- still on disk silently loads OpenOS's library.
    local unhooked = {}
    for name in pairs(registered) do
      if not lazy[name] then unhooked[#unhooked + 1] = name end
    end
    table.sort(unhooked)
    if #unhooked > 0 then
      print("    registered by compat.init but NOT in OPENOS_SHIMS:")
      for _, n in ipairs(unhooked) do print("      " .. n) end
    end
    test("every registered shim is also a lazy trigger", #unhooked == 0)

    -- The mirror image: a trigger for a name nothing registers loads the
    -- whole compat layer and then still misses, which is pure cost.
    local unregistered = {}
    for name in pairs(lazy) do
      if not registered[name] then unregistered[#unregistered + 1] = name end
    end
    table.sort(unregistered)
    if #unregistered > 0 then
      print("    triggers compat but is not registered by it:")
      for _, n in ipairs(unregistered) do print("      " .. n) end
    end
    test("every lazy trigger is actually registered", #unregistered == 0)

    -- `internet` specifically, because this is the one that shipped.
    test("internet is registered by compat.init", registered["internet"] == true)
    test("internet triggers the lazy load (the bug: it did not)",
      lazy["internet"] == true)

    -- The hook has to run BEFORE the path search, or none of the above
    -- matters: the search would reach /lib first and win.
    local hookPos   = initSrc:find("OPENOS_SHIMS%[name%]")
    local searchPos = initSrc:find("for _, pattern in ipairs%(searchPaths%)")
    test("the shim hook precedes the search-path loop",
      hookPos ~= nil and searchPos ~= nil and hookPos < searchPos)
  end
end

-- Every shim the map points at must exist, or the name registers as a
-- failure and the search path quietly answers instead.
if compatSrc then
  local shimBlock = compatSrc:match("local shims = (%b{})")
  if shimBlock then
    local missing = {}
    for path in shimBlock:gmatch('=%s*"compat%.([%a_][%w_]*)"') do
      if not findUp("tos/compat/" .. path .. ".lua") then
        missing[#missing + 1] = path
      end
    end
    table.sort(missing)
    for _, m in ipairs(missing) do print("    no such file: tos/compat/" .. m .. ".lua") end
    test("every shim path resolves to a real file", #missing == 0)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
