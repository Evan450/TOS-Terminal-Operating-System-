-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the recovery menu                            ║
-- ║                                                                ║
-- ║  When a critical file was missing, /init.lua could only reboot ║
-- ║  or switch disks, with a verified copy sitting in srm's store  ║
-- ║  on the same disk. The menu runs before the kernel exists, so  ║
-- ║  this drives it the way /init.lua does: the real menu and the  ║
-- ║  real srm over a raw filesystem proxy, with scripted keys.     ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_recovery.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_recovery.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, totalMemory = function() return 8e6 end,
  pullSignal = function() return nil end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

local recovery = require("kernel.recovery")
local srm = require("kernel.srm")

-- A raw filesystem proxy, shaped like OC's: rename refuses an existing target.
local function newProxy(files)
  local px, handles, nextH = {}, {}, 0
  local writes = {}
  px.writes = writes
  function px.exists(p)
    if files[p] then return true end
    for k in pairs(files) do if k:sub(1, #p + 1) == p .. "/" then return true end end
    return false
  end
  function px.size(p) return files[p] and #files[p] or 0 end
  function px.remove(p) local had = files[p] ~= nil; files[p] = nil; return had end
  function px.makeDirectory() return true end
  function px.rename(a, b)
    if files[b] or not files[a] then return false end
    files[b], files[a] = files[a], nil
    return true
  end
  function px.open(p, mode)
    if mode == "r" and not files[p] then return nil, "no such file" end
    nextH = nextH + 1
    if mode == "w" then files[p] = "" end
    handles[nextH] = { path = p, pos = 1 }
    return nextH
  end
  function px.read(h, n)
    local st = handles[h]
    local data = files[st.path]
    if st.pos > #data then return nil end
    local chunk = data:sub(st.pos, st.pos + n - 1)
    st.pos = st.pos + #chunk
    return chunk
  end
  function px.write(h, data)
    local st = handles[h]
    if px.failWrites and st.path:find(px.failWrites, 1, true) then return nil, "disk full" end
    files[st.path] = files[st.path] .. data
    writes[#writes + 1] = st.path
    return true
  end
  function px.close(h) handles[h] = nil end
  return px
end

local function screenOf(keys, px, extra)
  local shown, ticks = {}, { n = 0 }
  local ctx = {
    W = 80, H = 25, px = px, component = package.loaded["component"],
    otherDisk = function() end,
    clear = function() end,
    color = function(role) return role end,
    set = function(_, _, text) shown[#shown + 1] = tostring(text) end,
    tick = function() ticks.n = ticks.n + 1 end,
    readKey = function()
      local k = table.remove(keys, 1)
      if not k then error("the menu asked for more keys than the script has") end
      return "key_down", k, 0
    end,
  }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return ctx, shown, ticks
end
local function byte(c) return c:byte() end
local function text(shown) return table.concat(shown, "\n") end

print("=== what it offers ===")
print()
do
  local function labels(items)
    local t = {}
    for _, i in ipairs(items) do t[#t + 1] = i.action end
    return table.concat(t, " ")
  end
  test("a machine that got to POST can carry on",
    labels(recovery.items(false, true)) == "continue safe settings check restore disk reboot off",
    labels(recovery.items(false, true)))
  test("one that failed its file check is offered only what can work from there",
    labels(recovery.items(true, true)) == "check restore disk reboot off",
    labels(recovery.items(true, true)))
  test("with no way to another disk, that is not on the list",
    labels(recovery.items(true, false)) == "check restore reboot off")
end

print()
print("=== the menu answers ===")
print()
do
  for _, c in ipairs({ { 1, "continue" }, { 2, "safe" }, { 3, "settings" } }) do
    local ctx = screenOf({ 48 + c[1] }, newProxy({}))
    test("key " .. c[1] .. " is " .. c[2], recovery.run(ctx) == c[2])
  end
  local ctx = screenOf({ 57, 0, 55 }, newProxy({}), { otherDisk = function() end })
  test("a key off the list does nothing, and it waits for one that is",
    recovery.run(ctx) == "reboot")
  ctx = screenOf({ 56 }, newProxy({}), { otherDisk = function() end })
  test("the last item powers off", recovery.run(ctx) == "off")

  local switched = false
  ctx = screenOf({ 51, 52 }, newProxy({}), { failed = true,
    otherDisk = function() switched = true end })
  test("the disk switch reaches /init.lua's",
    recovery.run(ctx) == "reboot" and switched)

  local _, shown
  ctx, shown = screenOf({ 52 }, newProxy({}), { failed = true, why = "3 system file(s) are missing.",
    otherDisk = function() end })
  recovery.run(ctx)
  test("it says what brought it here", text(shown):find("3 system file(s) are missing.", 1, true) ~= nil)
end

print()
print("=== a file comes back ===")
print()
do
  local crypto = require("kernel.crypto")
  local files = {
    ["/var/pkg/installed/tos-core/package.lua"] =
      'return { critical = { "/tos/kernel/a.lua", "/tos/kernel/b.lua" } }',
    ["/tos/kernel/a.lua"] = "return 'the real a'",
    ["/tos/kernel/b.lua"] = "return 'the real b'",
  }
  local px = newProxy(files)
  local fs = recovery.fsOver(px)
  test("reading through the adapter returns the file", fs.readFile("/tos/kernel/a.lua") == "return 'the real a'")
  local deps = { fs = fs, crypto = crypto, component = package.loaded["component"] }
  local okB, sum = srm.baseline(deps, { content = true })
  test("a baseline with copies can be captured through the adapter",
    okB and sum.stored == 2, okB and sum.stored or sum)

  -- A clean machine.
  local ctx, shown, ticks = screenOf({ byte("1"), 0, byte("4") }, px, { failed = true })
  test("the check runs", recovery.run(ctx) == "reboot")
  test("and it says the files are fine", text(shown):lower():find("match", 1, true) ~= nil
    or text(shown):lower():find("intact", 1, true) ~= nil
    or text(shown):lower():find("ok", 1, true) ~= nil, text(shown))
  test("it yields between files: OC stops a machine that does not", ticks.n >= 2, ticks.n)
  test("and leaves nothing behind for srm", srm.beat == nil)

  -- The failure this exists for.
  files["/tos/kernel/b.lua"] = nil
  files["/tos/kernel/a.lua"] = "return 'someone changed this'"
  ctx, shown = screenOf({ byte("1"), 0, 0, byte("4") }, px, { failed = true })
  recovery.run(ctx)
  test("the check names what is wrong", text(shown):find("b.lua", 1, true) ~= nil, text(shown))
  test("and changes nothing", files["/tos/kernel/b.lua"] == nil
    and files["/tos/kernel/a.lua"] == "return 'someone changed this'")

  ctx = screenOf({ byte("2"), byte("n"), byte("4") }, px, { failed = true })
  recovery.run(ctx)
  test("no is no", files["/tos/kernel/b.lua"] == nil)

  ctx, shown = screenOf({ byte("2"), byte("y"), 0, byte("4") }, px, { failed = true })
  test("yes restores", recovery.run(ctx) == "reboot")
  test("the missing file is back", files["/tos/kernel/b.lua"] == "return 'the real b'", text(shown))
  test("the changed one too", files["/tos/kernel/a.lua"] == "return 'the real a'")
  test("with no temp file left over", files["/tos/kernel/a.lua.tos-tmp"] == nil
    and files["/tos/kernel/b.lua.tos-tmp"] == nil)

  -- A restore that cannot write must not destroy what is there.
  files["/tos/kernel/a.lua"] = "the only copy of a"
  px.failWrites = "a.lua"
  ctx, shown = screenOf({ byte("2"), byte("y"), 0, byte("4") }, px, { failed = true })
  recovery.run(ctx)
  px.failWrites = nil
  test("a write that fails leaves the old file alone", files["/tos/kernel/a.lua"] == "the only copy of a",
    files["/tos/kernel/a.lua"])
  test("and says so", text(shown):find("write failed", 1, true) ~= nil, text(shown))
end

print()
print("=== when it cannot help ===")
print()
do
  local px = newProxy({})
  local ctx, shown = screenOf({ byte("1"), 0, byte("4") }, px, { failed = true })
  recovery.run(ctx)
  test("no baseline says how to get one, and does not fall over",
    text(shown):find("baseline", 1, true) ~= nil, text(shown))

  local realSrm = package.loaded["kernel.srm"]
  package.loaded["kernel.srm"] = nil
  package.preload["kernel.srm"] = function() error("kernel/srm.lua is damaged") end
  ctx, shown = screenOf({ byte("1"), 0, byte("4") }, px, { failed = true })
  test("a damaged srm is said, and the menu carries on", recovery.run(ctx) == "reboot"
    and text(shown):find("did not load", 1, true) ~= nil, text(shown))
  package.preload["kernel.srm"] = nil
  package.loaded["kernel.srm"] = realSrm
end

print()
print("=== /init.lua's side ===")
print()
do
  local h = assert(io.open("init.lua", "rb"))
  local src = h:read("a"):gsub("\r\n", "\n"); h:close()
  test("the POST line offers it", src:find("R Recovery", 1, true) ~= nil)
  test("R opens it", src:find("elseif ch == 114 or ch == 82 then recover = true", 1, true) ~= nil)
  local screen = src:find('runRecovery(true, #missingFiles', 1, true)
  local fallback = screen and src:find("otherDisk()", screen, true)
  test("the missing-files screen tries the menu, then what it always did",
    screen ~= nil and fallback ~= nil)
  test("a menu that fails is caught, so it cannot stop a boot",
    src:find("local okM, action = pcall(rec.run", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
