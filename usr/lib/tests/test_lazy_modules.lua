-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: #MEM lazy-load + streaming-load round   ║
-- ║                                                            ║
-- ║  The v1.4.x memory round moved boot-time module loading    ║
-- ║  to first-use and replaced read-whole-file+load() with     ║
-- ║  STREAMING load() readers. This pins the contracts that    ║
-- ║  round depends on:                                         ║
-- ║                                                            ║
-- ║   1. the streaming reader contract (empty-chunk hazard) —  ║
-- ║      shared by /init.lua's loadModuleFile and the kernel's ║
-- ║      verifySystem streamLoad;                              ║
-- ║   2. net.setServiceArm — the fail-closed arm state that    ║
-- ║      lets fileshare/rshd gate a backend they no longer     ║
-- ║      force into RAM;                                       ║
-- ║   3. compat.init idempotence (it can now be reached from   ║
-- ║      several call sites, not just boot);                   ║
-- ║   4. cron's lazy self-init + re-init timer safety.         ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_lazy_modules.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- Mirrors /init.lua's searchPaths: kernel.net lives at kernel/net/init.lua.
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- ============================================================
-- 1. Module-loader reader contract
-- ============================================================
-- Both loaders (/init.lua loadModuleFile, kernel verifySystem streamLoad)
-- read a file into a table of chunks and then feed load() from that TABLE,
-- releasing each piece as it is consumed. Two separate hazards make that
-- exact shape mandatory, and both are silent or fatal if got wrong:
--
--   (a) Lua treats an EMPTY string from a reader as end-of-chunk, so a
--       short read reaching load() compiles a PREFIX of the module with no
--       error raised at all;
--   (b) the reader must do NO I/O. In OpenComputers a component call can
--       yield (each machine has a direct-call budget and yields when it
--       runs out), load() is a C function, and yielding inside its reader
--       is a fatal "attempt to yield across a C-call boundary" — this
--       panicked the kernel on every boot, regardless of RAM.
print("\n-- module-loader reader contract --")

local SRC = "local t = 0\nfor i = 1, 10 do t = t + i end\nreturn t\n"

-- Stand-in for proxy.read(h, 4096): hands out `size`-byte slices and ends
-- with nil. With `injectEmpties`, it returns a spurious "" before every
-- real slice WITHOUT consuming source — the short-read a real filesystem
-- can produce.
local function fakeRead(src, size, injectEmpties)
  local pos, pendingEmpty = 1, injectEmpties
  return function()
    if pos > #src then return nil end
    if pendingEmpty then pendingEmpty = false; return "" end
    pendingEmpty = injectEmpties
    local piece = src:sub(pos, pos + size - 1)
    pos = pos + size
    return piece
  end
end

do
  local fn = assert(load(fakeRead(SRC, 4), "=stream", "t"))
  eq("streamed load produces the same result as whole-string load", 55, fn())
  local whole = assert(load(SRC, "=whole", "t"))
  eq("whole-string load agrees", whole(), fn())
end

do
  -- Feeding those reads to load() UNGUARDED ends the chunk at the first ""
  -- — the module compiles as an empty/partial prefix with no error raised.
  -- This is why the `#chunk > 0` skip in both loaders is load-bearing.
  local truncating = load(fakeRead(SRC, 4, true), "=trunc", "t")
  local result = nil
  if truncating then local _; _, result = pcall(truncating) end
  test("an unguarded '' read truncates the chunk (hazard is real)",
    result ~= 55)
end

do
  -- The guarded form — skip empties, end only on nil.
  local rawRead = fakeRead(SRC, 4, true)
  local fn = assert(load(function()
    while true do
      local chunk = rawRead()
      if chunk == nil then return nil end
      if #chunk > 0 then return chunk end
    end
  end, "=guarded", "t"))
  eq("guarded reader (skips '') compiles the whole source", 55, fn())
end

do
  -- Hazard (b). A reader that yields — which is what ANY filesystem read
  -- inside load() eventually does on OpenComputers — cannot produce a
  -- working chunk.
  --
  -- We assert only that, NOT a specific error: the failure MODE is
  -- host-dependent and this suite runs on stock Lua, not OC. Stock 5.4
  -- swallows the yield and hands back a nil/empty chunk; OC's 5.3 raises
  -- "attempt to yield across a C-call boundary" and panics the kernel,
  -- which is how this shipped and broke every boot. Either way the rule
  -- the loaders must obey is the same: never do I/O in the reader.
  local rawRead = fakeRead(SRC, 4)
  local co = coroutine.create(function()
    local fn = load(function()
      coroutine.yield()     -- stands in for a component call hitting the budget
      return rawRead()
    end, "=yielding", "t")
    return fn and fn()
  end)
  local ok, res = coroutine.resume(co)
  while ok and coroutine.status(co) ~= "dead" do ok, res = coroutine.resume(co) end
  test("a reader that yields never produces a working chunk",
    not (ok and res == 55))
end

do
  -- The safe shape both loaders now use: do the yielding reads FIRST, then
  -- compile from memory where the reader can only do table lookups. The
  -- yields below stand in for component calls hitting the OC call budget.
  local co = coroutine.create(function()
    local rawRead = fakeRead(SRC, 4, true)
    local chunks, n = {}, 0
    while true do
      coroutine.yield()               -- a component read yielding mid-file
      local c = rawRead()
      if c == nil then break end
      if #c > 0 then n = n + 1; chunks[n] = c end
    end
    local i = 0
    local fn = load(function()
      i = i + 1
      local c = chunks[i]
      chunks[i] = nil                 -- release as consumed
      return c
    end, "=safe", "t")
    return fn and fn()
  end)
  local ok, res = coroutine.resume(co)
  while ok and coroutine.status(co) ~= "dead" do ok, res = coroutine.resume(co) end
  test("read-then-compile survives yields during the read phase", ok)
  eq("...and still compiles the whole source", 55, res)
end

-- ============================================================
-- 2. net.setServiceArm — fail-closed daemon arm state
-- ============================================================
print("\n-- net service arm state --")

package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end,
  type = function() return nil end,
}
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 512 * 1024 end,
  totalMemory = function() return 1024 * 1024 end,
  pullSignal = function() return nil end,
  address = function() return "test" end,
}

local net = require("kernel.net")

test("net exposes setServiceArm", type(net.setServiceArm) == "function")
test("net exposes getServiceArm", type(net.getServiceArm) == "function")

-- Fail-closed: an unset service reads as NOT armed. This is what makes an
-- unloaded transfer/remote backend refuse requests exactly like a loaded-
-- but-disabled one.
eq("unknown service is not armed (fail-closed)", false, net.getServiceArm("fileshare"))
eq("unknown name is not armed", false, net.getServiceArm("nonesuch"))

net.setServiceArm("fileshare", true)
eq("fileshare arms", true, net.getServiceArm("fileshare"))
eq("rshd stays independent", false, net.getServiceArm("rshd"))
net.setServiceArm("fileshare", false)
eq("fileshare disarms", false, net.getServiceArm("fileshare"))

-- When the backend IS already loaded, arming must reach through to it
-- immediately (the service can be started after the module loaded).
do
  local seen = nil
  package.loaded["kernel.net.transfer"] = {
    setEnabled = function(v) seen = v end,
  }
  net.setServiceArm("fileshare", true)
  eq("arming a LOADED backend calls setEnabled(true)", true, seen)
  net.setServiceArm("fileshare", false)
  eq("disarming a LOADED backend calls setEnabled(false)", false, seen)
  package.loaded["kernel.net.transfer"] = nil
  net.setServiceArm("fileshare", false)
end

-- ============================================================
-- 3. compat.init idempotence
-- ============================================================
print("\n-- compat.init idempotence --")

do
  -- Preload every shim so compat.init resolves them without touching disk.
  local shimNames = {
    "sides", "colors", "keyboard", "text", "serialization",
    "buffer", "term", "filesystem", "event", "shell_api", "io",
    "internet",
  }
  -- Derived, not hardcoded: this count and the two below used to be three
  -- separate literal 11s, so adding a shim failed the suite in a way that
  -- said nothing about which number was authoritative.
  local SHIM_COUNT = #shimNames
  local built = 0
  for _, n in ipairs(shimNames) do
    package.loaded["compat." .. n] = {
      write = function() end,
      _shim = n,
    }
    built = built + 1
  end
  test("shim stubs registered", built == SHIM_COUNT)

  local compat = require("compat")
  local savedPrint, savedIO, savedOS = print, rawget(_G, "io"), rawget(_G, "os")

  local l1, f1 = compat.init({})
  local l2, f2 = compat.init({})
  print = savedPrint  -- compat.init overrides _G.print; restore for output

  eq("first init loaded every shim", SHIM_COUNT, l1)
  eq("first init had no failures", 0, f1)
  eq("second init returns the same loaded count", l1, l2)
  eq("second init returns the same failed count", f1, f2)

  -- A repeat init must still forward a late procSleep injection.
  local slept = nil
  compat.init({ procSleep = function(n) slept = n end })
  print = savedPrint
  if _G.os and _G.os.sleep then _G.os.sleep(3) end
  eq("repeat init still forwards procSleep", 3, slept)

  _G.io, _G.os = savedIO, savedOS
end

-- ============================================================
-- 4. cron lazy self-init + re-init safety
-- ============================================================
print("\n-- cron lazy self-init --")

do
  local intervals, cancelled = 0, 0
  local fakeEvent = {
    interval = function() intervals = intervals + 1; return 100 + intervals end,
    cancelTimer = function() cancelled = cancelled + 1; return true end,
  }
  local fakeFS = {
    exists = function() return false end,
    readFile = function() return nil end,
    writeFile = function() return true end,
  }
  package.loaded["kernel.serialize"] = {
    loadFile = function() return nil end,
    saveFile = function() return true end,
    encode = function() return "" end,
    decode = function() return nil end,
  }

  -- The kernel only skips cron at boot when there are no saved jobs; the
  -- module then brings ITSELF up on first require from the live _TOS.
  _G._TOS = { fs = fakeFS, logObj = nil, event = fakeEvent }
  local cron = require("kernel.cron")

  eq("self-init registered exactly one tick timer", 1, intervals)
  test("cron API is usable after self-init", type(cron.list) == "function")

  -- An explicit init afterwards (kernel or a test) must not leave TWO
  -- schedulers ticking — the re-init guard cancels the previous timer.
  cron.init({ fs = fakeFS, log = nil, event = fakeEvent })
  eq("re-init cancelled the previous timer", 1, cancelled)
  eq("re-init registered its replacement", 2, intervals)

  _G._TOS = nil
end

-- ============================================================
-- 5. Boot-profile gates survive the move to lazy loading
-- ============================================================
-- Deferring a module to first-use must not let it slip past the boot
-- profile. Safe Mode / minimal gate cron OFF; the shell's `cron` command
-- require()s the module directly, so the SELF-INIT is what has to refuse.
print("\n-- boot-profile gates on lazy self-init --")

do
  local intervals = 0
  local fakeEvent = {
    interval = function() intervals = intervals + 1; return 1 end,
    cancelTimer = function() return true end,
  }
  local fakeFS = { exists = function() return false end }

  -- Re-load cron from source with the gate set, so its self-init block
  -- runs again under Safe Mode conditions.
  package.loaded["kernel.cron"] = nil
  _G._TOS = { fs = fakeFS, event = fakeEvent, cronDisabled = true }
  local cron2 = assert(loadfile("tos/kernel/cron.lua"))()

  eq("cronDisabled blocks self-init (no tick timer)", 0, intervals)
  test("module still loads and exposes its API", type(cron2.init) == "function")

  -- The gate must not be a permanent lobotomy: an EXPLICIT init (the
  -- kernel's own, on a normal boot) still brings the scheduler up.
  cron2.init({ fs = fakeFS, log = nil, event = fakeEvent })
  eq("explicit init still works", 1, intervals)

  _G._TOS = nil
  package.loaded["kernel.cron"] = nil
end

-- ============================================================
print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
end
print("*** ALL TESTS PASSED ***")
return true
