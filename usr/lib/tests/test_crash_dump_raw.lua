-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a crash report survives a broken kernel.fs   ║
-- ║                                                                ║
-- ║  A panic after boot is often IN the filesystem layer, and the  ║
-- ║  flight recorder wrote only through it. Worse, a write that    ║
-- ║  RAISED was reported as saved (pcall's error string is truthy) ║
-- ║  and the stop screen named a report that did not exist.        ║
-- ║  crashDump now falls back to raw component invokes -- boot     ║
-- ║  disk first, then any writable disk but the tmpfs -- and the   ║
-- ║  next boot finds a report wherever it landed.                  ║
-- ║                                                                ║
-- ║  The three functions are LIFTED from tos/kernel/init.lua and   ║
-- ║  run against fake disks: requiring the kernel would boot it.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_crash_dump_raw.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local src = assert(io.open("tos/kernel/init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local function lift(fname)
  return src:match("(function kernel%." .. fname .. "%(.-\nend)\n")
end
local DUMP, RAW, CHECK = lift("crashDump"), lift("crashWriteRaw"), lift("checkLastCrash")
test("found crashDump and checkLastCrash", DUMP ~= nil and CHECK ~= nil)

-- ── Disks, reached only through component.invoke ──────────────────
local BOOT, TMP, FLOP, ROM = "b00t-0000", "7777-tmp0", "f10p-0000", "r0m0-0000"
local ME = "c0mp-uter"
local disks
local function fresh(bootRO)
  disks = {
    [BOOT] = { files = {}, ro = bootRO or false },
    [TMP]  = { files = {}, ro = false },
    [FLOP] = { files = {}, ro = false },
    [ROM]  = { files = {}, ro = true },
  }
end
local handles, nextH = {}, 0
local component = {
  list = function(kind)
    local keys = {}
    if kind == "filesystem" then
      -- ROM and the tmpfs come back first: the order must not matter.
      keys = { ROM, TMP, FLOP, BOOT }
    end
    local i = 0
    return function() i = i + 1; return keys[i] end
  end,
  type = function(a) return disks[a] and "filesystem" or nil end,
  invoke = function(a, m, ...)
    local d = assert(disks[a], "no such component")
    local args = { ... }
    if m == "isReadOnly" then return d.ro
    elseif m == "makeDirectory" then return not d.ro
    elseif m == "open" then
      if d.ro then return nil, "filesystem is read-only" end
      nextH = nextH + 1; handles[nextH] = { disk = d, path = args[1], buf = {} }
      return nextH
    elseif m == "write" then
      local h = handles[args[1]]; h.buf[#h.buf + 1] = args[2]; return true
    elseif m == "close" then
      local h = handles[args[1]]
      if h then h.disk.files[h.path] = table.concat(h.buf); handles[args[1]] = nil end
      return true
    end
    error("unexpected method " .. tostring(m))
  end,
}
local computer = {
  uptime = function() return 1234.5 end,
  freeMemory = function() return 40 * 1024 end,
  totalMemory = function() return 512 * 1024 end,
  getBootAddress = function() return BOOT end,
  tmpAddress = function() return TMP end,
  address = function() return ME end,
}
local warned = {}
local LOG = {
  recent = function() return { { time = 1.5, source = "net", msg = "SECRET-LOG-LINE" } } end,
  warn = function(_, msg) warned[#warned + 1] = msg end,
}

-- One kernel per case, so each sees the _TOS it is given.
local function kernelWith(TOS)
  local kernel = {}
  local G = setmetatable({ _TOS = TOS }, { __index = _G })
  local env = setmetatable({
    kernel = kernel, computer = computer, component = component, _G = G,
    require = function(n) if n == "kernel.log" then return LOG end return require(n) end,
  }, { __index = _G })
  for _, chunk in ipairs({ RAW or "", DUMP, CHECK }) do
    assert(load(chunk, "=lifted", "t", env))()
  end
  return kernel
end

-- A kernel.fs over the boot disk: the normal path.
local function bootFs(mode)
  local F = {}
  function F.writeFile(p, d)
    if mode == "raise" then error("kernel.fs: attempt to index a nil value (upvalue 'proxy')") end
    if mode == "refuse" then return false, "disk full" end
    disks[BOOT].files[p] = d; return true
  end
  function F.exists(p) return disks[BOOT].files[p] ~= nil end
  function F.readFile(p) return disks[BOOT].files[p] end
  function F.remove(p) disks[BOOT].files[p] = nil; return true end
  function F.mounts() return {} end
  return F
end

print("=== a crash report survives a broken kernel.fs ===")
print()

if DUMP and CHECK then
  fresh()
  local k = kernelWith({ fs = bootFs() })
  local r = k.crashDump("KERNEL PANIC [E-201 ERR_KERNEL_PANIC]", "boom\ntraceback")
  test("a working kernel.fs: the report is written through it",
    r == "/var/crash/crash-1234.txt" and disks[BOOT].files[r] ~= nil)
  test("...with the marker", disks[BOOT].files["/var/crash/NEW"] ~= nil)

  fresh()
  k = kernelWith({ fs = bootFs("raise") })
  r = k.crashDump("KERNEL PANIC", "boom")
  local onDisk = disks[BOOT].files["/var/crash/crash-1234.txt"]
  test("kernel.fs RAISES: the report reaches the boot disk anyway", onDisk ~= nil)
  test("...and the path it reports is one that exists", r == "/var/crash/crash-1234.txt" and onDisk ~= nil)
  test("...with the whole report, log included",
    onDisk ~= nil and onDisk:find("SECRET-LOG-LINE", 1, true) ~= nil and onDisk:find("boom", 1, true) ~= nil)
  test("...and the marker the next boot reads",
    disks[BOOT].files["/var/crash/NEW"] == "KERNEL PANIC @ uptime 1234s")

  fresh()
  k = kernelWith({ fs = bootFs("refuse") })
  r = k.crashDump("KERNEL PANIC", "boom")
  test("kernel.fs refuses the write: same fallback",
    r == "/var/crash/crash-1234.txt" and disks[BOOT].files[r] ~= nil)

  fresh()
  k = kernelWith({})
  r = k.crashDump("KERNEL PANIC", "boom")
  test("no kernel.fs at all: same fallback", disks[BOOT].files["/var/crash/crash-1234.txt"] ~= nil)

  -- The boot disk will not take it: the next writable disk does.
  fresh(true)
  k = kernelWith({ fs = bootFs("raise") })
  r = k.crashDump("KERNEL PANIC", "boom")
  local away = disks[FLOP].files["/var/crash/crash-1234.txt"]
  test("boot disk read-only: the report goes to another disk", away ~= nil)
  test("...never the tmpfs, which a reboot wipes", next(disks[TMP].files) == nil)
  test("...and the path says which disk", r == "/var/crash/crash-1234.txt on disk " .. FLOP:sub(1, 8))
  test("...without the log ring, which is admin-read on the boot disk",
    away ~= nil and away:find("SECRET-LOG-LINE", 1, true) == nil and away:find("boom", 1, true) ~= nil)
  test("...and a marker naming this machine",
    disks[FLOP].files["/var/crash/NEW"] == "KERNEL PANIC @ uptime 1234s\nmachine " .. ME)

  fresh(true); disks[FLOP].ro = true
  k = kernelWith({ fs = bootFs("raise") })
  test("nothing writable: it says so instead of naming a file", k.crashDump("KERNEL PANIC") == false)

  -- ── the next boot ────────────────────────────────────────────────
  print()
  print("--- the next boot finds it ---")
  local function mountedFs()
    local F = bootFs()
    function F.exists(p)
      local flop = p:match("^/mnt/flop(/.*)$")
      if flop then return disks[FLOP].files[flop] ~= nil end
      return disks[BOOT].files[p] ~= nil
    end
    function F.readFile(p)
      local flop = p:match("^/mnt/flop(/.*)$")
      if flop then return disks[FLOP].files[flop] end
      return disks[BOOT].files[p]
    end
    function F.remove(p)
      local flop = p:match("^/mnt/flop(/.*)$")
      if flop then disks[FLOP].files[flop] = nil else disks[BOOT].files[p] = nil end
      return true
    end
    function F.mounts()
      return { { mountPoint = "/", address = BOOT }, { mountPoint = "/mnt/flop", address = FLOP },
               { mountPoint = "/net/far", address = "netfs-not-a-component" } }
    end
    return F
  end

  fresh()
  disks[BOOT].files["/var/crash/NEW"] = "KERNEL PANIC @ uptime 9s"
  warned = {}
  kernelWith({ fs = mountedFs() }).checkLastCrash()
  test("the boot disk's marker is reported", warned[1] == "Last run crashed: KERNEL PANIC @ uptime 9s — see /var/crash (`crash`)")
  test("...and cleared", disks[BOOT].files["/var/crash/NEW"] == nil)

  fresh()
  disks[FLOP].files["/var/crash/NEW"] = "KERNEL PANIC @ uptime 9s\nmachine " .. ME
  warned = {}
  kernelWith({ fs = mountedFs() }).checkLastCrash()
  test("a marker on another disk naming this machine is reported, with where",
    warned[1] == "Last run crashed: KERNEL PANIC @ uptime 9s — see /mnt/flop/var/crash")
  test("...and cleared", disks[FLOP].files["/var/crash/NEW"] == nil)

  fresh()
  disks[FLOP].files["/var/crash/NEW"] = "KERNEL PANIC @ uptime 9s\nmachine someone-else"
  warned = {}
  kernelWith({ fs = mountedFs() }).checkLastCrash()
  test("another machine's marker is not reported", #warned == 0)
  test("...and not touched", disks[FLOP].files["/var/crash/NEW"] ~= nil)
end

-- The panic handler must not stop at a crashDump that saved nothing.
do
  local boot = assert(io.open("init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
  test("the panic handler falls through when crashDump saves nothing",
    boot:find("if okK and r then report = r; return end", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
