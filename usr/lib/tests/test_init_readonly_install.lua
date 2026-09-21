-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a read-only boot disk offers the install    ║
-- ║                                                                ║
-- ║  /init.lua offers "install TOS to the hard drive" when it      ║
-- ║  boots from a floppy. It recognised a floppy only by size      ║
-- ║  (spaceTotal <= 512 KB), and OpenComputers mounts a loot disk  ║
-- ║  -- the TOS floppy from a dungeon chest -- through             ║
-- ║  ReadOnlyWrapper, whose spaceTotal() is spaceUsed(): ~1.4 MB.  ║
-- ║  So that disk never got the offer and booted into a root that  ║
-- ║  cannot keep a password. A read-only boot disk now gets the    ║
-- ║  offer at any size, and only a writable disk is a target.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_init_readonly_install.lua   (from the TOS-Dev root)
--
-- Runs the REAL /init.lua against fake components, and stops it at the
-- first assignment to _G._TOS -- the line right after the install offer --
-- so nothing past Stage 0 has to be faked.

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_init_readonly_install.lua"
local base = here:gsub("[^/\\]*$", "")
local INIT
for _, p in ipairs({ base .. "../../../init.lua", "init.lua", "TOS-Dev/init.lua" }) do
  local f = io.open(p, "rb")
  if f then f:close(); INIT = p; break end
end
assert(INIT, "cannot find TOS-Dev/init.lua")

local STAGE1   = "STAGE1-SENTINEL"     -- init.lua got past the install offer
local SHUTDOWN = "SHUTDOWN-SENTINEL"   -- init.lua rebooted the machine
local HANG     = "HANG-SENTINEL"       -- init.lua waited on a prompt nobody answers

-- ------------------------------------------------------------
-- A managed OpenComputers filesystem, in memory. A read-only one
-- reports spaceTotal() == spaceUsed(), exactly as OC's ReadOnlyWrapper
-- does (verified in OpenComputers 1.8.10) -- that is the whole bug.
-- ------------------------------------------------------------
local function fakeFS(address, files, opts)
  opts = opts or {}
  local fs = { address = address, files = {}, dirs = { ["/"] = true }, writes = 0 }
  local function norm(p)
    p = ("/" .. p):gsub("/+", "/")
    if #p > 1 then p = p:gsub("/$", "") end
    return p
  end
  local function addParents(p)
    local d = p:match("^(.*)/[^/]*$")
    while d and d ~= "" do fs.dirs[d] = true; d = d:match("^(.*)/[^/]*$") end
  end
  for p, c in pairs(files or {}) do p = norm(p); fs.files[p] = c; addParents(p) end
  local function used()
    local n = 0
    for _, c in pairs(fs.files) do n = n + #c end
    return n
  end
  function fs.spaceUsed() return used() end
  function fs.spaceTotal()
    if opts.readOnly then return used() end
    return opts.capacity
  end
  function fs.isReadOnly() return opts.readOnly == true end
  function fs.exists(p) p = norm(p); return fs.files[p] ~= nil or fs.dirs[p] == true end
  function fs.isDirectory(p) return fs.dirs[norm(p)] == true end
  function fs.size(p) local c = fs.files[norm(p)]; return c and #c or 0 end
  function fs.list(dir)
    dir = norm(dir)
    local prefix = dir == "/" and "/" or dir .. "/"
    local out, seen = {}, {}
    local function consider(p, isDir)
      if p ~= dir and p:sub(1, #prefix) == prefix then
        local rest = p:sub(#prefix + 1)
        local name = rest:match("^[^/]+")
        local entry = (isDir or rest:find("/", 1, true)) and name .. "/" or name
        if not seen[entry] then seen[entry] = true; out[#out + 1] = entry end
      end
    end
    for p in pairs(fs.files) do consider(p, false) end
    for p in pairs(fs.dirs) do consider(p, true) end
    table.sort(out)
    return out
  end
  function fs.makeDirectory(p)
    if opts.readOnly then return false end
    p = norm(p); fs.dirs[p] = true; addParents(p)
    return true
  end
  function fs.open(p, mode)
    p = norm(p)
    if mode and mode:sub(1, 1) == "w" then
      if opts.readOnly then return nil, "filesystem is read-only" end
      return { path = p, buf = {}, size = 0, w = true }
    end
    if not fs.files[p] then return nil, p end
    return { path = p, pos = 1 }
  end
  function fs.read(h, n)
    local c = fs.files[h.path]
    if not c or h.pos > #c then return nil end
    local chunk = c:sub(h.pos, h.pos + n - 1)
    h.pos = h.pos + #chunk
    return chunk
  end
  function fs.write(h, data)
    if opts.readOnly or not h.w then return false, "filesystem is read-only" end
    if used() + h.size + #data > (opts.capacity or math.huge) then
      return false, "not enough space"
    end
    h.buf[#h.buf + 1] = data
    h.size = h.size + #data
    fs.writes = fs.writes + 1
    return true
  end
  function fs.close(h)
    if h.w then fs.files[h.path] = table.concat(h.buf); addParents(h.path) end
  end
  return fs
end

-- A TOS tree big enough that the old 512 KB test alone could never match it.
local function tosTree()
  return {
    ["/init.lua"]             = "-- TOS boot",
    ["/install.lua"]          = "-- TOS installer",
    ["/tos/kernel/init.lua"]  = "-- TOS kernel",
    ["/tos/kernel/big.lua"]   = string.rep("-", 600 * 1024),
    ["/tos/shell/init.lua"]   = "-- TOS shell",
  }
end

local KB = 1024

-- ------------------------------------------------------------
-- Boot the real /init.lua from `bootDisk` with `others` attached.
-- `answers` maps a prompt drawn on screen to the key the operator
-- presses for it; each prompt is answered once, and anything else the
-- machine waits for times out -- as it would if nobody touched the keys.
-- ------------------------------------------------------------
local function boot(bootDisk, others, answers, preset)
  local m = { screen = {}, answered = {}, bootAddress = bootDisk.address, waits = 0 }
  local gpu = {
    bind = function() return true end,
    setBackground = function() end, setForeground = function() end,
    getResolution = function() return 80, 25 end,
    fill = function() end,
    set = function(_, _, s) m.screen[#m.screen + 1] = tostring(s) end,
  }
  local kinds = { ["gpu-0001"] = "gpu", ["scr-0001"] = "screen" }
  local byAddr = { ["gpu-0001"] = gpu }
  for _, d in ipairs({ bootDisk, table.unpack(others) }) do
    kinds[d.address] = "filesystem"; byAddr[d.address] = d
  end
  local component = {
    list = function(kind)
      local addrs = {}
      for a, k in pairs(kinds) do if k == kind then addrs[#addrs + 1] = a end end
      table.sort(addrs)
      local i = 0
      return function() i = i + 1; return addrs[i] end
    end,
    proxy = function(a) return byAddr[a] end,
  }
  local clock = 0
  local computer = {
    pullSignal = function()
      m.waits = m.waits + 1
      if m.waits > 50 then error(HANG, 0) end
      for i = #m.screen, 1, -1 do
        for prompt, key in pairs(answers or {}) do
          if not m.answered[prompt] and m.screen[i]:find(prompt, 1, true) then
            m.answered[prompt] = true
            return "key_down", "kbd-0001", key, 0
          end
        end
      end
      return nil
    end,
    uptime = function() clock = clock + 1; return clock end,
    freeMemory = function() return 128 * 1024 end,
    totalMemory = function() return 256 * 1024 end,
    shutdown = function() error(SHUTDOWN, 0) end,
    setBootAddress = function(a) m.bootAddress = a end,
    getBootAddress = function() return bootDisk.address end,
    beep = function() end,
  }
  local g = {}
  for k, v in pairs(preset or {}) do g[k] = v end
  setmetatable(g, { __newindex = function(t, k, v)
    if k == "_TOS" then error(STAGE1, 0) end
    rawset(t, k, v)
  end })
  local env = setmetatable({ _G = g, component = component, computer = computer },
    { __index = _G })
  local chunk = assert(loadfile(INIT, "t", env))
  local ok, err = pcall(chunk, bootDisk)
  m.outcome = ok and "returned" or tostring(err)
  if m.outcome ~= STAGE1 and m.outcome ~= SHUTDOWN then
    print("    (init.lua stopped with: " .. m.outcome .. ")")
  end
  function m.shown(text)
    for _, s in ipairs(m.screen) do if s:find(text, 1, true) then return true end end
    return false
  end
  return m
end

local OFFER = "Install TOS to the hard drive"
local KEY_1, KEY_Y = 49, 121
local INSTALL = { ["Press 1 or 2"] = KEY_1, ["[Y] update EEPROM"] = KEY_Y }

print("=== /init.lua: read-only boot disk install offer ===")
print()

-- 1. The case this fixes: a loot disk and an empty tier 2 hard drive.
do
  local loot = fakeFS("loot-0001", tosTree(), { readOnly = true })
  local hdd  = fakeFS("hdd-0001", {}, { capacity = 2048 * KB })
  test("precondition: the loot disk reports more than 512 KB, as OC's does",
    loot.spaceTotal() > 512 * KB)
  local m = boot(loot, { hdd }, INSTALL)
  test("loot disk: the install offer is shown", m.shown(OFFER))
  test("loot disk: the offer says the disk is read-only", m.shown("read-only disk"))
  test("loot disk: pressing 1 installs, then reboots", m.outcome == SHUTDOWN)
  test("loot disk: the hard drive got /init.lua", hdd.files["/init.lua"] == "-- TOS boot")
  test("loot disk: the hard drive got the kernel", hdd.files["/tos/kernel/init.lua"] == "-- TOS kernel")
  test("loot disk: a large file arrived whole",
    hdd.files["/tos/kernel/big.lua"] == loot.files["/tos/kernel/big.lua"])
  test("loot disk: Y points the EEPROM at the hard drive", m.bootAddress == "hdd-0001")
end

-- 2. Declining (or nobody at the keyboard) still boots, and writes nothing.
do
  local loot = fakeFS("loot-0001", tosTree(), { readOnly = true })
  local hdd  = fakeFS("hdd-0001", {}, { capacity = 2048 * KB })
  local m = boot(loot, { hdd }, {})
  test("no answer: the offer is shown", m.shown(OFFER))
  test("no answer: boot continues past the offer", m.outcome == STAGE1)
  test("no answer: nothing was written to the hard drive", hdd.writes == 0)
  test("no answer: the EEPROM is left alone", m.bootAddress == "loot-0001")
end

-- 3. An installed system -- a writable hard drive -- is never offered anything.
do
  local root  = fakeFS("hdd-0001", tosTree(), { capacity = 2048 * KB })
  local other = fakeFS("hdd-0002", {}, { capacity = 4096 * KB })
  local m = boot(root, { other }, INSTALL)
  test("writable root: no install offer", not m.shown(OFFER))
  test("writable root: boot continues", m.outcome == STAGE1)
  test("writable root: the other drive is untouched", other.writes == 0)
end

-- 4. The case that already worked: a small writable floppy.
do
  local floppy = fakeFS("flop-0001", { ["/init.lua"] = "-- TOS boot",
    ["/install.lua"] = "-- TOS installer", ["/tos/kernel/init.lua"] = "-- TOS kernel" },
    { capacity = 512 * KB })
  local hdd = fakeFS("hdd-0001", {}, { capacity = 2048 * KB })
  local m = boot(floppy, { hdd }, INSTALL)
  test("writable floppy: the offer is still shown", m.shown(OFFER))
  test("writable floppy: ...and still calls it a floppy", m.shown("floppy disk"))
  test("writable floppy: the install still completes", hdd.files["/tos/kernel/init.lua"] ~= nil)
end

-- 5. A read-only disk is never an install target.
do
  local loot  = fakeFS("loot-0001", tosTree(), { readOnly = true })
  local other = fakeFS("loot-0002", tosTree(), { readOnly = true })
  other.files["/tos/kernel/bigger.lua"] = string.rep("-", 200 * KB)
  local m = boot(loot, { other }, INSTALL)
  test("only a read-only disk to copy to: no offer", not m.shown(OFFER))
  test("only a read-only disk to copy to: boot continues", m.outcome == STAGE1)
end

-- 6. ...even when it is the biggest disk attached.
do
  local loot  = fakeFS("loot-0001", tosTree(), { readOnly = true })
  local huge  = fakeFS("loot-0002", tosTree(), { readOnly = true })
  huge.files["/tos/kernel/bigger.lua"] = string.rep("-", 3000 * KB)
  local hdd   = fakeFS("hdd-0001", {}, { capacity = 2048 * KB })
  local m = boot(loot, { huge, hdd }, INSTALL)
  test("larger read-only disk present: the writable drive is the target",
    hdd.files["/tos/kernel/init.lua"] == "-- TOS kernel")
  test("larger read-only disk present: the EEPROM points at the writable drive",
    m.bootAddress == "hdd-0001")
end

-- 7. #SEC H1: a one-time boot never offers a migration, read-only or not.
do
  local loot = fakeFS("loot-0001", tosTree(), { readOnly = true })
  local hdd  = fakeFS("hdd-0001", {}, { capacity = 2048 * KB })
  local m = boot(loot, { hdd }, INSTALL, { _BIOS_ONETIME = true })
  test("one-time boot: no install offer", not m.shown(OFFER))
  test("one-time boot: nothing written", hdd.writes == 0)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
